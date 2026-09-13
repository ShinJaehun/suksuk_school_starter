class Classrooms::ManagementContext
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
    @school_years = if actor.school_operations_manager_for?(school)
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
    selected_school_year.present? &&
      (selected_school_year.archived? || selected_school.inactive?)
  end

  def creatable?
    return ClassroomPolicy.new(actor, Classroom).create? if actor.admin? && selected_school_year.nil?
    return false unless selected_school_year&.school&.active?
    return false unless selected_school_year.active? || selected_school_year.planning?

    ClassroomPolicy.new(actor, Classroom.new(school_year: selected_school_year)).create?
  end

  def context_params(school_year = selected_school_year)
    return {} unless school_year

    { school_id: school_year.school_id, school_year_id: school_year.id }
  end

  def edit_context_params
    selected_school_year&.planning? ? context_params : {}
  end

  def show_context_params
    selected_school_year&.archived? ? context_params : {}
  end

  def creation_context_explicit?
    school_id.present? || school_year_id.present?
  end

  def creation_school
    return @creation_school if defined?(@creation_school)

    @creation_school = if actor.admin?
                         if creation_context_explicit?
                           raise ActiveRecord::RecordNotFound if school_id.blank?

                           schools_scope.active.find(positive_id!(:school_id))
                         end
                       else
                         actor_school
                       end
  end

  def creation_school_year
    return @creation_school_year if defined?(@creation_school_year)
    return @creation_school_year = nil unless creation_school

    years = creation_school_years
    @creation_school_year = if school_year_id.present?
                              years.find(positive_id!(:school_year_id))
                            else
                              years.find_by!(status: :active)
                            end
  end

  def planning_mutation_school_year
    school = selected_school
    raise ActiveRecord::RecordNotFound unless school&.active?

    school.school_years.planning.find(positive_id!(:school_year_id))
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
    active_year = school.active_school_year
    planning_year = school.planning_school_year
    years = school.school_years.archived.to_a
    years << active_year if active_year
    years << planning_year if active_year && planning_year&.year == active_year.year + 1
    SchoolYear.where(id: years.map(&:id)).order(year: :desc)
  end

  def creation_school_years
    return creation_school.school_years.where(status: %i[active planning]) if actor.admin?

    active_year = creation_school.active_school_year
    planning_year = creation_school.planning_school_year
    years = [active_year]
    years << planning_year if active_year && planning_year&.year == active_year.year + 1
    SchoolYear.where(id: years.compact.map(&:id))
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
