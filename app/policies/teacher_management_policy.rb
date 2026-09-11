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

    school_year.school == user.annual_school &&
      school_year.year == user.school_year.year + 1
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
