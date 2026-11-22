# Methods and reproduction

This guide describes the national analyses and the independent extensions.
See [data access](data-access.md) for authorized inputs and
[survey design](survey-design.md) for estimators, variance calculations and
country-specific sampling checks. The root README contains the build commands.

## From the IR file to analytical records

1. Read the labelled women's Individual Recode file supplied by the caller.
   Check the survey release, woman identifiers, required variables, calendar
   lengths and date alignment. Preserve fixed-width calendar strings and labels.
2. Align the method/status calendar (`vcal_1`) and reason calendar (`vcal_2`)
   with century-month dates using the calendar/interview fields. Work in
   chronological order. A consecutive run of one method becomes a method-use
   episode; pregnancy-related and no-method records remain distinguishable.
3. Link each run, episode and person-month to its woman. Inherit her original
   weight, PSU and stratum. The original full IR supplies the survey frame even
   for domains containing only some women or episodes.
4. Construct each analysis cohort separately. Published-table life tables use
   the DHS 3–62-month observation window, appropriate delayed entry and right
   censoring. Country-specific boundary/reason alignment checks are retained.
   Models requiring a known method start exclude left-censored starts where
   specified. Post-ending pathways require their stated follow-up coverage.
5. Validate intermediate counts and national controls before fitting downstream
   models. Cohort counts can differ because the published-table, regression,
   current-user planning and complete-follow-up questions require different
   records. Those denominators must not be treated as interchangeable.

## Definitions and denominators

Original-method discontinuation analyses focus on modern methods excluding EC,
unless a section explicitly reproduces an all-method DHS benchmark. EC remains
modern for current all-women mCPR and subsequent-use classifications.

Potentially actionable reasons are method failure, wanting a more effective
method, changes in menstrual bleeding, other side effects/health, and
access/cost/convenience. Partner/spousal disapproval is separate and is not
included in actionable risk or retention calculations.

| Quantity | Meaning |
|---|---|
| Cumulative discontinuation probability | Probability of an original-method ending by the stated duration, allowing for censoring and competing ending reasons |
| Reason share | Weighted percentage of the specified observed endings attributed to a reason; shares within a complete grouping sum to 100% |
| Current mCPR | Weighted percentage of all women aged 15–49 currently using a modern method, regardless of marital status |
| Post-ending endpoint share | Weighted percentage of eligible actionable endings followed by the stated status at a specified month after stopping |

Reason shares are not reason-specific discontinuation probabilities. An
original method can end while modern use continues through a direct switch.

## Life tables, regression and regional comparisons

Weighted monthly risk sets produce all-cause survival and cause-specific
cumulative incidence. Other ending reasons remain competing events. Timing
curves show accumulation since method initiation, not the distribution of
durations among discontinuers alone.

DHS benchmark tables retain the small-sample display convention: suppress
rates below 125 unweighted first-month exposures and use parentheses for
125–249. The [DHS calendar tutorial](https://www.dhsprogram.com/data/calendar-tutorial/upload/DHS-Contraceptive-Calendar-Tutorial.pdf)
defines this denominator. This differs from the separately stated warning
rules in exploratory regional tables.

Episode-month regressions estimate the stated monthly event probabilities.
Regional comparisons distinguish observed rates, a common method mix, and a
common method/covariate composition. Standardized predictions average over the
specified reference records. Regional contrasts use joint design covariance or
stratified PSU refits, with the stated multiple-comparison correction. Model
formulas and sample restrictions remain country/analysis specific.

## Current-user planning: the next twelve months

The planning cohort consists of current non-EC modern users at the observed
baseline. Each woman's method and elapsed duration determine her estimated
next-twelve-month actionable ending probability. Current prevalence and method
composition come from the IR; external UN WPP women-aged-15–49 populations
convert prevalence into user counts. Normalized survey weights alone do not
provide national population totals.

The report distinguishes three probability approaches:

- **First-year:** apply first-year method-specific probabilities. This does not
  account for how long a current user has already used her method.
- **Historical duration-aware:** use historical method-use landmarks with a
  similar elapsed duration and observe the following twelve months. Duration
  pooling, sparse-cell fallbacks and long-duration proxies are documented in
  the relevant outputs.
- **AFT duration-aware:** fit cause-specific parametric survival models, combine
  their hazards with competing endings, and predict actionable discontinuation
  over the next twelve months conditional on current method and elapsed use.
  The selected distribution family is held fixed during uncertainty estimation.

Main tables count each actionable original-method ending as a lost modern user.
Sensitivity tables instead estimate endings that leave the woman outside any
modern method at the common twelve-month endpoint. They include historical
subsequent-use patterns, an AFT/historical hybrid, and the labelled modeled
monthly-transition sensitivity. Return followed by another stop before the
endpoint does not count as endpoint modern use. These are conditional
calculations, not measured intervention effects.

For a fixed baseline cohort, estimated retained users are the population-scaled
sum of current-user weights times the relevant probabilities. The mCPR
contribution is:

`additional percentage points = 100 × additional retained users / outcome-year WRA`.

For method `m`, baseline users are `baseline WRA × weighted current prevalence
of m`. Usual-condition outcome-year users are `usual-condition mCPR / 100 ×
outcome-year WRA`. Add the estimated retained users to that numerator, or
equivalently add their percentage-point contribution to usual-condition mCPR.
Use the same outcome-year population in both comparisons. Mutually exclusive
method/cause contributions add to the total; their confidence-limit endpoints
do not add.

| Country | Baseline convention | Outcome year |
|---|---:|---:|
| Ethiopia | 2024–25 survey treated as 2025 | 2026 |
| Nigeria | 2024 | 2025 |
| DRC | 2023–24 survey treated as 2024 | 2025 |

Recent DHS, longer-term DHS and FPET trend scenarios set the usual-condition
mCPR comparison. They use the documented annual percentage-point changes and
source periods. Changing that trend changes usual-condition and with-retention
mCPR; it does not change a retention contribution when the baseline cohort and
outcome-year population are held fixed. Population and growth assumptions are
fixed inputs, not estimated from contraceptive-calendar episode counts.

## Extensions: what follows an actionable ending?

The independent extensions reconstruct their own records from all three IRs.
Complete-follow-up actionable modern-method endings form the alluvial cohort.
Snapshots at months 1, 3, 6 and 12 describe status at those times; they do not
imply uninterrupted use between snapshots. First-return curves measure time
from ending to the first subsequent modern use. Continuation-after-return
curves start a new clock at that return and allow direct modern-to-modern
switching. The one-ending-per-woman appendix changes the contribution rule;
the main episode analysis retains all eligible endings with PSU-based inference.

These post-ending clocks differ from the current-user planning clock. Someone
stopping nine months after a planning baseline has three months remaining
before its endpoint, rather than a further twelve months after stopping.

## Rebuilds, uncertainty and review

National builds reconstruct records and refit models and 500 joint survey
replicates in a new private directory. The extensions use 1,999 full-frame
stratified PSU replicates. Records from a woman remain together within their
PSU. Survey intervals do not include uncertainty in population projections,
secular growth, selected AFT families or hypothetical intervention effectiveness.

The three standalone state scripts retain the full Nigeria survey frame and
export each state's tables and figures. State planning counts are normalized
per 100,000 baseline WRA and use the stated national WRA-growth ratio as a state
assumption. They do not independently rebuild the complete combined state HTML
or PowerPoint. That reporting limitation is distinct from the national builds
and must not be represented as a verified combined-report rebuild.

Source/unit checks and complete numerical rebuilds are separate checks.
Reference HTMLs and presentations are not analytical inputs. Comparisons run
after estimation; a disagreement is recorded rather than silently replacing
approved values. A layout-only manifest restores report navigation and heading
anchors without supplying estimates, tables or figures. DRC's slide gallery
renders the reviewed PPTX for display only. The build does not recreate the
PowerPoint presentation or certify text embedded in slide images.

During review, use `--reference-policy=report`; the default `strict` policy
requires agreement with the reviewed reference. Rendering/font differences and
intentional numerical corrections require review before updating references.
Keep private build trees, restricted data, credentials and runtime logs out of
the repository. Consult the generated private validation results for the exact
checks completed by a particular build; a successful source check alone is not
evidence that every report has rebuilt.

### Updating presentation-table numbers

For a reviewed numerical correction, the extracted
`tools/sync_presentation_tables.py` can update existing editable table cells
from the fresh HTML while preserving the presentation's layout and styling.
The prior HTML identifies table correspondence and display units; it supplies
no new estimates. Unmatched or structurally changed tables stop the update
rather than guessing. This is an explicit maintenance step, separate from a
normal read-only report build:

```sh
Rscript build_reports.R --extract-source="$SOURCE_INSPECTION_DIR" --python=python3
python3 "$SOURCE_INSPECTION_DIR/tools/sync_presentation_tables.py" \
  --reference-html "$PRIOR_HTML" --html "$FRESH_HTML" \
  --pptx "$PRIOR_PPTX" --output "$REVIEWED_PPTX" --plan "$PRIVATE_CHANGE_PLAN"
python3 "$SOURCE_INSPECTION_DIR/tools/check_html_pptx.py" \
  --html "$FRESH_HTML" --pptx "$REVIEWED_PPTX" --output "$PRIVATE_COMPARISON"
```

Review the updated slides visually, check that unrelated package parts and
formatting remain unchanged, and verify notes and metadata before replacing a
reviewed artifact. Numerical table matching alone does not validate every
chart, title or embedded slide image.

### State tables

Run the three state scripts with the same new aggregate-cache directory. The
first script calculates all three states from the full authorized IR; the
remaining scripts reuse those same-build results, keyed to the source code,
input checksum and replicate settings, to export their state-specific tables.
No prior fitted models are required.

```sh
for state in Kano Kaduna Lagos; do
  Rscript "Nigeria_analysis/Kano_Kaduna_Lagos/${state}_discontinuation_analysis.R" \
    --ir-file="$NIGERIA_IR_FILE" \
    --output-dir="$DHS_BUILD_DIR/states/$state" \
    --cache-dir="$DHS_BUILD_DIR/state-cache" --cores=4
done
python3 "$SOURCE_INSPECTION_DIR/tools/refresh_state_report_tables.py" \
  --source=Nigeria_analysis/Kano_Kaduna_Lagos/Kano_Kaduna_Lagos_discontinuation_analysis.html \
  --analysis-dir="$DHS_BUILD_DIR/states" --output="$FRESH_STATE_HTML"
```

Each script exports 20 tables. Its optional `--reference-html` parameter checks
those cells exactly against the combined HTML after refresh. The overview mCPR
table also comes from the fresh IR-derived state results. The refresh preserves
the existing report layout and graphics; it is not an independent reconstruction
of that complete combined document. State SVG figures are separate fresh exports.
