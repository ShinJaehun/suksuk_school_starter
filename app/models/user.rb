class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :rememberable, :validatable
  GENDERS = %w[male female].freeze
  TEACHER_MALE_AVATAR_KEYS = (1..8).map { |number| format('teacherM%02d', number) }.freeze
  TEACHER_FEMALE_AVATAR_KEYS = (1..6).map { |number| format('teacherF%02d', number) }.freeze
  ADMIN_AVATAR_KEYS = %w[admin].freeze
  TEACHER_AVATAR_KEYS = (TEACHER_MALE_AVATAR_KEYS + TEACHER_FEMALE_AVATAR_KEYS).freeze
  AVATAR_KEYS_BY_ROLE = {
    'teacher' => TEACHER_AVATAR_KEYS,
    'admin' => (ADMIN_AVATAR_KEYS + TEACHER_AVATAR_KEYS).freeze
  }.freeze
  AVATAR_KEYS_BY_GENDER = {
    'male' => TEACHER_MALE_AVATAR_KEYS,
    'female' => TEACHER_FEMALE_AVATAR_KEYS,
    'admin' => ADMIN_AVATAR_KEYS
  }.freeze
  AVATAR_KEYS = AVATAR_KEYS_BY_GENDER.values.flatten.freeze

  validates :name, presence: true, length: { maximum: 30 }
  validates :gender, inclusion: { in: GENDERS }, allow_nil: true
  validates :avatar_key, inclusion: { in: AVATAR_KEYS }, allow_nil: true, if: :will_save_change_to_avatar_key?
  validate :avatar_key_allowed_for_role, if: :will_save_change_to_avatar_key?
  validates :school_year, :login_id, :school_role, presence: true, if: :teacher?
  validates :school_role, inclusion: { in: %w[member manager] }, if: :teacher?
  validates :grade,
            numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 6 },
            allow_nil: true,
            if: :teacher?
  validates :school_year, :login_id, :school_role, :grade, absence: true, unless: :teacher?
  validate :annual_school_year_immutable, on: :update, if: :teacher?

  enum :role, { teacher: 'teacher', admin: 'admin' }
  scope :active, -> { where(active: true) }
  scope :inactive, -> { where(active: false) }
  has_one_attached :avatar

  before_validation :normalize_teacher_login_id, if: :teacher?
  before_update :release_assigned_classroom, if: :deactivating_teacher?

  belongs_to :school_year, optional: true
  has_many :homeroom_assignments,
           foreign_key: :teacher_id,
           inverse_of: :teacher,
           dependent: :restrict_with_error
  has_one :current_homeroom_assignment,
          -> { current },
          class_name: 'HomeroomAssignment',
          foreign_key: :teacher_id
  has_one :assigned_classroom, through: :current_homeroom_assignment, source: :classroom
  has_many :issued_teacher_credential_events,
           class_name: 'TeacherCredentialEvent',
           foreign_key: :actor_user_id,
           inverse_of: :actor_user,
           dependent: :restrict_with_error
  has_many :teacher_credential_events,
           foreign_key: :teacher_user_id,
           inverse_of: :teacher_user,
           dependent: :restrict_with_error

  def self.avatar_keys_for(gender)
    AVATAR_KEYS_BY_GENDER.fetch(gender.to_s, [])
  end

  def self.avatar_keys_for_role(role)
    AVATAR_KEYS_BY_ROLE.fetch(role.to_s, [])
  end

  def self.find_for_database_authentication(warden_conditions)
    email = warden_conditions[:email].to_s.strip.downcase
    admin.find_by(email: email)
  end

  def inactive?
    !active?
  end

  def active_teacher?
    teacher? && active?
  end

  def current_operational_teacher?
    active_teacher? && school_year&.active? && annual_school&.active?
  end

  def current_operational_manager?
    current_operational_teacher? && school_manager?
  end

  def annual_school
    school_year&.school
  end

  def school_manager?
    teacher? && school_role == 'manager'
  end

  def school_member?
    teacher? && school_role == 'member'
  end

  def active_for_authentication?
    super && (!teacher? || active?)
  end

  def inactive_message
    teacher? && inactive? ? :inactive : super
  end

  def email_required?
    admin?
  end

  private

  def normalize_teacher_login_id
    return unless new_record? || will_save_change_to_login_id?

    self.login_id = login_id.to_s.strip.downcase.presence
  end

  def annual_school_year_immutable
    return unless will_save_change_to_school_year_id?
    return if school_year_id_in_database.nil?

    errors.add(:school_year, :immutable)
  end

  def deactivating_teacher?
    teacher? && will_save_change_to_active?(from: true, to: false)
  end

  def release_assigned_classroom
    assignment = current_homeroom_assignment
    return unless assignment
    return if assignment.classroom.school_year.archived?

    assignment.update!(ended_on: Date.current)
  end

  def avatar_key_allowed_for_role
    return if avatar_key.blank? || self.class.avatar_keys_for_role(role).include?(avatar_key)

    errors.add(:avatar_key, :inclusion)
  end
end
