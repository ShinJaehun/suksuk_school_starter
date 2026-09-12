module SchoolYears
  class CreatePlanning
    def self.call(actor:, school:)
      new(actor: actor, school: school).call
    end

    def initialize(actor:, school:)
      @actor = actor
      @school = school
    end

    def call
      SchoolYear.transaction do
        school.lock!
        actor.reload
        validate_current_context
        raise ActiveRecord::Rollback if school_year.errors.any?
        authorize_after_lock!

        school_year.save!
      end

      school_year
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
      school_year.errors.add(:base, I18n.t("school_years.errors.creation_conflict"))
      school_year
    end

    private

    attr_reader :actor, :school

    def school_year
      @school_year ||= school.school_years.build(status: :planning)
    end

    def authorize_after_lock!
      policy = SchoolYearPolicy.new(actor, school_year)
      return if policy.create?

      raise Pundit::NotAuthorizedError, query: :create?, record: school_year, policy: policy
    end

    def validate_current_context
      active_years = school.school_years.active.limit(2).to_a
      planning_years = school.school_years.planning.limit(2).to_a

      school_year.errors.add(:base, I18n.t("school_years.errors.active_year_required")) unless active_years.one?
      school_year.errors.add(:base, I18n.t("school_years.errors.planning_year_exists")) if planning_years.any?
      return unless school_year.errors.empty?

      school_year.year = active_years.first.year + 1
      return unless school.school_years.where(year: school_year.year).exists?

      school_year.errors.add(:base, I18n.t("school_years.errors.year_exists"))
    end
  end
end
