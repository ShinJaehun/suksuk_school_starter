require 'rails_helper'

RSpec.describe 'Classroom members', type: :request do
  let(:classroom) { create(:classroom, class_label: '2반') }
  let(:admin) { create(:user, :admin) }
  let(:teacher) do
    create(:user, :teacher, :active_annual_teacher,
           annual_school: classroom.school_year.school,
           name: '담당 교사')
  end

  def managed_student(classroom: nil, status: 'active', student_number: nil, **attributes)
    classroom ||= self.classroom
    attributes[:gender] = 'boy' unless attributes.key?(:gender)
    attributes[:avatar_key] = 'boy01' unless attributes.key?(:avatar_key)

    create(
      :student,
      classroom:,
      active: status == 'active',
      student_number:,
      **attributes
    )
  end

  it 'shows member management sections to a classroom teacher' do
    assign_teacher(classroom, teacher)
    student = managed_student(name: '활성 학생', gender: 'boy', avatar_key: 'boy01')
    sign_in teacher

    get classroom_members_path(classroom)

    document = Nokogiri::HTML(response.body)
    active_filter = document.at_css(
      %(a[href="#{classroom_members_path(classroom, status: 'active')}"])
    )
    inactive_filter = document.at_css(
      %(a[href="#{classroom_members_path(classroom, status: 'inactive')}"])
    )
    all_filter = document.at_css(
      %(a[href="#{classroom_members_path(classroom, status: 'all')}"])
    )

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('구성원 관리')
    expect(response.body).to include('2반')
    expect(response.body).to include('학생 관리')
    expect(response.body).to include(student.name)
    expect(response.body).to include('alt="활성 학생 avatar"')

    expect(active_filter.text.squish).to eq('활성 1')
    expect(inactive_filter.text.squish).to eq('비활성 0')
    expect(all_filter.text.squish).to eq('전체 1')

    expect(response.body).to include('학생 명단 일괄 편집')
    expect(response.body).to include(classroom_edit_member_student_names_path(classroom))
    expect(response.body).to include('id="student-creation-actions"')
    expect(response.body).to include('id="student-bulk-management-actions"')
    expect(response.body).to include('data-turbo-frame="modal"')
    expect(response.body).not_to include('id="student-name-editor"')
    expect(response.body).not_to include('id="student_names_form"')
    expect(response.body).not_to include('type="checkbox"')
    expect(response.body).to include(deactivate_classroom_student_path(classroom, student))
    expect(response.body).to include(new_classroom_student_path(classroom))
    expect(response.body).to include(new_classroom_student_path(classroom, return_to: 'members'))
    expect(response.body).to include(bulk_new_classroom_students_path(classroom))
    expect(response.body).to include(bulk_new_classroom_students_path(classroom, return_to: 'members'))
    expect(response.body).not_to include(%(action="#{classroom_member_student_names_path(classroom)}"))
    expect(response.body).to include(classroom_edit_member_student_pin_path(classroom))
    expect(response.body).to include('활성 학생 PIN 재설정')
    expect(response.body).not_to include(student_login_info_classroom_path(classroom))
    expect(response.body).not_to include('학생 로그인 관리')
    expect(response.body).to include(edit_classroom_student_path(classroom, student))
    expect(response.body).not_to include(public_student_login_url(student_login_token: classroom.student_login_token))
    expect(response.body).not_to include('QR 코드 보기')
    expect(response.body).not_to include('QR 코드 다운로드')
    expect(response.body).not_to include('학생 로그인 주소 재발급')
    expect(response.body).not_to include('담당 선생님 배정')
    expect(response.body).not_to include('classroom[teacher_ids][]')
  end

  it 'does not show teacher assignment controls to an admin' do
    assign_teacher(classroom, teacher)
    sign_in admin

    get classroom_members_path(classroom)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('2반')
    expect(response.body).to include('학생 관리')
    expect(response.body).not_to include('담당 선생님 배정')
    expect(response.body).not_to include('담당 선생님 저장')
    expect(response.body).not_to include('classroom[teacher_ids][]')
    expect(response.body).not_to include('학생 로그인 주소 재발급')
  end

  it 'shows active students by default with matching row actions' do
    active_student = managed_student(name: '김활동')
    inactive_student = managed_student(name: '박휴식', status: 'inactive')
    active_membership = active_student
    sign_in admin

    get classroom_members_path(classroom)

    document = Nokogiri::HTML(response.body)
    active_row = document.at_css("#member_row_student_#{active_membership.id}")
    student_management = document.at_css('#student-management')

    expect(response).to have_http_status(:ok)
    expect(document.at_css(%(a[aria-current="page"])).text).to include('활성')
    expect(active_row.text).to include(active_student.name, '활성')
    expect(active_row.text).not_to include(active_membership.id.to_s)
    expect(response.body).to include(edit_classroom_student_path(classroom, active_student))
    expect(response.body).to include(deactivate_classroom_student_path(classroom, active_student))
    expect(response.body).to include('data-turbo-confirm')
    expect(response.body).to include('name="_method"')
    expect(response.body).to include('value="patch"')
    expect(response.body).not_to include(inactive_student.name)
    expect(response.body).not_to include(reactivate_classroom_student_path(classroom, inactive_student))
    expect(response.body).not_to include('더보기')

    expect(student_management.at_css('details')).to be_nil
    expect(student_management.at_css('input[type="checkbox"]')).to be_nil

    expect(response.body).to include('활성')
  end

  it 'filters inactive and all students with matching row actions' do
    active_student = managed_student(name: '김활동')
    inactive_student = managed_student(name: '박휴식', status: 'inactive')
    active_membership = active_student
    inactive_membership = inactive_student
    sign_in admin

    get classroom_members_path(classroom, status: 'inactive')

    inactive_document = Nokogiri::HTML(response.body)
    inactive_row = inactive_document.at_css("#member_row_student_#{inactive_membership.id}")

    expect(response).to have_http_status(:ok)
    expect(inactive_document.at_css(%(a[aria-current="page"])).text).to include('비활성')
    expect(response.body).not_to include(active_student.name)
    expect(inactive_row.text).to include(inactive_student.name, '비활성')
    expect(inactive_row.text).not_to include(inactive_membership.id.to_s)
    expect(response.body).not_to include("member_row_student_#{active_membership.id}")
    expect(response.body).to include(edit_classroom_student_path(classroom, inactive_student))
    expect(response.body).to include(reactivate_classroom_student_path(classroom, inactive_student))
    expect(response.body).not_to include(deactivate_classroom_student_path(classroom, inactive_student))

    get classroom_members_path(classroom, status: 'all')

    all_document = Nokogiri::HTML(response.body)

    expect(all_document.at_css(%(a[aria-current="page"])).text).to include('전체')
    expect(response.body).to include(active_student.name, inactive_student.name)
    expect(all_document.at_css("#member_row_student_#{active_membership.id}").text).not_to include(active_membership.id.to_s)
    expect(all_document.at_css("#member_row_student_#{inactive_membership.id}").text).not_to include(inactive_membership.id.to_s)

    get classroom_members_path(classroom, status: 'unknown')

    fallback_document = Nokogiri::HTML(response.body)

    expect(fallback_document.at_css(%(a[aria-current="page"])).text).to include('활성')
    expect(response.body).to include(active_student.name)
    expect(response.body).not_to include(inactive_student.name)
  end

  it 'orders active, inactive, and all filters by roster number within status groups' do
    active_students = [
      managed_student(name: '활성 5', student_number: 5),
      managed_student(name: '활성 번호 없음 B'),
      managed_student(name: '활성 1', student_number: 1),
      managed_student(name: '활성 2', student_number: 2),
      managed_student(name: '활성 번호 없음 A')
    ]
    inactive_students = [
      managed_student(name: '비활성 5 B', status: 'inactive', student_number: 5),
      managed_student(name: '비활성 1', status: 'inactive', student_number: 1),
      managed_student(name: '비활성 5 A', status: 'inactive', student_number: 5),
      managed_student(name: '비활성 번호 없음', status: 'inactive')
    ]
    sign_in admin

    get classroom_members_path(classroom, status: 'active')
    active_rows = Nokogiri::HTML(response.body).css('[data-student-row]')
    expect(active_rows.map { |row| row['data-student-id'].to_i }).to eq(
      [active_students[2], active_students[3], active_students[0], active_students[4], active_students[1]].map(&:id)
    )
    expect(active_rows.map { |row| row.at_css('[data-student-number]').text.squish }).to eq(
      ['1번', '2번', '5번', '번호 미지정', '번호 미지정']
    )

    get classroom_members_path(classroom, status: 'inactive')
    inactive_rows = Nokogiri::HTML(response.body).css('[data-student-row]')
    expect(inactive_rows.map { |row| row['data-student-id'].to_i }).to eq(
      [inactive_students[1], inactive_students[2], inactive_students[0], inactive_students[3]].map(&:id)
    )
    expect(response.body).to include(
      reactivate_classroom_student_path(classroom, inactive_students[1])
    )

    get classroom_members_path(classroom, status: 'all')
    all_rows = Nokogiri::HTML(response.body).css('[data-student-row]')
    expect(all_rows.map { |row| row['data-student-id'].to_i }).to eq(
      [
        active_students[2], active_students[3], active_students[0], active_students[4], active_students[1],
        inactive_students[1], inactive_students[2], inactive_students[0], inactive_students[3]
      ].map(&:id)
    )
    expect(response.body).to include(
      classroom_edit_member_student_names_path(classroom, status: 'all')
    )
  end

  it 'renders an empty inactive filter state' do
    active_student = managed_student(name: '김활동')
    sign_in admin

    get classroom_members_path(classroom, status: 'inactive')

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('비활성 학생이 없습니다.')
    expect(response.body).not_to include(active_student.name)
  end

  it 'does not count an admin as an assigned teacher' do
    sign_in admin

    get classroom_members_path(classroom)

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include('담당 선생님 배정')
    expect(response.body).not_to include('0명 선택됨')
    expect(response.body).not_to include('checked="checked"')
  end

  it 'does not show an admin in the classrooms index preview' do
    classroom
    sign_in admin

    get classrooms_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('담당 선생님 없음')
  end

  it 'rejects a teacher who does not manage the classroom' do
    sign_in teacher

    get classroom_members_path(classroom)

    expect(response).to redirect_to(root_path)
  end

  it 'allows a manager who is not assigned to the classroom' do
    teacher.update!(school_role: 'manager')
    student = managed_student(name: '활성 학생')
    sign_in teacher

    get classroom_members_path(classroom)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(student.name)
  end

  it 'allows a manager assigned as the classroom teacher to manage members' do
    teacher.update!(school_role: 'manager')
    assign_teacher(classroom, teacher)
    student = managed_student(name: '활성 학생')
    sign_in teacher

    get classroom_members_path(classroom)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('구성원 관리')
    expect(response.body).to include(student.name)
  end

  it 'renders the filtered student roster edit modal with Student-scoped fields' do
    assign_teacher(classroom, teacher)
    active_student = managed_student(name: '활성 이름', student_number: 7)
    inactive_student = managed_student(name: '비활성 이름', status: 'inactive')
    active_membership = active_student
    inactive_membership = inactive_student
    sign_in teacher

    get classroom_edit_member_student_names_path(classroom, status: 'inactive'), headers: { 'Turbo-Frame' => 'modal' }

    document = Nokogiri::HTML(response.body)
    form = document.at_css('form#student_names_form')
    active_row = document.at_css("#name_row_student_#{active_membership.id}")
    inactive_row = document.at_css("#name_row_student_#{inactive_membership.id}")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('학생 명단 일괄 편집')
    expect(form['action']).to eq(classroom_member_student_names_path(classroom, status: 'inactive'))
    expect(active_row).to be_nil
    expect(inactive_row).not_to be_nil
    expect(response.body).not_to include(%(name="students[#{active_membership.id}][name]"))
    expect(response.body).to include(%(name="students[#{inactive_membership.id}][name]"))
    expect(response.body).to include(%(name="students[#{inactive_membership.id}][student_number]"))
    expect(response.body).to include(%(name="students[#{inactive_membership.id}][gender]"))
    expect(response.body).to include(%(name="students[#{inactive_membership.id}][avatar_key]"))
    expect(response.body).to include('비활성 이름')
    expect(response.body).not_to include('name="student_pin"')
    expect(response.body).to include('data-controller="student-roster-editor"')
    number_input = document.at_css(%(input[name="students[#{inactive_membership.id}][student_number]"]))
    expect(number_input['value'].to_s).to be_empty
  end

  it 'orders roster edit rows by filter status and roster order' do
    active_two = managed_student(name: '활성 2', student_number: 2)
    active_one = managed_student(name: '활성 1', student_number: 1)
    inactive_one = managed_student(name: '비활성 1', status: 'inactive', student_number: 1)
    inactive_nil = managed_student(name: '비활성 미지정', status: 'inactive')
    sign_in admin

    get classroom_edit_member_student_names_path(classroom, status: 'all')

    rows = Nokogiri::HTML(response.body).css('[data-student-roster-editor-target="row"]')
    expect(rows.map { |row| row['id'] }).to eq(
      [active_one, active_two, inactive_one, inactive_nil].map do |membership|
        "name_row_student_#{membership.id}"
      end
    )
  end

  it 'uses the Student number in the roster editor' do
    student = managed_student(student_number: 7)
    current_membership = student
    sign_in admin

    get classroom_edit_member_student_names_path(classroom, status: 'active')

    input = Nokogiri::HTML(response.body).at_css(
      %(input[name="students[#{current_membership.id}][student_number]"])
    )
    expect(input['value']).to eq('7')
  end

  it 'keeps the selected filter after saving names from the modal' do
    assign_teacher(classroom, teacher)
    active_student = managed_student(name: '활성 저장 전')
    inactive_student = managed_student(name: '비활성 저장 전', status: 'inactive')
    active_membership = active_student
    inactive_membership = inactive_student
    sign_in teacher

    get classroom_members_path(classroom, status: 'inactive')
    inactive_document = Nokogiri::HTML(response.body)
    inactive_edit_link = inactive_document.at_css(%(a[href="#{classroom_edit_member_student_names_path(classroom,
                                                                                                       status: 'inactive')}"]))

    expect(inactive_edit_link['data-turbo-frame']).to eq('modal')

    patch classroom_member_student_names_path(classroom, status: 'inactive'),
          params: {
            students: {
              inactive_membership.id => { name: '비활성 저장 후' }
            }
          },
          headers: { 'ACCEPT' => 'text/vnd.turbo-stream.html' }

    inactive_result = Nokogiri::HTML.fragment(response.body)
    inactive_row = inactive_result.at_css(
      "#member_row_student_#{inactive_membership.id}"
    )

    expect(response.media_type).to eq('text/vnd.turbo-stream.html')
    expect(response.body).to include('target="student-management"', 'target="modal"')
    expect(inactive_result.at_css(%(a[aria-current="page"])).text).to include('비활성')

    expect(inactive_row.text).to include('비활성 저장 후')
    expect(inactive_result.at_css("#member_row_student_#{active_membership.id}")).to be_nil
    expect(active_student.reload.name).to eq('활성 저장 전')

    get classroom_members_path(classroom, status: 'all')
    all_document = Nokogiri::HTML(response.body)
    all_edit_link = all_document.at_css(%(a[href="#{classroom_edit_member_student_names_path(classroom,
                                                                                             status: 'all')}"]))

    expect(all_edit_link['data-turbo-frame']).to eq('modal')

    patch classroom_member_student_names_path(classroom, status: 'all'),
          params: {
            students: {
              active_membership.id => { name: '활성 전체 저장' },
              inactive_membership.id => { name: '비활성 전체 저장' }
            }
          },
          headers: { 'ACCEPT' => 'text/vnd.turbo-stream.html' }

    all_result = Nokogiri::HTML.fragment(response.body)
    active_row = all_result.at_css(
      "#member_row_student_#{active_membership.id}"
    )
    inactive_row = all_result.at_css(
      "#member_row_student_#{inactive_membership.id}"
    )

    expect(all_result.at_css(%(a[aria-current="page"])).text).to include('전체')
    expect(active_row.text).to include('활성 전체 저장')
    expect(inactive_row.text).to include('비활성 전체 저장')
  end

  describe 'PATCH /classrooms/:classroom_id/members/students/name' do
    it 'updates student numbers, names, genders, and avatar keys together' do
      assign_teacher(classroom, teacher)
      first = managed_student(name: '첫 학생', gender: 'boy', avatar_key: 'boy01', student_number: 1)
      second = managed_student(name: '둘 학생', gender: 'girl', avatar_key: 'girl01', student_number: 2)
      first_membership = first
      second_membership = second
      sign_in teacher

      patch classroom_member_student_names_path(classroom, status: 'active'), params: {
        students: {
          first_membership.id => {
            student_number: '3', name: '첫 수정', gender: 'girl', avatar_key: 'girl02',
            role: 'admin', status: 'inactive', student_pin: '9999'
          },
          second_membership.id => {
            student_number: '4', name: '둘 수정', gender: 'boy', avatar_key: 'boy02'
          }
        }
      }

      expect(response).to redirect_to(classroom_members_path(classroom, status: 'active'))
      expect(first_membership.reload.student_number).to eq(3)
      expect(second_membership.reload.student_number).to eq(4)
      expect(first.reload.attributes.values_at('name', 'gender', 'avatar_key')).to eq(
        ['첫 수정', 'girl', 'girl02']
      )
      expect(second.reload.attributes.values_at('name', 'gender', 'avatar_key')).to eq(
        ['둘 수정', 'boy', 'boy02']
      )
      expect(first_membership).to be_active
      expect(first.authenticate_student_pin('1234')).to be_truthy
      expect(first.authenticate_student_pin('9999')).to be_falsey
    end

    it 'preserves a legacy mismatched avatar during an unrelated roster update' do
      student = managed_student(name: '기존 이름', gender: 'boy', avatar_key: 'boy01', student_number: 7)
      student.update_column(:avatar_key, 'girl01')
      membership = student
      sign_in admin

      patch classroom_member_student_names_path(classroom), params: {
        students: {
          membership.id => {
            student_number: '8', name: '수정 이름', gender: 'boy', avatar_key: 'girl01'
          }
        }
      }

      expect(response).to redirect_to(classroom_members_path(classroom))
      expect(membership.reload.student_number).to eq(8)
      expect(student.reload.attributes.values_at('name', 'gender', 'avatar_key')).to eq(
        ['수정 이름', 'boy', 'girl01']
      )
    end

    it 'rejects a manipulated mismatched avatar when gender is unchanged' do
      student = managed_student(name: '기존 이름', gender: 'boy', avatar_key: 'boy01', student_number: 7)
      membership = student
      sign_in admin

      patch classroom_member_student_names_path(classroom), params: {
        students: {
          membership.id => {
            student_number: '8', name: '변경 금지', gender: 'boy', avatar_key: 'girl07'
          }
        }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('성별에 맞는 썸네일을 선택해 주세요.')
      expect(membership.reload.student_number).to eq(7)
      expect(student.reload.attributes.values_at('name', 'gender', 'avatar_key')).to eq(
        ['기존 이름', 'boy', 'boy01']
      )
    end

    it 'keeps a legacy avatar that becomes valid for the changed gender' do
      student = managed_student(gender: 'boy', avatar_key: 'boy01', student_number: 7)
      student.update_column(:avatar_key, 'girl01')
      membership = student
      sign_in admin

      patch classroom_member_student_names_path(classroom), params: {
        students: {
          membership.id => {
            student_number: '7', name: student.name, gender: 'girl', avatar_key: 'girl01'
          }
        }
      }

      expect(response).to redirect_to(classroom_members_path(classroom))
      expect(student.reload.attributes.values_at('gender', 'avatar_key')).to eq(%w[girl girl01])
    end

    it 'swaps two active student numbers without violating the unique index' do
      first = managed_student(name: '1번', student_number: 1)
      second = managed_student(name: '2번', student_number: 2)
      first_membership = first
      second_membership = second
      sign_in admin

      patch classroom_member_student_names_path(classroom), params: {
        students: {
          first_membership.id => { student_number: '2', name: first.name },
          second_membership.id => { student_number: '1', name: second.name }
        }
      }

      expect(response).to redirect_to(classroom_members_path(classroom))
      expect(first_membership.reload.student_number).to eq(2)
      expect(second_membership.reload.student_number).to eq(1)
    end

    it 'supports a three-student number cycle' do
      memberships = [1, 2, 3].map do |number|
        managed_student(name: "#{number}번", student_number: number)
      end
      sign_in admin

      patch classroom_member_student_names_path(classroom), params: {
        students: {
          memberships[0].id => { student_number: '2', name: memberships[0].name },
          memberships[1].id => { student_number: '3', name: memberships[1].name },
          memberships[2].id => { student_number: '1', name: memberships[2].name }
        }
      }

      expect(memberships.map { |membership| membership.reload.student_number }).to eq([2, 3, 1])
    end

    it 'allows clearing a number and editing a legacy student without assigning gender' do
      numbered = managed_student(name: '번호 학생', gender: 'boy', avatar_key: 'boy01', student_number: 7)
      legacy = managed_student(name: '레거시 학생', gender: nil, avatar_key: nil)
      numbered_membership = numbered
      legacy_membership = legacy
      sign_in admin

      patch classroom_member_student_names_path(classroom), params: {
        students: {
          numbered_membership.id => { student_number: '', name: numbered.name },
          legacy_membership.id => { student_number: '', name: '레거시 수정' }
        }
      }

      expect(numbered_membership.reload.student_number).to be_nil
      expect(legacy_membership.reload.student_number).to be_nil
      expect(legacy.reload.name).to eq('레거시 수정')
      expect(legacy.gender).to be_nil
    end

    it 'rejects invalid raw student numbers and preserves input while rolling back other rows' do
      first = managed_student(name: '원래 첫째', student_number: 1)
      second = managed_student(name: '원래 둘째', student_number: 2)
      first_membership = first
      second_membership = second
      sign_in admin

      %w[0 -1 1.5 abc].each do |invalid_number|
        patch classroom_member_student_names_path(classroom), params: {
          students: {
            first_membership.id => { student_number: invalid_number, name: '저장 금지' },
            second_membership.id => { student_number: '3', name: '함께 저장 금지' }
          }
        }

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include('출석번호는 1 이상의 정수여야 합니다.')
        expect(response.body).to include(%(value="#{invalid_number}"))
        expect(first.reload.name).to eq('원래 첫째')
        expect(second.reload.name).to eq('원래 둘째')
        expect(first_membership.reload.student_number).to eq(1)
        expect(second_membership.reload.student_number).to eq(2)
      end
    end

    it 'rejects duplicate final active numbers for submitted and unsubmitted students' do
      students = 3.times.map do |index|
        managed_student(name: "학생 #{index}", student_number: index + 1)
      end
      memberships = students
      sign_in admin

      patch classroom_member_student_names_path(classroom), params: {
        students: {
          memberships[0].id => { student_number: '2', name: students[0].name },
          memberships[1].id => { student_number: '2', name: students[1].name }
        }
      }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body.scan('2번 출석번호가 중복되었습니다.').size).to be >= 2

      patch classroom_member_student_names_path(classroom), params: {
        students: {
          memberships[0].id => { student_number: '3', name: '변경 금지' }
        }
      }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('3번 출석번호가 중복되었습니다.')
      expect(students[0].reload.name).to eq('학생 0')
      expect(memberships.map { |membership| membership.reload.student_number }).to eq([1, 2, 3])
    end

    it 'allows inactive students to share numbers with active and inactive students' do
      active = managed_student(student_number: 7)
      active_membership = active
      inactive_students = 2.times.map { managed_student(status: 'inactive', student_number: 8) }
      inactive_memberships = inactive_students
      sign_in admin

      patch classroom_member_student_names_path(classroom, status: 'inactive'), params: {
        students: inactive_memberships.each_with_object({}) do |membership, rows|
          rows[membership.id] = { student_number: '7', name: membership.name }
        end
      }

      expect(response).to redirect_to(classroom_members_path(classroom, status: 'inactive'))
      expect(inactive_memberships.map { |membership| membership.reload.student_number }).to eq([7, 7])
      expect(active_membership.reload.student_number).to eq(7)
    end

    it 'rolls back every field when a Student row is invalid' do
      first = managed_student(name: '첫 원본', gender: 'boy', avatar_key: 'boy01', student_number: 1)
      second = managed_student(name: '둘 원본', gender: 'girl', avatar_key: 'girl01', student_number: 2)
      first_membership = first
      second_membership = second
      sign_in admin

      patch classroom_member_student_names_path(classroom), params: {
        students: {
          first_membership.id => {
            student_number: '3', name: '첫 변경', gender: 'girl', avatar_key: 'girl02'
          },
          second_membership.id => {
            student_number: '4', name: '', gender: 'boy', avatar_key: 'girl02'
          }
        }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('성별에 맞는 썸네일을 선택해 주세요.')
      expect(first.reload.attributes.values_at('name', 'gender', 'avatar_key')).to eq(
        ['첫 원본', 'boy', 'boy01']
      )
      expect(first_membership.reload.student_number).to eq(1)
      expect(second_membership.reload.student_number).to eq(2)
    end

    it 'rejects an invalid submitted gender' do
      student = managed_student(gender: 'boy', avatar_key: 'boy01', student_number: 1)
      membership = student
      sign_in admin

      patch classroom_member_student_names_path(classroom), params: {
        students: {
          membership.id => {
            student_number: '1', name: student.name, gender: 'other', avatar_key: 'boy01'
          }
        }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('성별을 확인해 주세요.')
      expect(student.reload.gender).to eq('boy')
    end

    it 'rolls back temporary number clears when a later Student save raises' do
      students = 2.times.map do |index|
        managed_student(name: "원본 #{index}", student_number: index + 1)
      end
      memberships = students
      calls = 0
      allow_any_instance_of(Student).to receive(:save!).and_wrap_original do |method|
        calls += 1
        if calls == 2
          method.receiver.errors.add(:base, 'student failed')
          raise ActiveRecord::RecordInvalid.new(method.receiver)
        end

        method.call
      end
      sign_in admin

      patch classroom_member_student_names_path(classroom), params: {
        students: {
          memberships[0].id => { student_number: '2', name: '변경 0' },
          memberships[1].id => { student_number: '1', name: '변경 1' }
        }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(students.map { |student| student.reload.name }).to eq(['원본 0', '원본 1'])
      expect(memberships.map { |membership| membership.reload.student_number }).to eq([1, 2])
    end

    it 'handles a database number race without leaving temporary nil values' do
      students = 2.times.map do |index|
        managed_student(name: "학생 #{index}", student_number: index + 1)
      end
      memberships = students
      allow_any_instance_of(Student).to receive(:save!)
        .and_raise(ActiveRecord::RecordNotUnique)
      sign_in admin

      patch classroom_member_student_names_path(classroom), params: {
        students: {
          memberships[0].id => { student_number: '2', name: students[0].name },
          memberships[1].id => { student_number: '1', name: students[1].name }
        }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('출석번호가 중복되었습니다.')
      expect(memberships.map { |membership| membership.reload.student_number }).to eq([1, 2])
    end

    it 'lets a classroom teacher update active student names' do
      assign_teacher(classroom, teacher)
      student = managed_student(name: '이전 이름')
      membership = student
      sign_in teacher

      patch classroom_member_student_names_path(classroom), params: {
        students: {
          membership.id => { name: '새 이름' }
        }
      }

      expect(response).to redirect_to(classroom_members_path(classroom))
      expect(flash[:notice]).to eq(I18n.t('students.members.update_names.success'))
      expect(student.reload.name).to eq('새 이름')
    end

    it 'lets a classroom teacher update inactive student names' do
      assign_teacher(classroom, teacher)
      student = managed_student(name: '쉬는 학생', status: 'inactive')
      membership = student
      sign_in teacher

      patch classroom_member_student_names_path(classroom, status: 'inactive'), params: {
        students: {
          membership.id => { name: '돌아올 학생' }
        }
      }

      expect(response).to redirect_to(
        classroom_members_path(classroom, status: 'inactive')
      )
      expect(student.reload.name).to eq('돌아올 학생')
    end

    it 'lets an admin update student names' do
      student = managed_student(name: '관리 전')
      membership = student
      sign_in admin

      patch classroom_member_student_names_path(classroom), params: {
        students: {
          membership.id => { name: '관리 후' }
        }
      }

      expect(response).to redirect_to(classroom_members_path(classroom))
      expect(student.reload.name).to eq('관리 후')
    end

    it 'rejects a teacher who does not manage the classroom' do
      student = managed_student(name: '유지')
      membership = student
      sign_in teacher

      patch classroom_member_student_names_path(classroom), params: {
        students: {
          membership.id => { name: '변경 시도' }
        }
      }

      expect(response).to redirect_to(root_path)
      expect(student.reload.name).to eq('유지')
    end

    it 'allows a manager who is not assigned to the classroom' do
      teacher.update!(school_role: 'manager')
      student = managed_student(name: '유지')
      membership = student
      sign_in teacher

      patch classroom_member_student_names_path(classroom), params: {
        students: {
          membership.id => { name: '변경 시도' }
        }
      }

      expect(response).to redirect_to(classroom_members_path(classroom))
      expect(student.reload.name).to eq('변경 시도')
    end

    it 'fails when a membership outside the classroom is submitted' do
      assign_teacher(classroom, teacher)
      student = managed_student(name: '내 학생')
      membership = student
      other_student = managed_student(classroom: create(:classroom), name: '다른 학생')
      other_membership = other_student
      sign_in teacher

      patch classroom_member_student_names_path(classroom), params: {
        students: {
          membership.id => { name: '변경 실패' },
          other_membership.id => { name: '변경되면 안 됨' }
        }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(I18n.t('students.members.update_names.invalid_membership'))
      expect(student.reload.name).to eq('내 학생')
      expect(other_student.reload.name).to eq('다른 학생')
    end

    it 'rejects a membership outside the selected status filter' do
      inactive_student = managed_student(name: '비활성 유지', status: 'inactive')
      inactive_membership = inactive_student
      sign_in admin

      patch classroom_member_student_names_path(classroom, status: 'active'), params: {
        students: {
          inactive_membership.id => { name: '변경 금지' }
        }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(I18n.t('students.members.update_names.invalid_membership'))
      expect(inactive_student.reload.name).to eq('비활성 유지')
    end

    it 'rolls back all changes and shows row errors when any name is invalid' do
      assign_teacher(classroom, teacher)
      valid_student = managed_student(name: '유효 학생')
      invalid_student = managed_student(name: '무효 학생')
      valid_membership = valid_student
      invalid_membership = invalid_student
      sign_in teacher

      patch classroom_member_student_names_path(classroom, status: 'active'), params: {
        students: {
          valid_membership.id => { name: '저장되면 안 됨' },
          invalid_membership.id => { name: '' }
        }
      }

      document = Nokogiri::HTML(response.body)
      form = document.at_css('form#student_names_form')

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('id="modal"')
      expect(form['action']).to eq(classroom_member_student_names_path(classroom, status: 'active'))
      expect(response.body).to include('학생 명단을 수정하지 못했습니다')
      expect(response.body).to include('저장되면 안 됨')
      expect(valid_student.reload.name).to eq('유효 학생')
      expect(invalid_student.reload.name).to eq('무효 학생')
    end
  end

  describe 'student PIN reset' do
    let(:turbo_headers) { { 'ACCEPT' => 'text/vnd.turbo-stream.html' } }

    it 'shows the PIN reset modal form' do
      assign_teacher(classroom, teacher)
      sign_in teacher

      get classroom_edit_member_student_pin_path(classroom)

      document = Nokogiri::HTML(response.body)
      pin_input = document.at_css('input[name="student_pin"]')

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('활성 학생 PIN 재설정')
      expect(response.body).to include('새 PIN')
      expect(response.body).to include('PIN 재설정 적용')
      expect(response.body).to include(classroom_member_student_pin_path(classroom))
      expect(pin_input).not_to be_nil
      expect(pin_input['type']).to eq('password')
      expect(pin_input['value'].to_s).to be_empty
      expect(response.body).to include('type="submit"')
      expect(response.body).to include('data-testid="active-student-pin-reset-submit"')
    end

    it 'lets a classroom teacher reset active student PINs without changing inactive students' do
      assign_teacher(classroom, teacher)
      active_student = managed_student(student_pin: '1234')
      second_active_student = managed_student(student_pin: '2345')
      inactive_student = managed_student(student_pin: '3456', status: 'inactive')
      sign_in teacher

      patch classroom_member_student_pin_path(classroom),
            params: { student_pin: '4321' },
            headers: turbo_headers

      expect(response.media_type).to eq('text/vnd.turbo-stream.html')
      expect(response.body).to include('target="modal"')
      expect(response.body).to include('target="flash"')
      expect(flash[:notice]).to eq(I18n.t('students.members.pin_reset.success', count: 2))
      expect(active_student.reload.authenticate_student_pin('4321')).to be_truthy
      expect(active_student.authenticate_student_pin('1234')).to be_falsey
      expect(second_active_student.reload.authenticate_student_pin('4321')).to be_truthy
      expect(inactive_student.reload.authenticate_student_pin('3456')).to be_truthy
      expect(inactive_student.authenticate_student_pin('4321')).to be_falsey
    end

    it 'lets an admin reset active student PINs' do
      active_student = managed_student(student_pin: '1234')
      sign_in admin

      patch classroom_member_student_pin_path(classroom), params: { student_pin: '6789' }

      expect(response).to redirect_to(classroom_members_path(classroom))
      expect(active_student.reload.authenticate_student_pin('6789')).to be_truthy
    end

    it 'rejects a teacher who does not manage the classroom' do
      active_student = managed_student(student_pin: '1234')
      sign_in teacher

      patch classroom_member_student_pin_path(classroom), params: { student_pin: '4321' }

      expect(response).to redirect_to(root_path)
      expect(active_student.reload.authenticate_student_pin('1234')).to be_truthy
    end

    it 'keeps the modal open when PIN is blank' do
      assign_teacher(classroom, teacher)
      active_student = managed_student(student_pin: '1234')
      sign_in teacher

      patch classroom_member_student_pin_path(classroom),
            params: { student_pin: '' },
            headers: turbo_headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(I18n.t('students.members.pin_reset.blank'))
      expect(response.body).to include('id="modal"')
      expect(active_student.reload.authenticate_student_pin('1234')).to be_truthy
    end

    it 'keeps the modal open when PIN is not four digits' do
      assign_teacher(classroom, teacher)
      active_student = managed_student(student_pin: '1234')
      sign_in teacher

      patch classroom_member_student_pin_path(classroom),
            params: { student_pin: '12ab' },
            headers: turbo_headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(I18n.t('students.members.pin_reset.invalid'))
      expect(active_student.reload.authenticate_student_pin('1234')).to be_truthy
    end
  end
end
