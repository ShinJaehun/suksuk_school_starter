require "securerandom"

module Teachers
  class TemporaryPassword
    CHARACTERS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789".freeze
    LENGTH = 8

    def self.generate(login_id:)
      loop do
        password = Array.new(LENGTH) do
          CHARACTERS[SecureRandom.random_number(CHARACTERS.length)]
        end.join

        return password unless password.casecmp?(login_id.to_s)
      end
    end
  end
end
