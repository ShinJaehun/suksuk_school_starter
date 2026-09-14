require 'rails_helper'

RSpec.describe SchoolYears::Rollover do
  include ActiveSupport::Testing::TimeHelpers

  around { |example| travel_to(Time.zone.local(2027, 2, 1)) { example.run } }

  let(:school) { create(:school) }
  let!(:active_year) { create(:school_year, :active, school: school, year: 2026) }
  let!(:planning_year) { create(:school_year, school: school, year: 2027) }
  let!(:planning_manager) do
    create(:user, :teacher, school_year: planning_year, school_role: 'manager',
      login_id: 'rollover-manager')
  end

  def rollover
    described_class.call(school: school, target_school_year_id: planning_year.id)
  end

  it 'rejects January 31 at the transition boundary without consuming an automatic attempt' do
    travel_to Time.zone.local(2027, 1, 31, 23, 59, 59)

    expect { rollover }.to raise_error(described_class::InvalidState) { |error|
      expect(error.key).to eq(:rollover_not_open)
    }
    expect(active_year.reload).to be_active
    expect(planning_year.reload).to be_planning
    expect(planning_year.automatic_rollover_attempted_at).to be_nil
  end

  it 'opens on February 1 without consuming an automatic attempt' do
    rollover

    expect(active_year.reload).to be_archived
    expect(planning_year.reload).to be_active
    expect(planning_year.automatic_rollover_attempted_at).to be_nil
  end

  it 'does not allow consecutive rollover into a future target year' do
    rollover
    next_year = create(:school_year, school: school, year: 2028)
    create(:user, :teacher, school_year: next_year, school_role: 'manager', login_id: 'future-manager')

    expect {
      described_class.call(school: school, target_school_year_id: next_year.id)
    }.to raise_error(described_class::InvalidState) { |error|
      expect(error.key).to eq(:rollover_not_open)
    }
    expect(planning_year.reload).to be_active
    expect(next_year.reload).to be_planning
  end

  [{ active: false }, { encrypted_password: '' }, { encrypted_password: 'invalid' }].each do |corruption|
    it "rejects #{corruption.inspect} without changing annual resources or credentials" do
      planning_manager.update_columns(corruption)
      original = planning_manager.reload.attributes

      expect do
        expect { rollover }.to raise_error(described_class::InvalidState) { |error|
          expect(error.key).to eq(:manager_credentials_invalid)
        }
      end.not_to change { [User.count, Classroom.count, HomeroomAssignment.count, TeacherCredentialEvent.count] }

      expect(active_year.reload).to be_active
      expect(planning_year.reload).to be_planning
      expect(planning_manager.reload.attributes).to eq(original)
    end
  end

  it 'rechecks the manager after acquiring the School and SchoolYear locks' do
    expect(SchoolYears::RolloverEligibility.new(school_year: planning_year)).to be_eligible
    allow(school).to receive(:lock!).and_wrap_original do |method, *args|
      method.call(*args)
      planning_manager.update_column(:encrypted_password, '')
    end

    expect { rollover }.to raise_error(described_class::InvalidState) { |error|
      expect(error.key).to eq(:manager_credentials_invalid)
    }
    expect(active_year.reload).to be_active
    expect(planning_year.reload).to be_planning
  end

  it 'rolls over a manager with temporary credentials and no classroom preparation' do
    planning_manager.update!(password_change_required: true, grade: nil, email: nil)
    digest = planning_manager.encrypted_password

    rollover

    expect(planning_year.reload).to be_active
    expect(planning_manager.reload).to have_attributes(password_change_required: true, encrypted_password: digest)
    expect(planning_year.classrooms).to be_empty
  end

  it 'atomically archives the current year and activates the explicit planning year' do
    result = rollover

    expect(active_year.reload).to be_archived
    expect(planning_year.reload).to be_active
    expect(result.active_school_year).to eq(planning_year)
    expect(result.archived_school_year).to eq(active_year)
    expect(school.school_years.active).to contain_exactly(planning_year)
    expect(school.school_years.planning).to be_empty
  end

  it 'preserves annual resources and the planning manager role' do
    classroom = create(:classroom, school_year: planning_year, grade: 3)
    planning_manager.update!(grade: classroom.grade)
    assignment = create(:homeroom_assignment, teacher: planning_manager, classroom: classroom,
      started_on: Date.new(planning_year.year, 3, 1))

    expect { rollover }.not_to change { [User.count, Classroom.count, HomeroomAssignment.count] }

    expect(planning_manager.reload).to be_school_manager
    expect(classroom.reload.school_year).to eq(planning_year)
    expect(assignment.reload).to be_current
  end

  it 'rejects a planning year without a manager' do
    planning_manager.update!(school_role: 'member')

    expect { rollover }.to raise_error(described_class::InvalidState) { |error|
      expect(error.key).to eq(:manager_missing)
    }

    expect(active_year.reload).to be_active
    expect(planning_year.reload).to be_planning
  end

  it 'rejects a non-consecutive planning year' do
    planning_year.update!(year: 2028)

    expect { rollover }.to raise_error(described_class::InvalidState) { |error|
      expect(error.key).to eq(:non_consecutive_year)
    }
  end

  it 'rejects rollover when the current active SchoolYear is missing' do
    active_year.update!(status: :archived)

    expect { rollover }.to raise_error(described_class::InvalidState) { |error|
      expect(error.key).to eq(:active_school_year_missing)
    }
  end

  it 'rolls back the archival when activating the target fails' do
    allow_any_instance_of(SchoolYear).to receive(:update!).and_wrap_original do |method, *args, **attributes|
      school_year = method.receiver
      raise ActiveRecord::RecordInvalid, school_year if school_year.id == planning_year.id

      method.call(*args, **attributes)
    end

    expect { rollover }.to raise_error(ActiveRecord::RecordInvalid)

    expect(active_year.reload).to be_active
    expect(planning_year.reload).to be_planning
  end
end
