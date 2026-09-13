class StudentPolicy < ApplicationPolicy
  def show?
    return true if admin?
    return true if archived_school_manager?
    return true if school_operations_manager? && operational_classroom?(record.classroom)
    return teacher_of_classroom? if teacher?

    student? && user == record && eligible_student?(record)
  end

  def manage_own_student_pin?
    user.is_a?(Student) && user == record && eligible_student?(record)
  end

  def manage?
    return true if admin? && operational_classroom?(record.classroom)
    return true if school_operations_manager? && operational_classroom?(record.classroom)

    teacher? && teacher_of_classroom?
  end

  private

  def teacher_of_classroom?
    operational_classroom?(record.classroom) && record.classroom.teacher == user
  end

  def eligible_student?(student)
    student.active? && operational_classroom?(student.classroom)
  end

  def operational_classroom?(classroom)
    classroom.active? && classroom.school_year.active? &&
      classroom.school_year.school.active?
  end

  def archived_school_manager?
    classroom = record.classroom
    classroom.school_year.archived? && user.is_a?(User) &&
      user.school_operations_manager_for?(classroom.school_year.school)
  end

  def school_operations_manager?
    user.is_a?(User) && user.school_operations_manager_for?(record.classroom.school_year.school)
  end
end
