module Admin
  class SchoolManagersController < ApplicationController
    before_action :authenticate_user!
    before_action :set_school
    before_action :set_manager_school_year
    before_action :authorize_manager_mutation

    def create
      teacher = @manager_school_year.users.teacher.find(params.require(:user_id))
      manager_assigned = false

      User.transaction do
        @manager_school_year.lock!
        ensure_authorized_after_lock!
        teacher.lock!

        if teacher_eligible?(teacher)
          current_manager = @manager_school_year.users.teacher
            .where(school_role: "manager")
            .where.not(id: teacher.id)
            .lock
            .first
          current_manager&.update!(school_role: "member")
          teacher.update!(school_role: "manager") unless teacher.school_manager?
          manager_assigned = true
        end
      end

      if manager_assigned
        render_manager_success("admin.school_managers.create.success")
      else
        redirect_to manager_success_path,
          alert: t("admin.school_managers.errors.inactive_manager"),
          status: :see_other
      end
    end

    def destroy
      User.transaction do
        @manager_school_year.lock!
        ensure_authorized_after_lock!
        teacher = @manager_school_year.users.teacher
          .find_by!(id: params[:user_id], school_role: "manager")
        teacher.lock!
        teacher.update!(school_role: "member")
      end
      render_manager_success("admin.school_managers.destroy.success")
    end

    private

    def set_school
      @school = policy_scope(School).find(params[:school_id])
      if params[:school_year_id].present? && @school.inactive?
        raise ActiveRecord::RecordNotFound
      end
    end

    def authorize_manager_mutation
      predicate = @manager_school_year.planning? ? :manage_planning_managers? : :manage_managers?
      authorize @school, predicate
    end

    def set_manager_school_year
      @manager_school_year = if params[:school_year_id].present?
        raise ActiveRecord::RecordNotFound unless @school.active?

        school_year = @school.school_years.planning.find(positive_school_year_id!)
        active_year = @school.active_school_year
        raise ActiveRecord::RecordNotFound unless active_year && school_year.year == active_year.year + 1

        if !current_user.admin? &&
           (!current_user.current_operational_manager? ||
            school_year.year != current_user.school_year.year + 1)
          raise ActiveRecord::RecordNotFound
        end
        school_year
      else
        @school.school_years.active.first!
      end
    end

    def positive_school_year_id!
      value = params[:school_year_id].to_s
      raise ActiveRecord::RecordNotFound unless value.match?(/\A[1-9]\d*\z/)

      value.to_i
    end

    def teacher_eligible?(teacher)
      teacher.active?
    end

    def ensure_authorized_after_lock!
      current_user.reload
      return if current_user.admin?
      return if current_user.current_operational_manager? &&
                current_user.annual_school == @school &&
                @manager_school_year == @school.reload.planning_school_year &&
                @manager_school_year.year == current_user.school_year.year + 1

      raise Pundit::NotAuthorizedError
    end

    def render_manager_success(message_key)
      redirect_to manager_success_path,
        notice: t(message_key),
        status: :see_other
    end

    def manager_success_path
      return edit_school_path(@school) unless @manager_school_year.planning?

      school_planning_path(@school)
    end
  end
end
