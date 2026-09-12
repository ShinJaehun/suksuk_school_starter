class StudentPolicy < ApplicationPolicy
  def show?
    return true if admin?
    return true if teacher? && archived_school_manager?
    return teacher_of_classroom? if teacher?

    student? && user == record && eligible_student?(record)
  end

  def manage_own_student_pin?
    user.is_a?(Student) && user == record && eligible_student?(record)
  end

  def manage?
    return true if admin? && operational_classroom?(record.classroom)

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
    user.current_operational_manager? && classroom.school_year.archived? &&
      user.annual_school == classroom.school_year.school
  end
end
