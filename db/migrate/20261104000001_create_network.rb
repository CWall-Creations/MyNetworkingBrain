class CreateNetwork < ActiveRecord::Migration[8.1]
  def change
    create_table :companies do |t|
      t.string :name, null: false
      t.string :normalized_name, null: false, index: { unique: true }
      t.string :industry
      t.string :ats_provider                 # greenhouse | lever | ashby | workday | none
      t.string :ats_slug                     # board slug, or careers URL for workday
      t.boolean :ats_verified, default: false, null: false
      t.datetime :ats_checked_at
      t.string :careers_url
      t.boolean :watch, default: false, null: false   # track even with no contacts there
      t.text :news_summary                   # latest hiring/news signal from the agent
      t.datetime :news_checked_at
      t.timestamps
    end

    # Hubs like "Uncle", "Sister", "Family Friend" who connected you to people.
    create_table :introducers do |t|
      t.string :label, null: false, index: { unique: true }
      t.references :person                   # set when the hub is also a contact (e.g. your uncle)
      t.timestamps
    end

    create_table :people do |t|
      t.string :name, null: false
      t.string :position
      t.string :status, default: "employed", null: false  # employed | retired | self_employed | student | unemployed
      t.string :industry                     # broad bucket (graph color/cluster)
      t.json :industry_tags, default: []     # your raw tags, e.g. ["Payments", "Developer Tools"]
      t.string :how_met                      # raw text, kept verbatim
      t.string :relationship_context         # work | family | school | volunteer | ...
      t.references :introducer, foreign_key: true
      t.date :met_on
      t.date :last_contact_on                # optional manual override when you have no logged interactions
      t.integer :closeness, default: 3, null: false
      t.text :notes
      t.string :source, default: "form", null: false  # form | yaml | spreadsheet | linkedin | agent
      t.string :linkedin_url
      t.timestamps
    end
    add_index :people, :name

    create_table :affiliations do |t|
      t.references :person, null: false, foreign_key: true
      t.references :company, null: false, foreign_key: true
      t.boolean :primary, default: false, null: false
      t.boolean :current, default: true, null: false
      t.timestamps
    end
    add_index :affiliations, [:person_id, :company_id], unique: true

    create_table :interactions do |t|
      t.references :person, null: false, foreign_key: true
      t.date :occurred_on, null: false
      t.string :kind, null: false, default: "message"
      t.text :notes
      t.timestamps
    end

    create_table :job_postings do |t|
      t.references :company, null: false, foreign_key: true
      t.string :external_id, null: false
      t.string :title, null: false
      t.string :url
      t.string :location
      t.string :source                       # greenhouse | lever | ashby | workday | curated | web
      t.boolean :new_grad, default: false, null: false
      t.datetime :posted_at
      t.datetime :first_seen_at
      t.datetime :last_seen_at
      t.timestamps
    end
    add_index :job_postings, [:company_id, :external_id], unique: true

    create_table :company_snapshots do |t|
      t.references :company, null: false, foreign_key: true
      t.date :taken_on, null: false
      t.integer :open_count, default: 0, null: false
      t.integer :new_grad_count, default: 0, null: false
      t.timestamps
    end
    add_index :company_snapshots, [:company_id, :taken_on], unique: true

    create_table :industry_fits do |t|
      t.string :industry, null: false, index: { unique: true }
      t.float :score, null: false
      t.text :reason
      t.timestamps
    end

    create_table :feed_items do |t|
      t.string :key, null: false, index: { unique: true }  # stable id so dismissals stick
      t.string :kind, null: false            # job_match | reach_out | industry_fit | trend
      t.float :score, default: 0, null: false
      t.string :headline, null: false
      t.string :reason
      t.string :url
      t.references :person, foreign_key: true
      t.references :company, foreign_key: true
      t.references :job_posting, foreign_key: true
      t.string :state, default: "open", null: false  # open | done | dismissed
      t.datetime :refreshed_at
      t.timestamps
    end

    create_table :import_batches do |t|
      t.string :filename
      t.string :format                       # spreadsheet | linkedin
      t.json :rows, default: []              # parsed rows awaiting your review
      t.string :state, default: "review", null: false  # review | applied
      t.timestamps
    end

    create_table :refresh_runs do |t|
      t.datetime :started_at
      t.datetime :finished_at
      t.text :log
      t.timestamps
    end
  end
end
