require 'rails_helper'

RSpec.describe TeacherManagementPolicy do
  let(:school) { create(:school) }
  let(:manager) do
    create(:user, :teacher, :active_annual_teacher,
           annual_school: school,
           annual_school_role: 'manager')
  end
  let(:member) { create(:user, :teacher, :active_annual_teacher, annual_school: school) }
  let(:outside_teacher) do
    create(:user, :teacher, :active_annual_teacher, annual_school: create(:school))
  end

  it 'allows admins and managers to access and create' do
    admin = create(:user, :admin)

    expect(described_class.new(admin, User).index?).to eq(true)
    expect(described_class.new(admin, User).access?).to eq(true)
    expect(described_class.new(admin, User.new(role: :teacher)).create?).to eq(true)
    expect(described_class.new(manager, User).access?).to eq(true)
    expect(described_class.new(manager, User.new(role: :teacher)).create?).to eq(true)
  end

  it 'does not allow a current ordinary teacher to read the teacher index' do
    expect(described_class.new(member, User).index?).to eq(false)
    expect(described_class.new(member, User).access?).to eq(false)
    expect(described_class.new(member, User.new(role: :teacher)).create?).to eq(false)
  end

  it 'limits manager profile management and scope to their school' do
    expect(described_class.new(manager, member).update_profile?).to eq(true)
    expect(described_class.new(manager, manager).update_profile?).to eq(true)
    expect(described_class.new(manager, outside_teacher).update_profile?).to eq(false)
    expect(described_class::Scope.new(manager, User).resolve).to contain_exactly(manager, member)
  end

  it 'authorizes temporary password reissue by role and SchoolYear' do
    admin = create(:user, :admin)
    other_manager = create(:user, :teacher, :active_annual_teacher,
                           annual_school: create(:school), annual_school_role: 'manager')
    planning_year = create(:school_year, school: school, year: 2027, status: :planning)
    other_year_member = create(:user, :teacher, school_year: planning_year,
                                                school_role: 'member', login_id: 'next-year-member')

    expect(described_class.new(admin, member).reissue_temporary_password?).to eq(true)
    expect(described_class.new(admin, manager).reissue_temporary_password?).to eq(true)
    expect(described_class.new(manager, member).reissue_temporary_password?).to eq(true)
    expect(described_class.new(manager, manager).reissue_temporary_password?).to eq(false)
    expect(described_class.new(manager, other_manager).reissue_temporary_password?).to eq(false)
    expect(described_class.new(manager, other_year_member).reissue_temporary_password?).to eq(false)
    expect(described_class.new(manager, outside_teacher).reissue_temporary_password?).to eq(false)
  end

  it "limits the admin scope to teachers in each school's active SchoolYear" do
    admin = create(:user, :admin)
    active_teacher = member
    other_active_teacher = outside_teacher
    planning_year = create(:school_year, school: school, year: 2027, status: :planning)
    archived_year = create(:school_year, :archived, school: school, year: 2025)
    planning_teacher = create(:user, :teacher, school_year: planning_year, school_role: 'member',
                                               login_id: 'planning-teacher')
    archived_teacher = create(:user, :teacher, school_year: archived_year, school_role: 'member',
                                               login_id: 'archived-teacher')

    expect(described_class::Scope.new(admin, User).resolve).to contain_exactly(
      active_teacher,
      other_active_teacher
    )
  end

  it 'rejects manager roles outside the current operational context' do
    planning_manager = create(:user, :teacher,
                              school_year: create(:school_year, school: school, year: 2027),
                              login_id: 'planning-manager', school_role: 'manager')
    archived_school = create(:school)
    archived_manager = create(:user, :teacher,
                              school_year: create(:school_year, :archived, school: archived_school, year: 2025),
                              login_id: 'archived-manager', school_role: 'manager')
    inactive_manager = manager.tap { |user| user.update!(active: false) }

    [planning_manager, archived_manager, inactive_manager].each do |actor|
      expect(described_class.new(actor, User).index?).to eq(false)
      expect(described_class.new(actor, User).access?).to eq(false)
      expect(described_class::Scope.new(actor, User).resolve).to be_empty
    end
  end
end
