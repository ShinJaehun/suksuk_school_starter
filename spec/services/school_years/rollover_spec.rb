require 'rails_helper'

RSpec.describe SchoolYears::Rollover do
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
