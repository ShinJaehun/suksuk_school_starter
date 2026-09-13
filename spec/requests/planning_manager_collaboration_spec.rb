require 'rails_helper'

RSpec.describe 'Planning manager collaboration', type: :request do
  let(:school) { create(:school) }
  let!(:active_year) { create(:school_year, :active, school: school, year: 2026) }
  let!(:planning_year) { create(:school_year, school: school, year: 2027) }
  let!(:planning_manager) do
    create(:user, :teacher, school_year: planning_year, school_role: 'manager',
                            login_id: 'planning-manager', grade: 4)
  end
  let!(:planning_teacher) do
    create(:user, :teacher, school_year: planning_year, school_role: 'member',
                            name: '다음 학년도 교사', login_id: 'planning-member', grade: 4)
  end
  let(:context) { { school_id: school.id, school_year_id: planning_year.id } }

  before { sign_in planning_manager }

  it 'defaults unscoped Teacher and Classroom indexes to its planning SchoolYear' do
    planning_classroom = create(:classroom, school_year: planning_year, class_label: '준비반')
    active_teacher = create(:user, :teacher, school_year: active_year, school_role: 'member',
                                             name: '현재 학년도 교사', login_id: 'active-year-teacher')
    active_classroom = create(:classroom, school_year: active_year, class_label: '운영반')

    get teachers_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(planning_teacher.name)
    expect(response.body).not_to include(active_teacher.name)

    get classrooms_path
    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    expect(document.at_css(%(a[href="#{classroom_path(planning_classroom)}"]))).to be_present
    expect(document.at_css(%(a[href="#{classroom_path(active_classroom)}"]))).to be_nil
  end

  it 'lets the planning manager explicitly select its School active Classroom context' do
    active_classroom = create(:classroom, school_year: active_year, class_label: '운영반')
    planning_classroom = create(:classroom, school_year: planning_year, class_label: '준비반')

    get classrooms_path, params: { school_id: school.id, school_year_id: active_year.id }

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    expect(document.at_css(%(a[href="#{classroom_path(active_classroom)}"]))).to be_present
    expect(document.at_css(%(a[href="#{classroom_members_path(active_classroom)}"]))).to be_present
    expect(document.at_css(%(a[href="#{classroom_path(planning_classroom)}"]))).to be_nil
  end

  it 'creates a member Teacher in its exact planning context' do
    post teachers_path, params: context.merge(
      membership_grade: 3,
      user: { name: '함께 준비한 교사', login_id: 'collaborative-teacher', email: '' }
    )

    created_teacher = planning_year.users.teacher.find_by!(login_id: 'collaborative-teacher')
    expect(created_teacher).to have_attributes(school_role: 'member', grade: 3)
  end

  it 'updates a member Teacher and its planning assignment' do
    classroom = create(:classroom, school_year: planning_year, grade: 5)

    patch teacher_path(planning_teacher), params: context.merge(
      membership_grade: 5,
      classroom_id: classroom.id,
      user: { name: '수정된 준비 교사', email: planning_teacher.email }
    )

    expect(planning_teacher.reload).to have_attributes(name: '수정된 준비 교사', grade: 5)
    expect(planning_teacher.assigned_classroom).to eq(classroom)
  end

  it 'deactivates a member Teacher by deleting its preparation assignment' do
    classroom = create(:classroom, school_year: planning_year, grade: planning_teacher.grade)
    assignment = create(:homeroom_assignment, teacher: planning_teacher, classroom: classroom,
                                              started_on: Date.new(planning_year.year, 3, 1))

    patch deactivate_teacher_path(planning_teacher), params: context

    expect(planning_teacher.reload).to be_inactive
    expect(HomeroomAssignment.exists?(assignment.id)).to eq(false)
    expect(Classroom.exists?(classroom.id)).to eq(true)

    patch reactivate_teacher_path(planning_teacher), params: context

    expect(planning_teacher.reload).to be_active
    expect(planning_teacher.assigned_classroom).to be_nil
  end

  it 'keeps an inactive member Teacher manageable without restoring its assignment' do
    planning_teacher.update!(active: false)

    get teachers_path, params: context.merge(status: 'inactive')
    document = Nokogiri::HTML(response.body)
    expect(document.at_css("a[href='#{edit_teacher_path(planning_teacher, context)}']")).to be_present

    get edit_teacher_path(planning_teacher), params: context
    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    expect(
      document.at_css("form[action='#{reactivate_teacher_path(planning_teacher, context)}']")
    ).to be_present
    expect(
      document.at_css("form[action='#{reissue_temporary_password_teacher_path(planning_teacher, context)}']")
    ).to be_nil

    patch reactivate_teacher_path(planning_teacher), params: context
    expect(planning_teacher.reload).to be_active
    expect(planning_teacher.assigned_classroom).to be_nil
  end

  it 'reissues a planning member temporary password through the existing credential flow' do
    get edit_teacher_path(planning_teacher), params: context
    document = Nokogiri::HTML(response.body)
    expect(
      document.at_css(
        "form[action='#{reissue_temporary_password_teacher_path(planning_teacher, context)}']"
      )
    ).to be_present

    expect do
      patch reissue_temporary_password_teacher_path(planning_teacher), params: context
    end.to change { planning_teacher.teacher_credential_events.temporary_password_reissued.count }.by(1)

    expect(response).to have_http_status(:ok)
    expect(planning_teacher.teacher_credential_events.temporary_password_reissued.last.actor_user).to eq(planning_manager)
  end

  it 'lets the current manager recover active planning Teacher credentials' do
    current_manager = create(:user, :teacher, school_year: active_year, school_role: 'manager',
                                              login_id: 'current-manager')
    sign_in current_manager

    [planning_teacher, planning_manager].each do |target|
      get edit_teacher_path(target), params: context
      document = Nokogiri::HTML(response.body)
      expect(
        document.at_css("form[action='#{reissue_temporary_password_teacher_path(target, context)}']")
      ).to be_present
    end

    expect do
      patch reissue_temporary_password_teacher_path(planning_manager), params: context
    end.to change { planning_manager.teacher_credential_events.temporary_password_reissued.count }.by(1)

    expect(planning_manager.teacher_credential_events.temporary_password_reissued.last.actor_user).to eq(current_manager)
  end

  it 'cannot deactivate the planning manager' do
    patch deactivate_teacher_path(planning_manager), params: context

    expect(planning_manager.reload).to be_active
    expect(flash[:alert]).to eq(I18n.t('teacher_status.planning_manager'))
  end

  it 'creates and updates a Classroom in its exact planning context' do
    expect do
      post classrooms_path, params: context.merge(
        classroom: { grade: 4, class_label: '협업반' }
      )
    end.to change { planning_year.classrooms.reload.count }.by(1)

    classroom = planning_year.classrooms.order(:id).last

    patch classroom_path(classroom), params: context.merge(
      classroom: { grade: 4, class_label: '함께 준비한 반' }
    )

    expect(classroom.reload.class_label).to eq('함께 준비한')
  end

  it 'deletes a planning Classroom' do
    classroom = create(:classroom, school_year: planning_year, grade: 4)

    expect do
      delete classroom_path(classroom), params: context
    end.to change(Classroom, :count).by(-1)
  end

  it 'deletes a planning member Teacher but not the planning manager' do
    expect do
      delete teacher_path(planning_teacher), params: context
    end.to change(User, :count).by(-1)

    delete teacher_path(planning_manager), params: context

    expect(User.exists?(planning_manager.id)).to eq(true)
  end

  it 'reads its School archive but cannot mutate it' do
    archived_year = create(:school_year, :archived, school: school, year: 2025)
    archived_teacher = create(:user, :teacher, school_year: archived_year,
                                               login_id: 'archived-member', school_role: 'member')
    archived_classroom = create(:classroom, school_year: archived_year)
    archived_context = { school_id: school.id, school_year_id: archived_year.id }

    get teachers_path, params: archived_context
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(archived_teacher.name)

    get classroom_path(archived_classroom), params: archived_context
    expect(response).to have_http_status(:ok)

    patch teacher_path(archived_teacher), params: archived_context.merge(
      membership_grade: 3,
      user: { name: '변경 금지', email: archived_teacher.email }
    )
    expect(response).to have_http_status(:not_found)
    expect(archived_teacher.reload.name).not_to eq('변경 금지')
  end

  it 'manages active Teachers in its School while preserving self protections' do
    active_teacher = create(:user, :teacher, school_year: active_year, school_role: 'member',
                                             login_id: 'active-member')
    active_classroom = create(:classroom, school_year: active_year, grade: 3)
    active_context = { school_id: school.id, school_year_id: active_year.id }

    post teachers_path, params: active_context.merge(
      membership_grade: 2,
      user: { name: '새 운영 교사', login_id: 'new-active-member', email: '' }
    )
    expect(active_year.users.teacher.find_by!(login_id: 'new-active-member')).to have_attributes(grade: 2)

    patch teacher_path(active_teacher), params: active_context.merge(
      membership_grade: 3,
      classroom_id: active_classroom.id,
      user: { name: '변경 허용', email: active_teacher.email }
    )
    expect(active_teacher.reload).to have_attributes(name: '변경 허용', grade: 3)
    expect(active_teacher.assigned_classroom).to eq(active_classroom)

    expect do
      patch reissue_temporary_password_teacher_path(active_teacher), params: active_context
    end.to change { active_teacher.teacher_credential_events.temporary_password_reissued.count }.by(1)

    patch deactivate_teacher_path(active_teacher), params: active_context
    expect(active_teacher.reload).to be_inactive
    patch reactivate_teacher_path(active_teacher), params: active_context
    expect(active_teacher.reload).to be_active

    patch reissue_temporary_password_teacher_path(planning_manager), params: context
    expect(planning_manager.teacher_credential_events.temporary_password_reissued).not_to exist
    patch deactivate_teacher_path(planning_manager), params: context
    expect(planning_manager.reload).to be_active
  end

  it 'manages active Classrooms and Students in its School' do
    active_classroom = create(:classroom, school_year: active_year, grade: 3)
    empty_classroom = create(:classroom, school_year: active_year)
    student = create(:student, classroom: active_classroom, name: '운영 학생')

    get classroom_path(active_classroom)
    expect(response).to have_http_status(:ok)

    patch classroom_path(active_classroom), params: {
      classroom: { grade: 3, class_label: '수정 운영반' }
    }
    expect(active_classroom.reload.class_label).to eq('수정 운영')

    get classroom_members_path(active_classroom)
    expect(response).to have_http_status(:ok)

    patch classroom_student_path(active_classroom, student), params: {
      student: { name: '수정 학생' }
    }
    expect(student.reload.name).to eq('수정 학생')

    patch deactivate_classroom_path(active_classroom)
    expect(active_classroom.reload).not_to be_active
    patch reactivate_classroom_path(active_classroom)
    expect(active_classroom.reload).to be_active

    expect do
      delete classroom_path(empty_classroom)
    end.to change(Classroom, :count).by(-1)
  end

  it 'cannot access another School planning governance surface' do
    other_school = create(:school)
    create(:school_year, :active, school: other_school, year: 2026)
    create(:school_year, school: other_school, year: 2027)

    get school_planning_path(other_school)
    expect(response).to have_http_status(:not_found)
  end

  it 'cannot access another School Classroom contexts' do
    other_school = create(:school)
    active_year = create(:school_year, :active, school: other_school, year: 2026)
    planning_year = create(:school_year, school: other_school, year: 2027)
    archived_year = create(:school_year, :archived, school: other_school, year: 2025)

    aggregate_failures do
      {
        active: active_year,
        planning: planning_year,
        archived: archived_year
      }.each do |status, school_year|
        sign_in planning_manager

        get classrooms_path,
            params: { school_id: other_school.id, school_year_id: school_year.id }
        expect(response).to have_http_status(:not_found),
                            "#{status}: status=#{response.status}, location=#{response.location}"
      end
    end
  end

  it 'cannot access another School Teacher contexts' do
    other_school = create(:school)
    active_year = create(:school_year, :active, school: other_school, year: 2026)
    planning_year = create(:school_year, school: other_school, year: 2027)
    archived_year = create(:school_year, :archived, school: other_school, year: 2025)

    aggregate_failures do
      {
        active: active_year,
        planning: planning_year,
        archived: archived_year
      }.each do |status, school_year|
        sign_in planning_manager

        get teachers_path,
            params: { school_id: other_school.id, school_year_id: school_year.id }
        expect(response).to have_http_status(:not_found),
                            "#{status}: status=#{response.status}, location=#{response.location}"
      end
    end
  end

  it 'keeps the same session as the new operational manager after rollover' do
    SchoolYears::Rollover.call(school: school, target_school_year_id: planning_year.id)
    planning_manager.reload

    get school_path(school)

    expect(response).to have_http_status(:ok)
    expect(controller.current_user).to eq(planning_manager)
    expect(controller.current_user).to be_current_operational_manager
  end
end
