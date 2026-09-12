module PlanningClassrooms
  class Destroy
    def self.call(classroom:)
      new(classroom: classroom).call
    end

    def initialize(classroom:)
      @classroom = classroom
    end

    def call
      Classroom.transaction do
        classroom.lock!
        ensure_destroyable_target!
        fail_destroy!(:students_present) if classroom.students.exists?
        fail_destroy!(:homeroom_history_present) if ended_assignments.exists?

        classroom.current_homeroom_assignment&.destroy!
        classroom.destroy!
      end
    end

    private

    attr_reader :classroom

    def ended_assignments
      classroom.homeroom_assignments.where.not(ended_on: nil)
    end

    def ensure_destroyable_target!
      return if classroom.school_year&.planning? && classroom.school_year.school.active?

      fail_destroy!(:invalid_planning_classroom)
    end

    def fail_destroy!(error)
      classroom.errors.add(:base, error)
      raise ActiveRecord::RecordNotDestroyed.new('Planning Classroom could not be deleted', classroom)
    end
  end
end
