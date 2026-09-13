module ApplicationHelper
  def grouped_school_year_options(school_years, selected_id)
    groups = {
      t("school_years.selector.active") => [],
      t("school_years.selector.planning") => [],
      t("school_years.selector.archived") => []
    }

    school_years.each do |school_year|
      group_key = t("school_years.selector.#{school_year.status}")
      label = if school_year.archived?
        t("school_years.selector.archived_option", year: school_year.year)
      else
        t(
          "school_years.selector.current_option",
          year: school_year.year,
          status: t("school_years.status.#{school_year.status}")
        )
      end
      groups.fetch(group_key) << [label, school_year.id]
    end

    grouped_options_for_select(groups.compact_blank, selected_id)
  end

end
