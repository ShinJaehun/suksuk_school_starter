require 'rails_helper'

RSpec.describe 'Classroom student login link', type: :request do
  let(:classroom) { create(:classroom) }
  let(:teacher) { create(:user, :teacher, :active_annual_teacher, annual_school: classroom.school_year.school) }
  let(:admin) { create(:user, :admin) }
  let(:student) { create(:student, classroom: classroom, student_pin: '1234') }

  def sign_in_student
    post public_student_login_path(student_login_token: classroom.student_login_token),
         params: { student_id: student.id, student_pin: '1234' }
  end

  it 'shows the student login modal link without exposing the token URL on the classroom show page' do
    assign_teacher(classroom, teacher)
    sign_in teacher

    get classroom_path(classroom)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('학생 로그인')
    expect(response.body).to include(student_login_info_classroom_path(classroom))
    expect(response.body).to include('data-turbo-frame="modal"')
    expect(response.body).to include('구성원 관리')
    expect(response.body).to include(classroom_members_path(classroom))
    expect(response.body).not_to include('학생 로그인 주소')
    expect(response.body).not_to include('QR 코드 보기')
    expect(response.body).not_to include(classroom.student_login_token)
    expect(response.body).not_to include(public_student_login_url(student_login_token: classroom.student_login_token))
  end

  it 'shows actual homeroom teachers to an admin on the classroom show page' do
    assign_teacher(classroom, teacher)
    sign_in admin

    get classroom_path(classroom)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(teacher.name)
    expect(response.body).to include("#{teacher.name} avatar")
  end

  it 'does not show an admin as a homeroom teacher' do
    admin.update!(name: '레거시 관리자')
    sign_in admin

    get classroom_path(classroom)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('담당 교사 없음')
  end

  it 'shows the token student login controls to a classroom teacher in the modal' do
    assign_teacher(classroom, teacher)
    sign_in teacher

    get student_login_info_classroom_path(classroom)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('학생 로그인')
    expect(response.body).to include(public_student_login_url(student_login_token: classroom.student_login_token))
    expect(response.body).to include('URL 복사')
    expect(response.body).to include('QR 코드 보기')
    expect(response.body).to include(student_login_qr_classroom_path(classroom))
    expect(response.body).to include('QR 코드 다운로드')
    expect(response.body).to include(download_student_login_qr_classroom_path(classroom))
    expect(response.body).to include('학생 로그인 주소 재발급')
  end

  it 'shows the token student login controls to an admin in the modal' do
    sign_in admin

    get student_login_info_classroom_path(classroom)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(public_student_login_url(student_login_token: classroom.student_login_token))
  end

  it 'requires authentication for the student login info modal' do
    get student_login_info_classroom_path(classroom)

    expect(response).to redirect_to(new_user_session_path)
  end

  it 'does not expose the token student login URL to a Student session' do
    sign_in_student

    get classroom_path(classroom)

    expect(response).to redirect_to(new_user_session_path)
    expect(response.body).not_to include(classroom.student_login_token)
  end

  it 'does not allow a Student session to access the student login info modal' do
    sign_in_student

    get student_login_info_classroom_path(classroom)

    expect(response).to redirect_to(new_user_session_path)
    expect(response.body).not_to include(classroom.student_login_token)
  end

  it 'does not allow a non-managing teacher to access token management' do
    sign_in teacher

    get student_login_info_classroom_path(classroom)

    expect(response).to redirect_to(root_path)
    expect(response.body).not_to include(classroom.student_login_token)
  end

  it 'allows an unassigned school manager to access token management' do
    teacher.update!(school_role: 'manager')
    sign_in teacher

    get student_login_info_classroom_path(classroom)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(
      public_student_login_url(student_login_token: classroom.student_login_token)
    )
  end

  it 'does not show student login controls on the members page' do
    assign_teacher(classroom, teacher)
    sign_in teacher

    get classroom_members_path(classroom)

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include(public_student_login_url(student_login_token: classroom.student_login_token))
    expect(response.body).not_to include('URL 복사')
    expect(response.body).not_to include('QR 코드 보기')
    expect(response.body).not_to include('QR 코드 다운로드')
    expect(response.body).not_to include('학생 로그인 주소 재발급')
  end

  it 'shows the student login QR page to a classroom teacher' do
    assign_teacher(classroom, teacher)
    sign_in teacher

    get student_login_qr_classroom_path(classroom)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('학생 로그인 QR 코드')
    expect(response.body).to include('data:image/png;base64,')
    expect(response.body).to include(public_student_login_url(student_login_token: classroom.student_login_token))
  end

  it 'shows the student login QR page to an admin' do
    sign_in admin

    get student_login_qr_classroom_path(classroom)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('data:image/png;base64,')
    expect(response.body).to include(public_student_login_url(student_login_token: classroom.student_login_token))
  end

  it 'downloads the student login QR PNG for a classroom teacher' do
    assign_teacher(classroom, teacher)
    sign_in teacher

    get download_student_login_qr_classroom_path(classroom)

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq('image/png')
    expect(response.headers['Content-Disposition']).to include(
      'attachment',
      "student-login-qr-#{classroom.id}.png"
    )
    expect(response.body.bytes.first(4)).to eq([137, 80, 78, 71])
  end

  it 'does not allow a non-managing teacher to download the QR PNG' do
    sign_in teacher

    get download_student_login_qr_classroom_path(classroom)

    expect(response).to redirect_to(root_path)
    expect(response.body).not_to include(classroom.student_login_token)
  end

  it 'does not allow a Student session to download the QR PNG' do
    sign_in_student

    get download_student_login_qr_classroom_path(classroom)

    expect(response).to redirect_to(new_user_session_path)
    expect(response.body).not_to include(classroom.student_login_token)
  end

  it 'does not allow a non-managing teacher to access the QR page' do
    sign_in teacher

    get student_login_qr_classroom_path(classroom)

    expect(response).to redirect_to(root_path)
    expect(response.body).not_to include(classroom.student_login_token)
  end

  it 'does not allow a Student session to access the QR page' do
    sign_in_student

    get student_login_qr_classroom_path(classroom)

    expect(response).to redirect_to(new_user_session_path)
    expect(response.body).not_to include(classroom.student_login_token)
  end

  it 'regenerates the student login token for a classroom teacher' do
    assign_teacher(classroom, teacher)
    old_token = classroom.student_login_token
    sign_in teacher

    patch regenerate_student_login_token_classroom_path(classroom)

    expect(response).to redirect_to(classroom_path(classroom))
    expect(flash[:notice]).to include('학생 로그인 주소를 재발급했습니다.')
    expect(flash[:notice]).to include('기존에 복사해 둔 주소와 기존 QR 코드는 더 이상 사용할 수 없습니다.')
    expect(flash[:notice]).to include('아래 새 주소를 다시 복사하거나 QR 코드를 다시 안내하세요.')
    expect(classroom.reload.student_login_token).not_to eq(old_token)
  end

  it 'uses the new token URL on the QR page after regeneration' do
    assign_teacher(classroom, teacher)
    old_token = classroom.student_login_token
    sign_in teacher

    patch regenerate_student_login_token_classroom_path(classroom)
    new_token = classroom.reload.student_login_token

    get student_login_qr_classroom_path(classroom)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(public_student_login_url(student_login_token: new_token))
    expect(response.body).not_to include(public_student_login_url(student_login_token: old_token))
  end

  it 'downloads a QR PNG after regeneration' do
    assign_teacher(classroom, teacher)
    sign_in teacher

    patch regenerate_student_login_token_classroom_path(classroom)

    get download_student_login_qr_classroom_path(classroom)

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq('image/png')
    expect(response.body.bytes.first(4)).to eq([137, 80, 78, 71])
  end

  it 'expires the old token route and keeps the new token route available after regeneration' do
    assign_teacher(classroom, teacher)
    old_token = classroom.student_login_token
    sign_in teacher

    patch regenerate_student_login_token_classroom_path(classroom)
    new_token = classroom.reload.student_login_token
    delete destroy_user_session_path

    get public_student_login_path(student_login_token: old_token)
    expect(response).to have_http_status(:not_found)
    expect(response.body).to include('학생 로그인 주소를 사용할 수 없습니다.')

    get public_student_login_path(student_login_token: new_token)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('학생 PIN 로그인')
  end

  it 'does not allow a non-managing teacher to regenerate the token' do
    old_token = classroom.student_login_token
    sign_in teacher

    patch regenerate_student_login_token_classroom_path(classroom)

    expect(response).to redirect_to(root_path)
    expect(classroom.reload.student_login_token).to eq(old_token)
  end

  it 'allows an unassigned school manager to regenerate the token' do
    teacher.update!(school_role: 'manager')
    old_token = classroom.student_login_token
    sign_in teacher

    patch regenerate_student_login_token_classroom_path(classroom)

    expect(response).to redirect_to(classroom_path(classroom))
    expect(classroom.reload.student_login_token).not_to eq(old_token)
  end
end
