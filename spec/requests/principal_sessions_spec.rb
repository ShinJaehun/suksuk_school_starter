require 'rails_helper'

RSpec.describe 'Student and User principal isolation', type: :request do
  let(:school) { create(:school) }
  let(:active_year) { create(:school_year, :active, school: school, year: 2026) }
  let(:classroom) { create(:classroom, school_year: active_year) }
  let(:student) { create(:student, classroom: classroom, student_pin: '1234') }
  let(:teacher) do
    create(:user, :teacher, school_year: active_year, school_role: 'member',
      login_id: 'principal-teacher', password: 'password123')
  end

  around do |example|
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    example.run
  ensure
    Rails.cache = original_cache
  end

  before do
    post public_student_login_path(student_login_token: classroom.student_login_token),
      params: { student_id: student.id, student_pin: '1234' }
    expect(response).to redirect_to(student_profile_path)
    expect(session[:student_id]).to eq(student.id)
  end

  def login_teacher(user, headers: {})
    post school_teacher_login_path(school), params: {
      teacher: { login_id: user.login_id, school_year_id: user.school_year_id, password: 'password123' }
    }, headers: headers
  end

  def expect_student_cleared
    expect(session[:student_id]).to be_nil
    expect(session[:student_login_classroom_id]).to be_nil
    expect(session[:student_last_seen_at]).to be_nil
    expect(controller.send(:current_student)).to be_nil
  end

  ['text/html', 'text/vnd.turbo-stream.html, text/html, application/xhtml+xml'].each do |accept|
    it "clears the Student principal on active Teacher login and logout (#{accept})" do
      login_teacher(teacher, headers: { 'ACCEPT' => accept })

      expect(response).to redirect_to(classrooms_path)
      expect(controller.current_user).to eq(teacher)
      expect_student_cleared
      get classrooms_path
      expect_student_cleared
      delete destroy_user_session_path
      expect(response).to redirect_to(school_teacher_login_path(school))
      get student_profile_path
      expect(response).to redirect_to(new_student_session_path)
      expect_student_cleared
    end

    it "clears the Student principal on Admin login and logout (#{accept})" do
      admin = create(:user, :admin, password: 'password123')
      post user_session_path, params: { user: { email: admin.email, password: 'password123' } },
        headers: { 'ACCEPT' => accept }

      expect(response).to redirect_to(schools_path)
      expect(controller.current_user).to eq(admin)
      expect_student_cleared
      delete destroy_user_session_path
      expect_student_cleared
      get student_profile_path, headers: { 'ACCEPT' => 'text/html' }
      expect(response).to redirect_to(new_student_session_path)
      expect_student_cleared
    end
  end

  it 'clears the Student principal on planning manager login, including scoped sign-out' do
    planning_year = create(:school_year, school: school, year: 2027)
    manager = create(:user, :teacher, school_year: planning_year, school_role: 'manager',
      login_id: 'planning-principal', password: 'password123')
    login_teacher(manager)

    expect(response).to redirect_to(school_planning_path(school))
    expect_student_cleared
    manager.update!(school_role: 'member')
    get school_planning_path(school)
    expect(response).to redirect_to(school_teacher_login_path(school))
    expect_student_cleared
    get student_profile_path
    expect(response).to redirect_to(new_student_session_path)
  end

  it 'clears the Student principal before the forced-password redirect' do
    teacher.update!(password_change_required: true)
    login_teacher(teacher)

    expect(response).to redirect_to(edit_forced_password_path)
    expect_student_cleared
    follow_redirect!
    expect(response).to have_http_status(:ok)
    expect_student_cleared
    delete destroy_user_session_path
    get student_profile_path
    expect(response).to redirect_to(new_student_session_path)
  end

  it 'preserves the Student principal on Teacher login page visits, failures and throttling' do
    get school_teacher_login_path(school)
    expect(controller.send(:current_student)).to eq(student)

    6.times do
      post school_teacher_login_path(school), params: {
        teacher: { login_id: teacher.login_id, password: 'wrong' }
      }
      expect(session[:student_id]).to eq(student.id)
      expect(session[:student_login_classroom_id]).to eq(classroom.id)
      expect(session[:student_last_seen_at]).to be_present
    end
    expect(response).to have_http_status(:too_many_requests)
    get student_profile_path
    expect(response).to have_http_status(:ok)
  end

  it 'preserves the Student principal on Admin login page visits, failures and throttling' do
    admin = create(:user, :admin, password: 'password123')
    get new_user_session_path
    expect(controller.send(:current_student)).to eq(student)

    6.times do
      post user_session_path, params: { user: { email: admin.email, password: 'wrong' } }
      expect(session[:student_id]).to eq(student.id)
      expect(session[:student_login_classroom_id]).to eq(classroom.id)
      expect(session[:student_last_seen_at]).to be_present
    end
    expect(response).to have_http_status(:too_many_requests)
    get student_profile_path
    expect(response).to have_http_status(:ok)
  end
end
