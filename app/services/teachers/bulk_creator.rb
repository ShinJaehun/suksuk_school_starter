require "securerandom"

module Teachers
  class BulkCreator
    MAX_ROWS = 30
    Entry = Data.define(:line, :name, :login_id, :gender, :avatar_key, :grade, :classroom_id, :user, :errors)

    attr_reader :entries, :errors, :credentials

    def initialize(school_year:, rows:, actor:)
      @school_year = school_year
      @actor = actor
      @entries = normalized_rows(rows).each_with_index.map { |row, index| build_entry(row, index) }
      @errors = []
      @credentials = []
    end

    def call
      return invalid_context unless mutable_school_year?

      User.transaction do
        school_year.lock!
        validate_entries
        raise ActiveRecord::Rollback if invalid?

        entries.each do |entry|
          credential = AnnualTeacherUsers::TemporaryCredential.call(
            teacher: entry.user,
            actor: actor,
            action: :temporary_password_issued
          )
          unless credential.success?
            entry.errors.concat(entry.user.errors.full_messages)
            raise ActiveRecord::Rollback
          end

          create_assignment(entry)
          credentials << {
            name: entry.user.name,
            login_id: entry.user.login_id,
            temporary_password: credential.temporary_password
          }
        end
      end

      credentials.clear if invalid? || entries.any? { |entry| !entry.user.persisted? }
      self
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
      errors << I18n.t("admin.teachers.bulk.errors.save_conflict")
      credentials.clear
      self
    end

    def success?
      !invalid? && entries.present? && entries.all? { |entry| entry.user.persisted? }
    end

    private

    attr_reader :school_year, :actor

    def mutable_school_year?
      school_year&.school&.active? && (school_year.active? || school_year.planning?)
    end

    def invalid_context
      errors << I18n.t("admin.teachers.bulk.errors.context_invalid")
      self
    end

    def normalized_rows(rows)
      Array(rows).map { |row| row.to_h.stringify_keys }
                 .reject { |row| row.values_at("name", "login_id", "gender", "avatar_key", "grade", "classroom_id").all?(&:blank?) }
    end

    def build_entry(row, index)
      grade = normalized_grade(row["grade"])
      user = User.new(
        role: :teacher,
        school_year: school_year,
        school_role: "member",
        active: true,
        name: row["name"],
        login_id: row["login_id"],
        grade: grade == :invalid ? row["grade"] : grade,
        gender: row["gender"],
        avatar_key: row["avatar_key"]
      )
      Entry.new(
        line: index + 1,
        name: row["name"],
        login_id: row["login_id"],
        gender: row["gender"],
        avatar_key: row["avatar_key"],
        grade: grade,
        classroom_id: row["classroom_id"].presence,
        user: user,
        errors: []
      )
    end

    def validate_entries
      errors << I18n.t("admin.teachers.bulk.errors.row_count") unless entries.size.between?(1, MAX_ROWS)
      validate_internal_duplicates
      validate_existing_login_ids
      classrooms = locked_classrooms

      entries.each do |entry|
        entry.errors << I18n.t("admin.teachers.bulk.errors.grade_invalid") if entry.grade == :invalid
        validate_gender_and_avatar(entry)
        validate_user(entry)
        validate_classroom(entry, classrooms[entry.classroom_id.to_i]) if entry.classroom_id
      end
    end

    def validate_gender_and_avatar(entry)
      unless User::GENDERS.include?(entry.gender)
        entry.errors << I18n.t("admin.teachers.bulk.errors.gender_invalid")
      end
      unless User.avatar_keys_for(entry.gender).include?(entry.avatar_key)
        entry.errors << I18n.t("admin.teachers.bulk.errors.avatar_invalid")
      end
    end

    def validate_user(entry)
      entry.user.password = SecureRandom.alphanumeric(20)
      entry.user.password_confirmation = entry.user.password
      entry.user.valid?
      entry.user.errors.each do |error|
        next if error.attribute == :grade && entry.grade == :invalid

        entry.errors << error.full_message
      end
      entry.user.password = nil
      entry.user.password_confirmation = nil
    end

    def validate_internal_duplicates
      duplicate_entries(entries, &:login_id).each do |entry|
        entry.errors << I18n.t("admin.teachers.bulk.errors.login_id_internal_duplicate")
      end
      duplicate_entries(entries.select(&:classroom_id), &:classroom_id).each do |entry|
        entry.errors << I18n.t("admin.teachers.bulk.errors.classroom_internal_duplicate")
      end
    end

    def duplicate_entries(collection)
      collection.group_by { |entry| yield(entry).to_s.strip.downcase }
                .select { |value, matches| value.present? && matches.many? }
                .values.flatten
    end

    def validate_existing_login_ids
      existing = school_year.users.teacher
                            .where(login_id: entries.map { |entry| entry.login_id.to_s.strip.downcase })
                            .pluck(:login_id)
                            .to_set
      entries.each do |entry|
        if existing.include?(entry.login_id.to_s.strip.downcase)
          entry.errors << I18n.t("admin.teachers.bulk.errors.login_id_taken")
        end
      end
    end

    def locked_classrooms
      ids = entries.filter_map { |entry| positive_id(entry.classroom_id) }.uniq
      school_year.classrooms.where(id: ids).order(:id).lock.index_by(&:id)
    end

    def validate_classroom(entry, classroom)
      if positive_id(entry.classroom_id).nil? || classroom.nil? || !classroom.active?
        entry.errors << I18n.t("admin.teachers.bulk.errors.classroom_invalid")
      elsif entry.grade == :invalid || classroom.grade != entry.grade
        entry.errors << I18n.t("admin.teachers.bulk.errors.classroom_grade_mismatch")
      elsif HomeroomAssignment.current.exists?(classroom_id: classroom.id)
        entry.errors << I18n.t("admin.teachers.bulk.errors.classroom_occupied")
      end
    end

    def create_assignment(entry)
      return unless entry.classroom_id

      HomeroomAssignment.create!(
        teacher: entry.user,
        classroom_id: entry.classroom_id,
        started_on: assignment_started_on
      )
    end

    def assignment_started_on
      school_year.planning? ? Date.new(school_year.year, 3, 1) : Date.current
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
