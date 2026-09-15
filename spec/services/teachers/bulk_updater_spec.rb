require "rails_helper"

RSpec.describe Teachers::BulkUpdater do
  context "after a February rollover with a March 1 assignment" do
    include ActiveSupport::Testing::TimeHelpers

    let(:school) { create(:school) }
    let(:planning_year) { create(:school_year, school: school, year: 2027) }
    let(:record) do
      create(:user, :teacher, school_year: planning_year, school_role: "manager",
        login_id: "february-rollover-manager", grade: 4)
    end
    let(:original_classroom) { create(:classroom, school_year: planning_year, grade: 4) }
    let(:replacement) { create(:classroom, school_year: planning_year, grade: 4) }
    let(:assignment) do
      create(:homeroom_assignment, teacher: record, classroom: original_classroom,
        started_on: Date.new(2027, 3, 1))
    end

    before do
      travel_to Time.zone.local(2027, 2, 1)
      create(:school_year, :active, school: school, year: 2026)
      assignment
      replacement
      SchoolYears::Rollover.call(school: school, target_school_year_id: planning_year.id)
      record.reload
      travel_to Time.zone.local(2027, 2, 15)
    end

    after { travel_back }

    def change_rollover_assignment(classroom)
      described_class.new(
        school_year: planning_year.reload,
        scope: planning_year.users.teacher,
        rows: [row(record, classroom: classroom)]
      ).call
    end

    it "releases the future assignment without retaining history" do
      expect(change_rollover_assignment(nil)).to be_success

      expect(HomeroomAssignment.exists?(assignment.id)).to eq(false)
      expect(record.reload.current_homeroom_assignment).to be_nil
      expect(record.homeroom_assignments).to be_empty
    end

    it "replaces the future assignment with an active assignment starting today" do
      expect(change_rollover_assignment(replacement)).to be_success

      expect(HomeroomAssignment.exists?(assignment.id)).to eq(false)
      expect(record.reload.homeroom_assignments.count).to eq(1)
      expect(record.current_homeroom_assignment).to have_attributes(
        classroom: replacement, started_on: Date.new(2027, 2, 15), ended_on: nil
      )
      expect(original_classroom.reload.teacher).to be_nil
    end

    it "preserves started assignment history from March 1 onward" do
      travel_to Time.zone.local(2027, 3, 1)

      expect(change_rollover_assignment(replacement)).to be_success
      expect(assignment.reload).to have_attributes(
        started_on: Date.new(2027, 3, 1), ended_on: Date.new(2027, 3, 1)
      )
      new_assignment = record.reload.current_homeroom_assignment
      expect(new_assignment).to have_attributes(
        classroom: replacement, started_on: Date.new(2027, 3, 1), ended_on: nil
      )

      travel_to Time.zone.local(2027, 3, 2)

      expect(change_rollover_assignment(nil)).to be_success
      expect(new_assignment.reload).to have_attributes(
        started_on: Date.new(2027, 3, 1), ended_on: Date.new(2027, 3, 2)
      )
      expect(record.reload.current_homeroom_assignment).to be_nil
      expect(record.homeroom_assignments).to contain_exactly(assignment, new_assignment)
    end
  end

  let(:school) { create(:school) }
  let(:school_year) { create(:school_year, :active, school: school) }

  def teacher(index, grade: 4, classroom: nil, active: true)
    record = create(:user, :teacher, school_year: school_year, school_role: "member",
      login_id: "update-teacher-#{index}", name: "교사 #{index}", grade: grade, active: active)
    create(:homeroom_assignment, teacher: record, classroom: classroom) if classroom
    record
  end

  def row(record, classroom: record.assigned_classroom, **attributes)
    { id: record.id, name: record.name, login_id: record.login_id,
      grade: record.grade, classroom_id: classroom&.id }.merge(attributes)
  end

  def update(rows)
    described_class.new(school_year: school_year, scope: school_year.users.teacher, rows: rows).call
  end

  it "updates profile and assigns or releases a Classroom with active history" do
    teacher_record = teacher(1)
    classroom = create(:classroom, school_year: school_year, grade: 5)
    expect(update([row(teacher_record, classroom: classroom, name: "변경", login_id: "changed", grade: 5)])).to be_success
    expect(teacher_record.reload).to have_attributes(name: "변경", login_id: "changed", grade: 5)
    assignment = teacher_record.current_homeroom_assignment

    expect(update([row(teacher_record, classroom: nil)])).to be_success
    expect(assignment.reload.ended_on).to eq(Date.current)
  end

  it "supports a two-Teacher Classroom swap" do
    first_classroom = create(:classroom, school_year: school_year, grade: 4)
    second_classroom = create(:classroom, school_year: school_year, grade: 4)
    first = teacher(1, classroom: first_classroom)
    second = teacher(2, classroom: second_classroom)

    expect(update([row(first, classroom: second_classroom), row(second, classroom: first_classroom)])).to be_success
    expect(first.reload.assigned_classroom).to eq(second_classroom)
    expect(second.reload.assigned_classroom).to eq(first_classroom)
  end

  it "supports a three-Teacher Classroom cycle" do
    classrooms = 3.times.map { create(:classroom, school_year: school_year, grade: 4) }
    teachers = classrooms.each_with_index.map { |classroom, index| teacher(index, classroom: classroom) }
    rows = teachers.each_with_index.map { |record, index| row(record, classroom: classrooms[(index + 1) % 3]) }

    expect(update(rows)).to be_success
    expect(teachers.map { |record| record.reload.assigned_classroom }).to eq(classrooms.rotate)
  end

  it "rejects taking an outside occupant Classroom and rolls every row back" do
    occupied = create(:classroom, school_year: school_year, grade: 4)
    outsider = teacher(1, classroom: occupied)
    first = teacher(2)
    second = teacher(3)

    result = update([row(first, classroom: occupied, name: "탈취"), row(second, name: "변경")])

    expect(result).not_to be_success
    expect(first.reload.name).not_to eq("탈취")
    expect(second.reload.name).not_to eq("변경")
    expect(occupied.reload.teacher).to eq(outsider)
  end

  it "rejects duplicate login IDs and duplicate final Classrooms without partial profile changes" do
    classroom = create(:classroom, school_year: school_year, grade: 4)
    first = teacher(1)
    second = teacher(2)

    result = update([
      row(first, classroom: classroom, name: "변경 1", login_id: "duplicate-login"),
      row(second, classroom: classroom, name: "변경 2", login_id: "DUPLICATE-LOGIN")
    ])

    expect(result).not_to be_success
    expect(first.reload.name).to eq("교사 1")
    expect(second.reload.name).to eq("교사 2")
    expect(classroom.reload.teacher).to be_nil
  end

  it "rejects inactive and foreign-year Teacher ids" do
    inactive = teacher(1, active: false)
    other_year = create(:school_year, :archived, school: school, year: school_year.year - 1)
    foreign = create(:user, :teacher, school_year: other_year, school_role: "member", login_id: "foreign-update")

    expect(update([row(inactive, name: "변경")])).not_to be_success
    expect(update([{ id: foreign.id, name: foreign.name, login_id: foreign.login_id, grade: nil }])).not_to be_success
  end

  it "deletes old planning preparation assignments when moving" do
    active_year = school_year
    planning_year = create(:school_year, school: school, year: active_year.year + 1)
    first = create(:classroom, school_year: planning_year, grade: 4)
    second = create(:classroom, school_year: planning_year, grade: 4)
    record = create(:user, :teacher, school_year: planning_year, school_role: "member",
      login_id: "planning-bulk-update", grade: 4)
    old_assignment = create(:homeroom_assignment, teacher: record, classroom: first,
      started_on: Date.new(planning_year.year, 3, 1))

    result = described_class.new(
      school_year: planning_year,
      scope: planning_year.users.teacher,
      rows: [{ id: record.id, name: record.name, login_id: record.login_id, grade: 4, classroom_id: second.id }]
    ).call

    expect(result).to be_success
    expect(HomeroomAssignment).not_to exist(old_assignment.id)
    expect(record.reload.current_homeroom_assignment).to have_attributes(
      classroom: second, started_on: Date.new(planning_year.year, 3, 1)
    )
  end
end
