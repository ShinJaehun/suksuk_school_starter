class AddAutomaticRolloverAttemptedAtToSchoolYears < ActiveRecord::Migration[8.1]
  def change
    add_column :school_years, :automatic_rollover_attempted_at, :datetime
  end
end
