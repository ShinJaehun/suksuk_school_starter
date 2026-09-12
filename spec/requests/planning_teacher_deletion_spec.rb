require 'rails_helper'

RSpec.describe 'Planning Teacher deletion', type: :request do
  let(:admin) { create(:user, :admin) }
  let(:school) { create(:school) }
  let!(:active_year) { create(:school_year, :active, school: school, year: 2026) }
  let!(:planning_year) { create(:school_year, school: school, year: 2027) }
  let(:context) { { school_id: school.id, school_year_id: planning_year.id } }
  let!(:planning_teacher) do
    create(:user, :teacher, school_year: planning_year, school_role: 'member',
                            login_id: 'planning-delete', grade: 2)
  end

  def manager_for(target_school = school, year: 2026)
    school_year = target_school.school_years.find_by(status: :active) ||
                  create(:school_year, :active, school: target_school, year: year)
    create(:user, :teacher, school_year: school_year, school_role: 'manager',
                            login_id: "manager-#{target_school.id}")
  end

  def delete_teacher(teacher = planning_teacher, request_context: context)
    delete teacher_path(teacher), params: request_context
  end

  it 'lets an admin delete a planning member and preserves its context redirect' do
    sign_in admin

    expect { delete_teacher }.to change(User, :count).by(-1)

    expect(response).to redirect_to(teachers_path(context))
    expect(flash[:notice]).to eq(I18n.t('admin.teachers.destroy.success'))
  end

  it 'lets the current manager delete a member in their immediately following planning year' do
    sign_in manager_for

    expect { delete_teacher }.to change(User, :count).by(-1)
  end

  it 'deletes the current planning assignment but preserves the Classroom' do
    classroom = create(:classroom, school_year: planning_year, grade: planning_teacher.grade)
    assignment = create(:homeroom_assignment, teacher: planning_teacher, classroom: classroom,
                                              started_on: Date.new(planning_year.year, 3, 1))
    sign_in admin

    delete_teacher

    expect(HomeroomAssignment.exists?(assignment.id)).to eq(false)
    expect(Classroom.exists?(classroom.id)).to eq(true)
  end

  it 'deletes credential events targeting the planning Teacher' do
    event = TeacherCredentialEvent.create!(actor_user: admin, teacher_user: planning_teacher,
                                           action: :temporary_password_issued)
    sign_in admin

    delete_teacher

    expect(TeacherCredentialEvent.exists?(event.id)).to eq(false)
  end

  it 'lets an admin delete the planning manager and leaves zero managers' do
    planning_teacher.update!(school_role: 'manager')
    sign_in admin

    delete_teacher

    expect(planning_year.users.teacher.where(school_role: 'manager')).to be_empty
  end

  it 'rejects a current manager deleting the planning manager' do
    planning_teacher.update!(school_role: 'manager')
    sign_in manager_for

    expect { delete_teacher }.not_to change(User, :count)

    expect(response).to redirect_to(root_path)
  end

  it 'rejects an ordinary teacher' do
    sign_in create(:user, :teacher, school_year: active_year, school_role: 'member', login_id: 'ordinary')

    expect { delete_teacher }.not_to change(User, :count)

    expect(response).to redirect_to(root_path)
  end

  it 'rejects another School manager' do
    sign_in manager_for(create(:school))

    expect { delete_teacher }.not_to change(User, :count)

    expect(response).to have_http_status(:not_found)
  end

  it 'fails closed for a cross-School context' do
    sign_in admin

    delete_teacher(request_context: context.merge(school_id: create(:school).id))

    expect(response).to have_http_status(:not_found)
    expect(User.exists?(planning_teacher.id)).to eq(true)
  end

  it 'does not hard delete an active Teacher' do
    teacher = create(:user, :teacher, school_year: active_year,
                                      school_role: 'member', login_id: 'active-target')
    sign_in admin

    delete_teacher(teacher, request_context: { school_id: school.id, school_year_id: active_year.id })

    expect(response).to redirect_to(root_path)
    expect(User.exists?(teacher.id)).to eq(true)
  end

  it 'fails closed for an archived Teacher context' do
    archived_year = create(:school_year, :archived, school: school, year: 2025)
    teacher = create(:user, :teacher, school_year: archived_year,
                                      school_role: 'member', login_id: 'archived-target')
    sign_in admin

    delete_teacher(teacher, request_context: { school_id: school.id, school_year_id: archived_year.id })

    expect(response).to have_http_status(:not_found)
  end

  it 'fails closed for an inactive School' do
    school.update!(active: false)
    sign_in admin

    delete_teacher

    expect(response).to have_http_status(:not_found)
  end

  it 'fails closed for malformed context' do
    sign_in admin

    delete_teacher(request_context: { school_id: school.id, school_year_id: 'invalid' })

    expect(response).to have_http_status(:not_found)
  end

  it 'rolls back when the planning Teacher is an unexpected credential actor' do
    other_teacher = create(:user, :teacher, school_year: planning_year,
                                            school_role: 'member', login_id: 'credential-target')
    event = TeacherCredentialEvent.create!(actor_user: planning_teacher, teacher_user: other_teacher,
                                           action: :temporary_password_issued)
    classroom = create(:classroom, school_year: planning_year, grade: planning_teacher.grade)
    assignment = create(:homeroom_assignment, teacher: planning_teacher, classroom: classroom,
                                              started_on: Date.new(planning_year.year, 3, 1))
    sign_in admin

    delete_teacher

    expect(User.exists?(planning_teacher.id)).to eq(true)
    expect(HomeroomAssignment.exists?(assignment.id)).to eq(true)
    expect(TeacherCredentialEvent.exists?(event.id)).to eq(true)
    expect(flash[:alert]).to eq(I18n.t('admin.teachers.destroy.failure'))
  end

  it 'rolls back assignment removal when ended history restricts deletion' do
    current_classroom = create(:classroom, school_year: planning_year, grade: planning_teacher.grade)
    current_assignment = create(:homeroom_assignment, teacher: planning_teacher, classroom: current_classroom,
                                                      started_on: Date.new(planning_year.year, 3, 1))
    history_classroom = create(:classroom, school_year: planning_year, grade: planning_teacher.grade,
                                           class_label: 'history')
    history = create(:homeroom_assignment, teacher: planning_teacher, classroom: history_classroom,
                                           started_on: Date.new(planning_year.year, 3, 1), ended_on: Date.new(planning_year.year, 3, 2))
    sign_in admin

    delete_teacher

    expect(User.exists?(planning_teacher.id)).to eq(true)
    expect(HomeroomAssignment.exists?(current_assignment.id)).to eq(true)
    expect(HomeroomAssignment.exists?(history.id)).to eq(true)
  end

  it 'shows the delete control to an admin for a planning manager' do
    planning_teacher.update!(school_role: 'manager')
    sign_in admin

    get edit_teacher_path(planning_teacher, context)

    document = Nokogiri::HTML(response.body)
    delete_control = document.at_css(
      %(form[action="#{teacher_path(planning_teacher, context)}"] input[name="_method"][value="delete"])
    )

    expect(delete_control).to be_present
  end

  it 'hides the planning manager delete control from the current manager' do
    planning_teacher.update!(school_role: 'manager')
    sign_in manager_for

    get edit_teacher_path(planning_teacher, context)

    expect(response).to redirect_to(root_path)
  end

  it 'does not add a hard-delete control to an active Teacher edit page' do
    active_teacher = create(:user, :teacher, school_year: active_year,
                                             school_role: 'member', login_id: 'active-ui')
    sign_in admin

    get edit_teacher_path(active_teacher)

    document = Nokogiri::HTML(response.body)
    delete_control = document.at_css(
      %(form[action="#{teacher_path(active_teacher)}"] input[name="_method"][value="delete"])
    )

    expect(delete_control).to be_nil
  end
end
