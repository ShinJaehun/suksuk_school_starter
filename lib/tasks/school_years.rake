namespace :school_years do
  desc "Attempt each overdue planning SchoolYear rollover once; run periodically outside requests"
  task reconcile_rollovers: :environment do
    SchoolYear.planning
      .where(automatic_rollover_attempted_at: nil)
      .where(year: ..SchoolYear.academic_year_for(Date.current))
      .find_each do |school_year|
        SchoolYears::AutomaticRollover.call(
          school: school_year.school,
          target_school_year_id: school_year.id
        )
      end
  end
end
