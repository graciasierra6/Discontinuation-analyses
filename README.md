# Contraceptive discontinuation analyses

Latest saved reports, presentations, and parameterized R analysis entry points
for Ethiopia, Nigeria, DRC, and the combined Kano–Kaduna–Lagos analysis.

## Files

| Analysis | Folder | Report / R entry point |
| --- | --- | --- |
| Ethiopia DHS 2024–25 | `Ethiopia_analysis/` | `Ethiopia_discontinuation_analysis.html` / `Ethiopia_final_html_analysis.R` |
| Nigeria DHS 2024 | `Nigeria_analysis/` | `Nigeria_discontinuation_analysis.html` / `Nigeria_final_html_analysis.R` |
| DRC DHS 2023–24 | `DRC_analysis/` | `DRC_discontinuation_analysis.html` / `DRC_final_html_analysis.R` |
| Kano, Kaduna, Lagos | `Nigeria_analysis/Kano_Kaduna_Lagos/` | Combined HTML/PPTX and one `State_discontinuation_analysis.R` entry point per state |

Each folder includes a README. The saved presentations have no presenter notes.
No confidential IR files, fitted models, credentials, or personal input locations
are included. Each national `revision_inputs/` contains only the aggregate
estimates, 500 joint bootstrap draws, and metadata needed to rebuild the revision.
IR inputs are caller-supplied parameters or environment variables; generated
working files are excluded by `.gitignore`.

## Reproducibility status

**National reports:** the updated R files retain the numerical source collections
and add tested revision calculations and incremental HTML builders. Those builds
take the validated report layout plus included aggregate point estimates and bootstrap draws;
they do not freshly compute every unchanged chapter or figure. Raw-IR preparation
is available separately. Full raw-IR-to-complete-formatted-report regeneration
remains unfinished and must not be described as verified end to end.

**Three-state report:** the three standalone R scripts were tested from the full
2024 Nigeria IR through numerical estimates, planning and statistical figures.
All 60 state display tables matched the combined HTML, including confidence
intervals. The scripts export numerical tables/figures, not native PPTX slides.

Revision builds matched every saved national table: Ethiopia 154, Nigeria 133,
DRC 143. Matching saved tables is separate from statistical or arithmetic
validation. In particular, some Ethiopia AFT method-scenario rows mix two fitted
output versions: discrepancies are about 68 women for gross endings and 23 for
switching sensitivity. Rounded overall pp gains remain unchanged. These existing
report discrepancies are preserved and explicitly flagged by the new build.

## Analytical definitions

- Discontinuation denominators are eligible modern-method use episodes, or
  episodes of the specified method. EC is excluded from ongoing-method ending
  analyses but remains in current all-women mCPR.
- All-cause results precede the focus on potentially actionable causes: method
  failure, wanted greater effectiveness, bleeding changes, other side effects/
  health, and access/cost/convenience. Partner/spousal disapproval is separate.
- Main user-loss planning treats actionable original-method endings as losses;
  switching/restarting sensitivities are separately labelled. The three risk
  approaches are first-year probabilities, historical duration-aware estimates,
  and AFT survival predictions.
- Nigeria and DRC use 2024 as baseline and project 2025; Ethiopia treats the
  2024–25 survey as the 2025 baseline and projects 2026. Added-user pp equivalents
  use the projected outcome-year women ages 15–49 as the denominator.
- National scenarios use recent DHS, longer-term DHS, and FPET-informed annual
  changes. State scenarios use the two verified state DHS trends. Growth and
  demographic assumptions are fixed, not estimated intervention effects.

Country source collections contain historical variants with different cohorts,
outcomes and specifications. Follow the folder README; do not run all modules
indiscriminately or equate preparation/syntax checks with full report replication.

## Work locally

For national revision builds, install R packages `jsonlite`, `digest`, and `abind`.
The wider analysis dependencies are listed by each script's `--packages` option.
Install the HTML helper dependency with `python -m pip install -r requirements.txt`.
Supply authorized IR inputs through `DHS_IR_FILE` or `--ir-file`. Country READMEs
document `--run=prepare`, `--run=build-planning`, and `--run=build-html`, along
with the aggregate-input requirements. Existing saved reports are not overwritten
by those commands. No API credentials or data acquisition are bundled.

This current working copy is prepared for review/upload. No remote changes have
been pushed by preparing this folder.
