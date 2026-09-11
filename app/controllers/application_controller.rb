class ApplicationController < ActionController::Base
  STUDENT_SESSION_TTL = 20.minutes

  include Pundit::Authorization
  include Pagy::Method

  helper_method :navigation_context, :current_student, :student_signed_in?

  before_action :configure_permitted_parameters, if: :devise_controller?
  before_action :expire_ineligible_teacher_session
  before_action :require_teacher_password_change
  before_action :expire_student_session_if_inactive

  def after_sign_in_path_for(resource_or_scope)
    role_landing_path_for(resource_or_scope)
  end

  rescue_from Pundit::NotAuthorizedError do
    respond_to do |format|
      format.html do
        redirect_to(root_path, alert: t('errors.not_authorized'))
      end
      format.json do
        render json: { ok: false, error: 'not_authorized' }, status: :forbidden
      end
      format.any do
        head :forbidden
      end
    end
  end

  # 개발 시 권한 체크 누락 방지: index는 policy_scope, 그 외는 authorize 요구
  after_action :verify_authorized, unless: :skip_pundit_verify_authorized?
  after_action :verify_policy_scoped, if: :pundit_verify_policy_scoped?

  protected

  def current_student
    return @current_student if defined?(@current_student)

    student = Student.includes(classroom: { school_year: :school }).find_by(id: session[:student_id])
    @current_student = student_session_eligible?(student) ? student : nil
  end

  def student_signed_in?
    current_student.present?
  end

  def student_session_eligible?(student, classroom_id: session[:student_login_classroom_id])
    return false unless student&.active?
    return false if classroom_id.blank? || student.classroom_id.to_s != classroom_id.to_s

    classroom = student.classroom
    classroom.active? && classroom.school_year.active? && classroom.school_year.school.active?
  end

  def clear_student_session
    session.delete(:student_id)
    session.delete(:student_login_classroom_id)
    session.delete(:student_last_seen_at)
    remove_instance_variable(:@current_student) if defined?(@current_student)
  end

  def pundit_user
    current_user || current_student
  end

  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_up, keys: [:name])
    devise_parameter_sanitizer.permit(:account_update, keys: %i[name gender avatar_key])
  end

  private

  def navigation_context
    return {} unless request.format.html?
    return @navigation_context if defined?(@navigation_context)

    if current_user
      @navigation_context = { user: current_user }
    elsif current_student
      return @navigation_context = { student: current_student }
    else
      return @navigation_context = {}
    end

    return @navigation_context unless current_user.current_operational_teacher?

    manager = current_user if current_user.current_operational_manager?

    @navigation_context.merge!(
      manager: manager,
      classrooms: manager ? [] : teacher_nav_classrooms
    )
  end

  def teacher_nav_classrooms
    return [] unless current_user&.current_operational_teacher?
    return @teacher_nav_classrooms if defined?(@teacher_nav_classrooms)

    classroom = current_user.assigned_classroom
    @teacher_nav_classrooms = if classroom&.active? &&
                                 classroom.school_year.active? && classroom.school_year.school.active?
                                [classroom]
                              else
                                []
                              end
  end

  def expire_ineligible_teacher_session
    return unless current_user&.teacher?
    return if current_user.current_operational_teacher?

    school = current_user.school_year&.school
    message_key = current_user.inactive? ? 'devise.failure.inactive' : 'users.sessions.teacher_ineligible'
    sign_out(:user)
    redirect_to school ? school_teacher_login_path(school) : new_user_session_path, alert: t(message_key)
  end

  def require_teacher_password_change
    return unless current_user&.teacher? && current_user.password_change_required?

    redirect_to edit_forced_password_path
  end

  def expire_student_session_if_inactive
    return unless session[:student_id].present?
    return if student_session_ttl_exempt_controller?

    classroom_id = session[:student_login_classroom_id]
    unless current_student
      clear_student_session
      return redirect_to student_session_timeout_redirect_path(classroom_id),
                         alert: '사용 시간이 지나 자동으로 로그아웃되었습니다. 다시 로그인해 주세요.'
    end

    now = Time.current.to_i
    last_seen_at = session[:student_last_seen_at]

    unless last_seen_at.present?
      session[:student_last_seen_at] = now
      return
    end

    if now - last_seen_at.to_i > STUDENT_SESSION_TTL.to_i
      classroom_id = session[:student_login_classroom_id]
      clear_student_session
      redirect_to student_session_timeout_redirect_path(classroom_id),
                  alert: '사용 시간이 지나 자동으로 로그아웃되었습니다. 다시 로그인해 주세요.'
    else
      session[:student_last_seen_at] = now
    end
  end

  def student_session_ttl_exempt_controller?
    devise_controller? || is_a?(StudentSessionsController)
  end

  def student_session_timeout_redirect_path(classroom_id)
    return new_student_session_path if classroom_id.blank?

    classroom = Classroom.find_by(id: classroom_id)
    return new_student_session_path unless classroom

    public_student_login_path(student_login_token: classroom.student_login_token)
  end

  def role_landing_path
    role_landing_path_for(current_user)
  end

  def role_landing_path_for(user)
    return schools_path if user.admin?

    return school_path(user.annual_school) if user.current_operational_manager?

    regular_teacher_landing_path_for(user)
  end

  def regular_teacher_landing_path_for(user)
    classroom = user.assigned_classroom
    if classroom&.active? && classroom.school_year.active? && classroom.school_year.school.active?
      classroom_path(classroom)
    else
      classrooms_path
    end
  end

  # index가 아닌 액션에서는 authorize 검증, Devise 컨트롤러는 제외
  def skip_pundit_verify_authorized?
    devise_controller? || action_name == 'index'
  end

  # index 액션에서만 policy_scope 검증, Devise 컨트롤러는 제외
  def pundit_verify_policy_scoped?
    !devise_controller? && action_name == 'index'
  end
end
