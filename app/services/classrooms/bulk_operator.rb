module Classrooms
  class BulkOperator
    MAX_ROWS = 30
    OPERATIONS = %w[assign_grade activate deactivate].freeze

    attr_reader :error

    def initialize(actor:, school_year:, scope:, classroom_ids:, operation:, grade: nil)
      @actor = actor
      @school_year = school_year
      @scope = scope
      @raw_ids = Array(classroom_ids).map(&:to_s)
      @operation = operation.to_s
      @grade = grade.to_s
    end

    def call
      unless mutable_school_year?
        fail_with(:context_invalid)
        return self
      end

      unless valid_ids?
        fail_with(:selection_required)
        return self
      end

      unless OPERATIONS.include?(operation)
        fail_with(:operation_invalid)
        return self
      end

      if school_year.planning? && operation != 'assign_grade'
        fail_with(:planning_lifecycle)
        return self
      end

      if operation == 'assign_grade' && normalized_grade.nil?
        fail_with(:grade_invalid)
        return self
      end

      Classroom.transaction do
        school_year.lock!
        classrooms = locked_classrooms
        raise ActiveRecord::Rollback unless classrooms

        assignments = HomeroomAssignment.current.where(classroom_id: ids).order(:id).lock.to_a
        raise ActiveRecord::Rollback unless operation_allowed?(classrooms, assignments)

        apply(classrooms)
      end
      self
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
      fail_with(:save_conflict)
      self
    end

    def success?
      error.nil?
    end

    private

    attr_reader :actor, :school_year, :scope, :raw_ids, :operation, :grade

    def locked_classrooms
      allowed = scope.where(id: ids).pluck(:id)
      return fail_with(:classroom_scope) unless allowed.sort == ids.sort

      Classroom.where(id: ids).order(:id).lock.to_a
    end

    def operation_allowed?(classrooms, assignments)
      if operation == 'assign_grade'
        return fail_with(:grade_assignment_present) unless classrooms.all?(&:active?) && assignments.empty?

        labels = classrooms.map(&:class_label)
        duplicate = school_year.classrooms.where(grade: normalized_grade, class_label: labels)
                               .where.not(id: ids).exists? || labels.uniq.size != labels.size
        return fail_with(:classroom_duplicate) if duplicate

        return true
      end
      query = operation == 'activate' ? :reactivate? : :deactivate?
      return true if classrooms.all? { |classroom| ClassroomPolicy.new(actor, classroom).public_send(query) }

      fail_with(:operation_forbidden)
    end

    def apply(classrooms)
      case operation
      when 'assign_grade'
        classrooms.each { |classroom| classroom.update!(grade: normalized_grade) }
      when 'activate'
        classrooms.each { |classroom| classroom.update!(active: true) }
      when 'deactivate'
        classrooms.each { |classroom| classroom.update!(active: false) }
      end
    end

    def ids
      @ids ||= raw_ids.map(&:to_i)
    end

    def valid_ids?
      raw_ids.present? && raw_ids.size <= MAX_ROWS &&
        raw_ids.all? { |id| id.match?(/\A[1-9]\d*\z/) } && ids.uniq.size == ids.size
    end

    def normalized_grade
      @normalized_grade ||= grade.to_i if grade.match?(/\A[1-6]\z/)
    end

    def mutable_school_year?
      school_year&.school&.active? && (school_year.active? || school_year.planning?)
    end

    def fail_with(key)
      @error ||= I18n.t("admin.classrooms.bulk.errors.#{key}")
      nil
    end
  end
end
