module Importers
  # data/network.yml => people (+ their interactions). Applied directly (no review),
  # since you wrote the file yourself.
  class YamlNetwork
    def initialize(path = Profile.data_dir.join("network.yml")) = @path = path

    def import!
      return 0 unless File.exist?(@path)
      people = Array((YAML.safe_load_file(@path, permitted_classes: [Date]) || {})["people"])
      people.each do |p|
        row = Row.build(name: p["name"], position: p["position"], company: p["company"],
                        industry_tags: p["industry_tags"], how_met: p["how_met"],
                        closeness: p["closeness"], notes: p["notes"], met_on: p["met_on"])
        row["industry"] = p["industry"] if p["industry"].present?
        person = Applier.apply_row!(row, source: "yaml")
        Array(p["interactions"]).each do |i|
          person.interactions.find_or_create_by!(occurred_on: Date.parse(i["date"].to_s), kind: i["kind"] || "message") do |x|
            x.notes = i["notes"]
          end
        end
      end
      people.size
    end
  end
end
