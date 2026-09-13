require "rails_helper"

RSpec.describe UserPolicy do
  describe "generic user authorization" do
    let(:school) { create(:school) }
    let(:manager) do
      create(:user, :teacher, :active_annual_teacher,
        annual_school: school,
        annual_school_role: "manager")
    end
    let(:member) do
      create(:user, :teacher, :active_annual_teacher,
        annual_school: school,
        annual_school_role: "member")
    end

    it "keeps index, create, update, and scope admin-only" do
      admin = create(:user, :admin)

      expect(described_class.new(admin, User).index?).to eq(true)
      expect(described_class.new(admin, User.new(role: :teacher)).create?).to eq(true)
      expect(described_class.new(manager, User).index?).to eq(false)
      expect(described_class.new(manager, User.new(role: :teacher)).create?).to eq(false)
      expect(described_class.new(manager, member).update?).to eq(false)
      expect(described_class::Scope.new(manager, User).resolve).to contain_exactly(manager)
    end
  end

  describe "teacher status actions" do
    let(:school) { create(:school) }
    let(:manager) do
      create(:user, :teacher, :active_annual_teacher,
        annual_school: school,
        annual_school_role: "manager")
    end
    let(:member) do
      create(:user, :teacher, :active_annual_teacher,
        annual_school: school,
        annual_school_role: "member")
    end

    it "allows admins to change teacher status" do
      admin = create(:user, :admin)
      expect(described_class.new(admin, member).deactivate_teacher?).to eq(true)
      member.update!(active: false)
      expect(described_class.new(admin, member).reactivate_teacher?).to eq(true)
    end

    it "allows a manager only for another same-school member" do
      expect(described_class.new(manager, member).deactivate_teacher?).to eq(true)
      expect(described_class.new(manager, manager).deactivate_teacher?).to eq(false)
      expect(described_class.new(member, manager).deactivate_teacher?).to eq(false)
      other_school = create(:school)
      other_teacher = create(:user, :teacher, :active_annual_teacher, annual_school: other_school)

      expect(described_class.new(manager, other_teacher).deactivate_teacher?).to eq(false)
      expect(described_class.new(manager, create(:user, :admin)).deactivate_teacher?).to eq(false)
    end

    it "lets an eligible planning manager change an active Teacher status in its School" do
      planning_year = create(:school_year, school: school, year: manager.school_year.year + 1)
      planning_manager = create(:user, :teacher, school_year: planning_year,
        login_id: "planning-manager", school_role: "manager")

      expect(described_class.new(planning_manager, member).deactivate_teacher?).to eq(true)
      expect(described_class.new(planning_manager, planning_manager).deactivate_teacher?).to eq(false)

      archived_teacher = create(:user, :teacher,
        school_year: create(:school_year, :archived, school: school, year: manager.school_year.year - 1),
        login_id: "archived-member", school_role: "member")
      expect(described_class.new(planning_manager, archived_teacher).deactivate_teacher?).to eq(false)
    end
  end
end
