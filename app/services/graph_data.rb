# Nodes + links for the floating network graph.
#
#   you ── person                      (met directly)
#   you ── hub ── person               (introduced by "Uncle", "Sister", ...)
#
# If a hub is also a contact (e.g. your uncle is in your network), that
# person's node *is* the hub, so the people they introduced orbit them.
class GraphData
  def initialize(people: Person.includes(:companies, :introducer, :interactions).to_a)
    @people = people
    @hiring_ids = JobPosting.new_grad.live.distinct.pluck(:company_id).to_set
  end

  def to_h
    nodes = [{ id: "me", type: "me", label: Profile.current.name.split.first }]
    links = []
    strengths = @people.to_h { |p| [p.id, p.strength] }

    hubs = Introducer.where(id: @people.map(&:introducer_id).compact.uniq).to_a
    hub_node_id = {}
    hubs.each do |h|
      if h.person_id && strengths.key?(h.person_id)
        hub_node_id[h.id] = "p#{h.person_id}"
      else
        hub_node_id[h.id] = "h#{h.id}"
        kids = @people.select { |p| p.introducer_id == h.id }
        nodes << { id: "h#{h.id}", type: "hub", label: h.label, count: kids.size }
        links << { source: "me", target: "h#{h.id}", strength: 0.6, kind: "hub" }
      end
    end

    @people.each do |p|
      company = p.primary_company
      nodes << {
        id: "p#{p.id}", type: "person", person_id: p.id, label: p.name,
        position: p.position, company: p.company_names.presence || p.status.humanize,
        industry: p.industry.presence || "Other", strength: strengths[p.id], closeness: p.closeness,
        status: p.status, hiring: p.companies.any? { |c| @hiring_ids.include?(c.id) },
        hub: hubs.any? { |h| h.person_id == p.id }, company_id: company&.id
      }
      source = p.introducer_id ? hub_node_id[p.introducer_id] : "me"
      source = "me" if source == "p#{p.id}" # can't introduce yourself
      links << { source:, target: "p#{p.id}", strength: strengths[p.id], kind: source == "me" ? "direct" : "via" }
    end

    slots = IndustryPalette.slots
    counts = nodes.filter_map { |n| n[:industry] }.tally
    industries = IndustryPalette.order.select { |i| counts[i] }.map { |i| { name: i, slot: slots[i], count: counts[i] } }
    { nodes:, links:, industries: }
  end
end
