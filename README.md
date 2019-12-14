Agtor-jl
=====

[![Build Status](https://travis-ci.com/ConnectedSystems/agtor.jl.svg?branch=master)](https://travis-ci.com/ConnectedSystems/agtor.jl)
[![Codecov](https://codecov.io/gh/ConnectedSystems/agtor.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/ConnectedSystems/agtor.jl)


An agricultural management model currently under development.


Description
===========
Based on an earlier version developed for the Lower Campaspe region in North-Central Victoria.

This repository holds the experimental Julia port of [Agtor](https://github.com/ConnectedSystems/Agtor)

Agtor is designed to facilitate multi-disciplinary investigation of interactions across systems that interact with agriculture. Agtor operates at a zonal scale where the zone may represent an individual farm, sub-catchment area, or the catchment itself.

Contributions are welcome.

Why the name "Agtor"?
------------

The model represents agricultural actors within a system and so the name is a portmandeau of "agriculture" and "actor".


Development Setup
=================

1. Fork or clone this repository.
2. Set up and activate a conda environment for the project (optional but recommended).

The tests found in the `tests` directory represent tentative usage examples. The `test_run.py` file gives an example of a model run. (not yet available for the Julia version)

Run from the top-level of the project, e.g.

```bash
$ julia ./tests/test_run.py
```

As Agtor is under development all current details are subject to change.