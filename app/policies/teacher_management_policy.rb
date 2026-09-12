class TeacherManagementPolicy < ApplicationPolicy
  class IndexScope < ApplicationPolicy::Scope
    def resolve
      return scope.teacher if user&.admin?

      return scope.none unless user&.current_operational_manager? || user&.planning_manager_session_eligible?
      return scope.teacher.where(school_year_id: user.school_year_id) if user.planning_manager_session_eligible?

      scope.teacher
           .joins(:school_year)
           .where(school_years: { school_id: user.annual_school.id })
    end
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.teacher.joins(:school_year).merge(SchoolYear.active) if user&.admin?

      return scope.none unless user&.current_operational_manager? || user&.planning_manager_session_eligible?

      if user.planning_manager_session_eligible?
        return scope.teacher.where(school_year_id: user.school_year_id)
      end

      scope.teacher
           .where(school_year_id: user.school_year_id)
    end
  end

  def index?
    access?
  end

  def access?
    user&.admin? || school_manager? || user&.planning_manager_session_eligible?
  end

  def create?
    return access? if record.teacher? && record.school_year.nil?

    return false unless access?
    return true unless record.respond_to?(:school_year) && record.school_year

    school_year = record.school_year
    return false unless school_year.active? || school_year.planning?

    if school_year.active?
      return true if user&.admin?

      return school_year == user.school_year
    end

    return false unless school_year.school&.active?
    return true if user&.admin?

    planning_operator_for?(school_year)
  end

  def edit?
    update_profile? || UserPolicy.new(user, record).reactivate_teacher?
  end

  def update_profile?
    return false unless record.teacher?

    school_year = record.school_year
    if school_year&.planning?
      return false unless record.active? && school_year.school.active?
      return true if user&.admin?

      return planning_operator_for?(school_year) &&
        school_year.school == user.annual_school
    end

    return true if user&.admin?

    school_manager? && record.school_year_id == user.school_year_id
  end

  def reissue_temporary_password?
    return false unless record.teacher? && record.active?
    return false if record == user

    school_year = record.school_year
    return false unless school_year&.school&.active?
    return false unless school_year.active? || school_year.planning?
    return true if user&.admin?

    if school_year.active?
      return school_manager? && record.school_member? && school_year == user.school_year
    end

    return false unless planning_operator_for?(school_year)

    user.current_operational_manager? || record.school_member?
  end

  def destroy?
    return false unless record.teacher?

    school_year = record.school_year
    return false unless school_year&.planning? && school_year.school.active?
    return true if user&.admin?
    return false unless record.school_member?

    planning_operator_for?(school_year) &&
      school_year.school == user.annual_school &&
      school_year == school_year.school.planning_school_year
  end

  private

  def school_manager?
    user&.current_operational_manager?
  end

  def planning_operator_for?(school_year)
    user.is_a?(User) && user.planning_preparation_operator_for?(school_year)
  end
end
