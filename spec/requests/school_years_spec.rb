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

    get school_path(school)
    document = Nokogiri::HTML(response.body)
    expect(response.body).to include(I18n.t('school_years.planning.start', year: 2027))
    expect(document.at_css(%(form[action="#{school_school_years_path(school)}"]))).to be_present

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

  it 'shows planning preparation counts and future entry labels on the school overview' do
    planning_year = create(:school_year, school: school, year: 2027)
    assigned_teacher = create(:user, :teacher, school_year: planning_year,
                                               login_id: 'assigned-teacher', school_role: 'member', grade: 4)
    create(:user, :teacher, school_year: planning_year,
                            login_id: 'unassigned-teacher', school_role: 'member', grade: 5)
    create(:user, :teacher, school_year: planning_year,
                            login_id: 'inactive-teacher', school_role: 'member', grade: 6, active: false)
    assigned_classroom = create(:classroom, school_year: planning_year, grade: 4)
    create(:classroom, school_year: planning_year, grade: 5)
    create(:classroom, school_year: planning_year, grade: 6, active: false)
    create(:homeroom_assignment,
           teacher: assigned_teacher,
           classroom: assigned_classroom,
           started_on: Date.new(2027, 3, 1))
    sign_in admin

    get school_path(school)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('선생님 준비', '2명')
    expect(response.body).to include('교실 준비', '2개')
    expect(response.body).to include('담임 연결', '1 / 2')
    document = Nokogiri::HTML(response.body)
    expect(
      document.at_css(
        %(a[href="#{teachers_path(school_id: school.id, school_year_id: planning_year.id)}"])
      )
    ).to be_present
    expect(
      document.at_css(
        %(a[href="#{classrooms_path(school_id: school.id, school_year_id: planning_year.id)}"])
      )
    ).to be_present
  end

  it 'shows planning preparation only to an authorized planning operator' do
    create(:school_year, school: school, year: 2027)
    other_school = create(:school)
    create(:school_year, :active, school: other_school, year: 2026)
    other_manager = create(:user, :teacher, :active_annual_teacher,
                           annual_school: other_school, annual_school_role: 'manager')

    sign_in manager
    get school_path(school)
    expect(response.body).to include('선생님 준비', '교실 준비', '담임 연결')

    sign_in other_manager
    get school_path(school)
    expect(response).to have_http_status(:not_found)

    sign_in create(:user, :teacher, :active_annual_teacher, annual_school: school)
    get school_path(school)
    expect(response.body).not_to include('선생님 준비', '교실 준비', '담임 연결')
  end
end
