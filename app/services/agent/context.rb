module Agent
  # Builds the shared "who I am" block for every agent call (anonymized).
  module Context
    module_function

    def profile_block(anon)
      p = Profile.current
      <<~TXT
        ## The user (refer to them as "you")
        Graduating: #{p["graduation_date"]} — #{p["degree"]}
        Locations: #{p.locations.join(", ")}
        Work authorization: #{p["work_authorization"]}
        Target industries: #{p.target_industries.join(", ")}
        Curious about: #{p.curious_industries.join(", ")}
        Avoid: #{p.exclusions.join(", ")}
        Target roles: #{p.target_roles.join(", ")}

        ## Resume
        #{anon.scrub(p.resume_text).strip.presence || "(no resume provided)"}
      TXT
    end

    def network_block(anon, people = Person.includes(:companies, :introducer).to_a)
      lines = people.map do |pr|
        [anon.token(pr), pr.position, pr.company_names.presence || pr.status, pr.industry,
         Array(pr.industry_tags).join("/"), "closeness #{pr.closeness}/5",
         ("via #{pr.introducer.label}" if pr.introducer)].compact.join(" | ")
      end
      "## Network (names replaced by tokens)\n" + lines.join("\n")
    end

    def system_prompt(task)
      <<~TXT
        You are a career-networking strategist for a soon-to-graduate student. You help them
        understand which industries fit them, which contacts can help, and when to reach out.
        Be concrete and brief. Contacts appear as tokens like P-012; always refer to people by
        their token, never invent names. #{task}
      TXT
    end
  end
end
