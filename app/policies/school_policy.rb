class SchoolPolicy < ApplicationPolicy
  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.all if admin?
      return scope.active.where(id: user.annual_school.id) if teacher?

      scope.none
    end
  end

  def index?
    admin? || teacher?
  end

  def show?
    admin? || (record.active? && school_member?)
  end

  def manage_operations?
    record.active? && (admin? || school_manager?)
  end

  def manage_managers?
    record.active? && admin?
  end

  def manage_teachers?
    record.active? && school_manager?
  end

  def create?
    admin?
  end

  def update?
    admin?
  end

  def deactivate?
    admin? && record.active?
  end

  def reactivate?
    admin? && record.inactive?
  end

  def destroy?
    false
  end

  private

  def school_member?
    teacher? && user.annual_school&.id == record.id
  end

  def school_manager?
    school_member? && user.current_operational_manager?
  end
end
