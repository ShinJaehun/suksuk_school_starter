require 'rails_helper'

RSpec.describe 'Planning year cancellation', type: :request do
  let(:school) { create(:school) }
  let!(:active_year) { create(:school_year, :active, school:, year: 2026) }
  let!(:planning_year) { create(:school_year, school:, year: 2027) }
  let(:admin) { create(:user, :admin) }
  let!(:current_manager) do
    create(:user, :teacher, school_year: active_year, school_role: 'manager', login_id: 'current-manager')
  end
  let!(:planning_manager) do
    create(:user, :teacher, school_year: planning_year, school_role: 'manager', login_id: 'planning-manager')
  end

  def cancel(actor: admin, school_year_id: planning_year.id, confirmation_year: planning_year.year.to_s)
    sign_in actor
    delete school_planning_path(school), params: { school_year_id:, confirmation_year: }
  end

  it 'shows the danger form only to a global admin' do
    sign_in admin
    get school_planning_path(school)

    form = Nokogiri::HTML(response.body).at_css(%(form[action="#{school_planning_path(school)}"] input[name="confirmation_year"]))
    expect(form).to be_present

    sign_in current_manager
    get school_planning_path(school)
    expect(Nokogiri::HTML(response.body).at_css(%(input[name="confirmation_year"]))).to be_nil

    sign_in planning_manager
    get school_planning_path(school)
    expect(Nokogiri::HTML(response.body).at_css(%(input[name="confirmation_year"]))).to be_nil
  end

  it 'lets a global admin cancel and start the same next year again' do
    planning_year_id = planning_year.id

    cancel

    expect(response).to redirect_to(school_path(school))
    expect(flash[:notice]).to eq(I18n.t('school_years.cancellation.success', year: 2027))
    expect(SchoolYear.exists?(planning_year_id)).to eq(false)

    result = SchoolYears::CreatePlanning.call(actor: admin, school: school)
    expect(result).to be_persisted
    expect(result.year).to eq(2027)
  end

  it 'rejects managers, wrong confirmation, and stale or arbitrary targets' do
    ordinary_teacher = create(:user, :teacher, school_year: active_year,
                                               school_role: 'member', login_id: 'ordinary-teacher')

    [current_manager, planning_manager, ordinary_teacher].each do |actor|
      cancel(actor:)
      expect(response).to redirect_to(root_path)
      expect(planning_year.reload).to be_planning
    end

    cancel(confirmation_year: '2026')
    expect(response).to redirect_to(school_planning_path(school))
    expect(planning_year.reload).to be_planning

    cancel(school_year_id: active_year.id)
    expect(response).to have_http_status(:not_found)
    expect(planning_year.reload).to be_planning

    other_school = create(:school)
    create(:school_year, :active, school: other_school, year: 2026)
    other_planning_year = create(:school_year, school: other_school, year: 2027)
    cancel(school_year_id: other_planning_year.id)
    expect(response).to have_http_status(:not_found)

    planning_year.update!(status: :archived)
    cancel(school_year_id: planning_year.id)
    expect(response).to have_http_status(:not_found)
  end

  it 'invalidates the deleted planning manager session on its next request' do
    sign_in planning_manager
    SchoolYears::CancelPlanning.call(actor: admin, school:, target_school_year_id: planning_year.id,
                                     confirmation_year: planning_year.year.to_s)

    get school_path(school)

    expect(response).to redirect_to(school_teacher_login_path(school))
  end
end
