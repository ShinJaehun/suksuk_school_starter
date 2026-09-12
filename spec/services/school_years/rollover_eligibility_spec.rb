require 'rails_helper'

RSpec.describe SchoolYears::RolloverEligibility do
  let(:school) { create(:school) }
  let(:planning_year) { create(:school_year, school: school, year: 2027) }

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
