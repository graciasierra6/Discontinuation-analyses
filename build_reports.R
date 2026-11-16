#!/usr/bin/env Rscript
# Build a national report from a caller-supplied IR, keeping approved reports read-only.
CONTROLLER_CODE <- r"-----------------------(#!/usr/bin/env Rscript
# Cold national rebuild from an authorized, caller-supplied DHS IR file.
main<-function(){
  a<-commandArgs(TRUE)
  if('--help'%in%a){cat('Rscript build_reports.R --country=Ethiopia|Nigeria|DRC --ir-file=INPUT --output-dir=OUTPUT [--python=python3] [--cores=4] [--soffice=soffice]\nA new output directory is required. Restricted inputs and intermediate records remain there. Approved presentations are read-only comparison artifacts.\n');quit(status=0)}
  opt<-list(python=Sys.getenv('PYTHON',unset='python3'),cores='4',soffice=Sys.getenv('SOFFICE',unset='soffice'))
  for(x in a){if(!grepl('^--[^=]+=.+$',x))stop('Use --name=value arguments.');k<-sub('^--([^=]+)=.*$','\\1',x);if(!k%in%c('country','ir-file','output-dir','python','cores','soffice'))stop('Unknown option.');opt[[k]]<-sub('^--[^=]+=','',x)}
  if(!all(c('country','ir-file','output-dir')%in%names(opt)))stop('Supply country, ir-file and output-dir.')
  country<-opt$country;if(!country%in%c('Ethiopia','Nigeria','DRC'))stop('Unknown country.')
  f<-sub('^--file=','',grep('^--file=',commandArgs(FALSE),value=TRUE)[1]);if(!file.exists(f))f<-gsub('~+~',' ',f,fixed=TRUE);repo<-dirname(normalizePath(f))
  rscript<-file.path(R.home('bin'),'Rscript');root<-opt[['output-dir']]
  if(dir.exists(root)&&length(list.files(root,all.files=TRUE,no..=TRUE)))stop('Choose an empty output directory; an old analysis cache is not a cold rebuild.')
  # All existing report artifacts are immutable throughout a build, including failures.
  if(!requireNamespace('digest',quietly=TRUE))stop('Restore the R dependencies before building.')
  report_folders<-c(file.path(repo,paste0(c('Ethiopia','Nigeria','DRC'),'_analysis')),file.path(repo,'discontinuation_extensions/output'))
  frozen_paths<-unlist(lapply(report_folders,function(folder)list.files(folder,pattern='[.](html|pptx)$',recursive=TRUE,full.names=TRUE,ignore.case=TRUE)),use.names=FALSE)
  frozen_paths<-frozen_paths[!grepl('/src/',frozen_paths,fixed=TRUE)]
  hash_reports<-function()vapply(frozen_paths,function(path){if(!file.exists(path))return(NA_character_);digest::digest(path,file=TRUE,algo='sha256')},character(1))
  frozen_hashes<-hash_reports()
  verify_frozen<-function(){if(!identical(frozen_hashes,hash_reports()))stop('A frozen HTML/PPTX artifact changed. The build is not validated.')}
  on.exit(verify_frozen(),add=TRUE)
  dir.create(root,recursive=TRUE,showWarnings=FALSE);root<-normalizePath(root)
  if(identical(root,repo)||startsWith(root,paste0(repo,.Platform$file.sep)))stop('Use a private build directory outside the repository.')
  status<-system2(rscript,shQuote(c(file.path(repo,'recompute_planning.R'),paste0('--country=',country),paste0('--ir-file=',opt[['ir-file']]),paste0('--output-dir=',root),paste0('--python=',opt$python),paste0('--cores=',opt$cores))))
  if(status!=0L)stop('Fresh data preparation or planning estimation failed.')
  root<-normalizePath(root);entry<-file.path(root,'Code',paste0(country,'_source_snapshot.R'))
  if(!file.exists(entry))stop('The preparation source snapshot is missing.')
  logs<-file.path(root,'output/logs');stats<-file.path(root,'output/survey_planning');tables<-file.path(root,'output/planning_tables')
  run<-function(exe,arguments,label,cwd=NULL){old<-getwd();on.exit(setwd(old),add=TRUE);if(!is.null(cwd))setwd(cwd);cat('Running ',label,'\n',sep='');flush.console();status<-system2(exe,shQuote(arguments),stdout=file.path(logs,paste0(label,'.log')),stderr=file.path(logs,paste0(label,'.log')));if(status!=0L)stop('Stage failed: ',label,'. Inspect its runtime log.')}
  do.call(Sys.setenv,setNames(list(root),paste0(toupper(country),'_PROJECT_ROOT')))
  if(country=='Ethiopia')stopifnot(file.copy(file.path(repo,'Ethiopia_analysis/reference_data/ethiopia_adm1_hdx_2025.geojson'),file.path(root,'output/Supporting_data/ethiopia_adm1_hdx_2025.geojson'),overwrite=TRUE))
  modules<-switch(country,
   Nigeria=c('03_nigeria_zone_models.R','04_nigeria_subgroups_and_tests.R','13_nigeria_all_reason_models.R','17_nigeria_selected_reason_models.R','26_nigeria_actionable_method_zone_models.R','29_zone_method_mix_decomposition.R','09_nigeria_post_discontinuation_pathways.R','34_nigeria_historical_current_user_pathways.R','37_nigeria_selected_reason_extensions.R','38_nigeria_other_reason_followup.R','40_nigeria_selected_current_user_planning.R','42_nigeria_crossvalidated_selected_risk_strata.R','16_nigeria_all_reason_current_user_bridge.py','22_nigeria_landmark_support.R','25_duration_aware_cause_pp_tables.R','35_nigeria_alluvial_figures.R','44_nigeria_replication_figures.R','202_nigeria_survey_coefficients.R'),
   DRC=c('04_drc_province_models.R','17_drc_selected_reason_subgroups.R','18_drc_method_timing.R','26_drc_reference_slide_data.R','27_drc_all_reason_subgroup_model.R','28_drc_province_mcpr.R','32_drc_actionable_subgroup_predictions.R','34_drc_html_extra_analyses.R','36_drc_other_reason_followup.R','37_drc_selected_reason_province_models.R','38_drc_injectable_reason_destinations.R','41_drc_selected_reason_risk_strata.R','216_reconcile_reason_distributions.R','09_drc_post_discontinuation_pathways.R','12_drc_2026_planning.py','211_full_frame_survey_inference.R'),
   Ethiopia=c('211_presentation_inputs.R','212_allcause_inputs.R','10_retained_reason_distribution.R','12_reason_mix_by_method_restricted.R','14_restricted_discontinuation_curve.R','16_mix_vs_restricted_discontinuation.R','18_initiation_mix_excluding_ec.R','19_mix_vs_allcause_excluding_ec.R','21_other_reason_breakdown.R','23_infrequent_sex_followup_states.R','25_other_recorded_reason_followup.R','31_method_experience_12_month_detail.R','34_selected_reason_regression.R','36_selected_reason_contrasts.R','37_selected_reason_regional_analysis.R','39_selected_reason_other_breakdown.R','40_unadjusted_selected_regional_ci.R','42_regional_method_mix_diagnostic.R','43_injectable_regional_reason_ci.R','44_selected_region_method_ci.R','45_injectable_region_checkpoints.R','46_regional_modern_start_mix.R','47_regional_mix_vs_allcause_method_panels.R','49_rebuild_presentation_figures_tables.R','51_duration_adjusted_reason_projection.R','53_descriptive_selected_reason_subgroups.R','54_extended_selected_reason_regression.R','56_crossvalidated_selected_reason_risk_strata.R','58_selected_reason_by_method_duration_class.R','60_short_acting_selected_reason_distribution.R','63_regional_episode_mix_vs_selected_risk.R','70_four_marital_four_parity_selected_regression.R','72_five_wealth_four_marital_selected_regression.R','79_age_15_19_selected_by_method.R','80_descriptive_characteristics_selected_reasons.R','82_descriptive_characteristics_method_experience_reasons.R','84_method_experience_age_timepoints.R','86_top_three_reasons_by_subgroup_and_method.R','88_direct_next_month_modern_switch_life_table.R','90_regional_method_experience_detailed.R','91_plot_regional_method_experience_detailed.R','95_regional_actionable_timepoints.R','96_plot_regional_actionable_timepoints.R','98_preview_actionable_heatmap_locator.R','99_leadership_regional_timing_locator.R','100_regional_initiation_mix_stacked.R','105_regional_actionable_method_pair_preview.R','108_regional_actionable_reason_mix_by_method.R','112_regional_actionable_adjusted_models.R','114_regional_actionable_sample_audit.R','115_dhs_late_entry_reconciliation.R','120_relevel_regional_actionable_models.R','117_export_regional_actionable_model_results.R','119_regional_actionable_design_pvalues.R','122_matched_cohort_regional_raw_for_visual.R','130_regional_actionable_raw_pairwise_bootstrap.R','133_test_regional_actionable_method_mix_differences.R','134_regional_actionable_all_region_method_mix.R','136_regional_actionable_pairwise_shared_mix.py','138_regional_actionable_3_month_pairwise_tests.R','141_regional_method_interaction_actionable.R','144_global_regional_method_interaction_test.R','145_test_actionable_regional_rates_injectables_implants.R','148_injectable_actionable_fully_adjusted_regional_tests.R','209_finalize_regional_inference.R','139_plot_regional_actionable_three_comparisons.R','142_plot_regional_method_interaction_actionable.R','146_plot_actionable_regional_injectables_implants.R','149_plot_injectable_three_stage_regional_tests.R','213_render_allcause_subgroups.py'))
  # Model inference keeps repeated episode-months within the sampled woman's PSU.
  if(country=='Ethiopia')Sys.setenv(BOOTSTRAP_REPS='300',REGIONAL_ACTIONABLE_BOOTSTRAP_REPS='500')
  run(rscript,c(entry,paste0('--run=',paste(modules,collapse=',')),paste0('--project-root=',root),paste0('--python=',opt$python)),'national_analysis_modules')
  if(country=='DRC')run(rscript,c('218_validate_aft_transitions.R',root,stats,file.path(root,'output/validation/transitions')),'post_ending_model_validation',file.path(root,'Code'))
  if(country=='Nigeria')run(rscript,c(file.path(repo,'Nigeria_analysis/src/validate_aft_transitions.R'),root,stats,file.path(root,'output/validation/transitions')),'post_ending_model_validation')
  if(country=='Ethiopia')run(rscript,c(file.path(repo,'Ethiopia_analysis/src/validate_aft_transitions.R'),root,stats,file.path(root,'output/validation/transitions')),'post_ending_model_validation')
  if(country!='Ethiopia'&&file.exists(file.path(stats,'transition_validation.json')))file.copy(file.path(stats,'transition_validation.json'),file.path(tables,'transition_validation.json'),overwrite=TRUE)
  assembler<-file.path(repo,'tools',if(country=='Ethiopia')'assemble_ethiopia.py'else'assemble_national.py')
  run(opt$python,c(assembler,paste0('--country=',country),paste0('--project-root=',root),paste0('--repo-root=',repo),paste0('--statistics-dir=',stats),paste0('--table-dir=',tables),paste0('--rscript=',rscript),paste0('--soffice=',opt$soffice)),'assemble_national_html')
  report<-file.path(root,'output',paste0(country,'_discontinuation_analysis_rebuilt.html'));deck<-file.path(repo,paste0(country,'_analysis'),switch(country,Ethiopia='ethiopia_presentation.pptx',Nigeria='Nigeria_discontinuation.pptx',DRC='DRC_discontinuation.pptx'))
  run(opt$python,c(file.path(repo,'tools/check_html_pptx.py'),'--html',report,'--pptx',deck,'--output',file.path(root,'output/validation/html_presentation_comparison.json')),'compare_presentation_tables')
  reference_html<-file.path(repo,paste0(country,'_analysis'),paste0(country,'_discontinuation_analysis.html'))
  run(opt$python,c(file.path(repo,'tools/check_report_reproduction.py'),'--reference',reference_html,'--rebuilt',report,'--output',file.path(root,'output/validation/final_html_comparison.json')),'compare_final_report')
  verify_frozen()
  # Publish only inside the caller's private output tree; no approved artifact is edited.
  final_report<-file.path(root,'output',basename(reference_html))
  stopifnot(file.copy(report,final_report,overwrite=TRUE))
  stopifnot(file.copy(deck,file.path(root,'output',basename(deck)),overwrite=TRUE))
  input_audit<-jsonlite::read_json(file.path(root,'output/validation/input_validation.json'),simplifyVector=TRUE)
  comparison<-jsonlite::read_json(file.path(root,'output/validation/html_presentation_comparison.json'),simplifyVector=TRUE)
  jsonlite::write_json(list(status='pass',country=country,input_sha256=input_audit$sha256,full_report_regenerated=TRUE,planning_replicates=500L,prior_html_used_for_estimation=FALSE,saved_fitted_results_used_for_estimation=FALSE,presentation_edited=FALSE,final_reports_unchanged=TRUE,full_html_content_comparison='pass',report_file=basename(final_report),presentation_file=basename(deck),native_presentation_tables=as.integer(comparison$native_tables),native_tables_matching=as.integer(comparison$matched_tables),image_based_presentation_tables='not independently checked',scope='Cold raw-IR national numerical analyses and report rendering; conditional descriptive/model estimates, not proof of causal intervention effectiveness.'),file.path(root,'output/validation/national_build.json'),auto_unbox=TRUE,pretty=TRUE)
  verify_frozen()
  cat('Completed cold national rebuild and presentation table checks. The approved PPTX was not edited.\n')
}
main()
)-----------------------"
PLANNING_CODE <- r"-----------------------(#!/usr/bin/env Rscript
# Re-estimate national planning models from an authorized IR file.
# This numerical entry point does not use revision_inputs or an existing HTML.
args<-commandArgs(TRUE)
if('--help'%in%args){
 cat('Rscript recompute_planning.R --country=Ethiopia|Nigeria|DRC --ir-file=INPUT --output-dir=OUTPUT [--cores=4] [--python=python3]\n')
 cat('Reconstructs calendars, estimates historical and AFT probabilities, and refits 500 joint survey replicates. No existing report or fitted estimates are inputs.\n')
 quit(status=0)
}
opt<-list(cores='4',python=Sys.getenv('PYTHON',unset='python3'))
for(a in args){
 if(!grepl('^--[^=]+=.+$',a))stop('Use --name=value arguments.')
 key<-sub('^--([^=]+)=.*$','\\1',a)
 if(!key%in%c('country','ir-file','output-dir','cores','python'))stop('Unknown option.')
 opt[[key]]<-sub('^--[^=]+=','',a)
}
if(!all(c('country','ir-file','output-dir')%in%names(opt)))stop('Supply country, ir-file and output-dir.')
country<-opt$country
if(!country%in%c('Ethiopia','Nigeria','DRC'))stop('Unknown country.')
cores<-as.integer(opt$cores)
if(is.na(cores)||cores<1L)stop('cores must be positive.')
if(!file.exists(opt[['ir-file']]))stop('The supplied IR input does not exist.')
if(dir.exists(opt[['output-dir']])&&length(list.files(opt[['output-dir']],all.files=TRUE,no..=TRUE)))
 stop('Choose an empty output directory. This entry point does not import an old analysis cache.')
script<-sub('^--file=','',grep('^--file=',commandArgs(FALSE),value=TRUE)[1])
if(!file.exists(script))script<-gsub('~+~',' ',script,fixed=TRUE)
repo<-dirname(normalizePath(script))
entry<-file.path(repo,paste0(country,'_analysis'),paste0(country,'_final_html_analysis.R'))
dir.create(opt[['output-dir']],recursive=TRUE,showWarnings=FALSE)
root<-normalizePath(opt[['output-dir']]);input<-normalizePath(opt[['ir-file']])
if(startsWith(input,paste0(repo,.Platform$file.sep)))stop('Supply an authorized IR file from private storage outside the repository.')
if(identical(root,repo)||startsWith(root,paste0(repo,.Platform$file.sep)))stop('Use a private build directory outside the repository.')
# Freeze the analysis source for the lifetime of this build.
dir.create(file.path(root,'Code'),recursive=TRUE,showWarnings=FALSE)
snapshot<-file.path(root,'Code',paste0(country,'_source_snapshot.R'))
stopifnot(file.copy(entry,snapshot,overwrite=FALSE))
entry<-snapshot
for(p in c('output/logs','output/survey_planning','output/planning_tables'))dir.create(file.path(root,p),recursive=TRUE,showWarnings=FALSE)
logs<-file.path(root,'output/logs')
rscript<-file.path(R.home('bin'),'Rscript')
run<-function(exe,arguments,label){
 cat(label,'\n');flush.console()
 status<-system2(exe,shQuote(arguments),stdout=file.path(logs,paste0(label,'.log')),stderr=file.path(logs,paste0(label,'.log')))
 if(status!=0L)stop('Stage failed: ',label,'. Inspect its runtime log.')
}
run(rscript,c(entry,'--run=prepare',paste0('--project-root=',root),paste0('--ir-file=',input)),'prepare')
env<-new.env(parent=globalenv());sys.source(entry,envir=env)
do.call(Sys.setenv,setNames(list(root),paste0(toupper(country),'_PROJECT_ROOT')))
Sys.setenv(DHS_IR_FILE=input)
if(country=='DRC')Sys.setenv(DRC_IR_FILE=input)
stages<-switch(country,
 Ethiopia=c('202_ethiopia_planning_from_ir.R','171_aft_switching_bridge.R'),
 Nigeria=c('02_nigeria_descriptive_analyses.R','12_nigeria_all_reason_bridge.R',
  '15_nigeria_initiation_mix.R','70_modern_five_year_reasons.R',
  '08_nigeria_population_and_planning.R','23_nigeria_current_user_switch_and_duration.R',
  '91_nigeria_aft_switching_bridge.R'),
 DRC=c('02_drc_descriptive_analyses.R','05_drc_current_user_planning.R',
  '06_drc_historical_landmarks.R','07_drc_duration_aware_planning.R',
  '08_drc_aft_duration_by_method_cause.R'))
run(rscript,c(entry,paste0('--run=',paste(stages,collapse=',')),paste0('--project-root=',root),
 paste0('--ir-file=',input)),'planning_inputs')
stats<-file.path(root,'output/survey_planning')
audit<-switch(country,Ethiopia='planning_audit.R',Nigeria='310_nigeria_planning_audit.R',DRC='217_aft_transition_planning.R')
previous<-getwd();setwd(file.path(root,'Code'))
run(rscript,c(audit,root,stats,'500',as.character(cores)),'joint_survey_models')
setwd(previous)
point<-readRDS(file.path(stats,'planning_point.rds'))
draws<-readRDS(file.path(stats,'planning_replicates.rds'))
stopifnot(length(draws)==500L,identical(dim(point$risk),c(9L,5L,5L)),
 all(vapply(draws,function(d)is.null(d$error),FALSE)))
table_out<-file.path(root,'output/planning_tables')
if(country=='Ethiopia'){
 # The general summarizer retains the separately recomputed diagnostics.
 write.csv(data.frame(key=character(),estimate=numeric(),lower=numeric(),upper=numeric()),
  file.path(stats,'planning_intervals.csv'),row.names=FALSE)
 run(rscript,c(file.path(repo,'tools/ethiopia_planning_diagnostics.R'),root,stats),'planning_diagnostics')
 run(rscript,c(file.path(root,'Code/summarize_planning.R'),stats),'summarize_planning')
 run(opt$python,c(file.path(root,'Code/build_tables.py'),stats,table_out),'render_planning_tables')
}else{
 growth<-file.path(table_out,'growth_assumptions.json')
 schema<-file.path(table_out,'table_schema.json')
 writeLines(env$REVISED_GROWTH_ASSUMPTIONS,growth,useBytes=TRUE)
 writeLines(env$REVISED_TABLE_SCHEMA,schema,useBytes=TRUE)
 run(rscript,c(file.path(root,'Code/300_revised_planning.R'),stats,growth,table_out),'summarize_planning')
 run(opt$python,c(file.path(root,'Code/301_revised_tables.py'),table_out,schema,table_out),'render_planning_tables')
}
run(opt$python,c(file.path(repo,'tools/render_planning_report.py'),paste0('--country=',country),
 paste0('--specifications=',file.path(table_out,'planning_html.json')),
 paste0('--output=',file.path(root,'output/Planning_tables.html'))),'planning_html')
if(country=='Ethiopia'){
 language<-file.path(root,'Code/planning_language.py')
 writeLines(env$PLANNING_LANGUAGE_HELPER,language,useBytes=TRUE)
 run(opt$python,c(language,file.path(root,'output/Planning_tables.html'),
  file.path(root,'output/Planning_tables.html')),'planning_language')
}
prep<-jsonlite::read_json(file.path(root,'output/validation/preparation_validation.json'),simplifyVector=TRUE)
jsonlite::write_json(list(country=country,input_sha256=prep$input_sha256,
 raw_ir_preparation=TRUE,fresh_planning_fit=TRUE,fresh_survey_replicates=length(draws),
 risk_components=dim(point$risk)[1],planning_table_specifications=48L,
 existing_fitted_results_used=FALSE,complete_national_html_regenerated=FALSE,
 scope='Numerical planning models and table specifications. Full national report assembly is a separate stage.'),
 file.path(root,'output/validation/fresh_planning_build.json'),pretty=TRUE,auto_unbox=TRUE)
cat('Finished fresh planning fits and table specifications. No approved HTML or PPTX was modified.\n')
)-----------------------"

write_source<-function(text,path){dir.create(dirname(path),recursive=TRUE,showWarnings=FALSE);writeLines(enc2utf8(text),path,sep='',useBytes=TRUE)}
reference_files<-function(){
 c('Ethiopia_analysis/Ethiopia_discontinuation_analysis.html','Ethiopia_analysis/ethiopia_presentation.pptx',
   'Nigeria_analysis/Nigeria_discontinuation_analysis.html','Nigeria_analysis/Nigeria_discontinuation.pptx',
   'DRC_analysis/DRC_discontinuation_analysis.html','DRC_analysis/DRC_discontinuation.pptx',
   'Nigeria_analysis/Kano_Kaduna_Lagos/Kano_Kaduna_Lagos_discontinuation_analysis.html',
   'Nigeria_analysis/Kano_Kaduna_Lagos/Kano_Kaduna_Lagos_discontinuation.pptx',
   'discontinuation_extensions/output/Discontinuation_and_switching_extensions.html',
   'discontinuation_extensions/output/Modern_method_discontinuation_maps.html')
}
materialize_sources<-function(repo,destination,python,reference){
 dir.create(destination,recursive=TRUE,showWarnings=FALSE)
 for(country in c('Ethiopia','Nigeria','DRC')){
  relative<-file.path(paste0(country,'_analysis'),paste0(country,'_final_html_analysis.R'))
  entry<-file.path(repo,relative);e<-new.env(parent=globalenv());sys.source(entry,envir=e)
  write_source(paste(readLines(entry,warn=FALSE),collapse='\n'),file.path(destination,relative))
  for(name in names(e$REPORT_FILES))write_source(e$REPORT_FILES[[name]],file.path(destination,paste0(country,'_analysis'),name))
 }
 states<-list.files(file.path(repo,'Nigeria_analysis/Kano_Kaduna_Lagos'),pattern='[.]R$',full.names=TRUE)
 for(from in states){to<-file.path(destination,'Nigeria_analysis/Kano_Kaduna_Lagos',basename(from));dir.create(dirname(to),recursive=TRUE,showWarnings=FALSE);stopifnot(file.copy(from,to,overwrite=TRUE))}
 geometry<-jsonlite::read_json(file.path(repo,'geography.json'))$files
 for(name in names(geometry))write_source(geometry[[name]],file.path(destination,name))
 stopifnot(file.copy(file.path(repo,'geography.json'),file.path(destination,'geography.json'),overwrite=TRUE))
 write_source(CONTROLLER_CODE,file.path(destination,'build_reports.R'))
 write_source(PLANNING_CODE,file.path(destination,'recompute_planning.R'))
 status<-system2(python,shQuote(c(file.path(repo,'report_tools.py'),paste0('--extract=',destination))))
 if(status!=0L)stop('Could not extract shared reporting sources.')
 # Extension sources are also inspectable and independently executable.
 extension<-file.path(repo,'discontinuation_extensions/run_analysis.R')
 e<-new.env(parent=globalenv());sys.source(extension,envir=e)
 for(name in names(e$EXTENSION_FILES))write_source(e$EXTENSION_FILES[[name]],file.path(destination,'discontinuation_extensions',name))
 for(name in reference_files()){
  from<-file.path(reference,name);to<-file.path(destination,name)
  if(file.exists(from)){dir.create(dirname(to),recursive=TRUE,showWarnings=FALSE);stopifnot(file.copy(from,to,overwrite=TRUE))}
 }
 invisible(destination)
}
main<-function(){
 args<-commandArgs(TRUE)
 if('--help'%in%args||!length(args)){
  cat('Rscript build_reports.R --country=Ethiopia|Nigeria|DRC --ir-file=INPUT --output-dir=PRIVATE_NEW_DIRECTORY [--python=python3] [--cores=4] [--reference-dir=REPOSITORY]\n')
  cat('Rscript build_reports.R --check [--python=python3]\n')
  cat('Rscript build_reports.R --extract-source=PRIVATE_DIRECTORY [--python=python3]\n')
  cat('Existing HTML/PPTX files are read-only. Reference files are used after estimation; DRC also displays the reviewed slide preview.\n')
  return(invisible(NULL))
 }
 opt<-list(python=Sys.getenv('PYTHON',unset='python3'),cores='4',soffice=Sys.getenv('SOFFICE',unset='soffice'),check=FALSE)
 for(x in args){
  if(x=='--check'){opt$check<-TRUE;next}
  if(!grepl('^--[^=]+=.+$',x))stop('Use --name=value arguments.')
  key<-sub('^--([^=]+)=.*$','\\1',x)
  if(!key%in%c('country','ir-file','output-dir','python','cores','soffice','reference-dir','extract-source'))stop('Unknown option.')
  opt[[key]]<-sub('^--[^=]+=','',x)
 }
 script<-sub('^--file=','',grep('^--file=',commandArgs(FALSE),value=TRUE)[1]);if(!file.exists(script))script<-gsub('~+~',' ',script,fixed=TRUE)
 repo<-dirname(normalizePath(script));reference<-if(is.null(opt[['reference-dir']]))repo else normalizePath(opt[['reference-dir']],mustWork=TRUE)
 if(!requireNamespace('jsonlite',quietly=TRUE)||!requireNamespace('digest',quietly=TRUE))stop('Restore the R dependencies before building.')
 originals<-file.path(reference,reference_files());originals<-originals[file.exists(originals)]
 hashes<-vapply(originals,function(p)digest::digest(p,file=TRUE,algo='sha256'),'')
 on.exit({current<-vapply(originals,function(p)if(file.exists(p))digest::digest(p,file=TRUE,algo='sha256')else NA_character_,'');if(!identical(hashes,current))stop('A frozen report changed; validation failed.')},add=TRUE)
 extract<-opt[['extract-source']]
 if(!is.null(extract)){
  if(dir.exists(extract)&&length(list.files(extract,all.files=TRUE,no..=TRUE)))stop('Use an empty private source directory.')
  dir.create(extract,recursive=TRUE,showWarnings=FALSE);extract<-normalizePath(extract)
  if(identical(extract,repo)||startsWith(extract,paste0(repo,.Platform$file.sep)))stop('Extract sources outside the repository.')
  materialize_sources(repo,extract,opt$python,reference)
  cat('Source extraction completed; no models were fitted.\n');return(invisible(NULL))
 }
 runtime<-tempfile('discontinuation-source-');dir.create(runtime);on.exit(unlink(runtime,recursive=TRUE),add=TRUE)
 if(isTRUE(opt$check)){
  materialize_sources(repo,runtime,opt$python,reference)
  status<-system2(opt$python,shQuote(c(file.path(repo,'report_tools.py'),paste0('--check-runtime=',runtime))))
  if(status!=0L)stop('Source validation failed.')
  return(invisible(NULL))
 }
 if(!all(c('country','ir-file','output-dir')%in%names(opt)))stop('Supply country, ir-file and output-dir.')
 country<-opt$country;if(!country%in%c('Ethiopia','Nigeria','DRC'))stop('Unknown country.')
 input<-normalizePath(opt[['ir-file']],mustWork=TRUE)
 for(parent in unique(c(repo,reference)))if(startsWith(input,paste0(parent,.Platform$file.sep)))stop('Keep the IR in private storage outside the repository.')
 output<-opt[['output-dir']]
 if(dir.exists(output)&&length(list.files(output,all.files=TRUE,no..=TRUE)))stop('Use a new empty output directory.')
 dir.create(output,recursive=TRUE,showWarnings=FALSE);output<-normalizePath(output)
 for(parent in unique(c(repo,reference)))if(identical(output,parent)||startsWith(output,paste0(parent,.Platform$file.sep)))stop('Build outside the repository and reference directory.')
 needed<-reference_files()[startsWith(reference_files(),paste0(country,'_analysis/'))]
 if(!all(file.exists(file.path(reference,needed))))stop('Approved HTML/PPTX references are missing. Supply --reference-dir or merge the code update into the existing repository.')
 materialize_sources(repo,runtime,opt$python,reference)
 rscript<-file.path(R.home('bin'),'Rscript')
 status<-system2(rscript,shQuote(c(file.path(runtime,'build_reports.R'),paste0('--country=',country),paste0('--ir-file=',input),paste0('--output-dir=',output),paste0('--python=',opt$python),paste0('--cores=',opt$cores),paste0('--soffice=',opt$soffice))))
 if(status!=0L)stop('The build or reference comparison did not pass. Existing reports were not replaced; inspect private runtime validation files.')
 cat('Independent build and read-only report comparisons completed. Existing reports are unchanged.\n')
}
if(sys.nframe()==0L)main()
