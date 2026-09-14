module SchoolYears
  class CancelPlanning
    class InvalidState < StandardError
      attr_reader :key

      def initialize(key)
        @key = key
        super(key.to_s)
      end
    end

    Result = Data.define(:year)

    def self.call(actor:, school:, target_school_year_id:, confirmation_year:)
      new(actor:, school:, target_school_year_id:, confirmation_year:).call
    end

    def initialize(actor:, school:, target_school_year_id:, confirmation_year:)
      @actor = actor
      @school = school
      @target_school_year_id = target_school_year_id
      @confirmation_year = confirmation_year.to_s
    end

    def call
      School.transaction do
        school.lock!
        fail_with!(:inactive_school) unless school.active?

        planning_year = lock_planning_year!
        active_year = lock_active_year!
        authorize_after_lock!(planning_year)
        validate_target!(active_year, planning_year)
        validate_dependencies!(planning_year)

        year = planning_year.year
        destroy_workspace!(planning_year)
        Result.new(year:)
      end
    end

    private

    attr_reader :actor, :school, :target_school_year_id, :confirmation_year

    def lock_planning_year!
      planning_years = school.school_years.planning.lock.order(:id).to_a
      fail_with!(:planning_school_year_mismatch) unless planning_years.one?
      fail_with!(:planning_school_year_mismatch) unless planning_years.first.id == target_school_year_id

      planning_years.first
    end

    def lock_active_year!
      active_years = school.school_years.active.lock.order(:id).to_a
      fail_with!(:active_school_year_missing) unless active_years.one?

      active_years.first
    end

    def validate_target!(active_year, planning_year)
      fail_with!(:non_consecutive_year) unless planning_year.year == active_year.year + 1
      fail_with!(:confirmation_mismatch) unless confirmation_year == planning_year.year.to_s
    end

    def authorize_after_lock!(planning_year)
      policy = SchoolYearPolicy.new(actor, planning_year)
      return if policy.cancel?

      raise Pundit::NotAuthorizedError, query: :cancel?, record: planning_year, policy: policy
    end

    def validate_dependencies!(planning_year)
      teacher_ids = planning_year.users.teacher.select(:id)
      classroom_ids = planning_year.classrooms.select(:id)

      fail_with!(:students_present) if Student.where(classroom_id: classroom_ids).exists?
      fail_with!(:external_credential_event) if TeacherCredentialEvent
        .where(actor_user_id: teacher_ids)
        .where.not(teacher_user_id: teacher_ids)
        .exists?
    end

    def destroy_workspace!(planning_year)
      teachers = planning_year.users.teacher.order(:id).to_a
      classrooms = planning_year.classrooms.order(:id).to_a
      teacher_ids = teachers.map(&:id)
      classroom_ids = classrooms.map(&:id)

      HomeroomAssignment.where(teacher_id: teacher_ids)
        .or(HomeroomAssignment.where(classroom_id: classroom_ids))
        .order(:id).each(&:destroy!)
      TeacherCredentialEvent.where(teacher_user_id: teacher_ids).order(:id).each(&:destroy!)
      classrooms.each(&:destroy!)
      teachers.each(&:destroy!)
      planning_year.destroy!
    end

    def fail_with!(key)
      raise InvalidState, key
    end
  end
end
