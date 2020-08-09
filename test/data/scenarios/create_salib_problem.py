# create_salib_problem

import SALib
from SALib.sample.latin import sample as latin_sampler
import pandas as pd

params = pd.read_csv("test_params.csv")

param_names = params["name"].tolist()
param_bounds = params.loc[:, ["min_val", "max_val"]].values.tolist()

problem = {
  'num_vars': len(param_names),
  'names': param_names,
  'bounds': param_bounds
}

raw_samples = latin_sampler(problem, 5)
samples = pd.DataFrame(raw_samples, columns=param_names)

samples.to_csv("sampled_params.csv", index=False)

