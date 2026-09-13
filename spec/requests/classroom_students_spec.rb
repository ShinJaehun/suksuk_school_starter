require 'rails_helper'

RSpec.describe 'Classroom students', type: :request do
  include ActionView::RecordIdentifier

  let(:classroom) { create(:classroom) }
  let(:teacher) { create(:user, :teacher, :active_annual_teacher, annual_school: classroom.school_year.school) }
  let(:turbo_headers) { { 'ACCEPT' => 'text/vnd.turbo-stream.html' } }

  before do
    assign_teacher(classroom, teacher)
    sign_in teacher
  end

  def create_active_students(count, classroom:)
    count.times do |index|
      student = create(:student, classroom: classroom, name: "기존 활성 학생 #{index}")
    end
  end

  def create_outside_teacher
    outside_school = create(:school)
    create(:user, :teacher, :active_annual_teacher, annual_school: outside_school)
  end

  def sign_in_student(student)
    sign_out teacher
    post public_student_login_path(student_login_token: student.classroom.student_login_token),
         params: { student_id: student.id, student_pin: '1234' }
  end

  describe 'GET /classrooms/:id roster' do
    it 'shows active students in current-classroom roster order' do
      students = [
        create(:student, classroom: classroom, name: '5번 학생', student_number: 5),
        create(:student, classroom: classroom, name: '번호 없음 B'),
        create(:student, classroom: classroom, name: '1번 학생', student_number: 1),
        create(:student, classroom: classroom, name: '2번 학생', student_number: 2),
        create(:student, classroom: classroom, name: '번호 없음 A')
      ]
      past_classroom = create(:classroom)
      create(:student, classroom: past_classroom, name: students[2].name, active: false, student_number: 12)
      inactive_student = create(:student, classroom: classroom, name: '현재 비활성 학생', active: false, student_number: 3)

      get classroom_path(classroom)

      cards = Nokogiri::HTML(response.body).css('[data-student-card]')
      expect(cards.map { |card| card['data-student-id'].to_i }).to eq(
        [students[2], students[3], students[0], students[4], students[1]].map(&:id)
      )
      expect(cards.map { |card| card.at_css('[data-student-number]').text.squish }).to eq(
        ['1번', '2번', '5번', '번호 미지정', '번호 미지정']
      )
      expect(response.body).not_to include(inactive_student.name, '12번')
    end
  end

  describe 'GET /classrooms/:classroom_id/students/new' do
    it 'shows PIN fields without student password inputs' do
      get new_classroom_student_path(classroom)

      expect(response).to have_http_status(:ok)

      document = Nokogiri::HTML(response.body)
      student_number_input = document.at_css('input[name="student[student_number]"]')
      student_pin_input = document.at_css('input[name="student[student_pin]"]')

      expect(student_number_input).to be_present
      expect(student_number_input['required']).to be_nil

      expect(student_pin_input).to be_present
      expect(student_pin_input['type']).to eq('password')
      expect(student_pin_input['required']).to eq('required')
      expect(student_pin_input['maxlength']).to eq('4')

      expect(response.body).not_to include('name="user[email]"')
      expect(response.body).not_to include('name="user[password]"')
      expect(response.body).not_to include('name="user[password_confirmation]"')
      gender_select = document.at_css('select[name="student[gender]"]')
      expect(gender_select).to be_present
      expect(gender_select['required']).to eq('required')
      expect(gender_select.css('option').map { |option| option['value'] }).to include('boy', 'girl')
    end
  end

  describe 'POST /classrooms/:classroom_id/students' do
    it 'assigns an unused avatar_key from the selected gender pool' do
      used_avatar_keys = Student::BOY_AVATAR_KEYS.first(22)
      used_avatar_keys.each do |avatar_key|
        create(:student, classroom: classroom, gender: 'boy', avatar_key: avatar_key)
      end

      post classroom_students_path(classroom), params: {
        student: { student_number: 1,
                   name: '새 학생',
                   gender: 'boy',
                   student_pin: '1234' }
      }

      student = Student.find_by!(name: '새 학생')
      expect(student.gender).to eq('boy')
      expect(student.avatar_key).to eq('boy23')
      expect(student.avatar_key).not_to be_in(used_avatar_keys)
      expect(student.authenticate_student_pin('1234')).to be_truthy
      expect(response).to redirect_to(classroom_path(classroom))
    end

    it 'creates a Student without a User account with turbo stream' do
      user_count = User.count
      expect do
        post classroom_students_path(classroom),
             params: {
               student: { student_number: 1,
                          name: '터보 학생',
                          gender: 'girl',
                          student_pin: '2345' }
             },
             headers: turbo_headers
      end.to change(Student, :count).by(1)

      student = Student.find_by!(name: '터보 학생')
      expect(response.media_type).to eq('text/vnd.turbo-stream.html')
      expect(response.body).to include(%(target="students_list_#{classroom.id}"))
      expect(response.body).not_to include('target="student-management"')
      expect(response.body).to include('data-student-card', '1번')
      expect(student.classroom).to eq(classroom)
      expect(student.student_number).to eq(1)
      expect(User.count).to eq(user_count)
      expect(student.authenticate_student_pin('2345')).to be_truthy
    end

    it 'ignores submitted student email and Devise password params' do
      post classroom_students_path(classroom), params: {
        student: { student_number: 1,
                   name: '무비번 학생',
                   gender: 'girl',
                   email: 'ignored-student@example.com',
                   password: 'password123',
                   password_confirmation: 'password123',
                   student_pin: '4567' }
      }

      student = Student.find_by!(name: '무비번 학생')
      expect(student).not_to respond_to(:email)
      expect(student.authenticate_student_pin('4567')).to be_truthy
    end

    it 'creates a student and refreshes member management when submitted from members' do
      inactive_student = create(:student, classroom: classroom, name: '기존 비활성 학생', active: false)

      expect do
        post classroom_students_path(classroom),
             params: {
               return_to: 'members',
               student: { student_number: 1,
                          name: '구성원 학생',
                          gender: 'girl',
                          student_pin: '3456' }
             },
             headers: turbo_headers
      end.to change(Student, :count).by(1)

      document = Nokogiri::HTML.fragment(response.body)
      student = Student.find_by!(name: '구성원 학생')
      inactive_filter = document.at_css(
        %(a[href="#{classroom_members_path(classroom, status: 'inactive')}"])
      )

      expect(response.media_type).to eq('text/vnd.turbo-stream.html')
      expect(response.body).to include('target="student-management"')
      expect(response.body).to include('구성원 학생')
      expect(response.body).to include('1번')

      expect(response.body).not_to include('기존 비활성 학생')
      expect(response.body).not_to include(reactivate_classroom_student_path(classroom, inactive_student))
      expect(inactive_filter.text.squish).to eq('비활성 1')
      expect(response.body).to include(
        classroom_edit_member_student_names_path(classroom, status: 'active')
      )

      expect(response.body).to include(edit_classroom_student_path(classroom, student))
      expect(response.body).to include(deactivate_classroom_student_path(classroom, student))
      expect(response.body).to include('target="modal"')
      expect(student.classroom).to eq(classroom)
      expect(student.authenticate_student_pin('3456')).to be_truthy
    end

    it 'returns 422 with turbo stream when the student is invalid' do
      expect do
        post classroom_students_path(classroom),
             params: {
               student: { student_number: 1,
                          name: '',
                          gender: 'boy',
                          student_pin: '1234' }
             },
             headers: turbo_headers
      end.not_to change(Student, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.media_type).to eq('text/vnd.turbo-stream.html')
      expect(response.body).to include('target="modal"')
      expect(response.body).to include('이름')
    end

    it 'keeps validation errors inside the modal when submitted from members' do
      expect do
        post classroom_students_path(classroom),
             params: {
               return_to: 'members',
               student: { student_number: 1,
                          name: '',
                          gender: 'boy',
                          student_pin: '1234' }
             },
             headers: turbo_headers
      end.not_to change(Student, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.media_type).to eq('text/vnd.turbo-stream.html')
      expect(response.body).to include('target="modal"')
      expect(response.body).to include('name="return_to"')
      expect(response.body).to include('value="members"')
      expect(response.body).to include('이름')
    end

    it 'rejects a teacher outside the classroom' do
      outsider = create_outside_teacher
      sign_out teacher
      sign_in outsider

      expect do
        post classroom_students_path(classroom), params: {
          student: { student_number: 1,
                     name: '외부 생성',
                     gender: 'boy',
                     student_pin: '1234' }
        }
      end.not_to change(Student, :count)

      expect(response).to redirect_to(root_path)
    end

    it 'rejects a student' do
      student = create(:student, classroom: classroom)
      sign_out teacher

      expect do
        post classroom_students_path(classroom), params: {
          student: { student_number: 1,
                     name: '학생 생성',
                     gender: 'girl',
                     student_pin: '1234' }
        }
      end.not_to change(Student, :count)

      expect(response).to redirect_to(new_user_session_path)
    end

    it 'allows creating one student when the classroom has 29 active students' do
      create_active_students(29, classroom: classroom)

      expect do
        post classroom_students_path(classroom), params: {
          student: { student_number: 1,
                     name: '30번째 학생',
                     gender: 'boy',
                     student_pin: '1234' }
        }
      end.to change(Student, :count).by(1)

      expect(response).to redirect_to(classroom_path(classroom))
    end

    it 'rejects creating one student when the classroom already has 30 active students' do
      create_active_students(30, classroom: classroom)

      expect do
        post classroom_students_path(classroom), params: {
          student: { student_number: 1,
                     name: '초과 학생',
                     gender: 'girl',
                     student_pin: '1234' }
        }
      end.not_to change(Student, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('최대 30명')
      expect(Student.find_by(name: '초과 학생')).to be_nil
    end

    it 'does not count inactive students toward the individual create limit' do
      create_active_students(29, classroom: classroom)
      inactive_student = create(:student, classroom: classroom, name: '기존 비활성 학생', active: false)

      expect do
        post classroom_students_path(classroom), params: {
          student: { student_number: 1,
                     name: '활성 추가 학생',
                     gender: 'girl',
                     student_pin: '1234' }
        }
      end.to change(Student, :count).by(1)

      expect(response).to redirect_to(classroom_path(classroom))
    end

    it 'rejects blank PIN values on individual create' do
      expect do
        post classroom_students_path(classroom),
             params: {
               student: { student_number: 1,
                          name: 'PIN 없는 학생',
                          gender: 'boy',
                          student_pin: '' }
             },
             headers: turbo_headers
      end.not_to change(Student, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.media_type).to eq('text/vnd.turbo-stream.html')
      expect(response.body).to include('target="modal"')
      expect(response.body).to include('PIN은 4자리 숫자여야 합니다.')
    end

    it 'rejects invalid PIN values on individual create' do
      expect do
        post classroom_students_path(classroom),
             params: {
               student: { student_number: 1,
                          name: 'PIN 오류 학생',
                          gender: 'girl',
                          student_pin: '12ab' }
             },
             headers: turbo_headers
      end.not_to change(Student, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('PIN은 4자리 숫자여야 합니다.')
    end

    it 'allows a blank student number and rejects invalid nonblank numbers on individual create' do
      [
        ['0', '출석번호는 1 이상의 정수여야 합니다.'],
        ['-1', '출석번호는 1 이상의 정수여야 합니다.'],
        ['1.5', '출석번호는 1 이상의 정수여야 합니다.'],
        ['abc', '출석번호는 1 이상의 정수여야 합니다.']
      ].each do |student_number, message|
        expect do
          post classroom_students_path(classroom),
               params: {
                 student: { student_number: student_number, name: '번호 오류 학생', gender: 'boy', student_pin: '1234' }
               },
               headers: turbo_headers
        end.not_to change(Student, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include(message)
        expect(response.body).to include(%(value="#{student_number}")) if student_number.present?
      end

      expect do
        post classroom_students_path(classroom), params: {
          student: { student_number: '', name: '번호 미지정 학생', gender: 'boy', student_pin: '1234' }
        }
      end.to change(Student, :count).by(1)
      expect(Student.find_by!(name: '번호 미지정 학생').student_number).to be_nil
    end

    it 'rejects a student number used by another active student in the classroom' do
      existing = create(:student, classroom: classroom, student_number: 7)

      expect do
        post classroom_students_path(classroom),
             params: {
               student: { student_number: 7, name: '중복 번호 학생', gender: 'girl', student_pin: '1234' }
             },
             headers: turbo_headers
      end.not_to change(Student, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('7번 출석번호는 이미 사용 중입니다.')
      expect(Student.find_by(name: '중복 번호 학생')).to be_nil
    end

    it 'allows the same student number in another classroom' do
      other_classroom = create(:classroom)
      other_student = create(:student, classroom: other_classroom, student_number: 7)

      post classroom_students_path(classroom), params: {
        student: { student_number: 7, name: '다른 교실 번호 학생', gender: 'boy', student_pin: '1234' }
      }

      student = Student.find_by!(name: '다른 교실 번호 학생')
      expect(student.student_number).to eq(7)
      expect(response).to redirect_to(classroom_path(classroom))
    end

    it 'turns a student number database race into a form error and rolls back the Student' do
      allow_any_instance_of(Student).to receive(:save!)
        .and_raise(ActiveRecord::RecordNotUnique)

      expect do
        post classroom_students_path(classroom),
             params: {
               student: { student_number: 7, name: '경쟁 충돌 학생', gender: 'boy', student_pin: '1234' }
             },
             headers: turbo_headers
      end.not_to change(Student, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('7번 출석번호는 이미 사용 중입니다.')
      expect(Student.find_by(name: '경쟁 충돌 학생')).to be_nil
    end

    it 'rolls back the Student when saving fails' do
      invalid_student = build(:student, classroom: classroom)
      invalid_student.errors.add(:base, 'student failed')
      allow_any_instance_of(Student).to receive(:save!).and_raise(
        ActiveRecord::RecordInvalid.new(invalid_student)
      )

      expect do
        post classroom_students_path(classroom),
             params: {
               student: { student_number: 1,
                          name: '롤백 학생',
                          gender: 'boy',
                          student_pin: '1234' }
             },
             headers: turbo_headers
      end.not_to change(Student, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('target="modal"')
      expect(Student.find_by(name: '롤백 학생')).to be_nil
    end
  end

  describe 'bulk student creation' do
    def draft_params
      {
        '0' => { student_number: '1', name: '김학생', gender: 'girl', avatar_key: 'girl01' },
        '1' => { student_number: '2', name: '이학생', gender: 'boy', avatar_key: 'boy01' }
      }
    end

    def turbo_frame_headers
      {
        'Turbo-Frame' => 'modal',
        'Accept' => 'text/html'
      }
    end

    it 'renders the setup modal without creating students' do
      expect do
        get bulk_new_classroom_students_path(classroom), headers: { 'Turbo-Frame' => 'modal' }
      end.not_to change(Student, :count)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('id="bulk-student-setup-form"')
      expect(response.body).to include('name="student_count"', 'name="student_pin"')
      expect(response.body).not_to include('name="boy_count"', 'name="girl_count"')
      expect(response.body).to include('required="required"')
      expect(response.body).to include('명단 만들기')
      expect(response.body).not_to include('name="user[email]"')
      expect(response.body).not_to include('name="user[password]"')
    end

    it 'previews student draft rows without writing to the database' do
      user_count = Student.count

      expect do
        post bulk_preview_classroom_students_path(classroom),
             params: { student_count: 3, student_pin: '2468', boy_count: 30, girl_count: 30 },
             headers: turbo_frame_headers
      end.not_to change(Student, :count)

      document = Nokogiri::HTML.fragment(response.body)
      rows = document.css('#bulk-student-draft-list > .bulk-student-draft-row')

      expect(Student.count).to eq(user_count)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('id="bulk-student-preview-form"')
      expect(rows.size).to eq(3)
      expect(response.body).to include('placeholder="이름"')
      expect(response.body).to include('삭제')
      expect(response.body).to include('name="students[0][student_number]"')
      expect(response.body).to include('name="students[0][gender]"')
      expect(response.body).to include('bulk-student-draft#selectGender')
      expect(response.body).to include('name="students[0][avatar_key]"')
      expect(response.body).to include('data-bulk-student-draft-target="studentCount"')
      expect(response.body).to include('value="1"', 'value="2"', 'value="3"')
      expect(response.body).to include('bulk-student-draft#add', 'bulk-student-draft#remove')
      expect(response.body).not_to include('name="students[0][email]"')
      expect(response.body).not_to include('name="students[0][password]"')
      expect(response.request.fullpath).not_to include('2468')
    end

    it 'keeps setup values when preview validation fails' do
      expect do
        post bulk_preview_classroom_students_path(classroom),
             params: { student_count: 0, student_pin: '12ab' },
             headers: turbo_frame_headers
      end.not_to change(Student, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('id="bulk-student-setup-form"')
      expect(response.body).to include('value="0"')
      expect(response.body).to include('value="12ab"')
      expect(response.body).to include('등록할 학생 수는 1 이상의 정수여야 합니다.')
    end

    it 'rejects invalid student counts' do
      ['', '0', '-1', '1.5', 'abc'].each do |student_count|
        post bulk_preview_classroom_students_path(classroom),
             params: {
               student_count: student_count,
               student_pin: '2468'
             },
             headers: turbo_frame_headers

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include('등록할 학생 수는 1 이상의 정수여야 합니다.')
      end
    end

    it 'rejects preview when the PIN format is invalid' do
      post bulk_preview_classroom_students_path(classroom),
           params: { student_count: 1, student_pin: '12ab' },
           headers: turbo_frame_headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('초기 PIN은 4자리 숫자여야 합니다.')
    end

    it 'rejects preview when the PIN is blank' do
      post bulk_preview_classroom_students_path(classroom),
           params: { student_count: 1, student_pin: '' },
           headers: turbo_frame_headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('초기 PIN은 4자리 숫자여야 합니다.')
    end

    it 'rejects preview when the classroom would exceed the student limit' do
      29.times do |index|
        student = create(:student, classroom: classroom, name: "기존 학생 #{index}")
      end

      post bulk_preview_classroom_students_path(classroom),
           params: { student_count: 2, student_pin: '2468' },
           headers: turbo_frame_headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('최대 30명')
    end

    it 'allows preview when only active student memberships fit within the limit' do
      create_active_students(29, classroom: classroom)
      inactive_student = create(:student, classroom: classroom, name: '기존 비활성 학생', active: false)

      post bulk_preview_classroom_students_path(classroom),
           params: { student_count: 1, student_pin: '2468' },
           headers: turbo_frame_headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('id="bulk-student-preview-form"')
    end

    it 'rejects final create when active students changed after preview' do
      create_active_students(28, classroom: classroom)

      post bulk_preview_classroom_students_path(classroom),
           params: { student_count: 2, student_pin: '2468' },
           headers: turbo_frame_headers

      expect(response).to have_http_status(:ok)

      added_student = create(:student, classroom: classroom, name: '중간 추가 학생')

      expect do
        post bulk_create_classroom_students_path(classroom),
             params: {
               student_pin: '2468',
               students: {
                 '0' => { student_number: '1', name: '최종 학생 1', gender: 'boy', avatar_key: 'boy01' },
                 '1' => { student_number: '2', name: '최종 학생 2', gender: 'boy', avatar_key: 'boy02' }
               }
             },
             headers: turbo_headers
      end.not_to change(Student, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('최대 30명')
    end

    it 'returns to setup from preview without exposing the PIN in the URL' do
      post bulk_preview_classroom_students_path(classroom),
           params: { back: '1', student_count: 5, student_pin: '2468' },
           headers: turbo_frame_headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('id="bulk-student-setup-form"')
      expect(response.body).to include('value="5"', 'value="2468"')
      expect(response.request.fullpath).not_to include('2468')
    end

    it 'creates only submitted draft rows in a transaction' do
      expect do
        post bulk_create_classroom_students_path(classroom),
             params: {
               student_pin: '2468',
               students: draft_params.merge(
                 '2' => { student_number: '3', name: '', gender: 'boy', avatar_key: 'boy02' }
               ).except('2')
             }
      end.to change(Student, :count).by(2)

      created_students = classroom.students.order(:created_at).last(2)

      expect(created_students.map(&:name)).to contain_exactly('김학생', '이학생')
      expect(created_students.map(&:avatar_key)).to contain_exactly('boy01', 'girl01')
      expect(created_students).to all(satisfy { |student| student.authenticate_student_pin('2468') })
      expect(created_students.map(&:student_number)).to contain_exactly(1, 2)
      expect(created_students).to all(be_active)
      expect(flash[:notice]).to eq(I18n.t('students.bulk_create.success', count: 2))
    end

    it 'creates a mixed-preset nonconsecutive roster in submitted row order' do
      roster = {
        'a' => { student_number: '1', name: '첫째', gender: 'girl', avatar_key: 'girl01' },
        'b' => { student_number: '2', name: '둘째', gender: 'boy', avatar_key: 'boy01' },
        'c' => { student_number: '5', name: '셋째', gender: 'girl', avatar_key: 'girl02' },
        'd' => { student_number: '3', name: '넷째', gender: 'boy', avatar_key: 'boy02' }
      }

      expect do
        post bulk_create_classroom_students_path(classroom),
             params: { student_pin: '2468', students: roster }
      end.to change(Student, :count).by(4)

      students = classroom.students.where(name: %w[첫째 둘째 셋째 넷째])
      expect(students.pluck(:name, :student_number).to_h).to eq('첫째' => 1, '둘째' => 2, '셋째' => 5, '넷째' => 3)
      expect(students).to all(
        satisfy { |student| student.authenticate_student_pin('2468') }
      )
    end

    it 'rejects each invalid roster field and preserves the submitted row' do
      invalid_rows = [
        [{ student_number: '0', name: '학생', gender: 'boy', avatar_key: 'boy01' }, '출석번호는 1 이상의 정수여야 합니다.'],
        [{ student_number: '-1', name: '학생', gender: 'boy', avatar_key: 'boy01' }, '출석번호는 1 이상의 정수여야 합니다.'],
        [{ student_number: '1.5', name: '학생', gender: 'boy', avatar_key: 'boy01' }, '출석번호는 1 이상의 정수여야 합니다.'],
        [{ student_number: 'abc', name: '학생', gender: 'boy', avatar_key: 'boy01' }, '출석번호는 1 이상의 정수여야 합니다.'],
        [{ student_number: '7', name: '', gender: 'boy', avatar_key: 'boy01' }, '이름을 입력해 주세요.'],
        [{ student_number: '7', name: '학생', gender: '', avatar_key: 'boy01' }, '성별을 선택해 주세요.'],
        [{ student_number: '7', name: '학생', gender: 'boy', avatar_key: '' }, '썸네일을 선택해 주세요.'],
        [{ student_number: '7', name: '학생', gender: 'boy', avatar_key: 'teacherM01' }, '썸네일을 확인해 주세요.'],
        [{ student_number: '7', name: '학생', gender: 'boy', avatar_key: 'girl01' }, '썸네일을 확인해 주세요.']
      ]

      invalid_rows.each do |row, message|
        expect do
          post bulk_create_classroom_students_path(classroom),
               params: { student_pin: '2468', students: { 'kept-row' => row } },
               headers: turbo_headers
        end.not_to change(Student, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include(message, 'bulk_student_draft_kept-row')
        expect(response.body).to include(%(value="#{row[:student_number]}"))
      end
    end

    it 'marks every duplicate student number in the submitted roster' do
      expect do
        post bulk_create_classroom_students_path(classroom),
             params: {
               student_pin: '2468',
               students: {
                 'first' => { student_number: '7', name: '첫 학생', gender: 'boy', avatar_key: 'boy01' },
                 'second' => { student_number: '7', name: '둘 학생', gender: 'girl', avatar_key: 'girl01' }
               }
             },
             headers: turbo_headers
      end.not_to change(Student, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body.scan('7번 출석번호가 명단 안에서 중복되었습니다.').size).to be >= 2
    end

    it 'rejects a number held by an active student but ignores inactive numbers' do
      active_student = create(:student, classroom: classroom, student_number: 7)
      inactive_student = create(:student, classroom: classroom, active: false, student_number: 8)

      post bulk_create_classroom_students_path(classroom),
           params: {
             student_pin: '2468',
             students: {
               '0' => { student_number: '7', name: '충돌 학생', gender: 'boy', avatar_key: 'boy01' }
             }
           },
           headers: turbo_headers
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('7번 출석번호는 이미 사용 중입니다.')

      post bulk_create_classroom_students_path(classroom),
           params: {
             student_pin: '2468',
             students: {
               '0' => { student_number: '8', name: '허용 학생', gender: 'girl', avatar_key: 'girl01' }
             }
           }
      expect(Student.find_by!(name: '허용 학생')).to be_present
    end

    it 'rolls back all rows when a later Student save fails' do
      calls = 0
      allow_any_instance_of(Student).to receive(:save!).and_wrap_original do |method, *args, **kwargs|
        calls += 1
        raise ActiveRecord::RecordInvalid.new(method.receiver) if calls == 2

        method.call(*args, **kwargs)
      end

      expect do
        post bulk_create_classroom_students_path(classroom),
             params: { student_pin: '2468', students: draft_params },
             headers: turbo_headers
      end.not_to change(Student, :count)

      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'rolls back all rows when a later Student create fails' do
      calls = 0
      allow_any_instance_of(ActiveRecord::Associations::CollectionProxy).to receive(:create!).and_wrap_original do |method, *args|
        calls += 1
        if calls == 2
          invalid_student = build(:student, classroom: classroom)
          invalid_student.errors.add(:base, 'student failed')
          raise ActiveRecord::RecordInvalid.new(invalid_student)
        end

        method.call(*args)
      end

      expect do
        post bulk_create_classroom_students_path(classroom),
             params: { student_pin: '2468', students: draft_params },
             headers: turbo_headers
      end.not_to change(Student, :count)

      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'turns a database student number race into a roster error and rolls back all rows' do
      allow_any_instance_of(Student).to receive(:save!)
        .and_raise(ActiveRecord::RecordNotUnique)

      expect do
        post bulk_create_classroom_students_path(classroom),
             params: { student_pin: '2468', students: draft_params },
             headers: turbo_headers
      end.not_to change(Student, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('1번 출석번호는 이미 사용 중입니다.')
      expect(response.body).to include('김학생', '이학생')
    end

    it 'refreshes member management and closes the modal when submitted from members' do
      expect do
        post bulk_create_classroom_students_path(classroom),
             params: {
               return_to: 'members',
               student_pin: '1357',
               students: draft_params
             },
             headers: turbo_headers
      end.to change(Student, :count).by(2)

      expect(response.media_type).to eq('text/vnd.turbo-stream.html')
      expect(response.body).to include('target="student-management"')
      expect(response.body).to include('target="modal"')
      expect(response.body).to include('김학생', '이학생')
      expect(response.body).to include('1번', '2번')
    end

    it 'rolls back when final submitted rows are invalid and keeps entered drafts visible' do
      expect do
        post bulk_create_classroom_students_path(classroom),
             params: {
               student_pin: '2468',
               students: {
                 '0' => { student_number: '1', name: '유지 학생', gender: 'boy', avatar_key: 'boy01' },
                 '2' => { student_number: 'abc', name: '', gender: 'girl', avatar_key: 'girl01' }
               }
             },
             headers: turbo_headers
      end.not_to change(Student, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('id="bulk-student-preview-form"')
      expect(response.body).to include('유지 학생')
      expect(response.body).to include('bulk_student_draft_0')
      expect(response.body).to include('bulk_student_draft_2')
      expect(response.body).not_to include('bulk_student_draft_1')
      expect(response.body).to include('이름을 입력해 주세요')
      expect(response.body).to include('value="abc"')
    end

    it 'does not create students when final submitted rows are empty' do
      expect do
        post bulk_create_classroom_students_path(classroom),
             params: { student_pin: '2468', students: {} },
             headers: turbo_headers
      end.not_to change(Student, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('생성할 학생이 없습니다.')
    end

    it 'renders the submitted roster for a direct HTML validation error' do
      post bulk_create_classroom_students_path(classroom),
           params: {
             student_pin: '2468',
             students: {
               'html-row' => {
                 student_number: 'abc',
                 name: 'HTML 유지 학생',
                 gender: 'boy',
                 avatar_key: 'boy01'
               }
             }
           }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('id="bulk-student-preview-form"')
      expect(response.body).to include('HTML 유지 학생', 'value="abc"')
    end

    it 'does not create students when final PIN is blank' do
      expect do
        post bulk_create_classroom_students_path(classroom),
             params: {
               student_pin: '',
               students: draft_params
             },
             headers: turbo_headers
      end.not_to change(Student, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('초기 PIN은 4자리 숫자여야 합니다.')
    end

    it 'rolls back when final create would exceed the student limit' do
      create_active_students(29, classroom: classroom)

      expect do
        post bulk_create_classroom_students_path(classroom),
             params: {
               student_pin: '2468',
               students: draft_params
             },
             headers: turbo_headers
      end.not_to change(Student, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('최대 30명')
    end

    it 'allows final create when inactive memberships do not exceed the active student limit' do
      create_active_students(29, classroom: classroom)
      inactive_student = create(:student, classroom: classroom, name: '기존 비활성 학생', active: false)

      expect do
        post bulk_create_classroom_students_path(classroom),
             params: {
               student_pin: '2468',
               students: {
                 '0' => { student_number: '1', name: '추가 학생', gender: 'boy', avatar_key: 'boy01' }
               }
             }
      end.to change(Student, :count).by(1)

      expect(Student.find_by!(name: '추가 학생').authenticate_student_pin('2468')).to be_truthy
    end

    it 'rolls back when final avatar params are not valid for students' do
      expect do
        post bulk_create_classroom_students_path(classroom),
             params: {
               student_pin: '2468',
               students: {
                 '0' => { student_number: '1', name: '잘못된 학생', gender: 'boy', avatar_key: 'teacherM01' }
               }
             },
             headers: turbo_headers
      end.not_to change(Student, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('썸네일을 확인해 주세요')
    end

    it 'rejects a preset avatar that does not match the submitted gender' do
      expect do
        post bulk_create_classroom_students_path(classroom),
             params: {
               student_pin: '2468',
               students: {
                 '0' => { student_number: '1', name: '성별 불일치', gender: 'boy', avatar_key: 'girl01' }
               }
             },
             headers: turbo_headers
      end.not_to change(Student, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('썸네일을 확인해 주세요')
    end

    it 'ignores arbitrary role email and password params on final create' do
      other_classroom = create(:classroom)
      post bulk_create_classroom_students_path(classroom),
           params: {
             student_pin: '2468',
             students: {
               '0' => {
                 student_number: '1',
                 name: '보안 학생',
                 gender: 'boy',
                 avatar_key: 'boy01',
                 role: 'admin',
                 status: 'inactive',
                 classroom_id: other_classroom.id,
                 email: 'ignored@example.com',
                 password: 'password123'
               }
             }
           }

      student = Student.find_by!(name: '보안 학생')
      expect(student).to be_active
      expect(student.student_number).to eq(1)
      expect(student.classroom).to eq(classroom)
    end

    it 'rejects a teacher outside the classroom' do
      outsider = create_outside_teacher
      sign_out teacher
      sign_in outsider

      expect do
        post bulk_preview_classroom_students_path(classroom), params: { student_count: 2 }
      end.not_to change(Student, :count)

      expect(response).to redirect_to(root_path)
    end

    it 'allows an admin to preview drafts' do
      admin = create(:user, :admin)
      sign_out teacher
      sign_in admin

      post bulk_preview_classroom_students_path(classroom),
           params: { student_count: 1, student_pin: '2468' },
           headers: turbo_frame_headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('id="bulk-student-preview-form"')
    end

    it 'rejects a student' do
      student = create(:student, classroom: classroom)
      sign_out teacher

      expect do
        post bulk_create_classroom_students_path(classroom), params: { students: draft_params }
      end.not_to change(Student, :count)

      expect(response).to redirect_to(new_user_session_path)
    end

    it 'rejects a guest' do
      sign_out teacher

      expect do
        post bulk_preview_classroom_students_path(classroom), params: { student_count: 1 }
      end.not_to change(Student, :count)

      expect(response).to redirect_to(new_user_session_path)
    end
  end

  describe 'classroom-scoped student read boundaries' do
    let(:student) { create(:student, classroom: classroom) }
    let(:past_classroom) { create(:classroom, annual_school: classroom.school_year.school, class_label: '과거 학급') }
    let(:past_student) { create(:student, classroom: past_classroom, name: student.name, active: false) }

    it 'allows the assigned teacher to view the student in the URL classroom' do
      get classroom_student_path(classroom, student)

      expect(response).to have_http_status(:ok)
    end

    it 'rejects a teacher from the student page in an unassigned URL classroom' do
      get classroom_student_path(past_classroom, past_student)

      expect(response).to redirect_to(root_path)
    end

    it 'allows the past classroom teacher to view inactive student records' do
      past_teacher = create(:user, :teacher, :active_annual_teacher,
                            annual_school: past_classroom.school_year.school)
      assign_teacher(past_classroom, past_teacher)
      sign_out teacher
      sign_in past_teacher

      get classroom_student_path(past_classroom, past_student)

      expect(response).to have_http_status(:ok)
    end

    it 'allows an admin to view inactive student records' do
      sign_out teacher
      sign_in create(:user, :admin)

      get classroom_student_path(past_classroom, past_student)

      expect(response).to have_http_status(:ok)
    end

    it 'allows an unassigned school manager in its School' do
      manager = create(:user, :teacher, :active_annual_teacher,
                       annual_school: past_classroom.school_year.school,
                       annual_school_role: 'manager')
      sign_out teacher
      sign_in manager

      get classroom_student_path(past_classroom, past_student)

      expect(response).to have_http_status(:ok)
    end
  end

  describe 'GET /classrooms/:classroom_id/students/:id/edit' do
    it 'shows student PIN management without password inputs' do
      student = create(:student, classroom: classroom, student_number: 7)

      get edit_classroom_student_path(classroom, student)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('name="student[student_pin]"')
      expect(response.body).to include('name="student[student_number]"')
      expect(response.body).to include('value="7"')
      expect(response.body).not_to include('name="user[email]"')
      expect(response.body).not_to include('name="user[password]"')
      expect(response.body).not_to include('name="user[password_confirmation]"')
    end
  end

  describe 'PATCH /classrooms/:classroom_id/students/:id' do
    it 'keeps the existing admin student update flow and redirect' do
      student = create(:student, classroom: classroom, name: '기존 이름', avatar_key: 'boy01')
      membership = student
      sign_out teacher
      sign_in create(:user, :admin)

      patch classroom_student_path(classroom, student), params: {
        student: { student_number: 6, name: '관리자 수정', avatar_key: 'boy01' }
      }

      expect(response).to redirect_to(edit_classroom_student_path(classroom, student))
      expect(student.reload.name).to eq('관리자 수정')
      expect(membership.reload.student_number).to eq(6)
    end

    it 'lets a teacher add, change, and clear a student number' do
      student = create(:student, classroom: classroom, name: '번호 편집 학생', student_number: nil)
      membership = student

      patch classroom_student_path(classroom, student), params: {
        student: { student_number: 7, name: student.name }
      }
      expect(response).to redirect_to(edit_classroom_student_path(classroom, student))
      expect(membership.reload.student_number).to eq(7)

      patch classroom_student_path(classroom, student), params: {
        student: { student_number: 9, name: student.name }
      }
      expect(membership.reload.student_number).to eq(9)

      patch classroom_student_path(classroom, student), params: {
        student: { student_number: '', name: student.name }
      }
      expect(membership.reload.student_number).to be_nil
    end

    it 'rolls back user changes when an active student number is already used' do
      student = create(:student, classroom: classroom, name: '기존 이름', student_number: 7)
      membership = student
      classmate = create(:student, classroom: classroom, student_number: 8)

      patch classroom_student_path(classroom, student), params: {
        student: { student_number: 8, name: '저장되면 안 되는 이름' }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('8번 출석번호는 이미 사용 중입니다.')
      expect(student.reload.name).to eq('기존 이름')
      expect(membership.reload.student_number).to eq(7)
    end

    it 'allows an inactive student to use a number held by an active student' do
      active_student = create(:student, classroom: classroom, student_number: 7)
      inactive_student = create(:student, classroom: classroom, active: false, student_number: 9)
      inactive_membership = inactive_student

      patch classroom_student_path(classroom, inactive_student), params: {
        student: { student_number: 7, name: inactive_student.name }
      }

      expect(response).to redirect_to(edit_classroom_student_path(classroom, inactive_student))
      expect(inactive_membership.reload.student_number).to eq(7)
    end

    it 'turns a student number database race into an edit error without saving user changes' do
      student = create(:student, classroom: classroom, name: '경쟁 전 이름', student_number: 7)
      membership = student
      allow_any_instance_of(Student).to receive(:update)
        .and_raise(ActiveRecord::RecordNotUnique)

      patch classroom_student_path(classroom, student), params: {
        student: { student_number: 8, name: '경쟁 후 이름' }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('8번 출석번호는 이미 사용 중입니다.')
      expect(student.reload.name).to eq('경쟁 전 이름')
      expect(membership.reload.student_number).to eq(7)
    end
  end

  it 'reassigns avatar_key when gender changes and avatar_key is omitted' do
    student = create(:student, classroom: classroom, gender: 'boy', avatar_key: 'boy01')
    Student::GIRL_AVATAR_KEYS.first(16).each do |avatar_key|
      create(:student, classroom: classroom, gender: 'girl', avatar_key: avatar_key)
    end

    patch classroom_student_path(classroom, student), params: { student: { gender: 'girl' } }

    expect(response).to redirect_to(edit_classroom_student_path(classroom, student))
    expect(student.reload.gender).to eq('girl')
    expect(student.avatar_key).to eq('girl17')
  end

  it 'keeps the current avatar when avatar_key is omitted and gender is unchanged' do
    student = create(:student, classroom: classroom, gender: 'boy', avatar_key: 'boy01')

    patch classroom_student_path(classroom, student), params: { student: { name: '이름 변경' } }

    expect(student.reload.avatar_key).to eq('boy01')
  end

  it 'allows a matching avatar_key when gender changes' do
    student = create(:student, classroom: classroom, gender: 'boy', avatar_key: 'boy01')

    patch classroom_student_path(classroom, student), params: {
      student: { gender: 'girl', avatar_key: 'girl03' }
    }

    expect(response).to redirect_to(edit_classroom_student_path(classroom, student))
    expect(student.reload.gender).to eq('girl')
    expect(student.avatar_key).to eq('girl03')
  end

  it 'rejects an opposite-gender avatar_key when gender is unchanged' do
    student = create(:student, classroom: classroom, gender: 'girl', avatar_key: 'girl01')

    patch classroom_student_path(classroom, student), params: { student: { avatar_key: 'boy02' } }

    expect(response).to have_http_status(:unprocessable_content)
    expect(student.reload.avatar_key).to eq('girl01')
  end

  it 'rejects an unknown avatar key' do
    student = create(:student, classroom: classroom, gender: 'boy', avatar_key: 'boy01')

    patch classroom_student_path(classroom, student), params: { student: { avatar_key: 'unknown' } }

    expect(response).to have_http_status(:unprocessable_content)
    expect(student.reload.avatar_key).to eq('boy01')
  end

  it 'rejects a teacher avatar key' do
    student = create(:student, classroom: classroom, gender: 'girl', avatar_key: 'girl01')

    patch classroom_student_path(classroom, student), params: { student: { avatar_key: 'teacherM01' } }

    expect(response).to have_http_status(:unprocessable_content)
    expect(student.reload.avatar_key).to eq('girl01')
  end

  it 'allows unrelated updates when avatar_key is nil' do
    student = create(:student, classroom: classroom, avatar_key: nil)

    patch classroom_student_path(classroom, student), params: { student: { name: '수정 이름' } }

    expect(student.reload.name).to eq('수정 이름')
    expect(student.avatar_key).to be_nil
  end

  describe 'PATCH /classrooms/:classroom_id/students/:id/deactivate' do
    it 'lets the classroom teacher deactivate a student without deleting records' do
      student = create(:student, classroom: classroom)
      membership = student

      expect do
        patch deactivate_classroom_student_path(classroom, student)
      end.not_to change(Student, :count)

      expect(membership.reload).to be_inactive
      expect(response).to redirect_to(classroom_members_path(classroom))
      expect(flash[:notice]).to eq(I18n.t('students.deactivate.success'))
    end

    it 'lets an admin deactivate a student' do
      admin = create(:user, :admin)
      student = create(:student, classroom: classroom)
      membership = student
      sign_out teacher
      sign_in admin

      expect do
        patch deactivate_classroom_student_path(classroom, student)
      end.not_to change(Student, :count)

      expect(membership.reload).to be_inactive
    end

    it 'rejects a teacher outside the classroom' do
      outsider = create_outside_teacher
      student = create(:student, classroom: classroom)
      membership = student
      sign_out teacher
      sign_in outsider

      expect do
        patch deactivate_classroom_student_path(classroom, student)
      end.not_to change(Student, :count)

      expect(response).to redirect_to(root_path)
      expect(membership.reload).to be_active
    end

    it 'rejects a student' do
      student = create(:student, classroom: classroom)
      membership = student
      sign_in_student(student)

      expect do
        patch deactivate_classroom_student_path(classroom, student)
      end.not_to change(Student, :count)

      expect(response).to redirect_to(new_user_session_path)
      expect(membership.reload).to be_active
    end
  end

  describe 'PATCH /classrooms/:classroom_id/students/:id/reactivate' do
    it 'lets the classroom teacher reactivate an inactive student' do
      create_active_students(29, classroom: classroom)
      student = create(:student, classroom: classroom, active: false)
      membership = student

      patch reactivate_classroom_student_path(classroom, student)

      expect(membership.reload).to be_active
      expect(response).to redirect_to(classroom_members_path(classroom))
      expect(flash[:notice]).to eq(I18n.t('students.reactivate.success'))
    end

    it 'lets an admin reactivate an inactive student' do
      admin = create(:user, :admin)
      student = create(:student, classroom: classroom, active: false)
      membership = student
      sign_out teacher
      sign_in admin

      patch reactivate_classroom_student_path(classroom, student)

      expect(membership.reload).to be_active
    end

    it 'does not confuse an independent Student in another Classroom' do
      active_classroom = create(:classroom)
      other_student = create(:student, classroom: active_classroom, student_number: 7)
      student = create(:student, classroom: classroom, active: false, student_number: 7)

      patch reactivate_classroom_student_path(classroom, student)

      expect(response).to redirect_to(classroom_members_path(classroom))
      expect(student.reload).to be_active
      expect(other_student.reload).to be_active
    end

    it 'rejects reactivation when the classroom already has 30 active students' do
      create_active_students(30, classroom: classroom)
      student = create(:student, classroom: classroom, active: false)
      membership = student

      patch reactivate_classroom_student_path(classroom, student)

      expect(response).to redirect_to(classroom_members_path(classroom))
      expect(flash[:alert]).to eq(I18n.t('students.reactivate.too_many', count: Classroom::MAX_ACTIVE_STUDENTS))
      expect(membership.reload).to be_inactive
    end

    it 'applies the active student limit to an admin reactivation' do
      admin = create(:user, :admin)
      create_active_students(30, classroom: classroom)
      student = create(:student, classroom: classroom, active: false)
      membership = student
      sign_out teacher
      sign_in admin

      patch reactivate_classroom_student_path(classroom, student)

      expect(response).to redirect_to(classroom_members_path(classroom))
      expect(flash[:alert]).to eq(I18n.t('students.reactivate.too_many', count: Classroom::MAX_ACTIVE_STUDENTS))
      expect(membership.reload).to be_inactive
    end

    it 'applies the active number conflict rule to an admin' do
      admin = create(:user, :admin)
      create(:student, classroom: classroom, student_number: 7)
      student = create(:student, classroom: classroom, active: false, student_number: 7)
      sign_out teacher
      sign_in admin

      patch reactivate_classroom_student_path(classroom, student)

      expect(response).to redirect_to(classroom_members_path(classroom))
      expect(flash[:alert]).to eq(I18n.t('students.reactivate.active_membership_conflict'))
      expect(student.reload).to be_inactive
    end

    it 'does not let the active classroom teacher reactivate the student in another classroom' do
      other_classroom = create(:classroom)
      student = create(:student, classroom: other_classroom, active: false)

      patch reactivate_classroom_student_path(other_classroom, student)

      expect(response).to redirect_to(root_path)
      expect(student.reload).to be_inactive
    end

    it 'rejects a teacher outside the classroom' do
      outsider = create_outside_teacher
      student = create(:student, classroom: classroom, active: false)
      membership = student
      sign_out teacher
      sign_in outsider

      patch reactivate_classroom_student_path(classroom, student)

      expect(membership.reload).to be_inactive
      expect(response).to redirect_to(root_path)
    end

    it 'rejects a student' do
      student = create(:student, classroom: classroom, active: false)
      membership = student
      sign_in_student(student.tap { |record| record.update!(active: true) })
      student.update!(active: false)

      patch reactivate_classroom_student_path(classroom, student)

      expect(membership.reload).to be_inactive
      expect(response).to redirect_to(
        public_student_login_path(student_login_token: classroom.student_login_token)
      )
    end
  end

  describe 'DELETE /classrooms/:classroom_id/students/:id' do
    it 'keeps direct delete calls from hard deleting a student' do
      student = create(:student, classroom: classroom)
      membership = student

      expect do
        delete classroom_student_path(classroom, student)
      end.not_to change(Student, :count)

      expect(membership.reload).to be_inactive
      expect(response).to redirect_to(classroom_members_path(classroom))
    end
  end

  describe 'managed Student navigation and profile fields' do
    let(:student) { create(:student, classroom: classroom, student_pin: '1234', gender: 'boy', avatar_key: 'boy01') }

    it 'links from member management with the current filter context' do
      student
      get classroom_members_path(classroom, status: 'active')

      row = Nokogiri::HTML(response.body).at_css(%([data-student-row][data-student-id="#{student.id}"]))
      link = row.css('a').find { |item| item.text.strip == I18n.t('students.members.actions.account') }
      uri = URI.parse(link['href'])
      expect(uri.path).to eq(edit_classroom_student_path(classroom, student))
      expect(Rack::Utils.parse_nested_query(uri.query)).to eq('return_to' => 'members')
    end

    it 'returns to member management without the default active status query' do
      get edit_classroom_student_path(classroom, student, return_to: 'members', status: 'active')

      expect(response.body).to include(%(href="#{classroom_members_path(classroom)}"))
      expect(response.body).not_to include(%(href="#{classroom_members_path(classroom, status: 'active')}"))
    end

    it 'returns to member management with a non-default filter context' do
      student.update!(active: false)
      get edit_classroom_student_path(classroom, student, return_to: 'members', status: 'inactive')

      expect(response.body).to include(classroom_members_path(classroom, status: 'inactive'))
      expect(response.body).to include(I18n.t('students.edit.back_to_members'))
    end

    it 'keeps the Student detail return link on direct entry' do
      get edit_classroom_student_path(classroom, student)

      expect(response.body).to include(classroom_student_path(classroom, student))
      expect(response.body).to include(I18n.t('students.edit.back_to_student'))
    end

    it 'preserves member management context after saving' do
      patch classroom_student_path(classroom, student, return_to: 'members', status: 'all'),
            params: { student: { name: '변경된 이름' } }

      expect(student.reload.name).to eq('변경된 이름')
      expect(response).to redirect_to(edit_classroom_student_path(classroom, student, return_to: 'members',
                                                                                      status: 'all'))
    end

    it 'shows Student management fields without legacy account fields' do
      get edit_classroom_student_path(classroom, student)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('name="student[name]"', 'name="student[avatar_key]"',
                                       'name="student[student_pin]"')
      expect(response.body).to include('name="student[gender]"')
      expect(response.body).to include('id="student-avatar-dialog"')
      expect(response.body).to include('data-controller="student-avatar-picker"')
      expect(response.body).to include('change-&gt;student-avatar-picker#changeGender')
      expect(response.body).to include('data-gender="boy"', 'data-gender="girl"')
      expect(response.body).not_to include('name="user[email]"', 'name="user[password]"')
    end

    it 'updates Student name without accepting legacy account params' do
      patch classroom_student_path(classroom, student), params: {
        student: { name: '새 이름', email: 'ignored@example.com', password: 'ignored' }
      }

      expect(student.reload.name).to eq('새 이름')
      expect(student).not_to respond_to(:email)
    end

    it 'allows a classroom teacher to update gender with a matching Student preset avatar' do
      patch classroom_student_path(classroom, student), params: {
        student: { gender: 'girl', avatar_key: 'girl03' }
      }

      expect(student.reload.gender).to eq('girl')
      expect(student.avatar_key).to eq('girl03')
    end

    it 'allows an admin to update a Student preset avatar' do
      sign_out teacher
      sign_in create(:user, :admin)

      patch classroom_student_path(classroom, student), params: { student: { avatar_key: 'boy04' } }

      expect(student.reload.gender).to eq('boy')
      expect(student.avatar_key).to eq('boy04')
    end

    it 'rejects non-Student preset avatar keys' do
      patch classroom_student_path(classroom, student), params: { student: { avatar_key: 'teacherM01' } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(student.reload.avatar_key).to eq('boy01')
    end
  end
end
