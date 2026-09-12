class Classrooms::SettingsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_classroom
  before_action :prepare_classroom_edit_context

  def edit
    authorize @classroom, :edit?
    render "classrooms/edit"
  end

  def update
    authorize @classroom, :manage_structure?

    if association_change_attempt?
      render "classrooms/edit", status: :unprocessable_content
    elsif @classroom.update(classroom_params)
      redirect_to classroom_update_success_path, notice: t("classrooms.update.success")
    else
      render "classrooms/edit", status: :unprocessable_content
    end
  end

  private

  def set_classroom
    @classroom = Classroom.find(params[:id])
  end

  def classroom_params
    permitted = []
    permitted.concat(%i[class_label grade]) if structure_settings_allowed?
    params.require(:classroom).permit(*permitted.uniq)
  end

  def structure_settings_allowed?
    policy(@classroom).manage_structure?
  end

  def association_change_attempt?
    return false unless structure_settings_allowed?

    submitted = params.require(:classroom)
    school_changed = submitted.key?(:school_id) &&
                     submitted[:school_id].to_s != @classroom.school_year.school_id.to_s
    school_year_changed = submitted.key?(:school_year_id) &&
                          submitted[:school_year_id].to_s != @classroom.school_year_id.to_s
    return false unless school_changed || school_year_changed

    @classroom.errors.add(:school_year, :immutable)
    true
  end

  def prepare_classroom_edit_context
    @classroom_edit_context_params = {}
    @show_classroom_lifecycle = @classroom.school_year.active?
    return unless explicit_context? || @classroom.school_year.planning?

    school_id = positive_context_id!(:school_id)
    school_year_id = positive_context_id!(:school_year_id)
    school = School.active.find(school_id)
    school_year = school.school_years.where(status: %i[active planning]).find(school_year_id)

    raise ActiveRecord::RecordNotFound unless school_year == @classroom.school_year
    return unless school_year.planning?

    raise ActiveRecord::RecordNotFound unless planning_context_authorized?(school_year)

    @classroom_edit_context_params = {
      school_id: school.id,
      school_year_id: school_year.id
    }
  end

  def planning_context_authorized?(school_year)
    return true if current_user.admin?
    return false unless current_user.current_operational_manager?

    current_user.annual_school == school_year.school &&
      school_year == school_year.school.planning_school_year &&
      school_year.year == current_user.school_year.year + 1
  end

  def positive_context_id!(key)
    value = params[key].to_s
    raise ActiveRecord::RecordNotFound unless value.match?(/\A[1-9]\d*\z/)

    value.to_i
  end

  def explicit_context?
    params[:school_id].present? || params[:school_year_id].present?
  end

  def classroom_update_success_path
    return @classroom unless @classroom.school_year.planning?

    classrooms_path(@classroom_edit_context_params)
  end
end
