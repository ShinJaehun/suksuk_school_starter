class UserPolicy < ApplicationPolicy
  class Scope < ApplicationPolicy::Scope
    def resolve
      user.admin? ? scope.all : scope.where(id: user.id)
    end
  end

  def index?
    user.admin?
  end

  def create?
    user.admin?
  end

  def show?
    user&.admin? || (user&.active_teacher? && user == record)
  end

  # Admin 영역에서 교사 계정 수정 권한
  def edit?
    update?
  end

  def update?
    user&.admin? && record.teacher?
  end

  def deactivate_teacher?
    teacher_status_change_allowed? && record.active?
  end

  def reactivate_teacher?
    teacher_status_change_allowed? && record.inactive?
  end

  private

  def teacher_status_change_allowed?
    return false unless record.teacher?
    if record.school_year&.planning?
      return false if record.school_manager?
      return false if user == record
      return true if user&.admin?

      return record.school_member? && user.is_a?(User) &&
        user.planning_preparation_operator_for?(record.school_year)
    end

    return true if user&.admin?
    return false unless user&.active_teacher?
    return false if user.id == record.id
    return false unless user.school_manager? && record.school_member?

    user.school_year_id == record.school_year_id
  end
end
