# DRC: discontinuation analysis

- Report: `DRC_discontinuation_analysis.html`
- Presentation: `DRC_discontinuation.pptx` — 79 slides, without presenter notes.
- R entry point: `DRC_final_html_analysis.R`
- Planning horizon: observed **2024** users to projected **2025** mCPR.

## Rebuild the planning report

The R entry point includes numerical modules and an incremental HTML builder.
The tested build recalculates planning summaries from the included aggregate
point estimates and 500 joint survey bootstrap draws in `revision_inputs/`.
It preserves other analytical chapters and figures from the supplied HTML.
This is not a verified single-command raw-IR-to-entire-report rebuild. R does
not generate the presentation.

Requires R packages `jsonlite`, `digest`, and `abind`, and Python 3 with `lxml`.
Use `--packages` for dependencies of the wider numerical module collection.

```sh
Rscript DRC_final_html_analysis.R --validate
Rscript DRC_final_html_analysis.R --run=build-html --project-root=work/build
```

The result is `work/build/output/DRC_discontinuation_analysis.html`. The build
also writes numerical summaries and a validation manifest. Use `--base-html`
for a different validated layout, `--statistics-dir` for replacement aggregate
inputs, `--revision-inputs` for a growth-assumption JSON, and `--python` to select
Python. `--run=build-planning` produces numerical summaries without the HTML.
The build does not overwrite its inputs.

## Authorized IR preparation and numerical modules

No restricted microdata, fitted individual-level objects, credentials, or
personal computer locations are included. Supply the authorized IR at runtime:

```sh
Rscript DRC_final_html_analysis.R --run=prepare --project-root=work/raw --ir-file="$DHS_IR_FILE"
```

Preparation validates the IR and constructs chronological calendars, method
spells, episode-level records, repeated-woman links, weights, PSUs, strata,
delayed entry and censoring. It does not fit every downstream model.
`--list`, `--extract`, and `--run=MODULE_NAME` expose the retained stages.
The original `survey-update` sequence creates the original planning fits and
supporting tables. The new `217_aft_transition_planning.R` module additionally
needs those prepared records and fitted-family summaries; it fits the new
sensitivity and 500 bootstrap replicates. `218_validate_aft_transitions.R` adds
held-out PSU checks and `transition_validation.json`. Numerical modules are
ordered stages, not interchangeable alternatives to the tested aggregate build.

## Definitions and assumptions

Discontinuation analyses concern modern-method episodes excluding EC. EC stays
in all-women mCPR and counts as modern at the sensitivity endpoint. Potentially
actionable reasons are method failure, wanting a more effective method,
bleeding changes, other side effects/health, and access/cost/convenience.
Partner/spousal disapproval is separate and excluded. Other method endings
remain competing events.

Main tables count every actionable original-method ending as a lost modern
user. The exploratory first-year calculation ignores elapsed use. Historical
and AFT calculations estimate next-12-month endings conditional on current
method and time already used. Historical users at 61+ months use observed
37–60-month experience. The DRC AFT specification preserves six cause-specific
models: five actionable causes and other endings.

Three separate sensitivity sets deduct women using any modern method at the
common endpoint, 12 months from baseline: historical observed histories; AFT
endings with observed histories; and AFT endings with a categorical immediate
state model plus AFT-based subsequent transitions. A switch/restart only
reduces a loss if modern use persists to the endpoint.

The new post-ending model uses 987 endings from 833 women. Selected transition
families are lognormal for modern use, loglogistic for nonmodern use/nonuse,
and lognormal for pregnancy-related states. Pregnancy-related transitions pool
prior methods and causes. Boundary fits are excluded from family selection.
Five-fold held-out PSU checks overpredict month-12 modern use by 5.4 percentage
points; this may understate year-end losses and limits the sensitivity estimate.
IUD has only 23 eligible episodes and 14 current users: its AFT ending and
post-ending predictions use the Other-modern proxy. Intervals do not capture
uncertainty about that proxy, distribution-family choice, or transportability.

Survey uncertainty uses the full 778-PSU, 51-stratum frame, including PSUs with
no eligible episodes. Five hundred smoothed Rao–Wu resamples use epsilon
0.0001; summary deviations are corrected for smoothing. Joint draws propagate
current-use composition, observed probabilities and fitted-model uncertainty.
Repeated records remain linked within PSU. AFT families are fixed in resamples.
Confidence limits are not additive; zero-event cells have no reliable empirical
interval.

The observed 2024 cohort is fixed across scenarios. Population and growth are
fixed assumptions. The three annual changes are the 2014–2024 DHS trend
(+0.1773 pp), 2007–2024 DHS trend (+0.1905 pp), and an FPET-informed increment
(+0.40 pp). The last is an assumed increment applied to the DHS baseline,
not an official FPET forecast. Women aged 15–49 are from the UN WPP 2024
population extract: 24,386,254.5 in 2024 and 25,246,885 in 2025.
Retained users divided by **2025** WRA, multiplied by 100, give mCPR pp gains.
Changing the secular-growth assumption changes projected mCPR but does not
change the fixed cohort's retained-user contribution.
