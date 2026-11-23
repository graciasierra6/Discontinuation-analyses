# Contraceptive discontinuation analyses

Reproduce DHS contraceptive-calendar analyses for **Ethiopia, Nigeria and DRC** from authorized women's Individual Recode (IR) files. The analyses cover method starts, discontinuation, reasons, timing, switching/restarting, regional comparisons and potential contributions to mCPR.

**Choose either workflow. Both national workflows run the same analysis and report builder.**

| How you prefer to work | What to open |
|---|---|
| **Option 1: Terminal or coding assistant** | [National builder](build_reports.R) · [Windows instructions](#windows--powershell) · [macOS instructions](#macos--terminal-using-zsh) |
| **Option 2: RStudio** | [Ethiopia script](Ethiopia_analysis/Ethiopia_final_html_analysis.R) · [Nigeria script](Nigeria_analysis/Nigeria_final_html_analysis.R) · [DRC script](DRC_analysis/DRC_final_html_analysis.R) |

No microdata are included. Existing HTMLs and presentations are read-only references. A run writes new results to a separate private folder; it does not replace the approved files.

[Reports and scripts](#reports-and-scripts) · [First-time setup](#before-your-first-run) · [Terminal workflow](#option-1--terminal-or-coding-assistant) · [RStudio workflow](#option-2--rstudio-open-source-select-the-ir) · [Results](#where-are-my-results) · [Troubleshooting](#troubleshooting)

## Reports and scripts

Use the script links to find the correct entry point. For a full HTML rebuild, **download the complete repository first**, then open the script from that extracted folder. The saved HTML links below identify the reviewed reports; GitHub may show their source, so open the downloaded HTML in your browser to view it. Presentations are reviewed references used for comparison, not newly generated decks.

| Report | Script to open in RStudio | Saved HTML | Presentation |
|---|---|---|---|
| Ethiopia national analysis | [Ethiopia R script](Ethiopia_analysis/Ethiopia_final_html_analysis.R) | [Ethiopia HTML](Ethiopia_analysis/Ethiopia_discontinuation_analysis.html) | [Ethiopia PPTX](Ethiopia_analysis/ethiopia_presentation.pptx) |
| Nigeria national analysis | [Nigeria R script](Nigeria_analysis/Nigeria_final_html_analysis.R) | [Nigeria HTML](Nigeria_analysis/Nigeria_discontinuation_analysis.html) | [Nigeria PPTX](Nigeria_analysis/Nigeria_discontinuation.pptx) |
| DRC national analysis | [DRC R script](DRC_analysis/DRC_final_html_analysis.R) | [DRC HTML](DRC_analysis/DRC_discontinuation_analysis.html) | [DRC PPTX](DRC_analysis/DRC_discontinuation.pptx) |
| Timing, alluvials and switching extensions | [Extensions R script](discontinuation_extensions/run_analysis.R) | [Extensions HTML](discontinuation_extensions/output/Discontinuation_and_switching_extensions.html) | — |
| Interactive discontinuation maps | [Extensions R script](discontinuation_extensions/run_analysis.R) | [Maps HTML](discontinuation_extensions/output/Modern_method_discontinuation_maps.html) | — |
| Return and continuation curves | [Extensions R script](discontinuation_extensions/run_analysis.R) | [Return/continuation HTML](discontinuation_extensions/output/Return_and_continuation_same_cohort_preview.html) | — |
| Optional state numerical results | [Kano](Nigeria_analysis/Kano_Kaduna_Lagos/Kano_discontinuation_analysis.R) · [Kaduna](Nigeria_analysis/Kano_Kaduna_Lagos/Kaduna_discontinuation_analysis.R) · [Lagos](Nigeria_analysis/Kano_Kaduna_Lagos/Lagos_discontinuation_analysis.R) | [Combined state reference](Nigeria_analysis/Kano_Kaduna_Lagos/Kano_Kaduna_Lagos_discontinuation_analysis.html) | [Combined state PPTX](Nigeria_analysis/Kano_Kaduna_Lagos/Kano_Kaduna_Lagos_discontinuation.pptx) |

The extensions entry point produces all three extensions/maps reports and asks for all three countries' IR files. The optional state scripts generate individual numerical results and simple galleries; they do not independently reconstruct the saved combined state HTML/PPTX layout. See [optional analyses](#optional-extensions-maps-and-state-analyses).

## Before your first run

1. Install a current **R** and, for the graphical workflow, **RStudio Desktop**. The checked analysis environment uses R 4.6.0; package versions are recorded in `renv.lock`.
2. On the GitHub repository page, click **Code → Download ZIP**. Extract the complete ZIP (**Extract All** on Windows; double-click on macOS) and keep its folders together. You do not need to install or use Git.
3. Obtain the authorized DHS women's IR download and extract it separately. Keep the data outside the repository. Select the original labelled **`.dta` file**, not the ZIP or an HTML report.
4. For **DRC only**, install **LibreOffice** once. Its command-line renderer reproduces the report's presentation-preview gallery; it is not used to estimate discontinuation. The workflow checks for it before the long analytical run.
5. Keep internet access available for first-time dependency installation. R packages, Python and the pinned Python rendering packages are prepared automatically. Later runs can reuse the installed dependencies.

| Country | Survey | IR file to select | Planning baseline → outcome |
|---|---|---|---|
| Ethiopia | DHS 2024–25 | `ETIR8AFL.dta` | 2025 → 2026 |
| Nigeria | DHS 2024 | `NGIR8BFL.dta` | 2024 → 2025 |
| DRC | DHS 2023–24 | `CDIR81FL.dta` | 2024 → 2025 |

The scripts check the validated release and calendar fields. They stop rather than silently use a different release. [Data access instructions](docs/data-access.md) explain DHS authorization, optional R download tools and why the public aggregate API cannot replace the individual calendars.

## Option 1 — Terminal or coding assistant

Choose this route if you use terminal commands, directly or through a coding assistant with terminal access. Use [build_reports.R](build_reports.R); the same R analysis runs in either case. No assistant-specific integration is required.

Open the complete extracted repository, then open a terminal **in its root**, where `README.md` and `build_reports.R` live. `Rscript --version` must work in that terminal; on Windows this may require adding your R installation's executable directory to PATH. The RStudio workflow locates its own R executable and does not require that PATH setup.

The commands below ask for your own locations at runtime. Paste the locations **without surrounding quotes**. Choose a new output folder outside the repository.

### Windows — PowerShell

```powershell
$ir = Read-Host "Full location of the Nigeria IR .dta file"
$out = Read-Host "Full location for a NEW private results folder"
Rscript .\build_reports.R --country=Nigeria "--ir-file=$ir" "--output-dir=$out"
```

### macOS — Terminal using zsh

```zsh
read -r "ir?Full location of the Nigeria IR .dta file: "
read -r "out?Full location for a NEW private results folder: "
Rscript build_reports.R --country=Nigeria "--ir-file=$ir" "--output-dir=$out"
```

Replace `Nigeria` with `Ethiopia` or `DRC` and supply that country's IR. Python dependencies are set up automatically through [reticulate’s managed environments](https://rstudio.github.io/reticulate/reference/py_require.html). Output files have the same structure as the RStudio workflow.

Useful options:

```sh
Rscript build_reports.R --help
Rscript build_reports.R --check
```

`--check` parses the analytical/reporting source without fitting models. It is a setup check, not a complete numerical rebuild. Add `--cores=4` for more workers on macOS. Windows runs fork-based stages serially while retaining the replicate seeds and survey design. Advanced users can supply an existing prepared interpreter with `--python=EXECUTABLE`; it must match `requirements.txt`.

The standalone numerical route remains available. Supply `DHS_IR_FILE` and `DHS_ANALYSIS_OUTPUT` as runtime environment variables for the selected country's IR and a new private output folder:

```sh
Rscript Ethiopia_analysis/Ethiopia_final_html_analysis.R --run=analysis --ir-file="$DHS_IR_FILE" --output-dir="$DHS_ANALYSIS_OUTPUT" --analysis-scope=all --replicates=500 --cores=1
```

That last command produces R/CSV results without formatting the national HTML. It is separate from clicking Source, which builds the full national report. See [one-script numerical analysis](#one-script-numerical-analysis-without-html) if you only downloaded a country R file.

## Option 2 — RStudio: open, Source, select the IR

**You do not need to type a command or edit a personal file path.**

Use this route for the full report if you prefer opening a script and clicking Source. Keep the complete repository together; downloading just the R file is not sufficient to assemble the HTML.

1. In RStudio, choose **File → Open File** and open the script for your country:

   | Country | Script inside the extracted repository |
   |---|---|
   | Ethiopia | [Ethiopia_analysis/Ethiopia_final_html_analysis.R](Ethiopia_analysis/Ethiopia_final_html_analysis.R) |
   | Nigeria | [Nigeria_analysis/Nigeria_final_html_analysis.R](Nigeria_analysis/Nigeria_final_html_analysis.R) |
   | DRC | [DRC_analysis/DRC_final_html_analysis.R](DRC_analysis/DRC_final_html_analysis.R) |

2. Click **Source** at the top right of the script editor. Use Source for the entire file, rather than running one selected line.
3. The package block near the top automatically installs missing R packages into a writable R library and loads the declared libraries. A private user library is created if the existing libraries are not writable.
4. A file browser asks you to select the country's extracted **IR `.dta`** file.
5. The workflow prepares the Python report renderer, reconstructs calendars, fits the models and survey bootstrap replicates, then builds and checks the HTML.
6. Leave RStudio running. A full build can take **several hours**. The Console reports its current stage; it is not necessary to click Source again.
7. After a successful build, the HTML opens in your browser. In RStudio's Environment pane:
   - `report_results` identifies the new HTML and output folder.
   - `analysis_results` contains the numerical tables. For example, enter `analysis_results$planning_overall` or `analysis_results$table_index` in the Console.

### Where are my results?

By default, a new `discontinuation_results` folder is created **alongside the extracted repository folder**. Each run has its own country and timestamp:

```text
Discontinuation-analyses/             # extracted repository; left unchanged
  ...
discontinuation_results/
  ethiopia_<run timestamp>/
    output/
      Ethiopia_discontinuation_analysis.html
      validation/                    # report/data/model checks
      logs/                          # progress and failure details
    results/
      analysis_results.rds           # numerical results for R
      planning_overall.csv
      planning_by_method.csv
      planning_by_cause.csv
      planning_by_method_cause.csv
      planning_scenarios.csv
      table_index.csv                # table locations relative to this folder
    Data/                            # RESTRICTED source/derived records
    Code/                            # source used for this run
```

Nigeria and DRC use their own country names. **Keep the whole build folder private** because it contains source or derived survey records. Share the reviewed report, not the entire build folder.

### Optional settings at the top of each country script

Most users can leave these alone:

- `IR_FILE`: blank opens the file browser; a runtime `DHS_IR_FILE` value skips it.
- `OUTPUT_DIRECTORY`: blank uses the new folder described above. A supplied location must be new, private and outside the repository.
- `REPORT_WORKERS`: default `1`, which works without forked workers. macOS users can increase it if their computer has capacity. Windows uses serial execution for fork-based stages.
- `PYTHON_EXECUTABLE`: default `auto` prepares Python and the exact Python packages in `requirements.txt`. No manual Python installation is needed for this default route.
- `OPEN_REPORT`: controls whether a successful report opens in the browser.
- `REFERENCE_POLICY`: default `strict` requires the final comparisons to pass. See troubleshooting before changing it.

To **load functions without starting a build**, run `Sys.setenv(DHS_AUTO_RUN = "false")` before sourcing. This is for advanced/programmatic use; it is not needed for the normal Source workflow.

### One-script numerical analysis without HTML

A national R script alone can run its embedded numerical analysis. It cannot assemble the full HTML without the repository's reporting resources. For the verified full-report workflow, use Option 1 or Option 2 above.

If you deliberately downloaded just one country R script:

1. In the RStudio Console, run `Sys.setenv(DHS_AUTO_RUN = "false")`.
2. Open that country R script and click **Source** to load its functions.
3. Run the following in the Console. The file browser selects your own IR; the output location is supplied at runtime. Paste a new private folder location without surrounding quotes.

```r
ir_file <- file.choose()
output_dir <- readline("New private output folder: ")
analysis_results <- run_analysis(
  ir_file = ir_file,
  output_dir = output_dir,
  scope = "all",
  replicates = 500L,
  cores = 1L
)
analysis_results$planning_overall
```

`run_analysis()` installs/loads the declared packages before calculating results. It returns numerical tables in R and writes numerical files; it does not create the national HTML or a new PPTX. To return to the full-report Source workflow, keep the complete repository and run `Sys.setenv(DHS_AUTO_RUN = "true")` before sourcing the country script again.

## What lives where?

```text
Discontinuation-analyses/
  README.md                          # start here
  build_reports.R                    # national CLI builder
  workflow.R                         # RStudio launchers and dependency setup
  survey_design.R                    # shared DHS survey estimators/checks
  report_tools.py                    # reporting and comparison resources
  method_sensitivity_report.py        # method-group sensitivity displays
  geography.json                     # pinned public map resources
  renv.lock                          # checked R package versions
  requirements.txt                   # pinned Python rendering packages
  Ethiopia_analysis/                 # Ethiopia script + approved HTML/PPTX
  Nigeria_analysis/                  # Nigeria script + approved HTML/PPTX
    Kano_Kaduna_Lagos/                # optional state scripts/results
  DRC_analysis/                      # DRC script + approved HTML/PPTX
  discontinuation_extensions/
    run_analysis.R                   # extensions/maps entry point
    output/                          # approved extensions/maps references
  docs/                              # data access, methods and survey design
  tests/                             # analytical and workflow checks
```

Supporting source is expanded into a private runtime during a build. You do not need to find or run those pieces yourself. **A single national script is sufficient for numerical-only mode; the complete extracted repository is required to assemble the full HTML.**

## Optional extensions, maps and state analyses

For the extensions/maps in RStudio, open [discontinuation_extensions/run_analysis.R](discontinuation_extensions/run_analysis.R) and click **Source**. It asks for the **three IR `.dta` files**, one country at a time, and writes new HTMLs in a private extensions results folder. This reproduces reason-specific timing, alluvials, subsequent-use displays, destinations and interactive maps.

CLI equivalent, with caller-supplied input variables:

```sh
Rscript discontinuation_extensions/run_analysis.R --ethiopia-ir="$ETHIOPIA_IR_FILE" --nigeria-ir="$NIGERIA_IR_FILE" --drc-ir="$DRC_IR_FILE" --output-dir="$DHS_BUILD_DIR" --python=auto
```

The state scripts—[Kano](Nigeria_analysis/Kano_Kaduna_Lagos/Kano_discontinuation_analysis.R), [Kaduna](Nigeria_analysis/Kano_Kaduna_Lagos/Kaduna_discontinuation_analysis.R) and [Lagos](Nigeria_analysis/Kano_Kaduna_Lagos/Lagos_discontinuation_analysis.R)—also accept **Source → select Nigeria IR**. They export that state's numerical tables and SVG figures and open a simple HTML results gallery. This gallery is **not a rebuild of the approved combined three-state HTML or its PowerPoint**. The existing combined-report table-refresh workflow is documented under [state tables](docs/methods.md#state-tables). State counts retain their documented normalization and assumptions.

## Troubleshooting

| What happened? | What to do |
|---|---|
| The script cannot find `workflow.R` or a report resource | Extract the complete repository ZIP and keep the folders together. Open the country script from inside that folder. |
| The file browser was cancelled | Click Source again and select the IR `.dta`. |
| Source loads functions but no file browser appears | Restart R, or run `Sys.setenv(DHS_AUTO_RUN = "true")`, then click Source for the entire country script. |
| Wrong survey/release or missing calendar variables | Check the table of required IR files above; do not edit calendar strings or substitute a different release. |
| R package installation fails | Read the named package's error. Current R binaries usually avoid compilation; some packages may require operating-system libraries. Install those requirements, restart R and retry. |
| Automatic Python setup fails | Check internet access/proxy restrictions, restart R and retry. An existing prepared Python can be supplied through `PYTHON` or `--python`. |
| DRC cannot find LibreOffice | Install LibreOffice and restart R. The workflow searches installed executables and standard installation information. A custom installation can be supplied through `SOFFICE` or `--soffice`. |
| The output folder is not empty | Use a new folder. Cold rebuilds do not silently reuse earlier fitted results. |
| R is still busy | Full models and bootstrap refits can take hours. Inspect the Console stage and private `output/logs`; do not start duplicate runs. |
| The HTML was built but reference comparisons differ | Review `output/validation`. Fonts and rendering libraries can change figures across computers. Numerical differences also require review. `--reference-policy=report` (or `REFERENCE_POLICY <- "report"`) retains an explicitly flagged candidate instead of requiring reference agreement. It does not change the estimates or approve differences. |

## Methods, reproducibility and checks

The IR is read using `haven::read_dta()`. Monthly calendars are converted into linked episodes/person-months. Records inherit DHS weight `v005 / 1,000,000`, PSU `v021` and stratum `v022`. Standard survey estimators and full-frame stratified PSU uncertainty procedures preserve the complex survey design and repeated histories within women. See [methods](docs/methods.md) and [survey design](docs/survey-design.md).

Potentially actionable planning causes are method failure, wanting a more effective method, bleeding changes, other side effects/health, and access/cost/convenience. Partner/spousal disapproval is separate. EC is excluded as an original continuing method but remains modern for current mCPR and subsequent use. Permanent current users remain in mCPR and receive no stopping gain.

Historical and AFT planning account for method and elapsed use. Main calculations count actionable endings as losses; switching/restarting sensitivities count absence from modern use at the common next-12-month endpoint. Population projections, growth scenarios and selected AFT families are held fixed. These are conditional planning scenarios, not established intervention effects.

Verification on 23 November 2026 used fresh authorized-IR builds with 500 joint planning replicates per country, followed by targeted rechecks of Nigeria's supplemental current-user pathway correction. The resulting 515 HTML tables, 171 embedded figures and 168 editable presentation tables reconcile with the reviewed references. All 13,349 planning estimate/interval records matched the validated baseline exactly. Nigeria's supplemental pathway now includes permanent users consistently in its table and figure; this correction does not change the main planning results. A source-only test does not certify a complete numerical rebuild. The Windows serial branch is implemented and tested through portable checks; a full build has not yet been run on a native Windows host.

For exact package restoration, advanced users may install `renv` and run `renv::restore(lockfile="renv.lock", prompt=FALSE)` from the repository root. Automatic setup installs missing R packages; it does not silently replace existing versions. Different R/BLAS, package or font environments can introduce small numerical or rendering differences.

Published DHS checks match 66 Ethiopian and 110 Nigerian tested rate cells. DRC has six documented 0.1-pp differences among 110 tested cells. Sparse DRC IUD estimates use Other-modern curves; its fully modeled switching sensitivity overpredicted held-out month-12 modern use and remains secondary. Detailed limitations remain in the methods/report documentation.

The builder creates a fresh HTML and compares it with the approved HTML and PPTX. It does **not regenerate or edit the PowerPoint**; a presentation copied into the output folder is the existing read-only reference. Preserve and review validation differences before sharing a newly built report.
