class Admin::TeachersController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_teacher_management!
  before_action :prepare_bulk_context, except: :index
  before_action :set_teacher,
    only: %i[destroy deactivate reactivate temporary_password reissue_temporary_password]

  def index
    prepare_index_context
    if @teacher_context_mutable
      @bulk_school_year = @selected_school_year
      @grade = valid_management_grade
      prepare_bulk_management
    else
      prepare_read_only_rows
    end
  end

  def bulk_setup
    @grade = valid_bulk_setup_grade
    @count = valid_bulk_count || 10
    render "teachers/bulk_setup"
  end

  def bulk_new
    @grade = valid_bulk_setup_grade
    @count = valid_bulk_count
    unless @grade && @count
      flash.now[:alert] = t("admin.teachers.bulk.errors.setup_invalid")
      @count = params[:count]
      return render "teachers/bulk_setup", status: :unprocessable_content
    end

    row_grade = @grade == "unassigned" ? nil : @grade
    @bulk_entries = Array.new(@count) do
      { grade: row_grade, name: "", login_id: "", gender: "", avatar_key: "", classroom_id: nil, errors: [] }
    end
    prepare_bulk_classrooms
    render "teachers/bulk_new"
  end

  def bulk_create
    @grade = valid_bulk_setup_grade
    @bulk_entries = submitted_bulk_rows

    result = Teachers::BulkCreator.new(
      school_year: @bulk_school_year,
      rows: @bulk_entries,
      actor: current_user
    ).call
    @bulk_entries = result.entries.map(&:to_h)
    prepare_bulk_classrooms

    if result.success?
      render_bulk_credentials(result.credentials)
    else
      flash.now[:alert] = (result.errors + result.entries.flat_map(&:errors)).uniq.to_sentence
      render "teachers/bulk_new", status: :unprocessable_content
    end
  end

  def bulk_update
    @grade = valid_management_grade
    result = Teachers::BulkUpdater.new(
      school_year: @bulk_school_year,
      scope: bulk_teacher_scope,
      rows: submitted_bulk_rows
    ).call

    if result.success?
      redirect_to bulk_management_path, notice: t("admin.teachers.bulk.update_success")
    else
      @bulk_entries = result.entries
      flash.now[:alert] = (result.errors + result.entries.flat_map(&:errors)).uniq.to_sentence
      prepare_bulk_management
      prepare_index_context
      render :index, status: :unprocessable_content
    end
  end

  def bulk_operation
    @grade = valid_management_grade
    result = Teachers::BulkOperator.new(
      actor: current_user,
      school_year: @bulk_school_year,
      scope: bulk_teacher_scope,
      teacher_ids: params[:teacher_ids],
      operation: params[:operation],
      grade: params[:grade]
    ).call

    if result.success?
      redirect_to bulk_management_path, notice: t("admin.teachers.bulk.operation_success")
    else
      redirect_to bulk_management_path, alert: result.error
    end
  end

  def destroy
    authorize @teacher, :destroy?, policy_class: TeacherManagementPolicy
    PlanningTeachers::Destroy.call(teacher: @teacher)
    redirect_to bulk_management_path,
      notice: t("admin.teachers.destroy.success"),
      status: :see_other
  rescue ActiveRecord::RecordNotDestroyed, ActiveRecord::InvalidForeignKey
    redirect_to bulk_management_path,
      alert: t("admin.teachers.destroy.failure"),
      status: :see_other
  end

  def deactivate
    authorize @teacher, :deactivate_teacher?
    update_status(false)
  end

  def reactivate
    authorize @teacher, :reactivate_teacher?
    update_status(true)
  end

  def temporary_password
    authorize @teacher, :reissue_temporary_password?, policy_class: TeacherManagementPolicy
  end

  def reissue_temporary_password
    authorize @teacher, :reissue_temporary_password?, policy_class: TeacherManagementPolicy
    result = AnnualTeacherUsers::TemporaryCredential.call(
      teacher: @teacher,
      actor: current_user,
      action: :temporary_password_reissued
    )

    if result.success?
      @credential = {
        name: @teacher.name,
        login_id: @teacher.login_id,
        temporary_password: result.temporary_password
      }
      response.headers["Cache-Control"] = "no-store"
      render :temporary_password
    else
      redirect_to bulk_management_path,
        alert: t("admin.teachers.temporary_password_reissue.failure"),
        status: :see_other
    end
  end

  private

  def authorize_teacher_management!
    authorize User, :access?, policy_class: TeacherManagementPolicy
  end

  def prepare_index_context
    @filter_schools = teacher_management_context.schools
    @selected_school = teacher_management_context.selected_school
    @school_year_options = teacher_management_context.school_years
    @selected_school_year = teacher_management_context.selected_school_year
    @teacher_context_mutable = @selected_school_year.present? && teacher_management_context.mutable?
    @bulk_context_params = teacher_management_context.context_params(@selected_school_year)
  end

  def prepare_bulk_context
    @bulk_school_year = teacher_management_context.explicit_mutation_school_year
    candidate = User.new(
      role: :teacher,
      school_year: @bulk_school_year,
      school_role: "member",
      active: true
    )
    authorize candidate, :update_profile?, policy_class: TeacherManagementPolicy
    @selected_school = @bulk_school_year.school
    @selected_school_year = @bulk_school_year
    @teacher_context_mutable = true
    @filter_schools = teacher_management_context.schools
    @school_year_options = teacher_management_context.school_years
    @bulk_context_params = teacher_management_context.context_params(@bulk_school_year)
  end

  def prepare_bulk_management
    @school = @selected_school || @bulk_school_year.school
    @bulk_context_params = teacher_management_context.context_params(@bulk_school_year)
    @teachers = bulk_ordered_teachers(filtered_bulk_teacher_scope).includes(:school_year, :assigned_classroom)
    @bulk_permissions = @teachers.to_h do |teacher|
      [teacher.id, {
        deactivate: UserPolicy.new(current_user, teacher).deactivate_teacher?,
        reactivate: UserPolicy.new(current_user, teacher).reactivate_teacher?,
        reissue: TeacherManagementPolicy.new(current_user, teacher).reissue_temporary_password?,
        destroy: TeacherManagementPolicy.new(current_user, teacher).destroy?
      }]
    end
    @bulk_entries ||= @teachers.map do |teacher|
      {
        id: teacher.id,
        name: teacher.name,
        login_id: teacher.login_id,
        grade: teacher.grade,
        classroom_id: teacher.assigned_classroom&.id,
        user: teacher,
        errors: []
      }
    end
    prepare_bulk_classrooms
  end

  def prepare_read_only_rows
    return @teacher_rows = [] unless @selected_school_year

    @teacher_rows = @selected_school_year.users.teacher
                                        .with_attached_avatar
                                        .includes(:assigned_classroom)
                                        .order(:created_at)
  end

  def set_teacher
    @teacher = @bulk_school_year.users.teacher.find(positive_id_param!(:id))
  end

  def bulk_teacher_scope
    @bulk_teacher_scope ||= @bulk_school_year.users.teacher
  end

  def filtered_bulk_teacher_scope
    return bulk_teacher_scope if @grade == "all"

    bulk_teacher_scope.where(grade: @grade == "unassigned" ? nil : @grade.to_i)
  end

  def bulk_ordered_teachers(scope)
    scope.left_joins(:current_homeroom_assignment)
         .order(Arel.sql("CASE WHEN users.school_role = 'manager' THEN 0 WHEN users.active THEN 1 ELSE 2 END"))
         .order(Arel.sql("users.grade ASC NULLS LAST"))
         .order(Arel.sql("CASE WHEN homeroom_assignments.id IS NULL THEN 1 ELSE 0 END"))
         .order(:login_id, :id)
  end

  def prepare_bulk_classrooms
    locked_ids = Array(@teachers).filter_map do |teacher|
      teacher.assigned_classroom&.id if teacher.assigned_classroom&.inactive?
    end
    @teacher_classrooms = @bulk_school_year.classrooms
                                             .where(active: true)
                                             .or(@bulk_school_year.classrooms.where(id: locked_ids))
                                             .order(:grade, :class_label, :id)
    @classrooms = @teacher_classrooms
  end

  def valid_management_grade
    value = params[:grade].presence || params[:management_grade].presence
    value = value.to_s
    value == "unassigned" || value.match?(/\A[1-6]\z/) ? value : "all"
  end

  def valid_bulk_setup_grade
    value = params[:grade].to_s
    return value if value == "unassigned" || value.match?(/\A[1-6]\z/)

    nil
  end

  def valid_bulk_count
    count = Integer(params[:count], exception: false)
    count if count&.between?(1, Teachers::BulkCreator::MAX_ROWS)
  end

  def submitted_bulk_rows
    rows = params.fetch(:teachers, {}).fetch(:rows, {})
    rows = rows.to_unsafe_h if rows.respond_to?(:to_unsafe_h)
    rows.sort_by { |index, _attributes| index.to_i }
        .map { |_index, attributes| attributes.to_h.stringify_keys }
  end

  def bulk_management_path
    admin_teachers_path(@bulk_context_params.merge(grade: @grade))
  end

  def render_bulk_credentials(credentials)
    @credentials = credentials
    @credentials_title = t("admin.teachers.bulk.credentials_title")
    @credentials_return_path = bulk_management_path
    response.headers["Cache-Control"] = "no-store"
    render "teachers/credentials"
  end

  def update_status(active)
    if @teacher.update(active: active, remember_created_at: nil)
      redirect_to bulk_management_path,
        notice: t(active ? "teacher_status.reactivated" : "teacher_status.deactivated"),
        status: :see_other
    else
      redirect_to bulk_management_path,
        alert: @teacher.errors.full_messages.to_sentence.presence || t("teacher_status.failure"),
        status: :see_other
    end
  end

  def positive_id_param!(key)
    value = params[key].to_s
    raise ActiveRecord::RecordNotFound unless value.match?(/\A[1-9]\d*\z/)

    value.to_i
  end

  def teacher_management_context
    @teacher_management_context ||= Teachers::ManagementContext.new(
      actor: current_user,
      params: params,
      schools_scope: policy_scope(School)
    )
  end
end
