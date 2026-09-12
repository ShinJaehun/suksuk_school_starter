require "rails_helper"

RSpec.describe "School planning preparation", type: :request do
  let(:school) { create(:school, name: "아라초등학교") }
  let!(:active_year) { create(:school_year, :active, school: school, year: 2026) }
  let!(:planning_year) { create(:school_year, school: school, year: 2027) }
  let(:admin) { create(:user, :admin) }
  let(:manager) do
    create(:user, :teacher, :active_annual_teacher,
      annual_school: school,
      annual_school_role: "manager")
  end

  it "lets a global admin view the preparation page" do
    sign_in admin

    get school_planning_path(school)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(school.name, "2027학년도 · 준비 중")
  end

  it "lets the current manager view their own preparation page" do
    sign_in manager

    get school_planning_path(school)

    expect(response).to have_http_status(:ok)
  end

  it "lets the active planning manager view the preparation page without manager controls" do
    planning_manager = create_planning_teacher(name: "다음 관리자", school_role: "manager")
    sign_in planning_manager

    get school_planning_path(school)

    document = Nokogiri::HTML(response.body)
    expect(response).to have_http_status(:ok)
    expect(document.at_css(%(form[action="#{admin_school_school_managers_path(school)}"]))).to be_nil
    expect(document.at_css(%(form[action="#{school_planning_rollover_path(school)}"]))).to be_nil
  end

  it "rejects an ordinary teacher" do
    teacher = create(:user, :teacher, :active_annual_teacher, annual_school: school)
    sign_in teacher

    get school_planning_path(school)

    expect(response).to redirect_to(root_path)
  end

  it "fails closed for a manager from another School" do
    other_school = create(:school)
    other_manager = create(:user, :teacher, :active_annual_teacher,
      annual_school: other_school,
      annual_school_role: "manager")
    sign_in other_manager

    get school_planning_path(school)

    expect(response).to have_http_status(:not_found)
  end

  it "fails closed without a planning SchoolYear" do
    planning_year.destroy!
    sign_in admin

    get school_planning_path(school)

    expect(response).to have_http_status(:not_found)
  end

  it "fails closed for an inactive School" do
    school.update!(active: false)
    sign_in admin

    get school_planning_path(school)

    expect(response).to have_http_status(:not_found)
  end

  it "shows planning counts, status, and context-preserving links" do
    assigned_teacher = create_planning_teacher(name: "배정 교사", grade: 4)
    create_planning_teacher(name: "미배정 교사", grade: 5)
    assigned_classroom = create(:classroom, school_year: planning_year, grade: 4)
    create(:classroom, school_year: planning_year, grade: 5)
    create(:homeroom_assignment,
      teacher: assigned_teacher,
      classroom: assigned_classroom,
      started_on: Date.new(planning_year.year, 3, 1))
    sign_in admin

    get school_planning_path(school)

    document = Nokogiri::HTML(response.body)
    expect(response.body).to include(
      school.name,
      "#{planning_year.year}학년도 · 준비 중",
      "선생님 준비",
      "2명",
      "교실 준비",
      "2개",
      "담임 연결",
      "1 / 2"
    )
    expect(document.at_css(%(a[href="#{teachers_path(school_id: school.id, school_year_id: planning_year.id)}"]))).to be_present
    expect(document.at_css(%(a[href="#{classrooms_path(school_id: school.id, school_year_id: planning_year.id)}"]))).to be_present
  end

  it "links the School overview summary to the preparation page" do
    sign_in admin

    get school_path(school)

    document = Nokogiri::HTML(response.body)
    expect(document.at_css(%(a[href="#{school_planning_path(school)}"]))).to be_present
  end

  it "shows the planning manager empty state" do
    sign_in admin

    get school_planning_path(school)

    expect(response.body).to include("아직 다음 학년도 학교 관리자가 지정되지 않았습니다.")
  end

  it "shows planning manager assignment controls to the current manager in the empty state" do
    candidate = create_planning_teacher(name: "다음 관리자 후보")
    sign_in manager

    get school_planning_path(school)

    document = Nokogiri::HTML(response.body)
    form = document.at_css(%(form[action="#{admin_school_school_managers_path(school)}"]))
    expect(form).to be_present
    expect(form.at_css(%(input[name="school_year_id"][value="#{planning_year.id}"]))).to be_present
    expect(form.at_css(%(option[value="#{candidate.id}"]))).to be_present
  end

  it "shows the planning manager" do
    planning_manager = create_planning_teacher(name: "다음 관리자", school_role: "manager")
    sign_in admin

    get school_planning_path(school)

    expect(response.body).to include("다음 학년도 관리자", planning_manager.name)
  end

  it "shows manager mutation controls to a global admin" do
    planning_manager = create_planning_teacher(name: "다음 관리자", school_role: "manager")
    sign_in admin

    get school_planning_path(school)

    document = Nokogiri::HTML(response.body)
    expect(document.at_css(%(form[action="#{admin_school_school_managers_path(school)}"]))).to be_present
    expect(document.at_css(%(a[href="#{admin_school_manager_path(school, planning_manager, school_year_id: planning_year.id)}"]))).to be_present
  end

  it "shows manager mutation controls to the current manager" do
    planning_manager = create_planning_teacher(name: "다음 관리자", school_role: "manager")
    sign_in manager

    get school_planning_path(school)

    document = Nokogiri::HTML(response.body)
    expect(response.body).to include(planning_manager.name)
    expect(document.at_css(%(form[action="#{admin_school_school_managers_path(school)}"]))).to be_present
    expect(document.at_css(%(a[href="#{admin_school_manager_path(school, planning_manager, school_year_id: planning_year.id)}"]))).to be_present
  end

  it "limits manager candidates to the planning SchoolYear" do
    planning_candidate = create_planning_teacher(name: "다음 후보")
    inactive_candidate = create_planning_teacher(name: "비활성 후보")
    inactive_candidate.update!(active: false)
    active_candidate = create(:user, :teacher, :active_annual_teacher,
      annual_school: school,
      name: "현재 후보")
    other_school = create(:school)
    other_active_year = create(:school_year, :active, school: other_school, year: 2026)
    other_planning_year = create(:school_year, school: other_school, year: other_active_year.year + 1)
    other_candidate = create(:user, :teacher,
      school_year: other_planning_year,
      login_id: generate(:annual_teacher_login_id),
      school_role: "member",
      name: "다른 학교 후보")
    sign_in admin

    get school_planning_path(school)

    document = Nokogiri::HTML(response.body)
    form = document.at_css(%(form input[name="school_year_id"][value="#{planning_year.id}"]))
      .xpath("ancestor::form")
      .first
    option_values = form.css(%(select[name="user_id"] option)).map { |option| option["value"] }
    expect(option_values).to include(planning_candidate.id.to_s)
    expect(option_values).not_to include(
      inactive_candidate.id.to_s,
      active_candidate.id.to_s,
      other_candidate.id.to_s
    )
  end

  it "does not expose planning manager UI on School settings" do
    create_planning_teacher(name: "설정에 나오면 안 됨", school_role: "manager")
    sign_in admin

    get edit_school_path(school)

    expect(response.body).not_to include(
      "다음 학년도 관리자",
      "아직 다음 학년도 학교 관리자가 지정되지 않았습니다.",
      "설정에 나오면 안 됨"
    )
  end

  def create_planning_teacher(name:, grade: 4, school_role: "member")
    create(:user, :teacher,
      school_year: planning_year,
      login_id: generate(:annual_teacher_login_id),
      name: name,
      grade: grade,
      school_role: school_role,
      active: true)
  end
end
