"""An example of collating all model parameters from specification files."""

using Agtor
using CSV

# Data location
zone_spec_dir = "test/data/zones/"

# Load a Zone specification
zone_params = load_spec(zone_spec_dir)
tgt_zone = zone_params[:Zone_1]

@info tgt_zone

# Collate all the non-constant variables in the model
agparams = collect_agparams(tgt_zone)

@info agparams

CSV.write("collated_params.csv", agparams)