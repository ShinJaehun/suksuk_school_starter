class TeacherManagementPolicy < ApplicationPolicy
  class IndexScope < ApplicationPolicy::Scope
    def resolve
      return scope.teacher if user&.admin?

      return scope.none unless user&.current_operational_manager?

      scope.teacher
           .joins(:school_year)
           .where(school_years: { school_id: user.annual_school.id })
    end
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.teacher.joins(:school_year).merge(SchoolYear.active) if user&.admin?

      return scope.none unless user&.current_operational_manager?

      scope.teacher
           .where(school_year_id: user.school_year_id)
    end
  end

  def index?
    access?
  end

  def access?
    user&.admin? || school_manager?
  end

  def create?
    access?
  end

  def update_profile?
    return false unless record.teacher?
    return true if user&.admin?

    school_manager? && record.school_year_id == user.school_year_id
  end

  def reissue_temporary_password?
    return false unless record.teacher?
    return true if user&.admin?

    school_manager? &&
      record != user &&
      record.school_member? &&
      record.school_year_id == user.school_year_id
  end

  private

  def school_manager?
    user&.current_operational_manager?
  end
end
