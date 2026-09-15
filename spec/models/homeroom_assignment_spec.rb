require 'rails_helper'

RSpec.describe HomeroomAssignment, type: :model do
  include ActiveSupport::Testing::TimeHelpers

  def teacher_for(classroom, **attributes)
    create(:user, :teacher, :active_annual_teacher,
           annual_school: classroom.school_year.school,
           annual_grade: classroom.grade,
           **attributes)
  end

  it 'provides current teacher and assigned classroom read APIs' do
    classroom = create(:classroom)
    teacher = teacher_for(classroom)
    assignment = create(:homeroom_assignment, classroom: classroom, teacher: teacher)

    expect(classroom.reload.teacher).to eq(teacher)
    expect(teacher.reload.assigned_classroom).to eq(classroom)

    assignment.update!(ended_on: Date.current)

    expect(classroom.reload.teacher).to be_nil
    expect(teacher.reload.assigned_classroom).to be_nil
  end

  it 'rejects a second current assignment for a classroom or teacher' do
    classroom = create(:classroom)
    other_classroom = create(:classroom, school_year: classroom.school_year)
    teacher = teacher_for(classroom)
    other_teacher = teacher_for(classroom)
    create(:homeroom_assignment, classroom: classroom, teacher: teacher)

    expect(build(:homeroom_assignment, classroom: classroom, teacher: other_teacher)).not_to be_valid
    expect(build(:homeroom_assignment, classroom: other_classroom, teacher: teacher)).not_to be_valid
  end

  it 'enforces current Classroom cardinality at the database boundary' do
    classroom = create(:classroom)
    teacher = teacher_for(classroom)
    other_teacher = teacher_for(classroom)
    create(:homeroom_assignment, classroom: classroom, teacher: teacher)

    expect do
      build(:homeroom_assignment, classroom: classroom, teacher: other_teacher)
        .save!(validate: false)
    end.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it 'enforces current teacher cardinality at the database boundary' do
    classroom = create(:classroom)
    other_classroom = create(:classroom, school_year: classroom.school_year)
    teacher = teacher_for(classroom)
    create(:homeroom_assignment, classroom: classroom, teacher: teacher)

    expect do
      build(:homeroom_assignment, classroom: other_classroom, teacher: teacher)
        .save!(validate: false)
    end.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it 'rejects role, SchoolYear, grade, and lifecycle mismatches' do
    classroom = create(:classroom)
    valid_teacher = teacher_for(classroom)
    other_year = create(:school_year, :planning, school: classroom.school_year.school, year: 2027)
    other_year_teacher = create(:user, :teacher, school_year: other_year,
                                                 login_id: 'other-year', school_role: 'member', grade: classroom.grade)
    wrong_grade = teacher_for(classroom, annual_grade: classroom.grade + 1)
    inactive_teacher = teacher_for(classroom, active: false)

    invalid = [
      build(:homeroom_assignment, classroom: classroom, teacher: create(:user, :admin)),
      build(:homeroom_assignment, classroom: classroom, teacher: other_year_teacher),
      build(:homeroom_assignment, classroom: classroom, teacher: wrong_grade),
      build(:homeroom_assignment, classroom: classroom, teacher: inactive_teacher),
      build(:homeroom_assignment, classroom: classroom.tap { |record| record.active = false }, teacher: valid_teacher)
    ]

    expect(invalid).to all(be_invalid)
  end

  it 'allows assignment creation in a planning SchoolYear' do
    school = create(:school)
    school_year = create(:school_year, :planning, school: school)
    classroom = create(:classroom, school_year: school_year, grade: 4)
    teacher = create(:user, :teacher,
                     school_year: school_year,
                     login_id: 'planning-teacher',
                     school_role: 'member',
                     grade: 4)

    expect(build(:homeroom_assignment, classroom: classroom, teacher: teacher)).to be_valid
  end

  it 'requires a present matching Teacher grade in a planning SchoolYear' do
    school = create(:school)
    school_year = create(:school_year, :planning, school: school)
    classroom = create(:classroom, school_year: school_year, grade: 4)
    teachers = [
      create(:user, :teacher, school_year: school_year,
        login_id: 'planning-ungraded', school_role: 'member', grade: nil),
      create(:user, :teacher, school_year: school_year,
        login_id: 'planning-wrong-grade', school_role: 'member', grade: 5)
    ]

    assignments = teachers.map do |teacher|
      build(:homeroom_assignment, classroom: classroom, teacher: teacher)
    end
    expect(assignments).to all(be_invalid)
  end

  it 'rejects assignment creation in an archived SchoolYear' do
    classroom = create(:classroom)
    teacher = teacher_for(classroom)
    classroom.school_year.update!(status: 'archived')

    expect(build(:homeroom_assignment, classroom: classroom, teacher: teacher)).not_to be_valid
  end

  it 'rejects ending an assignment in an archived SchoolYear' do
    assignment = create(:homeroom_assignment)
    assignment.classroom.school_year.update!(status: 'archived')

    expect(assignment.update(ended_on: Date.current)).to eq(false)
  end

  it 'preserves archived assignment history when the teacher is deactivated' do
    assignment = create(:homeroom_assignment)
    assignment.classroom.school_year.update!(status: 'archived')

    assignment.teacher.update!(active: false)

    expect(assignment.reload.ended_on).to be_nil
    expect(assignment.teacher.reload).to be_inactive
  end

  it 'deletes a future-start assignment when the teacher is deactivated after a February rollover' do
    travel_to Time.zone.local(2027, 2, 1) do
      school = create(:school)
      create(:school_year, :active, school: school, year: 2026)
      planning_year = create(:school_year, school: school, year: 2027)
      create(:user, :teacher, school_year: planning_year, school_role: 'manager',
                             login_id: 'deactivation-rollover-manager')
      teacher = create(:user, :teacher, school_year: planning_year, school_role: 'member',
                                       login_id: 'deactivation-rollover-teacher', grade: 4)
      classroom = create(:classroom, school_year: planning_year, grade: 4)
      assignment = create(:homeroom_assignment, teacher: teacher, classroom: classroom,
                                                started_on: Date.new(2027, 3, 1))

      expect(planning_year).to be_planning
      expect(assignment.reload.started_on).to eq(Date.new(2027, 3, 1))

      SchoolYears::Rollover.call(school: school, target_school_year_id: planning_year.id)
      expect(planning_year.reload).to be_active
      travel_to Time.zone.local(2027, 2, 15)

      expect(teacher.reload.update(active: false)).to eq(true)

      expect(teacher.reload).to be_inactive
      expect(HomeroomAssignment.exists?(assignment.id)).to eq(false)
      expect(teacher.homeroom_assignments).to be_empty
      expect(teacher.assigned_classroom).to be_nil
    end
  end

  it 'keeps ended history when a teacher with a started active assignment is deactivated' do
    travel_to Time.zone.local(2027, 3, 15) do
      assignment = create(:homeroom_assignment, started_on: Date.new(2027, 3, 1))
      teacher = assignment.teacher

      expect(assignment.classroom.school_year).to be_active
      expect(teacher.update(active: false)).to eq(true)

      expect(teacher.reload).to be_inactive
      expect(assignment.reload).to have_attributes(
        started_on: Date.new(2027, 3, 1), ended_on: Date.current
      )
      expect(teacher.homeroom_assignments).to contain_exactly(assignment)
      expect(teacher.assigned_classroom).to be_nil
    end
  end

  it 'rejects an end date before its start date' do
    assignment = build(:homeroom_assignment, started_on: Date.current, ended_on: Date.yesterday)

    expect(assignment).not_to be_valid
  end

  it 'protects Classroom and teacher history from physical deletion' do
    assignment = create(:homeroom_assignment)

    expect(assignment.classroom.destroy).to eq(false)
    expect(assignment.teacher.destroy).to eq(false)
    expect(described_class.exists?(assignment.id)).to eq(true)
  end
end
