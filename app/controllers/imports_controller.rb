class ImportsController < ApplicationController
  def new
    @files = Dir[Profile.data_dir.join("imports/*.csv")].map { |f| File.basename(f) }.sort
  end

  def create
    text, name =
      if params[:file].respond_to?(:read)
        [params[:file].read, params[:file].original_filename]
      elsif params[:existing].present?
        path = Profile.data_dir.join("imports", File.basename(params[:existing]))
        [File.read(path), File.basename(path)]
      end
    return redirect_to(new_import_path, alert: "Choose a CSV file.") if text.blank?

    text = text.force_encoding("UTF-8").scrub
    linkedin = Importers::LinkedinCsv.linkedin?(text)
    rows = linkedin ? Importers::LinkedinCsv.new(text).rows : Importers::SpreadsheetCsv.new(text).rows
    return redirect_to(new_import_path, alert: "No rows found. Check the column names in data/profile.yml (spreadsheet_columns).") if rows.empty?

    batch = ImportBatch.create!(filename: name, format: linkedin ? "linkedin" : "spreadsheet", rows:)
    redirect_to import_path(batch)
  end

  def show
    @batch = ImportBatch.find(params[:id])
  end

  # Saves your edits, then either asks the agent for fixes or applies the import.
  def update
    @batch = ImportBatch.find(params[:id])
    edited = params.fetch(:rows, {}).to_unsafe_h
    rows = @batch.rows.each_with_index.map do |row, i|
      e = edited[i.to_s] or next row
      row.merge(
        "include" => e["include"] == "1",
        "name" => e["name"], "position" => e["position"],
        "companies" => e["companies"].to_s.split(/\s*&\s*/).map(&:strip).reject(&:empty?),
        "status" => e["status"], "industry" => e["industry"],
        "introducer" => e["introducer"].presence, "context" => e["context"].presence,
        "closeness" => e["closeness"].to_i.clamp(1, 5)
      )
    end
    @batch.update!(rows:)

    if params[:commit_action] == "clean"
      Agent::Tasks.clean_rows!(@batch)
      redirect_to import_path(@batch), notice: "Suggested fixes are highlighted. Review, then import."
    else
      n = Importers::Applier.apply_batch!(@batch)
      redirect_to people_path, notice: "Imported #{n} people. Rate closeness below, then hit Refresh on the graph."
    end
  end
end
