#!/usr/bin/env Rscript
# Rebuild the separate three-country extensions report and interactive maps.
# Example: Rscript run_analysis.R --ethiopia-ir=data/ethiopia.dta 
#          --nigeria-ir=data/nigeria.dta --drc-ir=data/drc.dta
args <- commandArgs(TRUE)
if('--help' %in% args || !length(args)) {
  cat(paste(
    'Rebuild discontinuation extensions and maps from authorized IR files.',
    'Required: --ethiopia-ir=FILE --nigeria-ir=FILE --drc-ir=FILE',
    'Accepted inputs: original Stata .dta or lossless labelled IR .rds.',
    'Alternative inputs: ETHIOPIA_IR_FILE, NIGERIA_IR_FILE, DRC_IR_FILE.',
    'Optional: --output-dir=output --python=python3 --target=all|extensions|maps',
    'Default uncertainty: 1,999 full-frame stratified PSU bootstrap replicates.',
    'Inputs stay private; intermediate woman/episode files are temporary and removed.',
    sep='\n'),'\n')
  quit(status=if(length(args))0 else 1)
}
opt <- list('output-dir'='output',python='python3',target='all')
for(a in args) {
  if(!grepl('^--[^=]+=.+$',a)) stop('Use --name=value arguments.',call.=FALSE)
  opt[[sub('^--([^=]+)=.*$','\\1',a)]]<-sub('^--[^=]+=','',a)
}
if(!all(names(opt) %in% c('output-dir','python','target','ethiopia-ir','nigeria-ir','drc-ir')))
  stop('Unrecognized argument; see --help.',call.=FALSE)
stopifnot(opt$target %in% c('all','extensions','maps'))
script <- sub('^--file=','',grep('^--file=',commandArgs(FALSE),value=TRUE)[1])
script <- gsub('~+~',' ',script,fixed=TRUE)
root <- dirname(normalizePath(script,mustWork=TRUE))
needed <- c('haven','jsonlite','survival','digest','svglite')
missing <- needed[!vapply(needed,requireNamespace,TRUE,quietly=TRUE)]
if(length(missing))stop('Install required R packages: ',paste(missing,collapse=', '),call.=FALSE)
python <- Sys.which(opt$python)
if(!nzchar(python))stop('Supply a working Python 3 executable with --python.',call.=FALSE)
run <- function(exe,parameters,label) {
  log <- tempfile(fileext='.log');on.exit(unlink(log),add=TRUE)
  status <- system2(exe,args=vapply(parameters,shQuote,''),stdout=log,stderr=log)
  if(status!=0) {
    # Do not export a subprocess traceback containing private runtime locations.
    stop(label,' failed. No report is certified; inspect inputs and installed packages.',call.=FALSE)
  }
}
run(python,c('-c','import sys; assert sys.version_info >= (3,9)'), 'Python version check')
input <- setNames(character(3),c('Ethiopia','Nigeria','DRC'))
for(c in names(input)) {
  k<-paste0(tolower(c),'-ir');env<-paste0(toupper(c),'_IR_FILE')
  input[c]<-if(!is.null(opt[[k]]))opt[[k]]else Sys.getenv(env)
  if(!nzchar(input[c])||!file.exists(input[c]))stop('Supply an authorized ',c,' IR file.',call.=FALSE)
}
main <- function() {
  work<-tempfile('discontinuation-analysis-');dir.create(work)
  on.exit(unlink(work,recursive=TRUE),add=TRUE)
  out<-normalizePath(opt[['output-dir']],mustWork=FALSE)
  dir.create(out,recursive=TRUE,showWarnings=FALSE)
  rd<-file.path(root,'src/R');pd<-file.path(root,'src/python')
  rs<-file.path(R.home('bin'),'Rscript')
  r<-function(name,params,label)run(rs,c(file.path(rd,name),params),label)
  py<-function(name,params,label)run(python,c(file.path(pd,name),params),label)
  source(file.path(rd,'prepare_ir.R'),local=TRUE)
  results<-file.path(work,'results');switching<-file.path(work,'switching')
  figures<-file.path(work,'figures');timing<-file.path(work,'timing')
  maps<-file.path(work,'maps');aggregation<-file.path(work,'aggregation')
  for(d in c(results,switching,figures,timing,maps,aggregation))dir.create(d,recursive=TRUE)
  surveys<-c(Ethiopia='2024–25',Nigeria='2024',DRC='2023–24')
  for(c in names(input)) {
    slug<-tolower(c);priv<-file.path(work,'private',slug)
    prepare_ir(input[[c]],c,priv)
    ir<-file.path(priv,'ir.rds');ep<-file.path(priv,'episodes.rds')
    cal<-file.path(priv,'calendar.rds');res<-file.path(results,slug)
    seed<-c(Ethiopia=20261112L,Nigeria=20262112L,DRC=20263112L)[[c]]
    common<-c(paste0('--country=',c),paste0('--ir=',ir),paste0('--episodes=',ep),paste0('--seed=',seed))
    message(c,': weighted life tables and survey uncertainty.')
    r('calculate_partner_rates.R',c(common,paste0('--output=',res)),paste(c,'national rates'))
    reference<-file.path(res,'results.json')
    if(opt$target %in% c('all','extensions')) {
      r('calculate_partner_subgroups.R',c(common,paste0('--reference=',reference),paste0('--output=',res)),paste(c,'subgroups'))
      tn<-if(c=='Ethiopia')'timing.json'else paste0(slug,'_timing.json')
      r('calculate_timing.R',c(ep,file.path(timing,tn),c,surveys[c]),paste(c,'reason timing'))
      fn<-paste0(c,'_actionable_reason_timing',if(c=='Ethiopia')'_comparable'else'','.svg')
      py('render_timing.py',c(file.path(timing,tn),file.path(timing,fn),'8'),paste(c,'timing figure'))
      ref<-file.path(switching,paste0(slug,'.json'))
      reason<-file.path(switching,paste0(slug,'_reason_endpoint.json'))
      destinations<-file.path(switching,paste0(slug,'_destinations.json'))
      duration<-file.path(switching,paste0(slug,'_endpoint_duration_table.json'))
      message(c,': complete follow-up pathways and interruption summaries.')
      r('calculate_pathways.R',c(cal,c,surveys[c],ref),paste(c,'pathways'))
      r('calculate_reason_endpoint.R',c(cal,ir,ref,reason),paste(c,'reason-specific follow-up'))
      r('calculate_destinations.R',c(cal,ir,ref,destinations),paste(c,'modern destinations'))
      r('calculate_endpoint_duration.R',c(cal,ir,ref,reason,duration),paste(c,'interruption durations'))
      py('render_reason_endpoint.py',c(paste0('--input=',reason),paste0('--output-dir=',figures)),paste(c,'outcome figure'))
      py('render_destinations.py',c(paste0('--input=',destinations),paste0('--output-dir=',figures)),paste(c,'destination figure'))
      r('render_endpoint_bar.R',c(duration,figures),paste(c,'interruption figure'))
    }
    if(opt$target %in% c('all','maps')) {
      message(c,': regional/provincial maps and reason shares.')
      r('calculate_geography.R',c(common,paste0('--reference=',reference),paste0('--output=',file.path(maps,slug))),paste(c,'geography'))
      if(c!='Ethiopia') {
        scheme<-if(c=='Nigeria')'nigeria_zones6'else'drc_geographic6'
        r('calculate_grouped_geography.R',c(common,paste0('--reference=',reference),
          paste0('--scheme=',scheme),paste0('--output=',file.path(aggregation,scheme))),paste(c,'grouped geography'))
      }
    }
  }
  if(opt$target %in% c('all','extensions')) {
    py('render_alluvials.py',c(paste0('--aggregate-dir=',switching),paste0('--output-dir=',figures)),'Alluvial figures')
    py('build_report.py',c('--results-dir',results,'--reason-timing-dir',timing,
      '--alluvial-dir',figures,'--alluvial-aggregate-dir',switching,
      '--output',file.path(out,'Discontinuation_and_switching_extensions.html')),'Extensions HTML')
  }
  if(opt$target %in% c('all','maps')) {
    dir.create(file.path(maps,'boundaries'))
    for(f in list.files(file.path(root,'assets/boundaries'),pattern='geojson$',full.names=TRUE))
      stopifnot(file.copy(f,file.path(maps,'boundaries',basename(f))))
    py('build_maps.py',c('--build-dir',maps,'--aggregation-dir',aggregation,
      '--output',file.path(out,'Modern_method_discontinuation_maps.html')),'Maps HTML')
  }
  py('validate_results.py',c('--work-dir',work,'--reference',file.path(root,'validation/expected_results.json'),
    '--output',file.path(out,'validation.json'),'--target',opt$target),'Numerical and output validation')
  versions<-data.frame(package=c('R',needed),version=c(as.character(getRversion()),
    vapply(needed,function(p)as.character(utils::packageVersion(p)),'')))
  write.csv(versions,file.path(out,'software_versions.csv'),row.names=FALSE)
  message('Completed: regenerated reports passed numerical regression and structural checks.')
}
main()
