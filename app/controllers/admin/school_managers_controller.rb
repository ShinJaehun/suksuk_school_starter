module Admin
  class SchoolManagersController < Admin::BaseController
    before_action :set_school
    before_action :authorize_admin
    before_action :set_manager_school_year

    def create
      teacher = @manager_school_year.users.teacher.find(params.require(:user_id))
      manager_assigned = false

      User.transaction do
        @manager_school_year.lock!
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
        redirect_to edit_school_path(@school),
          alert: t("admin.school_managers.errors.inactive_manager"),
          status: :see_other
      end
    end

    def destroy
      User.transaction do
        @manager_school_year.lock!
        teacher = @manager_school_year.users.teacher
          .find_by!(id: params[:user_id], school_role: "manager")
        teacher.lock!
        teacher.update!(school_role: "member")
      end
      render_manager_success("admin.school_managers.destroy.success")
    end

    private

    def set_school
      @school = School.find(params[:school_id])
      if params[:school_year_id].present? && @school.inactive?
        raise ActiveRecord::RecordNotFound
      end
    end

    def authorize_admin
      authorize @school, :manage_managers?
    end

    def set_manager_school_year
      @manager_school_year = if params[:school_year_id].present?
        raise ActiveRecord::RecordNotFound unless @school.active?

        @school.school_years.planning.find(positive_school_year_id!)
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
      @manager_school_year.planning? || teacher.active?
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
