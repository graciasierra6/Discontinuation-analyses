# Kano, Kaduna and Lagos discontinuation analysis

These three standalone R scripts reproduce the numerical tables and statistical
figures behind the current combined state report. Each exports its named state's
results. They do not modify the saved HTML or PowerPoint, or create PowerPoint slides.

## Run

Use the **full Nigeria DHS 2024 women's IR**, as `.dta` or lossless `.rds`.
The full survey frame and the joint three-state AFT fit are required; a state-only
input will not reproduce the report. Install `haven`, `jsonlite`, `survival`,
`digest`, and `svglite`. Table reconciliation also requires `xml2`.

Set `DHS_IR_FILE` in your environment, then run from the project directory:

```sh
Rscript Kano_discontinuation_analysis.R --output-dir=output/kano --cache-dir=work/shared
Rscript Kaduna_discontinuation_analysis.R --output-dir=output/kaduna --cache-dir=work/shared
Rscript Lagos_discontinuation_analysis.R --output-dir=output/lagos --cache-dir=work/shared
```

Alternatively pass `--ir-file="$DHS_IR_FILE"`. Use `--help` for options,
`--validate-input` to check the input, and `--no-cache` for fresh calculations.
The shared cache is optional and contains aggregate results, not calendar records
or individual data. Its key includes the input checksum, code, bootstrap settings
and population assumption. The first run computes all three states; the other
scripts can reuse the matching joint results.

Add the following to each command to compare its 20 regenerated display tables
with the current combined report:

```sh
--reference-html=Kano_Kaduna_Lagos_discontinuation_analysis.html
```

Default inference uses 999 descriptive and 999 planning bootstrap replicates.
Use `--cores=4` for parallel planning on supported systems. The
`--planning-replicates=0` option is for point-only diagnostic runs; it does not
reproduce the report's planning confidence intervals.

## Definitions and calculations

- Reverse aligned `vcal_1`/`vcal_2` strings into chronological order, preserve
  valid calendar months and dates, and identify continuous method-use episodes.
  Retain delayed entry and censoring in the 3–62-month window before interview.
- Validate national life-table calculations against all 110 published rate cells
  and 10 weighted episode counts in Table 7.12. National Table 7.13 detailed reason
  percentages are a separate rounded-value check with tolerance 0.2 pp.
- Main discontinuation results pool modern methods, excluding EC. mCPR covers
  all women ages 15–49 and includes EC. Initiation mix includes all observed
  contraceptive starts, including EC and non-modern methods.
- All-cause and actionable timing are cumulative risks. The five-year distribution
  of recorded reasons is a separate measure. First-year actionable composition
  divides each cause's cumulative incidence by total actionable incidence.
- Actionable codes are method failure (1), wanted greater effectiveness (7),
  bleeding changes (15), other side effects/health (4, 5), and access/cost/convenience
  (6, 8, 10). Partner/spousal disapproval (3) is separate. Other endings remain
  competing events in life tables.
- Use `v005/1,000,000`, strata `v022` and clusters `v021`. Rao–Wu bootstrap draws
  use the full survey frame, including PSUs without eligible episodes. Repeated
  episodes and landmarks retain their woman's PSU multiplier. Seed: 20241107.
- Method-specific discontinuation is exploratory. Flag fewer than 125 month-1
  exposures and 125–249. Display “Insufficient data” below 25 exposures or five
  first-year endings. Cause cells below 10 first-year endings are flagged.
- Planning uses first-year, historical duration-aware, and lognormal AFT
  probabilities. Historical estimates pool sparse adjacent duration bins and use
  shorter-duration experience for the longest durations. AFT includes state effects
  and a shared scale across all three states, without method interactions.
- All three planning approaches treat actionable original-method endings as lost
  users; switching and restarting are not deducted. The observed 2024 current-user
  cohort is fixed across the two 2025 growth scenarios. Counts are per 100,000
  women in 2024, not verified absolute state population counts.
- Recent annual change is `(mCPR2024 − mCPR2018)/6`; longer-term change is
  `(mCPR2024 − mCPR2013)/11`, in pp/year. The script contains the prior validated
  state survey aggregates. No state FPET annual trend is assumed.
- Projected 2025 WRA uses the fixed national UN WPP ratio
  `57,393,553 / 55,819,549.5` as a common state assumption. Override it with
  `--wra-growth-factor` if intentionally changing that assumption.
  `mCPR gain (pp) = 100 × retained users / projected 2025 WRA`.
  Confidence intervals are joint survey-bootstrap intervals conditional on the
  fixed trend and population assumptions.

Outputs include 20 display-table CSVs per state, numerical JSON, monthly risks,
sample sizes, historical support, seven SVG figures, and validation manifests.
The fresh reconstruction matched all 60 state display tables in the current
combined HTML, including their confidence intervals. Descriptive estimates,
monthly timing and planning summaries also matched the saved numerical results.
Files record checksums and package versions without input locations. No survey
microdata, personal file locations, or credentials are bundled. Input acquisition
is caller-managed; automated acquisition and full report/deck rendering are separate.
