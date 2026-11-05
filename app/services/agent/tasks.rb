module Agent
  # Each task: build an anonymized prompt -> call Claude -> apply results locally.
  module Tasks
    module_function

    def anon = Anonymizer.new

    PROFILE_SCHEMA_FIELDS = %w[name graduation_date degree school locations work_authorization
                               target_roles target_industries curious_industries].freeze

    # Reads your resume and fills in your profile. By default only blank fields are
    # filled, so anything you typed yourself is kept. Returns the fields it changed.
    def profile_from_resume!(overwrite: false)
      profile = Profile.current
      resume = anon.scrub_contacts(profile.resume_text)
      raise ArgumentError, "Upload your resume first." if resume.blank?

      buckets = IndustryClassifier.names
      list = ->(items = { type: "string" }) { { type: "array", items: items } }
      schema = {
        type: "object", additionalProperties: false, required: PROFILE_SCHEMA_FIELDS,
        properties: {
          name: { type: "string" }, graduation_date: { type: "string" }, degree: { type: "string" },
          school: { type: "string" }, work_authorization: { type: "string" },
          locations: list.(), target_roles: list.(),
          target_industries: list.({ type: "string", enum: buckets }),
          curious_industries: list.({ type: "string", enum: buckets })
        }
      }
      out = Client.new.json(
        system: Context.system_prompt(<<~T),
          Read the user's resume and fill in their job-search profile. Use "" or [] when the resume
          doesn't say. graduation_date as YYYY-MM (expected graduation). locations: cities/regions
          they've lived, studied or worked in that they'd plausibly want to work in. target_roles: 2-4
          new-grad job titles their experience best supports. target_industries: the 2-3 industry
          buckets their experience points to most directly. curious_industries: 2-3 adjacent buckets
          worth exploring. Never guess work authorization: leave it "" unless the resume states it.
        T
        prompt: "Resume:\n#{resume}", schema:, effort: :medium
      )
      changed = PROFILE_SCHEMA_FIELDS.select do |f|
        new_val = out[f]
        next false if new_val.blank?
        overwrite || profile[f].blank?
      end
      profile.update!(changed.to_h { |f| [f, out[f].is_a?(Array) ? out[f].join(", ") : out[f]] })
      changed
    end

    # Ranks industry buckets by fit with your resume + goals + network.
    def industry_fit!
      a = anon
      buckets = IndustryClassifier.names
      schema = {
        type: "object", additionalProperties: false, required: ["industries"],
        properties: { industries: { type: "array", items: {
          type: "object", additionalProperties: false, required: %w[industry score reason],
          properties: { industry: { type: "string", enum: buckets }, score: { type: "number" },
                        reason: { type: "string" } }
        } } }
      }
      prompt = <<~TXT
        #{Context.profile_block(a)}
        #{Context.network_block(a)}

        Rank the 6 industries that fit this person best for a new-grad role (score 0..1).
        Weigh: resume skills, stated targets/curiosities, and how much network leverage they have there.
        Each reason: one short sentence, e.g. "Your CV + Rails work maps to their stack; 2 strong contacts."
      TXT
      out = Client.new.json(system: Context.system_prompt("Output JSON only."), prompt:, schema:, effort: :high)
      IndustryFit.transaction do
        IndustryFit.delete_all
        out["industries"].each do |i|
          IndustryFit.create!(industry: i["industry"], score: i["score"].to_f.clamp(0, 1), reason: a.restore(i["reason"]))
        end
      end
      IndustryFit.order(score: :desc)
    end

    # Fills in industry buckets for people/companies (AI version of IndustryClassifier).
    def classify!(people = Person.includes(:companies).to_a)
      return 0 if people.empty?
      a = anon
      schema = {
        type: "object", additionalProperties: false, required: ["people"],
        properties: { people: { type: "array", items: {
          type: "object", additionalProperties: false, required: %w[token industry],
          properties: { token: { type: "string" }, industry: { type: "string", enum: IndustryClassifier.names } }
        } } }
      }
      list = people.map { |p| "#{a.token(p)} | #{p.position} | #{p.company_names} | #{Array(p.industry_tags).join(', ')}" }
      out = Client.new.json(system: Context.system_prompt("Classify each contact into exactly one industry bucket."),
                            prompt: "Contacts:\n#{list.join("\n")}", schema:, effort: :low)
      by_token = people.index_by { |p| a.token(p) }
      out["people"].each do |r|
        person = by_token[r["token"]] or next
        person.update!(industry: r["industry"])
        person.companies.each { |c| c.update!(industry: r["industry"]) if c.industry.blank? }
      end
      out["people"].size
    end

    # Suggests fixes for imported rows (typos, company names, statuses). No names are sent.
    def clean_rows!(batch)
      schema = {
        type: "object", additionalProperties: false, required: ["rows"],
        properties: { rows: { type: "array", items: {
          type: "object", additionalProperties: false,
          required: %w[index position companies status industry introducer context],
          properties: {
            index: { type: "integer" }, position: { type: "string" },
            companies: { type: "array", items: { type: "string" } },
            status: { type: "string", enum: Person::STATUSES },
            industry: { type: "string", enum: IndustryClassifier.names },
            introducer: { type: %w[string null] }, context: { type: %w[string null] }
          }
        } } }
      }
      lines = batch.rows.each_with_index.map do |r, i|
        { index: i, position: r["position"], companies: r["companies"], status: r["status"],
          industry_tags: r["industry_tags"], how_met: r["how_met"] }.to_json
      end
      out = Client.new.json(
        system: Context.system_prompt(<<~T),
          You clean up a hand-typed networking spreadsheet. Fix obvious typos in positions and company
          names (use the company's real official name), split multiple employers, mark retired /
          self-employed / student correctly, choose the best industry bucket, and extract who introduced
          them (a relationship label like "Uncle" or "Family Friend", or null if met directly) and the
          context (work, family, school, volunteer, sport, linkedin, roommate, personal, event).
          Do not change anything that looks intentional.
        T
        prompt: lines.join("\n"), schema:, effort: :low
      )
      rows = batch.rows.map(&:dup)
      out["rows"].each do |fix|
        row = rows[fix["index"]] or next
        changes = []
        %w[position companies status industry introducer context].each do |f|
          next if fix[f] == row[f] || (fix[f].blank? && row[f].blank?)
          changes << "#{f}: #{Array(row[f]).join(' & ').presence || '—'} → #{Array(fix[f]).join(' & ').presence || '—'}"
          row[f] = fix[f]
        end
        row["ai_changes"] = changes
      end
      batch.update!(rows:)
      batch
    end

    # Turns a plain-English description of someone into structured fields.
    # Only the description is sent (you type the name into a separate field).
    def intake(description)
      schema = {
        type: "object", additionalProperties: false,
        required: %w[position company industry_tags how_met closeness notes],
        properties: {
          position: { type: "string" }, company: { type: "string" },
          industry_tags: { type: "array", items: { type: "string" } },
          how_met: { type: "string" }, closeness: { type: "integer" }, notes: { type: "string" }
        }
      }
      Client.new.json(
        system: Context.system_prompt("Extract a contact record from the user's note. Use empty strings for unknowns. closeness is 1-5 (default 3)."),
        prompt: anon.scrub(description), schema:, effort: :low
      )
    end

    # Web research on one company: hiring signals + careers site + new grad roles.
    def hiring_news!(company)
      text = Client.new.research(
        system: Context.system_prompt("Use web search. Be factual and cite nothing you did not find."),
        prompt: <<~TXT, max_searches: 4
          Company: #{company.name} (industry: #{company.industry || 'unknown'})
          Find, from the last ~3 months: hiring momentum (layoffs, freezes, funding, expansion),
          any new-grad / early-career / university program openings, and the official careers page URL.
          Finish with a fenced ```json block:
          {"summary": "<one sentence>", "signal": "rising|steady|slowing|unknown",
           "careers_url": "<url or empty>", "new_grad_roles": [{"title": "...", "url": "..."}]}
        TXT
      )
      data = Client.extract_json(text)
      attrs = { news_summary: [data["signal"], data["summary"]].compact_blank.join(": ").presence,
                news_checked_at: Time.current }
      if (url = data["careers_url"].presence)
        attrs[:careers_url] = url
        if url.include?("myworkdayjobs.com") && company.ats_provider.blank?
          attrs.merge!(ats_provider: "workday", ats_slug: url, ats_verified: false)
        end
      end
      company.update!(attrs)
      Array(data["new_grad_roles"]).first(10).each do |r|
        next if r["title"].blank? || r["url"].blank?
        Jobs::Ingest.upsert_posting(company, Jobs::Boards::Posting.new(
          external_id: "web-#{Digest::SHA1.hexdigest(r['url'])[0, 12]}", title: r["title"], url: r["url"]
        ), source: "web", force_new_grad: true)
      end
      data
    end

    # Drafts a short outreach message for a person.
    def draft_message(person, reason: nil)
      a = anon
      recent = person.interactions.first(3).map { |i| "#{i.occurred_on}: #{i.kind} — #{i.notes}" }
      prompt = <<~TXT
        #{Context.profile_block(a)}
        Write a short, warm, specific message (LinkedIn/text length, < 90 words) from the user to #{a.token(person)}.
        About them: #{person.position} at #{person.company_names.presence || person.status}; industry #{person.industry}.
        How they know each other: #{a.scrub(person.how_met_summary)}.
        Recent interactions: #{a.scrub(recent.join('; ')).presence || 'none logged'}.
        Notes: #{a.scrub(person.notes).presence || 'none'}
        Why now: #{a.scrub(reason).presence || 'reconnect and learn about new-grad opportunities'}
        Address them as #{a.token(person)} (it will be replaced with their name). Plain text only.
      TXT
      text = Client.new.json(system: Context.system_prompt("Output JSON."), prompt:, effort: :low,
                             schema: { type: "object", additionalProperties: false, required: ["message"],
                                       properties: { message: { type: "string" } } })["message"]
      a.restore(text)
    end
  end
end
