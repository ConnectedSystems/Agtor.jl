Agtor.jl
========

[![Build Status](https://travis-ci.com/ConnectedSystems/Agtor.jl.svg?branch=master)](https://travis-ci.com/ConnectedSystems/Agtor.jl)
[![Codecov](https://codecov.io/gh/ConnectedSystems/Agtor.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/ConnectedSystems/Agtor.jl)


An agricultural management model currently under development.


Description
===========
Agtor is designed to facilitate interdisciplinary exploratory scenario modelling of agricultural systems and related system interactions. Agtor operates at a zonal scale where the zone may represent an individual farm/field, sub-catchment area, or the catchment itself.

Based on an earlier version developed for the Lower Campaspe region in North-Central Victoria.

Contributions are welcome.


Why the name "Agtor"?
---------------------

The model represents agricultural actors within a system and so the name is a portmandeau of "agriculture" and "actor".


Development Setup
=================

1. Fork or clone this repository.
2. Navigate to the project directory and instantiate package environment:

```bash
$ julia --project=.

julia> ]

(Agtor) pkg> instantiate
```

Examples may use `PyCall` to interact with the SALib package.

To set up PyCall, first activate the target Python environment and then
run `Pkg.build()`, for example:

```bash
$ conda activate salib

(salib) $ julia --project=.

julia> using Pkg

julia> Pkg.build("PyCall")
   Building Conda ─→ `...`
   Building PyCall → `...`

julia>
```


Tentative usage examples are provided in the `examples` directory.

Tests are found in the `test` directory and the `runtests.jl` will invoke all available tests.

As Agtor is under development all current details are subject to change.

Documentation is forthcoming.
