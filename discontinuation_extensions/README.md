# Discontinuation and switching extensions

Independent three-country module for Ethiopia DHS 2024–25, Nigeria DHS 2024,
and DRC DHS 2023–24. It rebuilds the two separate reports:

- `output/Discontinuation_and_switching_extensions.html`
- `output/Modern_method_discontinuation_maps.html`

This module lives in the repository subfolder `discontinuation_extensions/`.
It does not read, modify, or require the national presentations or their larger
analysis projects. It does not rebuild those presentations or the mCPR planning
tables. The supplied HTMLs are examples of the completed rebuild, not inputs.

## Run

From the repository root, first run `cd discontinuation_extensions`, then use
the commands below. This module has its own entry point and dependencies.

Use R 4.4 or newer and Python 3.9 or newer. Python uses only its standard
library. Install the R packages once:

```r
install.packages(c("haven", "jsonlite", "survival", "digest", "svglite"),
                 repos = "https://cloud.r-project.org")
```

Provide the authorized, unaltered woman-level IR files as command-line
parameters. The following are project-relative example locations, not bundled
data files:

```sh
Rscript run_analysis.R \
  --ethiopia-ir=data/ethiopia.dta \
  --nigeria-ir=data/nigeria.dta \
  --drc-ir=data/drc.dta \
  --output-dir=output
```

Alternatively set `ETHIOPIA_IR_FILE`, `NIGERIA_IR_FILE`, and `DRC_IR_FILE` at
runtime, then run `Rscript run_analysis.R --output-dir=output`. Inputs may be
original Stata `.dta` files or lossless labelled IR `.rds` copies. Country,
calendar alignment, women, survey frame, and required variables are checked.
The pipeline deliberately stops for different survey releases. It does not
download restricted DHS microdata or infer a private data location.

Optional arguments: `--target=extensions`, `--target=maps`, and
`--python=python3`. The default target is `all`. All three country inputs are
required because the reports contain all three countries. Source files are
located relative to the entry script, so the folder can be moved and invoked
from another working directory. Filesystem paths are resolved only at runtime.

R computes the estimates and renders the interruption bars. The bundled Python
modules draw the remaining SVG figures and assemble the embedded HTML. No
previous aggregate files are required. Run time depends on the machine; each
country includes 1,999 survey-bootstrap replicates across multiple analyses.

## Obtaining the input data

The tested entry point reads authorized woman-level IR files; it does not
retrieve individual calendar records through the public DHS indicator API.
That API provides aggregate indicators and a dataset catalogue, which are not
sufficient to reconstruct individual episodes and follow-up histories.
See the [DHS API description](https://api.dhsprogram.com/).

To reproduce the reports with data obtained directly from DHS:

1. Sign in to a DHS account approved for the relevant research project and
   countries. Follow the [DHS access instructions](https://dhsprogram.com/data/Access-Instructions.cfm).
2. Download the Individual Women's Recode (IR), preferably Stata format, for
   Ethiopia 2024–25, Nigeria 2024 and DRC 2023–24. The tested releases are
   ETIR8A, NGIR8B and CDIR81, respectively. Extract the original `.dta` files
   without changing their calendar strings or value labels.
3. Supply those files to `run_analysis.R` through its three input parameters or
   environment variables. The code rebuilds the calendar and episode data,
   estimates the results and validates them against the checked report baseline.
   A newer or altered release must be reviewed if those validation checks fail.

**Authenticated download is possible, but is not enabled in this release.**
The `rdhs` package provides
[`get_datasets()`](https://docs.ropensci.org/rdhs/reference/get_datasets.html)
to download files available to an approved DHS account. It requires account
credentials and an authorized project; this is distinct from public aggregate
API access. That authenticated connection has not been tested for this module,
so the documented and tested route remains caller-supplied IR files. A future
connector should download the original archive, retain labels and calendar
spacing, and pass the extracted file through the same validation pipeline.
Credentials, authentication cookies, private configuration and restricted files
must remain outside the repository.

**Reproducibility boundary:** the complete analysis and both HTML reports have
been rebuilt from the supplied IR inputs. Fresh authenticated downloads from DHS
have not been verified. Internet access to microdata is not implied by the saved
validation results.

## Calculations

1. Read the full IR file without filtering women or changing calendar strings.
   Reverse valid calendar positions to chronological order using `v017`–`v019`.
   Each uninterrupted run of one calendar character becomes an event record.
   Pregnancy/birth/termination, no use, and traditional use remain available for
   follow-up. The last nonblank reason inside a method run is retained under
   the established report-matching reason-recovery convention.
2. Reconstruct known-start use episodes overlapping months 3–62 before interview.
   Retain eligible delayed entry at its elapsed duration; censor exposure at the
   interview-minus-three-month boundary. Preserve the established boundary
   reason convention. First-year life tables use `entry < month` and
   `exposure >= month` at durations 1–12.
3. Estimate reason-specific cumulative incidence with all other original-method
   endings as competing events. Independently compare the life tables with
   weighted Aalen–Johansen calculations. All-reason and actionable probabilities
   and observed-ending reason shares have distinct, labelled denominators.
4. Follow actionable endings at **any original use duration** through months
   1–12 after the ending. Require all twelve months before the excluded final
   three calendar months. The alluvials show months 1, 3, 6 and 12. These are
   ending-level histories, and a woman may contribute several endings.
5. Compute outcomes by reason, the seven-part endpoint/interruption summary,
   and the first modern destination recorded at any point during follow-up.
   First destination is not necessarily the method used at month 12. The new
   interruption groups count **total months outside modern use**, including
   traditional and pregnancy-related records; they need not be consecutive.
6. Build the geography views from pooled episodes, not averages of area rates:
   Ethiopia's 14 survey regions/administrations; Nigeria's six zones with
   optional states/FCT; DRC's six geographic groups with optional 26 provinces.
   Interview geography can differ from where the historical episode occurred.

Original modern-method episodes exclude EC. Subsequent EC is classified as
modern use in follow-up. The five potentially actionable categories are:

| Category | Native reason codes |
|---|---|
| Method failure | 1 |
| Wanted a more effective method | 7 |
| Bleeding changes | 15 |
| Other side effects/health | 4, 5 |
| Access/cost/convenience | 6, 8, 10 |

Partner/spousal disapproval, code 3, remains separate and is never included
in those categories. Its national method-specific and age/parity/residence
analyses are preserved in the extensions report. Age and parity are measured
at episode initiation; residence is measured at interview.

Point estimates use `v005 / 1,000,000`. Intervals use full-frame stratified
Rao–Wu n−1 PSU resampling with `v021` and `v022`, including PSUs without eligible
episodes. All records from the same woman remain in the same resampled PSU.
Sparse life-table risk sets use epsilon-smoothed multipliers with corrected
replicate deviations. The follow-up analyses use unsmoothed PSU resampling;
unsupported sparse-domain intervals are withheld. Zero observed events do not
establish zero population risk. Sample flags are screening rules, not formal
power tests. The code does not fit causal intervention models.

## Files and validation

- `run_analysis.R`: the single entry point.
- `src/R/`: IR/calendar preparation and statistical calculations.
- `src/python/`: report renderers and numerical/HTML validation.
- `assets/boundaries/`: pinned, simplified public map geometry and attribution.
- `validation/expected_results.json`: checked aggregate reference values used
  **only to test** newly computed results, never to supply estimates.
- `output/validation.json`: comparison results and structural checks.
- `output/software_versions.csv`: runtime package versions without machine paths.

The rebuild checks all stored numerical fields against the checked report
baseline, including probabilities, shares, counts and intervals. It also checks
reason sums, geographic joins, follow-up margins, embedded images and section
links. This tests reproduction of the current reports; it is not a new claim
that every derived grouping corresponds to a published DHS table. Browser
interaction and desktop/mobile layout were checked separately for this release.
Font appearance may vary across operating systems. A failed validation must be
resolved before treating a fresh report as equivalent to this release.

Woman-level inputs and intermediate calendar/episode files are kept in an
automatically cleaned temporary working area. The upload folder contains no
restricted microdata, individual histories, personal paths or input-location
configuration. Do not commit authorized IR files or private configuration.

## Public references

- [DHS contraceptive calendar tutorial](https://www.dhsprogram.com/data/calendar-tutorial/upload/DHS-Contraceptive-Calendar-Tutorial.pdf)
- [DHS Guide to Statistics](https://www.dhsprogram.com/pubs/pdf/DHSG1/Guide_to_DHS_Statistics_DHS-8.pdf)
- [DHS discontinuation indicator code](https://github.com/DHSProgram/DHS-Indicators-Stata/blob/master/Chap07_FP/FP_DISCONT.do)
- Public boundaries and their licences: `assets/boundaries/provenance.json`.

The bundled map snapshots use OCHA/HDX COD-AB boundaries, projected to a local
equal-area coordinate system and simplified for display. They retain only
survey-matched areas; Ethiopia's 14-region view is not a claim that the current
public boundary dataset contains only 14 units. Nigeria's zone geometry is
formed by joining states through the IR's zone labels. DRC's six broad groups
are geographic groupings, not current administrative provinces. Boundary names
and designations do not imply official endorsement or acceptance by the
United Nations.
