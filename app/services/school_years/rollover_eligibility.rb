module SchoolYears
  class RolloverEligibility
    attr_reader :manager_count

    def initialize(school_year:)
      @school_year = school_year
      @manager_count = managers.count
    end

    def eligible?
      manager_count == 1
    end

    def manager
      managers.first if eligible?
    end

    private

    attr_reader :school_year

    def managers
      @managers ||= school_year.users.teacher.where(school_role: 'manager').order(:id)
    end
  end
end
