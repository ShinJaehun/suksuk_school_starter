require 'rails_helper'

RSpec.describe 'Teacher bulk management', type: :request do
  let(:school) { create(:school) }
  let(:active_year) { create(:school_year, :active, school: school, year: 2026) }
  let(:planning_year) { create(:school_year, school: school, year: 2027) }
  let(:current_manager) do
    create(:user, :teacher, school_year: active_year, school_role: 'manager',
                            login_id: 'current-bulk-manager', grade: 4)
  end
  let(:planning_manager) do
    create(:user, :teacher, school_year: planning_year, school_role: 'manager',
                            login_id: 'planning-bulk-manager', grade: 4)
  end

  def context(year)
    { school_id: school.id, school_year_id: year.id }
  end

  it 'keeps the existing individual management UI at /teachers' do
    teacher = create(:user, :teacher, school_year: active_year, school_role: 'member',
                                      login_id: 'individual-surface-teacher')
    sign_in current_manager

    get teachers_path

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    expect(document.at_css(%(a[href="#{edit_teacher_path(teacher, context(active_year))}"]))).to be_present
    expect(response.body).not_to include(bulk_update_admin_teachers_path, bulk_setup_admin_teachers_path)
  end

  it 'renders the source grade tabs and bulk controls at /admin/teachers' do
    sign_in current_manager

    get admin_teachers_path

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    expect(document.css('a').map(&:text)).to include('전체', '1학년', '2학년', '3학년', '4학년', '5학년', '6학년', '미배정')
    expect(document.at_css(%(a[href^="#{bulk_setup_admin_teachers_path}"]))).to be_present
    expect(document.at_css(%(form[action^="#{bulk_update_admin_teachers_path}"]))).to be_present
  end

  it 'keeps the current manager on the active SchoolYear by default' do
    active_year
    planning_year
    sign_in current_manager
    get admin_teachers_path

    expect(response).to have_http_status(:ok)
    expect(Nokogiri::HTML(response.body).at_css(
             %(select[name="school_year_id"] option[value="#{active_year.id}"][selected])
           )).to be_present
  end

  it 'keeps the planning manager on the planning SchoolYear by default' do
    active_year
    planning_year
    sign_in planning_manager
    get admin_teachers_path
    expect(response).to have_http_status(:ok)
    expect(Nokogiri::HTML(response.body).at_css(
             %(select[name="school_year_id"] option[value="#{planning_year.id}"][selected])
           )).to be_present
  end

  it 'lets both managers open active and planning bulk setup while preserving context' do
    [current_manager, planning_manager].each do |actor|
      sign_in actor
      [active_year, planning_year].each do |year|
        get bulk_setup_admin_teachers_path, params: context(year)
        expect(response).to have_http_status(:ok)
        document = Nokogiri::HTML(response.body)
        expect(document.at_css(%(input[name="school_id"][value="#{school.id}"]))).to be_present
        expect(document.at_css(%(input[name="school_year_id"][value="#{year.id}"]))).to be_present
      end
    end
  end

  it 'creates a batch and returns committed credentials with no-store' do
    sign_in current_manager

    expect do
      post bulk_create_admin_teachers_path, params: context(active_year).merge(
        grade: '4',
        teachers: { rows: { '0' => { name: '일괄 교사', login_id: 'bulk-request', grade: '4' } } }
      )
    end.to change { active_year.users.teacher.count }.by(1)
                                                     .and change(TeacherCredentialEvent, :count).by(1)

    expect(response).to have_http_status(:ok)
    expect(response.headers['Cache-Control']).to include('no-store')
    expect(response.body).to include('bulk-request', I18n.t('admin.teachers.bulk.credentials_warning'))
  end

  it 'lets current and planning managers create planning preparation Teachers' do
    classroom = create(:classroom, school_year: planning_year, grade: 4)

    [current_manager, planning_manager].each_with_index do |actor, index|
      sign_in actor
      expect do
        post bulk_create_admin_teachers_path, params: context(planning_year).merge(
          grade: '4',
          teachers: { rows: { '0' => {
            name: "준비 교사 #{index}", login_id: "planning-bulk-request-#{index}",
            grade: '4', classroom_id: index.zero? ? classroom.id : nil
          } } }
        )
      end.to change { planning_year.users.teacher.count }.by(1)
      expect(response).to have_http_status(:ok)
    end

    expect(classroom.reload.teacher.login_id).to eq('planning-bulk-request-0')
  end

  it 'does not render or authorize bulk mutation in archive context' do
    archived_year = create(:school_year, :archived, school: school, year: 2025)
    archived_teacher = create(:user, :teacher, school_year: archived_year,
                                               school_role: 'member', login_id: 'archived-bulk-teacher')
    sign_in current_manager

    get admin_teachers_path, params: context(archived_year)
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include(bulk_update_admin_teachers_path, bulk_setup_admin_teachers_path)

    sign_in current_manager
    patch bulk_update_admin_teachers_path, params: context(archived_year).merge(
      teachers: { rows: { '0' => { id: archived_teacher.id, name: '변경', login_id: archived_teacher.login_id } } }
    )
    expect(response).to have_http_status(:not_found)
  end

  it 'denies ordinary Teachers and fails closed for cross-School contexts and ids' do
    ordinary = create(:user, :teacher, school_year: active_year, school_role: 'member',
                                       login_id: 'ordinary-bulk-teacher')
    sign_in ordinary
    get bulk_setup_admin_teachers_path, params: context(active_year)
    expect(response).to redirect_to(root_path)

    other_school = create(:school)
    other_year = create(:school_year, :active, school: other_school)
    sign_in current_manager
    get bulk_setup_admin_teachers_path, params: { school_id: other_school.id, school_year_id: other_year.id }
    expect(response).to have_http_status(:not_found)

    sign_in current_manager
    patch bulk_update_admin_teachers_path, params: context(active_year).merge(
      teachers: { rows: { '0' => { id: ordinary.id, name: ordinary.name,
                                   login_id: ordinary.login_id, grade: ordinary.grade, classroom_id: create(
                                     :classroom, school_year: other_year, grade: 4
                                   ).id } } }
    )
    expect(response).to have_http_status(:unprocessable_content)
    expect(ordinary.reload.assigned_classroom).to be_nil
  end
end
