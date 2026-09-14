require 'rails_helper'

RSpec.describe 'Planning rollover recovery', type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:school) { create(:school) }
  let!(:active_year) { create(:school_year, :active, school: school, year: 2026) }
  let(:admin) { create(:user, :admin) }

  around { |example| travel_to(Time.zone.local(2027, 4, 10)) { example.run } }

  it 'lets an admin prepare and manually activate a late year without any former manager' do
    sign_in admin
    post school_school_years_path(school)

    planning_year = school.school_years.planning.sole
    expect(planning_year.year).to eq(2027)
    expect(response).to redirect_to(school_planning_path(school))

    # The automatic service's real failure/commit is covered in its service spec.
    # This request flow starts from an already consumed, unsuccessful attempt.
    attempted_at = Time.current
    planning_year.update!(automatic_rollover_attempted_at: attempted_at)
    get school_planning_path(school)
    expect(response.body).to include(
      I18n.t('school_years.rollover.overdue', year: 2027),
      I18n.t('school_years.rollover.errors.manager_missing')
    )

    context = { school_id: school.id, school_year_id: planning_year.id }
    post teachers_path, params: context.merge(
      membership_grade: 3,
      user: { name: '새 대표', login_id: 'recovery-manager', email: '' }
    )
    teacher = planning_year.users.teacher.find_by!(login_id: 'recovery-manager')
    expect(teacher.encrypted_password).to be_present
    expect(teacher.teacher_credential_events.temporary_password_issued.count).to eq(1)

    post admin_school_school_managers_path(school),
         params: { school_year_id: planning_year.id, user_id: teacher.id }
    expect(response).to redirect_to(school_planning_path(school))
    expect(teacher.reload).to be_school_manager

    expect do
      patch reissue_temporary_password_teacher_path(teacher), params: context
    end.to change { teacher.teacher_credential_events.temporary_password_reissued.count }.by(1)
    expect(response).to have_http_status(:ok)

    post classrooms_path, params: context.merge(classroom: { grade: 3, class_label: '복구반' })
    expect(planning_year.classrooms.find_by!(class_label: '복구').grade).to eq(3)
    expect(SchoolYears::RolloverEligibility.new(school_year: planning_year)).to be_eligible

    post school_planning_rollover_path(school), params: { school_year_id: planning_year.id }

    expect(response).to redirect_to(school_path(school))
    expect(active_year.reload).to be_archived
    expect(planning_year.reload).to be_active
    expect(planning_year.automatic_rollover_attempted_at).to eq(attempted_at)
    expect(teacher.reload).to be_current_operational_manager

    sign_in teacher
    patch forced_password_path, params: {
      user: { password: 'recovered-password123', password_confirmation: 'recovered-password123' }
    }
    expect(teacher.reload).not_to be_password_change_required
    get teachers_path
    expect(response).to have_http_status(:ok)
    get classrooms_path
    expect(response).to have_http_status(:ok)
  end

  it 'allows planning creation, Teacher and Classroom preparation, and designation before February' do
    travel_to Time.zone.local(2026, 12, 1)
    sign_in admin
    post school_school_years_path(school)
    planning_year = school.school_years.planning.sole
    context = { school_id: school.id, school_year_id: planning_year.id }

    post teachers_path, params: context.merge(
      membership_grade: 3,
      user: { name: '준비 대표', login_id: 'early-manager', email: '' }
    )
    teacher = planning_year.users.teacher.find_by!(login_id: 'early-manager')
    post admin_school_school_managers_path(school),
         params: { school_year_id: planning_year.id, user_id: teacher.id }
    expect(teacher.reload).to be_school_manager

    post classrooms_path, params: context.merge(classroom: { grade: 3, class_label: '준비반' })

    expect(planning_year.classrooms.find_by!(class_label: '준비').grade).to eq(3)
    expect(active_year.reload).to be_active
    expect(planning_year.reload).to be_planning
    expect(planning_year.automatic_rollover_attempted_at).to be_nil
  end
end
