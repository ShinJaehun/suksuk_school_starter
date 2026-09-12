class TeachersController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_teacher_index!, only: :index
  before_action :authorize_teacher_management!, except: :index
  before_action :prepare_teacher_creation_context, only: %i[new create]
  before_action :set_teacher, only: %i[edit update destroy deactivate reactivate reissue_temporary_password]

  def index
    prepare_index
  end

  def new
    @teacher = User.new(role: :teacher, school_year: @teacher_creation_school_year)
    authorize @teacher, :create?, policy_class: TeacherManagementPolicy
    prepare_form
  end

  def create
    @teacher = User.new(
      normalized_profile_attributes(create_params).merge(
        role: :teacher,
        school_year: @teacher_creation_school_year
      )
    )
    authorize @teacher, :create?, policy_class: TeacherManagementPolicy
    school = managed_school
    membership_grade = normalized_membership_grade
    classroom_id = if @teacher_creation_school_year&.planning?
                     nil
                   else
                     selected_classroom_id(school, membership_grade)
                   end
    unless assignment_invalid?
      result = save_teacher(school, classroom_id, attributes: {},
                                                  membership_grade: membership_grade)
    end

    if result&.success?
      @temporary_password = result.temporary_password
      @teacher_context_return_path = teacher_creation_return_path
      response.headers['Cache-Control'] = 'no-store'
      render :temporary_password
    else
      prepare_form
      flash.now[:alert] = t('admin.teachers.create.failure')
      render :new, status: :unprocessable_content
    end
  end

  def classroom_options
    prepare_classroom_options_context
    school = managed_school
    render partial: 'teachers/classroom_options', locals: classroom_option_locals(school)
  end

  def edit
    authorize @teacher, :update_profile?, policy_class: TeacherManagementPolicy
    @can_reissue_temporary_password = TeacherManagementPolicy.new(
      current_user,
      @teacher
    ).reissue_temporary_password? && !@teacher.school_year.planning?
    @can_destroy_planning_teacher = TeacherManagementPolicy.new(current_user, @teacher).destroy?
    prepare_form
  end

  def update
    authorize @teacher, :update_profile?, policy_class: TeacherManagementPolicy
    school = managed_school
    membership_grade = normalized_membership_grade
    classroom_id = selected_classroom_id(school, membership_grade)
    attributes = normalized_profile_attributes(update_params, current_avatar_key: @teacher.avatar_key)
    unless assignment_invalid?
      result = save_teacher(
        school,
        classroom_id,
        attributes: attributes,
        membership_grade: membership_grade
      )
    end

    if result&.success?
      redirect_to teacher_update_return_path,
                  notice: t('admin.teachers.update.success'),
                  status: :see_other
    else
      prepare_form
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    authorize @teacher, :destroy?, policy_class: TeacherManagementPolicy
    return_path = teacher_update_return_path
    PlanningTeachers::Destroy.call(teacher: @teacher)

    redirect_to return_path,
                notice: t('admin.teachers.destroy.success'),
                status: :see_other
  rescue ActiveRecord::RecordNotDestroyed, ActiveRecord::InvalidForeignKey
    redirect_to edit_teacher_path(@teacher, teacher_form_context_params),
                alert: t('admin.teachers.destroy.failure'),
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

  def reissue_temporary_password
    authorize @teacher, :reissue_temporary_password?, policy_class: TeacherManagementPolicy
    result = AnnualTeacherUsers::TemporaryCredential.call(
      teacher: @teacher,
      actor: current_user,
      action: :temporary_password_reissued
    )

    if result.success?
      @temporary_password = result.temporary_password
      response.headers['Cache-Control'] = 'no-store'
      render :temporary_password
    else
      redirect_to edit_teacher_path(@teacher),
                  alert: t('admin.teachers.temporary_password_reissue.failure'),
                  status: :see_other
    end
  end

  private

  def authorize_teacher_management!
    authorize User, :access?, policy_class: TeacherManagementPolicy
  end

  def authorize_teacher_index!
    authorize User, :index?, policy_class: TeacherManagementPolicy
  end

  def set_teacher
    if params[:school_year_id].present?
      @teacher_edit_school_year = explicit_teacher_management_year
      @teacher = @teacher_edit_school_year.users.teacher.active.find(positive_id_param!(:id))
    else
      @teacher = teacher_management_scope.find(params[:id])
    end
  end

  def prepare_index
    @teacher_status = params[:status].presence_in(%w[active inactive all]) || 'active'
    prepare_teacher_index_context
    scope = policy_scope(
      teacher_index_scope,
      policy_scope_class: TeacherManagementPolicy::IndexScope
    ).with_attached_avatar.includes(
      school_year: :school,
      assigned_classroom: { school_year: :school }
    )
    scope = scope.where(active: @teacher_status == 'active') unless @teacher_status == 'all'
    @teacher_rows = scope.order(:created_at).map { |teacher| teacher_row(teacher) }
  end

  def prepare_teacher_index_context
    if current_user.admin? &&
       params[:school_year_id].present? &&
       params[:school_id].blank?
      raise ActiveRecord::RecordNotFound
    end

    @show_school_year_selector = current_user.admin? || current_user.current_operational_manager?
    @filter_schools = teacher_context_schools
    @selected_school = selected_teacher_context_school
    @school_year_options = allowed_teacher_context_years(@selected_school)
    @selected_school_year = selected_teacher_context_year
    @teacher_context_mutable = teacher_context_mutable?
    @teacher_context_creatable = teacher_context_creatable?
    @new_teacher_path = new_teacher_path(teacher_context_params)
  end

  def prepare_teacher_creation_context
    @teacher_creation_context_explicit = params[:school_year_id].present?
    @teacher_creation_school = selected_teacher_context_school

    @teacher_creation_school_year =
      if @teacher_creation_context_explicit
        raise ActiveRecord::RecordNotFound if current_user.admin? && params[:school_id].blank?

        raise ActiveRecord::RecordNotFound unless @teacher_creation_school

        school_year = @teacher_creation_school.school_years.find(params[:school_year_id])

        raise ActiveRecord::RecordNotFound unless school_year.active? || school_year.planning?

        school_year
      else
        @teacher_creation_school&.school_years&.active&.first
      end

    @planning_teacher_creation = @teacher_creation_school_year&.planning?
  end

  def teacher_context_schools
    return policy_scope(School).order(:name, :id).load if current_user.admin?

    [current_user.annual_school]
  end

  def selected_teacher_context_school
    if current_user.admin?
      return nil if params[:school_id].blank?

      return policy_scope(School).find(positive_id_param!(:school_id))
    end

    school = current_user.annual_school
    raise ActiveRecord::RecordNotFound if params[:school_id].present? && positive_id_param!(:school_id) != school.id

    school
  end

  def allowed_teacher_context_years(school)
    return SchoolYear.none unless school
    return school.school_years.order(year: :desc) if current_user.admin?

    if current_user.current_operational_manager?
      years = school.school_years.archived.to_a << current_user.school_year
      planning_year = school.planning_school_year
      years << planning_year if planning_year&.year == current_user.school_year.year + 1
      return SchoolYear.where(id: years.map(&:id)).order(year: :desc)
    end

    SchoolYear.where(id: current_user.school_year_id)
  end

  def selected_teacher_context_year
    if params[:school_year_id].present?
      raise ActiveRecord::RecordNotFound unless @selected_school

      return @school_year_options.find(positive_id_param!(:school_year_id))
    end

    return nil if current_user.admin? && @selected_school.nil?

    @school_year_options.find_by!(status: :active)
  end

  def teacher_index_scope
    return User.teacher.where(school_year_id: @selected_school_year.id) if @selected_school_year

    User.teacher.joins(:school_year).merge(SchoolYear.active)
  end

  def teacher_context_mutable?
    return true if current_user.admin? && @selected_school_year.nil?
    return false unless @selected_school_year

    candidate = User.new(
      role: :teacher,
      school_year: @selected_school_year,
      school_role: 'member',
      active: true
    )
    return TeacherManagementPolicy.new(current_user, candidate).update_profile? if @selected_school_year.planning?
    return false unless @selected_school_year.active?

    current_user.admin? || current_user.current_operational_manager?
  end

  def teacher_context_creatable?
    candidate = User.new(role: :teacher, school_year: @selected_school_year)
    TeacherManagementPolicy.new(current_user, candidate).create?
  end

  def teacher_context_params
    return {} unless @selected_school_year

    {
      school_id: @selected_school_year.school_id,
      school_year_id: @selected_school_year.id
    }
  end

  def positive_id_param!(key)
    value = params[key].to_s
    raise ActiveRecord::RecordNotFound unless value.match?(/\A[1-9]\d*\z/)

    value.to_i
  end

  def prepare_form
    assigned_classroom = @teacher&.assigned_classroom
    @locked_classroom = assigned_classroom if assigned_classroom&.inactive?
    @schools = manageable_schools
    @selected_school_id = managed_school&.id
    @membership_grade = @locked_classroom ? @teacher.grade : membership_grade_for_form
    @classroom_selection_ready = @selected_school_id.present? && selected_membership_grade.present?
    @classroom_selection_prompt_key = classroom_selection_prompt_key
    @classroom_candidates = @locked_classroom ? Classroom.none : classroom_candidates(managed_school)
    @selected_classroom_id = selected_classroom_id_for_form
    @planning_teacher_creation = @teacher.new_record? && @teacher_creation_school_year&.planning?
    @teacher_form_school_year = @teacher_creation_school_year || @teacher_edit_school_year
    @teacher_form_path = if @teacher.persisted?
                           teacher_path(@teacher, teacher_form_context_params)
                         else
                           teachers_path
                         end
    @teacher_classroom_options_path = classroom_options_teachers_path(
      teacher_form_context_params.merge(teacher_id: @teacher.id)
    )
  end

  def classroom_candidates(school)
    return Classroom.none unless school && selected_membership_grade

    classrooms = teacher_assignment_school_year(school)&.classrooms&.active || Classroom.none
    occupied_classroom_ids = HomeroomAssignment.current
                                               .where.not(teacher_id: @teacher&.id)
                                               .select(:classroom_id)
    classrooms.where(grade: selected_membership_grade)
              .where.not(id: occupied_classroom_ids)
              .order(:class_label, :id)
              .load
  end

  def classroom_option_locals(school)
    {
      classrooms: classroom_candidates(school),
      selected_classroom_id: selected_classroom_id_for_form,
      selection_ready: school.present? && selected_membership_grade.present?,
      selection_prompt_key: classroom_selection_prompt_key
    }
  end

  def classroom_selection_prompt_key
    return 'admin.teachers.form.select_school_and_grade' if current_user.admin?

    'admin.teachers.form.select_grade'
  end

  def selected_membership_grade
    value = if params.key?(:membership_grade)
              params[:membership_grade]
            else
              @teacher&.grade
            end

    value = value.to_s
    value.to_i if value.match?(/\A[1-6]\z/)
  end

  def normalized_membership_grade
    return @normalized_membership_grade if defined?(@normalized_membership_grade)

    value = params[:membership_grade].to_s
    return @normalized_membership_grade = nil if value.blank?
    return @normalized_membership_grade = value.to_i if value.match?(/\A[1-6]\z/)

    @teacher.errors.add(:base, t('admin.teachers.errors.membership_grade_invalid'))
    @assignment_invalid = true
    @normalized_membership_grade = nil
  end

  def membership_grade_for_form
    return params[:membership_grade] if params.key?(:membership_grade)

    @teacher.grade
  end

  def manageable_schools
    @manageable_schools ||=
      if current_user.admin?
        current_school_id = @teacher&.annual_school&.id
        policy_scope(School).active
                            .or(School.where(id: current_school_id))
                            .order(:name, :id)
                            .load
      else
        [manager_school]
      end
  end

  def manager_school
    current_user.annual_school
  end

  def managed_school
    return manager_school unless current_user.admin?
    return @managed_school if defined?(@managed_school)

    unless params.key?(:school_id)
      @managed_school = @teacher.annual_school if @teacher&.persisted?
      return @managed_school
    end

    id = params[:school_id].to_s
    @managed_school = manageable_schools.find { |school| school.id == id.to_i } if id.match?(/\A[1-9]\d*\z/)
  end

  def selected_classroom_id(school, membership_grade)
    raw_id = params[:classroom_id].to_s
    return nil if raw_id.blank?

    classroom = if raw_id.match?(/\A[1-9]\d*\z/) && school && membership_grade
                  teacher_assignment_school_year(school)&.classrooms&.find_by(
                    id: raw_id,
                    grade: membership_grade
                  )
                end
    if classroom&.inactive? &&
       (teacher_assignment_school_year(school)&.planning? || classroom != @teacher.assigned_classroom)
      classroom = nil
    end
    if classroom.nil? || (classroom.teacher && classroom.teacher != @teacher)
      @assignment_invalid = true
      @teacher.errors.add(:base, t('admin.teachers.errors.classroom_not_found'))
    end
    raw_id.to_i
  end

  def selected_classroom_id_for_form
    return params[:classroom_id].presence&.to_i if params.key?(:classroom_id)

    @teacher&.assigned_classroom&.id
  end

  def assignment_invalid?
    if managed_school.nil? && !current_user.admin?
      @teacher.errors.add(:base, t('admin.teachers.errors.school_not_found'))
      @assignment_invalid = true
    end
    @assignment_invalid == true
  end

  def save_teacher(school, classroom_id, attributes:, membership_grade:)
    Teachers::SaveWithAssignment.call(
      teacher: @teacher,
      attributes: attributes,
      school: school,
      membership_grade: membership_grade,
      classroom_id: classroom_id,
      actor: current_user,
      school_year: teacher_save_school_year
    )
  end

  def prepare_classroom_options_context
    return unless params[:school_year_id].present?

    @teacher_edit_school_year = explicit_teacher_management_year
    return if params[:teacher_id].blank?

    @teacher = @teacher_edit_school_year.users.teacher.active.find(
      positive_id_param!(:teacher_id)
    )
    authorize @teacher, :update_profile?, policy_class: TeacherManagementPolicy
  end

  def explicit_teacher_management_year
    raise ActiveRecord::RecordNotFound if current_user.admin? && params[:school_id].blank?

    school = selected_teacher_context_school
    raise ActiveRecord::RecordNotFound unless school&.active?

    allowed_teacher_context_years(school)
      .where(status: %i[active planning])
      .find(positive_id_param!(:school_year_id))
  end

  def teacher_assignment_school_year(school)
    school_year = @teacher_edit_school_year || @teacher_creation_school_year
    return school_year if school_year&.school == school
    return @teacher.school_year if @teacher&.persisted? && @teacher.annual_school == school

    school&.active_school_year
  end

  def teacher_save_school_year
    return @teacher_creation_school_year if @teacher.new_record?
    return @teacher.school_year if @teacher.school_year&.planning?

    nil
  end

  def teacher_form_context_params
    school_year = @teacher_form_school_year || @teacher_edit_school_year
    return {} unless school_year

    {
      school_id: school_year.school_id,
      school_year_id: school_year.id
    }
  end

  def teacher_update_return_path
    return teachers_path unless @teacher.school_year&.planning?

    teachers_path(
      school_id: @teacher.school_year.school_id,
      school_year_id: @teacher.school_year.id
    )
  end

  def teacher_creation_return_path
    return unless @teacher_creation_context_explicit && @teacher_creation_school_year

    teachers_path(
      school_id: @teacher_creation_school_year.school_id,
      school_year_id: @teacher_creation_school_year.id
    )
  end

  def create_params
    params.require(:user).permit(:name, :email, :login_id, :gender, :avatar_key)
  end

  def update_params
    params.require(:user).permit(:name, :email, :login_id, :gender, :avatar_key)
  end

  def normalized_profile_attributes(permitted_params, current_avatar_key: nil)
    attributes = permitted_params.to_h.symbolize_keys
    attributes[:email] = attributes[:email].presence if attributes.key?(:email)
    attributes[:gender] = nil if attributes.key?(:gender) && !%w[male female].include?(attributes[:gender])
    gender = attributes.key?(:gender) ? attributes[:gender] : @teacher&.gender
    avatar_key = attributes[:avatar_key].presence || current_avatar_key
    pool = User.avatar_keys_for(gender).presence || User.avatar_keys_for_role('teacher')
    attributes[:avatar_key] = pool.sample unless pool.include?(avatar_key)
    attributes
  end

  def teacher_management_scope
    policy_scope(User, policy_scope_class: TeacherManagementPolicy::Scope)
  end

  def update_status(active)
    if @teacher.update(active: active, remember_created_at: nil)
      redirect_to edit_teacher_path(@teacher),
                  notice: t(active ? 'teacher_status.reactivated' : 'teacher_status.deactivated'), status: :see_other
    else
      redirect_to edit_teacher_path(@teacher), alert: t('teacher_status.failure'), status: :see_other
    end
  end

  def school_filter_id
    value = params[:school_id].to_s
    value.to_i if value.match?(/\A[1-9]\d*\z/)
  end

  def teacher_row(teacher)
    {
      teacher: teacher,
      school: teacher.annual_school,
      membership_grade: teacher.grade,
      role: teacher.school_role,
      classroom: teacher.assigned_classroom,
      manageable: @teacher_context_mutable && TeacherManagementPolicy.new(current_user, teacher).update_profile?,
      edit_path: edit_teacher_path(teacher, teacher_context_params)
    }
  end
end
