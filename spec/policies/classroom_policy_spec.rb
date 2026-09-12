require "rails_helper"

RSpec.describe ClassroomPolicy do
  def annual_teacher(school:, school_role: "member", grade: nil)
    create(:user, :teacher, :active_annual_teacher,
      annual_school: school,
      annual_school_role: school_role,
      annual_grade: grade)
  end

  describe "Scope" do
    let(:school) { create(:school) }
    let(:other_school) { create(:school) }
    let!(:classroom) { create(:classroom, annual_school: school) }
    let!(:other_classroom) { create(:classroom, annual_school: other_school) }

    it "returns every classroom for an admin" do
      admin = create(:user, :admin)

      expect(Pundit.policy_scope!(admin, Classroom)).to contain_exactly(classroom, other_classroom)
    end

    it "returns every classroom in the manager school" do
      manager = annual_teacher(school: school, school_role: "manager")

      expect(Pundit.policy_scope!(manager, Classroom)).to contain_exactly(classroom)
    end

    it "returns only assigned classrooms for a regular teacher" do
      assigned_classroom = create(:classroom, annual_school: school)
      teacher = annual_teacher(school: school, grade: assigned_classroom.grade)
      assign_teacher(assigned_classroom, teacher)
      expect(Pundit.policy_scope!(teacher, Classroom)).to contain_exactly(assigned_classroom)
    end

    it "does not grant a Student scope to another classroom" do
      student = create(:student, classroom: classroom)

      expect(Pundit.policy_scope!(student, Classroom)).not_to include(other_classroom)
    end

    it "returns only the Student actor's active classroom" do
      student = create(:student, classroom: classroom)

      expect(Pundit.policy_scope!(student, Classroom)).to contain_exactly(classroom)
    end

    it "returns no classrooms for an inactive Student actor" do
      student = create(:student, classroom: classroom, active: false)

      expect(Pundit.policy_scope!(student, Classroom)).to be_empty
    end

    it "lets the index scope include an admin-selected SchoolYear without widening mutation scope" do
      admin = create(:user, :admin)
      planning_year = create(:school_year,
        school: school,
        year: classroom.school_year.year + 1)
      archived_year = create(:school_year, :archived,
        school: school,
        year: classroom.school_year.year - 1)
      planning_classroom = create(:classroom, school_year: planning_year)
      archived_classroom = create(:classroom, school_year: archived_year)

      expect(described_class::IndexScope.new(admin, Classroom).resolve).to include(
        classroom,
        planning_classroom,
        archived_classroom
      )
      expect(described_class::Scope.new(admin, Classroom).resolve).not_to include(
        planning_classroom,
        archived_classroom
      )
    end

    it "limits a manager index scope to their own school across allowed controller contexts" do
      manager = annual_teacher(school: school, school_role: "manager")
      planning_year = create(:school_year,
        school: school,
        year: manager.school_year.year + 1)
      planning_classroom = create(:classroom, school_year: planning_year)

      expect(described_class::IndexScope.new(manager, Classroom).resolve).to include(
        classroom,
        planning_classroom
      )
      expect(described_class::IndexScope.new(manager, Classroom).resolve).not_to include(other_classroom)
    end

    it "does not grant classroom scope to a Student in an inactive classroom" do
      student = create(:student, classroom: classroom)
      classroom.update!(active: false)

      expect(Pundit.policy_scope!(student, Classroom)).to be_empty
    end
  end

  describe "#show?" do
    it "permits a manager to view an unassigned classroom in their school" do
      school = create(:school)
      classroom = create(:classroom, annual_school: school)
      manager = annual_teacher(school: school, school_role: "manager")

      expect(described_class.new(manager, classroom).show?).to eq(true)
    end

    it "rejects a manager outside the classroom school" do
      classroom = create(:classroom)
      manager = annual_teacher(school: create(:school), school_role: "manager")

      expect(described_class.new(manager, classroom).show?).to eq(false)
    end
  end

  describe "#view_student_data?" do
    let(:school) { create(:school) }
    let(:classroom) { create(:classroom, annual_school: school) }

    it "permits an admin" do
      expect(described_class.new(create(:user, :admin), classroom).view_student_data?).to eq(true)
    end

    it "permits a teacher assigned to the classroom" do
      teacher = annual_teacher(school: school, grade: classroom.grade)
      assign_teacher(classroom, teacher)
      expect(described_class.new(teacher, classroom).view_student_data?).to eq(true)
    end

    it "rejects a teacher outside the classroom" do
      teacher = annual_teacher(school: school)
      expect(described_class.new(teacher, classroom).view_student_data?).to eq(false)
    end

    it "rejects an unassigned school manager" do
      manager = annual_teacher(school: school, school_role: "manager")

      expect(described_class.new(manager, classroom).view_student_data?).to eq(false)
    end

    it "permits a manager who is also assigned to the classroom" do
      manager = annual_teacher(school: school, school_role: "manager", grade: classroom.grade)
      assign_teacher(classroom, manager)
      expect(described_class.new(manager, classroom).view_student_data?).to eq(true)
    end

    it "does not grant student-data access to a Student from another classroom" do
      student = create(:student)

      expect(described_class.new(student, classroom).view_student_data?).to eq(false)
    end

    it "permits an active Student actor only in its operational classroom" do
      student = create(:student, classroom: classroom)

      expect(described_class.new(student, classroom).view_student_data?).to eq(true)
      expect(described_class.new(student, create(:classroom)).view_student_data?).to eq(false)
    end
  end

  describe "classroom operation permissions" do
    let(:school) { create(:school) }
    let(:classroom) { create(:classroom, annual_school: school) }
    let(:manager) do
      annual_teacher(school: school, school_role: "manager", grade: classroom.grade)
    end

    it "keeps settings update access for an unassigned manager but blocks teacher operations" do
      policy = described_class.new(manager, classroom)

      expect(policy.update?).to eq(true)
      expect(policy.manage_members?).to eq(false)
      expect(policy.destroy?).to eq(false)
    end

    it "combines manager access with existing classroom teacher permissions" do
      assign_teacher(classroom, manager)
      policy = described_class.new(manager, classroom)

      expect(policy.update?).to eq(true)
      expect(policy.manage_members?).to eq(true)
      expect(policy.destroy?).to eq(false)
    end

  end

  describe "settings permissions" do
    let(:school) { create(:school) }
    let(:classroom) { create(:classroom, annual_school: school) }

    it "allows an admin to render structure fields before a new classroom has a school" do
      policy = described_class.new(create(:user, :admin), Classroom.new)

      expect(policy.manage_structure?).to eq(true)
    end

    it "allows an admin to manage structure, operations, and members" do
      policy = described_class.new(create(:user, :admin), classroom)

      expect(policy.manage_structure?).to eq(true)
      expect(policy.manage_operations?).to eq(true)
      expect(policy.update?).to eq(true)
      expect(policy.manage_members?).to eq(true)
    end

    it "allows an unassigned school manager to manage only structure" do
      manager = annual_teacher(school: school, school_role: "manager")
      policy = described_class.new(manager, classroom)

      expect(policy.manage_structure?).to eq(true)
      expect(policy.manage_operations?).to eq(false)
      expect(policy.update?).to eq(true)
      expect(policy.manage_members?).to eq(false)
    end

    it "combines structure and teacher permissions for an assigned school manager" do
      manager = annual_teacher(school: school, school_role: "manager", grade: classroom.grade)
      assign_teacher(classroom, manager)
      policy = described_class.new(manager, classroom)

      expect(policy.manage_structure?).to eq(true)
      expect(policy.manage_operations?).to eq(true)
      expect(policy.update?).to eq(true)
      expect(policy.manage_members?).to eq(true)
    end

    it "allows an assigned regular teacher to manage operations and members only" do
      teacher = annual_teacher(school: school, grade: classroom.grade)
      assign_teacher(classroom, teacher)
      policy = described_class.new(teacher, classroom)

      expect(policy.manage_structure?).to eq(false)
      expect(policy.manage_operations?).to eq(true)
      expect(policy.update?).to eq(false)
      expect(policy.edit?).to eq(false)
      expect(policy.manage_members?).to eq(true)
    end

    it "rejects an unassigned teacher, student, and guest" do
      users = [annual_teacher(school: school), create(:student, classroom: classroom), nil]

      users.each do |user|
        policy = described_class.new(user, classroom)

        expect(policy.manage_structure?).to eq(false)
        expect(policy.manage_operations?).to eq(false)
        expect(policy.update?).to eq(false)
        expect(policy.manage_members?).to eq(false)
      end
    end

    it "rejects a manager role outside the current operational SchoolYear" do
      planning_year = create(:school_year, school: school, year: 2027)
      planning_manager = create(:user, :teacher, school_year: planning_year,
        login_id: "planning-manager", school_role: "manager")
      policy = described_class.new(planning_manager, classroom)

      expect(policy.show?).to eq(false)
      expect(policy.manage_structure?).to eq(false)
      expect(described_class::Scope.new(planning_manager, Classroom).resolve).to be_empty
    end

    it "does not widen existing classroom mutation permissions in planning context" do
      planning_year = create(:school_year, school: school, year: classroom.school_year.year + 1)
      planning_classroom = create(:classroom, school_year: planning_year)
      admin = create(:user, :admin)
      manager = annual_teacher(school: school, school_role: "manager")

      [admin, manager].each do |actor|
        policy = described_class.new(actor, planning_classroom)

        expect(policy.manage_structure?).to eq(false)
        expect(policy.update?).to eq(false)
        expect(policy.deactivate?).to eq(false)
        expect(policy.reactivate?).to eq(false)
      end
    end
  end

  describe "lifecycle permissions" do
    let(:school) { create(:school) }
    let(:active_classroom) { create(:classroom, annual_school: school) }
    let(:inactive_classroom) { create(:classroom, annual_school: school, active: false) }

    it "allows an admin to deactivate active and reactivate inactive classrooms" do
      admin = create(:user, :admin)

      expect(described_class.new(admin, active_classroom).deactivate?).to eq(true)
      expect(described_class.new(admin, inactive_classroom).reactivate?).to eq(true)
    end

    it "allows only the classroom school's manager" do
      manager = annual_teacher(school: school, school_role: "manager")
      other_manager = annual_teacher(school: create(:school), school_role: "manager")

      expect(described_class.new(manager, active_classroom).deactivate?).to eq(true)
      expect(described_class.new(manager, inactive_classroom).reactivate?).to eq(true)
      expect(described_class.new(other_manager, active_classroom).deactivate?).to eq(false)
      expect(described_class.new(other_manager, inactive_classroom).reactivate?).to eq(false)
    end

    it "rejects ordinary teachers and students" do
      teacher = annual_teacher(school: school, grade: active_classroom.grade)
      student = create(:student, classroom: active_classroom)
      assign_teacher(active_classroom, teacher)

      [teacher, student].each do |user|
        expect(described_class.new(user, active_classroom).deactivate?).to eq(false)
        expect(described_class.new(user, inactive_classroom).reactivate?).to eq(false)
      end
    end

    it "rejects lifecycle mutations inside an inactive school" do
      admin = create(:user, :admin)
      school.update!(active: false)

      expect(described_class.new(admin, active_classroom).deactivate?).to eq(false)
      expect(described_class.new(admin, inactive_classroom).reactivate?).to eq(false)
    end

    it "blocks ordinary operations and member management in inactive classrooms" do
      admin = create(:user, :admin)

      expect(described_class.new(admin, inactive_classroom).edit?).to eq(true)
      expect(described_class.new(admin, inactive_classroom).manage_structure?).to eq(false)
      expect(described_class.new(admin, inactive_classroom).manage_operations?).to eq(false)
      expect(described_class.new(admin, inactive_classroom).manage_members?).to eq(false)
      expect(described_class.new(admin, inactive_classroom).update?).to eq(false)
    end
  end

  describe "#destroy?" do
    let(:school) { create(:school) }
    let(:classroom) { create(:classroom, annual_school: school) }

    it "permits an admin" do
      expect(described_class.new(create(:user, :admin), classroom).destroy?).to eq(true)
    end

    it "rejects an assigned teacher" do
      teacher = annual_teacher(school: school, grade: classroom.grade)
      assign_teacher(classroom, teacher)
      expect(described_class.new(teacher, classroom).destroy?).to eq(false)
    end

    it "rejects an unassigned teacher" do
      teacher = annual_teacher(school: school)
      expect(described_class.new(teacher, classroom).destroy?).to eq(false)
    end

    it "rejects an unassigned school manager" do
      manager = annual_teacher(school: school, school_role: "manager")

      expect(described_class.new(manager, classroom).destroy?).to eq(false)
    end

    it "rejects a school manager who is also an assigned teacher" do
      manager = annual_teacher(school: school, school_role: "manager", grade: classroom.grade)
      assign_teacher(classroom, manager)
      expect(described_class.new(manager, classroom).destroy?).to eq(false)
    end

    it "rejects a student" do
      expect(described_class.new(create(:student, classroom: classroom), classroom).destroy?).to eq(false)
    end

    it "rejects a guest" do
      expect(described_class.new(nil, classroom).destroy?).to eq(false)
    end
  end

end
