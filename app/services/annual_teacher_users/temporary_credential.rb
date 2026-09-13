module AnnualTeacherUsers
  class TemporaryCredential
    Result = Data.define(:teacher, :temporary_password, :event) do
      def success?
        teacher.errors.empty?
      end
    end

    def self.call(teacher:, actor:, action:)
      new(teacher:, actor:, action:).call
    end

    def initialize(teacher:, actor:, action:)
      @teacher = teacher
      @actor = actor
      @action = action.to_s
    end

    def call
      temporary_password = Teachers::TemporaryPassword.generate(login_id: teacher.login_id)
      event = nil

      User.transaction do
        teacher.lock! if teacher.persisted?
        teacher.assign_attributes(
          password: temporary_password,
          password_confirmation: temporary_password,
          password_change_required: true
        )
        teacher.save!
        event = TeacherCredentialEvent.create!(
          actor_user: actor,
          teacher_user: teacher,
          action: action
        )
      end

      Result.new(teacher:, temporary_password:, event:)
    rescue ActiveRecord::RecordInvalid => error
      if error.record != teacher
        messages = error.record.errors.full_messages
        if messages.present?
          messages.each { |message| teacher.errors.add(:base, message) }
        else
          teacher.errors.add(:base, :invalid)
        end
      end
      Result.new(teacher:, temporary_password: nil, event: nil)
    end

    private

    attr_reader :teacher, :actor, :action
  end
end
