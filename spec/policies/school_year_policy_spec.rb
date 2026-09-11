require "rails_helper"

RSpec.describe SchoolYearPolicy do
  let(:school) { create(:school) }
  let!(:active_year) { create(:school_year, :active, school: school, year: 2026) }
  let(:planning_year) { build(:school_year, school: school, year: 2027) }

  it "allows a global admin for any active school" do
    expect(described_class.new(create(:user, :admin), planning_year).create?).to eq(true)
  end

  it "resolves only a persisted planning year as a visible planning context" do
    admin = create(:user, :admin)
    persisted_planning_year = create(:school_year, school: school, year: 2027)
    archived_year = create(:school_year, :archived, school: school, year: 2025)

    expect(described_class.new(admin, persisted_planning_year).show?).to eq(true)
    expect(described_class.new(admin, active_year).show?).to eq(false)
    expect(described_class.new(admin, archived_year).show?).to eq(false)
    expect(described_class.new(admin, planning_year).show?).to eq(false)
  end

  it "allows a current operational manager only for their own school" do
    manager = create(:user, :teacher, :active_annual_teacher,
      annual_school: school, annual_school_role: "manager")
    other_school = create(:school)
    create(:school_year, :active, school: other_school, year: 2026)

    expect(described_class.new(manager, planning_year).create?).to eq(true)
    expect(described_class.new(manager, build(:school_year, school: other_school, year: 2027)).create?).to eq(false)
  end

  it "rejects ordinary and non-operational manager accounts" do
    member = create(:user, :teacher, :active_annual_teacher, annual_school: school)
    planning_manager = create(:user, :teacher,
      school_year: create(:school_year, school: school, year: 2027),
      login_id: "planning-manager", school_role: "manager")
    archived_school = create(:school)
    archived_manager = create(:user, :teacher,
      school_year: create(:school_year, :archived, school: archived_school, year: 2025),
      login_id: "archived-manager", school_role: "manager")

    expect(described_class.new(member, planning_year).create?).to eq(false)
    expect(described_class.new(planning_manager, planning_year).create?).to eq(false)
    expect(described_class.new(archived_manager, planning_year).create?).to eq(false)
  end
end
