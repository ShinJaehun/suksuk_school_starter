module SchoolWorkspacePrepareable
  extend ActiveSupport::Concern

  private

  def prepare_school_workspace
    prepare_school_overview
  end

  def prepare_school_overview
    @classroom_count = active_school_year&.classrooms&.count.to_i
    @teacher_count = active_school_teachers.active.count
    @managers = active_school_teachers.active.where(school_role: "manager").order(:id)
    @planning_school_year = @school.planning_school_year
    @next_planning_year = active_school_year&.year&.+(1)
    planning_record = @planning_school_year || @school.school_years.build(status: :planning)
    @can_prepare_planning_school_year = @planning_school_year.present? && policy(planning_record).prepare?
    @can_manage_planning_school_year = @can_prepare_planning_school_year ||
      (@next_planning_year.present? && policy(planning_record).create?)
    @planning_preparation_summary = planning_preparation_summary if @can_prepare_planning_school_year
    if @can_prepare_planning_school_year
      @planning_teacher_path = teachers_path(
        school_id: @school.id,
        school_year_id: @planning_school_year.id
      )
      @planning_classroom_path = classrooms_path(
        school_id: @school.id,
        school_year_id: @planning_school_year.id
      )
    end
  end

  def prepare_school_settings
    @managers = active_school_teachers.where(school_role: "manager").order(:id)
    @manager_candidates = active_school_teachers.active.order(:school_role, :id)
  end

  def active_school_teachers
    active_school_year ? active_school_year.users.teacher : User.none
  end

  def active_school_year
    @active_school_year ||= @school.active_school_year
  end

  def planning_preparation_summary
    active_teachers = @planning_school_year.users.teacher.active
    active_classrooms = @planning_school_year.classrooms.active
    assigned_classroom_count = HomeroomAssignment.current
      .where(
        classroom_id: active_classrooms.select(:id),
        teacher_id: active_teachers.select(:id)
      )
      .count

    {
      teacher_count: active_teachers.count,
      classroom_count: active_classrooms.count,
      assigned_classroom_count: assigned_classroom_count
    }
  end
end
