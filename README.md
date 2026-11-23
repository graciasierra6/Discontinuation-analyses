# Contraceptive discontinuation analyses

Reproduce DHS contraceptive-calendar analyses for **Ethiopia, Nigeria and DRC** from authorized women's Individual Recode (IR) files. The analyses cover method starts, discontinuation, reasons, timing, switching/restarting, regional comparisons and potential contributions to mCPR.

**Choose one of three ways to run the same analyses. For RStudio, you can download just one report R file; its public support files are prepared automatically.**

| How you prefer to work | What to open |
|---|---|
| **Option 1: Terminal** | [Terminal instructions](#option-1--terminal) · [Windows](#windows--powershell) · [macOS](#macos--terminal-using-zsh) |
| **Option 2: RStudio** | [RStudio instructions](#option-2--rstudio-open-source-select-the-ir) · [Ethiopia script](Ethiopia_analysis/Ethiopia_final_html_analysis.R) · [Nigeria script](Nigeria_analysis/Nigeria_final_html_analysis.R) · [DRC script](DRC_analysis/DRC_final_html_analysis.R) |
| **Option 3: Coding assistant with terminal access** | [Step-by-step instructions and request to copy](#option-3--coding-assistant) |

No microdata are included. Existing HTMLs and presentations are read-only references. A run writes new results to a separate private folder; it does not replace the approved files.

[Reports and scripts](#reports-and-scripts) · [Country file locations](#country-file-locations) · [First-time setup](#before-your-first-run) · [Terminal workflow](#option-1--terminal) · [RStudio workflow](#option-2--rstudio-open-source-select-the-ir) · [Coding-assistant workflow](#option-3--coding-assistant) · [Results](#where-are-my-results) · [Troubleshooting](#troubleshooting)

## Reports and scripts

Use the script links to find the correct entry point. **For RStudio, download the report R file and click Source.** The script installs missing packages and obtains pinned public support files automatically. A complete repository download remains available for the terminal workflow. The saved HTML links below identify the reviewed reports; GitHub may show their source, so open the downloaded HTML in your browser to view it. Presentations are reviewed references used for comparison, not newly generated decks.

| Report | Script to open in RStudio | Saved HTML | Presentation |
|---|---|---|---|
| Ethiopia national analysis | [Ethiopia R script](Ethiopia_analysis/Ethiopia_final_html_analysis.R) | [Ethiopia HTML](Ethiopia_analysis/Ethiopia_discontinuation_analysis.html) | [Ethiopia PPTX](Ethiopia_analysis/ethiopia_presentation.pptx) |
| Nigeria national analysis | [Nigeria R script](Nigeria_analysis/Nigeria_final_html_analysis.R) | [Nigeria HTML](Nigeria_analysis/Nigeria_discontinuation_analysis.html) | [Nigeria PPTX](Nigeria_analysis/Nigeria_discontinuation.pptx) |
| DRC national analysis | [DRC R script](DRC_analysis/DRC_final_html_analysis.R) | [DRC HTML](DRC_analysis/DRC_discontinuation_analysis.html) | [DRC PPTX](DRC_analysis/DRC_discontinuation.pptx) |
| Timing, alluvials and switching extensions | [Extensions R script](discontinuation_extensions/Discontinuation_and_switching_extensions.R) | [Extensions HTML](discontinuation_extensions/output/Discontinuation_and_switching_extensions.html) | — |
| Interactive discontinuation maps | [Maps R script](discontinuation_extensions/Modern_method_discontinuation_maps.R) | [Maps HTML](discontinuation_extensions/output/Modern_method_discontinuation_maps.html) | — |
| Return and continuation curves | [Return/continuation R script](discontinuation_extensions/Return_and_continuation_analysis.R) | [Return/continuation HTML](discontinuation_extensions/output/Return_and_continuation_same_cohort_preview.html) | — |
| Optional state numerical results | [Kano](Nigeria_analysis/Kano_Kaduna_Lagos/Kano_discontinuation_analysis.R) · [Kaduna](Nigeria_analysis/Kano_Kaduna_Lagos/Kaduna_discontinuation_analysis.R) · [Lagos](Nigeria_analysis/Kano_Kaduna_Lagos/Lagos_discontinuation_analysis.R) | [Combined state reference](Nigeria_analysis/Kano_Kaduna_Lagos/Kano_Kaduna_Lagos_discontinuation_analysis.html) | [Combined state PPTX](Nigeria_analysis/Kano_Kaduna_Lagos/Kano_Kaduna_Lagos_discontinuation.pptx) |

Each extensions/maps entry asks for all three countries' IR files. The return/continuation and main extensions entries share calculations and also produce the companion extensions report. The original [combined extensions entry](discontinuation_extensions/run_analysis.R) can still build all three outputs. The optional state scripts generate individual numerical results and simple galleries; they do not independently reconstruct the saved combined state HTML/PPTX layout. See [optional analyses](#optional-extensions-maps-and-state-analyses).

## Country file locations

All locations below start at the **repository root**: the extracted folder containing this `README.md`. They are repository-relative locations, not locations on anyone's computer. The filename links open the corresponding file on GitHub; the same folders and filenames are present after you download and extract the complete repository.

**Which file should I use?**

- **R script (`.R`):** the country analysis entry point. It contains package installation/loading and the analysis code. Open the downloaded file in RStudio and click Source to select your own authorized IR file and rebuild the HTML. Public supporting code is obtained automatically. [Numerical-only analysis](#one-script-numerical-analysis-without-html) is also available.
- **HTML report (`.html`):** the detailed, reviewed analysis, including figures, tables, methods and planning scenarios. To read the findings, open the downloaded HTML in Chrome, Edge, Safari or another browser. You do not need R just to view it.
- **PowerPoint presentation (`.pptx`):** the reviewed presentation slides for PowerPoint or Keynote, with no presenter notes. Use this for presenting the findings. The report workflow checks editable slide tables against the HTML; it does not regenerate or edit the deck.

| Country | File type | Location from the repository root |
|---|---|---|
| Ethiopia | R analysis script | [Ethiopia_analysis/Ethiopia_final_html_analysis.R](Ethiopia_analysis/Ethiopia_final_html_analysis.R) |
| Ethiopia | HTML report | [Ethiopia_analysis/Ethiopia_discontinuation_analysis.html](Ethiopia_analysis/Ethiopia_discontinuation_analysis.html) |
| Ethiopia | PowerPoint slides | [Ethiopia_analysis/ethiopia_presentation.pptx](Ethiopia_analysis/ethiopia_presentation.pptx) |
| Nigeria | R analysis script | [Nigeria_analysis/Nigeria_final_html_analysis.R](Nigeria_analysis/Nigeria_final_html_analysis.R) |
| Nigeria | HTML report | [Nigeria_analysis/Nigeria_discontinuation_analysis.html](Nigeria_analysis/Nigeria_discontinuation_analysis.html) |
| Nigeria | PowerPoint slides | [Nigeria_analysis/Nigeria_discontinuation.pptx](Nigeria_analysis/Nigeria_discontinuation.pptx) |
| DRC | R analysis script | [DRC_analysis/DRC_final_html_analysis.R](DRC_analysis/DRC_final_html_analysis.R) |
| DRC | HTML report | [DRC_analysis/DRC_discontinuation_analysis.html](DRC_analysis/DRC_discontinuation_analysis.html) |
| DRC | PowerPoint slides | [DRC_analysis/DRC_discontinuation.pptx](DRC_analysis/DRC_discontinuation.pptx) |

**To read results:** choose the country's HTML. **To present results:** choose its PPTX. **To rerun the analysis:** choose its R script and follow the [RStudio instructions](#option-2--rstudio-open-source-select-the-ir), the [terminal instructions](#option-1--terminal), or the [coding-assistant instructions](#option-3--coding-assistant).

## Before your first run

1. Install a current **R** and, for the graphical workflow, **RStudio Desktop**. The checked analysis environment uses R 4.6.0; package versions are recorded in `renv.lock`.
2. **For RStudio:** download the report's `.R` file using its link above and open it in RStudio. **For the terminal workflow:** click **Code → Download ZIP**, extract the complete ZIP, and keep its folders together. Git is not required.
3. Obtain the authorized DHS women's IR download and extract it separately. Keep the data outside the repository. Select the original labelled **`.dta` file**, not the ZIP or an HTML report.
4. For **DRC only**, install **LibreOffice** once. Its command-line renderer reproduces the report's presentation-preview gallery; it is not used to estimate discontinuation. The workflow checks for it before the long analytical run.
5. Keep internet access available for first-time dependency installation. R packages, Python and the pinned Python rendering packages are prepared automatically. Later runs can reuse the installed dependencies.

| Country | Survey | IR file to select | Planning baseline → outcome |
|---|---|---|---|
| Ethiopia | DHS 2024–25 | `ETIR8AFL.dta` | 2025 → 2026 |
| Nigeria | DHS 2024 | `NGIR8BFL.dta` | 2024 → 2025 |
| DRC | DHS 2023–24 | `CDIR81FL.dta` | 2024 → 2025 |

The scripts check the validated release and calendar fields. They stop rather than silently use a different release. [Data access instructions](docs/data-access.md) explain DHS authorization, optional R download tools and why the public aggregate API cannot replace the individual calendars.

<a id="option-1--terminal-or-coding-assistant"></a>

## Option 1 — Terminal

Choose this route if you prefer to run commands yourself. Use [build_reports.R](build_reports.R). The country R calculations are the same as in the RStudio and coding-assistant routes.

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

Use this route for the full report if you prefer opening one script and clicking Source. **You do not need a local repository checkout.** On first use, the entry prepares a checked public support version automatically; you still supply the original IR data yourself.

1. Download the country R file from its GitHub file page. In RStudio, choose **File → Open File** and open that downloaded file:

   | Country | Script inside the extracted repository |
   |---|---|
   | Ethiopia | [Ethiopia_analysis/Ethiopia_final_html_analysis.R](Ethiopia_analysis/Ethiopia_final_html_analysis.R) |
   | Nigeria | [Nigeria_analysis/Nigeria_final_html_analysis.R](Nigeria_analysis/Nigeria_final_html_analysis.R) |
   | DRC | [DRC_analysis/DRC_final_html_analysis.R](DRC_analysis/DRC_final_html_analysis.R) |

2. Click **Source** at the top right of the script editor. Use Source for the entire file, rather than running one selected line.
3. The package block near the top automatically installs missing R packages into a writable R library and loads the declared libraries. A private user library is created if the existing libraries are not writable.
4. Public support files are downloaded once, verified against pinned checksums, and cached. A file browser asks you to select the country's extracted **IR `.dta`** file.
5. The workflow prepares the Python report renderer, reconstructs calendars, fits the models and survey bootstrap replicates, then builds and checks the HTML.
6. Leave RStudio running. A full build can take **several hours**. The Console reports its current stage; it is not necessary to click Source again.
7. After a successful build, the HTML opens in your browser. In RStudio's Environment pane:
   - `report_results` identifies the new HTML and output folder.
   - `analysis_results` contains the numerical tables. For example, enter `analysis_results$planning_overall` or `analysis_results$table_index` in the Console.

### Where are my results?

If you downloaded one R file, its default results go into **`discontinuation_results` beside that R file**. If you use a complete local repository, results go alongside the repository folder. Each run has its own country and timestamp:

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

The default one-file Source workflow builds the HTML and obtains its public rendering resources automatically. If you want only R/CSV results, the national script also has an embedded numerical-only mode that bypasses report formatting.

To run numerical-only mode:

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

`run_analysis()` installs/loads the declared packages before calculating results. It returns numerical tables in R and writes numerical files; it does not create the national HTML or a new PPTX. To return to the automatic HTML workflow, run `Sys.setenv(DHS_AUTO_RUN = "true")` before sourcing the report R file again.

## Option 3 — Coding assistant

Choose this route if you want an assistant with **file and terminal access** to execute the repository's existing scripts. It must have access to R, the code and your authorized IR files in the environment where the analysis runs. A repository link alone does not supply the confidential data. This is another way to execute the same analyses, not a different statistical approach.

1. Give it the [repository link](https://github.com/graciasierra6/Discontinuation-analyses) and specify **Ethiopia, Nigeria or DRC**, or one of the [extensions reports](#optional-extensions-maps-and-state-analyses).
2. Make the original IR file available privately in that execution environment. Use the [country/file table](#before-your-first-run) to choose the correct release. Extensions and maps require all three IRs. Keep microdata out of GitHub.
3. Ask it to obtain the repository, read this README and [data-access instructions](docs/data-access.md), and check R and the required software. The scripts handle package setup. DRC additionally needs LibreOffice for its slide-preview gallery.
4. Ask it to execute the existing [terminal workflow](#option-1--terminal), supplying the input location at runtime and choosing a **new private output folder outside the repository**. It should preserve the analytical definitions and reviewed HTML/PPTX files.
5. Ask for the command, commit, completion status, validation comparisons and location of the generated HTML. Reviewing source code or running `--check` alone does not reproduce results.

**Request to copy for one national report:**

> Reproduce the Nigeria national report from https://github.com/graciasierra6/Discontinuation-analyses using the authorized NGIR8BFL.dta file that I will make available privately. Obtain the repository and read README.md and docs/data-access.md. Run build_reports.R with --country=Nigeria, the IR supplied through --ir-file, and a new private --output-dir outside the repository. Let the workflow prepare its dependencies and run the full numerical/report comparisons. Use the existing analysis without changing definitions or the reviewed reports. Return the commit, executed command, completion status, comparison results and generated HTML location. Explain any failures or differences. Do not commit, push or upload microdata.

For Ethiopia, substitute `Ethiopia` and `ETIR8AFL.dta`; for DRC, substitute `DRC` and `CDIR81FL.dta`. For extensions, select the linked report entry and follow its input instructions instead of the national builder. The assistant must execute and inspect the run; its choice of interface does not itself verify reproduction.

## How a single-file report starts

The entry obtains supporting code and reviewed comparison assets from a [fixed public source revision](https://github.com/graciasierra6/Discontinuation-analyses/tree/78b16c17deeb5ab359977d276e8a496c9190a65a). Every cached file is checked against its SHA-256 checksum before use. This public cache contains code, public inputs and report references; it does not contain IR microdata.

For national reports, the country code in the R file you opened is staged with those support files and used for the analysis. The original IR is read from your selection, calendars and episodes are reconstructed, and estimates are recomputed. Reviewed HTML/PPTX files are comparison references after estimation; DRC also uses its PPTX for the display-only slide gallery.

You can change the output location with `OUTPUT_DIRECTORY`. Advanced users can choose a writable public dependency cache through the runtime `DHS_RUNTIME_CACHE` environment variable. Neither setting contains a location specific to the original developer's computer.

## What lives where?

```text
Discontinuation-analyses/
  README.md                          # start here
  build_reports.R                    # national CLI builder
  workflow.R                         # RStudio launchers and dependency setup
  standalone_support.R               # pinned public dependency startup
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
    Discontinuation_and_switching_extensions.R
    Modern_method_discontinuation_maps.R
    Return_and_continuation_analysis.R
    run_analysis.R                   # optional combined extensions entry
    output/                          # approved extensions/maps references
  docs/                              # data access, methods and survey design
  tests/                             # analytical and workflow checks
```

Supporting source is expanded into a private runtime during a build. You do not need to find or run those pieces yourself. **One downloaded country/report entry is sufficient to start the HTML workflow.** First-time dependency preparation needs internet access.

## Optional extensions, maps and state analyses

Download the entry for the report you want, open it in RStudio and click **Source**:

| Report | Independent R entry |
|---|---|
| Timing, alluvials and switching | [Discontinuation_and_switching_extensions.R](discontinuation_extensions/Discontinuation_and_switching_extensions.R) |
| Interactive maps | [Modern_method_discontinuation_maps.R](discontinuation_extensions/Modern_method_discontinuation_maps.R) |
| Return and continuation curves | [Return_and_continuation_analysis.R](discontinuation_extensions/Return_and_continuation_analysis.R) |

Each entry installs missing libraries, obtains public support files when needed, and asks for the **three original IR `.dta` files**, one country at a time. The requested HTML opens after a successful build. The original combined entry below remains available for CLI use.

CLI equivalent, with caller-supplied input variables:

```sh
Rscript discontinuation_extensions/run_analysis.R --ethiopia-ir="$ETHIOPIA_IR_FILE" --nigeria-ir="$NIGERIA_IR_FILE" --drc-ir="$DRC_IR_FILE" --output-dir="$DHS_BUILD_DIR" --python=auto
```

The state scripts—[Kano](Nigeria_analysis/Kano_Kaduna_Lagos/Kano_discontinuation_analysis.R), [Kaduna](Nigeria_analysis/Kano_Kaduna_Lagos/Kaduna_discontinuation_analysis.R) and [Lagos](Nigeria_analysis/Kano_Kaduna_Lagos/Lagos_discontinuation_analysis.R)—also accept **Source → select Nigeria IR**. They export that state's numerical tables and SVG figures and open a simple HTML results gallery. This gallery is **not a rebuild of the approved combined three-state HTML or its PowerPoint**. The existing combined-report table-refresh workflow is documented under [state tables](docs/methods.md#state-tables). State counts retain their documented normalization and assumptions.

## Troubleshooting

| What happened? | What to do |
|---|---|
| A public support download or checksum check fails | Check internet access and retry Source. Use a fresh copy of the current report R file. No models run with an unverified public dependency cache. |
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

The new independent-entry structure has passed isolated-file setup, public-download/checksum, file-picker and report-dispatch checks. Isolated-file maps and return/continuation runs have also rebuilt all three extensions HTML files byte for byte from the original IRs: 18,855 map values match exactly, and 9,362 extensions values differ by at most 1.43 × 10⁻¹⁴ from the checked baseline. National numerical rechecks continue after this structure update. The isolated Ethiopia numerical run already matches all 2,687 planning estimate/interval records and all 500 planning replicates exactly; its remaining regional analyses are still running. The saved reports and PPTX files have not been changed by the startup update. Kano, Kaduna and Lagos are outside this update.

For exact package restoration, advanced users may install `renv` and run `renv::restore(lockfile="renv.lock", prompt=FALSE)` from the repository root. Automatic setup installs missing R packages; it does not silently replace existing versions. Different R/BLAS, package or font environments can introduce small numerical or rendering differences.

Published DHS checks match 66 Ethiopian and 110 Nigerian tested rate cells. DRC has six documented 0.1-pp differences among 110 tested cells. Sparse DRC IUD estimates use Other-modern curves; its fully modeled switching sensitivity overpredicted held-out month-12 modern use and remains secondary. Detailed limitations remain in the methods/report documentation.

The builder creates a fresh HTML and compares it with the approved HTML and PPTX. It does **not regenerate or edit the PowerPoint**; a presentation copied into the output folder is the existing read-only reference. Preserve and review validation differences before sharing a newly built report.
