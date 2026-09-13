class Admin::ClassroomsController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_classroom_management!
  before_action :prepare_bulk_context, except: :index
  before_action :set_classroom, only: %i[destroy deactivate reactivate]

  def index
    prepare_index_context
    if @classroom_context_mutable
      @bulk_school_year = @selected_school_year
      @grade = valid_management_grade
      prepare_management
    else
      prepare_read_only_rows
    end
  end

  def bulk_setup
    @default_grade = valid_setup_grade
    @count = valid_count || 10
    render "classrooms/bulk_setup"
  end

  def bulk_new
    @default_grade = valid_setup_grade
    @count = valid_count
    unless @default_grade && @count
      flash.now[:alert] = t("admin.classrooms.bulk.errors.setup_invalid")
      @count = params[:count]
      return render "classrooms/bulk_setup", status: :unprocessable_content
    end
    @entries = Array.new(@count) do |index|
      { grade: @default_grade, class_label: index + 1, teacher_id: nil, errors: [] }
    end
    prepare_teachers
    render "classrooms/bulk_new"
  end

  def bulk_create
    @default_grade = valid_setup_grade
    result = Classrooms::BulkCreator.new(school_year: @bulk_school_year, rows: submitted_rows).call
    @entries = result.entries
    prepare_teachers
    if result.success?
      redirect_to management_path, notice: t("admin.classrooms.bulk.create_success")
    else
      flash.now[:alert] = (result.errors + result.entries.flat_map(&:errors)).uniq.to_sentence
      render "classrooms/bulk_new", status: :unprocessable_content
    end
  end

  def bulk_update
    @grade = valid_management_grade
    result = Classrooms::BulkUpdater.new(
      school_year: @bulk_school_year, scope: classroom_scope, rows: submitted_rows
    ).call
    if result.success?
      redirect_to management_path, notice: t("admin.classrooms.bulk.update_success")
    else
      @entries = result.entries
      flash.now[:alert] = (result.errors + result.entries.flat_map(&:errors)).uniq.to_sentence
      prepare_management
      prepare_index_context
      render :index, status: :unprocessable_content
    end
  end

  def bulk_operation
    @grade = valid_management_grade
    result = Classrooms::BulkOperator.new(
      actor: current_user, school_year: @bulk_school_year, scope: classroom_scope,
      classroom_ids: params[:classroom_ids], operation: params[:operation], grade: params[:bulk_grade]
    ).call
    if result.success?
      redirect_to management_path, notice: t("admin.classrooms.bulk.operation_success")
    else
      redirect_to management_path, alert: result.error
    end
  end

  def destroy
    authorize @classroom, :destroy?
    if @classroom.school_year.planning?
      PlanningClassrooms::Destroy.call(classroom: @classroom)
    else
      @classroom.destroy!
    end
    redirect_to management_path, notice: t("classrooms.destroy.success"), status: :see_other
  rescue ActiveRecord::RecordNotDestroyed, ActiveRecord::InvalidForeignKey
    redirect_to management_path, alert: t("classrooms.destroy.failure"), status: :see_other
  end

  def deactivate
    authorize @classroom, :deactivate?
    update_status(false)
  end

  def reactivate
    authorize @classroom, :reactivate?
    update_status(true)
  end

  private

  def authorize_classroom_management!
    authorize Classroom, :create?
  end

  def prepare_index_context
    @filter_schools = management_context.schools
    @selected_school = management_context.selected_school
    @school_year_options = management_context.school_years
    @selected_school_year = management_context.selected_school_year
    @classroom_context_mutable = @selected_school_year.present? && management_context.creatable?
    @bulk_context_params = management_context.context_params(@selected_school_year)
  end

  def prepare_bulk_context
    @bulk_school_year = management_context.explicit_mutation_school_year
    authorize Classroom.new(school_year: @bulk_school_year), :create?
    @selected_school = @bulk_school_year.school
    @selected_school_year = @bulk_school_year
    @classroom_context_mutable = true
    @filter_schools = management_context.schools
    @school_year_options = management_context.school_years
    @bulk_context_params = management_context.context_params(@bulk_school_year)
  end

  def prepare_management
    @school = @selected_school || @bulk_school_year.school
    @classrooms = ordered_classrooms(filtered_scope).includes(:teacher)
    @entries ||= @classrooms.map do |classroom|
      { id: classroom.id, grade: classroom.grade, class_label: classroom.class_label,
        teacher_id: classroom.teacher&.id, classroom: classroom, errors: [] }
    end
    @classroom_permissions = @classrooms.to_h do |classroom|
      [classroom.id, {
        update: ClassroomPolicy.new(current_user, classroom).manage_structure?,
        deactivate: ClassroomPolicy.new(current_user, classroom).deactivate?,
        reactivate: ClassroomPolicy.new(current_user, classroom).reactivate?,
        destroy: ClassroomPolicy.new(current_user, classroom).destroy?
      }]
    end
    @student_counts = Student.active.where(classroom_id: @classrooms.map(&:id)).group(:classroom_id).count
    prepare_teachers
  end

  def prepare_teachers
    @teachers = @bulk_school_year.users.teacher.active.order(:grade, :name, :id).includes(:assigned_classroom)
  end

  def prepare_read_only_rows
    @classrooms = @selected_school_year ? @selected_school_year.classrooms.includes(:teacher).order(:grade, :class_label) : []
  end

  def set_classroom
    @classroom = @bulk_school_year.classrooms.find(positive_id!(:id))
  end

  def classroom_scope
    @classroom_scope ||= @bulk_school_year.classrooms
  end

  def filtered_scope
    @grade == "all" ? classroom_scope : classroom_scope.where(grade: @grade.to_i)
  end

  def ordered_classrooms(scope)
    scope.order(:grade, :class_label, :id)
  end

  def submitted_rows
    rows = params.fetch(:classrooms, {}).fetch(:rows, {})
    rows = rows.to_unsafe_h if rows.respond_to?(:to_unsafe_h)
    rows.sort_by { |index, _row| index.to_i }.map { |_index, row| row.to_h.stringify_keys }
  end

  def valid_management_grade
    value = params[:grade].to_s
    value.match?(/\A[1-6]\z/) ? value : "all"
  end

  def valid_setup_grade
    value = params[:grade].to_s
    value if value.match?(/\A[1-6]\z/)
  end

  def valid_count
    value = Integer(params[:count], exception: false)
    value if value&.between?(1, Classrooms::BulkCreator::MAX_ROWS)
  end

  def management_path
    admin_classrooms_path(@bulk_context_params.merge(grade: @grade))
  end

  def update_status(active)
    if @classroom.update(active: active)
      redirect_to management_path,
        notice: t(active ? "classroom_status.reactivated" : "classroom_status.deactivated"), status: :see_other
    else
      redirect_to management_path, alert: t("classroom_status.failure"), status: :see_other
    end
  end

  def positive_id!(key)
    value = params[key].to_s
    raise ActiveRecord::RecordNotFound unless value.match?(/\A[1-9]\d*\z/)

    value.to_i
  end

  def management_context
    @management_context ||= Classrooms::ManagementContext.new(
      actor: current_user, params: params, schools_scope: policy_scope(School)
    )
  end
end
