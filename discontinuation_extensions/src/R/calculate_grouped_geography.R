#!/usr/bin/env Rscript
# Modern-method life tables by current survey geography from supplied inputs.
opt<-list(replicates='1999',seed='20261112')
for(a in commandArgs(TRUE)){
 if(!grepl('^--[^=]+=.+$',a))stop('Use --name=value arguments.')
 opt[[sub('^--([^=]+)=.*$','\\1',a)]]<-sub('^--[^=]+=','',a)
}
stopifnot(all(c('country','ir','episodes','reference','output')%in%names(opt)))
suppressPackageStartupMessages({library(jsonlite);library(survival)})
x<-readRDS(opt$ir);e<-readRDS(opt$episodes)
e<-e[e$method_code%in%c(1L,2L,3L,5L,6L,7L,11L,13L,14L,15L,17L,18L,19L,20L)&e$entry<12&e$exposure>e$entry,]
stopifnot(all(as.character(e$caseid)==as.character(x$caseid[e$woman_row])),!any(e$method_code==16L))
stopifnot('scheme'%in%names(opt))
original_area<-as.integer(x$v024[e$woman_row])
if(opt$scheme=='nigeria_zones6'){
 stopifnot(opt$country=='Nigeria')
 e$area<-original_area
 labs<-attr(x$v024,'labels');codes<-sort(unique(e$area))
 area_names<-names(labs)[match(codes,as.integer(labs))]
 names(area_names)<-as.character(codes)
 expected_areas<-6L
}else if(opt$scheme=='drc_historical11'){
 stopifnot(opt$country=='DRC',all(original_area%in%1:26))
 mapping<-c(1L,2L,3L,3L,3L,4L,4L,4L,4L,4L,5L,5L,5L,5L,6L,7L,8L,9L,9L,9L,9L,10L,10L,10L,11L,11L)
 e$area<-mapping[original_area]
 area_names<-setNames(c('Kinshasa','Kongo Central','Bandundu (historical)','Equateur (historical)','Orientale (historical)','Nord-Kivu','Sud-Kivu','Maniema','Katanga (historical)','Kasai Oriental (historical)','Kasai Occidental (historical)'),1:11)
 codes<-sort(unique(e$area));expected_areas<-11L
}else if(opt$scheme=='drc_geographic6'){
 stopifnot(opt$country=='DRC',all(original_area%in%1:26))
 mapping<-c(1L,2L,2L,2L,2L,5L,5L,5L,5L,5L,4L,4L,4L,4L,4L,4L,4L,6L,6L,6L,6L,3L,3L,3L,3L,3L)
 e$area<-mapping[original_area]
 area_names<-setNames(c('Kinshasa','Grand Ouest','Grand Kasai','Grand Est','Grand Equateur','Grand Katanga'),1:6)
 codes<-sort(unique(e$area));expected_areas<-6L
}else stop('Unknown aggregation scheme.')
stopifnot(!anyNA(e$area),!anyNA(area_names),length(codes)==expected_areas)
frame<-unique(data.frame(psu=as.integer(x$v021),stratum=as.integer(x$v022)))
frame$key<-paste(frame$stratum,frame$psu,sep=':')
index<-match(paste(as.integer(x$v022[e$woman_row]),as.integer(x$v021[e$woman_row]),sep=':'),frame$key)
stopifnot(!anyNA(index),!anyNA(frame),max(abs(e$wt-as.numeric(x$v005[e$woman_row])/1e6))<1e-12)
strata<-split(seq_len(nrow(frame)),frame$stratum);stopifnot(all(lengths(strata)>1))
B<-as.integer(opt$replicates);stopifnot(B>=999);epsilon<-1e-4
set.seed(as.integer(opt$seed));mult<-matrix(1,nrow(frame),B+1)
for(ids in strata){n<-length(ids);for(b in seq_len(B))mult[ids,b+1]<-epsilon+(1-epsilon)*n/(n-1)*tabulate(sample.int(n,n-1,replace=TRUE),nbins=n)}
W<-mult[index,,drop=FALSE]*e$wt
actionable<-c(1L,4L,5L,6L,7L,8L,10L,15L)
causes<-list('Method failure'=1L,'Wanted a more effective method'=7L,
 'Changes in menstrual bleeding'=15L,'Other side effects/health concerns'=c(4L,5L),
 'Access/cost/convenience'=c(6L,8L,10L),'Wanted pregnancy'=2L,
 'Other fertility-related reasons'=c(9L,12L,13L),'Partner/spousal disapproval'=3L,
 'Other/unknown/missing'=c(0L,11L,96L,98L,99L))
stopifnot(!anyDuplicated(unlist(causes)),all(e$reason_code[e$discontinued]%in%unlist(causes)))
rows<-list();monthly<-list();reason_rows<-list();max_error<-0
scopes<-c(NA_integer_,codes)
for(code in scopes){
 ix<-if(is.na(code))seq_len(nrow(e))else which(e$area==code)
 d<-e[ix,];w<-W[ix,,drop=FALSE]
 S<-rep(1,B+1);F<-rep(0,B+1);Fc<-matrix(0,B+1,length(causes))
 ap<-sp<-matrix(0,B+1,13);risk_n<-integer(12)
 for(t in 1:12){
  risk<-d$entry<t&d$exposure>=t;ev<-risk&d$discontinued&d$exposure==t
  den<-colSums(w[risk,,drop=FALSE]);stopifnot(all(den>0))
  h<-colSums(w[ev,,drop=FALSE])/den
  hs<-colSums(w[ev&d$reason_code%in%actionable,,drop=FALSE])/den
  for(j in seq_along(causes))Fc[,j]<-Fc[,j]+S*colSums(w[ev&d$reason_code%in%causes[[j]],,drop=FALSE])/den
  F<-F+S*hs;S<-S*(1-h);ap[,t+1]<-100*(1-S);sp[,t+1]<-100*F;risk_n[t]<-sum(risk)
 }
 d$stop<-pmin(d$exposure,12)
 d$status<-factor(ifelse(!d$discontinued|d$exposure>12,'censored',ifelse(d$reason_code%in%actionable,'actionable','other')),levels=c('censored','actionable','other'))
 d$id<-seq_len(nrow(d));sf<-survival::survfit(survival::Surv(entry,stop,status)~1,data=d,weights=wt,id=id)
 aj<-summary(sf,times=1:12,extend=TRUE)$pstate;colnames(aj)<-sf$states
 err<-max(abs(100*(1-aj[,1])-ap[1,2:13]),abs(100*aj[,'actionable']-sp[1,2:13]));stopifnot(err<1e-8);max_error<-max(max_error,err)
 stopifnot(max(abs(100*rowSums(Fc)-ap[,13]))<1e-8,max(abs(100*rowSums(Fc[,1:5,drop=FALSE])-sp[,13]))<1e-8)
 observed_all<-d$discontinued&d$exposure<=12
 observed_act<-observed_all&d$reason_code%in%actionable
 den_all<-colSums(w[observed_all,,drop=FALSE]);den_act<-colSums(w[observed_act,,drop=FALSE])
 stopifnot(all(den_all>0),all(den_act>0))
 share_interval<-function(v,n){
  if(n==0)return(c(NA_real_,NA_real_))
  corrected<-v[1]+(v[-1]-v[1])/(1-epsilon)
  c(max(0,unname(quantile(corrected,.025))),min(100,unname(quantile(corrected,.975))))
 }
 for(j in seq_along(causes)){
  point<-100*Fc[1,j];replicate_values<-point+(100*Fc[-1,j]-point)/(1-epsilon)
  ending_n<-sum(d$discontinued&d$exposure<=12&d$reason_code%in%causes[[j]])
  low<-if(ending_n>0)max(0,unname(quantile(replicate_values,.025)))else NA_real_
  high<-if(ending_n>0)min(100,unname(quantile(replicate_values,.975)))else NA_real_
  numerator<-colSums(w[observed_all&d$reason_code%in%causes[[j]],,drop=FALSE])
  share_all<-100*numerator/den_all;share_all_ci<-share_interval(share_all,ending_n)
  share_act<-if(j<=5)100*numerator/den_act else rep(NA_real_,B+1)
  share_act_ci<-if(j<=5)share_interval(share_act,ending_n)else c(NA_real_,NA_real_)
  reason_rows[[paste(if(is.na(code))'National'else code,j,sep=':')]]<-data.frame(
   country=opt$country,area_code=if(is.na(code))0L else code,reason=names(causes)[j],
   actionable=j<=5,probability_12=point,ci_low_12=low,ci_high_12=high,
   observed_endings=ending_n,weighted_endings=numerator[1],
   weighted_all_endings=den_all[1],weighted_actionable_endings=den_act[1],
   share_all=share_all[1],share_all_ci_low=share_all_ci[1],share_all_ci_high=share_all_ci[2],
   share_actionable=share_act[1],share_actionable_ci_low=share_act_ci[1],share_actionable_ci_high=share_act_ci[2])
 }
 for(outcome in c('All reasons','Potentially actionable')){
  points<-if(outcome=='All reasons')ap else sp
  target<-d$discontinued&d$exposure<=12&(outcome=='All reasons'|d$reason_code%in%actionable)
  stopifnot(all(points>=-1e-8),all(points<=100+1e-8),all(apply(points,1,function(v)all(diff(v)>=-1e-9))))
  corrected<-sweep(sweep(points[-1,,drop=FALSE],2,points[1,],'-')/(1-epsilon),2,points[1,],'+')
  lo<-pmax(0,apply(corrected,2,quantile,.025,names=FALSE));hi<-pmin(100,apply(corrected,2,quantile,.975,names=FALSE))
  cumulative_events<-vapply(1:12,function(t)sum(target&d$exposure<=t),0L)
  lo[c(TRUE,cumulative_events==0)]<-NA_real_;hi[c(TRUE,cumulative_events==0)]<-NA_real_
  flag<-if(sum(target)<5||risk_n[1]<25)'Very sparse'else if(sum(target)<30||risk_n[1]<250||risk_n[12]<25)'Limited sample'else'Assess confidence interval'
  key<-paste(if(is.na(code))'National'else code,outcome,sep=':')
  rows[[key]]<-data.frame(country=opt$country,area_code=if(is.na(code))0L else code,
   area=if(is.na(code))'National'else unname(area_names[as.character(code)]),outcome=outcome,
   probability_12=points[1,13],ci_low_12=lo[13],ci_high_12=hi[13],eligible_episodes=nrow(d),
   month1_episodes=risk_n[1],month12_episodes=risk_n[12],observed_target_endings=sum(target),flag=flag)
  monthly[[key]]<-data.frame(country=opt$country,area_code=if(is.na(code))0L else code,outcome=outcome,
   month=c(3L,6L,9L,12L),probability=points[1,c(4,7,10,13)],ci_low=lo[c(4,7,10,13)],ci_high=hi[c(4,7,10,13)])
 }
}
result<-do.call(rbind,rows);mm<-do.call(rbind,monthly);reasons<-do.call(rbind,reason_rows)
for(area in unique(reasons$area_code)){
 rr<-reasons[reasons$area_code==area,]
 stopifnot(abs(sum(rr$share_all)-100)<1e-8,abs(sum(rr$share_actionable[rr$actionable])-100)<1e-8)
}
for(outcome in c('All reasons','Potentially actionable')){
 z<-result[result$outcome==outcome,];stopifnot(sum(z$eligible_episodes[z$area_code!=0])==nrow(e),sum(z$observed_target_endings[z$area_code!=0])==z$observed_target_endings[z$area_code==0])
}
ref<-read_json(opt$reference,simplifyVector=TRUE)$metadata$validation
stopifnot(abs(result$probability_12[result$area_code==0&result$outcome=='All reasons']-ref$reference_all_reason_12)<1e-9,
 abs(result$probability_12[result$area_code==0&result$outcome=='Potentially actionable']-ref$reference_actionable_12)<1e-9)
meta<-list(country=opt$country,aggregation=opt$scheme,survey=switch(opt$country,Ethiopia='2024–25',Nigeria='2024',DRC='2023–24'),
 definition='Unadjusted cumulative discontinuation among modern-method episodes excluding EC. Geography is measured at interview, not necessarily where method use occurred.',
 reason_share_definition='Survey-weighted distribution of reported main reasons among observed first-year endings in the eligible modern-method cohort. All-reason shares use all observed endings, including unknown/missing; actionable shares use only actionable endings. EC excluded.',
 actionable_codes=actionable,partner_disapproval_excluded_from_actionable=TRUE,replicates=B,
 uncertainty='Full-frame stratified Rao-Wu n-1 PSU bootstrap; epsilon-smoothed multipliers with corrected deviations; percentile 95% intervals.',
 full_frame_psus=nrow(frame),full_frame_strata=length(strata),
 flag_definition='Very sparse: fewer than 5 target endings or fewer than 25 month-1 episodes. Limited: fewer than 30 target endings, fewer than 250 month-1 episodes, or fewer than 25 month-12 episodes. Screening rules are not power thresholds.',
 validation=list(status='pass',max_Aalen_Johansen_difference_pp=max_error,national_matches_reference=TRUE,area_counts_reconcile=TRUE,reason_probabilities_reconcile=TRUE,EC_episodes=0L))
dir.create(opt$output,recursive=TRUE,showWarnings=FALSE)
write.csv(result,file.path(opt$output,'geography_summary.csv'),row.names=FALSE)
write.csv(reasons,file.path(opt$output,'geography_reasons.csv'),row.names=FALSE)
write_json(list(metadata=meta,summary=result,monthly=mm,reasons=reasons),file.path(opt$output,'geography.json'),auto_unbox=TRUE,pretty=TRUE,na='null',digits=15,dataframe='rows')
cat(opt$country,': ',length(codes),' areas; national and geographic checks passed.\n',sep='')
