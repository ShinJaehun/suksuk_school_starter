require 'rails_helper'

RSpec.describe 'SchoolYear rollover', type: :request do
  let(:school) { create(:school) }
  let!(:active_year) { create(:school_year, :active, school: school, year: 2026) }
  let!(:planning_year) { create(:school_year, school: school, year: 2027) }
  let(:admin) { create(:user, :admin) }
  let!(:old_manager) do
    create(:user, :teacher, school_year: active_year, school_role: 'manager',
                            login_id: 'old-manager')
  end
  let!(:planning_manager) do
    create(:user, :teacher, school_year: planning_year, school_role: 'manager',
                            login_id: 'new-manager')
  end

  def rollover(target: planning_year, target_id: target.id)
    post school_planning_rollover_path(school), params: { school_year_id: target_id }
  end

  it 'lets a global admin rollover and redirects to the School overview' do
    sign_in admin

    rollover

    expect(response).to redirect_to(school_path(school))
    expect(flash[:notice]).to eq(I18n.t('school_years.rollover.success', year: planning_year.year))
    expect(active_year.reload).to be_archived
    expect(planning_year.reload).to be_active
  end

  it 'makes the new manager operational and removes old manager authority' do
    sign_in admin

    rollover

    expect(planning_manager.reload).to be_current_operational_manager
    expect(old_manager.reload).not_to be_current_operational_manager
  end

  it 'rejects the archived former manager after rollover' do
    sign_in admin
    rollover
    sign_in old_manager.reload

    get school_path(school)

    expect(response).to redirect_to(school_teacher_login_path(school))
  end

  it 'allows the new manager to use existing operational authority after login' do
    sign_in admin
    rollover
    sign_in planning_manager.reload

    get school_path(school)

    expect(response).to have_http_status(:ok)
  end

  it 'does not create another planning SchoolYear' do
    sign_in admin

    expect { rollover }.not_to change(SchoolYear, :count)

    expect(school.school_years.planning).to be_empty
  end

  it 'rejects the current operational manager' do
    sign_in old_manager

    expect { rollover }.not_to(change { [active_year.reload.status, planning_year.reload.status] })

    expect(response).to redirect_to(root_path)
  end

  it 'rejects an ordinary teacher' do
    teacher = create(:user, :teacher, school_year: active_year, school_role: 'member',
                                      login_id: 'ordinary-rollover')
    sign_in teacher

    rollover

    expect(response).to redirect_to(root_path)
  end

  it 'rejects a planning Teacher actor' do
    sign_in planning_manager

    rollover

    expect(response).to redirect_to(root_path)
  end

  it 'requires authentication' do
    rollover

    expect(response).to redirect_to(new_user_session_path)
  end

  it 'fails closed for an inactive School' do
    school.update!(active: false)
    sign_in admin

    rollover

    expect(response).to have_http_status(:not_found)
  end

  it 'fails closed when the planning year no longer exists' do
    target_id = planning_year.id
    planning_manager.destroy!
    planning_year.destroy!
    sign_in admin

    rollover(target_id: target_id)

    expect(response).to redirect_to(school_path(school))
    expect(active_year.reload).to be_active
  end

  it 'rejects a planning year without a manager' do
    planning_manager.update!(school_role: 'member')
    sign_in admin

    rollover

    expect(response).to redirect_to(school_planning_path(school))
    expect(active_year.reload).to be_active
  end

  it 'fails closed for a malformed target id' do
    sign_in admin

    rollover(target_id: 'invalid')

    expect(response).to have_http_status(:not_found)
  end

  it 'does not substitute a target from another School' do
    other_school = create(:school)
    create(:school_year, :active, school: other_school, year: 2026)
    other_target = create(:school_year, school: other_school, year: 2027)
    sign_in admin

    rollover(target: other_target)

    expect(response).to redirect_to(school_path(school))
    expect(active_year.reload).to be_active
  end

  it 'rejects an active SchoolYear disguised as the target' do
    sign_in admin

    rollover(target: active_year)

    expect(response).to redirect_to(school_path(school))
    expect(active_year.reload).to be_active
  end

  it 'rejects an archived SchoolYear disguised as the target' do
    archived_year = create(:school_year, :archived, school: school, year: 2025)
    sign_in admin

    rollover(target: archived_year)

    expect(response).to redirect_to(school_path(school))
    expect(active_year.reload).to be_active
  end

  it 'rejects a non-consecutive planning year' do
    planning_year.update!(year: 2028)
    sign_in admin

    rollover

    expect(response).to redirect_to(school_path(school))
    expect(active_year.reload).to be_active
  end

  it 'rejects a repeated stale request after a successful rollover' do
    sign_in admin
    rollover

    post school_planning_rollover_path(school), params: { school_year_id: planning_year.id }

    expect(response).to redirect_to(school_path(school))
    expect(school.school_years.active).to contain_exactly(planning_year)
    expect(active_year.reload).to be_archived
  end

  it 'shows the rollover control only to an eligible global admin' do
    sign_in admin

    get school_planning_path(school)

    document = Nokogiri::HTML(response.body)
    form = document.at_css(
      %(form[action="#{school_planning_rollover_path(school)}"][method="post"])
    )
    expect(form).to be_present
    expect(form.at_css(%(input[name="school_year_id"][value="#{planning_year.id}"]))).to be_present
  end

  it 'hides the rollover control when the planning manager is missing' do
    planning_manager.update!(school_role: 'member')
    sign_in admin

    get school_planning_path(school)

    document = Nokogiri::HTML(response.body)
    expect(document.at_css(%(form[action="#{school_planning_rollover_path(school)}"]))).to be_nil
    expect(response.body).to include(I18n.t('schools.planning.rollover.manager_required'))
  end

  it 'hides the rollover control from the current manager' do
    sign_in old_manager

    get school_planning_path(school)

    document = Nokogiri::HTML(response.body)
    expect(document.at_css(%(form[action="#{school_planning_rollover_path(school)}"]))).to be_nil
  end
end
