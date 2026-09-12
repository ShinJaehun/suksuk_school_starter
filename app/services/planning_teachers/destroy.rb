module PlanningTeachers
  class Destroy
    def self.call(teacher:)
      new(teacher: teacher).call
    end

    def initialize(teacher:)
      @teacher = teacher
    end

    def call
      User.transaction do
        teacher.lock!
        ensure_destroyable_target!
        fail_destroy!(:credential_actor_present) if teacher.issued_teacher_credential_events.exists?

        teacher.current_homeroom_assignment&.destroy!
        teacher.teacher_credential_events.destroy_all
        teacher.destroy!
      end
    end

    private

    attr_reader :teacher

    def ensure_destroyable_target!
      return if teacher.teacher? && teacher.school_year&.planning? && teacher.annual_school&.active?

      fail_destroy!(:invalid_planning_teacher)
    end

    def fail_destroy!(error)
      teacher.errors.add(:base, error)
      raise ActiveRecord::RecordNotDestroyed.new('Planning Teacher could not be deleted', teacher)
    end
  end
end
