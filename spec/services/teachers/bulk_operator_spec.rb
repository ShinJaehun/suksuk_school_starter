require "rails_helper"

RSpec.describe Teachers::BulkOperator do
  let(:school) { create(:school) }
  let(:school_year) { create(:school_year, :active, school: school) }
  let(:manager) do
    create(:user, :teacher, school_year: school_year, school_role: "manager",
      login_id: "bulk-manager", grade: 4)
  end

  def teacher(index, active: true)
    create(:user, :teacher, school_year: school_year, school_role: "member",
      login_id: "operator-teacher-#{index}", grade: 4, active: active)
  end

  def call(ids, operation, grade: nil)
    described_class.new(actor: manager, school_year: school_year,
      scope: school_year.users.teacher, teacher_ids: ids, operation: operation, grade: grade).call
  end

  it "assigns a grade only when every selected Teacher has no assignment" do
    first = teacher(1)
    second = teacher(2)
    classroom = create(:classroom, school_year: school_year, grade: 4)
    create(:homeroom_assignment, teacher: second, classroom: classroom)

    expect(call([first.id], "assign_grade", grade: 5)).to be_success
    expect(first.reload.grade).to eq(5)
    expect(call([first.id, second.id], "assign_grade", grade: 6)).not_to be_success
    expect(first.reload.grade).to eq(5)
    expect(second.reload.grade).to eq(4)
  end

  it "activates and deactivates an authorized batch" do
    inactive = teacher(1, active: false)
    active = teacher(2)

    expect(call([inactive.id], "activate")).to be_success
    expect(inactive.reload).to be_active
    expect(call([active.id], "deactivate")).to be_success
    expect(active.reload).to be_inactive
  end

  it "rolls back a deactivate batch containing the actor" do
    other = teacher(1)

    expect(call([other.id, manager.id], "deactivate")).not_to be_success
    expect(other.reload).to be_active
    expect(manager.reload).to be_active
  end

  it "rejects a planning manager target and an out-of-scope Teacher" do
    planning_year = create(:school_year, school: school, year: school_year.year + 1)
    planning_manager = create(:user, :teacher, school_year: planning_year, school_role: "manager",
      login_id: "planning-manager-target")
    other = teacher(1)

    planning_result = described_class.new(actor: manager, school_year: planning_year,
      scope: planning_year.users.teacher, teacher_ids: [planning_manager.id], operation: "deactivate").call
    scope_result = call([other.id, create(:user, :teacher, school_year: create(
      :school_year, :active, school: create(:school)
    ), school_role: "member", login_id: "foreign-operation").id], "deactivate")

    expect(planning_result).not_to be_success
    expect(scope_result).not_to be_success
    expect(other.reload).to be_active
  end

  it "rejects every operation in an archived SchoolYear" do
    archived_year = create(:school_year, :archived, school: school, year: school_year.year - 1)
    archived_teacher = create(:user, :teacher, school_year: archived_year,
      school_role: "member", login_id: "archived-operation")

    result = described_class.new(actor: manager, school_year: archived_year,
      scope: archived_year.users.teacher, teacher_ids: [archived_teacher.id],
      operation: "assign_grade", grade: 5).call

    expect(result).not_to be_success
    expect(archived_teacher.reload.grade).to be_nil
  end
end
