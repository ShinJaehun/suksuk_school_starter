require 'rails_helper'

RSpec.describe 'Classroom deletion', type: :request do
  let(:school) { create(:school) }

  it 'keeps the existing admin deletion behavior for an empty active Classroom' do
    admin = create(:user, :admin)
    classroom = create(:classroom, annual_school: school)
    sign_in admin

    expect do
      delete classroom_path(classroom)
    end.to change(Classroom, :count).by(-1)

    expect(response).to redirect_to(classrooms_path)
    expect(response).to have_http_status(:see_other)
  end

  it 'rejects deleting a classroom with homeroom history' do
    admin = create(:user, :admin)
    teacher = create(:user, :teacher, :active_annual_teacher, annual_school: school)
    classroom = create(:classroom, annual_school: school)
    assign_teacher(classroom, teacher)
    sign_in admin

    expect do
      delete classroom_path(classroom)
    end.not_to change(Classroom, :count)

    expect(response).to redirect_to(edit_classroom_path(classroom))
    expect(response).to have_http_status(:see_other)
    expect(User.exists?(teacher.id)).to eq(true)
    expect(classroom.reload.teacher).to eq(teacher)
    expect(flash[:alert]).to be_present
  end

  it 'rejects direct deletion by an assigned teacher' do
    teacher = create(:user, :teacher, :active_annual_teacher, annual_school: school)
    classroom = create(:classroom, annual_school: school)
    assign_teacher(classroom, teacher)
    sign_in teacher

    expect do
      delete classroom_path(classroom)
    end.not_to change(Classroom, :count)

    expect(response).to redirect_to(root_path)
    expect(response).to have_http_status(:found)
    expect(classroom.reload.teacher).to eq(teacher)
    expect(flash[:notice]).to be_nil
  end

  it 'rejects direct deletion by an unassigned school manager' do
    manager = create(:user, :teacher, :active_annual_teacher,
      annual_school: school,
      annual_school_role: "manager")
    classroom = create(:classroom, annual_school: school)
    sign_in manager

    expect do
      delete classroom_path(classroom)
    end.not_to change(Classroom, :count)

    expect(response).to redirect_to(root_path)
    expect(response).to have_http_status(:found)
    expect(flash[:notice]).to be_nil
  end

  it 'rejects direct deletion by a manager who is also an assigned teacher' do
    manager = create(:user, :teacher, :active_annual_teacher,
      annual_school: school,
      annual_school_role: "manager")
    classroom = create(:classroom, annual_school: school)
    assign_teacher(classroom, manager)
    sign_in manager

    expect do
      delete classroom_path(classroom)
    end.not_to change(Classroom, :count)

    expect(response).to redirect_to(root_path)
    expect(response).to have_http_status(:found)
    expect(classroom.reload.teacher).to eq(manager)
  end

  it 'preserves an admin classroom when a Student exists' do
    admin = create(:user, :admin)
    classroom = create(:classroom, annual_school: school)
    student = create(:student, classroom: classroom, active: false)
    sign_in admin

    expect do
      delete classroom_path(classroom)
    end.not_to change(Classroom, :count)

    expect(response).to redirect_to(edit_classroom_path(classroom))
    expect(response).to have_http_status(:see_other)
    expect(Student.exists?(student.id)).to eq(true)
    expect(flash[:alert]).to include(I18n.t('activerecord.errors.models.classroom.attributes.base.students_present'))
    expect(flash[:notice]).to be_nil
  end

  it 'shows the delete area only on an admin edit page' do
    admin = create(:user, :admin)
    teacher = create(:user, :teacher, :active_annual_teacher, annual_school: school)
    classroom = create(:classroom, annual_school: school)
    assign_teacher(classroom, teacher)
    delete_description = I18n.t('classrooms.edit.delete_description')

    sign_in admin
    get edit_classroom_path(classroom)

    admin_document = Nokogiri::HTML(response.body)
    admin_delete_links = admin_document.css(
      %(a[href="#{classroom_path(classroom)}"][data-turbo-method="delete"])
    )

    expect(response.body).to include(delete_description)
    expect(admin_delete_links).not_to be_empty

    sign_in teacher
    get edit_classroom_path(classroom)

    teacher_document = Nokogiri::HTML(response.body)
    teacher_delete_links = teacher_document.css(
      %(a[href="#{classroom_path(classroom)}"][data-turbo-method="delete"])
    )

    expect(response.body).not_to include(delete_description)
    expect(teacher_delete_links).to be_empty
  end

  it 'hides the delete area from school managers, including assigned managers' do
    manager = create(:user, :teacher, :active_annual_teacher,
      annual_school: school,
      annual_school_role: "manager")
    classroom = create(:classroom, annual_school: school)
    assign_teacher(classroom, manager)
    sign_in manager

    get edit_classroom_path(classroom)

    document = Nokogiri::HTML(response.body)
    classroom_delete_links = document.css(
      %(a[href="#{classroom_path(classroom)}"][data-turbo-method="delete"])
    )

    expect(response.body).not_to include(I18n.t('classrooms.edit.delete_description'))
    expect(classroom_delete_links).to be_empty
  end
end
