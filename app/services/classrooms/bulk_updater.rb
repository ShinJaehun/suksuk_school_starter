module Classrooms
  class BulkUpdater
    MAX_ROWS = 30
    Entry = Data.define(:line, :id, :grade, :class_label, :teacher_id, :classroom, :errors)

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

      Classroom.transaction do
        school_year.lock!
        build_entries
        validate_entries
        raise ActiveRecord::Rollback if invalid?

        release_changed_assignments
        entries.sort_by(&:id).each { |entry| entry.classroom.save! }
        create_changed_assignments
      end
      self
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
      errors << I18n.t("admin.classrooms.bulk.errors.save_conflict")
      self
    end

    def success?
      !invalid? && entries.present?
    end

    private

    attr_reader :school_year, :scope, :rows, :classrooms, :teachers, :assignments

    def build_entries
      errors << I18n.t("admin.classrooms.bulk.errors.row_count") unless rows.size.between?(1, MAX_ROWS)
      ids = rows.map { |row| positive_id(row.to_h.stringify_keys["id"]) }
      unless ids.all? && ids.uniq.size == ids.size && scope.where(id: ids).pluck(:id).sort == ids.sort
        errors << I18n.t("admin.classrooms.bulk.errors.classroom_scope")
        return
      end

      @classrooms = Classroom.where(id: ids).order(:id).lock.index_by(&:id)
      rows.each_with_index do |raw, index|
        row = raw.to_h.stringify_keys
        classroom = classrooms.fetch(row["id"].to_i)
        entries << Entry.new(line: index + 1, id: classroom.id, grade: normalized_grade(row["grade"]),
          class_label: normalized_label(row["class_label"]), teacher_id: row["teacher_id"].presence,
          classroom: classroom, errors: [])
      end
    end

    def validate_entries
      return if entries.empty?

      load_assignment_state
      validate_duplicate_final_state
      entry_by_classroom = entries.index_by(&:id)
      final_teacher_ids = entries.filter_map { |entry| positive_id(entry.teacher_id) }
      outside_assignments = HomeroomAssignment.current.where(teacher_id: final_teacher_ids)
                                             .where.not(classroom_id: entries.map(&:id)).exists?
      errors << I18n.t("admin.classrooms.bulk.errors.teacher_assigned") if outside_assignments

      entries.each do |entry|
        entry.errors << I18n.t("admin.classrooms.bulk.errors.inactive_classroom") unless entry.classroom.active?
        entry.classroom.assign_attributes(grade: entry.grade, class_label: entry.class_label)
        validate_fields(entry)
        validate_teacher(entry, entry_by_classroom)
      end
    end

    def load_assignment_state
      teacher_ids = entries.filter_map { |entry| positive_id(entry.teacher_id) }
      @teachers = school_year.users.teacher.active.where(id: teacher_ids).order(:id).lock.index_by(&:id)
      @assignments = HomeroomAssignment.current
                                        .where(classroom_id: entries.map(&:id))
                                        .or(HomeroomAssignment.current.where(teacher_id: teacher_ids))
                                        .order(:id).lock.to_a
    end

    def validate_duplicate_final_state
      entries.group_by { |entry| [entry.grade, entry.class_label] }
             .select { |_key, matches| matches.many? }.each_value do |matches|
        matches.each { |entry| entry.errors << I18n.t("admin.classrooms.bulk.errors.classroom_duplicate") }
      end
      entries.select(&:teacher_id).group_by { |entry| positive_id(entry.teacher_id) }
             .select { |id, matches| id && matches.many? }.each_value do |matches|
        matches.each { |entry| entry.errors << I18n.t("admin.classrooms.bulk.errors.teacher_duplicate") }
      end
      entries.each do |entry|
        if school_year.classrooms.where.not(id: entries.map(&:id))
                      .exists?(grade: entry.grade, class_label: entry.class_label)
          entry.errors << I18n.t("admin.classrooms.bulk.errors.classroom_duplicate")
        end
      end
    end

    def validate_fields(entry)
      temporary = Classroom.new(school_year: school_year, grade: entry.grade,
        class_label: entry.class_label, active: entry.classroom.active)
      temporary.valid?
      temporary.errors.each do |error|
        next if error.attribute == :class_label && error.type == :taken

        entry.errors << error.full_message
      end
    end

    def validate_teacher(entry, entry_by_classroom)
      return if entry.teacher_id.blank?

      teacher = teachers[positive_id(entry.teacher_id)]
      if teacher.nil?
        entry.errors << I18n.t("admin.classrooms.bulk.errors.teacher_invalid")
      elsif teacher.grade != entry.grade
        entry.errors << I18n.t("admin.classrooms.bulk.errors.teacher_grade_mismatch")
      end
      assignment = assignments.find { |record| record.teacher_id == teacher&.id }
      return unless assignment && assignment.classroom_id != entry.id
      return if entry_by_classroom.key?(assignment.classroom_id)

      entry.errors << I18n.t("admin.classrooms.bulk.errors.teacher_assigned")
    end

    def release_changed_assignments
      target_teacher = entries.to_h { |entry| [entry.id, positive_id(entry.teacher_id)] }
      assignments.each do |assignment|
        next unless target_teacher.key?(assignment.classroom_id)
        next if target_teacher[assignment.classroom_id] == assignment.teacher_id

        school_year.planning? ? assignment.destroy! : assignment.update!(ended_on: Date.current)
      end
    end

    def create_changed_assignments
      current_teacher = assignments.index_by(&:classroom_id)
      entries.sort_by(&:id).each do |entry|
        teacher_id = positive_id(entry.teacher_id)
        next unless teacher_id
        next if current_teacher[entry.id]&.teacher_id == teacher_id

        HomeroomAssignment.create!(classroom: entry.classroom, teacher_id: teacher_id,
          started_on: school_year.planning? ? Date.new(school_year.year, 3, 1) : Date.current)
      end
    end

    def normalized_grade(value)
      value.to_s.match?(/\A[1-6]\z/) ? value.to_i : value
    end

    def normalized_label(value)
      value.to_s.strip.delete_suffix("반").strip.presence
    end

    def mutable_school_year?
      school_year&.school&.active? && (school_year.active? || school_year.planning?)
    end

    def invalid_context
      errors << I18n.t("admin.classrooms.bulk.errors.context_invalid")
      self
    end

    def positive_id(value)
      value.to_s.to_i if value.to_s.match?(/\A[1-9]\d*\z/)
    end

    def invalid?
      errors.any? || entries.any? { |entry| entry.errors.any? }
    end
  end
end
