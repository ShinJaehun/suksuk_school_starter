class SchoolYearPolicy < ApplicationPolicy
  def show?
    record.persisted? && record.planning? && planning_operator?
  end

  def create?
    record.new_record? && planning_operator?
  end

  private

  def planning_operator?
    school = record.school
    return false unless school&.active?
    return true if admin?

    user.is_a?(User) && user.current_operational_manager? && user.annual_school == school
  end
end
