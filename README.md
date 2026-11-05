# Contraceptive Discontinuation Analyses

This repository examines modern contraceptive method use and discontinuation in
Ethiopia, Nigeria, and the Democratic Republic of the Congo (DRC), using
Demographic and Health Survey (DHS) individual women's recode data.

The analyses describe which methods women initiate, when and why method-use
episodes end, how patterns vary across population groups and geographic areas,
and the implications of improved continuation for modern contraceptive
prevalence (mCPR). Reports and presentations support family planning research
and program planning.

## Country coverage

| Country | Survey | Main subnational geography |
| --- | --- | --- |
| Ethiopia | DHS 2024–25 | Survey regions |
| Nigeria | DHS 2024 | Six geopolitical zones |
| DRC | DHS 2023–24 | 26 provinces |

A common analytical framework is applied across countries while retaining
country-specific survey coding, published-table definitions, and documented
cohort restrictions.

## Analyses

- Method initiation and method mix, nationally and subnationally.
- All-cause modern-method discontinuation and its timing during the first year.
- Reasons for discontinuation, by method, population subgroup, and geography.
- Discontinuation due to potentially actionable causes.
- Adjusted subgroup and subnational comparisons, including comparisons that
  account for method mix and measured population characteristics.
- Post-discontinuation switching, restarting, and contraceptive-use pathways.
- Estimated users discontinuing and mCPR percentage-point scenarios under
  alternative continuation and growth assumptions.

**Potentially actionable causes** comprise method failure, wanting a more
effective method, changes in menstrual bleeding, other side effects/health
concerns, and access/cost/convenience. Method failure means becoming pregnant
while using a method; it is distinct from stopping to become pregnant. This
classification does not imply that every associated ending is preventable.

## Data and methods

The woman-level IR file is used to align the method/state calendar (`vcal_1`)
with the discontinuation-reason calendar (`vcal_2`). Chronological monthly
histories are converted into continuous method-use episodes. Regression inputs
expand eligible episodes into observed months of method use.

A woman can contribute multiple episodes. Modern-method analyses use eligible
modern-method episodes; method-specific analyses use episodes of that method.
Nonuse, pregnancy, birth, and termination states remain in the calendar but do
not enter modern-method discontinuation denominators. Broader method groups
may appear separately when replicating published DHS tables.

Life tables retain delayed entry and right censoring, with other ending causes
competing in reason-specific cumulative incidence. Weights derive from
`v005 / 1,000,000`; survey-design fields and woman/episode links are preserved
for inference. Uncertainty methods are specified for each analysis. Preparation
retains the full PSU/stratum frame, including PSUs without eligible episodes.

EC is excluded from ongoing-method discontinuation but remains in current mCPR
where included in the survey's modern-method classification. Country materials
explain additional definitions, model specifications, and small-sample flags.

## User projections and mCPR

The planning analyses distinguish three approaches:

1. **First-year probabilities:** apply probabilities during months 1–12 after
   initiation to the current-user stock.
2. **Historical duration-aware probabilities:** use observed calendar experience
   to estimate next-12-month outcomes conditional on elapsed method use.
3. **AFT survival models:** estimate next-12-month outcomes conditional on
   elapsed use through fitted survival distributions.

A method ending is distinct from leaving modern use: a woman may switch to
another modern method or later restart. Gross-ending scenarios and
switching/restarting sensitivities therefore use different assumptions.

```text
mCPR difference (percentage points)
    = 100 × additional modern users / projected women aged 15–49
```

The baseline and alternative scenario use the same target-year population.
Population inputs, mCPR growth assumptions, and probability definitions are
documented by country. These are conditional planning scenarios, rather than
identified causal program effects.

## Files

Each country bundle contains:

| File | Purpose |
| --- | --- |
| `*_discontinuation_analysis.html` | Analytical report with tables, figures, and explanations |
| `*_final_html_analysis.R` | Numerical modules and parameterized input preparation |
| `*.pptx` | Presentation of findings and planning scenarios |
| `README.md` | Country-specific instructions and validation notes |
| `assets/` | Figures required by the HTML |

Keep each HTML file beside its corresponding `assets/` directory.

## Running the code

Use R 4.0 or later and install the required packages. `--packages` lists the
country script's dependencies. Obtain authorized IR data through the
[DHS Program](https://dhsprogram.com/data/Access-Instructions.cfm); restricted
microdata and credentials are not included in this repository.

Run from the directory containing the selected country script. Supply the IR
location at runtime through `--ir-file` or `DHS_IR_FILE`. For example:

```sh
# Check that the embedded R modules parse.
Rscript Ethiopia_final_html_analysis.R --validate

# Validate and stage the supplied IR file without running the analyses.
Rscript Ethiopia_final_html_analysis.R --validate-input --project-root=work/ethiopia --ir-file="$DHS_IR_FILE"

# Reconstruct and validate calendar, episode, covariate, and month-level inputs.
Rscript Ethiopia_final_html_analysis.R --run=prepare --project-root=work/ethiopia --ir-file="$DHS_IR_FILE"

# List available numerical modules.
Rscript Ethiopia_final_html_analysis.R --list
```

Substitute the Nigeria or DRC script and a separate working directory for those
countries. Ethiopia and DRC accept Stata IR files; Nigeria also accepts its
lossless IR RDS copy. Optional `--expected-ir-sha256` enforces a known checksum.
Use a fresh `--project-root` when rebuilding. Subsequent modules run through
`--run=MODULE_NAME` or an ordered comma-separated list, with their dependencies
available as documented in the country code.

Generated files stay under the supplied project root: `Data/` for staged
inputs, `Data/Derived/` for prepared records, and `output/` for numerical
results and logs. `output/validation/` records input checksums, software versions,
derived-file checksums, and preparation summaries. Keep generated microdata,
credentials, and machine-specific working files outside published contents.

## Reproducibility status

Parameterized IR import and calendar/episode preparation have been tested in
fresh working directories for all three countries. Prepared legacy inputs were
compared with those used by the existing analyses. Published-table checks and
known discrepancies are documented by country.

The numerical modules have separate dependencies. `--run=prepare` does not fit
every model or regenerate the complete HTML/PPTX. A single-command rebuild of
the formatted reports, a pinned software environment, and authenticated API
acquisition remain future repository work. Current input preparation uses
supplied IR files and requires no API connection.
