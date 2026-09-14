require 'rails_helper'
require 'rake'

RSpec.describe 'school_years:reconcile_rollovers' do
  include ActiveSupport::Testing::TimeHelpers

  around do |example|
    original_application = Rake.application
    Rake.application = Rake::Application.new
    load Rails.root.join('lib/tasks/school_years.rake')
    Rake::Task.define_task(:environment)
    travel_to(Time.zone.local(2027, 3, 1)) { example.run }
  ensure
    Rake.application = original_application
  end

  it 'dispatches only due, unattempted planning targets' do
    overdue = create(:school_year, year: 2026)
    due = create(:school_year, year: 2027)
    create(:school_year, year: 2028)
    create(:school_year, year: 2027, automatic_rollover_attempted_at: Time.current)
    create(:school_year, :active, year: 2027)
    create(:school_year, :archived, year: 2026)

    expect(SchoolYears::AutomaticRollover).to receive(:call)
      .with(school: overdue.school, target_school_year_id: overdue.id).once
    expect(SchoolYears::AutomaticRollover).to receive(:call)
      .with(school: due.school, target_school_year_id: due.id).once

    Rake::Task['school_years:reconcile_rollovers'].invoke
  end

  it 'does not select this year before March 1' do
    travel_to Time.zone.local(2027, 2, 28)
    create(:school_year, year: 2027)
    expect(SchoolYears::AutomaticRollover).not_to receive(:call)

    Rake::Task['school_years:reconcile_rollovers'].invoke
  end
end
