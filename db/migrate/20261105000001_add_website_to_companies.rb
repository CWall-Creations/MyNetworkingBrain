class AddWebsiteToCompanies < ActiveRecord::Migration[8.1]
  def change
    add_column :companies, :website, :string
    add_column :companies, :careers_checked_at, :datetime
  end
end
