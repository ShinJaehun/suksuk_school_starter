require "rails_helper"

RSpec.describe Teachers::SaveWithAssignment do
  let(:actor) { create(:user, :admin) }

  def annual_teacher(school:, grade:, school_role: "member", **attributes)
    create(:user, :teacher, :active_annual_teacher, annual_school: school,
      annual_school_role: school_role, annual_grade: grade, **attributes)
  end

  def save(teacher:, school:, grade:, classroom: nil, attributes: {})
    described_class.call(teacher: teacher, attributes: attributes, school: school,
      membership_grade: grade, classroom_id: classroom&.id, actor: actor)
  end

  it "creates an annual member teacher with a temporary credential" do
    school = create(:school)
    create(:school_year, :active, school: school)
    teacher = build(:user, :teacher, login_id: " NewTeacher ", email: nil)

    result = save(teacher: teacher, school: school, grade: 5)

    expect(result).to be_success
    expect(teacher).to have_attributes(school_year: school.school_years.active.first,
      login_id: "newteacher", school_role: "member", grade: 5, password_change_required: true)
    expect(result.temporary_password).to be_present
    expect(teacher.teacher_credential_events.temporary_password_issued).to exist
  end

  it "creates a member teacher in an explicitly selected planning SchoolYear" do
    school = create(:school)
    active_year = create(:school_year, :active, school: school, year: 2026)
    planning_year = create(:school_year, school: school, year: active_year.year + 1)
    teacher = build(:user, :teacher, login_id: " planning-teacher ", email: nil)

    result = described_class.call(
      teacher: teacher,
      attributes: {},
      school: school,
      school_year: planning_year,
      membership_grade: 5,
      classroom_id: nil,
      actor: actor
    )

    expect(result).to be_success
    expect(teacher).to have_attributes(
      school_year: planning_year,
      login_id: "planning-teacher",
      school_role: "member",
      grade: 5,
      password_change_required: true
    )
    expect(result.temporary_password).to be_present
    expect(teacher.teacher_credential_events.temporary_password_issued).to exist
  end

  it "rejects an explicit archived or cross-school SchoolYear" do
    school = create(:school)
    create(:school_year, :active, school: school, year: 2026)
    archived_year = create(:school_year, :archived, school: school, year: 2025)
    other_school = create(:school)
    other_planning_year = create(:school_year, school: other_school, year: 2027)

    [archived_year, other_planning_year].each_with_index do |school_year, index|
      teacher = build(:user, :teacher, login_id: "invalid-context-#{index}")
      result = described_class.call(
        teacher: teacher,
        attributes: {},
        school: school,
        school_year: school_year,
        membership_grade: 5,
        classroom_id: nil,
        actor: actor
      )

      expect(result).not_to be_success
      expect(teacher).not_to be_persisted
    end
  end

  it "updates profile attributes while preserving the annual login ID" do
    school = create(:school)
    teacher = annual_teacher(school: school, grade: nil, name: "변경 전")
    login_id = teacher.login_id

    result = save(teacher: teacher, school: school, grade: nil, attributes: { name: "변경 후" })

    expect(result).to be_success
    expect(teacher.reload).to have_attributes(name: "변경 후", login_id: login_id)
  end

  it "preserves an inactive classroom assignment during a profile update" do
    school = create(:school)
    teacher = annual_teacher(school: school, grade: 4)
    classroom = create(:classroom, annual_school: school, grade: 4, teacher: teacher)
    classroom.update!(active: false)

    result = save(teacher: teacher, school: school, grade: 4,
      classroom: classroom, attributes: { name: "변경 후" })

    expect(result).to be_success
    expect(teacher.reload.name).to eq("변경 후")
    expect(classroom.reload.teacher).to eq(teacher)
  end

  it "rejects changing, removing, or moving an inactive classroom assignment" do
    school = create(:school)
    teacher = annual_teacher(school: school, grade: 4)
    classroom = create(:classroom, annual_school: school, grade: 4, teacher: teacher)
    destination = create(:classroom, annual_school: school, grade: 4)
    classroom.update!(active: false)

    expect(save(teacher: teacher, school: school, grade: 5, classroom: classroom)).not_to be_success
    expect(teacher.reload.grade).to eq(4)
    teacher.errors.clear
    expect(save(teacher: teacher, school: school, grade: 4)).not_to be_success
    teacher.errors.clear
    expect(save(teacher: teacher, school: school, grade: 4, classroom: destination)).not_to be_success
    expect(classroom.reload.teacher).to eq(teacher)
    expect(destination.reload.teacher).to be_nil
  end

  it "assigns, moves, and removes one matching active classroom" do
    school = create(:school)
    teacher = annual_teacher(school: school, grade: 5)
    first = create(:classroom, annual_school: school, grade: 5)
    second = create(:classroom, annual_school: school, grade: 5)

    expect(save(teacher: teacher, school: school, grade: 5, classroom: first)).to be_success
    expect(first.reload.teacher).to eq(teacher)
    first_assignment = first.current_homeroom_assignment
    expect(save(teacher: teacher, school: school, grade: 5, classroom: second)).to be_success
    expect(first.reload.teacher).to be_nil
    expect(first_assignment.reload.ended_on).to eq(Date.current)
    expect(second.reload.teacher).to eq(teacher)
    second_assignment = second.current_homeroom_assignment
    expect(save(teacher: teacher, school: school, grade: 5)).to be_success
    expect(second.reload.teacher).to be_nil
    expect(second_assignment.reload.ended_on).to eq(Date.current)
    expect(teacher.homeroom_assignments.count).to eq(2)
  end

  it "assigns, replaces, and removes a planning classroom without history" do
    school = create(:school)
    active_year = create(:school_year, :active, school: school, year: 2026)
    planning_year = create(:school_year, school: school, year: active_year.year + 1)
    teacher = create(:user, :teacher, school_year: planning_year,
      login_id: "planning-assignment", school_role: "member", grade: 5)
    first = create(:classroom, school_year: planning_year, grade: 5)
    second = create(:classroom, school_year: planning_year, grade: 5)

    save_planning = lambda do |classroom|
      described_class.call(
        teacher: teacher,
        attributes: {},
        school: school,
        school_year: planning_year,
        membership_grade: 5,
        classroom_id: classroom&.id,
        actor: actor
      )
    end

    expect(save_planning.call(first)).to be_success
    first_assignment = first.current_homeroom_assignment
    expect(first_assignment.started_on).to eq(Date.new(2027, 3, 1))

    expect(save_planning.call(second)).to be_success
    expect(HomeroomAssignment.exists?(first_assignment.id)).to eq(false)
    second_assignment = second.reload.current_homeroom_assignment
    expect(second_assignment).to have_attributes(
      teacher: teacher,
      started_on: Date.new(2027, 3, 1),
      ended_on: nil
    )

    expect(save_planning.call(nil)).to be_success
    expect(HomeroomAssignment.exists?(second_assignment.id)).to eq(false)
    expect(teacher.reload.assigned_classroom).to be_nil
  end

  it "rejects invalid planning classroom candidates" do
    school = create(:school)
    active_year = create(:school_year, :active, school: school, year: 2026)
    planning_year = create(:school_year, school: school, year: active_year.year + 1)
    teacher = create(:user, :teacher, school_year: planning_year,
      login_id: "planning-candidate", school_role: "member", grade: 5)
    occupied_teacher = create(:user, :teacher, school_year: planning_year,
      login_id: "planning-occupied", school_role: "member", grade: 5)
    invalid_classrooms = [
      create(:classroom, school_year: active_year, grade: 5),
      create(:classroom, school_year: planning_year, grade: 4),
      create(:classroom, school_year: planning_year, grade: 5, active: false),
      create(:classroom, school_year: planning_year, grade: 5, teacher: occupied_teacher)
    ]

    invalid_classrooms.each do |classroom|
      result = described_class.call(
        teacher: teacher,
        attributes: {},
        school: school,
        school_year: planning_year,
        membership_grade: 5,
        classroom_id: classroom.id,
        actor: actor
      )

      expect(result).not_to be_success
      expect(teacher.reload.assigned_classroom).to be_nil
      teacher.errors.clear
    end
  end

  it "is idempotent when the selected classroom is unchanged" do
    school = create(:school)
    teacher = annual_teacher(school: school, grade: 5)
    classroom = create(:classroom, annual_school: school, grade: 5, teacher: teacher)

    expect do
      expect(save(teacher: teacher, school: school, grade: 5, classroom: classroom)).to be_success
    end.not_to change(HomeroomAssignment, :count)
  end

  it "rejects mismatched, inactive, occupied, and nonexistent classrooms" do
    school = create(:school)
    teacher = annual_teacher(school: school, grade: 5)
    other_teacher = annual_teacher(school: school, grade: 5)
    invalid_classrooms = [
      create(:classroom, grade: 5),
      create(:classroom, annual_school: school, grade: 6),
      create(:classroom, annual_school: school, grade: 5, active: false),
      create(:classroom, annual_school: school, grade: 5, teacher: other_teacher)
    ]

    invalid_classrooms.each do |classroom|
      expect(save(teacher: teacher, school: school, grade: 5, classroom: classroom)).not_to be_success
      expect(teacher.assigned_classroom).to be_nil
      teacher.errors.clear
    end

    missing = described_class.call(teacher: teacher, attributes: {}, school: school,
      membership_grade: 5, classroom_id: Classroom.maximum(:id).to_i + 10_000, actor: actor)
    expect(missing).not_to be_success
  end

  it "rejects a non-teacher, inactive teacher, and inactive school" do
    expect(save(teacher: create(:user, :admin), school: create(:school), grade: 4)).not_to be_success

    school = create(:school)
    teacher = annual_teacher(school: school, grade: 4)
    teacher.update!(active: false)
    classroom = create(:classroom, annual_school: school, grade: 4)
    expect(save(teacher: teacher, school: school, grade: 4, classroom: classroom)).not_to be_success

    inactive_school = create(:school, active: false)
    expect(save(teacher: build(:user, :teacher, login_id: "new-teacher"),
      school: inactive_school, grade: 4)).not_to be_success
  end

  it "preserves an annual manager role in the same school" do
    school = create(:school)
    teacher = annual_teacher(school: school, grade: 4, school_role: "manager")

    expect(save(teacher: teacher, school: school, grade: 4)).to be_success
    expect(teacher.reload.school_role).to eq("manager")
  end

  it "rejects moving an existing annual teacher to another school" do
    school = create(:school)
    teacher = annual_teacher(school: school, grade: 4, school_role: "manager", name: "변경 전")
    current_classroom = create(:classroom, annual_school: school, grade: 4, teacher: teacher)
    destination_school = create(:school)
    destination_classroom = create(:classroom, annual_school: destination_school, grade: 5)

    result = save(teacher: teacher, school: destination_school, grade: 5,
      classroom: destination_classroom, attributes: { name: "변경 후" })

    expect(result).not_to be_success
    expect(teacher.reload).to have_attributes(school_year: school.school_years.active.first,
      school_role: "manager", grade: 4, name: "변경 전")
    expect(current_classroom.reload.teacher).to eq(teacher)
    expect(destination_classroom.reload.teacher).to be_nil
  end

  it "rejects detaching an annual teacher when school is nil" do
    school = create(:school)
    teacher = annual_teacher(school: school, grade: 4)
    classroom = create(:classroom, annual_school: school, grade: 4, teacher: teacher)

    expect(save(teacher: teacher, school: nil, grade: nil)).not_to be_success
    expect(teacher.reload).to have_attributes(school_year: school.school_years.active.first, grade: 4)
    expect(classroom.reload.teacher).to eq(teacher)
  end

  it "rolls back profile, grade, and assignment changes on failure" do
    school = create(:school)
    teacher = annual_teacher(school: school, grade: 5)
    classroom = create(:classroom, annual_school: school, grade: 5, teacher: teacher)

    result = save(teacher: teacher, school: school, grade: 4, attributes: { name: "" })

    expect(result).not_to be_success
    expect(teacher.reload.grade).to eq(5)
    expect(classroom.reload.teacher).to eq(teacher)
  end
end
