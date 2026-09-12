require "rails_helper"

RSpec.describe "Planning classroom settings", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:school) { create(:school) }
  let!(:active_year) { create(:school_year, :active, school: school, year: 2026) }
  let!(:planning_year) { create(:school_year, school: school, year: 2027) }
  let!(:classroom) do
    create(:classroom, school_year: planning_year, grade: 2, class_label: "준비 학급")
  end
  let(:context) { { school_id: school.id, school_year_id: planning_year.id } }

  def create_manager(target_school = school)
    create(:user, :teacher, :active_annual_teacher,
      annual_school: target_school,
      annual_school_role: "manager")
  end

  def update_classroom(target = classroom, params: {}, request_context: context)
    patch classroom_path(target), params: request_context.merge(
      classroom: {
        class_label: target.class_label,
        grade: target.grade
      }.merge(params)
    )
  end

  it "lets an admin update grade and class label in the selected planning context" do
    sign_in admin

    update_classroom(params: { grade: 4, class_label: "수정 학급" })

    expect(classroom.reload).to have_attributes(grade: 4, class_label: "수정 학급")
    expect(response).to redirect_to(classrooms_path(context))
  end

  it "lets the current manager update their immediately following planning classroom" do
    sign_in create_manager

    update_classroom(params: { grade: 3, class_label: "관리자 학급" })

    expect(classroom.reload).to have_attributes(grade: 3, class_label: "관리자 학급")
    expect(response).to redirect_to(classrooms_path(context))
  end

  it "rejects an ordinary teacher" do
    teacher = create(:user, :teacher, :active_annual_teacher, annual_school: school)
    sign_in teacher

    update_classroom(params: { class_label: "변경 금지" })

    expect(response).to have_http_status(:not_found)
    expect(classroom.reload.class_label).to eq("준비 학급")
  end

  it "fails closed for a cross-school context" do
    other_school = create(:school)
    sign_in admin

    update_classroom(request_context: {
      school_id: other_school.id,
      school_year_id: planning_year.id
    })

    expect(response).to have_http_status(:not_found)
  end

  it "fails closed for a cross-year context" do
    sign_in admin

    update_classroom(request_context: {
      school_id: school.id,
      school_year_id: active_year.id
    })

    expect(response).to have_http_status(:not_found)
  end

  it "fails closed for an archived context" do
    archived_year = create(:school_year, :archived, school: school, year: 2025)
    archived_classroom = create(:classroom, school_year: archived_year)
    sign_in admin

    update_classroom(archived_classroom, request_context: {
      school_id: school.id,
      school_year_id: archived_year.id
    })

    expect(response).to have_http_status(:not_found)
  end

  it "fails closed for an inactive School" do
    school.update!(active: false)
    sign_in admin

    update_classroom

    expect(response).to have_http_status(:not_found)
  end

  it "fails closed for malformed context ids" do
    sign_in admin

    update_classroom(request_context: {
      school_id: "invalid",
      school_year_id: planning_year.id
    })

    expect(response).to have_http_status(:not_found)
  end

  it "fails closed when a manager targets another School's Classroom" do
    other_school = create(:school)
    create(:school_year, :active, school: other_school, year: 2026)
    other_planning_year = create(:school_year, school: other_school, year: 2027)
    other_classroom = create(:classroom, school_year: other_planning_year)
    sign_in create_manager

    update_classroom(other_classroom, request_context: {
      school_id: other_school.id,
      school_year_id: other_planning_year.id
    })

    expect(response).to have_http_status(:not_found)
  end

  it "fails closed when a manager targets a non-following planning year" do
    active_year.update!(year: 2025)
    sign_in create_manager

    update_classroom

    expect(response).to have_http_status(:not_found)
  end

  it "does not allow the SchoolYear to change" do
    other_school = create(:school)
    other_year = create(:school_year, :active, school: other_school, year: 2026)
    sign_in admin

    update_classroom(params: { school_year_id: other_year.id, class_label: "변경 금지" })

    expect(response).to have_http_status(:unprocessable_content)
    expect(classroom.reload).to have_attributes(
      school_year: planning_year,
      class_label: "준비 학급"
    )
  end

  it "allows a grade change when there is no current HomeroomAssignment" do
    sign_in admin

    update_classroom(params: { grade: 5 })

    expect(classroom.reload.grade).to eq(5)
  end

  it "rejects a grade that differs from the current teacher and preserves the assignment" do
    teacher = planning_teacher(login_id: "planning-homeroom")
    assignment = create(:homeroom_assignment,
      classroom: classroom,
      teacher: teacher,
      started_on: Date.new(planning_year.year, 3, 1))
    sign_in admin

    update_classroom(params: { grade: 6 })

    document = Nokogiri::HTML(response.body)
    expect(response).to have_http_status(:unprocessable_content)
    expect(classroom.reload.grade).to eq(2)
    expect(assignment.reload).to be_current
    expect(classroom.teacher).to eq(teacher)
    expect(response.body).to include(
      "담임 선생님이 지정된 교실의 학년은 변경할 수 없습니다. 먼저 선생님 설정에서 담임 배정을 해제해 주세요."
    )
    expect(document.at_css(%(select[name="classroom[grade]"] option[value="6"][selected]))).to be_present
    expect(document.at_css(%(input[name="school_id"][value="#{school.id}"]))).to be_present
    expect(document.at_css(%(input[name="school_year_id"][value="#{planning_year.id}"]))).to be_present
  end

  it "allows a class label change while preserving the current assignment" do
    teacher = planning_teacher(login_id: "planning-label-homeroom")
    assignment = create(:homeroom_assignment,
      classroom: classroom,
      teacher: teacher,
      started_on: Date.new(planning_year.year, 3, 1))
    sign_in admin

    update_classroom(params: { class_label: "이름 수정" })

    expect(classroom.reload.class_label).to eq("이름 수정")
    expect(assignment.reload).to be_current
  end

  it "keeps planning context and submitted values after validation failure" do
    create(:classroom, school_year: planning_year, grade: 2, class_label: "중복")
    sign_in admin

    update_classroom(params: { class_label: "중복" })

    document = Nokogiri::HTML(response.body)
    expect(response).to have_http_status(:unprocessable_content)
    expect(document.at_css(%(input[name="school_id"][value="#{school.id}"]))).to be_present
    expect(document.at_css(%(input[name="school_year_id"][value="#{planning_year.id}"]))).to be_present
    expect(document.at_css(%(input[name="classroom[class_label]"][value="중복"]))).to be_present
  end

  it "includes the exact planning context in the index edit link" do
    sign_in admin

    get classrooms_path(context)

    document = Nokogiri::HTML(response.body)
    expected_path = edit_classroom_path(classroom, context)
    expect(document.at_css(%(a[href="#{expected_path}"]))).to be_present
  end

  it "keeps the existing active-year update redirect" do
    active_classroom = create(:classroom, school_year: active_year, class_label: "운영 학급")
    sign_in admin

    patch classroom_path(active_classroom), params: {
      classroom: { class_label: "운영 수정", grade: active_classroom.grade }
    }

    expect(active_classroom.reload.class_label).to eq("운영 수정")
    expect(response).to redirect_to(classroom_path(active_classroom))
  end

  def planning_teacher(login_id:)
    create(:user, :teacher,
      school_year: planning_year,
      login_id: login_id,
      school_role: "member",
      grade: classroom.grade,
      active: true)
  end
end
