require 'rails_helper'

RSpec.describe Teachers::ManagementContext do
  def context(actor, schools_scope: School.all, **params)
    described_class.new(actor: actor, params: params, schools_scope: schools_scope)
  end

  def annual_manager(school:, school_year: nil)
    create(
      :user,
      :teacher,
      school_year: school_year || school.active_school_year,
      login_id: "manager-#{SecureRandom.hex(4)}",
      school_role: 'manager'
    )
  end

  it 'gives an admin all years for an explicitly selected School and defaults to its active year' do
    admin = create(:user, :admin)
    school = create(:school)
    active_year = create(:school_year, :active, school: school, year: 2026)
    planning_year = create(:school_year, school: school, year: 2027)
    archived_year = create(:school_year, :archived, school: school, year: 2025)
    management_context = context(admin, school_id: school.id)

    expect(management_context.school_years).to contain_exactly(active_year, planning_year, archived_year)
    expect(management_context.selected_school_year).to eq(active_year)
    expect(management_context).to be_mutable
    expect(management_context).to be_creatable
  end

  it "keeps the admin's unscoped index context empty and creatable" do
    management_context = context(create(:user, :admin))

    expect(management_context.selected_school).to be_nil
    expect(management_context.selected_school_year).to be_nil
    expect(management_context.context_params).to eq({})
    expect(management_context).to be_creatable
  end

  it 'lets a current manager select active, immediate planning, and archived years in its School' do
    school = create(:school)
    active_year = create(:school_year, :active, school: school, year: 2026)
    planning_year = create(:school_year, school: school, year: 2027)
    archived_year = create(:school_year, :archived, school: school, year: 2025)
    manager = annual_manager(school: school, school_year: active_year)

    expect(context(manager).selected_school_year).to eq(active_year)
    expect(context(manager).school_years).to contain_exactly(active_year, planning_year, archived_year)

    archived_context = context(manager, school_id: school.id, school_year_id: archived_year.id)
    expect(archived_context.selected_school_year).to eq(archived_year)
    expect(archived_context).to be_read_only
    expect(archived_context).not_to be_creatable
  end

  it 'limits a planning manager to its own planning year and uses it as the default' do
    school = create(:school)
    active_year = create(:school_year, :active, school: school, year: 2026)
    planning_year = create(:school_year, school: school, year: 2027)
    planning_manager = annual_manager(school: school, school_year: planning_year)
    management_context = context(planning_manager)

    expect(management_context.school_years).to contain_exactly(planning_year)
    expect(management_context.selected_school_year).to eq(planning_year)
    expect(management_context).to be_mutable
    expect(management_context).to be_creatable
    expect do
      context(planning_manager, school_year_id: active_year.id).selected_school_year
    end.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'resolves active and planning creation contexts but rejects archived creation' do
    admin = create(:user, :admin)
    school = create(:school)
    active_year = create(:school_year, :active, school: school, year: 2026)
    planning_year = create(:school_year, school: school, year: 2027)
    archived_year = create(:school_year, :archived, school: school, year: 2025)

    expect(context(admin, school_id: school.id).creation_school_year).to eq(active_year)
    expect(
      context(admin, school_id: school.id, school_year_id: planning_year.id).creation_school_year
    ).to eq(planning_year)
    expect do
      context(admin, school_id: school.id, school_year_id: archived_year.id).creation_school_year
    end.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'fails closed for malformed, unpaired, cross-School, and unauthorized School contexts' do
    admin = create(:user, :admin)
    school = create(:school)
    active_year = create(:school_year, :active, school: school)
    other_school = create(:school)
    manager = annual_manager(school: school, school_year: active_year)

    expect { context(admin, school_id: 'invalid').selected_school }.to raise_error(ActiveRecord::RecordNotFound)
    expect do
      context(admin, school_year_id: active_year.id).selected_school_year
    end.to raise_error(ActiveRecord::RecordNotFound)
    expect do
      context(admin, school_id: other_school.id, school_year_id: active_year.id).selected_school_year
    end.to raise_error(ActiveRecord::RecordNotFound)
    expect do
      context(manager, school_id: other_school.id).selected_school
    end.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'returns only identifiers when preserving context' do
    admin = create(:user, :admin)
    school = create(:school)
    school_year = create(:school_year, :active, school: school)
    management_context = context(admin, school_id: school.id, school_year_id: school_year.id)

    expect(management_context.context_params).to eq(
      school_id: school.id,
      school_year_id: school_year.id
    )
  end
end
