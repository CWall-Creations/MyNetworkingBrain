# data.example/

Template data. `bin/setup` copies this folder to `data/` (gitignored) the first time it runs.
Put **your** real info in `data/`, never here: this folder is committed to git.

| File | What it is |
|---|---|
| `profile.yml` | You: graduation, locations, goals, strength tuning, spreadsheet column mapping |
| `network.yml` | Optional starting network (YAML). You can also import a CSV or add people in the app |
| `resume.md` | Your resume (`.md`, `.txt` or `.pdf`; set `resume_file` in profile.yml) |
| `imports/` | Drop CSV exports here (Google Sheets / LinkedIn `Connections.csv`) |
