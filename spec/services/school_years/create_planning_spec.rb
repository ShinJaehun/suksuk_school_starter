require "rails_helper"

RSpec.describe SchoolYears::CreatePlanning do
  let(:school) { create(:school) }
  let!(:active_year) { create(:school_year, :active, school: school, year: 2026) }
  let(:admin) { create(:user, :admin) }

  it "creates the year immediately after the active year" do
    school_year = described_class.call(actor: admin, school: school)

    expect(school_year).to be_persisted
    expect(school_year).to have_attributes(year: 2027, status: "planning")
    expect(active_year.reload).to be_active
  end

  it "uses the current active year as the source when it changes" do
    school_2027 = create(:school)
    active_2027 = create(:school_year, :active, school: school_2027, year: 2027)

    school_year = described_class.call(actor: admin, school: school_2027)

    expect(school_year).to be_persisted
    expect(school_year).to have_attributes(year: 2028, status: "planning")
    expect(active_2027.reload).to be_active
  end

  it "rejects creation when a planning year already exists" do
    existing = create(:school_year, school: school, year: 2027)

    duplicate = described_class.call(actor: admin, school: school)

    expect(duplicate).not_to be_persisted
    expect(school.school_years.planning).to contain_exactly(existing)
    expect(active_year.reload).to be_active
  end

  it "fails closed when the school has no active year" do
    school_without_active_year = create(:school)

    school_year = described_class.call(actor: admin, school: school_without_active_year)

    expect(school_year).not_to be_persisted
    expect(school_year.errors[:base]).to be_present
  end

  it "rejects an inactive school without changing its active year" do
    school.update!(active: false)

    expect do
      described_class.call(actor: admin, school: school)
    end.to raise_error(Pundit::NotAuthorizedError)
    expect(school.school_years.planning).to be_empty
    expect(active_year.reload).to be_active
  end

  it "rechecks manager authority inside the operation" do
    manager = create(:user, :teacher, :active_annual_teacher,
      annual_school: school, annual_school_role: "manager")
    school.update!(active: false)

    expect do
      described_class.call(actor: manager, school: school)
    end.to raise_error(Pundit::NotAuthorizedError)
    expect(school.school_years.planning).to be_empty
    expect(active_year.reload).to be_active
  end
end
