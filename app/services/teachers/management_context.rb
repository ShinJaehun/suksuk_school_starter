class Teachers::ManagementContext
  def initialize(actor:, params:, schools_scope:)
    @actor = actor
    @params = params
    @schools_scope = schools_scope
  end

  def schools
    @schools ||= if actor.admin?
                   schools_scope.order(:name, :id).load
                 else
                   [actor.annual_school]
                 end
  end

  def selected_school
    return @selected_school if defined?(@selected_school)

    @selected_school = if actor.admin?
                         school_id.present? ? schools_scope.find(positive_id!(:school_id)) : nil
                       else
                         actor_school
                       end
  end

  def school_years
    return @school_years if defined?(@school_years)

    school = selected_school
    return @school_years = SchoolYear.none unless school
    return @school_years = school.school_years.order(year: :desc) if actor.admin?

    @school_years = if actor.current_operational_manager?
                      manager_school_years(school)
                    else
                      SchoolYear.where(id: actor.school_year_id)
                    end
  end

  def selected_school_year
    return @selected_school_year if defined?(@selected_school_year)

    @selected_school_year = if school_year_id.present?
                              raise ActiveRecord::RecordNotFound unless selected_school

                              school_years.find(positive_id!(:school_year_id))
                            elsif actor.admin? && selected_school.nil?
                              nil
                            elsif actor.planning_manager_session_eligible?
                              actor.school_year
                            else
                              school_years.find_by!(status: :active)
                            end
  end

  def read_only?
    selected_school_year.present? && !mutable?
  end

  def mutable?
    return true if actor.admin? && selected_school_year.nil?
    return false unless selected_school_year
    return false unless selected_school_year.active? || selected_school_year.planning?

    candidate = User.new(
      role: :teacher,
      school_year: selected_school_year,
      school_role: "member",
      active: true
    )
    TeacherManagementPolicy.new(actor, candidate).update_profile?
  end

  def creatable?
    candidate = User.new(role: :teacher, school_year: selected_school_year)
    TeacherManagementPolicy.new(actor, candidate).create?
  end

  def context_params(school_year = selected_school_year)
    return {} unless school_year

    { school_id: school_year.school_id, school_year_id: school_year.id }
  end

  def creation_context_explicit?
    school_year_id.present?
  end

  def creation_school_year
    return @creation_school_year if defined?(@creation_school_year)

    school = selected_school
    @creation_school_year = if creation_context_explicit?
                              raise ActiveRecord::RecordNotFound if actor.admin? && school_id.blank?
                              raise ActiveRecord::RecordNotFound unless school

                              school.school_years
                                    .where(status: %i[active planning])
                                    .find(positive_id!(:school_year_id))
                            else
                              school&.school_years&.active&.first
                            end
  end

  def explicit_mutation_school_year
    raise ActiveRecord::RecordNotFound if actor.admin? && school_id.blank?

    school = selected_school
    raise ActiveRecord::RecordNotFound unless school&.active?

    school_years.where(status: %i[active planning]).find(positive_id!(:school_year_id))
  end

  private

  attr_reader :actor, :params, :schools_scope

  def actor_school
    school = actor.annual_school
    if school_id.present? && positive_id!(:school_id) != school.id
      raise ActiveRecord::RecordNotFound
    end

    school
  end

  def manager_school_years(school)
    years = school.school_years.archived.to_a << actor.school_year
    planning_year = school.planning_school_year
    years << planning_year if planning_year&.year == actor.school_year.year + 1
    SchoolYear.where(id: years.map(&:id)).order(year: :desc)
  end

  def school_id
    params[:school_id]
  end

  def school_year_id
    params[:school_year_id]
  end

  def positive_id!(key)
    value = params[key].to_s
    raise ActiveRecord::RecordNotFound unless value.match?(/\A[1-9]\d*\z/)

    value.to_i
  end
end
