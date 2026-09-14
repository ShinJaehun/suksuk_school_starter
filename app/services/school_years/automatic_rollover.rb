module SchoolYears
  class AutomaticRollover
    def self.call(school:, target_school_year_id:)
      new(school: school, target_school_year_id: target_school_year_id).call
    end

    def initialize(school:, target_school_year_id:)
      @school = school
      @target_school_year_id = target_school_year_id
    end

    def call
      # A savepoint cannot make the marker durable before an enclosing rollback.
      if School.connection.transaction_open?
        raise ArgumentError, "Automatic rollover must run outside an existing transaction"
      end

      return unless claim_attempt

      # The claim is committed before entering the canonical transition. Even a
      # crash or failed transition consumes this target's automatic opportunity.
      begin
        Rollover.call(school: school, target_school_year_id: target_school_year_id)
      rescue Rollover::InvalidState, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => error
        reason = error.is_a?(Rollover::InvalidState) ? error.key : :transition_failed
        Rails.logger.warn("Automatic rollover failed: school_year_id=#{target_school_year_id} reason=#{reason}")
        nil
      end
    end

    private

    attr_reader :school, :target_school_year_id

    def claim_attempt
      School.transaction do
        school.lock!
        target = school.school_years.lock.find_by(id: target_school_year_id)
        if target&.rollover_overdue? && target.automatic_rollover_attempted_at.nil?
          target.update!(automatic_rollover_attempted_at: Time.current)
          true
        else
          false
        end
      end
    end
  end
end
