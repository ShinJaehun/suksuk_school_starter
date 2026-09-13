require "rails_helper"

RSpec.describe Classrooms::BulkUpdater do
  let(:school) { create(:school) }
  let(:year) { create(:school_year, :active, school: school) }

  def teacher(index, grade: 4)
    create(:user, :teacher, school_year: year, school_role: "member", login_id: "class-updater-#{index}", grade: grade)
  end

  def row(classroom, teacher: classroom.teacher, grade: classroom.grade, label: classroom.class_label)
    { id: classroom.id, grade: grade, class_label: label, teacher_id: teacher&.id }
  end

  def update(rows)
    described_class.new(school_year: year, scope: year.classrooms, rows: rows).call
  end

  it "updates grade/class_label and assigns then releases a Teacher with active history" do
    classroom = create(:classroom, school_year: year, grade: 4)
    teacher = teacher(1, grade: 5)
    expect(update([row(classroom, teacher: teacher, grade: 5, label: "새반")])).to be_success
    assignment = classroom.reload.current_homeroom_assignment
    expect(classroom).to have_attributes(grade: 5, class_label: "새")

    expect(update([row(classroom, teacher: nil)])).to be_success
    expect(assignment.reload.ended_on).to eq(Date.current)
  end

  it "supports two-way swaps and three-way cycles" do
    classrooms = 3.times.map { |i| create(:classroom, school_year: year, grade: 4, class_label: (i + 1).to_s) }
    teachers = 3.times.map { |i| teacher(i) }
    classrooms.zip(teachers).each { |classroom, record| create(:homeroom_assignment, classroom: classroom, teacher: record) }

    expect(update([row(classrooms[0], teacher: teachers[1]), row(classrooms[1], teacher: teachers[0])])).to be_success
    expect(classrooms.first(2).map { |classroom| classroom.reload.teacher }).to eq(teachers.first(2).reverse)

    expect(update(classrooms.each_with_index.map { |classroom, i| row(classroom, teacher: teachers[(i + 1) % 3]) })).to be_success
    expect(classrooms.map { |classroom| classroom.reload.teacher }).to eq(teachers.rotate)
  end

  it "rejects outside assignments, grade mismatch, duplicate final labels, and foreign ids atomically" do
    first = create(:classroom, school_year: year, grade: 4, class_label: "1")
    second = create(:classroom, school_year: year, grade: 4, class_label: "2")
    outside = create(:classroom, school_year: year, grade: 4, class_label: "3")
    occupied = teacher(1)
    create(:homeroom_assignment, classroom: outside, teacher: occupied)
    wrong = teacher(2, grade: 5)
    foreign = create(:classroom, school_year: create(:school_year, :active, school: create(:school)), grade: 4)

    result = update([
      row(first, teacher: occupied, label: "변경"),
      row(second, teacher: wrong, label: "변경"),
      { id: foreign.id, grade: 4, class_label: "4", teacher_id: nil }
    ])

    expect(result).not_to be_success
    expect(first.reload).to have_attributes(class_label: "1", teacher: nil)
    expect(second.reload).to have_attributes(class_label: "2", teacher: nil)
  end

  it "deletes and recreates planning preparation assignments" do
    planning = create(:school_year, school: school, year: year.year + 1)
    classroom = create(:classroom, school_year: planning, grade: 4)
    first = create(:user, :teacher, school_year: planning, school_role: "member", login_id: "p1", grade: 4)
    second = create(:user, :teacher, school_year: planning, school_role: "member", login_id: "p2", grade: 4)
    old = create(:homeroom_assignment, classroom: classroom, teacher: first, started_on: Date.new(planning.year, 3, 1))

    result = described_class.new(school_year: planning, scope: planning.classrooms,
      rows: [{ id: classroom.id, grade: 4, class_label: classroom.class_label, teacher_id: second.id }]).call

    expect(result).to be_success
    expect(HomeroomAssignment).not_to exist(old.id)
    expect(classroom.reload.current_homeroom_assignment).to have_attributes(teacher: second, started_on: Date.new(planning.year, 3, 1))
  end
end
