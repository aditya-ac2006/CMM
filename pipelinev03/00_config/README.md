# CMM Pipeline v03 — Configuration

This directory contains the configuration layer for the CMM
tire-modeling pipeline.

The configuration layer is intentionally kept separate from
data processing, model fitting, optimization, validation, and
output generation.

---

## Files

### `CMM_paths.m`

Defines filesystem locations.

It answers:

> Where is everything?

It contains paths for:

- CMM repository
- pipelinev02 reference
- private data
- canonical database
- pipelinev03 outputs
- model artifacts

### Important

`CMM_paths.m` must be side-effect free.

It must NOT:

- create output folders
- delete files
- modify files
- load datasets
- run fitting
- run optimization

It only defines and validates paths.

---

### `CMM_config.m`

Defines the general pipeline configuration.

It answers:

> What are we running?

Examples include:

- model runs
- development run
- holdout run
- excluded runs
- rim size
- pipeline version
- validation policy
- general fitting settings

---

### `CMM_model_config.m`

Defines the tire-model configuration.

It answers:

> How is the model structured?

It contains:

- Magic Formula formulation
- parameter names
- parameter groups
- operating-condition dependencies
- local-fit configuration
- response-surface targets
- physical constraints
- extreme-behavior features
- future vehicle-model interface

It does NOT perform fitting.

---

# Configuration Philosophy

Pipeline v03 follows four rules.

## 1. Configuration is not computation

Configuration files define behavior.

They do not perform analysis.

---

## 2. Paths are not hard-coded into analysis scripts

All filesystem paths should originate from `CMM_paths.m`.

Do not write machine-specific paths such as:

```text
C:\Users\Aditya\...