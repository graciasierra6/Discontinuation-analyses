# DRC discontinuation analysis

The HTML is the saved report; the PPTX is the presentation. The R file contains
numerical analysis modules and a raw-IR preparation entry point.
Keep `assets/` beside the HTML: it is required to display its figures.

## Inputs and commands

Supply the authorized DRC 2023–24 individual women's recode as a Stata `.dta`
file. Set `DHS_IR_FILE` in your own environment; no personal input location is
saved in the script. Use a new `--project-root` for a fresh reconstruction.

```sh
Rscript DRC_final_html_analysis.R --validate
Rscript DRC_final_html_analysis.R --validate-input --project-root=work --ir-file="$DHS_IR_FILE"
Rscript DRC_final_html_analysis.R --run=prepare --project-root=work --ir-file="$DHS_IR_FILE"
```

The second command validates/stages the input only. The third reconstructs
calendars/episodes, checks published Table 7.13 and prepares the model inputs.
Preparation requires R 4.0+ and the `digest`, `haven`, `jsonlite` and `nnet`
packages. `--packages` lists dependencies used by the wider module collection.
Optional `--expected-ir-sha256` enforces a previously recorded source checksum.

## Calendar and analysis inputs

- Import all 27,583 women without trimming calendar strings or changing the
  source file. Check the release dimensions, unique identifiers, required
  variables, positive weights, country and calendar dates/positions.
- Align `vcal_1` (method/state) with `vcal_2` (ending reason), reverse them into
  chronological order and retain `v019` valid months using `v017`/`v008` dates.
- Consecutive identical method/state characters form runs. Save these runs
  and a month-level calendar retaining nonuse, pregnancy, births and
  terminations, with the original woman link, weight, PSU and stratum.
- Select method episodes contributing exposure in the interview-relative
  3–62-month window. Preserve the existing within-run reason recovery,
  observation-boundary handling, delayed entry and right censoring.
- Preserve the existing modern-method/model cohorts, excluding EC from
  ongoing-method discontinuation. Nonuse and pregnancy spells do not enter
  modern-method denominators. Other ending reasons remain competing events.
- Retain all 26 provinces and the full 778-PSU, 51-stratum survey frame,
  including PSUs without eligible episodes. Small-sample flags belong in the
  subsequent statistical analyses; preparation does not pool provinces.
- Age at episode start uses the woman's birth month; parity counts births
  through the episode-start month. Expand observed exposure into duration-
  month records with continuing, actionable-ending or competing outcomes.

## Outputs and checks

Generated files stay under `--project-root`: the staged IR in `Data/`, calendars,
episodes/covariates/month records in `Data/Derived/`, and checksum, software
version and validation summaries in `output/validation/`. Manifests use
project-relative output names and contain no personal machine locations.

The existing Table 7.13 comparison matches 104/110 published rate cells and
all 10 episode counts. Six rate cells differ by 0.1 percentage point. These
known differences are documented, not forced to match. Preparation also checks
all unrounded table results against the frozen released-data reference used
by the existing analyses. Model inputs contain 4,146 episodes and 31,415
observed episode-months. Preparation does not fit regression or AFT models.

Use `--list` to list downstream modules and `--run=MODULE_NAME` (or an ordered
comma-separated list) to run them. Their dependencies and output filenames
remain in the code. Preparation does not overwrite the saved HTML/PPTX.
A single-command rebuild of the full formatted report remains a separate
repository step; this input workflow is not that report renderer.

IR acquisition uses supplied files. No credentials, confidential microdata or
fixed personal paths are bundled. API acquisition and a pinned environment
are deferred. Publish the deliverables, not generated `work/` data or logs.
