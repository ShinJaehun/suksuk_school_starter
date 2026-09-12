require 'rails_helper'

RSpec.describe 'Planning Teacher homeroom assignments', type: :request do
  let(:school) { create(:school) }
  let!(:active_year) { create(:school_year, :active, school: school, year: 2026) }
  let!(:planning_year) { create(:school_year, school: school, year: 2027) }
  let!(:teacher) do
    create(:user, :teacher, school_year: planning_year, grade: 4,
                            school_role: 'member', login_id: 'planning-homeroom')
  end

  def context
    { school_id: school.id, school_year_id: planning_year.id }
  end

  def update_params(classroom_id:, grade: 4)
    context.merge(
      membership_grade: grade,
      classroom_id: classroom_id,
      user: { name: teacher.name }
    )
  end

  it 'reuses the Teacher settings form with eligible planning Classrooms' do
    available = create(:classroom, school_year: planning_year, grade: 4)
    current = create(:classroom, school_year: planning_year, grade: 4, teacher: teacher)
    wrong_grade = create(:classroom, school_year: planning_year, grade: 5)
    inactive = create(:classroom, school_year: planning_year, grade: 4, active: false)
    occupied_teacher = create(:user, :teacher, school_year: planning_year, grade: 4,
                                               school_role: 'member', login_id: 'occupied-planning')
    occupied = create(:classroom, school_year: planning_year, grade: 4, teacher: occupied_teacher)
    active_classroom = create(:classroom, school_year: active_year, grade: 4)
    sign_in create(:user, :admin)

    get edit_teacher_path(teacher, context)

    document = Nokogiri::HTML(response.body)
    expect(response).to have_http_status(:ok)
    expect(document.at_css(%(input[name="school_year_id"][value="#{planning_year.id}"]))).to be_present
    form = document.at_css('form[data-teacher-classroom-picker-url-value]')
    picker_url = form['data-teacher-classroom-picker-url-value']
    expect(picker_url).to include(
      classroom_options_teachers_path,
      "school_id=#{school.id}",
      "school_year_id=#{planning_year.id}",
      "teacher_id=#{teacher.id}"
    )
    option_values = document.css('select[name=classroom_id] option').map { |option| option['value'] }
    expect(option_values).to include('', available.id.to_s, current.id.to_s)
    expect(option_values).not_to include(
      wrong_grade.id.to_s,
      inactive.id.to_s,
      occupied.id.to_s,
      active_classroom.id.to_s
    )
  end

  it 'returns same-year available Classrooms for a changed planning grade' do
    current = create(:classroom, school_year: planning_year, grade: 4, teacher: teacher)
    available = create(:classroom, school_year: planning_year, grade: 5)
    wrong_grade = create(:classroom, school_year: planning_year, grade: 4)
    inactive = create(:classroom, school_year: planning_year, grade: 5, active: false)
    occupied_teacher = create(:user, :teacher, school_year: planning_year, grade: 5,
                                               school_role: 'member', login_id: 'picker-occupied')
    occupied = create(:classroom, school_year: planning_year, grade: 5, teacher: occupied_teacher)
    active_classroom = create(:classroom, school_year: active_year, grade: 5)
    sign_in create(:user, :admin)

    get classroom_options_teachers_path, params: context.merge(
      teacher_id: teacher.id,
      membership_grade: 5,
      classroom_id: current.id
    )

    option_values = Nokogiri::HTML.fragment(response.body)
                                  .css('option')
                                  .map { |option| option['value'] }
    expect(response).to have_http_status(:ok)
    expect(option_values).to include('', available.id.to_s)
    expect(option_values).not_to include(
      current.id.to_s,
      wrong_grade.id.to_s,
      inactive.id.to_s,
      occupied.id.to_s,
      active_classroom.id.to_s
    )
  end

  it 'keeps the current planning Classroom in candidates for its selected grade' do
    current = create(:classroom, school_year: planning_year, grade: 4, teacher: teacher)
    sign_in create(:user, :admin)

    get classroom_options_teachers_path, params: context.merge(
      teacher_id: teacher.id,
      membership_grade: 4,
      classroom_id: current.id
    )

    option = Nokogiri::HTML.fragment(response.body)
                           .at_css(%(option[value="#{current.id}"][selected]))
    expect(response).to have_http_status(:ok)
    expect(option).to be_present
  end

  it 'lets an admin connect, replace, and release through the Teacher settings endpoint' do
    first = create(:classroom, school_year: planning_year, grade: 5)
    second = create(:classroom, school_year: planning_year, grade: 5)
    sign_in create(:user, :admin)

    patch teacher_path(teacher), params: update_params(classroom_id: first.id, grade: 5)
    first_assignment = teacher.reload.current_homeroom_assignment
    expect(teacher.grade).to eq(5)
    expect(first_assignment.started_on).to eq(Date.new(2027, 3, 1))

    patch teacher_path(teacher), params: update_params(classroom_id: second.id, grade: 5)
    expect(HomeroomAssignment.exists?(first_assignment.id)).to eq(false)
    second_assignment = teacher.reload.current_homeroom_assignment
    expect(second_assignment).to have_attributes(
      classroom: second,
      started_on: Date.new(2027, 3, 1),
      ended_on: nil
    )

    patch teacher_path(teacher), params: update_params(classroom_id: '', grade: 5)
    expect(HomeroomAssignment.exists?(second_assignment.id)).to eq(false)
    expect(teacher.reload.assigned_classroom).to be_nil
    expect(response).to redirect_to(teachers_path(context))
  end

  it 'lets a current manager assign a member in their immediately following planning year' do
    manager = create(:user, :teacher, :active_annual_teacher,
                     annual_school: school, annual_school_role: 'manager')
    classroom = create(:classroom, school_year: planning_year, grade: 4)
    sign_in manager

    patch teacher_path(teacher), params: update_params(classroom_id: classroom.id)

    expect(response).to redirect_to(teachers_path(context))
    expect(teacher.reload.assigned_classroom).to eq(classroom)
  end

  it 'keeps active-year classroom_options behavior' do
    active_teacher = create(:user, :teacher, :active_annual_teacher,
                            annual_school: school, annual_grade: 4)
    active_classroom = create(:classroom, school_year: active_year, grade: 4)
    planning_classroom = create(:classroom, school_year: planning_year, grade: 4)
    sign_in create(:user, :admin)

    get classroom_options_teachers_path, params: {
      school_id: school.id,
      school_year_id: active_year.id,
      teacher_id: active_teacher.id,
      membership_grade: 4
    }

    option_values = Nokogiri::HTML.fragment(response.body)
                                  .css('option')
                                  .map { |option| option['value'] }
    expect(response).to have_http_status(:ok)
    expect(option_values).to include('', active_classroom.id.to_s)
    expect(option_values).not_to include(planning_classroom.id.to_s)
  end

  it 'rejects invalid Classroom choices without changing the assignment' do
    valid = create(:classroom, school_year: planning_year, grade: 4, teacher: teacher)
    occupied_teacher = create(:user, :teacher, school_year: planning_year, grade: 4,
                                               school_role: 'member', login_id: 'other-planning')
    invalid_classrooms = [
      create(:classroom, school_year: active_year, grade: 4),
      create(:classroom, school_year: planning_year, grade: 5),
      create(:classroom, school_year: planning_year, grade: 4, active: false),
      create(:classroom, school_year: planning_year, grade: 4, teacher: occupied_teacher)
    ]
    sign_in create(:user, :admin)

    invalid_classrooms.each do |classroom|
      patch teacher_path(teacher), params: update_params(classroom_id: classroom.id)

      expect(response).to have_http_status(:unprocessable_content)
      expect(teacher.reload.assigned_classroom).to eq(valid)
    end
  end

  it 'fails closed for unauthorized and archived Teacher contexts' do
    classroom = create(:classroom, school_year: planning_year, grade: 4)
    ordinary_teacher = create(:user, :teacher, :active_annual_teacher,
                              annual_school: school, annual_grade: 4)
    sign_in ordinary_teacher

    patch teacher_path(teacher), params: update_params(classroom_id: classroom.id)

    expect(response).to redirect_to(root_path)
    expect(teacher.reload.assigned_classroom).to be_nil

    archived_year = create(:school_year, :archived, school: school, year: 2025)
    archived_teacher = create(:user, :teacher, school_year: archived_year, grade: 4,
                                               school_role: 'member', login_id: 'archived-homeroom')
    sign_in create(:user, :admin)

    patch teacher_path(archived_teacher), params: {
      school_id: school.id,
      school_year_id: archived_year.id,
      membership_grade: 4,
      classroom_id: classroom.id,
      user: { name: archived_teacher.name }
    }

    expect(response).to have_http_status(:not_found)
    expect(archived_teacher.reload.assigned_classroom).to be_nil
  end

  it 'fails closed for a cross-School Teacher context' do
    manager = create(:user, :teacher, :active_annual_teacher,
                     annual_school: school, annual_school_role: 'manager')
    other_school = create(:school)
    create(:school_year, :active, school: other_school, year: 2026)
    other_planning_year = create(:school_year, school: other_school, year: 2027)
    outside_teacher = create(:user, :teacher, school_year: other_planning_year, grade: 4,
                                              school_role: 'member', login_id: 'outside-planning')
    outside_classroom = create(:classroom, school_year: other_planning_year, grade: 4)
    sign_in manager

    patch teacher_path(outside_teacher), params: {
      school_id: other_school.id,
      school_year_id: other_planning_year.id,
      membership_grade: 4,
      classroom_id: outside_classroom.id,
      user: { name: outside_teacher.name }
    }

    expect(response).to have_http_status(:not_found)
    expect(outside_teacher.reload.assigned_classroom).to be_nil
  end

  it 'rejects a malformed Classroom id without changing the assignment' do
    sign_in create(:user, :admin)

    patch teacher_path(teacher), params: update_params(classroom_id: 'invalid')

    expect(response).to have_http_status(:unprocessable_content)
    expect(teacher.reload.assigned_classroom).to be_nil
  end

  it 'fails closed for an inactive planning Teacher target' do
    inactive_teacher = create(:user, :teacher, school_year: planning_year, grade: 4,
                                               school_role: 'member', login_id: 'inactive-planning', active: false)
    classroom = create(:classroom, school_year: planning_year, grade: 4)
    sign_in create(:user, :admin)

    patch teacher_path(inactive_teacher), params: context.merge(
      membership_grade: 4,
      classroom_id: classroom.id,
      user: { name: inactive_teacher.name }
    )

    expect(response).to have_http_status(:not_found)
    expect(inactive_teacher.reload.assigned_classroom).to be_nil
  end

  it 'fails closed for a malformed planning School context in classroom_options' do
    sign_in create(:user, :admin)

    get classroom_options_teachers_path, params: context.merge(
      school_id: 'invalid',
      teacher_id: teacher.id,
      membership_grade: 4
    )

    expect(response).to have_http_status(:not_found)
  end

  it 'fails closed for a malformed planning SchoolYear context in classroom_options' do
    sign_in create(:user, :admin)

    get classroom_options_teachers_path, params: context.merge(
      school_year_id: 'invalid',
      teacher_id: teacher.id,
      membership_grade: 4
    )

    expect(response).to have_http_status(:not_found)
  end

  it 'fails closed for a cross-school planning context in classroom_options' do
    other_school = create(:school)
    create(:school_year, :active, school: other_school, year: 2026)
    sign_in create(:user, :admin)

    get classroom_options_teachers_path, params: context.merge(
      school_id: other_school.id,
      teacher_id: teacher.id,
      membership_grade: 4
    )

    expect(response).to have_http_status(:not_found)
  end

  it 'fails closed for an active SchoolYear used as a planning classroom_options context' do
    sign_in create(:user, :admin)

    get classroom_options_teachers_path, params: context.merge(
      school_year_id: active_year.id,
      teacher_id: teacher.id,
      membership_grade: 4
    )

    expect(response).to have_http_status(:not_found)
  end

  it 'fails closed for an archived classroom_options context' do
    archived_year = create(
      :school_year,
      :archived,
      school: school,
      year: 2025
    )
    sign_in create(:user, :admin)

    get classroom_options_teachers_path, params: context.merge(
      school_year_id: archived_year.id,
      teacher_id: teacher.id,
      membership_grade: 4
    )

    expect(response).to have_http_status(:not_found)
  end

  it 'fails closed for an inactive-school planning classroom_options context' do
    other_school = create(:school)
    other_active_year = create(
      :school_year,
      :active,
      school: other_school,
      year: 2026
    )
    other_planning_year = create(
      :school_year,
      school: other_school,
      year: other_active_year.year + 1
    )
    other_teacher = create(
      :user,
      :teacher,
      school_year: other_planning_year,
      grade: 4,
      school_role: 'member',
      login_id: 'other-picker-teacher'
    )
    other_school.update!(active: false)
    sign_in create(:user, :admin)

    get classroom_options_teachers_path, params: {
      school_id: other_school.id,
      school_year_id: other_planning_year.id,
      teacher_id: other_teacher.id,
      membership_grade: 4
    }

    expect(response).to have_http_status(:not_found)
  end

  it 'does not let an ordinary teacher use planning classroom_options' do
    sign_in create(
      :user,
      :teacher,
      :active_annual_teacher,
      annual_school: school,
      annual_grade: 4
    )

    get classroom_options_teachers_path, params: context.merge(
      teacher_id: teacher.id,
      membership_grade: 4
    )

    expect(response).to redirect_to(root_path)
  end
end
