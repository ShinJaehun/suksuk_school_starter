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

  it 'allows creation in authorized active or planning contexts but not archived context' do
    admin = create(:user, :admin)
    active_year = manager.school_year
    planning_year = create(:school_year, school: school, year: active_year.year + 1)
    archived_year = create(:school_year, :archived, school: school, year: active_year.year - 1)

    [active_year, planning_year].each do |school_year|
      teacher = User.new(role: :teacher, school_year: school_year)
      expect(described_class.new(admin, teacher).create?).to eq(true)
      expect(described_class.new(manager, teacher).create?).to eq(true)
    end

    archived_teacher = User.new(role: :teacher, school_year: archived_year)
    expect(described_class.new(admin, archived_teacher).create?).to eq(false)
    expect(described_class.new(manager, archived_teacher).create?).to eq(false)
  end

  it 'rejects a manager creating in another school planning context' do
    other_school = create(:school)
    other_active_year = create(:school_year, :active, school: other_school)
    other_planning_year = create(:school_year, school: other_school, year: other_active_year.year + 1)
    teacher = User.new(role: :teacher, school_year: other_planning_year)

    expect(described_class.new(manager, teacher).create?).to eq(false)
  end

  it 'limits manager profile management and scope to their school' do
    expect(described_class.new(manager, member).update_profile?).to eq(true)
    expect(described_class.new(manager, manager).update_profile?).to eq(true)
    expect(described_class.new(manager, outside_teacher).update_profile?).to eq(false)
    expect(described_class::Scope.new(manager, User).resolve).to contain_exactly(manager, member)
  end

  it 'allows planning Teacher settings only in an authorized next-year context' do
    admin = create(:user, :admin)
    planning_year = create(:school_year, school: school, year: manager.school_year.year + 1)
    planning_member = create(:user, :teacher, school_year: planning_year,
                                              school_role: 'member', login_id: 'planning-member')
    planning_manager = create(:user, :teacher, school_year: planning_year,
                                               school_role: 'manager', login_id: 'planning-manager')

    expect(described_class.new(admin, planning_member).update_profile?).to eq(true)
    expect(described_class.new(manager, planning_member).update_profile?).to eq(true)
    expect(described_class.new(manager, planning_manager).update_profile?).to eq(true)
    expect(described_class.new(planning_manager, planning_member).update_profile?).to eq(true)
    expect(described_class.new(planning_manager, member).update_profile?).to eq(true)
    expect(
      described_class.new(planning_manager, User.new(role: :teacher, school_year: manager.school_year)).create?
    ).to eq(true)
    expect(described_class.new(member, planning_member).update_profile?).to eq(false)
  end

  it 'authorizes temporary password reissue by role and SchoolYear' do
    admin = create(:user, :admin)
    other_manager = create(:user, :teacher, :active_annual_teacher,
                           annual_school: create(:school), annual_school_role: 'manager')
    planning_year = create(:school_year, school: school, year: 2027, status: :planning)
    planning_member = create(:user, :teacher, school_year: planning_year,
                                              school_role: 'member', login_id: 'next-year-member')
    planning_manager = create(:user, :teacher, school_year: planning_year,
                                               school_role: 'manager', login_id: 'next-year-manager')
    inactive_planning_member = create(:user, :teacher, school_year: planning_year,
                                                       school_role: 'member', active: false,
                                                       login_id: 'inactive-next-year-member')
    archived_year = create(:school_year, :archived, school: school, year: 2025)
    archived_member = create(:user, :teacher, school_year: archived_year,
                                              school_role: 'member', login_id: 'archived-member')

    expect(described_class.new(admin, member).reissue_temporary_password?).to eq(true)
    expect(described_class.new(admin, manager).reissue_temporary_password?).to eq(true)
    expect(described_class.new(admin, inactive_planning_member).reissue_temporary_password?).to eq(false)
    expect(described_class.new(admin, archived_member).reissue_temporary_password?).to eq(false)
    expect(described_class.new(manager, member).reissue_temporary_password?).to eq(true)
    expect(described_class.new(manager, manager).reissue_temporary_password?).to eq(false)
    expect(described_class.new(manager, planning_member).reissue_temporary_password?).to eq(true)
    expect(described_class.new(manager, planning_manager).reissue_temporary_password?).to eq(true)
    expect(described_class.new(manager, inactive_planning_member).reissue_temporary_password?).to eq(false)
    expect(described_class.new(planning_manager, planning_member).reissue_temporary_password?).to eq(true)
    expect(described_class.new(planning_manager, planning_manager).reissue_temporary_password?).to eq(false)
    expect(described_class.new(planning_manager, member).reissue_temporary_password?).to eq(true)
    expect(described_class.new(manager, other_manager).reissue_temporary_password?).to eq(false)
    expect(described_class.new(manager, outside_teacher).reissue_temporary_password?).to eq(false)
  end

  it 'allows planning Teacher hard delete without widening active or archived deletion' do
    admin = create(:user, :admin)
    planning_year = create(:school_year, school: school, year: manager.school_year.year + 1)
    archived_year = create(:school_year, :archived, school: school, year: manager.school_year.year - 1)
    planning_member = create(:user, :teacher, school_year: planning_year,
                                              school_role: 'member', login_id: 'delete-member')
    planning_manager = create(:user, :teacher, school_year: planning_year,
                                               school_role: 'manager', login_id: 'delete-manager')
    archived_teacher = create(:user, :teacher, school_year: archived_year,
                                               school_role: 'member', login_id: 'delete-archived')

    expect(described_class.new(admin, planning_member).destroy?).to eq(true)
    expect(described_class.new(manager, planning_member).destroy?).to eq(true)
    expect(described_class.new(admin, planning_manager).destroy?).to eq(true)
    expect(described_class.new(manager, planning_manager).destroy?).to eq(false)
    expect(described_class.new(manager, member).destroy?).to eq(false)
    expect(described_class.new(admin, archived_teacher).destroy?).to eq(false)
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

  it 'allows an eligible active planning manager to use its active and planning Teacher scope' do
    active_year = manager.school_year
    planning_manager = create(
      :user,
      :teacher,
      school_year: create(
        :school_year,
        school: school,
        year: active_year.year + 1
      ),
      login_id: 'planning-manager',
      school_role: 'manager'
    )

    expect(described_class.new(planning_manager, User).index?).to eq(true)
    expect(described_class.new(planning_manager, User).access?).to eq(true)
    other_school_teacher = outside_teacher
    scope = described_class::Scope.new(planning_manager, User).resolve
    expect(scope).to contain_exactly(
      manager,
      member,
      planning_manager
    )
    expect(scope).not_to include(other_school_teacher)
  end

  it 'rejects inactive and archived manager actors' do
    archived_school = create(:school)
    archived_manager = create(:user, :teacher,
                              school_year: create(:school_year, :archived, school: archived_school, year: 2025),
                              login_id: 'archived-manager', school_role: 'manager')
    inactive_manager = manager.tap { |user| user.update!(active: false) }

    [archived_manager, inactive_manager].each do |actor|
      expect(described_class.new(actor, User).index?).to eq(false)
      expect(described_class.new(actor, User).access?).to eq(false)
      expect(described_class::Scope.new(actor, User).resolve).to be_empty
    end
  end
end
