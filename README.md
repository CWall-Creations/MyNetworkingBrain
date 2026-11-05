# MyNetworkingBrain

A private, local-only map of the people you know, plus an agent that knows your goals
and tells you **which openings in your network matter and when to reach out**.

- **Floating network graph.** You in the center, people grouped by industry, introducers
  (Uncle, Sister, Family Friend…) as hubs. Thicker, closer links mean stronger connections.
  A dashed ring means that company is hiring new grads.
- **"Right now" feed.** At most 7 items: new-grad openings at your contacts' companies,
  who to reconnect with (based on hiring season, a cooling connection and time since you last talked),
  hiring trends, and industries where you fit but have few contacts.
- **Agent (Claude).** Ranks industries by fit with your resume, cleans up imports,
  turns "met her at a hackathon, PM at Stripe" into a contact, researches hiring news,
  and drafts outreach messages.

Everything runs on your machine. **Your data is never committed** (see Privacy below).

## Use it as your own

```bash
git clone <this repo> && cd MyNetworkingBrain
# Ruby 3.3+ (see .ruby-version). With rbenv: rbenv install 3.3.13
bin/setup            # installs gems, creates data/ + .env, installs the privacy hook, starts the app
```

Open http://localhost:3000. You'll see a demo network. Then make it yours:

1. **Profile.** Edit `data/profile.yml` (or the Profile page): graduation date, locations,
   target and curious industries, target roles. Put your resume in `data/` and set `resume_file`.
2. **People.** Pick any combination:
   - *Spreadsheet:* export it as CSV (Google Sheets: File → Download → CSV). If your column
     headers differ, map them under `spreadsheet_columns` in `data/profile.yml`.
     Then People → Import CSV, review each row, and click Import.
   - *LinkedIn:* Settings → Data privacy → Get a copy of your data → Connections. Import `Connections.csv`.
   - *By hand:* People → Add person, or "Describe someone" and let the agent fill in the form.
   - *YAML:* `data/network.yml` (same format as `data.example/network.yml`), loaded by `bin/rails db:seed`.
   To clear the demo people: `bin/rails db:reset` after emptying `data/network.yml`.
3. **Rate closeness** (1–5) right in the People table.
4. **Agent.** Put `ANTHROPIC_API_KEY=...` in `.env` and restart. Without a key, everything
   except the AI features still works (industries come from keywords in `config/industries.yml`).
5. Hit **Refresh** on the graph. The app also refreshes itself once a day while it's open.

### Spreadsheet format

| Name | Role | Company | Tags | How we met |
|---|---|---|---|---|
| Jamie Park | Data Analyst | Spotify | Music Streaming, Analytics | Coworker of Aunt |

- "How we met" is parsed into an introducer hub plus a context: `Friend of Sister` →
  hub "Sister"; `Coworker of Aunt` → hub "Aunt", context work. If someone's entry is just
  `Aunt`, *they* become the Aunt hub, and everyone introduced by Aunt orbits them.
- Multiple employers: `Pixel Forge & Northwind`. Non-employers like `Retired` / `Self-employed`
  become a status and are skipped for job searches.

## How it decides things

| | |
|---|---|
| **Strength** | `closeness/5 × recency`. Recency halves every `half_life_days` (default 120) since your last logged interaction, and never drops below 20%. Logging a coffee chat refreshes it. |
| **Openings** | Public job boards (Greenhouse, Lever, Ashby, auto-detected per company; Workday if you paste the careers URL on the Companies page), plus community new-grad lists (`config/job_sources.yml`), plus agent web search. Only new-grad roles matching your `target_roles` count. |
| **Reach-out timing** | Every one of these must be true: (industry hiring season in `config/hiring_cycles.yml`, **or** live new-grad roles, **or** openings trending up) **and** the connection is cooling **and** at least `min_gap_days` since you last talked **and** it's relevant to your target industries (or you're close). Quiet in late December. |
| **Trends** | A snapshot of each company's open roles is taken on every refresh. A ±20% change over ~3 weeks shows up in the feed. |

## Privacy

- Personal data lives only in `data/` (profile, resume, network, imports), `storage/` (SQLite) and `.env`.
  All of these are gitignored.
- `bin/privacy-check` runs as a **git pre-commit hook** (installed by `bin/setup`). It blocks
  commits that include those paths, any CSV/PDF, or any file containing the name of someone in your local database.
  Run `bin/privacy-check --all` to scan everything that's tracked.
- **Claude never sees your contacts' names.** They're replaced with tokens (`P-007`) before
  each request and swapped back locally. Your own name becomes `[ME]`. Company names, roles and
  industries are sent. When you "describe someone", only the description is sent; the name field stays local.

## Project map

```
app/services/
  how_met_parser.rb, company_parser.rb   # free-text cleanup for imports
  strength_score.rb                      # hybrid connection strength
  importers/ exporters/                  # CSV / LinkedIn / YAML in, CSV out
  jobs/                                  # job boards, new-grad filter, curated lists, ingestion
  timing/reach_out_advisor.rb            # "good time to reach out?"
  feed/builder.rb                        # the ranked feed
  agent/                                 # Claude client, anonymizer, tasks
  graph_data.rb                          # nodes/links for the D3 graph
app/javascript/controllers/graph_controller.js   # the floating graph (D3)
config/industries.yml, hiring_cycles.yml, job_sources.yml   # generic, editable
data.example/                            # template data (committed)
```

Tests: `bin/rails test`
