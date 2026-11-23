#!/usr/bin/env Rscript
# Workflow tests use synthetic files; no restricted survey data are required.
arg<-sub('^--file=','',grep('^--file=',commandArgs(FALSE),value=TRUE)[1])
arg<-gsub('~+~',' ',arg,fixed=TRUE)
repo<-dirname(dirname(normalizePath(arg,winslash='/')))
source(file.path(repo,'workflow.R'))
stage<-tempfile('workflow-test-');dir.create(stage)
original_environment<-Sys.getenv(c('DHS_IR_FILE','DHS_ANALYSIS_OUTPUT','DHS_AUTO_RUN','DHS_ANALYSIS_CORES','ETHIOPIA_IR_FILE','NIGERIA_IR_FILE','DRC_IR_FILE'),unset=NA_character_)
restore<-function(){for(k in names(original_environment))if(is.na(original_environment[[k]]))Sys.unsetenv(k)else do.call(Sys.setenv,setNames(list(original_environment[[k]]),k));unlink(stage,recursive=TRUE)}
tryCatch({
  fake_ir<-file.path(stage,'input.dta');writeBin(charToRaw('synthetic fixture'),fake_ir)
  if(.Platform$OS.type!='windows'){
    dir.create(file.path(stage,'base'));dir.create(file.path(stage,'environment'))
    base_python<-file.path(stage,'base/python');writeLines('synthetic executable',base_python)
    launcher<-file.path(stage,'environment/python');stopifnot(file.symlink(base_python,launcher))
    stopifnot(basename(dirname(dhs_python_launcher(launcher)))=='environment',
              !identical(dhs_python_launcher(launcher),normalizePath(launcher)))
  }
  for(country in c('Ethiopia','Nigeria','DRC')){
    output<-file.path(stage,paste0(country,' results'))
    Sys.unsetenv('DHS_IR_FILE');Sys.setenv(DHS_ANALYSIS_OUTPUT=output,DHS_AUTO_RUN='true')
    entry<-file.path(repo,paste0(country,'_analysis'),paste0(country,'_final_html_analysis.R'))
    e<-new.env(parent=globalenv());calls<-list();interactive_calls<-0L;selections<-0L
    # Source must launch once in RStudio, irrespective of the working directory.
    e$interactive<-function(){interactive_calls<<-interactive_calls+1L;interactive_calls==1L}
    e$file.choose<-function(...){selections<<-selections+1L;fake_ir}
    e$system2<-function(command,args,...){
      clean<-gsub("^['\"]|['\"]$",'',args)
      stopifnot(basename(clean[1])=='build_reports.R',
                paste0('--country=',country)%in%clean,
                paste0('--ir-file=',normalizePath(fake_ir,winslash='/'))%in%clean)
      calls[[length(calls)+1L]]<<-clean
      dir.create(file.path(output,'output'),recursive=TRUE)
      dir.create(file.path(output,'results'))
      writeLines('<!doctype html><html><body>test result</body></html>',
                 file.path(output,'output',paste0(country,'_discontinuation_analysis.html')))
      saveRDS(list(test=TRUE),file.path(output,'results/analysis_results.rds'))
      0L
    }
    prior<-getwd();setwd(stage)
    tryCatch(source(entry,local=e,echo=FALSE),finally=setwd(prior))
    stopifnot(length(calls)==1L,selections==1L,
      identical(e$ENTRY_SCRIPT,normalizePath(entry,winslash='/')),
      file.exists(e$report_results$html),isTRUE(analysis_results$test))
    rm(analysis_results,envir=.GlobalEnv)
    # Expanded source is deterministic and safe to reuse across CLI stages.
    runtime<-file.path(stage,paste0(country,' runtime with spaces'))
    e$extract_sources(runtime)
    before<-readLines(file.path(runtime,'Code/numerical_source_manifest.tsv'))
    e$extract_sources(runtime)
    stopifnot(identical(before,readLines(file.path(runtime,'Code/numerical_source_manifest.tsv'))))
    # Windows serial and macOS parallel scheduling retain per-replicate seeds.
    worker<-new.env(parent=globalenv())
    eval(parse(text=e$portable_runtime_source('')),worker)
    Sys.setenv(DHS_ANALYSIS_CORES='2')
    draw<-function(i){set.seed(417+i);rnorm(4)}
    expected<-lapply(1:5,draw)
    worker$.Platform<-list(OS.type='windows')
    stopifnot(identical(worker$dhs_parallel_apply(1:5,draw,mc.cores=2L),expected))
    worker$.Platform<-base::.Platform
    stopifnot(identical(worker$dhs_parallel_apply(1:5,draw,mc.cores=2L,mc.preschedule=FALSE),expected))
    # Table indexes must resolve from results/ in both supported build layouts.
    for(layout in c('standalone','report')){
      folder<-file.path(stage,paste(country,layout))
      destination<-if(layout=='standalone')folder else file.path(folder,'results')
      project<-if(layout=='standalone')file.path(folder,'work')else folder
      dir.create(destination,recursive=TRUE)
      dir.create(file.path(project,'output/Supporting_data'),recursive=TRUE)
      write.csv(data.frame(value=1),file.path(project,'output/example.csv'),row.names=FALSE)
      write.csv(data.frame(value=2),file.path(project,'output/Supporting_data/example.csv'),row.names=FALSE)
      values<-e$export_numerical_results(project,destination,'core',0L)
      stopifnot(nrow(values$table_index)==2L,
        all(file.exists(file.path(destination,values$table_index$file))),
        !any(grepl('^(/|[A-Za-z]:)',values$table_index$file)))
    }
    cat(country,': Source launcher, input selection, CLI dispatch, output loading, repeat extraction, worker portability and relative result indexes pass.\n')
  }
  # The optional state gallery is computed from current CSVs/SVGs, not saved HTML.
  state<-file.path(stage,'state');dir.create(file.path(state,'tables'),recursive=TRUE)
  dir.create(file.path(state,'figures'))
  writeLines(c('"Method","Value"','"Pill","12.3"'),file.path(state,'tables/one.csv'))
  writeLines('<svg xmlns="http://www.w3.org/2000/svg"><text>test</text></svg>',file.path(state,'figures/one.svg'))
  html<-dhs_state_preview(state,'Kano')
  stopifnot(file.exists(html),any(grepl('12.3',readLines(html),fixed=TRUE)))
  cat('State results gallery uses the freshly exported values.\n')
  signatures<-vapply(c('Kano','Kaduna','Lagos'),function(state){
    code<-readLines(file.path(repo,'Nigeria_analysis/Kano_Kaduna_Lagos',paste0(state,'_discontinuation_analysis.R')),warn=FALSE)
    code<-sub('^REPORT_STATE <- .*$', 'REPORT_STATE <- "STATE"',code)
    code<-code[!grepl("^[[:space:]]*(#|$)",code)]
    digest::digest(paste(code,collapse="\n"),algo="sha256",serialize=FALSE)
  },'')
  stopifnot(length(unique(signatures))==1L)
  # Optional report launchers select the right inputs and dispatch their existing CLI.
  Sys.unsetenv(c('ETHIOPIA_IR_FILE','NIGERIA_IR_FILE','DRC_IR_FILE'))
  extension_output<-file.path(stage,'extensions')
  selections<-0L
  chooser<-function(){selections<<-selections+1L;fake_ir}
  extension_command<-function(command,args,...){
    clean<-gsub("^['\"]|['\"]$",'',args)
    stopifnot(sum(grepl('^--(ethiopia|nigeria|drc)-ir=',clean))==3L)
    writeLines('<html><body>synthetic extension</body></html>',file.path(extension_output,'extensions.html'))
    0L
  }
  extra<-dhs_run_extensions_ui(file.path(repo,'discontinuation_extensions/run_analysis.R'),
    output=extension_output,open_report=FALSE,run_command=extension_command,choose=chooser)
  stopifnot(selections==3L,length(extra$html)==1L)
  state_output<-file.path(stage,'state launcher')
  state_command<-function(command,args,...){
    clean<-gsub("^['\"]|['\"]$",'',args)
    stopifnot(basename(clean[1])=='Kano_discontinuation_analysis.R','--no-cache'%in%clean)
    dir.create(file.path(state_output,'tables'));dir.create(file.path(state_output,'figures'))
    writeLines(c('\"Outcome\",\"Percent\"','\"Example\",\"12.3\"'),file.path(state_output,'tables/example.csv'))
    0L
  }
  optional<-dhs_run_state_ui(file.path(repo,'Nigeria_analysis/Kano_Kaduna_Lagos/Kano_discontinuation_analysis.R'),
    state='Kano',output=state_output,open_report=FALSE,run_command=state_command,choose=chooser)
  stopifnot(file.exists(optional$html))
  cat('Optional extensions and state launchers dispatch their CLI and return the generated HTML.\n')
},finally=restore())
