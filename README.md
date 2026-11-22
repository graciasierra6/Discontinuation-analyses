# Contraceptive discontinuation analyses

DHS contraceptive-calendar analyses for Ethiopia (2024–25), Nigeria (2024), and DRC (2023–24). The repository covers method initiation, discontinuation and its reasons, timing, switching/restarting, subnational comparisons, and potential contributions to mCPR.

## Repository structure

- `build_reports.R`: national report build entry point.
- `survey_design.R`: shared survey-design estimators and inherited-record checks.
- `tests/test_survey_design.R`: portable design and estimator-equivalence tests.
- `tests/check_planning_outputs.R`: planning stocks, method/cause totals, replicate bounds and scenario arithmetic.
- `<Country>_analysis/<Country>_final_html_analysis.R`: each country's analytical and reporting source.
- `report_tools.py`: shared rendering and read-only report comparisons.
- `geography.json`: pinned public map geometry and attribution; no survey records.
- `Nigeria_analysis/Kano_Kaduna_Lagos/`: state-specific R entry points.
- `discontinuation_extensions/run_analysis.R`: independent extensions and interactive maps.
- `renv.lock` and `requirements.txt`: dependency versions.
- [Data access](docs/data-access.md): parameterized IR inputs and R download instructions.
- [Methods and reproduction](docs/methods.md): calendar construction, cohorts, models, planning calculations and report checks.

Source resources are expanded into private runtime directories during execution. Survey microdata, fitted-model caches, credentials and individual-level intermediate records are not repository inputs or contents.

## Data and dependencies

Obtain authorized women's Individual Recode files through [The DHS Program](https://dhsprogram.com/data/). Keep IR files outside the repository and supply their locations through parameters. The public DHS API provides indicators and a dataset catalogue; downloading IR microdata requires approved account access. The data-access guide documents both routes and their verification limits.

Restore the R packages and install the Python dependencies:

```sh
Rscript -e 'renv::restore(lockfile="renv.lock", prompt=FALSE)'
python3 -m pip install -r requirements.txt
```

Each national, state and extensions R entry point starts with its survey year,
IR release, calendar variables, episode-construction description and survey-design
fields. Its `setup_analysis_packages()` block installs missing R packages from
CRAN with `install.packages()` and attaches the declared packages with `library()`
before analysis. It does not upgrade packages that are already available.
For the validated versions, restore `renv.lock` **before** running an analysis;
a missing-package installation alone does not reproduce that locked environment.
Help/source checks do not initialize the full analytical package stack. Package
installation failures stop execution; any required operating-system libraries
must be installed separately. Python dependencies use `requirements.txt` above.

DRC's display-only slide-preview gallery also requires LibreOffice (`soffice`).

## National reports

From the repository root:

```sh
Rscript tests/test_survey_design.R
Rscript build_reports.R --check --python=python3
Rscript build_reports.R --country=Nigeria --ir-file="$DHS_IR_FILE" \
  --output-dir="$DHS_BUILD_DIR/nigeria" --python=python3 --cores=4
```

Use `Ethiopia` or `DRC` for the other countries. The output directory must be new and outside the repository. The build reconstructs calendars and episodes from the IR, computes weighted estimates, fits models and 500 joint planning survey replicates, and renders a new HTML. Existing HTML and cached fitted results are not used to calculate estimates. Full bootstrap runs can be lengthy.

Approved HTML and PPTX files are read-only references. Use `--reference-policy=report` to produce a candidate and record differences for review; the default `strict` policy requires agreement. Comparisons run after estimation and require a matching reference version; differences stop validation without replacing approved files. `--reference-dir` supplies an alternative directory with the same country-folder layout. DRC uses the reviewed PPTX only for its displayed slide-preview gallery. Successful reports are written under the private output directory.

`--check` verifies source syntax without fitting models. `--extract-source="$SOURCE_INSPECTION_DIR"` expands the source into an empty private directory for inspection. Complete builds additionally compare native slide tables, HTML table cells, report text/navigation and embedded figures. Fonts and rendering-library differences can require review.

## Extensions, maps and states

```sh
Rscript discontinuation_extensions/run_analysis.R \
  --ethiopia-ir="$ETHIOPIA_IR_FILE" --nigeria-ir="$NIGERIA_IR_FILE" \
  --drc-ir="$DRC_IR_FILE" --output-dir="$DHS_BUILD_DIR/extensions" --python=python3
```

The extensions HTML includes reason-specific timing, alluvials, reason-specific subsequent use and modern destinations. Its “Potential additions” section presents first return, the alluvial and continuation after return for each country. `Return_and_continuation_same_cohort_preview.html` supplies paired curves and the one-ending-per-woman appendix. First return is measured from the actionable ending; continuation starts a new clock at the first modern return and allows direct modern-to-modern switching. Both use the same complete-follow-up ending cohorts as the alluvials (Ethiopia 1,799; Nigeria 1,607; DRC 797). Later interruptions include all reasons. Full-frame survey bootstrap inference keeps each woman's histories together.

All three IRs and a new private output directory are required. `--target=extensions` or `--target=maps` selects one report; the default produces both. This module reconstructs its own records and uses 1,999 full-frame survey-bootstrap replicates.

The three state entry points export numerical results and figures. The extracted `tools/refresh_state_report_tables.py` refreshes the 60 analytical tables in the existing combined state HTML from those exports; presentation-table synchronization uses the same maintenance utility as the national reports. State scripts do not independently author the complete combined HTML layout or PowerPoint. See [state reproduction](docs/methods.md#state-tables) for commands. The national command covers the three national reports.

## Analytical definitions

Continuing-modern-method discontinuation excludes EC as an original method. Potentially actionable causes comprise method failure, wanting a more effective method, bleeding changes, other side effects/health, and access/cost/convenience. Partner/spousal disapproval is separate. EC remains part of all-women current mCPR and subsequent modern use.

All estimates inherit the DHS woman weight (`v005 / 1,000,000`), PSU (`v021`) and stratum (`v022`). The [survey-design implementation](docs/survey-design.md) covers survey percentages, binary and multinomial regression, AFT fits and full-frame PSU inference for life tables and planning. Transformations preserve woman linkage and the original design identifiers. Main planning counts every actionable ending as a lost modern user. Switching/restarting sensitivities account for modern use at the common next-12-month endpoint. Historical and AFT probabilities condition on method and elapsed use.

National planning separates permanent current users from the reversible-method risk cohort. Permanent users remain in mCPR and receive no modeled stopping probability or retention gain. Nigeria and DRC append overall checks with male condoms and LAM modeled separately; Ethiopia retains the pooled reversible group because of limited sample support. The additional checks show point estimates. The modeled-switching sensitivity treats subsequent permanent-method use as an absorbing modern-use destination. Sparse permanent uptake is pooled; it does not support method-by-cause uptake models.

Outcome years are 2026 for Ethiopia and 2025 for Nigeria/DRC. [UN WPP population inputs](https://population.un.org/wpp/), growth assumptions and selected AFT families are held fixed in the intervals. mCPR contributions are conditional scenarios rather than established intervention effects.

## Validation and limitations

The validated survey releases produce these analytical counts:

| Country | Calendar runs | Published-table eligible episodes | Regional model cohort |
|---|---:|---:|---:|
| Ethiopia | 89,220 | 9,068 | 8,611 |
| Nigeria | 163,203 | 11,210 | 8,341 |
| DRC | 132,217 | 8,934 | 4,146 |

The national permanent-method update was rebuilt from the authorized IR inputs, including planning point fits and all 500 joint replicates per country. Repeat rendering reproduced all three updated national HTMLs byte-for-byte: 515 tables and 171 embedded figures in total. All 168 editable PowerPoint tables match the updated HTMLs. The extensions and maps were validated in the preceding survey-design update; they are unchanged by this national planning correction. These checks apply to the supplied survey releases and documented dependencies; source checks alone do not certify a complete rebuild or future forecast accuracy. Native-table comparison does not independently verify text embedded in slide images.

The state run used 999 descriptive and 999 joint planning replicates. All 60 exported state tables reconcile exactly with the refreshed combined HTML, and its 45 editable presentation tables match. The state reporting limitation described above remains: those entry points export numerical content and figures, rather than independently authoring the complete combined document layout.

Published DHS checks match all 66 Ethiopian and 110 Nigerian tested rate cells. DRC matches 104 of 110 tested rate cells, with six 0.1-pp differences documented. Sparse DRC IUD original-ending/transition estimates use Other-modern curves. DRC's modeled-transition sensitivity overpredicted held-out month-12 modern use by 5.39 pp and remains a sensitivity rather than a primary estimate.

Sparse samples, recall, historical transportability and fixed model assumptions limit interpretation. Country-specific exploratory diagnostics retain their stated specifications and are not all identical estimators. Detailed runtime validation files remain in private build directories.
