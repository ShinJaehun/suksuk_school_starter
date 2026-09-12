class TeacherSessionsController < ApplicationController
  skip_after_action :verify_authorized
  skip_after_action :verify_policy_scoped
  skip_before_action :expire_ineligible_teacher_session
  skip_before_action :expire_student_session_if_inactive

  def new
    @school = School.find(params[:school_id])
    prepare_login_contexts
  end

  def create
    @school = School.find(params[:school_id])
    prepare_login_contexts
    login_id = params.dig(:teacher, :login_id).to_s.strip.downcase
    school_year = selected_login_school_year
    teacher = authentication_candidate(school_year, login_id) if login_id.present?
    limiter = UserPasswordAttemptLimiter.new(
      school_id: @school.id,
      login_id:,
      credential_generation: teacher&.encrypted_password,
      remote_ip: request.remote_ip
    )
    return render_throttled if limiter.blocked?

    if teacher&.active? && teacher.valid_password?(params.dig(:teacher, :password).to_s)
      limiter.reset
      sign_in(:user, teacher)
      redirect_to teacher.password_change_required? ? edit_forced_password_path : after_sign_in_path_for(teacher)
    else
      limiter.record_failure
      flash.now[:alert] = t("users.teacher_sessions.invalid")
      render :new, status: limiter.blocked? ? :too_many_requests : :unprocessable_content
    end
  end

  private

  def prepare_login_contexts
    @active_school_year = @school.active? ? @school.active_school_year : nil
    @planning_school_year = eligible_planning_school_year
    @login_school_years = [@active_school_year, @planning_school_year].compact
    @selected_school_year_id = submitted_school_year_id || @active_school_year&.id
  end

  def eligible_planning_school_year
    return unless @school.active? && @active_school_year

    planning_year = @school.planning_school_year
    return unless planning_year&.year == @active_school_year.year + 1
    return unless planning_year.users.teacher.active.where(school_role: 'manager').count == 1

    planning_year
  end

  def submitted_school_year_id
    value = params.dig(:teacher, :school_year_id).to_s
    return if value.blank?
    return value.to_i if value.match?(/\A[1-9]\d*\z/)

    false
  end

  def selected_login_school_year
    return unless @selected_school_year_id

    @login_school_years.find { |school_year| school_year.id == @selected_school_year_id }
  end

  def authentication_candidate(school_year, login_id)
    return unless school_year

    scope = school_year.users.teacher.active
    scope = scope.where(school_role: 'manager') if school_year.planning?
    scope.find_by(login_id: login_id)
  end

  def render_throttled
    flash.now[:alert] = t("users.sessions.throttled")
    render :new, status: :too_many_requests
  end
end
