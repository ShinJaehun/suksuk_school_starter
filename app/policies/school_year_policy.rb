class SchoolYearPolicy < ApplicationPolicy
  def show?
    prepare?
  end

  def prepare?
    record.persisted? && record.planning? && planning_operator?
  end

  def create?
    return false unless record.new_record? && record.school&.active?
    return true if admin?

    user.is_a?(User) && user.current_operational_manager? &&
      user.annual_school == record.school && record.year == user.school_year.year + 1
  end

  private

  def planning_operator?
    school = record.school
    return false unless school&.active?
    return true if admin?

    user.is_a?(User) && user.planning_preparation_operator_for?(record)
  end
end
