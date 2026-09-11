class TeachersController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_teacher_management!
  before_action :set_teacher, only: %i[edit update deactivate reactivate reissue_temporary_password]

  def index
    prepare_index
  end

  def new
    @teacher = User.new(role: :teacher)
    authorize @teacher, :create?, policy_class: TeacherManagementPolicy
    prepare_form
  end

  def create
    @teacher = User.new(normalized_profile_attributes(create_params).merge(role: :teacher))
    authorize @teacher, :create?, policy_class: TeacherManagementPolicy
    school = managed_school
    membership_grade = normalized_membership_grade
    classroom_id = selected_classroom_id(school, membership_grade)
    unless assignment_invalid?
      result = save_teacher(school, classroom_id, attributes: {},
                                                  membership_grade: membership_grade)
    end

    if result&.success?
      @temporary_password = result.temporary_password
      response.headers['Cache-Control'] = 'no-store'
      render :temporary_password
    else
      prepare_form
      flash.now[:alert] = t('admin.teachers.create.failure')
      render :new, status: :unprocessable_content
    end
  end

  def classroom_options
    school = managed_school
    render partial: 'teachers/classroom_options', locals: classroom_option_locals(school)
  end

  def edit
    authorize @teacher, :update_profile?, policy_class: TeacherManagementPolicy
    @can_reissue_temporary_password = TeacherManagementPolicy.new(
      current_user,
      @teacher
    ).reissue_temporary_password?
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
      redirect_to teachers_path, notice: t('admin.teachers.update.success'), status: :see_other
    else
      prepare_form
      render :edit, status: :unprocessable_content
    end
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

  def set_teacher
    @teacher = teacher_management_scope.find(params[:id])
  end

  def prepare_index
    @teacher_status = params[:status].presence_in(%w[active inactive all]) || 'active'
    @filter_schools = manageable_schools
    @selected_school = if current_user.admin?
                         @filter_schools.find do |school|
                           school.id == school_filter_id
                         end
                       else
                         manager_school
                       end
    scope = teacher_management_scope.with_attached_avatar.includes(
      school_year: :school,
      assigned_classroom: { school_year: :school }
    )
    scope = scope.where(active: @teacher_status == 'active') unless @teacher_status == 'all'
    if @selected_school
      scope = scope.joins(:school_year).where(school_years: { school_id: @selected_school.id })
    end
    @teacher_rows = scope.order(:created_at).map { |teacher| teacher_row(teacher) }
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
  end

  def classroom_candidates(school)
    return Classroom.none unless school && selected_membership_grade

    classrooms = school.active_school_year&.classrooms&.active || Classroom.none
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
                  school.active_school_year&.classrooms&.find_by(id: raw_id, grade: membership_grade)
                end
    classroom = nil if classroom&.inactive? && classroom != @teacher.assigned_classroom
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
      actor: current_user
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
      classroom: teacher.assigned_classroom
    }
  end
end
