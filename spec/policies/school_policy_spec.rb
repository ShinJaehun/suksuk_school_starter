require "rails_helper"

RSpec.describe SchoolPolicy do
  let!(:school) { create(:school) }
  let!(:other_school) { create(:school) }

  def annual_teacher(school:, school_role: "member")
    create(:user, :teacher, :active_annual_teacher,
      annual_school: school,
      annual_school_role: school_role)
  end

  describe "Scope" do
    it "returns all schools for an admin" do
      admin = create(:user, :admin)

      expect(described_class::Scope.new(admin, School).resolve).to contain_exactly(school, other_school)
    end

    it "returns only the member teacher's school" do
      teacher = annual_teacher(school: school)

      expect(described_class::Scope.new(teacher, School).resolve).to contain_exactly(school)
    end

    it "returns only the manager teacher's school" do
      teacher = annual_teacher(school: school, school_role: "manager")

      expect(described_class::Scope.new(teacher, School).resolve).to contain_exactly(school)
    end

    it "hides an inactive member school from teachers but not admins" do
      teacher = annual_teacher(school: school)
      school.update!(active: false)

      expect(described_class::Scope.new(teacher, School).resolve).to be_empty
      expect(described_class::Scope.new(create(:user, :admin), School).resolve).to include(school)
    end

    it "returns an empty relation for a student" do
      student = create(:student)

      expect(described_class::Scope.new(student, School).resolve).to be_empty
    end
  end

  describe "permissions" do
    it "allows an admin to view and manage every school" do
      admin = create(:user, :admin)

      [school, other_school].each do |record|
        policy = described_class.new(admin, record)

        expect(policy.index?).to eq(true)
        expect(policy.show?).to eq(true)
        expect(policy.manage_operations?).to eq(true)
      end
    end

    it "allows a member to view only their school without managing operations" do
      teacher = annual_teacher(school: school)

      own_policy = described_class.new(teacher, school)
      other_policy = described_class.new(teacher, other_school)

      expect(own_policy.index?).to eq(true)
      expect(own_policy.show?).to eq(true)
      expect(own_policy.manage_operations?).to eq(false)
      expect(other_policy.show?).to eq(false)
      expect(other_policy.manage_operations?).to eq(false)
    end

    it "allows a manager to view and manage operations only for their school" do
      teacher = annual_teacher(school: school, school_role: "manager")

      own_policy = described_class.new(teacher, school)
      other_policy = described_class.new(teacher, other_school)

      expect(own_policy.index?).to eq(true)
      expect(own_policy.show?).to eq(true)
      expect(own_policy.manage_operations?).to eq(true)
      expect(other_policy.show?).to eq(false)
      expect(other_policy.manage_operations?).to eq(false)
    end

    it "rejects a manager role when its SchoolYear is not active" do
      planning_year = create(:school_year, school: school, year: 2027)
      planning_manager = create(:user, :teacher, school_year: planning_year,
        login_id: "planning-manager", school_role: "manager")

      expect(described_class::Scope.new(planning_manager, School).resolve).to be_empty
      expect(described_class.new(planning_manager, school).show?).to eq(false)
      expect(described_class.new(planning_manager, school).manage_operations?).to eq(false)
    end

    it "allows only an admin to manage school managers" do
      admin = create(:user, :admin)
      manager = annual_teacher(school: school, school_role: "manager")
      member = annual_teacher(school: other_school)
      student = create(:student)

      expect(described_class.new(admin, school).manage_managers?).to eq(true)
      expect(described_class.new(manager, school).manage_managers?).to eq(false)
      expect(described_class.new(member, school).manage_managers?).to eq(false)
      expect(described_class.new(student, school).manage_managers?).to eq(false)
    end

    it "rejects a student" do
      [create(:student)].each do |user|
        policy = described_class.new(user, school)

        expect(policy.index?).to eq(false)
        expect(policy.show?).to eq(false)
        expect(policy.manage_operations?).to eq(false)
        expect(policy.manage_teachers?).to eq(false)
      end
    end

    it "allows only managers of the record school to manage school teachers" do
      admin = create(:user, :admin)
      manager = annual_teacher(school: school, school_role: "manager")
      member = annual_teacher(school: school)
      other_manager = annual_teacher(school: other_school, school_role: "manager")
      student = create(:student)

      expect(described_class.new(admin, school).manage_teachers?).to eq(false)
      expect(described_class.new(manager, school).manage_teachers?).to eq(true)
      expect(described_class.new(member, school).manage_teachers?).to eq(false)
      expect(described_class.new(other_manager, school).manage_teachers?).to eq(false)
      expect(described_class.new(student, school).manage_teachers?).to eq(false)
      expect(described_class.new(nil, school).manage_teachers?).to be_falsey
    end

    it "keeps school creation, updates, and deletion admin-only" do
      admin_policy = described_class.new(create(:user, :admin), school)
      manager = annual_teacher(school: school, school_role: "manager")
      manager_policy = described_class.new(manager, school)

      expect(admin_policy.create?).to eq(true)
      expect(admin_policy.update?).to eq(true)
      expect(admin_policy.destroy?).to eq(false)
      expect(manager_policy.create?).to eq(false)
      expect(manager_policy.update?).to eq(false)
      expect(manager_policy.destroy?).to eq(false)
    end

    it "allows only admins to change school lifecycle state" do
      admin = create(:user, :admin)
      manager = annual_teacher(school: school, school_role: "manager")

      expect(described_class.new(admin, school).deactivate?).to eq(true)
      expect(described_class.new(manager, school).deactivate?).to eq(false)

      school.update!(active: false)
      expect(described_class.new(admin, school).reactivate?).to eq(true)
      expect(described_class.new(admin, school).show?).to eq(true)
      expect(described_class.new(admin, school).update?).to eq(true)
      expect(described_class.new(admin, school).manage_operations?).to eq(false)
      expect(described_class.new(manager, school).show?).to eq(false)
      expect(described_class.new(manager, school).manage_teachers?).to eq(false)
    end
  end
end
