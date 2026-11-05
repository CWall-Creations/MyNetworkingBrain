# Your profile is a YAML file in data/ (gitignored), not a DB row, so it is
# easy to edit by hand and never ends up in git.
class Profile
  DEFAULTS = {
    "strength" => { "half_life_days" => 120, "default_closeness" => 3 },
    "reach_out" => { "min_gap_days" => 45 },
    "spreadsheet_columns" => { "name" => "Name" }
  }.freeze

  EDITABLE = %w[name graduation_date degree school work_authorization].freeze
  LIST_FIELDS = %w[locations target_industries curious_industries exclusions target_roles].freeze

  def self.data_dir
    dir = ENV["NB_DATA_DIR"].presence || Rails.root.join(Rails.env.test? ? "data.example" : "data")
    dir = Rails.root.join("data.example") unless File.directory?(dir)
    Pathname(dir)
  end

  def self.path = data_dir.join("profile.yml")

  def self.current
    @current = nil if @mtime != (File.mtime(path) rescue nil)
    @mtime = (File.mtime(path) rescue nil)
    @current ||= new(File.exist?(path) ? (YAML.safe_load_file(path, permitted_classes: [Date]) || {}) : {})
  end

  attr_reader :data

  def initialize(data) = @data = DEFAULTS.deep_merge(data.to_h.transform_keys(&:to_s))

  def [](key) = data[key.to_s]
  def name = data["name"].presence || "Me"
  def half_life_days = data.dig("strength", "half_life_days").to_i.nonzero? || 120
  def default_closeness = data.dig("strength", "default_closeness").to_i.clamp(1, 5)
  def min_gap_days = data.dig("reach_out", "min_gap_days").to_i
  def spreadsheet_columns = data["spreadsheet_columns"].to_h
  LIST_FIELDS.each { |f| define_method(f) { Array(data[f]) } }

  # Your industries in your own words ("pro sports tech", "ML startups") mapped onto
  # the app's buckets ("Sports Tech", "AI/ML") so they can be compared with contacts.
  def target_buckets = to_buckets(target_industries)
  def curious_buckets = to_buckets(curious_industries)
  def focus_industries = (target_buckets + curious_buckets).uniq

  def to_buckets(entries)
    entries.filter_map do |e|
      IndustryClassifier.names.find { |b| b.casecmp?(e.strip) } || IndustryClassifier.best_match(e)
    end.uniq
  end

  ROLE_STOPWORDS = %w[and or of the a an to in at for with i ii new grad junior senior associate].freeze

  # Keywords from target_roles ("Software Engineer" -> software, engineer).
  # A posting is relevant if its title shares one. No target roles => everything is relevant.
  def role_keywords
    @role_keywords ||= target_roles.flat_map { |r| r.downcase.scan(/[a-z+#\/]+/) }.uniq - ROLE_STOPWORDS
  end

  # Other engineering disciplines: "Electrical Engineer" shouldn't match "Software Engineer"
  # just because both say "engineer". Ignored if one of your target roles names the discipline.
  OTHER_DISCIPLINES = %w[electrical mechanical civil chemical structural manufacturing process rf analog
                         asic fpga materials industrial quality nuclear propulsion thermal optical].freeze

  def role_match?(title)
    return true if role_keywords.empty?
    words = title.to_s.downcase.scan(/[a-z+#\/]+/)
    return false if (words & (OTHER_DISCIPLINES - role_keywords)).any?
    (words & role_keywords).any?
  end

  def resume_text
    file = data["resume_file"].presence or return ""
    path = self.class.data_dir.join(file)
    return "" unless File.exist?(path)
    if path.extname.downcase == ".pdf"
      PDF::Reader.new(path).pages.map(&:text).join("\n")
    else
      File.read(path)
    end
  rescue PDF::Reader::MalformedPDFError
    ""
  end

  RESUME_TYPES = %w[.pdf .md .txt].freeze

  # Saves an uploaded resume into data/ (gitignored) and points the profile at it.
  def attach_resume!(upload)
    ext = File.extname(upload.original_filename.to_s).downcase
    raise ArgumentError, "Resume must be a PDF, .md or .txt file." unless RESUME_TYPES.include?(ext)
    raise ArgumentError, "Resume is too large (max 10 MB)." if upload.size > 10.megabytes
    RESUME_TYPES.each { |e| FileUtils.rm_f(self.class.data_dir.join("resume#{e}")) }
    File.binwrite(self.class.data_dir.join("resume#{ext}"), upload.read)
    data["resume_file"] = "resume#{ext}"
    save!
    raise ArgumentError, "Saved, but no text could be read from that PDF (is it a scanned image?)." if resume_text.blank?
  end

  def save!
    File.write(self.class.path, data.to_yaml)
    self.class.instance_variable_set(:@current, nil)
  end

  def update!(attrs)
    attrs = attrs.to_h.stringify_keys
    EDITABLE.each { |f| data[f] = attrs[f] if attrs.key?(f) }
    LIST_FIELDS.each do |f|
      data[f] = attrs[f].to_s.split(/[,\n]/).map(&:strip).reject(&:empty?) if attrs.key?(f)
    end
    save!
  end
end
