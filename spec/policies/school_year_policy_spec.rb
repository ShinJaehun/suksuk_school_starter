require "rails_helper"

RSpec.describe SchoolYearPolicy do
  let(:school) { create(:school) }
  let!(:active_year) { create(:school_year, :active, school: school, year: 2026) }
  let(:planning_year) { build(:school_year, school: school, year: 2027) }

  it "allows a global admin for any active school" do
    expect(described_class.new(create(:user, :admin), planning_year).create?).to eq(true)
  end

  it "allows preparation only for a persisted planning year" do
    admin = create(:user, :admin)
    persisted_planning_year = create(:school_year, school: school, year: 2027)
    archived_year = create(:school_year, :archived, school: school, year: 2025)

    expect(described_class.new(admin, persisted_planning_year).prepare?).to eq(true)
    expect(described_class.new(admin, active_year).prepare?).to eq(false)
    expect(described_class.new(admin, archived_year).prepare?).to eq(false)
    expect(described_class.new(admin, planning_year).prepare?).to eq(false)
    expect(described_class.new(admin, persisted_planning_year).show?).to eq(true)
  end

  it "allows a current operational manager only for their own school" do
    manager = create(:user, :teacher, :active_annual_teacher,
      annual_school: school, annual_school_role: "manager")
    other_school = create(:school)
    create(:school_year, :active, school: other_school, year: 2026)

    expect(described_class.new(manager, planning_year).create?).to eq(true)
    expect(described_class.new(manager, build(:school_year, school: other_school, year: 2027)).create?).to eq(false)
  end

  it "allows a current operational manager to prepare only their own planning year" do
    manager = create(:user, :teacher, :active_annual_teacher,
      annual_school: school, annual_school_role: "manager")
    own_planning_year = create(:school_year, school: school, year: 2027)
    other_school = create(:school)
    create(:school_year, :active, school: other_school, year: 2026)
    other_planning_year = create(:school_year, school: other_school, year: 2027)

    expect(described_class.new(manager, own_planning_year).prepare?).to eq(true)
    expect(described_class.new(manager, other_planning_year).prepare?).to eq(false)
  end

  it "allows an eligible active planning manager to prepare but not create" do
    planning_manager = create(:user, :teacher,
      school_year: create(:school_year, school: school, year: 2027),
      login_id: "planning-manager", school_role: "manager")

    expect(described_class.new(planning_manager, planning_manager.school_year).prepare?).to eq(true)
    expect(described_class.new(planning_manager, planning_year).create?).to eq(false)
  end

  it "rejects ordinary and ineligible manager accounts" do
    member = create(:user, :teacher, :active_annual_teacher, annual_school: school)
    archived_school = create(:school)
    archived_manager = create(:user, :teacher,
      school_year: create(:school_year, :archived, school: archived_school, year: 2025),
      login_id: "archived-manager", school_role: "manager")

    expect(described_class.new(member, planning_year).create?).to eq(false)
    expect(described_class.new(archived_manager, planning_year).create?).to eq(false)

    persisted_planning_year = create(:school_year, school: school, year: 2027)
    expect(described_class.new(member, persisted_planning_year).prepare?).to eq(false)
    expect(described_class.new(archived_manager, persisted_planning_year).prepare?).to eq(false)
  end
end
