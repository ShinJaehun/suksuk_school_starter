require 'rails_helper'

RSpec.describe Teachers::BulkCreator do
  let(:school) { create(:school) }
  let(:school_year) { create(:school_year, :active, school: school) }
  let(:actor) { create(:user, :admin) }

  def row(index, grade: 4, classroom: nil, **attributes)
    {
      name: "선생님 #{index}",
      login_id: "bulk-teacher-#{index}",
      grade: grade,
      classroom_id: classroom&.id
    }.merge(attributes)
  end

  it 'creates one member Teacher, assignment, credential, and audit event atomically' do
    classroom = create(:classroom, school_year: school_year, grade: 4)

    result = described_class.new(
      school_year: school_year,
      actor: actor,
      rows: [row(1, classroom: classroom, school_role: 'manager', role: 'admin')]
    ).call

    teacher = school_year.users.teacher.find_by!(login_id: 'bulk-teacher-1')
    expect(result).to be_success
    expect(teacher).to have_attributes(school_role: 'member', active: true, grade: 4)
    expect(teacher.assigned_classroom).to eq(classroom)
    expect(teacher.teacher_credential_events.temporary_password_issued).to exist
    expect(result.credentials.sole.fetch(:temporary_password)).to be_present
  end

  it 'accepts 30 rows and rejects 31 rows without a partial write' do
    accepted = described_class.new(
      school_year: school_year, actor: actor, rows: 30.times.map { |index| row(index) }
    ).call
    rejected = described_class.new(
      school_year: school_year, actor: actor, rows: 31.times.map { |index| row(index + 100) }
    ).call

    expect(accepted).to be_success
    expect(rejected).not_to be_success
    expect(school_year.users.teacher.count).to eq(30)
  end

  it 'rejects internal and existing normalized login ID duplicates' do
    create(:user, :teacher, school_year: school_year, school_role: 'member', login_id: 'existing')
    result = described_class.new(
      school_year: school_year,
      actor: actor,
      rows: [row(1, login_id: ' Same '), row(2, login_id: 'same'), row(3, login_id: 'EXISTING')]
    ).call

    expect(result).not_to be_success
    expect(school_year.users.teacher.count).to eq(1)
    expect(result.credentials).to be_empty
  end

  it 'rejects duplicate, occupied, wrong-grade, foreign-year, and foreign-School classrooms' do
    available = create(:classroom, school_year: school_year, grade: 4)
    occupied = create(:classroom, school_year: school_year, grade: 4, teacher: create(
      :user, :teacher, school_year: school_year, school_role: 'member', grade: 4, login_id: 'occupant'
    ))
    other_year = create(:school_year, :archived, school: school, year: school_year.year - 1)
    invalid_classrooms = [
      available,
      available,
      occupied,
      create(:classroom, school_year: school_year, grade: 5),
      create(:classroom, school_year: other_year, grade: 4),
      create(:classroom, school_year: create(:school_year, :active, school: create(:school)), grade: 4)
    ]
    rows = invalid_classrooms.each_with_index.map { |classroom, index| row(index, classroom: classroom) }

    expect do
      result = described_class.new(school_year: school_year, actor: actor, rows: rows).call
      expect(result).not_to be_success
    end.not_to(change { school_year.users.teacher.count })
  end

  it 'rolls back all Teachers, assignments, and credential events when one row is invalid' do
    classroom = create(:classroom, school_year: school_year, grade: 4)
    actor

    expect do
      result = described_class.new(
        school_year: school_year,
        actor: actor,
        rows: [row(1, classroom: classroom), row(2, grade: 9)]
      ).call
      expect(result).not_to be_success
      expect(result.credentials).to be_empty
    end.to change(User, :count).by(0)
                               .and change(HomeroomAssignment, :count).by(0)
                                                                      .and change(TeacherCredentialEvent, :count).by(0)
  end

  it 'rolls back an earlier credential event when a later credential creation fails' do
    calls = 0
    allow(AnnualTeacherUsers::TemporaryCredential).to receive(:call).and_wrap_original do |original, **arguments|
      calls += 1
      if calls == 1
        original.call(**arguments)
      else
        instance_double(
          AnnualTeacherUsers::TemporaryCredential::Result,
          success?: false,
          temporary_password: nil
        )
      end
    end

    expect do
      result = described_class.new(
        school_year: school_year, actor: actor, rows: [row(1), row(2)]
      ).call
      expect(result).not_to be_success
      expect(result.credentials).to be_empty
    end.to change { school_year.users.teacher.count }.by(0)
                                                     .and change(TeacherCredentialEvent, :count).by(0)
  end

  it 'creates planning Teachers and preparation assignments without Student data' do
    planning_year = create(:school_year, school: school, year: school_year.year + 1)
    classroom = create(:classroom, school_year: planning_year, grade: 4)

    expect do
      result = described_class.new(
        school_year: planning_year, actor: actor, rows: [row(1, classroom: classroom)]
      ).call
      expect(result).to be_success
      expect(result.entries.sole.user.current_homeroom_assignment.started_on).to eq(Date.new(planning_year.year, 3, 1))
    end.not_to change(Student, :count)
  end
end
