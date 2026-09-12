module SchoolYears
  class Rollover
    class InvalidState < StandardError
      attr_reader :key

      def initialize(key)
        @key = key
        super(key.to_s)
      end
    end

    Result = Struct.new(:active_school_year, :archived_school_year, keyword_init: true)

    def self.call(school:, target_school_year_id:)
      new(school: school, target_school_year_id: target_school_year_id).call
    end

    def initialize(school:, target_school_year_id:)
      @school = school
      @target_school_year_id = target_school_year_id
    end

    def call
      School.transaction do
        school.lock!
        validate_school!

        active_school_year = lock_current_active_school_year!
        target_school_year = lock_target_school_year!
        validate_target!(active_school_year, target_school_year)

        active_school_year.update!(status: :archived)
        target_school_year.update!(status: :active)

        Result.new(
          active_school_year: target_school_year,
          archived_school_year: active_school_year
        )
      end
    end

    private

    attr_reader :school, :target_school_year_id

    def validate_school!
      fail_with!(:inactive_school) unless school.active?
    end

    def lock_current_active_school_year!
      active_school_years = school.school_years.active.lock.order(:id).to_a
      fail_with!(:active_school_year_missing) unless active_school_years.one?

      active_school_years.first
    end

    def lock_target_school_year!
      school.school_years.lock.find_by(id: target_school_year_id) || fail_with!(:planning_school_year_missing)
    end

    def validate_target!(active_school_year, target_school_year)
      fail_with!(:target_not_planning) unless target_school_year.planning?
      fail_with!(:planning_school_year_mismatch) unless school.school_years.planning.where.not(id: target_school_year.id).none?
      fail_with!(:non_consecutive_year) unless target_school_year.year == active_school_year.year + 1

      eligibility = RolloverEligibility.new(school_year: target_school_year)
      fail_with!(:manager_missing) if eligibility.manager_count.zero?
      fail_with!(:manager_cardinality_invalid) unless eligibility.eligible?
    end

    def fail_with!(key)
      raise InvalidState, key
    end
  end
end
