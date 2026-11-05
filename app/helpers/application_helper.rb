module ApplicationHelper
  # Small colored dot for an industry (same color as on the graph).
  def industry_dot(industry)
    @industry_slots ||= IndustryPalette.slots
    tag.span(class: "ind-dot", style: "background: #{IndustryPalette.css_var(industry, @industry_slots)}",
             title: industry.presence || "No industry")
  end
end
