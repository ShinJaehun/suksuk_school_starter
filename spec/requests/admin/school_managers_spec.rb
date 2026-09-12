require 'rails_helper'

RSpec.describe 'Admin school managers', type: :request do
  let(:admin) { create(:user, :admin) }
  let(:school) { create(:school) }
  let(:teacher) do
    create(:user, :teacher, :active_annual_teacher,
           annual_school: school, annual_grade: 4)
  end

  it 'designates the annual teacher role' do
    sign_in admin
    post admin_school_school_managers_path(school), params: { user_id: teacher.id }

    expect(response).to redirect_to(edit_school_path(school))
    expect(teacher.reload).to be_school_manager
  end

  it 'promotes a member without changing assignments' do
    classroom = create(:classroom, annual_school: school, grade: 4)
    assign_teacher(classroom, teacher)
    sign_in admin

    post admin_school_school_managers_path(school), params: { user_id: teacher.id }

    expect(teacher.reload).to be_school_manager
    expect(classroom.reload.teacher).to eq(teacher)
  end

  it 'rejects promoting an inactive member without changing managers' do
    existing_manager = create(:user, :teacher, :active_annual_teacher,
                              annual_school: school, annual_school_role: 'manager')
    inactive_teacher = create(:user, :teacher, :active_annual_teacher,
                              annual_school: school, active: false)
    sign_in admin

    expect do
      post admin_school_school_managers_path(school), params: { user_id: inactive_teacher.id }
    end.not_to(change { school.school_years.active.first.users.where(school_role: 'manager').count })

    expect(response).to have_http_status(:see_other)
    expect(response).to redirect_to(edit_school_path(school))
    expect(flash[:alert]).to include(I18n.t('admin.school_managers.errors.inactive_manager'))
    expect(inactive_teacher.reload).to be_school_member
    expect(existing_manager.reload).to be_school_manager
  end

  it 'demotes a manager without changing assignments' do
    teacher.update!(school_role: 'manager')
    classroom = create(:classroom, annual_school: school, grade: 4)
    assign_teacher(classroom, teacher)
    sign_in admin

    delete admin_school_manager_path(school, teacher)

    expect(response).to redirect_to(edit_school_path(school))
    expect(teacher.reload).to be_school_member
    expect(classroom.reload.teacher).to eq(teacher)
  end

  it 'atomically replaces the existing manager' do
    existing_manager = create(:user, :teacher, :active_annual_teacher,
                              annual_school: school, annual_school_role: 'manager')
    sign_in admin

    post admin_school_school_managers_path(school), params: { user_id: teacher.id }

    expect(response).to have_http_status(:see_other)
    expect(response).to redirect_to(edit_school_path(school))
    expect(existing_manager.reload).to be_school_member
    expect(teacher.reload).to be_school_manager
    expect(school.school_years.active.first.users.where(school_role: 'manager').count).to eq(1)
  end

  it 'succeeds without changing an existing target manager' do
    teacher.update!(school_role: 'manager')
    sign_in admin

    post admin_school_school_managers_path(school), params: { user_id: teacher.id }

    expect(response).to redirect_to(edit_school_path(school))
    expect(teacher.reload).to be_school_manager
    expect(school.school_years.active.first.users.where(school_role: 'manager').count).to eq(1)
  end

  it 'rolls back the existing manager demotion when promotion fails' do
    existing_manager = create(:user, :teacher, :active_annual_teacher,
                              annual_school: school, annual_school_role: 'manager')
    allow_any_instance_of(User).to receive(:update!).and_wrap_original do |method, attributes|
      raise ActiveRecord::RecordInvalid if attributes[:school_role] == 'manager'

      method.call(attributes)
    end
    sign_in admin

    post admin_school_school_managers_path(school), params: { user_id: teacher.id }

    expect(existing_manager.reload).to be_school_manager
    expect(teacher.reload).to be_school_member
  end

  it 'returns to school settings after a Turbo manager change' do
    sign_in admin
    post admin_school_school_managers_path(school), params: { user_id: teacher.id },
                                                    headers: { 'Accept' => Mime[:turbo_stream].to_s }

    expect(response).to have_http_status(:see_other)
    expect(response).to redirect_to(edit_school_path(school))
    expect(teacher.reload).to be_school_manager
  end

  it 'rejects a school manager actor' do
    actor = create(:user, :teacher, :active_annual_teacher,
                   annual_school: school, annual_school_role: 'manager')
    sign_in actor

    post admin_school_school_managers_path(school), params: { user_id: teacher.id }

    expect(response).to redirect_to(root_path)
    expect(teacher.reload).to be_school_member
  end

  it 'rejects a school member actor' do
    actor = create(:user, :teacher, :active_annual_teacher, annual_school: school)
    sign_in actor

    post admin_school_school_managers_path(school), params: { user_id: teacher.id }

    expect(response).to redirect_to(root_path)
    expect(teacher.reload).to be_school_member
  end

  it 'rejects a school manager actor demoting a manager' do
    teacher.update!(school_role: 'manager')
    actor = create(:user, :teacher, :active_annual_teacher,
                   annual_school: create(:school), annual_school_role: 'manager')
    sign_in actor

    delete admin_school_manager_path(school, teacher)

    expect(response).to redirect_to(root_path)
    expect(teacher.reload).to be_school_manager
  end

  it 'rejects a school member actor demoting a manager' do
    teacher.update!(school_role: 'manager')
    actor = create(:user, :teacher, :active_annual_teacher, annual_school: school)
    sign_in actor

    delete admin_school_manager_path(school, teacher)

    expect(response).to redirect_to(root_path)
    expect(teacher.reload).to be_school_manager
  end

  it 'rejects a non-teacher target' do
    target = create(:user, :admin)
    sign_in admin

    post admin_school_school_managers_path(school), params: { user_id: target.id }

    expect(response).to have_http_status(:not_found)
  end

  it 'rejects an other-school teacher target without changing annual authority' do
    target = create(:user, :teacher, :active_annual_teacher, annual_school: create(:school))
    original_school_year = target.school_year
    sign_in admin

    post admin_school_school_managers_path(school), params: { user_id: target.id }

    expect(response).to have_http_status(:not_found)
    expect(target.reload).to have_attributes(
      school_year: original_school_year,
      school_role: 'member'
    )
  end

  it 'rejects a teacher from another SchoolYear' do
    planning_year = create(:school_year, school: school, year: 2027)
    target = create(:user, :teacher, school_year: planning_year,
                                     login_id: 'planning-manager', school_role: 'member')
    sign_in admin

    post admin_school_school_managers_path(school), params: { user_id: target.id }

    expect(response).to have_http_status(:not_found)
    expect(target.reload).to be_school_member
  end

  describe 'planning manager management' do
    let!(:active_year) do
      school.school_years.active.first || create(:school_year, :active, school: school, year: 2026)
    end
    let!(:planning_year) { create(:school_year, school: school, year: active_year.year + 1) }
    let(:planning_teacher) { create_planning_teacher(name: '다음 관리자') }
    let(:planning_context) { { school_year_id: planning_year.id } }

    it 'designates a planning Teacher without changing the active manager' do
      active_manager = teacher
      active_manager.update!(school_role: 'manager')
      sign_in admin

      post admin_school_school_managers_path(school), params: planning_context.merge(user_id: planning_teacher.id)

      expect(response).to redirect_to(school_planning_path(school))
      expect(planning_teacher.reload).to be_school_manager
      expect(active_manager.reload).to be_school_manager
    end

    it 'atomically replaces the existing planning manager' do
      existing_manager = create_planning_teacher(name: '기존 다음 관리자', school_role: 'manager')
      sign_in admin

      post admin_school_school_managers_path(school), params: planning_context.merge(user_id: planning_teacher.id)

      expect(existing_manager.reload).to be_school_member
      expect(planning_teacher.reload).to be_school_manager
      expect(planning_year.users.teacher.where(school_role: 'manager').count).to eq(1)
    end

    it 'rolls back a planning manager replacement when promotion fails' do
      existing_manager = create_planning_teacher(name: '유지할 다음 관리자', school_role: 'manager')
      target = planning_teacher
      allow_any_instance_of(User).to receive(:update!).and_wrap_original do |method, attributes|
        raise ActiveRecord::RecordInvalid if attributes[:school_role] == 'manager'

        method.call(attributes)
      end
      sign_in admin

      post admin_school_school_managers_path(school), params: planning_context.merge(user_id: target.id)

      expect(existing_manager.reload).to be_school_manager
      expect(target.reload).to be_school_member
    end

    it 'releases the planning manager back to member' do
      planning_teacher.update!(school_role: 'manager')
      sign_in admin

      delete admin_school_manager_path(school, planning_teacher), params: planning_context

      expect(response).to redirect_to(school_planning_path(school))
      expect(planning_teacher.reload).to be_school_member
      expect(planning_year.users.teacher.where(school_role: 'manager')).to be_empty
    end

    it 'idempotently keeps the same planning manager' do
      planning_teacher.update!(school_role: 'manager')
      sign_in admin

      post admin_school_school_managers_path(school), params: planning_context.merge(user_id: planning_teacher.id)

      expect(planning_teacher.reload).to be_school_manager
      expect(planning_year.users.teacher.where(school_role: 'manager').count).to eq(1)
    end

    it 'preserves profile, grade, credentials, active state, and HomeroomAssignment' do
      classroom = create(:classroom, school_year: planning_year, grade: planning_teacher.grade)
      assignment = create(:homeroom_assignment,
                          classroom: classroom,
                          teacher: planning_teacher,
                          started_on: Date.new(planning_year.year, 3, 1))
      original_attributes = planning_teacher.attributes.slice(
        'name', 'grade', 'encrypted_password', 'active'
      )
      sign_in admin

      post admin_school_school_managers_path(school), params: planning_context.merge(user_id: planning_teacher.id)

      expect(planning_teacher.reload.attributes).to include(original_attributes)
      expect(assignment.reload).to be_current
      expect(classroom.reload.teacher).to eq(planning_teacher)
    end

    it 'rejects a current operational manager actor' do
      actor = teacher
      actor.update!(school_role: 'manager')
      sign_in actor

      post admin_school_school_managers_path(school), params: planning_context.merge(user_id: planning_teacher.id)

      expect(response).to redirect_to(root_path)
      expect(planning_teacher.reload).to be_school_member
    end

    it 'rejects an ordinary teacher actor' do
      sign_in teacher

      post admin_school_school_managers_path(school), params: planning_context.merge(user_id: planning_teacher.id)

      expect(response).to redirect_to(root_path)
      expect(planning_teacher.reload).to be_school_member
    end

    it 'does not let a planning Teacher act as an operational manager' do
      planning_teacher.update!(school_role: 'manager')

      expect(planning_teacher).not_to be_current_operational_manager
      expect(SchoolPolicy.new(planning_teacher, school).manage_operations?).to eq(false)

      post school_teacher_login_path(school), params: {
        teacher: { login_id: planning_teacher.login_id, password: 'password123' }
      }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'rejects a planning Teacher actor' do
      actor = planning_teacher
      actor.update!(school_role: 'manager')
      target = create_planning_teacher(name: '변경되면 안 되는 후보')
      sign_in actor

      post admin_school_school_managers_path(school), params: planning_context.merge(user_id: target.id)

      expect(response).to redirect_to(school_teacher_login_path(school))
      expect(target.reload).to be_school_member
    end

    it 'fails closed for a cross-School planning context' do
      other_school = create(:school)
      other_active_year = create(:school_year, :active, school: other_school, year: active_year.year)
      other_planning_year = create(:school_year, school: other_school, year: other_active_year.year + 1)
      sign_in admin

      post admin_school_school_managers_path(school), params: {
        school_year_id: other_planning_year.id,
        user_id: planning_teacher.id
      }

      expect(response).to have_http_status(:not_found)
    end

    it 'fails closed when an active-year Teacher is submitted as the planning target' do
      sign_in admin

      post admin_school_school_managers_path(school), params: planning_context.merge(user_id: teacher.id)

      expect(response).to have_http_status(:not_found)
      expect(teacher.reload).to be_school_member
    end

    it 'fails closed when the active SchoolYear is submitted as planning context' do
      sign_in admin

      post admin_school_school_managers_path(school), params: {
        school_year_id: active_year.id,
        user_id: planning_teacher.id
      }

      expect(response).to have_http_status(:not_found)
    end

    it 'fails closed for a Teacher from another School planning year' do
      other_school = create(:school)
      other_active_year = create(:school_year, :active, school: other_school, year: active_year.year)
      other_planning_year = create(:school_year, school: other_school, year: other_active_year.year + 1)
      other_teacher = create(:user, :teacher,
                             school_year: other_planning_year,
                             login_id: generate(:annual_teacher_login_id),
                             school_role: 'member')
      sign_in admin

      post admin_school_school_managers_path(school), params: planning_context.merge(user_id: other_teacher.id)

      expect(response).to have_http_status(:not_found)
    end

    it 'fails closed for an archived SchoolYear context' do
      archived_year = create(:school_year, :archived, school: school, year: active_year.year - 1)
      sign_in admin

      post admin_school_school_managers_path(school), params: {
        school_year_id: archived_year.id,
        user_id: planning_teacher.id
      }

      expect(response).to have_http_status(:not_found)
    end

    it 'fails closed for an inactive School' do
      school.update!(active: false)
      sign_in admin

      post admin_school_school_managers_path(school), params: planning_context.merge(user_id: planning_teacher.id)

      expect(response).to have_http_status(:not_found)
    end

    it 'fails closed for a malformed SchoolYear context' do
      sign_in admin

      post admin_school_school_managers_path(school), params: {
        school_year_id: 'invalid',
        user_id: planning_teacher.id
      }

      expect(response).to have_http_status(:not_found)
    end

    it 'fails closed for a non-teacher planning target' do
      sign_in admin

      post admin_school_school_managers_path(school), params: planning_context.merge(user_id: admin.id)

      expect(response).to have_http_status(:not_found)
    end

    def create_planning_teacher(name:, school_role: 'member')
      create(:user, :teacher,
             school_year: planning_year,
             login_id: generate(:annual_teacher_login_id),
             name: name,
             grade: 4,
             school_role: school_role,
             active: true)
    end
  end
end
