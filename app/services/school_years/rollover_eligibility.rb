module SchoolYears
  class RolloverEligibility
    attr_reader :manager_count

    def initialize(school_year:)
      @school_year = school_year
      @manager_count = managers.count
    end

    def eligible?
      error_key.nil?
    end

    def error_key
      return :manager_missing if manager_count.zero?
      return :manager_cardinality_invalid unless manager_count == 1
      return :manager_credentials_invalid unless manager_credentials_usable?
    end

    def manager
      managers.first if eligible?
    end

    private

    attr_reader :school_year

    def manager_credentials_usable?
      manager = managers.first
      return false unless manager&.active?
      return false if manager.login_id.blank? || manager.login_id != manager.login_id.strip.downcase
      return false unless BCrypt::Password.valid_hash?(manager.encrypted_password)

      # Inspect only the stored format; never authenticate or generate credentials here.
      digest = BCrypt::Password.new(manager.encrypted_password)
      %w[2a 2b 2x 2y].include?(digest.version) &&
        digest.cost.between?(BCrypt::Engine::MIN_COST, BCrypt::Engine::MAX_COST)
    end

    def managers
      @managers ||= school_year.users.teacher.where(school_role: 'manager').order(:id)
    end
  end
end
