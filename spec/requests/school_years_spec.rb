require 'rails_helper'

RSpec.describe 'Planning SchoolYears', type: :request do
  let(:school) { create(:school, name: '아라초등학교') }
  let!(:active_year) { create(:school_year, :active, school: school, year: 2026) }
  let(:admin) { create(:user, :admin) }
  let(:manager) do
    create(:user, :teacher, :active_annual_teacher,
           annual_school: school, annual_school_role: 'manager')
  end

  it 'lets a global admin create the server-resolved next year from the school overview' do
    sign_in admin

    get school_path(school)
    expect(response.body).to include('2027학년도 준비 시작')
    expect(response.body).not_to include('type="number"')

    post school_school_years_path(school), params: { school_year: { year: 2035 } }

    planning_year = school.school_years.planning.sole
    expect(planning_year.year).to eq(2027)
    expect(response).to redirect_to(school_path(school))
    follow_redirect!
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('2027학년도 준비 중')
    expect(response.body).not_to include('2027학년도 준비 시작')
  end

  it 'lets a current manager create planning context only for their own school' do
    other_school = create(:school)
    create(:school_year, :active, school: other_school, year: 2026)
    sign_in manager

    post school_school_years_path(school)
    expect(response).to redirect_to(school_path(school))
    expect(school.school_years.planning.sole.year).to eq(2027)

    post school_school_years_path(other_school)
    expect(response).to have_http_status(:not_found)
    expect(other_school.school_years.planning).to be_empty
  end

  it 'rejects an ordinary teacher' do
    member = create(:user, :teacher, :active_annual_teacher, annual_school: school)
    sign_in member

    post school_school_years_path(school)

    expect(response).to redirect_to(root_path)
    expect(school.school_years.planning).to be_empty
  end

  it 'rejects a school without an active year' do
    school_without_active_year = create(:school)
    sign_in admin

    post school_school_years_path(school_without_active_year)
    expect(response).to redirect_to(school_path(school_without_active_year))
    expect(school_without_active_year.school_years.planning).to be_empty
  end

  it 'rejects an inactive school' do
    sign_in admin
    school.update!(active: false)

    post school_school_years_path(school)
    expect(response).to redirect_to(root_path)
    expect(school.school_years.planning).to be_empty
    expect(active_year.reload).to be_active
  end

  it 'keeps the existing planning year when duplicate creation is attempted' do
    existing = create(:school_year, school: school, year: 2027)
    sign_in admin
    post school_school_years_path(school)

    expect(response).to redirect_to(school_path(school))
    expect(school.school_years.planning).to contain_exactly(existing)
    expect(active_year.reload).to be_active
  end

  it 'shows the existing planning status instead of another creation action' do
    create(:school_year, school: school, year: 2027)
    sign_in admin

    get school_path(school)

    expect(response.body).to include('2027학년도 준비 중')
    expect(response.body).not_to include('2027학년도 준비 시작')
  end
end
