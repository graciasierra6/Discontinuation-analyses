# DHS survey design

All analyses use the woman's sampling weight `v005 / 1,000,000`, primary
sampling unit `v021`, and sampling-error stratum `v022` for the three supplied
survey releases. PSU identifiers are nested within strata. No finite-population
correction is supplied; inference uses the with-replacement PSU approximation.
The input checks reject missing/invalid design identifiers or nonpositive base
weights. Singleton strata require an explicit documented treatment and otherwise
stop estimation.

The sampling descriptions were checked against the actual IR identifiers:

| Survey | Documented stratification | IR strata | Observed IR PSUs |
|---|---|---:|---:|
| Ethiopia 2024–25 | Region × urban/rural; Addis Ababa urban-only | 27 | 797 |
| Nigeria 2024 | State/FCT × urban/rural | 74 | 1,380 |
| DRC 2023–24 | Province × urban/rural; Kinshasa urban-only | 51 | 778 |

Within each IR, `v022` maps one-to-one to the stated geography/residence cells,
each `v021` belongs to one stratum, and `v021` agrees with `v001`. Reporting
geographies do not replace sampling strata: Nigeria's six-zone estimates retain
all 74 state/residence strata. The PSU counts above describe observed records,
rather than every cluster originally selected for fieldwork.

Sampling sources: [Ethiopia report](https://ess.gov.et/wp-content/uploads/2026/01/edhs-2024-25-kir-01172026.pdf),
[Nigeria report](https://preview.dhsprogram.com/pubs/pdf/PR157/PR157.pdf), and
[DRC Appendix A](https://dhsprogram.com/pubs/pdf/FR393/FR393.pdf).
DRC documents two sampling stages in urban areas and three in rural areas.
Inference here uses the declared PSU/stratum design and compound individual
weights under the ultimate-cluster with-replacement approximation; it does not
reconstruct lower-stage sampling fractions.

## Women, episodes and months

The full realized IR sample supplies the sampled PSU and stratum inventory.
Calendar runs, episodes and person-months
retain their woman linkage and original sampling weight. Calendar preparation
also retains the original PSU and stratum. An episode weight is not divided by
the number of episodes contributed by its woman. All records from the same PSU
remain together for inference and resampling.

A survey object is an estimator input, not a permanent property of a data frame.
The shared implementation in `survey_design.R` builds designs for the relevant
record level. Domain calculations retain the full original PSU/stratum frame,
including PSUs with no eligible records. Zero-weight frame placeholders have no
contribution to estimates; full-frame degrees of freedom are retained explicitly.
The same implementation is embedded in the standalone country and state sources
and the independent extensions runner. Tests check that the copies agree.

## Estimation

- **Percentages and means:** `survey::svydesign()` with `svyratio()` or
  `svymean()`, and Taylor-linearized uncertainty. The standardized national
  descriptive output covers current use, method mix, initiation and recorded
  reason shares by country/geography and method. Some rendering and life-table
  kernels use equivalent weighted arithmetic; it does not supply independent-row
  standard errors.
- **Binary regression:** `survey::svyglm()` with the declared design.
- **Multinomial regression:** weighted `nnet::multinom()` coefficients with
  full-frame PSU score covariance from `survey::svyrecvar()` and a sandwich
  derivative. Fitted point objects retain this covariance for `summary()` and
  `vcov()`. Prediction-only or bootstrap-refit objects reject ordinary-Hessian
  inference; their uncertainty comes from the joint survey replicates.
- **AFT regression:** point fits use `survey::svysurvreg()`. Within stratified
  PSU bootstrap replicates, the same weighted likelihood is refitted and the
  distribution of replicate results supplies joint planning uncertainty.
  `svysurvreg()` intentionally removes its likelihood. Where family selection
  is required, `dhs_aft_aic()` separately retains the previous weighted
  pseudo-AIC comparison; this is not a survey-adjusted likelihood test. The
  intervals condition on that family selection.
- **Life tables and competing events:** weighted monthly risk sets and cause-
  specific cumulative incidence retain delayed entry and right censoring. Other
  ending reasons remain competing events. Design uncertainty uses full-frame
  stratified PSU replicates or the documented PSU influence calculation.
- **Switching, restarting and custom transitions:** weighted histories and
  likelihoods use the same inherited design. Joint PSU replicates refit models
  and current-user composition together. Direct switches and modern use at the
  endpoint remain distinct quantities.

Every resampling procedure draws PSUs within strata. A shared multiplier applies
to all women, episodes and months in a PSU. Rao–Wu and documented positive
multiplier schemes preserve the full survey frame. Sparse-event limits and
replicate-convergence checks are retained. Unweighted sample counts remain
explicitly labelled; DHS normalized weights alone are not national population
counts. User counts use the stated external population scale.

## Comparisons and interpretation

Survey inference usually changes uncertainty without changing a weighted point
estimate. Identical point comparisons require identical records, weights, event
and censoring definitions, model specification and standardization population.
The source also resolves the current-use duration code `v337=95` from
`v008 - v317`; this is a duration correction, separate from survey adjustment,
and can change AFT predictions. Unresolved special codes stop estimation.

Population projections, secular-growth assumptions and selected AFT families
are held fixed in the planning intervals. Sparse samples, model-family choice,
historical transportability and intervention effectiveness are not fully captured
by survey intervals. Confidence-interval endpoints do not add across cells.

## Running checks and reviewing changed reports

```sh
Rscript tests/test_survey_design.R
Rscript build_reports.R --check --python=python3
Rscript build_reports.R --country=Nigeria --ir-file="$DHS_IR_FILE" \
  --output-dir="$DHS_BUILD_DIR/nigeria" --python=python3 \
  --reference-policy=report
```

The unit checks cover domain/zero-domain-PSU variance, repeated-record inheritance,
regression covariance, and weighted-versus-survey point equivalence. Complete
builds require the authorized IR and regenerate the national numerical stages.
Source checks alone are not a complete numerical rebuild.

The default `--reference-policy=strict` stops on differences from the reviewed
reports. `report` writes a candidate report and comparison results when numerical
results differ; it does not label a failed comparison as passed. Build failures
still stop execution. Approved HTML/PPTX files remain read-only under either
policy. Restricted records, intermediate fits and runtime validation outputs stay
outside the repository.

## Method references

- [DHS guidance on design-based analysis](https://github.com/DHSProgram/DHS-Analysis-Code/blob/main/Intro_DHSdata_Analysis/Readme.md).
- [Survey percentages and totals](https://r-survey.r-forge.r-project.org/pkgdown/docs/reference/surveysummary.html).
- [Survey AFT regression and linearized errors](https://r-survey.r-forge.r-project.org/pkgdown/docs/reference/svysurvreg.html).
