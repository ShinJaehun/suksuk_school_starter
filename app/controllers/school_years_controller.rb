class SchoolYearsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_school

  def create
    @school_year = @school.school_years.build(status: :planning)
    authorize @school_year

    @school_year = SchoolYears::CreatePlanning.call(
      actor: current_user,
      school: @school
    )

    if @school_year.persisted?
      redirect_to school_path(@school),
        notice: t("school_years.create.success"),
        status: :see_other
    else
      redirect_to school_path(@school),
        alert: @school_year.errors.full_messages.to_sentence,
        status: :see_other
    end
  end

  private

  def set_school
    @school = policy_scope(School).find(params[:school_id])
  end
end
