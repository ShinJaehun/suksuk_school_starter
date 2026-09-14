require 'rails_helper'

RSpec.describe SchoolYears::CancelPlanning do
  let(:school) { create(:school) }
  let!(:active_year) { create(:school_year, :active, school:, year: 2026) }
  let!(:planning_year) { create(:school_year, school:, year: 2027) }
  let!(:admin) { create(:user, :admin) }
  let!(:current_manager) do
    create(:user, :teacher, school_year: active_year, school_role: 'manager', login_id: 'current-manager')
  end
  let!(:active_teacher) do
    create(:user, :teacher, school_year: active_year, school_role: 'member', login_id: 'active-member')
  end
  let!(:active_classroom) { create(:classroom, school_year: active_year) }
  let!(:active_student) { create(:student, classroom: active_classroom) }
  let!(:planning_manager) do
    create(:user, :teacher, school_year: planning_year, school_role: 'manager', login_id: 'planning-manager')
  end
  let!(:planning_teacher) do
    create(:user, :teacher, school_year: planning_year, school_role: 'member', login_id: 'planning-member')
  end
  let!(:planning_classroom) { create(:classroom, school_year: planning_year, grade: 3) }
  let!(:planning_assignment) do
    planning_teacher.update!(grade: planning_classroom.grade)
    create(:homeroom_assignment, teacher: planning_teacher, classroom: planning_classroom,
                                 started_on: Date.new(planning_year.year, 3, 1))
  end
  let!(:planning_event) do
    TeacherCredentialEvent.create!(actor_user: planning_manager, teacher_user: planning_teacher,
                                   action: :temporary_password_reissued)
  end
  let!(:current_manager_planning_event) do
    TeacherCredentialEvent.create!(actor_user: current_manager, teacher_user: planning_teacher,
                                   action: :temporary_password_reissued)
  end
  let!(:active_event) do
    TeacherCredentialEvent.create!(actor_user: current_manager, teacher_user: active_teacher,
                                   action: :temporary_password_reissued)
  end

  def cancel(actor: admin, target_id: planning_year.id, confirmation_year: planning_year.year.to_s)
    described_class.call(actor:, school:, target_school_year_id: target_id, confirmation_year:)
  end

  it 'discards the whole planning workspace and preserves active data' do
    planning_teacher
    planning_assignment
    planning_event
    current_manager_planning_event
    active_event

    expect { cancel }.to change(SchoolYear, :count).by(-1)
                                                   .and change(User, :count).by(-2)
                                                                            .and change(Classroom, :count).by(-1)
                                                                                                          .and change(
                                                                                                            HomeroomAssignment, :count
                                                                                                          ).by(-1)
      .and change(
        TeacherCredentialEvent, :count
      ).by(-2)

    expect(school.school_years.planning).to be_empty
    expect([active_year, current_manager, active_teacher, active_classroom, active_student, active_event])
      .to all(satisfy { |record| record.class.exists?(record.id) })
  end

  it 'fails closed when a planning Teacher issued an external credential event' do
    external_event = TeacherCredentialEvent.create!(actor_user: planning_manager, teacher_user: active_teacher,
                                                    action: :temporary_password_reissued)

    expect { cancel }.to raise_error(described_class::InvalidState) { |error|
      expect(error.key).to eq(:external_credential_event)
    }
    expect([planning_year, planning_manager, planning_teacher, planning_classroom, external_event])
      .to all(satisfy { |record| record.class.exists?(record.id) })
  end

  it 'fails closed when a planning Classroom contains a Student' do
    student = create(:student, classroom: planning_classroom)

    expect { cancel }.to raise_error(described_class::InvalidState) { |error|
      expect(error.key).to eq(:students_present)
    }
    expect(Student.exists?(student.id)).to eq(true)
    expect(planning_year.reload).to be_planning
  end

  it 'rejects a wrong confirmation, unauthorized actor, and arbitrary target' do
    expect { cancel(confirmation_year: '2026') }.to raise_error(described_class::InvalidState)
    expect { cancel(actor: current_manager) }.to raise_error(Pundit::NotAuthorizedError)
    expect { cancel(target_id: active_year.id) }.to raise_error(described_class::InvalidState)
    expect(planning_year.reload).to be_planning
  end

  it 'rolls back when a workspace record cannot be destroyed' do
    planning_assignment
    allow_any_instance_of(Classroom).to receive(:destroy!) do |classroom|
      raise ActiveRecord::RecordNotDestroyed.new('failed', classroom) if classroom.id == planning_classroom.id
    end

    expect { cancel }.to raise_error(ActiveRecord::RecordNotDestroyed)
    expect(planning_year.reload).to be_planning
    expect(User.exists?(planning_teacher.id)).to eq(true)
    expect(Classroom.exists?(planning_classroom.id)).to eq(true)
    expect(HomeroomAssignment.exists?(planning_assignment.id)).to eq(true)
  end
end
