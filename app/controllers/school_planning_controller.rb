class SchoolPlanningController < ApplicationController
  before_action :authenticate_user!

  def show
    @school = policy_scope(School).active.find(params[:school_id])
    @planning_school_year = @school.school_years.planning.first!
    authorize @planning_school_year, :show?

    planning_teachers = @planning_school_year.users.teacher
    planning_classrooms = @planning_school_year.classrooms
    active_teachers = planning_teachers.active
    active_classrooms = planning_classrooms.active

    @planning_preparation_summary = {
      teacher_count: active_teachers.count,
      classroom_count: active_classrooms.count,
      assigned_classroom_count: HomeroomAssignment.current.where(
        classroom_id: active_classrooms.select(:id),
        teacher_id: active_teachers.select(:id)
      ).count
    }
    @planning_teacher_path = teachers_path(
      school_id: @school.id,
      school_year_id: @planning_school_year.id
    )
    @planning_classroom_path = classrooms_path(
      school_id: @school.id,
      school_year_id: @planning_school_year.id
    )
    @planning_managers = planning_teachers.where(school_role: "manager").order(:id)
    @planning_manager_candidates = planning_teachers.active.order(:school_role, :id)
    @can_manage_planning_manager = policy(@school).manage_planning_managers?
    @rollover_eligibility = SchoolYears::RolloverEligibility.new(school_year: @planning_school_year)
    @rollover_error_key = @rollover_eligibility.error_key
    @can_rollover = policy(@school).rollover? && @rollover_eligibility.eligible?
    @can_cancel_planning = policy(@planning_school_year).cancel?
    @cancellation_summary = {
      teacher_count: planning_teachers.count,
      classroom_count: planning_classrooms.count
    }
  end

  def destroy
    @school = policy_scope(School).active.find(params[:school_id])
    planning_year = @school.school_years.planning.find(positive_school_year_id!)
    authorize planning_year, :cancel?

    result = SchoolYears::CancelPlanning.call(
      actor: current_user,
      school: @school,
      target_school_year_id: planning_year.id,
      confirmation_year: params[:confirmation_year]
    )

    redirect_to school_path(@school),
      notice: t("school_years.cancellation.success", year: result.year),
      status: :see_other
  rescue SchoolYears::CancelPlanning::InvalidState => error
    redirect_to school_planning_path(@school),
      alert: t("school_years.cancellation.errors.#{error.key}"),
      status: :see_other
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotDestroyed
    redirect_to school_planning_path(@school),
      alert: t("school_years.cancellation.errors.destruction_failed"),
      status: :see_other
  end

  private

  def positive_school_year_id!
    value = params[:school_year_id].to_s
    raise ActiveRecord::RecordNotFound unless value.match?(/\A[1-9]\d*\z/)

    value.to_i
  end
end
