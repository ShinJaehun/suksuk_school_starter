require "rails_helper"

RSpec.describe Teachers::TemporaryPassword do
  describe ".generate" do
    it "returns eight characters from the unambiguous alphabet" do
      password = described_class.generate(login_id: "teacher-login")

      expect(password.length).to eq(8)
      expect(password).to match(/\A[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{8}\z/)
      expect(password).not_to match(/[IO01]/)
    end

    it "regenerates a case-insensitive login ID match" do
      indexes = "ABCDEFGH".chars.map { |character| described_class::CHARACTERS.index(character) }
      replacement = described_class::CHARACTERS.index("Z")
      allow(SecureRandom).to receive(:random_number).and_return(*indexes, *Array.new(8, replacement))

      expect(described_class.generate(login_id: "abcdefgh")).to eq("ZZZZZZZZ")
    end
  end
end
