# Contraceptive discontinuation analyses

DHS contraceptive-calendar analyses for Ethiopia (2024–25), Nigeria (2024), and DRC (2023–24), with separate Nigeria state analyses and a three-country discontinuation/switching extensions module.

## Files

- `build_reports.R`: national build entry point.
- `<Country>_analysis/<Country>_final_html_analysis.R`: each country's analytical code, reporting code and layouts, consolidated as plain source.
- `report_tools.py`: shared rendering and read-only comparison code.
- `geography.json`: pinned public map geometry and attribution; no survey records.
- `Nigeria_analysis/Kano_Kaduna_Lagos/`: three parameterized state R entry points.
- `discontinuation_extensions/run_analysis.R`: independent extensions and maps entry point.
- `renv.lock`, `requirements.txt`: dependency versions.
- [Data access](docs/data-access.md): IR input parameters and R download instructions.

The entry points expand their readable source resources into private runtime directories. This keeps the repository small without dropping analytical stages. Saved fitted models, aggregate rebuild caches, generated validation inventories and working files are not required in the repository.

## Run a national report

Obtain an authorized IR file through DHS and keep it outside the repository. Restore the R packages in `renv.lock` and install Python dependencies from `requirements.txt`. DRC's display-only slide-preview gallery also requires LibreOffice (`soffice`).

```sh
Rscript -e 'renv::restore(lockfile="renv.lock", prompt=FALSE)'
python3 -m pip install -r requirements.txt
Rscript build_reports.R --check --python=python3
Rscript build_reports.R --country=Nigeria --ir-file="$DHS_IR_FILE" \
  --output-dir="$DHS_BUILD_DIR/nigeria" --python=python3 --cores=4
```

Use `Ethiopia` or `DRC` for the other countries. The output directory must be new and outside the repository. The build reads the IR, reconstructs calendars/episodes, fits models, computes 500 joint planning survey replicates and renders the HTML. It does not read an existing HTML or cached fitted results to calculate estimates. Full bootstrap runs can be lengthy.

Approved HTML and PPTX files remain in their existing repository locations as read-only comparison references. A code-only upload omits those files. `--reference-dir` can supply a different directory containing the same country-folder layout. Comparisons run after estimation and fail on differences; approved reports are never replaced. DRC uses the supplied deck only for the displayed slide-preview gallery. Successful new reports are written under the private output directory.

For source inspection, `--extract-source="$SOURCE_INSPECTION_DIR"` expands the source into an empty directory outside the repository without fitting models. `--check` checks source syntax; it does not establish numerical/model validity. Native slide tables and all HTML tables, text/navigation and embedded figures are checked during a complete build. Fonts and rendering-library differences can require review.

## Extensions, maps and states

```sh
Rscript discontinuation_extensions/run_analysis.R \
  --ethiopia-ir="$ETHIOPIA_IR_FILE" --nigeria-ir="$NIGERIA_IR_FILE" \
  --drc-ir="$DRC_IR_FILE" --output-dir="$DHS_BUILD_DIR/extensions" --python=python3
```

All three IRs and a new private output directory are required. `--target=extensions` or `--target=maps` selects one report; the default produces both. The module reconstructs its own records and uses 1,999 full-frame survey-bootstrap replicates. Authentication/download and public catalogue access are distinct; see the data-access guide.

The three state entry points preserve their existing numerical/figure exports. They do not author the combined state PowerPoint or rebuild its entire combined HTML. The national command covers the three national reports.

## Definitions and verification

Original continuing-modern-method episodes exclude EC. Potentially actionable causes are failure, wanting a more effective method, bleeding changes, other side effects/health, and access/cost/convenience. Partner/spousal disapproval is separate. EC remains part of all-women current mCPR and subsequent modern use. Point estimates use woman weights; survey inference keeps each woman's episodes together within the resampled PSU/stratum frame.

Main planning counts every actionable ending as a lost modern user. Switching/restarting sensitivities count modern use at the common next-12-month endpoint. Historical/AFT probabilities condition on method and elapsed use. Outcome years are 2026 for Ethiopia and 2025 for Nigeria/DRC. Fixed [UN WPP population inputs](https://population.un.org/wpp/), growth assumptions and selected AFT families are not uncertain in those intervals. Sparse-cell, recall and historical-transportability limitations remain; mCPR contributions are conditional scenarios, not established intervention effects.

The consolidated code preserves the numerical modules and is checked against the independently rebuilt local report versions. The existing GitHub national HTMLs are pre-reconciliation versions. This source-only update preserves them; strict comparison can flag that known version difference. No finished report or presentation is included or changed by this upload.

## Consolidation checks and remaining limits

All 224 existing analytical module bodies are unchanged. Fresh IR preparation again produced the same calendar/cohort counts:

| Country | Calendar runs | Published-table eligible episodes | Regional model cohort |
|---|---:|---:|---:|
| Ethiopia | 89,220 | 9,068 | 8,611 |
| Nigeria | 163,203 | 11,210 | 8,341 |
| DRC | 132,217 | 8,934 | 4,146 |

Rendering from the independently recomputed numerical outputs reproduced all 510 national HTML tables, 171 embedded figures and 164 native PowerPoint table counterparts. The prior raw-IR planning verification covered the point fits and all 500 joint replicates. Consolidation reran preparation and rendering; it did not change model expressions or refit those 500 draws again. Existing report/PPTX hashes remain unchanged.

Published DHS checks match all 66 Ethiopian and 110 Nigerian tested rate cells. DRC matches 104 of 110 tested rate cells, with six 0.1-pp differences retained in the audit. DRC's sparse IUD original-ending/transition estimates use Other-modern curves. Its modeled-transition sensitivity overpredicted held-out month-12 modern use by 5.37 pp, so it remains a sensitivity, not a primary estimate. Country-specific exploratory diagnostics retain their reviewed specifications; they are not all identical estimators. Detailed validation files are generated privately during rebuilding rather than stored as many repository files.

## Cleanup after uploading this update

Upload all 15 source/configuration files first. Keep all existing finished HTML reports and PPTXs. The old helper directories below have been consolidated into the country scripts, `report_tools.py` and `geography.json`.

If using a local Git checkout, run from its root after the new files are in place:

```sh
git rm -r --ignore-unmatch -- \
  tools recompute_planning.R validate_repository.py validation_summary.json \
  Ethiopia_analysis/src Ethiopia_analysis/reference_data Ethiopia_analysis/revision_inputs \
  Ethiopia_analysis/README.md Ethiopia_analysis/validation_summary.json \
  Nigeria_analysis/src Nigeria_analysis/revision_inputs \
  Nigeria_analysis/README.md Nigeria_analysis/validation_summary.json \
  Nigeria_analysis/Kano_Kaduna_Lagos/README.md \
  DRC_analysis/src DRC_analysis/revision_inputs \
  DRC_analysis/README.md DRC_analysis/validation_summary.json \
  discontinuation_extensions/src discontinuation_extensions/assets \
  discontinuation_extensions/validation discontinuation_extensions/README.md \
  discontinuation_extensions/.gitignore \
  discontinuation_extensions/output/browser_validation.json \
  discontinuation_extensions/output/software_versions.csv \
  discontinuation_extensions/output/validation.json
```

On GitHub web, remove the same named directories/files individually. Some will be absent if the larger update was never uploaded. **Keep** `discontinuation_extensions/output/Discontinuation_and_switching_extensions.html` and `Modern_method_discontinuation_maps.html`, all national report HTMLs/PPTXs, and the combined state HTML/PPTX. Never delete a whole country folder or the extensions `output` folder. The three state R entry points also stay.

With the current GitHub contents, this cleanup removes 56 obsolete support files and leaves 15 source/configuration files plus the 10 existing finished reports. Source syntax can then be checked with `Rscript build_reports.R --check`; a full independent rebuild additionally requires authorized IR inputs and the approved reference reports.
