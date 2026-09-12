require 'rails_helper'

RSpec.describe 'Planning Classroom deletion', type: :request do
  let(:admin) { create(:user, :admin) }
  let(:school) { create(:school) }
  let!(:active_year) { create(:school_year, :active, school: school, year: 2026) }
  let!(:planning_year) { create(:school_year, school: school, year: 2027) }
  let(:context) { { school_id: school.id, school_year_id: planning_year.id } }
  let!(:classroom) { create(:classroom, school_year: planning_year, grade: 2) }

  def manager_for(target_school = school)
    active = target_school.school_years.find_by(status: :active) ||
             create(:school_year, :active, school: target_school, year: 2026)
    create(:user, :teacher, school_year: active, school_role: 'manager',
                            login_id: "manager-#{target_school.id}")
  end

  def delete_classroom(target = classroom, request_context: context)
    delete classroom_path(target), params: request_context
  end

  it 'lets an admin delete a planning Classroom and preserves the context redirect' do
    sign_in admin

    expect { delete_classroom }.to change(Classroom, :count).by(-1)

    expect(response).to redirect_to(classrooms_path(context))
    expect(flash[:notice]).to eq(I18n.t('classrooms.destroy.planning_success'))
  end

  it 'lets the current manager delete their immediately following planning Classroom' do
    sign_in manager_for

    expect { delete_classroom }.to change(Classroom, :count).by(-1)
  end

  it 'deletes a current planning assignment and preserves its Teacher' do
    teacher = create(:user, :teacher, school_year: planning_year, school_role: 'member',
                                      login_id: 'assigned-planning', grade: classroom.grade)
    assignment = create(:homeroom_assignment, teacher: teacher, classroom: classroom,
                                              started_on: Date.new(planning_year.year, 3, 1))
    sign_in admin

    delete_classroom

    expect(HomeroomAssignment.exists?(assignment.id)).to eq(false)
    expect(User.exists?(teacher.id)).to eq(true)
  end

  it 'rejects deletion when a Student exists and preserves both records' do
    student = create(:student, classroom: classroom)
    sign_in admin

    delete_classroom

    expect(Classroom.exists?(classroom.id)).to eq(true)
    expect(Student.exists?(student.id)).to eq(true)
    expect(flash[:alert]).to eq(I18n.t('classrooms.destroy.failure'))
  end

  it 'rejects unexpected ended assignment history and preserves it' do
    teacher = create(:user, :teacher, school_year: planning_year, school_role: 'member',
                                      login_id: 'history-teacher', grade: classroom.grade)
    history = create(:homeroom_assignment, teacher: teacher, classroom: classroom,
                                           started_on: Date.new(planning_year.year, 3, 1), ended_on: Date.new(planning_year.year, 3, 2))
    sign_in admin

    delete_classroom

    expect(Classroom.exists?(classroom.id)).to eq(true)
    expect(HomeroomAssignment.exists?(history.id)).to eq(true)
  end

  it 'rejects an ordinary teacher' do
    teacher = create(:user, :teacher, school_year: active_year, school_role: 'member', login_id: 'ordinary')
    sign_in teacher

    delete_classroom

    expect(response).to redirect_to(root_path)
    expect(Classroom.exists?(classroom.id)).to eq(true)
  end

  it 'rejects another School manager' do
    sign_in manager_for(create(:school))

    delete_classroom

    expect(response).to have_http_status(:not_found)
  end

  it 'fails closed for a cross-School context' do
    sign_in admin

    delete_classroom(request_context: context.merge(school_id: create(:school).id))

    expect(response).to have_http_status(:not_found)
  end

  it 'fails closed when an active year is presented as planning' do
    active_classroom = create(:classroom, school_year: active_year)
    sign_in admin

    delete_classroom(active_classroom, request_context: {
                       school_id: school.id, school_year_id: active_year.id
                     })

    expect(response).to have_http_status(:not_found)
    expect(Classroom.exists?(active_classroom.id)).to eq(true)
  end

  it 'fails closed for an archived context' do
    archived_year = create(:school_year, :archived, school: school, year: 2025)
    archived_classroom = create(:classroom, school_year: archived_year)
    sign_in admin

    delete_classroom(archived_classroom, request_context: {
                       school_id: school.id, school_year_id: archived_year.id
                     })

    expect(response).to have_http_status(:not_found)
  end

  it 'fails closed for an inactive School' do
    school.update!(active: false)
    sign_in admin

    delete_classroom

    expect(response).to have_http_status(:not_found)
  end

  it 'fails closed for malformed context' do
    sign_in admin

    delete_classroom(request_context: { school_id: school.id, school_year_id: 'invalid' })

    expect(response).to have_http_status(:not_found)
  end

  it 'shows the planning delete control with exact context to an admin' do
    sign_in admin

    get edit_classroom_path(classroom, context)

    document = Nokogiri::HTML(response.body)
    expect(document.at_css(%(a[href="#{classroom_path(classroom,
                                                      context)}"][data-turbo-method="delete"]))).to be_present
  end

  it 'shows the planning delete control to the current manager' do
    sign_in manager_for

    get edit_classroom_path(classroom, context)

    document = Nokogiri::HTML(response.body)
    expect(document.at_css(%(a[href="#{classroom_path(classroom,
                                                      context)}"][data-turbo-method="delete"]))).to be_present
  end
end
