#!/usr/bin/env Rscript
# Rebuild national planning reports from the included aggregate inputs.
args <- commandArgs(TRUE)
if ('--help' %in% args) {
  cat('Run from the repository root.\nOptions: --country=all|Ethiopia|Nigeria|DRC, --output-dir=work/build, --python=python3\nOutputs are separate from the checked reports. Presentations are not regenerated.\n')
  quit(status=0)
}
opt <- list(country='all', 'output-dir'=file.path('work','build'), python=Sys.getenv('PYTHON',unset='python3'))
for (arg in args) {
  if (!grepl('^--[^=]+=.+$',arg)) stop('Use --name=value arguments.')
  key <- sub('^--([^=]+)=.*$','\\1',arg)
  if (!key %in% names(opt)) stop('Unknown option: ',key)
  opt[[key]] <- sub('^--[^=]+=','',arg)
}
scripts <- c(Ethiopia='Ethiopia_final_html_analysis.R',Nigeria='Nigeria_final_html_analysis.R',DRC='DRC_final_html_analysis.R')
selected <- if(tolower(opt$country)=='all')names(scripts)else names(scripts)[tolower(names(scripts))==tolower(opt$country)]
if(!length(selected))stop('Choose all, Ethiopia, Nigeria or DRC.')
for(country in selected) {
  folder <- paste0(country,'_analysis')
  source <- file.path(folder,scripts[[country]])
  if(!file.exists(source))stop('Run this command from the repository root.')
  output <- file.path(opt[['output-dir']],folder)
  cat('Rebuilding ',country,' planning tables and report...\n',sep='')
  status <- system2(file.path(R.home('bin'),'Rscript'), shQuote(c(source,'--run=build-html',paste0('--project-root=',output),paste0('--python=',opt$python))))
  if(status!=0L)stop(country,' report build failed.')
}
cat('Completed. Unchanged chapters and figures came from the supplied HTML layouts.\n')
