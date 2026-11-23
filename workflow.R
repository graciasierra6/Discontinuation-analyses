# Shared launch and dependency setup for CLI and RStudio entry points.
# All data/output locations are caller supplied or resolved at runtime.

dhs_script_file <- function() {
  frames<-rev(sys.frames())
  for(frame in frames)if(is.character(frame$ofile)&&length(frame$ofile)==1L&&file.exists(frame$ofile))
    return(normalizePath(frame$ofile,winslash='/',mustWork=TRUE))
  args<-grep('^--file=',base::commandArgs(FALSE),value=TRUE)
  if(length(args)){
    file<-gsub('~+~',' ',sub('^--file=','',args[1]),fixed=TRUE)
    if(file.exists(file))return(normalizePath(file,winslash='/',mustWork=TRUE))
  }
  stop('Open the saved script and use Source, or run Rscript with its filename.',call.=FALSE)
}

dhs_repo_root <- function(script) {
  directory<-dirname(normalizePath(script,winslash='/',mustWork=TRUE))
  for(i in 1:6){
    if(all(file.exists(file.path(directory,c('build_reports.R','workflow.R','requirements.txt')))))return(directory)
    parent<-dirname(directory);if(identical(parent,directory))break;directory<-parent
  }
  stop('Keep the complete extracted repository together. The root build_reports.R, workflow.R and requirements.txt are required.',call.=FALSE)
}

dhs_install_packages <- function(packages) {
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
  missing<-packages[!vapply(packages,requireNamespace,FALSE,quietly=TRUE)]
  if(length(missing))utils::install.packages(missing,lib=install_library,repos='https://cloud.r-project.org')
  absent<-packages[!vapply(packages,requireNamespace,FALSE,quietly=TRUE)]
  if(length(absent))stop('Packages could not be installed: ',paste(absent,collapse=', '),
    '. Check the R package system requirements.',call.=FALSE)
  suppressPackageStartupMessages(invisible(lapply(packages,function(p)library(p,character.only=TRUE))))
}

# Preserve the environment-specific executable, even when it is a symlink.
dhs_python_launcher <- function(python) {
  file.path(normalizePath(dirname(python),winslash='/',mustWork=TRUE),basename(python))
}

dhs_python <- function(repo,python='auto') {
  requirements<-readLines(file.path(repo,'requirements.txt'),warn=FALSE)
  requirements<-trimws(requirements[!grepl('^[[:space:]]*(#|$)',requirements)])
  if(identical(python,'auto')||!nzchar(python)){
    dhs_install_packages('reticulate')
    if(utils::packageVersion('reticulate')<'1.41.0'){
      utils::install.packages('reticulate',repos='https://cloud.r-project.org')
      stop('Reticulate was updated. Restart R and run the same script again.',call.=FALSE)
    }
    # A clean R child avoids an unrelated Python already initialized in RStudio.
    directory<-tempfile('report-dependencies-');dir.create(directory)
    on.exit(unlink(directory,recursive=TRUE),add=TRUE)
    helper<-file.path(directory,'prepare_python.R');selected<-file.path(directory,'python.txt')
    writeLines(c(
      "suppressPackageStartupMessages(library(reticulate))",
      "args<-commandArgs(TRUE)",
      "requirements<-readLines(args[1],warn=FALSE)",
      "requirements<-trimws(requirements[!grepl('^[[:space:]]*(#|$)',requirements)])",
      "Sys.setenv(RETICULATE_PYTHON='managed',RETICULATE_USE_MANAGED_VENV='yes')",
      "reticulate::py_require(requirements,python_version='3.12')",
      "invisible(reticulate::import('sys',convert=FALSE))",
      "writeLines(reticulate::py_config()$python,args[2])"),helper)
    cat('Preparing the report renderer and its pinned Python packages. First setup needs internet access.\n')
    status<-system2(file.path(R.home('bin'),'Rscript'),shQuote(c(helper,file.path(repo,'requirements.txt'),selected)))
    if(status!=0L||!file.exists(selected))stop('Automatic Python setup failed. Check internet access, restart R and retry. An existing prepared interpreter can also be supplied with --python or PYTHON.',call.=FALSE)
    python<-readLines(selected,warn=FALSE)[1]
  } else {
    found<-Sys.which(python)
    if(nzchar(found))python<-unname(found)
    if(!file.exists(python))stop('The supplied Python executable was not found. Use python="auto" for automatic setup.',call.=FALSE)
  }
  # Fail before estimation when the selected environment cannot render the reports.
  # JSON avoids mixing R vector syntax with Python syntax.
  dhs_install_packages('jsonlite')
  code<-paste0("import importlib.metadata as m,sys,json; assert sys.version_info >= (3,10); ",
    "req=json.loads(",encodeString(jsonlite::toJSON(requirements,auto_unbox=FALSE),quote='\"'),
    "); bad=[r for r in req if m.version(r.split('==')[0]) != r.split('==')[1]]; ",
    "assert not bad, 'Package versions differ from requirements.txt: '+', '.join(bad)")
  status<-system2(python,shQuote(c('-c',code)),stdout=FALSE)
  if(status!=0L)stop('The selected Python does not match requirements.txt. Omit --python or set PYTHON=auto for automatic setup.',call.=FALSE)
  # Keep the environment's launcher. Resolving its final symlink can select
  # the base interpreter and discard the environment's installed packages.
  dhs_python_launcher(python)
}

dhs_soffice <- function(soffice=Sys.getenv('SOFFICE',unset='')) {
  candidates<-c(soffice,unname(Sys.which(c('soffice','libreoffice'))))
  if(.Platform$OS.type=='windows')for(k in c('ProgramFiles','ProgramFiles(x86)')){
    base<-Sys.getenv(k,unset='');if(nzchar(base))candidates<-c(candidates,file.path(base,'LibreOffice','program','soffice.exe'))
  }
  if(Sys.info()[['sysname']]=='Darwin'&&nzchar(Sys.which('mdfind'))){
    apps<-tryCatch(system2('mdfind',shQuote("kMDItemCFBundleIdentifier == 'org.libreoffice.script'"),stdout=TRUE,stderr=FALSE),error=function(e)character())
    candidates<-c(candidates,file.path(apps,'Contents','MacOS','soffice'))
  }
  candidates<-unique(candidates[nzchar(candidates)])
  for(candidate in candidates){found<-Sys.which(candidate);if(nzchar(found))candidate<-unname(found)
    if(file.exists(candidate)&&!dir.exists(candidate))return(normalizePath(candidate,winslash='/',mustWork=TRUE))}
  stop('DRC needs LibreOffice to reproduce its slide-preview gallery. Install LibreOffice, restart R, and retry. If it is not detected, supply its executable through SOFFICE or --soffice. See README.md.',call.=FALSE)
}

dhs_private_output <- function(repo,label,output='') {
  if(!nzchar(output))output<-file.path(dirname(repo),'discontinuation_results',
    paste0(tolower(label),'_',format(Sys.time(),'%Y%m%d_%H%M%S')))
  if(file.exists(output)&&!dir.exists(output))stop('The output location is a file; choose a new folder.',call.=FALSE)
  if(dir.exists(output)&&length(list.files(output,all.files=TRUE,no..=TRUE)))
    stop('The output folder is not empty. Select a new folder so previous results are preserved.',call.=FALSE)
  if(!dir.create(output,recursive=TRUE,showWarnings=FALSE)&&!dir.exists(output))
    stop('Cannot create the results folder. Set OUTPUT_DIRECTORY to a writable private folder outside the repository.',call.=FALSE)
  output<-normalizePath(output,winslash='/',mustWork=TRUE)
  repo<-normalizePath(repo,winslash='/',mustWork=TRUE)
  if(identical(tolower(output),tolower(repo))||startsWith(tolower(output),paste0(tolower(repo),'/')))
    stop('Keep results and restricted derived records outside the repository. Set OUTPUT_DIRECTORY to a private location.',call.=FALSE)
  output
}

dhs_choose_ir <- function(country,input='',choose=file.choose) {
  if(!nzchar(input)){
    cat('Select the original women\'s IR .dta file for ',country,'.\n',sep='')
    input<-tryCatch(choose(),error=function(e)stop('No IR file selected. Source the script again to retry.',call.=FALSE))
  }
  if(length(input)!=1L||is.na(input)||!nzchar(input)||!file.exists(input))stop('Select an existing IR file.',call.=FALSE)
  if(tolower(tools::file_ext(input))!='dta')stop('Select the extracted Stata IR (.dta), not the downloaded ZIP or an HTML report.',call.=FALSE)
  normalizePath(input,winslash='/',mustWork=TRUE)
}

dhs_run_report <- function(script,country,ir_file='',output='',cores=1L,python='auto',
                            reference_policy='strict',open_report=TRUE,
                            run_command=system2,choose=file.choose) {
  repo<-dhs_repo_root(script)
  cat('\n',country,': preparing the national HTML report.\n',sep='')
  input<-dhs_choose_ir(country,ir_file,choose)
  output<-dhs_private_output(repo,country,output)
  rscript<-file.path(R.home('bin'),'Rscript')
  args<-c(file.path(repo,'build_reports.R'),paste0('--country=',country),paste0('--ir-file=',input),
    paste0('--output-dir=',output),paste0('--cores=',cores),paste0('--python=',python),
    paste0('--reference-policy=',reference_policy))
  cat('Calendar reconstruction, models and bootstrap refits can take several hours. Progress appears below.\n')
  status<-run_command(rscript,shQuote(args))
  report<-file.path(output,'output',paste0(country,'_discontinuation_analysis.html'))
  if(status!=0L){
    candidate<-file.path(output,'output',paste0(country,'_discontinuation_analysis_rebuilt.html'))
    if(file.exists(candidate))cat('An HTML candidate exists, but report/reference validation did not pass. Review output/validation before sharing it.\n')
    stop('The build stopped. See the current stage and the private output/logs folder; approved reports were not overwritten.',call.=FALSE)
  }
  if(!file.exists(report))stop('The build returned without its expected HTML report.',call.=FALSE)
  numbers<-file.path(output,'results','analysis_results.rds')
  if(file.exists(numbers))assign('analysis_results',readRDS(numbers),envir=.GlobalEnv)
  cat('\nFinished. The HTML is in the results folder under output/. Numerical CSVs are under results/.\n')
  if(open_report&&interactive())utils::browseURL(report)
  invisible(list(country=country,html=report,output_directory=output))
}

# The extensions report uses all three national IR files.
dhs_run_extensions_ui <- function(script,output='',python='auto',target='all',open_report=TRUE,
                                   run_command=system2,choose=file.choose) {
  repo<-dhs_repo_root(script)
  input<-setNames(vapply(c('Ethiopia','Nigeria','DRC'),function(c)
    dhs_choose_ir(c,Sys.getenv(paste0(toupper(c),'_IR_FILE'),unset=''),choose),''),c('Ethiopia','Nigeria','DRC'))
  output<-dhs_private_output(repo,'extensions',output)
  args<-c(script,paste0('--output-dir=',output),paste0('--python=',python),paste0('--target=',target),
    paste0('--',tolower(names(input)),'-ir=',input))
  cat('Rebuilding extensions and/or maps from the three supplied IR files.\n')
  status<-run_command(file.path(R.home('bin'),'Rscript'),shQuote(args))
  if(status!=0L)stop('Extensions stopped; existing reports were not changed. See the stage message.',call.=FALSE)
  reports<-list.files(output,pattern='[.]html$',recursive=TRUE,full.names=TRUE)
  if(!length(reports))stop('No extensions HTML was produced.',call.=FALSE)
  if(open_report&&interactive())utils::browseURL(reports[1])
  invisible(list(output_directory=output,html=reports))
}

dhs_state_preview <- function(output,state) {
  escape<-function(x){x<-gsub('&','&amp;',x,fixed=TRUE);x<-gsub('<','&lt;',x,fixed=TRUE);gsub('>','&gt;',x,fixed=TRUE)}
  tables<-sort(list.files(file.path(output,'tables'),pattern='[.]csv$',full.names=TRUE))
  body<-character()
  for(file in tables){
    tab<-read.csv(file,header=FALSE,check.names=FALSE,colClasses='character',na.strings=NULL)
    rows<-vapply(seq_len(nrow(tab)),function(i){cell<-if(i==1L)'th'else'td';
      paste0('<tr>',paste0('<',cell,'>',escape(as.character(tab[i,])),'</',cell,'>',collapse=''),'</tr>')},'')
    body<-c(body,paste0('<section><h2>',escape(tools::file_path_sans_ext(basename(file))),'</h2><div class="table"><table>',paste(rows,collapse=''),'</table></div></section>'))
  }
  figures<-list.files(file.path(output,'figures'),pattern='[.]svg$',full.names=TRUE)
  for(file in figures){svg<-paste(readLines(file,warn=FALSE),collapse='\n');svg<-sub('^[\\s\\S]*?(<svg\\b)','\\1',svg,perl=TRUE)
    body<-c(body,paste0('<section><h2>',escape(gsub('_',' ',tools::file_path_sans_ext(basename(file)))),'</h2>',svg,'</section>'))}
  title<-paste(state,'discontinuation: numerical results and figures')
  destination<-file.path(output,paste0(state,'_analysis_results.html'))
  writeLines(paste0('<!doctype html><html><head><meta charset="utf-8"><title>',escape(title),'</title><style>body{font:16px Arial,sans-serif;color:#173F59;background:#f7f5ef;max-width:1200px;margin:40px auto;padding:0 24px}h1{border-top:4px solid #DA9A25;padding-top:20px}section{background:white;padding:24px;margin:24px 0;border-radius:8px}.table{overflow-x:auto}table{border-collapse:collapse;width:100%;font-size:14px}th{background:#173F59;color:white}td,th{padding:10px;text-align:left;border-bottom:1px solid #ddd}svg{width:100%;height:auto}</style></head><body><h1>',escape(title),'</h1><p>Fresh state-specific estimates from the Nigeria 2024 Individual Recode. The tables retain their stated definitions, assumptions and sample warnings. This results gallery is separate from the approved combined three-state report.</p>',paste(body,collapse='\n'),'</body></html>'),destination,useBytes=TRUE)
  destination
}

dhs_run_state_ui <- function(script,state,ir_file='',output='',cores=1L,open_report=TRUE,
                              run_command=system2,choose=file.choose) {
  repo<-dhs_repo_root(script)
  input<-dhs_choose_ir('Nigeria 2024',ir_file,choose)
  output<-dhs_private_output(repo,state,output)
  args<-c(script,paste0('--ir-file=',input),paste0('--output-dir=',output),paste0('--cores=',cores),'--no-cache')
  cat('Rebuilding ',state,' estimates, tables and figures. Bootstrap refits can take hours.\n',sep='')
  status<-run_command(file.path(R.home('bin'),'Rscript'),shQuote(args))
  if(status!=0L)stop('The state analysis stopped; see the stage message.',call.=FALSE)
  report<-dhs_state_preview(output,state)
  if(open_report&&interactive())utils::browseURL(report)
  invisible(list(state=state,html=report,output_directory=output))
}

# Adapt only execution mechanics; statistical formulas, cohorts and seeds stay intact.
dhs_portable_source <- function(code,language='R') {
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
