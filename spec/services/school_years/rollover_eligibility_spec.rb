require 'rails_helper'

RSpec.describe SchoolYears::RolloverEligibility do
  let(:school) { create(:school) }
  let(:planning_year) { create(:school_year, school: school, year: 2027) }
  let(:manager) do
    create(:user, :teacher, school_year: planning_year, school_role: 'manager', login_id: 'manager')
  end

  it 'counts an inactive manager but rejects its credentials' do
    manager.update_column(:active, false)
    eligibility = described_class.new(school_year: planning_year)

    expect(eligibility.manager_count).to eq(1)
    expect(eligibility).not_to be_eligible
    expect(eligibility.manager).to be_nil
    expect(eligibility.error_key).to eq(:manager_credentials_invalid)
  end

  ['', ' ', 'not-a-bcrypt-hash', '$2a$99$' + 'a' * 53, '$9z$04$' + 'a' * 53].each do |digest|
    it "rejects an unusable digest #{digest.inspect}" do
      manager.update_column(:encrypted_password, digest)
      eligibility = described_class.new(school_year: planning_year)

      expect(eligibility).not_to be_eligible
      expect(eligibility.error_key).to eq(:manager_credentials_invalid)
    end
  end

  [nil, '', ' ', ' MANAGER ', 'Manager'].each do |login_id|
    it "rejects noncanonical login ID #{login_id.inspect} without weakening DB constraints" do
      manager
      allow_any_instance_of(User).to receive(:login_id).and_return(login_id)

      expect(described_class.new(school_year: planning_year)).not_to be_eligible
    end
  end

  it 'does not hide an inactive manager when checking cardinality' do
    manager
    other_year = create(:school_year, :archived, school: school, year: 2025)
    extra = create(:user, :teacher, school_year: other_year, school_role: 'manager', login_id: 'extra')
    extra.update_column(:active, false)
    # Simulate a broken target association without removing the unique manager index.
    allow(planning_year).to receive(:users).and_return(User.where(id: [manager.id, extra.id]))
    eligibility = described_class.new(school_year: planning_year)

    expect(eligibility.manager_count).to eq(2)
    expect(eligibility).not_to be_eligible
    expect(eligibility.error_key).to eq(:manager_cardinality_invalid)
    expect(eligibility.manager).to be_nil
  end

  it 'allows temporary credentials and ignores unrelated Teacher credentials' do
    manager.update!(password_change_required: true, email: nil, grade: nil)
    member = create(:user, :teacher, school_year: planning_year, school_role: 'member', login_id: 'member')
    member.update_columns(active: false, encrypted_password: '')

    expect(described_class.new(school_year: planning_year)).to be_eligible
  end

  it 'is derived from exactly one planning manager' do
    missing = described_class.new(school_year: planning_year)
    expect(missing).not_to be_eligible
    expect(missing.manager_count).to eq(0)
    expect(missing.manager).to be_nil

    manager = create(:user, :teacher, school_year: planning_year,
      school_role: 'manager', login_id: 'eligibility-manager')
    eligible = described_class.new(school_year: planning_year)

    expect(eligible).to be_eligible
    expect(eligible.manager_count).to eq(1)
    expect(eligible.manager).to eq(manager)
  end
end
