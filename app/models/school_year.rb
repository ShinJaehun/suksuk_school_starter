class SchoolYear < ApplicationRecord
  def self.academic_year_for(date)
    date.month >= 3 ? date.year : date.year - 1
  end

  belongs_to :school
  has_many :users, dependent: :restrict_with_error
  has_many :classrooms, dependent: :restrict_with_error

  enum :status,
    {
      planning: "planning",
      active: "active",
      archived: "archived"
    },
    validate: true

  validates :year,
    numericality: {
      only_integer: true,
      greater_than_or_equal_to: 1000,
      less_than_or_equal_to: 9999
    },
    uniqueness: { scope: :school_id }
  validates :status,
    uniqueness: { scope: :school_id },
    if: :capacity_limited_status?

  def rollover_open?
    Date.current >= Date.new(year, 2, 1)
  end

  def rollover_overdue?
    planning? && Date.current >= Date.new(year, 3, 1)
  end

  private

  def capacity_limited_status?
    planning? || active?
  end
end
