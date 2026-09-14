require 'rails_helper'

RSpec.describe SchoolYears::AutomaticRollover, type: :model do
  include ActiveSupport::Testing::TimeHelpers

  # Real commits are required to verify that a failed transition cannot erase
  # the claim and that competing connections observe the same consumed attempt.
  self.use_transactional_tests = false

  let!(:school) { create(:school) }
  let!(:active_year) { create(:school_year, :active, school: school, year: 2026) }
  let!(:planning_year) { create(:school_year, school: school, year: 2027) }
  let!(:manager) do
    create(:user, :teacher, school_year: planning_year, school_role: 'manager',
                            login_id: 'automatic-rollover-manager')
  end

  around { |example| travel_to(Time.zone.local(2027, 3, 1)) { example.run } }

  after do
    # Delete only records owned by this example's School, including archived rows.
    years = school.school_years.select(:id)
    classrooms = Classroom.where(school_year_id: years)
    teachers = User.where(school_year_id: years)
    HomeroomAssignment.where(classroom_id: classrooms.select(:id)).delete_all
    TeacherCredentialEvent.where(teacher_user_id: teachers.select(:id)).delete_all
    classrooms.delete_all
    teachers.delete_all
    SchoolYear.where(school_id: school.id).delete_all
    school.delete
  end

  def reconcile
    described_class.call(school: school, target_school_year_id: planning_year.id)
  end

  it 'does not consume the opportunity before March 1' do
    travel_to Time.zone.local(2027, 2, 28, 23, 59, 59)
    expect(SchoolYears::Rollover).not_to receive(:call)

    reconcile

    expect(active_year.reload).to be_active
    expect(planning_year.reload).to be_planning
    expect(planning_year.automatic_rollover_attempted_at).to be_nil
  end

  it 'uses the canonical transition on March 1 after durably committing the marker' do
    expect(SchoolYears::Rollover).to receive(:call).once.and_wrap_original do |method, **arguments|
      committed_marker = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          SchoolYear.find(planning_year.id).automatic_rollover_attempted_at
        end
      end.value
      expect(committed_marker).to eq(Time.current)
      method.call(**arguments)
    end

    result = reconcile

    expect(result.active_school_year).to eq(planning_year)
    expect(active_year.reload).to be_archived
    expect(planning_year.reload).to be_active
    expect(planning_year).not_to be_rollover_overdue
    expect(planning_year.automatic_rollover_attempted_at).to eq(Time.current)
    expect(manager.reload).to be_current_operational_manager
    expect(school.school_years.count).to eq(2)
  end

  it 'catches up on the first reconciliation after downtime' do
    travel_to Time.zone.local(2027, 4, 10)

    reconcile

    expect(active_year.reload).to be_archived
    expect(planning_year.reload).to be_active
    expect(planning_year.automatic_rollover_attempted_at).to eq(Time.current)
  end

  [
    { school_role: 'member' },
    { active: false },
    { encrypted_password: '' },
    { encrypted_password: 'invalid' }
  ].each do |blocker|
    it "preserves statuses, workspace and the consumed marker for #{blocker.inspect}" do
      manager.update_columns(blocker)
      classroom = create(:classroom, school_year: planning_year, grade: 3)
      original_manager = manager.reload.attributes
      original_classroom = classroom.attributes

      expect { reconcile }.not_to(change { [User.count, Classroom.count, HomeroomAssignment.count] })

      expect(active_year.reload).to be_active
      expect(planning_year.reload).to be_planning
      expect(planning_year).to be_rollover_overdue
      expect(planning_year.automatic_rollover_attempted_at).to eq(Time.current)
      expect(manager.reload.attributes).to eq(original_manager)
      expect(classroom.reload.attributes).to eq(original_classroom)
    end
  end

  it 'preserves the committed marker when the status transaction rolls back' do
    allow_any_instance_of(SchoolYear).to receive(:update!).and_wrap_original do |method, *args, **attributes|
      if method.receiver.id == planning_year.id && attributes[:status] == :active
        raise ActiveRecord::RecordInvalid, method.receiver
      end

      method.call(*args, **attributes)
    end

    reconcile

    expect(active_year.reload).to be_active
    expect(planning_year.reload).to be_planning
    expect(planning_year.automatic_rollover_attempted_at).to eq(Time.current)
    expect(SchoolYears::Rollover).not_to receive(:call)
    reconcile
  end

  it 'does not retry after failure or repair' do
    manager.update!(school_role: 'member')
    reconcile
    attempted_at = planning_year.reload.automatic_rollover_attempted_at
    expect(attempted_at).to be_present

    expect(SchoolYears::Rollover).not_to receive(:call)
    2.times { reconcile }
    manager.update!(school_role: 'manager')
    reconcile
    expect(planning_year.reload).to be_planning
    expect(planning_year.automatic_rollover_attempted_at).to eq(attempted_at)
  end

  it 'allows manual rollover after repairing a failed automatic attempt' do
    manager.update!(school_role: 'member')
    reconcile
    attempted_at = planning_year.reload.automatic_rollover_attempted_at
    manager.update!(school_role: 'manager')

    SchoolYears::Rollover.call(school: school, target_school_year_id: planning_year.id)

    expect(active_year.reload).to be_archived
    expect(planning_year.reload).to be_active
    expect(planning_year.automatic_rollover_attempted_at).to eq(attempted_at)
  end

  it 'consumes at most one opportunity across simultaneous reconciliation connections' do
    ready = Queue.new
    start = Queue.new
    expect(SchoolYears::Rollover).to receive(:call).once.and_call_original

    workers = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          separate_school = School.find(school.id)
          ready << true
          start.pop
          described_class.call(school: separate_school, target_school_year_id: planning_year.id)
        end
      end
    end
    2.times { ready.pop }
    2.times { start << true }
    workers.each(&:value)

    expect(active_year.reload).to be_archived
    expect(planning_year.reload).to be_active
    expect(planning_year.automatic_rollover_attempted_at).to be_present
  end

  it 'does not automatically enter a target already activated manually' do
    SchoolYears::Rollover.call(school: school, target_school_year_id: planning_year.id)
    expect(SchoolYears::Rollover).not_to receive(:call)

    reconcile

    expect(planning_year.reload.automatic_rollover_attempted_at).to be_nil
  end

  it 'preserves canonical structural validation for an inactive school' do
    school.update!(active: false)

    reconcile

    expect(active_year.reload).to be_active
    expect(planning_year.reload).to be_planning
    expect(planning_year.automatic_rollover_attempted_at).to be_present
  end

  it 'does not bypass the exact immediate year invariant even when the target is overdue' do
    active_year.update!(year: 2025)

    reconcile

    expect(active_year.reload).to be_active
    expect(planning_year.reload).to be_planning
    expect(planning_year.automatic_rollover_attempted_at).to be_present
  end

  it 'does not retry an uncertain attempt after an unexpected interruption' do
    allow(SchoolYears::Rollover).to receive(:call).and_raise('interrupted after claim')

    expect { reconcile }.to raise_error('interrupted after claim')

    expect(planning_year.reload.automatic_rollover_attempted_at).to be_present
    expect(SchoolYears::Rollover).not_to receive(:call)
    reconcile
    expect(active_year.reload).to be_active
    expect(planning_year.reload).to be_planning
  end

  it 'rejects an enclosing transaction that could roll back the claimed attempt' do
    School.transaction do
      expect { reconcile }.to raise_error(ArgumentError, /outside an existing transaction/)
    end

    expect(planning_year.reload.automatic_rollover_attempted_at).to be_nil
  end
end
