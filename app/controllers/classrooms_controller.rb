# app/controllers/classrooms_controller.rb

class ClassroomsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_classroom, only: :show
  before_action :set_destroy_classroom, only: :destroy
  before_action :set_lifecycle_classroom, only: %i[deactivate reactivate]

  def index
    if current_user.current_operational_teacher? && !current_user_school_manager?
      policy_scope(Classroom)

      reject_ordinary_teacher_context_params!
      assigned_landing_path = regular_teacher_landing_path_for(current_user)
      return redirect_to(assigned_landing_path) unless assigned_landing_path == classrooms_path
    end

    prepare_classroom_index_context if current_user.admin? || current_user_school_manager?
    classrooms_scope = policy_scope(
      classroom_index_scope,
      policy_scope_class: ClassroomPolicy::IndexScope
    )
    @selected_grade = grade_filter
    classrooms_scope = classrooms_scope.where(grade: @selected_grade) if @selected_grade
    context = Classrooms::IndexContext.new(classrooms_scope: classrooms_scope)
    @classrooms = context.classrooms
    @classrooms_index_title = t(classrooms_index_title_key)
    classroom_ids = @classrooms.map(&:id)
    @classroom_teachers = context.teachers
    @classroom_student_counts = context.student_counts
    @classroom_student_previews = context.student_previews
    assigned_classroom_ids =
      if current_user.current_operational_teacher?
        classroom_ids.include?(current_user.assigned_classroom&.id) ? [current_user.assigned_classroom.id].to_set : Set.new
      else
        Set.new
      end
    @manageable_classroom_ids =
      if @classroom_context_read_only
        Set.new
      elsif current_user.admin?
        classroom_ids.to_set
      elsif current_user_school_manager?
        classroom_ids.to_set
      elsif current_user.current_operational_teacher?
        assigned_classroom_ids
      else
        Set.new
      end
    @member_manageable_classroom_ids =
      if @classroom_context_read_only
        Set.new
      elsif current_user.admin?
        classroom_ids.to_set
      elsif current_user_school_manager?
        classroom_ids.to_set
      elsif current_user.current_operational_teacher?
        assigned_classroom_ids
      else
        Set.new
      end
    # authorize Classroom  # <- 불필요 (after_action에서 index는 verify_authorized 제외)
  end

  def show
    authorize @classroom
    @can_manage_classroom = policy(@classroom).update?
    @can_manage_classroom_members = policy(@classroom).manage_members?
    context = Classrooms::ShowContext.new(classroom: @classroom)
    @students = context.students
    @homeroom_teacher = context.homeroom_teacher
  end

  def new
    authorize Classroom
    prepare_classroom_creation_context
    @classroom = Classroom.new
    assign_classroom_school_year
    prepare_classroom_form
  end

  def create
    authorize Classroom
    prepare_classroom_creation_context
    @classroom = Classroom.new
    assign_classroom_school_year
    @classroom.assign_attributes(classroom_params)

    if @classroom.school_year&.school&.inactive?
      @classroom.errors.add(:school_year, t('school_status.inactive_school'))
      prepare_classroom_form
      render :new, status: :unprocessable_content
    elsif @classroom.save
      redirect_to classroom_creation_success_path, notice: t('classrooms.create.success')
    else
      prepare_classroom_form
      render :new, status: :unprocessable_content
    end
  end

  def destroy
    authorize @classroom

    if @classroom.school_year.planning?
      PlanningClassrooms::Destroy.call(classroom: @classroom)
      return redirect_to classrooms_path(classroom_destroy_context_params),
                         notice: t('classrooms.destroy.planning_success'),
                         status: :see_other
    end

    if @classroom.destroy
      redirect_to classrooms_path,
                  notice: t('classrooms.destroy.success'),
                  status: :see_other
    else
      redirect_to edit_classroom_path(@classroom),
                  alert: classroom_destroy_error_message,
                  status: :see_other
    end
  rescue ActiveRecord::InvalidForeignKey, ActiveRecord::RecordNotDestroyed
    redirect_to edit_classroom_path(@classroom, classroom_destroy_context_params),
                alert: t('classrooms.destroy.failure'),
                status: :see_other
  end

  def deactivate
    authorize @classroom, :deactivate?
    update_classroom_status(false)
  end

  def reactivate
    authorize @classroom, :reactivate?
    update_classroom_status(true)
  end

  private

  def set_classroom
    unless params[:school_id].present? || params[:school_year_id].present?
      @classroom = Classroom.find(params[:id])
      return
    end

    raise ActiveRecord::RecordNotFound unless
      params[:school_id].present? && params[:school_year_id].present?

    school = School.find(params[:school_id])

    raise ActiveRecord::RecordNotFound if current_user.teacher? && current_user.annual_school != school

    school_year = school.school_years.find(params[:school_year_id])

    if school_year.archived? &&
       !current_user.admin? &&
       !current_user.school_operations_manager_for?(school)
      raise ActiveRecord::RecordNotFound
    end

    @classroom = school_year.classrooms.find(positive_classroom_context_id!(:id))
  end

  def set_destroy_classroom
    unless params[:school_id].present? || params[:school_year_id].present?
      @classroom = policy_scope(Classroom).find(params[:id])
      return
    end

    raise ActiveRecord::RecordNotFound unless params[:school_id].present? && params[:school_year_id].present?

    school = classroom_management_context.selected_school
    school_year = classroom_management_context.planning_mutation_school_year

    @classroom = school_year.classrooms.find(positive_classroom_context_id!(:id))
    @classroom_destroy_context = { school_id: school.id, school_year_id: school_year.id }
  end

  def set_lifecycle_classroom
    @classroom = policy_scope(Classroom).find(params[:id])
  end

  def update_classroom_status(active)
    if @classroom.update(active: active)
      redirect_to classrooms_path,
                  notice: t(active ? 'classroom_status.reactivated' : 'classroom_status.deactivated'),
                  status: :see_other
    else
      redirect_to classroom_path(@classroom),
                  alert: t('classroom_status.failure'),
                  status: :see_other
    end
  end

  def classroom_destroy_error_message
    @classroom.errors.full_messages.to_sentence.presence || t('classrooms.destroy.failure')
  end

  def classroom_destroy_context_params
    @classroom_destroy_context || {}
  end

  def classroom_params
    permitted = []
    permitted.concat(%i[class_label grade]) if structure_settings_allowed?
    permitted << :school_id if current_user.admin?

    params.require(:classroom).permit(*permitted.uniq).except(:school_id)
  end

  def structure_settings_allowed?
    return false unless defined?(@classroom) && @classroom.present?
    return true if @classroom_creation_structure_allowed

    policy(@classroom).manage_structure?
  end

  def load_school_options
    @school_options = policy_scope(School).active.order(:name, :id)
  end

  def prepare_classroom_form
    @classroom_creation_structure_allowed = true
    load_school_options if current_user.admin?
  end

  def prepare_classroom_creation_context
    @classroom_creation_structure_allowed = true
    @classroom_creation_context_explicit = classroom_management_context.creation_context_explicit?
    @classroom_creation_school = classroom_management_context.creation_school
    @classroom_creation_school_year = classroom_management_context.creation_school_year
  end

  def current_user_school_manager?
    current_user&.current_operational_manager? || current_user&.planning_manager_session_eligible?
  end

  def prepare_classroom_index_context
    @show_school_year_selector = true
    @filter_schools = classroom_management_context.schools
    @selected_school = classroom_management_context.selected_school
    @school_year_options = classroom_management_context.school_years
    @selected_school_year = classroom_management_context.selected_school_year
    @classroom_context_read_only = classroom_management_context.read_only?
    @classroom_context_creatable = classroom_management_context.creatable?
    @new_classroom_path = new_classroom_path(classroom_context_params)
    @classroom_edit_context_params = classroom_management_context.edit_context_params
    @classroom_show_context_params = classroom_management_context.show_context_params
  end

  def classroom_index_scope
    return Classroom.where(school_year_id: @selected_school_year.id) if @selected_school_year

    Classroom.joins(school_year: :school)
             .merge(SchoolYear.active)
             .merge(School.active)
  end

  def classroom_context_params
    classroom_management_context.context_params(@selected_school_year)
  end

  def reject_ordinary_teacher_context_params!
    return if params[:school_id].blank? && params[:school_year_id].blank?

    raise ActiveRecord::RecordNotFound
  end

  def positive_classroom_context_id!(key)
    value = params[key].to_s
    raise ActiveRecord::RecordNotFound unless value.match?(/\A[1-9]\d*\z/)

    value.to_i
  end

  def grade_filter
    value = params[:grade].to_s
    return nil unless value.match?(/\A[1-6]\z/)

    value.to_i
  end

  def assign_classroom_school_year
    if @classroom_creation_school_year
      @classroom.school_year = @classroom_creation_school_year
    elsif current_user.admin?
      school_id = params.dig(:classroom, :school_id)
      return if school_id.blank?

      school = policy_scope(School).active.find_by(id: school_id)
      @classroom.school_year = school&.active_school_year
    end
  end

  def classroom_creation_success_path
    if @classroom_creation_context_explicit && @classroom_creation_school_year&.planning?
      return classrooms_path(
        school_id: @classroom_creation_school_year.school_id,
        school_year_id: @classroom_creation_school_year.id
      )
    end

    classroom_path(@classroom)
  end

  def classrooms_index_title_key
    return 'classrooms.index.admin_title' if current_user.admin?
    return 'classrooms.index.manager_title' if current_user_school_manager?

    'classrooms.index.teacher_title'
  end

  def classroom_management_context
    @classroom_management_context ||= Classrooms::ManagementContext.new(
      actor: current_user,
      params: params,
      schools_scope: policy_scope(School)
    )
  end
end
