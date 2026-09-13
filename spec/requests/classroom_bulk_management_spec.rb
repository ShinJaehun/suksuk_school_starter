require "rails_helper"

RSpec.describe "Classroom bulk management", type: :request do
  let(:school) { create(:school) }
  let(:active_year) { create(:school_year, :active, school: school, year: 2026) }
  let(:planning_year) { create(:school_year, school: school, year: 2027) }
  let(:manager) { create(:user, :teacher, school_year: active_year, school_role: "manager", login_id: "class-bulk-manager") }
  let(:planning_manager) { create(:user, :teacher, school_year: planning_year, school_role: "manager", login_id: "planning-class-bulk-manager") }

  def context(year)
    { school_id: school.id, school_year_id: year.id }
  end

  it "keeps the existing Classroom card UI at /classrooms without bulk controls" do
    classroom = create(:classroom, school_year: active_year)
    sign_in manager
    get classrooms_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(classroom_path(classroom))
    expect(response.body).not_to include("classroom_bulk_update", bulk_setup_admin_classrooms_path)
  end

  it "renders grade tabs and bulk controls at /admin/classrooms" do
    sign_in manager
    get admin_classrooms_path

    document = Nokogiri::HTML(response.body)
    expect(response).to have_http_status(:ok)
    expect(document.css("a").map(&:text)).to include("전체", "1학년", "2학년", "3학년", "4학년", "5학년", "6학년")
    expect(document.at_css("form#classroom_bulk_update")).to be_present
    expect(document.at_css(%(a[href^="#{bulk_setup_admin_classrooms_path}"]))).to be_present
    expect(document.at_css('[data-management-filter-panel]')).to be_present
  end

  it "keeps current and planning manager default contexts" do
    active_year
    planning_year
    sign_in manager
    get admin_classrooms_path
    expect(Nokogiri::HTML(response.body).at_css(%(option[value="#{active_year.id}"][selected]))).to be_present

    sign_in planning_manager
    get admin_classrooms_path
    expect(Nokogiri::HTML(response.body).at_css(%(option[value="#{planning_year.id}"][selected]))).to be_present
  end

  it "allows both managers to select own active/planning and preserves bulk setup context" do
    [manager, planning_manager].each do |actor|
      sign_in actor
      [active_year, planning_year].each do |year|
        get bulk_setup_admin_classrooms_path, params: context(year)
        expect(response).to have_http_status(:ok)
        document = Nokogiri::HTML(response.body)
        expect(document.at_css(%(input[name="school_id"][value="#{school.id}"]))).to be_present
        expect(document.at_css(%(input[name="school_year_id"][value="#{year.id}"]))).to be_present
      end
    end
  end

  it "shows the School selector to a global admin" do
    sign_in create(:user, :admin)
    get admin_classrooms_path
    expect(Nokogiri::HTML(response.body).at_css("select[name='school_id']")).to be_present
  end

  it "renders archive read-only and fails closed for mutation and other Schools" do
    archived = create(:school_year, :archived, school: school, year: 2025)
    classroom = create(:classroom, school_year: archived)
    sign_in manager
    get admin_classrooms_path, params: context(archived)
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("classroom_bulk_update", bulk_setup_admin_classrooms_path)

    patch bulk_update_admin_classrooms_path, params: context(archived).merge(
      classrooms: { rows: { "0" => { id: classroom.id, grade: 4, class_label: "변경" } } }
    )
    expect(response).to have_http_status(:not_found)

    other_school = create(:school)
    other_year = create(:school_year, :active, school: other_school)
    get admin_classrooms_path, params: { school_id: other_school.id, school_year_id: other_year.id }
    expect(response).to have_http_status(:not_found)
  end

  it "denies an ordinary Teacher direct access" do
    teacher = create(:user, :teacher, school_year: active_year, school_role: "member", login_id: "ordinary-class-bulk")
    sign_in teacher
    get admin_classrooms_path
    expect(response).to redirect_to(root_path)
  end
end
