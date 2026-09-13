module Classrooms
  class BulkCreator
    MAX_ROWS = 30
    Entry = Data.define(:line, :grade, :class_label, :teacher_id, :classroom, :errors)

    attr_reader :entries, :errors

    def initialize(school_year:, rows:)
      @school_year = school_year
      @entries = Array(rows).each_with_index.map { |row, index| build_entry(row.to_h.stringify_keys, index) }
      @errors = []
    end

    def call
      return invalid_context unless mutable_school_year?

      Classroom.transaction do
        school_year.lock!
        validate_entries
        raise ActiveRecord::Rollback if invalid?

        entries.each do |entry|
          entry.classroom.save!
          create_assignment(entry)
        end
      end
      self
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
      errors << I18n.t("admin.classrooms.bulk.errors.save_conflict")
      self
    end

    def success?
      !invalid? && entries.present? && entries.all? { |entry| entry.classroom.persisted? }
    end

    private

    attr_reader :school_year

    def build_entry(row, index)
      classroom = Classroom.new(
        school_year: school_year,
        grade: row["grade"],
        class_label: row["class_label"],
        active: true
      )
      classroom.valid?
      Entry.new(line: index + 1, grade: row["grade"], class_label: row["class_label"],
        teacher_id: row["teacher_id"].presence, classroom: classroom, errors: [])
    end

    def validate_entries
      errors << I18n.t("admin.classrooms.bulk.errors.row_count") unless entries.size.between?(1, MAX_ROWS)
      validate_classroom_duplicates
      validate_teacher_duplicates
      teachers = locked_teachers
      assignments = HomeroomAssignment.current.where(teacher_id: teachers.keys).order(:id).lock.index_by(&:teacher_id)

      entries.each do |entry|
        entry.classroom.valid?
        entry.errors.concat(entry.classroom.errors.full_messages)
        validate_teacher(entry, teachers[positive_id(entry.teacher_id)], assignments) if entry.teacher_id
      end
    end

    def validate_classroom_duplicates
      entries.group_by { |entry| [entry.classroom.grade, entry.classroom.class_label] }
             .select { |_key, matches| matches.many? }
             .each_value do |matches|
        matches.each { |entry| entry.errors << I18n.t("admin.classrooms.bulk.errors.classroom_duplicate") }
      end
    end

    def validate_teacher_duplicates
      entries.filter_map { |entry| entry if entry.teacher_id }
             .group_by { |entry| positive_id(entry.teacher_id) }
             .select { |id, matches| id && matches.many? }
             .each_value do |matches|
        matches.each { |entry| entry.errors << I18n.t("admin.classrooms.bulk.errors.teacher_duplicate") }
      end
    end

    def locked_teachers
      ids = entries.filter_map { |entry| positive_id(entry.teacher_id) }.uniq
      school_year.users.teacher.active.where(id: ids).order(:id).lock.index_by(&:id)
    end

    def validate_teacher(entry, teacher, assignments)
      if positive_id(entry.teacher_id).nil? || teacher.nil?
        entry.errors << I18n.t("admin.classrooms.bulk.errors.teacher_invalid")
      elsif teacher.grade != entry.classroom.grade
        entry.errors << I18n.t("admin.classrooms.bulk.errors.teacher_grade_mismatch")
      elsif assignments[teacher.id]
        entry.errors << I18n.t("admin.classrooms.bulk.errors.teacher_assigned")
      end
    end

    def create_assignment(entry)
      return unless entry.teacher_id

      HomeroomAssignment.create!(classroom: entry.classroom,
        teacher_id: entry.teacher_id, started_on: assignment_started_on)
    end

    def assignment_started_on
      school_year.planning? ? Date.new(school_year.year, 3, 1) : Date.current
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
