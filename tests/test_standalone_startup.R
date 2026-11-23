#!/usr/bin/env Rscript
# Tests isolated report entry points with synthetic inputs and mocked model runs.
# The first run downloads the pinned public runtime if it is not already cached.
arg<-sub('^--file=','',grep('^--file=',commandArgs(FALSE),value=TRUE)[1])
arg<-gsub('~+~',' ',arg,fixed=TRUE)
repo<-dirname(dirname(normalizePath(arg,winslash='/')))
source(file.path(repo,'standalone_support.R'))
stage<-tempfile('standalone-test-');dir.create(stage)
variables<-c('DHS_AUTO_RUN','DHS_IR_FILE','DHS_ANALYSIS_OUTPUT','ETHIOPIA_IR_FILE','NIGERIA_IR_FILE','DRC_IR_FILE')
before<-Sys.getenv(variables,unset=NA_character_)
restore<-function(){
  for(k in names(before))if(is.na(before[[k]]))Sys.unsetenv(k)else do.call(Sys.setenv,setNames(list(before[[k]]),k))
  unlink(stage,recursive=TRUE)
}
tryCatch({
  Sys.unsetenv(variables)
  dummy<-file.path(stage,'input.dta');writeLines('synthetic input; model run is mocked',dummy)
  relative<-c(paste0(c('Ethiopia','Nigeria','DRC'),'_analysis/',c('Ethiopia','Nigeria','DRC'),'_final_html_analysis.R'),
    'discontinuation_extensions/Discontinuation_and_switching_extensions.R',
    'discontinuation_extensions/Modern_method_discontinuation_maps.R',
    'discontinuation_extensions/Return_and_continuation_analysis.R')
  # Every independently distributed entry point carries the same startup code.
  scripts<-list.files(repo,pattern='[.]R$',recursive=TRUE,full.names=TRUE)
  embedded<-0L
  for(file in scripts){
    expressions<-as.list(parse(file))
    hit<-Filter(function(x)is.call(x)&&identical(x[[1]],as.name('<-'))&&
      identical(x[[2]],as.name('STANDALONE_SUPPORT')),expressions)
    if(length(hit)){
      stopifnot(length(hit)==1L,identical(hit[[1]][[3]],paste0(paste(readLines(file.path(repo,'standalone_support.R'),warn=FALSE),collapse='\n'),'\n')))
      embedded<-embedded+1L
    }
  }
  stopifnot(embedded==7L)
  current_extension<-new.env(parent=globalenv())
  sys.source(file.path(repo,'discontinuation_extensions/run_analysis.R'),current_extension)
  for(i in seq_along(relative)){
    directory<-file.path(stage,paste0('entry-',i));dir.create(directory)
    script<-file.path(directory,basename(relative[i]));file.copy(file.path(repo,relative[i]),script)
    stopifnot(dhs_local_report_root(script)=='')
    runtime<-dhs_report_runtime(script)
    stopifnot(dhs_runtime_valid(runtime),
      identical(runtime,dhs_report_runtime(script,download=function(...)stop('Valid cache was not reused'))))
    if(i==4L){pinned_extension<-new.env(parent=globalenv());sys.source(file.path(runtime,'discontinuation_extensions/run_analysis.R'),pinned_extension);stopifnot(identical(current_extension$EXTENSION_FILES,pinned_extension$EXTENSION_FILES))}
    output<-file.path(stage,paste0('output-',i));Sys.setenv(DHS_AUTO_RUN='true',DHS_ANALYSIS_OUTPUT=output)
    e<-new.env(parent=globalenv());interactive_calls<-0L;choices<-0L;commands<-list()
    e$interactive<-function(){interactive_calls<<-interactive_calls+1L;interactive_calls==1L}
    e$file.choose<-function(){choices<<-choices+1L;dummy}
    e$system2<-function(command,args,...){
      clean<-gsub("^['\"]|['\"]$",'',args);commands[[length(commands)+1L]]<<-clean
      if(i<=3L){
        country<-c('Ethiopia','Nigeria','DRC')[i]
        stopifnot(paste0('--country=',country)%in%clean)
        dispatched<-file.path(dirname(clean[1]),paste0(country,'_analysis'),paste0(country,'_final_html_analysis.R'))
        stopifnot(identical(readBin(dispatched,'raw',file.info(dispatched)$size),readBin(script,'raw',file.info(script)$size)))
        dir.create(file.path(output,'output'),recursive=TRUE)
        dir.create(file.path(output,'results'))
        writeLines('<html><body>synthetic report</body></html>',file.path(output,'output',paste0(country,'_discontinuation_analysis.html')))
        saveRDS(list(synthetic=TRUE),file.path(output,'results/analysis_results.rds'))
      }else{
        target<-if(i==5L)'maps'else'extensions'
        stopifnot(paste0('--target=',target)%in%clean,
          sum(grepl('^--(ethiopia|nigeria|drc)-ir=',clean))==3L)
        for(name in c('Discontinuation_and_switching_extensions.html','Modern_method_discontinuation_maps.html','Return_and_continuation_same_cohort_preview.html'))
          writeLines('<html><body>synthetic report</body></html>',file.path(output,name))
      }
      0L
    }
    source(script,local=e)
    if(i<=3L){
      country<-c('Ethiopia','Nigeria','DRC')[i]
      pinned<-new.env(parent=globalenv())
      sys.source(file.path(runtime,paste0(country,'_analysis'),paste0(country,'_final_html_analysis.R')),pinned)
      stopifnot(identical(e$MODULES,pinned$MODULES),identical(e$EXTERNAL_INPUTS,pinned$EXTERNAL_INPUTS),identical(e$REPORT_FILES,pinned$REPORT_FILES))
    }
    stopifnot(length(commands)==1L,choices==if(i<=3L)1L else 3L,file.exists(e$report_results$html))
    cat(basename(script),': one-file Source, automatic public resources, input selection and HTML dispatch pass.\n')
  }
},finally=restore())
