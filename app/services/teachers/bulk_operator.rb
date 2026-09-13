module Teachers
  class BulkOperator
    MAX_ROWS = 30
    OPERATIONS = %w[assign_grade activate deactivate].freeze

    attr_reader :error

    def initialize(actor:, school_year:, scope:, teacher_ids:, operation:, grade: nil)
      @actor = actor
      @school_year = school_year
      @scope = scope
      @raw_ids = Array(teacher_ids).map(&:to_s)
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

      if operation == 'assign_grade' && normalized_grade == :invalid
        fail_with(:grade_invalid)
        return self
      end

      User.transaction do
        school_year.lock!
        users = locked_users
        raise ActiveRecord::Rollback unless users

        assignments = HomeroomAssignment.current.where(teacher_id: ids).order(:id).lock.includes(:classroom).to_a
        Classroom.where(id: assignments.map(&:classroom_id)).order(:id).lock.load
        raise ActiveRecord::Rollback unless operation_allowed?(users, assignments)

        apply(users)
      end
      self
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
      fail_with(:save_conflict)
    end

    def success?
      error.nil?
    end

    private

    attr_reader :actor, :school_year, :scope, :raw_ids, :operation, :grade

    def mutable_school_year?
      school_year&.school&.active? && (school_year.active? || school_year.planning?)
    end

    def valid_ids?
      raw_ids.present? && raw_ids.size <= MAX_ROWS &&
        raw_ids.all? { |id| id.match?(/\A[1-9]\d*\z/) } && ids.uniq.size == ids.size
    end

    def ids
      @ids ||= raw_ids.map(&:to_i)
    end

    def locked_users
      allowed_ids = scope.where(id: ids).pluck(:id)
      return fail_with(:teacher_scope) unless allowed_ids.sort == ids.sort

      User.where(id: ids).order(:id).lock.to_a
    end

    def operation_allowed?(users, assignments)
      if operation == 'assign_grade'
        return fail_with(:grade_assignment_present) unless users.all?(&:active?) && assignments.empty?

        return true
      end

      query = operation == 'activate' ? :reactivate_teacher? : :deactivate_teacher?
      return true if users.all? { |user| UserPolicy.new(actor, user).public_send(query) }

      fail_with(:operation_forbidden)
    end

    def apply(users)
      case operation
      when 'assign_grade'
        users.each { |user| user.update!(grade: normalized_grade) }
      when 'activate'
        users.each { |user| user.update!(active: true) }
      when 'deactivate'
        users.each { |user| user.update!(active: false, remember_created_at: nil) }
      end
    end

    def normalized_grade
      return @normalized_grade if defined?(@normalized_grade)

      @normalized_grade = if grade.blank? || grade == 'unassigned'
                            nil
                          elsif grade.match?(/\A[1-6]\z/)
                            grade.to_i
                          else
                            :invalid
                          end
    end

    def fail_with(key)
      @error ||= I18n.t("admin.teachers.bulk.errors.#{key}")
      nil
    end
  end
end
