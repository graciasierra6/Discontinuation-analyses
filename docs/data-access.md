# Data access and a reproducible build

IR microdata are **not included in this repository**. Supply an authorized file
through `--ir-file` (or the documented environment-variable input for the
extensions). Build directories, downloaded archives, extracted records and
authentication configuration must stay outside the repository.

## Which data?

| Country | Survey | Validated release prefix |
|---|---|---|
| Ethiopia | DHS 2024–25 | `ETIR8A` |
| Nigeria | DHS 2024 | `NGIR8B` |
| DRC | DHS 2023–24 | `CDIR81` |

Use the original labelled women's Individual Recode. Keep calendar strings,
spacing, monthly positions and value labels intact. A later dataset release
must be reviewed rather than silently substituted. Validation records the
input checksum and checks survey, woman, calendar and analytical-cohort fields.

## Tested route: an authorized IR file

Download the approved IR through [The DHS Program's data access process](https://dhsprogram.com/data/Access-Instructions.cfm).
Extract it into private storage. From the repository root, run:

```sh
Rscript build_reports.R --country=Nigeria \
  --ir-file="$DHS_IR_FILE" \
  --output-dir="$DHS_BUILD_DIR" \
  --python=python3
```

The two variables are supplied by the caller; no actual input location is
recorded in shared files. Use a new output directory outside the repository.
The country can also be `Ethiopia` or `DRC`. Numerical analyses are calculated
from the supplied IR, not copied from existing reports or fitted results.

## R access through DHS

The [public DHS API](https://api.dhsprogram.com/) provides aggregate indicators
and a survey/dataset catalogue. It does not supply individual contraceptive
calendars. In R, `rdhs::dhs_datasets()` can query that catalogue.
`rdhs::get_datasets()` separately logs into the DHS website to download files
that the account's approved project can access. See the package's
[catalogue](https://docs.ropensci.org/rdhs/reference/dhs_datasets.html),
[authentication](https://docs.ropensci.org/rdhs/reference/set_rdhs_config.html),
and [download](https://docs.ropensci.org/rdhs/reference/get_datasets.html)
documentation.

The optional example below is intended for an interactive R session started
at the repository root. Set `DHS_PRIVATE_DIR`, `DHS_EMAIL`, `DHS_PROJECT` and
optionally `DHS_COUNTRY` in runtime configuration. Obtain DHS approval first.
The password is requested by the package, not embedded in this code.

```r
# Optional download dependency; the numerical build does not require rdhs.
# install.packages("rdhs", repos = "https://cloud.r-project.org")
stopifnot(requireNamespace("rdhs", quietly = TRUE))
repo_root <- normalizePath(".")
private_dir <- Sys.getenv("DHS_PRIVATE_DIR")
country <- Sys.getenv("DHS_COUNTRY", unset = "Nigeria")
email <- Sys.getenv("DHS_EMAIL")
project <- Sys.getenv("DHS_PROJECT")
stopifnot(nzchar(private_dir), nzchar(email), nzchar(project))
dir.create(private_dir, recursive = TRUE, showWarnings = FALSE)
private_dir <- normalizePath(private_dir)
stopifnot(private_dir != repo_root,
          !startsWith(private_dir, paste0(repo_root, .Platform$file.sep)))

country_codes <- c(Ethiopia = "ET", Nigeria = "NG", DRC = "CD")
archives_expected <- c(Ethiopia = "ETIR8ADT.ZIP",
                       Nigeria = "NGIR8BDT.ZIP", DRC = "CDIR81DT.ZIP")
stopifnot(country %in% names(country_codes))

# Local configuration is created in private storage, never in the repository.
setwd(private_dir)
rdhs::set_rdhs_config(
  email = email, project = project,
  config_path = "rdhs.json", cache_path = file.path(private_dir, "cache"),
  global = FALSE, verbose_setup = FALSE, verbose_download = FALSE
)
catalogue <- as.data.frame(rdhs::dhs_datasets(
  countryIds = unname(country_codes[country]),
  fileType = "IR", fileFormat = "DT", surveyYearStart = 2023
))
selected <- catalogue[toupper(catalogue$FileName) ==
                        archives_expected[[country]], , drop = FALSE]
stopifnot(nrow(selected) == 1L)
downloaded <- rdhs::get_datasets(
  dataset_filenames = selected$FileName,
  download_option = "zip", reformat = FALSE,
  output_dir_root = file.path(private_dir, "downloads")
)
archives <- unlist(downloaded, use.names = FALSE)
archives <- archives[!is.na(archives) & grepl("[.]zip$", archives,
                                            ignore.case = TRUE)]
stopifnot(length(archives) == 1L, file.exists(archives))
extracted <- file.path(private_dir, paste0(tolower(country), "-ir"))
dir.create(extracted, showWarnings = FALSE)
unzip(archives, exdir = extracted)
ir_file <- list.files(extracted, pattern = "[.]dta$", ignore.case = TRUE,
                      recursive = TRUE, full.names = TRUE)
stopifnot(length(ir_file) == 1L)
setwd(repo_root)
status <- system2("Rscript", shQuote(c(
  "build_reports.R", paste0("--country=", country),
  paste0("--ir-file=", ir_file),
  paste0("--output-dir=", file.path(private_dir,
                                    paste0(tolower(country), "-build"))),
  paste0("--python=", Sys.getenv("PYTHON", unset = "python3"))
)))
stopifnot(status == 0L)
```

Authentication configuration may contain credentials. Keep it private and do
not print or upload it. The public catalogue was checked and listed all three pinned Stata archives.
The authenticated download has **not** been exercised
with a DHS login in this verification. The file-input route has been tested;
public catalogue access and an authenticated microdata download are different
operations. The same preparation and validation code runs after either route.

## What is rebuilt and what is preserved?

The build reconstructs the calendar and eligible episodes, computes weighted
estimates, fits the models and survey replicates, and renders a new HTML in the
private output directory. Final HTML and PPTX files in the repository are
read-only references. They are used for comparison after estimation.

All final HTML tables, report text and embedded figures are compared with the
independent output. A difference stops validation; it never updates an approved
report. Raster figures can differ with fonts or rendering-library versions;
such a difference must be reviewed even when numerical tables agree. The PPTX
is not regenerated. DRC's slide-preview gallery renders the supplied reviewed
PPTX for display, independently of estimation.

Share the validated HTML and reviewed PPTX, not the whole private build tree.
Microdata, intermediate woman/episode records, credentials and private runtime
logs remain outside the repository. Small regression references used by the extensions module are embedded as checks;
no saved fitted-object inputs are required for national estimation.
