class Users::RegistrationsController < Devise::RegistrationsController
  before_action :disable_public_registration!, only: %i[new create]
  before_action :set_account_avatar_keys, only: [:edit, :update]
  before_action :authenticate_scope!, only: [:edit_password, :update_password]

  def edit
    self.resource = current_user
  end

  def edit_password
    self.resource = current_user
    clean_up_passwords(resource)
    set_minimum_password_length

    render :edit_password, layout: false
  end

  def update_password
    self.resource = current_user

    if resource.update_with_password(password_update_params)
      bypass_sign_in(resource, scope: resource_name)
      flash.now[:notice] = "비밀번호를 변경했습니다."
      render :update_password, formats: :turbo_stream
    else
      clean_up_passwords(resource)
      set_minimum_password_length
      render :edit_password, formats: :html, layout: false, status: :unprocessable_content
    end
  end

  def destroy
    redirect_to edit_user_registration_path,
      alert: I18n.t("users.registrations.account_deletion_disabled"),
      status: :see_other
  end

  protected

  def update_resource(resource, params)
    filter_account_avatar_params!(resource, params)
    return super if password_change_params?(params) || admin_email_change?(resource, params)

    params.delete(:current_password)
    resource.update_without_password(params)
  end

  def after_update_path_for(resource)
    edit_user_registration_path
  end

  private

  def disable_public_registration!
    redirect_to new_user_session_path,
      alert: I18n.t("users.registrations.public_registration_disabled"),
      status: :see_other
  end

  def set_account_avatar_keys
    @account_avatar_keys = account_avatar_keys_for(current_user).select { |avatar_key| helpers.avatar_asset_key?(avatar_key) }
  end

  def filter_account_avatar_params!(user, params)
    if params[:avatar_key].present? && !account_avatar_keys_for(user).include?(params[:avatar_key])
      params.delete(:avatar_key)
    end

    params.delete(:gender) unless (user.teacher? || user.admin?) && %w[male female].include?(params[:gender])
  end

  def account_avatar_keys_for(user)
    User.avatar_keys_for_role(user&.role)
  end

  def password_change_params?(params)
    params[:password].present? || params[:password_confirmation].present?
  end

  def admin_email_change?(user, params)
    user.admin? && params.key?(:email) && params[:email].to_s.strip.downcase != user.email
  end

  def password_update_params
    params.require(resource_name).permit(:password, :password_confirmation, :current_password)
  end
end
