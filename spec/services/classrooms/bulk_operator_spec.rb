require "rails_helper"

RSpec.describe Classrooms::BulkOperator do
  let(:school) { create(:school) }
  let(:year) { create(:school_year, :active, school: school) }
  let(:manager) { create(:user, :teacher, school_year: year, school_role: "manager", login_id: "class-operator") }

  def call(classrooms, operation, grade: nil, target_year: year)
    described_class.new(actor: manager, school_year: target_year, scope: target_year.classrooms,
      classroom_ids: classrooms.map(&:id), operation: operation, grade: grade).call
  end

  it "assigns grade only when every Classroom has no Teacher and final labels are unique" do
    first = create(:classroom, school_year: year, grade: 4, class_label: "1")
    second = create(:classroom, school_year: year, grade: 5, class_label: "2")
    expect(call([first, second], "assign_grade", grade: 6)).to be_success
    expect([first.reload.grade, second.reload.grade]).to eq([6, 6])

    teacher = create(:user, :teacher, school_year: year, school_role: "member", login_id: "assigned-op", grade: 6)
    create(:homeroom_assignment, classroom: first, teacher: teacher)
    expect(call([first, second], "assign_grade", grade: 5)).not_to be_success
    expect(second.reload.grade).to eq(6)
  end

  it "rejects a duplicate resulting class label" do
    first = create(:classroom, school_year: year, grade: 4, class_label: "1")
    create(:classroom, school_year: year, grade: 5, class_label: "1")
    expect(call([first], "assign_grade", grade: 5)).not_to be_success
    expect(first.reload.grade).to eq(4)
  end

  it "activates and deactivates active-year Classrooms atomically" do
    active = create(:classroom, school_year: year)
    inactive = create(:classroom, school_year: year, active: false)
    expect(call([active], "deactivate")).to be_success
    expect(active.reload).to be_inactive
    expect(call([inactive], "activate")).to be_success
    expect(inactive.reload).to be_active
  end

  it "rejects foreign targets, planning lifecycle, and every archived operation" do
    foreign = create(:classroom, school_year: create(:school_year, :active, school: create(:school)))
    expect(call([foreign], "deactivate")).not_to be_success

    planning = create(:school_year, school: school, year: year.year + 1)
    planning_classroom = create(:classroom, school_year: planning)
    expect(call([planning_classroom], "deactivate", target_year: planning)).not_to be_success

    archived = create(:school_year, :archived, school: school, year: year.year - 1)
    archived_classroom = create(:classroom, school_year: archived)
    expect(call([archived_classroom], "assign_grade", grade: 5, target_year: archived)).not_to be_success
  end
end
