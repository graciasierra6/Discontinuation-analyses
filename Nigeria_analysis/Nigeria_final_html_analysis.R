#!/usr/bin/env Rscript
# Nigeria DHS 2024: contraceptive discontinuation and switching.
# Data: original women's Individual Recode (IR), validated release NGIR8B.
# Respondents are women ages 15–49, regardless of marital status.
# vcal_1 records monthly contraceptive use/pregnancy; vcal_2 records stopping reasons.
# Calendar positions are aligned using v008 and v017–v019, then reconstructed as
# episode-level and person-month records. A woman can contribute multiple episodes.
# The survey year identifies the interview round; calendar histories cover earlier
# months as well. Each analysis states its retrospective window and eligibility.
# Current use/mCPR uses v312 and v313. Survey weight: v005/1e6; PSU: v021; stratum: v022.
# Planning baseline: 2024; outcome year: 2025. Population inputs are documented separately.
# Supply the authorized IR through --ir-file or DHS_IR_FILE; no microdata are embedded.
# The root build_reports.R runs fresh estimation and HTML rendering.

# In RStudio: open this file and click Source. Select the extracted IR .dta file when prompted.
# Or: Rscript Nigeria_final_html_analysis.R --run=analysis --ir-file=INPUT --output-dir=OUTPUT
# Source builds the HTML; missing public support files are obtained automatically.
# --run=analysis is numerical-only and uses this file's embedded analytical code.

# Most users change nothing here: click Source, then select the extracted IR .dta.
# All output paths below are project-relative unless supplied by the caller.
IR_FILE <- Sys.getenv("DHS_IR_FILE", unset="")
OUTPUT_DIRECTORY <- Sys.getenv("DHS_ANALYSIS_OUTPUT", unset="")
ANALYSIS_SCOPE <- "all"          # "all", "planning", or "core"
PLANNING_REPLICATES <- 500L       # retain 500 for the planning uncertainty analysis
ANALYSIS_WORKERS <- 1L            # increase only if your computer has capacity
# Source runs automatically in an interactive R session. Set this environment
# variable to false before source() only when loading functions for advanced use.
RUN_ON_SOURCE <- interactive() &&
  !tolower(Sys.getenv("DHS_AUTO_RUN", unset="true")) %in% c("false","no","0")

# Package setup: install missing packages, then attach them before analysis.
# For the validated package versions, run renv::restore() from the repo root first.
# Help, source inspection and syntax checks do not install the full analysis stack.
REQUIRED_R_PACKAGES <- c('abind', 'data.table', 'digest', 'ggplot2', 'grDevices', 'grid', 'gridExtra', 'haven', 'jsonlite', 'MASS', 'nnet', 'parallel', 'scales', 'sf', 'splines', 'stats', 'survey', 'survival', 'svglite', 'tools', 'reticulate')
setup_analysis_packages <- function(packages=REQUIRED_R_PACKAGES, install_missing=TRUE) {
  # Use a writable R library and pass the selected library paths to R children.
  libraries<-.libPaths()
  writable<-libraries[dir.exists(libraries)&file.access(libraries,2L)==0L]
  if(!length(writable)){
    managed_library<-file.path(tools::R_user_dir('discontinuation-analyses','data'),
      paste0('R-',getRversion()),'library')
    dir.create(managed_library,recursive=TRUE,showWarnings=FALSE)
    if(!dir.exists(managed_library)||file.access(managed_library,2L)!=0L)
      stop('Cannot create a writable R package library. Ask your IT team to enable a user R library.',call.=FALSE)
    .libPaths(c(managed_library,libraries));writable<-managed_library
  }
  .libPaths(c(writable[1],.libPaths()))
  Sys.setenv(R_LIBS=paste(.libPaths(),collapse=.Platform$path.sep))
  install_library<-writable[1]
  packages <- unique(as.character(packages))
  available <- vapply(packages, requireNamespace, logical(1), quietly=TRUE)
  missing <- packages[!available]
  if (length(missing)) {
    if (!isTRUE(install_missing))
      stop('Missing R packages: ', paste(missing, collapse=', '), call.=FALSE)
    utils::install.packages(missing, lib=install_library, repos='https://cloud.r-project.org')
  }
  missing <- packages[!vapply(packages, requireNamespace, logical(1), quietly=TRUE)]
  if (length(missing))
    stop('Package installation was unsuccessful: ', paste(missing, collapse=', '),
         '. Check the package system requirements and restore the documented environment.', call.=FALSE)
  suppressPackageStartupMessages(invisible(lapply(packages, function(package)
    library(package, character.only=TRUE, quietly=TRUE, warn.conflicts=FALSE))))
  invisible(packages)
}


# Public dependency startup; embedded so this file can run on its own.
STANDALONE_SUPPORT <- r"------------------------------------(# Portable startup for a report launched from one downloaded R file.
# Public support files are version-pinned; IR inputs are selected at runtime.
DHS_RUNTIME_REVISION <- "78b16c17deeb5ab359977d276e8a496c9190a65a"
DHS_RUNTIME_SHA256 <- c(
  ".gitignore"="247c924bd3e6d854ba924c67012b323b38beda03101e6742c137de95373882fa",
  "DRC_analysis/DRC_discontinuation.pptx"="7aecccb44f125919aea6d243452799d07ba7f933589ea1d41dcd2befdd585653",
  "DRC_analysis/DRC_discontinuation_analysis.html"="bd8949e047c3850491d6b70c02128f80d6dc6e95d04c1e86f6daa6f2cb72e812",
  "DRC_analysis/DRC_final_html_analysis.R"="f3f7bc7a74002a4cdc6ca8ea8c8a6624f9e6cf6669cc15275e0623e00e91bdc1",
  "Ethiopia_analysis/Ethiopia_discontinuation_analysis.html"="5fa78e8ddaa1bc66f74d67094339a0f07ff45bb4cdcf50b101a9cdea67031660",
  "Ethiopia_analysis/Ethiopia_final_html_analysis.R"="653de79226127f7b134d44e8a3fb644396bc791414f8708ef2bd6a30c283b23b",
  "Ethiopia_analysis/ethiopia_presentation.pptx"="4c7eff1eac293d59a6d469989081ba4a86a1bdea7c13b448832d5a353d05fb75",
  "Nigeria_analysis/Kano_Kaduna_Lagos/Kaduna_discontinuation_analysis.R"="d9e2ea3f3b7e5d50b786b363e924a222848e1e36e5dcd0986c15bb315371c92d",
  "Nigeria_analysis/Kano_Kaduna_Lagos/Kano_Kaduna_Lagos_discontinuation.pptx"="3d0edd3b4d7e9e250ea0727883ce9fd78b763d92fdb5765a16cd13846b46f39a",
  "Nigeria_analysis/Kano_Kaduna_Lagos/Kano_Kaduna_Lagos_discontinuation_analysis.html"="be8f9b99ec2a54f5dedac81cc421cb53ab8618002323325948fffc50adbf3980",
  "Nigeria_analysis/Kano_Kaduna_Lagos/Kano_discontinuation_analysis.R"="93befd66a32629f0de07bf5944016fb04446d197283eadab5c71fa2354ad42cf",
  "Nigeria_analysis/Kano_Kaduna_Lagos/Lagos_discontinuation_analysis.R"="a8a13f72aa8cace6a09655bf4e49193657021fcd0c5a7206c4ef2b302b4a0dbd",
  "Nigeria_analysis/Nigeria_discontinuation.pptx"="1e1f2491e1833ab1b592642029f86f67bff7c56f4582a966b9e9bbd893ac95cd",
  "Nigeria_analysis/Nigeria_discontinuation_analysis.html"="f946c1078aeb423a6ae52afa1e6bd9ec13680231ac92b9e6896f066fd0154ff0",
  "Nigeria_analysis/Nigeria_final_html_analysis.R"="e00b855f3ec101d1c2fa3770ed285e09b75be8b2957cca7515a94fac3da56943",
  "README.md"="fc630363998b24bc623ffd44b473ab28535cafff3c69a0b78bb1492aaa928065",
  "build_reports.R"="b195ba1bda800434fa6270fff4fb04fce2c02a46a768f1f7b74d1dbef59561c5",
  "discontinuation_extensions/output/Discontinuation_and_switching_extensions.html"="40a224a8cdf5dcd4b91c050ef27141343f175d6ac569bde5cc58eb929d00d6b1",
  "discontinuation_extensions/output/Modern_method_discontinuation_maps.html"="09f75f42a5e435cb96af2fee273611481d947fc18b03817a29ff016f197f2388",
  "discontinuation_extensions/output/Return_and_continuation_same_cohort_preview.html"="7bb4628193d804b41f8c5f102ee42af3191b199c1a158207ed1f2c638ffa39f0",
  "discontinuation_extensions/run_analysis.R"="41e74d1abd396829b710f2384b8fd6c2385cda5e01bd15bd77ffc5a824af5f30",
  "docs/data-access.md"="0987db53a872290243d38bddb04720395d2b5c0bcf350291b7e8dba94e643238",
  "docs/methods.md"="fdfddac4dc419c774a570c4b297104236d16a5b9865d82fc33c8e388b958ce89",
  "docs/survey-design.md"="3f575926155c0ee8669e9e5b25c00ce86b86a6583bb61e7fe67f2351057afc01",
  "geography.json"="4a4d8950a82fd99626d4de6ef008c5c97f0e12a6409a28a53bef5511a170af3a",
  "method_sensitivity_report.py"="dae63e6bdeb6513dec476f2c21d10afd3b031f3d6c28660f1cb01dc420e4eb06",
  "renv.lock"="23ccfc02a6414fa697d4a2de6dadc2a6b87d293d807c111c69c4f59704d34392",
  "report_tools.py"="a900ef37897364f3efaa21cd4ddd45b3d0200999471f9170dacf3e3616e6438f",
  "requirements.txt"="7c7929572668b95766509270024df410a7a723d9ed93e7348ae75fc3232abd9e",
  "survey_design.R"="a6ee764ece430cf7c842c9dbdc01bd94a32820a0d4f0162e410f0e9104b7f003",
  "tests/check_planning_outputs.R"="6c889ae52126f86756b302c7ad3cd2109816971ebcec8cf822172a25d6cd5996",
  "tests/test_reporting.py"="e9439c74f6a8471cffbd14bb711f9d1bdf986212739354f60d6877746cd089ee",
  "tests/test_survey_design.R"="60fc8edaa58dfecf6cc73fc1007cab0803cc0b66b8b52e58d13c14cb27a3aec5",
  "tests/test_workflow.R"="31ca9ddc63e22297d500187dac92b1057133335a39c47c50258c16d5cf0a41ea",
  "workflow.R"="e9e185c7022267b157005c55c7fdbae01ad41f43555efcfa59b051c548690d85"
)

dhs_local_report_root <- function(script) {
  directory<-dirname(normalizePath(script,winslash='/',mustWork=TRUE))
  for(i in 1:7){
    if(all(file.exists(file.path(directory,c('workflow.R','build_reports.R','requirements.txt')))))return(directory)
    parent<-dirname(directory);if(identical(parent,directory))break;directory<-parent
  }
  ''
}

dhs_runtime_valid <- function(directory) {
  if(!dir.exists(directory))return(FALSE)
  actual<-list.files(directory,recursive=TRUE,all.files=TRUE,no..=TRUE)
  if(!setequal(actual,names(DHS_RUNTIME_SHA256)))return(FALSE)
  all(vapply(names(DHS_RUNTIME_SHA256),function(name)
    identical(digest::digest(file=file.path(directory,name),algo='sha256'),
      unname(DHS_RUNTIME_SHA256[[name]])),TRUE))
}

dhs_report_runtime <- function(script,download=utils::download.file) {
  local<-dhs_local_report_root(script)
  if(nzchar(local))return(local)
  cache<-Sys.getenv('DHS_RUNTIME_CACHE',unset='')
  if(!nzchar(cache))cache<-file.path(tools::R_user_dir('discontinuation-analyses','cache'),'public-runtime')
  dir.create(cache,recursive=TRUE,showWarnings=FALSE)
  if(!dir.exists(cache)||file.access(cache,2L)!=0L)
    stop('Cannot write the public dependency cache. Supply a writable DHS_RUNTIME_CACHE and retry.',call.=FALSE)
  root<-file.path(cache,DHS_RUNTIME_REVISION)
  if(dhs_runtime_valid(root))return(normalizePath(root,winslash='/'))
  cat('Preparing pinned public analysis code and report resources. First setup needs internet access.\n')
  stage<-tempfile('public-runtime-',tmpdir=cache);dir.create(stage)
  on.exit(unlink(stage,recursive=TRUE),add=TRUE)
  archive<-file.path(stage,'source.zip')
  url<-paste0('https://codeload.github.com/graciasierra6/Discontinuation-analyses/zip/',DHS_RUNTIME_REVISION)
  status<-download(url,archive,mode='wb',quiet=FALSE)
  if(status!=0L||!file.exists(archive))stop('Public report resources could not be downloaded. Check internet access and retry.',call.=FALSE)
  entries<-utils::unzip(archive,list=TRUE)
  if(!nrow(entries)||sum(entries$Length)>200e6||
     any(grepl('(^[/\\\\]|^[A-Za-z]:|(^|[/\\\\])[.][.]([/\\\\]|$))',entries$Name)))
    stop('The public source archive did not pass its file checks.',call.=FALSE)
  prefixes<-unique(sub('/.*$','',entries$Name))
  if(length(prefixes)!=1L)stop('Unexpected public archive structure.',call.=FALSE)
  utils::unzip(archive,exdir=stage)
  unpacked<-file.path(stage,prefixes[1])
  if(!dhs_runtime_valid(unpacked))stop('Public resource checksums differ from the pinned version. No analysis was run.',call.=FALSE)
  if(dir.exists(root))unlink(root,recursive=TRUE)
  if(!file.rename(unpacked,root))stop('Cannot finalize the public dependency cache. Retry after closing files in that cache.',call.=FALSE)
  normalizePath(root,winslash='/',mustWork=TRUE)
}

dhs_report_output <- function(script,label,output='',force=FALSE) {
  if(nzchar(output)||(!force&&nzchar(dhs_local_report_root(script))))return(output)
  file.path(dirname(normalizePath(script,winslash='/',mustWork=TRUE)),
    'discontinuation_results',paste0(tolower(label),'_',format(Sys.time(),'%Y%m%d_%H%M%S')))
}


# Run the country code in the downloaded R file, with pinned rendering support.
dhs_country_runtime <- function(script,country) {
  root<-dhs_report_runtime(script)
  relative<-file.path(paste0(country,'_analysis'),paste0(country,'_final_html_analysis.R'))
  if(identical(normalizePath(script,winslash='/'),normalizePath(file.path(root,relative),winslash='/')))
    return(list(repo=root,temporary=FALSE))
  stage<-tempfile('country-report-runtime-');dir.create(stage)
  success<-FALSE;on.exit(if(!success)unlink(stage,recursive=TRUE),add=TRUE)
  for(name in names(DHS_RUNTIME_SHA256)){
    destination<-file.path(stage,name);dir.create(dirname(destination),recursive=TRUE,showWarnings=FALSE)
    if(!file.copy(file.path(root,name),destination,overwrite=TRUE))stop('Cannot prepare public report resources.',call.=FALSE)
  }
  if(!file.copy(script,file.path(stage,relative),overwrite=TRUE))stop('Cannot stage the selected country R script.',call.=FALSE)
  success<-TRUE
  list(repo=normalizePath(stage,winslash='/'),temporary=TRUE)
}

dhs_standalone_workflow <- function(script) {
  root<-dhs_report_runtime(script)
  shared<-new.env(parent=globalenv())
  sys.source(file.path(root,'workflow.R'),envir=shared)
  shared$.report_repo<-root
  shared
}

dhs_named_extension <- function(script,filename,target='extensions',output='',
                                python='auto',open_report=TRUE,choose=file.choose,
                                run_command=system2) {
  shared<-dhs_standalone_workflow(script)
  output<-dhs_report_output(script,tools::file_path_sans_ext(filename),output)
  result<-shared$dhs_run_extensions_ui(
    file.path(shared$.report_repo,'discontinuation_extensions/run_analysis.R'),
    output=output,python=python,target=target,open_report=FALSE,
    run_command=run_command,choose=choose)
  report<-file.path(result$output_directory,filename)
  if(!file.exists(report))stop('The requested report was not produced; inspect the build messages.',call.=FALSE)
  if(open_report&&interactive())utils::browseURL(report)
  invisible(list(html=report,output_directory=result$output_directory))
}
)------------------------------------"

# Locate this saved entry point independently of RStudio's working directory.
ENTRY_SCRIPT <- local({
  paths<-as.character(unlist(lapply(sys.frames(),function(frame)if(is.character(frame$ofile))frame$ofile else character()),use.names=FALSE))
  paths<-paths[file.exists(paths)]
  if(length(paths))normalizePath(tail(paths,1L),winslash="/",mustWork=TRUE)else{
    arg<-grep("^--file=",base::commandArgs(FALSE),value=TRUE)
    if(length(arg))gsub("~+~"," ",sub("^--file=","",arg[1]),fixed=TRUE)else ""
  }
})
REPORT_WORKERS <- 1L
PYTHON_EXECUTABLE <- Sys.getenv("PYTHON",unset="auto")
REFERENCE_POLICY <- "strict"
OPEN_REPORT <- TRUE

launch_report <- function(script=ENTRY_SCRIPT,ir_file=IR_FILE,output=OUTPUT_DIRECTORY,
                          cores=REPORT_WORKERS,python=PYTHON_EXECUTABLE,
                          reference_policy=REFERENCE_POLICY,open_report=OPEN_REPORT) {
  setup_analysis_packages()
  if(!nzchar(script)||!file.exists(script))
    stop("Open the saved country script in RStudio and click Source.",call.=FALSE)
  startup<-new.env(parent=environment());eval(parse(text=STANDALONE_SUPPORT),envir=startup)
  runtime<-startup$dhs_country_runtime(script,COUNTRY);repo<-runtime$repo
  on.exit(if(runtime$temporary)unlink(repo,recursive=TRUE),add=TRUE)
  output<-startup$dhs_report_output(script,COUNTRY,output,force=runtime$temporary)
  shared<-new.env(parent=environment());sys.source(file.path(repo,'workflow.R'),envir=shared)
  register_analysis_survey_methods()
  entry<-file.path(repo,paste0(COUNTRY,'_analysis'),paste0(COUNTRY,'_final_html_analysis.R'))
  shared$dhs_run_report(entry,COUNTRY,ir_file,output,cores,python,reference_policy,open_report)
}

# Package installation/loading happens automatically when Source is clicked.
if(isTRUE(RUN_ON_SOURCE))setup_analysis_packages()

# Resolve a caller-selected DHS download without extracting unrelated files.
resolve_analysis_input <- function(input_file) {
  if(length(input_file)!=1L || is.na(input_file) || !nzchar(input_file) || !file.exists(input_file))
    stop('Select an existing DHS IR file or its Stata download ZIP.',call.=FALSE)
  input_file<-normalizePath(input_file,mustWork=TRUE)
  extension<-tolower(tools::file_ext(input_file))
  allowed<-if(COUNTRY=='Nigeria')c('dta','rds','zip')else c('dta','zip')
  if(!extension%in%allowed)
    stop('Select the original Stata IR (.dta) or a ZIP containing it.',call.=FALSE)
  if(extension!='zip')return(list(file=input_file,temporary_directory=NULL,archive=NULL))
  expected<-switch(COUNTRY,Ethiopia='ETIR8AFL.dta',Nigeria='NGIR8BFL.dta',DRC='CDIR81FL.dta')
  archive_sha<-digest::digest(file=input_file,algo='sha256')
  entries<-tryCatch(utils::unzip(input_file,list=TRUE),
    error=function(e)stop('Cannot read this ZIP. Select an intact DHS Stata download or the extracted IR.',call.=FALSE))
  index<-which(tolower(basename(gsub('\\\\','/',entries$Name)))==tolower(expected))
  if(length(index)!=1L)
    stop('The ZIP must contain exactly one ',expected,'. Select the corresponding DHS Stata IR download.',call.=FALSE)
  member<-entries$Name[index]
  if(grepl('(^[/\\\\]|^[A-Za-z]:|(^|[/\\\\])[.][.]([/\\\\]|$))',member))
    stop('The selected ZIP contains an unsafe member location; use the extracted IR instead.',call.=FALSE)
  directory<-tempfile('dhs-ir-');dir.create(directory)
  success<-FALSE
  on.exit(if(!success)unlink(directory,recursive=TRUE),add=TRUE)
  tryCatch(utils::unzip(input_file,files=member,exdir=directory,junkpaths=TRUE),
    error=function(e)stop('IR extraction failed. Extract the download yourself and select the .dta file.',call.=FALSE))
  selected<-file.path(directory,basename(gsub('\\\\','/',member)))
  if(!file.exists(selected)||file.info(selected)$size!=entries$Length[index])
    stop('IR extraction was incomplete. Select an intact extracted .dta file.',call.=FALSE)
  success<-TRUE
  list(file=selected,temporary_directory=directory,
       archive=list(sha256=archive_sha,selected_member=basename(selected),format='zip'),
       archive_file=input_file)
}

ANALYSIS_PLANNING_INPUTS <- c("02_nigeria_descriptive_analyses.R","12_nigeria_all_reason_bridge.R","15_nigeria_initiation_mix.R","70_modern_five_year_reasons.R","08_nigeria_population_and_planning.R","23_nigeria_current_user_switch_and_duration.R","91_nigeria_aft_switching_bridge.R")
ANALYSIS_NUMERICAL_MODULES <- c("03_nigeria_zone_models.R","04_nigeria_subgroups_and_tests.R","13_nigeria_all_reason_models.R","17_nigeria_selected_reason_models.R","26_nigeria_actionable_method_zone_models.R","29_zone_method_mix_decomposition.R","09_nigeria_post_discontinuation_pathways.R","34_nigeria_historical_current_user_pathways.R","37_nigeria_selected_reason_extensions.R","38_nigeria_other_reason_followup.R","40_nigeria_selected_current_user_planning.R","42_nigeria_crossvalidated_selected_risk_strata.R","analysis_all_reason_user_bridge.R","22_nigeria_landmark_support.R","25_duration_aware_cause_pp_tables.R","35_nigeria_alluvial_figures.R","202_nigeria_survey_coefficients.R")

# Run from R with result <- run_analysis(ir_file=..., output_dir=...).
# Only this country file and the authorized IR are needed for this numerical mode.
# Dependencies are R packages; no HTML, PowerPoint, Python or repository files are read.
run_analysis <- function(ir_file=Sys.getenv('DHS_IR_FILE', unset=''),
                         output_dir=Sys.getenv('DHS_ANALYSIS_OUTPUT', unset=''),
                         scope=c('all','planning','core'), replicates=500L,
                         cores=1L, analysis_replicates=NULL) {
  scope <- match.arg(scope)
  replicates <- as.integer(replicates); cores <- as.integer(cores)
  if(!is.null(analysis_replicates))analysis_replicates <- as.integer(analysis_replicates)
  if(length(replicates)!=1L || is.na(replicates) || replicates<0L || replicates==1L)
    stop('Use replicates=0 for point estimates or at least 2 for uncertainty.')
  if(replicates>0L && replicates<500L)
    warning('Fewer than 500 planning replicates: use for testing, not for the validated presentation intervals.',call.=FALSE)
  if(length(cores)!=1L || is.na(cores) || cores<1L)stop('cores must be positive.')
  if(!is.null(analysis_replicates) && (length(analysis_replicates)!=1L || is.na(analysis_replicates)||analysis_replicates<2L))
    stop('analysis_replicates must be NULL for validated module defaults or at least 2.')
  if(scope=='all' && !is.null(analysis_replicates) && analysis_replicates<1000L)
    stop('For scope=all, retain module defaults (analysis_replicates=NULL) or request at least 1000.')
  if(!nzchar(ir_file)||!file.exists(ir_file))stop('Supply the authorized IR file or Stata ZIP with ir_file or DHS_IR_FILE.')
  if(!nzchar(output_dir))stop('Supply a new private output_dir or DHS_ANALYSIS_OUTPUT.')
  if(dir.exists(output_dir)&&length(list.files(output_dir,all.files=TRUE,no..=TRUE)))
    stop('Use an empty output directory; this mode never imports earlier fitted results.')
  setup_analysis_packages()
  register_analysis_survey_methods()
  selected_input <- resolve_analysis_input(ir_file)
  if(!is.null(selected_input$temporary_directory))
    on.exit(unlink(selected_input$temporary_directory,recursive=TRUE),add=TRUE)
  ir_file <- selected_input$file
  dir.create(output_dir,recursive=TRUE,showWarnings=FALSE)
  output_dir <- normalizePath(output_dir,mustWork=TRUE)
  root <- file.path(output_dir,'work')
  extract_sources(root)
  result_dir <- file.path(output_dir,'results')
  dir.create(result_dir,recursive=TRUE,showWarnings=FALSE)
  env_names <- unique(c(paste0(toupper(COUNTRY),c('_PROJECT_ROOT','_INPUT_DIR','_IR_FILE')),
                        'DHS_IR_FILE','DHS_ANALYSIS_CORES','ANALYSIS_COUNTRY',BOOTSTRAP_ENV))
  old_env <- Sys.getenv(env_names,unset=NA_character_)
  on.exit({for(k in seq_along(env_names))if(is.na(old_env[k]))Sys.unsetenv(env_names[k])else
    do.call(Sys.setenv,setNames(list(old_env[k]),env_names[k]))},add=TRUE)
  do.call(Sys.setenv,setNames(list(root),paste0(toupper(COUNTRY),'_PROJECT_ROOT')))
  data_dir <- if(COUNTRY=='Nigeria')file.path(root,'Data/raw_dhs_ir')else file.path(root,'Data')
  do.call(Sys.setenv,setNames(list(data_dir),paste0(toupper(COUNTRY),'_INPUT_DIR')))
  Sys.setenv(DHS_IR_FILE=ir_file,ANALYSIS_COUNTRY=COUNTRY,DHS_ANALYSIS_CORES=as.character(cores))
  if(COUNTRY=='DRC')Sys.setenv(DRC_IR_FILE=ir_file)
  Sys.unsetenv(BOOTSTRAP_ENV)
  if(COUNTRY=='Ethiopia')Sys.setenv(BOOTSTRAP_REPS='300',REGIONAL_ACTIONABLE_BOOTSTRAP_REPS='500')
  if(!is.null(analysis_replicates))for(k in BOOTSTRAP_ENV)
    do.call(Sys.setenv,setNames(list(as.character(analysis_replicates)),k))
  # read_validated_ir() uses haven::read_dta() on the supplied Stata IR.
  validation <- read_validated_ir(ir_file)
  prepare_ir(root,ir_file)
  write_ir_validation(root,validation)
  ir_dimensions <- c(women=validation$rows,variables=validation$columns)
  input_sha256 <- validation$sha256
  rm(validation);invisible(gc())
  log_dir <- file.path(root,'output/logs');dir.create(log_dir,recursive=TRUE,showWarnings=FALSE)
  rscript <- file.path(R.home('bin'),'Rscript')
  completed <- character()
  run <- function(name,arguments=character()) {
    if(!name%in%names(MODULES)||MODULES[[name]]$language!='R')
      stop('Numerical R module is unavailable: ',name)
    cat('Running ',name,'\n',sep='');flush.console()
    log_file<-file.path(log_dir,paste0(name,'.log'))
    status<-system2(rscript,shQuote(c(file.path(root,'Code',name),arguments)),
                    stdout=log_file,stderr=log_file)
    txt<-readLines(log_file,warn=FALSE)
    txt<-gsub(ir_file,'<IR_FILE>',txt,fixed=TRUE)
    txt<-gsub(root,'<PROJECT_ROOT>',txt,fixed=TRUE)
    txt<-gsub(output_dir,'<OUTPUT_DIR>',txt,fixed=TRUE)
    writeLines(txt,log_file,useBytes=TRUE)
    if(status!=0L)stop('Analysis stopped in ',name,'. See work/output/logs/',basename(log_file),'.')
    completed<<-c(completed,name)
    invisible(NULL)
  }
  # Calendar reconstruction and analysis-specific cohorts are fresh IR-derived records.
  for(n in c(CORE_MODULES,'210_prepare_analysis_inputs.R'))run(n)
  validation <- read_validated_ir(ir_file)
  complete_preparation_audit(root,validation)
  rm(validation);invisible(gc())
  if(scope!='core')for(n in ANALYSIS_PLANNING_INPUTS)run(n)
  run('dhs_survey_descriptives.R')
  stats<-file.path(root,'output/survey_planning')
  if(scope!='core') {
    dir.create(stats,recursive=TRUE,showWarnings=FALSE)
    driver<-switch(COUNTRY,Ethiopia='planning_audit.R',Nigeria='310_nigeria_planning_audit.R',DRC='217_aft_transition_planning.R')
    run(driver,c(root,stats,as.character(replicates),as.character(cores)))
    if(replicates>0L) {
      draws<-readRDS(file.path(stats,'planning_replicates.rds'))
      if(length(draws)!=replicates||!all(vapply(draws,function(z)is.null(z$error),FALSE)))
        stop('Every requested survey replicate must succeed; no failed replicate is silently omitted.')
      if(COUNTRY=='Ethiopia') {
        run('analysis_planning_diagnostics.R',c(root,stats))
        run('summarize_planning.R',stats)
      }else{
        growth<-file.path(stats,'growth_assumptions.json')
        writeLines(REVISED_GROWTH_ASSUMPTIONS,growth,useBytes=TRUE)
        run('300_revised_planning.R',c(stats,growth,stats))
      }
    }
    if(COUNTRY!='Ethiopia')run('999_method_group_sensitivity.R',c(COUNTRY,root,file.path(root,'output/method_group_sensitivity')))
  }
  if(scope=='all') {
    for(n in ANALYSIS_NUMERICAL_MODULES)run(n)
  }
  if(scope=='all')run('dhs_survey_descriptives.R')
  if(scope=='all')run(if(COUNTRY=='DRC')'218_validate_aft_transitions.R'else'analysis_validate_transitions.R',
    c(root,stats,file.path(root,'output/validation/transitions')))
  result <- export_numerical_results(root,result_dir,scope,replicates)
  if(!identical(input_sha256,digest::digest(file=ir_file,algo='sha256')))
    stop('The supplied IR changed during analysis.')
  result$country<-COUNTRY;result$input_sha256<-input_sha256
  if(!is.null(selected_input$archive)){
    if(!identical(selected_input$archive$sha256,digest::digest(file=selected_input$archive_file,algo='sha256')))
      stop('The supplied ZIP changed during analysis.')
    result$input_archive<-selected_input$archive
  }
  result$input_dimensions<-ir_dimensions
  result$run_settings<-list(scope=scope,planning_replicates=replicates,
                            analysis_replicates=analysis_replicates,cores=cores)
  result$completed_modules<-completed
  result$software_versions<-data.frame(package=REQUIRED_R_PACKAGES,
    version=vapply(REQUIRED_R_PACKAGES,function(n)as.character(utils::packageVersion(n)),''))
  write.csv(result$software_versions,file.path(result_dir,'software_versions.csv'),row.names=FALSE)
  result$record_locations<-list(calendar='work/Data/Derived',individual_recode='work/Data',
                                numerical_sources='work/Code')
  saveRDS(result,file.path(result_dir,'analysis_results.rds'))
  write.csv(data.frame(module=completed),file.path(result_dir,'completed_modules.csv'),row.names=FALSE)
  writeLines(c(paste('Country:',COUNTRY),paste('Scope:',scope),
    paste('Planning replicates:',replicates),
    'analysis_results.rds contains the named result tables and aggregate planning objects.',
    'All primary CSV tables are in this results directory. Additional numerical outputs are in work/output/Supporting_data.',
    'The work/Data directory contains restricted derived records; keep the entire output directory private.',
    'No existing HTML, presentation, fitted-model cache or repository layout is used as an analytical input.'),
    file.path(result_dir,'README.txt'))
  if(!is.null(result$planning_overall)){cat('\nPotentially actionable endings and year-end losses:\n');print(result$planning_overall[c('approach','estimated_users','contribution_pp','users_ci_low','users_ci_high','pp_ci_low','pp_ci_high')],row.names=FALSE)}
  cat('\nNumerical analysis complete. Read the returned R list or results/analysis_results.rds.\n')
  invisible(result)
}

# Restore the protected survey methods when opening saved fitted objects in R.
register_analysis_survey_methods <- function() {
  helper <- new.env(parent=globalenv())
  eval(parse(text=MODULES[['dhs_survey_tools.R']]$code),envir=helper)
  registerS3method('vcov','dhs_multinom',helper$vcov.dhs_multinom,envir=asNamespace('stats'))
  registerS3method('summary','dhs_multinom',helper$summary.dhs_multinom,envir=asNamespace('base'))
  invisible(NULL)
}
load_analysis_results <- function(file) {
  setup_analysis_packages()
  register_analysis_survey_methods()
  readRDS(file)
}

# Adapt only execution mechanics; statistical formulas, cohorts and seeds stay intact.
portable_runtime_source <- function(code,language='R') {
  if(language!='R')return(code)
  code<-gsub('parallel::mclapply(','dhs_parallel_apply(',code,fixed=TRUE)
  code<-gsub('mclapply(','dhs_parallel_apply(',code,fixed=TRUE)
  prefix<-r"-----(# Portable argument handling and bootstrap worker scheduling.
commandArgs <- function(trailingOnly=FALSE) {
  args<-base::commandArgs(trailingOnly=trailingOnly)
  if(!trailingOnly){i<-startsWith(args,'--file=');args[i]<-gsub('~+~',' ',args[i],fixed=TRUE)}
  args
}
dhs_parallel_apply <- function(X,FUN,...,mc.preschedule=TRUE,mc.set.seed=TRUE,
    mc.silent=FALSE,mc.cores=1L,mc.cleanup=TRUE,mc.allow.recursive=TRUE,
    affinity.list=NULL) {
  limit<-suppressWarnings(as.integer(Sys.getenv('DHS_ANALYSIS_CORES',unset='1')))
  requested<-suppressWarnings(as.integer(mc.cores))
  if(length(limit)!=1L||is.na(limit)||limit<1L)limit<-1L
  if(length(requested)!=1L||is.na(requested)||requested<1L)requested<-1L
  use<-max(1L,min(requested,limit))
  if(.Platform$OS.type=='windows'||use==1L)return(lapply(X,FUN,...))
  parallel::mclapply(X,FUN,...,mc.preschedule=mc.preschedule,mc.set.seed=mc.set.seed,
    mc.silent=mc.silent,mc.cores=use,mc.cleanup=mc.cleanup,
    mc.allow.recursive=mc.allow.recursive,affinity.list=affinity.list)
}
)-----"
  paste0(prefix,'\n',code)
}
prepare_numerical_runtime <- function(root,cores=1L) {
  for(name in names(MODULES))writeLines(portable_runtime_source(MODULES[[name]]$code,
    MODULES[[name]]$language),file.path(root,'Code',name),useBytes=TRUE)
  manifest<-data.frame(module=names(MODULES),language=vapply(MODULES,function(z)z$language,''),
    sha256=vapply(names(MODULES),function(n)digest::digest(file=file.path(root,'Code',n),algo='sha256'),''))
  write.table(manifest,file.path(root,'Code/numerical_source_manifest.tsv'),sep='\t',quote=FALSE,row.names=FALSE)
  invisible(NULL)
}

export_numerical_results <- function(root,destination,scope,replicates) {
  support<-file.path(root,'output/Supporting_data')
  result<-list()
  files<-list.files(support,pattern='[.]csv$',recursive=TRUE,full.names=TRUE)
  # Analysis tables are freshly computed; documented population assumptions remain fixed inputs.
  # No report or previously fitted result is parsed to supply estimates.
  result$supporting_tables<-setNames(lapply(files,function(p)read.csv(p,check.names=FALSE)),
    make.unique(sub('[.]csv$','',substring(files,nchar(support)+2L))))
  direct<-list.files(file.path(root,'output'),pattern='[.]csv$',full.names=TRUE)
  result$analysis_tables<-setNames(lapply(direct,function(p)read.csv(p,check.names=FALSE)),
    sub('[.]csv$','',basename(direct)))
  checks<-list.files(file.path(root,'output/method_group_sensitivity'),pattern='[.]csv$',full.names=TRUE)
  result$method_group_checks<-setNames(lapply(checks,function(p)read.csv(p,check.names=FALSE)),
    sub('[.]csv$','',basename(checks)))
  from<-strsplit(normalizePath(destination,winslash='/',mustWork=TRUE),'/',fixed=TRUE)[[1]]
  to<-strsplit(normalizePath(root,winslash='/',mustWork=TRUE),'/',fixed=TRUE)[[1]]
  shared<-0L
  for(i in seq_len(min(length(from),length(to)))){
    same<-if(.Platform$OS.type=='windows')tolower(from[i])==tolower(to[i])else from[i]==to[i]
    if(!same)break
    shared<-i
  }
  parts<-c(rep('..',length(from)-shared),if(shared<length(to))to[seq.int(shared+1L,length(to))])
  root_prefix<-if(length(parts))paste0(paste(parts,collapse='/'),'/')else ''
  index<-function(tables,paths,collection){
    data.frame(collection=rep(collection,length(paths)),table=if(length(paths))names(tables)else character(),
      rows=vapply(tables,nrow,0L),columns=vapply(tables,ncol,0L),
      file=if(length(paths))paste0(root_prefix,substring(paths,nchar(root)+2L))else character())
  }
  result$table_index<-rbind(index(result$analysis_tables,direct,'analysis_tables'),
    index(result$supporting_tables,files,'supporting_tables'),
    index(result$method_group_checks,checks,'method_group_checks'))
  write.csv(result$table_index,file.path(destination,'table_index.csv'),row.names=FALSE)
  stats<-file.path(root,'output/survey_planning')
  if(scope=='core')return(result)
  p<-readRDS(file.path(stats,'planning_point.rds'));meta<-readRDS(file.path(stats,'planning_metadata.rds'))
  primary<-c('First-year: every actionable ending'=1L,'Historical: every actionable ending'=2L,
             'AFT: every actionable ending'=3L,'Historical + observed switching'=4L,
             'AFT + observed switching'=5L,'AFT + modeled switching'=9L)
  interval_id<-c(1L,2L,3L,4L,5L,12L)
  outcome<-meta[[paste0('wra',meta$outcome_year)]]
  baseline<-meta[[paste0('wra',meta$reference_year)]]
  interval_file<-file.path(stats,'planning_intervals.csv')
  # Full national builds place the freshly summarized intervals with their
  # planning tables; numerical-only builds summarize into the statistics folder.
  if(!file.exists(interval_file))interval_file<-file.path(root,'output/planning_tables/planning_intervals.csv')
  intervals<-if(replicates>0L)read.csv(interval_file)else NULL
  ci<-function(key){if(is.null(intervals))return(c(NA_real_,NA_real_));i<-match(key,intervals$key)
    if(is.na(i))stop('A requested interval is missing: ',key)
    row<-intervals[i,]
    if(grepl('^(count|pp)[|]',key) && max(abs(as.numeric(row[c('estimate','lower','upper')])))<1e-9)
      return(c(NA_real_,NA_real_))
    as.numeric(row[c('lower','upper')])}
  rows<-list()
  for(a in seq_along(primary))for(m in c(meta$methods,'Total'))for(ca in c(meta$causes,'Total')){
    mi<-if(m=='Total')seq_along(meta$methods)else match(m,meta$methods)
    cj<-if(ca=='Total')seq_along(meta$causes)else match(ca,meta$causes)
    n<-sum(p$counts[primary[a],mi,cj]);stock<-if(m=='Total')sum(p$stock[meta$methods])else p$stock[m]
    base_approach<-c(1L,2L,3L,2L,3L,3L)[a]
    original_endings<-sum(p$counts[base_approach,mi,cj])
    key<-paste(interval_id[a],m,ca,sep='|');nc<-ci(paste0('count|',key));pc<-ci(paste0('pp|',key))
    rows[[length(rows)+1L]]<-data.frame(approach=names(primary)[a],method=m,cause=ca,
      current_reversible_users=stock,estimated_users=n,
      actionable_ending_probability_pct=100*original_endings/stock,
      year_end_loss_probability_pct=if(a>3L)100*n/stock else NA_real_,
      original_method_endings=original_endings,
      modern_at_endpoint_after_ending=if(a>3L)original_endings-n else NA_real_,
      contribution_pp=100*n/outcome,users_ci_low=nc[1],users_ci_high=nc[2],
      pp_ci_low=pc[1],pp_ci_high=pc[2],outcome_year=meta$outcome_year,outcome_wra=outcome,
      definition=if(a<=3)'Every actionable original-method ending counted as lost'else
        'Actionable ending followed by absence from any modern method at the common next-12-month endpoint')
  }
  all<-do.call(rbind,rows)
  result$planning_by_method_cause<-all[all$method!='Total'&all$cause!='Total',]
  result$planning_by_method<-all[all$method!='Total'&all$cause=='Total',]
  result$planning_by_cause<-all[all$method=='Total'&all$cause!='Total',]
  result$planning_overall<-all[all$method=='Total'&all$cause=='Total',]
  if(COUNTRY=='Ethiopia'){
    rates<-c((22.7286887783964-28.1)/6,(22.7286887783964-24.9)/9,.7)
    labels<-c('6-year DHS trend','9-year DHS trend','FPET-informed growth')
  }else{
    growth<-jsonlite::fromJSON(REVISED_GROWTH_ASSUMPTIONS)
    rates<-growth$scenarios$annual_change_pp;labels<-growth$scenarios$scenario
  }
  scenario<-list();methods<-c(meta$methods,'EC','Permanent methods','Total')
  for(a in seq_along(primary))for(j in seq_along(rates))for(m in methods){
    usual<-p$mcpr+rates[j];mix<-if(m=='Total')1 else p$mix[m]
    add<-if(m=='Total')sum(p$counts[primary[a],,])else
      if(m%in%c('EC','Permanent methods'))0 else sum(p$counts[primary[a],m,])
    stock<-if(m=='Total')sum(p$stock)else p$stock[m]
    scenario[[length(scenario)+1L]]<-data.frame(approach=names(primary)[a],scenario=labels[j],
      annual_change_pp=rates[j],method=m,baseline_year=meta$reference_year,
      outcome_year=meta$outcome_year,baseline_wra=baseline,outcome_wra=outcome,
      baseline_users=stock,baseline_mcpr_pct=p$mcpr*mix,
      usual_users=usual/100*outcome*mix,usual_mcpr_pct=usual*mix,
      additional_users=add,contribution_pp=100*add/outcome,
      users_if_retained=usual/100*outcome*mix+add,mcpr_if_retained_pct=usual*mix+100*add/outcome)
  }
  scenario<-do.call(rbind,scenario)
  result$planning_scenarios<-scenario[scenario$method=='Total',]
  result$planning_method_scenarios<-scenario[scenario$method!='Total',]
  result$current_users<-data.frame(method=names(p$stock),estimated_users=as.numeric(p$stock),
                                   baseline_year=meta$reference_year,baseline_wra=baseline,
                                   prevalence_pct=100*as.numeric(p$stock)/baseline)
  result$planning_point<-p;result$planning_metadata<-meta
  result$transition_models<-readRDS(file.path(stats,'transition_point_fits.rds'))
  if(!is.null(intervals))result$planning_intervals<-intervals
  for(n in names(result))if(is.data.frame(result[[n]]))
    write.csv(result[[n]],file.path(destination,paste0(n,'.csv')),row.names=FALSE,na='')
  # Exact accounting checks are independent of HTML/PPTX reference values.
  stopifnot(all(is.finite(all$estimated_users)),all(all$estimated_users>=-1e-6),
    abs(sum(p$stock)-baseline*p$mcpr/100)<1e-5,
    all(abs(scenario$users_if_retained-scenario$usual_users-scenario$additional_users)<1e-5),
    all(abs(scenario$mcpr_if_retained_pct-scenario$usual_mcpr_pct-scenario$contribution_pp)<1e-10))
  for(a in names(primary)){
    v<-all[all$approach==a,];t<-v$estimated_users[v$method=='Total'&v$cause=='Total']
    stopifnot(abs(sum(v$estimated_users[v$method!='Total'&v$cause!='Total'])-t)<1e-5)
  }
  result
}

RECONCILIATION_CODE <- r"-----(#!/usr/bin/env python3
"""Reconcile saved HTML with aggregate numerical outputs, without editing it.

All locations are parameters. Saved-output matches are NOT fresh reproduction.
Inference about candidate sources never counts as end-to-end verification.
"""
import argparse,csv,hashlib,json,re,math
from pathlib import Path
from collections import Counter
from urllib.parse import unquote,urlsplit
from lxml import html


def norm(x):
    return re.sub(r'\s+',' ',str(x).replace('\u00a0',' ')).strip().casefold()

def variants(x):
    s=norm(x);out={s}
    try:
        v=float(s)
        if math.isfinite(v):
            for n in range(7):
                out.update((f'{v:.{n}f}',f'{v:,.{n}f}',f'{v:.{n}f}%'))
        else:out.update(('','—','–','na','nan'))
    except ValueError:pass
    return out

def table_rows(el):
    return [[norm(c.text_content()) for c in row.xpath('./th|./td')]
            for row in el.xpath('./thead/tr|./tbody/tr|./tr|./tfoot/tr')]

def csv_read(path):
    try:
        with path.open(encoding='utf-8-sig',newline='') as f:
            rows=list(csv.reader(f))
        return rows if rows and all(len(r)==len(rows[0]) for r in rows) else []
    except (UnicodeError,csv.Error):return []

def compare(a,b):
    if len(a)!=len(b):return False
    for x,y in zip(a,b):
        if len(x)!=len(y):return False
        for v,w in zip(x,y):
            if v==w:continue
            try:
                if math.isnan(float(v)) and math.isnan(float(w)):continue
                if math.isclose(float(v),float(w),rel_tol=1e-10,abs_tol=1e-10):continue
            except ValueError:pass
            return False
    return True

_indices={}
def candidate_rows(row,source):
    key=id(source)
    if key not in _indices:
        ix={}
        for i,r in enumerate(source[1:]):
            for t in set(norm(x) for x in r):
                if t and not re.fullmatch(r'[-+\d.eE,%]+',t):ix.setdefault(t,set()).add(i)
        _indices[key]=ix
    ix=_indices[key]
    available=[ix[t] for t in row if t in ix]
    return sorted(set.intersection(*available)) if available else range(len(source)-1)

def match_rows(body,source):
    """Require one consistent column projection and every displayed row.
    This is a candidate, not proof of the statistical meaning of a column.
    """
    data=source[1:]
    if not body or not data or any(len(r)!=len(body[0]) for r in body):return None
    if len(body[0])>len(source[0]):return None
    # Try source rows matching every first displayed cell; avoid one-number tables.
    if len(body[0])<2:return None
    poss=[]
    for ri in candidate_rows(body[0],source):
        row=data[ri]
        vs=[variants(x) for x in row]
        cols=[[i for i,v in enumerate(vs) if token in v] for token in body[0]]
        if all(cols):poss.append((ri,cols))
    if len(poss)>40:return None
    import itertools
    for ri,cols in poss:
        if math.prod(map(len,cols))>1000:continue
        for mapping in itertools.product(*cols):
            if len(set(mapping))<len(mapping):continue
            indices=[]
            for row in body:
                found=next((i for i in candidate_rows(row,source) if all(t in variants(data[i][j]) for t,j in zip(row,mapping))),None)
                if found is None:break
                indices.append(found)
            if len(indices)==len(body):return dict(columns=[source[0][j] for j in mapping],source_rows=[i+2 for i in indices])
    return None

def write_csv(path,rows,fields):
    with path.open('w',newline='',encoding='utf-8') as f:
        w=csv.DictWriter(f,fieldnames=fields);w.writeheader();w.writerows(rows)

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--country',required=True)
    ap.add_argument('--report-html',type=Path,required=True)
    ap.add_argument('--project-root',type=Path,required=True)
    ap.add_argument('--fresh-root',type=Path)
    ap.add_argument('--output-dir',type=Path,required=True)
    ap.add_argument('--strict',action='store_true')
    a=ap.parse_args();a.output_dir.mkdir(parents=True,exist_ok=True)
    doc=html.fromstring(a.report_html.read_text());sections=doc.xpath('//section')
    source_files=list((a.project_root/'output/Supporting_data').glob('*.csv'))
    saved={p.name:csv_read(p) for p in source_files}
    saved={n:r for n,r in saved.items() if r and len(r)<10000}
    compared={};fresh_rows=[]
    for name,rows in saved.items():
        fresh=a.fresh_root/'output/Supporting_data'/name if a.fresh_root else None
        status='not_recomputed'
        if fresh and fresh.exists():status='fresh_matches_saved' if compare(rows,csv_read(fresh)) else 'fresh_differs_from_saved'
        compared[name]=status
        fresh_rows.append(dict(file=name,status=status))
    inventory=[];bindings=[]
    for i,t in enumerate(doc.xpath('//table'),1):
        ancestors=t.xpath('ancestor::section[1]');sid=ancestors[0].get('id','') if ancestors else '(outside section)'
        rows=table_rows(t);body=rows[1:];tokens={x for r in body for x in r if x and not re.fullmatch(r'[\d.,%+−–—-]+',x)}
        candidates=[]
        if body and tokens:
            for name,src in saved.items():
                # Cheap filter on text labels before cell-by-cell checks.
                labels={norm(x) for row in src[1:] for x in row if not re.fullmatch(r'[-+\d.eE]+',x)}
                if not tokens.intersection(labels):continue
                binding=match_rows(body,src)
                if binding:candidates.append((name,binding))
        status='unmapped'
        if candidates:status='candidate_saved_output_match'
        inventory.append(dict(table=i,section=sid,rows=len(body),columns=len(rows[0]) if rows else 0,
                              status=status,candidate_sources='; '.join(n for n,_ in candidates),
                              fresh_candidate_matches=sum(compared[n]=='fresh_matches_saved' for n,_ in candidates)))
        bindings.append(dict(table=i,section=sid,candidates=[dict(file=n,**b) for n,b in candidates]))
    assets=[]
    for src in dict.fromkeys(doc.xpath('//img/@src')):
        u=urlsplit(src)
        if u.scheme or u.netloc:status='external_or_embedded';digest=''
        else:
            p=a.report_html.parent/unquote(u.path)
            status='present' if p.is_file() else 'missing'
            digest=hashlib.sha256(p.read_bytes()).hexdigest() if p.is_file() else ''
        assets.append(dict(asset=src,status=status,sha256=digest,recomputed='not_verified'))
    ids=Counter(doc.xpath('//@id'))
    issues=[]
    if a.country=='DRC':
        issues += [dict(section='method-duration-class-discontinuation',issue='The reviewed exploratory short-acting grouping contains pills and injectables. This is a country-specific grouping, not all short-acting modern methods.',status='documented_definition'),
                   dict(section='selected-reason-risk-strata',issue='The reviewed DRC risk-band diagnostic is in-sample; it is not the held-out prediction diagnostic used in Ethiopia.',status='documented_model_difference')]
    if a.country=='Nigeria':
        issues += [dict(section='regional-actionable-method-mix-decomposition',issue='The reviewed zone decomposition pools IUD with other modern and has its own cohort and estimator. It is distinct from Ethiopia pair-specific shared-mix standardization.',status='documented_model_difference')]
    summary=dict(country=a.country,report_sha256=hashlib.sha256(a.report_html.read_bytes()).hexdigest(),
      sections=len(sections),tables=len(inventory),images=len(assets),missing_images=sum(x['status']=='missing' for x in assets),
      table_candidate_matches=sum(bool(x['candidate_sources']) for x in inventory),
      fresh_outputs_matching=sum(v=='fresh_matches_saved' for v in compared.values()),
      fresh_outputs_differing=sum(v=='fresh_differs_from_saved' for v in compared.values()),
      duplicate_ids=[k for k,v in ids.items() if v>1],
      numerical_reproduction_complete=False,html_regeneration_complete=False,
      explanation='Candidate cell matches are provenance leads, not validation. Unmapped tables, figures, inference and scientific definitions still require review. No report was edited.')
    (a.output_dir/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
    (a.output_dir/'candidate_bindings.json').write_text(json.dumps(bindings,indent=2)+'\n')
    write_csv(a.output_dir/'tables.csv',inventory,['table','section','rows','columns','status','candidate_sources','fresh_candidate_matches'])
    write_csv(a.output_dir/'assets.csv',assets,['asset','status','sha256','recomputed'])
    write_csv(a.output_dir/'fresh_outputs.csv',fresh_rows,['file','status'])
    write_csv(a.output_dir/'definition_issues.csv',issues,['section','issue','status'])
    print(json.dumps(summary,indent=2))
    if a.strict:raise SystemExit(2)
if __name__=='__main__':main()
)-----"

COUNTRY <- "Nigeria"

REPORT_BASENAME <- "Nigeria_discontinuation_analysis.html"

REPORT_SHA256 <- "9681f56c3a79fa0ae8524667f018c6d208d5de812e0579d1b52eb633df857980"

RAW_RELATIVE <- "Data/raw_dhs_ir/NG2024DHS__NGIR8BDT__IR_raw.rds"

CORE_MODULES <- c("01_nigeria_calendar_life_table.R")

PLANNING_MODULES <- c("01_nigeria_calendar_life_table.R", "02_nigeria_descriptive_analyses.R", "08_nigeria_population_and_planning.R", "22_nigeria_landmark_support.R", "23_nigeria_current_user_switch_and_duration.R", "91_nigeria_aft_switching_bridge.R", "95_build_duration_planning_data.py")

BOOTSTRAP_ENV <- c("NIGERIA_PLANNING_BOOTSTRAP_REPS", "BOOTSTRAP_REPS", "NIGERIA_ALL_REASON_BOOTSTRAP_REPS", "NIGERIA_ALL_REASON_MODEL_BOOTSTRAP_REPS", "NIGERIA_BOOTSTRAP_REPS", "NIGERIA_METHOD_ZONE_REPS", "NIGERIA_MODEL_BOOTSTRAP_REPS", "NIGERIA_SELECTED_BOOTSTRAP_REPS", "NIGERIA_SELECTED_MODEL_BOOTSTRAP_REPS", "NIGERIA_SUBGROUP_BOOTSTRAP_REPS", "REFERENCE_BOOTSTRAP_REPS", "REFERENCE_MODEL_REPS", "RISK_STRATA_BOOTSTRAP_REPS")

SECTION_INDEX <- r"-----(section_id	title
methodology	What each probability measures
current-use	Current modern use and implications for user-loss planning
initiation	Entry methods set the denominator for future retention risk
dhs-712	The calendar reconstruction matches published Table 7.12
dhs-713	Reasons among recorded modern-method discontinuations
all-cause	All-reason discontinuation comes first
regional-method-paired-bars	Method starts and all-reason discontinuation by zone
all-reason-users	Illustrative current-user endings for all reasons
twelve-month-three-column-comparison	12-month discontinuation by method and reason definition
all-reason-transitions	What follows an all-reason discontinuation?
selected-reasons	The intermediate selected-reason measure
selected-models	Who is more likely to discontinue for a selected reason?
selected-reason-transitions	What follows discontinuation for a selected reason?
selected-followup	What happened after selected-reason discontinuation?
other-reasons-count-breakdown	What falls under “Other” reasons?
other-reason-followup	What follows an “Other” ending?
selected-reason-descriptive-subgroups	Unadjusted 12-month selected-reason discontinuation by subgroup
method-experience-subgroup-reasons	Method experience and access reasons within subgroups
top-three-reasons-by-subgroup-method	Top three actionable reasons by subgroup and method
selected-reason-risk-strata	Cross-validated lower, middle and higher risk bands
method-duration-class-discontinuation	Selected-reason risk by method-duration class
short-acting-selected-reason-distribution	Why short-acting modern methods ended within 12 months
selected-reason-regional-analysis	Selected-reason discontinuation across Nigeria’s six zones
selected-reason-regional-adjusted	Observed and adjusted 12-month probabilities by zone
selected-reason-regional-reason-heatmap	Reason mix among selected discontinuations by zone
regional-episode-mix-and-risk	Episode method mix and within-method selected-reason risk
national	Method starts and 12-month actionable risk
post-ending	Modern use after an actionable method ending
timing	Actionable discontinuation accumulates during the first year
zone-rates	Potentially actionable risk differs across the six zones
zone-reasons	The mix of actionable reasons varies by zone
method-mix	Entry method mix is different across the six zones
methods-by-zone	Within-method risk shows where method mix cannot explain the whole pattern
method-reasons	Reasons within each method and zone
action-pathways	From injectable endings to program action
models	Adjustment helps separate composition from zone differences
subgroups	Observed actionable risk by subgroup
pairwise	Which zone contrasts survive statistical testing?
method-zone-regressions	Within-method comparisons across Nigeria’s six zones
regional-actionable-method-mix-decomposition	How much of each zone gap reflects method mix?
regional-analyses	Regional analyses
population	Nigeria population and mCPR inputs
user-projections	Illustrative current-user method endings
current-user-reason-planning	Illustrative first-year method endings by selected reason
duration-adjusted-reason-planning	Next-year original-method endings among current users
standardized-current-users	Expected pathway among current modern users
mcpr-scenarios	Illustrative 2026 mCPR scenarios
method-level-mcpr-scenarios	2026 mCPR scenarios by current method
three-approach-planning	Three approaches to actionable discontinuation and mCPR
historical-duration-aware-planning	Historical duration-aware planning
aft-duration-aware-planning	AFT survival and observed pathways
duration-planning-appendix	Earlier switching and duration-aware analyses
switch-bridge	Direct modern switching reduces the gross user-loss illustration
duration-bridge	Accounting for elapsed use and modern status at year end
duration-aware-cause-pp-matrices	Actionable endings and year-end modern use: method by cause)-----"

stopifnot(getRversion() >= '4.0.0')

EXTERNAL_INPUTS <- list()

parse_options <- function(args) {
  out <- list(); i <- 1L
  while (i <= length(args)) {
    a <- args[i]
    if (!startsWith(a, '--')) stop('Expected a named --option.')
    a <- substring(a, 3L)
    if (grepl('=', a, fixed=TRUE)) {
      k <- sub('=.*$', '', a); out[[k]] <- substring(a, nchar(k) + 2L)
    } else if (a %in% c('list','validate','extract','overwrite','help','packages','reconcile','verify-planning','validate-input')) {
      out[[a]] <- TRUE
    } else {
      if (i == length(args)) stop('Missing option value.')
      i <- i + 1L; out[[a]] <- args[i]
    }
    i <- i + 1L
  }
  allowed <- c('list','validate','extract','overwrite','help','packages','run',
               'project-root','ir-file','auxiliary-dir','python','bootstrap-reps','reconcile','report-html','fresh-root','audit-output','verify-planning','expected-ir-sha256','validate-input','statistics-dir','base-html','revision-inputs','output-dir','replicates','cores','analysis-scope','analysis-replicates')
  if (length(setdiff(names(out), allowed))) stop('Unrecognized option.')
  out
}

list_modules <- function() {
  cat(COUNTRY, ': numerical modules accompanying ', REPORT_BASENAME, '\n', sep='')
  for (name in names(MODULES)) {
    cat(sprintf('  %-65s %s\n', name, MODULES[[name]]$language))
  }
  cat('\nCore alias: ', paste(CORE_MODULES, collapse=', '), '\n', sep='')
  cat('Use --run=filename or an ordered comma-separated list. Use --validate to parse all R sources.\n')
}

write_checked <- function(text, path, overwrite=FALSE) {
  dir.create(dirname(path), recursive=TRUE, showWarnings=FALSE)
  text <- sub('[\r\n]+$', '', text)
  if (file.exists(path)) {
    old <- paste(readLines(path, warn=FALSE, encoding='UTF-8'), collapse='\n')
    if (identical(sub('[\r\n]+$', '', old), text)) return(invisible(path))
    if (!overwrite) stop('Destination already contains a different file: ', basename(path),
                         '. Use a new project root or --overwrite.')
  }
  writeLines(enc2utf8(text), path, useBytes=TRUE)
  invisible(path)
}

extract_sources <- function(root, overwrite=FALSE, aux='') {
  dir.create(root, recursive=TRUE, showWarnings=FALSE)
  root <- normalizePath(root, mustWork=TRUE)
  for (name in names(MODULES)) {
    write_checked(portable_runtime_source(MODULES[[name]]$code,MODULES[[name]]$language), file.path(root,'Code',name), overwrite)
  }
  # User-supplied auxiliary inputs take precedence over frozen external inputs.
  if (nzchar(aux)) {
    if (!dir.exists(aux)) stop('Auxiliary input directory does not exist.')
    aux <- normalizePath(aux, mustWork=TRUE)
    files <- list.files(aux, recursive=TRUE, all.files=TRUE, full.names=FALSE,
                        include.dirs=FALSE, no..=TRUE)
    for (rel in files) {
      dest <- file.path(root,rel); src <- file.path(aux,rel)
      dir.create(dirname(dest), recursive=TRUE, showWarnings=FALSE)
      if (file.exists(dest) && !overwrite && tools::md5sum(src) != tools::md5sum(dest))
        stop('Different auxiliary destination exists: ', basename(dest))
      if (!file.exists(dest) || overwrite) {
        if (!file.copy(src,dest,overwrite=overwrite)) stop('Could not copy auxiliary file.')
      }
    }
  }
  for (rel in names(EXTERNAL_INPUTS)) {
    target <- file.path(root,rel)
    if (!file.exists(target)) write_checked(EXTERNAL_INPUTS[[rel]],target,FALSE)
  }
  dir.create(file.path(root,'output','Supporting_data'),recursive=TRUE,showWarnings=FALSE)
  dir.create(file.path(root,'Data','Derived'),recursive=TRUE,showWarnings=FALSE)
  write_checked(SECTION_INDEX, file.path(root,'Code','report_section_index.tsv'), overwrite)
  manifest <- data.frame(module=names(MODULES),
    language=vapply(MODULES,function(z)z$language,''),
    sha256=vapply(names(MODULES),function(n)digest::digest(file=file.path(root,'Code',n),algo='sha256'),''))
  write.table(manifest,file.path(root,'Code','numerical_source_manifest.tsv'),
              sep='\t',quote=FALSE,row.names=FALSE)
  root
}

prepare_ir <- function(root, ir_file) {
  if (!nzchar(ir_file)) return(invisible(NULL))
  if (!file.exists(ir_file)) stop('The supplied IR input file does not exist.')
  ir_file <- normalizePath(ir_file,mustWork=TRUE)
  ext <- tolower(tools::file_ext(ir_file))
  if (COUNTRY %in% c('Ethiopia','DRC') && ext != 'dta')
    stop('This country core uses a labelled Stata .dta IR input.')
  if (COUNTRY == 'Nigeria' && !ext %in% c('dta','rds'))
    stop('Nigeria IR input must be .dta or .rds.')
  if (COUNTRY == 'DRC') {
    Sys.setenv(DRC_IR_FILE=ir_file)
    return(invisible(NULL))
  }
  target <- file.path(root,RAW_RELATIVE)
  dir.create(dirname(target),recursive=TRUE,showWarnings=FALSE)
  if (COUNTRY == 'Nigeria' && ext == 'dta') {
    if (!requireNamespace('haven',quietly=TRUE)) stop('Install R package haven first.')
    incoming <- as.data.frame(haven::read_dta(ir_file))
    if (file.exists(target)) {
      if (!identical(readRDS(target), incoming)) stop('Cached IR differs from supplied IR.')
    } else saveRDS(incoming,target)
  } else if (file.exists(target)) {
    if (unname(tools::md5sum(target)) != unname(tools::md5sum(ir_file)))
      stop('Cached IR differs from supplied IR; choose a new project root.')
  } else if (!file.copy(ir_file,target,overwrite=FALSE)) stop('Could not stage supplied IR.')
  invisible(NULL)
}

run_full_rebuild <- function(opt,planning_only=FALSE) {
 f<-sub('^--file=','',grep('^--file=',commandArgs(FALSE),value=TRUE)[1])
 if(!file.exists(f))f<-gsub('~+~',' ',f,fixed=TRUE)
 repo<-dirname(dirname(normalizePath(f)))
 script<-file.path(repo,if(planning_only)'recompute_planning.R'else'build_reports.R')
 if(!file.exists(script))stop('Run from the complete repository, including the root build script and tools directory.')
 input<-if(!is.null(opt[['ir-file']]))opt[['ir-file']]else Sys.getenv('DHS_IR_FILE',unset='')
 if(!nzchar(input)||is.null(opt[['project-root']]))stop('A full rebuild requires --ir-file and a new --project-root output directory.')
 python<-if(!is.null(opt$python))opt$python else Sys.getenv('PYTHON',unset='auto')
 status<-system2(file.path(R.home('bin'),'Rscript'),shQuote(c(script,paste0('--country=',COUNTRY),paste0('--ir-file=',input),paste0('--output-dir=',opt[['project-root']]),paste0('--python=',python))))
 if(status!=0L)stop('The full raw-IR build failed. Inspect its runtime diagnostics.')
 invisible(NULL)
}

main <- function() {
  opt <- parse_options(commandArgs(trailingOnly=TRUE))
  if(isTRUE(opt$help)){
    cat(COUNTRY," national discontinuation analysis\n\n",sep="")
    cat("RStudio: open this script from the complete repository and click Source.\n")
    cat("Select the extracted IR .dta when asked; the workflow builds the national HTML.\n\n")
    cat("CLI full report, from the repository root:\nRscript build_reports.R --country=",COUNTRY,
      " --ir-file=INPUT --output-dir=NEW_PRIVATE_DIRECTORY\n\n",sep="")
    cat("Numerical results only, from the repository root:\nRscript ",COUNTRY,"_analysis/",COUNTRY,"_final_html_analysis.R --run=analysis --ir-file=INPUT --output-dir=NEW_PRIVATE_DIRECTORY --analysis-scope=all --replicates=500\n\n",sep="")
    cat("See README.md for Windows/macOS instructions. Advanced source inspection: --list or --validate.\n")
    return(invisible(NULL))
  }
  if(!length(opt)){
    report_results <- launch_report()
    assign('report_results',report_results,envir=.GlobalEnv)
    return(invisible(report_results))
  }
  if(identical(opt$run,'analysis') || (is.null(opt$run) && !is.null(opt[['ir-file']]) && !is.null(opt[['output-dir']]))) {
    return(run_analysis(ir_file=if(!is.null(opt[['ir-file']]))opt[['ir-file']]else Sys.getenv('DHS_IR_FILE',unset=''),
      output_dir=if(!is.null(opt[['output-dir']]))opt[['output-dir']]else Sys.getenv('DHS_ANALYSIS_OUTPUT',unset=''),
      scope=if(!is.null(opt[['analysis-scope']]))opt[['analysis-scope']]else'all',
      replicates=if(!is.null(opt$replicates))as.integer(opt$replicates)else 500L,
      cores=if(!is.null(opt$cores))as.integer(opt$cores)else 1L,
      analysis_replicates=if(!is.null(opt[['analysis-replicates']]))as.integer(opt[['analysis-replicates']])else NULL))
  }

  if(!is.null(opt$run) && opt$run %in% c('full','build-html'))return(run_full_rebuild(opt))
  if(identical(opt$run,'build-planning'))return(run_full_rebuild(opt,TRUE))
  if (!is.null(opt$run) && opt$run %in% c("revised-html","revised-planning")) return(run_revised_report(opt))
  if (isTRUE(opt$reconcile) || isTRUE(opt[['verify-planning']])) {
    if (is.null(opt[['report-html']]) || is.null(opt[['project-root']]))
      stop('Reconciliation requires --report-html and --project-root.')
    python <- if(!is.null(opt$python))opt$python else Sys.getenv('PYTHON',unset='python3')
    tmp <- tempfile(fileext='.py');on.exit(unlink(tmp),add=TRUE)
    writeLines(if(isTRUE(opt[['verify-planning']])) MODULES[['201_verify_planning_html.py']]$code else RECONCILIATION_CODE,tmp,useBytes=TRUE)
    dest <- if(!is.null(opt[['audit-output']]))opt[['audit-output']] else
      file.path(dirname(opt[['report-html']]),'reconciliation')
    args <- c(tmp,'--country',COUNTRY,'--report-html',opt[['report-html']],'--output-dir',dest)
    if(!isTRUE(opt[['verify-planning']]))args<-c(args,'--project-root',opt[['project-root']])
    if(isTRUE(opt[['verify-planning']]) && is.null(opt[['fresh-root']]))stop('Planning verification requires --fresh-root.')
    if(!is.null(opt[['fresh-root']]))args<-c(args,'--fresh-root',opt[['fresh-root']])
    result<-system2(python,shQuote(args))
    if(result!=0L)stop('Reconciliation audit failed.')
    return(invisible(NULL))
  }
  if (!length(opt) || isTRUE(opt$help)) {
    cat('Portable numerical source collection for ', COUNTRY, '.\n',sep='')
    cat('Options: --list, --validate, --validate-input, --packages, --extract, --run=core|planning|survey-update|reference|MODULE[,MODULE], --reconcile\n')
    cat('Inputs: --project-root, --ir-file, --auxiliary-dir; optional --expected-ir-sha256, --python and --bootstrap-reps.\n')
    cat('Use --run=analysis for the standalone numerical workflow; no analysis runs without inputs.\n')
    return(invisible(NULL))
  }
  if (isTRUE(opt$list)) list_modules()
  if (isTRUE(opt$packages)) cat(paste(REQUIRED_R_PACKAGES,collapse=', '),'\n')
  if (isTRUE(opt[['validate']])) {
    rnames <- names(MODULES)[vapply(MODULES,function(z)z$language=='R',FALSE)]
    for (name in rnames) {
      tryCatch(parse(text=MODULES[[name]]$code,keep.source=FALSE),
               error=function(e)stop('R parsing failed for ',name,': ',conditionMessage(e)))
    }
    cat('Parsed ',length(rnames),' embedded R modules successfully.\n',sep='')
  }
  if (!isTRUE(opt$extract) && is.null(opt$run) && !isTRUE(opt[['validate-input']])) return(invisible(NULL))
  setup_analysis_packages(packages=if(is.null(opt$run) && !isTRUE(opt[['validate-input']])) 'digest' else REQUIRED_R_PACKAGES)
  root <- if (!is.null(opt[['project-root']])) opt[['project-root']] else
    Sys.getenv('ANALYSIS_ROOT',unset=file.path('analysis_output',tolower(COUNTRY)))
  aux <- if (!is.null(opt[['auxiliary-dir']])) opt[['auxiliary-dir']] else ''
  if(!requireNamespace('digest',quietly=TRUE))stop('Install R package digest first.')
  root <- extract_sources(root,isTRUE(opt$overwrite),aux)
  do.call(Sys.setenv,setNames(list(root),paste0(toupper(COUNTRY),'_PROJECT_ROOT')))
  data <- if(COUNTRY=='Nigeria') file.path(root,'Data','raw_dhs_ir') else file.path(root,'Data')
  do.call(Sys.setenv,setNames(list(data),paste0(toupper(COUNTRY),'_INPUT_DIR')))
  ir <- if(!is.null(opt[['ir-file']])) opt[['ir-file']] else Sys.getenv('DHS_IR_FILE',unset='')
  if (nzchar(ir)) ir <- normalizePath(ir,mustWork=TRUE)
  validation <- NULL
  if (nzchar(ir)) {
    expected <- if(!is.null(opt[['expected-ir-sha256']]))opt[['expected-ir-sha256']]else''
    validation <- read_validated_ir(ir,expected)
  } else if (isTRUE(opt[['validate-input']]) || identical(opt$run,'prepare')) {
    stop('Supply --ir-file or DHS_IR_FILE for input preparation.',call.=FALSE)
  }
  prepare_ir(root,ir)
  if(!is.null(validation))write_ir_validation(root,validation)
  if(isTRUE(opt[['validate-input']]) && is.null(opt$run)) {
    cat('IR input validated; no analyses run.\n');return(invisible(NULL))
  }
  Sys.setenv(ANALYSIS_COUNTRY=COUNTRY)
  if(nzchar(ir)) Sys.setenv(DHS_IR_FILE=ir)
  if (!is.null(opt[['bootstrap-reps']])) {
    reps <- suppressWarnings(as.integer(opt[['bootstrap-reps']]))
    if (is.na(reps) || reps<1L) stop('bootstrap-reps must be a positive integer.')
    for (env in BOOTSTRAP_ENV) do.call(Sys.setenv,setNames(list(as.character(reps)),env))
  }
  cat('Extracted ',length(MODULES),' modules and the report section index.\n',sep='')
  if (is.null(opt$run)) return(invisible(NULL))
  selected <- strsplit(opt$run,',',fixed=TRUE)[[1]]
  preparing <- identical(selected,'prepare')
  if (preparing) selected <- c(CORE_MODULES,'210_prepare_analysis_inputs.R')
  if (identical(selected,'core')) selected <- CORE_MODULES
  if (identical(selected,'reference')) selected <- '200_reference_analysis_extensions.R'
  if (identical(selected,'planning')) selected <- PLANNING_MODULES
  if (identical(selected,'survey-update')) selected <- c('02_nigeria_descriptive_analyses.R','12_nigeria_all_reason_bridge.R','03_nigeria_zone_models.R','04_nigeria_subgroups_and_tests.R','13_nigeria_all_reason_models.R','17_nigeria_selected_reason_models.R','26_nigeria_actionable_method_zone_models.R','29_zone_method_mix_decomposition.R','37_nigeria_selected_reason_extensions.R','42_nigeria_crossvalidated_selected_risk_strata.R','203_nigeria_planning_survey_ci.R','204_summarize_planning.R')
  if (identical(selected,'survey-descriptives')) selected <- 'dhs_survey_descriptives.R'
  if (any(!selected %in% names(MODULES))) stop('Unknown module; use --list for filenames.')
  if (!nzchar(ir) && any(selected %in% CORE_MODULES))
    stop('Supply --ir-file or DHS_IR_FILE before running the core analysis.')
  python <- if (!is.null(opt$python)) opt$python else Sys.getenv('PYTHON',unset='python3')
  original_wd <- getwd(); on.exit(setwd(original_wd),add=TRUE)
  setwd(file.path(root,'Code'))
  log_dir <- file.path(root,'output','logs'); dir.create(log_dir,recursive=TRUE,showWarnings=FALSE)
  for (name in selected) {
    spec <- MODULES[[name]]
    exe <- if (spec$language=='R') file.path(R.home('bin'),'Rscript') else python
    argv <- c(shQuote(file.path(root,'Code',name)),spec$args)
    if ('--project-root' %in% spec$args) argv <- c(argv,shQuote(root))
    cat('Running ',name,'\n',sep='')
    log_file <- file.path(log_dir,paste0(name,'.log'))
    status <- system2(exe,argv,stdout=log_file,stderr=log_file)
    # Log paths are replaced with parameter labels; source-data rows are never printed here.
    log <- readLines(log_file,warn=FALSE)
    log <- gsub(root,'<PROJECT_ROOT>',log,fixed=TRUE)
    if (nzchar(ir)) log <- gsub(normalizePath(ir,mustWork=FALSE),'<IR_FILE>',log,fixed=TRUE)
    writeLines(log,log_file,useBytes=TRUE)
    if (!identical(status,0L)) stop('Module failed: ',name,'. See its log for missing inputs or model diagnostics.')
    cat('Completed ',name,'\n',sep='')
  }
  if(preparing) {
    if(!identical(digest::digest(file=ir,algo='sha256'),validation$sha256))
      stop('The source IR file changed during preparation.',call.=FALSE)
    complete_preparation_audit(root,validation)
  }
  invisible(NULL)
}

EXTERNAL_INPUTS[["output/Supporting_data/nigeria_wpp2024_wra_2024_2026.csv"]] <- r"-----(year,women_15_49,source
2024,55819549.5,"UN World Population Prospects 2024, female single ages, medium variant, 1 July"
2025,57393553.0,"UN World Population Prospects 2024, female single ages, medium variant, 1 July"
2026,59000784.5,"UN World Population Prospects 2024, female single ages, medium variant, 1 July"
)-----"

EXTERNAL_INPUTS[["output/Supporting_data/nigeria_published_table_7_13_reason_distribution.csv"]] <- r"-----(reason,IUD,Injectables,Implants,Pill,Male condom,Emergency contraception,Rhythm,Withdrawal,Other,All methods
Became pregnant while using,1.7,4.4,1.4,7.2,4.7,6.5,12.3,14.7,6.1,6.2
Wanted to become pregnant,35.6,34.7,41.8,27.7,28.4,26.5,49.1,39.3,24.2,34.0
Husband/partner disapproved,2.1,4.3,2.4,3.9,5.5,1.9,3.0,4.3,2.6,3.7
Wanted a more effective method,3.1,5.0,4.4,11.9,9.4,15.9,14.6,17.5,34.1,12.5
Changes in menstrual bleeding,2.7,16.7,10.9,10.4,0.1,3.8,1.3,0.4,4.0,8.0
Other side effects/health concerns,24.8,17.5,24.3,16.4,1.4,9.4,0.5,0.7,1.4,11.5
Lack of access/too far,0.0,2.3,0.7,2.7,2.0,2.4,1.4,0.5,0.8,1.5
Cost too much,0.0,1.4,0.4,2.5,0.7,0.3,0.0,0.0,0.0,0.8
Inconvenient to use,10.8,3.5,3.9,4.6,9.5,3.5,0.4,2.7,2.9,4.1
Up to God/fatalistic,1.8,1.3,0.4,0.7,1.5,1.6,0.3,2.2,5.3,1.7
Difficult to get pregnant/menopausal,5.6,0.0,0.1,0.5,0.4,0.0,0.9,0.9,0.4,0.4
Infrequent sex/husband away,5.5,4.3,2.4,9.1,27.8,22.4,12.9,13.8,9.6,10.1
Marital dissolution/separation,0.0,0.8,1.2,0.6,4.1,3.2,1.8,1.1,0.2,1.3
Other,6.2,3.1,4.1,1.1,2.5,0.6,0.7,1.5,7.7,3.2
Don’t know,0.0,0.5,0.8,0.5,1.2,0.5,0.3,0.4,0.3,0.6
Missing,0.0,0.3,0.6,0.1,0.7,1.4,0.4,0.0,0.3,0.4
)-----"

read_validated_ir <- function(ir_file, expected_sha256='') {
  for (pkg in c('haven','jsonlite','digest'))
    if (!requireNamespace(pkg, quietly=TRUE)) stop('Install required R package: ',pkg,call.=FALSE)
  if (!nzchar(ir_file) || !file.exists(ir_file))
    stop('Supply an existing authorized IR file with --ir-file or DHS_IR_FILE.',call.=FALSE)
  ext <- tolower(tools::file_ext(ir_file))
  allowed <- if(COUNTRY=='Ethiopia') 'dta' else c('dta','rds')
  if (!ext %in% allowed) stop('Unsupported input format for this country.',call.=FALSE)
  sha <- digest::digest(file=ir_file, algo='sha256')
  if (nzchar(expected_sha256) && (!grepl('^[a-fA-F0-9]{64}$',expected_sha256) ||
      !identical(tolower(expected_sha256),sha)))
    stop('Input SHA-256 does not match --expected-ir-sha256.',call.=FALSE)
  x <- tryCatch(if(ext=='dta') as.data.frame(haven::read_dta(ir_file)) else readRDS(ir_file),
    error=function(e)stop('Cannot read the supplied IR file; verify format and integrity.',call.=FALSE))
  if (!is.data.frame(x)) stop('IR input must be a woman-level data frame.',call.=FALSE)
  expected <- if(COUNTRY=='Ethiopia') c(21395L,6648L,797L,27L) else c(39050L,6411L,1380L,74L)
  required <- c('caseid','v000','v005','v008','v011','v012','v017','v018','v019',
                'v021','v022','v024','v025','v106','v190','v312','v313','v337',
                'v501','vcal_1','vcal_2')
  if(COUNTRY=='Nigeria') required<-c(required,'sstate')
  missing <- setdiff(required,names(x))
  if(length(missing))stop('Required IR variables missing: ',paste(missing,collapse=', '),call.=FALSE)
  if(anyDuplicated(names(x)) || anyDuplicated(x$caseid) || anyNA(x$caseid))
    stop('IR variables and woman identifiers must be unique and nonmissing.',call.=FALSE)
  if(nrow(x)!=expected[1] || ncol(x)!=expected[2])
    stop('IR dimensions differ from the validated country release; review before analysis.',call.=FALSE)
  num <- function(k)as.numeric(x[[k]])
  if(!all(as.character(x$v000)==if(COUNTRY=='Ethiopia')'ET8'else'NG8'))
    stop('Wrong country/recode phase.',call.=FALSE)
  keys<-c('v005','v008','v011','v012','v017','v018','v019','v021','v022','v024')
  if(any(vapply(keys,function(k)any(!is.finite(num(k))),FALSE)))
    stop('Nonfinite required dates, weights or survey-design fields.',call.=FALSE)
  stopifnot(all(num('v005')>0),all(num('v012')%in%15:49),
    all(num('v019')>=1 & num('v019')<=80),
    all(num('v008')-num('v017')+1==num('v019')),
    all(num('v018')+num('v019')==81),
    is.character(x$vcal_1),is.character(x$vcal_2),
    !anyNA(x$vcal_1),!anyNA(x$vcal_2),all(nchar(x$vcal_1)==80L),
    all(nchar(x$vcal_2)<=80L),length(grep('^b3_',names(x)))>0)
  f<-unique(data.frame(psu=num('v021'),stratum=num('v022')))
  stopifnot(nrow(f)==expected[3],length(unique(f$stratum))==expected[4],
    !anyDuplicated(f$psu),all(table(f$stratum)>1))
  if(COUNTRY=='Nigeria')stopifnot(all(num('v024')%in%1:6))
  # Never trim, reverse, filter or impute the raw input here.
  list(data=x,sha256=sha,format=ext,rows=nrow(x),columns=ncol(x),
       psus=nrow(f),strata=length(unique(f$stratum)))
}

write_ir_validation <- function(root, v) {
  dest<-file.path(root,'output','validation');dir.create(dest,recursive=TRUE,showWarnings=FALSE)
  fields<-list(country=COUNTRY,input_parameter='--ir-file or DHS_IR_FILE',
    format=v$format,sha256=v$sha256,women=v$rows,variables=v$columns,
    psus=v$psus,strata=v$strata,calendar_alignment='passed',unique_women='passed',
    source_file_modified=FALSE,api_used=FALSE,
    validated_utc=format(Sys.time(),'%Y-%m-%dT%H:%M:%SZ',tz='UTC'))
  jsonlite::write_json(fields,file.path(dest,'input_validation.json'),auto_unbox=TRUE,pretty=TRUE)
  packages<-c('haven','jsonlite','digest','survey','survival','nnet','ggplot2')
  vers<-vapply(packages,function(p)if(requireNamespace(p,quietly=TRUE))
    as.character(utils::packageVersion(p))else'not installed','')
  write.csv(data.frame(package=c('R',packages),version=c(as.character(getRversion()),vers)),
    file.path(dest,'software_versions.csv'),row.names=FALSE)
}

complete_preparation_audit <- function(root, v) {
  prefix<-if(COUNTRY=='Ethiopia')'ethiopia'else'nigeria'
  derived<-file.path(root,'Data','Derived')
  load<-function(name)readRDS(file.path(derived,name))
  events<-load(paste0(prefix,'_2024_calendar_events.rds'))
  ep<-load(if(COUNTRY=='Ethiopia')'ethiopia_2024_table_7_11_episodes.rds'else'nigeria_2024_table_7_12_episodes.rds')
  months<-load(paste0(prefix,'_2024_calendar_months.rds'))
  cov<-load(if(COUNTRY=='Ethiopia')'ethiopia_2024_full_model_episode_covariates.rds'else'nigeria_2024_model_episode_covariates.rds')
  person<-load(paste0(prefix,'_2024_person_month.rds'))
  frame<-load(paste0(prefix,'_2024_full_survey_frame.rds'))
  stopifnot(nrow(months)==sum(as.integer(v$data$v019)),
    nrow(months)==sum(events$duration),all(ep$entry<ep$exposure),
    all(ep$entry<12),!anyDuplicated(ep$episode_id),
    nrow(frame)==v$psus,length(unique(frame$stratum))==v$strata,
    all(ep$wt==as.numeric(v$data$v005[ep$woman_row])/1e6),
    sum(person$outcome=='actionable')>0,
    !anyNA(person[,c('wt','cluster','stratum','month','outcome')]))
  for_month<-if(COUNTRY=='Ethiopia')cov else cov
  stopifnot(nrow(person)==sum(pmin(12L,for_month$exposure)-for_month$entry))
  # Every retained episode-month uses the original woman's weight; other
  # endings remain competing events. Calendar nonuse is not a method episode.
  if(COUNTRY=='Ethiopia'){
    audit<-jsonlite::read_json(file.path(root,'output/Supporting_data/Table_7_11/table_7_11_results.json'))$audit
    stopifnot(audit$rate_cells_matching==66,audit$count_cells_matching==6,
      nrow(events)==89220,nrow(ep)==9068,nrow(cov)==8611,nrow(person)==70691,
      sum(person$outcome=='actionable')==1321)
    validated_cells<-66L;validated_counts<-6L
  }else{
    audit<-read.csv(file.path(root,'output/Supporting_data/nigeria_table_7_12_validation.csv'))
    stopifnot(sum(audit$rate_cells_matching)==110,all(audit$episode_count_matching),
      nrow(events)==163203,nrow(ep)==11210,nrow(cov)==8341,nrow(person)==69445)
    validated_cells<-110L;validated_counts<-10L
  }
  files<-list.files(derived,pattern='\\.rds$',full.names=TRUE)
  hashes<-data.frame(file=paste0('Data/Derived/',basename(files)),
    sha256=vapply(files,function(f)digest::digest(file=f,algo='sha256'),''))
  dest<-file.path(root,'output/validation')
  write.csv(hashes,file.path(dest,'derived_file_checksums.csv'),row.names=FALSE)
  result<-list(country=COUNTRY,input_sha256=v$sha256,
    calendar_runs=nrow(events),calendar_months=nrow(months),
    published_table_episodes=nrow(ep),model_episodes=nrow(cov),
    model_episode_months=nrow(person),psus=nrow(frame),strata=v$strata,
    dhs_rate_cells_matching=validated_cells,dhs_episode_counts_matching=validated_counts,
    input_preparation_complete=TRUE,full_html_regeneration=FALSE,
    html_and_pptx_modified=FALSE)
  jsonlite::write_json(result,file.path(dest,'preparation_validation.json'),
    auto_unbox=TRUE,pretty=TRUE,digits=15)
  cat('Preparation passed: ',nrow(events),' calendar runs; ',nrow(ep),
      ' published-table episodes; ',nrow(cov),' model episodes.\n',sep='')
}

REVISED_GROWTH_ASSUMPTIONS <- r"--------({
  "scenarios": [
    {
      "scenario": "6-year DHS trend",
      "annual_change_pp": 0.4318981911348668
    },
    {
      "scenario": "11-year DHS trend",
      "annual_change_pp": 0.1777353742882184
    },
    {
      "scenario": "FPET-informed growth",
      "annual_change_pp": 0.4
    }
  ],
  "rates_from": {
    "dhs2013": 11.149075984364499,
    "dhs2018": 10.5127759547257,
    "dhs2024": 13.104165101534901,
    "fpet2024": 13.2,
    "fpet2025": 13.6
  }
})--------"

REVISED_TABLE_SCHEMA <- r"--------([
  {
    "title": "First-year: actionable discontinuation and mCPR",
    "kind": "method",
    "approach": 1,
    "scenario": null
  },
  {
    "title": "First-year: users by method and cause",
    "kind": "cause",
    "approach": 1,
    "scenario": null
  },
  {
    "title": "First-year: mCPR growth scenarios",
    "kind": "baseline",
    "approach": 1,
    "scenario": 3
  },
  {
    "title": "First-year: mCPR if actionable losses are avoided",
    "kind": "scenario",
    "approach": 1,
    "scenario": 3
  },
  {
    "title": "First-year: 6-year DHS trend by method",
    "kind": "method_scenario",
    "approach": 1,
    "scenario": 1
  },
  {
    "title": "First-year: 11-year DHS trend by method",
    "kind": "method_scenario",
    "approach": 1,
    "scenario": 2
  },
  {
    "title": "First-year: FPET-informed growth by method",
    "kind": "method_scenario",
    "approach": 1,
    "scenario": 3
  },
  {
    "title": "First-year: mCPR equivalent by cause",
    "kind": "cause_pp",
    "approach": 1,
    "scenario": null
  },
  {
    "title": "Historical duration-aware: actionable discontinuation and mCPR",
    "kind": "method",
    "approach": 2,
    "scenario": null
  },
  {
    "title": "Historical duration-aware: users by method and cause",
    "kind": "cause",
    "approach": 2,
    "scenario": null
  },
  {
    "title": "Historical duration-aware: mCPR growth scenarios",
    "kind": "baseline",
    "approach": 2,
    "scenario": 3
  },
  {
    "title": "Historical duration-aware: mCPR if actionable losses are avoided",
    "kind": "scenario",
    "approach": 2,
    "scenario": 3
  },
  {
    "title": "Historical duration-aware: 6-year DHS trend by method",
    "kind": "method_scenario",
    "approach": 2,
    "scenario": 1
  },
  {
    "title": "Historical duration-aware: 11-year DHS trend by method",
    "kind": "method_scenario",
    "approach": 2,
    "scenario": 2
  },
  {
    "title": "Historical duration-aware: FPET-informed growth by method",
    "kind": "method_scenario",
    "approach": 2,
    "scenario": 3
  },
  {
    "title": "Historical duration-aware: mCPR equivalent by cause",
    "kind": "cause_pp",
    "approach": 2,
    "scenario": null
  },
  {
    "title": "AFT survival: actionable discontinuation and mCPR",
    "kind": "method",
    "approach": 3,
    "scenario": null
  },
  {
    "title": "AFT survival: users by method and cause",
    "kind": "cause",
    "approach": 3,
    "scenario": null
  },
  {
    "title": "AFT survival: mCPR growth scenarios",
    "kind": "baseline",
    "approach": 3,
    "scenario": 3
  },
  {
    "title": "AFT survival: mCPR if actionable losses are avoided",
    "kind": "scenario",
    "approach": 3,
    "scenario": 3
  },
  {
    "title": "AFT survival: 6-year DHS trend by method",
    "kind": "method_scenario",
    "approach": 3,
    "scenario": 1
  },
  {
    "title": "AFT survival: 11-year DHS trend by method",
    "kind": "method_scenario",
    "approach": 3,
    "scenario": 2
  },
  {
    "title": "AFT survival: FPET-informed growth by method",
    "kind": "method_scenario",
    "approach": 3,
    "scenario": 3
  },
  {
    "title": "AFT survival: mCPR equivalent by cause",
    "kind": "cause_pp",
    "approach": 3,
    "scenario": null
  },
  {
    "title": "Historical sensitivity: actionable discontinuation and mCPR",
    "kind": "method",
    "approach": 4,
    "scenario": null
  },
  {
    "title": "Historical sensitivity: users by method and cause",
    "kind": "cause",
    "approach": 4,
    "scenario": null
  },
  {
    "title": "Historical sensitivity: mCPR growth scenarios",
    "kind": "baseline",
    "approach": 4,
    "scenario": 3
  },
  {
    "title": "Historical sensitivity: mCPR if actionable losses are avoided",
    "kind": "scenario",
    "approach": 4,
    "scenario": 3
  },
  {
    "title": "Historical sensitivity: 6-year DHS trend by method",
    "kind": "method_scenario",
    "approach": 4,
    "scenario": 1
  },
  {
    "title": "Historical sensitivity: 11-year DHS trend by method",
    "kind": "method_scenario",
    "approach": 4,
    "scenario": 2
  },
  {
    "title": "Historical sensitivity: FPET-informed growth by method",
    "kind": "method_scenario",
    "approach": 4,
    "scenario": 3
  },
  {
    "title": "Historical sensitivity: mCPR equivalent by cause",
    "kind": "cause_pp",
    "approach": 4,
    "scenario": null
  },
  {
    "title": "AFT sensitivity: actionable discontinuation and mCPR",
    "kind": "method",
    "approach": 5,
    "scenario": null
  },
  {
    "title": "AFT sensitivity: users by method and cause",
    "kind": "cause",
    "approach": 5,
    "scenario": null
  },
  {
    "title": "AFT sensitivity: mCPR growth scenarios",
    "kind": "baseline",
    "approach": 5,
    "scenario": 3
  },
  {
    "title": "AFT sensitivity: mCPR if actionable losses are avoided",
    "kind": "scenario",
    "approach": 5,
    "scenario": 3
  },
  {
    "title": "AFT sensitivity: 6-year DHS trend by method",
    "kind": "method_scenario",
    "approach": 5,
    "scenario": 1
  },
  {
    "title": "AFT sensitivity: 11-year DHS trend by method",
    "kind": "method_scenario",
    "approach": 5,
    "scenario": 2
  },
  {
    "title": "AFT sensitivity: FPET-informed growth by method",
    "kind": "method_scenario",
    "approach": 5,
    "scenario": 3
  },
  {
    "title": "AFT sensitivity: mCPR equivalent by cause",
    "kind": "cause_pp",
    "approach": 5,
    "scenario": null
  }
])--------"

REVISION_HELPER_NAMES <- c("300_revised_planning.R", "301_revised_tables.py", "302_revised_html.py",
"303_validate_revised.py", "wording.py")

run_revised_report <- function(opt) {
  if (!requireNamespace("jsonlite",quietly=TRUE) || !requireNamespace("digest",quietly=TRUE))
    stop("Install jsonlite and digest.")
  root <- opt[["project-root"]]
  if (is.null(root)) root <- file.path("analysis_output",tolower(COUNTRY),"revised")
  dir.create(root,recursive=TRUE,showWarnings=FALSE);root<-normalizePath(root,mustWork=TRUE)
  script_arg<-grep("^--file=",commandArgs(),value=TRUE)
  script_folder<-if(length(script_arg))dirname(sub("^--file=","",script_arg[1]))else"."
  stats <- opt[["statistics-dir"]]
  if(is.null(stats))stats<-file.path(script_folder,"revision_inputs")
  if (is.null(stats)||!dir.exists(stats)) stop("Supply --statistics-dir with fitted point estimates and survey bootstrap draws.")
  stats<-normalizePath(stats,mustWork=TRUE)
  required<-c("planning_point.rds","planning_replicates.rds",if(COUNTRY=="Ethiopia")"metadata.json"else"planning_metadata.rds")
  if(COUNTRY=="Ethiopia")required<-c(required,"planning_intervals.csv")
  if(!all(file.exists(file.path(stats,required))))stop("The numerical input directory is incomplete.")
  if(length(readRDS(file.path(stats,"planning_replicates.rds")))!=500L)
    stop("The saved-report revision requires the validated 500-replicate numerical output.")
  build<-file.path(root,"build");result<-file.path(root,"output");code<-file.path(root,"Code")
  for(d in c(build,result,code))dir.create(d,recursive=TRUE,showWarnings=FALSE)
  for(n in names(REVISION_HELPERS))writeLines(REVISION_HELPERS[[n]],file.path(code,n),useBytes=TRUE)
  assumptions<-opt[["revision-inputs"]]
  if(is.null(assumptions)) {assumptions<-file.path(build,"growth_assumptions.json");writeLines(REVISED_GROWTH_ASSUMPTIONS,assumptions,useBytes=TRUE)}
  if(!file.exists(assumptions))stop("Revision assumptions file does not exist.")
  schema<-file.path(build,"table_schema.json");writeLines(REVISED_TABLE_SCHEMA,schema,useBytes=TRUE)
  python<-if(!is.null(opt$python))opt$python else Sys.getenv("PYTHON",unset="python3")
  run<-function(exe,args) {
    status<-system2(exe,shQuote(args))
    if(!identical(status,0L))stop("Revised build failed; no checked report was overwritten.")
  }
  run(file.path(R.home("bin"),"Rscript"),c(file.path(code,"300_revised_planning.R"),stats,assumptions,build))
  if(identical(opt$run,"revised-planning"))return(invisible(NULL))
  template<-opt[["base-html"]]
  if(is.null(template)) {
    template<-file.path(script_folder,REPORT_BASENAME)
  }
  if(!file.exists(template))stop("Supply --base-html with the latest validated report layout.")
  template<-normalizePath(template,mustWork=TRUE)
  target<-file.path(result,REPORT_BASENAME)
  if(identical(normalizePath(target,mustWork=FALSE),template))stop("Build output must differ from the input report.")
  run(python,c(file.path(code,"301_revised_tables.py"),build,schema,build))
  if(COUNTRY=="Ethiopia") {
    run(python,c(file.path(code,"302_revised_html.py"),build,schema,template,target))
  } else if(COUNTRY=="Nigeria") {
    run(python,c(file.path(code,"302_revised_html.py"),template,build,file.path(build,"planning_html.json"),target))
  } else {
    run(python,c(file.path(code,"302_revised_html.py"),template,template,build,file.path(build,"planning_html.json"),target))
  }
  run(python,c(file.path(code,"303_validate_revised.py"),COUNTRY,template,target,build,result))
  cat("Revised HTML build completed. Review output/revised_build_validation.json for its scope.\n")
}

REQUIRED_R_PACKAGES <- unique(c(REQUIRED_R_PACKAGES,"abind"))






run_revised_report <- function(opt) {
 if(!requireNamespace("jsonlite",quietly=TRUE)||!requireNamespace("digest",quietly=TRUE))stop("Install jsonlite and digest.")
 root<-if(!is.null(opt[["project-root"]]))opt[["project-root"]]else file.path("analysis_output","nigeria","updated")
 for(n in c("build","output","Code"))dir.create(file.path(root,n),recursive=TRUE,showWarnings=FALSE)
 script_arg<-grep("^--file=",commandArgs(),value=TRUE);folder<-if(length(script_arg))dirname(sub("^--file=","",script_arg[1]))else"."
 stats<-if(!is.null(opt[["statistics-dir"]]))opt[["statistics-dir"]]else file.path(folder,"revision_inputs")
 need<-c("planning_point.rds","planning_replicates.rds","planning_metadata.rds","transition_validation.json")
 if(!all(file.exists(file.path(stats,need))))stop("Supply the fitted numerical inputs, including the new transition sensitivity.")
 if(dim(readRDS(file.path(stats,"planning_point.rds"))$risk)[1]!=9L)stop("Expected nine risk components, including modeled transitions.")
 if(length(readRDS(file.path(stats,"planning_replicates.rds")))!=500L)stop("The report requires all 500 valid joint survey replicates.")
 code<-file.path(root,"Code");build<-file.path(root,"build");result<-file.path(root,"output")
 for(n in names(REVISION_HELPERS))writeLines(REVISION_HELPERS[[n]],file.path(code,n),useBytes=TRUE)
 file.copy(file.path(stats,"transition_validation.json"),file.path(build,"transition_validation.json"),overwrite=TRUE)
 assumptions<-opt[["revision-inputs"]];if(is.null(assumptions)){assumptions<-file.path(build,"growth_assumptions.json");writeLines(REVISED_GROWTH_ASSUMPTIONS,assumptions,useBytes=TRUE)}
 schema<-file.path(build,"original_table_schema.json");writeLines(REVISED_TABLE_SCHEMA,schema,useBytes=TRUE)
 python<-if(!is.null(opt$python))opt$python else Sys.getenv("PYTHON",unset="python3")
 run<-function(exe,a){status<-system2(exe,shQuote(a));if(status!=0L)stop("Report build failed.")}
 run(file.path(R.home("bin"),"Rscript"),c(file.path(code,"300_revised_planning.R"),stats,assumptions,build))
 run(python,c(file.path(code,"301_revised_tables.py"),build,schema,build))
 if(identical(opt$run,"revised-planning"))return(invisible(NULL))
 base<-if(!is.null(opt[["base-html"]]))opt[["base-html"]]else file.path(folder,REPORT_BASENAME)
 target<-file.path(result,REPORT_BASENAME)
 if(!file.exists(base))stop("Supply the validated HTML layout.")
 if(identical(normalizePath(base),normalizePath(target,mustWork=FALSE)))stop("Output must differ from the input report.")
 run(python,c(file.path(code,"302_revised_html.py"),base,build,file.path(build,"planning_html.json"),target))
 run(python,c(file.path(code,"303_validate_revised.py"),COUNTRY,base,target,build,result))
 cat("Rebuilt 48 planning tables and updated the companion diagnostics. Other chapters and figures retained.\n")
}

MODULES <- list()
MODULES[["200_reference_analysis_extensions.R"]] <- list(language="R", packaged_sha256="15ce23019c6dda0f20e2e02c759630f98f8daf3f2bd5669b7c105d61d7c3c3fb", args=character(0), code=r"----------------------(if(!requireNamespace('haven',quietly=TRUE))stop('Install R package haven first.')
# DHS complex survey design for this module.
.dhs_root <- Sys.getenv('NIGERIA_PROJECT_ROOT')
if (!nzchar(.dhs_root)) {
 .dhs_file <- sub('^--file=','',grep('^--file=',commandArgs(FALSE),value=TRUE)[1])
 .dhs_root <- dirname(dirname(normalizePath(.dhs_file)))
}
source(file.path(.dhs_root,'Code','dhs_survey_tools.R'),local=TRUE)
dhs_set_context(country='Nigeria',root=.dhs_root)
#!/usr/bin/env Rscript
# Reference-aligned numerical analyses for Ethiopia, Nigeria, and DRC.
# This module supplements the archived country modules; it never edits HTML/PPTX.
# Native calendar reason codes are used throughout, not the recoded nine groups.
# Statistical reference: the Ethiopia final HTML and its numerical source modules.
# Country differences in geography, source labels and population are retained.
# Run after the country's calendar module. Supply ANALYSIS_COUNTRY and its
# COUNTRY_PROJECT_ROOT; DHS_IR_FILE can override the staged IR input.
# REFERENCE_TASKS: descriptive,models,pathways (default: all three).
# REFERENCE_BOOTSTRAP_REPS and REFERENCE_MODEL_REPS default to 400.
# Fewer than 100 replicates is diagnostic only: no CIs or p-values are emitted.
# REFERENCE_MODEL_SPECS can select a comma-separated subset of model IDs below.
# Results go to output/reference_alignment, separately from existing report data.

country <- Sys.getenv('ANALYSIS_COUNTRY')
if (!country %in% c('Ethiopia','Nigeria','DRC')) stop('Set ANALYSIS_COUNTRY.')
root <- Sys.getenv(paste0(toupper(country),'_PROJECT_ROOT'))
if (!nzchar(root)) stop('Set the country project root.')
out <- file.path(root,'output','reference_alignment')
dir.create(out,recursive=TRUE,showWarnings=FALSE)
tasks <- strsplit(Sys.getenv('REFERENCE_TASKS','descriptive,models,pathways'),',',fixed=TRUE)[[1]]
if('risk_strata'%in%tasks)stop('The retired optional risk_strata task was removed. Use the country report risk-profile module instead.')
B <- as.integer(Sys.getenv('REFERENCE_BOOTSTRAP_REPS','400'))
MB <- as.integer(Sys.getenv('REFERENCE_MODEL_REPS','400'))
stopifnot(is.finite(B),B>=0,is.finite(MB),MB>=0)
emit <- function(x,name) write.csv(x,file.path(out,paste0(name,'.csv')),row.names=FALSE,na='')
input <- function(rel) file.path(root,rel)
config <- switch(country,
 Ethiopia=list(ir='Data/ET2024DHS__ETIR8ADT__IR_raw.rds',
  episodes='Data/Derived/ethiopia_2024_specified_modern_method_episodes.rds',
  calendar='Data/Derived/ethiopia_2024_calendar_events.rds'),
 Nigeria=list(ir='Data/raw_dhs_ir/NG2024DHS__NGIR8BDT__IR_raw.rds',
  episodes='Data/Derived/nigeria_2024_modern_episodes.rds',
  calendar='Data/Derived/nigeria_2024_calendar_events.rds'),
 DRC=list(ir='Data/CDIR81FL.dta',episodes='Data/Derived/drc_2023_24_modern_episodes.rds',
  calendar='Data/Derived/drc_2023_24_calendar_events.rds'))
ir_file <- Sys.getenv('DHS_IR_FILE',unset=Sys.getenv(paste0(toupper(country),'_IR_FILE'),unset=input(config$ir)))
ir <- if (tolower(tools::file_ext(ir_file))=='rds') readRDS(ir_file) else as.data.frame(haven::read_dta(ir_file))
e <- readRDS(input(config$episodes)); cal <- readRDS(input(config$calendar))
e <- e[e$method_code!=16L,] # EC is not a continuing-method risk denominator.
stopifnot(all(e$entry<e$exposure),all(e$wt>0),!anyNA(e$reason_code))
modern <- sort(unique(e$method_code))
method_name <- function(z) ifelse(z==3,'Injectables',ifelse(z==11,'Implants',
 ifelse(z==1,'Pill',ifelse(z==2,'IUD',ifelse(z==16,'EC','Other modern')))))
method_levels <- c('Injectables','Implants','Pill','IUD','Other modern')
cause_codes <- list('Method failure'=1L,'Wanted more effective method'=7L,
 'Changes in menstrual bleeding'=15L,'Other side effects/health'=c(4L,5L),
 'Access/cost/convenience'=c(6L,8L,10L))
actionable <- unlist(cause_codes,use.names=FALSE)
all_reason_codes <- c(cause_codes,list('Wanted pregnancy'=2L,'Partner disapproval'=3L,
 'Other fertility-related'=c(9L,12L,13L),
 'Other recorded'=c(0L,11L,96L,98L,99L)))
native_map <- c('1'=1L,'2'=2L,'3'=3L,'4'=4L,'5'=5L,'6'=6L,'7'=7L,'8'=8L,'9'=9L,
 'C'=10L,'F'=11L,'A'=12L,'D'=13L,'M'=15L,'W'=96L,'K'=98L,'?'=99L,' '=0L)
event_flag <- function(x,scope) switch(scope,all=rep(TRUE,nrow(x)),
 selected=!(x$reason_code %in% c(2L,3L)),actionable=x$reason_code %in% actionable)
e$method_group <- factor(method_name(e$method_code),levels=method_levels)
wi <- e$woman_row
e$stratum <- as.integer(ir$v022[wi]); e$cluster <- paste(e$stratum,as.integer(ir$v021[wi]),sep=':')
if(country=='Ethiopia') {
 region_labels <- c('1'='Tigray','2'='Afar','3'='Amhara','4'='Oromia','5'='Somali',
  '6'='Benishangul-Gumuz','7'='Central Ethiopia','8'='Sidama','9'='South West Ethiopia',
  '10'='South Ethiopia','12'='Gambella','13'='Harari','14'='Addis Ababa','15'='Dire Dawa')
 e$region <- factor(unname(region_labels[as.character(as.integer(ir$v024[wi]))]))
} else e$region <- factor(if(country=='DRC') as.character(e$province) else as.character(e$zone_name))
e$age_start <- floor((e$start-as.numeric(ir$v011[wi]))/12)
births <- as.matrix(ir[wi,grep('^b3_',names(ir),value=TRUE)])
e$parity_start <- rowSums(!is.na(births)&births<=e$start)
e$age <- cut(e$age_start,c(14,19,24,34,49),labels=c('15-19','20-24','25-34','35-49'))
e$parity <- factor(ifelse(e$parity_start==0,'0',ifelse(e$parity_start<=2,'1-2',
 ifelse(e$parity_start<=4,'3-4','5+'))),levels=c('0','1-2','3-4','5+'))
e$parity_legacy <- factor(ifelse(e$parity_start==0,'0',ifelse(e$parity_start<=2,'1-2',
 ifelse(e$parity_start==3,'3','4+'))),levels=c('0','1-2','3','4+'))
m <- as.integer(ir$v501[wi]); ed <- as.integer(ir$v106[wi]); w <- as.integer(ir$v190[wi]); res <- as.integer(ir$v025[wi])
e$marital <- factor(ifelse(m==0,'Never in union',ifelse(m==1,'Married',ifelse(m==2,
 'Living together',ifelse(m%in%3:5,'Formerly in union',NA)))),
 levels=c('Never in union','Living together','Married','Formerly in union'))
e$marital_legacy <- factor(ifelse(m==0,'Never in union',ifelse(m%in%c(1,2),
 'Married/living together',ifelse(m%in%3:5,'Formerly in union',NA))))
e$education <- factor(ifelse(ed==0,'None',ifelse(ed==1,'Primary',ifelse(ed%in%c(2,3),'Secondary+',NA))))
e$wealth <- factor(c('Poorest','Poorer','Middle','Richer','Richest')[w],
 levels=c('Poorest','Poorer','Middle','Richer','Richest'))
e$wealth_three <- factor(ifelse(w<=2,'Poorest 40%',ifelse(w==3,'Middle 20%','Richest 40%')),
 levels=c('Poorest 40%','Middle 20%','Richest 40%'))
e$residence <- factor(ifelse(res==1,'Urban',ifelse(res==2,'Rural',NA)),levels=c('Urban','Rural'))
e$start_year <- factor((e$start-1L)%/%12L+1900L)
e$duration_class <- ifelse(e$method_code%in%c(1L,3L,5L),'Short-acting reversible',
 ifelse(e$method_code%in%c(2L,11L),'Long-acting reversible','Other modern, mixed'))
covars <- c('age','parity','marital','education','wealth','residence','region','method_group','start_year','stratum','cluster')
complete <- complete.cases(e[,covars])
d <- droplevels(e[complete,])
emit(data.frame(country=country,full_modern_episodes=nrow(e),complete_age15_49_episodes=nrow(d),
 age_below15=sum(e$age_start<15,na.rm=TRUE),age_missing=sum(is.na(e$age_start)),
 other_missing=sum(!complete & !is.na(e$age)),late_entry_full=sum(e$entry>0),
 late_entry_complete=sum(d$entry>0),non_ec_modern_codes=paste(modern,collapse=',')), 'cohort_audit')
saveRDS(d,file.path(out,'reference_episode_covariates.rds'))

# Multiple-decrement life table: all endings reduce survival, whatever the
# selected cause. Do not delete competing endings from starting risk sets.
cif <- function(x,weights=x$wt,horizons=c(3L,6L,9L,12L),codes=all_reason_codes) {
 s<-1; val<-setNames(numeric(length(codes)),names(codes)); ans<-matrix(NA_real_,length(horizons),length(codes),dimnames=list(horizons,names(codes)))
 for(t in 1:max(horizons)) {
  at<-x$entry<t & x$exposure>=t;den<-sum(weights[at]);ended<-at & x$discontinued & x$exposure==t
  if(den<=0) {if(s>1e-12)break} else {
   for(j in seq_along(codes))val[j]<-val[j]+s*sum(weights[ended & x$reason_code%in%codes[[j]]])/den
   s<-s*(1-sum(weights[ended])/den)
  }
  if(t%in%horizons)ans[as.character(t),]<-100*val
 }
 ans
}
design <- function(x) {
 # Use the full IR frame, then map the current analytical rows into that frame.
 frame<-unique(data.frame(cluster=paste(as.integer(ir$v022),as.integer(ir$v021),sep=':'),
                          stratum=as.integer(ir$v022)))
 stopifnot(!anyNA(frame),all(table(frame$stratum)>1L))
 frame$id<-seq_len(nrow(frame));id<-match(x$cluster,frame$cluster)
 stopifnot(length(id)==nrow(x),!anyNA(id),all(x$stratum==frame$stratum[id]))
 list(frame=frame,groups=split(frame$id,frame$stratum),id=id)
}
resample_psu <- function(des,b) {
 set.seed(20261031L+b); mult<-numeric(nrow(des$frame))
 for(ids in des$groups) {
  n<-length(ids);stopifnot(n>1L);mult[ids]<-n/(n-1)*tabulate(sample.int(n,n-1,replace=TRUE),nbins=n)
 }
 mult
}
design_d<-design(d)
emit(data.frame(stratum=names(design_d$groups),psus=lengths(design_d$groups),
 singleton_treated_as_certainty=lengths(design_d$groups)==1L),'design_support')
ci <- function(z,nreps) if(nreps>=100 && sum(is.finite(z))>=max(80,.8*nreps))
 unname(quantile(z,c(.025,.975),na.rm=TRUE)) else c(NA_real_,NA_real_)

if('descriptive'%in%tasks) {
 scopes<-list('Overall::All modern'=seq_len(nrow(d)))
 for(v in c('age','parity','parity_legacy','marital','marital_legacy','education','wealth','wealth_three','residence','method_group','region','duration_class'))
  for(level in unique(as.character(d[[v]])))scopes[[paste(v,level,sep='::')]]<-which(d[[v]]==level)
 for(pair in list(c('age','parity'),c('age','method_group'),c('parity','method_group')))
  for(a in levels(d[[pair[1]]]))for(b in levels(d[[pair[2]]]))
   scopes[[paste('combination',pair[1],a,pair[2],b,sep='::')]]<-which(d[[pair[1]]]==a&d[[pair[2]]]==b)
 for(m in method_levels)for(v in c('age','parity','marital','education','wealth','residence','region'))
  for(level in levels(d[[v]]))scopes[[paste('method_subgroup',m,v,level,sep='::')]]<-which(d$method_group==m & d[[v]]==level)
 scopes<-scopes[lengths(scopes)>0]
 rows<-list();top<-list()
 for(key in names(scopes)) {
  x<-d[scopes[[key]],];z<-cif(x); events<-x$discontinued & x$entry<x$exposure & x$exposure<=12
  for(h in rownames(z)) {
   all<-sum(z[h,]);sel<-sum(z[h,!colnames(z)%in%c('Wanted pregnancy','Partner disapproval')]);act<-sum(z[h,names(cause_codes)])
   rows[[length(rows)+1L]]<-data.frame(scope=key,month=as.integer(h),episodes=nrow(x),weighted_episodes=sum(x$wt),
    selected_endings=sum(events & event_flag(x,'selected')),actionable_endings=sum(events & event_flag(x,'actionable')),
    all_reason_pct=all,selected_pct=sel,actionable_pct=act)
  }
  risks<-z['12',names(cause_codes)]; denom<-sum(risks)
  for(j in seq_along(risks))top[[length(top)+1L]]<-data.frame(scope=key,cause=names(risks)[j],
   cause_cif_pct=risks[j],share_of_actionable_cif_pct=if(is.finite(denom)&&denom>0)100*risks[j]/denom else NA_real_,
   rank=if(all(is.finite(risks)))rank(-risks,ties.method='first')[j] else NA_integer_,
   actionable_endings=sum(events & event_flag(x,'actionable')),withhold=sum(events & event_flag(x,'actionable'))<10,
   sparse=sum(events & event_flag(x,'actionable'))<30)
 }
 estimates<-do.call(rbind,rows);reason_table<-do.call(rbind,top)
 estimates$ci_low<-estimates$ci_high<-NA_real_;estimates$ci_outcome<-'selected';estimates$bootstrap_valid<-0L
 aggregate_keys<-names(scopes)[!grepl('^(combination|method_subgroup)::',names(scopes))]
 boots<-array(NA_real_,c(B,length(aggregate_keys),4),dimnames=list(NULL,aggregate_keys,c(3,6,9,12)))
 for(b in seq_len(B)) {
  weights<-d$wt*resample_psu(design_d,b)[design_d$id]
  for(key in aggregate_keys) {
   ix<-scopes[[key]];z<-cif(d[ix,],weights[ix]);boots[b,key,]<-rowSums(z[,!colnames(z)%in%c('Wanted pregnancy','Partner disapproval'),drop=FALSE])
  }
 }
 for(key in aggregate_keys)for(h in c(3,6,9,12)) {
  ix<-which(estimates$scope==key&estimates$month==h);z<-boots[,key,as.character(h)];bounds<-ci(z,B)
  estimates$ci_low[ix]<-bounds[1];estimates$ci_high[ix]<-bounds[2];estimates$bootstrap_valid[ix]<-sum(is.finite(z))
 }
 estimates$combination_display<-!grepl('^combination::',estimates$scope)|(estimates$episodes>=100 & estimates$selected_endings>=20)
 emit(estimates,'selected_subgroups_and_timepoints');emit(reason_table,'actionable_cause_risks_and_shares')
 emit(reason_table[reason_table$rank<=3 & !is.na(reason_table$rank),],'top_three_by_method_subgroup')
 # Full eligible modern episodes (including starts before age 15) for DHS-scope curves.
 fullscopes<-c(list(National=seq_len(nrow(e))),split(seq_len(nrow(e)),e$method_group),split(seq_len(nrow(e)),e$region))
 full<-do.call(rbind,lapply(names(fullscopes),function(key) {
  z<-cif(e[fullscopes[[key]],]);data.frame(scope=key,month=as.integer(rownames(z)),
   all_reason_pct=rowSums(z),selected_pct=rowSums(z[,!colnames(z)%in%c('Wanted pregnancy','Partner disapproval'),drop=FALSE]),
   actionable_pct=rowSums(z[,names(cause_codes),drop=FALSE]))
 }))
 emit(full,'full_modern_timepoints')
 # Five-year reason distribution: inspect v018 ... v018+59 directly, as the
 # reference table does. Do not substitute calendar run ends or the first year.
 rec<-list();k<-0L;chars<-strsplit('123456789WNALCFEMS~','')[[1]]
 for(i in seq_len(nrow(ir))) {
  pos<-as.integer(ir$v018[i])+0:59
  rc<-substring(sprintf('%-80s',ir$vcal_2[i]),pos,pos);mc<-substring(ir$vcal_1[i],pos,pos)
  methods<-match(mc,chars);reason<-unname(native_map[rc]);take<-rc!=' '&methods%in%modern&!is.na(reason)&reason>0
  if(any(take)){k<-k+1L;rec[[k]]<-data.frame(method=method_name(methods[take]),reason_code=reason[take],wt=as.numeric(ir$v005[i])/1e6)}
 }
 recorded<-do.call(rbind,rec);rr<-aggregate(wt~method+reason_code,recorded,sum)
 rr$share_pct<-100*rr$wt/ave(rr$wt,rr$method,FUN=sum);emit(rr,'five_year_recorded_reason_distribution')
 # Calendar observed starts are a separate denominator, retaining non-modern starts.
 starts<-cal[cal$method_code%in%1:18 & cal$start>cal$calendar_start &
  cal$interview-cal$start>=3 & cal$interview-cal$start<=62,]
 starts$method<-ifelse(starts$method_code%in%c(8,9),'Non-modern methods',method_name(starts$method_code))
 starts$region<-as.character(haven::as_factor(ir$v024[starts$woman_row]))
 mix<-aggregate(wt~region+method,starts,sum);mix$share_all_starts_pct<-100*mix$wt/ave(mix$wt,mix$region,FUN=sum)
 emit(mix,'initiation_mix_by_region')
}

person_months <- function(x,scope) {
 n<-pmax(0L,pmin(12L,x$exposure)-x$entry);idx<-rep(seq_len(nrow(x)),n)
 month<-unlist(Map(function(a,n)seq.int(a+1L,length.out=n),x$entry,n),use.names=FALSE)
 p<-x[idx,];p$episode_index<-idx;p$month<-factor(month,levels=1:12)
 ended<-x$discontinued[idx]&month==x$exposure[idx]
 p$outcome<-factor(ifelse(!ended,'continue',ifelse(event_flag(x,scope)[idx],'target','competing')),
  levels=if(scope=='all')c('continue','target') else c('continue','target','competing'))
 p
}
fit_model <- function(formula,p,w=p$wt) {
 p$fit_weight<-w
 fit<-dhs_multinom_fit(formula,data=p,weights=fit_weight,trace=FALSE,maxit=500,MaxNWts=30000,Hess=FALSE)
 if(fit$convergence!=0L)stop('Model did not converge')
 fit
}
risk_individual <- function(fit,x,horizon=12L) {
 s<-rep(1,nrow(x));v<-numeric(nrow(x))
 for(t in 1:horizon) {
  x$month<-factor(t,levels=1:12);p<-predict(fit,newdata=x,type='probs')
  if(is.null(dim(p))) {
   if(length(fit$lev)==2L)p<-cbind(continue=1-p,target=p) else
    p<-matrix(p,nrow=1,dimnames=list(NULL,fit$lev))
  }
  v<-v+s*p[,'target'];s<-s*p[,'continue']
 }
 100*v
}

# Model families retain the precise distinction between all/selected/actionable
# endings. Five wealth levels and the earlier three-level variant are separate.
specs<-list(
 all_full=list(scope='all',method=NULL,rhs='month+method_group+region+age+parity+marital+education+wealth+residence+start_year'),
 selected_legacy=list(scope='selected',method=NULL,rhs='month+method_group+region+age+parity_legacy+marital_legacy+education+wealth_three+residence+start_year'),
 selected_three_wealth=list(scope='selected',method=NULL,rhs='month+method_group+region+age+parity+marital+education+wealth_three+residence+start_year'),
 selected_full=list(scope='selected',method=NULL,rhs='month+method_group+region+age+parity+marital+education+wealth+residence+start_year'),
 selected_injectables=list(scope='selected',method='Injectables',rhs='month+region+age+parity+marital+education+wealth_three+residence+start_year'),
 selected_pill=list(scope='selected',method='Pill',rhs='month+region+age+parity+marital+education+wealth_three+residence+start_year'),
 actionable_method_mix=list(scope='actionable',method=NULL,rhs='month+method_group+region'),
 actionable_full=list(scope='actionable',method=NULL,rhs='month+method_group+region+age+parity+marital+education+wealth+residence+start_year'),
 actionable_injectables_duration=list(scope='actionable',method='Injectables',rhs='month+region'),
 actionable_implants_duration=list(scope='actionable',method='Implants',rhs='month+region'),
 actionable_injectables=list(scope='actionable',method='Injectables',rhs='month+region+age+parity+marital+education+wealth+residence+start_year'),
 actionable_implants=list(scope='actionable',method='Implants',rhs='month+region+age+parity+marital+education+wealth+residence+start_year'),
 actionable_interaction=list(scope='actionable',method=NULL,rhs='month+method_group*region+age+parity+marital+education+wealth+residence+start_year'))

if('models'%in%tasks) {
 requested<-strsplit(Sys.getenv('REFERENCE_MODEL_SPECS',paste(names(specs),collapse=',')),',',fixed=TRUE)[[1]]
 if(any(!requested%in%names(specs)))stop('Unknown reference model ID')
 status<-list()
 for(id in requested) {
  sp<-specs[[id]];x<-if(is.null(sp$method))d else droplevels(d[d$method_group==sp$method,])
  p<-person_months(x,sp$scope);f<-as.formula(paste('outcome~',sp$rhs))
  # Explicitly remove a constant covariate only when the country/method has no
  # variation. Record it as a non-estimable contrast, never an inferred effect.
  vars<-setdiff(all.vars(f),c('outcome','month'));constant<-vars[vapply(vars,function(v)length(unique(p[[v]]))<2,TRUE)]
  if(length(constant))for(v in constant)f<-update(f,paste('.~.-',v))
  fit<-tryCatch(fit_model(f,p),error=function(err)err)
  if(inherits(fit,'error')){status[[id]]<-data.frame(model=id,status='not_estimable',detail=conditionMessage(fit));next}
  ref<-x[x$entry==0,];regions<-levels(x$region);des<-design(x)
  beta<-coef(fit);if(is.null(dim(beta)))beta<-matrix(beta,nrow=1,dimnames=list('target',names(beta)))
  coeff<-data.frame(outcome=rep(rownames(beta),each=ncol(beta)),term=rep(colnames(beta),times=nrow(beta)),
   log_odds=as.vector(t(beta)),odds_ratio=exp(as.vector(t(beta))))
  coeff$ci_low<-coeff$ci_high<-coeff$p_value<-NA_real_
  predict_region<-function(model,weights=ref$wt,own=FALSE){
   vapply(c('National',regions),function(r){
    take<-if(own && r!='National')which(ref$region==r) else seq_len(nrow(ref));z<-ref[take,]
    if(!nrow(z)||sum(weights[take])<=0)return(NA_real_)
    if(r!='National')z$region<-factor(r,levels=regions)
    weighted.mean(risk_individual(model,z),weights[take])
   },0.0)
  }
  point<-predict_region(fit);own<-predict_region(fit,own=TRUE)
  bounds<-matrix(NA_real_,MB,length(point));betaboot<-matrix(NA_real_,MB,nrow(coeff))
  pairs<-combn(regions,2,simplify=FALSE)
  # Model-1 symmetric pair mix: five method categories, observed-start shares.
  mixcalc<-function(model,weights=ref$wt){
   methods<-levels(x$method_group);share<-risk<-matrix(0,length(regions),length(methods),dimnames=list(regions,methods))
   for(r in regions)for(m in methods){
    share[r,m]<-sum(weights[ref$region==r & ref$method_group==m]);z<-ref[1,,drop=FALSE]
    z$region<-factor(r,levels=regions);z$method_group<-factor(m,levels=methods)
    risk[r,m]<-risk_individual(model,z)
   }
   share<-share/rowSums(share)
   ans<-do.call(rbind,lapply(pairs,function(ab){a<-ab[1];b<-ab[2];common<-(share[a,]+share[b,])/2
    ga<-sum(common*risk[a,]);gb<-sum(common*risk[b,]);own_gap<-sum(share[a,]*risk[a,])-sum(share[b,]*risk[b,])
    data.frame(region_a=a,region_b=b,shared_a_pct=ga,shared_b_pct=gb,shared_gap_pp=ga-gb,
     own_modeled_gap_pp=own_gap,mix_component_pp=own_gap-(ga-gb))}))
   list(table=ans,share=share,risk=risk)
  }
  mixpoint<-if(id=='actionable_method_mix')mixcalc(fit) else NULL
  mixboot<-matrix(NA_real_,MB,length(pairs))
  for(b in seq_len(MB)) {
   mult<-resample_psu(des,b);ww<-x$wt*mult[des$id];pw<-ww[p$episode_index];rw<-ww[x$entry==0]
   fm<-tryCatch(fit_model(f,p,pw),error=function(err)NULL)
   if(is.null(fm))next
   bounds[b,]<-tryCatch(predict_region(fm,rw),error=function(err)rep(NA_real_,length(point)))
   bb<-coef(fm);if(is.null(dim(bb)))bb<-matrix(bb,nrow=1,dimnames=list('target',names(bb)))
   if(identical(dimnames(bb),dimnames(beta)))betaboot[b,]<-as.vector(t(bb))
   if(!is.null(mixpoint))mixboot[b,]<-tryCatch(mixcalc(fm,rw)$table$shared_gap_pp,error=function(err)rep(NA_real_,length(pairs)))
  }
  margins<-data.frame(region=names(point),common_profile_pct=as.numeric(point),own_profile_pct=as.numeric(own),
   ci_low=apply(bounds,2,function(z)ci(z,MB)[1]),ci_high=apply(bounds,2,function(z)ci(z,MB)[2]),
   valid_bootstrap=colSums(is.finite(bounds)),bootstrap_reps=MB)
  margins$episodes<-vapply(margins$region,function(r)sum(r=='National'|as.character(x$region)==r),0L)
  margins$target_events<-vapply(margins$region,function(r)sum((r=='National'|as.character(x$region)==r)&x$discontinued&x$exposure<=12&event_flag(x,sp$scope)),0L)
  margins$sparse<-margins$target_events<30
  emit(margins,paste0(id,'_regional_probabilities'))
  contrasts<-do.call(rbind,lapply(seq_along(pairs),function(k){a<-pairs[[k]][1];b<-pairs[[k]][2]
   dif<-point[a]-point[b];z<-bounds[,match(a,names(point))]-bounds[,match(b,names(point))];qq<-ci(z,MB)
   data.frame(region_a=a,region_b=b,difference_pp=unname(dif),ci_low=qq[1],ci_high=qq[2],
    p_value=if(all(is.finite(qq)))2*pnorm(-abs(dif/sd(z,na.rm=TRUE))) else NA_real_,
    sparse=any(margins$sparse[margins$region%in%c(a,b)]))}))
  contrasts$holm_p<-p.adjust(contrasts$p_value,method='holm');contrasts$significant_05<-contrasts$holm_p<.05
  contrasts$significant_10<-contrasts$holm_p<.10;emit(contrasts,paste0(id,'_pairwise'))
  for(j in seq_len(nrow(coeff))){qq<-ci(betaboot[,j],MB);coeff$ci_low[j]<-exp(qq[1]);coeff$ci_high[j]<-exp(qq[2]);
   if(all(is.finite(qq)))coeff$p_value[j]<-2*pnorm(-abs(coeff$log_odds[j]/sd(betaboot[,j],na.rm=TRUE)))}
  coeff$precision_flag<-!is.finite(coeff$odds_ratio)|abs(coeff$log_odds)>10
  emit(coeff,paste0(id,'_coefficients'))
  # Covariate probabilities are point estimates; uncertainty is explicitly
  # restricted to region and coefficients in this extension.
  profile<-list()
  for(v in setdiff(all.vars(f),c('outcome','month','start_year','region')))for(lev in levels(ref[[v]])) {
   z<-ref;z[[v]]<-factor(lev,levels=levels(ref[[v]]));profile[[length(profile)+1L]]<-data.frame(covariate=v,category=lev,
    adjusted_pct=weighted.mean(risk_individual(fit,z),ref$wt),episodes=sum(x[[v]]==lev),
    target_events=sum(x[[v]]==lev & x$discontinued & x$exposure<=12 & event_flag(x,sp$scope)))
  }
  if(length(profile))emit(do.call(rbind,profile),paste0(id,'_subgroup_probabilities'))
  if(!is.null(mixpoint)) {
   mt<-mixpoint$table;mt$ci_low<-apply(mixboot,2,function(z)ci(z,MB)[1]);mt$ci_high<-apply(mixboot,2,function(z)ci(z,MB)[2])
   mt$p_value<-vapply(seq_len(nrow(mt)),function(j)if(is.finite(mt$ci_low[j]))2*pnorm(-abs(mt$shared_gap_pp[j]/sd(mixboot[,j],na.rm=TRUE))) else NA_real_,0.0)
   mt$holm_p<-p.adjust(mt$p_value,method='holm');emit(mt,'pair_specific_shared_method_mix')
   emit(data.frame(region=rep(rownames(mixpoint$share),each=ncol(mixpoint$share)),method=rep(colnames(mixpoint$share),nrow(mixpoint$share)),
    observed_start_share=as.vector(t(mixpoint$share)),method_specific_predicted_pct=as.vector(t(mixpoint$risk))),'shared_mix_cells')
  }
  status[[id]]<-data.frame(model=id,status='estimated',detail=paste('Formula:',paste(deparse(f),collapse=' '),
   '; constant terms omitted:',paste(constant,collapse=','),'; bootstrap replicates:',MB))
  saveRDS(fit,file.path(out,paste0(id,'_fit.rds')))
 }
 emit(do.call(rbind,status),'model_execution_status')
}

if('pathways'%in%tasks) {
 # Common 12-month observable cohort; the same endings appear at months 1/3/12.
 ends<-e[e$discontinued & e$exposure<=12 & e$end+12<=e$interview-3,]
 state<-function(code,original)ifelse(code==original,'Same original method',ifelse(code%in%modern,
  'Other continuing modern method',ifelse(code==16,'EC',ifelse(code%in%c(8,9),
  'Traditional method',ifelse(code%in%c(81,82,83),'Pregnancy/birth/termination','No method')))))
 codes_at<-function(w,cmc) {
  pos<-as.integer(ir$v018[w])+as.integer(ir$v008[w])-cmc
  cc<-substring(ir$vcal_1[w],pos,pos);mc<-match(cc,strsplit('123456789WNALCFEMS~','')[[1]])
  mc[cc=='0']<-0;mc[cc=='B']<-81;mc[cc=='T']<-82;mc[cc=='P']<-83;mc
 }
 for(t in c(1,3,12))ends[[paste0('month',t)]]<-state(codes_at(ends$woman_row,ends$end+t),ends$method_code)
 flows<-list();dist<-list()
 for(scope in c('all','selected','actionable')) {
  z<-ends[event_flag(ends,scope),];z$method<-as.character(z$method_group)
  for(m in c('All modern',method_levels)) {
   a<-if(m=='All modern')z else z[z$method==m,];if(!nrow(a))next
   f<-aggregate(wt~month1+month3+month12,a,sum);f$scope<-scope;f$method<-m;f$share_pct<-100*f$wt/sum(a$wt)
   flows[[length(flows)+1L]]<-f
   for(t in c(1,3,12)){r<-aggregate(a$wt,list(state=a[[paste0('month',t)]]),sum);names(r)[2]<-'weight'
    r$scope<-scope;r$method<-m;r$month<-t;r$share_pct<-100*r$weight/sum(a$wt);dist[[length(dist)+1L]]<-r}
  }
 }
 emit(do.call(rbind,flows),'post_ending_alluvial_flows');emit(do.call(rbind,dist),'post_ending_states')
 # Historical 15-month landmark, two duration bands, selected ending by reason:
 # the early Ethiopia planning analysis. A different multi-landmark, finer-band
 # analysis is preserved in the original duration-aware modules.
 landmarks<-list();chars<-strsplit('123456789WNALCFEMS~','')[[1]]
 for(i in seq_len(nrow(ir))) {
  p<-as.integer(ir$v018[i])+15L;if(p>80)next
  orig<-substring(ir$vcal_1[i],p,p);mc<-match(orig,chars);if(!mc%in%modern || mc%in%c(6L,7L))next
  dur<-1L;while(p+dur<=80 && substring(ir$vcal_1[i],p+dur,p+dur)==orig)dur<-dur+1L
  after<-substring(ir$vcal_1[i],p-1:12,p-1:12);change<-which(after!=orig)
  event<-if(length(change))min(change) else NA_integer_
  # Nonblank reason at a same-method month is also a recorded ending.
  reasonchars<-substring(sprintf('%-80s',ir$vcal_2[i]),p-0:11,p-0:11)
  recorded<-which(reasonchars!=' ')
  if(length(recorded))event<-min(c(event,recorded),na.rm=TRUE)
  reason<-if(is.na(event))NA_integer_ else unname(native_map[reasonchars[event]])
  if(!is.na(event)&&is.na(reason))reason<-99L
  landmarks[[length(landmarks)+1L]]<-data.frame(woman_row=i,method=method_name(mc),duration=dur,
   duration_band=ifelse(dur<=12,'0-12','13+'),wt=as.numeric(ir$v005[i])/1e6,
   reason_code=reason,month12_modern=match(after[12],chars)%in%c(modern,16L))
 }
 land<-do.call(rbind,landmarks);current<-data.frame(method=method_name(as.integer(ir$v312)),
  duration=as.numeric(ir$v337),wt=as.numeric(ir$v005)/1e6,modern=as.integer(ir$v313)==3 & as.integer(ir$v312)%in%setdiff(modern,c(6L,7L)))
 current<-current[current$modern & is.finite(current$duration)&current$duration<997,]
 current$duration_band<-ifelse(current$duration<=12,'0-12','13+')
 probs<-list()
 for(m in method_levels)for(band in c('0-12','13+')) {
  z<-land[land$method==m & land$duration_band==band,];cur<-current[current$method==m,]
  share<-if(nrow(cur))sum(cur$wt[cur$duration_band==band])/sum(cur$wt) else NA_real_
  for(reason in names(all_reason_codes))probs[[length(probs)+1L]]<-data.frame(method=m,duration_band=band,reason=reason,
   historical_women=nrow(z),current_duration_share=share,
   ending_probability=if(nrow(z))sum(z$wt[!is.na(z$reason_code)&z$reason_code%in%all_reason_codes[[reason]]])/sum(z$wt) else NA_real_)
 }
 probs<-do.call(rbind,probs);probs$standardized_contribution<-probs$current_duration_share*probs$ending_probability
 emit(probs,'fixed_landmark_selected_reason_planning')
 agg<-aggregate(standardized_contribution~method+reason,probs,sum,na.action=na.pass)
 emit(agg,'fixed_landmark_method_reason_probabilities')
}
emit(data.frame(country=country,tasks=paste(tasks,collapse=','),descriptive_reps=B,model_reps=MB,
 inference_available=B>=100,model_inference_available=MB>=100,
 outputs_update_final_reports=FALSE), 'execution_settings')
cat('Reference-aligned tasks completed for ',country,'.\n',sep='')
)----------------------")

MODULES[["201_verify_planning_html.py"]] <- list(language="Python", packaged_sha256="dd7600bad84be2898f4324c71c67f6ceffa9b8d9335c6f6315ccd83e0bc50853", args=character(0), code=r"----------------------(#!/usr/bin/env python3
"""Rebuild duration-planning tables from freshly computed aggregate results.

This verifies only the named planning sections, not the complete report.
All locations are parameters. The saved HTML is read-only.
"""
import argparse,csv,json,re
from pathlib import Path
from html import escape
from lxml import html

def norm(x):return re.sub(r'\s+',' ',str(x)).strip()
def rows(t):return [[norm(c.text_content()) for c in r.xpath('./th|./td')] for r in t.xpath('./thead/tr|./tbody/tr|./tr')]
def matrix(x):return [[norm(' '.join(str(v) for v in c) if isinstance(c,list) else c) for c in r] for r in x]
def numbers(cell):return re.findall(r'[-+]?\d[\d,]*(?:\.\d+)?',cell.replace('−','-'))
def render(table):return '<table>'+''.join('<tr>'+''.join(f'<{"th" if i==0 else "td"}>{escape(v)}</{"th" if i==0 else "td"}>' for v in r)+'</tr>' for i,r in enumerate(table))+'</table>'

def main():
 ap=argparse.ArgumentParser();ap.add_argument('--country',required=True);ap.add_argument('--fresh-root',type=Path,required=True);ap.add_argument('--report-html',type=Path,required=True);ap.add_argument('--output-dir',type=Path,required=True);a=ap.parse_args()
 out=a.output_dir;out.mkdir(parents=True,exist_ok=True);doc=html.fromstring(a.report_html.read_text());sup=a.fresh_root/'output/Supporting_data'
 ids=['historical-duration-aware-planning','aft-duration-aware-planning'];blocks=[]
 if a.country=='Ethiopia':
  data=json.loads((sup/'final_duration_planning_tables.json').read_text())
  for key in ['Historical duration-aware','AFT survival + pathways']:
   blocks.append([matrix(t) for k,t in sorted(data[key]['tables'].items(),key=lambda z:int(z[0]))])
 elif a.country=='Nigeria':
  data=json.loads((a.fresh_root/'output/nigeria_duration_planning_tables.json').read_text());blocks=[[matrix(s['table']) for s in b['slides']] for b in data['blocks']]
 else:
  import pandas as pd
  for approach in ['Historical duration-aware','AFT plus observed pathways']:
   tables=[]
   for stem in ['by_method','by_method_cause','scenarios']:
    df=pd.read_csv(sup/f'drc_2026_planning_{stem}.csv');df=df[df.approach==approach].copy()
    for c in df:
     if pd.api.types.is_float_dtype(df[c]):df[c]=df[c].map(lambda v:'—' if pd.isna(v) else f'{v:,.1f}')
     elif pd.api.types.is_integer_dtype(df[c]):df[c]=df[c].map(lambda v:f'{v:,}')
    tables.append(rows(html.fromstring(df.to_html(index=False))))
   blocks.append(tables)
 audit=[];page=['<!doctype html><html lang="en"><meta charset="utf-8"><title>Rebuilt planning tables</title><style>body{font:16px Arial;margin:36px;color:#153f5b}table{border-collapse:collapse;width:100%;margin:20px 0 40px}th{background:#153f5b;color:white}th,td{padding:10px;border-bottom:1px solid #ddd;text-align:right}th:first-child,td:first-child{text-align:left}tr:nth-child(even){background:#edf5f5}</style>',f'<h1>{escape(a.country)}: rebuilt duration-planning tables</h1><p>Generated from recalculated aggregate outputs. This is a reconciliation preview, not a replacement for the full report.</p>']
 for sid,block in zip(ids,blocks):
  target=doc.xpath('//*[@id=$id]',id=sid)[0];actual=target.xpath('.//table');page.append(f'<h2>{escape(sid.replace("-"," "))}</h2>')
  if len(block)!=len(actual):raise ValueError(f'Table count mismatch for {sid}')
  for i,(expected,table) in enumerate(zip(block,actual),1):
   actualrows=rows(table);shape=len(actualrows)==len(expected) and all(len(x)==len(y) for x,y in zip(actualrows,expected))
   # Cell-by-cell, not comparison of totals alone. Header word changes separately recorded.
   diffs=[]
   if shape:
    for ri,(ar,er) in enumerate(zip(actualrows[1:],expected[1:]),1):
     for ci,(av,ev) in enumerate(zip(ar,er)):
      if numbers(av)!=numbers(ev):diffs.append(f'row {ri}, column {ci+1}: {av} versus {ev}')
   else:diffs=['Different dimensions']
   labels=shape and actualrows==expected
   audit.append(dict(section=sid,table=i,numeric_cells_match=shape and not diffs,all_text_matches=labels,differences='; '.join(diffs)))
   page.append(f'<h3>Table {i}</h3>'+render(expected))
 (out/'rebuilt_duration_planning.html').write_text('\n'.join(page)+ '</html>')
 with (out/'planning_html_checks.csv').open('w',newline='') as f:
  w=csv.DictWriter(f,fieldnames=list(audit[0]));w.writeheader();w.writerows(audit)
 print(json.dumps({'country':a.country,'tables_checked':len(audit),'numeric_matches':sum(x['numeric_cells_match'] for x in audit),'text_matches':sum(x['all_text_matches'] for x in audit)},indent=2))
 if not all(x['numeric_cells_match'] for x in audit):raise SystemExit(2)
if __name__=='__main__':main()
)----------------------")

MODULES[["01_nigeria_calendar_life_table.R"]] <- list(language="R", packaged_sha256="8e34e454d6fc973204cc8538d49b5fe2dcb1ea6a95e1ce6a0804a79efb662715", args=character(0), code=r"----------------------(if(!requireNamespace('haven',quietly=TRUE))stop('Install R package haven first.')
# DHS complex survey design for this module.
.dhs_root <- Sys.getenv('NIGERIA_PROJECT_ROOT')
if (!nzchar(.dhs_root)) {
 .dhs_file <- sub('^--file=','',grep('^--file=',commandArgs(FALSE),value=TRUE)[1])
 .dhs_root <- dirname(dirname(normalizePath(.dhs_file)))
}
source(file.path(.dhs_root,'Code','dhs_survey_tools.R'),local=TRUE)
dhs_set_context(country='Nigeria',root=.dhs_root)
#!/usr/bin/env Rscript
# Nigeria DHS 2024: reconstruct contraceptive episodes and validate Table 7.12.
# Input is the authorized IR recode already available in the Nigeria project.
# One woman contributes zero or more calendar method-use episodes. The DHS
# 3–62-month window and left entry are retained; multiple-decrement estimates
# keep every ending reason as a competing event. This script never edits input.

options(stringsAsFactors=FALSE)
script_arg <- grep('^--file=', commandArgs(FALSE), value=TRUE)
default_root <- if(length(script_arg)) normalizePath(file.path(dirname(sub('^--file=', '', script_arg[1])), '..')) else normalizePath('..')
root <- Sys.getenv('NIGERIA_PROJECT_ROOT', unset=default_root)
input_dir <- Sys.getenv('NIGERIA_INPUT_DIR', unset=file.path(root, 'Data/raw_dhs_ir'))
source_rds <- file.path(input_dir, 'NG2024DHS__NGIR8BDT__IR_raw.rds')
derived <- file.path(root,'Data/Derived')
support <- file.path(root,'output/Supporting_data')
dir.create(derived,recursive=TRUE,showWarnings=FALSE)
dir.create(support,recursive=TRUE,showWarnings=FALSE)
x <- readRDS(source_rds)
dhs_set_context(ir=x)
stopifnot(nrow(x)==39050L,!anyDuplicated(x$caseid),
          all(as.numeric(x$v008)-as.numeric(x$v017)+1==as.numeric(x$v019)),
          all(nchar(x$vcal_1)==80L),
          all(c('vcal_1','vcal_2','v005','v021','v022','v024','sstate') %in% names(x)))

# In both vcal fields character position is month. Reverse the stored order
# to work chronologically. The case-specific v019 tells us how many months are
# valid. A maximal continuous run of one vcal_1 character is one episode.
method_codes <- strsplit('123456789WNALCFEMS~','')[[1]]
reason_codes <- c('1'=1L,'2'=2L,'3'=3L,'4'=4L,'5'=5L,'6'=6L,
                  '7'=7L,'8'=8L,'9'=9L,'C'=10L,'F'=11L,'A'=12L,
                  'D'=13L,'M'=15L,'W'=96L,'K'=98L,'?'=99L,' '=0L)
events <- vector('list',nrow(x))
for(i in seq_len(nrow(x))){
  months <- as.integer(x$v019[i])
  cal <- rev(strsplit(x$vcal_1[i],'')[[1]])[seq_len(months)]
  reason_string <- sprintf('%-80s',x$vcal_2[i])
  reasons <- rev(strsplit(reason_string,'')[[1]])[seq_len(months)]
  runs <- rle(cal)
  ends <- cumsum(runs$lengths)
  starts <- ends-runs$lengths+1L
  codes <- match(runs$values,method_codes)
  codes[runs$values=='0'] <- 0L
  codes[runs$values=='B'] <- 81L
  codes[runs$values=='T'] <- 82L
  codes[runs$values=='P'] <- 83L
  codes[runs$values=='?'] <- 99L
  reason_at_end <- unname(reason_codes[reasons[ends]])
  reason <- reason_at_end
  offset <- integer(length(ends))
  for(k in seq_along(ends)){
    pos <- (starts[k]:ends[k])[reasons[starts[k]:ends[k]]!=' ']
    if(length(pos)){
      last <- tail(pos,1)
      reason[k] <- unname(reason_codes[reasons[last]])
      offset[k] <- ends[k]-last
    }
  }
  stopifnot(!anyNA(codes),!anyNA(reason),!anyNA(reason_at_end))
  events[[i]] <- data.frame(woman_row=i,caseid=x$caseid[i],
    event_no=seq_along(codes),wt=as.numeric(x$v005[i])/1e6,
    interview=as.numeric(x$v008[i]),calendar_start=as.numeric(x$v017[i]),
    zone=as.integer(x$v024[i]),state=as.integer(x$sstate[i]),
    start=as.numeric(x$v017[i])+starts-1L,end=as.numeric(x$v017[i])+ends-1L,
    duration=runs$lengths,method_code=codes,reason_code=reason,
    reason_at_method_end=reason_at_end,reason_offset=offset,
    next_code=c(codes[-1L],NA_integer_),
    next_duration=c(runs$lengths[-1L],NA_integer_),
    next2_code=c(codes,NA_integer_,NA_integer_)[seq_along(codes)+2L])
}
events <- do.call(rbind,events)
events <- dhs_calendar_records(events,x)
saveRDS(events,file.path(derived,'nigeria_2024_calendar_events.rds'))

# Each use episode may enter the 3–62-month observation window after it began.
# Retain late entrants with their correct duration of entry. An episode only
# contributes to a first-year life table when entry < 12 completed months.
e <- events[events$method_code %in% c(1:20,99) &
              events$start!=events$calendar_start,]
e$start_before_interview <- e$interview-e$start
e$end_before_interview <- e$interview-e$end
e <- e[e$start_before_interview>=3 & e$end_before_interview<=62,]
e$entry <- pmax(e$start_before_interview-62,0)
e$exposure <- e$duration-pmax(3-e$end_before_interview,0)
stopifnot(all(e$exposure>e$entry))
e <- e[e$entry<12,]
# The published "Other" row groups codes 10, 13, 14, 17, and 18. Code 6
# contributes to the all-methods total but not to that printed row.
e$method <- 'Unlisted'
e$method[e$method_code %in% c(10L,13L,14L,17L,18L)] <- 'Other'
e$method[e$method_code==2] <- 'IUD'
e$method[e$method_code==3] <- 'Injectables'
e$method[e$method_code==11] <- 'Implants'
e$method[e$method_code==1] <- 'Pill'
e$method[e$method_code==5] <- 'Male condom'
e$method[e$method_code==16] <- 'Emergency contraception'
e$method[e$method_code==8] <- 'Rhythm'
e$method[e$method_code==9] <- 'Withdrawal'

# Nine mutually exclusive DHS reason groups. Code 2 is wanted pregnancy;
# code 3 is partner disapproval. Codes 9/12/13 are other fertility-related.
reason_group <- function(z){
  result <- rep(9L,length(z))
  mapping <- c('1'=1L,'2'=2L,'9'=3L,'12'=3L,'13'=3L,'15'=4L,
               '4'=5L,'5'=5L,'7'=6L,'6'=7L,'8'=7L,'10'=7L,'3'=8L)
  for(k in names(mapping))result[z==as.integer(k)] <- mapping[[k]]
  result
}
is_method <- function(z)!is.na(z) & z %in% c(1:20,99)
classify <- function(d){
  d$discontinued <- d$end_before_interview>3
  d$reason <- ifelse(d$discontinued,reason_group(d$reason_code),0L)
  d$switched <- d$discontinued & (
    (is_method(d$next_code) & d$next_code!=d$method_code) |
    (d$reason_code==7L & !is.na(d$next_code) & d$next_code==0L &
     !is.na(d$next_duration) & d$next_duration==1L &
     is_method(d$next2_code) & d$next2_code!=d$method_code))
  d$boundary_reason <- FALSE
  for(j in which(d$end_before_interview<=3)){
    row <- d$woman_row[j]
    p <- as.integer(x$v018[row])+3L
    character <- substring(x$vcal_2[row],p,p)
    if(nzchar(trimws(character))){
      rcode <- unname(reason_codes[character])
      d$reason_code[j] <- rcode
      d$reason[j] <- reason_group(rcode)
      d$discontinued[j] <- TRUE
      d$boundary_reason[j] <- TRUE
      next1 <- substring(x$vcal_1[row],p-1L,p-1L)
      next2 <- substring(x$vcal_1[row],p-2L,p-2L)
      d$switched[j] <- next1 %in% method_codes ||
        (rcode==7L && next1=='0' && next2 %in% method_codes &&
         match(next2,method_codes)!=d$method_code[j])
    }
  }
  stopifnot(!anyNA(d$switched),all(d$switched<=d$discontinued))
  d
}
e <- classify(e)
e$episode_id <- seq_len(nrow(e))
saveRDS(e,file.path(derived,'nigeria_2024_table_7_12_episodes.rds'))

# DHS weighted multiple-decrement life table. The sum of reason-specific
# cumulative incidences equals the any-reason probability at every month.
life_table <- function(d){
  survival <- 1
  cif <- numeric(9)
  switched <- 0
  out <- vector('list',12)
  for(t in 1:12){
    at_risk <- d$entry<t & d$exposure>=t
    risk <- sum(d$wt[at_risk])
    ending <- at_risk & d$exposure==t & d$discontinued
    cause <- vapply(1:9,function(k)sum(d$wt[ending & d$reason==k]),numeric(1))
    sw <- sum(d$wt[ending & d$switched])
    if(risk>0){
      cif <- cif+survival*cause/risk
      switched <- switched+survival*sw/risk
      survival <- survival*(1-sum(cause)/risk)
    }
    out[[t]] <- data.frame(month=t,weighted_at_risk=risk,
      weighted_ending=sum(cause),any_reason_pct=100*(1-survival),
      switching_pct=100*switched,t(100*cif))
  }
  z <- do.call(rbind,out)
  names(z)[6:14] <- paste0('reason_',1:9,'_pct')
  stopifnot(max(abs(rowSums(z[paste0('reason_',1:9,'_pct')])-z$any_reason_pct))<1e-8)
  z
}

published_methods <- c('IUD','Injectables','Implants','Pill','Male condom',
                       'Emergency contraception','Rhythm','Withdrawal','Other','All methods')
results <- do.call(rbind,lapply(published_methods,function(m){
  d <- if(m=='All methods')e else e[e$method==m,]
  z <- life_table(d)
  last <- z[z$month==12,]
  data.frame(method=m,as.list(last[paste0('reason_',1:9,'_pct')]),
    any_reason_pct=last$any_reason_pct,switching_pct=last$switching_pct,
    weighted_episodes=sum(d$wt),unweighted_episodes=nrow(d),
    women=length(unique(d$caseid)),late_entries=sum(d$entry>0))
}))
reference <- rbind(
 c(.9,5.3,.3,2.1,5.3,.9,1.2,.4,0,16.3,0,199),
 c(1.9,13.3,2.7,11.4,9.9,2.4,4.1,3.1,3.1,51.9,2.9,2164),
 c(.3,4.2,.5,3,7.1,.9,.7,.5,.8,18.1,.7,2228),
 c(3.7,12.2,6.1,7.2,9.6,8.6,5.8,2.4,1,56.4,4.1,1012),
 c(1.2,8.5,11.6,.1,.2,3.1,4.3,2.1,1.9,33,2.7,1509),
 c(1.2,8.3,11.9,2.2,5.4,6.5,3.2,1.3,2.5,42.6,4.3,273),
 c(2.6,13.8,3,.1,.2,3.5,.8,1.4,.5,26.1,1.3,520),
 c(3,10.9,5.5,.2,.4,6.3,1,1.8,1.5,30.6,4.2,1542),
 c(3,7.7,5.4,2.3,.6,23,2.2,1.6,7.6,53.3,16.8,1207),
 c(1.9,9.3,4.7,4,4.8,5.7,2.7,1.8,2.3,37.2,4.1,10708))
rounded <- cbind(round(as.matrix(results[,2:12]),1),
                 round(results$weighted_episodes))
matching <- rounded==reference
audit <- data.frame(method=published_methods,
  rate_cells_matching=rowSums(matching[,1:11]),
  episode_count_matching=matching[,12],
  max_rate_abs_difference_pp=apply(abs(rounded[,1:11]-reference[,1:11]),1,max),
  weighted_episodes=results$weighted_episodes,
  unweighted_episodes=results$unweighted_episodes,
  late_entries=results$late_entries)
write.csv(results,file.path(support,'nigeria_table_7_12_replicated.csv'),row.names=FALSE)
write.csv(audit,file.path(support,'nigeria_table_7_12_validation.csv'),row.names=FALSE)
monthly <- do.call(rbind,lapply(published_methods,function(m){
  d <- if(m=='All methods')e else e[e$method==m,]
  cbind(method=m,life_table(d))
}))
write.csv(monthly,file.path(support,'nigeria_table_7_12_monthly.csv'),row.names=FALSE)
cat('Women:',nrow(x),'episodes:',nrow(e),'weighted:',sum(e$wt),'\n')
print(audit,row.names=FALSE)
cat('Exact published rate cells:',sum(matching[,1:11]),'of',length(matching[,1:11]),'\n')
cat('Exact published episode counts:',sum(matching[,12]),'of',nrow(matching),'\n')
if(!all(matching))stop('Nigeria Table 7.12 replication does not yet match every published cell.')
)----------------------")

MODULES[["02_nigeria_descriptive_analyses.R"]] <- list(language="R", packaged_sha256="53d8285fd8779a8916a8c3ec125c3d39e05eae1563b154429e8a46fbeb1a5cc5", args=character(0), code=r"----------------------(if(!requireNamespace('haven',quietly=TRUE))stop('Install R package haven first.')
# DHS complex survey design for this module.
.dhs_root <- Sys.getenv('NIGERIA_PROJECT_ROOT')
if (!nzchar(.dhs_root)) {
 .dhs_file <- sub('^--file=','',grep('^--file=',commandArgs(FALSE),value=TRUE)[1])
 .dhs_root <- dirname(dirname(normalizePath(.dhs_file)))
}
source(file.path(.dhs_root,'Code','dhs_survey_tools.R'),local=TRUE)
dhs_set_context(country='Nigeria',root=.dhs_root)
#!/usr/bin/env Rscript
# Nigeria DHS 2024 descriptive analysis. Run after 01_nigeria_calendar_life_table.R.
# No package download is needed. The source IR recode stays unchanged.
# The outcome is cessation of the ORIGINAL modern method within 12 months for
# one of eight potentially actionable calendar reason codes. All other endings
# remain competing events. Emergency contraception is excluded because it is
# an episodic intervention, although it remains in official mCPR tabulations.
# Six geopolitical zones (v024) are the primary subnational geography.

root <- Sys.getenv("NIGERIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
full_ir <- readRDS(file.path(root,'Data/raw_dhs_ir/NG2024DHS__NGIR8BDT__IR_raw.rds'))
full_frame <- unique(data.frame(cluster=as.numeric(full_ir$v021),stratum=as.numeric(full_ir$v022)))

support <- file.path(root,'output/Supporting_data')
derived <- file.path(root,'Data/Derived')
e <- readRDS(file.path(derived,'nigeria_2024_table_7_12_episodes.rds'))
ir <- readRDS(file.path(Sys.getenv("NIGERIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE)), 'Data/raw_dhs_ir/NG2024DHS__NGIR8BDT__IR_raw.rds'))
stopifnot(nrow(ir)==39050L,nrow(e)==11210L)

zone_names <- c('North West','North East','North Central','South East','South South','South West')
e$zone_name <- zone_names[e$zone]
e$cluster <- as.numeric(ir$v021[e$woman_row])
e$stratum <- as.numeric(ir$v022[e$woman_row])
e$method_group <- 'Other modern'
e$method_group[e$method_code==1] <- 'Pill'
e$method_group[e$method_code==2] <- 'IUD'
e$method_group[e$method_code==3] <- 'Injectables'
e$method_group[e$method_code==11] <- 'Implants'
modern_codes <- c(1L,2L,3L,5L,6L,7L,11L,13L,14L,15L,17L,18L,19L,20L)
e <- e[e$method_code %in% modern_codes,]
stopifnot(!any(e$method_code==16L),all(e$zone %in% 1:6))
saveRDS(e,file.path(derived,'nigeria_2024_modern_episodes.rds'))

reason_codes <- list('Method failure'=1L,'Wanted more effective method'=7L,
  'Changes in menstrual bleeding'=15L,'Other side effects/health'=c(4L,5L),
  'Access/cost/convenience'=c(6L,8L,10L))
actionable <- unlist(reason_codes,use.names=FALSE)
stopifnot(length(unique(actionable))==8L)
months <- c(3L,6L,9L,12L)

# Weighted multiple-decrement life table. A woman can contribute several
# episodes; all her episodes share her survey weight and PSU in the bootstrap.
estimate <- function(d, multipliers=NULL) {
  if(is.null(multipliers)) w <- d$wt else w <- d$wt*multipliers[as.character(d$cluster)]
  s <- 1; any <- 0; action <- 0
  cause <- setNames(numeric(length(reason_codes)),names(reason_codes))
  rows <- vector('list',12)
  for(t in 1:12) {
    at <- d$entry<t & d$exposure>=t
    risk <- sum(w[at]); stopifnot(risk>0)
    ended <- at & d$exposure==t & d$discontinued
    all_h <- sum(w[ended])/risk
    chosen <- ended & d$reason_code %in% actionable
    a_h <- sum(w[chosen])/risk
    for(j in seq_along(reason_codes))
      cause[j] <- cause[j]+s*sum(w[ended & d$reason_code %in% reason_codes[[j]]])/risk
    any <- any+s*all_h; action <- action+s*a_h
    s <- s*(1-all_h)
    rows[[t]] <- data.frame(month=t,weighted_at_risk=risk,
      all_reason_pct=100*any,actionable_pct=100*action)
  }
  list(monthly=do.call(rbind,rows),causes=100*cause)
}

scopes <- list('National'=rep(TRUE,nrow(e)))
for(z in seq_along(zone_names)) scopes[[zone_names[z]]] <- e$zone==z
methods <- c('Injectables','Implants','Pill','IUD','Other modern')
for(m in methods) scopes[[paste0('National: ',m)]] <- e$method_group==m
for(z in zone_names) for(m in methods)
  scopes[[paste0(z,': ',m)]] <- e$zone_name==z & e$method_group==m

times <- list(); reasons <- list()
for(label in names(scopes)) {
  d <- e[scopes[[label]],]
  if(!nrow(d)) next
  fit <- estimate(d)
  t <- fit$monthly[fit$monthly$month %in% months,]
  t$scope <- label; t$eligible_episodes_n <- nrow(d)
  t$weighted_episodes <- sum(d$wt)
  t$actionable_endings_n <- sum(d$discontinued & d$exposure<=12 &
    d$reason_code %in% actionable)
  t$limited_precision <- t$actionable_endings_n<30L
  times[[label]] <- t
  total <- sum(fit$causes)
  reasons[[label]] <- data.frame(scope=label,reason=names(fit$causes),
    cause_specific_12_month_pct=unname(fit$causes),
    share_among_actionable_pct=if(total>0)100*unname(fit$causes)/total else NA_real_,
    eligible_episodes_n=nrow(d),
    actionable_endings_n=t$actionable_endings_n[1],
    limited_precision=t$actionable_endings_n[1]<30L)
}
times <- do.call(rbind,times); reasons <- do.call(rbind,reasons)
rownames(times) <- rownames(reasons) <- NULL
stopifnot(max(abs(aggregate(share_among_actionable_pct~scope,reasons,sum)$share_among_actionable_pct-100))<1e-6)

# Stratified PSU bootstrap, preserving the original sample design. The
# percentile intervals describe sampling uncertainty; sparse zone x method
# cells are flagged for caution regardless of their numerical interval.
frame <- full_frame; frame$id <- seq_len(nrow(frame))
stopifnot(!anyDuplicated(frame$cluster))
groups <- split(frame$id,frame$stratum)
stopifnot(all(lengths(groups)>1L))
B <- as.integer(Sys.getenv('NIGERIA_BOOTSTRAP_REPS','300'))
focus <- names(scopes)
boot <- array(NA_real_,c(B,length(focus),4L),
  dimnames=list(NULL,focus,as.character(months)))
for(b in seq_len(B)) {
  set.seed(20261021L+b)
  mult <- numeric(nrow(frame))
  for(ids in groups) {
    n <- length(ids)
    mult[ids] <- n/(n-1)*tabulate(sample.int(n,n-1,replace=TRUE),nbins=n)
  }
  lookup <- setNames(mult,frame$cluster)
  for(j in seq_along(focus)) {
    d <- e[scopes[[focus[j]]],]
    fit <- tryCatch(estimate(d,lookup),error=function(err)NULL)
    if(!is.null(fit))boot[b,j,] <- fit$monthly$actionable_pct[months]
  }
}
for(j in seq_along(focus))for(k in seq_along(months)) {
  z <- boot[,j,k]; z <- z[is.finite(z)]
  if(length(z)<.9*B)stop('Too few valid bootstrap estimates: ',focus[j])
  sel <- times$scope==focus[j] & times$month==months[k]
  times$ci_low[sel] <- quantile(z,.025)
  times$ci_high[sel] <- quantile(z,.975)
}
write.csv(times,file.path(support,'nigeria_actionable_timepoints.csv'),row.names=FALSE)
write.csv(reasons,file.path(support,'nigeria_actionable_reason_mix.csv'),row.names=FALSE)
saveRDS(boot,file.path(derived,'nigeria_actionable_bootstrap.rds'))

# Observed modern-method starts: entry=0 corresponds to an observed start.
# These shares condition on modern starts and are retained for modeling and
# audit purposes. Presentation gold bars instead use ALL observed method
# starts from Code/15, matching the Ethiopia initiation-mix denominator.
# EC is omitted from ongoing-method risk.
starts <- e[e$entry==0L,]
start_rows <- list()
for(z in c('National',zone_names)) {
  d <- if(z=='National')starts else starts[starts$zone_name==z,]
  denom <- sum(d$wt)
  for(m in methods) {
    q <- d[d$method_group==m,]
    start_rows[[length(start_rows)+1L]] <- data.frame(scope=z,method=m,
      starts_n=nrow(q),weighted_starts=sum(q$wt),
      start_share_pct=100*sum(q$wt)/denom,
      actionable_12_month_pct=times$actionable_pct[
        times$scope==paste0(z,if(z=='National')': ' else ': ',m) & times$month==12][1])
  }
}
mix <- do.call(rbind,start_rows)
write.csv(mix,file.path(support,'nigeria_zone_modern_method_start_mix.csv'),row.names=FALSE)

# Survey-weighted all-women mCPR and current method shares. DHS v313=3 is
# modern use (including EC); numbers of users require a separate population
# denominator, so this script reports percentages only.
current <- data.frame(wt=as.numeric(ir$v005)/1e6,
  modern=as.numeric(ir$v313)==3,method=as.numeric(ir$v312),
  zone=zone_names[as.numeric(ir$v024)])
current_rows <- list()
for(z in c('National',zone_names)) {
  d <- if(z=='National')current else current[current$zone==z,]
  modern_users <- d[d$modern,]
  current_rows[[z]] <- data.frame(scope=z,women_n=nrow(d),
    modern_users_n=nrow(modern_users),
    all_women_mcpr_pct=100*sum(d$wt[d$modern])/sum(d$wt),
    ec_share_of_modern_users_pct=100*sum(modern_users$wt[modern_users$method==16])/
      sum(modern_users$wt))
}
write.csv(do.call(rbind,current_rows),
  file.path(support,'nigeria_current_use_mcpr.csv'),row.names=FALSE)
# Published Table 7.3, all-women total: mCPR 13.1%, sample 39,050. Its
# method columns are verified to one decimal before any user-count analysis.
published_use <- c(`Female sterilization`=.3,IUD=.6,Injectables=2.7,
  Implants=4.0,Pill=1.1,`Male condom`=3.0,EC=.4,LAM=.9,
  `Other modern`=.1)
current_codes <- list(`Female sterilization`=6L,IUD=2L,Injectables=3L,
  Implants=11L,Pill=1L,`Male condom`=5L,EC=16L,LAM=13L,
  `Other modern`=c(7L,14L,18L))
use_audit <- do.call(rbind,lapply(names(published_use),function(name){
  val <- 100*sum(current$wt[current$method %in% current_codes[[name]]])/
    sum(current$wt)
  data.frame(method=name,reconstructed_pct=val,
    published_rounded_pct=published_use[[name]],
    matches=round(val,1)==published_use[[name]])
}))
stopifnot(all(use_audit$matches),
  round(current_rows$National$all_women_mcpr_pct,1)==13.1)
write.csv(use_audit,file.path(support,'nigeria_table_7_3_current_use_validation.csv'),
  row.names=FALSE)
cat('Modern episodes:',nrow(e),'National actionable 12-month rate:',
    round(times$actionable_pct[times$scope=='National' & times$month==12],2),'\n')
print(times[times$month==12 & times$scope %in% c('National',zone_names),
  c('scope','eligible_episodes_n','actionable_endings_n','actionable_pct','ci_low','ci_high')],
  row.names=FALSE)
)----------------------")

MODULES[["03_nigeria_zone_models.R"]] <- list(language="R", packaged_sha256="5c48b32868ea5b1adc39388345b63b998d1a7cbc2ec20d440616cd1a4a3f262e", args=character(0), code=r"----------------------(if(!requireNamespace('haven',quietly=TRUE))stop('Install R package haven first.')
# DHS complex survey design for this module.
.dhs_root <- Sys.getenv('NIGERIA_PROJECT_ROOT')
if (!nzchar(.dhs_root)) {
 .dhs_file <- sub('^--file=','',grep('^--file=',commandArgs(FALSE),value=TRUE)[1])
 .dhs_root <- dirname(dirname(normalizePath(.dhs_file)))
}
source(file.path(.dhs_root,'Code','dhs_survey_tools.R'),local=TRUE)
dhs_set_context(country='Nigeria',root=.dhs_root)
#!/usr/bin/env Rscript
# Nigeria DHS 2024: adjusted zone comparison for actionable discontinuation.
# Run after scripts 01 and 02. Unit of fitting is the episode-month. Outcomes
# are continuation, actionable discontinuation, and another competing ending.
# Therefore pregnancy intentions, partner disapproval, other fertility reasons,
# and unresolved reasons remain in the starting cohort and leave at their end.
# The two multinomial discrete-time models mirror the Ethiopia specification:
# A: month of method use, method, zone; B: A plus measured characteristics.
# Method use month is elapsed duration since the ORIGINAL method began, not
# duration at interview. Both models retain delayed-entry episodes for fitting.
# Adjusted zone probabilities predict a 12-month first-year trajectory on the
# SAME observed-start national episodes with each zone assigned in turn. This
# is common-composition standardization, not each zone's actual observed mix.

root <- Sys.getenv("NIGERIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
full_ir <- readRDS(file.path(root,'Data/raw_dhs_ir/NG2024DHS__NGIR8BDT__IR_raw.rds'))
full_frame <- unique(data.frame(cluster=as.numeric(full_ir$v021),stratum=as.numeric(full_ir$v022)))

support <- file.path(root,'output/Supporting_data')
derived <- file.path(root,'Data/Derived')
if(!requireNamespace('nnet',quietly=TRUE))stop('nnet package is required')
e <- readRDS(file.path(derived,'nigeria_2024_modern_episodes.rds'))
ir <- readRDS(file.path(Sys.getenv("NIGERIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE)), 'Data/raw_dhs_ir/NG2024DHS__NGIR8BDT__IR_raw.rds'))
times <- read.csv(file.path(support,'nigeria_actionable_timepoints.csv'))
actionable <- c(1L,4L,5L,6L,7L,8L,10L,15L)
e$zone_name <- factor(e$zone_name,
  levels=c('North West','North East','North Central','South East','South South','South West'))
e$method_group <- factor(e$method_group,
  levels=c('IUD','Injectables','Implants','Pill','Other modern'))
e$age_at_start <- (e$start-as.numeric(ir$v011[e$woman_row]))/12
stopifnot(all(e$age_at_start>=10),all(e$age_at_start<50))
# A small number of calendar episodes began before age 15, although every
# respondent was 15–49 at interview. Retain them in an honestly labeled group.
e$age_group <- factor(ifelse(e$age_at_start<20,'Under 20',
  ifelse(e$age_at_start<25,'20–24',ifelse(e$age_at_start<35,'25–34','35–49'))),
  levels=c('25–34','Under 20','20–24','35–49'))
bcols <- grep('^b3_',names(ir),value=TRUE)
b <- as.matrix(ir[e$woman_row,bcols])
parity <- rowSums(!is.na(b) & b<=e$start)
e$parity_group <- factor(ifelse(parity==0,'0',ifelse(parity<=2,'1–2',
  ifelse(parity<=4,'3–4','5+'))),levels=c('0','1–2','3–4','5+'))
marital <- as.numeric(ir$v501[e$woman_row])
e$marital_group <- factor(ifelse(marital==0,'Never in union',
  ifelse(marital==1,'Married',ifelse(marital==2,'Living together',
  'Formerly in union'))),
  levels=c('Married','Never in union','Living together','Formerly in union'))
educ <- as.numeric(ir$v106[e$woman_row])
e$education <- factor(ifelse(educ==0,'None',ifelse(educ==1,'Primary',
  ifelse(educ %in% c(2,3),'Secondary or higher',NA_character_))),
  levels=c('None','Primary','Secondary or higher'))
e$wealth <- factor(c('Poorest','Poorer','Middle','Richer','Richest')[
  as.numeric(ir$v190[e$woman_row])],
  levels=c('Poorest','Poorer','Middle','Richer','Richest'))
e$residence <- factor(ifelse(as.numeric(ir$v025[e$woman_row])==1,'Urban','Rural'),
  levels=c('Urban','Rural'))
# Very recent 2024 starts contribute only 50 episodes and no observed
# actionable endings in the DHS window. A separate 2024 indicator therefore
# perfectly separates the event outcome. Pool 2023 and 2024 starts so the
# cohort term remains estimable while retaining all eligible episodes.
year <- (e$start-1L)%/%12L+1900L
e$start_year <- factor(ifelse(year>=2023,'2023–24',as.character(year)))
complete <- complete.cases(e[,c('method_group','zone_name','age_group',
  'parity_group','marital_group','education','wealth','residence','start_year')])
cat('Complete-case episodes:',sum(complete),'of',nrow(e),'\n')
e <- e[complete,]
saveRDS(e,file.path(derived,'nigeria_2024_model_episode_covariates.rds'))

observed_months <- pmax(0L,pmin(12L,e$exposure)-e$entry)
idx <- rep(seq_len(nrow(e)),observed_months)
month <- unlist(Map(function(first,n)seq.int(first+1L,length.out=n),
  e$entry,observed_months),use.names=FALSE)
person <- e[idx,c("woman_row",'wt','cluster','stratum','method_group','zone_name',
  'age_group','parity_group','marital_group','education','wealth',
  'residence','start_year')]
person <- dhs_calendar_records(person,dhs_context()$ir)
person$month <- factor(month,levels=1:12)
end <- e$discontinued[idx] & month==e$exposure[idx]
person$outcome <- factor(ifelse(!end,'continue',
  ifelse(e$reason_code[idx] %in% actionable,'actionable','competing')),
  levels=c('continue','actionable','competing'))
stopifnot(!anyNA(person),nrow(person)>40000)
saveRDS(person,file.path(derived,'nigeria_2024_person_month.rds'))

f1 <- outcome~month+method_group+zone_name
f2 <- outcome~month+method_group+zone_name+age_group+parity_group+
  marital_group+education+wealth+residence+start_year
fit <- function(formula,data,wts,with_hessian=TRUE){
  data$fit_weight <- wts
  m <- dhs_multinom_fit(formula,data=data,weights=fit_weight,trace=FALSE,
    maxit=350,MaxNWts=10000,Hess=with_hessian)
  m$call$formula <- formula
  if(m$convergence!=0L)stop('Model did not converge')
  m
}
model1 <- fit(f1,person,person$wt)
model2 <- fit(f2,person,person$wt)
saveRDS(model1,file.path(derived,'nigeria_actionable_zone_model_1.rds'))
saveRDS(model2,file.path(derived,'nigeria_actionable_zone_model_2.rds'))

# The common reference is modern episodes observed from initiation, thus its
# covariates represent the cohort to whom first-year predictions apply.
standard <- e[e$entry==0L,]
predict_cif <- function(model,zone,reference=standard,weights=reference$wt){
  d <- reference
  if(!is.null(zone) && !is.na(zone))
    d$zone_name <- factor(zone,levels=levels(e$zone_name))
  survival <- rep(1,nrow(d)); cumulative <- numeric(nrow(d))
  for(t in 1:12){
    d$month <- factor(t,levels=1:12)
    p <- predict(model,newdata=d,type='probs')
    cumulative <- cumulative+survival*p[,'actionable']
    survival <- survival*p[,'continue']
  }
  100*weighted.mean(cumulative,weights)
}
zones <- levels(e$zone_name)
point <- do.call(rbind,lapply(zones,function(z){
  raw <- times[times$scope==z & times$month==12,]
  data.frame(zone=z,eligible_episodes_n=raw$eligible_episodes_n,
    actionable_endings_n=raw$actionable_endings_n,
    unadjusted_pct=raw$actionable_pct,unadjusted_low=raw$ci_low,
    unadjusted_high=raw$ci_high,
    model_1_common_mix_pct=predict_cif(model1,z),
    model_2_common_mix_pct=predict_cif(model2,z))
}))
national <- times[times$scope=='National' & times$month==12,]
point <- rbind(data.frame(zone='National',
  eligible_episodes_n=national$eligible_episodes_n,
  actionable_endings_n=national$actionable_endings_n,
  unadjusted_pct=national$actionable_pct,
  unadjusted_low=national$ci_low,
  unadjusted_high=national$ci_high,
  model_1_common_mix_pct=predict_cif(model1,NULL),
  model_2_common_mix_pct=predict_cif(model2,NULL)),point)
write.csv(point,file.path(support,'nigeria_actionable_zone_adjusted_rates.csv'),
  row.names=FALSE)

# Model coefficients are odds ratios for each non-continuation event versus
# continuing that same episode-month. Wald inference uses full-frame survey covariance;
# survey-design bootstrap intervals are calculated for the zone probabilities
# below. Coefficients should be read as associations, not causal effects.
coefficient_table <- function(model,name){
  s <- dhs_multinom_summary(model,person)
  critical <- qt(.975,s$design_df)
  z <- s$coefficients/s$standard.errors
  p <- 2*pt(-abs(z),df=s$design_df)
  rows <- list()
  for(outcome in rownames(s$coefficients))for(v in colnames(s$coefficients)){
    beta <- s$coefficients[outcome,v]; se <- s$standard.errors[outcome,v]
    rows[[length(rows)+1L]] <- data.frame(model=name,outcome=outcome,
      covariate=v,odds_ratio=exp(beta),ci_low=exp(beta-critical*se),
      ci_high=exp(beta+critical*se),p_value=p[outcome,v])
  }
  do.call(rbind,rows)
}
coef <- rbind(coefficient_table(model1,'Method + duration'),
  coefficient_table(model2,'Full'))
write.csv(coef,file.path(support,'nigeria_actionable_zone_model_odds_ratios.csv'),
  row.names=FALSE)

# Optional stratified PSU bootstrap for adjusted probability intervals.
# It refits both models with the same resampled clusters. Minimum 90% valid
# refits required. Set NIGERIA_MODEL_BOOTSTRAP_REPS=0 to skip while prototyping.
B <- as.integer(Sys.getenv('NIGERIA_MODEL_BOOTSTRAP_REPS','500'))
if(B>0L){
  frame <- full_frame; frame$id<-seq_len(nrow(frame))
  groups <- split(frame$id,frame$stratum)
  stopifnot(!anyDuplicated(frame$cluster),all(lengths(groups)>1L))
  one <- function(b){
    set.seed(20261025L+b)
    mult <- numeric(nrow(frame))
    for(ids in groups){
      n<-length(ids)
      mult[ids]<-n/(n-1)*tabulate(sample.int(n,n-1,replace=TRUE),nbins=n)
    }
    lookup<-setNames(mult,frame$cluster)
    w<-person$wt*lookup[as.character(person$cluster)]
    sw<-standard$wt*lookup[as.character(standard$cluster)]
    # The Hessian is required for the single fitted coefficient table, but
    # not for bootstrap predictions. Omitting it avoids repeated unnecessary
    # matrix calculations while preserving the same fitted probabilities.
    m1<-tryCatch(fit(f1,person,w,FALSE),error=function(err)NULL)
    m2<-tryCatch(fit(f2,person,w,FALSE),error=function(err)NULL)
    if(is.null(m1)||is.null(m2))return(rep(NA_real_,14L))
    c(vapply(c(NA_character_,zones),function(z)predict_cif(m1,z,standard,sw),numeric(1)),
      vapply(c(NA_character_,zones),function(z)predict_cif(m2,z,standard,sw),numeric(1)))
  }
  draws<-parallel::mclapply(seq_len(B),one,
    mc.cores=min(4L,parallel::detectCores()),mc.preschedule=FALSE)
  draws<-do.call(rbind,draws)
  valid<-complete.cases(draws)
  if(sum(valid)<ceiling(.9*B))stop('Too few successful model bootstrap refits')
  colnames(draws)<-c(paste0('model1:',point$zone),paste0('model2:',point$zone))
  write.csv(draws,file.path(support,'nigeria_actionable_zone_model_bootstrap.csv'),
    row.names=FALSE)
  ci<-apply(draws[valid,,drop=FALSE],2,quantile,c(.025,.975),na.rm=TRUE)
  point$model_1_low<-ci[1,1:7]; point$model_1_high<-ci[2,1:7]
  point$model_2_low<-ci[1,8:14]; point$model_2_high<-ci[2,8:14]
  write.csv(point,file.path(support,'nigeria_actionable_zone_adjusted_rates.csv'),
    row.names=FALSE)
}
print(point,row.names=FALSE)

source(file.path(root,"Code","202_nigeria_survey_coefficients.R"),local=TRUE)
)----------------------")

MODULES[["04_nigeria_subgroups_and_tests.R"]] <- list(language="R", packaged_sha256="a10bedd671364b040fcf2e9be60f385e6bf42c8e0c409419d86c80678d73dffb", args=character(0), code=r"----------------------(if(!requireNamespace('haven',quietly=TRUE))stop('Install R package haven first.')
# DHS complex survey design for this module.
.dhs_root <- Sys.getenv('NIGERIA_PROJECT_ROOT')
if (!nzchar(.dhs_root)) {
 .dhs_file <- sub('^--file=','',grep('^--file=',commandArgs(FALSE),value=TRUE)[1])
 .dhs_root <- dirname(dirname(normalizePath(.dhs_file)))
}
source(file.path(.dhs_root,'Code','dhs_survey_tools.R'),local=TRUE)
dhs_set_context(country='Nigeria',root=.dhs_root)
#!/usr/bin/env Rscript
# Nigeria DHS 2024 subgroup and zone-pairwise analysis. Run after 01–03.
# Each subgroup rate is a weighted cumulative incidence among its eligible
# modern method episodes, with all non-actionable endings as competing events.
# Zone pairwise tests compare differences in 12-month percentage points.
# Holm adjustment controls family-wise error across all 15 zone pairs per
# comparison stage. PSU bootstraps are stratified and keep all woman episodes
# together. They remain exploratory for small method-specific cells.

root <- Sys.getenv("NIGERIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
full_ir <- readRDS(file.path(root,'Data/raw_dhs_ir/NG2024DHS__NGIR8BDT__IR_raw.rds'))
full_frame <- unique(data.frame(cluster=as.numeric(full_ir$v021),stratum=as.numeric(full_ir$v022)))

support <- file.path(root,'output/Supporting_data')
derived <- file.path(root,'Data/Derived')
e <- readRDS(file.path(derived,'nigeria_2024_model_episode_covariates.rds'))
reasons <- list('Method failure'=1L,'Wanted more effective method'=7L,
 'Changes in menstrual bleeding'=15L,'Other side effects/health'=c(4L,5L),
 'Access/cost/convenience'=c(6L,8L,10L))
actionable <- unlist(reasons,use.names=FALSE)
life <- function(d,w=d$wt){
 s<-1; f<-0; cause<-numeric(length(reasons))
 for(t in 1:12){
  at<-d$entry<t & d$exposure>=t
  risk<-sum(w[at]); if(risk<=0)return(rep(NA_real_,1+length(reasons)))
  end<-at & d$exposure==t & d$discontinued
  for(j in seq_along(reasons))cause[j]<-cause[j]+s*sum(w[end & d$reason_code %in% reasons[[j]]])/risk
  f<-f+s*sum(w[end & d$reason_code %in% actionable])/risk
  s<-s*(1-sum(w[end])/risk)
 }
 c(total=100*f,setNames(100*cause,names(reasons)))
}
covariates <- c('age_group','parity_group','marital_group','education',
 'wealth','residence','method_group','zone_name')
frame<-full_frame; frame$id<-seq_len(nrow(frame))
groups<-split(frame$id,frame$stratum)
stopifnot(!anyDuplicated(frame$cluster),all(lengths(groups)>1L))
B<-as.integer(Sys.getenv('NIGERIA_SUBGROUP_BOOTSTRAP_REPS','250'))
scopes<-list()
for(v in covariates)for(value in levels(e[[v]]))
 scopes[[paste(v,value,sep='::')]]<-which(e[[v]]==value)
point<-lapply(names(scopes),function(key){
 idx<-scopes[[key]]; d<-e[idx,]; x<-life(d)
 data.frame(covariate=strsplit(key,'::',fixed=TRUE)[[1]][1],
   category=strsplit(key,'::',fixed=TRUE)[[1]][2],
   eligible_episodes_n=nrow(d),weighted_episodes=sum(d$wt),
   actionable_endings_n=sum(d$discontinued & d$exposure<=12 &
     d$reason_code %in% actionable),
   actionable_12_month_pct=x[1],as.list(x[-1]),
   limited_precision=sum(d$discontinued & d$exposure<=12 &
     d$reason_code %in% actionable)<30L)
})
point<-do.call(rbind,point)
draw<-matrix(NA_real_,B,nrow(point))
for(b in seq_len(B)){
 set.seed(20261101L+b)
 mult<-numeric(nrow(frame))
 for(ids in groups){n<-length(ids);mult[ids]<-n/(n-1)*
   tabulate(sample.int(n,n-1,replace=TRUE),nbins=n)}
 lookup<-setNames(mult,frame$cluster)
 for(j in seq_along(scopes)){
  d<-e[scopes[[j]],]
  draw[b,j]<-life(d,d$wt*lookup[as.character(d$cluster)])[1]
 }
}
ci<-apply(draw,2,quantile,c(.025,.975),na.rm=TRUE)
point$ci_low<-ci[1,];point$ci_high<-ci[2,]
write.csv(point,file.path(support,'nigeria_actionable_subgroup_rates_reasons.csv'),
 row.names=FALSE)

# Convert the saved bootstrap trajectories to design-based contrasts. A
# two-sided normal statistic uses the PSU-bootstrap SE for each difference;
# report both raw and Holm-adjusted p-values. This is descriptive inference.
raw<-readRDS(file.path(derived,'nigeria_actionable_bootstrap.rds'))
modfile<-file.path(support,'nigeria_actionable_zone_model_bootstrap.csv')
if(file.exists(modfile)) {
  modeldraw<-read.csv(modfile,check.names=FALSE)
} else {
  modeldraw<-NULL
}
rates<-read.csv(file.path(support,'nigeria_actionable_zone_adjusted_rates.csv'))
zones<-rates$zone[rates$zone!='National']
pairs<-combn(zones,2,simplify=FALSE)
rows<-list()
for(stage in c('Unadjusted','Method adjusted','Fully adjusted')){
 if(stage!='Unadjusted' && is.null(modeldraw))next
 for(pair in pairs){
  a<-pair[1];b<-pair[2]
  if(stage=='Unadjusted'){
    v<-raw[,a,'12']-raw[,b,'12']
    diff<-rates$unadjusted_pct[rates$zone==a]-rates$unadjusted_pct[rates$zone==b]
  }else{
    stem<-if(stage=='Method adjusted')'model1:' else 'model2:'
    v<-modeldraw[[paste0(stem,a)]]-modeldraw[[paste0(stem,b)]]
    col<-if(stage=='Method adjusted')'model_1_common_mix_pct' else
      'model_2_common_mix_pct'
    diff<-rates[[col]][rates$zone==a]-rates[[col]][rates$zone==b]
  }
  v<-v[is.finite(v)]
  se<-sd(v)
  rows[[length(rows)+1L]]<-data.frame(stage=stage,zone_a=a,zone_b=b,
    difference_pp=diff,se_pp=se,ci_low=diff-1.96*se,
    ci_high=diff+1.96*se,p_value=2*pnorm(-abs(diff/se)),
    bootstrap_replicates=length(v))
 }
}
tests<-do.call(rbind,rows)
tests$p_holm<-ave(tests$p_value,tests$stage,FUN=function(p)p.adjust(p,'holm'))
tests$significant_5pct<-tests$p_holm<.05
tests$significant_10pct<-tests$p_holm<.10
write.csv(tests,file.path(support,'nigeria_zone_pairwise_three_stages.csv'),
 row.names=FALSE)
cat('Subgroups:',nrow(point),' pairwise rows:',nrow(tests),'\n')
print(aggregate(significant_5pct~stage,tests,sum),row.names=FALSE)
)----------------------")

MODULES[["08_nigeria_population_and_planning.R"]] <- list(language="R", packaged_sha256="3820c11985ffbd4aa0fdf9ac7b1d235474f7c329ee36f864694995dca1a15b8e", args=character(0), code=r"----------------------(if(!requireNamespace('haven',quietly=TRUE))stop('Install R package haven first.')
# DHS complex survey design for this module.
.dhs_root <- Sys.getenv('NIGERIA_PROJECT_ROOT')
if (!nzchar(.dhs_root)) {
 .dhs_file <- sub('^--file=','',grep('^--file=',commandArgs(FALSE),value=TRUE)[1])
 .dhs_root <- dirname(dirname(normalizePath(.dhs_file)))
}
source(file.path(.dhs_root,'Code','dhs_survey_tools.R'),local=TRUE)
dhs_set_context(country='Nigeria',root=.dhs_root)
#!/usr/bin/env Rscript
# Nigeria DHS 2024 current-use method mix and an illustrative 2024–26
# planning bridge. WRA comes from UN WPP 2024 medium variant (female single
# ages 15–49, mid-year). Pair the 2024 survey mCPR/mix with 2024 WRA first;
# then project both WRA and mCPR forward rather than calling 2025 observed.
# First-year episode risks are applied to the estimated current-user stock
# only as a transparent illustrative upper bound, not a duration-adjusted
# forecast of current-user discontinuation or loss of all modern use.
root <- Sys.getenv("NIGERIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
out <- file.path(root,'output/Supporting_data')
ir <- readRDS(file.path(Sys.getenv("NIGERIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE)), 'Data/raw_dhs_ir/NG2024DHS__NGIR8BDT__IR_raw.rds'))
e <- readRDS(file.path(root,'Data/Derived/nigeria_2024_modern_episodes.rds'))
e <- e[!e$method_code %in% c(6L,7L),]
times <- read.csv(file.path(out,'nigeria_actionable_timepoints.csv'))
reasons <- read.csv(file.path(out,'nigeria_actionable_reason_mix.csv'))
wra <- read.csv(file.path(out,'nigeria_wpp2024_wra_2024_2026.csv'))
d <- e[e$method_group=='Other modern',];S<-1;F<-numeric(5)
ccode<-list(1L,7L,15L,c(4L,5L),c(6L,8L,10L))
for(t in 1:12){at<-d$entry<t & d$exposure>=t;en<-at & d$discontinued & d$exposure==t;den<-sum(d$wt[at]);F<-F+S*vapply(ccode,function(cc)sum(d$wt[en & d$reason_code%in%cc])/den,0.0);S<-S*(1-sum(d$wt[en])/den)}
times$actionable_pct[times$scope=='National: Other modern' & times$month==12]<-100*sum(F)
rnames<-c('Method failure','Wanted more effective method','Changes in menstrual bleeding','Other side effects/health','Access/cost/convenience')
for(j in 1:5)reasons$cause_specific_12_month_pct[reasons$scope=='National: Other modern' & reasons$reason==rnames[j]]<-100*F[j]

stopifnot(all(c(2024,2025,2026) %in% wra$year),nrow(ir)==39050L)
modern <- as.numeric(ir$v313)==3
code <- as.numeric(ir$v312)
method <- rep(NA_character_,length(code))
method[code==3] <- 'Injectables';method[code==11] <- 'Implants'
method[code==1] <- 'Pill';method[code==2] <- 'IUD'
method[code==16] <- 'EC'
method[modern & is.na(method)] <- 'Other modern'
method[code%in%c(6L,7L)] <- 'Permanent methods'
stopifnot(all(!is.na(method[modern])),all(is.na(method[!modern])))
wt <- as.numeric(ir$v005)/1e6
mcpr <- 100*sum(wt[modern])/sum(wt)
stopifnot(round(mcpr,1)==13.1)
lev <- c('Injectables','Implants','Pill','IUD','Other modern','EC','Permanent methods')
mix <- data.frame(method=lev,weighted_users=vapply(lev,function(m)sum(wt[method==m],na.rm=TRUE),0.0))
mix$share_current_modern_pct <- 100*mix$weighted_users/sum(mix$weighted_users)
mix$current_method_prevalence_pct <- mcpr*mix$share_current_modern_pct/100
stopifnot(abs(sum(mix$share_current_modern_pct)-100)<1e-8)
w24 <- wra$women_15_49[wra$year==2024]
w25 <- wra$women_15_49[wra$year==2025]
w26 <- wra$women_15_49[wra$year==2026]
current_users_2024 <- w24*mcpr/100
mix$current_users_2024 <- current_users_2024*mix$share_current_modern_pct/100

# Source for the 0.4 percentage-point annual trend: Track20/FP2030 Nigeria
# 2025 indicator brief gives all-women mCPR 13.2% in 2024 and 13.6% in 2025.
# It is used here as a scenario increment, not as a 2026 prediction.
scenarios <- data.frame(scenario=c('No further growth in 2026','DHS anchored +0.4 pp/year','FP2030 2025 level +0.4 pp'),
  mcpr_2024_pct=rep(mcpr,3),
  mcpr_2025_pct=rep(mcpr+0.4,3),
  mcpr_2026_pct=c(mcpr+0.4,mcpr+0.8,14.0))
scenarios$wra_2024 <- w24;scenarios$wra_2025 <- w25;scenarios$wra_2026 <- w26
scenarios$current_users_2024 <- current_users_2024
scenarios$current_users_2025 <- w25*scenarios$mcpr_2025_pct/100
scenarios$usual_users_2026 <- w26*scenarios$mcpr_2026_pct/100

# The user-count slide applies each method's first-year actionable probability
# to estimated users in 2025. Cause-specific risks sum to method total.
central <- scenarios[scenarios$scenario=='DHS anchored +0.4 pp/year',]
mix$current_users_2025 <- central$current_users_2025*mix$share_current_modern_pct/100
mix$actionable_first_year_risk_pct <- NA_real_
for(i in seq_len(nrow(mix))){
  m <- mix$method[i]
  if(!m%in%c('EC','Permanent methods')) mix$actionable_first_year_risk_pct[i] <- times$actionable_pct[times$scope==paste0('National: ',m) & times$month==12]
}
mix$illustrative_original_method_endings <- mix$current_users_2025*mix$actionable_first_year_risk_pct/100
mix$illustrative_original_method_endings[is.na(mix$illustrative_original_method_endings)] <- 0
cause <- reasons[grepl('^National: ',reasons$scope),]
cause$method <- sub('^National: ','',cause$scope)
cause <- merge(cause,mix[,c('method','current_users_2025')],by='method')
cause$illustrative_users <- cause$current_users_2025*cause$cause_specific_12_month_pct/100
stopifnot(max(abs(aggregate(illustrative_users~method,cause,sum)$illustrative_users -
  mix$illustrative_original_method_endings[match(aggregate(illustrative_users~method,cause,sum)$method,mix$method)]))<1)

# A first-month switch to another modern method is not an immediate exit from
# modern contraceptive use. This descriptive bridge is from episode endings,
# without claiming to identify modern use at year-end.
modern_codes <- c(1L,2L,3L,5L,11L,13L,14L,15L,17L,18L,19L,20L)
e$modern_next <- e$next_code %in% c(modern_codes,6L,7L,14L,16L)
e$modern_next[is.na(e$modern_next)] <- FALSE
e$actionable <- e$discontinued & e$reason_code %in% c(1L,4L,5L,6L,7L,8L,10L,15L)
e$eligible_event <- e$actionable & e$exposure<=12
switch_share <- data.frame(method=c('All modern',lev[lev!='EC']),share_immediate_modern_pct=NA_real_,
  actionable_events_n=NA_integer_)
for(i in seq_len(nrow(switch_share))){
  d <- if(i==1) e else e[e$method_group==switch_share$method[i],]
  a <- d[d$eligible_event,]
  switch_share$actionable_events_n[i] <- nrow(a)
  switch_share$share_immediate_modern_pct[i] <- if(nrow(a))100*sum(a$wt[a$modern_next])/sum(a$wt) else NA_real_
}

gross <- sum(mix$illustrative_original_method_endings)
net_immediate <- sum(mix$illustrative_original_method_endings[1:5]*
  (1-switch_share$share_immediate_modern_pct[match(mix$method[1:5],switch_share$method)]/100))
scenarios$illustrative_gross_endings <- gross
scenarios$illustrative_after_immediate_switch <- net_immediate
scenarios$no_gross_endings_users_2026 <- scenarios$usual_users_2026+gross
scenarios$no_gross_endings_mcpr_2026_pct <- 100*scenarios$no_gross_endings_users_2026/scenarios$wra_2026
scenarios$gross_ceiling_gain_pp <- scenarios$no_gross_endings_mcpr_2026_pct-scenarios$mcpr_2026_pct
scenarios$no_non_switch_endings_users_2026 <- scenarios$usual_users_2026+net_immediate
scenarios$no_non_switch_endings_mcpr_2026_pct <- 100*scenarios$no_non_switch_endings_users_2026/scenarios$wra_2026
scenarios$non_switch_ceiling_gain_pp <- scenarios$no_non_switch_endings_mcpr_2026_pct-scenarios$mcpr_2026_pct

write.csv(mix,file.path(out,'nigeria_current_users_by_method_and_actionable_projection.csv'),row.names=FALSE)
write.csv(cause,file.path(out,'nigeria_current_users_actionable_by_cause.csv'),row.names=FALSE)
write.csv(switch_share,file.path(out,'nigeria_actionable_immediate_modern_switch_share.csv'),row.names=FALSE)
write.csv(scenarios,file.path(out,'nigeria_2026_mcpr_scenarios.csv'),row.names=FALSE)
cat('WRA 2024',w24,'users 2024',current_users_2024,'WRA 2025',w25,
  'WRA 2026',w26,'DHS 2024 mCPR',mcpr,'gross illustrative endings',gross,
  'after immediate switch',net_immediate,'\n')


# Separate first-year reversible-origin rates for the older all-cause
# planning illustration; descriptive DHS timepoints remain unchanged.
pt <- read.csv(file.path(out,'nigeria_modern_all_reason_timepoints.csv'))
pr <- read.csv(file.path(out,'nigeria_modern_all_reason_reason_mix.csv'))
rlabel <- unique(pr$reason[pr$scope=='National'])
for(m in c('Injectables','Implants','Pill','IUD','Other modern')){
 z<-e[e$method_group==m,];S<-1;F9<-numeric(9)
 for(t in 1:12){at<-z$entry<t & z$exposure>=t;en<-at & z$discontinued & z$exposure==t;den<-sum(z$wt[at]);F9<-F9+S*vapply(1:9,function(j)sum(z$wt[en & z$reason==j])/den,0.0);S<-S*(1-sum(z$wt[en])/den)}
 pt$all_reason_pct[pt$scope==paste0('National: ',m)&pt$month==12]<-100*sum(F9)
 for(j in 1:9)pr$cause_specific_12_month_pct[pr$scope==paste0('National: ',m)&pr$reason==rlabel[j]]<-100*F9[j]
}
write.csv(pt,file.path(out,'nigeria_reversible_planning_all_reason_timepoints.csv'),row.names=FALSE)
write.csv(pr,file.path(out,'nigeria_reversible_planning_all_reason_reason_mix.csv'),row.names=FALSE)
)----------------------")

MODULES[["09_nigeria_post_discontinuation_pathways.R"]] <- list(language="R", packaged_sha256="5a4b60698fc1d2d4b64973e9ce623d288da17acd0e4a0f6b0e7496a26262f835", args=character(0), code=r"----------------------(if(!requireNamespace('haven',quietly=TRUE))stop('Install R package haven first.')
# DHS complex survey design for this module.
.dhs_root <- Sys.getenv('NIGERIA_PROJECT_ROOT')
if (!nzchar(.dhs_root)) {
 .dhs_file <- sub('^--file=','',grep('^--file=',commandArgs(FALSE),value=TRUE)[1])
 .dhs_root <- dirname(dirname(normalizePath(.dhs_file)))
}
source(file.path(.dhs_root,'Code','dhs_survey_tools.R'),local=TRUE)
dhs_set_context(country='Nigeria',root=.dhs_root)
#!/usr/bin/env Rscript
# Descriptive status one and twelve months after an observed actionable
# original-method ending. This is a follow-up cohort, not a competing-risk
# life-table estimate. Only events with the respective follow-up month
# observable in the DHS calendar contribute at that checkpoint.
root <- Sys.getenv("NIGERIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
out <- file.path(root,'output/Supporting_data')
e <- readRDS(file.path(root,'Data/Derived/nigeria_2024_modern_episodes.rds'))
all <- readRDS(file.path(root,'Data/Derived/nigeria_2024_calendar_events.rds'))
modern <- c(1L,2L,3L,5L,6L,7L,11L,13L,14L,15L,17L,18L,19L,20L)
eligible <- e[e$discontinued & e$exposure<=12 & e$reason_code %in% c(1L,4L,5L,6L,7L,8L,10L,15L),]
stopifnot(nrow(eligible)>1000L)
status <- function(z,original) {
  if(is.na(z)) return('Unobserved')
  if(z %in% modern) return(if(z==original) 'Same modern method' else 'Different modern method')
  if(z %in% c(8L,9L,10L,12L,99L)) return('Traditional/other method')
  if(z %in% c(81L,82L,83L)) return('Pregnant, birth or termination')
  if(z==0L) return('No method recorded')
  'Other/unknown'
}
rows <- list()
inds <- split(seq_len(nrow(all)),all$woman_row)
code_at <- function(d,i,k){
  a <- all[inds[[as.character(d$woman_row[i])]],]
  pick <- which(a$start<=d$end[i]+k & a$end>=d$end[i]+k)
  if(length(pick)!=1L)stop('Calendar timeline is not uniquely partitioned')
  a$method_code[pick]
}
for(k in c(1L,12L)){
  d <- eligible[eligible$end+k<=eligible$interview,]
  # Calendar events partition each woman's observed months.
  next_code <- vapply(seq_len(nrow(d)),function(i)code_at(d,i,k),integer(1))
  d$status <- mapply(status,next_code,d$method_code)
  tab <- aggregate(d$wt,list(status=d$status),sum)
  tab$month_after_ending <- k
  tab$percent <- 100*tab$x/sum(d$wt)
  tab$observed_ending_events_n <- nrow(d)
  tab$weighted_ending_events <- sum(d$wt)
  names(tab)[names(tab)=='x'] <- 'weighted_events'
  rows[[as.character(k)]] <- tab
}
z <- do.call(rbind,rows);z <- z[,c('month_after_ending','status','weighted_events','percent','observed_ending_events_n','weighted_ending_events')]
write.csv(z,file.path(out,'nigeria_actionable_post_ending_pathways.csv'),row.names=FALSE)
# The joint table keeps only endings observed for a full 12 months. Its rows
# therefore describe real transitions in one common cohort; the marginal
# one-month table above has a larger observation window and a different base.
d <- eligible[eligible$end+12L<=eligible$interview,]
code1 <- vapply(seq_len(nrow(d)),function(i)code_at(d,i,1L),integer(1))
code12 <- vapply(seq_len(nrow(d)),function(i)code_at(d,i,12L),integer(1))
d$status_month_1 <- mapply(status,code1,d$method_code)
d$status_month_12 <- mapply(status,code12,d$method_code)
joint <- aggregate(d$wt,list(month_1=d$status_month_1,month_12=d$status_month_12),sum)
names(joint)[3] <- 'weighted_events'
joint$share_of_common_cohort_pct <- 100*joint$weighted_events/sum(d$wt)
joint$observed_ending_events_n <- nrow(d)
write.csv(joint,file.path(out,'nigeria_actionable_post_ending_transitions.csv'),row.names=FALSE)
print(z)

# Ethiopia's earlier pathway slides follow endings for any reason other than
# wanted pregnancy and partner disapproval. Reproduce that broader intermediate
# cohort separately so it is not confused with the actionable-only follow-up.
eligible <- e[e$discontinued & e$exposure<=12 &
  !(e$reason_code %in% c(2L,3L)),]
stopifnot(nrow(eligible)>1000L)
rows <- list()
for(k in c(1L,12L)){
  d <- eligible[eligible$end+k<=eligible$interview,]
  next_code <- vapply(seq_len(nrow(d)),function(i)code_at(d,i,k),integer(1))
  d$status <- mapply(status,next_code,d$method_code)
  tab <- aggregate(d$wt,list(status=d$status),sum)
  tab$month_after_ending <- k
  tab$percent <- 100*tab$x/sum(d$wt)
  tab$observed_ending_events_n <- nrow(d)
  tab$weighted_ending_events <- sum(d$wt)
  names(tab)[names(tab)=='x'] <- 'weighted_events'
  rows[[as.character(k)]] <- tab
}
selected <- do.call(rbind,rows)
selected <- selected[,c('month_after_ending','status','weighted_events','percent',
  'observed_ending_events_n','weighted_ending_events')]
write.csv(selected,file.path(out,'nigeria_selected_reason_post_ending_pathways.csv'),row.names=FALSE)
print(selected)
)----------------------")

MODULES[["12_nigeria_all_reason_bridge.R"]] <- list(language="R", packaged_sha256="3fab85ec36db0026bb1d2badd8931de2e2da88827ebec207be17123a12bfb8e8", args=character(0), code=r"----------------------(if(!requireNamespace('haven',quietly=TRUE))stop('Install R package haven first.')
# DHS complex survey design for this module.
.dhs_root <- Sys.getenv('NIGERIA_PROJECT_ROOT')
if (!nzchar(.dhs_root)) {
 .dhs_file <- sub('^--file=','',grep('^--file=',commandArgs(FALSE),value=TRUE)[1])
 .dhs_root <- dirname(dirname(normalizePath(.dhs_file)))
}
source(file.path(.dhs_root,'Code','dhs_survey_tools.R'),local=TRUE)
dhs_set_context(country='Nigeria',root=.dhs_root)
#!/usr/bin/env Rscript
# Reproduce the Ethiopia presentation's sequence for the Nigeria modern-method
# cohort: all-cause first-year risk, a selected-reason intermediate estimate
# (wanted pregnancy and partner disapproval remain competing events), and then
# the narrower potentially actionable cause set. The same episodes, weights,
# delayed entry, and multiple-decrement life-table denominator are used at all
# three stages. This is separate from the official all-methods Table 7.12 row.
root <- Sys.getenv("NIGERIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
full_ir <- readRDS(file.path(root,'Data/raw_dhs_ir/NG2024DHS__NGIR8BDT__IR_raw.rds'))
full_frame <- unique(data.frame(cluster=as.numeric(full_ir$v021),stratum=as.numeric(full_ir$v022)))

support <- file.path(root,'output/Supporting_data')
e <- readRDS(file.path(root,'Data/Derived/nigeria_2024_modern_episodes.rds'))
zones <- c('North West','North East','North Central','South East','South South','South West')
methods <- c('Injectables','Implants','Pill','IUD','Other modern')
labels <- c('Method failure','Wanted pregnancy','Other fertility-related',
  'Changes in menstrual bleeding','Other side effects/health',
  'Wanted more effective method','Access/cost/convenience',
  'Partner disapproved','Other recorded reasons')
actionable_ids <- c(1L,4L,5L,6L,7L)
selected_ids <- setdiff(1:9,c(2L,8L))
scopes <- list(National=rep(TRUE,nrow(e)))
for(z in zones)scopes[[z]] <- e$zone_name==z
for(m in methods)scopes[[paste0('National: ',m)]] <- e$method_group==m
for(z in zones)for(m in methods)scopes[[paste0(z,': ',m)]] <-
  e$zone_name==z & e$method_group==m

estimate <- function(d,w=d$wt){
  survival <- 1
  cif <- numeric(9)
  rows <- vector('list',12)
  for(t in 1:12){
    at <- d$entry<t & d$exposure>=t
    risk <- sum(w[at])
    if(risk<=0){
      rows[[t]] <- data.frame(month=t,all_reason_pct=100*sum(cif),
        selected_reason_pct=100*sum(cif[selected_ids]),
        actionable_pct=100*sum(cif[actionable_ids]))
      next
    }
    ended <- at & d$exposure==t & d$discontinued
    hazard <- vapply(1:9,function(k)sum(w[ended & d$reason==k])/risk,numeric(1))
    cif <- cif+survival*hazard
    survival <- survival*(1-sum(hazard))
    rows[[t]] <- data.frame(month=t,all_reason_pct=100*sum(cif),
      selected_reason_pct=100*sum(cif[selected_ids]),
      actionable_pct=100*sum(cif[actionable_ids]))
  }
  list(monthly=do.call(rbind,rows),causes=100*cif)
}

time_rows <- list(); reason_rows <- list()
for(scope in names(scopes)){
  d <- e[scopes[[scope]],]
  if(!nrow(d))next
  fit <- estimate(d)
  t <- fit$monthly[fit$monthly$month %in% c(3,6,9,12),]
  t$scope <- scope
  t$eligible_episodes_n <- nrow(d)
  t$weighted_episodes <- sum(d$wt)
  t$all_reason_endings_n <- sum(d$discontinued & d$exposure<=12)
  time_rows[[scope]] <- t
  total <- sum(fit$causes)
  reason_rows[[scope]] <- data.frame(scope=scope,reason=labels,
    cause_specific_12_month_pct=fit$causes,
    share_among_all_discontinuation_pct=if(total>0)100*fit$causes/total else NA_real_,
    eligible_episodes_n=nrow(d),all_reason_endings_n=t$all_reason_endings_n[1])
}
times <- do.call(rbind,time_rows)
reason <- do.call(rbind,reason_rows)
rownames(times) <- rownames(reason) <- NULL

# Survey-design intervals for the all-cause geographic comparison. Resample
# PSUs within strata; all episodes contributed by a woman move together.
frame <- full_frame; frame$id <- seq_len(nrow(frame))
groups <- split(frame$id,frame$stratum)
stopifnot(!anyDuplicated(frame$cluster),all(lengths(groups)>1L))
B <- as.integer(Sys.getenv('NIGERIA_ALL_REASON_BOOTSTRAP_REPS','300'))
draws <- matrix(NA_real_,B,length(zones)+1L,
  dimnames=list(NULL,c('National',zones)))
selected_draws <- draws
for(b in seq_len(B)){
  set.seed(20261022L+b)
  mult <- numeric(nrow(frame))
  for(ids in groups){
    n <- length(ids)
    mult[ids] <- n/(n-1)*tabulate(sample.int(n,n-1,replace=TRUE),nbins=n)
  }
  lookup <- setNames(mult,frame$cluster)
  for(z in colnames(draws)){
    d <- e[scopes[[z]],]
    v <- estimate(d,d$wt*lookup[as.character(d$cluster)])$monthly
    draws[b,z] <- v$all_reason_pct[12]
    selected_draws[b,z] <- v$selected_reason_pct[12]
  }
}
for(z in colnames(draws)){
  selected <- times$scope==z & times$month==12
  times$all_reason_ci_low[selected] <- quantile(draws[,z],.025,na.rm=TRUE)
  times$all_reason_ci_high[selected] <- quantile(draws[,z],.975,na.rm=TRUE)
  times$selected_reason_ci_low[selected] <- quantile(selected_draws[,z],.025,na.rm=TRUE)
  times$selected_reason_ci_high[selected] <- quantile(selected_draws[,z],.975,na.rm=TRUE)
}
write.csv(times,file.path(support,'nigeria_modern_all_reason_timepoints.csv'),row.names=FALSE)
write.csv(reason,file.path(support,'nigeria_modern_all_reason_reason_mix.csv'),row.names=FALSE)
cat('National all-cause / selected / actionable:',
  unlist(times[times$scope=='National' & times$month==12,
    c('all_reason_pct','selected_reason_pct','actionable_pct')]),'\n')
)----------------------")

MODULES[["13_nigeria_all_reason_models.R"]] <- list(language="R", packaged_sha256="f0daa85241b249b2164d574398c52c24dd3a62ded9c4797b9047f163673da0fd", args=character(0), code=r"----------------------(if(!requireNamespace('haven',quietly=TRUE))stop('Install R package haven first.')
# DHS complex survey design for this module.
.dhs_root <- Sys.getenv('NIGERIA_PROJECT_ROOT')
if (!nzchar(.dhs_root)) {
 .dhs_file <- sub('^--file=','',grep('^--file=',commandArgs(FALSE),value=TRUE)[1])
 .dhs_root <- dirname(dirname(normalizePath(.dhs_file)))
}
source(file.path(.dhs_root,'Code','dhs_survey_tools.R'),local=TRUE)
dhs_set_context(country='Nigeria',root=.dhs_root)
#!/usr/bin/env Rscript
# All-reason counterpart of the Nigeria actionable episode-month models.
# Every observed modern-method month contributes until its original-method
# ending or censoring. The binary event is ANY ending, including desired
# pregnancy, partner disapproval and method-related reasons. This supports the
# opening all-cause subgroup and regional slides used in Ethiopia before the
# presentation narrows to selected/program-actionable causes.
root <- Sys.getenv("NIGERIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
full_ir <- readRDS(file.path(root,'Data/raw_dhs_ir/NG2024DHS__NGIR8BDT__IR_raw.rds'))
full_frame <- unique(data.frame(cluster=as.numeric(full_ir$v021),stratum=as.numeric(full_ir$v022)))

derived <- file.path(root,'Data/Derived')
support <- file.path(root,'output/Supporting_data')
e <- readRDS(file.path(derived,'nigeria_2024_model_episode_covariates.rds'))
person <- readRDS(file.path(derived,'nigeria_2024_person_month.rds'))
person$ended <- as.integer(person$outcome!='continue')
stopifnot(nrow(e)==8341L,all(person$ended %in% 0:1))

f1 <- ended~month+method_group+zone_name
f2 <- ended~month+method_group+zone_name+age_group+parity_group+
  marital_group+education+wealth+residence+start_year
fit <- function(formula,wts){
  person$fit_weight <- wts
  dhs_binary_fit(formula,person,full_frame,weight='fit_weight')
}
m1 <- fit(f1,person$wt)
m2 <- fit(f2,person$wt)
if(!m1$converged||!m2$converged)stop('All-reason model did not converge')
saveRDS(m1,file.path(derived,'nigeria_all_reason_model_1.rds'))
saveRDS(m2,file.path(derived,'nigeria_all_reason_model_2.rds'))

standard <- e[e$entry==0L,]
zones <- levels(e$zone_name)
groups <- list('National'=rep(TRUE,nrow(standard)))
for(z in zones)groups[[z]] <- rep(TRUE,nrow(standard))
predict_risk <- function(model,d,weights=d$wt){
  survival <- rep(1,nrow(d))
  for(t in 1:12){
    d$month <- factor(t,levels=1:12)
    p <- predict(model,newdata=d,type='response')
    survival <- survival*(1-p)
  }
  100*weighted.mean(1-survival,weights)
}
zone_prediction <- function(model,zone,weights=standard$wt){
  d <- standard
  if(zone!='National')d$zone_name <- factor(zone,levels=zones)
  predict_risk(model,d,weights)
}
all_times <- read.csv(file.path(support,'nigeria_modern_all_reason_timepoints.csv'))
zone_rows <- do.call(rbind,lapply(c('National',zones),function(z){
  raw <- all_times[all_times$scope==z & all_times$month==12,]
  data.frame(zone=z,eligible_episodes_n=raw$eligible_episodes_n,
    unadjusted_pct=raw$all_reason_pct,
    unadjusted_low=raw$all_reason_ci_low,
    unadjusted_high=raw$all_reason_ci_high,
    model_1_pct=zone_prediction(m1,z),model_2_pct=zone_prediction(m2,z))
}))

# Adjusted subgroup probabilities are marginal predictions for the common
# observed-start cohort with the named covariate set to each category. They
# describe model-adjusted associations, not a causal change to those women.
subgroups <- c('age_group','parity_group','marital_group','education',
  'wealth','residence')
subgroup_rows <- list()
for(v in subgroups)for(level in levels(e[[v]])){
  d <- standard
  d[[v]] <- factor(level,levels=levels(e[[v]]))
  subgroup_rows[[length(subgroup_rows)+1L]] <- data.frame(
    covariate=v,category=level,adjusted_12_month_pct=predict_risk(m2,d))
}
subgroup_rows <- do.call(rbind,subgroup_rows)

# Stratified PSU bootstrap for standardized zone and subgroup intervals. Each
# sampled PSU carries all episodes contributed by women in that cluster.
B <- as.integer(Sys.getenv('NIGERIA_ALL_REASON_MODEL_BOOTSTRAP_REPS','300'))
frame <- full_frame;frame$id <- seq_len(nrow(frame))
strata <- split(frame$id,frame$stratum)
stopifnot(!anyDuplicated(frame$cluster),all(lengths(strata)>1L))
zone_draws <- matrix(NA_real_,B,nrow(zone_rows)*2L)
subgroup_draws <- matrix(NA_real_,B,nrow(subgroup_rows))
for(b in seq_len(B)){
  set.seed(20261023L+b)
  mult <- numeric(nrow(frame))
  for(ids in strata){
    n <- length(ids)
    mult[ids] <- n/(n-1)*tabulate(sample.int(n,n-1,replace=TRUE),nbins=n)
  }
  lookup <- setNames(mult,frame$cluster)
  pw <- person$wt*lookup[as.character(person$cluster)]
  sw <- standard$wt*lookup[as.character(standard$cluster)]
  a <- tryCatch(fit(f1,pw),error=function(err)NULL)
  bfit <- tryCatch(fit(f2,pw),error=function(err)NULL)
  if(is.null(a)||is.null(bfit)||!a$converged||!bfit$converged)next
  for(j in seq_len(nrow(zone_rows))){
    z <- zone_rows$zone[j]
    zone_draws[b,j] <- zone_prediction(a,z,sw)
    zone_draws[b,j+nrow(zone_rows)] <- zone_prediction(bfit,z,sw)
  }
  for(j in seq_len(nrow(subgroup_rows))){
    d <- standard
    v <- subgroup_rows$covariate[j]
    d[[v]] <- factor(subgroup_rows$category[j],levels=levels(e[[v]]))
    subgroup_draws[b,j] <- predict_risk(bfit,d,sw)
  }
}
if(sum(complete.cases(zone_draws))<ceiling(.9*B))stop('Too few all-reason model bootstrap refits')
for(j in seq_len(nrow(zone_rows))){
  zone_rows$model_1_low[j] <- quantile(zone_draws[,j],.025,na.rm=TRUE)
  zone_rows$model_1_high[j] <- quantile(zone_draws[,j],.975,na.rm=TRUE)
  k <- j+nrow(zone_rows)
  zone_rows$model_2_low[j] <- quantile(zone_draws[,k],.025,na.rm=TRUE)
  zone_rows$model_2_high[j] <- quantile(zone_draws[,k],.975,na.rm=TRUE)
}
for(j in seq_len(nrow(subgroup_rows))){
  subgroup_rows$ci_low[j] <- quantile(subgroup_draws[,j],.025,na.rm=TRUE)
  subgroup_rows$ci_high[j] <- quantile(subgroup_draws[,j],.975,na.rm=TRUE)
}
write.csv(zone_rows,file.path(support,'nigeria_all_reason_zone_models.csv'),row.names=FALSE)
write.csv(subgroup_rows,file.path(support,'nigeria_all_reason_adjusted_subgroups.csv'),row.names=FALSE)
cat('All-reason adjusted zone/subgroup output saved:',nrow(zone_rows),nrow(subgroup_rows),'rows\n')
)----------------------")

MODULES[["15_nigeria_initiation_mix.R"]] <- list(language="R", packaged_sha256="2a49bb418badb47a74e70e11fc89e478441e6e2601deb5b204ab1f935b3d5f64", args=character(0), code=r"----------------------(if(!requireNamespace('haven',quietly=TRUE))stop('Install R package haven first.')
# DHS complex survey design for this module.
.dhs_root <- Sys.getenv('NIGERIA_PROJECT_ROOT')
if (!nzchar(.dhs_root)) {
 .dhs_file <- sub('^--file=','',grep('^--file=',commandArgs(FALSE),value=TRUE)[1])
 .dhs_root <- dirname(dirname(normalizePath(.dhs_file)))
}
source(file.path(.dhs_root,'Code','dhs_survey_tools.R'),local=TRUE)
dhs_set_context(country='Nigeria',root=.dhs_root)
#!/usr/bin/env Rscript
# Nigeria counterpart of the Ethiopia initiation-mix diagnostic. These are
# weighted, observed calendar starts, not current use (v312) and not a life-
# table denominator. The 2024 calendar year is incomplete under the DHS
# 3–62-month analysis window and is therefore flagged rather than interpreted
# as a complete annual trend.
root <- Sys.getenv("NIGERIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
e <- readRDS(file.path(root,'Data/Derived/nigeria_2024_table_7_12_episodes.rds'))
e <- e[e$entry==0L,]
modern <- c(1L,2L,3L,5L,6L,7L,11L,13L,14L,15L,17L,18L,19L,20L)
e$method_start <- 'Non-modern methods'
e$method_start[e$method_code %in% modern] <- 'Other modern'
e$method_start[e$method_code==1L] <- 'Pill'
e$method_start[e$method_code==2L] <- 'IUD'
e$method_start[e$method_code==3L] <- 'Injectables'
e$method_start[e$method_code==11L] <- 'Implants'
e$method_start[e$method_code==16L] <- 'Emergency contraception'
e$year <- (e$start-1L)%/%12L+1900L
methods <- c('Injectables','Implants','Pill','IUD','Emergency contraception',
  'Other modern','Non-modern methods')
scope <- c('Overall',as.character(2021:2024))
rows <- list()
for(s in scope){
  d <- if(s=='Overall')e else e[e$year==as.integer(s),]
  total <- sum(d$wt)
  for(m in methods){
    selected <- d$method_start==m
    rows[[length(rows)+1L]] <- data.frame(scope=s,method=m,
      start_share_pct=100*sum(d$wt[selected])/total,
      weighted_starts=sum(d$wt[selected]),observed_starts_n=sum(selected),
      denominator_weighted_starts=total,denominator_observed_starts_n=nrow(d),
      incomplete_year=s=='2024')
  }
}
z <- do.call(rbind,rows)
stopifnot(max(abs(aggregate(start_share_pct~scope,z,sum)$start_share_pct-100))<1e-8)
write.csv(z,file.path(root,'output/Supporting_data/nigeria_initiation_mix_overall_by_year.csv'),row.names=FALSE)

# For the regional presentation, use the same denominator as Ethiopia's
# regional initiation-mix and paired start-share figures: ALL observed method
# starts in that geography. This includes non-modern methods and EC. It is
# deliberately distinct from the modern-method episode cohort used for the
# discontinuation probabilities on the paired bars.
zone_names <- c('North West','North East','North Central','South East',
  'South South','South West')
e$zone_name <- zone_names[e$zone]
zone_rows <- list()
for (zone in c('National',zone_names)) {
  d <- if (zone=='National') e else e[e$zone_name==zone,]
  denominator <- sum(d$wt)
  for (method in methods) {
    selected <- d$method_start==method
    zone_rows[[length(zone_rows)+1L]] <- data.frame(
      scope=zone, method=method, start_share_pct=100*sum(d$wt[selected])/denominator,
      weighted_starts=sum(d$wt[selected]), observed_starts_n=sum(selected),
      denominator_weighted_starts=denominator,
      denominator_observed_starts_n=nrow(d))
  }
}
zone_mix <- do.call(rbind,zone_rows)
stopifnot(max(abs(aggregate(start_share_pct~scope,zone_mix,sum)$start_share_pct-100))<1e-8)
write.csv(zone_mix,file.path(root,'output/Supporting_data/nigeria_zone_all_method_start_mix.csv'),row.names=FALSE)
print(z[z$scope=='Overall',c('method','start_share_pct')],row.names=FALSE)
)----------------------")

MODULES[["17_nigeria_selected_reason_models.R"]] <- list(language="R", packaged_sha256="9281435ee9fea6814ffb40ec6b0270ac79bdf8770edc46dc2de5de1496dcb163", args=character(0), code=r"----------------------(if(!requireNamespace('haven',quietly=TRUE))stop('Install R package haven first.')
# DHS complex survey design for this module.
.dhs_root <- Sys.getenv('NIGERIA_PROJECT_ROOT')
if (!nzchar(.dhs_root)) {
 .dhs_file <- sub('^--file=','',grep('^--file=',commandArgs(FALSE),value=TRUE)[1])
 .dhs_root <- dirname(dirname(normalizePath(.dhs_file)))
}
source(file.path(.dhs_root,'Code','dhs_survey_tools.R'),local=TRUE)
dhs_set_context(country='Nigeria',root=.dhs_root)
#!/usr/bin/env Rscript
# Ethiopia-style selected-reason counterpart for Nigeria. The event is ending
# for any recorded reason except wanted pregnancy (calendar code 2) or partner
# disapproval (code 3). Those two endings remain competing events: they are in
# the initial episode cohort and leave the risk set when they occur.
root <- Sys.getenv("NIGERIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
full_ir <- readRDS(file.path(root,'Data/raw_dhs_ir/NG2024DHS__NGIR8BDT__IR_raw.rds'))
full_frame <- unique(data.frame(cluster=as.numeric(full_ir$v021),stratum=as.numeric(full_ir$v022)))

derived <- file.path(root,'Data/Derived')
support <- file.path(root,'output/Supporting_data')
if(!requireNamespace('nnet',quietly=TRUE))stop('nnet package is required')
e <- readRDS(file.path(derived,'nigeria_2024_model_episode_covariates.rds'))
person <- readRDS(file.path(derived,'nigeria_2024_person_month.rds'))
observed_months <- pmax(0L,pmin(12L,e$exposure)-e$entry)
idx <- rep(seq_len(nrow(e)),observed_months)
month <- unlist(Map(function(first,n)seq.int(first+1L,length.out=n),
  e$entry,observed_months),use.names=FALSE)
stopifnot(length(idx)==nrow(person),length(month)==nrow(person))
end <- e$discontinued[idx] & month==e$exposure[idx]
person$selected_outcome <- factor(ifelse(!end,'continue',
  ifelse(e$reason_code[idx] %in% c(2L,3L),'competing','selected')),
  levels=c('continue','selected','competing'))
stopifnot(!anyNA(person$selected_outcome))

f1 <- selected_outcome~month+method_group+zone_name
f2 <- selected_outcome~month+method_group+zone_name+age_group+parity_group+
  marital_group+education+wealth+residence+start_year
fit <- function(formula,weights){
  person$fit_weight <- weights
  m <- dhs_multinom_fit(formula,data=person,weights=fit_weight,trace=FALSE,
    maxit=350,MaxNWts=10000)
  if(m$convergence!=0L)stop('Selected-reason model failed to converge')
  m
}
m1 <- fit(f1,person$wt)
m2 <- fit(f2,person$wt)
saveRDS(m1,file.path(derived,'nigeria_selected_reason_model_1.rds'))
saveRDS(m2,file.path(derived,'nigeria_selected_reason_model_2.rds'))

reference <- e[e$entry==0L,]
zones <- levels(e$zone_name)
predict_cif <- function(model,data=reference,weights=data$wt){
  d <- data
  survival <- rep(1,nrow(d)); risk <- numeric(nrow(d))
  for(t in 1:12){
    d$month <- factor(t,levels=1:12)
    prob <- predict(model,newdata=d,type='probs')
    risk <- risk+survival*prob[,'selected']
    survival <- survival*prob[,'continue']
  }
  100*weighted.mean(risk,weights)
}
zone_prediction <- function(model,z,weights=reference$wt){
  d <- reference
  if(z!='National')d$zone_name <- factor(z,levels=zones)
  predict_cif(model,d,weights)
}
all_times <- read.csv(file.path(support,'nigeria_modern_all_reason_timepoints.csv'))
zone_rows <- do.call(rbind,lapply(c('National',zones),function(z){
  raw <- all_times[all_times$scope==z & all_times$month==12,]
  data.frame(zone=z,eligible_episodes_n=raw$eligible_episodes_n,
    unadjusted_pct=raw$selected_reason_pct,
    unadjusted_low=raw$selected_reason_ci_low,
    unadjusted_high=raw$selected_reason_ci_high,
    model_1_pct=zone_prediction(m1,z),model_2_pct=zone_prediction(m2,z))
}))
subgroup_vars <- c('age_group','parity_group','marital_group','education',
  'wealth','residence')
subgroup_rows <- list()
for(v in subgroup_vars)for(level in levels(e[[v]])){
  d <- reference
  d[[v]] <- factor(level,levels=levels(e[[v]]))
  subgroup_rows[[length(subgroup_rows)+1L]] <- data.frame(
    covariate=v,category=level,adjusted_12_month_pct=predict_cif(m2,d))
}
subgroup_rows <- do.call(rbind,subgroup_rows)

# Survey-design uncertainty: resample PSUs within each sample stratum and
# retain all episodes from every sampled PSU, including repeated respondents.
B <- as.integer(Sys.getenv('NIGERIA_SELECTED_MODEL_BOOTSTRAP_REPS','300'))
frame <- full_frame;frame$id <- seq_len(nrow(frame))
strata <- split(frame$id,frame$stratum)
stopifnot(!anyDuplicated(frame$cluster),all(lengths(strata)>1L))
zone_draws <- matrix(NA_real_,B,nrow(zone_rows)*2L)
subgroup_draws <- matrix(NA_real_,B,nrow(subgroup_rows))
one <- function(b){
 Z<-rep(NA_real_,nrow(zone_rows)*2L); S<-rep(NA_real_,nrow(subgroup_rows))
  set.seed(20261024L+b)
  mult <- numeric(nrow(frame))
  for(ids in strata){
    n <- length(ids)
    mult[ids] <- n/(n-1)*tabulate(sample.int(n,n-1,replace=TRUE),nbins=n)
  }
  lookup <- setNames(mult,frame$cluster)
  pw <- person$wt*lookup[as.character(person$cluster)]
  sw <- reference$wt*lookup[as.character(reference$cluster)]
  a <- tryCatch(fit(f1,pw),error=function(err)NULL)
  bfit <- tryCatch(fit(f2,pw),error=function(err)NULL)
  if(is.null(a)||is.null(bfit))return(list(Z=Z,S=S))
  for(j in seq_len(nrow(zone_rows))){
    z <- zone_rows$zone[j]
    Z[j] <- zone_prediction(a,z,sw)
    Z[j+nrow(zone_rows)] <- zone_prediction(bfit,z,sw)
  }
  for(j in seq_len(nrow(subgroup_rows))){
    d <- reference
    v <- subgroup_rows$covariate[j]
    d[[v]] <- factor(subgroup_rows$category[j],levels=levels(e[[v]]))
    S[j] <- predict_cif(bfit,d,sw)
  }
return(list(Z=Z,S=S))
}
drawlist<-parallel::mclapply(seq_len(B),one,mc.cores=4L,mc.preschedule=FALSE)
zone_draws<-do.call(rbind,lapply(drawlist,`[[`,"Z"));subgroup_draws<-do.call(rbind,lapply(drawlist,`[[`,"S"))

if(sum(complete.cases(zone_draws))<ceiling(.9*B))stop('Too few selected-reason bootstrap refits')
for(j in seq_len(nrow(zone_rows))){
  zone_rows$model_1_low[j] <- quantile(zone_draws[,j],.025,na.rm=TRUE)
  zone_rows$model_1_high[j] <- quantile(zone_draws[,j],.975,na.rm=TRUE)
  k <- j+nrow(zone_rows)
  zone_rows$model_2_low[j] <- quantile(zone_draws[,k],.025,na.rm=TRUE)
  zone_rows$model_2_high[j] <- quantile(zone_draws[,k],.975,na.rm=TRUE)
}
for(j in seq_len(nrow(subgroup_rows))){
  subgroup_rows$ci_low[j] <- quantile(subgroup_draws[,j],.025,na.rm=TRUE)
  subgroup_rows$ci_high[j] <- quantile(subgroup_draws[,j],.975,na.rm=TRUE)
}
write.csv(zone_rows,file.path(support,'nigeria_selected_reason_zone_models.csv'),row.names=FALSE)
write.csv(subgroup_rows,file.path(support,'nigeria_selected_reason_adjusted_subgroups.csv'),row.names=FALSE)
cat('Selected-reason adjusted zone/subgroup output saved:',nrow(zone_rows),nrow(subgroup_rows),'rows\n')
)----------------------")

MODULES[["22_nigeria_landmark_support.R"]] <- list(language="R", packaged_sha256="1510714ffa80d6c0922fac4ba9732126ab94f196014f2ae246fe67ace01c203c", args=character(0), code=r"----------------------(if(!requireNamespace('haven',quietly=TRUE))stop('Install R package haven first.')
# DHS complex survey design for this module.
.dhs_root <- Sys.getenv('NIGERIA_PROJECT_ROOT')
if (!nzchar(.dhs_root)) {
 .dhs_file <- sub('^--file=','',grep('^--file=',commandArgs(FALSE),value=TRUE)[1])
 .dhs_root <- dirname(dirname(normalizePath(.dhs_file)))
}
source(file.path(.dhs_root,'Code','dhs_survey_tools.R'),local=TRUE)
dhs_set_context(country='Nigeria',root=.dhs_root)
#!/usr/bin/env Rscript
# Audit historical landmarks available for a prospective 12-month trajectory.
# A landmark is a month of current modern use at an observed duration since
# starting the original method, with 12 further calendar months observed.
root <- Sys.getenv("NIGERIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
events <- readRDS(file.path(root,'Data/Derived/nigeria_2024_calendar_events.rds'))
ir <- readRDS(file.path(root,'Data/raw_dhs_ir/NG2024DHS__NGIR8BDT__IR_raw.rds'))
modern <- c(1L,2L,3L,5L,11L,13L,14L,15L,17L,18L,19L,20L)
grp <- function(code) ifelse(code==3L,'Injectables',ifelse(code==11L,'Implants',ifelse(code==1L,'Pill',ifelse(code==2L,'IUD','Other modern'))))
br <- c(-1,3,6,12,24,36,48,60,Inf)
labs <- c('0–3','4–6','7–12','13–24','25–36','37–48','49–60','61+')
current <- ir[as.numeric(ir$v313)==3 & !as.numeric(ir$v312)%in%c(6L,7L,16L),]
current$method <- grp(as.integer(current$v312))
current$bin <- cut(as.numeric(current$v337),br,labels=labs)
cat('CURRENT USERS BY METHOD AND DURATION\n')
print(with(current,table(method,bin)),quote=FALSE)
valid <- events[events$method_code %in% modern & events$start>events$calendar_start,]
land <- vector('list',nrow(valid))
for(i in seq_len(nrow(valid))){
  a <- valid[i,]
  ts <- seq.int(a$start,min(a$end,a$interview-15L))
  ts <- ts[ts>=a$calendar_start]
  if(length(ts)==0L) next
  land[[i]] <- data.frame(method=grp(a$method_code),duration=ts-a$start+1L,wt=a$wt)
}
land <- do.call(rbind,land[!vapply(land,is.null,logical(1))])
land$bin <- cut(land$duration-1L,br,labels=labs)
cat('HISTORICAL OBSERVED LANDMARKS WITH FOLLOW-UP\n')
print(with(land,table(method,bin)),quote=FALSE)
)----------------------")

MODULES[["23_nigeria_current_user_switch_and_duration.R"]] <- list(language="R", packaged_sha256="72f372be10bfd95750d313565717ac8de18c51d1719811f29618b75e1c7845e7", args=character(0), code=r"----------------------(if(!requireNamespace('haven',quietly=TRUE))stop('Install R package haven first.')
# DHS complex survey design for this module.
.dhs_root <- Sys.getenv('NIGERIA_PROJECT_ROOT')
if (!nzchar(.dhs_root)) {
 .dhs_file <- sub('^--file=','',grep('^--file=',commandArgs(FALSE),value=TRUE)[1])
 .dhs_root <- dirname(dirname(normalizePath(.dhs_file)))
}
source(file.path(.dhs_root,'Code','dhs_survey_tools.R'),local=TRUE)
dhs_set_context(country='Nigeria',root=.dhs_root)
#!/usr/bin/env Rscript
# Nigeria DHS 2024: transparent bridges from original-method endings to
# modern-use status among projected current users. This script does not
# estimate a causal effect of preventing discontinuation.
#
# Bridge A retains the earlier first-year life-table estimates, applies them
# to projected 2025 current-user counts, and subtracts observed direct
# modern-to-modern switches. It is illustrative because current users have
# already accrued varying months on their methods.
#
# Bridge B emulates a 12-month follow-up from historical calendar months in
# which a woman was using a modern method. Matching on method and elapsed
# duration, it estimates the chance that her original method ends for an
# actionable reason, that she immediately switches, and whether she uses any
# modern method 12 months after that landmark. It standardizes these risks to
# the weighted duration distribution of DHS 2024 current users, then applies
# them to the projected 2025 stock. This is descriptive and makes a strong
# stationarity assumption when transported from history to 2025–26.

root <- Sys.getenv("NIGERIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
out <- file.path(root,'output/Supporting_data')
data_dir <- file.path(root,'Data/Derived')
ir <- readRDS(file.path(root,'Data/raw_dhs_ir/NG2024DHS__NGIR8BDT__IR_raw.rds'))
episodes <- readRDS(file.path(data_dir,'nigeria_2024_modern_episodes.rds'))
episodes <- episodes[!episodes$method_code %in% c(6L,7L),]
calendar <- readRDS(file.path(data_dir,'nigeria_2024_calendar_events.rds'))
users <- read.csv(file.path(out,'nigeria_current_users_by_method_and_actionable_projection.csv'))
scenario <- read.csv(file.path(out,'nigeria_2026_mcpr_scenarios.csv'))
stopifnot(nrow(ir)==39050L,all(c('method','current_users_2025','illustrative_original_method_endings') %in% names(users)))

modern <- c(1L,2L,3L,5L,11L,13L,14L,15L,17L,18L,19L,20L)
methods <- c('Injectables','Implants','Pill','IUD','Other modern')
causes <- c('Method failure','Wanted more effective method','Changes in menstrual bleeding',
            'Other side effects/health','Access/cost/convenience')
method_group <- function(z) ifelse(z==3L,'Injectables',ifelse(z==11L,'Implants',
  ifelse(z==1L,'Pill',ifelse(z==2L,'IUD','Other modern'))))
cause_group <- function(z) ifelse(z==1L,causes[1],ifelse(z==7L,causes[2],
  ifelse(z==15L,causes[3],ifelse(z %in% c(4L,5L),causes[4],
  ifelse(z %in% c(6L,8L,10L),causes[5],NA_character_)))))
roundint <- function(z) as.integer(round(z))

# A. Projected 2025 stock × original-method life-table risk. The direct
# switch fraction is measured among observed actionable first-year endings.
episodes$actionable <- episodes$discontinued & episodes$exposure<=12 &
  episodes$reason_code %in% c(1L,4L,5L,6L,7L,8L,10L,15L)
endings <- episodes[episodes$actionable,]
endings$method <- method_group(endings$method_code)
endings$cause <- cause_group(endings$reason_code)
endings$direct_modern <- endings$next_code %in% c(modern,6L,7L,14L,16L)
endings$direct_modern[is.na(endings$direct_modern)] <- FALSE
stopifnot(!anyNA(endings$cause))
bridge <- users[match(methods,users$method),c('method','current_users_2025',
  'actionable_first_year_risk_pct','illustrative_original_method_endings')]
bridge$observed_actionable_endings_n <- NA_integer_
bridge$direct_modern_switch_pct <- NA_real_
bridge$illustrative_direct_modern_switchers <- NA_real_
bridge$illustrative_not_directly_switching <- NA_real_
for(i in seq_len(nrow(bridge))){
  d <- endings[endings$method==bridge$method[i],]
  bridge$observed_actionable_endings_n[i] <- nrow(d)
  bridge$direct_modern_switch_pct[i] <- 100*sum(d$wt[d$direct_modern])/sum(d$wt)
  bridge$illustrative_direct_modern_switchers[i] <- bridge$illustrative_original_method_endings[i]*
    bridge$direct_modern_switch_pct[i]/100
  bridge$illustrative_not_directly_switching[i] <- bridge$illustrative_original_method_endings[i]-
    bridge$illustrative_direct_modern_switchers[i]
}
write.csv(bridge,file.path(out,'nigeria_switch_bridge_by_method.csv'),row.names=FALSE)

cause_bridge <- do.call(rbind,lapply(methods,function(m)do.call(rbind,lapply(causes,function(cause){
  d <- endings[endings$method==m & endings$cause==cause,]
  base <- read.csv(file.path(out,'nigeria_current_users_actionable_by_cause.csv'))
  projected <- base$illustrative_users[base$method==m & base$reason==cause]
  stopifnot(length(projected)==1L)
  frac <- if(nrow(d)>0)sum(d$wt[d$direct_modern])/sum(d$wt) else 0
  data.frame(method=m,reason=cause,observed_endings_n=nrow(d),
    illustrative_original_method_endings=projected,direct_modern_switch_pct=100*frac,
    illustrative_direct_modern_switchers=projected*frac,
    illustrative_not_directly_switching=projected*(1-frac))
}))))
# Calibrate the cause-specific allocations to the independently estimated
# method total, so every cause table reconciles exactly to the bridge above.
# This preserves the relative observed switching pattern across causes.
# Cause-specific direct-switch counts stay bounded by their own endings.
for(m in methods){
 ix <- cause_bridge$method==m
 j <- which(bridge$method==m)
 total <- sum(cause_bridge$illustrative_direct_modern_switchers[ix])
 bridge$illustrative_direct_modern_switchers[j] <- total
 bridge$illustrative_not_directly_switching[j] <- bridge$illustrative_original_method_endings[j]-total
 bridge$direct_modern_switch_pct[j] <- 100*total/bridge$illustrative_original_method_endings[j]
}
write.csv(bridge,file.path(out,'nigeria_switch_bridge_by_method.csv'),row.names=FALSE)
write.csv(cause_bridge,file.path(out,'nigeria_switch_bridge_by_method_cause.csv'),row.names=FALSE)

# B. The retrospective calendar is recorded in month units. A landmark can
# be used only if a full 12 future calendar months are visible and the
# original modern-method start is visible (not left censored at calendar start).
# Follow-up uses months t+1 through t+12. At month 12, modern-to-modern
# switchers and later modern restarters are both counted as modern users.
by_woman <- split(seq_len(nrow(calendar)),calendar$woman_row)
eligible_spells <- calendar[calendar$method_code %in% modern &
  calendar$start>calendar$calendar_start,]
bins <- c(-1,3,6,12,24,36,48,60,Inf)
bin_labels <- c('0–3','4–6','7–12','13–24','25–36','37–48','49–60','61+')
records <- vector('list',nrow(eligible_spells))
for(i in seq_len(nrow(eligible_spells))){
  a <- eligible_spells[i,]
  last <- min(a$end,a$interview-15L)
  if(last<a$start) next
  landmark <- seq.int(a$start,last)
  future <- landmark+12L
  person_events <- calendar[by_woman[[as.character(a$woman_row)]],]
  next_event <- findInterval(future,person_events$start)
  stopifnot(all(next_event>0L),all(person_events$end[next_event]>=future))
  code12 <- person_events$method_code[next_event]
  action <- a$end<future & a$reason_code %in% c(1L,4L,5L,6L,7L,8L,10L,15L)
  direct <- action & a$next_code %in% c(modern,6L,7L,14L,16L)
  direct[is.na(direct)] <- FALSE
  modern12 <- code12 %in% c(modern,6L,7L,14L,16L)
  records[[i]] <- data.frame(woman_row=a$woman_row,method=method_group(a$method_code),
    duration_completed=landmark-a$start,wt=a$wt,actionable=action,
    ending_reason_code=ifelse(a$end<future,a$reason_code,NA_integer_),
    direct_switch=direct,modern_at_month12=modern12,
    actionable_nonmodern_at_month12=action & !modern12,
    actionable_modern_at_month12=action & modern12,
    cause=ifelse(action,cause_group(a$reason_code),NA_character_))
}
landmarks <- do.call(rbind,records[!vapply(records,is.null,logical(1))])
landmarks$duration_bin <- cut(landmarks$duration_completed,bins,labels=bin_labels)
saveRDS(landmarks,file.path(data_dir,'nigeria_historical_duration_landmarks.rds'))
stopifnot(nrow(landmarks)>50000L,!anyNA(landmarks$duration_bin),
  all(landmarks$direct_switch<=landmarks$actionable),
  all(landmarks$actionable_nonmodern_at_month12+landmarks$actionable_modern_at_month12==landmarks$actionable))

current <- ir[as.numeric(ir$v313)==3 & !as.numeric(ir$v312)%in%c(6L,7L,16L),]
current$method <- method_group(as.integer(current$v312))
current$duration_completed <- as.numeric(current$v337)
current$duration_bin <- cut(current$duration_completed,bins,labels=bin_labels)
current$wt <- as.numeric(current$v005)/1e6
stopifnot(!anyNA(current$duration_bin),all(current$method %in% methods))

# No landmark with elapsed duration 61+ can have a complete following year
# inside the recorded calendar. The main scenario assigns the observed 37–60
# month risk to these long-duration users. This is an explicit extrapolation.
# We also retain the share of projected users who require that extrapolation.
outcome_cols <- c('actionable','direct_switch','actionable_nonmodern_at_month12',
                  'actionable_modern_at_month12','modern_at_month12')
estimate_bin <- function(d){
  c(n_landmarks=nrow(d),n_women=length(unique(d$woman_row)),
    setNames(vapply(outcome_cols,function(k)sum(d$wt*as.numeric(d[[k]]))/sum(d$wt),0.0),outcome_cols))
}
bin_rows <- list()
for(m in methods)for(b in bin_labels[1:7]){
  d <- landmarks[landmarks$method==m & landmarks$duration_bin==b,]
  cc <- current[current$method==m & current$duration_bin==b,]
  z <- estimate_bin(d)
  bin_rows[[length(bin_rows)+1L]] <- data.frame(method=m,duration_bin=b,
    current_users_n=nrow(cc),current_weight=sum(cc$wt),as.list(z),
    proxy_for_61plus=FALSE)
}
for(m in methods){
  d <- landmarks[landmarks$method==m & landmarks$duration_bin %in% c('37–48','49–60'),]
  cc <- current[current$method==m & current$duration_bin=='61+',]
  z <- estimate_bin(d)
  bin_rows[[length(bin_rows)+1L]] <- data.frame(method=m,duration_bin='61+',
    current_users_n=nrow(cc),current_weight=sum(cc$wt),as.list(z),
    proxy_for_61plus=TRUE)
}
duration_bins <- do.call(rbind,bin_rows)
write.csv(duration_bins,file.path(out,'nigeria_duration_landmark_support_and_risks.csv'),row.names=FALSE)

duration <- do.call(rbind,lapply(methods,function(m){
  z <- duration_bins[duration_bins$method==m,]
  stock <- users$current_users_2025[users$method==m]
  shares <- z$current_weight/sum(z$current_weight)
  risk <- function(k)sum(shares*z[[k]])
  gross <- stock*risk('actionable')
  direct <- stock*risk('direct_switch')
  modern_after <- stock*risk('actionable_modern_at_month12')
  nonmodern_after <- stock*risk('actionable_nonmodern_at_month12')
  data.frame(method=m,current_users_2025=stock,current_users_n=sum(z$current_users_n),
    current_users_61plus_n=z$current_users_n[z$duration_bin=='61+'],
    current_users_61plus_share_pct=100*shares[z$duration_bin=='61+'],
    actionable_ending_risk_next12_pct=100*risk('actionable'),
    projected_actionable_original_method_endings=gross,
    projected_direct_modern_switchers=direct,
    projected_not_directly_switching=gross-direct,
    projected_modern_at_month12_after_actionable=modern_after,
    projected_nonmodern_at_month12_after_actionable=nonmodern_after,
    descriptive_nonmodern_at_month12_pp=100*nonmodern_after/scenario$wra_2026[1])
}))
stopifnot(max(abs(duration$projected_actionable_original_method_endings-
    duration$projected_modern_at_month12_after_actionable-
    duration$projected_nonmodern_at_month12_after_actionable))<1e-5)
write.csv(duration,file.path(out,'nigeria_duration_aware_current_user_bridge.csv'),row.names=FALSE)

# Cause-specific endpoints use the same current-user duration weights.
cause_duration <- do.call(rbind,lapply(methods,function(m)do.call(rbind,lapply(causes,function(cause){
  current_bins <- duration_bins[duration_bins$method==m,]
  shares <- current_bins$current_weight/sum(current_bins$current_weight)
  results <- matrix(NA_real_,nrow=length(bin_labels),ncol=3)
  for(j in seq_along(bin_labels)){
    b <- bin_labels[j]
    observed_bins <- if(b=='61+') c('37–48','49–60') else b
    d <- landmarks[landmarks$method==m & landmarks$duration_bin %in% observed_bins,]
    flag <- !is.na(d$cause) & d$cause==cause
    results[j,] <- c(sum(d$wt*flag),sum(d$wt*flag*d$direct_switch),
      sum(d$wt*flag*(!d$modern_at_month12)))/sum(d$wt)
  }
  risk <- colSums(results*shares)
  stock <- users$current_users_2025[users$method==m]
  data.frame(method=m,reason=cause,current_users_2025=stock,
    projected_actionable_original_method_endings=stock*risk[1],
    projected_direct_modern_switchers=stock*risk[2],
    projected_nonmodern_at_month12=stock*risk[3])
}))))
for(m in methods){
  a <- cause_duration[cause_duration$method==m,]
  b <- duration[duration$method==m,]
  stopifnot(abs(sum(a$projected_actionable_original_method_endings)-b$projected_actionable_original_method_endings)<1e-5,
            abs(sum(a$projected_nonmodern_at_month12)-b$projected_nonmodern_at_month12)<1e-5)
}
write.csv(cause_duration,file.path(out,'nigeria_duration_aware_current_user_by_cause.csv'),row.names=FALSE)

scenario_bridge <- scenario[,c('scenario','mcpr_2026_pct','usual_users_2026','wra_2026')]
scenario_bridge$first_year_gross_endings <- sum(bridge$illustrative_original_method_endings)
scenario_bridge$first_year_not_directly_switching <- sum(bridge$illustrative_not_directly_switching)
scenario_bridge$duration_aware_actionable_endings <- sum(duration$projected_actionable_original_method_endings)
scenario_bridge$duration_aware_not_directly_switching <- sum(duration$projected_not_directly_switching)
scenario_bridge$duration_aware_nonmodern_at_month12 <- sum(duration$projected_nonmodern_at_month12_after_actionable)
scenario_bridge$descriptive_nonmodern_at_month12_pp <-
  100*scenario_bridge$duration_aware_nonmodern_at_month12/scenario_bridge$wra_2026
scenario_bridge$illustrative_mcpr_if_all_endpoint_users_retained <-
  scenario_bridge$mcpr_2026_pct+scenario_bridge$descriptive_nonmodern_at_month12_pp
write.csv(scenario_bridge,file.path(out,'nigeria_switch_duration_mcpr_scenarios.csv'),row.names=FALSE)
# Sensitivity to the unsupported 61+ duration group: replace its proxy with
# either the observed 37–48 or 49–60 month risk (the main estimate pools both).
long_sensitivity <- do.call(rbind,lapply(c('37–48','49–60'),function(proxy){
  total <- 0
  for(m in methods){
    z <- duration_bins[duration_bins$method==m,]
    shares <- z$current_weight/sum(z$current_weight)
    z$actionable_nonmodern_at_month12[z$duration_bin=='61+'] <-
      z$actionable_nonmodern_at_month12[z$duration_bin==proxy]
    total <- total + users$current_users_2025[users$method==m]*
      sum(shares*z$actionable_nonmodern_at_month12)
  }
  data.frame(proxy_for_61plus=proxy,projected_nonmodern_at_month12=total,
    illustrative_pp=100*total/scenario$wra_2026[1])
}))
write.csv(long_sensitivity,file.path(out,'nigeria_duration_61plus_sensitivity.csv'),row.names=FALSE)
cat('Historical landmarks:',nrow(landmarks),'from',length(unique(landmarks$woman_row)),
  'women. Current non-EC modern users:',nrow(current),'\n')
print(duration[,c('method','current_users_61plus_share_pct','actionable_ending_risk_next12_pct',
  'projected_actionable_original_method_endings','projected_nonmodern_at_month12_after_actionable')],row.names=FALSE)
print(scenario_bridge[,c('scenario','first_year_gross_endings','first_year_not_directly_switching',
  'duration_aware_actionable_endings','duration_aware_nonmodern_at_month12',
  'descriptive_nonmodern_at_month12_pp')],row.names=FALSE)
)----------------------")

MODULES[["25_duration_aware_cause_pp_tables.R"]] <- list(language="R", packaged_sha256="13fc649893ca2b2155a50d65008bba12f70aba8c6107d08e3429962db23c1b27", args=character(0), code=r"----------------------(if(!requireNamespace('haven',quietly=TRUE))stop('Install R package haven first.')
# DHS complex survey design for this module.
.dhs_root <- Sys.getenv('NIGERIA_PROJECT_ROOT')
if (!nzchar(.dhs_root)) {
 .dhs_file <- sub('^--file=','',grep('^--file=',commandArgs(FALSE),value=TRUE)[1])
 .dhs_root <- dirname(dirname(normalizePath(.dhs_file)))
}
source(file.path(.dhs_root,'Code','dhs_survey_tools.R'),local=TRUE)
dhs_set_context(country='Nigeria',root=.dhs_root)
# Recreate the method-by-cause percentage-point matrix from the duration-aware
# current-user analysis. The source CSV contains survey-derived projections of
# women who end their current method for an actionable reason and are not using
# any modern method 12 months after the current-use landmark. It has already
# accounted for subsequent modern switching and restarting.
#
# Run with Rscript from any directory. No extra packages are required.

args <- commandArgs(trailingOnly = FALSE)
file_arg <- args[grepl("^--file=", args)]
if (length(file_arg) != 1) stop("Run this file with Rscript")
script_path <- normalizePath(gsub("~\\+~", " ", sub("^--file=", "", file_arg)))
project <- dirname(dirname(script_path))
country <- "Nigeria"
support <- file.path(project, "output", "Supporting_data")

# Read the duration-aware projected counts and projected 2026 population.
cause_file <- file.path(support, paste0(tolower(country), "_duration_aware_current_user_by_cause.csv"))
scenario_file <- file.path(support, paste0(tolower(country), "_switch_duration_mcpr_scenarios.csv"))
causes <- read.csv(cause_file, check.names = FALSE, stringsAsFactors = FALSE)
scenarios <- read.csv(scenario_file, check.names = FALSE, stringsAsFactors = FALSE)
stopifnot(nrow(scenarios) >= 1, length(unique(scenarios$wra_2026)) == 1)
wra_2026 <- scenarios$wra_2026[1]

# Each cell's mCPR equivalent is its year-end count divided by women aged
# 15-49 in 2026. This is a descriptive maximum under perfect prevention of
# the associated ending, not a causal estimate of an intervention's effect.
causes$year_end_nonmodern <- as.numeric(causes$projected_nonmodern_at_month12)
causes$mcpr_equivalent_pp <- 100 * causes$year_end_nonmodern / wra_2026
causes$wra_2026 <- wra_2026
stopifnot(abs(sum(causes$year_end_nonmodern) -
              scenarios$duration_aware_nonmodern_at_month12[1]) < 1e-5)
stopifnot(abs(sum(causes$mcpr_equivalent_pp) -
              scenarios$descriptive_nonmodern_at_month12_pp[1]) < 1e-8)

out <- causes[c("method", "reason", "year_end_nonmodern", "mcpr_equivalent_pp", "wra_2026")]
output_file <- file.path(support, paste0(tolower(country), "_duration_aware_cause_pp_matrix.csv"))
write.csv(out, output_file, row.names = FALSE)
message("Saved ", output_file)
)----------------------")

MODULES[["26_nigeria_actionable_method_zone_models.R"]] <- list(language="R", packaged_sha256="d95e2eddd542f73cc5978d78b337b9fb0ba83d9ce3096cdc6fbbddca99eb459d", args=character(0), code=r"----------------------(if(!requireNamespace('haven',quietly=TRUE))stop('Install R package haven first.')
# DHS complex survey design for this module.
.dhs_root <- Sys.getenv('NIGERIA_PROJECT_ROOT')
if (!nzchar(.dhs_root)) {
 .dhs_file <- sub('^--file=','',grep('^--file=',commandArgs(FALSE),value=TRUE)[1])
 .dhs_root <- dirname(dirname(normalizePath(.dhs_file)))
}
source(file.path(.dhs_root,'Code','dhs_survey_tools.R'),local=TRUE)
dhs_set_context(country='Nigeria',root=.dhs_root)
#!/usr/bin/env Rscript
# Nigeria DHS 2024: within-method zone differences in first-year discontinuation
# for potentially actionable reasons. This is the Nigeria counterpart of the
# Ethiopia injectable/implant regional tests. Run scripts 01 and 03 first.
#
# Each risk set comprises eligible episodes of the stated original modern
# method. At an ending, actionable causes are the event of interest; every
# other reason is a competing event. Episodes observed after method initiation
# enter the monthly life table at their first observed month. The adjusted
# multinomial model uses one row per observed episode-month and includes month
# since method initiation, zone, age and parity at start, marital status,
# education, wealth, residence, and calendar start-year cohort. Region-specific
# predictions apply each zone coefficient to the same national distribution of
# observed-start episodes of that method. This standardizes composition but
# does not assume a program intervention or identify a causal zone effect.
#
# Survey uncertainty comes from resampling PSUs within DHS strata. Every
# episode from a selected PSU stays together, preserving repeated episodes
# from the same woman. Holm correction controls the 15 pairwise tests within
# each method and, separately, all 30 tests across the two methods.

root <- Sys.getenv("NIGERIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
full_ir <- readRDS(file.path(root,'Data/raw_dhs_ir/NG2024DHS__NGIR8BDT__IR_raw.rds'))
full_frame <- unique(data.frame(cluster=as.numeric(full_ir$v021),stratum=as.numeric(full_ir$v022)))

derived <- file.path(root, 'Data/Derived')
support <- file.path(root, 'output/Supporting_data')
stopifnot(requireNamespace('nnet', quietly=TRUE))
all_e <- readRDS(file.path(derived,'nigeria_2024_model_episode_covariates.rds'))
all_p <- readRDS(file.path(derived,'nigeria_2024_person_month.rds'))
zones <- c('North West','North East','North Central','South East',
           'South South','South West')
methods <- c('Injectables','Implants')
actionable <- c(1L,4L,5L,6L,7L,8L,10L,15L)
frame <- full_frame
frame$id <- seq_len(nrow(frame))
key <- function(s,c)paste(s,c,sep='::')
frame_key <- key(frame$stratum,frame$cluster)
all_e$psu_id <- frame$id[match(key(all_e$stratum,all_e$cluster),frame_key)]
all_p$psu_id <- frame$id[match(key(all_p$stratum,all_p$cluster),frame_key)]
stopifnot(!anyNA(all_e$psu_id),!anyNA(all_p$psu_id))
groups <- split(frame$id,frame$stratum)
stopifnot(all(lengths(groups)>1L))
K <- nrow(frame)
B <- as.integer(Sys.getenv('NIGERIA_METHOD_ZONE_REPS','400'))
stopifnot(B>=300L)

resample <- function(b) {
  set.seed(20261027L+b)
  mult <- numeric(K)
  for(ids in groups) {
    n <- length(ids)
    mult[ids] <- n/(n-1L)*
      tabulate(sample.int(n,n-1L,replace=TRUE),nbins=n)
  }
  mult
}
mults <- lapply(seq_len(B),resample)
formula <- outcome~month+zone_name+age_group+parity_group+
  marital_group+education+wealth+residence+start_year

get_method <- function(method) {
  e <- all_e[all_e$method_group==method,]
  p <- all_p[all_p$method_group==method,]
  e$zone_name <- factor(as.character(e$zone_name),levels=zones)
  p$zone_name <- factor(as.character(p$zone_name),levels=zones)
  ref <- e[e$entry==0L,]
  stopifnot(nrow(e)>1500,nrow(ref)>1200,
            all(table(e$zone_name)>=100))
  counts <- do.call(rbind,lapply(zones,function(z) {
    x <- e[e$zone_name==z,]
    selected <- x$discontinued & x$entry<x$exposure &
      x$exposure<=12L & x$reason_code %in% actionable
    data.frame(method=method,zone=z,eligible_episodes_n=nrow(x),
      actionable_endings_n=sum(selected),
      distinct_psus=length(unique(x$psu_id)))
  }))
  stopifnot(all(counts$actionable_endings_n>=20))

  # Cache weighted monthly risk sets by PSU. This is the same competing-risk
  # life-table formula used for the all-modern and Ethiopia method estimates.
  arrays <- lapply(zones,function(z) {
    risk <- ended <- chosen <- matrix(0,K,12L)
    scope <- e$zone_name==z
    for(t in 1:12) {
      at <- scope & e$entry<t & e$exposure>=t
      stop <- at & e$discontinued & e$exposure==t
      selected <- stop & e$reason_code %in% actionable
      for(item in c('risk','ended','chosen')) {
        mask <- switch(item,risk=at,ended=stop,chosen=selected)
        if(any(mask)) {
          sums <- rowsum(e$wt[mask],e$psu_id[mask],reorder=FALSE)
          target <- get(item)
          target[as.integer(rownames(sums)),t] <- sums[,1L]
          assign(item,target)
        }
      }
    }
    list(risk=risk,ended=ended,chosen=chosen)
  })
  names(arrays) <- zones
  cif <- function(a,mult) {
    R <- as.numeric(crossprod(mult,a$risk))
    E <- as.numeric(crossprod(mult,a$ended))
    C <- as.numeric(crossprod(mult,a$chosen))
    if(any(R<=0) || any(E>R+1e-6))return(NA_real_)
    s <- 1; f <- 0
    for(t in 1:12) {
      f <- f+s*C[t]/R[t]
      s <- s*(1-E[t]/R[t])
    }
    100*f
  }
  raw <- vapply(arrays,cif,numeric(1),mult=rep(1,K))
  raw_draws <- do.call(rbind,parallel::mclapply(mults,function(mult)
    vapply(arrays,cif,numeric(1),mult=mult),
    mc.cores=min(4L,parallel::detectCores()),mc.preschedule=FALSE))
  colnames(raw_draws) <- zones

  fit <- function(w) {
    p$boot_weight <- w
    out <- tryCatch(dhs_multinom_fit(formula,data=p,weights=boot_weight,
      maxit=400,MaxNWts=10000,trace=FALSE,Hess=FALSE),
      error=function(err)NULL)
    if(is.null(out) || out$convergence!=0L)return(NULL)
    out
  }
  model <- fit(p$wt)
  if(is.null(model))stop('Full model did not converge for ',method)
  saveRDS(model,file.path(derived,
    paste0('nigeria_actionable_',tolower(method),'_zone_full_model.rds')))
  rhs <- delete.response(terms(formula))
  baseline <- ref
  baseline$zone_name <- factor(zones[1],levels=zones)
  X <- lapply(1:12,function(t) {
    baseline$month <- factor(t,levels=1:12)
    model.matrix(rhs,baseline)
  })
  one <- baseline[1,,drop=FALSE]
  one$month <- factor(1,levels=1:12)
  x0 <- model.matrix(rhs,one)[1,]
  offsets <- lapply(zones,function(z) {
    one$zone_name <- factor(z,levels=zones)
    model.matrix(rhs,one)[1,]-x0
  })
  predict_cif <- function(fit,weights) {
    beta <- coef(fit)
    if(!is.matrix(beta) ||
       !identical(rownames(beta),c('actionable','competing')) ||
       !identical(colnames(beta),colnames(X[[1]])))
       return(rep(NA_real_,length(zones)))
    A <- sapply(X,function(x)as.vector(x%*%beta['actionable',]))
    C <- sapply(X,function(x)as.vector(x%*%beta['competing',]))
    vapply(offsets,function(off) {
      a0 <- sum(off*beta['actionable',])
      c0 <- sum(off*beta['competing',])
      survival <- rep(1,nrow(ref))
      incidence <- rep(0,nrow(ref))
      for(t in 1:12) {
        aa <- exp(A[,t]+a0); cc <- exp(C[,t]+c0)
        denom <- 1+aa+cc
        incidence <- incidence+survival*aa/denom
        survival <- survival/denom
      }
      100*weighted.mean(incidence,weights)
    },numeric(1))
  }
  adjusted <- predict_cif(model,ref$wt)
  names(adjusted) <- zones
  adj_draws <- do.call(rbind,parallel::mclapply(seq_len(B),function(b) {
    mult <- mults[[b]]
    bm <- fit(p$wt*mult[p$psu_id])
    if(is.null(bm))return(rep(NA_real_,length(zones)))
    predict_cif(bm,ref$wt*mult[ref$psu_id])
  },mc.cores=min(4L,parallel::detectCores()),mc.preschedule=FALSE))
  colnames(adj_draws) <- zones
  valid <- complete.cases(adj_draws)
  cat(method,':',sum(valid),'of',B,'valid bootstrap refits\n')
  if(sum(valid)<ceiling(.9*B))stop('Insufficient bootstrap refits: ',method)
  write.csv(data.frame(replicate=seq_len(B),raw_draws,
    check.names=FALSE),file.path(support,paste0(
    'nigeria_actionable_',tolower(method),'_zone_raw_bootstrap.csv')),
    row.names=FALSE)
  write.csv(data.frame(replicate=seq_len(B),adj_draws,
    check.names=FALSE),file.path(support,paste0(
    'nigeria_actionable_',tolower(method),'_zone_full_bootstrap.csv')),
    row.names=FALSE)
  ci <- function(draws) {
    t(apply(draws,2,quantile,c(.025,.975),na.rm=TRUE))
  }
  rci <- ci(raw_draws); aci <- ci(adj_draws[valid,,drop=FALSE])
  point <- transform(counts,
    unadjusted_pct=as.numeric(raw[zones]),
    unadjusted_low=rci[,1],unadjusted_high=rci[,2],
    adjusted_pct=as.numeric(adjusted[zones]),
    adjusted_low=aci[,1],adjusted_high=aci[,2],
    valid_adjusted_bootstrap=sum(valid),
    precision_flag=ifelse(actionable_endings_n<30,
      'Exploratory: fewer than 30 actionable endings',''))
  pair_table <- function(stage,estimate,draws) {
    d <- draws[complete.cases(draws),,drop=FALSE]
    out <- do.call(rbind,lapply(combn(zones,2,simplify=FALSE),
      function(pair) {
        delta <- unname(estimate[pair[1]]-estimate[pair[2]])
        bd <- d[,pair[1]]-d[,pair[2]]
        se <- sd(bd)
        interval <- quantile(bd,c(.025,.975),names=FALSE)
        data.frame(method=method,stage=stage,zone_a=pair[1],
          zone_b=pair[2],difference_pp=delta,
          ci_low_pp=interval[1],ci_high_pp=interval[2],
          bootstrap_se_pp=se,p_value=2*pnorm(-abs(delta/se)),
          valid_bootstrap_draws=nrow(d))
      }))
    out$holm_p_within_method <- p.adjust(out$p_value,'holm')
    out$significant_5pct <- out$holm_p_within_method<.05
    out
  }
  pairs <- rbind(pair_table('Unadjusted',raw,raw_draws),
    pair_table('Fully adjusted',adjusted,adj_draws))
  global <- function(stage,estimate,draws) {
    d <- draws[complete.cases(draws),,drop=FALSE]
    ref <- zones[1]
    other <- zones[-1]
    contrast <- sweep(d[,other,drop=FALSE],1,d[,ref],'-')
    delta <- estimate[other]-estimate[ref]
    V <- cov(contrast)
    stat <- as.numeric(crossprod(delta,solve(V,delta)))
    data.frame(method=method,stage=stage,zones_tested=length(zones),
      wald_chisq=stat,df=length(other),
      p_value=pchisq(stat,df=length(other),lower.tail=FALSE),
      valid_bootstrap_draws=nrow(d))
  }
  list(point=point,pairs=pairs,
    global=rbind(global('Unadjusted',raw,raw_draws),
                 global('Fully adjusted',adjusted,adj_draws)))
}

out <- lapply(methods,get_method)
points <- do.call(rbind,lapply(out,`[[`,'point'))
pairs <- do.call(rbind,lapply(out,`[[`,'pairs'))
global <- do.call(rbind,lapply(out,`[[`,'global'))
for(stage in unique(pairs$stage)) {
  k <- pairs$stage==stage
  pairs$holm_p_across_methods[k] <- p.adjust(pairs$p_value[k],'holm')
}
write.csv(points,file.path(support,
  'nigeria_actionable_injectable_implant_zone_probabilities.csv'),row.names=FALSE)
write.csv(pairs,file.path(support,
  'nigeria_actionable_injectable_implant_zone_pairwise.csv'),row.names=FALSE)
write.csv(global,file.path(support,
  'nigeria_actionable_injectable_implant_zone_global.csv'),row.names=FALSE)
print(points,row.names=FALSE)
print(global,row.names=FALSE)
cat('Holm-significant within-method pairs:\n')
print(pairs[pairs$significant_5pct,],row.names=FALSE)
)----------------------")

MODULES[["29_zone_method_mix_decomposition.R"]] <- list(language="R", packaged_sha256="4b07ff78de8ee41085b809b7f046092c2a22f4a3051b56d947776a5e612d38fa", args=character(0), code=r"----------------------(if(!requireNamespace('haven',quietly=TRUE))stop('Install R package haven first.')
# DHS complex survey design for this module.
.dhs_root <- Sys.getenv('NIGERIA_PROJECT_ROOT')
if (!nzchar(.dhs_root)) {
 .dhs_file <- sub('^--file=','',grep('^--file=',commandArgs(FALSE),value=TRUE)[1])
 .dhs_root <- dirname(dirname(normalizePath(.dhs_file)))
}
source(file.path(.dhs_root,'Code','dhs_survey_tools.R'),local=TRUE)
dhs_set_context(country='Nigeria',root=.dhs_root)
#!/usr/bin/env Rscript
# Nigeria DHS 2024: descriptive, symmetric decomposition of each pair of six
# zones. The denominator is eligible modern-method episodes excluding EC.
# Potentially actionable method endings are the event; all other endings are
# competing events. Weighted method shares use eligible episodes, including
# late-entry episodes. The constructed weighted mixture is not identical to
# the pooled life-table rate and should be labeled as such.
root <- Sys.getenv("NIGERIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
full_ir <- readRDS(file.path(root,'Data/raw_dhs_ir/NG2024DHS__NGIR8BDT__IR_raw.rds'))
full_frame <- unique(data.frame(cluster=as.numeric(full_ir$v021),stratum=as.numeric(full_ir$v022)))

d <- readRDS(file.path(root,'Data/Derived/nigeria_2024_modern_episodes.rds'))
d$four <- ifelse(d$method_group %in% c('IUD','Other modern'),
                 'IUD + other modern',d$method_group)
zones <- c('North Central','North East','North West','South East','South South','South West')
methods <- c('Injectables','Implants','Pill','IUD + other modern')
actionable <- c(1L,4L,5L,6L,7L,8L,10L,15L)
psu <- full_frame
psu$id <- seq_len(nrow(psu))
d$id <- match(d$cluster,psu$cluster)
ids <- split(psu$id,psu$stratum)
K <- nrow(psu)
cells <- list()
for(z in zones) for(m in methods){
  x <- d[d$zone_name==z & d$four==m,]
  count <- numeric(K)
  a <- rowsum(x$wt,x$id,reorder=FALSE)
  count[as.integer(rownames(a))] <- a[,1]
  risk <- all <- selected <- matrix(0,K,12)
  for(t in 1:12){
    at <- x$entry<t & x$exposure>=t
    end <- at & x$discontinued & x$exposure==t
    for(label in c('risk','all','selected')){
      mask <- switch(label,risk=at,all=end,
                     selected=end & x$reason_code %in% actionable)
      a <- rowsum(x$wt[mask],x$id[mask],reorder=FALSE)
      if(nrow(a)){
        mat <- get(label)
        mat[as.integer(rownames(a)),t] <- a[,1]
        assign(label,mat)
      }
    }
  }
  cells[[paste(z,m,sep='|')]] <- list(n=nrow(x),count=count,
     risk=risk,all=all,selected=selected,
     actionable_n=sum(x$discontinued & x$exposure<=12 &
       x$entry<x$exposure & x$reason_code %in% actionable))
}
cif <- function(cell,mult){
  R <- as.vector(crossprod(mult,cell$risk))
  A <- as.vector(crossprod(mult,cell$all))
  D <- as.vector(crossprod(mult,cell$selected))
  if(any(R<=0) || any(A>R+1e-6)) return(NA_real_)
  s <- 1; q <- 0
  for(t in 1:12){q <- q+s*D[t]/R[t];s <- s*(1-A[t]/R[t])}
  100*q
}
estimate <- function(mult){
  p <- q <- matrix(NA_real_,length(zones),length(methods),
                   dimnames=list(zones,methods))
  for(z in zones){
    n <- sapply(methods,function(m) sum(cells[[paste(z,m,sep='|')]]$count*mult))
    p[z,] <- n/sum(n)
    q[z,] <- sapply(methods,function(m) cif(cells[[paste(z,m,sep='|')]],mult))
  }
  out <- c()
  for(pair in combn(zones,2,simplify=FALSE)){
    a <- pair[1]; b <- pair[2]; key <- paste(a,b,sep=' vs ')
    mix <- sum((p[a,]-p[b,])*(q[a,]+q[b,])/2)
    within <- sum((q[a,]-q[b,])*(p[a,]+p[b,])/2)
    out[paste(key,'gap',sep='|')] <- mix+within
    out[paste(key,'mix',sep='|')] <- mix
    out[paste(key,'within',sep='|')] <- within
  }
  list(values=out,p=p,q=q)
}
point <- estimate(rep(1,K))
B <- as.integer(Sys.getenv('BOOTSTRAP_REPS','500'))
draws <- matrix(NA_real_,B,length(point$values),dimnames=list(NULL,names(point$values)))
for(b in seq_len(B)){
  set.seed(20261027+b)
  mult <- numeric(K)
  for(group in ids){
    n <- length(group)
    if(n>1) mult[group] <- n/(n-1)*tabulate(sample(group,n-1,replace=TRUE),nbins=K)[group]
    else mult[group] <- 1
  }
  draws[b,] <- estimate(mult)$values
}
lo <- apply(draws,2,quantile,probs=.025,na.rm=TRUE)
hi <- apply(draws,2,quantile,probs=.975,na.rm=TRUE)
pieces <- strsplit(names(point$values),'|',fixed=TRUE)
summary <- data.frame(pair=sapply(pieces,`[`,1),component=sapply(pieces,`[`,2),
 estimate_pp=as.vector(point$values),ci_low_pp=as.vector(lo),
 ci_high_pp=as.vector(hi),valid_draws=colSums(is.finite(draws)))
detail <- do.call(rbind,lapply(zones,function(z)
  do.call(rbind,lapply(methods,function(m)
    data.frame(zone=z,method=m,episode_share_pct=100*point$p[z,m],
      actionable_risk_pct=point$q[z,m],
      episodes_n=cells[[paste(z,m,sep='|')]]$n,
      actionable_endings_n=cells[[paste(z,m,sep='|')]]$actionable_n)))))
stopifnot(all(abs(rowSums(point$p)-1)<1e-10))
out <- file.path(root,'output/Supporting_data')
write.csv(summary,file.path(out,'nigeria_actionable_zone_method_mix_decomposition.csv'),row.names=FALSE)
write.csv(detail,file.path(out,'nigeria_actionable_zone_method_mix_cells.csv'),row.names=FALSE)
cat('Wrote',nrow(summary),'decomposition rows and',nrow(detail),'cells\n')
)----------------------")

MODULES[["34_nigeria_historical_current_user_pathways.R"]] <- list(language="R", packaged_sha256="dd3ef1b98678cf2d78cfabcc3346b245e3ff1bd7f62cc080d155931d6c5a62ab", args=character(0), code=r"----------------------(if(!requireNamespace('haven',quietly=TRUE))stop('Install R package haven first.')
# DHS complex survey design for this module.
.dhs_root <- Sys.getenv('NIGERIA_PROJECT_ROOT')
if (!nzchar(.dhs_root)) {
 .dhs_file <- sub('^--file=','',grep('^--file=',commandArgs(FALSE),value=TRUE)[1])
 .dhs_root <- dirname(dirname(normalizePath(.dhs_file)))
}
source(file.path(.dhs_root,'Code','dhs_survey_tools.R'),local=TRUE)
dhs_set_context(country='Nigeria',root=.dhs_root)
#!/usr/bin/env Rscript
# Nigeria DHS 2024 historical current-user pathway and direct standardization.
# One woman using a modern method 15 months before interview contributes one
# landmark. The following 12 observed calendar months end 3 months before
# interview. Uninterrupted switching stays in continuous modern use; a later
# return after a nonmodern month is re-entry. This historical association is
# not an observed 2025-26 forecast. EC is included here because DHS counts it
# in interview-date modern use; it is grouped with other modern methods, and
# the separate original-method discontinuation life tables continue to omit EC.
root <- Sys.getenv("NIGERIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
out <- file.path(root,'output/Supporting_data')
ir <- readRDS(file.path(root,'Data/raw_dhs_ir/NG2024DHS__NGIR8BDT__IR_raw.rds'))
cal <- readRDS(file.path(root,'Data/Derived/nigeria_2024_calendar_events.rds'))
modern <- c(1L,2L,3L,5L,6L,7L,11L,13L,14L,15L,16L,17L,18L,19L,20L)
group <- function(z) ifelse(z==3L,'Injectables',ifelse(z==11L,'Implants',
  ifelse(z==1L,'Pill','Other modern including EC')))
durlev <- c('0–3 months','4–6 months','7–12 months','13–24 months','25+ months')
durgroup <- function(x) factor(ifelse(x<=3,durlev[1],ifelse(x<=6,durlev[2],
  ifelse(x<=12,durlev[3],ifelse(x<=24,durlev[4],durlev[5])))),levels=durlev)
events <- split(seq_len(nrow(cal)),cal$woman_row)
baseline_month <- as.integer(ir$v008)-15L
rows <- vector('list',nrow(ir)); k <- 0L
for(i in seq_len(nrow(ir))){
  a <- cal[events[[as.character(i)]],]
  if(!nrow(a))next
  bi <- which(a$start<=baseline_month[i] & a$end>=baseline_month[i])
  if(length(bi)!=1L)next
  b <- a$method_code[bi]
  if(!(b %in% modern))next
  follow <- baseline_month[i]+1:12
  ix <- findInterval(follow,a$start)
  stopifnot(all(ix>0L),all(a$end[ix]>=follow))
  codes <- a$method_code[ix]
  effective <- codes %in% modern
  # DHS one-month gap convention: a single no-method month between different
  # modern methods is a continuous switch when prior ending reason is 7.
  for(t in 1:11)if(codes[t]==0L){
    prev <- if(t==1L)b else codes[t-1L]
    subsequent <- codes[t+1L]
    prior_event <- which(a$end==follow[t]-1L & a$method_code==prev)
    if(length(prior_event)==1L && prev %in% modern && subsequent %in% modern &&
       subsequent!=prev && a$reason_code[prior_event]==7L)effective[t]<-TRUE
  }
  status <- function(t){
    exited <- any(!effective[1:t])
    changed <- any(codes[1:t][codes[1:t]%in%modern]!=b) ||
      any(effective[1:t] & !(codes[1:t]%in%modern))
    if(!exited)return(if(changed)'Continuous modern use after switch'
                      else 'Continuous baseline method')
    if(effective[t])return('Re-entered modern use after exit')
    if(codes[t]%in%c(81L,82L,83L))return('Pregnancy/birth/termination')
    'Outside modern use'
  }
  k<-k+1L
  rows[[k]]<-data.frame(woman_row=i,wt=as.numeric(ir$v005[i])/1e6,
    cluster=as.integer(ir$v021[i]),stratum=as.integer(ir$v022[i]),
    baseline_code=b,baseline_method=group(b),baseline_duration=baseline_month[i]-a$start[bi]+1L,
    month3_status=status(3L),month12_status=status(12L),
    any_gross_exit=any(!effective),stringsAsFactors=FALSE)
}
h <- do.call(rbind,rows[seq_len(k)])
h$duration_group <- durgroup(h$baseline_duration)
h$outcome <- ifelse(h$month12_status=='Continuous baseline method','No gross exit: baseline method',
 ifelse(h$month12_status=='Continuous modern use after switch','No gross exit: modern switch',
 ifelse(h$month12_status=='Re-entered modern use after exit','Gross exit: re-entered by month 12',
        'Gross exit: net absent at month 12')))
stopifnot(nrow(h)>2000L,!anyNA(h$duration_group),!anyNA(h$outcome))
saveRDS(h,file.path(root,'Data/Derived/nigeria_historical_current_user_pathways.rds'))
flows <- aggregate(wt~baseline_method+month3_status+month12_status,h,sum)
flows$pct <- 100*flows$wt/sum(flows$wt)
write.csv(flows,file.path(out,'nigeria_current_user_pathway_flows.csv'),row.names=FALSE)
current <- data.frame(method_code=as.integer(ir$v312),
 duration=as.numeric(ir$v337),wt=as.numeric(ir$v005)/1e6,
 modern=as.integer(ir$v313)==3)
permanent_current <- current[current$modern & current$method_code%in%c(6L,7L),]
current <- current[current$modern & current$method_code %in% setdiff(modern,c(6L,7L)) &
 is.finite(current$duration) & current$duration<997,]
current$method <- group(current$method_code)
current$duration_group <- durgroup(current$duration)
current_cells <- aggregate(wt~method+duration_group,current,sum)
names(current_cells)[3]<-'current_weight'
# Permanent users remain in the current-user denominator and do not stop.
permanent_weight <- sum(permanent_current$wt)
stock_weight <- sum(current_cells$current_weight)+permanent_weight
current_cells$current_share <- current_cells$current_weight/stock_weight
stock_cells <- current_cells
stock_cells$duration_group <- as.character(stock_cells$duration_group)
if(permanent_weight>0)stock_cells<-rbind(stock_cells,data.frame(
 method='Permanent methods',duration_group='Not applicable',
 current_weight=permanent_weight,current_share=permanent_weight/stock_weight))
stopifnot(abs(sum(stock_cells$current_share)-1)<1e-10)
write.csv(stock_cells,file.path(out,'nigeria_current_user_method_duration_distribution.csv'),row.names=FALSE)
h <- h[!h$baseline_code%in%c(6L,7L),]
historical <- aggregate(wt~baseline_method+duration_group+outcome,h,sum)
historical_n <- aggregate(woman_row~baseline_method+duration_group,h,length)
names(historical_n)[3]<-'historical_n'
historical <- merge(historical,historical_n,by=c('baseline_method','duration_group'))
den <- aggregate(wt~baseline_method+duration_group,h,sum)
names(den)[3]<-'historical_weight'
historical <- merge(historical,den,by=c('baseline_method','duration_group'))
historical$conditional_probability <- historical$wt/historical$historical_weight
write.csv(historical,file.path(out,'nigeria_historical_method_duration_pathway_probabilities.csv'),row.names=FALSE)
standard <- merge(current_cells[,c('method','duration_group','current_share')],
 historical[,c('baseline_method','duration_group','outcome','conditional_probability','historical_n')],
 by.x=c('method','duration_group'),by.y=c('baseline_method','duration_group'))
stopifnot(nrow(standard)>0,all(current_cells$current_share>0),
 all(paste(current_cells$method,current_cells$duration_group)%in%
     paste(standard$method,standard$duration_group)))
standard$contribution <- standard$current_share*standard$conditional_probability
if(permanent_weight>0){
 standard$duration_group<-as.character(standard$duration_group)
 fixed<-standard[1L,,drop=FALSE]
 fixed$method<-'Permanent methods';fixed$duration_group<-'Not applicable'
 fixed$current_share<-permanent_weight/stock_weight
 fixed$outcome<-'No gross exit: baseline method';fixed$conditional_probability<-1
 fixed$historical_n<-NA_integer_;fixed$contribution<-fixed$current_share
 standard<-rbind(standard,fixed)
}
summary <- aggregate(contribution~outcome,standard,sum)
summary$pct <- 100*summary$contribution
stopifnot(abs(sum(summary$pct)-100)<1e-8)
write.csv(standard,file.path(out,'nigeria_standardized_current_user_pathway_contributions.csv'),row.names=FALSE)
write.csv(summary,file.path(out,'nigeria_standardized_current_user_pathway_summary.csv'),row.names=FALSE)
cat('Historical women',nrow(h),'current modern users',nrow(current)+nrow(permanent_current),
    'smallest historical cell',min(historical_n$historical_n),'\n')
print(summary)
)----------------------")

MODULES[["35_nigeria_alluvial_figures.R"]] <- list(language="R", packaged_sha256="e0c2527cfa4157a0d9bc3231d913e8e161a84954223d60ca4f79dc58eb86c88a", args=character(0), code=r"----------------------(if(!requireNamespace('haven',quietly=TRUE))stop('Install R package haven first.')
# DHS complex survey design for this module.
.dhs_root <- Sys.getenv('NIGERIA_PROJECT_ROOT')
if (!nzchar(.dhs_root)) {
 .dhs_file <- sub('^--file=','',grep('^--file=',commandArgs(FALSE),value=TRUE)[1])
 .dhs_root <- dirname(dirname(normalizePath(.dhs_file)))
}
source(file.path(.dhs_root,'Code','dhs_survey_tools.R'),local=TRUE)
dhs_set_context(country='Nigeria',root=.dhs_root)
#!/usr/bin/env Rscript
# Nigeria DHS 2024 alluvial figures parallel to Ethiopia's episode and
# historical-current-user pathway displays. Every figure has a stated cohort:
# first-year injectable actionable endings with month 1 observed; a fixed
# historical modern-user cohort observed for 12 months; or that cohort's
# conditional outcomes standardized to the interview-date current-user mix.
root <- Sys.getenv("NIGERIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
support <- file.path(root,'output/Supporting_data')
assets <- file.path(root,'output/assets')
dir.create(assets,recursive=TRUE,showWarnings=FALSE)
e <- readRDS(file.path(root,'Data/Derived/nigeria_2024_modern_episodes.rds'))
cal <- readRDS(file.path(root,'Data/Derived/nigeria_2024_calendar_events.rds'))
h <- readRDS(file.path(root,'Data/Derived/nigeria_historical_current_user_pathways.rds'))
std <- read.csv(file.path(support,'nigeria_standardized_current_user_pathway_summary.csv'))
modern <- c(1L,2L,3L,5L,6L,7L,11L,13L,14L,15L,16L,17L,18L,19L,20L)
reason <- function(z) ifelse(z==1L,'Method failure',ifelse(z==7L,
 'Wanted more effective method',ifelse(z==15L,'Changes in menstrual bleeding',
 ifelse(z%in%c(4L,5L),'Other side effects/health','Access/cost/convenience'))))
status <- function(code,original) ifelse(code%in%modern,
 ifelse(code==original,'Same modern method','Different modern method'),
 ifelse(code==0L,'No method recorded',ifelse(code%in%c(81L,82L,83L),
 'Pregnancy, birth or termination',ifelse(code%in%c(8L,9L,10L,12L,99L),
 'Traditional/other method','Other/unknown'))))
rows <- split(seq_len(nrow(cal)),cal$woman_row)
injectable <- e[e$method_group=='Injectables' & e$discontinued &
 e$exposure<=12 & e$reason_code%in%c(1L,4L,5L,6L,7L,8L,10L,15L) &
 e$end+1<=e$interview,]
code1 <- vapply(seq_len(nrow(injectable)),function(i){
 a<-cal[rows[[as.character(injectable$woman_row[i])]],]
 j<-which(a$start<=injectable$end[i]+1 & a$end>=injectable$end[i]+1)
 stopifnot(length(j)==1L)
 a$method_code[j]
},integer(1))
injectable$reason_label <- reason(injectable$reason_code)
injectable$destination <- status(code1,injectable$method_code)
injectable$duration_group <- cut(injectable$exposure,c(0,3,6,12),
 labels=c('1–3 months','4–6 months','7–12 months'))
flows <- aggregate(wt~reason_label+destination,injectable,sum)
flows$pct <- 100*flows$wt/sum(flows$wt)
write.csv(flows,file.path(support,'nigeria_injectable_reason_destination_flows.csv'),row.names=FALSE)
timing <- aggregate(wt~reason_label+duration_group+destination,injectable,sum)
timing$pct_of_injectable_actionable_endings <- 100*timing$wt/sum(injectable$wt)
write.csv(timing,file.path(support,'nigeria_injectable_reason_timing_destination.csv'),row.names=FALSE)

palette <- c('Method failure'='#85909D','Wanted more effective method'='#DA9A25',
 'Changes in menstrual bleeding'='#D45A49','Other side effects/health'='#108B8D',
 'Access/cost/convenience'='#153F5B','Same modern method'='#108B8D',
 'Different modern method'='#153F5B','No method recorded'='#85909D',
 'Pregnancy, birth or termination'='#D45A49','Traditional/other method'='#DA9A25',
 'Other/unknown'='#B8BEC5','Injectables'='#108B8D','Implants'='#153F5B',
 'Pill'='#DA9A25','Other modern including EC'='#85909D',
 'Continuous baseline method'='#108B8D',
 'Continuous modern use after switch'='#153F5B',
 'Re-entered modern use after exit'='#DA9A25',
 'Outside modern use'='#85909D',
 'Pregnancy/birth/termination'='#D45A49',
 'No gross exit'='#108B8D','Gross modern-use exit'='#D45A49',
 'Gross exit: net absent at month 12'='#85909D',
 'Gross exit: re-entered by month 12'='#DA9A25',
 'No gross exit: baseline method'='#108B8D',
 'No gross exit: modern switch'='#153F5B')
bezier <- function(t,a,b) (1-t)^3*a+3*(1-t)^2*t*a+3*(1-t)*t^2*b+t^3*b
link <- function(x0,x1,top0,bot0,top1,bot1,col){
 t<-seq(0,1,length.out=90);x<-bezier(t,x0,x1)
 yt<-bezier(t,top0,top1);yb<-bezier(t,bot0,bot1)
 polygon(c(x,rev(x)),c(yt,rev(yb)),col=adjustcolor(col,alpha.f=.46),border=NA)
}
nodes <- function(labels,totals,top=.87,bottom=.10,gap=.028){
 scale<-(top-bottom-gap*(length(labels)-1))/sum(totals[labels])
 z<-data.frame(name=labels,top=NA_real_,bottom=NA_real_)
 y<-top
 for(i in seq_along(labels)){z$top[i]<-y;z$bottom[i]<-y-totals[labels[i]]*scale;y<-z$bottom[i]-gap}
 list(data=z,scale=scale)
}
draw <- function(mat1,mat2=NULL,file,title,subtitle,headers){
 # mat1: left-to-middle weighted flow matrix; optional mat2: middle-to-right.
 Lnames<-rownames(mat1);Mnames<-colnames(mat1)
 Ltot<-rowSums(mat1);Mtot<-colSums(mat1)
 L<-nodes(Lnames,Ltot,.84,.12,.030);M<-nodes(Mnames,Mtot,.84,.12,.030)
 if(!is.null(mat2)){
  stopifnot(max(abs(rowSums(mat2)-Mtot))<1e-6)
  Rnames<-colnames(mat2);Rtot<-colSums(mat2);R<-nodes(Rnames,Rtot,.84,.12,.030)
 }
 png(file,width=3200,height=1700,res=200,type='quartz')
 par(mar=c(4,3,5,3),family='sans',xpd=NA)
 plot.new();plot.window(xlim=c(-.27,1.28),ylim=c(0,1))
 xL<-c(.10,.13);xM<-if(is.null(mat2))c(.82,.85) else c(.48,.52)
 left<-setNames(L$data$top,Lnames);mid<-setNames(M$data$top,Mnames)
 for(m in Mnames)for(l in Lnames){w<-mat1[l,m];if(w<=0)next
  a<-left[l];b<-a-w*L$scale;c<-mid[m];d<-c-w*M$scale
  link(xL[2],xM[1],a,b,c,d,palette[m]);left[l]<-b;mid[m]<-d}
 if(!is.null(mat2)){
  xR<-c(.88,.92);mid<-setNames(M$data$top,Mnames);right<-setNames(R$data$top,Rnames)
  for(r in Rnames)for(m in Mnames){w<-mat2[m,r];if(w<=0)next
   a<-mid[m];b<-a-w*M$scale;c<-right[r];d<-c-w*R$scale
   link(xM[2],xR[1],a,b,c,d,palette[r]);mid[m]<-b;right[r]<-d}
 }
 rect(xL[1],L$data$bottom,xL[2],L$data$top,col=palette[Lnames],border=NA)
 rect(xM[1],M$data$bottom,xM[2],M$data$top,col=palette[Mnames],border=NA)
 if(!is.null(mat2))rect(xR[1],R$data$bottom,xR[2],R$data$top,col=palette[Rnames],border=NA)
 label <- function(dat,tot,x,adj){
  y<-rowMeans(dat[,c('top','bottom')]);
  text(x,y,paste0(dat$name,'  ',sprintf('%.1f%%',100*tot[dat$name]/sum(tot))),
   adj=adj,cex=.64,col='#17222C')
 }
 label(L$data,Ltot,.08,1)
 label(M$data,Mtot,xM[2]+.015,0)
 if(!is.null(mat2))label(R$data,Rtot,.94,0)
 text(xL[1],.93,headers[1],adj=0,cex=.77,font=2,col='#153F5B')
 text(xM[1],.93,headers[2],adj=0,cex=.77,font=2,col='#153F5B')
 if(!is.null(mat2))text(xR[1],.93,headers[3],adj=0,cex=.77,font=2,col='#153F5B')
 title(main=title,sub=subtitle,adj=.02,cex.main=1.3,col.main='#153F5B',
       cex.sub=.88,col.sub='#506879')
 dev.off()
}
reasons <- c('Method failure','Wanted more effective method','Changes in menstrual bleeding',
 'Other side effects/health','Access/cost/convenience')
dest <- c('Different modern method','Same modern method','No method recorded',
 'Pregnancy, birth or termination','Traditional/other method','Other/unknown')
observed_mat<-xtabs(wt~reason_label+destination,injectable)
mat<-matrix(0,length(reasons),length(dest),dimnames=list(reasons,dest))
mat[rownames(observed_mat),colnames(observed_mat)]<-observed_mat
mat<-mat[,colSums(mat)>0,drop=FALSE]
draw(mat,file=file.path(assets,'nigeria_injectable_reason_destination_alluvial.png'),
 title='Why injectable episodes end and what follows one month later',
 subtitle=paste(format(nrow(injectable),big.mark=','),'observed first-year actionable endings; weighted shares'),
 headers=c('RECORDED REASON','STATE ONE MONTH LATER'))

method_names<-c('Injectables','Implants','Pill','Other modern including EC')
path_names<-c('Continuous baseline method','Continuous modern use after switch',
 'Re-entered modern use after exit','Outside modern use','Pregnancy/birth/termination')
left<-xtabs(wt~baseline_method+month3_status,h)[method_names,path_names,drop=FALSE]
right<-xtabs(wt~month3_status+month12_status,h)[path_names,path_names,drop=FALSE]
draw(left,right,file=file.path(assets,'nigeria_current_user_pathway_3_12_alluvial.png'),
 title='Historical current users over 12 months',
 subtitle=paste(format(nrow(h),big.mark=','),'women using a modern method 15 months before interview'),
 headers=c('BASELINE METHOD','PATHWAY BY MONTH 3','STATE AT MONTH 12'))

outcomes<-c('No gross exit: baseline method','No gross exit: modern switch',
 'Gross exit: re-entered by month 12','Gross exit: net absent at month 12')
v<-setNames(std$pct,std$outcome)[outcomes]
mid<-c('No gross exit','Gross modern-use exit')
a<-matrix(c(v[1]+v[2],v[3]+v[4]),1,2,
 dimnames=list('Current modern-method users',mid))
b<-matrix(0,2,4,dimnames=list(mid,outcomes))
b[1,1:2]<-v[1:2];b[2,3:4]<-v[3:4]
palette['Current modern-method users']<-'#153F5B'
draw(a,b,file=file.path(assets,'nigeria_standardized_current_user_stock_alluvial.png'),
 title='Expected pathways per 100 interview-date current modern users',
 subtitle='Historical method-duration probabilities standardized to the DHS 2024 current-user stock',
 headers=c('CURRENT USER STOCK','ANY GROSS EXIT','STATE AT MONTH 12'))

# Repeat the Ethiopia method-to-follow-up displays for Nigeria. These figures
# condition on an observed first-year original-method ending with the required
# follow-up month recorded. They are reason/status distributions, not life-table
# probabilities and not current-user forecasts. Each month has its own cohort.
palette[c('Other modern','IUD')]<-c('#85909D','#D45A49')
origin <- c('Injectables','Implants','Pill','IUD','Other modern')
for (reason_set in c('all','selected')) for (follow_month in c(1L,12L)) {
  f <- e[e$discontinued & e$exposure<=12 & e$end+follow_month<=e$interview,]
  if(reason_set=='selected') f<-f[!(f$reason_code%in%c(2L,3L)),]
  f<-f[f$method_group%in%origin,]
  code <- vapply(seq_len(nrow(f)),function(i){
    z<-cal[rows[[as.character(f$woman_row[i])]],]
    j<-which(z$start<=f$end[i]+follow_month & z$end>=f$end[i]+follow_month)
    stopifnot(length(j)==1L)
    z$method_code[j]
  },integer(1))
  f$destination<-status(code,f$method_code)
  tab<-xtabs(wt~method_group+destination,f)
  mat<-matrix(0,length(origin),length(dest),dimnames=list(origin,dest))
  mat[rownames(tab),colnames(tab)]<-tab
  mat<-mat[,colSums(mat)>0,drop=FALSE]
  name<-sprintf('nigeria_%s_reason_method_to_month_%02d_alluvial.png',reason_set,follow_month)
  set_label<-if(reason_set=='all')'all recorded reasons' else 'reasons other than wanted pregnancy or partner disapproval'
  draw(mat,file=file.path(assets,name),
    title=paste('Modern-method endings and status',paste0(follow_month,' month',if(follow_month>1)'s' else ''),'later'),
    subtitle=paste(format(nrow(f),big.mark=','),'observed first-year endings for',set_label,'with follow-up'),
    headers=c('ORIGINAL METHOD',paste('STATE',paste0(follow_month,' MONTH',if(follow_month>1)'S' else ''),'LATER')))
  z<-as.data.frame(tab);names(z)<-c('method','destination','weighted_endings')
  z$reason_set<-reason_set;z$follow_month<-follow_month;z$observed_endings_n<-nrow(f)
  write.csv(z,file.path(support,sub('\\.png$','.csv',name)),row.names=FALSE)
}
cat('Created seven alluvial PNGs and source flow tables\n')
)----------------------")

MODULES[["37_nigeria_selected_reason_extensions.R"]] <- list(language="R", packaged_sha256="0def94362a3b887176097a9b80857e136adbe9c4635578b5ae7a830d5d1f72a0", args=character(0), code=r"----------------------(if(!requireNamespace('haven',quietly=TRUE))stop('Install R package haven first.')
# DHS complex survey design for this module.
.dhs_root <- Sys.getenv('NIGERIA_PROJECT_ROOT')
if (!nzchar(.dhs_root)) {
 .dhs_file <- sub('^--file=','',grep('^--file=',commandArgs(FALSE),value=TRUE)[1])
 .dhs_root <- dirname(dirname(normalizePath(.dhs_file)))
}
source(file.path(.dhs_root,'Code','dhs_survey_tools.R'),local=TRUE)
dhs_set_context(country='Nigeria',root=.dhs_root)
#!/usr/bin/env Rscript
# Nigeria DHS 2024 selected-reason exploratory analyses mirroring Ethiopia's
# descriptive subgroups, method-duration classes, reason rankings and regional
# method-mix panels. Eligible denominator: all modern-method episodes except
# EC. Wanted pregnancy (code 2) and partner disapproval (code 3) stay in the
# competing-risk life table; they are excluded only as events of interest.
# Survey weights enter every monthly hazard. Intervals resample PSUs within
# DHS strata, keeping repeated episodes of a woman together. Age and parity
# refer to episode start; other demographic covariates refer to interview.
root <- Sys.getenv("NIGERIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
full_ir <- readRDS(file.path(root,'Data/raw_dhs_ir/NG2024DHS__NGIR8BDT__IR_raw.rds'))
full_frame <- unique(data.frame(cluster=as.numeric(full_ir$v021),stratum=as.numeric(full_ir$v022)))

out <- file.path(root,'output/Supporting_data')
d <- readRDS(file.path(root,'Data/Derived/nigeria_2024_model_episode_covariates.rds'))
selected_codes <- list('Method failure'=1L,
 'Other fertility-related'=c(9L,12L,13L),
 'Changes in menstrual bleeding'=15L,
 'Other side effects/health'=c(4L,5L),
 'Wanted more effective method'=7L,
 'Access/cost/convenience'=c(6L,8L,10L),
 'Other recorded reasons'=c(11L,96L,98L,99L,0L))
all_selected <- unlist(selected_codes,use.names=FALSE)
stopifnot(!anyDuplicated(all_selected),
 all(d$reason_code[d$discontinued & !(d$reason_code %in% c(2L,3L))] %in% all_selected))
life <- function(x,w=x$wt){
  s<-1;v<-setNames(numeric(length(selected_codes)),names(selected_codes))
  for(t in 1:12){
    at<-x$entry<t & x$exposure>=t;den<-sum(w[at])
    if(den<=0)return(rep(NA_real_,length(v)+1))
    ended<-at & x$discontinued & x$exposure==t
    for(j in seq_along(selected_codes))
      v[j]<-v[j]+s*sum(w[ended & x$reason_code %in% selected_codes[[j]]])/den
    s<-s*(1-sum(w[ended])/den)
  }
  c(total=100*sum(v),100*v)
}
selected_n <- function(x)sum(x$discontinued & x$exposure<=12 &
 x$entry<x$exposure & x$reason_code %in% all_selected)
d$duration_class <- ifelse(d$method_code%in%c(1L,3L,5L),'Short-acting reversible',
 ifelse(d$method_code%in%c(2L,11L),'Long-acting reversible','Other modern, mixed'))
fields<-c('age_group','parity_group','marital_group','education','wealth',
          'residence','method_group','zone_name','duration_class')
scopes<-list('Overall::All modern'=seq_len(nrow(d)))
for(f in fields){
  lev<-if(is.factor(d[[f]]))levels(d[[f]]) else unique(d[[f]])
  for(v in lev)scopes[[paste(f,v,sep='::')]]<-which(d[[f]]==v)
}
for(z in levels(d$zone_name))for(m in levels(d$method_group))
  scopes[[paste('zone_method',z,m,sep='::')]]<-which(d$zone_name==z & d$method_group==m)
for(m in c('Injectables','Pill','IUD'))for(f in fields[1:6]){
  lev<-levels(d[[f]])
  for(v in lev)scopes[[paste('method_subgroup',m,f,v,sep='::')]]<-
    which(d$method_group==m & d[[f]]==v)
}
estimate <- function(key,idx,weights=NULL){
 x<-d[idx,];w<-if(is.null(weights))x$wt else weights[idx]
 v<-life(x,w)
 parts<-strsplit(key,'::',fixed=TRUE)[[1]]
 outrow<-data.frame(scope=key,variable=parts[1],category=paste(parts[-1],collapse=' / '),
    eligible_episodes_n=nrow(x),weighted_episodes=sum(x$wt),
    selected_endings_n=selected_n(x),selected_12_month_pct=v[1],
    stringsAsFactors=FALSE)
 for(j in seq_along(selected_codes)){
   name<-names(selected_codes)[j]
   outrow[[paste0('cause_',j,'_pct')]]<-v[j+1]
   outrow[[paste0('share_',j,'_pct')]]<-if(is.finite(v[1]) && v[1]>0)100*v[j+1]/v[1] else NA_real_
 }
 outrow
}
point<-do.call(rbind,lapply(names(scopes),function(key)estimate(key,scopes[[key]])))
rownames(point)<-NULL
point$limited_precision<-point$selected_endings_n<30L
point$withhold_reason_rank<-point$selected_endings_n<10L
stopifnot(max(abs(rowSums(point[paste0('cause_',1:7,'_pct')])-point$selected_12_month_pct),na.rm=TRUE)<1e-7,
 max(abs(rowSums(point[paste0('share_',1:7,'_pct')])-100),na.rm=TRUE)<1e-7)
# CIs for national, one-way, zone and method-duration category rates. The
# many small method-by-subgroup reason cells are descriptive only.
ci_keys<-names(scopes)[!grepl('^(zone_method|method_subgroup)::',names(scopes))]
frame<-full_frame;groups<-split(frame$cluster,frame$stratum)
stopifnot(!anyDuplicated(frame$cluster),all(lengths(groups)>1))
B<-as.integer(Sys.getenv('NIGERIA_SELECTED_BOOTSTRAP_REPS','300'))
boot<-matrix(NA_real_,B,length(ci_keys),dimnames=list(NULL,ci_keys))
for(b in seq_len(B)){
 set.seed(20261028L+b)
 mult<-setNames(numeric(nrow(frame)),frame$cluster)
 for(ids in groups){n<-length(ids);mult[as.character(ids)]<-n/(n-1)*
   tabulate(sample.int(n,n-1,replace=TRUE),nbins=n)}
 weights<-d$wt*mult[as.character(d$cluster)]
 for(j in seq_along(ci_keys)){
   ix<-scopes[[ci_keys[j]]]
   boot[b,j]<-tryCatch(life(d[ix,],weights[ix])[1],error=function(err)NA_real_)
 }
}
point$ci_low<-NA_real_;point$ci_high<-NA_real_;point$valid_bootstrap<-NA_integer_
for(key in ci_keys){
 x<-boot[,key];x<-x[is.finite(x)];ix<-which(point$scope==key)
 if(length(x)>=.8*B){point$ci_low[ix]<-quantile(x,.025);point$ci_high[ix]<-quantile(x,.975)}
 point$valid_bootstrap[ix]<-length(x)
}
write.csv(point,file.path(out,'nigeria_selected_reason_extensions.csv'),row.names=FALSE)
# Formal raw zone contrasts use paired differences from the same survey-cluster
# bootstrap draws; Holm controls the 15 simultaneous zone comparisons.
zones<-levels(d$zone_name)
pairs<-combn(zones,2,simplify=FALSE)
zone_pairs<-do.call(rbind,lapply(pairs,function(pair){
 a<-paste0('zone_name::',pair[1]);b<-paste0('zone_name::',pair[2])
 x<-boot[,a]-boot[,b];x<-x[is.finite(x)]
 est<-point$selected_12_month_pct[point$scope==a]-point$selected_12_month_pct[point$scope==b]
 se<-sd(x)
 data.frame(zone_a=pair[1],zone_b=pair[2],difference_pp=est,
  se_pp=se,ci_low=quantile(x,.025),ci_high=quantile(x,.975),
  p_value=2*pnorm(-abs(est/se)),valid_bootstrap=length(x))
}))
zone_pairs$p_holm<-p.adjust(zone_pairs$p_value,method='holm')
zone_pairs$significant_5pct<-zone_pairs$p_holm<.05
zone_pairs$significant_10pct<-zone_pairs$p_holm<.10
write.csv(zone_pairs,file.path(out,'nigeria_selected_reason_zone_pairwise.csv'),row.names=FALSE)
# The two raw 'other' families are distinguishable in the original calendar.
ends<-d[d$discontinued & d$exposure<=12 & d$entry<d$exposure,]
other<-ends[ends$reason_code%in%c(9L,11L,12L,13L,96L,98L,99L,0L),]
other_breakdown<-aggregate(wt~reason_code,other,sum)
other_n<-aggregate(woman_row~reason_code,other,length)
names(other_n)[2]<-'endings_n'
other_breakdown<-merge(other_breakdown,other_n,by='reason_code')
other_breakdown$group<-ifelse(other_breakdown$reason_code%in%c(9L,12L,13L),
 'Other fertility-related','Other recorded reasons')
write.csv(other_breakdown,file.path(out,'nigeria_other_reason_code_breakdown.csv'),row.names=FALSE)
cat('Wrote',nrow(point),'selected-reason rows; bootstrapped',length(ci_keys),
    'aggregate scopes with',B,'replicates\n')
)----------------------")

MODULES[["38_nigeria_other_reason_followup.R"]] <- list(language="R", packaged_sha256="95e442578fb9f6e34e4049256e5be886cd0708d63834f51aceb299b7b942539f", args=character(0), code=r"----------------------(if(!requireNamespace('haven',quietly=TRUE))stop('Install R package haven first.')
# DHS complex survey design for this module.
.dhs_root <- Sys.getenv('NIGERIA_PROJECT_ROOT')
if (!nzchar(.dhs_root)) {
 .dhs_file <- sub('^--file=','',grep('^--file=',commandArgs(FALSE),value=TRUE)[1])
 .dhs_root <- dirname(dirname(normalizePath(.dhs_file)))
}
source(file.path(.dhs_root,'Code','dhs_survey_tools.R'),local=TRUE)
dhs_set_context(country='Nigeria',root=.dhs_root)
#!/usr/bin/env Rscript
# Decompose residual 12-month modern-method endings and their observed status
# one and twelve months later. This is a conditional ending cohort, distinct
# from cause-specific cumulative incidence in the episode risk set.
root<-Sys.getenv("NIGERIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE));out<-file.path(root,'output/Supporting_data')
d<-readRDS(file.path(root,'Data/Derived/nigeria_2024_modern_episodes.rds'))
cal<-readRDS(file.path(root,'Data/Derived/nigeria_2024_calendar_events.rds'))
modern<-c(1L,2L,3L,5L,6L,7L,11L,13L,14L,15L,16L,17L,18L,19L,20L)
other_codes<-c(9L,11L,12L,13L,96L,98L,99L,0L)
label<-function(code)ifelse(code==9L,'Infrequent sex / husband away',
 ifelse(code==11L,'Up to God / fatalistic',
 ifelse(code==12L,'Difficult to get pregnant / menopausal',
 ifelse(code==13L,'Marital dissolution / separation',
 ifelse(code==96L,'Other specified',
 ifelse(code==98L,'Do not know',
 ifelse(code==99L,'Missing / unknown','Unspecified')))))))
status<-function(code,origin)ifelse(code%in%modern,
 ifelse(code==origin,'Same modern method','Different modern method'),
 ifelse(code==0L,'No method recorded',ifelse(code%in%c(81L,82L,83L),
 'Pregnancy, birth or termination','Traditional/other/unknown')))
ix<-split(seq_len(nrow(cal)),cal$woman_row)
z<-d[d$discontinued & d$entry<d$exposure & d$exposure<=12 &
 d$reason_code%in%other_codes,]
z$reason_label<-label(z$reason_code)
all<-list();n<-0L
for(k in c(1L,12L)){
 q<-z[z$end+k<=z$interview,]
 code<-vapply(seq_len(nrow(q)),function(i){
  a<-cal[ix[[as.character(q$woman_row[i])]],]
  pick<-which(a$start<=q$end[i]+k & a$end>=q$end[i]+k)
  stopifnot(length(pick)==1L)
  a$method_code[pick]
 },integer(1))
 q$destination<-status(code,q$method_code)
 tab<-aggregate(q$wt,list(reason_code=q$reason_code,reason=q$reason_label,
   month_after_ending=rep(k,nrow(q)),destination=q$destination),sum)
 names(tab)[5]<-'weighted_endings'
 count<-aggregate(q$woman_row,list(reason_code=q$reason_code,reason=q$reason_label,
   month_after_ending=rep(k,nrow(q)),destination=q$destination),length)
 names(count)[5]<-'endings_n'
 tab<-merge(tab,count,by=c('reason_code','reason','month_after_ending','destination'))
 denom<-aggregate(weighted_endings~reason_code+reason+month_after_ending,tab,sum)
 names(denom)[4]<-'denom_weighted'
 tab<-merge(tab,denom,by=c('reason_code','reason','month_after_ending'))
 tab$share_within_reason_pct<-100*tab$weighted_endings/tab$denom_weighted
 all[[as.character(k)]]<-tab
}
result<-do.call(rbind,all)
write.csv(result,file.path(out,'nigeria_other_reason_followup.csv'),row.names=FALSE)
cat('Other first-year endings',nrow(z),'follow-up rows',nrow(result),'\n')
)----------------------")

MODULES[["40_nigeria_selected_current_user_planning.R"]] <- list(language="R", packaged_sha256="d7882914dd1c9844245938999079aac3f4f38a57842a54057654a08290ebbd6d", args=character(0), code=r"----------------------(if(!requireNamespace('haven',quietly=TRUE))stop('Install R package haven first.')
# DHS complex survey design for this module.
.dhs_root <- Sys.getenv('NIGERIA_PROJECT_ROOT')
if (!nzchar(.dhs_root)) {
 .dhs_file <- sub('^--file=','',grep('^--file=',commandArgs(FALSE),value=TRUE)[1])
 .dhs_root <- dirname(dirname(normalizePath(.dhs_file)))
}
source(file.path(.dhs_root,'Code','dhs_survey_tools.R'),local=TRUE)
dhs_set_context(country='Nigeria',root=.dhs_root)
#!/usr/bin/env Rscript
# Parallel first-year and duration-aware 2025-current-user illustrations for
# seven selected discontinuation reasons (all except wanted pregnancy and
# partner disapproval). These are original-method endings, not necessarily
# exits from modern use. Historical duration risks are not causal forecasts.
root<-Sys.getenv("NIGERIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE));out<-file.path(root,'output/Supporting_data')
users<-read.csv(file.path(out,'nigeria_current_users_by_method_and_actionable_projection.csv'))
selected<-read.csv(file.path(out,'nigeria_selected_reason_extensions.csv'),check.names=FALSE)
landmarks<-readRDS(file.path(root,'Data/Derived/nigeria_historical_duration_landmarks.rds'))
duration<-read.csv(file.path(out,'nigeria_duration_landmark_support_and_risks.csv'))
methods<-c('Injectables','Implants','Pill','IUD','Other modern')
reason<-list('Method failure'=1L,'Other fertility-related'=c(9L,12L,13L),
 'Changes in menstrual bleeding'=15L,'Other side effects/health'=c(4L,5L),
 'Wanted more effective method'=7L,'Access/cost/convenience'=c(6L,8L,10L),
 'Other recorded reasons'=c(11L,96L,98L,99L,0L))
labels<-c('0–3','4–6','7–12','13–24','25–36','37–48','49–60','61+')
ep<-readRDS(file.path(root,'Data/Derived/nigeria_2024_modern_episodes.rds'))
ep<-ep[!ep$method_code%in%c(6L,7L),]
first_risk<-function(m,codes){z<-ep[ep$method_group==m,];S<-1;F<-0
 for(t in 1:12){at<-z$entry<t & z$exposure>=t;en<-at & z$discontinued & z$exposure==t;den<-sum(z$wt[at]);F<-F+S*sum(z$wt[en & z$reason_code%in%codes])/den;S<-S*(1-sum(z$wt[en])/den)};100*F}
rows<-list()
for(m in methods){
 stock<-users$current_users_2025[users$method==m]
 first<-selected[selected$scope==paste0('method_group::',m),]
 stopifnot(length(stock)==1L,nrow(first)==1L)
 bins<-duration[duration$method==m,]
 shares<-bins$current_weight/sum(bins$current_weight)
 for(j in seq_along(reason)){
   event<-reason[[j]]
   probs<-numeric(length(labels));support_n<-integer(length(labels))
   for(k in seq_along(labels)){
     target<-if(labels[k]=='61+')c('37–48','49–60') else labels[k]
     x<-landmarks[landmarks$method==m & landmarks$duration_bin%in%target,]
     support_n[k]<-nrow(x)
     probs[k]<-sum(x$wt*(x$ending_reason_code%in%event))/sum(x$wt)
   }
   risk<-sum(shares*probs)
   rows[[length(rows)+1L]]<-data.frame(method=m,reason=names(reason)[j],
     current_users_2025=stock,first_year_cause_risk_pct=first_risk(m,event),
     first_year_illustrative_endings=stock*first_risk(m,event)/100,
     duration_aware_next12_risk_pct=100*risk,
     duration_aware_illustrative_endings=stock*risk,
     minimum_historical_bin_landmarks=min(support_n),
     current_stock_61plus_share_pct=100*shares[labels=='61+'])
 }
}
result<-do.call(rbind,rows)
stopifnot(nrow(result)==35L)
write.csv(result,file.path(out,'nigeria_selected_current_user_method_reason_planning.csv'),row.names=FALSE)
totals<-aggregate(cbind(first_year_illustrative_endings,duration_aware_illustrative_endings)~method,
 result,sum)
total<-colSums(totals[,2:3])
cat('First-year illustrative selected endings',round(total[1]),
    'duration-aware selected endings',round(total[2]),'\n')
)----------------------")

MODULES[["42_nigeria_crossvalidated_selected_risk_strata.R"]] <- list(language="R", packaged_sha256="8c668d86988db26b02adc9f16d697d607c1382a3ca348db67e930bd12831cd05", args=character(0), code=r"----------------------(if(!requireNamespace('haven',quietly=TRUE))stop('Install R package haven first.')
# DHS complex survey design for this module.
.dhs_root <- Sys.getenv('NIGERIA_PROJECT_ROOT')
if (!nzchar(.dhs_root)) {
 .dhs_file <- sub('^--file=','',grep('^--file=',commandArgs(FALSE),value=TRUE)[1])
 .dhs_root <- dirname(dirname(normalizePath(.dhs_file)))
}
source(file.path(.dhs_root,'Code','dhs_survey_tools.R'),local=TRUE)
dhs_set_context(country='Nigeria',root=.dhs_root)
#!/usr/bin/env Rscript
# Out-of-fold risk stratification for 12-month discontinuation of the original
# modern method for any reason except wanted pregnancy or partner disapproval.
# The two excluded endings are competing events. This is an EPISODE-level
# risk-profile analysis, not woman-level sequence clustering.
#
# Predictive covariates are deliberately restricted to characteristics known
# at method start: original method, age group, and live-birth parity group.
# Interview-date marital status, wealth, education, region and residence are
# profiled after the risk strata are formed; they cannot generate a high-risk
# label mechanically and may have changed since an earlier episode.
#
# Five folds are assigned by DHS PSU within each stratum. Each episode's risk
# comes from a model that did not see its PSU. Observed selected-reason 12-month
# cumulative incidence is then estimated within the held-out risk strata with
# delayed entry and all competing endings retained. Stratified PSU bootstrap
# intervals hold the fitted scores and cut-points fixed; they do not include
# model-training uncertainty, which requires a nested bootstrap.

project <- Sys.getenv("NIGERIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
out <- file.path(project,"output","Supporting_data")
if(!requireNamespace("nnet",quietly=TRUE))
  install.packages("nnet",repos="https://cloud.r-project.org")
e <- readRDS(file.path(project,"Data/Derived/nigeria_2024_model_episode_covariates.rds"))
e <- e[!e$method_code %in% c(6L,7L),]
e$selected_event <- e$discontinued & e$exposure<=12 & e$entry<e$exposure & !(e$reason_code%in%c(2L,3L))
e$method_group <- factor(e$method_group,
  levels=c("Injectables","Implants","Pill","IUD","Other modern"))
e$age_group <- factor(e$age_group,levels=levels(e$age_group))
e$parity_group <- factor(e$parity_group,levels=levels(e$parity_group))
e$cluster <- as.character(e$cluster)
e$stratum <- as.integer(e$stratum)
stopifnot(nrow(e)>0L)

life <- function(d,w=d$wt){
  if(!nrow(d)||sum(w)<=0)return(NA_real_)
  survival <- 1;incidence <- 0
  for(t in 1:12){
    risk<-d$entry<t & d$exposure>=t
    den<-sum(w[risk]);if(den<=0)return(NA_real_)
    end<-risk & d$discontinued & d$exposure==t
    selected<-end & !(d$reason_code%in%c(2L,3L))
    incidence<-incidence+survival*sum(w[selected])/den
    survival<-survival*(1-sum(w[end])/den)
  }
  100*incidence
}

# Assign every PSU in the same DHS stratum to one validation fold.
cluster_frame <- unique(e[c("cluster","stratum")])
set.seed(20261005L)
cluster_frame$fold <- NA_integer_
for(s in unique(cluster_frame$stratum)){
  rows<-which(cluster_frame$stratum==s)
  cluster_frame$fold[rows] <- sample(rep(1:5,length.out=length(rows)))
}
e$fold <- cluster_frame$fold[match(e$cluster,cluster_frame$cluster)]
stopifnot(!anyNA(e$fold),all(table(e$fold)>1000L))

# Expand every episode over its observed at-risk months; repeated rows retain
# the same woman's sample weight and validation fold.
nmonths <- pmax(0L,pmin(12L,e$exposure)-e$entry)
index <- rep(seq_len(nrow(e)),nmonths)
month <- unlist(Map(function(first,n)seq.int(first+1L,length.out=n),
                    e$entry,nmonths),use.names=FALSE)
person <- e[index,c("woman_row","wt","method_group","age_group","parity_group","fold")]
person <- dhs_calendar_records(person,dhs_context()$ir)
person$month <- factor(month,levels=1:12)
ended <- e$discontinued[index] & month==e$exposure[index]
person$outcome <- factor(ifelse(!ended,"continue",
  ifelse(e$reason_code[index]%in%c(2L,3L),"excluded","selected")),
  levels=c("continue","selected","excluded"))
stopifnot(nrow(person)>50000L)
formula <- outcome ~ month + method_group + age_group + parity_group

predict_cif <- function(fit,x){
  survival<-rep(1,nrow(x));incidence<-numeric(nrow(x))
  for(t in 1:12){
    x$month<-factor(t,levels=1:12)
    p<-predict(fit,newdata=x,type="probs")
    incidence<-incidence+survival*p[,"selected"]
    survival<-survival*p[,"continue"]
  }
  100*incidence
}
e$oof_selected_risk_pct <- NA_real_
for(f in 1:5){
  fit<-dhs_multinom_fit(formula,data=person[person$fold!=f,],
    weights=person$wt[person$fold!=f],maxit=250,trace=FALSE,MaxNWts=10000)
  if(fit$convergence!=0L)stop("Fold ",f," failed to converge")
  held<-which(e$fold==f)
  e$oof_selected_risk_pct[held]<-predict_cif(fit,e[held,])
}
stopifnot(!anyNA(e$oof_selected_risk_pct))

weighted_quantile <- function(x,w,p){
  o<-order(x); x<-x[o];w<-w[o]
  x[which(cumsum(w)/sum(w)>=p)[1L]]
}
cut1<-weighted_quantile(e$oof_selected_risk_pct,e$wt,1/3)
cut2<-weighted_quantile(e$oof_selected_risk_pct,e$wt,2/3)
stopifnot(cut1<cut2)
e$risk_stratum <- factor(ifelse(e$oof_selected_risk_pct<=cut1,"Lower",
  ifelse(e$oof_selected_risk_pct<=cut2,"Middle","Higher")),
  levels=c("Lower","Middle","Higher"))
levels_risk<-levels(e$risk_stratum)

# Bootstrap realized (held-out) life-table rates and direct risk differences.
reps<-as.integer(Sys.getenv("RISK_STRATA_BOOTSTRAP_REPS","300"))
if(reps<100L)stop("Use at least 100 bootstrap replicates")
full_ir <- readRDS(file.path(project,'Data/raw_dhs_ir/NG2024DHS__NGIR8BDT__IR_raw.rds'))
cluster_frame <- unique(data.frame(cluster=as.character(full_ir$v021),stratum=as.numeric(full_ir$v022)))
clusters_by_stratum<-split(cluster_frame$cluster,cluster_frame$stratum)
stopifnot(all(lengths(clusters_by_stratum)>1L))
boot<-matrix(NA_real_,nrow=reps,ncol=3,dimnames=list(NULL,levels_risk))
for(b in seq_len(reps)){
  set.seed(20261005L+1000L+b)
  mult<-setNames(numeric(nrow(cluster_frame)),cluster_frame$cluster)
  for(ids in clusters_by_stratum){
    n<-length(ids);draw<-sample.int(n,n-1L,replace=TRUE)
    mult[ids]<-n/(n-1L)*tabulate(draw,nbins=n)
  }
  w<-e$wt*mult[e$cluster]
  for(j in seq_along(levels_risk)){
    take<-e$risk_stratum==levels_risk[j]
    boot[b,j]<-life(e[take,],w[take])
  }
}
stopifnot(all(colSums(!is.na(boot))>=.95*reps))
risk_rows<-do.call(rbind,lapply(levels_risk,function(g){
  z<-e[e$risk_stratum==g,]
  bb<-boot[,g]
  data.frame(risk_stratum=g,eligible_episodes=nrow(z),
    weighted_episodes=sum(z$wt),weighted_share_pct=100*sum(z$wt)/sum(e$wt),
    selected_endings=sum(z$selected_event),
    predicted_risk_median_pct=weighted_quantile(z$oof_selected_risk_pct,z$wt,.5),
    observed_12_month_probability_pct=life(z),
    ci_low=unname(quantile(bb,.025,na.rm=TRUE)),
    ci_high=unname(quantile(bb,.975,na.rm=TRUE)))
}))
differences<-data.frame(comparison=c("Middle minus Lower","Higher minus Middle","Higher minus Lower"),
  estimate_pp=c(diff(risk_rows$observed_12_month_probability_pct),
                risk_rows$observed_12_month_probability_pct[3]-risk_rows$observed_12_month_probability_pct[1]),
  ci_low=NA_real_,ci_high=NA_real_)
bd<-cbind(boot[,2]-boot[,1],boot[,3]-boot[,2],boot[,3]-boot[,1])
differences$ci_low<-apply(bd,2,quantile,.025,na.rm=TRUE,names=FALSE)
differences$ci_high<-apply(bd,2,quantile,.975,na.rm=TRUE,names=FALSE)

# Describe the distribution of each characteristic within a stratum. These
# profile shares are not adjusted effects. Age, parity, and method created the
# risk score; their enrichment is therefore partly mechanical. Interview-date
# variables did not enter the score, but may have changed after method start.
profile_variables<-c("method_group","age_group","parity_group",
                     "marital_group","education","wealth","residence")
profile<-do.call(rbind,lapply(profile_variables,function(v){
  do.call(rbind,lapply(levels_risk,function(g){
    z<-e[e$risk_stratum==g,];den<-sum(z$wt)
    lev<-sort(unique(as.character(e[[v]])))
    do.call(rbind,lapply(lev,function(l){
      a<-z[as.character(z[[v]])==l,]
      data.frame(characteristic=v,level=l,risk_stratum=g,
        unweighted_episodes=nrow(a),weighted_share_within_stratum_pct=100*sum(a$wt)/den)
    }))
  }))
}))

write.csv(e[,c("woman_row","episode_id","wt","cluster","stratum","fold",
              "method_group","age_group","parity_group","marital_group",
              "education","wealth","residence","entry","exposure",
              "discontinued","reason_code","selected_event","oof_selected_risk_pct",
              "risk_stratum")],
  file.path(out,"nigeria_selected_reason_oof_episode_scores.csv"),row.names=FALSE)
write.csv(risk_rows,file.path(out,"nigeria_selected_reason_crossvalidated_risk_strata.csv"),row.names=FALSE)
write.csv(differences,file.path(out,"nigeria_selected_reason_risk_strata_differences.csv"),row.names=FALSE)
write.csv(profile,file.path(out,"nigeria_selected_reason_risk_strata_profiles.csv"),row.names=FALSE)
write.csv(data.frame(eligible_episodes=nrow(e),weighted_episodes=sum(e$wt),
  risk_cut_lower_middle_pct=cut1,risk_cut_middle_higher_pct=cut2,
  folds=5,bootstrap_reps=reps,primary_predictors="Method, age and parity at episode start",
  note="Fixed-cutpoint bootstrap intervals do not include model-training uncertainty"),
  file.path(out,"nigeria_selected_reason_risk_strata_audit.csv"),row.names=FALSE)
cat("Out-of-fold cut-points:",round(cut1,2),round(cut2,2),"percent\n")
print(risk_rows,row.names=FALSE)
print(differences,row.names=FALSE)
)----------------------")

MODULES[["44_nigeria_replication_figures.R"]] <- list(language="R", packaged_sha256="3ec36d9aaf19d547dcd2e861e660d02c0eb00c7afcaf26358e199ba9ace372ea", args=character(0), code=r"----------------------(if(!requireNamespace('haven',quietly=TRUE))stop('Install R package haven first.')
# DHS complex survey design for this module.
.dhs_root <- Sys.getenv('NIGERIA_PROJECT_ROOT')
if (!nzchar(.dhs_root)) {
 .dhs_file <- sub('^--file=','',grep('^--file=',commandArgs(FALSE),value=TRUE)[1])
 .dhs_root <- dirname(dirname(normalizePath(.dhs_file)))
}
source(file.path(.dhs_root,'Code','dhs_survey_tools.R'),local=TRUE)
dhs_set_context(country='Nigeria',root=.dhs_root)
#!/usr/bin/env Rscript
# Reproduce the principal figure families in the Ethiopia working HTML using
# Nigeria DHS 2024 estimates already saved by the documented analysis scripts.
# No figures or estimates are copied from Ethiopia.
suppressPackageStartupMessages({library(ggplot2);library(svglite)})
root <- file.path(Sys.getenv("NIGERIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE)), 'output')
dat <- file.path(root, 'Supporting_data')
assets <- file.path(root, 'assets')
dir.create(assets, recursive=TRUE, showWarnings=FALSE)
read <- function(x) read.csv(file.path(dat, x), check.names=FALSE, stringsAsFactors=FALSE)
navy <- '#153F5B'; teal <- '#108B8D'; gold <- '#DA9A25'; red <- '#D45A49'; gray <- '#85909D'
zones <- c('North West','North East','North Central','South East','South South','South West')
methods <- c('Injectables','Implants','Pill','IUD','Other modern')
base <- theme_minimal(base_family='Arial', base_size=13)+theme(plot.title=element_text(family='Georgia',face='bold',size=19,color=navy),plot.subtitle=element_text(size=11,color=navy),panel.grid.minor=element_blank(),panel.grid.major.y=element_blank(),axis.title.y=element_blank(),legend.position='bottom',plot.margin=margin(20,22,20,22))
save <- function(p, name, w=11.5,h=6.5) {
 ggsave(file.path(assets,name),p,width=w,height=h,device=svglite::svglite,bg='white')
 ggsave(file.path(assets,sub('\\.svg$','.png',name)),p,width=w,height=h,dpi=150,bg='white')
}

# Overall and zone method-start mix: denominator includes every recorded method
# start, including emergency contraception and non-modern methods.
mix <- read('nigeria_zone_all_method_start_mix.csv')
mix$method <- factor(mix$method, levels=c('Injectables','Implants','Pill','IUD','Other modern','Non-modern methods','Emergency contraception'))
mix$scope <- factor(mix$scope, levels=rev(c('National',zones)))
pal <- c('Injectables'=teal,'Implants'=navy,'Pill'=gold,'IUD'=red,'Other modern'=gray,'Non-modern methods'='#A48865','Emergency contraception'='#B65F8C')
mix_plot <- ggplot(mix,aes(x=scope,y=start_share_pct,fill=method))+geom_col(width=.70)+scale_fill_manual(values=pal,drop=FALSE)+scale_y_continuous(limits=c(0,101),breaks=seq(0,100,20),expand=expansion(mult=c(0,0)))+labs(title='Method starts differ across Nigeria’s six zones',subtitle='Weighted share of all method starts, national benchmark first',x=NULL,y='Percent of observed starts',fill=NULL)+coord_flip()+base+theme(legend.text=element_text(size=11))
save(mix_plot,'nigeria_regional_method_start_mix.svg',12,6)

# Cumulative incidence lines keep excluded endings as competing events.
times <- read('nigeria_modern_all_reason_timepoints.csv')
curve <- subset(times, scope %in% c('National',paste0('National: ',methods)))
curve$Method <- ifelse(curve$scope=='National','All modern',sub('National: ','',curve$scope))
curve$month <- as.numeric(curve$month)
starts <- curve[match(c('National',paste0('National: ',methods)),curve$scope),,drop=FALSE]
starts$month <- 0; starts$all_reason_pct <- 0; starts$selected_reason_pct <- 0; starts$actionable_pct <- 0
curve <- rbind(starts,curve)
curve$Method <- factor(curve$Method,levels=c('All modern',methods))
cpal <- c('All modern'='#334957','Injectables'=teal,'Implants'=navy,'Pill'=gold,'IUD'=red,'Other modern'=gray)
for (measure in c('all_reason_pct','selected_reason_pct','actionable_pct')) {
 ttl <- switch(measure,all_reason_pct='All-reason discontinuation accumulates during year one',selected_reason_pct='Selected-reason discontinuation accumulates during year one',actionable_pct='Actionable discontinuation accumulates during year one')
 p <- ggplot(curve,aes(x=month,y=.data[[measure]],color=Method,group=Method))+geom_step(linewidth=1.15)+geom_point(data=subset(curve,month==12),size=2.8)+scale_color_manual(values=cpal)+scale_x_continuous(breaks=c(0,3,6,9,12),limits=c(0,12))+scale_y_continuous(labels=function(x)paste0(x,'%'),limits=c(0,max(curve[[measure]],na.rm=TRUE)*1.10))+labs(title=ttl,subtitle='Weighted cumulative probability of ending the original modern method',x='Months since method start',y='Cumulative discontinuation probability',color=NULL)+base
 save(p,paste0('nigeria_',measure,'_method_curves.svg'),11.7,6.3)
}

# Analog of the presentation slide with a method's share of starts and risk.
start <- subset(mix,scope=='National' & as.character(method) %in% methods)
ec_starts <- subset(mix,scope=='National' & as.character(method)=='Emergency contraception')$weighted_starts
start$start_share_pct <- 100*start$weighted_starts/(start$denominator_weighted_starts-ec_starts)
risk <- subset(times,month==12 & scope %in% paste0('National: ',methods))
risk$method <- sub('National: ','',risk$scope)
paired <- merge(start[,c('method','start_share_pct')],risk[,c('method','all_reason_pct','actionable_pct')],by='method')
paired$method <- factor(as.character(paired$method),levels=rev(methods))
for (measure in c('all_reason_pct','actionable_pct')) {
 d <- rbind(data.frame(method=paired$method,type='Share of all method starts',pct=paired$start_share_pct),data.frame(method=paired$method,type='12-month discontinuation',pct=paired[[measure]]))
 d$type <- factor(d$type,levels=c('Share of all method starts','12-month discontinuation'))
 p <- ggplot(d,aes(x=method,y=pct,fill=type))+geom_col(position=position_dodge2(width=.72,padding=0),width=.72)+geom_text(aes(label=sprintf('%.1f',pct)),position=position_dodge2(width=.72,padding=0),hjust=-.12,size=3.7,color='black')+scale_fill_manual(values=c('Share of all method starts'=gold,'12-month discontinuation'=navy))+scale_y_continuous(limits=c(0,max(d$pct)*1.18),breaks=seq(0,100,20))+coord_flip()+labs(title=if(measure=='all_reason_pct')'Starts and all-reason discontinuation by method' else 'Starts and actionable discontinuation by method',subtitle='Start-share denominator excludes EC; 12-month risk is among episodes of that method',x=NULL,y='Percent',fill=NULL)+base
 save(p,paste0('nigeria_national_start_vs_',measure,'.svg'),11.5,6)
}

# Actionable timing heatmap with an explicit early-share column.
tt <- read('nigeria_actionable_timepoints.csv');tt <- subset(tt,scope %in% c('National',zones));tt$scope <- factor(tt$scope,levels=rev(c('National',zones)))
wide <- reshape(tt[,c('scope','month','actionable_pct')],idvar='scope',timevar='month',direction='wide')
wide$early <- 100*wide[['actionable_pct.3']]/wide[['actionable_pct.12']]
long <- rbind(data.frame(scope=wide$scope,month='First 3 of 12 months',pct=wide$early),do.call(rbind,lapply(c(3,6,9,12),function(m)data.frame(scope=wide$scope,month=paste(m,'months'),pct=wide[[paste0('actionable_pct.',m)]]))))
long$month <- factor(long$month,levels=c('3 months','6 months','9 months','12 months','First 3 of 12 months'))
heat <- ggplot(long,aes(month,scope,fill=pct))+geom_tile(color='white',linewidth=2)+geom_text(aes(label=sprintf('%.1f',pct)),size=4,color='black')+scale_fill_gradient(low='#E8F1F3',high=teal)+scale_x_discrete(position='top')+labs(title='Actionable discontinuation accumulates at different rates',subtitle='Cumulative probability by month; final column is the share of the 12-month risk occurring by month 3',x=NULL,y=NULL,fill='Percent')+base+theme(panel.grid=element_blank(),axis.text.x=element_text(face='plain'),legend.position='none')
save(heat,'nigeria_actionable_zone_timing_heatmap.svg',12,5.7)

# Zone reason mix: each row is conditional on an actionable ending and sums to 100.
rmix <- read('nigeria_actionable_reason_mix.csv');rmix <- subset(rmix,scope %in% c('National',zones));rmix$scope <- factor(rmix$scope,levels=rev(c('National',zones)))
rmix$reason <- factor(rmix$reason,levels=c('Method failure','Wanted more effective method','Changes in menstrual bleeding','Other side effects/health','Access/cost/convenience'))
reasons <- ggplot(rmix,aes(reason,scope,fill=share_among_actionable_pct))+geom_tile(color='white',linewidth=2)+geom_text(aes(label=sprintf('%.0f',share_among_actionable_pct)),size=3.7,color='black')+scale_fill_gradient(low='#E8F1F3',high=teal)+scale_x_discrete(position='top',labels=function(x)gsub(' ','\n',x,fixed=TRUE))+labs(title='Reasons differ across zones',subtitle='Share among first-year potentially actionable discontinuations; rows total 100%',x=NULL,y=NULL,fill='Percent')+base+theme(panel.grid=element_blank(),axis.text.x=element_text(size=10),legend.position='none')
save(reasons,'nigeria_actionable_zone_reason_heatmap.svg',12,5.7)

# Regional observed and fully adjusted rates; every displayed CI is survey-bootstrap.
ad <- read('nigeria_actionable_zone_adjusted_rates.csv');ad <- subset(ad,zone %in% c('National',zones));ad$zone <- factor(ad$zone,levels=rev(c('National',zones)))
dd <- rbind(data.frame(zone=ad$zone,type='Observed',rate=ad$unadjusted_pct,low=ad$unadjusted_low,high=ad$unadjusted_high),data.frame(zone=ad$zone,type='Fully adjusted',rate=ad$model_2_common_mix_pct,low=ad$model_2_low,high=ad$model_2_high))
dd$type <- factor(dd$type,levels=c('Observed','Fully adjusted'))
forest <- ggplot(dd,aes(rate,zone,color=type))+geom_errorbar(aes(xmin=low,xmax=high),orientation='y',position=position_dodge(width=.5),width=.16,linewidth=.75)+geom_point(position=position_dodge(width=.5),size=2.8)+scale_color_manual(values=c('Observed'=gold,'Fully adjusted'=navy))+scale_x_continuous(limits=c(max(0,min(dd$low)-2),max(dd$high)+2),labels=function(x)paste0(x,'%'))+labs(title='Observed and adjusted actionable discontinuation',subtitle='12-month regional probabilities with 95% survey-bootstrap intervals',x='Probability of ending the original modern method',y=NULL,color=NULL)+base
save(forest,'nigeria_actionable_zone_observed_adjusted.svg',12,6)

# Selected-reason regional risk and conditional reason mix. These seven reason
# shares sum to 100 within each zone and are a different denominator from risk.
sel <- read('nigeria_selected_reason_extensions.csv')
sel <- subset(sel,variable=='zone_name')
sel$category <- factor(sel$category,levels=rev(zones))
sforest <- ggplot(sel,aes(selected_12_month_pct,category))+geom_errorbar(aes(xmin=ci_low,xmax=ci_high),orientation='y',width=.18,color=teal,linewidth=.8)+geom_point(size=3,color=teal)+scale_x_continuous(labels=function(x)paste0(x,'%'))+labs(title='Selected-reason discontinuation by zone',subtitle='Unadjusted 12-month probability and 95% survey-bootstrap interval',x='Probability of ending the original method',y=NULL)+base
save(sforest,'nigeria_selected_reason_zone_forest.svg',11.5,5.8)
reason_labels <- c('Method failure','Other fertility-related','Bleeding','Other side effects/health','More effective method','Access/cost/convenience','Other recorded')
sr <- do.call(rbind,lapply(seq_along(reason_labels),function(i)data.frame(zone=sel$category,reason=reason_labels[i],pct=sel[[paste0('share_',i,'_pct')]])))
sr$reason <- factor(sr$reason,levels=reason_labels)
sh <- ggplot(sr,aes(reason,zone,fill=pct))+geom_tile(color='white',linewidth=1.8)+geom_text(aes(label=sprintf('%.0f',pct)),size=3.1,color='black')+scale_fill_gradient(low='#E8F1F3',high=teal)+scale_x_discrete(position='top',labels=function(x)gsub(' ','\n',x,fixed=TRUE))+labs(title='Reasons within selected discontinuations',subtitle='Shares conditional on selected ending; each zone row sums to 100%',x=NULL,y=NULL,fill='Percent')+base+theme(panel.grid=element_blank(),axis.text.x=element_text(size=9),legend.position='none')
save(sh,'nigeria_selected_reason_zone_heatmap.svg',12,5.8)

sm <- read('nigeria_selected_reason_zone_models.csv');sm<-subset(sm,zone%in%c('National',zones));sm$zone<-factor(sm$zone,levels=rev(c('National',zones)))
sd <- rbind(data.frame(zone=sm$zone,type='Observed',rate=sm$unadjusted_pct,low=sm$unadjusted_low,high=sm$unadjusted_high),
 data.frame(zone=sm$zone,type='Method adjusted',rate=sm$model_1_pct,low=sm$model_1_low,high=sm$model_1_high),
 data.frame(zone=sm$zone,type='Fully adjusted',rate=sm$model_2_pct,low=sm$model_2_low,high=sm$model_2_high))
sd$type<-factor(sd$type,levels=c('Observed','Method adjusted','Fully adjusted'))
sp<-ggplot(sd,aes(rate,zone,color=type))+geom_errorbar(aes(xmin=low,xmax=high),orientation='y',position=position_dodge(width=.62),width=.12,linewidth=.6)+geom_point(position=position_dodge(width=.62),size=2.6)+scale_color_manual(values=c('Observed'=gold,'Method adjusted'=teal,'Fully adjusted'=navy))+scale_x_continuous(labels=function(x)paste0(x,'%'))+labs(title='Selected-reason risk after adjustment',subtitle='Regional estimates; adjusted intervals use 80 bootstrap refits and remain preliminary',x='12-month original-method discontinuation probability',y=NULL,color=NULL)+base
save(sp,'nigeria_selected_reason_zone_adjusted.svg',12,6)

# All-reason month-12 status by original method, a companion to the alluvial.
follow <- read('nigeria_all_reason_method_to_month_12_alluvial.csv')
follow$method<-factor(follow$method,levels=rev(methods))
follow$destination<-factor(follow$destination,levels=c('No method recorded','Different modern method','Same modern method','Pregnancy, birth or termination','Traditional/other method','Other/unknown'))
follow$share<-ave(follow$weighted_endings,follow$method,FUN=function(x)100*x/sum(x))
fpal<-c('No method recorded'='#85909D','Different modern method'=navy,'Same modern method'=teal,'Pregnancy, birth or termination'=red,'Traditional/other method'=gold,'Other/unknown'='#B8BEC5')
fp<-ggplot(follow,aes(method,share,fill=destination))+geom_col(width=.69)+scale_fill_manual(values=fpal,drop=TRUE)+scale_y_continuous(limits=c(0,101),breaks=seq(0,100,20))+coord_flip()+labs(title='Modern use varies 12 months after an all-reason ending',subtitle='Weighted share among observed first-year endings with 12-month follow-up',x=NULL,y='Percent of observed endings',fill=NULL)+base+theme(legend.text=element_text(size=10))
save(fp,'nigeria_all_reason_month12_followup_stacked.svg',11.8,6)

# Injectable reason, timing, and next-month destination. Row percentages are
# conditional on the named reason and add to 100 before rounding.
inj <- read('nigeria_injectable_reason_timing_destination.csv')
tim<-aggregate(wt~reason_label+duration_group,inj,sum)
tim$share<-ave(tim$wt,tim$reason_label,FUN=function(x)100*x/sum(x))
dest1<-aggregate(wt~reason_label+destination,inj,sum)
dest1$share<-ave(dest1$wt,dest1$reason_label,FUN=function(x)100*x/sum(x))
no<-subset(dest1,destination=='No method recorded')
no<-merge(data.frame(reason_label=unique(tim$reason_label)),no[,c('reason_label','share')],by='reason_label',all.x=TRUE)
no$share[is.na(no$share)]<-0
no$duration_group<-'No method one month later'
ih<-rbind(tim[,c('reason_label','duration_group','share')],no[,c('reason_label','duration_group','share')])
ih$duration_group<-factor(ih$duration_group,levels=c('1–3 months','4–6 months','7–12 months','No method one month later'))
ih$reason_label<-factor(ih$reason_label,levels=rev(c('Method failure','Wanted more effective method','Changes in menstrual bleeding','Other side effects/health','Access/cost/convenience')))
ip<-ggplot(ih,aes(duration_group,reason_label,fill=share))+geom_tile(color='white',linewidth=2)+geom_text(aes(label=sprintf('%.0f',share)),size=4,color='black')+scale_fill_gradient(low='#E8F1F3',high=teal)+scale_x_discrete(position='top',labels=c('1–3\nmonths','4–6\nmonths','7–12\nmonths','No method\nnext month'))+labs(title='Injectable ending timing and next-month nonuse by reason',subtitle='First three columns sum to 100 within reason; final column is a separate next-month outcome',x=NULL,y=NULL,fill='Percent')+base+theme(panel.grid=element_blank(),legend.position='none')
save(ip,'nigeria_injectable_reason_timing_destination_heatmap.svg',12,5.5)
cat('Created Nigeria figures in',assets,'\n')
)----------------------")

MODULES[["70_modern_five_year_reasons.R"]] <- list(language="R", packaged_sha256="484b8482c02efa21a0e364bfef6fb38bcad0c2b3f955ea4160cde54145a709f1", args=character(0), code=r"----------------------(if(!requireNamespace('haven',quietly=TRUE))stop('Install R package haven first.')
# DHS complex survey design for this module.
.dhs_root <- Sys.getenv('NIGERIA_PROJECT_ROOT')
if (!nzchar(.dhs_root)) {
 .dhs_file <- sub('^--file=','',grep('^--file=',commandArgs(FALSE),value=TRUE)[1])
 .dhs_root <- dirname(dirname(normalizePath(.dhs_file)))
}
source(file.path(.dhs_root,'Code','dhs_survey_tools.R'),local=TRUE)
dhs_set_context(country='Nigeria',root=.dhs_root)
#!/usr/bin/env Rscript
# Match Ethiopia's five-year reason-distribution denominator: observed endings
# of modern-method episodes, excluding emergency contraception. Reconstruct
# the published all-method column first as a validation control.
root <- Sys.getenv("NIGERIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
x <- readRDS(file.path(root,'Data/raw_dhs_ir/NG2024DHS__NGIR8BDT__IR_raw.rds'))
method_chars <- strsplit('123456789WNALCFEMS~','')[[1]]
reason_map <- c('1'=1L,'2'=2L,'3'=3L,'7'=4L,'M'=5L,
                '4'=6L,'6'=7L,'C'=8L,'8'=9L,'F'=10L,
                'A'=11L,'9'=12L,'D'=13L,'W'=14L,'K'=15L,'?'=16L)
reason_labels <- c('Became pregnant while using','Wanted to become pregnant',
  'Husband/partner disapproved','Wanted a more effective method',
  'Changes in menstrual bleeding','Other side effects/health concerns',
  'Lack of access/too far','Cost too much','Inconvenient to use',
  'Up to God/fatalistic','Difficult to get pregnant/menopausal',
  'Infrequent sex/husband away','Marital dissolution/separation','Other',
  'Don’t know','Missing')
pieces <- vector('list',nrow(x))
for(i in seq_len(nrow(x))){
  pos <- as.integer(x$v018[i]) + 0:59
  chars <- substring(sprintf('%-80s',x$vcal_2[i]),pos,pos)
  keep <- chars!=' '
  if(any(keep))pieces[[i]] <- data.frame(
    method_code=match(substring(x$vcal_1[i],pos[keep],pos[keep]),method_chars),
    reason_code=unname(reason_map[chars[keep]]),
    wt=as.numeric(x$v005[i])/1e6)
}
ev <- do.call(rbind,pieces)
ev <- ev[!is.na(ev$method_code)&!is.na(ev$reason_code),]
published <- read.csv(file.path(root,'output/Supporting_data/nigeria_published_table_7_13_reason_distribution.csv'),check.names=FALSE)
all_dist <- vapply(1:16,function(k)100*sum(ev$wt[ev$reason_code==k])/sum(ev$wt),numeric(1))
check <- data.frame(reason=reason_labels,computed=round(all_dist,1),published=published[['All methods']])
print(check,row.names=FALSE)
cat('All-method endings:',nrow(ev),'weighted:',sum(ev$wt),'\n')
if(max(abs(check$computed-check$published))>0.2)stop('All-method DHS validation failed')
modern_codes <- c(1L,2L,3L,5L,6L,7L,11L,13L,14L,15L,17L,18L,19L,20L)
ev <- ev[ev$method_code %in% modern_codes,]
ev$method <- ifelse(ev$method_code==3,'Injectables',
  ifelse(ev$method_code==11,'Implants',
  ifelse(ev$method_code==1,'Pill',
  ifelse(ev$method_code==2,'IUD','Other modern'))))
ev$group <- ifelse(ev$reason_code==2,'Wanted pregnancy',
  ifelse(ev$reason_code %in% c(1,4:9),'Method experience/access',
  ifelse(ev$reason_code==3,'Partner disapproval','Other reasons')))
groups <- c('Wanted pregnancy','Method experience/access','Partner disapproval','Other reasons')
out <- do.call(rbind,lapply(c('All modern','Injectables','Implants','Pill','IUD','Other modern'),function(m){
  d <- if(m=='All modern')ev else ev[ev$method==m,]
  data.frame(method=m,reason_group=groups,
    percent=vapply(groups,function(g)100*sum(d$wt[d$group==g])/sum(d$wt),numeric(1)),
    unweighted_endings=nrow(d),weighted_endings=sum(d$wt))
}))
stopifnot(all(abs(tapply(out$percent,out$method,sum)-100)<1e-8))
dest <- file.path(root,'output/Supporting_data/nigeria_modern_five_year_reason_distribution.csv')
write.csv(out,dest,row.names=FALSE)
seven <- c('Wanted to become pregnant'=2,
  'Bleeding / other health'=NA,
  'Wanted a more effective method'=4,
  'Access / cost / convenience'=NA,
  'Method failure'=1,
  'Partner disapproval'=3,
  'Other recorded reasons'=NA)
seven_percent <- vapply(names(seven),function(label){
  codes <- switch(label,
    'Bleeding / other health'=5:6,
    'Access / cost / convenience'=7:9,
    'Other recorded reasons'=10:16,
    seven[[label]])
  100*sum(ev$wt[ev$reason_code %in% codes])/sum(ev$wt)
},numeric(1))
seven_out <- data.frame(reason=names(seven),percent=unname(seven_percent),
  unweighted_endings=nrow(ev),weighted_endings=sum(ev$wt))
stopifnot(abs(sum(seven_out$percent)-100)<1e-8)
write.csv(seven_out,file.path(root,'output/Supporting_data/nigeria_modern_five_year_reason_distribution_seven.csv'),row.names=FALSE)
print(seven_out,row.names=FALSE)
print(out[out$method=='All modern',],row.names=FALSE)
cat(dest,'\n')
)----------------------")

MODULES[["89_nigeria_aft_duration_by_method.R"]] <- list(language="R", packaged_sha256="793e0ed65522f0361e7c81d15a1de9098ffd3db022217af11be0184a74d4a06f", args=character(0), code=r"----------------------(if(!requireNamespace('haven',quietly=TRUE))stop('Install R package haven first.')
# DHS complex survey design for this module.
.dhs_root <- Sys.getenv('NIGERIA_PROJECT_ROOT')
if (!nzchar(.dhs_root)) {
 .dhs_file <- sub('^--file=','',grep('^--file=',commandArgs(FALSE),value=TRUE)[1])
 .dhs_root <- dirname(dirname(normalizePath(.dhs_file)))
}
source(file.path(.dhs_root,'Code','dhs_survey_tools.R'),local=TRUE)
dhs_set_context(country='Nigeria',root=.dhs_root)
#!/usr/bin/env Rscript
# Nigeria DHS 2024: next-12-month actionable original-method ending risk
# conditional on a current user's elapsed method duration. Other endings
# compete. This is a descriptive AFT sensitivity analysis, not a forecast.

root <- Sys.getenv("NIGERIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
support <- file.path(root, 'output/Supporting_data')
e <- readRDS(file.path(root, 'Data/Derived/nigeria_2024_modern_episodes.rds'))
e <- e[!e$method_code %in% c(6L,7L),]
ir <- readRDS(file.path(root, 'Data/raw_dhs_ir/NG2024DHS__NGIR8BDT__IR_raw.rds'))
stocks <- read.csv(file.path(support, 'nigeria_current_users_by_method_and_actionable_projection.csv'))
landmark <- read.csv(file.path(support, 'nigeria_duration_aware_current_user_bridge.csv'))
wra26 <- read.csv(file.path(support, 'nigeria_2026_mcpr_scenarios.csv'))$wra_2026[1]

modern_codes <- c(1L,2L,3L,5L,11L,13L,14L,15L,17L,18L,19L,20L)
methods <- c('Injectables','Implants','Pill','IUD','Other modern')
method_group <- function(z) ifelse(z==3L,'Injectables',ifelse(z==11L,'Implants',
  ifelse(z==1L,'Pill',ifelse(z==2L,'IUD','Other modern'))))
actionable_codes <- c(1L,4L,5L,6L,7L,8L,10L,15L)

# AFT time from method start is identified only for visible starts. Episodes
# whose use began before calendar observation stay in descriptive life tables.
e <- e[e$entry==0L & e$method_code %in% modern_codes & e$exposure>0L,]
e$method <- factor(method_group(e$method_code),levels=methods)
e$action_event <- as.integer(e$discontinued & e$reason_code %in% actionable_codes)
e$other_event <- as.integer(e$discontinued & !e$reason_code %in% actionable_codes)
stopifnot(nrow(e)>0L,all(e$action_event+e$other_event<=1L),
  all(e$exposure>=1L),max(e$exposure)<=72L)

suppressPackageStartupMessages(library(survival))
fit_candidates <- function(event){
  choices <- c('weibull','loglogistic','lognormal','exponential')
  fits <- lapply(choices,function(d)dhs_aft_fit(
    as.formula(paste0('Surv(exposure,',event,')~method')),
    data=e,weights=wt,dist=d,control=survreg.control(maxiter=100)))
  aic <- vapply(fits,dhs_aft_aic,0.0); names(aic) <- choices
  best <- which.min(aic)
  list(fit=fits[[best]],distribution=choices[best],aic=aic)
}
model_a <- fit_candidates('action_event')
model_o <- fit_candidates('other_event')
fit_a <- model_a$fit; fit_o <- model_o$fit
stopifnot(fit_a$iter<100,fit_o$iter<100)
models <- lapply(methods,function(m){
  d <- data.frame(method=factor(m,levels=methods))
  c(mu_a=as.numeric(predict(fit_a,newdata=d,type='lp')),
    scale_a=fit_a$scale,mu_o=as.numeric(predict(fit_o,newdata=d,type='lp')),
    scale_o=fit_o$scale)
})
names(models) <- methods
cumhaz <- function(t,mu,scale,dist){
  if(t<=0)return(0)
  if(dist=='weibull')return((t/exp(mu))^(1/scale))
  if(dist=='exponential')return(t/exp(mu))
  if(dist=='loglogistic')return(log1p(exp((log(t)-mu)/scale)))
  if(dist=='lognormal')return(-pnorm((log(t)-mu)/scale,lower.tail=FALSE,log.p=TRUE))
  stop('Unsupported AFT distribution')
}
next12 <- function(age,par){
  s <- 1; risk_a <- 0; risk_o <- 0
  for(t in seq.int(age+1,age+12)){
    da <- cumhaz(t,par['mu_a'],par['scale_a'],model_a$distribution)-
      cumhaz(t-1,par['mu_a'],par['scale_a'],model_a$distribution)
    do <- cumhaz(t,par['mu_o'],par['scale_o'],model_o$distribution)-
      cumhaz(t-1,par['mu_o'],par['scale_o'],model_o$distribution)
    total <- da+do
    event <- s*(-expm1(-total))
    if(total>0){risk_a <- risk_a+event*da/total;risk_o <- risk_o+event*do/total}
    s <- s*exp(-total)
  }
  c(actionable=risk_a,other=risk_o,any=risk_a+risk_o)
}

current <- ir[as.numeric(ir$v313)==3 & as.numeric(ir$v312) %in% modern_codes,]
current$method <- method_group(as.integer(current$v312))
current$elapsed <- dhs_current_duration(current,seq_len(nrow(current)))
current$wt <- as.numeric(current$v005)/1e6
stopifnot(!anyNA(current$elapsed),all(current$elapsed>=0),
  all(current$method %in% methods))
rows <- lapply(methods,function(m){
  d <- current[current$method==m,]
  ages <- sort(unique(d$elapsed))
  risk <- vapply(ages,function(a)unname(next12(a,models[[m]])[1]),0.0)
  probability <- weighted.mean(risk[match(d$elapsed,ages)],d$wt)
  duration_weight <- tapply(d$wt,d$elapsed,sum)
  duration_weight <- duration_weight[order(as.numeric(names(duration_weight)))]
  median_duration <- as.numeric(names(duration_weight)[which(cumsum(duration_weight)>=sum(duration_weight)/2)[1]])
  stock <- stocks$current_users_2025[stocks$method==m]
  first <- stocks$actionable_first_year_risk_pct[stocks$method==m]
  old <- landmark$actionable_ending_risk_next12_pct[landmark$method==m]
  stopifnot(length(stock)==1L,length(first)==1L,length(old)==1L)
  data.frame(method=m,eligible_starts_n=sum(e$method==m),
    actionable_events_n=sum(e$method==m & e$action_event==1L),
    current_users_n=nrow(d),current_users_2025=stock,
    weighted_current_user_duration_median=median_duration,
    current_user_weight_share_duration_over60_pct=100*sum(d$wt[d$elapsed>60])/sum(d$wt),
    first_year_actionable_risk_pct=first,
    modeled_first_year_actionable_risk_pct=100*unname(next12(0,models[[m]])[1]),
    historical_landmark_next12_risk_pct=old,
    survival_model_next12_risk_pct=100*probability,
    survival_model_original_method_endings=stock*probability,
    gross_mcpr_equivalent_pp=100*stock*probability/wra26)
})
out <- do.call(rbind,rows)
out <- rbind(out,data.frame(method='All modern (EC excluded)',
  eligible_starts_n=sum(out$eligible_starts_n),
  actionable_events_n=sum(out$actionable_events_n),
  current_users_n=sum(out$current_users_n),
  current_users_2025=sum(out$current_users_2025),
  weighted_current_user_duration_median=NA_real_,
  current_user_weight_share_duration_over60_pct=100*sum(current$wt[current$elapsed>60])/sum(current$wt),
  first_year_actionable_risk_pct=weighted.mean(out$first_year_actionable_risk_pct,out$current_users_2025),
  modeled_first_year_actionable_risk_pct=weighted.mean(out$modeled_first_year_actionable_risk_pct,out$current_users_2025),
  historical_landmark_next12_risk_pct=weighted.mean(out$historical_landmark_next12_risk_pct,out$current_users_2025),
  survival_model_next12_risk_pct=weighted.mean(out$survival_model_next12_risk_pct,out$current_users_2025),
  survival_model_original_method_endings=sum(out$survival_model_original_method_endings),
  gross_mcpr_equivalent_pp=sum(out$gross_mcpr_equivalent_pp)))
stopifnot(all(is.finite(out$survival_model_next12_risk_pct)),
  all(out$survival_model_next12_risk_pct>=0 & out$survival_model_next12_risk_pct<=100))
write.csv(out,file.path(support,'nigeria_survival_model_duration_by_method.csv'),row.names=FALSE)
fit_report <- data.frame(distribution=names(model_a$aic),
  actionable_aic=as.numeric(model_a$aic),other_aic=as.numeric(model_o$aic),
  selected_actionable=names(model_a$aic)==model_a$distribution,
  selected_other=names(model_o$aic)==model_o$distribution)
write.csv(fit_report,file.path(support,'nigeria_survival_model_duration_fit.csv'),row.names=FALSE)
cat('Nigeria AFT gross original-method endings',sum(out$survival_model_original_method_endings[1:5]),'\n')
cat('Selected AFT distributions:',model_a$distribution,'for actionable,',model_o$distribution,'for other endings\n')
)----------------------")

MODULES[["90_nigeria_aft_duration_by_method_cause.R"]] <- list(language="R", packaged_sha256="f7619dab036cf3841b11675d7bac6e8e815ec37beeae58b2d3ba99ea55131d57", args=character(0), code=r"----------------------(if(!requireNamespace('haven',quietly=TRUE))stop('Install R package haven first.')
# DHS complex survey design for this module.
.dhs_root <- Sys.getenv('NIGERIA_PROJECT_ROOT')
if (!nzchar(.dhs_root)) {
 .dhs_file <- sub('^--file=','',grep('^--file=',commandArgs(FALSE),value=TRUE)[1])
 .dhs_root <- dirname(dirname(normalizePath(.dhs_file)))
}
source(file.path(.dhs_root,'Code','dhs_survey_tools.R'),local=TRUE)
dhs_set_context(country='Nigeria',root=.dhs_root)
#!/usr/bin/env Rscript
# Nigeria DHS 2024 sensitivity analysis: distribute the previously modeled next-year actionable
# original-method endings over the five established program-actionable causes.
# This is a calibrated cause-specific survival decomposition. It does not
# estimate modern-use exits or an intervention effect.
source(file.path(Sys.getenv("NIGERIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE)), 'Code/89_nigeria_aft_duration_by_method.R'), local=TRUE)
causes <- c('Method failure','Wanted more effective method',
  'Changes in menstrual bleeding','Other side effects/health',
  'Access/cost/convenience')
cause_codes <- list(c(1L),c(7L),c(15L),c(4L,5L),c(6L,8L,10L))
names(cause_codes) <- causes

# Each cause is an event in its own time-to-event fit. All other endings and
# survey censoring remain in the risk set until the corresponding time.
# Separate cause hazards are normalized to the master actionable hazard from
# script 166 so the cause-specific projections exactly reconcile to it.
fit_cause <- function(codes){
  e$cause_event <- as.integer(e$discontinued & e$reason_code %in% codes)
  choices <- c('weibull','loglogistic','lognormal','exponential')
  fits <- lapply(choices,function(d)tryCatch(dhs_aft_fit(
    Surv(exposure,cause_event)~method,data=e,weights=wt,dist=d,
    control=survreg.control(maxiter=100)),error=function(x)NULL))
  aic <- vapply(fits,function(f)if(is.null(f)) Inf else dhs_aft_aic(f),0.0)
  ix <- which.min(aic)
  stopifnot(is.finite(aic[ix]))
  list(fit=fits[[ix]],dist=choices[ix],aic=aic[ix],events=sum(e$cause_event))
}
fitted <- lapply(cause_codes,fit_cause)
cause_par <- lapply(methods,function(m){
  d <- data.frame(method=factor(m,levels=methods))
  lapply(fitted,function(f)c(mu=as.numeric(predict(f$fit,newdata=d,type='lp')),
                             scale=f$fit$scale))
})
names(cause_par) <- methods

next12_causes <- function(age,method){
  par <- models[[method]]
  result <- setNames(numeric(length(causes)),causes)
  survival <- 1
  for(t in seq.int(age+1,age+12)){
    ha <- cumhaz(t,par['mu_a'],par['scale_a'],model_a$distribution)-
      cumhaz(t-1,par['mu_a'],par['scale_a'],model_a$distribution)
    ho <- cumhaz(t,par['mu_o'],par['scale_o'],model_o$distribution)-
      cumhaz(t-1,par['mu_o'],par['scale_o'],model_o$distribution)
    raw <- vapply(seq_along(causes),function(j){
      p <- cause_par[[method]][[j]]
      cumhaz(t,p['mu'],p['scale'],fitted[[j]]$dist)-
        cumhaz(t-1,p['mu'],p['scale'],fitted[[j]]$dist)
    },0.0)
    stopifnot(all(raw>=-1e-10))
    raw <- pmax(raw,0)
    shares <- if(sum(raw)>0) raw/sum(raw) else rep(1/length(raw),length(raw))
    total <- ha+ho
    action_month <- survival*(-expm1(-total))*ha/total
    result <- result+action_month*shares
    survival <- survival*exp(-total)
  }
  stopifnot(abs(sum(result)-unname(next12(age,par)[1]))<1e-8)
  result
}

rows <- do.call(rbind,lapply(methods,function(m){
  d <- current[current$method==m,]
  ages <- sort(unique(d$elapsed))
  risks <- sapply(ages,function(a)next12_causes(a,m))
  if(is.null(dim(risks))) risks <- matrix(risks,nrow=length(causes))
  person_risk <- risks[,match(d$elapsed,ages),drop=FALSE]
  risk <- as.numeric(person_risk %*% d$wt/sum(d$wt))
  stock <- out$current_users_2025[out$method==m]
  data.frame(method=m,reason=causes,current_users_2025=stock,
    conditional_next12_risk_pct=100*risk,
    modeled_original_method_endings=stock*risk,
    gross_mcpr_equivalent_pp=100*stock*risk/wra26,
    cause_event_n=vapply(cause_codes,function(z)sum(e$method==m &
      e$discontinued & e$reason_code %in% z),0L))
}))
for(m in methods){
  a <- rows[rows$method==m,]
  b <- out[out$method==m,]
  stopifnot(abs(sum(a$modeled_original_method_endings)-
    b$survival_model_original_method_endings)<1e-5)
}
write.csv(rows,file.path(support,'nigeria_survival_model_duration_by_method_cause.csv'),row.names=FALSE)
write.csv(data.frame(cause=causes,distribution=vapply(fitted,`[[`,'','dist'),
  event_n=vapply(fitted,`[[`,0L,'events'),aic=vapply(fitted,`[[`,0.0,'aic')),
  file.path(support,'nigeria_survival_model_cause_fit.csv'),row.names=FALSE)
print(rows[,c('method','reason','conditional_next12_risk_pct',
  'modeled_original_method_endings','gross_mcpr_equivalent_pp','cause_event_n')],row.names=FALSE)
)----------------------")

MODULES[["91_nigeria_aft_switching_bridge.R"]] <- list(language="R", packaged_sha256="b62124600876443aa0b69a92cb3c407ffeb9a1475da23e0e5a103a8f74afe2de", args=character(0), code=r"----------------------(if(!requireNamespace('haven',quietly=TRUE))stop('Install R package haven first.')
# DHS complex survey design for this module.
.dhs_root <- Sys.getenv('NIGERIA_PROJECT_ROOT')
if (!nzchar(.dhs_root)) {
 .dhs_file <- sub('^--file=','',grep('^--file=',commandArgs(FALSE),value=TRUE)[1])
 .dhs_root <- dirname(dirname(normalizePath(.dhs_file)))
}
source(file.path(.dhs_root,'Code','dhs_survey_tools.R'),local=TRUE)
dhs_set_context(country='Nigeria',root=.dhs_root)
#!/usr/bin/env Rscript
# Nigeria sensitivity analysis: combine AFT next-12-month cause-specific
# original-method ending risks with observed post-ending method pathways.
# The AFT model alone does not predict switching or modern use at year end.
# This hybrid borrows weighted DHS calendar transition fractions conditional on
# original method, actionable cause, and elapsed-duration bin. Sparse cells
# use an explicitly reported fallback. It is descriptive, not causal.
root <- Sys.getenv("NIGERIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
outdir <- file.path(root,'output/Supporting_data')
source(file.path(root,'Code/90_nigeria_aft_duration_by_method_cause.R'),local=TRUE)
landmarks <- readRDS(file.path(root,'Data/Derived/nigeria_historical_duration_landmarks.rds'))
historical <- read.csv(file.path(outdir,'nigeria_duration_aware_current_user_bridge.csv'))
historical_causes <- read.csv(file.path(outdir,'nigeria_duration_aware_current_user_by_cause.csv'))
bins <- c(-1,3,6,12,24,36,48,60,Inf)
bin_labels <- c('0–3','4–6','7–12','13–24','25–36','37–48','49–60','61+')
aft_causes <- rows
aft_methods <- out[out$method %in% methods,]

weighted_fraction <- function(d,flag){
  denom <- sum(d$wt)
  if(nrow(d)==0 || denom<=0)return(NA_real_)
  sum(d$wt*flag)/denom
}
transition <- function(m,c,b){
  use_bins <- if(b=='61+') c('37–48','49–60') else b
  exact <- landmarks[!is.na(landmarks$cause) & landmarks$method==m &
    landmarks$duration_bin %in% use_bins & landmarks$cause==c,]
  level <- 'method × cause × duration'
  d <- exact
  if(nrow(d)<10){
    d <- landmarks[!is.na(landmarks$cause) & landmarks$method==m & landmarks$cause==c,]
    level <- 'method × cause pooled over duration'
  }
  if(nrow(d)<10){
    d <- landmarks[!is.na(landmarks$cause) & landmarks$cause==c,]
    level <- 'cause pooled over methods and duration'
  }
  stopifnot(nrow(d)>0)
  c(direct=weighted_fraction(d,d$direct_switch),
    nonmodern=weighted_fraction(d,!d$modern_at_month12),
    n=nrow(d),level=level)
}

result <- list(); support <- list()
for(m in methods){
  people <- current[current$method==m,]
  people$duration_bin <- cut(people$elapsed,bins,labels=bin_labels)
  stopifnot(!anyNA(people$duration_bin))
  stock <- aft_methods$current_users_2025[aft_methods$method==m]
  all_weight <- sum(people$wt)
  for(c in causes){
    gross <- direct <- nonmodern <- 0
    for(b in bin_labels){
      sub <- people[people$duration_bin==b,]
      if(nrow(sub)==0)next
      ages <- sort(unique(sub$elapsed))
      risk <- vapply(ages,function(a)unname(next12_causes(a,m)[c]),0.0)
      contribution <- stock*sum(sub$wt*risk[match(sub$elapsed,ages)])/all_weight
      tr <- transition(m,c,b)
      gross <- gross+contribution
      direct <- direct+contribution*as.numeric(tr['direct'])
      nonmodern <- nonmodern+contribution*as.numeric(tr['nonmodern'])
      support[[length(support)+1L]] <- data.frame(method=m,reason=c,duration_bin=b,
        projected_endings=contribution,transition_source=unname(tr['level']),
        observed_actionable_endings_n=as.integer(tr['n']),
        observed_direct_switch_fraction=as.numeric(tr['direct']),
        observed_nonmodern_at_year_end_fraction=as.numeric(tr['nonmodern']))
    }
    result[[length(result)+1L]] <- data.frame(method=m,reason=c,
      current_users_2025=stock,model_original_method_endings=gross,
      hybrid_direct_modern_switches=direct,
      hybrid_modern_at_year_end=gross-nonmodern,
      hybrid_nonmodern_at_year_end=nonmodern,
      hybrid_year_end_nonmodern_mcpr_pp=100*nonmodern/wra26,
      gross_method_ending_mcpr_pp=100*gross/wra26)
  }
}
bridge <- do.call(rbind,result)
support <- do.call(rbind,support)
for(m in methods){
  a <- bridge[bridge$method==m,]
  b <- aft_methods[aft_methods$method==m,]
  stopifnot(abs(sum(a$model_original_method_endings)-
    b$survival_model_original_method_endings)<1e-5,
    all(a$hybrid_nonmodern_at_year_end>=0),
    all(a$hybrid_nonmodern_at_year_end<=a$model_original_method_endings))
}
write.csv(bridge,file.path(outdir,'nigeria_aft_switching_by_method_cause.csv'),row.names=FALSE)
write.csv(support,file.path(outdir,'nigeria_aft_switching_transition_support.csv'),row.names=FALSE)
method_summary <- aggregate(bridge[c('model_original_method_endings',
  'hybrid_direct_modern_switches','hybrid_modern_at_year_end',
  'hybrid_nonmodern_at_year_end','hybrid_year_end_nonmodern_mcpr_pp')],
  by=list(method=bridge$method),FUN=sum)
method_summary <- method_summary[match(methods,method_summary$method),]
method_summary$current_users_2025 <- aft_methods$current_users_2025
method_summary$conditional_next12_risk_pct <- aft_methods$survival_model_next12_risk_pct
write.csv(method_summary,file.path(outdir,'nigeria_aft_switching_by_method.csv'),row.names=FALSE)
compare <- data.frame(method=methods,
  historical_original_method_endings=historical$projected_actionable_original_method_endings,
  aft_original_method_endings=method_summary$model_original_method_endings,
  historical_nonmodern_at_year_end=historical$projected_nonmodern_at_month12_after_actionable,
  aft_hybrid_nonmodern_at_year_end=method_summary$hybrid_nonmodern_at_year_end,
  historical_mcpr_pp=historical$descriptive_nonmodern_at_month12_pp,
  aft_hybrid_mcpr_pp=method_summary$hybrid_year_end_nonmodern_mcpr_pp)
write.csv(compare,file.path(outdir,'nigeria_aft_vs_historical_switching_comparison.csv'),row.names=FALSE)
cat('AFT original endings',sum(method_summary$model_original_method_endings),
  '\nHybrid direct switches',sum(method_summary$hybrid_direct_modern_switches),
  '\nHybrid nonmodern at year end',sum(method_summary$hybrid_nonmodern_at_year_end),
  '\nHybrid year-end mCPR pp',sum(method_summary$hybrid_year_end_nonmodern_mcpr_pp),
  '\nSparse/fallback transition cells',sum(support$transition_source!='method × cause × duration'),
  'of',nrow(support),'\n')
print(compare,row.names=FALSE)
)----------------------")

MODULES[["08a_extract_nigeria_wpp_population.py"]] <- list(language="Python", packaged_sha256="967828c11743b6c9718585493a84d17db7387244c127dc1cfaf7bb0b32a76cef", args=character(0), code=r"----------------------("""Extract Nigeria women aged 15–49 from the UN WPP 2024 medium variant.

Input is the official UN female single-age workbook already in the user's data
folder. The workbook reports thousands at 1 July, so sum ages 15–49 and
multiply by 1,000. Preserve fractional people for exact reproducibility;
tables round to whole women.
"""
import csv
import os
from pathlib import Path
import openpyxl

source = Path(os.environ['NIGERIA_PROJECT_ROOT']) / 'Data/References/WPP2024_POP_F01_3_POPULATION_SINGLE_AGE_FEMALE.xlsx'
out = Path(os.environ['NIGERIA_PROJECT_ROOT']) / 'output/Supporting_data/nigeria_wpp2024_wra_2024_2026.csv'
sheet = openpyxl.load_workbook(source, read_only=True, data_only=True)['Medium variant']
header = next(sheet.iter_rows(min_row=17,max_row=17,values_only=True))
assert header[5]=='ISO3 Alpha-code' and header[10]=='Year' and header[26]==15 and header[60]==49
rows=[]
for row in sheet.iter_rows(min_row=18, values_only=True):
    if row[5]=='NGA' and row[10] in (2024,2025,2026):
        rows.append({'year':row[10],'women_15_49':sum(float(row[11+a]) for a in range(15,50))*1000,
                     'source':'UN World Population Prospects 2024, female single ages, medium variant, 1 July'})
assert len(rows)==3
with out.open('w',newline='') as f:
    writer=csv.DictWriter(f,fieldnames=rows[0].keys());writer.writeheader();writer.writerows(rows)
print(rows)
)----------------------")

MODULES[["16_nigeria_all_reason_current_user_bridge.py"]] <- list(language="Python", packaged_sha256="b376cab32dadfa5f9ddf981a16a99f0ca252e2650a272d20b26cc18b20caefd3", args=character(0), code=r"----------------------(#!/usr/bin/env python3
"""Build the Ethiopia-style all-reason current-user planning bridge.

This is an illustration, not a next-year forecast: first-year probabilities
after method initiation are applied to the estimated 2025 current-user stock.
Method endings include switching and do not equal losses from modern use.
"""
import csv
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SUP = ROOT / "output/Supporting_data"


def read(name):
    with (SUP / name).open(newline="") as stream:
        return list(csv.DictReader(stream))


def write(name, rows, fields):
    with (SUP / name).open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


times = read("nigeria_reversible_planning_all_reason_timepoints.csv")
reasons = read("nigeria_reversible_planning_all_reason_reason_mix.csv")
users = read("nigeria_current_users_by_method_and_actionable_projection.csv")
methods = ["Injectables", "Implants", "Pill", "IUD", "Other modern"]
cause_names = [r["reason"] for r in reasons if r["scope"] == "National"]
summary = []
causes = []
for method in methods:
    user = next(r for r in users if r["method"] == method)
    life = next(r for r in times if r["scope"] == "National: " + method and r["month"] == "12")
    count = float(user["current_users_2025"])
    total = float(life["all_reason_pct"])
    summary.append({
        "method": method,
        "current_users_2025": count,
        "all_reason_first_year_risk_pct": total,
        "illustrative_original_method_endings": count * total / 100,
    })
    for reason in cause_names:
        entry = next(r for r in reasons if r["scope"] == "National: " + method and r["reason"] == reason)
        probability = float(entry["cause_specific_12_month_pct"])
        causes.append({
            "method": method,
            "reason": reason,
            "current_users_2025": count,
            "cause_specific_first_year_risk_pct": probability,
            "illustrative_original_method_endings": count * probability / 100,
        })
    cause_total = sum(float(r["illustrative_original_method_endings"]) for r in causes if r["method"] == method)
    assert abs(cause_total - summary[-1]["illustrative_original_method_endings"]) < 1e-6

write("nigeria_current_users_all_reason_projection.csv", summary, list(summary[0]))
write("nigeria_current_users_all_reason_by_cause.csv", causes, list(causes[0]))
print("All-reason illustrative original-method endings:", round(sum(r["illustrative_original_method_endings"] for r in summary)))
)----------------------")

MODULES[["95_build_duration_planning_data.py"]] <- list(language="Python", packaged_sha256="0739af4266246c1aaeef664e1fab5786c27657f767e08a1b87ed3e76f27577a7", args=character(0), code=r"----------------------(#!/usr/bin/env python3
"""Build Nigeria counterparts to Ethiopia's historical/AFT planning tables."""
import csv
import json
from decimal import Decimal, ROUND_HALF_UP
import os
from pathlib import Path

root = Path(os.environ['NIGERIA_PROJECT_ROOT'])
support = root / 'output/Supporting_data'
out = root / 'output/nigeria_duration_planning_tables.json'

def read(name):
    with (support / name).open(newline='') as f:
        return list(csv.DictReader(f))

def f(row, key): return float(row[key])
def integer(x):
    return f"{int(Decimal(str(x)).quantize(Decimal('1'), rounding=ROUND_HALF_UP)):,}"
def percent(x, places=1): return f'{x:.{places}f}%'
def pp(x): return f'+{x:.2f} pp'

stocks = {r['method']: r for r in read('nigeria_current_users_by_method_and_actionable_projection.csv')}
scenarios = read('nigeria_2026_mcpr_scenarios.csv')
historical = {r['method']: r for r in read('nigeria_duration_aware_current_user_bridge.csv')}
historical_cause = {(r['method'], r['reason']): r for r in read('nigeria_duration_aware_current_user_by_cause.csv')}
aft = {r['method']: r for r in read('nigeria_aft_switching_by_method.csv')}
aft_cause = {(r['method'], r['reason']): r for r in read('nigeria_aft_switching_by_method_cause.csv')}
methods = ['Injectables', 'Implants', 'Pill', 'IUD', 'Other modern']
causes = ['Method failure', 'Wanted more effective method', 'Changes in menstrual bleeding',
          'Other side effects/health', 'Access/cost/convenience']
wra = f(scenarios[0], 'wra_2026')
current_total = sum(f(stocks[m], 'current_users_2025') for m in methods + ['EC'])
no_ec_total = sum(f(stocks[m], 'current_users_2025') for m in methods)

def build(label, method_data, cause_data, risk_col, net_col, cause_net_col,
          gross_col, historical_mode):
    net = {m: f(method_data[m], net_col) for m in methods}
    gross = {m: f(method_data[m], gross_col) for m in methods}
    total_net = sum(net.values())
    total_gross = sum(gross.values())
    assert abs(total_net - sum(f(cause_data[m, c], cause_net_col)
                               for m in methods for c in causes)) < 1e-4
    cause_total = {c: sum(f(cause_data[m, c], cause_net_col) for m in methods)
                   for c in causes}
    impact = 100 * total_net / wra
    prefix = 'Historical duration-aware' if historical_mode else 'AFT + observed pathways'
    method_table = [[
        'Method', 'Current mix (%)', 'Projected 2025 users',
        'Actionable ending risk (%)', 'Nonmodern at year end']]
    for m in methods:
        method_table.append([m, f(stocks[m], 'share_current_modern_pct'),
                             f(stocks[m], 'current_users_2025'),
                             f(method_data[m], risk_col), net[m]])
    method_table.append(['EC', f(stocks['EC'], 'share_current_modern_pct'),
                         f(stocks['EC'], 'current_users_2025'), 'Not applied', 'Not estimated'])
    method_table.append(['Current-user mix total, excluding EC',
                         sum(f(stocks[m], 'share_current_modern_pct') for m in methods),
                         no_ec_total, 100 * total_gross / no_ec_total, total_net])

    cause_table = [[
        'Method', 'Projected 2025 users', 'Method failure', 'Wanted more effective',
        'Bleeding changes', 'Other side effects / health',
        'Access / cost / convenience', 'Nonmodern at year end']]
    for m in methods:
        cause_table.append([m, f(stocks[m], 'current_users_2025'),
                            *(f(cause_data[m, c], cause_net_col) for c in causes), net[m]])
    cause_table.append(['All methods, excluding EC', no_ec_total,
                        *(cause_total[c] for c in causes), total_net])

    baseline_table = [['Scenario', '2024 DHS mCPR', 'Projected 2025 mCPR',
                       'Illustrative 2026 mCPR']]
    for s in scenarios:
        baseline_table.append([s['scenario'], f(s, 'mcpr_2024_pct'),
                               f(s, 'mcpr_2025_pct'), f(s, 'mcpr_2026_pct')])
    scenario_table = [['Different mCPR growth scenarios', '2026 users, usual endings',
                       '2026 mCPR', '2026 users if retained', 'Revised 2026 mCPR',
                       'Difference']]
    method_scenarios = []
    for s in scenarios:
        usual = f(s, 'usual_users_2026')
        retained = usual + total_net
        scenario_table.append([s['scenario'], usual, f(s, 'mcpr_2026_pct'),
                               retained, 100 * retained / wra, impact])
        t = [['Method', 'Projected 2025 users', '2026 users', 'Year-end loss averted',
              '2026 if averted', '2026 mCPR', 'mCPR if averted']]
        for m in methods + ['EC']:
            usual_m = usual * f(stocks[m], 'current_users_2025') / current_total
            add = net.get(m, 0)
            t.append([m, f(stocks[m], 'current_users_2025'), usual_m,
                      add if m != 'EC' else '—', usual_m + add,
                      100 * usual_m / wra, 100 * (usual_m + add) / wra])
        t.append(['All modern', current_total, usual, total_net,
                  retained, f(s, 'mcpr_2026_pct'), 100 * retained / wra])
        method_scenarios.append(t)
    pp_table = [['Method / measure', 'Method failure', 'Want more effective',
                 'Bleeding changes', 'Other side effects / health',
                 'Access / cost / convenience', 'All actionable causes']]
    for m in methods:
        pp_table.append([m, *(f(cause_data[m, c], cause_net_col) for c in causes),
                         net[m]])
    pp_table.append(['Estimated nonmodern at year end',
                     *(cause_total[c] for c in causes), total_net])
    pp_table.append(['2026 women aged 15–49', *(wra for _ in causes), wra])
    pp_table.append(['Maximum mCPR equivalent',
                     *(100 * cause_total[c] / wra for c in causes), impact])

    if historical_mode:
        prob = ('Weighted 12-month actionable ending probability from historical '
                'method-duration calendar landmarks. The 61+ month current-user '
                'band uses observed 37–60-month risks. Year-end nonmodern counts '
                'include observed switching and restarting pathways.')
        caveat = ('Historical, descriptive projection; results assume past '
                  'method-duration and post-ending patterns apply to projected 2025 users.')
    else:
        prob = ('Two survey-weighted, method-only AFT models estimate actionable '
                'and other-ending hazards. Cause-specific AFT patterns split the '
                'actionable risk; observed post-ending pathways determine year-end '
                'nonmodern use.')
        caveat = ('Exploratory hybrid; 73 of 200 method × cause × duration transition '
                  'cells needed pooled fallback estimates. IUD cause fits have as '
                  'few as one observed event. No uncertainty interval is available.')

    raw = [method_table, cause_table, baseline_table, scenario_table,
           *method_scenarios, pp_table]
    kinds = ['method', 'cause', 'baseline', 'scenario',
             'method_scenario', 'method_scenario', 'method_scenario', 'cause_pp']
    titles = [f'{prefix}: actionable endings', f'{prefix}: year-end loss by cause',
              f'{prefix}: common 2026 mCPR baselines',
              f'{prefix}: mCPR if year-end loss avoided',
              f'{prefix}: no-growth mCPR by method',
              f'{prefix}: DHS-growth mCPR by method',
              f'{prefix}: FP2030-growth mCPR by method',
              f'{prefix}: mCPR equivalent by actionable cause']
    subtitle = [
        'Projected 2025 current users; next 12 months conditional on time already used',
        f'Projected 2025 current users; {integer(total_net)} nonmodern at year end',
        '2024 DHS baseline; projected 2025 and illustrative 2026 mCPR scenarios',
        f'{integer(total_net)} year-end nonmodern users after actionable endings',
        'No further mCPR growth in 2026',
        'DHS-anchored +0.4 percentage points per year',
        'FP2030 2025 modeled level +0.4 percentage points in 2026',
        'Year-end nonmodern users after actionable original-method endings']
    notes = [
        prob + ' ' + caveat + ' EC has no continuing-use risk.',
        ('Each cause count = projected 2025 users × the method- and cause-specific '
         'probability of an actionable ending followed by no modern use at year end. ' + caveat),
        ('The three mCPR baselines use Nigeria DHS 2024 all-women mCPR, Nigeria '
         '2025/2026 women aged 15–49 projections, and stated annual changes. '
         'These are planning scenarios, not observed 2026 outcomes.'),
        (f'{integer(total_net)} ÷ {integer(wra)} projected 2026 women aged 15–49 '
         f'= {pp(impact)}. Counts are calculated before rounding. ' + caveat),
        *[(f'Each mCPR contribution = method users ÷ {integer(wra)} projected 2026 '
           'women aged 15–49. Year-end loss averted uses ' + prob + ' ' + caveat)
          for _ in range(3)],
        (f'Each cause mCPR equivalent = year-end nonmodern users ÷ {integer(wra)} '
         'projected 2026 women aged 15–49. ' + caveat),
    ]

    def display(kind, table):
        result = []
        for i, row in enumerate(table):
            if i == 0:
                result.append([str(x) for x in row]); continue
            formatted = []
            for j, val in enumerate(row):
                if isinstance(val, str): formatted.append(val)
                elif kind == 'method' and j in (1, 3): formatted.append(f'{val:.1f}')
                elif kind == 'baseline' and j >= 1: formatted.append(percent(val, 2))
                elif kind == 'scenario' and j in (2, 4): formatted.append(percent(val, 2))
                elif kind == 'scenario' and j == 5: formatted.append(pp(val))
                elif kind == 'method_scenario' and j in (5, 6): formatted.append(percent(val, 2))
                elif kind == 'cause_pp' and i == len(table)-1 and j >= 1:
                    formatted.append(f'{val:.2f} pp')
                else: formatted.append(integer(val))
            result.append(formatted)
        return result
    slides = [dict(title=titles[i], subtitle=subtitle[i], kind=kinds[i],
                   table=display(kinds[i], raw[i]), note=notes[i]) for i in range(8)]
    return dict(label=label, total_gross=total_gross, total_net=total_net,
                mcpr_equivalent_pp=impact, slides=slides)

blocks = [build('historical', historical, historical_cause,
                'actionable_ending_risk_next12_pct',
                'projected_nonmodern_at_month12_after_actionable',
                'projected_nonmodern_at_month12',
                'projected_actionable_original_method_endings', True),
          build('aft', aft, aft_cause, 'conditional_next12_risk_pct',
                'hybrid_nonmodern_at_year_end', 'hybrid_nonmodern_at_year_end',
                'model_original_method_endings', False)]
out.write_text(json.dumps(dict(country='Nigeria', wra_2026=wra,
                               current_users_2025=current_total,
                               blocks=blocks), indent=2))
print(out)
for block in blocks:
    print(block['label'], 'gross', integer(block['total_gross']),
          'year-end nonmodern', integer(block['total_net']),
          'mCPR equivalent', pp(block['mcpr_equivalent_pp']))

# Reconcile final presentation labels, without altering arithmetic.

labels = {'DHS anchored +0.4 pp/year': 'Track20 growth (+0.4 pp)',
          'FP2030 2025 level +0.4 pp': 'UN growth (about +0.5 pp)',
          'Actionable ending risk (%)': 'Potentially actionable discontinuation (%)'}
def final_labels(value):
    if isinstance(value,str): return labels.get(value,value)
    if isinstance(value,list): return [final_labels(x) for x in value]
    if isinstance(value,dict): return {k:final_labels(v) for k,v in value.items()}
    return value
out.write_text(json.dumps(final_labels(json.loads(out.read_text())),indent=2))
)----------------------")

MODULES[["202_nigeria_survey_coefficients.R"]] <- list(language="R", packaged_sha256="3f36d2b236294a5d5edb12feee092a5536d4510b4a4681d94fea956e1a2b3b47", args=character(0), code=r"----------------------(if(!requireNamespace('haven',quietly=TRUE))stop('Install R package haven first.')
# DHS complex survey design for this module.
.dhs_root <- Sys.getenv('NIGERIA_PROJECT_ROOT')
if (!nzchar(.dhs_root)) {
 .dhs_file <- sub('^--file=','',grep('^--file=',commandArgs(FALSE),value=TRUE)[1])
 .dhs_root <- dirname(dirname(normalizePath(.dhs_file)))
}
source(file.path(.dhs_root,'Code','dhs_survey_tools.R'),local=TRUE)
dhs_set_context(country='Nigeria',root=.dhs_root)
suppressPackageStartupMessages(library(nnet))
root<-Sys.getenv("NIGERIA_PROJECT_ROOT");out<-file.path(root,"output/Supporting_data")
p<-readRDS(file.path(root,'Data/Derived/nigeria_2024_person_month.rds'))
ir<-readRDS(file.path(root,'Data/raw_dhs_ir/NG2024DHS__NGIR8BDT__IR_raw.rds'))
f<-unique(data.frame(cluster=as.numeric(ir$v021),stratum=as.numeric(ir$v022)))
g<-split(seq_len(nrow(f)),f$stratum);df<-nrow(f)-length(g)
rows<-list()
for(k in 1:2){
 m<-readRDS(file.path(root,paste0('Data/Derived/nigeria_actionable_zone_model_',k,'.rds')))
 X<-model.matrix(delete.response(terms(m)),p,contrasts.arg=m$contrasts)
 pr<-predict(m,newdata=p,type='probs');lev<-m$lev[-1]
 score<-do.call(cbind,lapply(lev,function(y)X*(p$wt*(as.numeric(p$outcome==y)-pr[,y]))))
 expected<-unlist(lapply(lev,function(y)paste(y,colnames(X),sep=':')))
 stopifnot(identical(colnames(m$Hessian),expected))
 s<-matrix(0,nrow(f),ncol(score));a<-rowsum(score,p$cluster);s[match(rownames(a),f$cluster),]<-a
 meat<-dhs_psu_variance(s,f)
 bread<-MASS::ginv(m$Hessian);v<-bread%*%meat%*%bread;se<-sqrt(pmax(diag(v),0));be<-as.vector(t(coef(m)));crit<-qt(.975,df)
 rows[[k]]<-data.frame(model=if(k==1)'Method + duration'else'Full',outcome=rep(lev,each=ncol(X)),covariate=rep(colnames(X),length(lev)),odds_ratio=exp(be),ci_low=exp(be-crit*se),ci_high=exp(be+crit*se),p_value=2*pt(-abs(be/se),df),survey_se=se,design_df=df)
 saveRDS(v,file.path(out,paste0('model_',k,'_survey_vcov.rds')))
}
write.csv(do.call(rbind,rows),file.path(out,'nigeria_actionable_zone_model_odds_ratios.csv'),row.names=FALSE)
cat('Full-frame cluster/strata sandwich:',nrow(f),'PSUs;',length(g),'strata;',df,'degrees of freedom\n')
)----------------------")

MODULES[["203_nigeria_planning_survey_ci.R"]] <- list(language="R", packaged_sha256="1418d5c97dbd818cf9c967e1438b1a9be7839f4c0ee8c2330d1d911a395bf978", args=character(0), code=r"----------------------(if(!requireNamespace('haven',quietly=TRUE))stop('Install R package haven first.')
# DHS complex survey design for this module.
.dhs_root <- Sys.getenv('NIGERIA_PROJECT_ROOT')
if (!nzchar(.dhs_root)) {
 .dhs_file <- sub('^--file=','',grep('^--file=',commandArgs(FALSE),value=TRUE)[1])
 .dhs_root <- dirname(dirname(normalizePath(.dhs_file)))
}
source(file.path(.dhs_root,'Code','dhs_survey_tools.R'),local=TRUE)
dhs_set_context(country='Nigeria',root=.dhs_root)
#!/usr/bin/env Rscript
# Survey-design inference for Nigeria planning scenarios. All inputs are parameters.
# Fixed population and growth assumptions; uncertainty includes IR sampling,
# current-use composition, empirical risks, fitted AFT parameters and pathways.
# AFT intervals condition on the previously selected distribution families.
root<-normalizePath(Sys.getenv('NIGERIA_PROJECT_ROOT'));out<-file.path(root,'output/survey_planning');dir.create(out,recursive=TRUE,showWarnings=FALSE)
B<-as.integer(Sys.getenv('NIGERIA_PLANNING_BOOTSTRAP_REPS','500'));cores<-4L
suppressPackageStartupMessages(library(survival))
ir<-readRDS(file.path(root,'Data/raw_dhs_ir/NG2024DHS__NGIR8BDT__IR_raw.rds'))
e<-readRDS(file.path(root,'Data/Derived/nigeria_2024_modern_episodes.rds'))
e<-e[!e$method_code%in%c(6L,7L),]
cal<-readRDS(file.path(root,'Data/Derived/nigeria_2024_calendar_events.rds'))
sup<-file.path(root,'output/Supporting_data')
script_file<-sub('^--file=','',grep('^--file=',commandArgs(FALSE),value=TRUE)[1])
signature<-unname(tools::md5sum(c(script_file,file.path(root,'Data/raw_dhs_ir/NG2024DHS__NGIR8BDT__IR_raw.rds'),file.path(root,'Data/Derived/nigeria_2024_modern_episodes.rds'),file.path(root,'Data/Derived/nigeria_2024_calendar_events.rds'),file.path(sup,'nigeria_wpp2024_wra_2024_2026.csv'),file.path(sup,'nigeria_survival_model_duration_fit.csv'),file.path(sup,'nigeria_survival_model_cause_fit.csv'))))
cache_signature<-file.path(out,'cache_signature.rds')
if(file.exists(cache_signature)){if(!identical(signature,readRDS(cache_signature)))stop('Inputs or code changed. Use a fresh output directory for bootstrap results.')}else{
 if(length(list.files(file.path(out,'replicates'))))stop('Unversioned bootstrap cache: use a fresh output directory.')
 saveRDS(signature,cache_signature)
}

pop<-read.csv(file.path(sup,'nigeria_wpp2024_wra_2024_2026.csv'))
w25<-pop$women_15_49[pop$year==2025];w26<-pop$women_15_49[pop$year==2026]
w24<-pop$women_15_49[pop$year==2024]
methods<-c('Injectables','Implants','Pill','IUD','Other modern')
causes<-c('Method failure','Wanted more effective method','Changes in menstrual bleeding','Other side effects/health','Access/cost/convenience')
codes<-list(1L,7L,15L,c(4L,5L),c(6L,8L,10L)); action<-unlist(codes)
modern<-c(1L,2L,3L,5L,6L,7L,11L,13L,14L,15L,17L,18L,19L,20L);modern<-setdiff(modern,c(6L,7L))
endpoint_modern<-c(modern,6L,7L,16L)
method_group<-function(x)ifelse(x==3,'Injectables',ifelse(x==11,'Implants',ifelse(x==1,'Pill',ifelse(x==2,'IUD','Other modern'))))
cause_group<-function(x){z<-rep(NA_integer_,length(x));for(j in 1:5)z[x %in% codes[[j]]]<-j;z}
wt<-as.numeric(ir$v005)/1e6;psu<-as.numeric(ir$v021);stratum<-as.numeric(ir$v022)
frame<-unique(data.frame(psu,stratum)); stopifnot(!anyDuplicated(frame$psu))
strata<-split(seq_len(nrow(frame)),frame$stratum);stopifnot(all(lengths(strata)>1))
psu_index<-match(psu,frame$psu)
u<-as.numeric(ir$v313)==3;umethod<-method_group(as.numeric(ir$v312));umethod[as.numeric(ir$v312)==16]<-'EC'
umethod[as.numeric(ir$v312)%in%c(6L,7L)]<-'Permanent methods'
uindex<-which(u & as.numeric(ir$v312) %in% modern)
current<-data.frame(woman=uindex,method=umethod[uindex],elapsed=dhs_current_duration(ir,uindex),wt=wt[uindex])
stopifnot(all(is.finite(current$elapsed)),all(current$elapsed>=0))
bins<-c(-1,3,6,12,24,36,48,60,Inf);blabel<-c('0–3','4–6','7–12','13–24','25–36','37–48','49–60','61+')
current$bin<-as.integer(cut(current$elapsed,bins))
# Reconstruct historical landmarks with an explicit year-end modern-use definition.
bywoman<-split(seq_len(nrow(cal)),cal$woman_row)
spells<-cal[cal$method_code %in% modern & cal$start>cal$calendar_start,]
records<-vector('list',nrow(spells))
for(i in seq_len(nrow(spells))){a<-spells[i,];last<-min(a$end,a$interview-15L);if(last<a$start)next
 t<-seq.int(a$start,last);future<-t+12L;timeline<-cal[bywoman[[as.character(a$woman_row)]],]
 code<-timeline$method_code[findInterval(future,timeline$start)]
 ended<-a$end<future & a$reason_code %in% action
 records[[i]]<-data.frame(woman=a$woman_row,episode=i,method=method_group(a$method_code),elapsed=t-a$start,wt=a$wt,
 cause=ifelse(ended,cause_group(a$reason_code),NA_integer_),net=ended & !code %in% endpoint_modern,
 net_legacy=ended & !code %in% modern, direct=ended & timeline$method_code[findInterval(a$end+1L,timeline$start)] %in% endpoint_modern)
}
land<-do.call(rbind,records);land$bin<-as.integer(cut(land$elapsed,bins))
# 61+ months has no direct complete-follow-up support; preserve documented proxy.
ci_index<-lapply(methods,function(m)which(current$method==m));names(ci_index)<-methods
land_index<-lapply(methods,function(m)lapply(1:8,function(b)which(land$method==m & land$bin %in% if(b==8)c(6,7)else b)));names(land_index)<-methods
# Fit data and fixed selected families (model-selection uncertainty is not included).
af<-e[e$entry==0 & e$exposure>0,];af$method<-factor(af$method_group,levels=methods)
af$action_event<-as.integer(af$discontinued & af$reason_code %in% action)
af$other_event<-as.integer(af$discontinued & !af$reason_code %in% action)
for(j in 1:5)af[[paste0('cause',j)]]<-as.integer(af$discontinued & af$reason_code %in% codes[[j]])
fam<-read.csv(file.path(sup,'nigeria_survival_model_duration_fit.csv'));cfam<-read.csv(file.path(sup,'nigeria_survival_model_cause_fit.csv'))
dists<-c(fam$distribution[fam$selected_actionable],fam$distribution[fam$selected_other],cfam$distribution[match(causes,cfam$cause)])
events<-c('action_event','other_event',paste0('cause',1:5));stopifnot(length(dists)==7,!anyNA(dists))
maxage<-max(current$elapsed)+12L;time<-0:maxage
cumhaz<-function(t,mu,sc,dist){
 if(dist=='weibull')return((t/exp(mu))^(1/sc))
 if(dist=='exponential')return(t/exp(mu))
 if(dist=='loglogistic')return(log1p(exp((log(t)-mu)/sc)))
 if(dist=='lognormal')return(-pnorm((log(t)-mu)/sc,lower.tail=FALSE,log.p=TRUE))
 stop('Unknown family')}
transition_index<-list();support<-list()
for(m in methods)for(b in 1:8)for(j in 1:5){
 z<-which(land$method==m & land$bin %in% (if(b==8)c(6,7)else b) & land$cause==j)
 # Use unique episodes, not repeated landmarks, to assess support.
 n<-length(unique(land$episode[z]));level<-'method × cause × duration'
 if(n<10){z<-which(land$method==m & land$cause==j);n<-length(unique(land$episode[z]));level<-'method × cause'}
 if(n<10){z<-which(land$cause==j);n<-length(unique(land$episode[z]));level<-'cause pooled over methods'}
 stopifnot(n>0);key<-paste(m,b,j,sep='|');transition_index[[key]]<-z
 support[[key]]<-data.frame(method=m,duration_bin=blabel[b],cause=causes[j],unique_episodes=n,unique_women=length(unique(land$woman[z])),landmarks=length(z),pooling=level)
}
write.csv(do.call(rbind,support),file.path(out,'switching_support.csv'),row.names=FALSE)
measure<-function(mult,replicate=0L){
 old_dhs<-options(dhs.replication=replicate>0L);on.exit(options(old_dhs),add=TRUE)
 iw<-wt*mult[psu_index];ew<-e$wt*mult[psu_index[e$woman_row]];lw<-land$wt*mult[psu_index[land$woman]];cw<-current$wt*mult[psu_index[current$woman]]
 mcpr<-100*sum(iw[u])/sum(iw);mix<-vapply(c(methods,'EC','Permanent methods'),function(m)sum(iw[u & umethod==m])/sum(iw[u]),0.0)
 stock<-w25*(mcpr+.4)/100*mix
 # Main gross estimates, year-end switching sensitivities, and direct-switch diagnostics.
 result<-array(0,c(8,5,5),dimnames=list(c('First-year gross','Historical gross','AFT gross','Historical switching','AFT switching','First-year direct switches','Historical direct switches','AFT direct switches'),methods,causes))
 risk<-result
 for(m in methods){d<-which(e$method_group==m);surv<-1;v<-numeric(5)
  for(t in 1:12){at<-d[e$entry[d]<t & e$exposure[d]>=t];den<-sum(ew[at]);if(den<=0)next
   end<-at[e$discontinued[at] & e$exposure[at]==t];h<-vapply(codes,function(cc)sum(ew[end[e$reason_code[end] %in% cc]])/den,0.0)
   v<-v+surv*h;surv<-surv*(1-sum(ew[end])/den)}
  risk[1,m,]<-v
  ends<-d[e$discontinued[d] & e$exposure[d]<=12 & e$reason_code[d] %in% action]
  raw<-vapply(1:5,function(j){ii<-ends[e$reason_code[ends] %in% codes[[j]]];den<-sum(ew[ii]);if(den>0)v[j]*sum(ew[ii][e$next_code[ii] %in% endpoint_modern])/den else 0},0)
  risk[6,m,]<-raw
  ix<-ci_index[[m]];cwtotal<-sum(cw[ix]);for(b in 1:8){share<-sum(cw[ix[current$bin[ix]==b]])/cwtotal;if(share==0)next
   z<-land_index[[m]][[b]];den<-sum(lw[z]);if(den<=0)stop('Empty landmark cell')
   for(j in 1:5){risk[2,m,j]<-risk[2,m,j]+share*sum(lw[z][!is.na(land$cause[z]) & land$cause[z]==j])/den
    risk[4,m,j]<-risk[4,m,j]+share*sum(lw[z][!is.na(land$cause[z]) & land$cause[z]==j & land$net[z]])/den
    risk[7,m,j]<-risk[7,m,j]+share*sum(lw[z][!is.na(land$cause[z]) & land$cause[z]==j & land$direct[z]])/den}}
 }
 aw<-af$wt*mult[psu_index[af$woman_row]]
 fits<-lapply(seq_along(events),function(j){ad<-af[aw>0,];ad$fw<-aw[aw>0];active<-methods[vapply(methods,function(m)sum(ad[[events[j]]][ad$method==m]),0)>0];ad<-ad[ad$method %in% active,];ad$method<-droplevels(ad$method);fit<-suppressWarnings(dhs_aft_fit(as.formula(paste0('Surv(exposure,',events[j],')~method')),data=ad,weights=fw,dist=dists[j],control=survreg.control(maxiter=500)));if(fit$iter>=500||any(!is.finite(coef(fit))))stop(paste('AFT convergence failure',events[j],dists[j]));attr(fit,'active_methods')<-active;fit})
 for(m in methods){nd<-data.frame(method=factor(m,levels=methods));hh<-sapply(seq_along(fits),function(j){f<-fits[[j]];if(!m %in% attr(f,'active_methods'))return(rep(0,length(time)-1));mu<-as.numeric(predict(f,newdata=nd,type='lp'));diff(cumhaz(time,mu,f$scale,dists[j]))})
  ix<-ci_index[[m]];den<-sum(cw[ix]);for(age in unique(current$elapsed[ix])){z<-ix[current$elapsed[ix]==age];share<-sum(cw[z])/den;if(share==0)next
   h<-hh[age+1:12,,drop=FALSE];total<-h[,1]+h[,2];s<-c(1,exp(-cumsum(total)))[1:12];monthly<-s*(-expm1(-total))*ifelse(total>0,h[,1]/total,0)
   hcause<-pmax(h[,3:7,drop=FALSE],0);cs<-hcause/pmax(rowSums(hcause),1e-300);if(any(!is.finite(cs)))stop('Invalid cause split')
   v<-colSums(monthly*cs);risk[3,m,]<-risk[3,m,]+share*v
   b<-as.integer(cut(age,bins));for(j in 1:5){q<-transition_index[[paste(m,b,j,sep='|')]];fraction<-sum(lw[q]*land$net[q])/sum(lw[q]);risk[5,m,j]<-risk[5,m,j]+share*v[j]*fraction;risk[8,m,j]<-risk[8,m,j]+share*v[j]*sum(lw[q]*land$direct[q])/sum(lw[q])}}
 }
 for(m in methods)result[,m,]<-risk[,m,]*stock[m]
 stopifnot(all(is.finite(result)),all(result>=0),all(apply(risk,c(1,2),sum)<=1+1e-8))
 list(counts=result,risk=risk,mcpr=mcpr,mix=mix,stock=stock,users2024=w24*mcpr/100*mix)
}
point<-measure(rep(1,nrow(frame)));saveRDS(point,file.path(out,'planning_point.rds'))
# Current national report tables use the full build entry point.
# Permanent users have no modeled stopping probability in this earlier diagnostic.
cat('Point totals:',apply(point$counts,1,sum),'\n');flush.console()
checkpoint<-file.path(out,'replicates');dir.create(checkpoint,showWarnings=FALSE)
one<-function(b){dest<-file.path(checkpoint,sprintf('rep_%04d.rds',b));if(file.exists(dest))return(readRDS(dest));set.seed(20261105L+b)
 mult<-numeric(nrow(frame));for(ids in strata){n<-length(ids);mult[ids]<-n/(n-1)*tabulate(sample.int(n,n-1,replace=TRUE),nbins=n)}
 v<-tryCatch(measure(mult,b),error=function(e)list(error=conditionMessage(e)));saveRDS(v,dest);v}
if(B>0){draws<-parallel::mclapply(seq_len(B),one,mc.cores=cores,mc.preschedule=FALSE);valid<-!vapply(draws,function(x)!is.null(x$error),FALSE)
 cat('Valid',sum(valid),'of',B,'\n');stopifnot(mean(valid)>=.95);saveRDS(draws,file.path(out,'planning_replicates.rds'))}
saveRDS(list(wra2024=w24,wra2025=w25,wra2026=w26,psus=nrow(frame),strata=length(strata),replicates=B,methods=methods,causes=causes,definitions=c('Gross: every actionable original-method ending treated as year-end loss','Switching sensitivity: EC included in modern use at year end; support assessed on unique episodes','AFT uncertainty conditional on selected distribution families','Population and growth scenarios fixed')),file.path(out,'planning_metadata.rds'))
)----------------------")

MODULES[["204_summarize_planning.R"]] <- list(language="R", packaged_sha256="aba890f805ef4078e2c1dcfaee9bbb34a60f6a1a4b02dc8877f8cff3c579d479", args=character(0), code=r"----------------------(if(!requireNamespace('haven',quietly=TRUE))stop('Install R package haven first.')
# DHS complex survey design for this module.
.dhs_root <- Sys.getenv('NIGERIA_PROJECT_ROOT')
if (!nzchar(.dhs_root)) {
 .dhs_file <- sub('^--file=','',grep('^--file=',commandArgs(FALSE),value=TRUE)[1])
 .dhs_root <- dirname(dirname(normalizePath(.dhs_file)))
}
source(file.path(.dhs_root,'Code','dhs_survey_tools.R'),local=TRUE)
dhs_set_context(country='Nigeria',root=.dhs_root)
o<-file.path(Sys.getenv("NIGERIA_PROJECT_ROOT"),"output/survey_planning");p<-readRDS(file.path(o,'planning_point.rds'));d<-readRDS(file.path(o,'planning_replicates.rds'));meta<-readRDS(file.path(o,'planning_metadata.rds'))
metrics<-function(x){
 x$counts<-abind::abind(x$counts,x$counts[1,,,drop=FALSE]-x$counts[6,,,drop=FALSE],x$counts[2,,,drop=FALSE]-x$counts[4,,,drop=FALSE],x$counts[3,,,drop=FALSE]-x$counts[5,,,drop=FALSE],along=1)
 y<-c(stock_no_ec=sum(x$stock[meta$methods]),mcpr2024=x$mcpr,mcpr2025=x$mcpr+.4,users2025=sum(x$stock),users2024=sum(x$users2024))
 for(m in c(meta$methods,'EC'))y[paste('stock',m,sep='|')]<-x$stock[m]
 for(i in 1:11)for(m in c(meta$methods,'Total'))for(c in c(meta$causes,'Total')){
  mi<-if(m=='Total')1:5 else match(m,meta$methods);ci<-if(c=='Total')1:5 else match(c,meta$causes)
  v<-sum(x$counts[i,mi,ci]);s<-if(m=='Total')sum(x$stock[meta$methods])else x$stock[m]
  key<-paste(i,m,c,sep='|');y[paste0('count|',key)]<-v;y[paste0('pp|',key)]<-100*v/meta$wra2026;y[paste0('risk|',key)]<-100*v/s
 }
 base<-c(x$mcpr+.4,x$mcpr+.8,14.0)
 for(j in 1:3){y[paste0('base|',j)]<-base[j];y[paste0('baseusers|',j)]<-base[j]/100*meta$wra2026
  for(i in 1:11)for(m in c(meta$methods,'EC','Total')){
   mix<-if(m=='Total')1 else x$mix[m];add<-if(m=='Total')sum(x$counts[i,,])else if(m=='EC')0 else sum(x$counts[i,m,]);b<-base[j]*mix;key<-paste(j,i,m,sep='|')
   y[paste0('usualusers|',key)]<-b/100*meta$wra2026;y[paste0('retainedusers|',key)]<-b/100*meta$wra2026+add
   y[paste0('usualmcpr|',key)]<-b;y[paste0('retainedmcpr|',key)]<-b+100*add/meta$wra2026
  }
 }
 y
}
pt<-metrics(p);ds<-vapply(d,metrics,pt);lo<-apply(ds,1,quantile,.025);hi<-apply(ds,1,quantile,.975)
write.csv(data.frame(key=names(pt),estimate=unname(pt),lower=unname(lo),upper=unname(hi)),file.path(o,'planning_intervals.csv'),row.names=FALSE)
jsonlite::write_json(meta,file.path(o,'metadata.json'),auto_unbox=TRUE,pretty=TRUE)
cat('95% intervals for',length(pt),'metrics from',ncol(ds),'valid replicates\n')
)----------------------")

MODULES[["210_prepare_analysis_inputs.R"]] <- list(language="R", packaged_sha256="1e3e1102e7c840c9c611e2ea772935416db5073aa88cd6309f05c1fa4679f23d", args=character(0), code=r"----------------------(if(!requireNamespace('haven',quietly=TRUE))stop('Install R package haven first.')
# DHS complex survey design for this module.
.dhs_root <- Sys.getenv('NIGERIA_PROJECT_ROOT')
if (!nzchar(.dhs_root)) {
 .dhs_file <- sub('^--file=','',grep('^--file=',commandArgs(FALSE),value=TRUE)[1])
 .dhs_root <- dirname(dirname(normalizePath(.dhs_file)))
}
source(file.path(.dhs_root,'Code','dhs_survey_tools.R'),local=TRUE)
dhs_set_context(country='Nigeria',root=.dhs_root)
#!/usr/bin/env Rscript
# Reuse existing country data definitions; stop before fitting any model.
root<-Sys.getenv('NIGERIA_PROJECT_ROOT');stopifnot(nzchar(root))
derived<-file.path(root,'Data','Derived');prefix<-'nigeria'

local({
#!/usr/bin/env Rscript
# Nigeria DHS 2024 descriptive analysis. Run after 01_nigeria_calendar_life_table.R.
# No package download is needed. The source IR recode stays unchanged.
# The outcome is cessation of the ORIGINAL modern method within 12 months for
# one of eight potentially actionable calendar reason codes. All other endings
# remain competing events. Emergency contraception is excluded because it is
# an episodic intervention, although it remains in official mCPR tabulations.
# Six geopolitical zones (v024) are the primary subnational geography.

root <- Sys.getenv("NIGERIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
full_ir <- readRDS(file.path(root,'Data/raw_dhs_ir/NG2024DHS__NGIR8BDT__IR_raw.rds'))
full_frame <- unique(data.frame(cluster=as.numeric(full_ir$v021),stratum=as.numeric(full_ir$v022)))

support <- file.path(root,'output/Supporting_data')
derived <- file.path(root,'Data/Derived')
e <- readRDS(file.path(derived,'nigeria_2024_table_7_12_episodes.rds'))
ir <- readRDS(file.path(Sys.getenv("NIGERIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE)), 'Data/raw_dhs_ir/NG2024DHS__NGIR8BDT__IR_raw.rds'))
stopifnot(nrow(ir)==39050L,nrow(e)==11210L)

zone_names <- c('North West','North East','North Central','South East','South South','South West')
e$zone_name <- zone_names[e$zone]
e$cluster <- as.numeric(ir$v021[e$woman_row])
e$stratum <- as.numeric(ir$v022[e$woman_row])
e$method_group <- 'Other modern'
e$method_group[e$method_code==1] <- 'Pill'
e$method_group[e$method_code==2] <- 'IUD'
e$method_group[e$method_code==3] <- 'Injectables'
e$method_group[e$method_code==11] <- 'Implants'
modern_codes <- c(1L,2L,3L,5L,6L,7L,11L,13L,14L,15L,17L,18L,19L,20L)
e <- e[e$method_code %in% modern_codes,]
stopifnot(!any(e$method_code==16L),all(e$zone %in% 1:6))
saveRDS(e,file.path(derived,'nigeria_2024_modern_episodes.rds'))

})
local({
#!/usr/bin/env Rscript
# Nigeria DHS 2024: adjusted zone comparison for actionable discontinuation.
# Run after scripts 01 and 02. Unit of fitting is the episode-month. Outcomes
# are continuation, actionable discontinuation, and another competing ending.
# Therefore pregnancy intentions, partner disapproval, other fertility reasons,
# and unresolved reasons remain in the starting cohort and leave at their end.
# The two multinomial discrete-time models mirror the Ethiopia specification:
# A: month of method use, method, zone; B: A plus measured characteristics.
# Method use month is elapsed duration since the ORIGINAL method began, not
# duration at interview. Both models retain delayed-entry episodes for fitting.
# Adjusted zone probabilities predict a 12-month first-year trajectory on the
# SAME observed-start national episodes with each zone assigned in turn. This
# is common-composition standardization, not each zone's actual observed mix.

root <- Sys.getenv("NIGERIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
full_ir <- readRDS(file.path(root,'Data/raw_dhs_ir/NG2024DHS__NGIR8BDT__IR_raw.rds'))
full_frame <- unique(data.frame(cluster=as.numeric(full_ir$v021),stratum=as.numeric(full_ir$v022)))

support <- file.path(root,'output/Supporting_data')
derived <- file.path(root,'Data/Derived')
if(!requireNamespace('nnet',quietly=TRUE))stop('nnet package is required')
e <- readRDS(file.path(derived,'nigeria_2024_modern_episodes.rds'))
ir <- readRDS(file.path(Sys.getenv("NIGERIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE)), 'Data/raw_dhs_ir/NG2024DHS__NGIR8BDT__IR_raw.rds'))
actionable <- c(1L,4L,5L,6L,7L,8L,10L,15L)
e$zone_name <- factor(e$zone_name,
  levels=c('North West','North East','North Central','South East','South South','South West'))
e$method_group <- factor(e$method_group,
  levels=c('IUD','Injectables','Implants','Pill','Other modern'))
e$age_at_start <- (e$start-as.numeric(ir$v011[e$woman_row]))/12
stopifnot(all(e$age_at_start>=10),all(e$age_at_start<50))
# A small number of calendar episodes began before age 15, although every
# respondent was 15–49 at interview. Retain them in an honestly labeled group.
e$age_group <- factor(ifelse(e$age_at_start<20,'Under 20',
  ifelse(e$age_at_start<25,'20–24',ifelse(e$age_at_start<35,'25–34','35–49'))),
  levels=c('25–34','Under 20','20–24','35–49'))
bcols <- grep('^b3_',names(ir),value=TRUE)
b <- as.matrix(ir[e$woman_row,bcols])
parity <- rowSums(!is.na(b) & b<=e$start)
e$parity_group <- factor(ifelse(parity==0,'0',ifelse(parity<=2,'1–2',
  ifelse(parity<=4,'3–4','5+'))),levels=c('0','1–2','3–4','5+'))
marital <- as.numeric(ir$v501[e$woman_row])
e$marital_group <- factor(ifelse(marital==0,'Never in union',
  ifelse(marital==1,'Married',ifelse(marital==2,'Living together',
  'Formerly in union'))),
  levels=c('Married','Never in union','Living together','Formerly in union'))
educ <- as.numeric(ir$v106[e$woman_row])
e$education <- factor(ifelse(educ==0,'None',ifelse(educ==1,'Primary',
  ifelse(educ %in% c(2,3),'Secondary or higher',NA_character_))),
  levels=c('None','Primary','Secondary or higher'))
e$wealth <- factor(c('Poorest','Poorer','Middle','Richer','Richest')[
  as.numeric(ir$v190[e$woman_row])],
  levels=c('Poorest','Poorer','Middle','Richer','Richest'))
e$residence <- factor(ifelse(as.numeric(ir$v025[e$woman_row])==1,'Urban','Rural'),
  levels=c('Urban','Rural'))
# Very recent 2024 starts contribute only 50 episodes and no observed
# actionable endings in the DHS window. A separate 2024 indicator therefore
# perfectly separates the event outcome. Pool 2023 and 2024 starts so the
# cohort term remains estimable while retaining all eligible episodes.
year <- (e$start-1L)%/%12L+1900L
e$start_year <- factor(ifelse(year>=2023,'2023–24',as.character(year)))
complete <- complete.cases(e[,c('method_group','zone_name','age_group',
  'parity_group','marital_group','education','wealth','residence','start_year')])
cat('Complete-case episodes:',sum(complete),'of',nrow(e),'\n')
e <- e[complete,]
saveRDS(e,file.path(derived,'nigeria_2024_model_episode_covariates.rds'))

observed_months <- pmax(0L,pmin(12L,e$exposure)-e$entry)
idx <- rep(seq_len(nrow(e)),observed_months)
month <- unlist(Map(function(first,n)seq.int(first+1L,length.out=n),
  e$entry,observed_months),use.names=FALSE)
person <- e[idx,c("woman_row",'wt','cluster','stratum','method_group','zone_name',
  'age_group','parity_group','marital_group','education','wealth',
  'residence','start_year')]
person <- dhs_calendar_records(person,dhs_context()$ir)
person$month <- factor(month,levels=1:12)
end <- e$discontinued[idx] & month==e$exposure[idx]
person$outcome <- factor(ifelse(!end,'continue',
  ifelse(e$reason_code[idx] %in% actionable,'actionable','competing')),
  levels=c('continue','actionable','competing'))
stopifnot(!anyNA(person),nrow(person)>40000)
saveRDS(person,file.path(derived,'nigeria_2024_person_month.rds'))

})
ir<-readRDS(file.path(root,'Data/raw_dhs_ir/NG2024DHS__NGIR8BDT__IR_raw.rds'))

# Save an explicit month-level calendar alongside the original run-level data.
# Nonuse, pregnancy, births and terminations remain in this broad calendar.
# Only method-use episodes enter discontinuation denominators.
cal <- readRDS(file.path(derived,paste0(prefix,'_2024_calendar_events.rds')))
w <- rep(seq_len(nrow(cal)),cal$duration)
offset <- sequence(cal$duration)-1L
cmc <- as.integer(cal$start[w]+offset)
wr <- cal$woman_row[w]
position <- as.integer(ir$v018[wr]+ir$v008[wr]-cmc)
stopifnot(all(position>=1L & position<=80L))
month_data <- data.frame(woman_row=wr,calendar_month_cmc=cmc,
 calendar_position=position,method_code=cal$method_code[w],
 method_character=substring(ir$vcal_1[wr],position,position),
 reason_character=substring(sprintf('%-80s',ir$vcal_2[wr]),position,position),
 wt=as.numeric(ir$v005[wr])/1e6,cluster=as.numeric(ir$v021[wr]),
 stratum=as.numeric(ir$v022[wr]))
# Assert exact character alignment, rather than checking row counts alone.
chars<-strsplit('123456789WNALCFEMS~','')[[1]]
expected_code<-match(month_data$method_character,chars)
for(pair in list(c('0',0L),c('B',81L),c('T',82L),c('P',83L),c('?',99L)))
 expected_code[month_data$method_character==pair[1]]<-as.integer(pair[2])
stopifnot(!anyNA(expected_code),all(expected_code==month_data$method_code),
 all(tabulate(month_data$woman_row,nbins=nrow(ir))==as.integer(ir$v019)))
saveRDS(month_data,file.path(derived,paste0(prefix,'_2024_calendar_months.rds')))
frame<-unique(data.frame(cluster=as.numeric(ir$v021),stratum=as.numeric(ir$v022)))
saveRDS(frame,file.path(derived,paste0(prefix,'_2024_full_survey_frame.rds')))
current<-which(as.integer(ir$v313)==3L)
current_users<-data.frame(woman_row=current,method_code=as.integer(ir$v312[current]),
 elapsed_months=as.numeric(ir$v337[current]),wt=as.numeric(ir$v005[current])/1e6,
 cluster=as.numeric(ir$v021[current]),stratum=as.numeric(ir$v022[current]),
 region=as.integer(ir$v024[current]))
saveRDS(current_users,file.path(derived,paste0(prefix,'_2024_current_modern_users.rds')))
cat('Created source-aligned calendar months, full survey frame and current-user inputs.\n')
)----------------------")

MODULES[["300_revised_planning.R"]] <- list(language="R", packaged_sha256="c877b5a3a87c7646cb162992c9000c5c0bb4e58a1193ae998b81252daf19f847", args=character(0), code=r"----------------------(#!/usr/bin/env Rscript
# Usage: compute_2025.R SAVED_STATS_DIR VERIFIED_GROWTH_JSON OUTPUT_DIR
# Reuses saved point estimates and 500 survey bootstrap draws. Models are not refitted.
a<-commandArgs(TRUE);stopifnot(length(a)==3)
suppressPackageStartupMessages(library(jsonlite))
point<-readRDS(file.path(a[1],'planning_point.rds'));reps<-readRDS(file.path(a[1],'planning_replicates.rds'));meta<-readRDS(file.path(a[1],'planning_metadata.rds'))
outdir<-a[3];dir.create(outdir,recursive=TRUE,showWarnings=FALSE)
verified<-fromJSON(a[2]);rates<-verified$scenarios$annual_change_pp
labels<-verified$scenarios$scenario
if(is.null(meta$epsilon))meta$epsilon<-0
metrics<-function(x){
 counts<-x$risk[1:8,,,drop=FALSE]
 for(m in meta$methods)counts[,m,]<-x$risk[1:8,m,]*x$users2024[m]
 new_counts<-x$risk[9,,,drop=FALSE];for(m in meta$methods)new_counts[1,m,]<-x$risk[9,m,]*x$users2024[m]
 counts<-abind::abind(counts,counts[1,,,drop=FALSE]-counts[6,,,drop=FALSE],counts[2,,,drop=FALSE]-counts[4,,,drop=FALSE],counts[3,,,drop=FALSE]-counts[5,,,drop=FALSE],new_counts,counts[3,,,drop=FALSE]-new_counts,along=1)
 y<-c(stock_no_ec=sum(x$users2024[meta$methods]),mcpr2024=x$mcpr,users2024=sum(x$users2024))
 for(m in c(meta$methods,'EC','Permanent methods'))y[paste('stock',m,sep='|')]<-x$users2024[m]
 for(i in 1:13)for(m in c(meta$methods,'Total'))for(ca in c(meta$causes,'Total')){
  mi<-if(m=='Total')1:5 else match(m,meta$methods);ci<-if(ca=='Total')1:5 else match(ca,meta$causes)
  v<-sum(counts[i,mi,ci]);stock<-if(m=='Total')sum(x$users2024[meta$methods])else x$users2024[m];key<-paste(i,m,ca,sep='|')
  y[paste0('count|',key)]<-v;y[paste0('pp|',key)]<-100*v/meta$wra2025;y[paste0('risk|',key)]<-100*v/stock
 }
 for(j in 1:3){base<-x$mcpr+rates[j];y[paste0('base|',j)]<-base;y[paste0('baseusers|',j)]<-base/100*meta$wra2025
  for(i in 1:13)for(m in c(meta$methods,'EC','Permanent methods','Total')){
   share<-if(m=='Total')1 else x$mix[m];add<-if(m=='Total')sum(counts[i,,])else if(m%in%c('EC','Permanent methods'))0 else sum(counts[i,m,]);usual<-base*share
   key<-paste(j,i,m,sep='|');y[paste0('usualusers|',key)]<-usual/100*meta$wra2025;y[paste0('retainedusers|',key)]<-usual/100*meta$wra2025+add
   y[paste0('usualmcpr|',key)]<-usual;y[paste0('retainedmcpr|',key)]<-usual+100*add/meta$wra2025
  }
 }
 for(i in 1:13)for(m in c(meta$methods,'Total'))for(ca in c(meta$causes,'Total')){
  base<-if(i==4)2 else if(i%in%c(5,12))3 else i;key<-paste(i,m,ca,sep='|');den<-y[paste0('count|',base,'|',m,'|',ca)]
  y[paste0('fraction|',key)]<-if(den>0)100*y[paste0('count|',key)]/den else 0
 }
 copykeys<-names(y)[grepl('^(count|pp|stock|base|usualusers|retainedusers|usualmcpr|retainedmcpr)[|]',names(y))]
 for(k in copykeys)y[paste0('legacy_',k)]<-y[k]
 y['legacy_stock|Total']<-sum(x$users2024)
 y
}
pt<-metrics(point);ds<-vapply(reps,metrics,pt);ds<-pt+(ds-pt)/(1-meta$epsilon)
lo<-apply(ds,1,quantile,.025);hi<-apply(ds,1,quantile,.975);lo<-pmax(0,pmin(lo,pt));hi<-pmax(hi,pt)
pct<-grepl('^(risk|usualmcpr|retainedmcpr)[|]',names(pt));hi[pct]<-pmin(100,hi[pct])
write.csv(data.frame(key=names(pt),estimate=unname(pt),lower=unname(lo),upper=unname(hi)),file.path(outdir,'revised_planning_intervals.csv'),row.names=FALSE)
write.csv(data.frame(key=names(pt),estimate=unname(pt),lower=unname(lo),upper=unname(hi)),file.path(outdir,'planning_intervals.csv'),row.names=FALSE)
meta$reference_year<-2024;meta$outcome_year<-2025;meta$definitions[4]<-'Observed 2024 current-user cohort; 2025 mCPR under recent DHS, longer-term DHS, or FPET-informed annual change. Growth and population assumptions are fixed.'
write_json(meta,file.path(outdir,'metadata.json'),auto_unbox=TRUE,pretty=TRUE)
summary<-data.frame(scenario=labels,annual_change_pp=rates,mcpr2024=point$mcpr,mcpr2025=point$mcpr+rates,users2024=sum(point$users2024),users2025=(point$mcpr+rates)/100*meta$wra2025)
write.csv(summary,file.path(outdir,'scenario_summary.csv'),row.names=FALSE)
jsonlite::write_json(list(scenarios=summary,reference_year=2024,outcome_year=2025,wra2024=meta$wra2024,wra2025=meta$wra2025,methods=meta$methods,causes=meta$causes,replicates=length(reps),rates_from=verified$rates_from,reference_stock=as.list(point$users2024),ending_totals=sapply(1:5,function(i)pt[paste0('count|',i,'|Total|Total')]),pp_totals=sapply(1:5,function(i)pt[paste0('pp|',i,'|Total|Total')])),file.path(outdir,'revision_inputs.json'),auto_unbox=TRUE,pretty=TRUE,digits=15)
stopifnot(!anyNA(pt),all(pt[grepl('^(count|pp)[|]',names(pt))]>=-1e-6))
cat('2025 mCPR gains (gross first-year / historical / AFT; switching historical / AFT):\n');print(sapply(1:5,function(i)pt[paste0('pp|',i,'|Total|Total')]))
print(summary)
)----------------------")

MODULES[["301_revised_tables.py"]] <- list(language="Python", packaged_sha256="51246815163f03b8b9d24611ce540e7c15a754d063e1849e9ef6beddac8b7f46", args=character(0), code=r"----------------------(#!/usr/bin/env python3
"""Usage: build_tables.py REVISED_STATS_DIR ORIGINAL_SPECS_JSON OUTPUT_DIR"""
from pathlib import Path
import sys,csv,json,copy
stats,oldfile,out=map(Path,sys.argv[1:]);out.mkdir(exist_ok=True,parents=True)
meta=json.loads((stats/'revision_inputs.json').read_text());D={r['key']:{k:float(r[k]) for k in ['estimate','lower','upper']} for r in csv.DictReader((stats/'revised_planning_intervals.csv').open())}
methods=meta['methods'];causes=meta['causes'];old=json.loads(oldfile.read_text());old=old+[dict(x,approach=12)for x in old if x['approach']==5]
labels=[f'6-year DHS trend\n({meta["scenarios"][0]["annual_change_pp"]:+.2f} pp/year)',f'11-year DHS trend\n({meta["scenarios"][1]["annual_change_pp"]:+.2f} pp/year)',f'FPET-informed growth\n({meta["scenarios"][2]["annual_change_pp"]:+.2f} pp/year)']
short=['6-year DHS trend','11-year DHS trend','FPET-informed growth']
def val(key,kind='num',deck=False):
 x=D[key];scale=1000 if deck and kind=='num' else 1;digits=(1 if deck else 0) if kind=='num' else 1 if kind=='risk' else 2
 def f(y):return '<0.01' if kind=='pp' and 0<y<.005 else '<0.1' if kind=='num' and deck and 0<y/scale<.05 else f'{y/scale:,.{digits}f}'
 suffix=' pp' if kind=='pp' else '%' if kind in ['risk','pct'] else ''
 v=f(x['estimate'])+suffix
 if x['estimate']==x['lower']==x['upper']==0:return v+'\n(CI unavailable†)'
 if not deck and abs(x['upper']-x['lower'])>1e-10:v+='\n('+f(x['lower'])+'–'+f(x['upper'])+')'
 return v
def make(sp,deck):
 s=copy.deepcopy(sp);a=s['approach'];kind=s['kind'];base=2 if a==4 else 3 if a in [5,12] else a;label=s['title'].split(':')[0]
 s['subtitle']='Users in thousands; point estimates' if deck else 'Numbers of women; estimates (95% survey intervals)'
 c=lambda m,ca:val(f'count|{a}|{m}|{ca}',deck=deck)
 pp=lambda m,ca:val(f'pp|{a}|{m}|{ca}','pp',deck)
 stock=lambda m:val('users2024' if m=='Total' else 'stock|'+m,deck=deck)
 name=lambda m:m
 heads=['Method / measure','Method\nfailure','Want more\neffective','Bleeding\nchanges','Other side\neffects/health','Access/cost/\nconvenience','All actionable\ncauses']
 if kind=='method':
  s['table']=[['Method','2024 survey\ncurrent users','Original-method ending\nprobability' if a>3 else 'Actionable ending\nprobability','Year-end losses\nafter switching' if a>3 else 'Users ending\noriginal method','mCPR equivalent']]
  for m in methods:s['table'].append([name(m),stock(m),val(f'risk|{base}|{m}|Total','risk',deck),c(m,'Total'),pp(m,'Total')])
  s['table'].append(['EC',stock('EC'),'Not applied','Not estimated','Not estimated'])
  s['table'].append(['Permanent methods',stock('Permanent methods'),'Not modeled','Not estimated','Not estimated'])
  s['table'].append(['Reversible users\nexcluding EC',val('stock_no_ec',deck=deck),val(f'risk|{base}|Total|Total','risk',deck),c('Total','Total'),pp('Total','Total')])
 elif kind in ['cause','cause_pp']:
  s['table']=[heads]+[[name(m),*[c(m,ca) for ca in causes],c(m,'Total')] for m in methods]
  s['table'].append(['Year-end losses' if a>3 else 'Users ending method',*[c('Total',ca) for ca in causes],c('Total','Total')])
  if kind=='cause_pp':
   pop=meta['wra2025']/1000 if deck else meta['wra2025']
   s['table'].append(['2025 women aged\n15–49 (fixed)',*[f'{pop:,.1f}']*6]);s['table'].append(['mCPR increase (pp)',*[pp('Total',ca) for ca in causes],pp('Total','Total')])
 elif kind=='baseline':
  s['title']=label+': mCPR growth scenarios';s['subtitle']='2024 survey baseline and projected 2025 mCPR under three annual-change assumptions'
  s['table']=[['Different mCPR\ngrowth scenarios','Annual change\n(pp/year)','2024 survey\nmCPR','Projected 2025\nmCPR']]+[[labels[j-1],f'{meta["scenarios"][j-1]["annual_change_pp"]:+.2f}',val('mcpr2024','pct',deck),val(f'base|{j}','pct',deck)] for j in range(1,4)]
 elif kind=='scenario':
  s['table']=[['Different mCPR\ngrowth scenarios','2025 users\nusual scenario','2025\nmCPR','2025 users\nif retained','mCPR\nif retained','Increase\n(pp)']]
  for j in range(1,4):
   k=f'{j}|{a}|Total';s['table'].append([labels[j-1],val('usualusers|'+k,deck=deck),val('usualmcpr|'+k,'pct',deck),val('retainedusers|'+k,deck=deck),val('retainedmcpr|'+k,'pct',deck),pp('Total','Total')])
 elif kind=='method_scenario':
  j=s['scenario'];s['title']=label+': '+short[j-1]+' by method'
  s['table']=[['Method','2024 survey\nusers','2025 users\nusual scenario','Losses\navoided','2025 users\nif retained','2025\nmCPR','mCPR\nif retained']]
  for m in methods+['EC','Permanent methods','Total']:
   k=f'{j}|{a}|{m}';s['table'].append(['All modern' if m=='Total' else name(m),stock(m),val('usualusers|'+k,deck=deck),'Not estimated' if m in ['EC','Permanent methods'] else c(m,'Total'),val('retainedusers|'+k,deck=deck),val('usualmcpr|'+k,'pct',deck),val('retainedmcpr|'+k,'pct',deck)])
 else:raise ValueError(kind)
 definitions={1:'First-year: weighted actionable cumulative incidence in months 1–12 after initiation, applied to observed 2024 current users. Elapsed use is not incorporated.',2:'Historical: observed next-12-month actionable ending probability at current elapsed duration. The 61+ month group uses 37–60-month experience.',3:'AFT: seven weighted models predict next-12-month actionable endings conditional on elapsed use. Actionable and other endings compete, and five cause models allocate actionable endings.'}
 s['note']=definitions[base]
 s['note']+=(' Sensitivity: year-end losses deduct modern-to-modern switches and later restarters; EC counts as modern at year end.' if a>3 else ' Every actionable original-method ending is treated as a lost user. Switching/restarting is not deducted.')
 s['note']+=' Partner/spousal disapproval is excluded. The observed 2024 cohort is fixed across scenarios. Population and growth assumptions are fixed.'
 if not deck:s['note']+=' 95% intervals use 500 stratified PSU bootstrap draws; AFT families are fixed. CI bounds are not additive.'
 if base==3:s['note']+=' Sparse IUD causes have only 1–11 observed training events.'
 if a>3:s['note']+=' Sparse pathway cells use documented pooling.'
 if kind=='method':s['note']+=' Total ending probability averages method-specific risks using the 2024 current-user mix, excluding EC.'
 if kind=='baseline':s['note']=f'Recent annual change = (2024 DHS {meta["rates_from"]["dhs2024"]:.4f}% − 2018 DHS {meta["rates_from"]["dhs2018"]:.4f}%)/6. Longer-term change = (2024 DHS − 2013 DHS {meta["rates_from"]["dhs2013"]:.4f}%)/11. FPET-informed change = {meta["rates_from"]["fpet2025"]:.1f}% − {meta["rates_from"]["fpet2024"]:.1f}%. Each is added once to the 2024 DHS baseline. Growth assumptions are fixed.'

 return s
from wording import revise
for deck in [True,False]:(out/('planning_slides.json' if deck else 'planning_html.json')).write_text(json.dumps([revise(make(s,deck),deck) for s in old],indent=2))
print('Built 48 Nigeria tables for 2024-to-2025, including all three switching sensitivity sets.')
)----------------------")

MODULES[["302_revised_html.py"]] <- list(language="Python", packaged_sha256="62a72a5babfa7974d5fbd704d153586e193f3960bca06efc722d3be42f09cbec", args=character(0), code=r"----------------------("""Update Nigeria planning chapters from an observed 2024 cohort to 2025.

Usage: update_html.py SOURCE_HTML STATS_DIR HTML_SPECS OUTPUT_HTML
"""
from pathlib import Path
from lxml import html
from html import escape
import json,csv,re,copy,sys
source,stats,specfile,target=map(Path,sys.argv[1:]);doc=html.parse(str(source))
meta=json.loads((stats/'revision_inputs.json').read_text());spec=json.loads(specfile.read_text())
D={r['key']:{k:float(r[k])for k in ['estimate','lower','upper']}for r in csv.DictReader((stats/'planning_intervals.csv').open())}
methods=meta['methods'];causes=meta['causes'];oldids=set(doc.xpath('//section/@id'))
def sec(sid):return doc.xpath(f'//section[@id="{sid}"]')[0]
def table(rows):
 return '<div class="tablewrap"><table class="survey-table"><thead><tr>'+''.join('<th>'+escape(str(v)).replace('\n','<br>')+'</th>'for v in rows[0])+'</tr></thead><tbody>'+''.join('<tr>'+''.join(('<th scope="row">'if j==0 else'<td>')+escape(str(v)).replace('\n','<br>')+('</th>'if j==0 else'</td>')for j,v in enumerate(row))+'</tr>'for row in rows[1:])+'</tbody></table></div>'
def article(s,ci=True):
 s=copy.deepcopy(s)
 if not ci:
  s['table']=[[re.sub(r'\n\([^\n]*[–−][^\n]*\)|\n\(CI unavailable†\)','',v)for v in row]for row in s['table']]
  s['subtitle']=s['subtitle'].replace('estimates (95% survey intervals)','point estimates').replace('Number of users (95% CI)','Number of users')
  s['note']=re.sub(r' 95% intervals use.*?CI bounds are not additive\.','',s['note'])
  s['note']=re.sub(r' 95% CIs use 500 survey bootstrap samples\. Population and growth assumptions stay fixed\. Confidence limits do not add across cells\. † No events observed, so no reliable CI\.',' Estimates use DHS survey weights. Population and growth assumptions stay fixed.',s['note']).replace('AFT intervals hold the selected curve families fixed.','Fits use the selected survival distributions.')
 return '<article class="duration-slide"><h3>'+escape(s['title'])+'</h3><p>'+escape(s['subtitle'])+'</p>'+table(s['table'])+'<p class="note">'+escape(s['note'])+'</p></article>'
def reset(sid,title,markup):
 s=sec(sid);s.clear();s.set('id',sid);s.set('class','analysis-section duration-block');h=html.Element('h2');h.text=title;s.append(h)
 for x in html.fragments_fromstring(markup):
  if isinstance(x,str):s.text=(s.text or'')+x
  else:s.append(x)
 return s
def val(key,kind='num'):
 x=D[key];digits=0 if kind=='num'else 1 if kind=='risk'else 2
 f=lambda v:f'{v:,.{digits}f}'
 suffix=' pp'if kind=='pp'else'%'if kind in ['risk','pct']else''
 return f(x['estimate'])+suffix+'\n('+f(x['lower'])+'–'+f(x['upper'])+')'
count=lambda a,m='Total',c='Total':val(f'count|{a}|{m}|{c}')
pp=lambda a,m='Total',c='Total':val(f'pp|{a}|{m}|{c}','pp')
def matrix(a,as_pp=False):return table([['Method / measure',*causes,'All actionable causes']]+[[m,*[(pp(a,m,c)if as_pp else count(a,m,c))for c in causes],pp(a,m)if as_pp else count(a,m)]for m in methods+['Total']])
reset('user-projections','First-year actionable discontinuation: 2024 users followed to 2025',article(spec[0])+article(spec[1]))
reset('mcpr-scenarios','First-year approach: 2025 mCPR under three growth scenarios',article(spec[2])+article(spec[3])+article(spec[7]))
reset('method-level-mcpr-scenarios','First-year approach: 2025 mCPR scenarios by method',''.join(article(s)for s in spec[4:7]))
rows=[['Approach (no switching adjustment)','Actionable original-method endings (95% CI)','2025 mCPR increase (95% CI)']]
for a,name in [(1,'First-year probability'),(2,'Historical duration-aware'),(3,'AFT survival')]:rows.append([name,count(a),pp(a)])
reset('three-approach-planning','Three approaches: observed 2024 users followed to 2025',
 '<p>All three main calculations concern potentially actionable endings of original modern methods, excluding EC and partner/spousal disapproval. The reference stock is the observed 2024 DHS all-women prevalence and method distribution multiplied by 2024 UN women aged 15–49. The historical and AFT probabilities use the observed 2024 elapsed-duration distribution. Each scenario projects usual-condition 2025 mCPR by adding one annual growth increment to the 2024 DHS baseline. Additional retained users are added to that usual-condition 2025 stock. The same observed 2024 cohort is fixed across scenarios. Every pp contribution divides the retained count by 57,393,553 projected women ages 15–49 in 2025, multiplied by 100. Main tables treat every actionable ending as a user lost and do not deduct switching or restarting. EC remains in baseline mCPR and contributes no retention increment.</p>'+table(rows)+
 '<p class="note">Intervals use the existing 500 full-frame stratified PSU bootstrap replicates. They propagate survey sampling, prevalence, method mix, duration, historical risks, fitted AFT curves and observed pathways. Population, secular-growth assumptions and selected AFT families remain fixed. These are conditional scenarios, not estimates of intervention effectiveness.</p>')
for sid,title,part,a in [('historical-duration-aware-planning','Historical duration-aware approach: 2025 mCPR without switching deduction',spec[8:16],2),('aft-duration-aware-planning','AFT survival approach: 2025 mCPR without switching deduction',spec[16:24],3)]:
 reset(sid,title,''.join(article(s,False)for s in part)+'<h3>Additional detail: 2025 mCPR percentage-point equivalent by method and cause (95% CI)</h3>'+matrix(a,True))
for sid,title,part in [('historical-switching-sensitivity','Historical switching sensitivity: 2024 users followed to 2025',spec[24:32]),('aft-switching-sensitivity','AFT switching sensitivity: 2024 users followed to 2025',spec[32:40])]:reset(sid,title,''.join(article(s)for s in part))
# Keep the complementary pathway diagnostics, with the same rebased counts.
rows=[['Method','Observed 2024 users','Gross actionable endings','Direct modern switches','Without direct switch']]
for m in methods+['Total']:rows.append([m,val('stock_no_ec'if m=='Total'else'stock|'+m),count(1,m),count(6,m),count(9,m)])
reset('switch-bridge','Sensitivity: direct switching only, 2024 to 2025','<p>Direct switching means modern use in the next recorded month. Later restarting is not deducted here. EC counts as modern at destination.</p>'+table(rows)+'<h3>Direct switches by cause (95% CI)</h3>'+matrix(6)+'<h3>2025 mCPR equivalent if endings without a direct switch were losses (95% CI)</h3>'+matrix(9,True))
rows=[['Current method','Gross actionable endings','Direct switches','Modern at year end after ending','Outside modern use at year end']]
for m in methods+['Total']:rows.append([m,count(2,m),count(7,m),count(10,m),count(4,m)])
reset('duration-bridge','Sensitivity: historical duration and modern use in 2025',table(rows)+'<h3>Outside modern use at year end by cause (95% CI)</h3>'+matrix(4)+article(spec[27]))
reset('duration-aware-cause-pp-matrices','Sensitivity: historical year-end loss by method and cause, 2025',matrix(4)+'<h3>2025 percentage-point equivalents (95% CI)</h3>'+matrix(4,True))
rows=[['Current method','AFT actionable endings','Direct switches','Modern at year end after ending','Outside modern use at year end']]
for m in methods+['Total']:rows.append([m,count(3,m),count(8,m),count(11,m),count(5,m)])
reset('duration-planning-appendix','Sensitivity: AFT pathway diagnostics, 2024 to 2025','<p>Original-method ending probabilities are unchanged. Year-end modern-use status comes from observed calendar pathways, including EC. User counts now start from observed 2024 users.</p>'+table(rows)+'<h3>AFT original-method endings by cause (95% CI)</h3>'+matrix(3)+'<h3>Direct switches by cause (95% CI)</h3>'+matrix(8)+'<h3>Outside modern use at year end by cause (95% CI)</h3>'+matrix(5))
for sid in ['switch-bridge','duration-bridge','duration-aware-cause-pp-matrices','duration-planning-appendix']:
 sec(sid).append(html.fragment_fromstring('<p class="note">Counts use the observed 2024 current-user cohort. All 2025 pp equivalents divide by 57,393,553 projected women ages 15–49. Intervals use 500 stratified PSU bootstrap draws, conditional on fixed population and growth assumptions.</p>'))
# Two-year reference table is replaced by a single one-year projection.
rows=[['Year','Women aged 15–49'],['2024',f'{meta["wra2024"]:,.0f}'],['2025',f'{meta["wra2025"]:,.0f}']]
growth=[['Year','Growth scenario','All-women mCPR (95% survey CI)','Women ages 15–49','Modern users (95% survey CI)'],['2024','Observed DHS baseline',val('mcpr2024','pct'),f'{meta["wra2024"]:,.0f}',val('users2024')]]
for j,s in enumerate(meta['scenarios'],1):growth.append(['2025',s['scenario']+f' ({s["annual_change_pp"]:+.2f} pp/year)',val(f'base|{j}','pct'),f'{meta["wra2025"]:,.0f}',val(f'baseusers|{j}')])
reset('population','Nigeria population and 2025 mCPR inputs','<p>All scenarios start from the 2024 DHS all-women mCPR of 13.104165%. Recent growth annualizes the 2018–2024 difference over six years. Longer-term growth annualizes the 2013–2024 difference over eleven years. FPET-informed growth applies the modeled 2024–2025 change of +0.40 pp. Each adds one annual increment to the 2024 DHS baseline. UN populations supply the 2024 current-user scale and the 2025 outcome denominator.</p>'+table(rows)+'<h3>Observed 2024 baseline and usual-condition 2025 scenarios</h3>'+table(growth)+'<p class="note">The retention calculation uses observed 2024 users, not projected 2025 users. Current method and elapsed-duration profiles remain those observed in the 2024 DHS. Those probabilities and the 2024 cohort remain fixed across scenarios. Survey intervals condition on fixed growth and population assumptions.</p>')
# A historical illustrative pathway is not a forecast of a particular cohort.
for p in sec('action-pathways').xpath('.//p'):
 if '2025–26' in p.text_content():p.text=p.text_content().replace('2025–26','2024–25')

# AFT original endings with modeled subsequent transitions.
existing=doc.xpath('//section[@id="aft-modeled-transition-sensitivity"]')
if existing:newsec=existing[0]
else:
 newsec=html.Element('section',id='aft-modeled-transition-sensitivity');sec('aft-switching-sensitivity').addnext(newsec)
newsec.clear();newsec.set('id','aft-modeled-transition-sensitivity');newsec.set('class','analysis-section duration-block')
h=html.Element('h2');h.text='AFT sensitivity using modeled switching and restarting';newsec.append(h)
p=html.Element('p');p.text='This sensitivity keeps the original AFT discontinuation probabilities. A separate model estimates immediate modern switching, while AFT-based transitions track later use or non-use, including restarting and stopping again. The tables count women outside modern use at the common endpoint, 12 months after the prediction starts. Modern use at that endpoint includes EC. Permanent-method destinations are absorbing; sparse uptake uses pooled observed probabilities.';newsec.append(p)
for item in spec[40:48]:newsec.append(html.fragment_fromstring(article(item)))
checkfile=stats/'transition_validation.json'
if checkfile.exists():
 check=json.loads(checkfile.read_text());v=next(x for x in check['held_out']if x['horizon']==12)
 p=html.Element('p',{'class':'note'});p.text=(f'The post-ending model uses {check["episodes"]:,} endings from {check["women"]:,} women. Held-out PSUs provide a separate prediction check. Among {v["observations"]:,} histories observed 12 months after an ending, predicted modern use was {100*v["predicted_modern"]:.1f}% versus {100*v["observed_modern"]:.1f}% observed. This post-ending check differs from the planning endpoint, which remains 12 months from baseline. Sparse method/cause groups, fixed distribution choices and future changes in behavior limit interpretation.');newsec.append(p)
# Keep the three approaches distinct in the section headings.
heads={'user-projections':'Exploratory estimates using first-year probabilities','historical-duration-aware-planning':'Next-year losses using historical duration probabilities','aft-duration-aware-planning':'Next-year losses using AFT duration probabilities','historical-switching-sensitivity':'Historical sensitivity allowing for switching and restarting','aft-switching-sensitivity':'AFT sensitivity using observed switching and restarting','switching-sensitivity':'Sensitivity analyses allowing for switching and restarting'}
for sid,title in heads.items():
 for h in sec(sid).xpath('./h2'):h.text=title
# Put the duration limitation before the first exploratory table.
for p in sec('user-projections').xpath('./p[@class="probability-explanation"]'):sec('user-projections').remove(p)
p=html.Element('p',{'class':'probability-explanation'});b=html.Element('strong');b.text='Basic exploratory calculation. ';p.append(b);b.tail='Applies first-year probabilities to all current users regardless of how long they have already used the method.';sec('user-projections').insert(1,p)
for sid in ['current-user-reason-planning','duration-adjusted-reason-planning']:
 for p in sec(sid).xpath('./p[@class="earlier-planning-notice"]'):sec(sid).remove(p)
 p=html.fragment_fromstring('<p class="earlier-planning-notice"><strong>Earlier exploratory analysis.</strong> This block uses a different reason scope or duration grouping. The current potentially actionable planning tables appear under <a href="#three-approach-planning">Three approaches</a> and the switching sensitivities.</p>');sec(sid).insert(1,p)

# Complete left navigation, retaining section anchors.
aside=doc.find('.//aside');aside.clear();strong=html.Element('strong');strong.text='Nigeria discontinuation';aside.append(strong)
for s in doc.xpath('//main/section[@id]'):
 h=s.find('.//h2')
 if h is not None:
  a=html.Element('a',href='#'+s.get('id'));a.text=h.text_content();aside.append(a)
assert oldids | {'aft-modeled-transition-sensitivity'} == set(doc.xpath('//section/@id'))
text=html.tostring(doc,encoding='unicode',doctype='<!doctype html>')
visible=' '.join(doc.xpath('//body//text()[not(ancestor::script) and not(ancestor::style)]'))
stale=re.search(r'2026|2025–26',visible)
assert not stale,visible[max(0,stale.start()-160):stale.start()+220]if stale else''
target.write_text(text);print('Updated all main and sensitivity planning sets; preserved',len(oldids),'sections.')
)----------------------")

MODULES[["303_validate_revised.py"]] <- list(language="Python", packaged_sha256="f400146ca7e3244cd807100d28207859e24e62860315e100913b497417ace7d7", args=character(0), code=r"----------------------("""Validate the incremental report build; do not claim a fresh full rebuild."""
from pathlib import Path
from lxml import html,etree
import sys,json,csv,hashlib,re
country,base,target,stats,out=sys.argv[1:]
base,target,stats,out=map(Path,[base,target,stats,out]);a=html.parse(str(base));b=html.parse(str(target))
ids=lambda d:set(d.xpath('//section/@id'))
assert ids(a)|{'aft-modeled-transition-sensitivity'}==ids(b),'Section coverage changed'
assert a.xpath('//img/@src')==b.xpath('//img/@src'),'Unrequested figure changes'
assert len(b.xpath('//img'))==len(a.xpath('//img'))
assert b.xpath('//*[@id="four-reason-groups"]'),'Partner/spousal classification block missing'
groups=b.xpath('//*[@id="four-reason-groups"]//tr')
assert any('Partner/spousal' in r.text_content()for r in groups)
scan=re.sub(r'data:[^;]+;base64,[A-Za-z0-9+/=]+','[embedded figure]',target.read_text())
assert not re.search(r'/(?:Users|Volumes)/|file:/{2,}|[A-Z]:\\',scan,re.I),'Personal path in report'
md=json.loads((stats/'revision_inputs.json').read_text())
assert len(md['scenarios'])==3
D={r['key']:float(r['estimate'])for r in csv.DictReader((stats/'revised_planning_intervals.csv').open())}
methods=md['methods'];causes=md['causes'];year=2026 if country=='Ethiopia' else 2025
for ap in [1,2,3,4,5,12]:
    total=D[f'count|{ap}|Total|Total']
    assert abs(total-sum(D[f'count|{ap}|{m}|{c}']for m in methods for c in causes))<1e-5
    assert abs(D[f'pp|{ap}|Total|Total']-100*total/md['wra'+str(year)])<1e-8
    for j in range(1,4):
        k=f'{j}|{ap}|Total'
        assert abs(D['retainedmcpr|'+k]-D['usualmcpr|'+k]-D[f'pp|{ap}|Total|Total'])<1e-8
def tables(d):
    return [[[re.sub(r'\s+','',c.text_content())for c in r.xpath('./th|./td')]for r in t.xpath('.//tr')]for t in d.xpath('//table')]
old,new=tables(a),tables(b)
same=sum(x==y for x,y in zip(old,new))
warnings=[]
def first_number(s):
    m=re.search(r'[-−]?\d[\d,]*(?:\.\d+)?',s)
    return float(m[0].replace(',','').replace('−','-'))if m else None
for article in b.xpath('//article[contains(@class,"duration-slide")]'):
    heading=article.find('h3');title=heading.text_content()if heading is not None else''
    if not title.endswith('by method'):continue
    for tr in article.xpath('.//table//tbody/tr'):
        cells=[c.text_content()for c in tr]
        if len(cells)!=7:continue
        usual,retained,loss=[first_number(cells[i])for i in [2,4,3]]
        if None in [usual,retained,loss]:continue
        delta=retained-usual-loss
        if abs(delta)>2:
            warnings.append(dict(table=title,row=cells[0],projected_users=usual,displayed_retained_users=loss,
                                 displayed_total=retained,displayed_count_discrepancy=delta,
                                 action='Preserved from the input report; reconcile fitted-output versions before treating the full report as mathematically reconciled.'))
result=dict(status='pass_with_existing_report_warnings'if warnings else'pass',country=country,reference_year=2025 if country=='Ethiopia' else 2024,outcome_year=year,
 sections=len(ids(b)),tables=len(new),base_tables=len(old),tables_matching_input_report=same,
 figures_preserved=len(b.xpath('//img')),incremental_build=True,full_raw_ir_to_all_chapters_verified=False,
 planning_arithmetic_input_vectors='pass',existing_report_arithmetic_warnings=warnings,
 base_report_sha256=hashlib.sha256(base.read_bytes()).hexdigest(),
 output_sha256=hashlib.sha256(target.read_bytes()).hexdigest(),
 scope='Planning arithmetic is rebuilt from supplied fitted estimates and bootstrap draws. Unchanged chapters and figures are preserved from the supplied validated HTML layout; they are not freshly recomputed by this command.')
(out/'revised_build_validation.json').write_text(json.dumps(result,indent=2))
print(json.dumps({k:v for k,v in result.items()if k not in ['scope','base_report_sha256','output_sha256']}))
)----------------------")

MODULES[["310_nigeria_planning_audit.R"]] <- list(language="R", packaged_sha256="b64e48a331227d0b24611f98fb1cd2f89c83e98c80421822b64e4870e9a542f7", args=character(0), code=r"----------------------(# DHS complex survey design for this module.
.dhs_root <- Sys.getenv('NIGERIA_PROJECT_ROOT')
if (!nzchar(.dhs_root)) {
 .dhs_file <- sub('^--file=','',grep('^--file=',commandArgs(FALSE),value=TRUE)[1])
 .dhs_root <- dirname(dirname(normalizePath(.dhs_file)))
}
source(file.path(.dhs_root,'Code','dhs_survey_tools.R'),local=TRUE)
dhs_set_context(country='Nigeria',root=.dhs_root)
#!/usr/bin/env Rscript
# Survey-design inference for Nigeria planning scenarios. All inputs are parameters.
# Fixed population and growth assumptions; uncertainty includes IR sampling,
# current-use composition, empirical risks, fitted AFT parameters and pathways.
# AFT intervals condition on the previously selected distribution families.
args <- commandArgs(trailingOnly=TRUE)
stopifnot(length(args)>=2)
root<-normalizePath(args[1]); out<-args[2];dir.create(out,recursive=TRUE,showWarnings=FALSE)
B<-if(length(args)>=3)as.integer(args[3])else 500L
cores<-if(length(args)>=4)as.integer(args[4])else 4L
suppressPackageStartupMessages(library(survival))
ir<-readRDS(file.path(root,'Data/raw_dhs_ir/NG2024DHS__NGIR8BDT__IR_raw.rds'))
e<-readRDS(file.path(root,'Data/Derived/nigeria_2024_modern_episodes.rds'))
e<-e[!e$method_code %in% c(6L,7L),]
cal<-readRDS(file.path(root,'Data/Derived/nigeria_2024_calendar_events.rds'))
sup<-file.path(root,'output/Supporting_data')
script_file<-sub('^--file=','',grep('^--file=',commandArgs(FALSE),value=TRUE)[1])
signature<-unname(tools::md5sum(c(script_file,file.path(dirname(script_file),'dhs_survey_tools.R'),file.path(dirname(script_file),'transition_model.R'),file.path(root,'Data/raw_dhs_ir/NG2024DHS__NGIR8BDT__IR_raw.rds'),file.path(root,'Data/Derived/nigeria_2024_modern_episodes.rds'),file.path(root,'Data/Derived/nigeria_2024_calendar_events.rds'),file.path(sup,'nigeria_wpp2024_wra_2024_2026.csv'),file.path(sup,'nigeria_survival_model_duration_fit.csv'),file.path(sup,'nigeria_survival_model_cause_fit.csv'))))
cache_signature<-file.path(out,'cache_signature.rds')
if(file.exists(cache_signature)){if(!identical(signature,readRDS(cache_signature)))stop('Inputs or code changed. Use a fresh output directory for bootstrap results.')}else{
 if(length(list.files(file.path(out,'replicates'))))stop('Unversioned bootstrap cache: use a fresh output directory.')
 saveRDS(signature,cache_signature)
}

pop<-read.csv(file.path(sup,'nigeria_wpp2024_wra_2024_2026.csv'))
w25<-pop$women_15_49[pop$year==2025];w26<-pop$women_15_49[pop$year==2026]
w24<-pop$women_15_49[pop$year==2024]
methods<-c('Injectables','Implants','Pill','IUD','Other modern')
causes<-c('Method failure','Wanted more effective method','Changes in menstrual bleeding','Other side effects/health','Access/cost/convenience')
codes<-list(1L,7L,15L,c(4L,5L),c(6L,8L,10L)); action<-unlist(codes)
modern<-c(1L,2L,3L,5L,6L,7L,11L,13L,14L,15L,17L,18L,19L,20L)
modern<-setdiff(modern,c(6L,7L))
endpoint_modern<-c(modern,6L,7L,16L)
method_group<-function(x)ifelse(x==3,'Injectables',ifelse(x==11,'Implants',ifelse(x==1,'Pill',ifelse(x==2,'IUD','Other modern'))))
cause_group<-function(x){z<-rep(NA_integer_,length(x));for(j in 1:5)z[x %in% codes[[j]]]<-j;z}
wt<-as.numeric(ir$v005)/1e6;psu<-as.numeric(ir$v021);stratum<-as.numeric(ir$v022)
frame<-unique(data.frame(psu,stratum)); stopifnot(!anyDuplicated(frame$psu))
strata<-split(seq_len(nrow(frame)),frame$stratum);stopifnot(all(lengths(strata)>1))
psu_index<-match(psu,frame$psu)
u<-as.numeric(ir$v313)==3;umethod<-method_group(as.numeric(ir$v312));umethod[as.numeric(ir$v312)==16]<-'EC'
umethod[as.numeric(ir$v312) %in% c(6L,7L)]<-'Permanent methods'
uindex<-which(u & as.numeric(ir$v312) %in% modern)
current<-data.frame(woman=uindex,method=umethod[uindex],elapsed=dhs_current_duration(ir,uindex),wt=wt[uindex])
stopifnot(all(is.finite(current$elapsed)),all(current$elapsed>=0))
bins<-c(-1,3,6,12,24,36,48,60,Inf);blabel<-c('0–3','4–6','7–12','13–24','25–36','37–48','49–60','61+')
current$bin<-as.integer(cut(current$elapsed,bins))
# Reconstruct historical landmarks with an explicit year-end modern-use definition.
bywoman<-split(seq_len(nrow(cal)),cal$woman_row)
spells<-cal[cal$method_code %in% modern & cal$start>cal$calendar_start,]
records<-vector('list',nrow(spells))
for(i in seq_len(nrow(spells))){a<-spells[i,];last<-min(a$end,a$interview-15L);if(last<a$start)next
 t<-seq.int(a$start,last);future<-t+12L;timeline<-cal[bywoman[[as.character(a$woman_row)]],]
 code<-timeline$method_code[findInterval(future,timeline$start)]
 ended<-a$end<future & a$reason_code %in% action
 records[[i]]<-data.frame(woman=a$woman_row,episode=i,method=method_group(a$method_code),elapsed=t-a$start,wt=a$wt,
 cause=ifelse(ended,cause_group(a$reason_code),NA_integer_),net=ended & !code %in% endpoint_modern,
 net_legacy=ended & !code %in% modern, direct=ended & timeline$method_code[findInterval(a$end+1L,timeline$start)] %in% endpoint_modern)
}
land<-do.call(rbind,records);land$bin<-as.integer(cut(land$elapsed,bins))
# 61+ months has no direct complete-follow-up support; preserve documented proxy.
ci_index<-lapply(methods,function(m)which(current$method==m));names(ci_index)<-methods
land_index<-lapply(methods,function(m)lapply(1:8,function(b)which(land$method==m & land$bin %in% if(b==8)c(6,7)else b)));names(land_index)<-methods
# Fit data and fixed selected families (model-selection uncertainty is not included).
af<-e[e$entry==0 & e$exposure>0,];af$method<-factor(af$method_group,levels=methods)
af$action_event<-as.integer(af$discontinued & af$reason_code %in% action)
af$other_event<-as.integer(af$discontinued & !af$reason_code %in% action)
for(j in 1:5)af[[paste0('cause',j)]]<-as.integer(af$discontinued & af$reason_code %in% codes[[j]])
fam<-read.csv(file.path(sup,'nigeria_survival_model_duration_fit.csv'));cfam<-read.csv(file.path(sup,'nigeria_survival_model_cause_fit.csv'))
dists<-c(fam$distribution[fam$selected_actionable],fam$distribution[fam$selected_other],cfam$distribution[match(causes,cfam$cause)])
events<-c('action_event','other_event',paste0('cause',1:5));stopifnot(length(dists)==7,!anyNA(dists))
maxage<-max(current$elapsed)+12L;time<-0:maxage
cumhaz<-function(t,mu,sc,dist){
 if(dist=='weibull')return((t/exp(mu))^(1/sc))
 if(dist=='exponential')return(t/exp(mu))
 if(dist=='loglogistic')return(log1p(exp((log(t)-mu)/sc)))
 if(dist=='lognormal')return(-pnorm((log(t)-mu)/sc,lower.tail=FALSE,log.p=TRUE))
 stop('Unknown family')}
transition_index<-list();support<-list()
for(m in methods)for(b in 1:8)for(j in 1:5){
 z<-which(land$method==m & land$bin %in% (if(b==8)c(6,7)else b) & land$cause==j)
 # Use unique episodes, not repeated landmarks, to assess support.
 n<-length(unique(land$episode[z]));level<-'method × cause × duration'
 if(n<10){z<-which(land$method==m & land$cause==j);n<-length(unique(land$episode[z]));level<-'method × cause'}
 if(n<10){z<-which(land$cause==j);n<-length(unique(land$episode[z]));level<-'cause pooled over methods'}
 stopifnot(n>0);key<-paste(m,b,j,sep='|');transition_index[[key]]<-z
 support[[key]]<-data.frame(method=m,duration_bin=blabel[b],cause=causes[j],unique_episodes=n,unique_women=length(unique(land$woman[z])),landmarks=length(z),pooling=level)
}
write.csv(do.call(rbind,support),file.path(out,'switching_support.csv'),row.names=FALSE)
source(file.path(dirname(script_file),'transition_model.R'))
point_transitions<-fit_models(initial,follow,'selected',.1)
selected_transition_families<-vapply(point_transitions$transitions,`[[`,'','family')
write.csv(data.frame(initial_permanent_probability=attr(point_transitions$initial,'permanent_probability'),monthly_permanent_probability=point_transitions$permanent_monthly_probability,initial_permanent_histories=sum(as.character(initial$next_state)=='Permanent'),later_permanent_entries=sum(follow$permanent_entry),rule='Pooled weighted entry; permanent state absorbing through endpoint'),file.path(out,'permanent_transition_assumptions.csv'),row.names=FALSE)
jsonlite::write_json(list(selected_families=selected_transition_families,episodes=nrow(initial),women=length(unique(initial$woman)),transitions=nrow(follow)),file.path(out,'transition_fit_metadata.json'),auto_unbox=TRUE,pretty=TRUE)
pred_grid<-unique(data.frame(method=rep(methods,each=60*5),cause=rep(rep(causes,each=60),5),end_duration=rep(1:60,25)))
pred_grid<-normalize_features(pred_grid);pred_grid$gid<-seq_len(nrow(pred_grid))
measure<-function(mult,replicate=0L){
 old_dhs<-options(dhs.replication=replicate>0L);on.exit(options(old_dhs),add=TRUE)
 iw<-wt*mult[psu_index];ew<-e$wt*mult[psu_index[e$woman_row]];lw<-land$wt*mult[psu_index[land$woman]];cw<-current$wt*mult[psu_index[current$woman]]
 mcpr<-100*sum(iw[u])/sum(iw);mix<-vapply(c(methods,'EC','Permanent methods'),function(m)sum(iw[u & umethod==m])/sum(iw[u]),0.0)
 stock<-w24*mcpr/100*mix
 # Main gross estimates, year-end switching sensitivities, and direct-switch diagnostics.
 result<-array(0,c(9,5,5),dimnames=list(c('First-year gross','Historical gross','AFT gross','Historical switching','AFT switching','First-year direct switches','Historical direct switches','AFT direct switches','AFT modeled transitions'),methods,causes))
 risk<-result
 for(m in methods){d<-which(e$method_group==m);surv<-1;v<-numeric(5)
  for(t in 1:12){at<-d[e$entry[d]<t & e$exposure[d]>=t];den<-sum(ew[at]);if(den<=0)next
   end<-at[e$discontinued[at] & e$exposure[at]==t];h<-vapply(codes,function(cc)sum(ew[end[e$reason_code[end] %in% cc]])/den,0.0)
   v<-v+surv*h;surv<-surv*(1-sum(ew[end])/den)}
  risk[1,m,]<-v
  ends<-d[e$discontinued[d] & e$exposure[d]<=12 & e$reason_code[d] %in% action]
  raw<-vapply(1:5,function(j){ii<-ends[e$reason_code[ends] %in% codes[[j]]];den<-sum(ew[ii]);if(den>0)v[j]*sum(ew[ii][e$next_code[ii] %in% endpoint_modern])/den else 0},0)
  risk[6,m,]<-raw
  ix<-ci_index[[m]];cwtotal<-sum(cw[ix]);for(b in 1:8){share<-sum(cw[ix[current$bin[ix]==b]])/cwtotal;if(share==0)next
   z<-land_index[[m]][[b]];den<-sum(lw[z]);if(den<=0)stop('Empty landmark cell')
   for(j in 1:5){risk[2,m,j]<-risk[2,m,j]+share*sum(lw[z][!is.na(land$cause[z]) & land$cause[z]==j])/den
    risk[4,m,j]<-risk[4,m,j]+share*sum(lw[z][!is.na(land$cause[z]) & land$cause[z]==j & land$net[z]])/den
    risk[7,m,j]<-risk[7,m,j]+share*sum(lw[z][!is.na(land$cause[z]) & land$cause[z]==j & land$direct[z]])/den}}
 }
 aw<-af$wt*mult[psu_index[af$woman_row]]
 fits<-lapply(seq_along(events),function(j){ad<-af[aw>0,];ad$fw<-aw[aw>0];active<-methods[vapply(methods,function(m)sum(ad[[events[j]]][ad$method==m]),0)>0];ad<-ad[ad$method %in% active,];ad$method<-droplevels(ad$method);fit<-suppressWarnings(dhs_aft_fit(as.formula(paste0('Surv(exposure,',events[j],')~method')),data=ad,weights=fw,dist=dists[j],control=survreg.control(maxiter=500)));if(fit$iter>=500||any(!is.finite(coef(fit))))stop(paste('AFT convergence failure',events[j],dists[j]));attr(fit,'active_methods')<-active;fit})
 new_initial<-data.table::copy(initial);new_follow<-data.table::copy(follow)
 new_initial$wt<-new_initial$wt*mult[match(new_initial$psu,frame$psu)];new_follow$wt<-new_follow$wt*mult[match(new_follow$psu,frame$psu)]
 tm<-if(replicate==0L)point_transitions else list(initial=fit_initial(new_initial),permanent_monthly_probability=permanent_rate(new_follow),transitions=setNames(lapply(states,function(s)fit_transition(new_follow[new_follow$current_state==s,],s,selected_transition_families[s],.1,start=point_transitions$transitions[[s]]$par)),states))
 epred<-as.data.frame(endpoint_prob(tm,pred_grid,12L))
 lookup<-merge(as.data.frame(pred_grid)[,c('gid','method','cause','end_duration')],epred,by='gid')
 lookup$key<-paste(lookup$method,lookup$cause,lookup$end_duration,lookup$horizon,sep='|')
 for(m in methods){nd<-data.frame(method=factor(m,levels=methods));hh<-sapply(seq_along(fits),function(j){f<-fits[[j]];if(!m %in% attr(f,'active_methods'))return(rep(0,length(time)-1));mu<-as.numeric(predict(f,newdata=nd,type='lp'));diff(cumhaz(time,mu,f$scale,dists[j]))})
  ix<-ci_index[[m]];den<-sum(cw[ix]);for(age in unique(current$elapsed[ix])){z<-ix[current$elapsed[ix]==age];share<-sum(cw[z])/den;if(share==0)next
   h<-hh[age+1:12,,drop=FALSE];total<-h[,1]+h[,2];s<-c(1,exp(-cumsum(total)))[1:12];monthly<-s*(-expm1(-total))*ifelse(total>0,h[,1]/total,0)
   hcause<-pmax(h[,3:7,drop=FALSE],0);cs<-hcause/pmax(rowSums(hcause),1e-300);if(any(!is.finite(cs)))stop('Invalid cause split')
   v<-colSums(monthly*cs);risk[3,m,]<-risk[3,m,]+share*v
   for(j in 1:5){keys<-paste(m,causes[j],pmin(60,pmax(1,age+1:12)),13L-(1:12),sep='|');pm<-lookup$p_modern[match(keys,lookup$key)];stopifnot(!anyNA(pm));risk[9,m,j]<-risk[9,m,j]+share*sum(monthly*cs[,j]*(1-pm))}
   b<-as.integer(cut(age,bins));for(j in 1:5){q<-transition_index[[paste(m,b,j,sep='|')]];fraction<-sum(lw[q]*land$net[q])/sum(lw[q]);risk[5,m,j]<-risk[5,m,j]+share*v[j]*fraction;risk[8,m,j]<-risk[8,m,j]+share*v[j]*sum(lw[q]*land$direct[q])/sum(lw[q])}}
 }
 for(m in methods)result[,m,]<-risk[,m,]*stock[m]
 stopifnot(all(is.finite(result)),all(result>=0),all(apply(risk,c(1,2),sum)<=1+1e-8))
 list(counts=result,risk=risk,mcpr=mcpr,mix=mix,stock=stock,users2024=w24*mcpr/100*mix)
}
write.csv(data.frame(firstyear_reversible_episodes=nrow(e),aft_known_start_reversible_episodes=nrow(af),current_reversible_users=nrow(current),historical_landmarks=nrow(land)),file.path(out,'planning_sample_support.csv'),row.names=FALSE)
point<-measure(rep(1,nrow(frame)));saveRDS(point,file.path(out,'planning_point.rds'))
write.csv(data.frame(method='Permanent methods',current_users=sum(wt[u & as.numeric(ir$v312) %in% c(6L,7L)])/sum(wt)*w24,probability='Not modeled: permanent method',potentially_actionable_users_retained=0),file.path(out,'permanent_method_stock.csv'),row.names=FALSE)

# Reversible-risk stock is a domain of all modern users, not a renormalized mix.
stopifnot(!any(current$woman %in% which(as.numeric(ir$v312) %in% c(6L,7L))))
saveRDS(point_transitions,file.path(out,'transition_point_fits.rds'))
cat('Point totals:',apply(point$counts,1,sum),'\n');flush.console()
checkpoint<-file.path(out,'replicates');dir.create(checkpoint,showWarnings=FALSE)
one<-function(b){dest<-file.path(checkpoint,sprintf('rep_%04d.rds',b));if(file.exists(dest))return(readRDS(dest));set.seed(20261105L+b)
 mult<-numeric(nrow(frame));for(ids in strata){n<-length(ids);mult[ids]<-n/(n-1)*tabulate(sample.int(n,n-1,replace=TRUE),nbins=n)}
 v<-tryCatch(measure(mult,b),error=function(e)list(error=conditionMessage(e)));saveRDS(v,dest);v}
if(B>0){draws<-parallel::mclapply(seq_len(B),one,mc.cores=cores,mc.preschedule=FALSE);valid<-!vapply(draws,function(x)!is.null(x$error),FALSE)
 cat('Valid',sum(valid),'of',B,'\n');stopifnot(mean(valid)>=.95);saveRDS(draws,file.path(out,'planning_replicates.rds'))}
saveRDS(list(country='Nigeria',reference_year=2024,outcome_year=2025,wra2024=w24,wra2025=w25,wra2026=w26,psus=nrow(frame),strata=length(strata),replicates=B,methods=methods,causes=causes,definitions=c('Gross: every actionable original-method ending treated as year-end loss','Switching sensitivity: EC included in modern use at year end; support assessed on unique episodes','AFT uncertainty conditional on selected distribution families','Population and growth scenarios fixed')),file.path(out,'planning_metadata.rds'))
)----------------------")

MODULES[["transition_model.R"]] <- list(language="R", packaged_sha256="2c24064909a2a85cfcbc4b610f173d90530a572bff2ff5f3c94f8e7bbbcf2a67", args=character(0), code=r"----------------------(# DHS complex survey design for this module.
.dhs_root <- Sys.getenv('NIGERIA_PROJECT_ROOT')
if (!nzchar(.dhs_root)) {
 .dhs_file <- sub('^--file=','',grep('^--file=',commandArgs(FALSE),value=TRUE)[1])
 .dhs_root <- dirname(dirname(normalizePath(.dhs_file)))
}
source(file.path(.dhs_root,'Code','dhs_survey_tools.R'),local=TRUE)
dhs_set_context(country='Nigeria',root=.dhs_root)
suppressPackageStartupMessages({library(data.table);library(nnet);library(splines)})
setDTthreads(1)
states <- c('Modern','Nonmodern','Pregnancy-related')
state <- function(z) ifelse(z %in% c(6L,7L),'Permanent',ifelse(z %in% endpoint_modern,states[1],ifelse(z %in% 81:83,states[3],states[2])))
normalize_features <- function(d) {
 d$method <- factor(d$method,levels=methods);d$cause <- factor(d$cause,levels=causes)
 d$end_duration <- pmin(60,pmax(1,d$end_duration));d$duration_log <- log1p(d$end_duration)
 d
}
wt <- as.numeric(ir$v005)/1e6
cal<-as.data.table(cal)
setorder(cal,woman_row,start)
bywoman <- split(seq_len(nrow(cal)),cal$woman_row)
endings <- cal[method_code %in% modern & start>calendar_start & reason_code %in% action & end<=interview-4 & end>=interview-62]
initial <- vector('list',nrow(endings)); follow <- vector('list',nrow(endings)); histories <- vector('list',nrow(endings))
for(i in seq_len(nrow(endings))) {
 ev <- endings[i]; tl <- cal[bywoman[[as.character(ev$woman_row)]]]
 h <- min(12L,as.integer(ev$interview-3-ev$end));stopifnot(h>=1L)
 times <- ev$end+seq_len(h);ix<-findInterval(times,tl$start)
 stopifnot(all(ix>0),all(tl$end[ix]>=times))
 st <- state(tl$method_code[ix]);run <- sequence(rle(st)$lengths)
 base <- data.table(episode=i,woman=ev$woman_row,psu=as.integer(ir$v021[ev$woman_row]),stratum=as.integer(ir$v022[ev$woman_row]),
                    method=method_group(ev$method_code),cause=causes[cause_group(ev$reason_code)],end_duration=ev$duration,wt=ev$wt)
 initial[[i]] <- cbind(base,data.table(next_state=st[1]))
 histories[[i]] <- cbind(base,data.table(horizon=seq_len(h),observed_state=st))
 if(h>1) {
  first_permanent<-match('Permanent',st,nomatch=h+1L)
  risk_months<-seq_len(h-1L);risk_months<-risk_months[risk_months<first_permanent]
  if(length(risk_months))follow[[i]] <- cbind(base,data.table(current_state=st[risk_months],
    state_duration=run[risk_months],post_month=risk_months,next_state=st[risk_months+1L],
    permanent_entry=st[risk_months+1L]=='Permanent'))
 }
}
initial <- normalize_features(rbindlist(initial));follow <- normalize_features(rbindlist(follow));histories <- normalize_features(rbindlist(histories))
initial$next_state <- factor(initial$next_state,levels=c(states,'Permanent'));follow$next_state <- factor(follow$next_state,levels=c(states,'Permanent'))
cat('SUPPORT',nrow(initial),'original endings;',uniqueN(initial$woman),'women;',nrow(follow),'post-ending transitions\n');flush.console()
write.csv(initial[,.(episodes=.N,women=uniqueN(woman)),by=.(method,cause)],file.path(out,'support_by_method_cause.csv'),row.names=FALSE)
write.csv(follow[,.(transitions=.N,episodes=uniqueN(episode)),by=.(current_state,next_state)],file.path(out,'transition_support.csv'),row.names=FALSE)
write.csv(histories[,.(episodes=.N,women=uniqueN(woman),weighted_modern=sum(wt*(observed_state%in%c('Modern','Permanent')))/sum(wt)),by=horizon],file.path(out,'observed_post_ending_status.csv'),row.names=FALSE)

# Positive waiting times use AFT-derived, clock-reset competing hazards.
# Immediate post-ending status has a separate categorical distribution because
# direct switches have no non-use waiting time.
# These pooled entries avoid fitting method/cause-specific sterilization effects
# from only a few observations. Post-entry use is absorbing in predictions.
pooled_permanent_probability <- function(d,indicator) {
 frame<-dhs_context()$frame
 records<-data.frame(wt=d$wt,cluster=d$psu,stratum=d$stratum)
 design<-dhs_design(records,frame)
 unname(dhs_percentage(design,as.numeric(indicator))['percent']/100)
}
permanent_rate <- function(d) {
 stopifnot(nrow(d)>0L,sum(d$wt)>0)
 pooled_permanent_probability(d,d$permanent_entry)
}
fit_initial <- function(d,decay=.1) {
 permanent_probability<-pooled_permanent_probability(d,as.character(d$next_state)=='Permanent')
 d<-data.table::copy(d[as.character(d$next_state)!='Permanent',])
 d$next_state<-factor(d$next_state,levels=states)
 d$fw<-d$wt/mean(d$wt)
 f<-dhs_multinom_fit(next_state~method+cause+ns(duration_log,df=2),data=d,weights=fw,
             decay=decay,maxit=1000,MaxNWts=5000,trace=FALSE,abstol=1e-8,reltol=1e-9)
 stopifnot(f$convergence==0);attr(f,'permanent_probability')<-permanent_probability;f
}
initial_probs <- function(f,d) {
 p<-predict(f,newdata=d,type='probs');if(is.null(dim(p)))p<-matrix(p,nrow=nrow(d),byrow=TRUE)
 if(is.null(colnames(p)))colnames(p)<-f$lev
 ans<-matrix(0,nrow(d),length(states),dimnames=list(NULL,states));ans[,colnames(p)]<-p;ans
}
design <- function(d) {
 d<-normalize_features(as.data.frame(d))
 if(!'entry_month'%in%names(d))d$entry_month<-d$post_month-d$state_duration+1
 d$entry_log<-log1p(pmax(1,d$entry_month))
 model.matrix(~method+cause+duration_log+entry_log,data=d)
}

# H and analytic derivatives under lognormal, Weibull, or log-logistic AFT.
H_derivatives <- function(t,mu,log_scale,family) {
 sc<-exp(log_scale);H<-dm<-ds<-numeric(length(mu));ok<-t>0
 z<-(log(t[ok])-mu[ok])/sc
 if(family=='lognormal') {
  logQ<-pnorm(z,lower.tail=FALSE,log.p=TRUE);m<-exp(dnorm(z,log=TRUE)-logQ)
  H[ok]<- -logQ;dm[ok]<- -m/sc;ds[ok]<- -m*z
 }else if(family=='weibull') {
  hz<-exp(pmin(z,650));H[ok]<-hz;dm[ok]<- -hz/sc;ds[ok]<- -hz*z
 }else if(family=='loglogistic') {
  H[ok]<-pmax(z,0)+log1p(exp(-abs(z)));dm[ok]<- -plogis(z)/sc;ds[ok]<- -plogis(z)*z
 }else stop('Unknown AFT transition family')
 list(H=H,mu=dm,scale=ds)
}
increment <- function(t,mu,ls,family) {
 hi<-H_derivatives(t,mu,ls,family);lo<-H_derivatives(t-1,mu,ls,family)
 list(h=pmax(hi$H-lo$H,1e-14),mu=hi$mu-lo$mu,scale=hi$scale-lo$scale)
}
fit_transition <- function(d,from,family='lognormal',ridge=.1,start=NULL,check_gradient=FALSE) {
 # Conditional transient-state model; permanent entries use the pooled branch.
 d<-d[!d$permanent_entry,]
 d$next_state<-factor(d$next_state,levels=states)
 X<-design(d);p<-ncol(X);dest<-setdiff(states,from)
 y<-match(as.character(d$next_state),dest);y[is.na(y)]<-0L
 w<-d$wt/mean(d$wt);duration<-as.numeric(d$state_duration)
 objective<-function(par,gradient=FALSE) {
  b1<-par[seq_len(p)];ls1<-par[p+1L];b2<-par[p+1L+seq_len(p)];ls2<-par[2L*(p+1L)]
  d1<-increment(duration,as.numeric(X%*%b1),ls1,family)
  d2<-increment(duration,as.numeric(X%*%b2),ls2,family)
  ht<-d1$h+d2$h;stay<-y==0L;exit<-!stay
  lp<- -ht
  if(any(exit))lp[exit]<-log(-expm1(-ht[exit]))+log(ifelse(y[exit]==1L,d1$h[exit],d2$h[exit]))-log(ht[exit])
  penalized<-c(2:p,(p+1L)+(2:p))
  scale_indices<-c(p+1L,2L*(p+1L))
  if(!gradient)return(-sum(w*lp)+ridge/2*sum(par[penalized]^2)+.001/2*sum(par[scale_indices]^2))
  common<-numeric(length(ht));small<-ht<1e-5
  common[small]<- -.5+ht[small]/12-ht[small]^3/720
  common[!small]<-1/expm1(pmin(ht[!small],700))-1/ht[!small]
  g1<-ifelse(stay,-1,common+as.numeric(y==1L)/d1$h)
  g2<-ifelse(stay,-1,common+as.numeric(y==2L)/d2$h)
  g<- -c(as.numeric(crossprod(X,w*g1*d1$mu)),sum(w*g1*d1$scale),
            as.numeric(crossprod(X,w*g2*d2$mu)),sum(w*g2*d2$scale))
  g[penalized]<-g[penalized]+ridge*par[penalized]
  g[scale_indices]<-g[scale_indices]+.001*par[scale_indices]
  g
 }
 par<-numeric(2L*(p+1L))
 for(j in 1:2) {
  rate<-max(.002,sum(w*(y==j))/sum(w));h<- -log1p(-min(.8,rate))
  mu<-if(family=='lognormal')-qnorm(-expm1(-h))else if(family=='weibull')-log(h)else -log(expm1(h))
  par[(j-1L)*(p+1L)+1L]<-mu
 }
 lower<-rep(-25,length(par));upper<-rep(25,length(par))
 lower[c(p+1L,2L*(p+1L))]<- -2.5;upper[c(p+1L,2L*(p+1L))]<-2.5
 if(!is.null(start))par<-start
 fit<-optim(par,objective,function(p)objective(p,TRUE),method='L-BFGS-B',lower=lower,upper=upper,
             control=list(maxit=2000,factr=1e6,pgtol=1e-5))
 stopifnot(fit$convergence==0,all(is.finite(fit$par)))
 # Numerical gradient check at the optimum prevents silent score errors.
 delta<-1e-5
 numerical<-if(check_gradient)vapply(seq_along(fit$par),function(i){hi<-lo<-fit$par;hi[i]<-hi[i]+delta;lo[i]<-lo[i]-delta;(objective(hi)-objective(lo))/(2*delta)},0.0)else objective(fit$par,TRUE)
 analytic<-objective(fit$par,TRUE)
 stopifnot(max(abs(analytic-numerical))<.02)
 penalty_indices<-c(2:p,(p+1L)+(2:p));scale_indices<-c(p+1L,2L*(p+1L))
 unpenalized_nll<-fit$value-ridge/2*sum(fit$par[penalty_indices]^2)-.001/2*sum(fit$par[scale_indices]^2)
 list(par=fit$par,p=p,columns=colnames(X),dest=dest,from=from,family=family,
      pseudo_aic=2*unpenalized_nll+2*length(fit$par),
      objective=fit$value,max_gradient_error=max(abs(analytic-numerical)),convergence=fit$convergence,
      boundary=any(abs(fit$par-lower)<1e-4|abs(fit$par-upper)<1e-4))
}
fit_models <- function(init,trans,family='lognormal',ridge=.1) {
 transitions<-setNames(lapply(states,function(s) {
  families<-if(family=='selected')c('lognormal','weibull','loglogistic')else family
  ff<-lapply(families,function(f)fit_transition(trans[trans$current_state==s,],s,f,ridge))
  ff[[which.min(vapply(ff,`[[`,0.0,'pseudo_aic'))]]
 }),states)
 list(initial=fit_initial(init),transitions=transitions,family=family,ridge=ridge,permanent_monthly_probability=permanent_rate(trans))
}
transition_probs <- function(fit,d) {
 X<-design(d);stopifnot(identical(colnames(X),fit$columns));p<-fit$p;par<-fit$par
 h1<-increment(d$state_duration,as.numeric(X%*%par[seq_len(p)]),par[p+1L],fit$family)$h
 h2<-increment(d$state_duration,as.numeric(X%*%par[p+1L+seq_len(p)]),par[2L*(p+1L)],fit$family)$h
 total<-h1+h2;ans<-matrix(0,nrow(d),3,dimnames=list(NULL,states))
 ans[,fit$from]<-exp(-total);ans[,fit$dest[1]]<- -expm1(-total)*h1/total;ans[,fit$dest[2]]<- -expm1(-total)*h2/total
 stopifnot(all(is.finite(ans)),max(abs(rowSums(ans)-1))<1e-8);ans
}
# Integrate transient AFT transitions and a separate absorbing permanent state.
# Sparse permanent uptake uses pooled weighted one-month entry probabilities.
endpoint_prob <- function(models,gr,max_horizon=13L) {
 stopifnot(max_horizon>=1L,nrow(gr)>0L)
 n<-nrow(gr);K<-length(states);p0<-initial_probs(models$initial,gr)
 q0<-attr(models$initial,'permanent_probability');if(is.null(q0))stop('Missing permanent-entry probability.')
 q<-models$permanent_monthly_probability;if(is.null(q))stop('Missing permanent monthly-entry probability.')
 stopifnot(length(q0)==1L,length(q)==1L,is.finite(q0),is.finite(q),q0>=0,q0<=1,q>=0,q<=1)
 permanent<-rep(q0,n);nodes<-array(0,c(n,K,max_horizon));nodes[,,1L]<-(1-q0)*p0
 outputs<-list(data.table(gid=gr$gid,horizon=1L,p_modern=permanent+nodes[,match('Modern',states),1L],p_permanent=permanent))
 if(max_horizon==1L)return(outputs[[1L]])
 tmp<-as.data.frame(gr);tmp$state_duration<-1;tmp$post_month<-1
 cache<-lapply(states,function(s){
  f<-models$transitions[[s]]
  X<-if('from'%in%names(formals(design)))design(tmp,from=s)else design(tmp)
  stopifnot(identical(colnames(X),f$columns));entry<-match('entry_log',colnames(X))
  b1<-f$par[seq_len(f$p)];b2<-f$par[f$p+1L+seq_len(f$p)]
  e1<-e2<-0;if(!is.na(entry)){e1<-b1[entry];e2<-b2[entry];X[,entry]<-0}
  list(mu1=as.numeric(X%*%b1),mu2=as.numeric(X%*%b2),e1=e1,e2=e2,
       scale1=f$par[f$p+1L],scale2=f$par[2L*(f$p+1L)],family=f$family,dest=match(f$dest,states))
 })
 for(k in 2:max_horizon){
  permanent_before<-permanent;permanent<-permanent+q*rowSums(nodes,dims=1)
  nextnodes<-array(0,c(n,K,max_horizon))
  for(s in seq_len(K))for(d in seq_len(k-1L)){
   mass<-(1-q)*nodes[,s,d];if(!any(mass>0))next
   f<-cache[[s]];entrylog<-log1p(k-d)
   h1<-increment(rep(d,n),f$mu1+f$e1*entrylog,f$scale1,f$family)$h
   h2<-increment(rep(d,n),f$mu2+f$e2*entrylog,f$scale2,f$family)$h
   total<-h1+h2;exit<- -expm1(-total)
   nextnodes[,s,d+1L]<-nextnodes[,s,d+1L]+mass*exp(-total)
   nextnodes[,f$dest[1],1L]<-nextnodes[,f$dest[1],1L]+mass*exit*h1/total
   nextnodes[,f$dest[2],1L]<-nextnodes[,f$dest[2],1L]+mass*exit*h2/total
  }
  nodes<-nextnodes
  stopifnot(all(is.finite(nodes)),max(abs(rowSums(nodes,dims=1)+permanent-1))<1e-8,
            all(permanent>=permanent_before-1e-12))
  outputs[[k]]<-data.table(gid=gr$gid,horizon=k,p_modern=permanent+rowSums(nodes[,match('Modern',states),,drop=FALSE],dims=1),p_permanent=permanent)
 }
 rbindlist(outputs,use.names=TRUE)
}
)----------------------")

MODULES[["wording.py"]] <- list(language="Python", packaged_sha256="9bf8827d0ccd8c561ffa452558899149068b69611eda7c94c6e4b059abf326a8", args=character(0), code=r"----------------------("""Plain-language explanations for Nigeria's 2024-to-2025 planning tables."""
import copy
LABELS={1:'Exploratory',2:'Historical',3:'AFT',4:'Historical switching',5:'AFT observed switching',12:'AFT modeled switching'}
PROB={
1:'Applies each method’s probability of an actionable ending in months 1–12 after starting to all current users of that method. It ignores how long they have already used it. Counts assume every actionable ending leaves the woman outside modern use at the 12-month endpoint. Switching and restarting are excluded.',
2:'Uses observed calendar histories to estimate an actionable ending over the next 12 months for users of the same method and a similar time already used. Counts assume every ending is a loss from modern use. Switching and restarting are excluded. Users already at 61+ months use the observed 37–60-month experience.',
3:'Uses fitted survival curves to estimate an actionable ending over the next 12 months, given the current method and months already used. Other reasons for ending the method remain competing events. Counts assume every actionable ending is a loss from modern use. Switching and restarting are excluded.',
4:'Uses observed calendar histories matched to the current method and time already used. Counts include women who end for an actionable reason and are outside modern use at the end of the next 12 months. Women using any modern method at that endpoint are deducted, including switchers and restarters. Users at 61+ months use 37–60-month experience.',
5:'AFT survival curves estimate the actionable ending of the original method. Observed calendar histories estimate how many would be outside modern use at the end of the next 12 months. The calculation subtracts women using any modern method at that endpoint, including switchers and restarters. Sparse history groups are pooled.',
12:'AFT survival curves estimate the actionable ending of the original method. A separate model estimates immediate switching. AFT-based transitions then track later use or non-use, including restarting and stopping again. Counts include only women outside modern use at the end of the next 12 months. Permanent methods are an absorbing destination; sparse uptake uses pooled observed probabilities.'}
DENOM='mCPR contribution (pp) = users retained ÷ 57,393,553 women aged 15–49 in 2025 × 100.'
GROWTH='Starts from the 2024 DHS all-women mCPR. Annual changes are (2024−2018)/6 for the recent DHS trend and (2024−2013)/11 for the longer trend. The FPET-informed scenario adds 0.40 pp to the DHS baseline. It is an assumed increment, not an official FPET forecast for 2025. The same observed 2024 user cohort applies across scenarios.'
SCEN=['6-year DHS trend','11-year DHS trend','FPET-informed growth']
def revise(old,deck=True):
 s=copy.deepcopy(old);a=s['approach'];kind=s['kind'];label=LABELS[a];sens=a in [4,5,12]
 if kind=='method':title=f'{label}: '+('users outside modern use at 12 months'if sens else'users who may discontinue for actionable reasons')
 elif kind=='cause':title=f'{label}: '+('year-end losses by method and cause'if sens else'actionable discontinuation by method and cause')
 elif kind=='cause_pp':title=f'{label}: mCPR contribution by actionable cause'
 elif kind=='baseline':title=f'{label}: assumptions for 2025 mCPR'
 elif kind=='scenario':title=f'{label}: 2025 mCPR if '+('year-end losses are avoided'if sens else'actionable discontinuation is averted')
 elif kind=='method_scenario':title=f'{label}: users and mCPR under '+SCEN[s['scenario']-1]
 else:raise ValueError(kind)
 s['title']=title;units='Users in thousands'if deck else'Number of users (95% CI)'
 if kind=='baseline':s['subtitle']='2024 survey baseline and a one-year projection to 2025'
 elif a==1:s['subtitle']='Exploratory estimate. Ignores time already using the method. '+units
 elif sens:s['subtitle']='Deducts women using any modern method at the 12-month endpoint. '+units
 else:s['subtitle']='Next 12 months, accounting for time already using the method. '+units
 note=GROWTH if kind=='baseline'else PROB[a]
 if a==1 and kind=='method':note+=' The total uses the current-user method mix. The pooled episode estimate is 21.4%.'
 if sens and kind=='method':note+=' The probability column describes the original method ending. The loss count also deducts modern use at the endpoint.'
 if kind in ['method','scenario','method_scenario','cause_pp']:note+=' '+DENOM
 if kind=='method_scenario':note+=' The usual scenario keeps the current method mix.'
 note+=' Partner/spousal disapproval is excluded.'
 note+=(' Estimates use DHS survey weights. Population and growth assumptions stay fixed.'if deck else' 95% CIs use 500 survey bootstrap samples. Population and growth assumptions stay fixed. Confidence limits do not add across cells. † No events observed, so no reliable CI.')
 if a in [3,5,12]:note+=(' Fits use the selected survival distributions.'if deck else' AFT intervals hold the selected curve families fixed.')+' Some method/cause estimates rely on very few events.'
 note+=' Permanent current users remain in mCPR. They receive no modeled stopping probability or retention gain; Other modern contains reversible methods only.'
 s['note']=note;return s
)----------------------")

MODULES[["05_render_nigeria_html.py"]] <- list(language="Python", packaged_sha256="4201bbe7a80ec0bf59f834f41306ce5bedf4ee5de514a7aa785dcd1d2b483496", args=character(0), code=r"----------------------(#!/usr/bin/env python3
"""Render the Nigeria working HTML from the complete saved analysis tables.

Run after the R pipeline. This file contains only layout and wording. All
reported estimates come from saved data tables, so the visuals are repeatable.
"""
import csv
import html
import re
from pathlib import Path
import os

ROOT = Path(os.environ["NIGERIA_PROJECT_ROOT"])
SUP = ROOT / 'output/Supporting_data'
OUT = ROOT / 'output/Nigeria_discontinuation_analysis.html'

def read(name):
    with (SUP / name).open(newline='') as f:
        return list(csv.DictReader(f))

def f(x, n=1):
    try: return f'{float(x):.{n}f}'
    except (ValueError, TypeError): return '—'

def integer(x):
    try: return f'{float(x):,.0f}'
    except (ValueError, TypeError): return '—'

def h(x): return html.escape(str(x))

table7 = read('nigeria_table_7_12_replicated.csv')
table713 = read('nigeria_published_table_7_13_reason_distribution.csv')
modern_five_year_reasons = read('nigeria_modern_five_year_reason_distribution_seven.csv')
modern_five_year_by_method = read('nigeria_modern_five_year_reason_distribution.csv')
initiation = read('nigeria_initiation_mix_overall_by_year.csv')
all_times = read('nigeria_modern_all_reason_timepoints.csv')
all_reasons = read('nigeria_modern_all_reason_reason_mix.csv')
all_models = read('nigeria_all_reason_zone_models.csv')
all_subgroups = read('nigeria_all_reason_adjusted_subgroups.csv')
selected_models = read('nigeria_selected_reason_zone_models.csv')
selected_subgroups = read('nigeria_selected_reason_adjusted_subgroups.csv')
times = read('nigeria_actionable_timepoints.csv')
reasons = read('nigeria_actionable_reason_mix.csv')
mix = read('nigeria_zone_modern_method_start_mix.csv')
all_start_mix = read('nigeria_zone_all_method_start_mix.csv')
current = read('nigeria_current_use_mcpr.csv')
models = read('nigeria_actionable_zone_adjusted_rates.csv')
coef = read('nigeria_actionable_zone_model_odds_ratios.csv')
subgroups = read('nigeria_actionable_subgroup_rates_reasons.csv') if (SUP/'nigeria_actionable_subgroup_rates_reasons.csv').exists() else []
tests = read('nigeria_zone_pairwise_three_stages.csv') if (SUP/'nigeria_zone_pairwise_three_stages.csv').exists() else []
wra = read('nigeria_wpp2024_wra_2024_2026.csv')
users = read('nigeria_current_users_by_method_and_actionable_projection.csv')
user_causes = read('nigeria_current_users_actionable_by_cause.csv')
all_users = read('nigeria_current_users_all_reason_projection.csv')
all_user_causes = read('nigeria_current_users_all_reason_by_cause.csv')
switch = read('nigeria_actionable_immediate_modern_switch_share.csv')
scenarios = read('nigeria_2026_mcpr_scenarios.csv')
pathways = read('nigeria_actionable_post_ending_pathways.csv')
selected_pathways = read('nigeria_selected_reason_post_ending_pathways.csv')
transitions = read('nigeria_actionable_post_ending_transitions.csv')
switch_bridge = read('nigeria_switch_bridge_by_method.csv')
switch_bridge_cause = read('nigeria_switch_bridge_by_method_cause.csv')
duration_bridge = read('nigeria_duration_aware_current_user_bridge.csv')
duration_bridge_cause = read('nigeria_duration_aware_current_user_by_cause.csv')
duration_scenarios = read('nigeria_switch_duration_mcpr_scenarios.csv')
duration_sensitivity = read('nigeria_duration_61plus_sensitivity.csv')
zones = ['National','North West','North East','North Central','South East','South South','South West']
methods = ['Injectables','Implants','Pill','IUD','Other modern']
start_methods = ['Injectables','Implants','Pill','IUD','Emergency contraception','Other modern','Non-modern methods']
cause_names = ['Method failure','Wanted more effective method','Changes in menstrual bleeding','Other side effects/health','Access/cost/convenience']
colors = {'Injectables':'#108B8D','Implants':'#153F5B','Pill':'#DA9A25','IUD':'#D45A49','Emergency contraception':'#B65F8C','Other modern':'#85909D','Non-modern methods':'#A48865'}

def times_row(scope,month=12):
    return next(r for r in times if r['scope']==scope and int(r['month'])==month)

def all_times_row(scope,month=12):
    return next(r for r in all_times if r['scope']==scope and int(r['month'])==month)

def all_reason_row(scope,reason):
    return next(r for r in all_reasons if r['scope']==scope and r['reason']==reason)

def mix_row(zone,method):
    return next(r for r in mix if r['scope']==zone and r['method']==method)

def all_start_row(zone,method):
    return next(r for r in all_start_mix if r['scope']==zone and r['method']==method)

def reason_row(scope,name):
    return next(r for r in reasons if r['scope']==scope and r['reason']==name)

def td(x,cl=''):
    return f'<td class="{cl}">{x}</td>'

def th(x): return f'<th>{h(x)}</th>'

def section(id,title,eyebrow='',text=''):
    return f'<section id="{id}"><div class="eyebrow">{h(eyebrow)}</div><h2>{h(title)}</h2><p class="intro">{text}</p>'

def bar(value,color,widthscale=100):
    width=min(100,max(0,float(value)/widthscale*100))
    return f'<div class="bartrack"><span style="width:{width:.2f}%;background:{color}"></span></div>'

def rangebar(point,lo,hi,maxx=40,color='#108d94'):
    p=float(point);lo=float(lo);hi=float(hi)
    left=max(0,min(100,lo/maxx*100));right=max(0,min(100,hi/maxx*100))
    pos=max(0,min(100,p/maxx*100))
    return (f'<div class="rangebar"><i style="left:{left:.2f}%;width:{right-left:.2f}%;background:{color}"></i>'
            f'<b style="left:{pos:.2f}%;background:{color}"></b></div>')

def dual_rangebar(raw,raw_lo,raw_hi,adjusted,adjusted_lo,adjusted_hi,maxx=40):
    def item(point,lo,hi,color,top):
        x=lambda v:max(0,min(100,float(v)/maxx*100))
        left=x(lo);right=x(hi);pos=x(point)
        return (f'<i style="left:{left:.2f}%;width:{right-left:.2f}%;top:{top}px;background:{color}"></i>'
                f'<b style="left:{pos:.2f}%;top:{top-3}px;background:{color}"></b>')
    return '<div class="dualplot">'+item(raw,raw_lo,raw_hi,'#DA9A25',8)+item(adjusted,adjusted_lo,adjusted_hi,'#153F5B',20)+'</div>'

def heat_cell(value,national=False):
    x=float(value)
    # Accessible single-hue teal scale; national uses the presentation gold.
    light=95-55*x/55
    if national: bg=f'hsl(38 76% {min(94,max(57,light+7)):.0f}%)'
    else: bg=f'hsl(184 42% {max(40,min(96,light)):.0f}%)'
    return f'<td class="heat" style="background:{bg}">{f(x)}%</td>'

parts=[]
parts.append('''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Nigeria DHS 2024 | Contraceptive discontinuation</title>
<style>
:root{--navy:#153F5B;--teal:#108B8D;--gold:#DA9A25;--ink:#17222C;--line:#D6E2E5;--light:#F5F8F9}
*{box-sizing:border-box}html{scroll-behavior:smooth}body{margin:0;color:var(--ink);font:16px/1.48 Arial,Helvetica,sans-serif;background:#fff}
aside{position:fixed;inset:0 auto 0 0;width:254px;overflow:auto;background:#f5f8f9;border-right:1px solid var(--line);padding:26px 17px;z-index:5}
aside strong{font:700 19px Georgia,serif;color:var(--navy)}aside small{display:block;color:#617783;margin:4px 0 22px}
aside a{display:block;text-decoration:none;color:#335366;font-size:13px;padding:7px 8px;border-radius:4px}aside a:hover{background:#e5f1f2;color:#085f66}
main{margin-left:254px;padding:0 38px 90px;max-width:1580px}header{padding:48px 0 25px;border-bottom:3px solid var(--navy)}
header h1,h2{font-family:Georgia,serif;color:var(--navy);line-height:1.13}header h1{font-size:37px;margin:7px 0 10px}header p{max-width:850px;margin:0;color:#445b68}
section{padding:38px 0 18px;border-bottom:1px solid var(--line);scroll-margin-top:10px}.eyebrow{color:#8b641f;font-size:12px;font-weight:700;letter-spacing:.09em;text-transform:uppercase}
h2{font-size:29px;margin:5px 0 9px}h3{font-size:20px;color:var(--navy);margin:25px 0 8px}.intro{max-width:1050px;margin:0 0 20px}
.metrics{display:flex;gap:32px;flex-wrap:wrap;margin:18px 0 22px}.metric strong{display:block;color:var(--navy);font:700 33px Georgia,serif}.metric span{font-size:13px;color:#526774}
.note{background:#f1f6f7;border-left:4px solid var(--teal);padding:12px 16px;margin:16px 0;font-size:14px}.goldnote{background:#fff7e8;border-color:var(--gold)}
.tablewrap{overflow-x:auto}table{border-collapse:collapse;width:100%;font-size:13px}th{text-align:left;color:var(--navy);border-bottom:2px solid var(--navy);padding:9px 8px;white-space:nowrap}td{border-bottom:1px solid #e3eaed;padding:8px}tbody tr:nth-child(even){background:#fbfcfc}.num{text-align:right;font-variant-numeric:tabular-nums}.small{font-size:12px;color:#5c6f78}.heat{text-align:center;font-variant-numeric:tabular-nums;color:#172e38;min-width:112px;border:2px solid white}
.pairchart{max-width:1000px}.pairrow{display:grid;grid-template-columns:145px 1fr 46px;align-items:center;gap:10px;margin:10px 0}.pairrow label{text-align:right}.pairrow .two{display:grid;gap:3px}.pairrow .two .sub{display:grid;grid-template-columns:110px 1fr 48px;align-items:center;gap:6px;font-size:12px}.bartrack{height:12px;background:#eef3f5;position:relative}.bartrack span{display:block;height:100%}.pairrow strong{font-size:13px}
.zonebars{max-width:930px}.zonebar{display:grid;grid-template-columns:125px 1fr;gap:12px;align-items:center;margin:10px 0}.stack{height:27px;display:flex;width:100%;background:#e7eef0}.stack span{height:100%}.legend{display:flex;flex-wrap:wrap;gap:14px;margin:12px 0 4px;font-size:13px}.legend span:before{content:'';display:inline-block;width:12px;height:12px;background:var(--c);margin-right:5px;vertical-align:-1px}
.forestrow{display:grid;grid-template-columns:133px minmax(220px,610px) 165px;gap:12px;align-items:center;margin:11px 0}.forestrow label{text-align:right}.rangebar{position:relative;height:20px;border-bottom:1px solid #cfdee3;background:repeating-linear-gradient(90deg,transparent 0,transparent calc(25% - 1px),#ecf1f3 calc(25% - 1px),#ecf1f3 25%)}.rangebar i{position:absolute;height:3px;top:9px}.rangebar b{position:absolute;width:9px;height:9px;border-radius:50%;top:6px;transform:translateX(-50%)}
.dualrow{display:grid;grid-template-columns:133px minmax(220px,610px) 105px 105px;gap:12px;align-items:center;margin:11px 0;font-variant-numeric:tabular-nums}.dualrow label{text-align:right}.dualrow.national{background:#F0F4F5}.dualplot{position:relative;height:30px;border-bottom:1px solid #cfdee3;background:repeating-linear-gradient(90deg,transparent 0,transparent calc(25% - 1px),#ecf1f3 calc(25% - 1px),#ecf1f3 25%)}.dualplot i{position:absolute;height:2px}.dualplot b{position:absolute;width:9px;height:9px;border-radius:50%;transform:translateX(-50%)}
.grid2{display:grid;grid-template-columns:1fr 1fr;gap:26px}.tag{display:inline-block;color:#754f14;background:#fff0cc;border-radius:3px;padding:1px 5px;font-size:11px}
@media(max-width:900px){aside{position:static;width:auto;max-height:170px;border-right:0;border-bottom:1px solid var(--line)}aside a{display:inline-block}main{margin:0;padding:0 18px 50px}.grid2{display:block}.forestrow{grid-template-columns:95px 1fr 93px;font-size:12px}header h1{font-size:30px}}
</style></head><body>''')
nav=[('overview','Overview'),('methodology','Definitions and denominators'),('initiation','Initiation mix'),('dhs-712','DHS Table 7.12 replication'),('dhs-713','Modern-method reasons and DHS validation'),('all-cause','All-reason discontinuation'),('selected-reasons','Excluding pregnancy and partner'),('selected-models','Selected-reason adjusted models'),('selected-followup','Follow-up after selected endings'),('all-reason-users','All-reason current-user illustration'),('national','Actionable national patterns'),('timing','Actionable risk over time'),('zone-rates','Actionable zone rates'),('zone-reasons','Actionable reasons by zone'),('method-mix','Method starts by zone'),('methods-by-zone','Methods within zones'),('method-reasons','Reasons within methods'),('models','Adjusted models'),('subgroups','Subgroups'),('pairwise','Pairwise differences'),('current-use','Current use'),('post-ending','Use after stopping'),('population','Population and assumptions'),('user-projections','Actionable user illustration'),('mcpr-scenarios','2026 mCPR scenarios'),('regional-analyses','Regional analyses summary'),('switch-bridge','Direct modern switching'),('duration-bridge','Duration and year-end use')]
story_order=['overview','methodology','current-use','initiation','dhs-712','dhs-713',
 'all-cause','all-reason-users','selected-reasons','selected-models',
 'selected-followup','national','timing','zone-rates','zone-reasons',
 'method-mix','methods-by-zone','method-reasons','models','subgroups',
 'pairwise','regional-analyses','post-ending','population','user-projections',
 'mcpr-scenarios','switch-bridge','duration-bridge']
nav.sort(key=lambda item: story_order.index(item[0]))
parts.append('<aside><strong>Nigeria discontinuation</strong><small>2024 DHS • working analysis</small>'+''.join(f'<a href="#{a}">{b}</a>' for a,b in nav)+'</aside><main>')
parts.append('<header id="overview"><div class="eyebrow">Nigeria DHS 2024</div><h1>Modern-method discontinuation: all reasons, then program-actionable causes</h1><p>The analysis follows the Ethiopia presentation sequence: validate the DHS all-method table; examine all-reason modern-method discontinuation, including pregnancy intentions and partner disapproval; then narrow to selected and potentially actionable causes. An original-method ending is different from stopping all modern contraceptive use.</p></header>')
nat=times_row('National');mc=next(r for r in current if r['scope']=='National')
parts.append(section('methodology','What each probability measures','Study frame',
    'The published DHS Table 7.12 uses all eligible method-use episodes, including traditional methods and emergency contraception. Our subsequent continuing-use analyses use eligible modern-method episodes, excluding emergency contraception. We show three cumulative probabilities on that modern episode cohort: ending the original method for any reason; ending for any reason except wanted pregnancy and partner disapproval; and ending for the narrower potentially actionable method experience or access causes. At every stage, other endings remain competing events in the starting risk set.'))
parts.append(f'<div class="metrics"><div class="metric"><strong>{integer(nat["eligible_episodes_n"])}</strong><span>eligible modern-method episodes</span></div><div class="metric"><strong>{f(nat["all_reason_pct"])}%</strong><span>12-month ending for any reason</span></div><div class="metric"><strong>{f(nat["actionable_pct"])}%</strong><span>12-month actionable ending</span></div><div class="metric"><strong>{f(mc["all_women_mcpr_pct"])}%</strong><span>current mCPR, all women 15–49</span></div></div>')
all_starts_n=int(all_start_mix[0]['denominator_observed_starts_n'])
model_reference_n=sum(int(r['observed_starts_n']) for r in all_start_mix
    if r['scope']=='National' and r['method'] in methods)
published_all=next(r for r in table7 if r['method']=='All methods')
parts.append('<h3>Which sample and denominator does each display use?</h3><div class="tablewrap"><table><thead><tr><th>Display</th><th>Observed source records</th><th>Denominator / interpretation</th></tr></thead><tbody>')
sample_rows=[
 ('Published DHS Table 7.12',f'{integer(published_all["unweighted_episodes"])} episodes; {integer(published_all["weighted_episodes"])} weighted; {integer(published_all["late_entries"])} late entries','All eligible episodes of any method, including traditional methods and EC; the life table updates the risk set by month.'),
 ('Method-start share',f'{integer(all_starts_n)} observed starts','All observed method starts; method shares sum to 100% within a geography.'),
 ('All-reason, selected and actionable risk',f'{integer(nat["eligible_episodes_n"])} modern episodes; {integer(int(nat["eligible_episodes_n"])-model_reference_n)} late entries','Eligible modern-method episodes, excluding EC; other reasons are competing endings. Each method-specific risk uses episodes of that method.'),
 ('Reason shares among discontinuations','The relevant observed first-year endings','The cause-specific 12-month probabilities divided by the total for the stated reason set; displayed shares sum to 100% before rounding.'),
 ('Adjusted regional predictions',f'{integer(nat["eligible_episodes_n"])} episodes for fitting; {integer(model_reference_n)} observed starts for prediction','Episode-month competing-outcome model; adjusted comparisons average predicted risks over one shared observed-start cohort.'),
 ('Current use and planning','39,050 interviewed women; projected user stock','DHS all-women mCPR and current method mix are applied to UN women 15–49; these are illustrations, not life-table denominators.')]
for label,count,meaning in sample_rows:
    parts.append('<tr>'+td(h(label))+td(h(count))+td(h(meaning))+'</tr>')
parts.append('</tbody></table></div><p class="small">The number of episodes is a cohort count, not a fixed denominator applied at every follow-up month; left-truncated episodes enter the risk set when observation begins. Survey weights are used for estimates, and stratified cluster resampling supplies the displayed probability intervals.</p>')
parts.append('<div class="note"><b>Interpretation:</b> 38.9% is the all-reason first-year cumulative incidence for the original modern method; 21.4% is its narrower actionable component. Neither is the fraction of current users who will stop all modern contraception next year. Switching is included when the original method ends and must be handled separately for mCPR planning.</div></section>')

parts.append(section('initiation','Entry methods set the denominator for future retention risk','Observed starts',
  'A method start is an observed beginning of an episode in the DHS calendar, not current contraceptive use at interview. This diagnostic initially includes all method categories and emergency contraception, as in the Ethiopia presentation. Later first-year continuing-use rates exclude EC and traditional methods.'))
parts.append('<h3>Overall method-start mix</h3><div class="tablewrap"><table><thead><tr><th>Method category</th><th>Weighted share of starts</th><th>Observed starts</th></tr></thead><tbody>')
for r in [x for x in initiation if x['scope']=='Overall']:
    parts.append('<tr>'+td(h(r['method']))+td(f(r['start_share_pct'])+'%','num')+td(integer(r['observed_starts_n']),'num')+'</tr>')
parts.append('</tbody></table></div>')
parts.append('<h3>Initiation mix by calendar year</h3><div class="tablewrap"><table><thead><tr><th>Year</th><th>Observed starts</th>'+''.join(th(m) for m in ['Injectables','Implants','Pill','IUD','Emergency contraception','Other modern','Non-modern methods'])+'</tr></thead><tbody>')
for year in ['2021','2022','2023','2024']:
    rows=[r for r in initiation if r['scope']==year]
    parts.append('<tr>'+td(year+(' *' if year=='2024' else ''))+td(integer(rows[0]['denominator_observed_starts_n']),'num')+''.join(td(f(r['start_share_pct'])+'%','num') for r in rows)+'</tr>')
parts.append('</tbody></table></div><p class="small">* The 2024 calendar-year start window is incomplete under the DHS 3–62-month analysis window and contains only 64 observed starts. Do not interpret its mix as a full-year trend. Survey weights are applied to shares.</p></section>')

parts.append(section('dhs-712','The calendar reconstruction matches published Table 7.12','Validation',
  'The 2024 Nigeria DHS report publishes a multiple-decrement life table for discontinuation within 12 months. Reconstructed rates match all 110 published rate cells and all 10 published weighted episode counts after rounding.'))
cols=[('reason_1_pct','Failure'),('reason_2_pct','Wanted pregnancy'),('reason_3_pct','Other fertility'),('reason_4_pct','Bleeding'),('reason_5_pct','Other health'),('reason_6_pct','More effective'),('reason_7_pct','Other method'),('reason_8_pct','Partner'),('reason_9_pct','Other'),('any_reason_pct','Any reason'),('switching_pct','Switched'),('weighted_episodes','Weighted episodes')]
parts.append('<div class="tablewrap"><table><thead><tr><th>Method</th>'+''.join(th(label) for _,label in cols)+'</tr></thead><tbody>')
for r in table7:
    parts.append('<tr>'+td(h(r['method']))+''.join(td(integer(r[k]) if k=='weighted_episodes' else f(r[k]),'num') for k,_ in cols)+'</tr>')
parts.append('</tbody></table></div><p class="small">All methods includes traditional methods and emergency contraception, as in the published table. The subsequent modern-method analyses use a narrower, explicitly labeled episode cohort. Source: <a href="https://www.health.gov.ng/wp-content/uploads/2025/10/NDHS-2024-Final-Report_Disseminated17102025.pdf">Nigeria DHS 2024 final report, Table 7.12</a>.</p></section>')

parts.append(section('dhs-713','Reasons among recorded modern-method discontinuations','Five-year calendar distribution',
  'Matching the Ethiopia presentation, the primary reason distribution includes only recorded endings of modern-method episodes in the five-year calendar, excluding emergency contraception. It contains 4,557 unweighted endings (4,531.8 weighted). These percentages describe reasons among endings, not a first-year discontinuation probability.'))
parts.append('<h3>All modern methods: reasons among recorded endings</h3><div class="tablewrap"><table><thead><tr><th>Recorded reason</th><th>Weighted share of modern-method endings</th></tr></thead><tbody>')
for r in modern_five_year_reasons:
    parts.append('<tr>'+td(h(r['reason']))+td(f(r['percent'])+'%','num')+'</tr>')
parts.append('</tbody></table></div><p class="small">The seven categories sum to 100% before rounding. Source: Nigeria DHS 2024 IR contraceptive calendar, survey-weighted; modern-method endings excluding EC.</p>')
parts.append('<h3>Reason distribution by modern method</h3><div class="tablewrap"><table><thead><tr><th>Method</th><th>Wanted pregnancy</th><th>Method experience/access</th><th>Partner disapproval</th><th>Other reasons</th><th>Observed endings</th></tr></thead><tbody>')
for m in ['All modern','Injectables','Implants','Pill','IUD','Other modern']:
    rows=[r for r in modern_five_year_by_method if r['method']==m]
    parts.append('<tr>'+td(h(m))+''.join(td(f(r['percent'])+'%','num') for r in rows)+td(integer(rows[0]['unweighted_endings']),'num')+'</tr>')
parts.append('</tbody></table></div><p class="small">Each row sums to 100% before rounding. The observed endings are unweighted; percentages use DHS survey weights. EC and traditional methods are excluded.</p>')
parts.append('<h3>Published DHS Table 7.13: all-method validation comparison</h3><p class="small">The official table below includes traditional methods and emergency contraception. It validates the calendar extraction but has a different denominator from the modern-method presentation figure.</p>')
table713_methods=['All methods','IUD','Injectables','Implants','Pill','Male condom','Emergency contraception','Rhythm','Withdrawal','Other']
parts.append('<div class="tablewrap"><table><thead><tr><th>Recorded reason</th>'+''.join(th(x) for x in table713_methods)+'</tr></thead><tbody>')
for r in table713:
    parts.append('<tr>'+td(h(r['reason']))+''.join(td(f(r[x])+'%','num') for x in table713_methods)+'</tr>')
parts.append('</tbody></table></div><p class="small">Published weighted numbers of discontinuations: all methods 5,847; injectables 1,412; implants 1,009; pill 708; IUD 78. The report also includes a small “missing reason” row. Source: <a href="https://www.health.gov.ng/wp-content/uploads/2025/10/NDHS-2024-Final-Report_Disseminated17102025.pdf">Nigeria DHS 2024, Table 7.13</a>.</p></section>')

parts.append(section('all-cause','All-reason discontinuation comes first','Modern-method cohort',
  'The modern-method cohort includes 8,341 eligible use episodes (emergency contraception excluded). The 12-month all-reason probability is 38.9%. An episode that ends because a woman wants pregnancy or because her partner disapproves counts here. The published DHS all-methods row is 37.2% because it includes a broader set of methods.'))
parts.append('<h3>Method starts and 12-month all-reason discontinuation</h3><div class="pairchart">')
for m in methods:
    r=all_start_row('National',m);t=all_times_row('National: '+m)
    parts.append(f'<div class="pairrow"><label>{h(m)}</label><div class="two"><div class="sub"><span>Start share</span>{bar(r["start_share_pct"],"#DA9A25",70)}<strong>{f(r["start_share_pct"])}%</strong></div><div class="sub"><span>Any-reason risk</span>{bar(t["all_reason_pct"],"#153e56",70)}<strong>{f(t["all_reason_pct"])}%</strong></div></div><span></span></div>')
parts.append('</div><p class="small">Both bars have a 0–70% scale. The gold share uses all observed method starts, including EC and non-modern methods. The navy risk uses eligible episodes of the named modern method, excluding EC.</p>')
parts.append('<h3>All-reason risk at 3, 6, 9 and 12 months</h3><div class="tablewrap"><table><thead><tr><th>Original method</th>'+''.join(th(f'{t} months') for t in (3,6,9,12))+'</tr></thead><tbody>')
for m in ['All modern']+methods:
    scope='National' if m=='All modern' else 'National: '+m
    parts.append('<tr>'+td(h(m))+''.join(td(f(all_times_row(scope,t)['all_reason_pct'])+'%','num') for t in (3,6,9,12))+'</tr>')
parts.append('</tbody></table></div>')
parts.append('<h3>Why modern-method episodes ended within 12 months</h3><p>These are weighted shares of the all-reason cumulative discontinuation probability, so the nine reason columns sum to 100% within each method before rounding. The table above instead expresses risk among all eligible episodes.</p>')
full_reason_names=[r['reason'] for r in all_reasons if r['scope']=='National']
parts.append('<div class="tablewrap"><table><thead><tr><th>Original method</th>'+''.join(th(x) for x in full_reason_names)+'</tr></thead><tbody>')
for m in ['All modern']+methods:
    scope='National' if m=='All modern' else 'National: '+m
    parts.append('<tr>'+td(h(m))+''.join(td(f(all_reason_row(scope,x)['share_among_all_discontinuation_pct'])+'%','num') for x in full_reason_names)+'</tr>')
parts.append('</tbody></table></div>')
parts.append('<h3>Unadjusted all-reason risk by geopolitical zone</h3><p>Intervals resample survey clusters within strata and retain all episodes for each woman together.</p>')
for z in zones:
    r=all_times_row(z)
    parts.append(f'<div class="forestrow"><label>{h(z)}</label>{rangebar(r["all_reason_pct"],r["all_reason_ci_low"],r["all_reason_ci_high"],60,"#DA9A25" if z=="National" else "#108d94")}<span>{f(r["all_reason_pct"])}% <small>({f(r["all_reason_ci_low"])}–{f(r["all_reason_ci_high"])}%)</small></span></div>')
parts.append('<h3>Reasons among all first-year discontinuations by zone</h3><p>Companion view to the regional risk plot, following the Ethiopia presentation. Each row divides the zone’s all-reason 12-month discontinuation probability and sums to 100% before rounding; it is not the probability among all starters.</p>')
all_cause_groups=[('Wanted pregnancy',['Wanted pregnancy']),
 ('Method experience/access',['Method failure','Changes in menstrual bleeding','Other side effects/health','Wanted more effective method','Access/cost/convenience']),
 ('Partner disapproved',['Partner disapproved']),
 ('Other',['Other fertility-related','Other recorded reasons'])]
parts.append('<div class="tablewrap"><table><thead><tr><th>Zone</th>'+''.join(th(label) for label,_ in all_cause_groups)+'</tr></thead><tbody>')
for z in zones:
    parts.append('<tr>'+td(h(z))+''.join(heat_cell(sum(float(all_reason_row(z,reason)['share_among_all_discontinuation_pct']) for reason in reason_list),z=='National') for _,reason_list in all_cause_groups)+'</tr>')
parts.append('</tbody></table></div>')
parts.append('<h3>Adjusted all-reason probability by subgroup</h3><p>Episode-month logistic regression estimates the probability that the original method ends for any reason. It includes original method, month of use, zone, age and parity at method start, marital status, education, wealth, residence and start year. Marginal predictions use the same observed-start cohort for each category; intervals resample survey clusters within strata. These are associations, not effects of changing a characteristic.</p>')
parts.append('<div class="tablewrap"><table><thead><tr><th>Characteristic</th><th>Category</th><th>Adjusted 12-month probability (95% CI)</th></tr></thead><tbody>')
for r in all_subgroups:
    parts.append('<tr>'+td(h(r['covariate'].replace('_',' ').title()))+td(h(r['category']))+td(f(r['adjusted_12_month_pct'])+f'% ({f(r["ci_low"])}–{f(r["ci_high"])}%)','num')+'</tr>')
parts.append('</tbody></table></div>')
parts.append('<h3>Observed and adjusted all-reason risk by zone</h3><p>Method-adjusted and fully adjusted predictions compare zones using the same national observed-start composition. The observed column retains each zone’s actual method and population mix.</p>')
parts.append('<div class="tablewrap"><table><thead><tr><th>Zone</th><th>Observed % (95% CI)</th><th>Method adjusted % (95% CI)</th><th>Fully adjusted % (95% CI)</th></tr></thead><tbody>')
for r in all_models:
    parts.append('<tr>'+td(h(r['zone']))+td(f(r['unadjusted_pct'])+f'% ({f(r["unadjusted_low"])}–{f(r["unadjusted_high"])}%)','num')+td(f(r['model_1_pct'])+f'% ({f(r["model_1_low"])}–{f(r["model_1_high"])}%)','num')+td(f(r['model_2_pct'])+f'% ({f(r["model_2_low"])}–{f(r["model_2_high"])}%)','num')+'</tr>')
parts.append('</tbody></table></div>')
parts.append('</section>')

sel=all_times_row('National')
parts.append(section('selected-reasons','The intermediate selected-reason measure','Excluding two reasons',
  f'Among all eligible modern-method episodes, the 12-month probability of ending for any reason other than wanted pregnancy or partner disapproval is {f(sel["selected_reason_pct"])}%. Wanted pregnancy and partner disapproval are retained as competing outcomes, not removed from the original cohort. This intermediate measure still includes other fertility-related and other recorded reasons; it is therefore broader than the actionable outcome used later.'))
parts.append('<div class="tablewrap"><table><thead><tr><th>Original method</th><th>Any reason</th><th>Except wanted pregnancy and partner disapproval</th><th>Potentially actionable</th></tr></thead><tbody>')
for m in ['All modern']+methods:
    scope='National' if m=='All modern' else 'National: '+m
    r=all_times_row(scope)
    parts.append('<tr>'+td(h(m))+td(f(r['all_reason_pct'])+'%','num')+td(f(r['selected_reason_pct'])+'%','num')+td(f(r['actionable_pct'])+'%','num')+'</tr>')
parts.append('</tbody></table></div>')
parts.append('<h3>Selected-reason cumulative risk by method</h3><p>Every percentage is a weighted life-table probability among eligible modern-method episodes of the named original method. Wanted pregnancy and partner disapproval still remove episodes from the risk set when they occur.</p>')
parts.append('<div class="tablewrap"><table><thead><tr><th>Original method</th>'+''.join(th(f'{k} months') for k in (3,6,9,12))+'</tr></thead><tbody>')
for m in ['All modern']+methods:
    scope='National' if m=='All modern' else 'National: '+m
    parts.append('<tr>'+td(h(m))+''.join(td(f(all_times_row(scope,k)['selected_reason_pct'])+'%','num') for k in (3,6,9,12))+'</tr>')
parts.append('</tbody></table></div>')
selected_names=[x for x in full_reason_names if x not in ('Wanted pregnancy','Partner disapproved')]
parts.append('<h3>Reason distribution among selected first-year discontinuations</h3><p>Each method row sums to 100% before displayed rounding. Its denominator is the cumulative probability of ending for any retained reason by month 12; this is a reason distribution, not the chance of ending among all starters.</p>')
parts.append('<div class="tablewrap"><table><thead><tr><th>Original method</th>'+''.join(th(x) for x in selected_names)+'</tr></thead><tbody>')
for m in ['All modern']+methods:
    scope='National' if m=='All modern' else 'National: '+m
    denom=float(all_times_row(scope)['selected_reason_pct'])
    parts.append('<tr>'+td(h(m))+''.join(td(f(100*float(all_reason_row(scope,x)['cause_specific_12_month_pct'])/denom)+'%','num') for x in selected_names)+'</tr>')
parts.append('</tbody></table></div>')
parts.append('<h3>Selected-reason risk and reason distribution by zone</h3><p>The zone probability uses all eligible modern-method episodes in that zone. The seven reason cells divide only the selected first-year discontinuations in that zone and sum to 100% before rounding.</p>')
parts.append('<div class="tablewrap"><table><thead><tr><th>Zone</th><th>12-month risk</th>'+''.join(th(x) for x in selected_names)+'</tr></thead><tbody>')
for z in zones:
    denom=float(all_times_row(z)['selected_reason_pct'])
    parts.append('<tr>'+td(h(z))+td(f(denom)+'%','num')+''.join(td(f(100*float(all_reason_row(z,x)['cause_specific_12_month_pct'])/denom)+'%','num') for x in selected_names)+'</tr>')
parts.append('</tbody></table></div>')
parts.append('<div class="note goldnote">The first two measures include discontinuations that are not necessarily service failures. The next phase focuses on method failure, wanting greater effectiveness, bleeding changes, other health effects, and access/cost/convenience.</div></section>')

parts.append(section('selected-models','Who is more likely to discontinue for a selected reason?','Adjusted selected-reason models',
  'The outcome in each observed episode-month is continuation of the original method, discontinuation for any reason except wanted pregnancy or partner disapproval, or discontinuation for one of those two competing reasons. Model 1 includes month of use, original method and zone. Model 2 additionally includes age and parity at method start, marital status, education, wealth, residence and start year. Adjusted probabilities are 12-month cumulative incidences predicted for the common observed-start cohort; survey clusters are resampled within strata for 95% intervals.'))
parts.append('<h3>Observed and adjusted 12-month probability by zone</h3><div class="tablewrap"><table><thead><tr><th>Zone</th><th>Observed (95% CI)</th><th>Model 1 (95% CI)</th><th>Model 2 (95% CI)</th></tr></thead><tbody>')
for r in selected_models:
    parts.append('<tr>'+td(h(r['zone']))+td(f(r['unadjusted_pct'])+f'% ({f(r["unadjusted_low"])}–{f(r["unadjusted_high"])}%)','num')+td(f(r['model_1_pct'])+f'% ({f(r["model_1_low"])}–{f(r["model_1_high"])}%)','num')+td(f(r['model_2_pct'])+f'% ({f(r["model_2_low"])}–{f(r["model_2_high"])}%)','num')+'</tr>')
parts.append('</tbody></table></div><h3>Adjusted 12-month probability by subgroup</h3><div class="tablewrap"><table><thead><tr><th>Characteristic</th><th>Category</th><th>Adjusted probability (95% CI)</th></tr></thead><tbody>')
for r in selected_subgroups:
    parts.append('<tr>'+td(h(r['covariate'].replace('_',' ').title()))+td(h(r['category']))+td(f(r['adjusted_12_month_pct'])+f'% ({f(r["ci_low"])}–{f(r["ci_high"])}%)','num')+'</tr>')
parts.append('</tbody></table></div><p class="small">Adjusted differences describe associations after measured covariates are accounted for; they do not establish a causal effect or that every regional pair differs significantly.</p></section>')

parts.append(section('selected-followup','What happened after selected-reason discontinuation?','Ethiopia pathway counterpart',
  'This follow-up cohort includes first-year modern-method endings for any reason except wanted pregnancy or partner disapproval. It is broader than the actionable cohort used later. The month-1 and month-12 tables have different observed denominators because a full year of subsequent calendar data is unavailable for some endings.'))
for checkpoint in (1,12):
    rows=[r for r in selected_pathways if int(r['month_after_ending'])==checkpoint]
    parts.append(f'<h3>{checkpoint} month{"s" if checkpoint!=1 else ""} after ending</h3><div class="tablewrap"><table><thead><tr><th>Contraceptive status</th><th>Weighted share</th><th>Observed endings</th></tr></thead><tbody>')
    for r in rows:
        parts.append('<tr>'+td(h(r['status']))+td(f(r['percent'])+'%','num')+td(integer(r['observed_ending_events_n']),'num')+'</tr>')
    parts.append('</tbody></table></div>')
parts.append('<p class="small">A method ending does not automatically mean exit from modern contraception. Later re-entry and switching are descriptive pathways, not part of the first-year discontinuation probability.</p></section>')

parts.append(section('all-reason-users','Illustrative current-user endings for all reasons','All-reason planning counterpart',
  'The 2024 baseline combines Nigeria DHS 2024 all-women mCPR and current-method shares with UN 2024 women aged 15–49. The 2025 counts project that baseline using UN 2025 population and an assumed 0.4-percentage-point rise in mCPR, holding method shares constant. Projected 2025 users of each ongoing modern method are multiplied by its 12-month all-reason probability after a method start. This is an original-method ending illustration, not a forecast of users lost from modern contraception. It does not account for duration already used or subsequent switching. Emergency contraception is included in current modern use but excluded from continuing-use risk.'))
parts.append('<div class="tablewrap"><table><thead><tr><th>Original method</th><th>2024 users (DHS × UN)</th><th>Projected 2025 users</th><th>First-year all-reason risk</th><th>Illustrative original-method endings</th></tr></thead><tbody>')
for r in all_users:
    baseline=next(u for u in users if u['method']==r['method'])
    parts.append('<tr>'+td(h(r['method']))+td(integer(baseline['current_users_2024']),'num')+td(integer(r['current_users_2025']),'num')+td(f(r['all_reason_first_year_risk_pct'])+'%','num')+td(integer(r['illustrative_original_method_endings']),'num')+'</tr>')
parts.append('</tbody></table></div><h3>Illustrative endings by recorded reason</h3><p>Each reason uses its own cause-specific life-table probability among all eligible starts of that method. Reason columns add to the all-reason ending count before display rounding.</p>')
parts.append('<div class="tablewrap"><table><thead><tr><th>Original method</th>'+''.join(th(x) for x in full_reason_names)+'<th>All reasons</th></tr></thead><tbody>')
for m in methods:
    rr={r['reason']:float(r['illustrative_original_method_endings']) for r in all_user_causes if r['method']==m}
    parts.append('<tr>'+td(h(m))+''.join(td(integer(rr.get(c,0)),'num') for c in full_reason_names)+td(integer(sum(rr.values())),'num')+'</tr>')
parts.append('</tbody></table></div><p class="small">The estimated 2025 user stock uses Nigeria-specific women aged 15–49, the stated mCPR scenario, and the Nigeria DHS current-method mix. This all-reason table is intentionally shown before the later potentially actionable user-loss scenario.</p></section>')

parts.append(section('national','Method starts and 12-month actionable risk','Program-actionable phase',
  'The gold share uses all observed method starts, as in the Ethiopia presentation. The paired navy rate is the probability that the named modern method ends for a potentially actionable reason by month 12 among eligible episodes of that method.'))
parts.append('<div class="pairchart">')
for m in methods:
    r=all_start_row('National',m); risk=mix_row('National',m)
    parts.append(f'<div class="pairrow"><label>{h(m)}</label><div class="two"><div class="sub"><span>Start share</span>{bar(r["start_share_pct"],"#DA9A25",50)}<strong>{f(r["start_share_pct"])}%</strong></div><div class="sub"><span>12-month risk</span>{bar(risk["actionable_12_month_pct"],"#153F5B",50)}<strong>{f(risk["actionable_12_month_pct"])}%</strong></div></div><span></span></div>')
parts.append('</div><p class="small">Both bar lengths use a 0–50% scale. Emergency contraception is excluded from continuing-use denominators.</p></section>')

parts.append(section('timing','Actionable discontinuation accumulates during the first year','National and zones',
    'Each cell is the weighted cumulative probability among eligible episodes in the row. The final column shows how much of the month-12 risk had already occurred by month 3.'))
parts.append('<div class="tablewrap"><table><thead><tr><th>Geography</th>'+''.join(th(f'{m} months') for m in (3,6,9,12))+th('Share by 3 months')+'</tr></thead><tbody>')
for z in zones:
    vals=[times_row(z,m) for m in (3,6,9,12)]
    share=100*float(vals[0]['actionable_pct'])/float(vals[-1]['actionable_pct'])
    parts.append('<tr>'+td(h(z))+''.join(heat_cell(r['actionable_pct'],z=='National') for r in vals)+td(f(share)+'%','num')+'</tr>')
parts.append('</tbody></table></div><p class="small">95% intervals account for sample strata, clusters, and survey weights; see the zone chart below.</p></section>')

parts.append(section('zone-rates','Potentially actionable risk differs across the six zones','Subnational',
    'Unadjusted 12-month cumulative incidence with 95% stratified cluster-bootstrap intervals. The national rate is the dotted reference in the presentation version.'))
for z in zones:
    r=times_row(z)
    parts.append(f'<div class="forestrow"><label>{h(z)}</label>{rangebar(r["actionable_pct"],r["ci_low"],r["ci_high"],40,"#DA9A25" if z=="National" else "#108d94")}<span>{f(r["actionable_pct"])}% <small>({f(r["ci_low"])}–{f(r["ci_high"])})</small></span></div>')
parts.append('</section>')

parts.append(section('zone-reasons','The mix of actionable reasons varies by zone','Reasons',
    'Within each row, the five shares add to 100% of the 12-month potentially actionable discontinuation probability. These are shares among actionable discontinuations, not risks among all starts.'))
parts.append('<div class="tablewrap"><table><thead><tr><th>Zone</th>'+''.join(th(x) for x in cause_names)+'</tr></thead><tbody>')
for z in zones:
    parts.append('<tr>'+td(h(z))+''.join(heat_cell(reason_row(z,x)['share_among_actionable_pct'],z=='National') for x in cause_names)+'</tr>')
parts.append('</tbody></table></div><p class="small">Other side effects/health includes other side effects or health concerns; menstrual bleeding changes are shown separately. Access/cost/convenience combines lack of access or too far, cost too much, and inconvenient to use.</p></section>')

parts.append(section('method-mix','Entry method mix is different across the six zones','Starts',
    'Each row sums to 100% of all observed method starts, including emergency contraception and non-modern methods, matching the Ethiopia slide denominator. National is shown first for comparison.'))
parts.append('<div class="zonebars">')
for z in zones:
    seg=''.join(f'<span title="{h(m)} {f(all_start_row(z,m)["start_share_pct"])}%" style="width:{float(all_start_row(z,m)["start_share_pct"]):.3f}%;background:{colors[m]}"></span>' for m in start_methods)
    parts.append(f'<div class="zonebar"><label>{h(z)}</label><div class="stack">{seg}</div></div>')
parts.append('</div><div class="legend">'+''.join(f'<span style="--c:{colors[m]}">{h(m)}</span>' for m in start_methods)+'</div></section>')

parts.append(section('methods-by-zone','Within-method risk shows where method mix cannot explain the whole pattern','Methods by zone',
    'For each method, the gold bar is its share of all observed method starts in that zone; the navy bar below is its 12-month actionable discontinuation probability among eligible episodes of that method. Small IUD cells need caution.'))
for m in methods:
    parts.append(f'<h3>{h(m)}</h3><div class="pairchart">')
    for z in zones:
        r=all_start_row(z,m); risk=mix_row(z,m); time=times_row(f'{z}: {m}' if z!='National' else f'National: {m}')
        small=int(time['actionable_endings_n'])<30
        parts.append(f'<div class="pairrow"><label>{h(z)}{" *" if small else ""}</label><div class="two"><div class="sub"><span>Start share</span>{bar(r["start_share_pct"],"#DA9A25",60)}<strong>{f(r["start_share_pct"])}%</strong></div><div class="sub"><span>12-month risk</span>{bar(risk["actionable_12_month_pct"],"#153F5B",60)}<strong>{f(risk["actionable_12_month_pct"])}%</strong></div></div><span></span></div>')
    parts.append('</div>')
parts.append('<p class="small">* Fewer than 30 observed actionable endings. Treat the rate as imprecise. Bars share a 0–60% axis within this section.</p></section>')

parts.append(section('method-reasons','Reasons within each method and zone','Method-specific reasons',
    'The five shares in each visible row sum to 100% of that method’s actionable 12-month risk. An asterisk flags fewer than 30 eligible episodes or 30 observed actionable endings; an em dash suppresses cells with fewer than 10 such endings or fewer than 30 eligible episodes.'))
for m in methods:
    parts.append(f'<h3>{h(m)}</h3><div class="tablewrap"><table><thead><tr><th>Zone</th>'+''.join(th(x) for x in cause_names)+'</tr></thead><tbody>')
    for z in zones:
        scope=f'National: {m}' if z=='National' else f'{z}: {m}'
        rr=[reason_row(scope,x) for x in cause_names]
        n=int(rr[0]['eligible_episodes_n']);ev=int(rr[0]['actionable_endings_n'])
        label=z+(' *' if ev<30 or n<30 else '')
        cells=(''.join(heat_cell(r['share_among_actionable_pct'],z=='National') for r in rr)
               if n>=30 and ev>=10 else ''.join(td('—','num') for _ in rr))
        parts.append('<tr>'+td(h(label))+cells+'</tr>')
    parts.append('</tbody></table></div>')
parts.append('<p class="small">* Fewer than 30 eligible episodes or 30 actionable endings; interpret cautiously. Gray cells have fewer than 30 episodes or 10 actionable endings and their shares are withheld. Other side effects/health includes other side effects or health concerns; menstrual bleeding changes are separate. Access/cost/convenience combines lack of access or too far, cost too much, and inconvenient to use. Percentages are cumulative-incidence contributions normalized within the actionable category.</p></section>')

parts.append(section('models','Adjustment helps separate composition from zone differences','Regression',
    'Both models use an episode-month multinomial outcome: continue the original method, end for an actionable reason, or end for a competing reason. Model 1 includes elapsed method-use month, original method, and zone. Model 2 adds age and parity at episode start, plus marital status, education, wealth, residence at interview, and calendar year of start. The 50 episodes started in 2024 had no observed actionable endings, so 2023 and 2024 starts are pooled in the model year term to avoid separation. Predictions use the same national observed-start cohort for every zone.'))
parts.append('<h3>Observed versus fully adjusted risk, with 95% intervals</h3><p><span style="color:#DA9A25">■</span> Observed &nbsp; <span style="color:#153F5B">■</span> Fully adjusted. Both intervals resample survey clusters within strata.</p>')
for z in zones:
    r=next(q for q in models if q['zone']==z)
    parts.append('<div class="dualrow'+(' national' if z=='National' else '')+'"><label>'+h(z)+'</label>'+dual_rangebar(r['unadjusted_pct'],r['unadjusted_low'],r['unadjusted_high'],r['model_2_common_mix_pct'],r['model_2_low'],r['model_2_high'])+'<span>'+f(r['unadjusted_pct'])+'%</span><span>'+f(r['model_2_common_mix_pct'])+'%</span></div>')
parts.append('<p class="small">Horizontal axis: 0–40%. The adjusted probability is standardized to the same observed-start cohort for each zone.</p>')
parts.append('<div class="tablewrap"><table><thead><tr><th>Zone</th><th>Observed % (95% CI)</th><th>Method adjusted %</th><th>Fully adjusted %</th></tr></thead><tbody>')
for z in zones:
    r=next(q for q in models if q['zone']==z)
    model1=f(r['model_1_common_mix_pct'])
    model2=f(r['model_2_common_mix_pct'])
    if r.get('model_1_low'):
        model1+=f' ({f(r["model_1_low"])}–{f(r["model_1_high"])})'
        model2+=f' ({f(r["model_2_low"])}–{f(r["model_2_high"])})'
    parts.append('<tr>'+td(h(z))+td(f(r['unadjusted_pct'])+f'% ({f(r["unadjusted_low"])}–{f(r["unadjusted_high"])})','num')+td(model1,'num')+td(model2,'num')+'</tr>')
parts.append('</tbody></table></div><div class="note goldnote">A standardized zone estimate is a model prediction for that zone under a common observed-start mix of methods and measured characteristics. It describes adjusted differences. It does not assign an intervention or prove a causal regional effect.</div>')
parts.append('<h3>Model 2 odds ratios for actionable ending versus continuing that month</h3><div class="tablewrap"><table><thead><tr><th>Covariate</th><th>Odds ratio</th><th>95% model CI</th><th>p value</th></tr></thead><tbody>')
for r in coef:
    if r['model']=='Full' and r['outcome']=='actionable' and r['covariate']!='(Intercept)' and not r['covariate'].startswith('month'):
        p_label='&lt;0.001' if float(r['p_value'])<.001 else f(r['p_value'],3)
        parts.append('<tr>'+td(h(r['covariate']))+td(f(r['odds_ratio'],2),'num')+td(f(r['ci_low'],2)+'–'+f(r['ci_high'],2),'num')+td(p_label,'num')+'</tr>')
parts.append('</tbody></table></div><p class="small">Reference categories: IUD; North West; ages 25–34; parity 0; married; no education; poorest; urban; first start-year category. Odds-ratio intervals and p values use the model Hessian and do not account for the DHS survey design; use the survey-cluster bootstrap comparisons above for regional inference.</p></section>')

parts.append(section('subgroups','Observed actionable risk by subgroup','Exploratory',
    'These rates use one covariate at a time and preserve competing endings. They describe subgroup patterns before model adjustment. Each reason share is a share of the subgroup’s actionable 12-month probability.'))
if subgroups:
    parts.append('<div class="tablewrap"><table><thead><tr><th>Characteristic</th><th>Category</th><th>Episodes</th><th>12-month risk (95% CI)</th><th>Leading actionable reason</th></tr></thead><tbody>')
    for r in subgroups:
        cs=[('Method failure',r.get('Method.failure','0')),('Wanted more effective method',r.get('Wanted.more.effective.method','0')),('Bleeding',r.get('Changes.in.menstrual.bleeding','0')),('Other health',r.get('Other.side.effects.health','0')),('Access',r.get('Access.cost.convenience','0'))]
        lead=max(cs,key=lambda x:float(x[1] or 0))[0]
        covariate_labels={'age_group':'Age at method start','parity':'Parity at method start','marital_status':'Marital status','education':'Education','wealth':'Wealth quintile','residence':'Residence','zone_name':'Geopolitical zone'}
        parts.append('<tr>'+td(h(covariate_labels.get(r['covariate'],r['covariate'])))+td(h(r['category']))+td(integer(r['eligible_episodes_n']),'num')+td(f(r['actionable_12_month_pct'])+f'% ({f(r["ci_low"])}–{f(r["ci_high"])})','num')+td(h(lead))+'</tr>')
    parts.append('</tbody></table></div>')
else: parts.append('<p>Subgroup bootstrap results are being generated from the same episode cohort.</p>')
parts.append('</section>')

parts.append(section('pairwise','Which zone contrasts survive statistical testing?','Inference',
    'All 15 pairwise zone contrasts are tested for the observed rates, method-adjusted predictions, and fully adjusted predictions. Tests use stratified PSU-bootstrap standard errors; Holm correction is applied within each stage.'))
if tests:
    for stage in ['Unadjusted','Method adjusted','Fully adjusted']:
        rows=[r for r in tests if r['stage']==stage]
        sig=[r for r in rows if r['significant_5pct']=='TRUE']
        parts.append(f'<h3>{h(stage)}: {len(sig)} of 15 contrasts at 5%</h3>')
        if sig:
            parts.append('<div class="tablewrap"><table><thead><tr><th>Zone A</th><th>Zone B</th><th>Difference (pp)</th><th>95% CI</th><th>Holm p</th></tr></thead><tbody>')
            for r in sorted(sig,key=lambda q:abs(float(q['difference_pp'])),reverse=True):
                parts.append('<tr>'+td(h(r['zone_a']))+td(h(r['zone_b']))+td(f(r['difference_pp']))+td(f(r['ci_low'])+'–'+f(r['ci_high']))+td(f(r['p_holm'],3))+'</tr>')
            parts.append('</tbody></table></div>')
        else: parts.append('<p>No pairwise contrast remains significant after Holm correction.</p>')
else: parts.append('<p>Pairwise bootstrap tests are being generated.</p>')
parts.append('<p class="small">A nonsignificant result does not establish that two zones have equal risk. The family of 15 tests is corrected separately for each comparison stage.</p></section>')

parts.append(section('current-use','Current modern use and implications for user-loss planning','Planning',
    'The 2024 IR recode estimates mCPR among all women age 15–49. Converting a first-year episode risk to expected losses among today’s users requires how long current users have already used each method; converting retained users to mCPR points also requires a dated national or zone-specific population of women age 15–49 and explicit assumptions about switching.'))
parts.append('<div class="tablewrap"><table><thead><tr><th>Geography</th><th>Women interviewed</th><th>Current modern users interviewed</th><th>All-women mCPR</th><th>EC share among current modern users</th></tr></thead><tbody>')
for z in zones:
    r=next(q for q in current if q['scope']==z)
    parts.append('<tr>'+td(h(z))+td(integer(r['women_n']),'num')+td(integer(r['modern_users_n']),'num')+td(f(r['all_women_mcpr_pct'])+'%','num')+td(f(r['ec_share_of_modern_users_pct'])+'%','num')+'</tr>')
parts.append('</tbody></table></div></section>')

parts.append(section('post-ending','Modern use after an actionable method ending','Pathways',
    'The calendar reveals contraceptive status after an observed method ending. The one-month and 12-month rows use different follow-up cohorts because the latter requires twelve observed months. These are weighted descriptive shares among observed actionable endings, not cumulative discontinuation probabilities.'))
parts.append('<div class="tablewrap"><table><thead><tr><th>Months after ending</th><th>Status</th><th>Share</th><th>Observed endings</th></tr></thead><tbody>')
for r in pathways:
    parts.append('<tr>'+td(h(r['month_after_ending']))+td(h(r['status']))+td(f(r['percent'])+'%','num')+td(integer(r['observed_ending_events_n']),'num')+'</tr>')
parts.append('</tbody></table></div><p class="small">The one-month checkpoint is relevant to switching; the 12-month checkpoint shows that later use can differ. Pregnancy, birth and termination are calendar states, not contraceptive methods.</p>')
parts.append('<h3>Transitions in the common twelve-month follow-up cohort</h3><p class="small">Each cell is a weighted percentage of the same 1,216 observed endings; all cells together sum to 100%. Rows are status one month after ending and columns are status twelve months after ending.</p>')
states=['No method recorded','Different modern method','Same modern method','Traditional/other method','Pregnant, birth or termination','Other/unknown']
parts.append('<div class="tablewrap"><table><thead><tr><th>Month 1 status</th>'+''.join(th(x) for x in states)+'</tr></thead><tbody>')
for a in states:
    cells=[]
    for b in states:
        found=next((r for r in transitions if r['month_1']==a and r['month_12']==b),None)
        cells.append(td(f(found['share_of_common_cohort_pct'])+'%' if found else '0.0%','num'))
    parts.append('<tr>'+td(h(a))+''.join(cells)+'</tr>')
parts.append('</tbody></table></div></section>')

parts.append(section('population','Nigeria population and mCPR inputs','Planning inputs',
    'The observed 2024 baseline pairs Nigeria DHS 2024 all-women mCPR and current-method mix with UN 2024 women aged 15–49. For 2025, we use the UN 2025 population and assume mCPR rises by 0.4 percentage points, holding the DHS method mix fixed. That increment comes from the Track20/FP2030 modeled all-women mCPR change from 13.2% in 2024 to 13.6% in 2025; it is transferred to the DHS baseline, not a relative 0.4% growth rate. The central 2026 scenario adds another 0.4 points. The third scenario instead uses the FP2030 2025 level of 13.6% plus 0.4 points to set 2026 mCPR at 14.0%. These are assumptions, not observed 2025 values or published 2026 forecasts.'))
parts.append('<div class="tablewrap"><table><thead><tr><th>Year</th><th>Women aged 15–49</th><th>Source</th></tr></thead><tbody>')
for r in wra:parts.append('<tr>'+td(h(r['year']))+td(integer(r['women_15_49']),'num')+td('UN WPP 2024 medium variant')+'</tr>')
parts.append('</tbody></table></div>')
central=scenarios[1]
parts.append('<h3>From the 2024 baseline to the central projection</h3><div class="tablewrap"><table><thead><tr><th>Year</th><th>All-women mCPR</th><th>Women aged 15–49</th><th>Modern users</th><th>Interpretation</th></tr></thead><tbody>')
for year,rate,women,count,label in [
    (2024,central['mcpr_2024_pct'],central['wra_2024'],central['current_users_2024'],'DHS 2024 prevalence × UN 2024 population'),
    (2025,central['mcpr_2025_pct'],central['wra_2025'],central['current_users_2025'],'Projected: +0.4 pp mCPR, UN 2025 population'),
    (2026,central['mcpr_2026_pct'],central['wra_2026'],central['usual_users_2026'],'Illustrative central scenario: another +0.4 pp')]:
    parts.append('<tr>'+td(year)+td(f(rate,2)+'%','num')+td(integer(women),'num')+td(integer(count),'num')+td(h(label))+'</tr>')
parts.append('</tbody></table></div>')
population_growth=(float(central['wra_2025'])/float(central['wra_2024'])-1)*100
user_growth=(float(central['current_users_2025'])/float(central['current_users_2024'])-1)*100
relative_mcpr_growth=(float(central['mcpr_2025_pct'])/float(central['mcpr_2024_pct'])-1)*100
parts.append(f'<p class="small">The planning increment is <b>+0.4 percentage points of mCPR per year</b>, transferred from the modeled Track20/FP2030 2024–25 difference. Relative to the DHS 2024 baseline, that is a {f(relative_mcpr_growth,2)}% proportional mCPR increase. UN women aged 15–49 grow {f(population_growth,2)}% from 2024 to 2025; together these assumptions raise the estimated number of modern users by {f(user_growth,2)}%. None of these is an observed DHS change between 2024 and 2025.</p>')
parts.append('<p class="small">Source: <a href="https://population.un.org/wpp/">UN WPP 2024</a>, female single-age workbook POP/F01-3. mCPR and method mix: weighted Nigeria DHS 2024 IR recode (v313 and v312). Trend source: <a href="https://www.track20.org/download/resources/Country%20Indicators/2025/2025%20Combo%20Briefs/English/Nigeria%202025%20Summary%20Brief%20and%20Handout.pdf">Track20/FP2030 Nigeria 2025 brief</a>.</p></section>')

parts.append(section('user-projections','Illustrative current-user method endings','Planning scale',
    'Estimated 2024 users by method equal UN 2024 women aged 15–49 × DHS 2024 mCPR × DHS 2024 current-method share. Projected 2025 users use UN 2025 population and a 2025 mCPR 0.4 points higher, holding method shares constant. Illustrative original-method endings equal projected 2025 users × method-specific first-year actionable life-table risk. These counts do not account for duration already used and are not forecasts of women leaving all modern contraception.'))
parts.append('<div class="tablewrap"><table><thead><tr><th>Method</th><th>DHS 2024 current mix</th><th>2024 users (DHS × UN)</th><th>Projected 2025 users</th><th>First-year actionable risk</th><th>Illustrative original-method endings</th></tr></thead><tbody>')
for r in users:
    risk='Not applied' if r['method']=='EC' else f(r['actionable_first_year_risk_pct'])+'%'
    endings='Not estimated' if r['method']=='EC' else integer(r['illustrative_original_method_endings'])
    parts.append('<tr>'+td(h(r['method']))+td(f(r['share_current_modern_pct'])+'%','num')+td(integer(r['current_users_2024']),'num')+td(integer(r['current_users_2025']),'num')+td(risk,'num')+td(endings,'num')+'</tr>')
gross_endings=sum(float(r['illustrative_original_method_endings']) for r in users)
current_users=sum(float(r['current_users_2025']) for r in users)
parts.append(f'</tbody></table></div><p class="small">The {f(100*gross_endings/current_users)}% ratio of illustrative endings to all projected 2025 modern users is not the {f(nat["actionable_pct"])}% national life-table risk. The former uses DHS 2024 current-method mix, includes EC users in the projected stock with no EC ending estimate, and assumes every ongoing-method user faces first-year start risks; the latter uses eligible episode starts.</p>')
parts.append('<h3>Original-method endings by actionable cause</h3><div class="tablewrap"><table><thead><tr><th>Method</th>'+''.join(th(x) for x in cause_names)+'<th>Total</th></tr></thead><tbody>')
for m in methods:
    rows=[r for r in user_causes if r['method']==m]
    vals={r['reason']:float(r['illustrative_users']) for r in rows}
    parts.append('<tr>'+td(h(m))+''.join(td(integer(vals.get(c,0)),'num') for c in cause_names)+td(integer(sum(vals.values())),'num')+'</tr>')
parts.append('</tbody></table></div><p class="small">Cause columns sum to the method total before displayed rounding. The IUD cause breakdown is based on only 17 observed actionable first-year endings and is especially imprecise.</p>')
parts.append('<h3>Immediate switching changes the interpretation</h3><div class="tablewrap"><table><thead><tr><th>Original method</th><th>Actionable endings observed</th><th>Next-month modern method (%)</th></tr></thead><tbody>')
for r in switch:parts.append('<tr>'+td(h(r['method']))+td(integer(r['actionable_events_n']),'num')+td(f(r['share_immediate_modern_pct'])+'%','num')+'</tr>')
parts.append('</tbody></table></div><p class="small">This is the weighted share using another modern method in the month after the original episode ended. It does not establish contraceptive status at the end of 2026.</p></section>')

parts.append(section('mcpr-scenarios','Illustrative 2026 mCPR scenarios','Planning scenarios',
    'Usual 2026 users equal projected 2026 women aged 15–49 multiplied by the assumed 2026 all-women mCPR. A gross upper bound then adds all illustrative actionable original-method endings. A narrower bound subtracts the portion that immediately switches to another modern method. Both remain illustrative because they apply first-year risks to current users and do not model their duration, later switching, entrants or causal intervention effectiveness.'))
parts.append('<div class="tablewrap"><table><thead><tr><th>Scenario</th><th>DHS 2024 mCPR</th><th>2024 users (DHS × UN)</th><th>Projected 2025 mCPR</th><th>Projected 2025 users</th><th>2026 usual mCPR</th><th>2026 usual users</th><th>Gross no-ending mCPR</th><th>Gross ceiling gain</th><th>After immediate-switch bound</th></tr></thead><tbody>')
for r in scenarios:
    parts.append('<tr>'+td(h(r['scenario']))+td(f(r['mcpr_2024_pct'])+'%','num')+td(integer(r['current_users_2024']),'num')+td(f(r['mcpr_2025_pct'])+'%','num')+td(integer(r['current_users_2025']),'num')+td(f(r['mcpr_2026_pct'])+'%','num')+td(integer(r['usual_users_2026']),'num')+td(f(r['no_gross_endings_mcpr_2026_pct'])+'%','num')+td(f(r['gross_ceiling_gain_pp'])+' pp','num')+td(f(r['no_non_switch_endings_mcpr_2026_pct'])+'%','num')+'</tr>')
parts.append('</tbody></table></div><div class="note goldnote">For the central DHS-anchored trend scenario, 2026 usual mCPR is '+f(scenarios[1]['mcpr_2026_pct'])+'%. Adding every illustrative original-method ending yields '+f(scenarios[1]['no_gross_endings_mcpr_2026_pct'])+'% (+'+f(scenarios[1]['gross_ceiling_gain_pp'])+' percentage points). Removing immediate modern switchers from that count yields a narrower '+f(scenarios[1]['no_non_switch_endings_mcpr_2026_pct'])+'% ceiling. Neither is a predicted effect of a real program.</div></section>')

parts.append(section('regional-analyses','Regional analyses','Subnational summary',
  'Nigeria’s six geopolitical zones are compared using three clearly different 12-month outcomes. The first column counts original-method endings for any reason. The second excludes wanted pregnancy and partner disapproval as events of interest, while retaining them as competing endings. The third—the focus of the detailed regional reason heatmaps, method-by-zone comparisons and pairwise tests—is limited to potentially actionable method experience and access causes. Every rate uses eligible modern-method episodes as its starting cohort; emergency contraception is excluded from continuing-use risk.'))
parts.append('<h3>Which reasons are included in each zone rate?</h3><div class="tablewrap"><table><thead><tr><th>Zone</th><th>Any reason (95% CI)</th><th>Except pregnancy intention and partner disapproval (95% CI)</th><th>Potentially actionable (95% CI)</th></tr></thead><tbody>')
for z in zones:
    a=all_times_row(z);q=times_row(z)
    parts.append('<tr>'+td(h(z))+td(f(a['all_reason_pct'])+f'% ({f(a["all_reason_ci_low"])}–{f(a["all_reason_ci_high"])}%)','num')+td(f(a['selected_reason_pct'])+f'% ({f(a["selected_reason_ci_low"])}–{f(a["selected_reason_ci_high"])}%)','num')+td(f(q['actionable_pct'])+f'% ({f(q["ci_low"])}–{f(q["ci_high"])}%)','num')+'</tr>')
parts.append('</tbody></table></div>')
parts.append('<h3>Reason mix within actionable first-year discontinuations</h3><p>Each row distributes only the actionable 12-month cumulative incidence in that zone. Its five cells add to 100% before display rounding. These are shares among actionable discontinuations, not rates among all episodes.</p>')
parts.append('<div class="tablewrap"><table><thead><tr><th>Zone</th>'+''.join(th(x) for x in cause_names)+'</tr></thead><tbody>')
for z in zones:
    parts.append('<tr>'+td(h(z))+''.join(heat_cell(reason_row(z,c)['share_among_actionable_pct'],z=='National') for c in cause_names)+'</tr>')
parts.append('</tbody></table></div><p class="small">Bleeding changes and other side effects/health are separate categories. Access/cost/convenience combines lack of access, cost and inconvenience. The <a href="#method-reasons">method-specific reason tables</a> show the same actionable cause distribution for injectables, implants, pills, IUDs and other modern methods in each zone. See <a href="#pairwise">pairwise zone tests</a> for statistical comparisons. Sparse method-by-zone cause cells are flagged in those detailed tables.</p></section>')

parts.append(section('switch-bridge','Direct modern switching reduces the gross user-loss illustration','Planning bridge A',
    'The earlier table applies each method’s 12-month actionable original-method ending probability to projected 2025 current users. Here the observed share of those endings followed immediately by another modern method is removed from the illustrative loss count. Direct switchers remain modern users. The remainder is <b>not</b> an estimate of women absent from the 2026 mCPR numerator because later restarting and existing method duration are still unaccounted for.'))
parts.append('<div class="tablewrap"><table><thead><tr><th>Original method</th><th>Projected 2025 current users</th><th>Gross actionable method endings</th><th>Direct modern switchers</th><th>Endings without direct modern switch</th><th>Observed actionable endings (n)</th></tr></thead><tbody>')
for r in switch_bridge:
    parts.append('<tr>'+td(h(r['method']))+td(integer(r['current_users_2025']),'num')+td(integer(r['illustrative_original_method_endings']),'num')+td(integer(r['illustrative_direct_modern_switchers']),'num')+td(integer(r['illustrative_not_directly_switching']),'num')+td(integer(r['observed_actionable_endings_n']),'num')+'</tr>')
ec_2025=next(float(r['current_users_2025']) for r in users if r['method']=='EC')
parts.append('<tr>'+td('EC')+td(integer(ec_2025),'num')+''.join(td('Not estimated') for _ in range(3))+td('—')+'</tr>')
parts.append('<tr><th>All modern</th>'+td(integer(ec_2025+sum(float(r['current_users_2025']) for r in switch_bridge)),'num')+''.join(td(integer(sum(float(r[k]) for r in switch_bridge)),'num') for k in ['illustrative_original_method_endings','illustrative_direct_modern_switchers','illustrative_not_directly_switching'])+td('—')+'</tr></tbody></table></div>')
parts.append('<p class="small">Direct modern switching means another modern method appears in the next calendar month. The observed switch fraction is survey weighted within each original-method group; counts are scaled to projected 2025 users. EC remains in current mCPR but has no ongoing-use ending risk. The IUD switching estimate rests on only 17 observed actionable endings and should not be interpreted as evidence of zero switching.</p>')
parts.append('<h3>Cause-specific gross endings and direct modern switches</h3><div class="tablewrap"><table><thead><tr><th>Method</th><th>Actionable cause</th><th>Gross original-method endings</th><th>Direct modern switchers</th><th>Without direct modern switch</th><th>Observed endings (n)</th></tr></thead><tbody>')
for r in switch_bridge_cause:
    parts.append('<tr>'+td(h(r['method']))+td(h(r['reason']))+td(integer(r['illustrative_original_method_endings']),'num')+td(integer(r['illustrative_direct_modern_switchers']),'num')+td(integer(r['illustrative_not_directly_switching']),'num')+td(integer(r['observed_endings_n']),'num')+'</tr>')
parts.append('</tbody></table></div><p class="small">Cause-specific switch patterns use observed first-year actionable endings within method and reason, then are calibrated to each method-level direct-switch total so the tables reconcile. Cells with fewer than 30 endings are exploratory; a displayed zero can reflect sparse data.</p>')
parts.append('<h3>How this changes the existing 2026 scenario illustration</h3><div class="tablewrap"><table><thead><tr><th>2026 mCPR scenario</th><th>Usual mCPR</th><th>Gross endings</th><th>After direct switches</th><th>Illustrative pp if all remaining women stayed modern</th></tr></thead><tbody>')
for r in duration_scenarios:
    pp=100*float(r['first_year_not_directly_switching'])/float(r['wra_2026'])
    parts.append('<tr>'+td(h(r['scenario']))+td(f(r['mcpr_2026_pct'],2)+'%','num')+td(integer(r['first_year_gross_endings']),'num')+td(integer(r['first_year_not_directly_switching']),'num')+td(f(pp,2)+' pp','num')+'</tr>')
parts.append('</tbody></table></div><p class="small">The last column is a mechanical ceiling, not a forecast of program effect. It still assumes every current user faces a first-year start risk and that every nonswitching ending would otherwise lower year-end mCPR.</p></section>')

parts.append(section('duration-bridge','Accounting for elapsed use and modern status at year end','Planning bridge B',
    'A current user who has already used a method for 18 months needs a risk for the <em>next</em> 12 months conditional on having continued for 18 months. The DHS 2024 current-user duration variable (v337) supplies that elapsed time. We use 103,447 historical method-use months from 5,192 women that have 12 more calendar months observed, calculate what happened over those months, and weight the method-and-duration results to the DHS current-user distribution. Thus the endpoint here is 12 months after a current-use landmark, not 12 months after method initiation.'))
parts.append('<div class="tablewrap"><table><thead><tr><th>Current method</th><th>Projected 2025 users</th><th>Actionable ending next 12 months</th><th>Direct modern switch</th><th>Modern at year end after actionable ending</th><th>Nonmodern at year end after actionable ending</th><th>Current users 61+ months</th></tr></thead><tbody>')
for r in duration_bridge:
    parts.append('<tr>'+td(h(r['method']))+td(integer(r['current_users_2025']),'num')+td(integer(r['projected_actionable_original_method_endings']),'num')+td(integer(r['projected_direct_modern_switchers']),'num')+td(integer(r['projected_modern_at_month12_after_actionable']),'num')+td(integer(r['projected_nonmodern_at_month12_after_actionable']),'num')+td(f(r['current_users_61plus_share_pct'])+'%','num')+'</tr>')
parts.append('<tr>'+td('EC')+td(integer(ec_2025),'num')+''.join(td('Not estimated') for _ in range(4))+td('—')+'</tr>')
parts.append('<tr><th>All modern</th>'+td(integer(ec_2025+sum(float(r['current_users_2025']) for r in duration_bridge)),'num')+''.join(td(integer(sum(float(r[k]) for r in duration_bridge)),'num') for k in ['projected_actionable_original_method_endings','projected_direct_modern_switchers','projected_modern_at_month12_after_actionable','projected_nonmodern_at_month12_after_actionable'])+td('—')+'</tr></tbody></table></div>')
parts.append('<p class="small">“Modern at year end” includes both direct switches and later restarts. “Nonmodern at year end” includes no method, traditional methods and pregnancy/birth/termination calendar states. These two statuses partition projected actionable original-method endings. Neither status is a causal estimate of how many women an intervention could retain.</p>')
parts.append('<h3>Cause-specific duration-aware endpoint</h3><div class="tablewrap"><table><thead><tr><th>Current method</th><th>Actionable cause of original-method ending</th><th>Endings in next 12 months</th><th>Direct modern switches</th><th>Nonmodern at year end</th></tr></thead><tbody>')
for r in duration_bridge_cause:
    parts.append('<tr>'+td(h(r['method']))+td(h(r['reason']))+td(integer(r['projected_actionable_original_method_endings']),'num')+td(integer(r['projected_direct_modern_switchers']),'num')+td(integer(r['projected_nonmodern_at_month12']),'num')+'</tr>')
parts.append('</tbody></table></div>')
parts.append('<h3>Illustrative mCPR scale, after duration and year-end modern use</h3><div class="tablewrap"><table><thead><tr><th>2026 scenario</th><th>Usual mCPR</th><th>Women nonmodern at year end after an actionable ending</th><th>Mechanical ceiling gain</th><th>mCPR under that ceiling</th></tr></thead><tbody>')
for r in duration_scenarios:
    parts.append('<tr>'+td(h(r['scenario']))+td(f(r['mcpr_2026_pct'],2)+'%','num')+td(integer(r['duration_aware_nonmodern_at_month12']),'num')+td(f(r['descriptive_nonmodern_at_month12_pp'],2)+' pp','num')+td(f(r['illustrative_mcpr_if_all_endpoint_users_retained'],2)+'%','num')+'</tr>')
parts.append('</tbody></table></div><div class="note goldnote"><b>Critical limit:</b> No current user with 61+ completed months has a matched historical calendar landmark with a full additional year observed. The displayed scenario assigns them the observed 37–60-month risk. They represent 10.9% of injectable users, 13.7% of implant users, 14.4% of pill users, 36.1% of IUD users and 14.2% of other-modern users. IUD estimates are especially fragile. Using only the observed 37–48 or 49–60-month risk for this unsupported group gives '+f(min(float(r['illustrative_pp']) for r in duration_sensitivity),2)+' to '+f(max(float(r['illustrative_pp']) for r in duration_sensitivity),2)+' pp; this narrow range does not include sampling uncertainty.</div>')
parts.append('<p class="small">These are descriptive transported-calendar scenarios, not causal forecasts. They assume the 2024 current-user duration distribution applies to projected 2025 users, that historical transitions apply in 2025–26, and that avoiding an actionable ending would keep each otherwise nonmodern woman using a modern method at year end. A program effect requires evidence on intervention uptake and effectiveness. The denominator for pp is projected 2026 women aged 15–49 (59,000,784). Repeated historical landmarks from one woman are not independent observations; these planning tables have no inferential confidence intervals.</p></section>')
parts.append('<footer class="small" style="padding-top:24px">Reproducible source: Code/01–17 in this Nigeria project. Survey weights v005, PSU v021, strata v022. Nigeria DHS 2024 IR calendar, official report Tables 7.12 and 7.13, UN WPP 2024 and Track20/FP2030 2025. Updated 22 October 2026.</footer></main></body></html>')
# Move complete sections into the Ethiopia deck's narrative order while
# keeping the calculations above independent and traceable to their tables.
document=''.join(parts)
matches=list(re.finditer(r'<section id="([^"]+)">.*?</section>',document,re.S))
blocks={match.group(1):match.group(0) for match in matches}
assert len(blocks)==len(matches)==len(story_order)-1
begin=document[:matches[0].start()]
end=document[matches[-1].end():]
document=begin+''.join(blocks[k] for k in story_order if k!='overview')+end
OUT.write_text(document,encoding='utf-8')
print(OUT.name))----------------------")

MODULES[["19_add_cause_mcpr_ceiling_html.py"]] <- list(language="Python", packaged_sha256="8fba6ca3a8f97e5013e871e42b112b852ddb7ed2fb0c467a8d53a24e8761ce4b", args=character(0), code=r"----------------------("""Append the cause-specific gross mCPR ceiling table to a country HTML report.

The user counts come from the existing method-by-cause projection. The same
projected 2026 women 15–49 denominator is used in every reason column.
Running this script again replaces its own section without duplicating it.
"""

import argparse
import csv
import html
from pathlib import Path
import os
import re


REASONS = [
    ("Method failure", "Method<br>failure"),
    ("Wanted more effective method", "Wanted more<br>effective method"),
    ("Changes in menstrual bleeding", "Bleeding<br>changes"),
    ("Other side effects/health", "Other side effects<br>/ health"),
    ("Access/cost/convenience", "Access / cost<br>/ convenience"),
]
METHODS = ["Injectables", "Implants", "Pill", "IUD", "Other modern"]
MARKER_START = "<!-- BEGIN ACTIONABLE CAUSE MCPR CEILING -->"
MARKER_END = "<!-- END ACTIONABLE CAUSE MCPR CEILING -->"


def build(country: str, root: Path) -> None:
    nigeria = country == "nigeria"
    output = root / "output"
    report = output / ("Nigeria_discontinuation_analysis.html" if nigeria else "Ethiopia_discontinuation_analysis.html")
    data = output / "Supporting_data" / (
        "nigeria_current_users_actionable_by_cause.csv" if nigeria else "current_users_actionable_by_cause.csv"
    )
    outcome_year = 2025 if nigeria else 2026
    if nigeria:
        with (output/'Supporting_data/nigeria_wpp2024_wra_2024_2026.csv').open() as stream:
            wra = next(float(r['women_15_49']) for r in csv.DictReader(stream) if int(r['year'])==outcome_year)
    else:
        wra = 35_016_171
    country_name = "Nigeria" if nigeria else "Ethiopia"
    with data.open(newline="") as f:
        source = list(csv.DictReader(f))
    values = {}
    for row in source:
        method = row["method"]
        if method.startswith("All modern"):
            continue  # Ethiopia CSV also contains pre-aggregated totals.
        if method == "Other modern methods":
            method = "Other modern"
        reason = row["reason" if nigeria else "actionable_cause"]
        values[(method, reason)] = float(row["illustrative_users" if nigeria else "illustrative_method_endings"])
    for method in METHODS:
        for reason, _ in REASONS:
            assert (method, reason) in values, (country, method, reason)
    fmt = lambda x: f"{round(x):,}"
    totals = [sum(values[(method, reason)] for method in METHODS) for reason, _ in REASONS]
    grand_total = sum(totals)
    projection = output/'Supporting_data'/('nigeria_current_users_by_method_and_actionable_projection.csv' if nigeria else 'current_users_actionable_12_month_projection.csv')
    with projection.open() as stream:
        expected = sum(float(r['illustrative_original_method_endings' if nigeria else 'illustrative_actionable_method_endings']) for r in csv.DictReader(stream) if r['method'].replace('Other modern methods','Other modern') in METHODS)
    assert abs(grand_total-expected)<1e-4

    def tr(label: str, cells: list[str], css: str = "") -> str:
        return f'<tr class="{css}"><th scope="row">{html.escape(label)}</th>' + "".join(f"<td>{cell}</td>" for cell in cells) + "</tr>"

    body_rows = []
    for method in METHODS:
        nums = [values[(method, reason)] for reason, _ in REASONS]
        body_rows.append(tr(method, [fmt(x) for x in nums] + [f"<strong>{fmt(sum(nums))}</strong>"]))
    body_rows.append(tr("Estimated original-method endings", [f"<strong>{fmt(x)}</strong>" for x in totals] + [f"<strong>{fmt(grand_total)}</strong>"], "cause-total"))
    body_rows.append(tr(f"{outcome_year} women aged 15–49", [fmt(wra)] * 6, "cause-wra"))
    body_rows.append(tr("Maximum illustrative mCPR increase", [f"<strong>{x / wra * 100:.2f} pp</strong>" for x in totals] + [f"<strong>{grand_total / wra * 100:.2f} pp</strong>"], "cause-pp"))
    headers = "".join(f'<th scope="col">{label}</th>' for _, label in REASONS)
    section = f"""{MARKER_START}
<section id="actionable-cause-mcpr-ceiling" class="cause-mcpr-ceiling">
<style>
.cause-mcpr-ceiling .cause-table-wrap{{overflow-x:auto;border:1px solid #d9e3e8;border-radius:6px;margin:20px 0 12px}}
.cause-mcpr-ceiling table{{width:100%;border-collapse:collapse;font:14px/1.35 Arial,sans-serif;font-variant-numeric:tabular-nums;min-width:950px}}
.cause-mcpr-ceiling th,.cause-mcpr-ceiling td{{padding:13px 11px;border-bottom:1px solid #dbe3e7;text-align:right;white-space:nowrap}}
.cause-mcpr-ceiling thead th{{background:#1a4059;color:#fff;font-weight:700;white-space:normal;vertical-align:bottom}}
.cause-mcpr-ceiling thead th:first-child,.cause-mcpr-ceiling tbody th{{text-align:left;min-width:195px}}
.cause-mcpr-ceiling tbody tr:nth-child(even):not(.cause-total):not(.cause-wra):not(.cause-pp){{background:#f3f6f7}}
.cause-mcpr-ceiling tbody tr.cause-total{{background:#e5eff2;color:#173d55;font-weight:700}}
.cause-mcpr-ceiling tbody tr.cause-wra{{background:#fff5e1;color:#243542}}
.cause-mcpr-ceiling tbody tr.cause-pp{{background:#dbecee;color:#103f58;font-weight:700;border-top:2px solid #1a4059}}
.cause-mcpr-ceiling tbody tr.cause-total th,.cause-mcpr-ceiling tbody tr.cause-wra th,.cause-mcpr-ceiling tbody tr.cause-pp th{{background:inherit}}
</style>
<div class="eyebrow">Planning illustration</div>
<h2>Potential mCPR gain by actionable discontinuation cause</h2>
<p class="intro">The table apportions the existing estimated original-method endings among 2025 current users across five potentially actionable causes. Each column's final row divides its estimated endings by {fmt(wra)} projected women aged 15–49 in {country_name} in {outcome_year}. The all-causes column adds the five mutually exclusive causes.</p>
<div class="cause-table-wrap" role="region" aria-label="Potential {outcome_year} mCPR gain by method and actionable cause" tabindex="0"><table>
<thead><tr><th scope="col">Method / measure</th>{headers}<th scope="col">All actionable<br>causes</th></tr></thead>
<tbody>{''.join(body_rows)}</tbody></table></div>
<p class="note"><strong>Interpretation:</strong> These percentage-point values are gross upper bounds, not expected program effects. An ending of the original method does not necessarily reduce modern contraceptive prevalence: a woman may switch to another modern method or restart before year-end. The cause-specific counts apply first-year, 12-month life-table probabilities to current users without adjusting for how long they have already used the method. Emergency contraception has current users in mCPR but no ongoing-use discontinuation estimate and is not included in the table's endings.</p>
<p class="note"><strong>Source:</strong> Existing country method-by-cause projection in <a href="Supporting_data/{data.name}">{html.escape(data.name)}</a>; 2026 women aged 15–49 denominator from the preceding population section.</p>
</section>
{MARKER_END}"""
    text = report.read_text()
    if MARKER_START in text:
        text = re.sub(re.escape(MARKER_START) + r".*?" + re.escape(MARKER_END), section, text, flags=re.S)
    else:
        text = text.replace("<footer", section + "\n<footer", 1)
    if '#actionable-cause-mcpr-ceiling' not in text.split('</aside>')[0]:
        link = '<a href="#actionable-cause-mcpr-ceiling">mCPR gain by actionable cause</a>' if nigeria else '<div class="toc-group"><a class="toc-major" href="#actionable-cause-mcpr-ceiling" title="Potential mCPR gain by actionable cause">Potential mCPR gain by actionable cause</a></div>'
        if nigeria:
            text = text.replace("</aside>", link + "</aside>", 1)
        else:
            text = text.replace("</nav></aside>", link + "</nav></aside>", 1)
    report.write_text(text)
    print(report, f"{round(grand_total):,} endings", f"{grand_total / wra * 100:.2f} pp")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("country", nargs="?", choices=["nigeria", "ethiopia"], default="nigeria")
    parser.add_argument("root", nargs="?", type=Path, default=Path(os.environ["NIGERIA_PROJECT_ROOT"]))
    args = parser.parse_args()
    build(args.country, args.root)
)----------------------")

MODULES[["27_add_method_zone_models_to_html.py"]] <- list(language="Python", packaged_sha256="8190d5cf309ce2243fbb49c83aaaf188e9b9cfe1f2c4a2520f150c89d17a81c6", args=character(0), code=r"----------------------(#!/usr/bin/env python3
"""Add reproducible injectable/implant zone model results to Nigeria HTML.

The estimates are read from script 26 CSVs. Existing sections and numerical
tables are preserved; this insertion makes the within-method tests visible
alongside the all-modern six-zone regression analysis.
"""
import csv
import html
import re
from pathlib import Path
import os

ROOT = Path(os.environ["NIGERIA_PROJECT_ROOT"])
SUP = ROOT / 'output/Supporting_data'
PAGE = ROOT / 'output/Nigeria_discontinuation_analysis.html'
def read(name):
    with (SUP / name).open(newline='') as f:
        return list(csv.DictReader(f))
points = read('nigeria_actionable_injectable_implant_zone_probabilities.csv')
pairs = read('nigeria_actionable_injectable_implant_zone_pairwise.csv')
global_tests = read('nigeria_actionable_injectable_implant_zone_global.csv')
assert len(points) == 12 and len(pairs) == 60 and len(global_tests) == 4
zones = ['North West','North East','North Central','South East','South South','South West']
methods = ['Injectables','Implants']
for method in methods:
    assert {r['zone'] for r in points if r['method']==method} == set(zones)

def pct(x): return f'{float(x):.1f}'
def pval(x):
    v=float(x)
    return '&lt;0.001' if v<.001 else f'{v:.3f}'
def esc(x): return html.escape(str(x))

def chart(method):
    rows = [next(r for r in points if r['method']==method and r['zone']==z)
            for z in zones]
    width, height, x0, x1 = 920, 332, 250, 790
    max_rate = max(float(r[k]) for r in rows for k in
                   ['unadjusted_high','adjusted_high'])
    high = 45 if max_rate<=45 else 60
    X=lambda v: x0+(float(v)/high)*(x1-x0)
    svg=[f'<svg viewBox="0 0 {width} {height}" '
         'style="width:100%;max-width:920px;height:auto;display:block" role="img" '
         f'aria-label="{esc(method)}: observed and composition-adjusted '
         '12-month actionable discontinuation by zone">']
    for t in range(0,high+1,10):
        x=X(t)
        svg.append(f'<line x1="{x:.1f}" y1="21" x2="{x:.1f}" y2="284" '
                   'stroke="#E4EAF0"/>')
        svg.append(f'<text x="{x:.1f}" y="309" text-anchor="middle" '
                   f'font-size="14" fill="#415A69">{t}%</text>')
    for i,r in enumerate(rows):
        y=42+i*42
        svg.append(f'<text x="10" y="{y+7}" font-size="16" '
                   f'fill="#153F5B">{esc(r["zone"])}</text>')
        if i%2==0:
            svg.append(f'<line x1="{x0}" y1="{y+21}" x2="{x1}" '
                       f'y2="{y+21}" stroke="#F0F3F6"/>')
        for prefix,off,color in [('unadjusted',-6,'#DA9A25'),
                                 ('adjusted',6,'#153F5B')]:
            yy=y+off
            lo,hi,v=(float(r[prefix+'_'+q]) for q in
                     ('low','high','pct'))
            svg.append(f'<line x1="{X(lo):.1f}" y1="{yy}" '
                       f'x2="{X(hi):.1f}" y2="{yy}" '
                       f'stroke="{color}" stroke-width="2.4"/>')
            for x in (X(lo),X(hi)):
                svg.append(f'<line x1="{x:.1f}" y1="{yy-4}" '
                           f'x2="{x:.1f}" y2="{yy+4}" '
                           f'stroke="{color}" stroke-width="2"/>')
            svg.append(f'<circle cx="{X(v):.1f}" cy="{yy}" r="5" '
                       f'fill="{color}"/>')
            svg.append(f'<text x="{X(v)+9:.1f}" y="{yy+4}" '
                       f'font-size="12" fill="{color}">{v:.1f}</text>')
    svg.append('</svg>')
    return ''.join(svg)

parts=['<section id="method-zone-regressions" class="analysis-section">',
       '<div class="eyebrow">Subnational regression</div>',
       '<h2>Within-method comparisons across Nigeria’s six zones</h2>',
       '<p class="intro">Injectables and implants are analyzed separately. '
       'Each observed rate is the competing-risk life-table probability that '
       'an eligible episode of that method ends for a potentially actionable '
       'cause within 12 months. The fully adjusted model uses episode-month '
       'data and controls for month since method start, age and parity at '
       'start, marital status, education, wealth and residence measured at '
       'interview, and start year. '
       'Other method endings are competing events; late-entry episodes '
       'contribute only observed months. Adjusted predictions use the same '
       'national observed-start covariate composition within each method to '
       'make zone contrasts comparable.</p>',
       '<p class="small"><span style="color:#DA9A25">●</span> Observed '
       'and <span style="color:#153F5B">●</span> fully adjusted; '
       'horizontal lines are 95% stratified-PSU bootstrap intervals. '
       'This is an association analysis, not a causal estimate.</p>']
for method in methods:
    rows=[r for r in points if r['method']==method]
    g=next(r for r in global_tests if r['method']==method and
           r['stage']=='Fully adjusted')
    flagged=[r['zone'] for r in rows if r['precision_flag']]
    parts += [f'<h3>{esc(method)}: observed and fully adjusted risk</h3>',
              chart(method),
              f'<p class="small">Full-model omnibus test across six zones: '
              f'p = {pval(g["p_value"])}. '
              + (f'Exploratory precision flag (&lt;30 actionable endings): '
                 f'{esc(", ".join(flagged))}. ' if flagged else '')
              + 'The same-method comparison has no method-mix stage: every '
              'episode in this panel started the named method.</p>']
    selected=[r for r in pairs if r['method']==method and
              r['stage']=='Fully adjusted' and r['significant_5pct']=='TRUE']
    if selected:
        parts.append('<p><b>Fully adjusted zone pairs remaining distinguishable '
                     'after Holm correction:</b></p><div class="tablewrap"><table>'
                     '<thead><tr><th>Zones</th><th>Difference (pp)</th>'
                     '<th>95% bootstrap CI (pp)</th><th>Holm p</th></tr></thead><tbody>')
        for r in sorted(selected,key=lambda x:float(x['holm_p_within_method'])):
            parts.append('<tr><td>'+esc(r['zone_a'])+' vs '+esc(r['zone_b'])+
                         '</td><td class="num">'+f'{float(r["difference_pp"]):+.1f}'+
                         '</td><td class="num">'+
                         f'{float(r["ci_low_pp"]):+.1f} to '
                         f'{float(r["ci_high_pp"]):+.1f}'+
                         '</td><td class="num">'+pval(r['holm_p_within_method'])+
                         '</td></tr>')
        parts.append('</tbody></table></div>')
    else:
        parts.append('<p class="small">No fully adjusted zone pair remains '
                     'distinguishable at 5% after Holm correction of the '
                     '15 comparisons for this method.</p>')
    if method == 'Implants':
        across=sum(r['method']=='Implants' and
                   r['stage']=='Fully adjusted' and
                   float(r['holm_p_across_methods'])<.05 for r in pairs)
        parts.append(f'<p class="small">If the family is widened to all 30 '
                     f'adjusted injectable and implant zone pairs, {across} '
                     'implant contrasts remain below 5% after Holm correction.'
                     '</p>')
parts.append('<details><summary>Full pairwise results and testing details</summary>'
             '<p class="small">Two-sided Wald tests use standard errors from '
             'stratified PSU bootstrap contrasts. Holm correction is applied '
             'to all 15 zone pairs within each method and stage; the saved '
             'supporting CSV also includes a 30-comparison correction across '
             'both methods. A nonsignificant result does not establish equal '
             'risks. The method-specific models and bootstrap draws are '
             'reproduced by Code/26_nigeria_actionable_method_zone_models.R.'
             '</p><div class="tablewrap"><table><thead><tr><th>Method</th>'
             '<th>Stage</th><th>Zones</th><th>Difference (pp)</th>'
             '<th>Holm p within method</th></tr></thead><tbody>')
for r in pairs:
    parts.append('<tr><td>'+esc(r['method'])+'</td><td>'+esc(r['stage'])+
                 '</td><td>'+esc(r['zone_a'])+' vs '+esc(r['zone_b'])+
                 '</td><td class="num">'+f'{float(r["difference_pp"]):+.1f}'+
                 '</td><td class="num">'+pval(r['holm_p_within_method'])+
                 '</td></tr>')
parts.append('</tbody></table></div></details></section>')
section=''.join(parts)
page=PAGE.read_text(encoding='utf-8')
page=re.sub(r'<section id="method-zone-regressions".*?</section>',
            '',page,flags=re.S)
needle='<section id="regional-analyses"'
assert page.count(needle)==1
page=page.replace(needle,section+needle,1)
page=page.replace('Reproducible source: Code/01–17 in this Nigeria project.',
                  'Reproducible source: Nigeria Code/01–27, including the '
                  'method-specific zone models in scripts 26–27.')
nav='<a href="#method-zone-regressions">Injectable and implant zone models</a>'
if nav not in page:
    anchor='<a href="#regional-analyses">Regional analyses summary</a>'
    assert page.count(anchor)==1
    page=page.replace(anchor,nav+anchor,1)
PAGE.write_text(page,encoding='utf-8')
print(PAGE))----------------------")

MODULES[["28_add_method_scenario_tables.py"]] <- list(language="Python", packaged_sha256="587c58f0a931e193027bb832ef365d477062e22589e8c353cb87a08bd64c4d18", args=character(0), code=r"----------------------(#!/usr/bin/env python3
"""Reproduce Ethiopia-style method-level 2026 mCPR scenarios for Nigeria.

Current-method shares come from Nigeria DHS 2024 IR data. The three 2026
all-women mCPR and WRA scenarios are in the existing supporting CSV. EC remains
in mCPR but is assigned no ongoing-method discontinuation risk. This is an
illustrative gross original-method retention ceiling, not a forecast.
"""
import csv
import html
from pathlib import Path
import os

ROOT = Path(os.environ["NIGERIA_PROJECT_ROOT"])
SUP = ROOT / 'output/Supporting_data'
PAGE = ROOT / 'output/Nigeria_discontinuation_analysis.html'

def read(name):
    with (SUP / name).open(newline='') as f:
        return list(csv.DictReader(f))

scenarios = read('nigeria_2026_mcpr_scenarios.csv')
methods = read('nigeria_current_users_by_method_and_actionable_projection.csv')
assert len(scenarios) == 3 and len(methods) == 7
assert abs(sum(float(m['share_current_modern_pct']) for m in methods)-100) < 1e-8
gross = sum(float(m['illustrative_original_method_endings']) for m in methods)
assert all(abs(float(s['illustrative_gross_endings'])-gross) < .01 for s in scenarios)

def fmt(x): return f'{x:,.0f}'
def pct(x): return f'{x:.2f}%'

parts = ['<section id="method-level-mcpr-scenarios" class="analysis-section">',
         '<div class="eyebrow">Current-user planning</div>',
         '<h2>2026 mCPR scenarios by current method</h2>',
         '<p>The 2026 status-quo total comes from each all-women mCPR scenario '
         'multiplied by projected 2026 women aged 15–49. We allocate that '
         'total across methods using Nigeria DHS 2024 current-user shares. '
         'For the illustrative retention ceiling, we add the projected '
         '2025 current users whose original method would end within 12 months '
         'for a potentially actionable cause. This assumes every such ending '
         'is prevented and each woman still uses her original modern method '
         'at year end. It does not account for time already spent on the method, '
         'switching or re-entry, and it must not be interpreted as a forecast '
         'of net mCPR gain. EC remains in current mCPR but has no continuing-use '
         'discontinuation estimate.</p>']
for i,s in enumerate(scenarios, 1):
    wra=float(s['wra_2026']); usual=float(s['usual_users_2026'])
    parts.append(f'<h3>{i}. {html.escape(s["scenario"])}</h3>')
    parts.append('<div class="tablewrap"><table><thead><tr><th>Method</th>'
                 '<th>2025 current users</th><th>2026 usual users</th>'
                 '<th>2026 usual mCPR contribution</th>'
                 '<th>Illustrative endings prevented</th>'
                 '<th>2026 users if prevented</th>'
                 '<th>2026 mCPR contribution if prevented</th></tr></thead><tbody>')
    total_2025=total_usual=total_added=total_retained=0
    for m in methods:
        share=float(m['share_current_modern_pct'])/100
        u=usual*share; add=float(m['illustrative_original_method_endings'])
        retained=u+add
        total_2025 += float(m['current_users_2025'])
        total_usual += u; total_added += add; total_retained += retained
        parts.append('<tr><th>'+html.escape(m['method'])+'</th><td class="num">'
                     +fmt(float(m['current_users_2025']))+'</td><td class="num">'
                     +fmt(u)+'</td><td class="num">'+pct(100*u/wra)
                     +'</td><td class="num">'+fmt(add)+'</td><td class="num">'
                     +fmt(retained)+'</td><td class="num">'+pct(100*retained/wra)
                     +'</td></tr>')
    assert abs(total_usual-usual)<.01
    assert abs(total_retained-float(s['no_gross_endings_users_2026']))<.01
    parts.append('<tr class="total"><th>All modern methods</th><td class="num">'
                 +fmt(total_2025)+'</td><td class="num">'+fmt(total_usual)
                 +'</td><td class="num">'+pct(100*total_usual/wra)
                 +'</td><td class="num">'+fmt(total_added)
                 +'</td><td class="num">'+fmt(total_retained)
                 +'</td><td class="num">'+pct(100*total_retained/wra)
                 +'</td></tr></tbody></table></div>')
    parts.append('<p class="small">Projected 2026 women aged 15–49: '
                 +fmt(wra)+'. The illustrative gross ceiling exceeds the '
                 'usual 2026 mCPR by '+f'{100*total_added/wra:.2f}'
                 +' percentage points.</p>')
parts.append('</section>')
section=''.join(parts)
source=PAGE.read_text()
start=source.find('<section id="method-level-mcpr-scenarios"')
if start>=0:
    end=source.find('</section>',start)+len('</section>')
    source=source[:start]+source[end:]
anchor='<section id="switch-bridge"'
assert anchor in source
source=source.replace(anchor,section+anchor,1)
toc='<a href="#method-level-mcpr-scenarios">2026 mCPR by method</a>'
if toc not in source:
    old='<a href="#switch-bridge">'
    assert old in source
    source=source.replace(old,toc+old,1)
PAGE.write_text(source)
print(PAGE))----------------------")

MODULES[["30_add_zone_method_mix_decomposition_html.py"]] <- list(language="Python", packaged_sha256="5a10586ee5f0d84998a2110bd1692a8ed22f1dd06e5e51ff5dac0152c4977c1d", args=character(0), code=r"----------------------(#!/usr/bin/env python3
"""Add the reproducible six-zone method-mix diagnostic to Nigeria HTML."""
import csv
import html
from pathlib import Path
import os

root=Path(os.environ["NIGERIA_PROJECT_ROOT"])
support=root/'output/Supporting_data'
page=root/'output/Nigeria_discontinuation_analysis.html'
with (support/'nigeria_actionable_zone_method_mix_decomposition.csv').open() as f:
    data=list(csv.DictReader(f))
with (support/'nigeria_actionable_zone_method_mix_cells.csv').open() as f:
    cells=list(csv.DictReader(f))
assert len(data)==45 and len(cells)==24
by={(r['pair'],r['component']):r for r in data}
pairs=list(dict.fromkeys(r['pair'] for r in data))
def n(x): return f'{float(x):+.1f}'
def interval(r): return f'{n(r["ci_low_pp"])} to {n(r["ci_high_pp"])}'
parts=['<section id="regional-actionable-method-mix-decomposition" class="analysis-section">',
 '<div class="eyebrow">Subnational diagnostic</div>',
 '<h2>How much of each zone gap reflects method mix?</h2>',
 '<p>For each zone and method, we estimate the survey-weighted share of eligible modern-method episodes and the 12-month competing-risk probability of an ending for a potentially actionable cause. We pool IUD with other modern methods because several separate cells are sparse. For each pair, a symmetric decomposition divides the constructed gap into (1) the difference in episode method shares, averaged over the two zones’ method-specific risks, and (2) the difference in within-method risks, averaged over their method shares. These components add exactly to the constructed gap. This is a descriptive accounting identity, not a causal estimate. The constructed gap can differ from the directly pooled all-modern life table because the method-specific cumulative incidences are combined using episode shares. Confidence intervals use 500 resamples of survey clusters within strata.</p>',
 '<p>For North East versus South East, the constructed gap is <b>+19.3 percentage points</b>. Different method shares account for <b>+3.5 points</b>; differences within methods account for <b>+15.8 points</b>. Sparse method-by-zone cells, especially South East pill and injectable endings, warrant caution.</p>',
 '<div class="tablewrap"><table><thead><tr><th>Zone contrast</th><th>Constructed gap (pp)</th><th>Method mix (pp)</th><th>Within-method risk (pp)</th><th>95% CI for mix</th><th>95% CI for within</th></tr></thead><tbody>']
for pair in pairs:
    gap=by[pair,'gap']; mix=by[pair,'mix']; within=by[pair,'within']
    assert abs(float(gap['estimate_pp'])-float(mix['estimate_pp'])-float(within['estimate_pp']))<1e-7
    parts.append('<tr><th>'+html.escape(pair)+'</th><td class="num">'+n(gap['estimate_pp'])+
      '</td><td class="num">'+n(mix['estimate_pp'])+'</td><td class="num">'+
      n(within['estimate_pp'])+'</td><td class="num">'+interval(mix)+
      '</td><td class="num">'+interval(within)+'</td></tr>')
parts.append('</tbody></table></div><p class="small">Positive values mean the first zone has higher constructed actionable discontinuation than the second. Episode method shares are not the share of observed new starts. This table is a diagnostic for targeting further investigation; the adjusted model and design-based pairwise tests elsewhere in this report address inferential comparisons.</p></section>')
section=''.join(parts)
source=page.read_text()
start=source.find('<section id="regional-actionable-method-mix-decomposition"')
if start>=0:
    end=source.find('</section>',start)+len('</section>')
    source=source[:start]+source[end:]
anchor='<section id="regional-analyses"'
assert anchor in source
source=source.replace(anchor,section+anchor,1)
toc='<a href="#regional-actionable-method-mix-decomposition">Method-mix decomposition</a>'
if toc not in source:
    old='<a href="#regional-analyses">'
    assert old in source
    source=source.replace(old,toc+old,1)
page.write_text(source)
print(page))----------------------")

MODULES[["36_add_alluvial_pathways_html.py"]] <- list(language="Python", packaged_sha256="87a0b2a2736ccedeb53bb0712e09b231e40085d0113a3a89bb3b5a9db571b575", args=character(0), code=r"----------------------(#!/usr/bin/env python3
"""Insert Nigeria episode and current-user pathway sections into working HTML."""
import csv
import html
from pathlib import Path
import os

root=Path(os.environ["NIGERIA_PROJECT_ROOT"])
support=root/'output/Supporting_data';page=root/'output/Nigeria_discontinuation_analysis.html'
def read(name):
    with (support/name).open(newline='') as f:return list(csv.DictReader(f))
summary=read('nigeria_standardized_current_user_pathway_summary.csv')
flows=read('nigeria_injectable_reason_destination_flows.csv')
timing=read('nigeria_injectable_reason_timing_destination.csv')
historical=read('nigeria_current_user_pathway_flows.csv')
stock={r['outcome']:float(r['pct']) for r in summary}
assert abs(sum(stock.values())-100)<1e-8
assert abs(sum(float(r['pct']) for r in flows)-100)<1e-8
assert abs(sum(float(r['pct']) for r in historical)-100)<1e-8
reason_order=['Method failure','Wanted more effective method',
 'Changes in menstrual bleeding','Other side effects/health','Access/cost/convenience']
dest_order=['Different modern method','Same modern method','No method recorded',
 'Pregnancy, birth or termination','Traditional/other method','Other/unknown']

def table(head,rows):
    return ('<div class="tablewrap"><table><thead><tr>'+''.join('<th>'+html.escape(x)+'</th>' for x in head)+
      '</tr></thead><tbody>'+''.join('<tr>'+''.join('<td>'+html.escape(str(x))+'</td>' for x in row)+'</tr>' for row in rows)+
      '</tbody></table></div>')
def img(name,alt):
    return '<figure style="margin:1.2rem 0"><img src="assets/'+name+'" alt="'+html.escape(alt)+'" style="width:100%;height:auto"></figure>'
actions=[
 ('Early injectable endings','Actionable injectable risk reaches 10.8% by month 3 and 29.6% by month 12.','Prioritize early follow-up and easy resupply.'),
 ('Bleeding and other side effects','These reasons together account for a large share of actionable injectable endings.','Offer anticipatory counseling, treatment and same-visit method alternatives.'),
 ('No method one month later','80.6% of the observed injectable actionable endings with follow-up had no method recorded one month later.','Make immediate modern switching and re-entry services accessible.'),
]
section1=('''<section id="action-pathways" class="analysis-section">
<div class="eyebrow">Post-discontinuation pathways</div><h2>From injectable endings to program action</h2>
<p>The first alluvial follows observed first-year injectable episodes that ended for a potentially actionable reason and had one calendar month of follow-up. Its denominator is discontinuation events, not all injectable episodes. The second alluvial follows one historical modern-method user per woman from 15 months before interview through the next 12 observed calendar months. It therefore uses women, not episodes, as its denominator. Direct modern switching without a qualifying gap remains continuous modern use; restarting after a gap is re-entry.</p>'''+
img('nigeria_injectable_reason_destination_alluvial.png','Actionable injectable ending reason connected to method status one month later')+
table(['Program signal','Nigeria DHS 2024 finding','Potential response'],actions)+
img('nigeria_current_user_pathway_3_12_alluvial.png','Historical current modern method users linked to month 3 and month 12 states')+
'''<p class="small">The historical pathway is a descriptive prototype. It does not predict the actual 2025–26 cohort without a transportability assumption. EC is included because it is reported as current modern use in the DHS, but it is not treated as an ongoing method in original-method discontinuation life tables.</p>
<p class="small"><a href="Supporting_data/nigeria_injectable_reason_destination_flows.csv">Injectable reason-to-destination flow data</a> · <a href="Supporting_data/nigeria_injectable_reason_timing_destination.csv">Reason, episode duration and destination data</a> · <a href="Supporting_data/nigeria_current_user_pathway_flows.csv">Historical pathway flows</a> · <a href="../Code/34_nigeria_historical_current_user_pathways.R">Historical pathway code</a> · <a href="../Code/35_nigeria_alluvial_figures.R">Figure code</a></p></section>''')
rows=[]
for name in ['No gross exit: baseline method','No gross exit: modern switch',
             'Gross exit: re-entered by month 12','Gross exit: net absent at month 12']:
    rows.append((name,f'{stock[name]:.1f}%'))
section2=('''<section id="standardized-current-users" class="analysis-section">
<div class="eyebrow">Current-user standardization</div><h2>Expected pathway among current modern users</h2>
<p>The following illustration estimates the 12-month pathway for the interview-date current-user stock. Historical outcome probabilities are calculated within four method groups and five completed-duration groups, then averaged using the DHS-weighted method-duration distribution of current users. The historical follow-up contains 3,747 women, and the current-stock standardization uses 5,357 DHS respondents using a modern method: reversible-method users with known duration, plus permanent-method users who remain in the baseline-method group. These are weighted percentages per 100 current users; they are not 12-month original-method discontinuation rates.</p>'''+
img('nigeria_standardized_current_user_stock_alluvial.png','Standardized current user stock to gross modern-use exit and month 12 outcome')+
table(['12-month pathway','Percent of current modern users'],rows)+
'''<p class="small">A gross exit is any month outside modern use. Continuous modern-to-modern switching remains in modern use. Re-entry is modern use at month 12 after an earlier exit. Net absence combines no modern method and pregnancy-related calendar states at month 12. This descriptive transport from past calendar users assumes historical method-duration risks apply to current users; it does not estimate the causal effect of preventing a particular reason for discontinuation. EC is grouped with other modern methods for mCPR consistency, although it is a one-time method.</p>
<p class="small"><a href="Supporting_data/nigeria_standardized_current_user_pathway_summary.csv">Standardized outcomes</a> · <a href="Supporting_data/nigeria_current_user_method_duration_distribution.csv">Current-user distribution</a> · <a href="Supporting_data/nigeria_historical_method_duration_pathway_probabilities.csv">Historical conditional probabilities</a> · <a href="Supporting_data/nigeria_standardized_current_user_pathway_contributions.csv">Standardization contributions</a></p></section>''')

source=page.read_text()
for anchor in ('action-pathways','standardized-current-users'):
    start=source.find(f'<section id="{anchor}"')
    if start>=0:
        end=source.find('</section>',start)+len('</section>')
        source=source[:start]+source[end:]
anchor='<section id="population"'
assert anchor in source
source=source.replace(anchor,section1+section2+anchor,1)
for id,label in [('action-pathways','Actionable pathways'),
                 ('standardized-current-users','Current-user pathway')]:
    toc=f'<a href="#{id}">{label}</a>'
    if toc not in source:
        old='<a href="#population">'
        assert old in source
        source=source.replace(old,toc+old,1)
page.write_text(source)
print(page))----------------------")

MODULES[["39_add_selected_exploratory_html.py"]] <- list(language="Python", packaged_sha256="5bb8b8693e5c5b06e41bd3b6937ba2122a523ae94b881509e4638b79d26c6e96", args=character(0), code=r"----------------------(#!/usr/bin/env python3
"""Add Nigeria counterparts of Ethiopia's selected-reason exploratory tables."""
import csv
import html
from pathlib import Path
import os

root=Path(os.environ["NIGERIA_PROJECT_ROOT"]);out=root/'output';sup=out/'Supporting_data'
page=out/'Nigeria_discontinuation_analysis.html'
def read(name):
    with (sup/name).open(newline='') as f:return list(csv.DictReader(f))
data=read('nigeria_selected_reason_extensions.csv')
other=read('nigeria_other_reason_code_breakdown.csv')
follow=read('nigeria_other_reason_followup.csv')
starts=read('nigeria_zone_all_method_start_mix.csv')
alltime=read('nigeria_modern_all_reason_timepoints.csv')
by={r['scope']:r for r in data}
reason_names=['Method failure','Other fertility-related','Changes in menstrual bleeding',
 'Other side effects/health','Wanted more effective method','Access/cost/convenience',
 'Other recorded reasons']
action_idx=[1,3,4,5,6]
variables=['age_group','parity_group','marital_group','education','wealth','residence']
varlabel={'age_group':'Age at method start','parity_group':'Parity at method start',
 'marital_group':'Marital status','education':'Education','wealth':'Wealth quintile',
 'residence':'Residence'}
zones=['North West','North East','North Central','South East','South South','South West']
methods=['Injectables','Implants','Pill','IUD','Other modern']
def num(x,n=1):return f'{float(x):.{n}f}'
def pct(x,n=1):return num(x,n)+'%'
def safe(x):return html.escape(str(x))
def table(head,rows):
 return ('<div class="tablewrap"><table><thead><tr>'+''.join('<th>'+safe(x)+'</th>' for x in head)+
 '</tr></thead><tbody>'+''.join('<tr>'+''.join('<td>'+safe(x)+'</td>' for x in row)+'</tr>' for row in rows)+
 '</tbody></table></div>')
def reasons(r,indices=range(1,8),top=None):
 v=[(reason_names[j-1],float(r[f'cause_{j}_pct'])) for j in indices]
 total=sum(x[1] for x in v)
 v.sort(key=lambda x:-x[1]);v=v[:top] if top else v
 return '; '.join(f'{name} {100*val/total:.1f}%' for name,val in v) if total else 'Insufficient data'
def heat_cell(v):
 strength=min(.62,.08+float(v)/100*.75)
 # navy tint, black numerals, consistent with presentation palette
 color=f'rgba(21,63,91,{strength:.3f})'
 return f'<td style="background:{color};color:#111;font-weight:400;text-align:center">{float(v):.1f}</td>'
def section(id,title,intro,body):
 return f'<section id="{id}" class="analysis-section"><div class="eyebrow">Selected-reason analysis</div><h2>{safe(title)}</h2><p>{intro}</p>{body}</section>'

labels={9:'Infrequent sex / husband away',11:'Up to God / fatalistic',
 12:'Difficult to get pregnant / menopausal',13:'Marital dissolution / separation',
 96:'Other specified',98:'Do not know',99:'Missing / unknown',0:'Unspecified'}
other_rows=[]
for r in other:
 code=int(float(r['reason_code']))
 other_rows.append((r['group'],labels[code],r['endings_n'],num(r['wt'],1)))
parts=[]
parts.append(section('other-reasons-count-breakdown','What falls under “Other” reasons?',
 'The first-year modern-method episode cohort distinguishes other fertility-related reasons from residual recorded reasons. These counts are among observed first-year endings; they are not life-table probabilities. EC is excluded.',
 table(['Group','Recorded reason','Observed endings','Weighted endings'],other_rows)))
follow_rows=[]
for code in sorted({int(float(r['reason_code'])) for r in follow}):
 for month in (1,12):
  rows=[r for r in follow if int(float(r['reason_code']))==code and int(float(r['month_after_ending']))==month]
  if not rows:continue
  sums={k:sum(float(r['share_within_reason_pct']) for r in rows if r['destination']==k)
        for k in ['No method recorded','Same modern method','Different modern method',
                  'Pregnancy, birth or termination','Traditional/other/unknown']}
  n=sum(int(float(r['endings_n'])) for r in rows)
  follow_rows.append((labels[code],str(month),str(n),*(pct(sums[k]) for k in sums)))
parts.append(section('other-reason-followup','What follows an “Other” ending?',
 'Each row conditions on an observed first-year ending for the named reason and on having the follow-up month recorded. The 1- and 12-month rows can have different denominators. Sparse reasons are descriptive only.',
 table(['Recorded reason','Month after ending','N','No method','Same modern','Different modern','Pregnancy/birth','Traditional/unknown'],follow_rows)))

subrows=[]
for f in variables:
 for r in [x for x in data if x['variable']==f]:
  ci=(f'{num(r["ci_low"])}–{num(r["ci_high"])}%' if r['ci_low'] not in ('','NA') else '—')
  subrows.append((varlabel[f],r['category'],r['eligible_episodes_n'],
                  pct(r['selected_12_month_pct']),ci,reasons(r)))
parts.append(section('selected-reason-descriptive-subgroups',
 'Unadjusted 12-month selected-reason discontinuation by subgroup',
 'Among all eligible modern-method episodes, the event is ending the original method for any recorded reason except wanted pregnancy or partner disapproval. Those two endings remain competing events. Confidence intervals use 300 stratified-PSU bootstrap replicates; demographic variables other than age and parity are measured at interview. Reason shares within each row add to 100% before rounding.',
 table(['Covariate','Category','Eligible episodes','12-month risk','95% CI','Reasons ranked by share'],subrows)))

actrows=[]
for f in variables:
 for r in [x for x in data if x['variable']==f]:
  total=sum(float(r[f'cause_{j}_pct']) for j in action_idx)
  actrows.append((varlabel[f],r['category'],r['selected_endings_n'],
    pct(total),reasons(r,action_idx)))
parts.append(section('method-experience-subgroup-reasons',
 'Method experience and access reasons within subgroups',
 'The five potentially actionable reasons are method failure, changes in menstrual bleeding, other side effects or health, wanting a more effective method, and access/cost/convenience. Their 12-month cumulative incidences use all eligible modern episodes; their shares are normalized within those five reasons and add to 100% in each row. This is descriptive, not an adjusted subgroup contrast.',
 table(['Covariate','Category','Selected endings (all retained reasons)','Actionable 12-month risk','Five actionable reasons ranked by share'],actrows)))

toprows=[]
for method in ['All modern','Injectables','Pill','IUD']:
 for f in variables:
  source=[r for r in data if r['variable']==f] if method=='All modern' else \
    [r for r in data if r['variable']=='method_subgroup' and r['category'].startswith(method+' / '+f+' / ')]
  for r in source:
   cat=r['category'] if method=='All modern' else r['category'].split(' / ',2)[-1]
   total=sum(float(r[f'cause_{j}_pct']) for j in action_idx)
   vals=[(reason_names[j-1],float(r[f'cause_{j}_pct'])) for j in action_idx]
   vals.sort(key=lambda x:-x[1])
   n=int(float(r['selected_endings_n']))
   ranked=[f'{name}: {val:.1f}% of episodes; {100*val/total:.1f}% of actionable risk' for name,val in vals[:3]] if n>=10 and total>0 else ['Withheld: <10 selected endings']
   toprows.append((method,varlabel[f],cat,str(n),*([*ranked]+['—']*(3-len(ranked)))))
parts.append(section('top-three-reasons-by-subgroup-method',
 'Top three actionable reasons by subgroup and method',
 'Rankings use absolute reason-specific 12-month cumulative probability, among eligible episodes of the named method and subgroup. The second percentage in each cell is the reason’s share of the five actionable reasons. Rankings with fewer than 10 selected endings are withheld; 10–29 endings remain tentative. No reason-specific intervals are claimed.',
 table(['Method','Covariate','Category','Selected endings','First','Second','Third'],toprows)))

classrows=[]
for r in [x for x in data if x['variable']=='duration_class']:
  ci=(f'{num(r["ci_low"])}–{num(r["ci_high"])}%' if r['ci_low'] not in ('','NA') else '—')
  classrows.append((r['category'],r['eligible_episodes_n'],r['selected_endings_n'],
                    pct(r['selected_12_month_pct']),ci))
parts.append(section('method-duration-class-discontinuation',
 'Selected-reason risk by method-duration class',
 'Short-acting reversible includes injectables, pills and male condoms; long-acting reversible includes implants and IUDs. The mixed group contains other modern methods and is not a coherent duration class. The same competing-risk definition and all-eligible-episode denominator apply.',
 table(['Method category','Eligible episodes','Selected endings','12-month risk','95% CI'],classrows)))
short=by['duration_class::Short-acting reversible']
shortrows=[]
for j,name in enumerate(reason_names,1):
 shortrows.append((name,pct(short[f'share_{j}_pct']),pct(short[f'cause_{j}_pct'])))
parts.append(section('short-acting-selected-reason-distribution',
 'Why short-acting modern methods ended within 12 months',
 'The weighted shares describe the distribution of reasons among selected first-year discontinuations of injectables, pills and male condoms. Shares sum to 100% before rounding. The adjacent risk column uses all eligible short-acting episodes as its denominator.',
 table(['Recorded reason','Share of selected reasons','12-month cause-specific risk'],shortrows)))

zone_rows=[]
for scope in ['Overall::All modern']+['zone_name::'+z for z in zones]:
 r=by[scope];label='National' if scope.startswith('Overall') else r['category']
 ci=f'{num(r["ci_low"])}–{num(r["ci_high"])}%'
 zone_rows.append((label,r['eligible_episodes_n'],pct(r['selected_12_month_pct']),ci,
                   reasons(r)))
parts.append(section('selected-reason-regional-analysis',
 'Selected-reason discontinuation across Nigeria’s six zones',
 'Observed 12-month probabilities use eligible modern episodes in each zone. The seven reason shares are conditional on that zone’s selected-reason cumulative incidence and add to 100% before rounding. This is the intermediate outcome, before restricting to potentially actionable causes.',
 table(['Zone','Eligible episodes','12-month risk','95% CI','Reasons ranked by share'],zone_rows)))
heat=(['<div class="tablewrap"><table><thead><tr><th>Zone</th>']+
      [f'<th>{safe(x)}</th>' for x in reason_names]+['</tr></thead><tbody>'])
for scope in ['Overall::All modern']+['zone_name::'+z for z in zones]:
 r=by[scope];label='National' if scope.startswith('Overall') else r['category']
 heat.append('<tr><th>'+safe(label)+'</th>'+''.join(heat_cell(r[f'share_{j}_pct']) for j in range(1,8))+'</tr>')
heat.append('</tbody></table></div>')
parts.append(section('selected-reason-regional-reason-heatmap',
 'Reason mix among selected discontinuations by zone',
 'Each zone row sums to 100% before rounding. These are shares of selected discontinuations, not probabilities among all method episodes. National is shown first as a comparison.',
 ''.join(heat)))

mixrows=[]
for zone in ['National']+zones:
 z=by['Overall::All modern'] if zone=='National' else by['zone_name::'+zone]
 for m in methods:
  scope=f'zone_method::{zone}::{m}' if zone!='National' else f'method_group::{m}'
  r=by.get(scope)
  if not r:continue
  share=100*float(r['weighted_episodes'])/float(z['weighted_episodes'])
  mixrows.append((zone,m,pct(share),pct(r['selected_12_month_pct']),
                  r['eligible_episodes_n'],'*' if r['limited_precision']=='TRUE' else ''))
parts.append(section('regional-episode-mix-and-risk',
 'Episode method mix and within-method selected-reason risk',
 'The share column is each method’s survey-weighted share of eligible modern episodes within the zone. The risk column is the 12-month selected-reason probability among episodes of that method in that zone. These denominators differ from observed initiation shares. An asterisk flags fewer than 30 selected endings.',
 table(['Zone','Method','Share of eligible episodes','Within-method 12-month risk','Eligible episodes','Flag'],mixrows)))

start={(r['scope'],r['method']):r for r in starts}
allrisk={(r['scope']):r for r in alltime if int(float(r['month']))==12}
paired=[]
for zone in ['National']+zones:
 ec=start[(zone,'Emergency contraception')]
 denom_weight=float(ec['denominator_weighted_starts'])-float(ec['weighted_starts'])
 denom_n=int(float(ec['denominator_observed_starts_n']))-int(float(ec['observed_starts_n']))
 for m in methods:
  share=start.get((zone,m));risk=allrisk.get(zone+': '+m)
  if not share or not risk:continue
  paired.append((zone,m,pct(100*float(share['weighted_starts'])/denom_weight),
                 pct(risk['all_reason_pct']),str(denom_n),risk['eligible_episodes_n']))
parts.append(section('regional-method-paired-bars',
 'Method starts and all-reason discontinuation by zone',
 'This reproduces the two measures in Ethiopia’s paired-bar extension. Gold start shares use observed contraceptive starts in the zone, excluding EC from numerator and denominator but retaining non-modern methods. The 12-month all-reason risk uses eligible episodes of the named original modern method; it includes switching as original-method discontinuation. The two columns therefore have deliberately different denominators.',
 table(['Zone','Method','Share of all starts','12-month all-reason risk','Observed starts denominator','Eligible method episodes'],paired)))

section_html=''.join(parts)
source=page.read_text()
ids=['other-reasons-count-breakdown','other-reason-followup','selected-reason-descriptive-subgroups',
 'method-experience-subgroup-reasons','top-three-reasons-by-subgroup-method',
 'method-duration-class-discontinuation','short-acting-selected-reason-distribution',
 'selected-reason-regional-analysis','selected-reason-regional-reason-heatmap',
 'regional-episode-mix-and-risk','regional-method-paired-bars']
for id in ids:
 start=source.find(f'<section id="{id}"')
 if start>=0:
  end=source.find('</section>',start)+len('</section>')
  source=source[:start]+source[end:]
anchor='<section id="national"';assert anchor in source
source=source.replace(anchor,section_html+anchor,1)
for id in ids:
 toc=f'<a href="#{id}">{id.replace("-"," ").capitalize()}</a>'
 if f'href="#{id}"' not in source:
  old='<a href="#national">';assert old in source
  source=source.replace(old,toc+old,1)
page.write_text(source)
print(page,len(ids),'sections'))----------------------")

MODULES[["41_add_selected_current_user_planning_html.py"]] <- list(language="Python", packaged_sha256="79e4678d247c92c113a75642ac4138f8bd971a861cf332c690295dcb73efddd3", args=character(0), code=r"----------------------(#!/usr/bin/env python3
"""Add Ethiopia-style selected-reason current-user planning tables to Nigeria."""
import csv,html
from pathlib import Path
import os
root=Path(os.environ["NIGERIA_PROJECT_ROOT"]);sup=root/'output/Supporting_data'
page=root/'output/Nigeria_discontinuation_analysis.html'
def read(n):
 with (sup/n).open(newline='') as f:return list(csv.DictReader(f))
planning=read('nigeria_selected_current_user_method_reason_planning.csv')
users=read('nigeria_current_users_by_method_and_actionable_projection.csv')
methods=['Injectables','Implants','Pill','IUD','Other modern']
reasons=list(dict.fromkeys(r['reason'] for r in planning))
assert len(planning)==35 and len(reasons)==7
stock={r['method']:float(r['current_users_2025']) for r in users}
stock_all=sum(stock.values())
def n(x):return f'{float(x):,.0f}'
def p(x):return f'{float(x):.2f}%'
def tab(head,rows):
 return ('<div class="tablewrap"><table><thead><tr>'+''.join('<th>'+html.escape(x)+'</th>' for x in head)+
 '</tr></thead><tbody>'+''.join('<tr>'+''.join('<td>'+html.escape(str(x))+'</td>' for x in row)+'</tr>' for row in rows)+
 '</tbody></table></div>')
def blocks(kind):
 col_risk='first_year_cause_risk_pct' if kind=='first' else 'duration_aware_next12_risk_pct'
 col_count='first_year_illustrative_endings' if kind=='first' else 'duration_aware_illustrative_endings'
 parts=[]
 for method in methods:
  z=[r for r in planning if r['method']==method]
  rows=[(r['reason'],p(r[col_risk]),n(r[col_count])) for r in z]
  rows.append(('All selected reasons',p(sum(float(r[col_risk]) for r in z)),
               n(sum(float(r[col_count]) for r in z))))
  parts.append(f'<h3>{html.escape(method)}: {n(stock[method])} projected 2025 current users</h3>')
  parts.append(tab(['Recorded reason','12-month probability','Illustrative original-method endings'],rows))
 allrows=[]
 for reason in reasons:
  z=[r for r in planning if r['reason']==reason]
  count=sum(float(r[col_count]) for r in z)
  allrows.append((reason,n(count),p(100*count/stock_all)))
 allcount=sum(float(r[col_count]) for r in planning)
 allrows.append(('All selected reasons',n(allcount),p(100*allcount/stock_all)))
 parts.append(f'<h3>All current modern users: {n(stock_all)} projected 2025 users, including EC</h3>')
 parts.append(tab(['Recorded reason','Illustrative original-method endings','As a share of all current modern users'],allrows))
 parts.append('<p class="small">EC is included in the current mCPR stock but contributes zero ongoing original-method endings. The all-modern percentage in this table is an illustrative ratio of projected endings to current users, not a pooled life-table cumulative incidence.</p>')
 return ''.join(parts)

compare=tab(['Approach','Probability source','Question answered','Main limitation'],[
 ('First year after a method start','Reason-specific competing-risk cumulative incidence in months 1–12 after method start','If current users faced the first-year risk observed after new starts, how many original methods would end?','Treats every current user as a new starter.'),
 ('Next 12 months after elapsed use','Historical landmark probability of an ending in the next 12 observed months, conditional on method and completed duration, standardized to current users','How many current users might end their original method over the next year given their duration mix?','Transports historical risks to the projected stock; 61+ month users use a 37–60 month proxy.')])
sec1=('<section id="current-user-reason-planning" class="analysis-section"><div class="eyebrow">Selected-reason planning</div>'
 '<h2>Illustrative first-year method endings by selected reason</h2>'
 '<p>Each current-user count is the projected 2025 stock from DHS 2024 mCPR, DHS 2024 current method shares and projected 2025 women aged 15–49. We multiply it by the method- and reason-specific 12-month competing-risk cumulative incidence from eligible original-method episodes. Wanted pregnancy and partner disapproval are excluded as events of interest but remain competing events. These figures count original-method endings, including women who switch to another modern method; they are not forecasts of net loss from mCPR.</p>'+blocks('first')+'</section>')
sec2=('<section id="duration-adjusted-reason-planning" class="analysis-section"><div class="eyebrow">Duration-aware planning</div>'
 '<h2>Next-year original-method endings among current users</h2>'
 '<p>These tables use historical landmark probabilities of an ending in the next 12 observed months, estimated within method and completed-duration bins and weighted to the projected current-user duration mix. The event remains any selected reason other than wanted pregnancy or partner disapproval; modern switching still counts as ending the original method. The 61+ month current-user group uses a 37–60 month historical risk proxy because 12-month follow-up at that duration is unavailable in the DHS calendar. Results are descriptive illustrations, not causal forecasts.</p>'+compare+blocks('duration')+
 '<p class="small"><a href="Supporting_data/nigeria_selected_current_user_method_reason_planning.csv">Download method-by-reason probabilities and counts</a> · <a href="../Code/40_nigeria_selected_current_user_planning.R">Open documented R code</a></p></section>')
source=page.read_text()
for id in ('current-user-reason-planning','duration-adjusted-reason-planning'):
 start=source.find(f'<section id="{id}"')
 if start>=0:
  end=source.find('</section>',start)+len('</section>')
  source=source[:start]+source[end:]
anchor='<section id="mcpr-scenarios"';assert anchor in source
source=source.replace(anchor,sec1+sec2+anchor,1)
for id,label in [('current-user-reason-planning','Selected-reason current users'),
                 ('duration-adjusted-reason-planning','Duration-aware selected reasons')]:
 toc=f'<a href="#{id}">{label}</a>'
 if f'href="#{id}"' not in source:
  old='<a href="#mcpr-scenarios">';assert old in source
  source=source.replace(old,toc+old,1)
page.write_text(source)
print(page))----------------------")

MODULES[["43_add_selected_risk_strata_html.py"]] <- list(language="Python", packaged_sha256="37613d20530fabb3df9268c324836880a449f23fc9e5f18f5d105766dd129b55", args=character(0), code=r"----------------------(#!/usr/bin/env python3
"""Present the Nigeria out-of-fold selected-reason risk strata and profiles."""
import csv,html
from pathlib import Path
import os
root=Path(os.environ["NIGERIA_PROJECT_ROOT"]);out=root/'output';sup=out/'Supporting_data'
page=out/'Nigeria_discontinuation_analysis.html'
def read(n):
 with (sup/n).open(newline='') as f:return list(csv.DictReader(f))
strata=read('nigeria_selected_reason_crossvalidated_risk_strata.csv')
diff=read('nigeria_selected_reason_risk_strata_differences.csv')
profiles=read('nigeria_selected_reason_risk_strata_profiles.csv')
audit=read('nigeria_selected_reason_risk_strata_audit.csv')[0]
assert len(strata)==3 and len(diff)==3
def n(x):return f'{float(x):.1f}'
def tab(head,rows):return '<div class="tablewrap"><table><thead><tr>'+''.join('<th>'+html.escape(h)+'</th>' for h in head)+'</tr></thead><tbody>'+''.join('<tr>'+''.join('<td>'+html.escape(str(x))+'</td>' for x in row)+'</tr>' for row in rows)+'</tbody></table></div>'
rows=[(r['risk_stratum'],r['eligible_episodes'],n(r['weighted_share_pct'])+'%',
       n(r['predicted_risk_median_pct'])+'%',n(r['observed_12_month_probability_pct'])+'%',
       n(r['ci_low'])+'–'+n(r['ci_high'])+'%') for r in strata]
contrasts=[(r['comparison'],n(r['estimate_pp'])+' pp',n(r['ci_low'])+' to '+n(r['ci_high'])+' pp') for r in diff]
profile=[]
for characteristic in ('method_group','age_group','parity_group','marital_group','education','wealth','residence'):
 for level in dict.fromkeys(r['level'] for r in profiles if r['characteristic']==characteristic):
  vals=[]
  for stratum in ('Lower','Middle','Higher'):
   r=next(x for x in profiles if x['characteristic']==characteristic and x['level']==level and x['risk_stratum']==stratum)
   vals.append(n(r['weighted_share_within_stratum_pct'])+'%')
  profile.append((characteristic.replace('_',' ').title(),level,*vals))
section=('<section id="selected-reason-risk-strata" class="analysis-section">'
 '<div class="eyebrow">Exploratory risk profiles</div><h2>Cross-validated lower, middle and higher risk bands</h2>'
 '<p>Five folds are assigned by DHS sampling cluster within stratum. A weighted discrete-time competing-outcome model trained outside each episode’s cluster predicts 12-month selected-reason risk from method, age at start and parity at start. Excluded pregnancy and partner endings remain competing outcomes. Episodes are split into three roughly equal weighted bands of out-of-fold predicted risk. Observed band-specific rates are recalculated with the life table, retaining delayed entry. This is a risk-profile analysis of episodes, not a clustering of women.</p>'+tab(['Band','Eligible episodes','Weighted share','Median predicted risk','Observed 12-month risk','95% bootstrap CI'],rows)+
 '<p>In Nigeria, all three observed bands are distinguishable in the fixed-score survey bootstrap. Their differences are:</p>'+tab(['Contrast','Difference','95% bootstrap CI'],contrasts)+
 '<h3>Characteristics represented within each risk band</h3>'+tab(['Covariate','Category','Lower','Middle','Higher'],profile)+
 '<p class="small">Method, age and parity create the score, so their profile differences are partly mechanical. Marital status, education, wealth and residence are observed at interview and were not score inputs; earlier episodes may have had different values. Bootstrap intervals hold model scores and cut points fixed and do not include model-training uncertainty.</p>'
 '<p class="small"><a href="Supporting_data/nigeria_selected_reason_crossvalidated_risk_strata.csv">Risk-band results</a> · <a href="Supporting_data/nigeria_selected_reason_risk_strata_profiles.csv">Profile data</a> · <a href="../Code/42_nigeria_crossvalidated_selected_risk_strata.R">Documented model code</a></p></section>')
source=page.read_text();start=source.find('<section id="selected-reason-risk-strata"')
if start>=0:
 end=source.find('</section>',start)+len('</section>');source=source[:start]+source[end:]
anchor='<section id="method-duration-class-discontinuation"';assert anchor in source
source=source.replace(anchor,section+anchor,1)
if 'href="#selected-reason-risk-strata"' not in source:
 old='<a href="#method-duration-class-discontinuation">';assert old in source
 source=source.replace(old,'<a href="#selected-reason-risk-strata">Selected-reason risk bands</a>'+old,1)
page.write_text(source);print(page))----------------------")

MODULES[["45_add_replication_figures_html.py"]] <- list(language="Python", packaged_sha256="c5abb0c1147e2b510f59e04787c7ddab0c274872a16e1a22d6be633c1401fa6e", args=character(0), code=r"----------------------(#!/usr/bin/env python3
"""Place Nigeria-specific figures within corresponding working-HTML analyses."""
from pathlib import Path
import os
import re
from html import escape

page=(Path(os.environ["NIGERIA_PROJECT_ROOT"]) / 'output/Nigeria_discontinuation_analysis.html')
source=page.read_text()
items=[
 ('initiation','nigeria_regional_method_start_mix.svg','Weighted method-start mix by zone; denominator includes EC and non-modern methods.'),
 ('all-cause','nigeria_all_reason_pct_method_curves.svg','Cumulative original-method discontinuation for all recorded reasons.'),
 ('all-cause','nigeria_national_start_vs_all_reason_pct.svg','Start share excludes EC from the start denominator; discontinuation is method-specific.'),
 ('all-reason-transitions','nigeria_all_reason_month12_followup_stacked.svg','Month-12 status is shown as a distribution among observed first-year all-reason endings with follow-up.'),
 ('selected-reasons','nigeria_selected_reason_pct_method_curves.svg','Selected endings exclude wanted pregnancy and partner disapproval as events of interest; both remain competing outcomes.'),
 ('selected-reason-regional-analysis','nigeria_selected_reason_zone_forest.svg','Unadjusted 12-month selected-reason discontinuation with survey-bootstrap intervals.'),
 ('selected-reason-regional-reason-heatmap','nigeria_selected_reason_zone_heatmap.svg','Shares among selected endings sum to 100 percent within zone.'),
 ('national','nigeria_actionable_pct_method_curves.svg','Cumulative original-method discontinuation for potentially actionable reasons.'),
 ('national','nigeria_national_start_vs_actionable_pct.svg','Method-start shares and actionable first-year risks use different denominators.'),
 ('action-pathways','nigeria_injectable_reason_timing_destination_heatmap.svg','Timing columns sum to 100 within each injectable reason; the final column shows no method one month later.'),
 ('zone-rates','nigeria_actionable_zone_observed_adjusted.svg','Observed and fully adjusted 12-month potentially actionable risk by zone with design-aware intervals.'),
 ('timing','nigeria_actionable_zone_timing_heatmap.svg','The first four columns are cumulative rates; the final column is the month-3 share of month-12 risk.'),
 ('zone-reasons','nigeria_actionable_zone_reason_heatmap.svg','Reason shares are conditional on an actionable ending and sum to 100 percent within zone.'),
 ('method-mix','nigeria_regional_method_start_mix.svg','National and zone method-start mix; includes EC and non-modern starts.'),
]
for section,name,caption in items:
 marker=f'<!-- nigeria-replication-figure:{name} -->'
 if marker in source:continue
 match=re.search(r'<section\s+[^>]*id="'+re.escape(section)+r'"[^>]*>',source)
 if not match:raise ValueError(section)
 h=re.search(r'</h[1-3]>',source[match.end():])
 if not h:raise ValueError('heading '+section)
 point=match.end()+h.end()
 block=f'{marker}<figure class="replication-figure"><img src="assets/{escape(name)}" alt="{escape(caption)}" loading="lazy"><figcaption>{escape(caption)}</figcaption></figure>'
 source=source[:point]+block+source[point:]
style='<style>.replication-figure{margin:1.1rem 0 1.8rem;padding:0}.replication-figure img{width:100%;height:auto;display:block}.replication-figure figcaption{font-size:.82rem;color:#506879;margin-top:.35rem}</style>'
if 'replication-figure{margin:' not in source:source=source.replace('</head>',style+'</head>',1)
page.write_text(source)
print(page))----------------------")

MODULES[["46_add_three_definition_comparison_html.py"]] <- list(language="Python", packaged_sha256="e432bb47f1d9571b36ee13fe59fa5b54a0c5d2de42c72b64690d27a3bdf5385f", args=character(0), code=r"----------------------(#!/usr/bin/env python3
"""Add the direct all/selected/actionable comparison in the Ethiopia structure."""
from pathlib import Path
import os
import csv,html,re
out=(Path(os.environ["NIGERIA_PROJECT_ROOT"]) / 'output');page=out/'Nigeria_discontinuation_analysis.html'
with (out/'Supporting_data/nigeria_modern_all_reason_timepoints.csv').open(newline='') as f: rows=list(csv.DictReader(f))
order=['National','National: Injectables','National: Implants','National: Pill','National: IUD','National: Other modern']
lookup={r['scope']:r for r in rows if r['month']=='12'}
assert all(x in lookup for x in order)
tr=[]
for scope in order:
 r=lookup[scope];label='All modern' if scope=='National' else scope.split(': ',1)[1]
 tr.append('<tr>'+''.join(f'<td>{html.escape(v)}</td>' for v in (label,*[f'{float(r[k]):.1f}%' for k in ('all_reason_pct','selected_reason_pct','actionable_pct')]))+'</tr>')
block='<section id="twelve-month-three-column-comparison" class="analysis-section"><div class="eyebrow">Three outcome definitions</div><h2>12-month discontinuation by method and reason definition</h2><p>Each cell is a weighted competing-risk life-table probability among episodes that started that modern method. The selected measure excludes wanted pregnancy and partner disapproval as events of interest; the actionable measure also excludes circumstantial and unresolved reasons. Excluded endings remain competing events, so the three columns describe nested event sets rather than different episode denominators. Emergency contraception is excluded from the episode cohorts.</p><div class="tablewrap"><table><thead><tr><th>Method</th><th>All recorded reasons</th><th>Selected reasons</th><th>Potentially actionable reasons</th></tr></thead><tbody>'+''.join(tr)+'</tbody></table></div><p class="small">Source: Nigeria DHS 2024 IR monthly calendar. The all-modern row is calculated from the pooled modern-episode life table, not an average of method-specific percentages.</p></section>'
s=page.read_text();old=re.search(r'<section id="twelve-month-three-column-comparison".*?</section>',s,re.S)
if old:s=s[:old.start()]+s[old.end():]
anchor='<section id="selected-reasons"';assert anchor in s;s=s.replace(anchor,block+anchor,1)
if 'href="#twelve-month-three-column-comparison"' not in s:
 target='<a href="#selected-reasons"';assert target in s
 s=s.replace(target,'<a href="#twelve-month-three-column-comparison">Three reason definitions</a>'+target,1)
page.write_text(s);print(page))----------------------")

MODULES[["47_add_method_followup_alluvials_html.py"]] <- list(language="Python", packaged_sha256="4fed23aac4595ade0b4cf3da01c893c74a699954614c6fb6ecebe8e931bd88a0", args=character(0), code=r"----------------------(#!/usr/bin/env python3
"""Insert the four Nigeria method-to-follow-up alluvials in narrative order."""
from pathlib import Path
import os
root=(Path(os.environ["NIGERIA_PROJECT_ROOT"]) / 'output');p=root/'Nigeria_discontinuation_analysis.html'
s=p.read_text()
def fig(name,alt):return f'<figure class="replication-figure"><img src="assets/{name}" alt="{alt}" loading="lazy"><figcaption>{alt}</figcaption></figure>'
allblock='<section id="all-reason-transitions" class="analysis-section"><div class="eyebrow">After an original-method ending</div><h2>What follows an all-reason discontinuation?</h2><p>Among observed first-year endings for any reason, the following figures show the recorded method or reproductive state one and twelve months later. Each figure conditions on having that follow-up month in the calendar. These are distributions among observed endings, not 12-month life-table risks and not projections of current users.</p>'+fig('nigeria_all_reason_method_to_month_01_alluvial.png','Original modern method and state one month after an all-reason ending.')+fig('nigeria_all_reason_method_to_month_12_alluvial.png','Original modern method and state twelve months after an all-reason ending.')+'</section>'
selblock='<section id="selected-reason-transitions" class="analysis-section"><div class="eyebrow">After a selected-reason ending</div><h2>What follows discontinuation for a selected reason?</h2><p>These figures exclude endings recorded as wanted pregnancy or partner disapproval. The month-one and month-twelve figures have different follow-up cohorts. A woman can restart or switch later; an original-method ending does not imply year-end nonuse of modern contraception.</p>'+fig('nigeria_selected_reason_method_to_month_01_alluvial.png','Original modern method and state one month after a selected-reason ending.')+fig('nigeria_selected_reason_method_to_month_12_alluvial.png','Original modern method and state twelve months after a selected-reason ending.')+'</section>'
for id in ('all-reason-transitions','selected-reason-transitions'):
 a=s.find(f'<section id="{id}"')
 if a>=0:
  b=s.find('</section>',a)+len('</section>');s=s[:a]+s[b:]
anchor='<section id="selected-reasons"';assert anchor in s;s=s.replace(anchor,allblock+anchor,1)
anchor='<section id="selected-followup"';assert anchor in s;s=s.replace(anchor,selblock+anchor,1)
for id,label,before in [('all-reason-transitions','After all-reason endings','selected-reasons'),('selected-reason-transitions','After selected-reason endings','selected-followup')]:
 if f'href="#{id}"' not in s:
  target=f'<a href="#{before}"';assert target in s;s=s.replace(target,f'<a href="#{id}">{label}</a>'+target,1)
p.write_text(s);print(p.name))----------------------")

MODULES[["48_add_selected_regional_adjustment_html.py"]] <- list(language="Python", packaged_sha256="538606cdb32497f6a16f9f5c37f5d68d84bc8264efb95b67f70b952de362f38f", args=character(0), code=r"----------------------(#!/usr/bin/env python3
"""Complete the selected-reason regional sequence with adjusted probabilities."""
from pathlib import Path
import os
import csv,re,html
root=(Path(os.environ["NIGERIA_PROJECT_ROOT"]) / 'output');page=root/'Nigeria_discontinuation_analysis.html'
with (root/'Supporting_data/nigeria_selected_reason_zone_models.csv').open(newline='') as f:r=list(csv.DictReader(f))
with (root/'Supporting_data/nigeria_selected_reason_zone_pairwise.csv').open(newline='') as f:pairs=list(csv.DictReader(f))
order=['National','North West','North East','North Central','South East','South South','South West']
by={x['zone']:x for x in r};assert all(z in by for z in order)
def cell(x,k,lo,hi):return f'{float(x[k]):.1f}% ({float(x[lo]):.1f}–{float(x[hi]):.1f})'
rows=[]
for zone in order:
 x=by[zone]
 rows.append('<tr>'+''.join('<td>'+html.escape(v)+'</td>' for v in (zone,x['eligible_episodes_n'],cell(x,'unadjusted_pct','unadjusted_low','unadjusted_high'),cell(x,'model_1_pct','model_1_low','model_1_high'),cell(x,'model_2_pct','model_2_low','model_2_high')))+'</tr>')
pair_rows=[]
for x in pairs:
 pair_rows.append('<tr>'+''.join('<td>'+html.escape(v)+'</td>' for v in (x['zone_a']+' vs '+x['zone_b'],f'{float(x["difference_pp"]):+.1f} pp',f'{float(x["ci_low"]):+.1f} to {float(x["ci_high"]):+.1f} pp',f'{float(x["p_holm"]):.3f}','Yes' if x['significant_5pct']=='TRUE' else 'No'))+'</tr>')
section='<section id="selected-reason-regional-adjusted" class="analysis-section"><div class="eyebrow">Selected-reason regional adjustment</div><h2>Observed and adjusted 12-month probabilities by zone</h2><p>All three columns estimate the probability that an episode ends its original modern method for any reason except wanted pregnancy or partner disapproval. Model 1 accounts for original method and month since method start. Model 2 additionally includes age and parity at method start, marital status, education, wealth, and urban/rural residence measured at interview, plus zone. Adjusted zone predictions hold the measured episode composition common across zones to compare like with like.</p><figure class="replication-figure"><img src="assets/nigeria_selected_reason_zone_adjusted.svg" alt="Observed, method-adjusted and fully adjusted regional selected-reason discontinuation with confidence intervals" loading="lazy"><figcaption>Intervals for adjusted estimates use 80 survey-cluster bootstrap refits and should be treated as preliminary.</figcaption></figure><div class="tablewrap"><table><thead><tr><th>Zone</th><th>Eligible episodes</th><th>Observed (95% CI)</th><th>Method adjusted (95% CI)</th><th>Fully adjusted (95% CI)</th></tr></thead><tbody>'+''.join(rows)+'</tbody></table></div><h3>Formal pairwise comparisons of observed rates</h3><p>All 15 raw zone pairs are tested using paired differences from 300 stratified PSU bootstrap draws. Holm-adjusted p-values control the family of comparisons. The table tests selected-reason rates; it is separate from the later actionable comparison.</p><div class="tablewrap"><table><thead><tr><th>Zone pair</th><th>Difference</th><th>95% CI</th><th>Holm p</th><th>Significant at 5%</th></tr></thead><tbody>'+''.join(pair_rows)+'</tbody></table></div><p class="small">Source: Nigeria DHS 2024 IR calendar. The 80-refit adjusted intervals are less stable than the 300–500 replicate analyses used for the later actionable regional comparisons. These are association and standardization estimates, not causal regional effects.</p></section>'
s=page.read_text();m=re.search(r'<section id="selected-reason-regional-adjusted".*?</section>',s,re.S)
if m:s=s[:m.start()]+s[m.end():]
anchor='<section id="selected-reason-regional-reason-heatmap"';assert anchor in s;s=s.replace(anchor,section+anchor,1)
if 'href="#selected-reason-regional-adjusted"' not in s:
 target='<a href="#selected-reason-regional-reason-heatmap"';assert target in s
 s=s.replace(target,'<a href="#selected-reason-regional-adjusted">Adjusted selected-reason rates</a>'+target,1)
page.write_text(s);print(page))----------------------")

MODULES[["50_add_all_reason_regional_paired_bars.py"]] <- list(language="Python", packaged_sha256="1d64e4055831a0d3eb9d4773fb249ee6ec46371a82ca666415d6026a8e6fc3aa", args=character(0), code=r"----------------------(#!/usr/bin/env python3
"""Mirror the Ethiopia by-method regional paired bars for all-reason risk."""
from pathlib import Path
import os
import csv,re,html
root=(Path(os.environ["NIGERIA_PROJECT_ROOT"]) / 'output');p=root/'Nigeria_discontinuation_analysis.html'
def read(n):
 with (root/'Supporting_data'/n).open(newline='') as f:return list(csv.DictReader(f))
mix={(x['scope'],x['method']):x for x in read('nigeria_zone_all_method_start_mix.csv')}
risk={x['scope']:x for x in read('nigeria_modern_all_reason_timepoints.csv') if x['month']=='12'}
zones=['National','North West','North East','North Central','South East','South South','South West']
methods=['Injectables','Implants','Pill','IUD','Other modern']
parts=['<!-- all-reason-paired-bars-start -->']
for method in methods:
 parts.append('<h3>'+html.escape(method)+'</h3><div class="pairchart">')
 for zone in zones:
  m=mix[(zone,method)];ec=mix[(zone,'Emergency contraception')]
  den=float(m['denominator_weighted_starts'])-float(ec['weighted_starts'])
  start=100*float(m['weighted_starts'])/den
  r=risk[zone+': '+method];rate=float(r['all_reason_pct'])
  flag='*' if int(float(r['all_reason_endings_n']))<30 else ''
  parts.append('<div class="pairrow"><label>'+html.escape(zone)+flag+'</label><div class="two">'
   '<div class="sub"><span>Start share</span><div class="bartrack"><span style="width:'+f'{min(100,start):.2f}'+'%;background:#DA9A25"></span></div><strong>'+f'{start:.1f}'+'%</strong></div>'
   '<div class="sub"><span>12-month risk</span><div class="bartrack"><span style="width:'+f'{min(100,rate):.2f}'+'%;background:#153F5B"></span></div><strong>'+f'{rate:.1f}'+'%</strong></div></div><span></span></div>')
 parts.append('</div>')
parts.append('<p class="small">Gold uses all observed method starts excluding EC as its denominator; navy uses eligible episodes of the named modern method. * Fewer than 30 observed first-year endings; interpret cautiously.</p><!-- all-reason-paired-bars-end -->')
block=''.join(parts)
s=p.read_text();s=re.sub(r'<!-- all-reason-paired-bars-start -->.*?<!-- all-reason-paired-bars-end -->','',s,flags=re.S)
a=s.index('<section id="regional-method-paired-bars"');h=re.search(r'</p>',s[a:]);assert h
at=a+h.end();s=s[:at]+block+s[at:]
p.write_text(s);print(p.name))----------------------")

MODULES[["57_align_working_html_sequence.py"]] <- list(language="Python", packaged_sha256="3b640d018846dff6c988560d0ceddc5fabd27ae92127798e82ca2ceea9d08868", args=character(0), code=r"----------------------(#!/usr/bin/env python3
"""Place Nigeria sections in the Ethiopia analytical sequence and group the TOC."""
from pathlib import Path
import os
from lxml import html

root=(Path(os.environ["NIGERIA_PROJECT_ROOT"]) / 'output')
source=root/'Nigeria_discontinuation_analysis.html'
doc=html.parse(str(source))
main=doc.xpath('//main')[0]
aside=doc.xpath('//aside')[0]

# This display is an all-reason method comparison. It belongs with the other
# all-reason evidence, not after the selected-reason regional analyses.
paired=doc.getroot().get_element_by_id('regional-method-paired-bars')
all_cause=doc.getroot().get_element_by_id('all-cause')
main.remove(paired)
all_cause.addnext(paired)
post=doc.getroot().get_element_by_id('post-ending')
national=doc.getroot().get_element_by_id('national')
main.remove(post)
national.addnext(post)
pathways=doc.getroot().get_element_by_id('action-pathways')
reasons=doc.getroot().get_element_by_id('method-reasons')
main.remove(pathways)
reasons.addnext(pathways)
standardized=doc.getroot().get_element_by_id('standardized-current-users')
duration=doc.getroot().get_element_by_id('duration-adjusted-reason-planning')
main.remove(standardized)
duration.addnext(standardized)

# The navigation follows the document order, with visible chapter labels.
for child in list(aside):
    if child.tag in ('a','div'):
        aside.remove(child)
groups=[
 ('Study frame',['methodology','current-use','initiation','dhs-712','dhs-713']),
 ('All reasons',['all-cause','regional-method-paired-bars','all-reason-users',
                 'twelve-month-three-column-comparison','all-reason-transitions']),
 ('Excluding pregnancy and partner disapproval',[
     'selected-reasons','selected-models','selected-reason-transitions','selected-followup',
     'other-reasons-count-breakdown','other-reason-followup',
     'selected-reason-descriptive-subgroups','method-experience-subgroup-reasons',
     'top-three-reasons-by-subgroup-method','selected-reason-risk-strata',
     'method-duration-class-discontinuation','short-acting-selected-reason-distribution',
     'selected-reason-regional-analysis','selected-reason-regional-adjusted',
     'selected-reason-regional-reason-heatmap','regional-episode-mix-and-risk']),
 ('Potentially actionable causes',[
     'national','post-ending','timing','zone-rates','zone-reasons','method-mix',
     'methods-by-zone','method-reasons','action-pathways','models','subgroups',
     'pairwise','method-zone-regressions',
     'regional-actionable-method-mix-decomposition','regional-analyses']),
 ('Current users and mCPR',[
     'population','user-projections','current-user-reason-planning',
     'duration-adjusted-reason-planning','standardized-current-users',
     'mcpr-scenarios','method-level-mcpr-scenarios',
     'switch-bridge','duration-bridge','duration-aware-cause-pp-matrices']),
 ('Reproducibility',['files']),
]
seen=set()
for title,ids in groups:
    label=html.Element('div',{'class':'toc-group'})
    label.text=title
    aside.append(label)
    for ident in ids:
        section=doc.getroot().get_element_by_id(ident)
        heading=section.xpath('./h2[1]')
        name=' '.join(' '.join(heading[0].itertext()).split()) if heading else ident.replace('-',' ').title()
        link=html.Element('a',href=f'#{ident}')
        link.text=name
        aside.append(link)
        seen.add(ident)
actual={x.get('id') for x in main.xpath('./section') if x.get('id')}
assert actual==seen,(sorted(actual-seen),sorted(seen-actual))

# Append a small, consistent navigation treatment without changing figures.
head=doc.xpath('//head')[0]
style=html.Element('style')
style.text='.toc-group{margin:1rem .7rem .25rem;color:#DA9A25;font:700 .73rem Arial,sans-serif;text-transform:uppercase;letter-spacing:.06em}'
head.append(style)
for a in aside.xpath('./a'):
    assert doc.getroot().get_element_by_id(a.get('href')[1:]) is not None
source.write_bytes(html.tostring(doc,encoding='utf-8',method='html',doctype='<!DOCTYPE html>'))
print('Aligned',len(seen),'Nigeria sections, pathways, planning and grouped navigation'))----------------------")

MODULES[["59_align_html_visual_style.py"]] <- list(language="Python", packaged_sha256="7134b7332317a0089c8249e769111b4b7ade48e3025ebac842a77392a6b63c4e", args=character(0), code=r"----------------------(from pathlib import Path
import os
import re

p=(Path(os.environ["NIGERIA_PROJECT_ROOT"]) / 'output/Nigeria_discontinuation_analysis.html')
html=p.read_text()
html=re.sub(r'<style id="ethiopia-visual-alignment">.*?</style>','',html,flags=re.S)
css='''
/* Align the Nigeria report shell, hierarchy and tables with the Ethiopia working HTML.
   Figure-specific colors and numerical content remain unchanged. */
body{background:#eef2f3;color:#18313e;font:15px/1.55 -apple-system,BlinkMacSystemFont,"Segoe UI",Arial,sans-serif}
aside{background:#234957;border-right:0;color:#fff;padding:27px 17px}
aside strong{font-family:Georgia,serif;color:#fff;font-size:20px}
aside small{color:#d1e1e5}
aside a{color:#e7f0f2;font-size:13px;padding:7px 9px}
aside a:hover,aside a:focus{background:#366170;color:#fff}
.toc-group{color:#e6bc65!important}
main{background:#fff;margin-left:254px;padding:48px 52px 90px;max-width:1600px;min-height:100vh}
header{padding:0 0 25px;border-bottom:0}
header h1{font-size:36px;color:#234957}
header p{color:#52666f}
section{padding:0 0 12px;border-bottom:0;scroll-margin-top:18px}
section h2{font-size:25px;color:#234957;margin:45px 0 9px;padding-top:12px;border-top:3px solid #234957}
section h3{font-size:18px;color:#234957}
.tablewrap{overflow-x:auto;border:1px solid #cbd8dc;border-radius:7px;margin:12px 0 18px}
table{font-size:13px}
thead th{background:#234957;color:#fff;border-bottom:0;padding:10px 9px;white-space:normal;vertical-align:bottom}
tbody th{color:#18313e;padding:9px;text-align:left}
tbody td{padding:9px;border-bottom:1px solid #e3eaed}
tbody tr:nth-child(even){background:#f6f9fa}
tbody tr.total{background:#ecf3f5;font-weight:700}
.note{background:#edf4f5;border-left-color:#2d7180}
.goldnote{background:#fff7e8;border-left-color:#DA9A25}
.metric strong{color:#234957}
.pairrow,.zonebar,.forestrow,.dualrow{font-size:14px}
@media(max-width:900px){aside{position:static;width:auto;max-height:195px;border-bottom:0}main{margin:0;padding:28px 18px 60px}section h2{margin-top:34px}thead th{font-size:12px}}
'''
html=html.replace('</head>', '<style id="ethiopia-visual-alignment">'+css+'</style></head>',1)
p.write_text(html)
print(p.name))----------------------")

MODULES[["72_correct_modern_reason_html.py"]] <- list(language="Python", packaged_sha256="7b0b04a66a6f3160decc5fe30d92d879445294b79ac685f5b390160d11160c0f", args=character(0), code=r"----------------------(#!/usr/bin/env python3
"""Correct the existing working HTML without discarding later added sections."""
import csv
from html import escape
from pathlib import Path
import os

root=Path(os.environ["NIGERIA_PROJECT_ROOT"])
path=root/'output/Nigeria_discontinuation_analysis.html'
sup=root/'output/Supporting_data'
with (sup/'nigeria_modern_five_year_reason_distribution_seven.csv').open() as f:
    seven=list(csv.DictReader(f))
with (sup/'nigeria_modern_five_year_reason_distribution.csv').open() as f:
    by_method=list(csv.DictReader(f))
s=path.read_text()
start=s.index('<section id="dhs-713">')
end=s.index('</section>',start)+len('</section>')
old=s[start:end]
table_start=old.index('<div class="tablewrap"><table>')
published=old[table_start:]
published=published.replace('</section>','')
intro=('<section id="dhs-713"><div class="eyebrow">Five-year calendar distribution</div>'
 '<h2>Reasons among recorded modern-method discontinuations</h2>'
 '<p class="intro">Matching the Ethiopia presentation, the primary reason distribution '
 'includes only recorded endings of modern-method episodes in the five-year calendar, '
 'excluding emergency contraception. It contains 4,557 unweighted endings (4,531.8 '
 'weighted). These are shares among endings, not 12-month discontinuation risks.</p>')
seven_table='<h3>All modern methods</h3><div class="tablewrap"><table><thead><tr><th>Recorded reason</th><th>Weighted share of endings</th></tr></thead><tbody>'
for row in seven:
    seven_table+=f'<tr><td>{escape(row["reason"])}</td><td class="num">{float(row["percent"]):.1f}%</td></tr>'
seven_table+='</tbody></table></div><p class="small">The seven categories sum to 100% before rounding. Source: Nigeria DHS 2024 IR contraceptive calendar, survey weighted; modern-method endings excluding EC.</p>'
method_table='<h3>Reason distribution by modern method</h3><div class="tablewrap"><table><thead><tr><th>Method</th><th>Wanted pregnancy</th><th>Method experience/access</th><th>Partner disapproval</th><th>Other reasons</th><th>Observed endings</th></tr></thead><tbody>'
for method in ['All modern','Injectables','Implants','Pill','IUD','Other modern']:
    rows=[r for r in by_method if r['method']==method]
    method_table+='<tr><td>'+escape(method)+'</td>'+''.join(f'<td class="num">{float(r["percent"]):.1f}%</td>' for r in rows)+f'<td class="num">{int(rows[0]["unweighted_endings"]):,}</td></tr>'
method_table+='</tbody></table></div><p class="small">Rows sum to 100% before rounding. Counts are unweighted and shares are survey weighted. EC and traditional methods are excluded.</p>'
published='<h3>Published DHS Table 7.13: all-method validation comparison</h3><p class="small">The official table below includes traditional methods and EC. Its all-method column is a validation control and is not the denominator for the presentation reasons chart.</p>'+published
s=s[:start]+intro+seven_table+method_table+published+'</section>'+s[end:]
path.write_text(s)
print(path))----------------------")

MODULES[["99_sync_duration_planning_html.py"]] <- list(language="Python", packaged_sha256="0e8329eabb09699476c39592be81886f1567d72b5acd3284f23219f8ef0eac11", args=character(0), code=r"----------------------(#!/usr/bin/env python3
"""Mirror Nigeria's 16 historical/AFT planning slides in the working HTML."""
from html import escape
from pathlib import Path
import os
import json

root = Path(os.environ["NIGERIA_PROJECT_ROOT"])
target = root / 'output/Nigeria_discontinuation_analysis.html'
backup = root / 'output/Nigeria_discontinuation_analysis_before_three_approaches.html'
data = json.loads((root / 'output/nigeria_duration_planning_tables.json').read_text())
aft_appendix = json.loads((root / 'output/nigeria_aft_appendix_tables.json').read_text())
source = target.read_text()

start = '<!-- BEGIN NIGERIA THREE APPROACHES -->'
end = '<!-- END NIGERIA THREE APPROACHES -->'
anchor = '<section id="switch-bridge"'

def table_html(rows, slide):
    lines = [f'<div class="tablewrap duration-table-wrap" role="region" tabindex="0" '
             f'aria-label="Slide {slide} table"><table class="duration-planning-table">',
             '<thead><tr>']
    lines += [f'<th scope="col">{escape(x)}</th>' for x in rows[0]]
    lines.append('</tr></thead><tbody>')
    for i, row in enumerate(rows[1:], 1):
        klass = ' class="duration-total"' if i == len(rows)-1 else ''
        lines.append(f'<tr{klass}><th scope="row">{escape(row[0])}</th>')
        lines += [f'<td>{escape(x)}</td>' for x in row[1:]]
        lines.append('</tr>')
    return ''.join(lines) + '</tbody></table></div>'

css = '''<style>
.duration-block .duration-slide{border-top:1px solid #d8e3e8;padding:1.2rem 0 1.6rem}
.duration-block .duration-slide h3{color:#153F5B;margin:.1rem 0 .35rem}
.duration-block .duration-subtitle{color:#375568;margin:.2rem 0 1rem}
.duration-block .duration-table-wrap{overflow-x:auto;margin:.7rem 0 1rem;border:1px solid #d8e3e8;border-radius:4px}
.duration-block .duration-planning-table{width:100%;min-width:860px;border-collapse:collapse;font:14px/1.35 Arial,sans-serif;font-variant-numeric:tabular-nums}
.duration-block th,.duration-block td{padding:10px 9px;border-bottom:1px solid #dce5e9;text-align:right;vertical-align:middle}
.duration-block thead th{background:#153F5B;color:white;font-weight:700}
.duration-block thead th:first-child,.duration-block tbody th{text-align:left;min-width:150px}
.duration-block tbody tr:nth-child(even):not(.duration-total){background:#f2f6f7}
.duration-block .duration-total{background:#e6f0f2;color:#153F5B;font-weight:700}
</style>'''

blocks = [start, css,
    '<section id="three-approach-planning" class="analysis-section duration-block">',
    '<div class="eyebrow">Nigeria 2024 DHS and 2026 planning</div>',
    '<h2>Three approaches to actionable discontinuation and mCPR</h2>',
    '<p>The first-year illustration applies risks after method starts to projected 2025 current users. '
    'The historical and AFT approaches condition on how long current users have already used their method; '
    'their year-end nonmodern counts also reflect observed switching and restarting. All three use the same '
    'three illustrative 2026 mCPR growth scenarios and the same projected 2026 women aged 15–49. '
    'All discontinuation counts here are restricted to potentially actionable causes. Emergency contraception '
    'is in the mCPR baseline but has no continuing-use discontinuation risk.</p>',
    '<div class="tablewrap"><table><thead><tr><th>Approach</th><th>Actionable original-method endings</th>'
    '<th>Outside modern use at year end</th><th>mCPR equivalent</th><th>Detailed tables</th></tr></thead><tbody>',
    '<tr><th scope="row">First-year risks applied to current users</th><td>1,486,395</td>'
    '<td>Not estimated in this approach</td><td>2.52 pp gross ceiling</td>'
    '<td><a href="#user-projections">First-year planning</a> and '
    '<a href="#method-level-mcpr-scenarios">three growth scenarios</a></td></tr>',
    '<tr><th scope="row">Historical duration-aware landmarks</th><td>854,152</td>'
    '<td>677,085</td><td>1.15 pp</td>'
    '<td><a href="#historical-duration-aware-planning">Historical tables</a></td></tr>',
    '<tr><th scope="row">AFT survival plus observed pathways</th><td>908,294</td>'
    '<td>730,325</td><td>1.24 pp</td>'
    '<td><a href="#aft-duration-aware-planning">AFT tables</a></td></tr>',
    '</tbody></table></div>',
    '<p class="small">The mCPR equivalents are descriptive planning comparisons, not predicted causal '
    'effects of a program. The AFT result is exploratory: 73 of 200 method × cause × duration transition '
    'cells used pooled fallback fractions, and several IUD cause fits had very few events.</p></section>']

for block, section_id, label, first in [
    (data['blocks'][0], 'historical-duration-aware-planning', 'Historical duration-aware planning', 56),
    (data['blocks'][1], 'aft-duration-aware-planning', 'AFT survival and observed pathways', 64)]:
    blocks += [f'<section id="{section_id}" class="analysis-section duration-block">',
               f'<div class="eyebrow">Slides {first}–{first+7}</div>',
               f'<h2>{label}</h2>']
    for i, slide in enumerate(block['slides']):
        n = first+i
        blocks += [f'<article class="duration-slide" id="nigeria-duration-slide-{n}" data-pptx-slide="{n}">',
                   f'<h3>{escape(slide["title"])}</h3>',
                   f'<p class="duration-subtitle">{escape(slide["subtitle"])}</p>',
                   table_html(slide['table'], n),
                   f'<p class="note">{escape(slide["note"])}</p>',
                   '</article>']
    blocks.append('</section>')
blocks += ['<section id="duration-planning-appendix" class="analysis-section">',
           '<div class="eyebrow">Appendix</div><h2>Earlier switching and duration-aware analyses</h2>',
           '<p>The following supplementary diagnostics correspond to the presentation appendix '
           'beginning at slide 72. The five AFT support tables match slides 81–85.</p>']
for i, slide in enumerate(aft_appendix, 81):
    blocks += [f'<article class="duration-slide" id="nigeria-duration-slide-{i}" data-pptx-slide="{i}">',
               f'<h3>{escape(slide["title"])}</h3>',
               f'<p class="duration-subtitle">{escape(slide["subtitle"])}</p>',
               table_html(slide['table'], i),
               f'<p class="note">{escape(slide["note"])}</p>',
               '</article>']
blocks += ['</section>', end]
new = '\n'.join(blocks) + '\n'
if start in source:
    before, rest = source.split(start, 1)
    _, after = rest.split(end, 1)
    source = before + after.lstrip('\n')
assert source.count(anchor) == 1
source = source.replace(anchor, new + anchor)

toc_anchor = '<a href="#switch-bridge">'
toc_start = '<!-- BEGIN NIGERIA DURATION TOC -->'
toc_end = '<!-- END NIGERIA DURATION TOC -->'
if toc_start in source:
    before, rest = source.split(toc_start, 1)
    _, after = rest.split(toc_end, 1)
    source = before + after
toc = [toc_start, '<div class="toc-group">Three planning approaches</div>',
       '<a href="#three-approach-planning">Three approaches and their mCPR equivalents</a>',
       '<a href="#historical-duration-aware-planning">Historical duration-aware tables</a>']
toc += [f'<a href="#nigeria-duration-slide-{n}">Historical slide {n}</a>' for n in range(56,64)]
toc += ['<a href="#aft-duration-aware-planning">AFT survival and observed pathways</a>']
toc += [f'<a href="#nigeria-duration-slide-{n}">AFT slide {n}</a>' for n in range(64,72)]
toc += ['<div class="toc-group">Appendix</div>',
        '<a href="#duration-planning-appendix">Earlier duration-aware analyses</a>']
toc += [f'<a href="#nigeria-duration-slide-{n}">AFT support slide {n}</a>' for n in range(81,86)]
toc += [toc_end]
assert source.count(toc_anchor) == 1
source = source.replace(toc_anchor, ''.join(toc) + toc_anchor)
source = source.replace('Nigeria_discontinuation_2024_UPDATED_full_replication.pptx',
                        'Nigeria_discontinuation_2024_UPDATED_three_approaches.pptx')
target.write_text(source)
print(target)
print('Mirrored tables:', sum(source.count(f'data-pptx-slide="{n}"') for n in [*range(56,72),*range(81,86)]))
)----------------------")

MODULES[["dhs_survey_tools.R"]] <- list(language="R", packaged_sha256="a6ee764ece430cf7c842c9dbdc01bd94a32820a0d4f0162e410f0e9104b7f003", args=character(0), code=r"----------------------(# DHS design utilities. Inputs are supplied by the calling analysis.
# No finite population correction: use the with-replacement PSU approximation.
dhs_require_survey <- function() {
  if (!requireNamespace('survey', quietly=TRUE)) stop('Install the survey package before estimation.')
}

dhs_frame <- function(ir) {
  required <- c('v005','v021','v022')
  if (!all(required %in% names(ir))) stop('IR data require v005, v021 and v022.')
  w <- as.numeric(ir$v005)/1e6
  if (anyNA(w) || any(!is.finite(w)) || any(w<=0)) stop('Invalid DHS sampling weights.')
  f <- unique(data.frame(cluster=as.character(ir$v021), stratum=as.character(ir$v022)))
  if (anyNA(f) || any(f$cluster=='') || any(f$stratum=='')) stop('Missing survey identifiers.')
  f[order(f$stratum,f$cluster),,drop=FALSE]
}

dhs_design <- function(data, frame, weight='wt', cluster='cluster', stratum='stratum') {
  dhs_require_survey()
  data <- as.data.frame(data)
  if (!all(c(weight,cluster,stratum)%in%names(data))) stop('Analysis records lack survey design variables.')
  f <- unique(data.frame(.dhs_psu=as.character(frame$cluster),.dhs_stratum=as.character(frame$stratum)))
  if (anyNA(f) || anyDuplicated(paste(f$.dhs_stratum,f$.dhs_psu,sep=':'))) stop('Invalid full survey frame.')
  data$.dhs_w <- as.numeric(data[[weight]])
  data$.dhs_psu <- as.character(data[[cluster]])
  data$.dhs_stratum <- as.character(data[[stratum]])
  if (anyNA(data[,c('.dhs_w','.dhs_psu','.dhs_stratum')]) || any(!is.finite(data$.dhs_w)) || any(data$.dhs_w<0)) stop('Invalid analysis design values.')
  key <- function(s,p) paste(s,p,sep=':')
  fk <- key(f$.dhs_stratum,f$.dhs_psu); dk <- key(data$.dhs_stratum,data$.dhs_psu)
  if (any(!dk%in%fk)) stop('Analysis PSU is absent from the supplied full frame.')
  data$.dhs_record <- TRUE
  absent <- which(!fk%in%dk)
  if (length(absent)) {
    if (!nrow(data)) stop('An empty domain cannot be estimated.')
    pad <- data[rep(1L,length(absent)),,drop=FALSE]
    pad$.dhs_w <- 0; pad$.dhs_record <- FALSE
    pad$.dhs_psu <- f$.dhs_psu[absent]; pad$.dhs_stratum <- f$.dhs_stratum[absent]
    data <- rbind(data,pad)
  }
  # Explicit policy: singleton strata are an error, never silently dropped or
  # treated as certainty PSUs. Resolve any such survey-specific case explicitly.
  if (any(table(f$.dhs_stratum)<2L)) stop('Singleton survey stratum: specify a documented survey-specific treatment.')
  design <- survey::svydesign(ids=~.dhs_psu,strata=~.dhs_stratum,weights=~.dhs_w,
                    data=data,nest=TRUE)
  # degf() excludes zero-weight placeholder PSUs. Retain the documented
  # full-frame degrees of freedom for domain intervals and model tests.
  attr(design,'dhs_design_df') <- nrow(f)-length(unique(f$.dhs_stratum))
  design
}

dhs_percentage <- function(design, indicator, domain=NULL) {
  n <- sum(design$variables$.dhs_record)
  if (length(indicator)!=n) stop('Indicator length does not match the analysis records.')
  if (is.null(domain)) domain <- rep(TRUE,n)
  if (length(domain)!=n || anyNA(domain)) stop('Invalid descriptive domain.')
  domain <- as.logical(domain)
  raw_w <- weights(design)[design$variables$.dhs_record]
  valid <- domain & !is.na(indicator)
  if (any(!as.numeric(indicator[valid])%in%c(0,1))) stop('Percentage indicators must be binary.')
  if (!any(valid) || sum(raw_w[valid])<=0) return(c(percent=NA_real_,se_pct=NA_real_,ci_low_pct=NA_real_,ci_high_pct=NA_real_,unweighted_n=sum(valid),weighted_n=sum(raw_w[valid]),design_df=attr(design,'dhs_design_df')))
  design$variables$.dhs_indicator <- 0
  design$variables$.dhs_domain <- FALSE
  at <- which(design$variables$.dhs_record)
  design$variables$.dhs_indicator[at] <- as.numeric(indicator)
  design$variables$.dhs_domain[at] <- valid
  # svyratio keeps the full survey frame for domain inference. Its point
  # estimate is the same weighted proportion as svymean on the domain.
  design$variables$.dhs_num <- ifelse(design$variables$.dhs_domain,design$variables$.dhs_indicator,0)
  fit <- survey::svyratio(~.dhs_num,~.dhs_domain,design,na.rm=TRUE)
  p <- as.numeric(coef(fit)); se <- as.numeric(survey::SE(fit)); df <- attr(design,'dhs_design_df')
  critical <- qt(.975,df)
  interval <- p+c(-1,1)*critical*se
  # With no observed variation, a zero-width Wald interval is misleading.
  # Preserve the point/SE but leave uncertainty bounds unreported.
  if (p<=0 || p>=1) interval <- c(NA_real_,NA_real_)
  c(percent=100*p,se_pct=100*se,ci_low_pct=100*max(0,interval[1]),
    ci_high_pct=100*min(1,interval[2]),unweighted_n=sum(valid),
    weighted_n=sum(raw_w[valid]),design_df=df)
}

dhs_psu_variance <- function(influence, frame) {
  # influence contains already-weighted sums, one row per original-frame PSU.
  # survey::svyrecvar supplies the stratified design covariance, not a naive
  # model Hessian or an independent-record variance.
  f <- data.frame(wt=1,cluster=as.character(frame$cluster),stratum=as.character(frame$stratum))
  if (nrow(as.matrix(influence))!=nrow(f)) stop('Influence rows do not match the full PSU frame.')
  d <- dhs_design(f,f)
  survey::svyrecvar(as.matrix(influence),d$cluster,d$strata,d$fpc,lonely.psu='fail')
}

dhs_binary_fit <- function(formula, data, frame, weight='wt') {
  # Padding has zero weight but retains full-frame design degrees of freedom.
  # Keep actual analysis rows for downstream prediction/score calculations.
  data <- dhs_attach_design(data,check_weights=FALSE)
  frame <- dhs_context()$frame
  design <- dhs_design(data,frame,weight=weight)
  fit <- survey::svyglm(formula,design=design,subset=.dhs_record,
                         family=quasibinomial(),rescale=FALSE,
                         control=glm.control(maxit=100L,epsilon=1e-10))
  fit$df.residual <- attr(design,'dhs_design_df')-fit$rank+1L
  fit
}

dhs_current_duration <- function(ir, rows) {
  elapsed <- as.numeric(ir$v337[rows])
  special <- elapsed==95L
  if (any(special,na.rm=TRUE)) {
    if (!'v317'%in%names(ir)) stop('v317 is needed to resolve all-calendar current use.')
    elapsed[special] <- as.numeric(ir$v008[rows[special]])-as.numeric(ir$v317[rows[special]])
  }
  if (anyNA(elapsed) || any(!is.finite(elapsed)) || any(elapsed<0) || any(as.numeric(ir$v337[rows])%in%c(96L,997L,998L,999L))) stop('Unresolved current-use duration: do not treat special DHS codes as exact months.')
  elapsed
}

# One context per analysis subprocess; restricted records stay in memory.
.dhs_context <- new.env(parent=emptyenv())
dhs_set_context <- function(country=NULL, root=NULL, ir=NULL) {
  if (!is.null(country)) .dhs_context$country <- country
  if (!is.null(root)) .dhs_context$root <- root
  if (!is.null(ir)) {
    stopifnot(all(c('v005','v021','v022') %in% names(ir)))
    .dhs_context$ir <- as.data.frame(ir[,intersect(c('caseid','v005','v021','v022','v008','v317','v337'),names(ir)),drop=FALSE])
    .dhs_context$frame <- dhs_frame(ir)
    .dhs_context$woman_design <- dhs_design(data.frame(wt=as.numeric(ir$v005)/1e6,cluster=as.character(ir$v021),stratum=as.character(ir$v022)),.dhs_context$frame)
  }
  invisible(NULL)
}
dhs_context <- function() {
  if (!exists('ir',.dhs_context,inherits=FALSE)) {
    if (!exists('root',.dhs_context,inherits=FALSE)) stop('Initialize the DHS analysis context.')
    raw <- switch(.dhs_context$country,Ethiopia='Data/ET2024DHS__ETIR8ADT__IR_raw.rds',
                  Nigeria='Data/raw_dhs_ir/NG2024DHS__NGIR8BDT__IR_raw.rds',DRC='Data/ir.rds')
    staged <- file.path(.dhs_context$root,raw)
    if(file.exists(staged)) {
      ir <- readRDS(staged)
    } else if(identical(.dhs_context$country,'DRC')) {
      # DRC's preparation stage creates its lossless RDS after expanding the
      # calendar. Its supplied/staged IR is already available at that point.
      input <- Sys.getenv('DRC_IR_FILE',unset=file.path(.dhs_context$root,'Data/CDIR81FL.dta'))
      if(!file.exists(input)||!requireNamespace('haven',quietly=TRUE))
        stop('Supply the authorized DRC IR input before calendar preparation.')
      ir <- as.data.frame(haven::read_dta(input))
    } else stop('The prepared IR input is missing; run input preparation first.')
    dhs_set_context(ir=ir)
  }
  .dhs_context
}
# Calendar records inherit their woman's original design identifiers.
# A supplied estimation weight may be a resampling weight and is preserved.
dhs_attach_design <- function(data, ir=NULL, check_weights=TRUE) {
  data <- as.data.frame(data)
  if (is.null(ir)) ir <- dhs_context()$ir
  id <- if ('woman_row'%in%names(data)) data$woman_row else if ('woman'%in%names(data)) data$woman else NULL
  if (is.null(id) && 'caseid'%in%names(data) && 'caseid'%in%names(ir)) id <- match(data$caseid,ir$caseid)
  if (!is.null(id)) {
    if(anyNA(id)||any(id<1L|id>nrow(ir))||any(id!=as.integer(id)))stop('Invalid woman-to-calendar linkage.')
    data$cluster <- as.character(ir$v021[id]);data$stratum <- as.character(ir$v022[id])
    base_weight <- as.numeric(ir$v005[id])/1e6
    if (check_weights && 'wt'%in%names(data) && any(abs(as.numeric(data$wt)-base_weight)>1e-10))
      stop('Calendar base weights differ from the linked woman weights.')
    if(!'wt'%in%names(data))data$wt <- base_weight
    data$dhs_base_weight <- base_weight
    data$woman_id <- if('caseid'%in%names(ir))as.character(ir$caseid[id])else as.character(id)
  } else {
    if(!'cluster'%in%names(data))stop('Calendar records require woman linkage or PSU/stratum identifiers.')
    # Older modules store the nested PSU key instead of the original numeric ID.
    nested <- paste(as.character(ir$v022),as.character(ir$v021),sep=':')
    if(any(grepl(':',as.character(data$cluster),fixed=TRUE))) {
      at<-match(as.character(data$cluster),nested)
      if(anyNA(at))stop('Unrecognized nested PSU key.')
      data$cluster<-as.character(ir$v021[at])
      if('stratum'%in%names(data)&&any(as.character(data$stratum)!=as.character(ir$v022[at])))
        stop('Nested PSU key and stratum disagree.')
      data$stratum<-as.character(ir$v022[at])
    }
    if(!'stratum'%in%names(data))stop('Unlinked calendar records require explicit strata or a verified nested PSU key.')
  }
  data
}

# Point AFT fits use survey linearization; bootstrap refits can use the weighted
# likelihood because joint uncertainty is taken from the stratified PSU replicates.
dhs_aft_fit <- function(formula, data, weights, dist, control, ...) {
  supplied <- as.numeric(eval(substitute(weights),envir=data,enclos=parent.frame()))
  if(length(supplied)!=nrow(data)||anyNA(supplied)||any(supplied<0))stop('Invalid AFT estimation weights.')
  data <- dhs_attach_design(data,check_weights=FALSE)
  data$.aft_weight <- supplied
  data <- data[supplied>0,,drop=FALSE]
  if(isTRUE(getOption('dhs.replication',FALSE))) {
    return(survival::survreg(formula,data=data,weights=.aft_weight,dist=dist,control=control,...))
  }
  design <- dhs_design(data,dhs_context()$frame,weight='.aft_weight')
  fit <- do.call(survey::svysurvreg,list(formula=formula,design=design,
       subset=quote(.dhs_record),dist=dist,control=control,...))
  # svysurvreg deliberately removes its likelihood. Preserve the previous
  # weighted pseudo-AIC only for the separate, conditional family comparison;
  # do not restore it as a survey-model likelihood or use it for uncertainty.
  likelihood_fit <- survival::survreg(formula,data=data,weights=.aft_weight,
                                      dist=dist,control=control,...)
  if(max(abs(coef(fit)-coef(likelihood_fit)))>1e-6 ||
       abs(fit$scale-likelihood_fit$scale)>1e-6)
    stop('Survey and weighted AFT point fits do not agree.')
  fit$dhs_weighted_aic <- stats::AIC(likelihood_fit)
  fit$call$design <- quote(design)
  attr(fit,'dhs_design_df') <- attr(design,'dhs_design_df')
  fit
}
dhs_aft_aic <- function(fit) {
  if(inherits(fit,'svysurvreg')) {
    if(is.null(fit$dhs_weighted_aic))stop('Weighted family-comparison score is absent.')
    return(fit$dhs_weighted_aic)
  }
  stats::AIC(fit)
}

# Weighted multinomial coefficients with full-frame stratified PSU covariance.
# Retains the likelihood Hessian as the derivative; never reports it as survey variance.
dhs_multinom_summary <- function(fit, data, frame=NULL) {
  data <- dhs_attach_design(data,check_weights=FALSE)
  if(is.null(frame))frame<-dhs_context()$frame
  X<-model.matrix(delete.response(terms(fit)),data,contrasts.arg=fit$contrasts)
  p<-predict(fit,newdata=data,type='probs')
  if(is.null(dim(p)))stop('Use svyglm for binary models.')
  lev<-fit$lev[-1L];y<-model.response(model.frame(terms(fit),data))
  w<-if('fit_weight'%in%names(data))data$fit_weight else data$wt
  score<-do.call(cbind,lapply(lev,function(k)X*(w*(as.numeric(y==k)-p[,k]))))
  H<-fit$Hessian
  if(is.null(H))H<-getFromNamespace('multinomHess','nnet')(fit,Z=X,probs=p)
  expected<-unlist(lapply(lev,function(k)paste(k,colnames(X),sep=':')))
  if(!is.null(colnames(H))&&!identical(colnames(H),expected))stop('Multinomial score ordering differs from the Hessian.')
  key<-function(s,p)paste(s,p,sep=':')
  keys<-key(frame$stratum,frame$cluster);at<-match(key(data$stratum,data$cluster),keys)
  if(anyNA(at))stop('Model records do not match the original survey frame.')
  U<-matrix(0,nrow(frame),ncol(score));z<-rowsum(score,at,reorder=FALSE);U[as.integer(rownames(z)),]<-z
  bread<-MASS::ginv(H);V<-bread%*%dhs_psu_variance(U,frame)%*%bread
  co<-coef(fit);se<-matrix(sqrt(pmax(diag(V),0)),nrow=nrow(co),byrow=TRUE,dimnames=dimnames(co))
  list(coefficients=co,standard.errors=se,covariance=V,
       design_df=nrow(frame)-length(unique(frame$stratum)),inference='Full-frame stratified PSU sandwich')
}

dhs_calendar_records <- function(data, ir) {
  if(!'woman_row'%in%names(data))stop('Calendar records require woman_row.')
  id<-data$woman_row
  if(anyNA(id)||any(id<1L|id>nrow(ir)))stop('Invalid calendar woman indices.')
  w<-as.numeric(ir$v005[id])/1e6
  if('wt'%in%names(data)&&any(abs(as.numeric(data$wt)-w)>1e-10))stop('Calendar weight inheritance failed.')
  data$wt<-w;data$v021<-as.numeric(ir$v021[id]);data$v022<-as.numeric(ir$v022[id])
  data$woman_id<-as.character(ir$caseid[id])
  attr(data,'dhs_ir_design')<-as.data.frame(ir[,intersect(c('caseid','v005','v021','v022'),names(ir)),drop=FALSE])
  data
}

# Preserve survey covariance on fitted multinomial objects so subsequent
# summary()/vcov() calls cannot silently fall back to independent-record errors.
dhs_multinom_fit <- function(formula, data, weights, ...) {
  supplied<-as.numeric(eval(substitute(weights),envir=data,enclos=parent.frame()))
  if(length(supplied)!=nrow(data)||anyNA(supplied)||any(supplied<0))stop('Invalid multinomial estimation weights.')
  data<-dhs_attach_design(data,check_weights=FALSE);data$.dhs_fit_weight<-supplied
  fit<-nnet::multinom(formula,data=data,weights=.dhs_fit_weight,...)
  if(!is.null(fit$Hessian)&&!isTRUE(getOption('dhs.replication',FALSE))) {
    data$fit_weight<-supplied
    z<-dhs_multinom_summary(fit,data)
    fit$dhs_survey_vcov<-z$covariance;fit$dhs_design_df<-z$design_df
  }
  fit$dhs_inference<-if(is.null(fit$dhs_survey_vcov))'Stratified PSU refits required; ordinary Hessian inference disabled'else'Full-frame stratified PSU sandwich'
  class(fit)<-c('dhs_multinom',class(fit));fit
}
vcov.dhs_multinom <- function(object, ...) {
  if(is.null(object$dhs_survey_vcov))stop('This prediction/refit model has no point survey covariance. Use its stratified-PSU replicate inference.')
  object$dhs_survey_vcov
}
summary.dhs_multinom <- function(object, ...) {
  if(is.null(object$dhs_survey_vcov))stop('This prediction/refit model requires its stratified-PSU replicate inference.')
  getS3method('summary','multinom',envir=asNamespace('nnet'))(object,...)
}
)----------------------")

MODULES[["dhs_survey_descriptives.R"]] <- list(language="R", packaged_sha256="8ea87334fad4a5e2414113503a825c5d1ea8867ee162d7e2377020a31cfebbc9", args=character(0), code=r"----------------------(# DHS complex survey design for this module.
.dhs_root <- Sys.getenv('NIGERIA_PROJECT_ROOT')
if (!nzchar(.dhs_root)) {
 .dhs_file <- sub('^--file=','',grep('^--file=',commandArgs(FALSE),value=TRUE)[1])
 .dhs_root <- dirname(dirname(normalizePath(.dhs_file)))
}
source(file.path(.dhs_root,'Code','dhs_survey_tools.R'),local=TRUE)
dhs_set_context(country='Nigeria',root=.dhs_root)
#!/usr/bin/env Rscript
# National and subnational descriptive percentages. Supply the prepared project
# root through the country entry point; no existing report is an input.
country <- Sys.getenv('ANALYSIS_COUNTRY')
if (!country%in%c('Ethiopia','Nigeria','DRC')) stop('Set ANALYSIS_COUNTRY through the country entry point.')
root <- Sys.getenv(paste0(toupper(country),'_PROJECT_ROOT'))
if (!nzchar(root)) stop('A prepared project root is required.')
source(file.path(root,'Code','dhs_survey_tools.R'),local=TRUE)
raw <- switch(country,Ethiopia='Data/ET2024DHS__ETIR8ADT__IR_raw.rds',
 Nigeria='Data/raw_dhs_ir/NG2024DHS__NGIR8BDT__IR_raw.rds',DRC='Data/ir.rds')
episodes <- switch(country,Ethiopia='ethiopia_2024_table_7_11_episodes.rds',
 Nigeria='nigeria_2024_table_7_12_episodes.rds',DRC='drc_2023_24_table_7_13_episodes.rds')
ir <- readRDS(file.path(root,raw)); e <- readRDS(file.path(root,'Data/Derived',episodes))
frame <- dhs_frame(ir)
modern_codes <- c(1L,2L,3L,5L,6L,7L,11L,13L,14L,15L,17L,18L,19L,20L)
actionable <- c(1L,4L,5L,6L,7L,8L,10L,15L)
reason_groups <- list('Method failure'=1L,'Wanted pregnancy'=2L,
 'Other fertility'=c(9L,12L,13L),'Bleeding changes'=15L,
 'Other side effects/health'=c(4L,5L),'Wanted more effective method'=7L,
 'Access/cost/convenience'=c(6L,8L,10L),'Partner/spousal disapproval'=3L,
 'Other/unspecified'=c(11L,14L,96L,98L,99L,0L))
method_group <- function(code) {
 x <- rep('Other modern',length(code));x[code==1L]<-'Pill';x[code==2L]<-'IUD'
 x[code==3L]<-'Injectables';x[code==11L]<-'Implants';x[code==16L]<-'EC'
 x[!code%in%c(modern_codes,16L)]<-'Non-modern/no method';x
}
women <- data.frame(wt=as.numeric(ir$v005)/1e6,cluster=as.character(ir$v021),
 stratum=as.character(ir$v022),region=as.character(ir$v024),
 modern=as.numeric(ir$v313)==3L,method=method_group(as.numeric(ir$v312)))
e$cluster <- as.character(ir$v021[e$woman_row]);e$stratum <- as.character(ir$v022[e$woman_row])
e$region <- as.character(ir$v024[e$woman_row]);e$group <- method_group(e$method_code)
dw <- dhs_design(women,frame);de <- dhs_design(e,frame)
scopes <- c('National',sort(unique(women$region)))
results <- list();check <- 0
add <- function(design,data,indicator,domain,analysis,scope,category,method='All') {
 z <- dhs_percentage(design,indicator,domain)
 valid <- domain & !is.na(indicator)
 plain <- if(any(valid))100*sum(data$wt[valid]*as.numeric(indicator[valid]))/sum(data$wt[valid])else NA_real_
 if(is.finite(plain)) {
   if(abs(z['percent']-plain)>1e-9) stop('Survey and weighted descriptive point estimates disagree.')
   check <<- check+1L
 }
 results[[length(results)+1L]] <<- data.frame(country=country,analysis=analysis,
  scope=scope,method=method,category=category,as.list(z),row.names=NULL,
  observed_events=sum(as.logical(indicator[valid])),
  limited_sample=sum(valid)<25L || sum(as.logical(indicator[valid]))<10L,
  uncertainty='survey Taylor linearization; full PSU frame; 95% t interval',
  stringsAsFactors=FALSE)
}
for(scope in scopes) {
 wdomain <- if(scope=='National')rep(TRUE,nrow(women))else women$region==scope
 edomain <- if(scope=='National')rep(TRUE,nrow(e))else e$region==scope
 add(dw,women,women$modern,wdomain,'All-women mCPR',scope,'Modern use including EC')
 for(m in c('Injectables','Implants','Pill','IUD','Other modern','EC')) {
  add(dw,women,women$method==m,wdomain & women$modern,'Current modern-method mix',scope,m)
  add(dw,women,women$modern & women$method==m,wdomain,'Method-specific prevalence among all women',scope,m)
 }
 start_domain <- edomain & e$entry==0L
 for(m in sort(unique(e$group))) add(de,e,e$group==m,start_domain,'Observed starts: all methods',scope,m)
 for(m in c('Injectables','Implants','Pill','IUD','Other modern'))
  add(de,e,e$group==m,start_domain & e$method_code%in%modern_codes,'Observed starts: modern excluding EC',scope,m)
 for(m in c('All','Injectables','Implants','Pill','IUD','Other modern')) {
  mdomain <- edomain & e$method_code%in%modern_codes & (m=='All' | e$group==m)
  for(window in c('All eligible endings','First-12-month endings')) {
   ended <- mdomain & e$discontinued
   if(window=='First-12-month endings')ended<-ended & e$exposure<=12 & e$entry<e$exposure
   # These are shares AMONG observed endings, not life-table discontinuation risks.
   for(reason in names(reason_groups))add(de,e,e$reason_code%in%reason_groups[[reason]],ended,
    paste('Recorded reason shares:',window),scope,reason,m)
   for(reason in c('Method failure','Bleeding changes','Other side effects/health',
                    'Wanted more effective method','Access/cost/convenience'))
    add(de,e,e$reason_code%in%reason_groups[[reason]],ended & e$reason_code%in%actionable,
     paste('Shares within potentially actionable endings:',window),scope,reason,m)
  }
 }
}
out <- file.path(root,'output/Supporting_data');dir.create(out,recursive=TRUE,showWarnings=FALSE)
write.csv(do.call(rbind,results),file.path(out,'dhs_survey_descriptive_percentages.csv'),row.names=FALSE,na='')
metadata <- data.frame(country=country,weight='v005 / 1000000',PSU='v021',stratum='v022',
 PSUs=nrow(frame),strata=length(unique(frame$stratum)),
 design_df=survey::degf(dw),point_comparisons=check,
 all_point_comparisons_passed=TRUE,full_frame_including_zero_domain_PSUs=TRUE,
 repeated_episodes_kept_within_PSU=TRUE,survey_version=as.character(packageVersion('survey')))
write.csv(metadata,file.path(out,'dhs_survey_design_checks.csv'),row.names=FALSE)
cat('Survey descriptives complete:',country,';',check,'weighted point comparisons passed.\n')
)----------------------")

REPORT_FILES <- list()
REPORT_FILES[["src/report/05_render_nigeria_html.py"]] <- r"----------------------(#!/usr/bin/env python3
"""Render the Nigeria working HTML from the complete saved analysis tables.

Run after the R pipeline. This file contains only layout and wording. All
reported estimates come from saved data tables, so the visuals are repeatable.
"""
import csv
import html
import re
from pathlib import Path
import os

ROOT = Path(os.environ["NIGERIA_PROJECT_ROOT"])
SUP = ROOT / 'output/Supporting_data'
OUT = ROOT / 'output/Nigeria_discontinuation_analysis.html'

def read(name):
    with (SUP / name).open(newline='') as f:
        return list(csv.DictReader(f))

def f(x, n=1):
    try: return f'{float(x):.{n}f}'
    except (ValueError, TypeError): return '—'

def integer(x):
    try: return f'{float(x):,.0f}'
    except (ValueError, TypeError): return '—'

def h(x): return html.escape(str(x))

table7 = read('nigeria_table_7_12_replicated.csv')
table713 = read('nigeria_published_table_7_13_reason_distribution.csv')
modern_five_year_reasons = read('nigeria_modern_five_year_reason_distribution_seven.csv')
modern_five_year_by_method = read('nigeria_modern_five_year_reason_distribution.csv')
initiation = read('nigeria_initiation_mix_overall_by_year.csv')
all_times = read('nigeria_modern_all_reason_timepoints.csv')
all_reasons = read('nigeria_modern_all_reason_reason_mix.csv')
all_models = read('nigeria_all_reason_zone_models.csv')
all_subgroups = read('nigeria_all_reason_adjusted_subgroups.csv')
selected_models = read('nigeria_selected_reason_zone_models.csv')
selected_subgroups = read('nigeria_selected_reason_adjusted_subgroups.csv')
times = read('nigeria_actionable_timepoints.csv')
reasons = read('nigeria_actionable_reason_mix.csv')
mix = read('nigeria_zone_modern_method_start_mix.csv')
all_start_mix = read('nigeria_zone_all_method_start_mix.csv')
current = read('nigeria_current_use_mcpr.csv')
models = read('nigeria_actionable_zone_adjusted_rates.csv')
coef = read('nigeria_actionable_zone_model_odds_ratios.csv')
subgroups = read('nigeria_actionable_subgroup_rates_reasons.csv') if (SUP/'nigeria_actionable_subgroup_rates_reasons.csv').exists() else []
tests = read('nigeria_zone_pairwise_three_stages.csv') if (SUP/'nigeria_zone_pairwise_three_stages.csv').exists() else []
wra = read('nigeria_wpp2024_wra_2024_2026.csv')
users = read('nigeria_current_users_by_method_and_actionable_projection.csv')
user_causes = read('nigeria_current_users_actionable_by_cause.csv')
all_users = read('nigeria_current_users_all_reason_projection.csv')
all_user_causes = read('nigeria_current_users_all_reason_by_cause.csv')
switch = read('nigeria_actionable_immediate_modern_switch_share.csv')
scenarios = read('nigeria_2026_mcpr_scenarios.csv')
pathways = read('nigeria_actionable_post_ending_pathways.csv')
selected_pathways = read('nigeria_selected_reason_post_ending_pathways.csv')
transitions = read('nigeria_actionable_post_ending_transitions.csv')
switch_bridge = read('nigeria_switch_bridge_by_method.csv')
switch_bridge_cause = read('nigeria_switch_bridge_by_method_cause.csv')
duration_bridge = read('nigeria_duration_aware_current_user_bridge.csv')
duration_bridge_cause = read('nigeria_duration_aware_current_user_by_cause.csv')
duration_scenarios = read('nigeria_switch_duration_mcpr_scenarios.csv')
duration_sensitivity = read('nigeria_duration_61plus_sensitivity.csv')
zones = ['National','North West','North East','North Central','South East','South South','South West']
methods = ['Injectables','Implants','Pill','IUD','Other modern']
start_methods = ['Injectables','Implants','Pill','IUD','Emergency contraception','Other modern','Non-modern methods']
cause_names = ['Method failure','Wanted more effective method','Changes in menstrual bleeding','Other side effects/health','Access/cost/convenience']
colors = {'Injectables':'#108B8D','Implants':'#153F5B','Pill':'#DA9A25','IUD':'#D45A49','Emergency contraception':'#B65F8C','Other modern':'#85909D','Non-modern methods':'#A48865'}

def times_row(scope,month=12):
    return next(r for r in times if r['scope']==scope and int(r['month'])==month)

def all_times_row(scope,month=12):
    return next(r for r in all_times if r['scope']==scope and int(r['month'])==month)

def all_reason_row(scope,reason):
    return next(r for r in all_reasons if r['scope']==scope and r['reason']==reason)

def mix_row(zone,method):
    return next(r for r in mix if r['scope']==zone and r['method']==method)

def all_start_row(zone,method):
    return next(r for r in all_start_mix if r['scope']==zone and r['method']==method)

def reason_row(scope,name):
    return next(r for r in reasons if r['scope']==scope and r['reason']==name)

def td(x,cl=''):
    return f'<td class="{cl}">{x}</td>'

def th(x): return f'<th>{h(x)}</th>'

def section(id,title,eyebrow='',text=''):
    return f'<section id="{id}"><div class="eyebrow">{h(eyebrow)}</div><h2>{h(title)}</h2><p class="intro">{text}</p>'

def bar(value,color,widthscale=100):
    width=min(100,max(0,float(value)/widthscale*100))
    return f'<div class="bartrack"><span style="width:{width:.2f}%;background:{color}"></span></div>'

def rangebar(point,lo,hi,maxx=40,color='#108d94'):
    p=float(point);lo=float(lo);hi=float(hi)
    left=max(0,min(100,lo/maxx*100));right=max(0,min(100,hi/maxx*100))
    pos=max(0,min(100,p/maxx*100))
    return (f'<div class="rangebar"><i style="left:{left:.2f}%;width:{right-left:.2f}%;background:{color}"></i>'
            f'<b style="left:{pos:.2f}%;background:{color}"></b></div>')

def dual_rangebar(raw,raw_lo,raw_hi,adjusted,adjusted_lo,adjusted_hi,maxx=40):
    def item(point,lo,hi,color,top):
        x=lambda v:max(0,min(100,float(v)/maxx*100))
        left=x(lo);right=x(hi);pos=x(point)
        return (f'<i style="left:{left:.2f}%;width:{right-left:.2f}%;top:{top}px;background:{color}"></i>'
                f'<b style="left:{pos:.2f}%;top:{top-3}px;background:{color}"></b>')
    return '<div class="dualplot">'+item(raw,raw_lo,raw_hi,'#DA9A25',8)+item(adjusted,adjusted_lo,adjusted_hi,'#153F5B',20)+'</div>'

def heat_cell(value,national=False):
    x=float(value)
    # Accessible single-hue teal scale; national uses the presentation gold.
    light=95-55*x/55
    if national: bg=f'hsl(38 76% {min(94,max(57,light+7)):.0f}%)'
    else: bg=f'hsl(184 42% {max(40,min(96,light)):.0f}%)'
    return f'<td class="heat" style="background:{bg}">{f(x)}%</td>'

parts=[]
parts.append('''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Nigeria DHS 2024 | Contraceptive discontinuation</title>
<style>
:root{--navy:#153F5B;--teal:#108B8D;--gold:#DA9A25;--ink:#17222C;--line:#D6E2E5;--light:#F5F8F9}
*{box-sizing:border-box}html{scroll-behavior:smooth}body{margin:0;color:var(--ink);font:16px/1.48 Arial,Helvetica,sans-serif;background:#fff}
aside{position:fixed;inset:0 auto 0 0;width:254px;overflow:auto;background:#f5f8f9;border-right:1px solid var(--line);padding:26px 17px;z-index:5}
aside strong{font:700 19px Georgia,serif;color:var(--navy)}aside small{display:block;color:#617783;margin:4px 0 22px}
aside a{display:block;text-decoration:none;color:#335366;font-size:13px;padding:7px 8px;border-radius:4px}aside a:hover{background:#e5f1f2;color:#085f66}
main{margin-left:254px;padding:0 38px 90px;max-width:1580px}header{padding:48px 0 25px;border-bottom:3px solid var(--navy)}
header h1,h2{font-family:Georgia,serif;color:var(--navy);line-height:1.13}header h1{font-size:37px;margin:7px 0 10px}header p{max-width:850px;margin:0;color:#445b68}
section{padding:38px 0 18px;border-bottom:1px solid var(--line);scroll-margin-top:10px}.eyebrow{color:#8b641f;font-size:12px;font-weight:700;letter-spacing:.09em;text-transform:uppercase}
h2{font-size:29px;margin:5px 0 9px}h3{font-size:20px;color:var(--navy);margin:25px 0 8px}.intro{max-width:1050px;margin:0 0 20px}
.metrics{display:flex;gap:32px;flex-wrap:wrap;margin:18px 0 22px}.metric strong{display:block;color:var(--navy);font:700 33px Georgia,serif}.metric span{font-size:13px;color:#526774}
.note{background:#f1f6f7;border-left:4px solid var(--teal);padding:12px 16px;margin:16px 0;font-size:14px}.goldnote{background:#fff7e8;border-color:var(--gold)}
.tablewrap{overflow-x:auto}table{border-collapse:collapse;width:100%;font-size:13px}th{text-align:left;color:var(--navy);border-bottom:2px solid var(--navy);padding:9px 8px;white-space:nowrap}td{border-bottom:1px solid #e3eaed;padding:8px}tbody tr:nth-child(even){background:#fbfcfc}.num{text-align:right;font-variant-numeric:tabular-nums}.small{font-size:12px;color:#5c6f78}.heat{text-align:center;font-variant-numeric:tabular-nums;color:#172e38;min-width:112px;border:2px solid white}
.pairchart{max-width:1000px}.pairrow{display:grid;grid-template-columns:145px 1fr 46px;align-items:center;gap:10px;margin:10px 0}.pairrow label{text-align:right}.pairrow .two{display:grid;gap:3px}.pairrow .two .sub{display:grid;grid-template-columns:110px 1fr 48px;align-items:center;gap:6px;font-size:12px}.bartrack{height:12px;background:#eef3f5;position:relative}.bartrack span{display:block;height:100%}.pairrow strong{font-size:13px}
.zonebars{max-width:930px}.zonebar{display:grid;grid-template-columns:125px 1fr;gap:12px;align-items:center;margin:10px 0}.stack{height:27px;display:flex;width:100%;background:#e7eef0}.stack span{height:100%}.legend{display:flex;flex-wrap:wrap;gap:14px;margin:12px 0 4px;font-size:13px}.legend span:before{content:'';display:inline-block;width:12px;height:12px;background:var(--c);margin-right:5px;vertical-align:-1px}
.forestrow{display:grid;grid-template-columns:133px minmax(220px,610px) 165px;gap:12px;align-items:center;margin:11px 0}.forestrow label{text-align:right}.rangebar{position:relative;height:20px;border-bottom:1px solid #cfdee3;background:repeating-linear-gradient(90deg,transparent 0,transparent calc(25% - 1px),#ecf1f3 calc(25% - 1px),#ecf1f3 25%)}.rangebar i{position:absolute;height:3px;top:9px}.rangebar b{position:absolute;width:9px;height:9px;border-radius:50%;top:6px;transform:translateX(-50%)}
.dualrow{display:grid;grid-template-columns:133px minmax(220px,610px) 105px 105px;gap:12px;align-items:center;margin:11px 0;font-variant-numeric:tabular-nums}.dualrow label{text-align:right}.dualrow.national{background:#F0F4F5}.dualplot{position:relative;height:30px;border-bottom:1px solid #cfdee3;background:repeating-linear-gradient(90deg,transparent 0,transparent calc(25% - 1px),#ecf1f3 calc(25% - 1px),#ecf1f3 25%)}.dualplot i{position:absolute;height:2px}.dualplot b{position:absolute;width:9px;height:9px;border-radius:50%;transform:translateX(-50%)}
.grid2{display:grid;grid-template-columns:1fr 1fr;gap:26px}.tag{display:inline-block;color:#754f14;background:#fff0cc;border-radius:3px;padding:1px 5px;font-size:11px}
@media(max-width:900px){aside{position:static;width:auto;max-height:170px;border-right:0;border-bottom:1px solid var(--line)}aside a{display:inline-block}main{margin:0;padding:0 18px 50px}.grid2{display:block}.forestrow{grid-template-columns:95px 1fr 93px;font-size:12px}header h1{font-size:30px}}
</style></head><body>''')
nav=[('overview','Overview'),('methodology','Definitions and denominators'),('initiation','Initiation mix'),('dhs-712','DHS Table 7.12 replication'),('dhs-713','Modern-method reasons and DHS validation'),('all-cause','All-reason discontinuation'),('selected-reasons','Excluding pregnancy and partner'),('selected-models','Selected-reason adjusted models'),('selected-followup','Follow-up after selected endings'),('all-reason-users','All-reason current-user illustration'),('national','Actionable national patterns'),('timing','Actionable risk over time'),('zone-rates','Actionable zone rates'),('zone-reasons','Actionable reasons by zone'),('method-mix','Method starts by zone'),('methods-by-zone','Methods within zones'),('method-reasons','Reasons within methods'),('models','Adjusted models'),('subgroups','Subgroups'),('pairwise','Pairwise differences'),('current-use','Current use'),('post-ending','Use after stopping'),('population','Population and assumptions'),('user-projections','Actionable user illustration'),('mcpr-scenarios','2026 mCPR scenarios'),('regional-analyses','Regional analyses summary'),('switch-bridge','Direct modern switching'),('duration-bridge','Duration and year-end use')]
story_order=['overview','methodology','current-use','initiation','dhs-712','dhs-713',
 'all-cause','all-reason-users','selected-reasons','selected-models',
 'selected-followup','national','timing','zone-rates','zone-reasons',
 'method-mix','methods-by-zone','method-reasons','models','subgroups',
 'pairwise','regional-analyses','post-ending','population','user-projections',
 'mcpr-scenarios','switch-bridge','duration-bridge']
nav.sort(key=lambda item: story_order.index(item[0]))
parts.append('<aside><strong>Nigeria discontinuation</strong><small>2024 DHS • working analysis</small>'+''.join(f'<a href="#{a}">{b}</a>' for a,b in nav)+'</aside><main>')
parts.append('<header id="overview"><div class="eyebrow">Nigeria DHS 2024</div><h1>Modern-method discontinuation: all reasons, then program-actionable causes</h1><p>The analysis follows the Ethiopia presentation sequence: validate the DHS all-method table; examine all-reason modern-method discontinuation, including pregnancy intentions and partner disapproval; then narrow to selected and potentially actionable causes. An original-method ending is different from stopping all modern contraceptive use.</p></header>')
nat=times_row('National');mc=next(r for r in current if r['scope']=='National')
parts.append(section('methodology','What each probability measures','Study frame',
    'The published DHS Table 7.12 uses all eligible method-use episodes, including traditional methods and emergency contraception. Our subsequent continuing-use analyses use eligible modern-method episodes, excluding emergency contraception. We show three cumulative probabilities on that modern episode cohort: ending the original method for any reason; ending for any reason except wanted pregnancy and partner disapproval; and ending for the narrower potentially actionable method experience or access causes. At every stage, other endings remain competing events in the starting risk set.'))
parts.append(f'<div class="metrics"><div class="metric"><strong>{integer(nat["eligible_episodes_n"])}</strong><span>eligible modern-method episodes</span></div><div class="metric"><strong>{f(nat["all_reason_pct"])}%</strong><span>12-month ending for any reason</span></div><div class="metric"><strong>{f(nat["actionable_pct"])}%</strong><span>12-month actionable ending</span></div><div class="metric"><strong>{f(mc["all_women_mcpr_pct"])}%</strong><span>current mCPR, all women 15–49</span></div></div>')
all_starts_n=int(all_start_mix[0]['denominator_observed_starts_n'])
model_reference_n=sum(int(r['observed_starts_n']) for r in all_start_mix
    if r['scope']=='National' and r['method'] in methods)
published_all=next(r for r in table7 if r['method']=='All methods')
parts.append('<h3>Which sample and denominator does each display use?</h3><div class="tablewrap"><table><thead><tr><th>Display</th><th>Observed source records</th><th>Denominator / interpretation</th></tr></thead><tbody>')
sample_rows=[
 ('Published DHS Table 7.12',f'{integer(published_all["unweighted_episodes"])} episodes; {integer(published_all["weighted_episodes"])} weighted; {integer(published_all["late_entries"])} late entries','All eligible episodes of any method, including traditional methods and EC; the life table updates the risk set by month.'),
 ('Method-start share',f'{integer(all_starts_n)} observed starts','All observed method starts; method shares sum to 100% within a geography.'),
 ('All-reason, selected and actionable risk',f'{integer(nat["eligible_episodes_n"])} modern episodes; {integer(int(nat["eligible_episodes_n"])-model_reference_n)} late entries','Eligible modern-method episodes, excluding EC; other reasons are competing endings. Each method-specific risk uses episodes of that method.'),
 ('Reason shares among discontinuations','The relevant observed first-year endings','The cause-specific 12-month probabilities divided by the total for the stated reason set; displayed shares sum to 100% before rounding.'),
 ('Adjusted regional predictions',f'{integer(nat["eligible_episodes_n"])} episodes for fitting; {integer(model_reference_n)} observed starts for prediction','Episode-month competing-outcome model; adjusted comparisons average predicted risks over one shared observed-start cohort.'),
 ('Current use and planning','39,050 interviewed women; projected user stock','DHS all-women mCPR and current method mix are applied to UN women 15–49; these are illustrations, not life-table denominators.')]
for label,count,meaning in sample_rows:
    parts.append('<tr>'+td(h(label))+td(h(count))+td(h(meaning))+'</tr>')
parts.append('</tbody></table></div><p class="small">The number of episodes is a cohort count, not a fixed denominator applied at every follow-up month; left-truncated episodes enter the risk set when observation begins. Survey weights are used for estimates, and stratified cluster resampling supplies the displayed probability intervals.</p>')
parts.append('<div class="note"><b>Interpretation:</b> 38.9% is the all-reason first-year cumulative incidence for the original modern method; 21.4% is its narrower actionable component. Neither is the fraction of current users who will stop all modern contraception next year. Switching is included when the original method ends and must be handled separately for mCPR planning.</div></section>')

parts.append(section('initiation','Entry methods set the denominator for future retention risk','Observed starts',
  'A method start is an observed beginning of an episode in the DHS calendar, not current contraceptive use at interview. This diagnostic initially includes all method categories and emergency contraception, as in the Ethiopia presentation. Later first-year continuing-use rates exclude EC and traditional methods.'))
parts.append('<h3>Overall method-start mix</h3><div class="tablewrap"><table><thead><tr><th>Method category</th><th>Weighted share of starts</th><th>Observed starts</th></tr></thead><tbody>')
for r in [x for x in initiation if x['scope']=='Overall']:
    parts.append('<tr>'+td(h(r['method']))+td(f(r['start_share_pct'])+'%','num')+td(integer(r['observed_starts_n']),'num')+'</tr>')
parts.append('</tbody></table></div>')
parts.append('<h3>Initiation mix by calendar year</h3><div class="tablewrap"><table><thead><tr><th>Year</th><th>Observed starts</th>'+''.join(th(m) for m in ['Injectables','Implants','Pill','IUD','Emergency contraception','Other modern','Non-modern methods'])+'</tr></thead><tbody>')
for year in ['2021','2022','2023','2024']:
    rows=[r for r in initiation if r['scope']==year]
    parts.append('<tr>'+td(year+(' *' if year=='2024' else ''))+td(integer(rows[0]['denominator_observed_starts_n']),'num')+''.join(td(f(r['start_share_pct'])+'%','num') for r in rows)+'</tr>')
parts.append('</tbody></table></div><p class="small">* The 2024 calendar-year start window is incomplete under the DHS 3–62-month analysis window and contains only 64 observed starts. Do not interpret its mix as a full-year trend. Survey weights are applied to shares.</p></section>')

parts.append(section('dhs-712','The calendar reconstruction matches published Table 7.12','Validation',
  'The 2024 Nigeria DHS report publishes a multiple-decrement life table for discontinuation within 12 months. Reconstructed rates match all 110 published rate cells and all 10 published weighted episode counts after rounding.'))
cols=[('reason_1_pct','Failure'),('reason_2_pct','Wanted pregnancy'),('reason_3_pct','Other fertility'),('reason_4_pct','Bleeding'),('reason_5_pct','Other health'),('reason_6_pct','More effective'),('reason_7_pct','Other method'),('reason_8_pct','Partner'),('reason_9_pct','Other'),('any_reason_pct','Any reason'),('switching_pct','Switched'),('weighted_episodes','Weighted episodes')]
parts.append('<div class="tablewrap"><table><thead><tr><th>Method</th>'+''.join(th(label) for _,label in cols)+'</tr></thead><tbody>')
for r in table7:
    parts.append('<tr>'+td(h(r['method']))+''.join(td(integer(r[k]) if k=='weighted_episodes' else f(r[k]),'num') for k,_ in cols)+'</tr>')
parts.append('</tbody></table></div><p class="small">All methods includes traditional methods and emergency contraception, as in the published table. The subsequent modern-method analyses use a narrower, explicitly labeled episode cohort. Source: <a href="https://www.health.gov.ng/wp-content/uploads/2025/10/NDHS-2024-Final-Report_Disseminated17102025.pdf">Nigeria DHS 2024 final report, Table 7.12</a>.</p></section>')

parts.append(section('dhs-713','Reasons among recorded modern-method discontinuations','Five-year calendar distribution',
  'Matching the Ethiopia presentation, the primary reason distribution includes only recorded endings of modern-method episodes in the five-year calendar, excluding emergency contraception. It contains 4,557 unweighted endings (4,531.8 weighted). These percentages describe reasons among endings, not a first-year discontinuation probability.'))
parts.append('<h3>All modern methods: reasons among recorded endings</h3><div class="tablewrap"><table><thead><tr><th>Recorded reason</th><th>Weighted share of modern-method endings</th></tr></thead><tbody>')
for r in modern_five_year_reasons:
    parts.append('<tr>'+td(h(r['reason']))+td(f(r['percent'])+'%','num')+'</tr>')
parts.append('</tbody></table></div><p class="small">The seven categories sum to 100% before rounding. Source: Nigeria DHS 2024 IR contraceptive calendar, survey-weighted; modern-method endings excluding EC.</p>')
parts.append('<h3>Reason distribution by modern method</h3><div class="tablewrap"><table><thead><tr><th>Method</th><th>Wanted pregnancy</th><th>Method experience/access</th><th>Partner disapproval</th><th>Other reasons</th><th>Observed endings</th></tr></thead><tbody>')
for m in ['All modern','Injectables','Implants','Pill','IUD','Other modern']:
    rows=[r for r in modern_five_year_by_method if r['method']==m]
    parts.append('<tr>'+td(h(m))+''.join(td(f(r['percent'])+'%','num') for r in rows)+td(integer(rows[0]['unweighted_endings']),'num')+'</tr>')
parts.append('</tbody></table></div><p class="small">Each row sums to 100% before rounding. The observed endings are unweighted; percentages use DHS survey weights. EC and traditional methods are excluded.</p>')
parts.append('<h3>Published DHS Table 7.13: all-method validation comparison</h3><p class="small">The official table below includes traditional methods and emergency contraception. It validates the calendar extraction but has a different denominator from the modern-method presentation figure.</p>')
table713_methods=['All methods','IUD','Injectables','Implants','Pill','Male condom','Emergency contraception','Rhythm','Withdrawal','Other']
parts.append('<div class="tablewrap"><table><thead><tr><th>Recorded reason</th>'+''.join(th(x) for x in table713_methods)+'</tr></thead><tbody>')
for r in table713:
    parts.append('<tr>'+td(h(r['reason']))+''.join(td(f(r[x])+'%','num') for x in table713_methods)+'</tr>')
parts.append('</tbody></table></div><p class="small">Published weighted numbers of discontinuations: all methods 5,847; injectables 1,412; implants 1,009; pill 708; IUD 78. The report also includes a small “missing reason” row. Source: <a href="https://www.health.gov.ng/wp-content/uploads/2025/10/NDHS-2024-Final-Report_Disseminated17102025.pdf">Nigeria DHS 2024, Table 7.13</a>.</p></section>')

parts.append(section('all-cause','All-reason discontinuation comes first','Modern-method cohort',
  'The modern-method cohort includes 8,341 eligible use episodes (emergency contraception excluded). The 12-month all-reason probability is 38.9%. An episode that ends because a woman wants pregnancy or because her partner disapproves counts here. The published DHS all-methods row is 37.2% because it includes a broader set of methods.'))
parts.append('<h3>Method starts and 12-month all-reason discontinuation</h3><div class="pairchart">')
for m in methods:
    r=all_start_row('National',m);t=all_times_row('National: '+m)
    parts.append(f'<div class="pairrow"><label>{h(m)}</label><div class="two"><div class="sub"><span>Start share</span>{bar(r["start_share_pct"],"#DA9A25",70)}<strong>{f(r["start_share_pct"])}%</strong></div><div class="sub"><span>Any-reason risk</span>{bar(t["all_reason_pct"],"#153e56",70)}<strong>{f(t["all_reason_pct"])}%</strong></div></div><span></span></div>')
parts.append('</div><p class="small">Both bars have a 0–70% scale. The gold share uses all observed method starts, including EC and non-modern methods. The navy risk uses eligible episodes of the named modern method, excluding EC.</p>')
parts.append('<h3>All-reason risk at 3, 6, 9 and 12 months</h3><div class="tablewrap"><table><thead><tr><th>Original method</th>'+''.join(th(f'{t} months') for t in (3,6,9,12))+'</tr></thead><tbody>')
for m in ['All modern']+methods:
    scope='National' if m=='All modern' else 'National: '+m
    parts.append('<tr>'+td(h(m))+''.join(td(f(all_times_row(scope,t)['all_reason_pct'])+'%','num') for t in (3,6,9,12))+'</tr>')
parts.append('</tbody></table></div>')
parts.append('<h3>Why modern-method episodes ended within 12 months</h3><p>These are weighted shares of the all-reason cumulative discontinuation probability, so the nine reason columns sum to 100% within each method before rounding. The table above instead expresses risk among all eligible episodes.</p>')
full_reason_names=[r['reason'] for r in all_reasons if r['scope']=='National']
parts.append('<div class="tablewrap"><table><thead><tr><th>Original method</th>'+''.join(th(x) for x in full_reason_names)+'</tr></thead><tbody>')
for m in ['All modern']+methods:
    scope='National' if m=='All modern' else 'National: '+m
    parts.append('<tr>'+td(h(m))+''.join(td(f(all_reason_row(scope,x)['share_among_all_discontinuation_pct'])+'%','num') for x in full_reason_names)+'</tr>')
parts.append('</tbody></table></div>')
parts.append('<h3>Unadjusted all-reason risk by geopolitical zone</h3><p>Intervals resample survey clusters within strata and retain all episodes for each woman together.</p>')
for z in zones:
    r=all_times_row(z)
    parts.append(f'<div class="forestrow"><label>{h(z)}</label>{rangebar(r["all_reason_pct"],r["all_reason_ci_low"],r["all_reason_ci_high"],60,"#DA9A25" if z=="National" else "#108d94")}<span>{f(r["all_reason_pct"])}% <small>({f(r["all_reason_ci_low"])}–{f(r["all_reason_ci_high"])}%)</small></span></div>')
parts.append('<h3>Reasons among all first-year discontinuations by zone</h3><p>Companion view to the regional risk plot, following the Ethiopia presentation. Each row divides the zone’s all-reason 12-month discontinuation probability and sums to 100% before rounding; it is not the probability among all starters.</p>')
all_cause_groups=[('Wanted pregnancy',['Wanted pregnancy']),
 ('Method experience/access',['Method failure','Changes in menstrual bleeding','Other side effects/health','Wanted more effective method','Access/cost/convenience']),
 ('Partner disapproved',['Partner disapproved']),
 ('Other',['Other fertility-related','Other recorded reasons'])]
parts.append('<div class="tablewrap"><table><thead><tr><th>Zone</th>'+''.join(th(label) for label,_ in all_cause_groups)+'</tr></thead><tbody>')
for z in zones:
    parts.append('<tr>'+td(h(z))+''.join(heat_cell(sum(float(all_reason_row(z,reason)['share_among_all_discontinuation_pct']) for reason in reason_list),z=='National') for _,reason_list in all_cause_groups)+'</tr>')
parts.append('</tbody></table></div>')
parts.append('<h3>Adjusted all-reason probability by subgroup</h3><p>Episode-month logistic regression estimates the probability that the original method ends for any reason. It includes original method, month of use, zone, age and parity at method start, marital status, education, wealth, residence and start year. Marginal predictions use the same observed-start cohort for each category; intervals resample survey clusters within strata. These are associations, not effects of changing a characteristic.</p>')
parts.append('<div class="tablewrap"><table><thead><tr><th>Characteristic</th><th>Category</th><th>Adjusted 12-month probability (95% CI)</th></tr></thead><tbody>')
for r in all_subgroups:
    parts.append('<tr>'+td(h(r['covariate'].replace('_',' ').title()))+td(h(r['category']))+td(f(r['adjusted_12_month_pct'])+f'% ({f(r["ci_low"])}–{f(r["ci_high"])}%)','num')+'</tr>')
parts.append('</tbody></table></div>')
parts.append('<h3>Observed and adjusted all-reason risk by zone</h3><p>Method-adjusted and fully adjusted predictions compare zones using the same national observed-start composition. The observed column retains each zone’s actual method and population mix.</p>')
parts.append('<div class="tablewrap"><table><thead><tr><th>Zone</th><th>Observed % (95% CI)</th><th>Method adjusted % (95% CI)</th><th>Fully adjusted % (95% CI)</th></tr></thead><tbody>')
for r in all_models:
    parts.append('<tr>'+td(h(r['zone']))+td(f(r['unadjusted_pct'])+f'% ({f(r["unadjusted_low"])}–{f(r["unadjusted_high"])}%)','num')+td(f(r['model_1_pct'])+f'% ({f(r["model_1_low"])}–{f(r["model_1_high"])}%)','num')+td(f(r['model_2_pct'])+f'% ({f(r["model_2_low"])}–{f(r["model_2_high"])}%)','num')+'</tr>')
parts.append('</tbody></table></div>')
parts.append('</section>')

sel=all_times_row('National')
parts.append(section('selected-reasons','The intermediate selected-reason measure','Excluding two reasons',
  f'Among all eligible modern-method episodes, the 12-month probability of ending for any reason other than wanted pregnancy or partner disapproval is {f(sel["selected_reason_pct"])}%. Wanted pregnancy and partner disapproval are retained as competing outcomes, not removed from the original cohort. This intermediate measure still includes other fertility-related and other recorded reasons; it is therefore broader than the actionable outcome used later.'))
parts.append('<div class="tablewrap"><table><thead><tr><th>Original method</th><th>Any reason</th><th>Except wanted pregnancy and partner disapproval</th><th>Potentially actionable</th></tr></thead><tbody>')
for m in ['All modern']+methods:
    scope='National' if m=='All modern' else 'National: '+m
    r=all_times_row(scope)
    parts.append('<tr>'+td(h(m))+td(f(r['all_reason_pct'])+'%','num')+td(f(r['selected_reason_pct'])+'%','num')+td(f(r['actionable_pct'])+'%','num')+'</tr>')
parts.append('</tbody></table></div>')
parts.append('<h3>Selected-reason cumulative risk by method</h3><p>Every percentage is a weighted life-table probability among eligible modern-method episodes of the named original method. Wanted pregnancy and partner disapproval still remove episodes from the risk set when they occur.</p>')
parts.append('<div class="tablewrap"><table><thead><tr><th>Original method</th>'+''.join(th(f'{k} months') for k in (3,6,9,12))+'</tr></thead><tbody>')
for m in ['All modern']+methods:
    scope='National' if m=='All modern' else 'National: '+m
    parts.append('<tr>'+td(h(m))+''.join(td(f(all_times_row(scope,k)['selected_reason_pct'])+'%','num') for k in (3,6,9,12))+'</tr>')
parts.append('</tbody></table></div>')
selected_names=[x for x in full_reason_names if x not in ('Wanted pregnancy','Partner disapproved')]
parts.append('<h3>Reason distribution among selected first-year discontinuations</h3><p>Each method row sums to 100% before displayed rounding. Its denominator is the cumulative probability of ending for any retained reason by month 12; this is a reason distribution, not the chance of ending among all starters.</p>')
parts.append('<div class="tablewrap"><table><thead><tr><th>Original method</th>'+''.join(th(x) for x in selected_names)+'</tr></thead><tbody>')
for m in ['All modern']+methods:
    scope='National' if m=='All modern' else 'National: '+m
    denom=float(all_times_row(scope)['selected_reason_pct'])
    parts.append('<tr>'+td(h(m))+''.join(td(f(100*float(all_reason_row(scope,x)['cause_specific_12_month_pct'])/denom)+'%','num') for x in selected_names)+'</tr>')
parts.append('</tbody></table></div>')
parts.append('<h3>Selected-reason risk and reason distribution by zone</h3><p>The zone probability uses all eligible modern-method episodes in that zone. The seven reason cells divide only the selected first-year discontinuations in that zone and sum to 100% before rounding.</p>')
parts.append('<div class="tablewrap"><table><thead><tr><th>Zone</th><th>12-month risk</th>'+''.join(th(x) for x in selected_names)+'</tr></thead><tbody>')
for z in zones:
    denom=float(all_times_row(z)['selected_reason_pct'])
    parts.append('<tr>'+td(h(z))+td(f(denom)+'%','num')+''.join(td(f(100*float(all_reason_row(z,x)['cause_specific_12_month_pct'])/denom)+'%','num') for x in selected_names)+'</tr>')
parts.append('</tbody></table></div>')
parts.append('<div class="note goldnote">The first two measures include discontinuations that are not necessarily service failures. The next phase focuses on method failure, wanting greater effectiveness, bleeding changes, other health effects, and access/cost/convenience.</div></section>')

parts.append(section('selected-models','Who is more likely to discontinue for a selected reason?','Adjusted selected-reason models',
  'The outcome in each observed episode-month is continuation of the original method, discontinuation for any reason except wanted pregnancy or partner disapproval, or discontinuation for one of those two competing reasons. Model 1 includes month of use, original method and zone. Model 2 additionally includes age and parity at method start, marital status, education, wealth, residence and start year. Adjusted probabilities are 12-month cumulative incidences predicted for the common observed-start cohort; survey clusters are resampled within strata for 95% intervals.'))
parts.append('<h3>Observed and adjusted 12-month probability by zone</h3><div class="tablewrap"><table><thead><tr><th>Zone</th><th>Observed (95% CI)</th><th>Model 1 (95% CI)</th><th>Model 2 (95% CI)</th></tr></thead><tbody>')
for r in selected_models:
    parts.append('<tr>'+td(h(r['zone']))+td(f(r['unadjusted_pct'])+f'% ({f(r["unadjusted_low"])}–{f(r["unadjusted_high"])}%)','num')+td(f(r['model_1_pct'])+f'% ({f(r["model_1_low"])}–{f(r["model_1_high"])}%)','num')+td(f(r['model_2_pct'])+f'% ({f(r["model_2_low"])}–{f(r["model_2_high"])}%)','num')+'</tr>')
parts.append('</tbody></table></div><h3>Adjusted 12-month probability by subgroup</h3><div class="tablewrap"><table><thead><tr><th>Characteristic</th><th>Category</th><th>Adjusted probability (95% CI)</th></tr></thead><tbody>')
for r in selected_subgroups:
    parts.append('<tr>'+td(h(r['covariate'].replace('_',' ').title()))+td(h(r['category']))+td(f(r['adjusted_12_month_pct'])+f'% ({f(r["ci_low"])}–{f(r["ci_high"])}%)','num')+'</tr>')
parts.append('</tbody></table></div><p class="small">Adjusted differences describe associations after measured covariates are accounted for; they do not establish a causal effect or that every regional pair differs significantly.</p></section>')

parts.append(section('selected-followup','What happened after selected-reason discontinuation?','Ethiopia pathway counterpart',
  'This follow-up cohort includes first-year modern-method endings for any reason except wanted pregnancy or partner disapproval. It is broader than the actionable cohort used later. The month-1 and month-12 tables have different observed denominators because a full year of subsequent calendar data is unavailable for some endings.'))
for checkpoint in (1,12):
    rows=[r for r in selected_pathways if int(r['month_after_ending'])==checkpoint]
    parts.append(f'<h3>{checkpoint} month{"s" if checkpoint!=1 else ""} after ending</h3><div class="tablewrap"><table><thead><tr><th>Contraceptive status</th><th>Weighted share</th><th>Observed endings</th></tr></thead><tbody>')
    for r in rows:
        parts.append('<tr>'+td(h(r['status']))+td(f(r['percent'])+'%','num')+td(integer(r['observed_ending_events_n']),'num')+'</tr>')
    parts.append('</tbody></table></div>')
parts.append('<p class="small">A method ending does not automatically mean exit from modern contraception. Later re-entry and switching are descriptive pathways, not part of the first-year discontinuation probability.</p></section>')

parts.append(section('all-reason-users','Illustrative current-user endings for all reasons','All-reason planning counterpart',
  'The 2024 baseline combines Nigeria DHS 2024 all-women mCPR and current-method shares with UN 2024 women aged 15–49. The 2025 counts project that baseline using UN 2025 population and an assumed 0.4-percentage-point rise in mCPR, holding method shares constant. Projected 2025 users of each ongoing modern method are multiplied by its 12-month all-reason probability after a method start. This is an original-method ending illustration, not a forecast of users lost from modern contraception. It does not account for duration already used or subsequent switching. Emergency contraception is included in current modern use but excluded from continuing-use risk.'))
parts.append('<div class="tablewrap"><table><thead><tr><th>Original method</th><th>2024 users (DHS × UN)</th><th>Projected 2025 users</th><th>First-year all-reason risk</th><th>Illustrative original-method endings</th></tr></thead><tbody>')
for r in all_users:
    baseline=next(u for u in users if u['method']==r['method'])
    parts.append('<tr>'+td(h(r['method']))+td(integer(baseline['current_users_2024']),'num')+td(integer(r['current_users_2025']),'num')+td(f(r['all_reason_first_year_risk_pct'])+'%','num')+td(integer(r['illustrative_original_method_endings']),'num')+'</tr>')
parts.append('</tbody></table></div><h3>Illustrative endings by recorded reason</h3><p>Each reason uses its own cause-specific life-table probability among all eligible starts of that method. Reason columns add to the all-reason ending count before display rounding.</p>')
parts.append('<div class="tablewrap"><table><thead><tr><th>Original method</th>'+''.join(th(x) for x in full_reason_names)+'<th>All reasons</th></tr></thead><tbody>')
for m in methods:
    rr={r['reason']:float(r['illustrative_original_method_endings']) for r in all_user_causes if r['method']==m}
    parts.append('<tr>'+td(h(m))+''.join(td(integer(rr.get(c,0)),'num') for c in full_reason_names)+td(integer(sum(rr.values())),'num')+'</tr>')
parts.append('</tbody></table></div><p class="small">The estimated 2025 user stock uses Nigeria-specific women aged 15–49, the stated mCPR scenario, and the Nigeria DHS current-method mix. This all-reason table is intentionally shown before the later potentially actionable user-loss scenario.</p></section>')

parts.append(section('national','Method starts and 12-month actionable risk','Program-actionable phase',
  'The gold share uses all observed method starts, as in the Ethiopia presentation. The paired navy rate is the probability that the named modern method ends for a potentially actionable reason by month 12 among eligible episodes of that method.'))
parts.append('<div class="pairchart">')
for m in methods:
    r=all_start_row('National',m); risk=mix_row('National',m)
    parts.append(f'<div class="pairrow"><label>{h(m)}</label><div class="two"><div class="sub"><span>Start share</span>{bar(r["start_share_pct"],"#DA9A25",50)}<strong>{f(r["start_share_pct"])}%</strong></div><div class="sub"><span>12-month risk</span>{bar(risk["actionable_12_month_pct"],"#153F5B",50)}<strong>{f(risk["actionable_12_month_pct"])}%</strong></div></div><span></span></div>')
parts.append('</div><p class="small">Both bar lengths use a 0–50% scale. Emergency contraception is excluded from continuing-use denominators.</p></section>')

parts.append(section('timing','Actionable discontinuation accumulates during the first year','National and zones',
    'Each cell is the weighted cumulative probability among eligible episodes in the row. The final column shows how much of the month-12 risk had already occurred by month 3.'))
parts.append('<div class="tablewrap"><table><thead><tr><th>Geography</th>'+''.join(th(f'{m} months') for m in (3,6,9,12))+th('Share by 3 months')+'</tr></thead><tbody>')
for z in zones:
    vals=[times_row(z,m) for m in (3,6,9,12)]
    share=100*float(vals[0]['actionable_pct'])/float(vals[-1]['actionable_pct'])
    parts.append('<tr>'+td(h(z))+''.join(heat_cell(r['actionable_pct'],z=='National') for r in vals)+td(f(share)+'%','num')+'</tr>')
parts.append('</tbody></table></div><p class="small">95% intervals account for sample strata, clusters, and survey weights; see the zone chart below.</p></section>')

parts.append(section('zone-rates','Potentially actionable risk differs across the six zones','Subnational',
    'Unadjusted 12-month cumulative incidence with 95% stratified cluster-bootstrap intervals. The national rate is the dotted reference in the presentation version.'))
for z in zones:
    r=times_row(z)
    parts.append(f'<div class="forestrow"><label>{h(z)}</label>{rangebar(r["actionable_pct"],r["ci_low"],r["ci_high"],40,"#DA9A25" if z=="National" else "#108d94")}<span>{f(r["actionable_pct"])}% <small>({f(r["ci_low"])}–{f(r["ci_high"])})</small></span></div>')
parts.append('</section>')

parts.append(section('zone-reasons','The mix of actionable reasons varies by zone','Reasons',
    'Within each row, the five shares add to 100% of the 12-month potentially actionable discontinuation probability. These are shares among actionable discontinuations, not risks among all starts.'))
parts.append('<div class="tablewrap"><table><thead><tr><th>Zone</th>'+''.join(th(x) for x in cause_names)+'</tr></thead><tbody>')
for z in zones:
    parts.append('<tr>'+td(h(z))+''.join(heat_cell(reason_row(z,x)['share_among_actionable_pct'],z=='National') for x in cause_names)+'</tr>')
parts.append('</tbody></table></div><p class="small">Other side effects/health includes other side effects or health concerns; menstrual bleeding changes are shown separately. Access/cost/convenience combines lack of access or too far, cost too much, and inconvenient to use.</p></section>')

parts.append(section('method-mix','Entry method mix is different across the six zones','Starts',
    'Each row sums to 100% of all observed method starts, including emergency contraception and non-modern methods, matching the Ethiopia slide denominator. National is shown first for comparison.'))
parts.append('<div class="zonebars">')
for z in zones:
    seg=''.join(f'<span title="{h(m)} {f(all_start_row(z,m)["start_share_pct"])}%" style="width:{float(all_start_row(z,m)["start_share_pct"]):.3f}%;background:{colors[m]}"></span>' for m in start_methods)
    parts.append(f'<div class="zonebar"><label>{h(z)}</label><div class="stack">{seg}</div></div>')
parts.append('</div><div class="legend">'+''.join(f'<span style="--c:{colors[m]}">{h(m)}</span>' for m in start_methods)+'</div></section>')

parts.append(section('methods-by-zone','Within-method risk shows where method mix cannot explain the whole pattern','Methods by zone',
    'For each method, the gold bar is its share of all observed method starts in that zone; the navy bar below is its 12-month actionable discontinuation probability among eligible episodes of that method. Small IUD cells need caution.'))
for m in methods:
    parts.append(f'<h3>{h(m)}</h3><div class="pairchart">')
    for z in zones:
        r=all_start_row(z,m); risk=mix_row(z,m); time=times_row(f'{z}: {m}' if z!='National' else f'National: {m}')
        small=int(time['actionable_endings_n'])<30
        parts.append(f'<div class="pairrow"><label>{h(z)}{" *" if small else ""}</label><div class="two"><div class="sub"><span>Start share</span>{bar(r["start_share_pct"],"#DA9A25",60)}<strong>{f(r["start_share_pct"])}%</strong></div><div class="sub"><span>12-month risk</span>{bar(risk["actionable_12_month_pct"],"#153F5B",60)}<strong>{f(risk["actionable_12_month_pct"])}%</strong></div></div><span></span></div>')
    parts.append('</div>')
parts.append('<p class="small">* Fewer than 30 observed actionable endings. Treat the rate as imprecise. Bars share a 0–60% axis within this section.</p></section>')

parts.append(section('method-reasons','Reasons within each method and zone','Method-specific reasons',
    'The five shares in each visible row sum to 100% of that method’s actionable 12-month risk. An asterisk flags fewer than 30 eligible episodes or 30 observed actionable endings; an em dash suppresses cells with fewer than 10 such endings or fewer than 30 eligible episodes.'))
for m in methods:
    parts.append(f'<h3>{h(m)}</h3><div class="tablewrap"><table><thead><tr><th>Zone</th>'+''.join(th(x) for x in cause_names)+'</tr></thead><tbody>')
    for z in zones:
        scope=f'National: {m}' if z=='National' else f'{z}: {m}'
        rr=[reason_row(scope,x) for x in cause_names]
        n=int(rr[0]['eligible_episodes_n']);ev=int(rr[0]['actionable_endings_n'])
        label=z+(' *' if ev<30 or n<30 else '')
        cells=(''.join(heat_cell(r['share_among_actionable_pct'],z=='National') for r in rr)
               if n>=30 and ev>=10 else ''.join(td('—','num') for _ in rr))
        parts.append('<tr>'+td(h(label))+cells+'</tr>')
    parts.append('</tbody></table></div>')
parts.append('<p class="small">* Fewer than 30 eligible episodes or 30 actionable endings; interpret cautiously. Gray cells have fewer than 30 episodes or 10 actionable endings and their shares are withheld. Other side effects/health includes other side effects or health concerns; menstrual bleeding changes are separate. Access/cost/convenience combines lack of access or too far, cost too much, and inconvenient to use. Percentages are cumulative-incidence contributions normalized within the actionable category.</p></section>')

parts.append(section('models','Adjustment helps separate composition from zone differences','Regression',
    'Both models use an episode-month multinomial outcome: continue the original method, end for an actionable reason, or end for a competing reason. Model 1 includes elapsed method-use month, original method, and zone. Model 2 adds age and parity at episode start, plus marital status, education, wealth, residence at interview, and calendar year of start. The 50 episodes started in 2024 had no observed actionable endings, so 2023 and 2024 starts are pooled in the model year term to avoid separation. Predictions use the same national observed-start cohort for every zone.'))
parts.append('<h3>Observed versus fully adjusted risk, with 95% intervals</h3><p><span style="color:#DA9A25">■</span> Observed &nbsp; <span style="color:#153F5B">■</span> Fully adjusted. Both intervals resample survey clusters within strata.</p>')
for z in zones:
    r=next(q for q in models if q['zone']==z)
    parts.append('<div class="dualrow'+(' national' if z=='National' else '')+'"><label>'+h(z)+'</label>'+dual_rangebar(r['unadjusted_pct'],r['unadjusted_low'],r['unadjusted_high'],r['model_2_common_mix_pct'],r['model_2_low'],r['model_2_high'])+'<span>'+f(r['unadjusted_pct'])+'%</span><span>'+f(r['model_2_common_mix_pct'])+'%</span></div>')
parts.append('<p class="small">Horizontal axis: 0–40%. The adjusted probability is standardized to the same observed-start cohort for each zone.</p>')
parts.append('<div class="tablewrap"><table><thead><tr><th>Zone</th><th>Observed % (95% CI)</th><th>Method adjusted %</th><th>Fully adjusted %</th></tr></thead><tbody>')
for z in zones:
    r=next(q for q in models if q['zone']==z)
    model1=f(r['model_1_common_mix_pct'])
    model2=f(r['model_2_common_mix_pct'])
    if r.get('model_1_low'):
        model1+=f' ({f(r["model_1_low"])}–{f(r["model_1_high"])})'
        model2+=f' ({f(r["model_2_low"])}–{f(r["model_2_high"])})'
    parts.append('<tr>'+td(h(z))+td(f(r['unadjusted_pct'])+f'% ({f(r["unadjusted_low"])}–{f(r["unadjusted_high"])})','num')+td(model1,'num')+td(model2,'num')+'</tr>')
parts.append('</tbody></table></div><div class="note goldnote">A standardized zone estimate is a model prediction for that zone under a common observed-start mix of methods and measured characteristics. It describes adjusted differences. It does not assign an intervention or prove a causal regional effect.</div>')
parts.append('<h3>Model 2 odds ratios for actionable ending versus continuing that month</h3><div class="tablewrap"><table><thead><tr><th>Covariate</th><th>Odds ratio</th><th>95% model CI</th><th>p value</th></tr></thead><tbody>')
for r in coef:
    if r['model']=='Full' and r['outcome']=='actionable' and r['covariate']!='(Intercept)' and not r['covariate'].startswith('month'):
        p_label='&lt;0.001' if float(r['p_value'])<.001 else f(r['p_value'],3)
        parts.append('<tr>'+td(h(r['covariate']))+td(f(r['odds_ratio'],2),'num')+td(f(r['ci_low'],2)+'–'+f(r['ci_high'],2),'num')+td(p_label,'num')+'</tr>')
parts.append('</tbody></table></div><p class="small">Reference categories: IUD; North West; ages 25–34; parity 0; married; no education; poorest; urban; first start-year category. Odds-ratio intervals and p values use the model Hessian and do not account for the DHS survey design; use the survey-cluster bootstrap comparisons above for regional inference.</p></section>')

parts.append(section('subgroups','Observed actionable risk by subgroup','Exploratory',
    'These rates use one covariate at a time and preserve competing endings. They describe subgroup patterns before model adjustment. Each reason share is a share of the subgroup’s actionable 12-month probability.'))
if subgroups:
    parts.append('<div class="tablewrap"><table><thead><tr><th>Characteristic</th><th>Category</th><th>Episodes</th><th>12-month risk (95% CI)</th><th>Leading actionable reason</th></tr></thead><tbody>')
    for r in subgroups:
        cs=[('Method failure',r.get('Method.failure','0')),('Wanted more effective method',r.get('Wanted.more.effective.method','0')),('Bleeding',r.get('Changes.in.menstrual.bleeding','0')),('Other health',r.get('Other.side.effects.health','0')),('Access',r.get('Access.cost.convenience','0'))]
        lead=max(cs,key=lambda x:float(x[1] or 0))[0]
        covariate_labels={'age_group':'Age at method start','parity':'Parity at method start','marital_status':'Marital status','education':'Education','wealth':'Wealth quintile','residence':'Residence','zone_name':'Geopolitical zone'}
        parts.append('<tr>'+td(h(covariate_labels.get(r['covariate'],r['covariate'])))+td(h(r['category']))+td(integer(r['eligible_episodes_n']),'num')+td(f(r['actionable_12_month_pct'])+f'% ({f(r["ci_low"])}–{f(r["ci_high"])})','num')+td(h(lead))+'</tr>')
    parts.append('</tbody></table></div>')
else: parts.append('<p>Subgroup bootstrap results are being generated from the same episode cohort.</p>')
parts.append('</section>')

parts.append(section('pairwise','Which zone contrasts survive statistical testing?','Inference',
    'All 15 pairwise zone contrasts are tested for the observed rates, method-adjusted predictions, and fully adjusted predictions. Tests use stratified PSU-bootstrap standard errors; Holm correction is applied within each stage.'))
if tests:
    for stage in ['Unadjusted','Method adjusted','Fully adjusted']:
        rows=[r for r in tests if r['stage']==stage]
        sig=[r for r in rows if r['significant_5pct']=='TRUE']
        parts.append(f'<h3>{h(stage)}: {len(sig)} of 15 contrasts at 5%</h3>')
        if sig:
            parts.append('<div class="tablewrap"><table><thead><tr><th>Zone A</th><th>Zone B</th><th>Difference (pp)</th><th>95% CI</th><th>Holm p</th></tr></thead><tbody>')
            for r in sorted(sig,key=lambda q:abs(float(q['difference_pp'])),reverse=True):
                parts.append('<tr>'+td(h(r['zone_a']))+td(h(r['zone_b']))+td(f(r['difference_pp']))+td(f(r['ci_low'])+'–'+f(r['ci_high']))+td(f(r['p_holm'],3))+'</tr>')
            parts.append('</tbody></table></div>')
        else: parts.append('<p>No pairwise contrast remains significant after Holm correction.</p>')
else: parts.append('<p>Pairwise bootstrap tests are being generated.</p>')
parts.append('<p class="small">A nonsignificant result does not establish that two zones have equal risk. The family of 15 tests is corrected separately for each comparison stage.</p></section>')

parts.append(section('current-use','Current modern use and implications for user-loss planning','Planning',
    'The 2024 IR recode estimates mCPR among all women age 15–49. Converting a first-year episode risk to expected losses among today’s users requires how long current users have already used each method; converting retained users to mCPR points also requires a dated national or zone-specific population of women age 15–49 and explicit assumptions about switching.'))
parts.append('<div class="tablewrap"><table><thead><tr><th>Geography</th><th>Women interviewed</th><th>Current modern users interviewed</th><th>All-women mCPR</th><th>EC share among current modern users</th></tr></thead><tbody>')
for z in zones:
    r=next(q for q in current if q['scope']==z)
    parts.append('<tr>'+td(h(z))+td(integer(r['women_n']),'num')+td(integer(r['modern_users_n']),'num')+td(f(r['all_women_mcpr_pct'])+'%','num')+td(f(r['ec_share_of_modern_users_pct'])+'%','num')+'</tr>')
parts.append('</tbody></table></div></section>')

parts.append(section('post-ending','Modern use after an actionable method ending','Pathways',
    'The calendar reveals contraceptive status after an observed method ending. The one-month and 12-month rows use different follow-up cohorts because the latter requires twelve observed months. These are weighted descriptive shares among observed actionable endings, not cumulative discontinuation probabilities.'))
parts.append('<div class="tablewrap"><table><thead><tr><th>Months after ending</th><th>Status</th><th>Share</th><th>Observed endings</th></tr></thead><tbody>')
for r in pathways:
    parts.append('<tr>'+td(h(r['month_after_ending']))+td(h(r['status']))+td(f(r['percent'])+'%','num')+td(integer(r['observed_ending_events_n']),'num')+'</tr>')
parts.append('</tbody></table></div><p class="small">The one-month checkpoint is relevant to switching; the 12-month checkpoint shows that later use can differ. Pregnancy, birth and termination are calendar states, not contraceptive methods.</p>')
parts.append('<h3>Transitions in the common twelve-month follow-up cohort</h3><p class="small">Each cell is a weighted percentage of the same 1,216 observed endings; all cells together sum to 100%. Rows are status one month after ending and columns are status twelve months after ending.</p>')
states=['No method recorded','Different modern method','Same modern method','Traditional/other method','Pregnant, birth or termination','Other/unknown']
parts.append('<div class="tablewrap"><table><thead><tr><th>Month 1 status</th>'+''.join(th(x) for x in states)+'</tr></thead><tbody>')
for a in states:
    cells=[]
    for b in states:
        found=next((r for r in transitions if r['month_1']==a and r['month_12']==b),None)
        cells.append(td(f(found['share_of_common_cohort_pct'])+'%' if found else '0.0%','num'))
    parts.append('<tr>'+td(h(a))+''.join(cells)+'</tr>')
parts.append('</tbody></table></div></section>')

parts.append(section('population','Nigeria population and mCPR inputs','Planning inputs',
    'The observed 2024 baseline pairs Nigeria DHS 2024 all-women mCPR and current-method mix with UN 2024 women aged 15–49. For 2025, we use the UN 2025 population and assume mCPR rises by 0.4 percentage points, holding the DHS method mix fixed. That increment comes from the Track20/FP2030 modeled all-women mCPR change from 13.2% in 2024 to 13.6% in 2025; it is transferred to the DHS baseline, not a relative 0.4% growth rate. The central 2026 scenario adds another 0.4 points. The third scenario instead uses the FP2030 2025 level of 13.6% plus 0.4 points to set 2026 mCPR at 14.0%. These are assumptions, not observed 2025 values or published 2026 forecasts.'))
parts.append('<div class="tablewrap"><table><thead><tr><th>Year</th><th>Women aged 15–49</th><th>Source</th></tr></thead><tbody>')
for r in wra:parts.append('<tr>'+td(h(r['year']))+td(integer(r['women_15_49']),'num')+td('UN WPP 2024 medium variant')+'</tr>')
parts.append('</tbody></table></div>')
central=scenarios[1]
parts.append('<h3>From the 2024 baseline to the central projection</h3><div class="tablewrap"><table><thead><tr><th>Year</th><th>All-women mCPR</th><th>Women aged 15–49</th><th>Modern users</th><th>Interpretation</th></tr></thead><tbody>')
for year,rate,women,count,label in [
    (2024,central['mcpr_2024_pct'],central['wra_2024'],central['current_users_2024'],'DHS 2024 prevalence × UN 2024 population'),
    (2025,central['mcpr_2025_pct'],central['wra_2025'],central['current_users_2025'],'Projected: +0.4 pp mCPR, UN 2025 population'),
    (2026,central['mcpr_2026_pct'],central['wra_2026'],central['usual_users_2026'],'Illustrative central scenario: another +0.4 pp')]:
    parts.append('<tr>'+td(year)+td(f(rate,2)+'%','num')+td(integer(women),'num')+td(integer(count),'num')+td(h(label))+'</tr>')
parts.append('</tbody></table></div>')
population_growth=(float(central['wra_2025'])/float(central['wra_2024'])-1)*100
user_growth=(float(central['current_users_2025'])/float(central['current_users_2024'])-1)*100
relative_mcpr_growth=(float(central['mcpr_2025_pct'])/float(central['mcpr_2024_pct'])-1)*100
parts.append(f'<p class="small">The planning increment is <b>+0.4 percentage points of mCPR per year</b>, transferred from the modeled Track20/FP2030 2024–25 difference. Relative to the DHS 2024 baseline, that is a {f(relative_mcpr_growth,2)}% proportional mCPR increase. UN women aged 15–49 grow {f(population_growth,2)}% from 2024 to 2025; together these assumptions raise the estimated number of modern users by {f(user_growth,2)}%. None of these is an observed DHS change between 2024 and 2025.</p>')
parts.append('<p class="small">Source: <a href="https://population.un.org/wpp/">UN WPP 2024</a>, female single-age workbook POP/F01-3. mCPR and method mix: weighted Nigeria DHS 2024 IR recode (v313 and v312). Trend source: <a href="https://www.track20.org/download/resources/Country%20Indicators/2025/2025%20Combo%20Briefs/English/Nigeria%202025%20Summary%20Brief%20and%20Handout.pdf">Track20/FP2030 Nigeria 2025 brief</a>.</p></section>')

parts.append(section('user-projections','Illustrative current-user method endings','Planning scale',
    'Estimated 2024 users by method equal UN 2024 women aged 15–49 × DHS 2024 mCPR × DHS 2024 current-method share. Projected 2025 users use UN 2025 population and a 2025 mCPR 0.4 points higher, holding method shares constant. Illustrative original-method endings equal projected 2025 users × method-specific first-year actionable life-table risk. These counts do not account for duration already used and are not forecasts of women leaving all modern contraception.'))
parts.append('<div class="tablewrap"><table><thead><tr><th>Method</th><th>DHS 2024 current mix</th><th>2024 users (DHS × UN)</th><th>Projected 2025 users</th><th>First-year actionable risk</th><th>Illustrative original-method endings</th></tr></thead><tbody>')
for r in users:
    risk='Not applied' if r['method']=='EC' else f(r['actionable_first_year_risk_pct'])+'%'
    endings='Not estimated' if r['method']=='EC' else integer(r['illustrative_original_method_endings'])
    parts.append('<tr>'+td(h(r['method']))+td(f(r['share_current_modern_pct'])+'%','num')+td(integer(r['current_users_2024']),'num')+td(integer(r['current_users_2025']),'num')+td(risk,'num')+td(endings,'num')+'</tr>')
gross_endings=sum(float(r['illustrative_original_method_endings']) for r in users)
current_users=sum(float(r['current_users_2025']) for r in users)
parts.append(f'</tbody></table></div><p class="small">The {f(100*gross_endings/current_users)}% ratio of illustrative endings to all projected 2025 modern users is not the {f(nat["actionable_pct"])}% national life-table risk. The former uses DHS 2024 current-method mix, includes EC users in the projected stock with no EC ending estimate, and assumes every ongoing-method user faces first-year start risks; the latter uses eligible episode starts.</p>')
parts.append('<h3>Original-method endings by actionable cause</h3><div class="tablewrap"><table><thead><tr><th>Method</th>'+''.join(th(x) for x in cause_names)+'<th>Total</th></tr></thead><tbody>')
for m in methods:
    rows=[r for r in user_causes if r['method']==m]
    vals={r['reason']:float(r['illustrative_users']) for r in rows}
    parts.append('<tr>'+td(h(m))+''.join(td(integer(vals.get(c,0)),'num') for c in cause_names)+td(integer(sum(vals.values())),'num')+'</tr>')
parts.append('</tbody></table></div><p class="small">Cause columns sum to the method total before displayed rounding. The IUD cause breakdown is based on only 17 observed actionable first-year endings and is especially imprecise.</p>')
parts.append('<h3>Immediate switching changes the interpretation</h3><div class="tablewrap"><table><thead><tr><th>Original method</th><th>Actionable endings observed</th><th>Next-month modern method (%)</th></tr></thead><tbody>')
for r in switch:parts.append('<tr>'+td(h(r['method']))+td(integer(r['actionable_events_n']),'num')+td(f(r['share_immediate_modern_pct'])+'%','num')+'</tr>')
parts.append('</tbody></table></div><p class="small">This is the weighted share using another modern method in the month after the original episode ended. It does not establish contraceptive status at the end of 2026.</p></section>')

parts.append(section('mcpr-scenarios','Illustrative 2026 mCPR scenarios','Planning scenarios',
    'Usual 2026 users equal projected 2026 women aged 15–49 multiplied by the assumed 2026 all-women mCPR. A gross upper bound then adds all illustrative actionable original-method endings. A narrower bound subtracts the portion that immediately switches to another modern method. Both remain illustrative because they apply first-year risks to current users and do not model their duration, later switching, entrants or causal intervention effectiveness.'))
parts.append('<div class="tablewrap"><table><thead><tr><th>Scenario</th><th>DHS 2024 mCPR</th><th>2024 users (DHS × UN)</th><th>Projected 2025 mCPR</th><th>Projected 2025 users</th><th>2026 usual mCPR</th><th>2026 usual users</th><th>Gross no-ending mCPR</th><th>Gross ceiling gain</th><th>After immediate-switch bound</th></tr></thead><tbody>')
for r in scenarios:
    parts.append('<tr>'+td(h(r['scenario']))+td(f(r['mcpr_2024_pct'])+'%','num')+td(integer(r['current_users_2024']),'num')+td(f(r['mcpr_2025_pct'])+'%','num')+td(integer(r['current_users_2025']),'num')+td(f(r['mcpr_2026_pct'])+'%','num')+td(integer(r['usual_users_2026']),'num')+td(f(r['no_gross_endings_mcpr_2026_pct'])+'%','num')+td(f(r['gross_ceiling_gain_pp'])+' pp','num')+td(f(r['no_non_switch_endings_mcpr_2026_pct'])+'%','num')+'</tr>')
parts.append('</tbody></table></div><div class="note goldnote">For the central DHS-anchored trend scenario, 2026 usual mCPR is '+f(scenarios[1]['mcpr_2026_pct'])+'%. Adding every illustrative original-method ending yields '+f(scenarios[1]['no_gross_endings_mcpr_2026_pct'])+'% (+'+f(scenarios[1]['gross_ceiling_gain_pp'])+' percentage points). Removing immediate modern switchers from that count yields a narrower '+f(scenarios[1]['no_non_switch_endings_mcpr_2026_pct'])+'% ceiling. Neither is a predicted effect of a real program.</div></section>')

parts.append(section('regional-analyses','Regional analyses','Subnational summary',
  'Nigeria’s six geopolitical zones are compared using three clearly different 12-month outcomes. The first column counts original-method endings for any reason. The second excludes wanted pregnancy and partner disapproval as events of interest, while retaining them as competing endings. The third—the focus of the detailed regional reason heatmaps, method-by-zone comparisons and pairwise tests—is limited to potentially actionable method experience and access causes. Every rate uses eligible modern-method episodes as its starting cohort; emergency contraception is excluded from continuing-use risk.'))
parts.append('<h3>Which reasons are included in each zone rate?</h3><div class="tablewrap"><table><thead><tr><th>Zone</th><th>Any reason (95% CI)</th><th>Except pregnancy intention and partner disapproval (95% CI)</th><th>Potentially actionable (95% CI)</th></tr></thead><tbody>')
for z in zones:
    a=all_times_row(z);q=times_row(z)
    parts.append('<tr>'+td(h(z))+td(f(a['all_reason_pct'])+f'% ({f(a["all_reason_ci_low"])}–{f(a["all_reason_ci_high"])}%)','num')+td(f(a['selected_reason_pct'])+f'% ({f(a["selected_reason_ci_low"])}–{f(a["selected_reason_ci_high"])}%)','num')+td(f(q['actionable_pct'])+f'% ({f(q["ci_low"])}–{f(q["ci_high"])}%)','num')+'</tr>')
parts.append('</tbody></table></div>')
parts.append('<h3>Reason mix within actionable first-year discontinuations</h3><p>Each row distributes only the actionable 12-month cumulative incidence in that zone. Its five cells add to 100% before display rounding. These are shares among actionable discontinuations, not rates among all episodes.</p>')
parts.append('<div class="tablewrap"><table><thead><tr><th>Zone</th>'+''.join(th(x) for x in cause_names)+'</tr></thead><tbody>')
for z in zones:
    parts.append('<tr>'+td(h(z))+''.join(heat_cell(reason_row(z,c)['share_among_actionable_pct'],z=='National') for c in cause_names)+'</tr>')
parts.append('</tbody></table></div><p class="small">Bleeding changes and other side effects/health are separate categories. Access/cost/convenience combines lack of access, cost and inconvenience. The <a href="#method-reasons">method-specific reason tables</a> show the same actionable cause distribution for injectables, implants, pills, IUDs and other modern methods in each zone. See <a href="#pairwise">pairwise zone tests</a> for statistical comparisons. Sparse method-by-zone cause cells are flagged in those detailed tables.</p></section>')

parts.append(section('switch-bridge','Direct modern switching reduces the gross user-loss illustration','Planning bridge A',
    'The earlier table applies each method’s 12-month actionable original-method ending probability to projected 2025 current users. Here the observed share of those endings followed immediately by another modern method is removed from the illustrative loss count. Direct switchers remain modern users. The remainder is <b>not</b> an estimate of women absent from the 2026 mCPR numerator because later restarting and existing method duration are still unaccounted for.'))
parts.append('<div class="tablewrap"><table><thead><tr><th>Original method</th><th>Projected 2025 current users</th><th>Gross actionable method endings</th><th>Direct modern switchers</th><th>Endings without direct modern switch</th><th>Observed actionable endings (n)</th></tr></thead><tbody>')
for r in switch_bridge:
    parts.append('<tr>'+td(h(r['method']))+td(integer(r['current_users_2025']),'num')+td(integer(r['illustrative_original_method_endings']),'num')+td(integer(r['illustrative_direct_modern_switchers']),'num')+td(integer(r['illustrative_not_directly_switching']),'num')+td(integer(r['observed_actionable_endings_n']),'num')+'</tr>')
ec_2025=next(float(r['current_users_2025']) for r in users if r['method']=='EC')
parts.append('<tr>'+td('EC')+td(integer(ec_2025),'num')+''.join(td('Not estimated') for _ in range(3))+td('—')+'</tr>')
parts.append('<tr><th>All modern</th>'+td(integer(ec_2025+sum(float(r['current_users_2025']) for r in switch_bridge)),'num')+''.join(td(integer(sum(float(r[k]) for r in switch_bridge)),'num') for k in ['illustrative_original_method_endings','illustrative_direct_modern_switchers','illustrative_not_directly_switching'])+td('—')+'</tr></tbody></table></div>')
parts.append('<p class="small">Direct modern switching means another modern method appears in the next calendar month. The observed switch fraction is survey weighted within each original-method group; counts are scaled to projected 2025 users. EC remains in current mCPR but has no ongoing-use ending risk. The IUD switching estimate rests on only 17 observed actionable endings and should not be interpreted as evidence of zero switching.</p>')
parts.append('<h3>Cause-specific gross endings and direct modern switches</h3><div class="tablewrap"><table><thead><tr><th>Method</th><th>Actionable cause</th><th>Gross original-method endings</th><th>Direct modern switchers</th><th>Without direct modern switch</th><th>Observed endings (n)</th></tr></thead><tbody>')
for r in switch_bridge_cause:
    parts.append('<tr>'+td(h(r['method']))+td(h(r['reason']))+td(integer(r['illustrative_original_method_endings']),'num')+td(integer(r['illustrative_direct_modern_switchers']),'num')+td(integer(r['illustrative_not_directly_switching']),'num')+td(integer(r['observed_endings_n']),'num')+'</tr>')
parts.append('</tbody></table></div><p class="small">Cause-specific switch patterns use observed first-year actionable endings within method and reason, then are calibrated to each method-level direct-switch total so the tables reconcile. Cells with fewer than 30 endings are exploratory; a displayed zero can reflect sparse data.</p>')
parts.append('<h3>How this changes the existing 2026 scenario illustration</h3><div class="tablewrap"><table><thead><tr><th>2026 mCPR scenario</th><th>Usual mCPR</th><th>Gross endings</th><th>After direct switches</th><th>Illustrative pp if all remaining women stayed modern</th></tr></thead><tbody>')
for r in duration_scenarios:
    pp=100*float(r['first_year_not_directly_switching'])/float(r['wra_2026'])
    parts.append('<tr>'+td(h(r['scenario']))+td(f(r['mcpr_2026_pct'],2)+'%','num')+td(integer(r['first_year_gross_endings']),'num')+td(integer(r['first_year_not_directly_switching']),'num')+td(f(pp,2)+' pp','num')+'</tr>')
parts.append('</tbody></table></div><p class="small">The last column is a mechanical ceiling, not a forecast of program effect. It still assumes every current user faces a first-year start risk and that every nonswitching ending would otherwise lower year-end mCPR.</p></section>')

parts.append(section('duration-bridge','Accounting for elapsed use and modern status at year end','Planning bridge B',
    'A current user who has already used a method for 18 months needs a risk for the <em>next</em> 12 months conditional on having continued for 18 months. The DHS 2024 current-user duration variable (v337) supplies that elapsed time. We use 103,447 historical method-use months from 5,192 women that have 12 more calendar months observed, calculate what happened over those months, and weight the method-and-duration results to the DHS current-user distribution. Thus the endpoint here is 12 months after a current-use landmark, not 12 months after method initiation.'))
parts.append('<div class="tablewrap"><table><thead><tr><th>Current method</th><th>Projected 2025 users</th><th>Actionable ending next 12 months</th><th>Direct modern switch</th><th>Modern at year end after actionable ending</th><th>Nonmodern at year end after actionable ending</th><th>Current users 61+ months</th></tr></thead><tbody>')
for r in duration_bridge:
    parts.append('<tr>'+td(h(r['method']))+td(integer(r['current_users_2025']),'num')+td(integer(r['projected_actionable_original_method_endings']),'num')+td(integer(r['projected_direct_modern_switchers']),'num')+td(integer(r['projected_modern_at_month12_after_actionable']),'num')+td(integer(r['projected_nonmodern_at_month12_after_actionable']),'num')+td(f(r['current_users_61plus_share_pct'])+'%','num')+'</tr>')
parts.append('<tr>'+td('EC')+td(integer(ec_2025),'num')+''.join(td('Not estimated') for _ in range(4))+td('—')+'</tr>')
parts.append('<tr><th>All modern</th>'+td(integer(ec_2025+sum(float(r['current_users_2025']) for r in duration_bridge)),'num')+''.join(td(integer(sum(float(r[k]) for r in duration_bridge)),'num') for k in ['projected_actionable_original_method_endings','projected_direct_modern_switchers','projected_modern_at_month12_after_actionable','projected_nonmodern_at_month12_after_actionable'])+td('—')+'</tr></tbody></table></div>')
parts.append('<p class="small">“Modern at year end” includes both direct switches and later restarts. “Nonmodern at year end” includes no method, traditional methods and pregnancy/birth/termination calendar states. These two statuses partition projected actionable original-method endings. Neither status is a causal estimate of how many women an intervention could retain.</p>')
parts.append('<h3>Cause-specific duration-aware endpoint</h3><div class="tablewrap"><table><thead><tr><th>Current method</th><th>Actionable cause of original-method ending</th><th>Endings in next 12 months</th><th>Direct modern switches</th><th>Nonmodern at year end</th></tr></thead><tbody>')
for r in duration_bridge_cause:
    parts.append('<tr>'+td(h(r['method']))+td(h(r['reason']))+td(integer(r['projected_actionable_original_method_endings']),'num')+td(integer(r['projected_direct_modern_switchers']),'num')+td(integer(r['projected_nonmodern_at_month12']),'num')+'</tr>')
parts.append('</tbody></table></div>')
parts.append('<h3>Illustrative mCPR scale, after duration and year-end modern use</h3><div class="tablewrap"><table><thead><tr><th>2026 scenario</th><th>Usual mCPR</th><th>Women nonmodern at year end after an actionable ending</th><th>Mechanical ceiling gain</th><th>mCPR under that ceiling</th></tr></thead><tbody>')
for r in duration_scenarios:
    parts.append('<tr>'+td(h(r['scenario']))+td(f(r['mcpr_2026_pct'],2)+'%','num')+td(integer(r['duration_aware_nonmodern_at_month12']),'num')+td(f(r['descriptive_nonmodern_at_month12_pp'],2)+' pp','num')+td(f(r['illustrative_mcpr_if_all_endpoint_users_retained'],2)+'%','num')+'</tr>')
parts.append('</tbody></table></div><div class="note goldnote"><b>Critical limit:</b> No current user with 61+ completed months has a matched historical calendar landmark with a full additional year observed. The displayed scenario assigns them the observed 37–60-month risk. They represent 10.9% of injectable users, 13.7% of implant users, 14.4% of pill users, 36.1% of IUD users and 14.2% of other-modern users. IUD estimates are especially fragile. Using only the observed 37–48 or 49–60-month risk for this unsupported group gives '+f(min(float(r['illustrative_pp']) for r in duration_sensitivity),2)+' to '+f(max(float(r['illustrative_pp']) for r in duration_sensitivity),2)+' pp; this narrow range does not include sampling uncertainty.</div>')
parts.append('<p class="small">These are descriptive transported-calendar scenarios, not causal forecasts. They assume the 2024 current-user duration distribution applies to projected 2025 users, that historical transitions apply in 2025–26, and that avoiding an actionable ending would keep each otherwise nonmodern woman using a modern method at year end. A program effect requires evidence on intervention uptake and effectiveness. The denominator for pp is projected 2026 women aged 15–49 (59,000,784). Repeated historical landmarks from one woman are not independent observations; these planning tables have no inferential confidence intervals.</p></section>')
parts.append('<footer class="small" style="padding-top:24px">Reproducible source: Code/01–17 in this Nigeria project. Survey weights v005, PSU v021, strata v022. Nigeria DHS 2024 IR calendar, official report Tables 7.12 and 7.13, UN WPP 2024 and Track20/FP2030 2025. Updated 22 October 2026.</footer></main></body></html>')
# Move complete sections into the Ethiopia deck's narrative order while
# keeping the calculations above independent and traceable to their tables.
document=''.join(parts)
matches=list(re.finditer(r'<section id="([^"]+)">.*?</section>',document,re.S))
blocks={match.group(1):match.group(0) for match in matches}
assert len(blocks)==len(matches)==len(story_order)-1
begin=document[:matches[0].start()]
end=document[matches[-1].end():]
document=begin+''.join(blocks[k] for k in story_order if k!='overview')+end
OUT.write_text(document,encoding='utf-8')
print(OUT.name)
)----------------------"

REPORT_FILES[["src/report/19_add_cause_mcpr_ceiling_html.py"]] <- r"----------------------("""Append the cause-specific gross mCPR ceiling table to a country HTML report.

The user counts come from the existing method-by-cause projection. The same
projected 2026 women 15–49 denominator is used in every reason column.
Running this script again replaces its own section without duplicating it.
"""

import argparse
import csv
import html
from pathlib import Path
import os
import re


REASONS = [
    ("Method failure", "Method<br>failure"),
    ("Wanted more effective method", "Wanted more<br>effective method"),
    ("Changes in menstrual bleeding", "Bleeding<br>changes"),
    ("Other side effects/health", "Other side effects<br>/ health"),
    ("Access/cost/convenience", "Access / cost<br>/ convenience"),
]
METHODS = ["Injectables", "Implants", "Pill", "IUD", "Other modern"]
MARKER_START = "<!-- BEGIN ACTIONABLE CAUSE MCPR CEILING -->"
MARKER_END = "<!-- END ACTIONABLE CAUSE MCPR CEILING -->"


def build(country: str, root: Path) -> None:
    nigeria = country == "nigeria"
    output = root / "output"
    report = output / ("Nigeria_discontinuation_analysis.html" if nigeria else "Ethiopia_discontinuation_analysis.html")
    data = output / "Supporting_data" / (
        "nigeria_current_users_actionable_by_cause.csv" if nigeria else "current_users_actionable_by_cause.csv"
    )
    outcome_year = 2025 if nigeria else 2026
    if nigeria:
        with (output/'Supporting_data/nigeria_wpp2024_wra_2024_2026.csv').open() as stream:
            wra = next(float(r['women_15_49']) for r in csv.DictReader(stream) if int(r['year'])==outcome_year)
    else:
        wra = 35_016_171
    country_name = "Nigeria" if nigeria else "Ethiopia"
    with data.open(newline="") as f:
        source = list(csv.DictReader(f))
    values = {}
    for row in source:
        method = row["method"]
        if method.startswith("All modern"):
            continue  # Ethiopia CSV also contains pre-aggregated totals.
        if method == "Other modern methods":
            method = "Other modern"
        reason = row["reason" if nigeria else "actionable_cause"]
        values[(method, reason)] = float(row["illustrative_users" if nigeria else "illustrative_method_endings"])
    for method in METHODS:
        for reason, _ in REASONS:
            assert (method, reason) in values, (country, method, reason)
    fmt = lambda x: f"{round(x):,}"
    totals = [sum(values[(method, reason)] for method in METHODS) for reason, _ in REASONS]
    grand_total = sum(totals)
    projection = output/'Supporting_data'/('nigeria_current_users_by_method_and_actionable_projection.csv' if nigeria else 'current_users_actionable_12_month_projection.csv')
    with projection.open() as stream:
        expected = sum(float(r['illustrative_original_method_endings' if nigeria else 'illustrative_actionable_method_endings']) for r in csv.DictReader(stream) if r['method'].replace('Other modern methods','Other modern') in METHODS)
    assert abs(grand_total-expected)<1e-4

    def tr(label: str, cells: list[str], css: str = "") -> str:
        return f'<tr class="{css}"><th scope="row">{html.escape(label)}</th>' + "".join(f"<td>{cell}</td>" for cell in cells) + "</tr>"

    body_rows = []
    for method in METHODS:
        nums = [values[(method, reason)] for reason, _ in REASONS]
        body_rows.append(tr(method, [fmt(x) for x in nums] + [f"<strong>{fmt(sum(nums))}</strong>"]))
    body_rows.append(tr("Estimated original-method endings", [f"<strong>{fmt(x)}</strong>" for x in totals] + [f"<strong>{fmt(grand_total)}</strong>"], "cause-total"))
    body_rows.append(tr(f"{outcome_year} women aged 15–49", [fmt(wra)] * 6, "cause-wra"))
    body_rows.append(tr("Maximum illustrative mCPR increase", [f"<strong>{x / wra * 100:.2f} pp</strong>" for x in totals] + [f"<strong>{grand_total / wra * 100:.2f} pp</strong>"], "cause-pp"))
    headers = "".join(f'<th scope="col">{label}</th>' for _, label in REASONS)
    section = f"""{MARKER_START}
<section id="actionable-cause-mcpr-ceiling" class="cause-mcpr-ceiling">
<style>
.cause-mcpr-ceiling .cause-table-wrap{{overflow-x:auto;border:1px solid #d9e3e8;border-radius:6px;margin:20px 0 12px}}
.cause-mcpr-ceiling table{{width:100%;border-collapse:collapse;font:14px/1.35 Arial,sans-serif;font-variant-numeric:tabular-nums;min-width:950px}}
.cause-mcpr-ceiling th,.cause-mcpr-ceiling td{{padding:13px 11px;border-bottom:1px solid #dbe3e7;text-align:right;white-space:nowrap}}
.cause-mcpr-ceiling thead th{{background:#1a4059;color:#fff;font-weight:700;white-space:normal;vertical-align:bottom}}
.cause-mcpr-ceiling thead th:first-child,.cause-mcpr-ceiling tbody th{{text-align:left;min-width:195px}}
.cause-mcpr-ceiling tbody tr:nth-child(even):not(.cause-total):not(.cause-wra):not(.cause-pp){{background:#f3f6f7}}
.cause-mcpr-ceiling tbody tr.cause-total{{background:#e5eff2;color:#173d55;font-weight:700}}
.cause-mcpr-ceiling tbody tr.cause-wra{{background:#fff5e1;color:#243542}}
.cause-mcpr-ceiling tbody tr.cause-pp{{background:#dbecee;color:#103f58;font-weight:700;border-top:2px solid #1a4059}}
.cause-mcpr-ceiling tbody tr.cause-total th,.cause-mcpr-ceiling tbody tr.cause-wra th,.cause-mcpr-ceiling tbody tr.cause-pp th{{background:inherit}}
</style>
<div class="eyebrow">Planning illustration</div>
<h2>Potential mCPR gain by actionable discontinuation cause</h2>
<p class="intro">The table apportions the existing estimated original-method endings among 2025 current users across five potentially actionable causes. Each column's final row divides its estimated endings by {fmt(wra)} projected women aged 15–49 in {country_name} in {outcome_year}. The all-causes column adds the five mutually exclusive causes.</p>
<div class="cause-table-wrap" role="region" aria-label="Potential {outcome_year} mCPR gain by method and actionable cause" tabindex="0"><table>
<thead><tr><th scope="col">Method / measure</th>{headers}<th scope="col">All actionable<br>causes</th></tr></thead>
<tbody>{''.join(body_rows)}</tbody></table></div>
<p class="note"><strong>Interpretation:</strong> These percentage-point values are gross upper bounds, not expected program effects. An ending of the original method does not necessarily reduce modern contraceptive prevalence: a woman may switch to another modern method or restart before year-end. The cause-specific counts apply first-year, 12-month life-table probabilities to current users without adjusting for how long they have already used the method. Emergency contraception has current users in mCPR but no ongoing-use discontinuation estimate and is not included in the table's endings.</p>
<p class="note"><strong>Source:</strong> Existing country method-by-cause projection in <a href="Supporting_data/{data.name}">{html.escape(data.name)}</a>; 2026 women aged 15–49 denominator from the preceding population section.</p>
</section>
{MARKER_END}"""
    text = report.read_text()
    if MARKER_START in text:
        text = re.sub(re.escape(MARKER_START) + r".*?" + re.escape(MARKER_END), section, text, flags=re.S)
    else:
        text = text.replace("<footer", section + "\n<footer", 1)
    if '#actionable-cause-mcpr-ceiling' not in text.split('</aside>')[0]:
        link = '<a href="#actionable-cause-mcpr-ceiling">mCPR gain by actionable cause</a>' if nigeria else '<div class="toc-group"><a class="toc-major" href="#actionable-cause-mcpr-ceiling" title="Potential mCPR gain by actionable cause">Potential mCPR gain by actionable cause</a></div>'
        if nigeria:
            text = text.replace("</aside>", link + "</aside>", 1)
        else:
            text = text.replace("</nav></aside>", link + "</nav></aside>", 1)
    report.write_text(text)
    print(report, f"{round(grand_total):,} endings", f"{grand_total / wra * 100:.2f} pp")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("country", nargs="?", choices=["nigeria", "ethiopia"], default="nigeria")
    parser.add_argument("root", nargs="?", type=Path, default=Path(os.environ["NIGERIA_PROJECT_ROOT"]))
    args = parser.parse_args()
    build(args.country, args.root)
)----------------------"

REPORT_FILES[["src/report/27_add_method_zone_models_to_html.py"]] <- r"----------------------(#!/usr/bin/env python3
"""Add reproducible injectable/implant zone model results to Nigeria HTML.

The estimates are read from script 26 CSVs. Existing sections and numerical
tables are preserved; this insertion makes the within-method tests visible
alongside the all-modern six-zone regression analysis.
"""
import csv
import html
import re
from pathlib import Path
import os

ROOT = Path(os.environ["NIGERIA_PROJECT_ROOT"])
SUP = ROOT / 'output/Supporting_data'
PAGE = ROOT / 'output/Nigeria_discontinuation_analysis.html'
def read(name):
    with (SUP / name).open(newline='') as f:
        return list(csv.DictReader(f))
points = read('nigeria_actionable_injectable_implant_zone_probabilities.csv')
pairs = read('nigeria_actionable_injectable_implant_zone_pairwise.csv')
global_tests = read('nigeria_actionable_injectable_implant_zone_global.csv')
assert len(points) == 12 and len(pairs) == 60 and len(global_tests) == 4
zones = ['North West','North East','North Central','South East','South South','South West']
methods = ['Injectables','Implants']
for method in methods:
    assert {r['zone'] for r in points if r['method']==method} == set(zones)

def pct(x): return f'{float(x):.1f}'
def pval(x):
    v=float(x)
    return '&lt;0.001' if v<.001 else f'{v:.3f}'
def esc(x): return html.escape(str(x))

def chart(method):
    rows = [next(r for r in points if r['method']==method and r['zone']==z)
            for z in zones]
    width, height, x0, x1 = 920, 332, 250, 790
    max_rate = max(float(r[k]) for r in rows for k in
                   ['unadjusted_high','adjusted_high'])
    high = 45 if max_rate<=45 else 60
    X=lambda v: x0+(float(v)/high)*(x1-x0)
    svg=[f'<svg viewBox="0 0 {width} {height}" '
         'style="width:100%;max-width:920px;height:auto;display:block" role="img" '
         f'aria-label="{esc(method)}: observed and composition-adjusted '
         '12-month actionable discontinuation by zone">']
    for t in range(0,high+1,10):
        x=X(t)
        svg.append(f'<line x1="{x:.1f}" y1="21" x2="{x:.1f}" y2="284" '
                   'stroke="#E4EAF0"/>')
        svg.append(f'<text x="{x:.1f}" y="309" text-anchor="middle" '
                   f'font-size="14" fill="#415A69">{t}%</text>')
    for i,r in enumerate(rows):
        y=42+i*42
        svg.append(f'<text x="10" y="{y+7}" font-size="16" '
                   f'fill="#153F5B">{esc(r["zone"])}</text>')
        if i%2==0:
            svg.append(f'<line x1="{x0}" y1="{y+21}" x2="{x1}" '
                       f'y2="{y+21}" stroke="#F0F3F6"/>')
        for prefix,off,color in [('unadjusted',-6,'#DA9A25'),
                                 ('adjusted',6,'#153F5B')]:
            yy=y+off
            lo,hi,v=(float(r[prefix+'_'+q]) for q in
                     ('low','high','pct'))
            svg.append(f'<line x1="{X(lo):.1f}" y1="{yy}" '
                       f'x2="{X(hi):.1f}" y2="{yy}" '
                       f'stroke="{color}" stroke-width="2.4"/>')
            for x in (X(lo),X(hi)):
                svg.append(f'<line x1="{x:.1f}" y1="{yy-4}" '
                           f'x2="{x:.1f}" y2="{yy+4}" '
                           f'stroke="{color}" stroke-width="2"/>')
            svg.append(f'<circle cx="{X(v):.1f}" cy="{yy}" r="5" '
                       f'fill="{color}"/>')
            svg.append(f'<text x="{X(v)+9:.1f}" y="{yy+4}" '
                       f'font-size="12" fill="{color}">{v:.1f}</text>')
    svg.append('</svg>')
    return ''.join(svg)

parts=['<section id="method-zone-regressions" class="analysis-section">',
       '<div class="eyebrow">Subnational regression</div>',
       '<h2>Within-method comparisons across Nigeria’s six zones</h2>',
       '<p class="intro">Injectables and implants are analyzed separately. '
       'Each observed rate is the competing-risk life-table probability that '
       'an eligible episode of that method ends for a potentially actionable '
       'cause within 12 months. The fully adjusted model uses episode-month '
       'data and controls for month since method start, age and parity at '
       'start, marital status, education, wealth and residence measured at '
       'interview, and start year. '
       'Other method endings are competing events; late-entry episodes '
       'contribute only observed months. Adjusted predictions use the same '
       'national observed-start covariate composition within each method to '
       'make zone contrasts comparable.</p>',
       '<p class="small"><span style="color:#DA9A25">●</span> Observed '
       'and <span style="color:#153F5B">●</span> fully adjusted; '
       'horizontal lines are 95% stratified-PSU bootstrap intervals. '
       'This is an association analysis, not a causal estimate.</p>']
for method in methods:
    rows=[r for r in points if r['method']==method]
    g=next(r for r in global_tests if r['method']==method and
           r['stage']=='Fully adjusted')
    flagged=[r['zone'] for r in rows if r['precision_flag']]
    parts += [f'<h3>{esc(method)}: observed and fully adjusted risk</h3>',
              chart(method),
              f'<p class="small">Full-model omnibus test across six zones: '
              f'p = {pval(g["p_value"])}. '
              + (f'Exploratory precision flag (&lt;30 actionable endings): '
                 f'{esc(", ".join(flagged))}. ' if flagged else '')
              + 'The same-method comparison has no method-mix stage: every '
              'episode in this panel started the named method.</p>']
    selected=[r for r in pairs if r['method']==method and
              r['stage']=='Fully adjusted' and r['significant_5pct']=='TRUE']
    if selected:
        parts.append('<p><b>Fully adjusted zone pairs remaining distinguishable '
                     'after Holm correction:</b></p><div class="tablewrap"><table>'
                     '<thead><tr><th>Zones</th><th>Difference (pp)</th>'
                     '<th>95% bootstrap CI (pp)</th><th>Holm p</th></tr></thead><tbody>')
        for r in sorted(selected,key=lambda x:float(x['holm_p_within_method'])):
            parts.append('<tr><td>'+esc(r['zone_a'])+' vs '+esc(r['zone_b'])+
                         '</td><td class="num">'+f'{float(r["difference_pp"]):+.1f}'+
                         '</td><td class="num">'+
                         f'{float(r["ci_low_pp"]):+.1f} to '
                         f'{float(r["ci_high_pp"]):+.1f}'+
                         '</td><td class="num">'+pval(r['holm_p_within_method'])+
                         '</td></tr>')
        parts.append('</tbody></table></div>')
    else:
        parts.append('<p class="small">No fully adjusted zone pair remains '
                     'distinguishable at 5% after Holm correction of the '
                     '15 comparisons for this method.</p>')
    if method == 'Implants':
        across=sum(r['method']=='Implants' and
                   r['stage']=='Fully adjusted' and
                   float(r['holm_p_across_methods'])<.05 for r in pairs)
        parts.append(f'<p class="small">If the family is widened to all 30 '
                     f'adjusted injectable and implant zone pairs, {across} '
                     'implant contrasts remain below 5% after Holm correction.'
                     '</p>')
parts.append('<details><summary>Full pairwise results and testing details</summary>'
             '<p class="small">Two-sided Wald tests use standard errors from '
             'stratified PSU bootstrap contrasts. Holm correction is applied '
             'to all 15 zone pairs within each method and stage; the saved '
             'supporting CSV also includes a 30-comparison correction across '
             'both methods. A nonsignificant result does not establish equal '
             'risks. The method-specific models and bootstrap draws are '
             'reproduced by Code/26_nigeria_actionable_method_zone_models.R.'
             '</p><div class="tablewrap"><table><thead><tr><th>Method</th>'
             '<th>Stage</th><th>Zones</th><th>Difference (pp)</th>'
             '<th>Holm p within method</th></tr></thead><tbody>')
for r in pairs:
    parts.append('<tr><td>'+esc(r['method'])+'</td><td>'+esc(r['stage'])+
                 '</td><td>'+esc(r['zone_a'])+' vs '+esc(r['zone_b'])+
                 '</td><td class="num">'+f'{float(r["difference_pp"]):+.1f}'+
                 '</td><td class="num">'+pval(r['holm_p_within_method'])+
                 '</td></tr>')
parts.append('</tbody></table></div></details></section>')
section=''.join(parts)
page=PAGE.read_text(encoding='utf-8')
page=re.sub(r'<section id="method-zone-regressions".*?</section>',
            '',page,flags=re.S)
needle='<section id="regional-analyses"'
assert page.count(needle)==1
page=page.replace(needle,section+needle,1)
page=page.replace('Reproducible source: Code/01–17 in this Nigeria project.',
                  'Reproducible source: Nigeria Code/01–27, including the '
                  'method-specific zone models in scripts 26–27.')
nav='<a href="#method-zone-regressions">Injectable and implant zone models</a>'
if nav not in page:
    anchor='<a href="#regional-analyses">Regional analyses summary</a>'
    assert page.count(anchor)==1
    page=page.replace(anchor,nav+anchor,1)
PAGE.write_text(page,encoding='utf-8')
print(PAGE)
)----------------------"

REPORT_FILES[["src/report/28_add_method_scenario_tables.py"]] <- r"----------------------(#!/usr/bin/env python3
"""Reproduce Ethiopia-style method-level 2026 mCPR scenarios for Nigeria.

Current-method shares come from Nigeria DHS 2024 IR data. The three 2026
all-women mCPR and WRA scenarios are in the existing supporting CSV. EC remains
in mCPR but is assigned no ongoing-method discontinuation risk. This is an
illustrative gross original-method retention ceiling, not a forecast.
"""
import csv
import html
from pathlib import Path
import os

ROOT = Path(os.environ["NIGERIA_PROJECT_ROOT"])
SUP = ROOT / 'output/Supporting_data'
PAGE = ROOT / 'output/Nigeria_discontinuation_analysis.html'

def read(name):
    with (SUP / name).open(newline='') as f:
        return list(csv.DictReader(f))

scenarios = read('nigeria_2026_mcpr_scenarios.csv')
methods = read('nigeria_current_users_by_method_and_actionable_projection.csv')
assert len(scenarios) == 3 and len(methods) == 7
assert abs(sum(float(m['share_current_modern_pct']) for m in methods)-100) < 1e-8
gross = sum(float(m['illustrative_original_method_endings']) for m in methods)
assert all(abs(float(s['illustrative_gross_endings'])-gross) < .01 for s in scenarios)

def fmt(x): return f'{x:,.0f}'
def pct(x): return f'{x:.2f}%'

parts = ['<section id="method-level-mcpr-scenarios" class="analysis-section">',
         '<div class="eyebrow">Current-user planning</div>',
         '<h2>2026 mCPR scenarios by current method</h2>',
         '<p>The 2026 status-quo total comes from each all-women mCPR scenario '
         'multiplied by projected 2026 women aged 15–49. We allocate that '
         'total across methods using Nigeria DHS 2024 current-user shares. '
         'For the illustrative retention ceiling, we add the projected '
         '2025 current users whose original method would end within 12 months '
         'for a potentially actionable cause. This assumes every such ending '
         'is prevented and each woman still uses her original modern method '
         'at year end. It does not account for time already spent on the method, '
         'switching or re-entry, and it must not be interpreted as a forecast '
         'of net mCPR gain. EC remains in current mCPR but has no continuing-use '
         'discontinuation estimate.</p>']
for i,s in enumerate(scenarios, 1):
    wra=float(s['wra_2026']); usual=float(s['usual_users_2026'])
    parts.append(f'<h3>{i}. {html.escape(s["scenario"])}</h3>')
    parts.append('<div class="tablewrap"><table><thead><tr><th>Method</th>'
                 '<th>2025 current users</th><th>2026 usual users</th>'
                 '<th>2026 usual mCPR contribution</th>'
                 '<th>Illustrative endings prevented</th>'
                 '<th>2026 users if prevented</th>'
                 '<th>2026 mCPR contribution if prevented</th></tr></thead><tbody>')
    total_2025=total_usual=total_added=total_retained=0
    for m in methods:
        share=float(m['share_current_modern_pct'])/100
        u=usual*share; add=float(m['illustrative_original_method_endings'])
        retained=u+add
        total_2025 += float(m['current_users_2025'])
        total_usual += u; total_added += add; total_retained += retained
        parts.append('<tr><th>'+html.escape(m['method'])+'</th><td class="num">'
                     +fmt(float(m['current_users_2025']))+'</td><td class="num">'
                     +fmt(u)+'</td><td class="num">'+pct(100*u/wra)
                     +'</td><td class="num">'+fmt(add)+'</td><td class="num">'
                     +fmt(retained)+'</td><td class="num">'+pct(100*retained/wra)
                     +'</td></tr>')
    assert abs(total_usual-usual)<.01
    assert abs(total_retained-float(s['no_gross_endings_users_2026']))<.01
    parts.append('<tr class="total"><th>All modern methods</th><td class="num">'
                 +fmt(total_2025)+'</td><td class="num">'+fmt(total_usual)
                 +'</td><td class="num">'+pct(100*total_usual/wra)
                 +'</td><td class="num">'+fmt(total_added)
                 +'</td><td class="num">'+fmt(total_retained)
                 +'</td><td class="num">'+pct(100*total_retained/wra)
                 +'</td></tr></tbody></table></div>')
    parts.append('<p class="small">Projected 2026 women aged 15–49: '
                 +fmt(wra)+'. The illustrative gross ceiling exceeds the '
                 'usual 2026 mCPR by '+f'{100*total_added/wra:.2f}'
                 +' percentage points.</p>')
parts.append('</section>')
section=''.join(parts)
source=PAGE.read_text()
start=source.find('<section id="method-level-mcpr-scenarios"')
if start>=0:
    end=source.find('</section>',start)+len('</section>')
    source=source[:start]+source[end:]
anchor='<section id="switch-bridge"'
assert anchor in source
source=source.replace(anchor,section+anchor,1)
toc='<a href="#method-level-mcpr-scenarios">2026 mCPR by method</a>'
if toc not in source:
    old='<a href="#switch-bridge">'
    assert old in source
    source=source.replace(old,toc+old,1)
PAGE.write_text(source)
print(PAGE)
)----------------------"

REPORT_FILES[["src/report/30_add_zone_method_mix_decomposition_html.py"]] <- r"----------------------(#!/usr/bin/env python3
"""Add the reproducible six-zone method-mix diagnostic to Nigeria HTML."""
import csv
import html
from pathlib import Path
import os

root=Path(os.environ["NIGERIA_PROJECT_ROOT"])
support=root/'output/Supporting_data'
page=root/'output/Nigeria_discontinuation_analysis.html'
with (support/'nigeria_actionable_zone_method_mix_decomposition.csv').open() as f:
    data=list(csv.DictReader(f))
with (support/'nigeria_actionable_zone_method_mix_cells.csv').open() as f:
    cells=list(csv.DictReader(f))
assert len(data)==45 and len(cells)==24
by={(r['pair'],r['component']):r for r in data}
pairs=list(dict.fromkeys(r['pair'] for r in data))
def n(x): return f'{float(x):+.1f}'
def interval(r): return f'{n(r["ci_low_pp"])} to {n(r["ci_high_pp"])}'
parts=['<section id="regional-actionable-method-mix-decomposition" class="analysis-section">',
 '<div class="eyebrow">Subnational diagnostic</div>',
 '<h2>How much of each zone gap reflects method mix?</h2>',
 '<p>For each zone and method, we estimate the survey-weighted share of eligible modern-method episodes and the 12-month competing-risk probability of an ending for a potentially actionable cause. We pool IUD with other modern methods because several separate cells are sparse. For each pair, a symmetric decomposition divides the constructed gap into (1) the difference in episode method shares, averaged over the two zones’ method-specific risks, and (2) the difference in within-method risks, averaged over their method shares. These components add exactly to the constructed gap. This is a descriptive accounting identity, not a causal estimate. The constructed gap can differ from the directly pooled all-modern life table because the method-specific cumulative incidences are combined using episode shares. Confidence intervals use 500 resamples of survey clusters within strata.</p>',
 '<p>For North East versus South East, the constructed gap is <b>+19.3 percentage points</b>. Different method shares account for <b>+3.5 points</b>; differences within methods account for <b>+15.8 points</b>. Sparse method-by-zone cells, especially South East pill and injectable endings, warrant caution.</p>',
 '<div class="tablewrap"><table><thead><tr><th>Zone contrast</th><th>Constructed gap (pp)</th><th>Method mix (pp)</th><th>Within-method risk (pp)</th><th>95% CI for mix</th><th>95% CI for within</th></tr></thead><tbody>']
for pair in pairs:
    gap=by[pair,'gap']; mix=by[pair,'mix']; within=by[pair,'within']
    assert abs(float(gap['estimate_pp'])-float(mix['estimate_pp'])-float(within['estimate_pp']))<1e-7
    parts.append('<tr><th>'+html.escape(pair)+'</th><td class="num">'+n(gap['estimate_pp'])+
      '</td><td class="num">'+n(mix['estimate_pp'])+'</td><td class="num">'+
      n(within['estimate_pp'])+'</td><td class="num">'+interval(mix)+
      '</td><td class="num">'+interval(within)+'</td></tr>')
parts.append('</tbody></table></div><p class="small">Positive values mean the first zone has higher constructed actionable discontinuation than the second. Episode method shares are not the share of observed new starts. This table is a diagnostic for targeting further investigation; the adjusted model and design-based pairwise tests elsewhere in this report address inferential comparisons.</p></section>')
section=''.join(parts)
source=page.read_text()
start=source.find('<section id="regional-actionable-method-mix-decomposition"')
if start>=0:
    end=source.find('</section>',start)+len('</section>')
    source=source[:start]+source[end:]
anchor='<section id="regional-analyses"'
assert anchor in source
source=source.replace(anchor,section+anchor,1)
toc='<a href="#regional-actionable-method-mix-decomposition">Method-mix decomposition</a>'
if toc not in source:
    old='<a href="#regional-analyses">'
    assert old in source
    source=source.replace(old,toc+old,1)
page.write_text(source)
print(page)
)----------------------"

REPORT_FILES[["src/report/36_add_alluvial_pathways_html.py"]] <- r"----------------------(#!/usr/bin/env python3
"""Insert Nigeria episode and current-user pathway sections into working HTML."""
import csv
import html
from pathlib import Path
import os

root=Path(os.environ["NIGERIA_PROJECT_ROOT"])
support=root/'output/Supporting_data';page=root/'output/Nigeria_discontinuation_analysis.html'
def read(name):
    with (support/name).open(newline='') as f:return list(csv.DictReader(f))
summary=read('nigeria_standardized_current_user_pathway_summary.csv')
flows=read('nigeria_injectable_reason_destination_flows.csv')
timing=read('nigeria_injectable_reason_timing_destination.csv')
historical=read('nigeria_current_user_pathway_flows.csv')
stock={r['outcome']:float(r['pct']) for r in summary}
assert abs(sum(stock.values())-100)<1e-8
assert abs(sum(float(r['pct']) for r in flows)-100)<1e-8
assert abs(sum(float(r['pct']) for r in historical)-100)<1e-8
reason_order=['Method failure','Wanted more effective method',
 'Changes in menstrual bleeding','Other side effects/health','Access/cost/convenience']
dest_order=['Different modern method','Same modern method','No method recorded',
 'Pregnancy, birth or termination','Traditional/other method','Other/unknown']

def table(head,rows):
    return ('<div class="tablewrap"><table><thead><tr>'+''.join('<th>'+html.escape(x)+'</th>' for x in head)+
      '</tr></thead><tbody>'+''.join('<tr>'+''.join('<td>'+html.escape(str(x))+'</td>' for x in row)+'</tr>' for row in rows)+
      '</tbody></table></div>')
def img(name,alt):
    return '<figure style="margin:1.2rem 0"><img src="assets/'+name+'" alt="'+html.escape(alt)+'" style="width:100%;height:auto"></figure>'
actions=[
 ('Early injectable endings','Actionable injectable risk reaches 10.8% by month 3 and 29.6% by month 12.','Prioritize early follow-up and easy resupply.'),
 ('Bleeding and other side effects','These reasons together account for a large share of actionable injectable endings.','Offer anticipatory counseling, treatment and same-visit method alternatives.'),
 ('No method one month later','80.6% of the observed injectable actionable endings with follow-up had no method recorded one month later.','Make immediate modern switching and re-entry services accessible.'),
]
section1=('''<section id="action-pathways" class="analysis-section">
<div class="eyebrow">Post-discontinuation pathways</div><h2>From injectable endings to program action</h2>
<p>The first alluvial follows observed first-year injectable episodes that ended for a potentially actionable reason and had one calendar month of follow-up. Its denominator is discontinuation events, not all injectable episodes. The second alluvial follows one historical modern-method user per woman from 15 months before interview through the next 12 observed calendar months. It therefore uses women, not episodes, as its denominator. Direct modern switching without a qualifying gap remains continuous modern use; restarting after a gap is re-entry.</p>'''+
img('nigeria_injectable_reason_destination_alluvial.png','Actionable injectable ending reason connected to method status one month later')+
table(['Program signal','Nigeria DHS 2024 finding','Potential response'],actions)+
img('nigeria_current_user_pathway_3_12_alluvial.png','Historical current modern method users linked to month 3 and month 12 states')+
'''<p class="small">The historical pathway is a descriptive prototype. It does not predict the actual 2025–26 cohort without a transportability assumption. EC is included because it is reported as current modern use in the DHS, but it is not treated as an ongoing method in original-method discontinuation life tables.</p>
<p class="small"><a href="Supporting_data/nigeria_injectable_reason_destination_flows.csv">Injectable reason-to-destination flow data</a> · <a href="Supporting_data/nigeria_injectable_reason_timing_destination.csv">Reason, episode duration and destination data</a> · <a href="Supporting_data/nigeria_current_user_pathway_flows.csv">Historical pathway flows</a> · <a href="../Code/34_nigeria_historical_current_user_pathways.R">Historical pathway code</a> · <a href="../Code/35_nigeria_alluvial_figures.R">Figure code</a></p></section>''')
rows=[]
for name in ['No gross exit: baseline method','No gross exit: modern switch',
             'Gross exit: re-entered by month 12','Gross exit: net absent at month 12']:
    rows.append((name,f'{stock[name]:.1f}%'))
section2=('''<section id="standardized-current-users" class="analysis-section">
<div class="eyebrow">Current-user standardization</div><h2>Expected pathway among current modern users</h2>
<p>The following illustration estimates the 12-month pathway for the interview-date current-user stock. Historical outcome probabilities are calculated within four method groups and five completed-duration groups, then averaged using the DHS-weighted method-duration distribution of current users. The historical follow-up contains 3,747 women, and the current-stock standardization uses 5,357 DHS respondents using a modern method: reversible-method users with known duration, plus permanent-method users who remain in the baseline-method group. These are weighted percentages per 100 current users; they are not 12-month original-method discontinuation rates.</p>'''+
img('nigeria_standardized_current_user_stock_alluvial.png','Standardized current user stock to gross modern-use exit and month 12 outcome')+
table(['12-month pathway','Percent of current modern users'],rows)+
'''<p class="small">A gross exit is any month outside modern use. Continuous modern-to-modern switching remains in modern use. Re-entry is modern use at month 12 after an earlier exit. Net absence combines no modern method and pregnancy-related calendar states at month 12. This descriptive transport from past calendar users assumes historical method-duration risks apply to current users; it does not estimate the causal effect of preventing a particular reason for discontinuation. EC is grouped with other modern methods for mCPR consistency, although it is a one-time method.</p>
<p class="small"><a href="Supporting_data/nigeria_standardized_current_user_pathway_summary.csv">Standardized outcomes</a> · <a href="Supporting_data/nigeria_current_user_method_duration_distribution.csv">Current-user distribution</a> · <a href="Supporting_data/nigeria_historical_method_duration_pathway_probabilities.csv">Historical conditional probabilities</a> · <a href="Supporting_data/nigeria_standardized_current_user_pathway_contributions.csv">Standardization contributions</a></p></section>''')

source=page.read_text()
for anchor in ('action-pathways','standardized-current-users'):
    start=source.find(f'<section id="{anchor}"')
    if start>=0:
        end=source.find('</section>',start)+len('</section>')
        source=source[:start]+source[end:]
anchor='<section id="population"'
assert anchor in source
source=source.replace(anchor,section1+section2+anchor,1)
for id,label in [('action-pathways','Actionable pathways'),
                 ('standardized-current-users','Current-user pathway')]:
    toc=f'<a href="#{id}">{label}</a>'
    if toc not in source:
        old='<a href="#population">'
        assert old in source
        source=source.replace(old,toc+old,1)
page.write_text(source)
print(page)
)----------------------"

REPORT_FILES[["src/report/39_add_selected_exploratory_html.py"]] <- r"----------------------(#!/usr/bin/env python3
"""Add Nigeria counterparts of Ethiopia's selected-reason exploratory tables."""
import csv
import html
from pathlib import Path
import os

root=Path(os.environ["NIGERIA_PROJECT_ROOT"]);out=root/'output';sup=out/'Supporting_data'
page=out/'Nigeria_discontinuation_analysis.html'
def read(name):
    with (sup/name).open(newline='') as f:return list(csv.DictReader(f))
data=read('nigeria_selected_reason_extensions.csv')
other=read('nigeria_other_reason_code_breakdown.csv')
follow=read('nigeria_other_reason_followup.csv')
starts=read('nigeria_zone_all_method_start_mix.csv')
alltime=read('nigeria_modern_all_reason_timepoints.csv')
by={r['scope']:r for r in data}
reason_names=['Method failure','Other fertility-related','Changes in menstrual bleeding',
 'Other side effects/health','Wanted more effective method','Access/cost/convenience',
 'Other recorded reasons']
action_idx=[1,3,4,5,6]
variables=['age_group','parity_group','marital_group','education','wealth','residence']
varlabel={'age_group':'Age at method start','parity_group':'Parity at method start',
 'marital_group':'Marital status','education':'Education','wealth':'Wealth quintile',
 'residence':'Residence'}
zones=['North West','North East','North Central','South East','South South','South West']
methods=['Injectables','Implants','Pill','IUD','Other modern']
def num(x,n=1):return f'{float(x):.{n}f}'
def pct(x,n=1):return num(x,n)+'%'
def safe(x):return html.escape(str(x))
def table(head,rows):
 return ('<div class="tablewrap"><table><thead><tr>'+''.join('<th>'+safe(x)+'</th>' for x in head)+
 '</tr></thead><tbody>'+''.join('<tr>'+''.join('<td>'+safe(x)+'</td>' for x in row)+'</tr>' for row in rows)+
 '</tbody></table></div>')
def reasons(r,indices=range(1,8),top=None):
 v=[(reason_names[j-1],float(r[f'cause_{j}_pct'])) for j in indices]
 total=sum(x[1] for x in v)
 v.sort(key=lambda x:-x[1]);v=v[:top] if top else v
 return '; '.join(f'{name} {100*val/total:.1f}%' for name,val in v) if total else 'Insufficient data'
def heat_cell(v):
 strength=min(.62,.08+float(v)/100*.75)
 # navy tint, black numerals, consistent with presentation palette
 color=f'rgba(21,63,91,{strength:.3f})'
 return f'<td style="background:{color};color:#111;font-weight:400;text-align:center">{float(v):.1f}</td>'
def section(id,title,intro,body):
 return f'<section id="{id}" class="analysis-section"><div class="eyebrow">Selected-reason analysis</div><h2>{safe(title)}</h2><p>{intro}</p>{body}</section>'

labels={9:'Infrequent sex / husband away',11:'Up to God / fatalistic',
 12:'Difficult to get pregnant / menopausal',13:'Marital dissolution / separation',
 96:'Other specified',98:'Do not know',99:'Missing / unknown',0:'Unspecified'}
other_rows=[]
for r in other:
 code=int(float(r['reason_code']))
 other_rows.append((r['group'],labels[code],r['endings_n'],num(r['wt'],1)))
parts=[]
parts.append(section('other-reasons-count-breakdown','What falls under “Other” reasons?',
 'The first-year modern-method episode cohort distinguishes other fertility-related reasons from residual recorded reasons. These counts are among observed first-year endings; they are not life-table probabilities. EC is excluded.',
 table(['Group','Recorded reason','Observed endings','Weighted endings'],other_rows)))
follow_rows=[]
for code in sorted({int(float(r['reason_code'])) for r in follow}):
 for month in (1,12):
  rows=[r for r in follow if int(float(r['reason_code']))==code and int(float(r['month_after_ending']))==month]
  if not rows:continue
  sums={k:sum(float(r['share_within_reason_pct']) for r in rows if r['destination']==k)
        for k in ['No method recorded','Same modern method','Different modern method',
                  'Pregnancy, birth or termination','Traditional/other/unknown']}
  n=sum(int(float(r['endings_n'])) for r in rows)
  follow_rows.append((labels[code],str(month),str(n),*(pct(sums[k]) for k in sums)))
parts.append(section('other-reason-followup','What follows an “Other” ending?',
 'Each row conditions on an observed first-year ending for the named reason and on having the follow-up month recorded. The 1- and 12-month rows can have different denominators. Sparse reasons are descriptive only.',
 table(['Recorded reason','Month after ending','N','No method','Same modern','Different modern','Pregnancy/birth','Traditional/unknown'],follow_rows)))

subrows=[]
for f in variables:
 for r in [x for x in data if x['variable']==f]:
  ci=(f'{num(r["ci_low"])}–{num(r["ci_high"])}%' if r['ci_low'] not in ('','NA') else '—')
  subrows.append((varlabel[f],r['category'],r['eligible_episodes_n'],
                  pct(r['selected_12_month_pct']),ci,reasons(r)))
parts.append(section('selected-reason-descriptive-subgroups',
 'Unadjusted 12-month selected-reason discontinuation by subgroup',
 'Among all eligible modern-method episodes, the event is ending the original method for any recorded reason except wanted pregnancy or partner disapproval. Those two endings remain competing events. Confidence intervals use 300 stratified-PSU bootstrap replicates; demographic variables other than age and parity are measured at interview. Reason shares within each row add to 100% before rounding.',
 table(['Covariate','Category','Eligible episodes','12-month risk','95% CI','Reasons ranked by share'],subrows)))

actrows=[]
for f in variables:
 for r in [x for x in data if x['variable']==f]:
  total=sum(float(r[f'cause_{j}_pct']) for j in action_idx)
  actrows.append((varlabel[f],r['category'],r['selected_endings_n'],
    pct(total),reasons(r,action_idx)))
parts.append(section('method-experience-subgroup-reasons',
 'Method experience and access reasons within subgroups',
 'The five potentially actionable reasons are method failure, changes in menstrual bleeding, other side effects or health, wanting a more effective method, and access/cost/convenience. Their 12-month cumulative incidences use all eligible modern episodes; their shares are normalized within those five reasons and add to 100% in each row. This is descriptive, not an adjusted subgroup contrast.',
 table(['Covariate','Category','Selected endings (all retained reasons)','Actionable 12-month risk','Five actionable reasons ranked by share'],actrows)))

toprows=[]
for method in ['All modern','Injectables','Pill','IUD']:
 for f in variables:
  source=[r for r in data if r['variable']==f] if method=='All modern' else \
    [r for r in data if r['variable']=='method_subgroup' and r['category'].startswith(method+' / '+f+' / ')]
  for r in source:
   cat=r['category'] if method=='All modern' else r['category'].split(' / ',2)[-1]
   total=sum(float(r[f'cause_{j}_pct']) for j in action_idx)
   vals=[(reason_names[j-1],float(r[f'cause_{j}_pct'])) for j in action_idx]
   vals.sort(key=lambda x:-x[1])
   n=int(float(r['selected_endings_n']))
   ranked=[f'{name}: {val:.1f}% of episodes; {100*val/total:.1f}% of actionable risk' for name,val in vals[:3]] if n>=10 and total>0 else ['Withheld: <10 selected endings']
   toprows.append((method,varlabel[f],cat,str(n),*([*ranked]+['—']*(3-len(ranked)))))
parts.append(section('top-three-reasons-by-subgroup-method',
 'Top three actionable reasons by subgroup and method',
 'Rankings use absolute reason-specific 12-month cumulative probability, among eligible episodes of the named method and subgroup. The second percentage in each cell is the reason’s share of the five actionable reasons. Rankings with fewer than 10 selected endings are withheld; 10–29 endings remain tentative. No reason-specific intervals are claimed.',
 table(['Method','Covariate','Category','Selected endings','First','Second','Third'],toprows)))

classrows=[]
for r in [x for x in data if x['variable']=='duration_class']:
  ci=(f'{num(r["ci_low"])}–{num(r["ci_high"])}%' if r['ci_low'] not in ('','NA') else '—')
  classrows.append((r['category'],r['eligible_episodes_n'],r['selected_endings_n'],
                    pct(r['selected_12_month_pct']),ci))
parts.append(section('method-duration-class-discontinuation',
 'Selected-reason risk by method-duration class',
 'Short-acting reversible includes injectables, pills and male condoms; long-acting reversible includes implants and IUDs. The mixed group contains other modern methods and is not a coherent duration class. The same competing-risk definition and all-eligible-episode denominator apply.',
 table(['Method category','Eligible episodes','Selected endings','12-month risk','95% CI'],classrows)))
short=by['duration_class::Short-acting reversible']
shortrows=[]
for j,name in enumerate(reason_names,1):
 shortrows.append((name,pct(short[f'share_{j}_pct']),pct(short[f'cause_{j}_pct'])))
parts.append(section('short-acting-selected-reason-distribution',
 'Why short-acting modern methods ended within 12 months',
 'The weighted shares describe the distribution of reasons among selected first-year discontinuations of injectables, pills and male condoms. Shares sum to 100% before rounding. The adjacent risk column uses all eligible short-acting episodes as its denominator.',
 table(['Recorded reason','Share of selected reasons','12-month cause-specific risk'],shortrows)))

zone_rows=[]
for scope in ['Overall::All modern']+['zone_name::'+z for z in zones]:
 r=by[scope];label='National' if scope.startswith('Overall') else r['category']
 ci=f'{num(r["ci_low"])}–{num(r["ci_high"])}%'
 zone_rows.append((label,r['eligible_episodes_n'],pct(r['selected_12_month_pct']),ci,
                   reasons(r)))
parts.append(section('selected-reason-regional-analysis',
 'Selected-reason discontinuation across Nigeria’s six zones',
 'Observed 12-month probabilities use eligible modern episodes in each zone. The seven reason shares are conditional on that zone’s selected-reason cumulative incidence and add to 100% before rounding. This is the intermediate outcome, before restricting to potentially actionable causes.',
 table(['Zone','Eligible episodes','12-month risk','95% CI','Reasons ranked by share'],zone_rows)))
heat=(['<div class="tablewrap"><table><thead><tr><th>Zone</th>']+
      [f'<th>{safe(x)}</th>' for x in reason_names]+['</tr></thead><tbody>'])
for scope in ['Overall::All modern']+['zone_name::'+z for z in zones]:
 r=by[scope];label='National' if scope.startswith('Overall') else r['category']
 heat.append('<tr><th>'+safe(label)+'</th>'+''.join(heat_cell(r[f'share_{j}_pct']) for j in range(1,8))+'</tr>')
heat.append('</tbody></table></div>')
parts.append(section('selected-reason-regional-reason-heatmap',
 'Reason mix among selected discontinuations by zone',
 'Each zone row sums to 100% before rounding. These are shares of selected discontinuations, not probabilities among all method episodes. National is shown first as a comparison.',
 ''.join(heat)))

mixrows=[]
for zone in ['National']+zones:
 z=by['Overall::All modern'] if zone=='National' else by['zone_name::'+zone]
 for m in methods:
  scope=f'zone_method::{zone}::{m}' if zone!='National' else f'method_group::{m}'
  r=by.get(scope)
  if not r:continue
  share=100*float(r['weighted_episodes'])/float(z['weighted_episodes'])
  mixrows.append((zone,m,pct(share),pct(r['selected_12_month_pct']),
                  r['eligible_episodes_n'],'*' if r['limited_precision']=='TRUE' else ''))
parts.append(section('regional-episode-mix-and-risk',
 'Episode method mix and within-method selected-reason risk',
 'The share column is each method’s survey-weighted share of eligible modern episodes within the zone. The risk column is the 12-month selected-reason probability among episodes of that method in that zone. These denominators differ from observed initiation shares. An asterisk flags fewer than 30 selected endings.',
 table(['Zone','Method','Share of eligible episodes','Within-method 12-month risk','Eligible episodes','Flag'],mixrows)))

start={(r['scope'],r['method']):r for r in starts}
allrisk={(r['scope']):r for r in alltime if int(float(r['month']))==12}
paired=[]
for zone in ['National']+zones:
 ec=start[(zone,'Emergency contraception')]
 denom_weight=float(ec['denominator_weighted_starts'])-float(ec['weighted_starts'])
 denom_n=int(float(ec['denominator_observed_starts_n']))-int(float(ec['observed_starts_n']))
 for m in methods:
  share=start.get((zone,m));risk=allrisk.get(zone+': '+m)
  if not share or not risk:continue
  paired.append((zone,m,pct(100*float(share['weighted_starts'])/denom_weight),
                 pct(risk['all_reason_pct']),str(denom_n),risk['eligible_episodes_n']))
parts.append(section('regional-method-paired-bars',
 'Method starts and all-reason discontinuation by zone',
 'This reproduces the two measures in Ethiopia’s paired-bar extension. Gold start shares use observed contraceptive starts in the zone, excluding EC from numerator and denominator but retaining non-modern methods. The 12-month all-reason risk uses eligible episodes of the named original modern method; it includes switching as original-method discontinuation. The two columns therefore have deliberately different denominators.',
 table(['Zone','Method','Share of all starts','12-month all-reason risk','Observed starts denominator','Eligible method episodes'],paired)))

section_html=''.join(parts)
source=page.read_text()
ids=['other-reasons-count-breakdown','other-reason-followup','selected-reason-descriptive-subgroups',
 'method-experience-subgroup-reasons','top-three-reasons-by-subgroup-method',
 'method-duration-class-discontinuation','short-acting-selected-reason-distribution',
 'selected-reason-regional-analysis','selected-reason-regional-reason-heatmap',
 'regional-episode-mix-and-risk','regional-method-paired-bars']
for id in ids:
 start=source.find(f'<section id="{id}"')
 if start>=0:
  end=source.find('</section>',start)+len('</section>')
  source=source[:start]+source[end:]
anchor='<section id="national"';assert anchor in source
source=source.replace(anchor,section_html+anchor,1)
for id in ids:
 toc=f'<a href="#{id}">{id.replace("-"," ").capitalize()}</a>'
 if f'href="#{id}"' not in source:
  old='<a href="#national">';assert old in source
  source=source.replace(old,toc+old,1)
page.write_text(source)
print(page,len(ids),'sections')
)----------------------"

REPORT_FILES[["src/report/41_add_selected_current_user_planning_html.py"]] <- r"----------------------(#!/usr/bin/env python3
"""Add Ethiopia-style selected-reason current-user planning tables to Nigeria."""
import csv,html
from pathlib import Path
import os
root=Path(os.environ["NIGERIA_PROJECT_ROOT"]);sup=root/'output/Supporting_data'
page=root/'output/Nigeria_discontinuation_analysis.html'
def read(n):
 with (sup/n).open(newline='') as f:return list(csv.DictReader(f))
planning=read('nigeria_selected_current_user_method_reason_planning.csv')
users=read('nigeria_current_users_by_method_and_actionable_projection.csv')
methods=['Injectables','Implants','Pill','IUD','Other modern']
reasons=list(dict.fromkeys(r['reason'] for r in planning))
assert len(planning)==35 and len(reasons)==7
stock={r['method']:float(r['current_users_2025']) for r in users}
stock_all=sum(stock.values())
def n(x):return f'{float(x):,.0f}'
def p(x):return f'{float(x):.2f}%'
def tab(head,rows):
 return ('<div class="tablewrap"><table><thead><tr>'+''.join('<th>'+html.escape(x)+'</th>' for x in head)+
 '</tr></thead><tbody>'+''.join('<tr>'+''.join('<td>'+html.escape(str(x))+'</td>' for x in row)+'</tr>' for row in rows)+
 '</tbody></table></div>')
def blocks(kind):
 col_risk='first_year_cause_risk_pct' if kind=='first' else 'duration_aware_next12_risk_pct'
 col_count='first_year_illustrative_endings' if kind=='first' else 'duration_aware_illustrative_endings'
 parts=[]
 for method in methods:
  z=[r for r in planning if r['method']==method]
  rows=[(r['reason'],p(r[col_risk]),n(r[col_count])) for r in z]
  rows.append(('All selected reasons',p(sum(float(r[col_risk]) for r in z)),
               n(sum(float(r[col_count]) for r in z))))
  parts.append(f'<h3>{html.escape(method)}: {n(stock[method])} projected 2025 current users</h3>')
  parts.append(tab(['Recorded reason','12-month probability','Illustrative original-method endings'],rows))
 allrows=[]
 for reason in reasons:
  z=[r for r in planning if r['reason']==reason]
  count=sum(float(r[col_count]) for r in z)
  allrows.append((reason,n(count),p(100*count/stock_all)))
 allcount=sum(float(r[col_count]) for r in planning)
 allrows.append(('All selected reasons',n(allcount),p(100*allcount/stock_all)))
 parts.append(f'<h3>All current modern users: {n(stock_all)} projected 2025 users, including EC</h3>')
 parts.append(tab(['Recorded reason','Illustrative original-method endings','As a share of all current modern users'],allrows))
 parts.append('<p class="small">EC is included in the current mCPR stock but contributes zero ongoing original-method endings. The all-modern percentage in this table is an illustrative ratio of projected endings to current users, not a pooled life-table cumulative incidence.</p>')
 return ''.join(parts)

compare=tab(['Approach','Probability source','Question answered','Main limitation'],[
 ('First year after a method start','Reason-specific competing-risk cumulative incidence in months 1–12 after method start','If current users faced the first-year risk observed after new starts, how many original methods would end?','Treats every current user as a new starter.'),
 ('Next 12 months after elapsed use','Historical landmark probability of an ending in the next 12 observed months, conditional on method and completed duration, standardized to current users','How many current users might end their original method over the next year given their duration mix?','Transports historical risks to the projected stock; 61+ month users use a 37–60 month proxy.')])
sec1=('<section id="current-user-reason-planning" class="analysis-section"><div class="eyebrow">Selected-reason planning</div>'
 '<h2>Illustrative first-year method endings by selected reason</h2>'
 '<p>Each current-user count is the projected 2025 stock from DHS 2024 mCPR, DHS 2024 current method shares and projected 2025 women aged 15–49. We multiply it by the method- and reason-specific 12-month competing-risk cumulative incidence from eligible original-method episodes. Wanted pregnancy and partner disapproval are excluded as events of interest but remain competing events. These figures count original-method endings, including women who switch to another modern method; they are not forecasts of net loss from mCPR.</p>'+blocks('first')+'</section>')
sec2=('<section id="duration-adjusted-reason-planning" class="analysis-section"><div class="eyebrow">Duration-aware planning</div>'
 '<h2>Next-year original-method endings among current users</h2>'
 '<p>These tables use historical landmark probabilities of an ending in the next 12 observed months, estimated within method and completed-duration bins and weighted to the projected current-user duration mix. The event remains any selected reason other than wanted pregnancy or partner disapproval; modern switching still counts as ending the original method. The 61+ month current-user group uses a 37–60 month historical risk proxy because 12-month follow-up at that duration is unavailable in the DHS calendar. Results are descriptive illustrations, not causal forecasts.</p>'+compare+blocks('duration')+
 '<p class="small"><a href="Supporting_data/nigeria_selected_current_user_method_reason_planning.csv">Download method-by-reason probabilities and counts</a> · <a href="../Code/40_nigeria_selected_current_user_planning.R">Open documented R code</a></p></section>')
source=page.read_text()
for id in ('current-user-reason-planning','duration-adjusted-reason-planning'):
 start=source.find(f'<section id="{id}"')
 if start>=0:
  end=source.find('</section>',start)+len('</section>')
  source=source[:start]+source[end:]
anchor='<section id="mcpr-scenarios"';assert anchor in source
source=source.replace(anchor,sec1+sec2+anchor,1)
for id,label in [('current-user-reason-planning','Selected-reason current users'),
                 ('duration-adjusted-reason-planning','Duration-aware selected reasons')]:
 toc=f'<a href="#{id}">{label}</a>'
 if f'href="#{id}"' not in source:
  old='<a href="#mcpr-scenarios">';assert old in source
  source=source.replace(old,toc+old,1)
page.write_text(source)
print(page)
)----------------------"

REPORT_FILES[["src/report/43_add_selected_risk_strata_html.py"]] <- r"----------------------(#!/usr/bin/env python3
"""Present the Nigeria out-of-fold selected-reason risk strata and profiles."""
import csv,html
from pathlib import Path
import os
root=Path(os.environ["NIGERIA_PROJECT_ROOT"]);out=root/'output';sup=out/'Supporting_data'
page=out/'Nigeria_discontinuation_analysis.html'
def read(n):
 with (sup/n).open(newline='') as f:return list(csv.DictReader(f))
strata=read('nigeria_selected_reason_crossvalidated_risk_strata.csv')
diff=read('nigeria_selected_reason_risk_strata_differences.csv')
profiles=read('nigeria_selected_reason_risk_strata_profiles.csv')
audit=read('nigeria_selected_reason_risk_strata_audit.csv')[0]
assert len(strata)==3 and len(diff)==3
def n(x):return f'{float(x):.1f}'
def tab(head,rows):return '<div class="tablewrap"><table><thead><tr>'+''.join('<th>'+html.escape(h)+'</th>' for h in head)+'</tr></thead><tbody>'+''.join('<tr>'+''.join('<td>'+html.escape(str(x))+'</td>' for x in row)+'</tr>' for row in rows)+'</tbody></table></div>'
rows=[(r['risk_stratum'],r['eligible_episodes'],n(r['weighted_share_pct'])+'%',
       n(r['predicted_risk_median_pct'])+'%',n(r['observed_12_month_probability_pct'])+'%',
       n(r['ci_low'])+'–'+n(r['ci_high'])+'%') for r in strata]
contrasts=[(r['comparison'],n(r['estimate_pp'])+' pp',n(r['ci_low'])+' to '+n(r['ci_high'])+' pp') for r in diff]
profile=[]
for characteristic in ('method_group','age_group','parity_group','marital_group','education','wealth','residence'):
 for level in dict.fromkeys(r['level'] for r in profiles if r['characteristic']==characteristic):
  vals=[]
  for stratum in ('Lower','Middle','Higher'):
   r=next(x for x in profiles if x['characteristic']==characteristic and x['level']==level and x['risk_stratum']==stratum)
   vals.append(n(r['weighted_share_within_stratum_pct'])+'%')
  profile.append((characteristic.replace('_',' ').title(),level,*vals))
section=('<section id="selected-reason-risk-strata" class="analysis-section">'
 '<div class="eyebrow">Exploratory risk profiles</div><h2>Cross-validated lower, middle and higher risk bands</h2>'
 '<p>Five folds are assigned by DHS sampling cluster within stratum. A weighted discrete-time competing-outcome model trained outside each episode’s cluster predicts 12-month selected-reason risk from method, age at start and parity at start. Excluded pregnancy and partner endings remain competing outcomes. Episodes are split into three roughly equal weighted bands of out-of-fold predicted risk. Observed band-specific rates are recalculated with the life table, retaining delayed entry. This is a risk-profile analysis of episodes, not a clustering of women.</p>'+tab(['Band','Eligible episodes','Weighted share','Median predicted risk','Observed 12-month risk','95% bootstrap CI'],rows)+
 '<p>In Nigeria, all three observed bands are distinguishable in the fixed-score survey bootstrap. Their differences are:</p>'+tab(['Contrast','Difference','95% bootstrap CI'],contrasts)+
 '<h3>Characteristics represented within each risk band</h3>'+tab(['Covariate','Category','Lower','Middle','Higher'],profile)+
 '<p class="small">Method, age and parity create the score, so their profile differences are partly mechanical. Marital status, education, wealth and residence are observed at interview and were not score inputs; earlier episodes may have had different values. Bootstrap intervals hold model scores and cut points fixed and do not include model-training uncertainty.</p>'
 '<p class="small"><a href="Supporting_data/nigeria_selected_reason_crossvalidated_risk_strata.csv">Risk-band results</a> · <a href="Supporting_data/nigeria_selected_reason_risk_strata_profiles.csv">Profile data</a> · <a href="../Code/42_nigeria_crossvalidated_selected_risk_strata.R">Documented model code</a></p></section>')
source=page.read_text();start=source.find('<section id="selected-reason-risk-strata"')
if start>=0:
 end=source.find('</section>',start)+len('</section>');source=source[:start]+source[end:]
anchor='<section id="method-duration-class-discontinuation"';assert anchor in source
source=source.replace(anchor,section+anchor,1)
if 'href="#selected-reason-risk-strata"' not in source:
 old='<a href="#method-duration-class-discontinuation">';assert old in source
 source=source.replace(old,'<a href="#selected-reason-risk-strata">Selected-reason risk bands</a>'+old,1)
page.write_text(source);print(page)
)----------------------"

REPORT_FILES[["src/report/45_add_replication_figures_html.py"]] <- r"----------------------(#!/usr/bin/env python3
"""Place Nigeria-specific figures within corresponding working-HTML analyses."""
from pathlib import Path
import os
import re
from html import escape

page=(Path(os.environ["NIGERIA_PROJECT_ROOT"]) / 'output/Nigeria_discontinuation_analysis.html')
source=page.read_text()
items=[
 ('initiation','nigeria_regional_method_start_mix.svg','Weighted method-start mix by zone; denominator includes EC and non-modern methods.'),
 ('all-cause','nigeria_all_reason_pct_method_curves.svg','Cumulative original-method discontinuation for all recorded reasons.'),
 ('all-cause','nigeria_national_start_vs_all_reason_pct.svg','Start share excludes EC from the start denominator; discontinuation is method-specific.'),
 ('all-reason-transitions','nigeria_all_reason_month12_followup_stacked.svg','Month-12 status is shown as a distribution among observed first-year all-reason endings with follow-up.'),
 ('selected-reasons','nigeria_selected_reason_pct_method_curves.svg','Selected endings exclude wanted pregnancy and partner disapproval as events of interest; both remain competing outcomes.'),
 ('selected-reason-regional-analysis','nigeria_selected_reason_zone_forest.svg','Unadjusted 12-month selected-reason discontinuation with survey-bootstrap intervals.'),
 ('selected-reason-regional-reason-heatmap','nigeria_selected_reason_zone_heatmap.svg','Shares among selected endings sum to 100 percent within zone.'),
 ('national','nigeria_actionable_pct_method_curves.svg','Cumulative original-method discontinuation for potentially actionable reasons.'),
 ('national','nigeria_national_start_vs_actionable_pct.svg','Method-start shares and actionable first-year risks use different denominators.'),
 ('action-pathways','nigeria_injectable_reason_timing_destination_heatmap.svg','Timing columns sum to 100 within each injectable reason; the final column shows no method one month later.'),
 ('zone-rates','nigeria_actionable_zone_observed_adjusted.svg','Observed and fully adjusted 12-month potentially actionable risk by zone with design-aware intervals.'),
 ('timing','nigeria_actionable_zone_timing_heatmap.svg','The first four columns are cumulative rates; the final column is the month-3 share of month-12 risk.'),
 ('zone-reasons','nigeria_actionable_zone_reason_heatmap.svg','Reason shares are conditional on an actionable ending and sum to 100 percent within zone.'),
 ('method-mix','nigeria_regional_method_start_mix.svg','National and zone method-start mix; includes EC and non-modern starts.'),
]
for section,name,caption in items:
 marker=f'<!-- nigeria-replication-figure:{name} -->'
 if marker in source:continue
 match=re.search(r'<section\s+[^>]*id="'+re.escape(section)+r'"[^>]*>',source)
 if not match:raise ValueError(section)
 h=re.search(r'</h[1-3]>',source[match.end():])
 if not h:raise ValueError('heading '+section)
 point=match.end()+h.end()
 block=f'{marker}<figure class="replication-figure"><img src="assets/{escape(name)}" alt="{escape(caption)}" loading="lazy"><figcaption>{escape(caption)}</figcaption></figure>'
 source=source[:point]+block+source[point:]
style='<style>.replication-figure{margin:1.1rem 0 1.8rem;padding:0}.replication-figure img{width:100%;height:auto;display:block}.replication-figure figcaption{font-size:.82rem;color:#506879;margin-top:.35rem}</style>'
if 'replication-figure{margin:' not in source:source=source.replace('</head>',style+'</head>',1)
page.write_text(source)
print(page)
)----------------------"

REPORT_FILES[["src/report/46_add_three_definition_comparison_html.py"]] <- r"----------------------(#!/usr/bin/env python3
"""Add the direct all/selected/actionable comparison in the Ethiopia structure."""
from pathlib import Path
import os
import csv,html,re
out=(Path(os.environ["NIGERIA_PROJECT_ROOT"]) / 'output');page=out/'Nigeria_discontinuation_analysis.html'
with (out/'Supporting_data/nigeria_modern_all_reason_timepoints.csv').open(newline='') as f: rows=list(csv.DictReader(f))
order=['National','National: Injectables','National: Implants','National: Pill','National: IUD','National: Other modern']
lookup={r['scope']:r for r in rows if r['month']=='12'}
assert all(x in lookup for x in order)
tr=[]
for scope in order:
 r=lookup[scope];label='All modern' if scope=='National' else scope.split(': ',1)[1]
 tr.append('<tr>'+''.join(f'<td>{html.escape(v)}</td>' for v in (label,*[f'{float(r[k]):.1f}%' for k in ('all_reason_pct','selected_reason_pct','actionable_pct')]))+'</tr>')
block='<section id="twelve-month-three-column-comparison" class="analysis-section"><div class="eyebrow">Three outcome definitions</div><h2>12-month discontinuation by method and reason definition</h2><p>Each cell is a weighted competing-risk life-table probability among episodes that started that modern method. The selected measure excludes wanted pregnancy and partner disapproval as events of interest; the actionable measure also excludes circumstantial and unresolved reasons. Excluded endings remain competing events, so the three columns describe nested event sets rather than different episode denominators. Emergency contraception is excluded from the episode cohorts.</p><div class="tablewrap"><table><thead><tr><th>Method</th><th>All recorded reasons</th><th>Selected reasons</th><th>Potentially actionable reasons</th></tr></thead><tbody>'+''.join(tr)+'</tbody></table></div><p class="small">Source: Nigeria DHS 2024 IR monthly calendar. The all-modern row is calculated from the pooled modern-episode life table, not an average of method-specific percentages.</p></section>'
s=page.read_text();old=re.search(r'<section id="twelve-month-three-column-comparison".*?</section>',s,re.S)
if old:s=s[:old.start()]+s[old.end():]
anchor='<section id="selected-reasons"';assert anchor in s;s=s.replace(anchor,block+anchor,1)
if 'href="#twelve-month-three-column-comparison"' not in s:
 target='<a href="#selected-reasons"';assert target in s
 s=s.replace(target,'<a href="#twelve-month-three-column-comparison">Three reason definitions</a>'+target,1)
page.write_text(s);print(page)
)----------------------"

REPORT_FILES[["src/report/47_add_method_followup_alluvials_html.py"]] <- r"----------------------(#!/usr/bin/env python3
"""Insert the four Nigeria method-to-follow-up alluvials in narrative order."""
from pathlib import Path
import os
root=(Path(os.environ["NIGERIA_PROJECT_ROOT"]) / 'output');p=root/'Nigeria_discontinuation_analysis.html'
s=p.read_text()
def fig(name,alt):return f'<figure class="replication-figure"><img src="assets/{name}" alt="{alt}" loading="lazy"><figcaption>{alt}</figcaption></figure>'
allblock='<section id="all-reason-transitions" class="analysis-section"><div class="eyebrow">After an original-method ending</div><h2>What follows an all-reason discontinuation?</h2><p>Among observed first-year endings for any reason, the following figures show the recorded method or reproductive state one and twelve months later. Each figure conditions on having that follow-up month in the calendar. These are distributions among observed endings, not 12-month life-table risks and not projections of current users.</p>'+fig('nigeria_all_reason_method_to_month_01_alluvial.png','Original modern method and state one month after an all-reason ending.')+fig('nigeria_all_reason_method_to_month_12_alluvial.png','Original modern method and state twelve months after an all-reason ending.')+'</section>'
selblock='<section id="selected-reason-transitions" class="analysis-section"><div class="eyebrow">After a selected-reason ending</div><h2>What follows discontinuation for a selected reason?</h2><p>These figures exclude endings recorded as wanted pregnancy or partner disapproval. The month-one and month-twelve figures have different follow-up cohorts. A woman can restart or switch later; an original-method ending does not imply year-end nonuse of modern contraception.</p>'+fig('nigeria_selected_reason_method_to_month_01_alluvial.png','Original modern method and state one month after a selected-reason ending.')+fig('nigeria_selected_reason_method_to_month_12_alluvial.png','Original modern method and state twelve months after a selected-reason ending.')+'</section>'
for id in ('all-reason-transitions','selected-reason-transitions'):
 a=s.find(f'<section id="{id}"')
 if a>=0:
  b=s.find('</section>',a)+len('</section>');s=s[:a]+s[b:]
anchor='<section id="selected-reasons"';assert anchor in s;s=s.replace(anchor,allblock+anchor,1)
anchor='<section id="selected-followup"';assert anchor in s;s=s.replace(anchor,selblock+anchor,1)
for id,label,before in [('all-reason-transitions','After all-reason endings','selected-reasons'),('selected-reason-transitions','After selected-reason endings','selected-followup')]:
 if f'href="#{id}"' not in s:
  target=f'<a href="#{before}"';assert target in s;s=s.replace(target,f'<a href="#{id}">{label}</a>'+target,1)
p.write_text(s);print(p.name)
)----------------------"

REPORT_FILES[["src/report/48_add_selected_regional_adjustment_html.py"]] <- r"----------------------(#!/usr/bin/env python3
"""Complete the selected-reason regional sequence with adjusted probabilities."""
from pathlib import Path
import os
import csv,re,html
root=(Path(os.environ["NIGERIA_PROJECT_ROOT"]) / 'output');page=root/'Nigeria_discontinuation_analysis.html'
with (root/'Supporting_data/nigeria_selected_reason_zone_models.csv').open(newline='') as f:r=list(csv.DictReader(f))
with (root/'Supporting_data/nigeria_selected_reason_zone_pairwise.csv').open(newline='') as f:pairs=list(csv.DictReader(f))
order=['National','North West','North East','North Central','South East','South South','South West']
by={x['zone']:x for x in r};assert all(z in by for z in order)
def cell(x,k,lo,hi):return f'{float(x[k]):.1f}% ({float(x[lo]):.1f}–{float(x[hi]):.1f})'
rows=[]
for zone in order:
 x=by[zone]
 rows.append('<tr>'+''.join('<td>'+html.escape(v)+'</td>' for v in (zone,x['eligible_episodes_n'],cell(x,'unadjusted_pct','unadjusted_low','unadjusted_high'),cell(x,'model_1_pct','model_1_low','model_1_high'),cell(x,'model_2_pct','model_2_low','model_2_high')))+'</tr>')
pair_rows=[]
for x in pairs:
 pair_rows.append('<tr>'+''.join('<td>'+html.escape(v)+'</td>' for v in (x['zone_a']+' vs '+x['zone_b'],f'{float(x["difference_pp"]):+.1f} pp',f'{float(x["ci_low"]):+.1f} to {float(x["ci_high"]):+.1f} pp',f'{float(x["p_holm"]):.3f}','Yes' if x['significant_5pct']=='TRUE' else 'No'))+'</tr>')
section='<section id="selected-reason-regional-adjusted" class="analysis-section"><div class="eyebrow">Selected-reason regional adjustment</div><h2>Observed and adjusted 12-month probabilities by zone</h2><p>All three columns estimate the probability that an episode ends its original modern method for any reason except wanted pregnancy or partner disapproval. Model 1 accounts for original method and month since method start. Model 2 additionally includes age and parity at method start, marital status, education, wealth, and urban/rural residence measured at interview, plus zone. Adjusted zone predictions hold the measured episode composition common across zones to compare like with like.</p><figure class="replication-figure"><img src="assets/nigeria_selected_reason_zone_adjusted.svg" alt="Observed, method-adjusted and fully adjusted regional selected-reason discontinuation with confidence intervals" loading="lazy"><figcaption>Intervals for adjusted estimates use 80 survey-cluster bootstrap refits and should be treated as preliminary.</figcaption></figure><div class="tablewrap"><table><thead><tr><th>Zone</th><th>Eligible episodes</th><th>Observed (95% CI)</th><th>Method adjusted (95% CI)</th><th>Fully adjusted (95% CI)</th></tr></thead><tbody>'+''.join(rows)+'</tbody></table></div><h3>Formal pairwise comparisons of observed rates</h3><p>All 15 raw zone pairs are tested using paired differences from 300 stratified PSU bootstrap draws. Holm-adjusted p-values control the family of comparisons. The table tests selected-reason rates; it is separate from the later actionable comparison.</p><div class="tablewrap"><table><thead><tr><th>Zone pair</th><th>Difference</th><th>95% CI</th><th>Holm p</th><th>Significant at 5%</th></tr></thead><tbody>'+''.join(pair_rows)+'</tbody></table></div><p class="small">Source: Nigeria DHS 2024 IR calendar. The 80-refit adjusted intervals are less stable than the 300–500 replicate analyses used for the later actionable regional comparisons. These are association and standardization estimates, not causal regional effects.</p></section>'
s=page.read_text();m=re.search(r'<section id="selected-reason-regional-adjusted".*?</section>',s,re.S)
if m:s=s[:m.start()]+s[m.end():]
anchor='<section id="selected-reason-regional-reason-heatmap"';assert anchor in s;s=s.replace(anchor,section+anchor,1)
if 'href="#selected-reason-regional-adjusted"' not in s:
 target='<a href="#selected-reason-regional-reason-heatmap"';assert target in s
 s=s.replace(target,'<a href="#selected-reason-regional-adjusted">Adjusted selected-reason rates</a>'+target,1)
page.write_text(s);print(page)
)----------------------"

REPORT_FILES[["src/report/50_add_all_reason_regional_paired_bars.py"]] <- r"----------------------(#!/usr/bin/env python3
"""Mirror the Ethiopia by-method regional paired bars for all-reason risk."""
from pathlib import Path
import os
import csv,re,html
root=(Path(os.environ["NIGERIA_PROJECT_ROOT"]) / 'output');p=root/'Nigeria_discontinuation_analysis.html'
def read(n):
 with (root/'Supporting_data'/n).open(newline='') as f:return list(csv.DictReader(f))
mix={(x['scope'],x['method']):x for x in read('nigeria_zone_all_method_start_mix.csv')}
risk={x['scope']:x for x in read('nigeria_modern_all_reason_timepoints.csv') if x['month']=='12'}
zones=['National','North West','North East','North Central','South East','South South','South West']
methods=['Injectables','Implants','Pill','IUD','Other modern']
parts=['<!-- all-reason-paired-bars-start -->']
for method in methods:
 parts.append('<h3>'+html.escape(method)+'</h3><div class="pairchart">')
 for zone in zones:
  m=mix[(zone,method)];ec=mix[(zone,'Emergency contraception')]
  den=float(m['denominator_weighted_starts'])-float(ec['weighted_starts'])
  start=100*float(m['weighted_starts'])/den
  r=risk[zone+': '+method];rate=float(r['all_reason_pct'])
  flag='*' if int(float(r['all_reason_endings_n']))<30 else ''
  parts.append('<div class="pairrow"><label>'+html.escape(zone)+flag+'</label><div class="two">'
   '<div class="sub"><span>Start share</span><div class="bartrack"><span style="width:'+f'{min(100,start):.2f}'+'%;background:#DA9A25"></span></div><strong>'+f'{start:.1f}'+'%</strong></div>'
   '<div class="sub"><span>12-month risk</span><div class="bartrack"><span style="width:'+f'{min(100,rate):.2f}'+'%;background:#153F5B"></span></div><strong>'+f'{rate:.1f}'+'%</strong></div></div><span></span></div>')
 parts.append('</div>')
parts.append('<p class="small">Gold uses all observed method starts excluding EC as its denominator; navy uses eligible episodes of the named modern method. * Fewer than 30 observed first-year endings; interpret cautiously.</p><!-- all-reason-paired-bars-end -->')
block=''.join(parts)
s=p.read_text();s=re.sub(r'<!-- all-reason-paired-bars-start -->.*?<!-- all-reason-paired-bars-end -->','',s,flags=re.S)
a=s.index('<section id="regional-method-paired-bars"');h=re.search(r'</p>',s[a:]);assert h
at=a+h.end();s=s[:at]+block+s[at:]
p.write_text(s);print(p.name)
)----------------------"

REPORT_FILES[["src/report/59_align_html_visual_style.py"]] <- r"----------------------(from pathlib import Path
import os
import re

p=(Path(os.environ["NIGERIA_PROJECT_ROOT"]) / 'output/Nigeria_discontinuation_analysis.html')
html=p.read_text()
html=re.sub(r'<style id="ethiopia-visual-alignment">.*?</style>','',html,flags=re.S)
css='''
/* Align the Nigeria report shell, hierarchy and tables with the Ethiopia working HTML.
   Figure-specific colors and numerical content remain unchanged. */
body{background:#eef2f3;color:#18313e;font:15px/1.55 -apple-system,BlinkMacSystemFont,"Segoe UI",Arial,sans-serif}
aside{background:#234957;border-right:0;color:#fff;padding:27px 17px}
aside strong{font-family:Georgia,serif;color:#fff;font-size:20px}
aside small{color:#d1e1e5}
aside a{color:#e7f0f2;font-size:13px;padding:7px 9px}
aside a:hover,aside a:focus{background:#366170;color:#fff}
.toc-group{color:#e6bc65!important}
main{background:#fff;margin-left:254px;padding:48px 52px 90px;max-width:1600px;min-height:100vh}
header{padding:0 0 25px;border-bottom:0}
header h1{font-size:36px;color:#234957}
header p{color:#52666f}
section{padding:0 0 12px;border-bottom:0;scroll-margin-top:18px}
section h2{font-size:25px;color:#234957;margin:45px 0 9px;padding-top:12px;border-top:3px solid #234957}
section h3{font-size:18px;color:#234957}
.tablewrap{overflow-x:auto;border:1px solid #cbd8dc;border-radius:7px;margin:12px 0 18px}
table{font-size:13px}
thead th{background:#234957;color:#fff;border-bottom:0;padding:10px 9px;white-space:normal;vertical-align:bottom}
tbody th{color:#18313e;padding:9px;text-align:left}
tbody td{padding:9px;border-bottom:1px solid #e3eaed}
tbody tr:nth-child(even){background:#f6f9fa}
tbody tr.total{background:#ecf3f5;font-weight:700}
.note{background:#edf4f5;border-left-color:#2d7180}
.goldnote{background:#fff7e8;border-left-color:#DA9A25}
.metric strong{color:#234957}
.pairrow,.zonebar,.forestrow,.dualrow{font-size:14px}
@media(max-width:900px){aside{position:static;width:auto;max-height:195px;border-bottom:0}main{margin:0;padding:28px 18px 60px}section h2{margin-top:34px}thead th{font-size:12px}}
'''
html=html.replace('</head>', '<style id="ethiopia-visual-alignment">'+css+'</style></head>',1)
p.write_text(html)
print(p.name)
)----------------------"

REPORT_FILES[["src/report/72_correct_modern_reason_html.py"]] <- r"----------------------(#!/usr/bin/env python3
"""Correct the existing working HTML without discarding later added sections."""
import csv
from html import escape
from pathlib import Path
import os

root=Path(os.environ["NIGERIA_PROJECT_ROOT"])
path=root/'output/Nigeria_discontinuation_analysis.html'
sup=root/'output/Supporting_data'
with (sup/'nigeria_modern_five_year_reason_distribution_seven.csv').open() as f:
    seven=list(csv.DictReader(f))
with (sup/'nigeria_modern_five_year_reason_distribution.csv').open() as f:
    by_method=list(csv.DictReader(f))
s=path.read_text()
start=s.index('<section id="dhs-713">')
end=s.index('</section>',start)+len('</section>')
old=s[start:end]
table_start=old.index('<div class="tablewrap"><table>')
published=old[table_start:]
published=published.replace('</section>','')
intro=('<section id="dhs-713"><div class="eyebrow">Five-year calendar distribution</div>'
 '<h2>Reasons among recorded modern-method discontinuations</h2>'
 '<p class="intro">Matching the Ethiopia presentation, the primary reason distribution '
 'includes only recorded endings of modern-method episodes in the five-year calendar, '
 'excluding emergency contraception. It contains 4,557 unweighted endings (4,531.8 '
 'weighted). These are shares among endings, not 12-month discontinuation risks.</p>')
seven_table='<h3>All modern methods</h3><div class="tablewrap"><table><thead><tr><th>Recorded reason</th><th>Weighted share of endings</th></tr></thead><tbody>'
for row in seven:
    seven_table+=f'<tr><td>{escape(row["reason"])}</td><td class="num">{float(row["percent"]):.1f}%</td></tr>'
seven_table+='</tbody></table></div><p class="small">The seven categories sum to 100% before rounding. Source: Nigeria DHS 2024 IR contraceptive calendar, survey weighted; modern-method endings excluding EC.</p>'
method_table='<h3>Reason distribution by modern method</h3><div class="tablewrap"><table><thead><tr><th>Method</th><th>Wanted pregnancy</th><th>Method experience/access</th><th>Partner disapproval</th><th>Other reasons</th><th>Observed endings</th></tr></thead><tbody>'
for method in ['All modern','Injectables','Implants','Pill','IUD','Other modern']:
    rows=[r for r in by_method if r['method']==method]
    method_table+='<tr><td>'+escape(method)+'</td>'+''.join(f'<td class="num">{float(r["percent"]):.1f}%</td>' for r in rows)+f'<td class="num">{int(rows[0]["unweighted_endings"]):,}</td></tr>'
method_table+='</tbody></table></div><p class="small">Rows sum to 100% before rounding. Counts are unweighted and shares are survey weighted. EC and traditional methods are excluded.</p>'
published='<h3>Published DHS Table 7.13: all-method validation comparison</h3><p class="small">The official table below includes traditional methods and EC. Its all-method column is a validation control and is not the denominator for the presentation reasons chart.</p>'+published
s=s[:start]+intro+seven_table+method_table+published+'</section>'+s[end:]
path.write_text(s)
print(path)
)----------------------"

REPORT_FILES[["src/validate_aft_transitions.R"]] <- r"----------------------(# DHS complex survey design for this module.
.dhs_root <- Sys.getenv('NIGERIA_PROJECT_ROOT')
if (!nzchar(.dhs_root)) {
 .dhs_file <- sub('^--file=','',grep('^--file=',commandArgs(FALSE),value=TRUE)[1])
 .dhs_root <- dirname(dirname(normalizePath(.dhs_file)))
}
source(file.path(.dhs_root,'Code','dhs_survey_tools.R'),local=TRUE)
dhs_set_context(country='Nigeria',root=.dhs_root)
#!/usr/bin/env Rscript
# Held-out PSU checks of modern use following actionable original-method endings.
a<-commandArgs(TRUE);stopifnot(length(a)==3);root<-a[1];fitdir<-a[2];out<-a[3];dir.create(out,recursive=TRUE,showWarnings=FALSE)
suppressPackageStartupMessages({library(data.table);library(jsonlite)})
ir<-readRDS(file.path(root,'Data/raw_dhs_ir/NG2024DHS__NGIR8BDT__IR_raw.rds'));cal<-readRDS(file.path(root,'Data/Derived/nigeria_2024_calendar_events.rds'))
methods<-c('Injectables','Implants','Pill','IUD','Other modern');causes<-c('Method failure','Wanted more effective method','Changes in menstrual bleeding','Other side effects/health','Access/cost/convenience');codes<-list(1L,7L,15L,c(4L,5L),c(6L,8L,10L));action<-unlist(codes)
modern<-c(1L,2L,3L,5L,6L,7L,11L,13L,14L,15L,17L,18L,19L,20L);modern<-setdiff(modern,c(6L,7L));endpoint_modern<-c(modern,6L,7L,16L)
method_group<-function(x)ifelse(x==3,'Injectables',ifelse(x==11,'Implants',ifelse(x==1,'Pill',ifelse(x==2,'IUD','Other modern'))));cause_group<-function(x){z<-rep(NA_integer_,length(x));for(j in 1:5)z[x%in%codes[[j]]]<-j;z}
source(file.path(root,'Code/transition_model.R'))
point<-readRDS(file.path(fitdir,'transition_point_fits.rds'))
diagnostics<-rbindlist(lapply(states,function(s){f<-point$transitions[[s]];check<-fit_transition(follow[follow$current_state==s,],s,f$family,.1,start=f$par,check_gradient=TRUE);data.table(state=s,family=f$family,boundary=f$boundary,convergence=f$convergence,max_gradient_error=check$max_gradient_error)}));write.csv(diagnostics,file.path(out,'transition_fit_diagnostics.csv'),row.names=FALSE)
set.seed(20261110);frame<-unique(data.table(psu=as.integer(ir$v021),stratum=as.integer(ir$v022)));frame[,fold:=sample(rep(1:5,length.out=.N)),by=stratum]
initial<-merge(initial,frame[,.(psu,fold)],by='psu');follow<-merge(follow,frame[,.(psu,fold)],by='psu');histories<-merge(histories,frame[,.(psu,fold)],by='psu');validation<-list()
for(k in 1:5){cat('Held-out fold',k,'\n');flush.console();fit<-fit_models(initial[initial$fold!=k,],follow[follow$fold!=k,],'selected',.1);test<-histories[histories$fold==k & histories$horizon%in%c(1L,3L,6L,12L),];gr<-unique(test[,.(method,cause,end_duration,duration_log)]);gr$gid<-seq_len(nrow(gr));pred<-merge(gr,endpoint_prob(fit,gr,12L),by='gid');v<-merge(test,pred,by=c('method','cause','end_duration','duration_log','horizon'));v[,observed:=as.numeric(observed_state%in%c('Modern','Permanent'))];validation[[k]]<-v[,.(horizon,wt,observed,p_modern,fold)]}
v<-rbindlist(validation);c<-v[,.(observations=.N,observed_modern=sum(wt*observed)/sum(wt),predicted_modern=sum(wt*p_modern)/sum(wt),brier=sum(wt*(observed-p_modern)^2)/sum(wt)),by=horizon];c[,difference_pp:=100*(predicted_modern-observed_modern)];write.csv(c,file.path(out,'held_out_calibration.csv'),row.names=FALSE);print(c)

checks<-jsonlite::fromJSON(file.path(fitdir,'transition_fit_metadata.json'),simplifyVector=FALSE)
checks$held_out<-lapply(seq_len(nrow(c)),function(i)as.list(c[i,]))
checks$fit_diagnostics<-lapply(seq_len(nrow(diagnostics)),function(i)as.list(diagnostics[i,]))
jsonlite::write_json(checks,file.path(fitdir,'transition_validation.json'),auto_unbox=TRUE,pretty=TRUE)
)----------------------"

# Additional national method-group checks, executed after primary planning.
MODULES[["999_method_group_sensitivity.R"]] <- list(language="R", packaged_sha256="b45a765ee0059c0d50e9b04882af65473970f43fa789664a798ede59489d1c31", args=character(0), code=r"----------------------(#!/usr/bin/env Rscript
# Overall actionable-ending sensitivity; inputs are supplied at runtime.
args<-commandArgs(TRUE)
if(!length(args)){root<-Sys.getenv('NIGERIA_PROJECT_ROOT');stopifnot(nzchar(root));args<-c('Nigeria',root,file.path(root,'output/method_group_sensitivity'))}
stopifnot(length(args)==3L)
country<-args[1];root<-normalizePath(args[2]);out<-args[3]
stopifnot(country%in%c('Nigeria','DRC'));dir.create(out,recursive=TRUE,showWarnings=FALSE)
suppressPackageStartupMessages({library(survey);library(survival);library(jsonlite)})
source(file.path(root,'Code','dhs_survey_tools.R'))
irfile<-if(country=='Nigeria')'Data/raw_dhs_ir/NG2024DHS__NGIR8BDT__IR_raw.rds'else'Data/ir.rds'
prefix<-if(country=='Nigeria')'nigeria_2024'else'drc_2023_24'
ir<-readRDS(file.path(root,irfile));dhs_set_context(country=country,root=root,ir=ir)
e<-readRDS(file.path(root,'Data/Derived',paste0(prefix,'_modern_episodes.rds')))
cal<-readRDS(file.path(root,'Data/Derived',paste0(prefix,'_calendar_events.rds')))
pop<-read.csv(file.path(root,'output/Supporting_data',if(country=='Nigeria')'nigeria_wpp2024_wra_2024_2026.csv'else'drc_wpp2024_wra_2024_2026.csv'))
w24<-pop$women_15_49[pop$year==2024];w25<-pop$women_15_49[pop$year==2025]
modern<-c(1L,2L,3L,5L,6L,7L,11L,13L,14L,15L,17L,18L,19L,20L)
reversible<-setdiff(modern,c(6L,7L));endpoint_modern<-c(modern,16L)
action<-c(1L,4L,5L,6L,7L,8L,10L,15L)
e<-e[e$method_code%in%reversible,]
mg<-function(x,split=FALSE){z<-ifelse(x==3L,'Injectables',ifelse(x==11L,'Implants',ifelse(x==1L,'Pill',ifelse(x==2L,'IUD','Other modern'))));if(split){z[x==5L]<-'Male condoms';z[x==13L]<-'LAM'};z}
base_methods<-c('Injectables','Implants','Pill','IUD','Other modern')
bins<-c(-1,3,6,12,24,36,48,60,Inf)
wt<-as.numeric(ir$v005)/1e6
current_ix<-which(as.numeric(ir$v313)==3&as.numeric(ir$v312)%in%reversible)
current<-data.frame(woman_row=current_ix,method_code=as.numeric(ir$v312[current_ix]),elapsed=dhs_current_duration(ir,current_ix),wt=wt[current_ix])
current$bin<-as.integer(cut(current$elapsed,bins));stopifnot(!anyNA(current$bin))
# Keep original permanent and EC classifications for observed endpoint use.
bywoman<-split(seq_len(nrow(cal)),cal$woman_row)
spells<-cal[cal$method_code%in%reversible&cal$start>cal$calendar_start,]
records<-vector('list',nrow(spells))
for(i in seq_len(nrow(spells))){a<-spells[i,];last<-min(a$end,a$interview-15L);if(last<a$start)next
 t<-seq.int(a$start,last);timeline<-cal[bywoman[[as.character(a$woman_row)]],];j<-findInterval(t+12L,timeline$start)
 stopifnot(all(j>0),all(timeline$end[j]>=t+12L));ending<-a$end<t+12L&a$reason_code%in%action
 records[[i]]<-data.frame(woman_row=a$woman_row,episode=i,method_code=a$method_code,elapsed=t-a$start,wt=a$wt,gross=as.numeric(ending),net=as.numeric(ending&!timeline$method_code[j]%in%endpoint_modern))
}
land<-do.call(rbind,records);land$bin<-as.integer(cut(land$elapsed,bins))
frame<-dhs_context()$frame
mean_design<-function(data,vars){d<-dhs_design(dhs_attach_design(data),frame);unname(coef(svymean(as.formula(paste('~',paste(vars,collapse='+'))),subset(d,.dhs_record))))}
ir_design<-dhs_context()$woman_design
stock<-function(m,split)w24*unname(dhs_percentage(ir_design,as.numeric(ir$v313)==3&mg(as.numeric(ir$v312),split)==m&as.numeric(ir$v312)%in%reversible)['percent'])/100
H<-function(t,mu,scale,dist){switch(dist,weibull=(t/exp(mu))^(1/scale),exponential=t/exp(mu),loglogistic=log1p(exp((log(t)-mu)/scale)),lognormal=-pnorm((log(t)-mu)/scale,lower.tail=FALSE,log.p=TRUE))}
fit_one<-function(data,event,dist){data$event<-data[[event]];f<-dhs_aft_fit(Surv(exposure,event)~method,data=data,weights=wt,dist=dist,control=survreg.control(maxiter=500));stopifnot(f$iter<500,all(is.finite(coef(f))),is.finite(f$scale));f}
fit_data<-function(split){d<-e[e$entry==0&e$exposure>0,];d$method<-mg(d$method_code,split);mm<-c(base_methods,if(split)c('Male condoms','LAM'))
 if(country=='DRC'){d$method[d$method=='IUD']<-'Other modern';mm<-setdiff(mm,'IUD')}
 d$method<-factor(d$method,levels=mm);d$actionable<-as.integer(d$discontinued&d$reason_code%in%action);d$other<-as.integer(d$discontinued&!d$reason_code%in%action);d}
pooldata<-fit_data(FALSE)
if(country=='Nigeria'){
 fam<-read.csv(file.path(root,'output/Supporting_data/nigeria_survival_model_duration_fit.csv'))
 families<-c(actionable=fam$distribution[fam$selected_actionable],other=fam$distribution[fam$selected_other])
 pooledfits<-setNames(lapply(names(families),function(v)fit_one(pooldata,v,families[[v]])),names(families))
}else{
 choice<-c('lognormal','weibull','loglogistic','exponential');families<-c(actionable='',other='');pooledfits<-list();aics<-list()
 for(v in names(families)){
  ff<-lapply(choice,function(dist)tryCatch(fit_one(pooldata,v,dist),error=function(e)NULL));ok<-which(!vapply(ff,is.null,FALSE));stopifnot(length(ok)>0)
  aa<-vapply(ff[ok],dhs_aft_aic,0.0);best<-ok[which.min(aa)];families[v]<-choice[best];pooledfits[[v]]<-ff[[best]];aics[[v]]<-setNames(aa,choice[ok])
 }
 write_json(aics,file.path(out,'aggregate_aft_family_checks.json'),pretty=TRUE,auto_unbox=TRUE)
}
next12<-function(age,method,fits,levels){nd<-data.frame(method=factor(method,levels=levels));hh<-sapply(names(fits),function(v){f<-fits[[v]];mu<-as.numeric(predict(f,nd,type='lp'));pmax(0,diff(H(age+0:12,mu,f$scale,families[[v]])))})
 total<-rowSums(hh);s<-c(1,exp(-cumsum(total)))[1:12];sum(s*(-expm1(-total))*ifelse(total>0,hh[,'actionable']/total,0))}
run<-function(split){
 methods<-c(base_methods,if(split)c('Male condoms','LAM'));l<-land;l$method<-mg(l$method_code,split);cur<-current;cur$method<-mg(cur$method_code,split)
 af<-fit_data(split);fits<-if(!split)pooledfits else setNames(lapply(names(families),function(v)fit_one(af,v,families[[v]])),names(families))
 historical<-list();fractions<-list();support<-list()
 for(m in methods)for(b in 1:8){
  selected<-if(b==8)c(6L,7L)else b;z<-which(l$method==m&l$bin%in%selected)
  while(length(unique(l$episode[z]))<25L&&length(selected)<7){selected<-sort(unique(pmax(1L,pmin(7L,c(selected,selected-1L,selected+1L)))));z<-which(l$method==m&l$bin%in%selected)}
  stopifnot(length(z)>0)
  # Adjacent duration pooling is a support guard, not a precision guarantee.
  historical[[paste(m,b)]]<-mean_design(l[z,],c('gross','net'))
  q<-which(l$method==m&l$bin%in%(if(b==8)c(6L,7L)else b)&l$gross==1)
  n<-length(unique(l$episode[q]));level<-'method and duration'
  if(n<10){q<-which(l$method==m&l$gross==1);n<-length(unique(l$episode[q]));level<-'method, durations pooled'}
  if(n<10){q<-which(l$gross==1);n<-length(unique(l$episode[q]));level<-'all reversible methods pooled'}
  stopifnot(length(q)>0);fractions[[paste(m,b)]]<-mean_design(l[q,],'net')
  support[[paste(m,b)]]<-data.frame(method=m,bin=b,historical_episodes=length(unique(l$episode[z])),expanded_duration=!identical(selected,if(b==8)c(6L,7L)else b),switching_ending_episodes=n,switching_pool=level,minimum_duration_episodes=25L,meets_duration_guard=length(unique(l$episode[z]))>=25L)
 }
 cur$firstyear<-cur$historical_gross<-cur$historical_net<-cur$aft_gross<-cur$aft_net<-NA_real_
 for(m in methods){
  d<-e[mg(e$method_code,split)==m,];s<-1;p<-0
  for(t in 1:12){at<-d$entry<t&d$exposure>=t;den<-sum(d$wt[at]);stopifnot(den>0);end<-at&d$discontinued&d$exposure==t;p<-p+s*sum(d$wt[end&d$reason_code%in%action])/den;s<-s*(1-sum(d$wt[end])/den)}
  for(b in 1:8){ix<-which(cur$method==m&cur$bin==b);if(!length(ix))next;hp<-historical[[paste(m,b)]];cur$firstyear[ix]<-p;cur$historical_gross[ix]<-hp[1];cur$historical_net[ix]<-hp[2]
   for(age in unique(cur$elapsed[ix])){
    ii<-ix[cur$elapsed[ix]==age];proxy<-country=='DRC'&&m=='IUD';ff<-if(proxy)pooledfits else fits;ll<-levels(if(proxy)pooldata$method else af$method);mm<-if(proxy)'Other modern'else m
    v<-next12(age,mm,ff,ll);cur$aft_gross[ii]<-v;cur$aft_net[ii]<-v*fractions[[paste(m,b)]]
   }
  }
 }
 vars<-c('firstyear','historical_gross','aft_gross','historical_net','aft_net');stopifnot(!anyNA(cur[,vars]),all(as.matrix(cur[,vars])>=0),all(as.matrix(cur[,vars])<=1),all(cur$historical_net<=cur$historical_gross+1e-12),all(cur$aft_net<=cur$aft_gross+1e-12))
 rows<-list()
 for(m in methods){ii<-which(cur$method==m);p<-mean_design(cur[ii,],vars);n<-stock(m,split)
  for(k in seq_along(vars))rows[[length(rows)+1L]]<-data.frame(country=country,grouping=if(split)'Condoms and LAM separate'else'Other reversible pooled',method=m,approach=vars[k],current_users=n,probability=p[k],users=n*p[k],pp=100*n*p[k]/w25)
 }
 rows<-do.call(rbind,rows);write.csv(rows,file.path(out,if(split)'separated_methods.csv'else'pooled_methods.csv'),row.names=FALSE)
 support<-do.call(rbind,support);write.csv(support,file.path(out,if(split)'separated_support.csv'else'pooled_support.csv'),row.names=FALSE)
 saveRDS(list(fits=fits,families=families,probabilities=cur,results=rows),file.path(out,if(split)'separated_point.rds'else'pooled_point.rds'))
 totals<-aggregate(cbind(users,pp)~country+grouping+approach,rows,sum)
 cat('\n',country,if(split)'SEPARATED'else'POOLED','families',paste(families,collapse=','),'\n');print(totals,row.names=FALSE)
 totals
}
pooled<-run(FALSE);separate<-run(TRUE);all<-rbind(pooled,separate)
write.csv(all,file.path(out,'overall_comparison.csv'),row.names=FALSE)
# The comparison is restricted to aggregate actionable endings. It does not
# disaggregate the five causes or refit the separate modeled-transition model.
# Reported LAM durations are calendar reports, not verified clinical eligibility.
lam <- data.frame(current_LAM_users=nrow(current[current$method_code==13L,]),
 LAM_users_over_six_reported_months=sum(current$method_code==13L & current$elapsed>6L),
 permanent_users=unname(dhs_percentage(ir_design,as.numeric(ir$v313)==3 & as.numeric(ir$v312)%in%c(6L,7L))['percent'])*w24/100,
 outcome_WRA=w25,minimum_duration_episodes=25L)
write.csv(lam,file.path(out,'method_sensitivity_context.csv'),row.names=FALSE)

reference<-readRDS(file.path(root,'output/survey_planning/planning_point.rds'))
stopifnot(abs(100*unname(dhs_percentage(ir_design,as.numeric(ir$v313)==3)['percent'])/100-reference$mcpr)<1e-10)
cat('Complete. Outcome WRA',w25,'current mCPR unchanged',reference$mcpr,'\n')
)----------------------")


REVISION_HELPERS <- setNames(lapply(REVISION_HELPER_NAMES, function(name) MODULES[[name]]$code), REVISION_HELPER_NAMES)

MODULES[["analysis_validate_transitions.R"]] <- list(language="R", packaged_sha256="66b25437034f2bb888a6640a4bdf7e2158bfbef84a118bbe93dcace7a61c2f6a", args=character(0), code=r"----------------------(# DHS complex survey design for this module.
.dhs_root <- Sys.getenv('NIGERIA_PROJECT_ROOT')
if (!nzchar(.dhs_root)) {
 .dhs_file <- sub('^--file=','',grep('^--file=',commandArgs(FALSE),value=TRUE)[1])
 .dhs_root <- dirname(dirname(normalizePath(.dhs_file)))
}
source(file.path(.dhs_root,'Code','dhs_survey_tools.R'),local=TRUE)
dhs_set_context(country='Nigeria',root=.dhs_root)
#!/usr/bin/env Rscript
# Held-out PSU checks of modern use following actionable original-method endings.
a<-commandArgs(TRUE);stopifnot(length(a)==3);root<-a[1];fitdir<-a[2];out<-a[3];dir.create(out,recursive=TRUE,showWarnings=FALSE)
suppressPackageStartupMessages({library(data.table);library(jsonlite)})
ir<-readRDS(file.path(root,'Data/raw_dhs_ir/NG2024DHS__NGIR8BDT__IR_raw.rds'));cal<-readRDS(file.path(root,'Data/Derived/nigeria_2024_calendar_events.rds'))
methods<-c('Injectables','Implants','Pill','IUD','Other modern');causes<-c('Method failure','Wanted more effective method','Changes in menstrual bleeding','Other side effects/health','Access/cost/convenience');codes<-list(1L,7L,15L,c(4L,5L),c(6L,8L,10L));action<-unlist(codes)
modern<-c(1L,2L,3L,5L,6L,7L,11L,13L,14L,15L,17L,18L,19L,20L);modern<-setdiff(modern,c(6L,7L));endpoint_modern<-c(modern,6L,7L,16L)
method_group<-function(x)ifelse(x==3,'Injectables',ifelse(x==11,'Implants',ifelse(x==1,'Pill',ifelse(x==2,'IUD','Other modern'))));cause_group<-function(x){z<-rep(NA_integer_,length(x));for(j in 1:5)z[x%in%codes[[j]]]<-j;z}
source(file.path(root,'Code/transition_model.R'))
point<-readRDS(file.path(fitdir,'transition_point_fits.rds'))
diagnostics<-rbindlist(lapply(states,function(s){f<-point$transitions[[s]];check<-fit_transition(follow[follow$current_state==s,],s,f$family,.1,start=f$par,check_gradient=TRUE);data.table(state=s,family=f$family,boundary=f$boundary,convergence=f$convergence,max_gradient_error=check$max_gradient_error)}));write.csv(diagnostics,file.path(out,'transition_fit_diagnostics.csv'),row.names=FALSE)
set.seed(20261110);frame<-unique(data.table(psu=as.integer(ir$v021),stratum=as.integer(ir$v022)));frame[,fold:=sample(rep(1:5,length.out=.N)),by=stratum]
initial<-merge(initial,frame[,.(psu,fold)],by='psu');follow<-merge(follow,frame[,.(psu,fold)],by='psu');histories<-merge(histories,frame[,.(psu,fold)],by='psu');validation<-list()
for(k in 1:5){cat('Held-out fold',k,'\n');flush.console();fit<-fit_models(initial[initial$fold!=k,],follow[follow$fold!=k,],'selected',.1);test<-histories[histories$fold==k & histories$horizon%in%c(1L,3L,6L,12L),];gr<-unique(test[,.(method,cause,end_duration,duration_log)]);gr$gid<-seq_len(nrow(gr));pred<-merge(gr,endpoint_prob(fit,gr,12L),by='gid');v<-merge(test,pred,by=c('method','cause','end_duration','duration_log','horizon'));v[,observed:=as.numeric(observed_state%in%c('Modern','Permanent'))];validation[[k]]<-v[,.(horizon,wt,observed,p_modern,fold)]}
v<-rbindlist(validation);c<-v[,.(observations=.N,observed_modern=sum(wt*observed)/sum(wt),predicted_modern=sum(wt*p_modern)/sum(wt),brier=sum(wt*(observed-p_modern)^2)/sum(wt)),by=horizon];c[,difference_pp:=100*(predicted_modern-observed_modern)];write.csv(c,file.path(out,'held_out_calibration.csv'),row.names=FALSE);print(c)

checks<-jsonlite::fromJSON(file.path(fitdir,'transition_fit_metadata.json'),simplifyVector=FALSE)
checks$held_out<-lapply(seq_len(nrow(c)),function(i)as.list(c[i,]))
checks$fit_diagnostics<-lapply(seq_len(nrow(diagnostics)),function(i)as.list(diagnostics[i,]))
jsonlite::write_json(checks,file.path(fitdir,'transition_validation.json'),auto_unbox=TRUE,pretty=TRUE))----------------------")

MODULES[["analysis_all_reason_user_bridge.R"]] <- list(language="R", packaged_sha256="7001b086eadbe33a1a03c15ee0b2af56272129a21980ee1074faa1d5785b78f8", args=character(0), code=r"----------------------(# All-reason first-year illustration, reconstructed from this run's IR-derived tables.
root<-Sys.getenv('NIGERIA_PROJECT_ROOT');stopifnot(nzchar(root))
sup<-file.path(root,'output/Supporting_data')
read<-function(n)read.csv(file.path(sup,n),check.names=FALSE)
times<-read('nigeria_reversible_planning_all_reason_timepoints.csv')
reasons<-read('nigeria_reversible_planning_all_reason_reason_mix.csv')
users<-read('nigeria_current_users_by_method_and_actionable_projection.csv')
methods<-c('Injectables','Implants','Pill','IUD','Other modern')
cause_names<-reasons$reason[reasons$scope=='National']
summary<-list();causes<-list()
for(m in methods){
 u<-users[users$method==m,];t<-times[times$scope==paste0('National: ',m)&times$month==12,]
 stopifnot(nrow(u)==1L,nrow(t)==1L)
 stock<-u$current_users_2025
 summary[[m]]<-data.frame(method=m,current_users_2025=stock,
  all_reason_first_year_risk_pct=t$all_reason_pct,
  illustrative_original_method_endings=stock*t$all_reason_pct/100)
 for(ca in cause_names){d<-reasons[reasons$scope==paste0('National: ',m)&reasons$reason==ca,];stopifnot(nrow(d)==1L)
  causes[[length(causes)+1L]]<-data.frame(method=m,reason=ca,current_users_2025=stock,
    cause_specific_first_year_risk_pct=d$cause_specific_12_month_pct,
    illustrative_original_method_endings=stock*d$cause_specific_12_month_pct/100)}
}
a<-do.call(rbind,summary);b<-do.call(rbind,causes)
for(m in methods)stopifnot(abs(sum(b$illustrative_original_method_endings[b$method==m])-a$illustrative_original_method_endings[a$method==m])<1e-6)
write.csv(a,file.path(sup,'nigeria_current_users_all_reason_projection.csv'),row.names=FALSE)
write.csv(b,file.path(sup,'nigeria_current_users_all_reason_by_cause.csv'),row.names=FALSE))----------------------")

if (sys.nframe() == 0L) {
  main()
  quit(save='no',status=0L,runLast=FALSE)
} else if (isTRUE(RUN_ON_SOURCE)) {
  report_results <- launch_report()
}
