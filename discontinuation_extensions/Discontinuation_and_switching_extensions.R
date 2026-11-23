#!/usr/bin/env Rscript
# Discontinuation and switching extensions
# Original IR inputs: Ethiopia DHS 2024–25 ETIR8A, Nigeria DHS 2024 NGIR8B,
# and DRC DHS 2023–24 CDIR81; all women ages 15–49.
# Monthly use/pregnancy vcal_1 and reasons vcal_2 are reconstructed as episodes.
# Weight v005/1e6, PSU v021 and stratum v022 retain the complex survey design.
# Public analysis/rendering support is version-pinned and downloaded if absent.
# IR microdata are selected by the user and are never obtained from GitHub.

OUTPUT_DIRECTORY <- Sys.getenv('DHS_ANALYSIS_OUTPUT',unset='')
OPEN_REPORT <- TRUE
RUN_ON_SOURCE <- interactive() && !tolower(Sys.getenv('DHS_AUTO_RUN',unset='true')) %in% c('false','no','0')
ENTRY_SCRIPT <- local({
  paths<-as.character(unlist(lapply(sys.frames(),function(f)if(is.character(f$ofile))f$ofile else character()),use.names=FALSE))
  paths<-paths[file.exists(paths)]
  if(length(paths))normalizePath(tail(paths,1L),winslash="/",mustWork=TRUE)else{
    arg<-grep("^--file=",base::commandArgs(FALSE),value=TRUE)
    if(length(arg))gsub("~+~"," ",sub("^--file=","",arg[1]),fixed=TRUE)else ""
  }
})
REQUIRED_R_PACKAGES <- c('digest','grid','haven','jsonlite','MASS','nnet','stats','survey','survival','svglite','tools','reticulate')
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

launch_report <- function(script=ENTRY_SCRIPT,output=OUTPUT_DIRECTORY,open_report=OPEN_REPORT) {
  setup_analysis_packages()
  startup<-new.env(parent=environment());eval(parse(text=STANDALONE_SUPPORT),startup)
  startup$dhs_named_extension(script,"Discontinuation_and_switching_extensions.html",target="extensions",output=output,open_report=open_report)
}
if(sys.nframe()==0L){
  args<-commandArgs(TRUE)
  if('--help'%in%args){cat('Open this file in RStudio and click Source. Or supply runtime IR/output environment variables and run it with Rscript. See README.md.\n')}else report_results<-launch_report()
}else if(isTRUE(RUN_ON_SOURCE))report_results<-launch_report()
