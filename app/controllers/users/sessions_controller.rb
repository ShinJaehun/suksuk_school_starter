class Users::SessionsController < Devise::SessionsController
  skip_before_action :expire_ineligible_teacher_session, only: :create
  skip_before_action :require_teacher_password_change, only: :destroy
  skip_before_action :expire_student_session_if_inactive, only: :create

  def create
    limiter = UserPasswordAttemptLimiter.new(
      email: params.dig(resource_name, :email),
      remote_ip: request.remote_ip
    )
    return render_throttled if limiter.blocked?

    authenticated = false
    failure_payload = catch(:warden) do
      super do
        limiter.reset
        clear_student_session
      end
      authenticated = true
    end

    return if authenticated
    return render_throttled if limiter.record_failure

    throw(:warden, failure_payload)
  end

  def destroy
    teacher_school = current_user&.annual_school if current_user&.teacher?

    super do
      return redirect_to school_teacher_login_path(teacher_school), status: :see_other if teacher_school
    end
  end

  private

  def render_throttled
    request.env.fetch('warden').lock!
    self.resource = resource_class.new(sign_in_params)
    clean_up_passwords(resource)
    flash.now[:alert] = t('users.sessions.throttled')
    render :new, status: :too_many_requests
  end
end
