# app/controllers/classrooms_controller.rb

class ClassroomsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_classroom, only: %i[
    show destroy
  ]
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
    redirect_to edit_classroom_path(@classroom),
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
    @classroom = Classroom.find(params[:id])
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
    @classroom_creation_context_explicit = params[:school_id].present? || params[:school_year_id].present?
    @classroom_creation_school = selected_classroom_creation_school
    @classroom_creation_school_year = selected_classroom_creation_school_year
  end

  def selected_classroom_creation_school
    if current_user.admin?
      return nil unless @classroom_creation_context_explicit
      raise ActiveRecord::RecordNotFound if params[:school_id].blank?

      return policy_scope(School).active.find(positive_classroom_context_id!(:school_id))
    end

    school = current_user.annual_school
    if params[:school_id].present? && positive_classroom_context_id!(:school_id) != school.id
      raise ActiveRecord::RecordNotFound
    end

    school
  end

  def selected_classroom_creation_school_year
    return nil unless @classroom_creation_school

    allowed_years = allowed_classroom_creation_years(@classroom_creation_school)
    return allowed_years.find(positive_classroom_context_id!(:school_year_id)) if params[:school_year_id].present?

    allowed_years.find_by!(status: :active)
  end

  def allowed_classroom_creation_years(school)
    return school.school_years.where(status: %i[active planning]) if current_user.admin?

    years = [current_user.school_year]
    planning_year = school.planning_school_year
    years << planning_year if planning_year&.year == current_user.school_year.year + 1
    SchoolYear.where(id: years.map(&:id))
  end

  def current_user_school_manager?
    current_user&.current_operational_manager?
  end

  def prepare_classroom_index_context
    if current_user.admin? && params[:school_year_id].present? && params[:school_id].blank?
      raise ActiveRecord::RecordNotFound
    end

    @show_school_year_selector = true
    @filter_schools = classroom_context_schools
    @selected_school = selected_classroom_context_school
    @school_year_options = allowed_classroom_context_years(@selected_school)
    @selected_school_year = selected_classroom_context_year
    @classroom_context_read_only = @selected_school_year.present? &&
                                   (!@selected_school_year.active? || @selected_school.inactive?)
    @classroom_context_creatable = classroom_context_creatable?
    @new_classroom_path = new_classroom_path(classroom_context_params)
    @classroom_edit_context_params = @selected_school_year&.planning? ? classroom_context_params : {}
  end

  def classroom_context_schools
    return policy_scope(School).order(:name, :id).load if current_user.admin?

    [current_user.annual_school]
  end

  def selected_classroom_context_school
    if current_user.admin?
      return nil if params[:school_id].blank?

      return policy_scope(School).find(positive_classroom_context_id!(:school_id))
    end

    school = current_user.annual_school
    if params[:school_id].present? && positive_classroom_context_id!(:school_id) != school.id
      raise ActiveRecord::RecordNotFound
    end

    school
  end

  def allowed_classroom_context_years(school)
    return SchoolYear.none unless school
    return school.school_years.order(year: :desc) if current_user.admin?

    years = [current_user.school_year]
    planning_year = school.planning_school_year
    years << planning_year if planning_year&.year == current_user.school_year.year + 1
    SchoolYear.where(id: years.map(&:id)).order(year: :desc)
  end

  def selected_classroom_context_year
    if params[:school_year_id].present?
      raise ActiveRecord::RecordNotFound unless @selected_school

      return @school_year_options.find(positive_classroom_context_id!(:school_year_id))
    end

    return nil if current_user.admin? && @selected_school.nil?

    @school_year_options.find_by!(status: :active)
  end

  def classroom_index_scope
    return Classroom.where(school_year_id: @selected_school_year.id) if @selected_school_year

    Classroom.joins(school_year: :school)
             .merge(SchoolYear.active)
             .merge(School.active)
  end

  def classroom_context_creatable?
    return true if current_user.admin? && @selected_school_year.nil?
    return false unless @selected_school_year&.school&.active?
    return false unless @selected_school_year.active? || @selected_school_year.planning?

    current_user.admin? || current_user_school_manager?
  end

  def classroom_context_params
    return {} unless @selected_school_year

    {
      school_id: @selected_school_year.school_id,
      school_year_id: @selected_school_year.id
    }
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
end
