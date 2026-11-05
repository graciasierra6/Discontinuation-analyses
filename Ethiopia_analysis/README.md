# Ethiopia discontinuation analysis

The HTML is the saved report; the PPTX is the presentation. The R file contains
numerical analysis modules and a tested raw-IR preparation entry point.
Keep `assets/` beside the HTML: it is required to display its figures.

## Inputs and commands

Supply the authorized Ethiopia individual women's recode as Stata `.dta`.
Set `DHS_IR_FILE` in your own environment; no personal input location is saved
in the script. Use a new `--project-root` for a fresh reconstruction.

```sh
Rscript Ethiopia_final_html_analysis.R --validate
Rscript Ethiopia_final_html_analysis.R --validate-input --project-root=work --ir-file="$DHS_IR_FILE"
Rscript Ethiopia_final_html_analysis.R --run=prepare --project-root=work --ir-file="$DHS_IR_FILE"
```

The second command validates/stages the supplied input only. The third reads
the IR, reconstructs calendars/episodes, validates published Table 7.11,
and prepares covariates, current-user records and episode-month data.
Required preparation packages: `digest`, `haven`, `jsonlite`, `survival`,
`survey`, and `ggplot2`; Nigeria's model-input setup also checks for `nnet`.
`--packages` lists dependencies used by the wider numerical module collection.
Optional `--expected-ir-sha256` enforces a previously recorded source checksum.

## How the calendar is constructed

- Import all women without trimming calendar strings or altering source data.
  Check the validated release dimensions, unique IDs, required fields,
  weights, country, survey strata/PSUs, and calendar dates/positions.
- Align `vcal_1` (method/state) with `vcal_2` (ending reason), reverse them into
  chronological order, and retain `v019` valid months using `v017`/`v008` dates.
- Consecutive identical method/state characters form runs. Save both these
  runs and a month-level calendar retaining nonuse, pregnancy, births and
  terminations. Preserve each woman's link, weight and survey design.
- Select method episodes contributing exposure in the interview-relative
  3–62-month window. Apply the existing reason-recovery/boundary conventions,
  delayed entry and right censoring; validate against the published table.
- Apply the existing modern-method and model-cohort definitions. Nonuse and
  pregnancy spells do not enter modern-method discontinuation denominators.
  Other ending causes remain competing events, rather than being deleted.
- Age at episode start uses the woman's birth month; parity counts births
  through the episode-start month. Expand observed episode exposure into
  month-of-use rows, with continuing, actionable-ending or competing outcomes.

## Outputs and validation

All generated files go under `--project-root`: `Data/` for staged inputs,
`Data/Derived/` for calendars/episodes/covariates/month records, and
`output/validation/` for input SHA-256, software versions, derived-file checksums
and a preparation summary. Manifests contain no personal machine locations.
The full survey frame retains PSUs with no eligible episodes.

Fresh-input checks matched all 66 published rate cells and 6 episode
counts; model input contains 8,611 episodes and 70,691 episode-months.
Prepared legacy inputs were compared with those used by the saved analyses.

Use `--list` to list downstream modules and `--run=MODULE_NAME` (or an ordered
comma-separated list) to run them. Data preparation fits no regression or AFT
models; model objects and inference are produced in the subsequent numerical
stages. Module dependencies and their output filenames remain in the code.
The existing HTML/PPTX are not overwritten by preparation. A single-command
regeneration of the full formatted report is a separate, unfinished repository
step; this input workflow must not be described as that report renderer.

IR acquisition uses supplied files. No credentials, confidential microdata or
fixed personal paths are bundled. API acquisition and a pinned environment are
deferred. Publish the deliverables, not generated `work/` microdata or logs.
