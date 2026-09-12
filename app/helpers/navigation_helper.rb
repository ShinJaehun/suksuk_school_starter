module NavigationHelper
  def primary_navigation_items(context)
    if context[:student]
      return [
        navigation_item('navigation.my_page', student_profile_path)
      ]
    end

    user = context[:user]
    return [] unless user

    if user.admin?
      [
        navigation_item('navigation.school_management', schools_path),
        navigation_item('navigation.classrooms', classrooms_path),
        (navigation_item('navigation.teacher_management', teachers_path) if can_manage_teachers?)
      ].compact
    elsif context[:manager]
      [
        navigation_item('navigation.school_operations', school_path(context[:manager].annual_school)),
        navigation_item('navigation.classrooms', classrooms_path),
        navigation_item('navigation.teacher_management', teachers_path)
      ]
    elsif context[:planning_manager]
      planning_context = {
        school_id: user.annual_school.id,
        school_year_id: user.school_year_id
      }
      [
        navigation_item('navigation.classrooms', classrooms_path(planning_context)),
        navigation_item('navigation.teacher_management', teachers_path(planning_context))
      ]
    elsif user.teacher?
      []
    else
      []
    end
  end

  def teacher_classroom_navigation(context)
    return unless context[:user]&.teacher? && !context[:manager] && !context[:planning_manager]

    classrooms = context.fetch(:classrooms, [])
    {
      mode: if classrooms.none?
              :index
            else
              (classrooms.one? ? :single : :multiple)
            end,
      classrooms: classrooms
    }
  end

  def management_navigation_groups
    []
  end

  def navigation_account(context)
    if (student = context[:student])
      return {
        actor: student,
        student: true,
        display_name: student.name,
        edit_path: nil,
        sign_out_label: t('navigation.account.finish'),
        sign_out_path: destroy_student_session_path
      }
    end

    user = context[:user]
    return unless user

    {
      actor: user,
      student: false,
      display_name: user.name.presence || user.email,
      edit_path: edit_user_registration_path,
      sign_out_label: t('navigation.account.sign_out'),
      sign_out_path: destroy_user_session_path
    }
  end

  # global admin과 학교 대표 선생님만 교사 관리 화면 접근 가능
  def can_manage_teachers?
    return false unless current_user

    TeacherManagementPolicy.new(current_user, User).access?
  end

  private

  def navigation_item(label_key, path)
    { label: t(label_key), path: path }
  end
end
