# Loads your network from data/network.yml (or the demo data in data.example/).
n = Importers::YamlNetwork.new.import!
puts "Loaded #{n} people from #{Profile.data_dir.join('network.yml')}"
