# app/controllers/classrooms_controller.rb

class ClassroomsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_classroom, only: %i[
    show destroy
  ]
  before_action :set_lifecycle_classroom, only: %i[deactivate reactivate]

  def index
    # index는 policy_scope만 요구(verify_policy_scoped 훅 통과)
    classrooms_scope = policy_scope(Classroom)
    if current_user.current_operational_teacher? && !current_user_school_manager?
      assigned_landing_path = regular_teacher_landing_path_for(current_user)
      return redirect_to(assigned_landing_path) unless assigned_landing_path == classrooms_path
    end

    prepare_school_filter if current_user.admin?
    if current_user.admin? && @selected_school
      classrooms_scope = classrooms_scope.where(school_years: { school_id: @selected_school.id })
    end
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
      if current_user.admin?
        classroom_ids.to_set
      elsif current_user_school_manager?
        classroom_ids.to_set
      elsif current_user.current_operational_teacher?
        assigned_classroom_ids
      else
        Set.new
      end
    @member_manageable_classroom_ids =
      if current_user.admin?
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
    @classroom = Classroom.new
    assign_classroom_school_year
    prepare_classroom_form
  end

  def create
    authorize Classroom
    @classroom = Classroom.new
    assign_classroom_school_year
    @classroom.assign_attributes(classroom_params)

    if @classroom.school_year&.school&.inactive?
      @classroom.errors.add(:school_year, t('school_status.inactive_school'))
      prepare_classroom_form
      render :new, status: :unprocessable_content
    elsif @classroom.save
      redirect_to classroom_path(@classroom), notice: t('classrooms.create.success')
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

    policy(@classroom).manage_structure?
  end

  def load_school_options
    @school_options = policy_scope(School).active.order(:name, :id)
  end

  def prepare_classroom_form
    load_school_options if current_user.admin?
  end

  def current_user_school_manager?
    current_user&.current_operational_manager?
  end

  def prepare_school_filter
    @filter_schools = policy_scope(School).active.order(:name, :id).load
    @selected_school = @filter_schools.detect { |school| school.id == school_filter_id }
  end

  def school_filter_id
    value = params[:school_id].to_s
    return nil unless value.match?(/\A[1-9]\d*\z/)

    value.to_i
  end

  def grade_filter
    value = params[:grade].to_s
    return nil unless value.match?(/\A[1-6]\z/)

    value.to_i
  end

  def assign_classroom_school_year
    if current_user.admin?
      school_id = params.dig(:classroom, :school_id)
      return if school_id.blank?

      school = policy_scope(School).active.find_by(id: school_id)
      @classroom.school_year = school&.active_school_year
    elsif current_user_school_manager?
      @classroom.school_year = current_user.school_year
    end
  end

  def classrooms_index_title_key
    return 'classrooms.index.admin_title' if current_user.admin?
    return 'classrooms.index.manager_title' if current_user_school_manager?

    'classrooms.index.teacher_title'
  end
end
