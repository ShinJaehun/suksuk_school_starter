require 'rails_helper'

RSpec.describe 'Classroom organization settings', type: :request do
  let(:admin) { create(:user, :admin) }
  let(:school) { create(:school, name: '새싹초등학교') }
  let!(:school_year) { create(:school_year, :active, school: school) }
  let(:teacher) { create(:user, :teacher, :active_annual_teacher, annual_school: school) }

  def create_annual_manager(school:)
    create(:user, :teacher, :active_annual_teacher,
           annual_school: school,
           annual_school_role: 'manager')
  end

  it 'shows school and grade fields only to an admin' do
    sign_in admin
    get new_classroom_path

    expect(response.body).to include('name="classroom[school_id]"')
    expect(response.body).to include('name="classroom[grade]"')
    expect(response.body).to include('학교 선택')
    expect(response.body).to include('학년 선택')

    sign_in teacher
    get new_classroom_path

    expect(response.body).not_to include('name="classroom[school_id]"')
    expect(response.body).not_to include('name="classroom[grade]"')
  end

  it 'shows a manager their whole school classrooms without other schools' do
    manager = create_annual_manager(school: school)
    assigned_classroom = create(:classroom, annual_school: school, class_label: '담당 학급')
    unassigned_classroom = create(:classroom, annual_school: school, class_label: '미담당 학급')
    create(:classroom, annual_school: create(:school), class_label: '다른 학교 학급')
    assign_teacher(assigned_classroom, manager)
    sign_in manager

    get classrooms_path

    expect(response.body).to include(
      '학교 전체 학급',
      '담당 학급',
      '미담당 학급',
      new_classroom_path
    )
    expect(response.body).to include(classroom_path(assigned_classroom), classroom_path(unassigned_classroom))
    expect(response.body).to include(
      classroom_members_path(assigned_classroom),
      edit_classroom_path(assigned_classroom),
      edit_classroom_path(unassigned_classroom)
    )
    expect(response.body).not_to include(classroom_members_path(unassigned_classroom))
    expect(response.body).to include(school_path(school))
    expect(response.body).not_to include('다른 학교 학급')
    expect(response.body).to include(teachers_path)
    expect(response.body).not_to include('학교 운영 정보')
    expect(response.body).not_to include('선생님 목록')
    expect(response.body).to include(%(href="#{classrooms_path}"))
    expect(response.body).not_to include('id="classroom-school-filter"')
  end

  it 'shows a school filter to an admin while keeping the full classroom list by default' do
    school.update!(color_key: 'emerald')
    other_school = create(:school, name: '나래초등학교')
    classroom = create(:classroom, annual_school: school, class_label: '새싹 학급')
    other_classroom = create(:classroom, annual_school: other_school, class_label: '나래 학급')
    sign_in admin

    get classrooms_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('id="classroom-school-filter"')
    expect(response.body).to include('name="school_id"')
    expect(response.body).to include('전체 학교')
    expect(response.body).to include(school.name, other_school.name)
    expect(response.body).to include(classroom.class_label, other_classroom.class_label)
    expect(response.body).to include(classroom_path(classroom), classroom_path(other_classroom))
    expect(response.body).not_to include(new_admin_school_path)

    document = Nokogiri::HTML(response.body)
    classroom_card = document.at_xpath("//h2[contains(normalize-space(), '#{classroom.class_label}')]/ancestor::article[1]")

    expect(classroom_card['class']).to include('border-emerald-200', 'bg-emerald-50/70')
    expect(classroom_card.at_css('.bg-emerald-500')).to be_present
  end

  it 'shows classroom status without lifecycle actions on the index' do
    active_classroom = create(:classroom, annual_school: school, class_label: '활성 학급')
    inactive_classroom = create(:classroom, annual_school: school, class_label: '비활성 학급', active: false)
    sign_in admin

    get classrooms_path

    document = Nokogiri::HTML(response.body)
    active_card = document.at_xpath(
      "//article[.//a[@href='#{classroom_path(active_classroom)}']]"
    )
    inactive_card = document.at_xpath(
      "//article[.//a[@href='#{classroom_path(inactive_classroom)}']]"
    )
    expect(active_card.text).to include(I18n.t('classroom_status.active'))
    expect(active_card.to_html).not_to include(
      deactivate_classroom_path(active_classroom),
      reactivate_classroom_path(active_classroom)
    )
    expect(inactive_card.text).to include(I18n.t('classroom_status.inactive'))
    expect(inactive_card.to_html).not_to include(
      deactivate_classroom_path(inactive_classroom),
      reactivate_classroom_path(inactive_classroom),
      classroom_members_path(inactive_classroom)
    )
    expect(inactive_card.to_html).to include(edit_classroom_path(inactive_classroom))
  end

  it 'shows structure and deactivate controls on an active classroom edit page' do
    classroom = create(:classroom, annual_school: school)
    sign_in admin

    get edit_classroom_path(classroom)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('name="classroom[class_label]"', deactivate_classroom_path(classroom))
    expect(response.body).not_to include(reactivate_classroom_path(classroom))
  end

  it 'lets a manager enter an inactive classroom edit page only to reactivate it' do
    manager = create_annual_manager(school: school)
    classroom = create(:classroom, annual_school: school, active: false)
    sign_in manager

    get edit_classroom_path(classroom)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(reactivate_classroom_path(classroom))
    expect(response.body).not_to include('name="classroom[class_label]"', deactivate_classroom_path(classroom))
  end

  it 'rejects structure updates for an inactive classroom' do
    classroom = create(:classroom, annual_school: school, active: false, class_label: '잠긴 학급')
    sign_in admin

    patch classroom_path(classroom), params: {
      classroom: classroom_update_params(classroom).merge(class_label: '변경되면 안 됨')
    }

    expect(response).to redirect_to(root_path)
    expect(classroom.reload.class_label).to eq('잠긴 학급')
  end

  it 'filters classrooms by selected school for an admin' do
    other_school = create(:school, name: '나래초등학교')
    classroom = create(:classroom, annual_school: school, class_label: '새싹 학급')
    other_classroom = create(:classroom, annual_school: other_school, class_label: '나래 학급')
    teacher = create(:user, :teacher, :active_annual_teacher,
                     annual_school: school,
                     name: '새싹 선생님')
    other_teacher = create(:user, :teacher, :active_annual_teacher,
                           annual_school: other_school,
                           name: '나래 선생님')
    student = create(:student, classroom: classroom, name: '새싹 학생')
    other_student = create(:student, classroom: other_classroom, name: '나래 학생')
    assign_teacher(classroom, teacher)
    assign_teacher(other_classroom, other_teacher)
    sign_in admin

    get classrooms_path, params: { school_id: school.id }

    expect(response).to have_http_status(:ok)
    expect(response.body).to match(%r{<option selected="selected" value="#{school.id}">#{school.name}</option>})
    expect(response.body).to include(classroom.class_label, classroom_path(classroom), teacher.name, '학생 1명')
    expect(response.body).not_to include(other_classroom.class_label)
    expect(response.body).not_to include(classroom_path(other_classroom))
    expect(response.body).not_to include(other_teacher.name)
    expect(response.body).not_to include(other_student.name)
  end

  it 'filters classrooms by grade within the selected school for an admin' do
    other_school = create(:school, name: '나래초등학교')
    selected = create(:classroom, annual_school: school, grade: 4, class_label: '선택 학급')
    other_grade = create(:classroom, annual_school: school, grade: 5, class_label: '다른 학년 학급')
    other_school_classroom = create(:classroom, annual_school: other_school, grade: 4, class_label: '다른 학교 학급')
    sign_in admin

    get classrooms_path, params: { school_id: school.id, grade: 4 }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(selected.class_label)
    expect(response.body).not_to include(other_grade.class_label, other_school_classroom.class_label)
    expect(response.body).to match(%r{<option selected="selected" value="#{school.id}">#{school.name}</option>})
    expect(response.body).to match(%r{<option selected="selected" value="4">4학년</option>})
  end

  it 'filters a manager within their school classrooms' do
    manager = create_annual_manager(school: school)
    selected = create(:classroom, annual_school: school, grade: 4, class_label: '학교 4학년')
    other_grade = create(:classroom, annual_school: school, grade: 5, class_label: '학교 5학년')
    outside = create(:classroom, annual_school: create(:school), grade: 4, class_label: '외부 4학년')
    sign_in manager

    get classrooms_path, params: { grade: 4 }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(selected.class_label)
    expect(response.body).not_to include(other_grade.class_label, outside.class_label)
  end

  it 'treats blank or invalid grades as the full authorized list' do
    grade_four = create(:classroom, annual_school: school, grade: 4, class_label: '전체 4학년')
    grade_five = create(:classroom, annual_school: school, grade: 5, class_label: '전체 5학년')
    sign_in admin

    ['', '0', '7', '4학년', 'missing'].each do |grade|
      get classrooms_path, params: { grade: grade }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(grade_four.class_label, grade_five.class_label)
    end
  end

  it 'shows the normal empty state when the selected grade has no classrooms' do
    create(:classroom, annual_school: school, grade: 4)
    sign_in admin

    get classrooms_path, params: { grade: 6 }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t('classrooms.index.empty'))
  end

  it 'counts and previews only active students on the classrooms index' do
    classroom = create(:classroom, annual_school: school, class_label: '활성 기준 학급')
    active_student = create(:student, classroom: classroom, name: '활성 미리보기 학생', avatar_key: 'boy01')
    inactive_student = create(:student, classroom: classroom, name: '비활성 제외 학생', avatar_key: 'girl01', active: false)
    assign_teacher(classroom, teacher)
    sign_in admin

    get classrooms_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('활성 기준 학급')
    expect(response.body).to include('학생 1명')
    expect(response.body).to include('활성 미리보기 학생 avatar')
    expect(response.body).not_to include('학생 2명')
    expect(response.body).not_to include('비활성 제외 학생')
    expect(response.body).not_to include('비활성 제외 학생 avatar')
  end

  it 'shows the single assigned teacher on the classrooms index' do
    classroom = create(:classroom, annual_school: school, class_label: '운영 교사 학급')
    assigned_teacher = create(:user, :teacher, :active_annual_teacher,
                              annual_school: school, name: '활성 담당 교사')
    assign_teacher(classroom, assigned_teacher)
    sign_in admin

    get classrooms_path

    card = Nokogiri::HTML(response.body)
                   .at_xpath("//h2[contains(normalize-space(), '#{classroom.class_label}')]/ancestor::article[1]")
    expect(card.text).to include(assigned_teacher.name)
  end

  it 'does not show a teacher released by deactivation on the classroom page' do
    classroom = create(:classroom, annual_school: school)
    teacher = create(:user, :teacher, :active_annual_teacher,
                     annual_school: school, name: '비활성 담임')
    assign_teacher(classroom, teacher)
    teacher.update!(active: false)
    sign_in admin

    get classroom_path(classroom)

    expect(classroom.reload.teacher).to be_nil
    expect(response.body).not_to include(teacher.name)
  end

  it 'hides inactive-school classrooms from index while keeping admin read access' do
    inactive_school = create(:school)
    classroom = create(:classroom, annual_school: inactive_school, class_label: '중단된 학교 교실')
    assigned_teacher = create(:user, :teacher, :active_annual_teacher, annual_school: inactive_school)
    assign_teacher(classroom, assigned_teacher)
    inactive_school.update!(active: false)
    sign_in admin

    get classrooms_path
    expect(response.body).not_to include(classroom.class_label)

    get classroom_path(classroom)
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include(classroom_members_path(classroom))

    inactive_school.update!(active: true)
    sign_in assigned_teacher
    inactive_school.update!(active: false)
    get classroom_path(classroom)
    expect(response).to redirect_to(school_teacher_login_path(inactive_school))

    inactive_school.update!(active: true)
    sign_in assigned_teacher

    get classroom_path(classroom)
    expect(response).to have_http_status(:ok)
  end

  it 'rejects creating or moving a classroom into an inactive school' do
    inactive_school = create(:school, active: false)
    classroom = create(:classroom, annual_school: school)
    sign_in admin

    expect do
      post classrooms_path, params: {
        classroom: { class_label: '금지된 교실', school_id: inactive_school.id, grade: 1 }
      }
    end.not_to change(Classroom, :count)
    expect(response).to have_http_status(:unprocessable_content)

    patch classroom_path(classroom), params: {
      classroom: classroom_update_params(classroom).merge(school_id: inactive_school.id)
    }
    expect(response).to have_http_status(:unprocessable_content)
    expect(classroom.reload.school_year.school).to eq(school)
  end

  it 'fails closed for an invalid admin classroom School context' do
    sign_in admin

    get classrooms_path, params: { school_id: 'missing' }

    expect(response).to have_http_status(:not_found)
  end

  it 'allows a manager to show an unassigned classroom in their school' do
    manager = create_annual_manager(school: school)
    classroom = create(:classroom, annual_school: school)
    sign_in manager

    get classroom_path(classroom)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('교실 설정')
    expect(response.body).not_to include('오늘의 칭찬왕')
    expect(response.body).not_to include('학생 로그인')
    expect(response.body).not_to include(classroom_members_path(classroom))
  end

  it "rejects a manager showing another school's classroom" do
    manager = create_annual_manager(school: school)
    classroom = create(:classroom, annual_school: create(:school))
    sign_in manager

    get classroom_path(classroom)

    expect(response).to redirect_to(root_path)
  end

  it 'allows an admin to create a classroom with a school and grade' do
    sign_in admin

    post classrooms_path, params: {
      classroom: {
        class_label: '1',
        school_id: school.id,
        grade: 1
      }
    }

    classroom = Classroom.find_by!(class_label: '1')
    expect(response).to redirect_to(classroom_path(classroom))
    expect(classroom.school_year.school).to eq(school)
    expect(classroom.grade).to eq(1)
  end

  it 'rejects admin classroom creation without a school' do
    sign_in admin

    expect do
      post classrooms_path, params: {
        classroom: { class_label: '학교 없는 학급', school_id: '', grade: 1 }
      }
    end.not_to change(Classroom, :count)

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include('학교')
    expect(response.body).to include('name="classroom[school_id]"')
  end

  it 'rejects admin classroom creation without a grade' do
    sign_in admin

    expect do
      post classrooms_path, params: {
        classroom: { class_label: '학년 없는 학급', school_id: school.id, grade: '' }
      }
    end.not_to change(Classroom, :count)

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include('학년')
    expect(response.body).to include('name="classroom[grade]"')
  end

  it 'rejects admin classroom creation with an out-of-range grade' do
    sign_in admin

    expect do
      post classrooms_path, params: {
        classroom: { class_label: '잘못된 학년', school_id: school.id, grade: 7 }
      }
    end.not_to change(Classroom, :count)

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include('학년')
  end

  it 'allows a manager to create a classroom fixed to their school' do
    manager = create_annual_manager(school: school)
    other_school = create(:school)
    sign_in manager

    post classrooms_path, params: {
      classroom: {
        class_label: '관리자 생성 학급',
        school_id: other_school.id,
        grade: 2
      }
    }

    classroom = Classroom.find_by!(class_label: '관리자 생성 학급')
    expect(response).to redirect_to(classroom_path(classroom))
    expect(classroom.school_year.school).to eq(school)
    expect(classroom.grade).to eq(2)
    expect(classroom.teacher).to be_nil
  end

  it 'rejects manager classroom creation without a grade' do
    manager = create_annual_manager(school: school)
    sign_in manager

    expect do
      post classrooms_path, params: {
        classroom: { class_label: '학년 없는 관리자 학급', grade: '' }
      }
    end.not_to change(Classroom, :count)

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include('학년')
  end

  it 'rejects manager classroom creation with an out-of-range grade' do
    manager = create_annual_manager(school: school)
    sign_in manager

    expect do
      post classrooms_path, params: {
        classroom: { class_label: '잘못된 관리자 학년', grade: 0 }
      }
    end.not_to change(Classroom, :count)

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include('학년')
  end

  it 'rejects classroom creation by a regular teacher' do
    sign_in teacher

    expect do
      post classrooms_path, params: {
        classroom: {
          class_label: '생성되면 안 되는 학급'
        }
      }
    end.not_to change(Classroom, :count)

    expect(response).to redirect_to(root_path)
  end

  it 'allows an admin to change an existing classroom grade' do
    classroom = create(:classroom, annual_school: school, grade: 2)
    sign_in admin

    patch classroom_path(classroom), params: {
      classroom: classroom_update_params(classroom).merge(grade: 6)
    }

    expect(response).to redirect_to(classroom_path(classroom))
    expect(classroom.reload).to have_attributes(school_year: school.school_years.active.first, grade: 6)
  end

  it 'rejects an admin school change and keeps the full update unchanged' do
    original_school = create(:school)
    target_school = create(:school)
    classroom = create(:classroom, annual_school: original_school, class_label: '기존 학급', grade: 2)
    sign_in admin

    patch classroom_path(classroom), params: {
      classroom: classroom_update_params(classroom).merge(
        class_label: '변경되면 안 됨',
        school_id: target_school.id,
        grade: 5
      )
    }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include('생성된 교실의 소속 학교는 변경할 수 없습니다.')
    expect(classroom.reload).to have_attributes(class_label: '기존 학급',
                                                school_year: original_school.school_years.active.first, grade: 2)
  end

  it 'allows a manager to update basic classroom fields in their school' do
    manager = create_annual_manager(school: school)
    classroom = create(:classroom, annual_school: school, class_label: '기존 학급', grade: 1)
    sign_in manager

    patch classroom_path(classroom), params: {
      classroom: classroom_update_params(classroom).merge(class_label: '변경 학급', grade: 5)
    }

    expect(response).to redirect_to(classroom_path(classroom))
    expect(classroom.reload).to have_attributes(class_label: '변경 학급', grade: 5,
                                                school_year: school.school_years.active.first)
  end

  it 'prevents a manager from deleting a classroom in their school' do
    manager = create_annual_manager(school: school)
    classroom = create(:classroom, annual_school: school)
    sign_in manager

    expect do
      delete classroom_path(classroom)
    end.not_to change(Classroom, :count)

    expect(response).to redirect_to(root_path)
  end

  it 'prevents a manager from moving a classroom to another school' do
    manager = create_annual_manager(school: school)
    other_school = create(:school)
    classroom = create(:classroom, annual_school: school, class_label: '기존 학급', grade: 1)
    sign_in manager

    patch classroom_path(classroom), params: {
      classroom: classroom_update_params(classroom).merge(class_label: '변경되면 안 됨', school_id: other_school.id, grade: 6)
    }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include('생성된 교실의 소속 학교는 변경할 수 없습니다.')
    expect(classroom.reload).to have_attributes(class_label: '기존 학급', grade: 1,
                                                school_year: school.school_years.active.first)
  end

  it 'rejects a blank grade submitted by a manager' do
    manager = create_annual_manager(school: school)
    classroom = create(:classroom, annual_school: school, grade: 3)
    sign_in manager

    patch classroom_path(classroom), params: {
      classroom: classroom_update_params(classroom).merge(grade: '')
    }

    expect(response).to have_http_status(:unprocessable_content)
    expect(classroom.reload.grade).to eq(3)
    expect(response.body).to include('학년')
  end

  it 'rejects an out-of-range grade submitted by a manager' do
    manager = create_annual_manager(school: school)
    classroom = create(:classroom, annual_school: school, grade: 3)
    sign_in manager

    patch classroom_path(classroom), params: {
      classroom: classroom_update_params(classroom).merge(grade: 7)
    }

    expect(response).to have_http_status(:unprocessable_content)
    expect(classroom.reload.grade).to eq(3)
    expect(response.body).to include('학년')
  end

  it 'rejects manager updates outside their school' do
    manager = create_annual_manager(school: school)
    classroom = create(:classroom, annual_school: create(:school), class_label: '다른 학교 학급')
    sign_in manager

    patch classroom_path(classroom), params: {
      classroom: classroom_update_params(classroom).merge(class_label: '변경되면 안 됨')
    }

    expect(response).to redirect_to(root_path)
    expect(classroom.reload.class_label).to eq('다른 학교 학급')
  end

  it 'keeps classroom identification while removing school and teacher management sections' do
    classroom = create(:classroom, class_label: '지정', annual_school: school, grade: 2)
    homeroom = create(:user, :teacher, :active_annual_teacher,
                      annual_school: school,
                      name: '담당 선생님')
    assign_teacher(classroom, homeroom)
    sign_in admin

    get classrooms_path

    document = Nokogiri::HTML(response.body)
    classroom_card = document.at_xpath("//h2[normalize-space()='2학년 지정반']/ancestor::article[1]")
    action_paths = classroom_card.css('a').map { |link| link['href'] }

    expect(classroom_card.text).to include(school.name, '2학년 지정반', '담당 선생님')
    expect(classroom_card.at_css('p').text).to include(school.name)
    expect(action_paths).to include(
      classroom_path(classroom),
      classroom_members_path(classroom),
      edit_classroom_path(classroom)
    )
    expect(classroom_card.at_css(%(a[href="#{classroom_members_path(classroom)}"]))['class']).to include(
      'border-indigo-300',
      'bg-indigo-50',
      'text-indigo-700'
    )
    expect(classroom_card.at_css(%(a[href="#{edit_classroom_path(classroom)}"])).text).to include('교실 설정')
    expect(response.body).not_to include(new_teacher_path)
    expect(response.body).not_to include(edit_teacher_path(homeroom))
    expect(response.body).not_to include(new_admin_school_path)
    expect(response.body).not_to include('선생님 목록')
    expect(response.body).not_to include('학교 운영 정보')
  end

  it 'rejects a grade outside the elementary school range' do
    classroom = create(:classroom, annual_school: school, grade: 3)
    sign_in admin

    patch classroom_path(classroom), params: {
      classroom: classroom_update_params(classroom).merge(grade: 7)
    }

    expect(response).to have_http_status(:unprocessable_content)
    expect(classroom.reload.grade).to eq(3)
    expect(response.body).to include('학년')
  end

  it 'rejects removing the grade from an existing classroom' do
    classroom = create(:classroom, annual_school: school, grade: 3)
    sign_in admin

    patch classroom_path(classroom), params: {
      classroom: classroom_update_params(classroom).merge(grade: '')
    }

    expect(response).to have_http_status(:unprocessable_content)
    expect(classroom.reload.grade).to eq(3)
    expect(response.body).to include('학년')
  end

  it 'safely rejects a school id that does not exist' do
    classroom = create(:classroom, annual_school: school, grade: 3)
    sign_in admin

    patch classroom_path(classroom), params: {
      classroom: classroom_update_params(classroom).merge(school_id: School.maximum(:id).to_i + 10_000)
    }

    expect(response).to have_http_status(:unprocessable_content)
    expect(classroom.reload.school_year.school).to eq(school)
    expect(response.body).to include('생성된 교실의 소속 학교는 변경할 수 없습니다.')
  end

  it 'rejects removing the school from an existing classroom' do
    classroom = create(:classroom, annual_school: school, grade: 3)
    sign_in admin

    patch classroom_path(classroom), params: {
      classroom: classroom_update_params(classroom).merge(school_id: '')
    }

    expect(response).to have_http_status(:unprocessable_content)
    expect(classroom.reload.school_year.school).to eq(school)
    expect(response.body).to include('생성된 교실의 소속 학교는 변경할 수 없습니다.')
  end

  def classroom_update_params(classroom)
    { class_label: classroom.class_label }
  end
end
