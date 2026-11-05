# One industry -> color mapping shared by the graph, tables and profile.
# Up to 7 industries get the categorical slots (CSS --series-1..7,
# validated for color-blind separation in light and dark); the rest share a neutral tone.
# Colors follow the industry, not its rank on a page, so filtering never repaints anything.
module IndustryPalette
  SLOTS = 7

  module_function

  # Your target/curious industries claim colors first (in the order you listed them),
  # then the rest by how many contacts you have there.
  def order
    counts = Person.where.not(industry: [nil, ""]).group(:industry).count
    focus = Profile.current.focus_industries
    counts.keys.sort_by { |name| [focus.index(name) || focus.size, -counts[name], name] }
  end

  def slots
    order.reject { |i| i == "Other" }.first(SLOTS).each_with_index.to_h { |ind, i| [ind, i + 1] }
  end

  def css_var(industry, slots = self.slots)
    (n = slots[industry]) ? "var(--series-#{n})" : "var(--series-other)"
  end
end
