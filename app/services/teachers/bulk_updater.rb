module Teachers
  class BulkUpdater
    MAX_ROWS = 30
    Entry = Data.define(:line, :id, :name, :login_id, :grade, :classroom_id, :user, :errors)

    attr_reader :entries, :errors

    def initialize(school_year:, scope:, rows:)
      @school_year = school_year
      @scope = scope
      @rows = Array(rows)
      @entries = []
      @errors = []
    end

    def call
      return invalid_context unless mutable_school_year?

      User.transaction do
        school_year.lock!
        build_entries
        validate_entries
        raise ActiveRecord::Rollback if invalid?

        release_changed_assignments
        entries.each { |entry| entry.user.save! }
        create_changed_assignments
      end
      self
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
      errors << I18n.t("admin.teachers.bulk.errors.save_conflict")
      self
    end

    def success?
      !invalid?
    end

    private

    attr_reader :school_year, :scope, :rows, :users, :classrooms, :current_assignments

    def mutable_school_year?
      school_year&.school&.active? && (school_year.active? || school_year.planning?)
    end

    def invalid_context
      errors << I18n.t("admin.teachers.bulk.errors.context_invalid")
      self
    end

    def build_entries
      errors << I18n.t("admin.teachers.bulk.errors.row_count") unless rows.size.between?(1, MAX_ROWS)
      raw_ids = rows.map { |row| row.to_h.stringify_keys["id"].to_s }
      unless raw_ids.all? { |id| id.match?(/\A[1-9]\d*\z/) } && raw_ids.uniq.size == raw_ids.size
        errors << I18n.t("admin.teachers.bulk.errors.teacher_scope")
        return
      end

      ids = raw_ids.map(&:to_i)
      allowed_ids = scope.where(id: ids).pluck(:id)
      unless allowed_ids.sort == ids.sort
        errors << I18n.t("admin.teachers.bulk.errors.teacher_scope")
        return
      end

      @users = User.where(id: ids).order(:id).lock.index_by(&:id)
      rows.each_with_index do |raw_row, index|
        row = raw_row.to_h.stringify_keys
        grade = normalized_grade(row["grade"])
        entries << Entry.new(
          line: index + 1,
          id: row["id"].to_i,
          name: row["name"],
          login_id: row["login_id"],
          grade: grade,
          classroom_id: row["classroom_id"].presence,
          user: users.fetch(row["id"].to_i),
          errors: []
        )
      end
    end

    def validate_entries
      return if entries.empty?

      load_locked_assignment_state
      validate_duplicate_targets
      validate_login_ids
      final_targets = entries.index_by(&:id)

      entries.each do |entry|
        entry.errors << I18n.t("admin.teachers.bulk.errors.inactive_teacher") unless entry.user.active?
        if inactive_assignment_changed?(entry)
          entry.errors << I18n.t("admin.teachers.bulk.errors.inactive_classroom_locked")
        end
        entry.errors << I18n.t("admin.teachers.bulk.errors.grade_invalid") if entry.grade == :invalid
        entry.user.assign_attributes(
          name: entry.name,
          login_id: entry.login_id,
          grade: entry.grade == :invalid ? entry.user.grade : entry.grade
        )
        entry.user.valid?
        entry.errors.concat(entry.user.errors.full_messages)
        validate_target_classroom(entry, final_targets) if entry.classroom_id
      end
    end

    def load_locked_assignment_state
      target_ids = entries.filter_map { |entry| positive_id(entry.classroom_id) }
      assignment_scope = HomeroomAssignment.current.where(teacher_id: entries.map(&:id))
                                            .or(HomeroomAssignment.current.where(classroom_id: target_ids))
      assignments = assignment_scope.order(:id).lock.includes(:classroom).to_a
      @current_assignments = assignments.index_by(&:teacher_id)
      classroom_ids = (target_ids + assignments.map(&:classroom_id)).uniq
      @classrooms = Classroom.where(id: classroom_ids).order(:id).lock.index_by(&:id)
    end

    def validate_duplicate_targets
      entries.select(&:classroom_id)
             .group_by { |entry| positive_id(entry.classroom_id) }
             .select { |id, matches| id && matches.many? }
             .each_value do |matches|
        matches.each { |entry| entry.errors << I18n.t("admin.teachers.bulk.errors.classroom_internal_duplicate") }
      end
    end

    def validate_login_ids
      normalized = entries.group_by { |entry| entry.login_id.to_s.strip.downcase }
      normalized.select { |value, matches| value.present? && matches.many? }.each_value do |matches|
        matches.each { |entry| entry.errors << I18n.t("admin.teachers.bulk.errors.login_id_internal_duplicate") }
      end
      existing = school_year.users.teacher.where.not(id: entries.map(&:id))
                            .where(login_id: normalized.keys).pluck(:login_id).to_set
      entries.each do |entry|
        entry.errors << I18n.t("admin.teachers.bulk.errors.login_id_taken") if existing.include?(entry.login_id.to_s.strip.downcase)
      end
    end

    def validate_target_classroom(entry, final_targets)
      classroom = classrooms[positive_id(entry.classroom_id)]
      if classroom.nil? || classroom.school_year_id != school_year.id || !classroom.active?
        entry.errors << I18n.t("admin.teachers.bulk.errors.classroom_invalid")
        return
      end
      if entry.grade == :invalid || classroom.grade != entry.grade
        entry.errors << I18n.t("admin.teachers.bulk.errors.classroom_grade_mismatch")
      end

      occupant = current_assignments.values.find { |assignment| assignment.classroom_id == classroom.id }
      return unless occupant && occupant.teacher_id != entry.id

      occupant_target = final_targets[occupant.teacher_id]
      if occupant_target.nil? || positive_id(occupant_target.classroom_id) == classroom.id
        entry.errors << I18n.t("admin.teachers.bulk.errors.classroom_occupied")
      end
    end

    def inactive_assignment_changed?(entry)
      assignment = current_assignments[entry.id]
      return false unless assignment&.classroom&.inactive?

      entry.grade != entry.user.grade || positive_id(entry.classroom_id) != assignment.classroom_id
    end

    def release_changed_assignments
      target_by_teacher = entries.index_by(&:id)
      current_assignments.each_value do |assignment|
        target_id = positive_id(target_by_teacher.fetch(assignment.teacher_id).classroom_id)
        next if target_id == assignment.classroom_id

        if school_year.planning? || assignment.started_on > Date.current
          assignment.destroy!
        else
          assignment.update!(ended_on: Date.current)
        end
      end
    end

    def create_changed_assignments
      entries.sort_by(&:id).each do |entry|
        classroom_id = positive_id(entry.classroom_id)
        next unless classroom_id
        next if current_assignments[entry.id]&.classroom_id == classroom_id

        HomeroomAssignment.create!(
          teacher: entry.user,
          classroom_id: classroom_id,
          started_on: school_year.planning? ? Date.new(school_year.year, 3, 1) : Date.current
        )
      end
    end

    def normalized_grade(value)
      return nil if value.blank? || value.to_s == "unassigned"

      value.to_s.match?(/\A[1-6]\z/) ? value.to_i : :invalid
    end

    def positive_id(value)
      value.to_s.to_i if value.to_s.match?(/\A[1-9]\d*\z/)
    end

    def invalid?
      errors.any? || entries.any? { |entry| entry.errors.any? }
    end
  end
end
