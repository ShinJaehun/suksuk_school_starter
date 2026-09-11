class TeacherSessionsController < ApplicationController
  skip_after_action :verify_authorized
  skip_after_action :verify_policy_scoped
  skip_before_action :expire_ineligible_teacher_session
  skip_before_action :expire_student_session_if_inactive

  def new
    @school = School.find(params[:school_id])
  end

  def create
    @school = School.find(params[:school_id])
    login_id = params.dig(:teacher, :login_id).to_s.strip.downcase
    teacher = active_school_year&.users&.teacher&.find_by(login_id: login_id) if login_id.present?
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

  def active_school_year
    return unless @school.active?

    @school.active_school_year
  end

  def render_throttled
    flash.now[:alert] = t("users.sessions.throttled")
    render :new, status: :too_many_requests
  end
end
