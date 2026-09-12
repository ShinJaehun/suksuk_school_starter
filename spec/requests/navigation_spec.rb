require 'rails_helper'

RSpec.describe 'Navigation', type: :request do
  def navbar
    document = Nokogiri::HTML(response.body)
    document.at_css('[data-navigation-root="navbar"]').tap do |navigation|
      expect(navigation).to be_present
    end
  end

  def navbar_links
    navbar.css('a[href]').map { |link| link['href'] }
  end

  it 'shows the sign in link to a guest' do
    get new_user_session_path

    expect(navbar.text).to include('Sign in')
    expect(navbar_links).to include(new_user_session_path)
  end

  it 'shows student navigation without teacher account or management links' do
    classroom = create(:classroom)
    student = create(
      :student,
      classroom: classroom,
      student_pin: '1234'
    )

    post public_student_login_path(
      student_login_token: classroom.student_login_token
    ), params: {
      student_id: student.id,
      student_pin: '1234'
    }

    expect(response).to redirect_to(student_profile_path)

    get student_profile_path

    expect(navbar_links).to include(
      student_profile_path,
      destroy_student_session_path
    )
    expect(navbar.text).to include(I18n.t('navigation.my_page'))
    expect(navbar_links).not_to include(
      edit_user_registration_path,
      destroy_user_session_path
    )
  end

  it 'links a teacher without classrooms to the classroom index' do
    teacher = create(:user, :teacher, :active_annual_teacher, annual_school: create(:school))
    sign_in teacher

    get classrooms_path

    expect(navbar_links).to include(classrooms_path)
  end

  it 'links a teacher with one classroom directly to that classroom' do
    classroom = create(:classroom)
    teacher = create(:user, :teacher, :active_annual_teacher, annual_school: classroom.school_year.school)
    assign_teacher(classroom, teacher)
    sign_in teacher

    get classrooms_path
    expect(response).to redirect_to(classroom_path(classroom))
    follow_redirect!

    expect(navbar_links).to include(classroom_path(classroom))
  end

  it 'links a planning manager only to its explicit planning preparation contexts' do
    school = create(:school)
    active_year = create(:school_year, :active, school: school, year: 2026)
    planning_year = create(:school_year, school: school, year: active_year.year + 1)
    planning_manager = create(:user, :teacher, school_year: planning_year,
                                               school_role: 'manager', login_id: 'navigation-manager')
    context = { school_id: school.id, school_year_id: planning_year.id }
    sign_in planning_manager

    get school_planning_path(school)

    expect(navbar_links).to include(teachers_path(context), classrooms_path(context))
    expect(navbar_links).not_to include(teachers_path, classrooms_path)
  end
end
