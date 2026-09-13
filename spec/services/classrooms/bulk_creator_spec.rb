require "rails_helper"

RSpec.describe Classrooms::BulkCreator do
  let(:school) { create(:school) }
  let(:year) { create(:school_year, :active, school: school) }

  def row(index, grade: 4, teacher: nil, label: nil)
    { grade: grade, class_label: label || index.to_s, teacher_id: teacher&.id }
  end

  it "creates one Classroom and optional HomeroomAssignment" do
    teacher = create(:user, :teacher, school_year: year, school_role: "member", login_id: "class-bulk-1", grade: 4)
    result = described_class.new(school_year: year, rows: [row(1, teacher: teacher)]).call

    expect(result).to be_success
    expect(result.entries.sole.classroom).to have_attributes(school_year: year, active: true)
    expect(result.entries.sole.classroom.teacher).to eq(teacher)
  end

  it "accepts 30 rows and rejects 31 without partial creation" do
    expect(described_class.new(school_year: year, rows: 30.times.map { |i| row(i) }).call).to be_success
    result = described_class.new(school_year: year, rows: 31.times.map { |i| row(i + 100) }).call
    expect(result).not_to be_success
    expect(year.classrooms.count).to eq(30)
  end

  it "rejects normalized batch and existing class-label duplicates" do
    create(:classroom, school_year: year, grade: 4, class_label: "기존")
    result = described_class.new(school_year: year, rows: [
      row(1, label: " 새반 "), row(2, label: "새"), row(3, label: "기존반")
    ]).call

    expect(result).not_to be_success
    expect(year.classrooms.count).to eq(1)
  end

  it "rejects duplicate, assigned, wrong-grade, and foreign-year Teachers atomically" do
    available = create(:user, :teacher, school_year: year, school_role: "member", login_id: "available", grade: 4)
    assigned = create(:user, :teacher, school_year: year, school_role: "member", login_id: "assigned", grade: 4)
    create(:classroom, school_year: year, grade: 4, teacher: assigned)
    wrong = create(:user, :teacher, school_year: year, school_role: "member", login_id: "wrong", grade: 5)
    other_year = create(:school_year, :active, school: create(:school))
    foreign = create(:user, :teacher, school_year: other_year, school_role: "member", login_id: "foreign", grade: 4)
    initial = year.classrooms.count

    result = described_class.new(school_year: year, rows: [
      row(1, teacher: available), row(2, teacher: available), row(3, teacher: assigned),
      row(4, teacher: wrong), row(5, teacher: foreign)
    ]).call

    expect(result).not_to be_success
    expect(year.classrooms.count).to eq(initial)
  end

  it "creates planning structure and assignment without Student data" do
    planning = create(:school_year, school: school, year: year.year + 1)
    teacher = create(:user, :teacher, school_year: planning, school_role: "member", login_id: "planning-class-bulk", grade: 4)

    expect do
      result = described_class.new(school_year: planning, rows: [row(1, teacher: teacher)]).call
      expect(result).to be_success
      expect(result.entries.sole.classroom.current_homeroom_assignment.started_on).to eq(Date.new(planning.year, 3, 1))
    end.not_to change(Student, :count)
  end
end
