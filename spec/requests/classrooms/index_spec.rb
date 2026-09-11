require 'rails_helper'

RSpec.describe 'Classrooms index entry', type: :request do
  it 'redirects an ordinary teacher to their active assigned classroom' do
    school = create(:school)
    teacher = create(:user, :teacher, :active_annual_teacher, annual_school: school, annual_grade: 4)
    classroom = create(:classroom, annual_school: school, grade: 4)
    assign_teacher(classroom, teacher)
    sign_in teacher

    get classrooms_path

    expect(response).to redirect_to(classroom_path(classroom))
  end

  it 'shows the empty index for an ordinary teacher without an assignment' do
    school = create(:school)
    teacher = create(:user, :teacher, :active_annual_teacher, annual_school: school)
    sign_in teacher

    get classrooms_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t('classrooms.index.empty'))
  end

  it 'does not redirect an ordinary teacher to an inactive assigned classroom' do
    school = create(:school)
    teacher = create(:user, :teacher, :active_annual_teacher, annual_school: school, annual_grade: 4)
    classroom = create(:classroom, annual_school: school, grade: 4, teacher: teacher)
    classroom.update!(active: false)
    sign_in teacher

    get classrooms_path

    expect(response).to have_http_status(:ok)
    expect(response).not_to redirect_to(classroom_path(classroom))
  end

  it 'expires an ordinary teacher session when their school becomes inactive' do
    school = create(:school)
    teacher = create(:user, :teacher, :active_annual_teacher, annual_school: school, annual_grade: 4)
    classroom = create(:classroom, annual_school: school, grade: 4, teacher: teacher)
    sign_in teacher
    school.update!(active: false)

    get classrooms_path

    expect(response).to redirect_to(school_teacher_login_path(school))
  end

  it 'keeps the classrooms index for a school manager' do
    school = create(:school)
    manager = create(:user, :teacher, :active_annual_teacher,
                     annual_school: school,
                     annual_school_role: 'manager',
                     annual_grade: 4)
    classroom = create(:classroom, annual_school: school, grade: 4, teacher: manager)
    sign_in manager

    get classrooms_path

    expect(response).to have_http_status(:ok)
    expect(response).not_to redirect_to(classroom_path(classroom))
  end

  it 'keeps the classrooms index for an admin' do
    classroom = create(:classroom)
    sign_in create(:user, :admin)

    get classrooms_path

    expect(response).to have_http_status(:ok)
    expect(response).not_to redirect_to(classroom_path(classroom))
  end

  it 'lets an admin explicitly read active, planning, and archived classroom contexts' do
    school = create(:school)
    active_year = create(:school_year, :active, school: school, year: 2026)
    planning_year = create(:school_year, school: school, year: 2027)
    archived_year = create(:school_year, :archived, school: school, year: 2025)
    active_classroom = create(:classroom, school_year: active_year, class_label: '현재고유교실')
    planning_classroom = create(:classroom, school_year: planning_year, class_label: '준비고유교실')
    archived_classroom = create(:classroom, school_year: archived_year, class_label: '지난고유교실')
    sign_in create(:user, :admin)

    get classrooms_path, params: { school_id: school.id, school_year_id: active_year.id }
    expect(response.body).to include(active_classroom.class_label)
    expect(response.body).not_to include(planning_classroom.class_label, archived_classroom.class_label)
    expect(response.body).to include(I18n.t('ui.buttons.new_classroom'))

    [
      [planning_year, planning_classroom],
      [archived_year, archived_classroom]
    ].each do |school_year, classroom|
      get classrooms_path, params: { school_id: school.id, school_year_id: school_year.id }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(classroom.class_label)
      expect(response.body).to include(I18n.t('classrooms.index.context_read_only'))
      expect(response.body).not_to include(I18n.t('ui.buttons.new_classroom'))
      expect(response.body).not_to include(classroom_path(classroom))
      expect(response.body).not_to include(edit_classroom_path(classroom))
      expect(response.body).not_to include(classroom_members_path(classroom))
    end
  end

  it 'lets a current manager read only their active and immediately following planning contexts' do
    school = create(:school)
    manager = create(:user, :teacher, :active_annual_teacher,
                     annual_school: school,
                     annual_school_role: 'manager')
    active_year = manager.school_year
    active_classroom = create(:classroom, school_year: active_year, class_label: '현재')
    planning_year = create(:school_year, school: school, year: active_year.year + 1)
    planning_classroom = create(:classroom, school_year: planning_year, class_label: '준비')
    archived_year = create(:school_year, :archived, school: school, year: active_year.year - 1)
    other_school = create(:school)
    other_active_year = create(:school_year, :active, school: other_school, year: active_year.year)
    other_planning_year = create(:school_year, school: other_school, year: other_active_year.year + 1)
    sign_in manager

    get classrooms_path, params: { school_year_id: active_year.id }
    expect(response.body).to include(active_classroom.class_label)
    expect(response.body).to include(I18n.t('ui.buttons.new_classroom'))

    get classrooms_path, params: { school_year_id: planning_year.id }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(planning_classroom.class_label)
    expect(response.body).to include(I18n.t('classrooms.index.context_read_only'))
    expect(response.body).not_to include(I18n.t('ui.buttons.new_classroom'))

    get classrooms_path, params: { school_year_id: archived_year.id }
    expect(response).to have_http_status(:not_found)

    get classrooms_path, params: {
      school_id: other_school.id,
      school_year_id: other_planning_year.id
    }
    expect(response).to have_http_status(:not_found)
  end

  it 'fails closed for a malformed School context' do
    sign_in create(:user, :admin)

    get classrooms_path, params: { school_id: 'invalid' }

    expect(response).to have_http_status(:not_found)
  end

  it 'fails closed when an admin supplies a SchoolYear without a School' do
    school = create(:school)
    other_year = create(:school_year, :active, school: school)
    sign_in create(:user, :admin)

    get classrooms_path, params: { school_year_id: other_year.id }

    expect(response).to have_http_status(:not_found)
  end

  it 'fails closed for a cross-school SchoolYear context' do
    school = create(:school)
    create(:school_year, :active, school: school)

    other_school = create(:school)
    other_year = create(:school_year, :active, school: other_school)

    sign_in create(:user, :admin)

    get classrooms_path, params: {
      school_id: school.id,
      school_year_id: other_year.id
    }

    expect(response).to have_http_status(:not_found)
  end

  it 'does not give an ordinary teacher a SchoolYear selector or explicit context' do
    school = create(:school)
    teacher = create(:user, :teacher, :active_annual_teacher, annual_school: school)
    sign_in teacher

    get classrooms_path
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include('name="school_year_id"')

    get classrooms_path, params: { school_year_id: teacher.school_year_id }
    expect(response).to have_http_status(:not_found)
  end
end
