require 'rails_helper'

RSpec.describe 'Archived SchoolYear read-only access', type: :request do
  let(:school) { create(:school) }
  let!(:active_year) { create(:school_year, :active, school: school, year: 2027) }
  let!(:archived_year) { create(:school_year, :archived, school: school, year: 2026) }
  let(:manager) do
    create(:user, :teacher, school_year: active_year, school_role: 'manager',
                            login_id: 'archive-current-manager')
  end
  let!(:archived_teacher) do
    create(:user, :teacher, school_year: archived_year, school_role: 'manager',
                            login_id: 'archive-former-manager', grade: 3)
  end
  let!(:archived_classroom) do
    create(:classroom, school_year: archived_year, grade: 3, class_label: '지난 반')
  end
  let(:context) { { school_id: school.id, school_year_id: archived_year.id } }

  it 'lets the current manager read archived Teacher and Classroom indexes' do
    sign_in manager

    get teachers_path, params: context
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(archived_teacher.name, I18n.t('admin.teachers.index.context_read_only'))

    get classrooms_path, params: context
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(archived_classroom.class_label, I18n.t('classrooms.index.context_read_only'))
  end

  it 'shows an archived Classroom and its existing roster without mutation controls' do
    archived_year.update!(status: :planning)
    assignment = create(:homeroom_assignment, teacher: archived_teacher, classroom: archived_classroom,
                                              started_on: Date.new(archived_year.year, 3, 1))
    archived_year.update!(status: :archived)
    student = create(:student, classroom: archived_classroom, name: '지난 학생')
    sign_in manager

    get classroom_path(archived_classroom, context)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(archived_teacher.name, student.name)
    expect(assignment.reload).to be_current
    document = Nokogiri::HTML(response.body)
    expect(document.at_css(%(a[href="#{edit_classroom_path(archived_classroom)}"]))).to be_nil
    expect(document.at_css(%(a[href="#{classroom_members_path(archived_classroom)}"]))).to be_nil
  end

  it 'rejects an ordinary Teacher selecting an archived context' do
    teacher = create(:user, :teacher, school_year: active_year, school_role: 'member',
                                      login_id: 'archive-ordinary')
    sign_in teacher

    get classrooms_path, params: context

    expect(response).to have_http_status(:not_found)
  end

  it 'rejects an ordinary Teacher opening an archived Classroom directly' do
    teacher = create(:user, :teacher, school_year: active_year, school_role: 'member',
                                      login_id: 'archive-direct-ordinary')
    sign_in teacher

    get classroom_path(archived_classroom, context)

    expect(response).to have_http_status(:not_found)
  end

  it 'rejects another School manager opening the archived Classroom' do
    other_school = create(:school)
    other_active_year = create(:school_year, :active, school: other_school, year: 2027)
    other_manager = create(:user, :teacher, school_year: other_active_year,
                                            school_role: 'manager', login_id: 'archive-other-manager')
    sign_in other_manager

    get classroom_path(archived_classroom, context)

    expect(response).to have_http_status(:not_found)
  end

  it 'keeps archived Classroom mutation closed to the current manager' do
    sign_in manager
    original_class_label = archived_classroom.reload.class_label

    patch classroom_path(archived_classroom), params: context.merge(
      classroom: { class_label: '변경 금지', grade: archived_classroom.grade }
    )

    expect(response).to have_http_status(:not_found)
    expect(archived_classroom.reload.class_label).to eq(original_class_label)
  end

  it 'keeps archived Student mutation closed to the current manager' do
    student = create(:student, classroom: archived_classroom)
    sign_in manager

    patch classroom_student_path(archived_classroom, student), params: {
      student: { name: '변경 금지' }
    }
    expect(response).to redirect_to(root_path)
    expect(student.reload.name).not_to eq('변경 금지')
  end

  it 'keeps archived Teacher profile mutation closed to a global admin' do
    sign_in create(:user, :admin)

    patch teacher_path(archived_teacher), params: context.merge(user: { name: '변경 금지' })

    expect(response).to have_http_status(:not_found)
    expect(archived_teacher.reload.name).not_to eq('변경 금지')
  end

  it 'keeps archived credential mutation closed to a global admin' do
    sign_in create(:user, :admin)

    patch reissue_temporary_password_teacher_path(archived_teacher), params: context

    expect(response).to have_http_status(:not_found)
  end

  it 'keeps global admin archived Classroom access read-only' do
    sign_in create(:user, :admin)

    get classroom_path(archived_classroom, context)
    expect(response).to have_http_status(:ok)

    delete classroom_path(archived_classroom), params: context
    expect(response).to have_http_status(:not_found)
    expect(Classroom.exists?(archived_classroom.id)).to eq(true)
  end
end
