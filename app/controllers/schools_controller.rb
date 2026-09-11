class SchoolsController < ApplicationController
  include SchoolWorkspacePrepareable

  before_action :authenticate_user!
  before_action :set_school, only: %i[show edit update]

  def index
    schools_scope = policy_scope(School)
    if current_user.admin?
      @school_status = params[:status].presence_in(%w[active inactive all]) || "active"
      schools_scope = schools_scope.where(active: @school_status == "active") unless @school_status == "all"
    end
    @schools = schools_scope.order(:name, :id).load
    authorize School

    redirect_to school_path(@schools.first) and return if current_user.current_operational_teacher? && @schools.one?

    school_ids = @schools.map(&:id)
    active_year_ids = SchoolYear.active
      .where(school_id: school_ids)
      .pluck(:school_id, :id)
      .group_by(&:first)
      .filter_map { |_school_id, rows| rows.first.last if rows.one? }
    @classroom_counts = Classroom.joins(:school_year)
      .where(school_year_id: active_year_ids)
      .group("school_years.school_id")
      .count
    annual_teachers = User.teacher.active
      .where(school_year_id: active_year_ids)
      .includes(:school_year)
      .to_a
    @teacher_counts = annual_teachers.group_by { |teacher| teacher.school_year.school_id }.transform_values(&:count)
    @managers_by_school_id = annual_teachers
      .select(&:school_manager?)
      .group_by { |teacher| teacher.school_year.school_id }
  end

  def show
    authorize @school, :show?

    prepare_school_workspace
  end

  def edit
    authorize @school, :update?
    prepare_school_settings
  end

  def update
    authorize @school, :update?

    if @school.update(school_params)
      redirect_to edit_school_path(@school),
        notice: t("schools.settings.update.success"),
        status: :see_other
    else
      prepare_school_settings
      render :edit, formats: :html, status: :unprocessable_content
    end
  end

  private

  def set_school
    @school = policy_scope(School).find(params[:id])
  end

  def school_params
    params.require(:school).permit(:name, :color_key)
  end

end
