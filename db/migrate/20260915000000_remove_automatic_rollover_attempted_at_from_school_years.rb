class RemoveAutomaticRolloverAttemptedAtFromSchoolYears < ActiveRecord::Migration[8.1]
  def change
    remove_column :school_years, :automatic_rollover_attempted_at, :datetime
  end
end
