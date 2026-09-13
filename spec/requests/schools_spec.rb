require 'rails_helper'

RSpec.describe 'School workspaces', type: :request do
  let!(:school) { create(:school, name: '새싹초등학교', color_key: 'sky') }
  let!(:other_school) { create(:school, name: '다른초등학교', color_key: 'violet') }
  let(:admin) { create(:user, :admin) }
  let(:member) { create(:user, :teacher, :active_annual_teacher, annual_school: school) }
  let(:manager) do
    create(:user, :teacher, :active_annual_teacher,
           annual_school: school,
           annual_school_role: 'manager')
  end

  it 'allows an admin to view every school workspace' do
    sign_in admin

    get school_path(other_school)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(other_school.name)
  end

  it 'shows every school in the admin index' do
    sign_in admin

    get schools_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(school.name, other_school.name)
    expect(response.body).not_to include('translation missing')

    document = Nokogiri::HTML(response.body)
    expect(document.at_css('[data-management-filter-panel]')).to be_present
    school_card = document.at_xpath("//h2[normalize-space()='#{school.name}']/ancestor::article[1]")
    other_school_card = document.at_xpath("//h2[normalize-space()='#{other_school.name}']/ancestor::article[1]")

    expect(school_card['class']).to include('border-sky-200', 'bg-sky-50/70')
    expect(school_card.at_css('.bg-sky-500')).to be_present
    expect(other_school_card['class']).to include('border-violet-200', 'bg-violet-50/70')
    expect(other_school_card.at_css('.bg-violet-500')).to be_present
  end

  it 'uses annual teachers for counts and manager identity' do
    active_manager = manager
    active_member = member
    active_manager.update!(name: '연간 관리자')
    active_member.update!(name: '연간 일반 교사')
    inactive_teacher = create(:user, :teacher, :active_annual_teacher,
                              annual_school: school,
                              name: '비활성 교사',
                              active: false)
    sign_in admin

    get schools_path

    card = Nokogiri::HTML(response.body)
                   .at_xpath("//h2[normalize-space()='#{school.name}']/ancestor::article[1]")
    expect(card.text).to include('소속 교사 2명')
    expect(card.text).to include(active_manager.name)
    expect(card.text).not_to include(active_member.name, '소속 교사 3명')

    inactive_teacher.update!(active: true)
    get schools_path

    card = Nokogiri::HTML(response.body)
                   .at_xpath("//h2[normalize-space()='#{school.name}']/ancestor::article[1]")
    expect(card.text).to include('소속 교사 3명')
  end

  it 'redirects a member or manager index to their only school without exposing others' do
    [member, manager].each do |teacher|
      sign_in teacher
      get schools_path
      expect(response).to redirect_to(school_path(school))
      expect(response.body).not_to include(other_school.name)
    end
  end

  it "shows school navigation only while a manager's school is active" do
    school_manager = manager
    sign_in school_manager

    get classrooms_path
    expect(response.body.scan(%(href="#{school_path(school)}")).size).to eq(2)
    expect(response.body.scan(%(href="#{teachers_path}")).size).to eq(2)

    school.update!(active: false)
    get classrooms_path
    expect(response).to redirect_to(school_teacher_login_path(school))
  end

  it 'does not show school navigation to a member of an inactive school' do
    sign_in member
    school.update!(active: false)

    get classrooms_path

    expect(response).to redirect_to(school_teacher_login_path(school))
  end

  it 'allows members and managers to view only their school' do
    [member, manager].each do |teacher|
      sign_in teacher
      get school_path(school)
      expect(response).to have_http_status(:ok)

      get school_path(other_school)
      expect(response).to have_http_status(:not_found)
    end
  end

  it 'rejects an unassigned teacher and a Student session' do
    unassigned_school = create(:school)
    unassigned_teacher = create(:user, :teacher, :active_annual_teacher,
                                annual_school: unassigned_school)

    sign_in unassigned_teacher
    get school_path(school)
    expect(response).to have_http_status(:not_found)

    student = create(:student, student_pin: '1234')
    sign_out :user
    post public_student_login_path(student_login_token: student.classroom.student_login_token),
         params: { student_id: student.id, student_pin: '1234' }
    get school_path(school)
    expect(response).to redirect_to(new_user_session_path)
  end

  it 'does not expose school workspace links from the classrooms index' do
    sign_in admin
    get classrooms_path
    expect(response.body).not_to include(school_path(school))

    sign_in member
    get classrooms_path
    expect(response.body).not_to include(school_path(school))
    expect(response.body).not_to include(school_path(other_school))
    expect(response.body).not_to include('translation missing')
  end
end
