class SchoolRolloversController < ApplicationController
  before_action :authenticate_user!
  before_action :set_school

  def create
    authorize @school, :rollover?
    result = SchoolYears::Rollover.call(
      school: @school,
      target_school_year_id: positive_school_year_id!
    )

    redirect_to school_path(@school),
      notice: t('school_years.rollover.success', year: result.active_school_year.year),
      status: :see_other
  rescue SchoolYears::Rollover::InvalidState => error
    redirect_to rollover_failure_path(error),
      alert: t("school_years.rollover.errors.#{error.key}", year: rollover_target_year),
      status: :see_other
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    redirect_to school_path(@school),
      alert: t('school_years.rollover.errors.transition_failed'),
      status: :see_other
  end

  private

  def set_school
    @school = policy_scope(School).active.find(params[:school_id])
  end

  def positive_school_year_id!
    value = params[:school_year_id].to_s
    raise ActiveRecord::RecordNotFound unless value.match?(/\A[1-9]\d*\z/)

    value.to_i
  end

  def rollover_failure_path(error)
    return school_planning_path(@school) if %i[manager_missing rollover_not_open].include?(error.key)

    school_path(@school)
  end

  def rollover_target_year
    @school.school_years.find_by(id: params[:school_year_id])&.year
  end
end
