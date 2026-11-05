import { Controller } from "@hotwired/stimulus"
import * as d3 from "d3"

// Ethereal floating network.
// - You are a luminous orb in the center; people drift in industry clusters.
// - Each cluster is labeled where it floats (dot + name): the label IS the legend.
//   Click a label to spotlight that industry; click it again (or empty space) to clear.
// - Introducers (Uncle, Sister, ...) are soft hollow rings between you and the people they connected you to.
// - Thread brightness/thickness = connection strength. A soft pulsing halo = company hiring new grads.
export default class extends Controller {
  static targets = ["svg", "drawer"]
  static values = { url: String }

  async connect() {
    const res = await fetch(this.urlValue, { headers: { Accept: "application/json" } })
    this.graph = await res.json()
    this.colorOf = new Map(this.graph.industries.map(i => [i.name, i.slot ? `var(--series-${i.slot})` : "var(--series-other)"]))
    this.reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches
    this.render()
    this.resizeObserver = new ResizeObserver(() => this.fit())
    this.resizeObserver.observe(this.svgTarget)
  }

  disconnect() {
    this.sim?.stop()
    this.resizeObserver?.disconnect()
    clearInterval(this.drift)
  }

  size() {
    const r = this.svgTarget.getBoundingClientRect()
    return { w: Math.max(r.width, 320), h: Math.max(r.height, 320) }
  }

  fit() {
    const { w, h } = this.size()
    d3.select(this.svgTarget).attr("viewBox", [-w / 2, -h / 2, w, h])
  }

  render() {
    const { nodes, links, industries } = this.graph
    const { w, h } = this.size()
    const svg = d3.select(this.svgTarget)
    svg.selectAll("*").remove()
    this.fit()
    this.defs(svg)

    // Drifting motes in the background (not zoomed)
    const motes = svg.append("g").attr("class", "motes")
    d3.range(46).forEach(() => {
      motes.append("circle")
        .attr("cx", (Math.random() - 0.5) * w).attr("cy", (Math.random() - 0.5) * h)
        .attr("r", Math.random() * 1.4 + 0.4)
        .style("animation-delay", `${-Math.random() * 18}s`)
        .style("animation-duration", `${14 + Math.random() * 12}s`)
    })

    const world = svg.append("g")
    svg.call(d3.zoom().scaleExtent([0.4, 3]).on("zoom", e => world.attr("transform", e.transform)))
    svg.on("click", e => { if (e.target === this.svgTarget) this.spotlight(null) })

    // Cluster anchors on a ring around you
    const ringR = Math.min(w, h) * 0.37
    this.anchors = new Map(industries.map((ind, i) => {
      const a = (i / industries.length) * 2 * Math.PI - Math.PI / 2
      return [ind.name, { x: Math.cos(a) * ringR, y: Math.sin(a) * ringR }]
    }))

    this.labeled = new Set(industries.filter(i => i.slot || i.count >= 2).map(i => i.name))
    const me = nodes.find(n => n.id === "me")
    me.fx = 0; me.fy = 0

    const radius = n => n.type === "me" ? 18 : n.type === "hub" ? 8 : 5 + (n.strength || 0) * 7
    const linkDistance = l => {
      const s = l.strength ?? 0.5
      if (l.kind === "hub") return 100
      if (l.kind === "via") return 40 + (1 - s) * 55
      return 75 + (1 - s) * 170
    }

    const link = world.append("g").attr("class", "threads")
      .selectAll("line").data(links).join("line")
      .attr("class", d => `thread ${d.kind}`)
      .attr("stroke-width", d => d.kind === "hub" ? 1 : 0.6 + (d.strength || 0) * 2.6)
      .attr("stroke-opacity", d => d.kind === "hub" ? 0.5 : 0.22 + (d.strength || 0) * 0.55)

    const node = world.append("g").attr("class", "nodes")
      .selectAll("g").data(nodes).join("g")
      .attr("class", d => `node ${d.type}${d.hub ? " is-hub" : ""}`)
      .attr("tabindex", d => d.type === "person" ? 0 : null)
      .attr("role", d => d.type === "person" ? "button" : null)
      .attr("aria-label", d => d.type === "person" ? `${d.label}, ${d.position || ""} ${d.company}` : null)
      .call(this.dragBehavior())

    node.filter(d => d.hiring).append("circle").attr("class", "halo")
      .attr("r", d => radius(d) + 7).attr("fill", d => this.colorOf.get(d.industry))
    node.filter(d => d.type === "me").append("circle").attr("class", "aura").attr("r", 42)
    node.append("circle").attr("class", "dot").attr("r", radius)
      .attr("fill", d => d.type === "person" ? this.colorOf.get(d.industry) : d.type === "me" ? "url(#orb)" : null)
      .attr("filter", d => d.type === "hub" ? null : "url(#glow)")
    node.append("text").attr("class", "label")
      .attr("dy", d => d.type === "me" ? 34 : -radius(d) - 7)
      .attr("text-anchor", "middle")
      .text(d => d.type === "me" ? "you" : d.type === "person" && !this.labeled.has(d.industry) ? `${d.label} · ${d.industry}` : d.label)
    node.filter(d => d.type === "person").append("title")
      .text(d => `${d.label}\n${d.position || ""}${d.position ? " · " : ""}${d.company}\n${d.industry}${d.hiring ? "\nHiring new grads" : ""}`)

    node.filter(d => d.type === "person")
      .on("click", (e, d) => { e.stopPropagation(); this.open(d.person_id, e.currentTarget) })
      .on("keydown", (e, d) => { if (e.key === "Enter" || e.key === " ") { e.preventDefault(); this.open(d.person_id, e.currentTarget) } })

    // Industry labels that float with their cluster (the legend). Only colored or
    // multi-person clusters get one; a lone gray dot names its industry on hover.
    const labeled = industries.filter(i => this.labeled.has(i.name))
    const tags = world.append("g").attr("class", "cluster-tags")
      .selectAll("g").data(labeled).join("g")
      .attr("class", "cluster-tag").attr("tabindex", 0).attr("role", "button")
      .attr("aria-label", d => `Spotlight ${d.name}`)
      .on("click", (e, d) => { e.stopPropagation(); this.spotlight(this.focus === d.name ? null : d.name) })
      .on("keydown", (e, d) => { if (e.key === "Enter") this.spotlight(this.focus === d.name ? null : d.name) })
    tags.append("rect").attr("class", "tag-bg").attr("rx", 10).attr("height", 20).attr("y", -14)
    tags.append("circle").attr("r", 4).attr("cx", 10).attr("cy", -4).attr("fill", d => this.colorOf.get(d.name))
    tags.append("text").attr("x", 19).attr("y", 0).text(d => d.name)
    this.tagWidths = new Map()
    tags.each((d, i, els) => {
      const g = d3.select(els[i])
      const tw = g.select("text").node().getComputedTextLength() + 28
      g.select("rect").attr("width", tw)
      this.tagWidths.set(d.name, tw)
    })

    const byIndustry = d3.group(nodes.filter(n => n.type === "person"), n => n.industry)

    this.sim = d3.forceSimulation(nodes)
      .force("link", d3.forceLink(links).id(d => d.id).distance(linkDistance).strength(l => l.kind === "direct" ? 0.02 : l.kind === "via" ? 0.05 : 0.3))
      .force("charge", d3.forceManyBody().strength(d => d.type === "me" ? -420 : d.type === "hub" ? -140 : -60).distanceMax(220))
      .force("collide", d3.forceCollide().radius(d => radius(d) + 7))
      .force("x", d3.forceX(d => this.anchors.get(d.industry)?.x ?? 0).strength(d => d.type === "person" ? 0.32 : 0))
      .force("y", d3.forceY(d => this.anchors.get(d.industry)?.y ?? 0).strength(d => d.type === "person" ? 0.32 : 0))
      .alphaTarget(this.reduceMotion ? 0 : 0.012)
      .on("tick", () => {
        link.attr("x1", d => d.source.x).attr("y1", d => d.source.y)
            .attr("x2", d => d.target.x).attr("y2", d => d.target.y)
        node.attr("transform", d => `translate(${d.x},${d.y})`)
        this.placeTags(tags, byIndustry, radius)
      })

    if (!this.reduceMotion) {
      this.drift = setInterval(() => {
        nodes.forEach(n => { if (n.fx == null) { n.vx += (Math.random() - 0.5) * 0.35; n.vy += (Math.random() - 0.5) * 0.35 } })
      }, 900)
    }

    this.nodeSel = node
    this.linkSel = link
    this.tagSel = tags
  }

  // Each label sits above its cluster; overlapping labels are nudged apart.
  placeTags(tags, byIndustry, radius) {
    const boxes = []
    tags.each(d => {
      const members = byIndustry.get(d.name) || []
      if (!members.length) return
      const w = this.tagWidths.get(d.name)
      boxes.push({ d, w, x: d3.mean(members, m => m.x) - w / 2, y: d3.min(members, m => m.y - radius(m)) - 30 })
    })
    for (let pass = 0; pass < 4; pass++) {
      for (let i = 0; i < boxes.length; i++) {
        for (let j = i + 1; j < boxes.length; j++) {
          const a = boxes[i], b = boxes[j]
          const overlapX = Math.min(a.x + a.w, b.x + b.w) - Math.max(a.x, b.x)
          const overlapY = 22 - Math.abs(a.y - b.y)
          if (overlapX > 0 && overlapY > 0) {
            const push = overlapY / 2 + 1
            if (a.y <= b.y) { a.y -= push; b.y += push } else { a.y += push; b.y -= push }
          }
        }
      }
    }
    const pos = new Map(boxes.map(b => [b.d.name, b]))
    tags.attr("transform", d => {
      const b = pos.get(d.name)
      return b ? `translate(${b.x},${b.y})` : "translate(-9999,-9999)"
    })
  }

  defs(svg) {
    const defs = svg.append("defs")
    const glow = defs.append("filter").attr("id", "glow").attr("x", "-80%").attr("y", "-80%").attr("width", "260%").attr("height", "260%")
    glow.append("feGaussianBlur").attr("stdDeviation", 3.2).attr("result", "blur")
    const merge = glow.append("feMerge")
    merge.append("feMergeNode").attr("in", "blur")
    merge.append("feMergeNode").attr("in", "SourceGraphic")

    const orb = defs.append("radialGradient").attr("id", "orb").attr("cx", "38%").attr("cy", "34%").attr("r", "70%")
    orb.append("stop").attr("offset", "0%").attr("style", "stop-color: var(--orb-core)")
    orb.append("stop").attr("offset", "55%").attr("style", "stop-color: var(--orb-mid)")
    orb.append("stop").attr("offset", "100%").attr("style", "stop-color: var(--orb-edge)")
  }

  dragBehavior() {
    return d3.drag()
      .on("start", (e, d) => { if (!e.active) this.sim.alphaTarget(0.2).restart(); if (d.id !== "me") { d.fx = d.x; d.fy = d.y } })
      .on("drag", (e, d) => { if (d.id !== "me") { d.fx = e.x; d.fy = e.y } })
      .on("end", (e, d) => { if (!e.active) this.sim.alphaTarget(this.reduceMotion ? 0 : 0.012); if (d.id !== "me") { d.fx = null; d.fy = null } })
  }

  // Dim everything outside one industry (null = show all)
  spotlight(industry) {
    this.focus = industry
    // Hubs stay lit only if they introduced someone in the spotlighted industry
    const litHubs = new Set(this.graph.links.filter(l => l.kind === "via" && l.target.industry === industry).map(l => l.source.id))
    const out = d => industry && ((d.type === "person" && d.industry !== industry) || (d.type === "hub" && !litHubs.has(d.id)))
    this.nodeSel.classed("dim", out)
    this.linkSel.classed("dim", l => industry && (out(l.target) || out(l.source) || (l.kind === "hub" && !litHubs.has(l.target.id))))
    this.tagSel.classed("dim", d => industry && d.name !== industry).classed("on", d => d.name === industry)
  }

  open(personId, el) {
    this.nodeSel.classed("selected", false)
    d3.select(el).classed("selected", true)
    this.drawerTarget.src = `/people/${personId}`
  }

  closeDrawer(event) {
    event.preventDefault()
    this.drawerTarget.removeAttribute("src")
    this.drawerTarget.innerHTML = ""
    this.nodeSel?.classed("selected", false)
  }
}
