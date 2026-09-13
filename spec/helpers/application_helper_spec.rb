require "rails_helper"

RSpec.describe ApplicationHelper do
  describe "#grouped_school_year_options" do
    it "groups available years without changing the selected value" do
      school = create(:school)
      archived = create(:school_year, :archived, school:, year: 2025)
      active = create(:school_year, :active, school:, year: 2026)
      planning = create(:school_year, school:, year: 2027)

      html = helper.grouped_school_year_options([active, planning, archived], planning.id)
      document = Nokogiri::HTML.fragment("<select>#{html}</select>")

      expect(document.css("optgroup").map { |group| group["label"] }).to eq(
        [
          I18n.t("school_years.selector.active"),
          I18n.t("school_years.selector.planning"),
          I18n.t("school_years.selector.archived")
        ]
      )
      expect(document.at_css(%(option[value="#{planning.id}"][selected]))).to be_present
      expect(document.text).to include(
        "2026학년도 · 운영 중",
        "2027학년도 · 준비 중",
        "2025학년도"
      )
    end
  end
end
