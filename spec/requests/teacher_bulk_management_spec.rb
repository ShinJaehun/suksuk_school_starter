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

  def create_row(index, **attributes)
    {
      name: "추가 교사 #{index}", login_id: "bulk-profile-#{index}",
      gender: 'male', avatar_key: User::TEACHER_MALE_AVATAR_KEYS.first,
      grade: '4', classroom_id: ''
    }.merge(attributes)
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
    teacher = create(:user, :teacher, school_year: active_year, school_role: 'member',
                                      login_id: 'avatar-bulk-teacher')
    sign_in current_manager

    get admin_teachers_path

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    expect(document.css('a').map(&:text)).to include('전체', '1학년', '2학년', '3학년', '4학년', '5학년', '6학년', '미배정')
    expect(document.at_css(%(a[href^="#{bulk_setup_admin_teachers_path}"]))).to be_present
    expect(document.at_css(%(form[action^="#{bulk_update_admin_teachers_path}"]))).to be_present
    expect(document.at_css('[data-management-filter-panel]')).to be_present
    name_input = document.at_css(%(input[name^="teachers[rows]"][name$="[name]"][value="#{teacher.name}"]))
    expect(name_input&.parent&.at_css('img.h-8.w-8')).to be_present
  end

  it 'returns single-create credentials to the trusted bulk management context only' do
    sign_in current_manager
    get admin_teachers_path, params: context(active_year)

    document = Nokogiri::HTML(response.body)
    add_link = document.at_css(%(a[href*="management_source=admin"][href^="#{new_teacher_path}"]))
    expect(add_link).to be_present

    get add_link['href']
    expect(Nokogiri::HTML(response.body).at_css(
             'input[name="management_source"][value="admin"]'
           )).to be_present

    post teachers_path, params: context(active_year).merge(
      management_source: 'admin',
      membership_grade: 4,
      user: { name: '단건 일괄 화면 교사', login_id: 'admin-surface-single', email: '' }
    )
    result = Nokogiri::HTML(response.body)
    expect(result.at_css(%(a[href="#{admin_teachers_path(context(active_year))}"]))).to be_present

    post teachers_path, params: context(active_year).merge(
      management_source: 'https://example.test/escape',
      membership_grade: 4,
      user: { name: '일반 화면 교사', login_id: 'untrusted-source-single', email: '' }
    )
    result = Nokogiri::HTML(response.body)
    expect(result.at_css(%(a[href="#{teachers_path(context(active_year))}"]))).to be_present
    expect(response.body).not_to include('example.test/escape')
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

  it 'lets the current manager open active and planning bulk setup' do
    sign_in current_manager

    [active_year, planning_year].each do |year|
      get bulk_setup_admin_teachers_path, params: context(year)

      expect(response).to have_http_status(:ok)
      document = Nokogiri::HTML(response.body)
      expect(document.at_css(%(input[name="school_id"][value="#{school.id}"]))).to be_present
      expect(document.at_css(%(input[name="school_year_id"][value="#{year.id}"]))).to be_present
    end
  end

  it 'limits the planning manager bulk context to its planning year' do
    active_year
    sign_in planning_manager

    get bulk_setup_admin_teachers_path, params: context(planning_year)
    expect(response).to have_http_status(:ok)

    get bulk_setup_admin_teachers_path, params: context(active_year)
    expect(response).to have_http_status(:not_found)
  end

  it 'starts four editable profile rows with the setup grade selected' do
    sign_in current_manager

    get bulk_new_admin_teachers_path, params: context(active_year).merge(grade: '6', count: 4)

    expect(response).to have_http_status(:ok)
    rows = Nokogiri::HTML(response.body).css('tr[data-teacher-bulk-target="row"]')
    expect(rows.size).to eq(4)
    rows.each do |row|
      expect(row.at_css('select[name$="[grade]"] option[selected]')['value']).to eq('6')
      expect(row.at_css('select[name$="[grade]"]')['data-action']).to eq('change->teacher-bulk#filter')
      gender = row.at_css('select[name$="[gender]"][required]')
      expect(gender).to be_present
      expect(gender.css('option').map { |option| option['value'] }).to eq(['', 'male', 'female'])
      expect(row.at_css('input[type="hidden"][name$="[avatar_key]"]')['value'].to_s).to eq('')
      expect(row.at_css('img[data-teacher-bulk-target="avatarImage"][hidden]')).to be_present
      expect(row.at_css('select[name$="[classroom_id]"]')).to be_present
    end
  end

  it 'starts unassigned rows with every grade and same-year active Classroom options available for filtering' do
    available = create(:classroom, school_year: active_year, grade: 3)
    inactive = create(:classroom, school_year: active_year, grade: 3, active: false)
    planning = create(:classroom, school_year: planning_year, grade: 3)
    sign_in current_manager

    get bulk_new_admin_teachers_path, params: context(active_year).merge(grade: 'unassigned', count: 2)

    expect(response).to have_http_status(:ok)
    rows = Nokogiri::HTML(response.body).css('tr[data-teacher-bulk-target="row"]')
    expect(rows.size).to eq(2)
    rows.each do |row|
      grade = row.at_css('select[name$="[grade]"]')
      expect(grade.css('option').map { |option| option['value'] }).to eq(['', *('1'..'6').to_a])
      selected = grade.at_css('option[selected]') || grade.at_css('option')
      expect(selected['value']).to eq('')
      classroom = row.at_css('select[name$="[classroom_id]"]')
      expect(classroom.at_css('option')['value']).to eq('')
      expect(classroom.at_css(%(option[value="#{available.id}"]))['data-grade']).to eq('3')
      expect(classroom.css('option').map { |option| option['value'] }).not_to include(inactive.id.to_s, planning.id.to_s)
    end
  end

  ['6', 'unassigned'].each do |setup_grade|
    it "creates matching assignments for mixed row grades without overwriting them with #{setup_grade}" do
      first_classroom = create(:classroom, school_year: active_year, grade: 3)
      second_classroom = create(:classroom, school_year: active_year, grade: 5)
      sign_in current_manager

      expect do
        post bulk_create_admin_teachers_path, params: context(active_year).merge(
          grade: setup_grade,
          teachers: { rows: {
            '0' => create_row(1, grade: '3', classroom_id: first_classroom.id),
            '1' => create_row(2, grade: '5', classroom_id: second_classroom.id,
                                gender: 'female', avatar_key: User::TEACHER_FEMALE_AVATAR_KEYS.last)
          } }
        )
      end.to change(User, :count).by(2)
                                 .and change(HomeroomAssignment, :count).by(2)
                                 .and change(TeacherCredentialEvent, :count).by(2)

      expect(response).to have_http_status(:ok)
      expect(first_classroom.reload.teacher).to have_attributes(
        login_id: 'bulk-profile-1', grade: 3, gender: 'male', avatar_key: User::TEACHER_MALE_AVATAR_KEYS.first
      )
      expect(second_classroom.reload.teacher).to have_attributes(
        login_id: 'bulk-profile-2', grade: 5, gender: 'female', avatar_key: User::TEACHER_FEMALE_AVATAR_KEYS.last
      )
    end
  end

  it 'rejects a tampered avatar batch and preserves submitted profiles, grades, and Classrooms on rerender' do
    classroom = create(:classroom, school_year: active_year, grade: 3)
    avatar_key = User::TEACHER_FEMALE_AVATAR_KEYS.last
    submitted_rows = [
      create_row(1, grade: '3', classroom_id: classroom.id, gender: 'female', avatar_key: avatar_key),
      create_row(2, grade: '', avatar_key: avatar_key)
    ]
    sign_in current_manager

    expect do
      post bulk_create_admin_teachers_path, params: context(active_year).merge(
        grade: '6', teachers: { rows: { '0' => submitted_rows.first, '1' => submitted_rows.last } }
      )
    end.to change(User, :count).by(0)
                               .and change(HomeroomAssignment, :count).by(0)
                               .and change(TeacherCredentialEvent, :count).by(0)

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include(I18n.t('admin.teachers.bulk.errors.avatar_invalid'))
    rows = Nokogiri::HTML(response.body).css('tr[data-teacher-bulk-target="row"]')
    expect(rows.size).to eq(2)
    rows.zip(submitted_rows).each do |row, submitted|
      %i[name login_id avatar_key].each do |field|
        expect(row.at_css(%(input[name$="[#{field}]"]))['value']).to eq(submitted.fetch(field))
      end
      %i[gender grade classroom_id].each do |field|
        select = row.at_css(%(select[name$="[#{field}]"]))
        selected = select.at_css('option[selected]') || select.at_css('option')
        expect(selected['value']).to eq(submitted.fetch(field).to_s)
      end
    end
    expect(rows.first.at_css('img[data-teacher-bulk-target="avatarImage"]')['src']).to include(avatar_key)
  end

  it 'creates a batch and returns committed credentials with no-store' do
    sign_in current_manager

    expect do
      post bulk_create_admin_teachers_path, params: context(active_year).merge(
        grade: '4',
        teachers: { rows: { '0' => {
          name: '일괄 교사', login_id: 'bulk-request', grade: '4',
          gender: 'male', avatar_key: User::TEACHER_MALE_AVATAR_KEYS.first
        } } }
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
            gender: 'male', avatar_key: User::TEACHER_MALE_AVATAR_KEYS.first,
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
