#!/usr/bin/env Rscript
# National descriptive subgroup estimates from supplied IR and episode inputs.
opt <- list(replicates='1999',seed='20261112')
for(a in commandArgs(TRUE)){
  if(!grepl('^--[^=]+=.+$',a))stop('Use --name=value arguments.')
  opt[[sub('^--([^=]+)=.*$','\\1',a)]] <- sub('^--[^=]+=','',a)
}
stopifnot(all(c('country','ir','episodes','reference','output') %in% names(opt)))
suppressPackageStartupMessages({library(jsonlite);library(survival)})
x<-readRDS(opt$ir);e<-readRDS(opt$episodes)
modern<-c(1L,2L,3L,5L,6L,7L,11L,13L,14L,15L,17L,18L,19L,20L)
e<-e[e$method_code%in%modern&e$entry<12&e$exposure>e$entry,]
stopifnot(nrow(e)>0,all(as.character(e$caseid)==as.character(x$caseid[e$woman_row])),
          !any(e$method_code==16),!anyNA(e$reason_code),
          max(abs(e$wt-as.numeric(x$v005[e$woman_row])/1e6))<1e-12)
age<-floor((e$start-as.numeric(x$v011[e$woman_row]))/12)
stopifnot(!anyNA(age),all(age>=0 & age<50))
e$age_group<-cut(age,c(-Inf,24,34,Inf),labels=c('Under 25','25–34','35+'))
birth_fields<-grep('^b3_[0-9]+$',names(x),value=TRUE)
stopifnot(length(birth_fields)>0)
births<-as.matrix(as.data.frame(lapply(x[birth_fields],as.numeric)))
births[births<=0|births>=9990]<-NA_real_
stopifnot(!anyNA(x$v201),all(rowSums(!is.na(births))==as.numeric(x$v201)))
parity<-rowSums(births[e$woman_row,,drop=FALSE]<=e$start,na.rm=TRUE)
stopifnot(all(parity<=as.numeric(x$v201[e$woman_row])))
e$parity_group<-cut(parity,c(-Inf,1,3,Inf),labels=c('0–1 children','2–3 children','4+ children'))
residence<-as.numeric(x$v025[e$woman_row]);stopifnot(all(residence%in%c(1,2)))
e$residence_group<-factor(ifelse(residence==1,'Urban','Rural'),levels=c('Urban','Rural'))
e$target<-e$discontinued&e$exposure<=12&e$reason_code==3L
frame<-unique(data.frame(psu=as.numeric(x$v021),stratum=as.numeric(x$v022)))
stopifnot(!anyNA(frame))
frame$key<-paste(frame$stratum,frame$psu,sep=':')
psu_index<-match(paste(as.numeric(x$v022[e$woman_row]),as.numeric(x$v021[e$woman_row]),sep=':'),frame$key)
stopifnot(!anyNA(psu_index),!anyDuplicated(frame$key))
strata<-split(seq_len(nrow(frame)),frame$stratum);stopifnot(all(lengths(strata)>1))
B<-as.integer(opt$replicates);stopifnot(B>=999)
epsilon<-1e-4;set.seed(as.integer(opt$seed))
mult<-matrix(1,nrow(frame),B+1)
for(ids in strata){
 n<-length(ids)
 for(b in seq_len(B))mult[ids,b+1]<-epsilon+(1-epsilon)*n/(n-1)*tabulate(sample.int(n,n-1,replace=TRUE),nbins=n)
}
W<-mult[psu_index,,drop=FALSE]*e$wt
scopes<-list(All=list(domain='National',label='All modern methods',ix=seq_len(nrow(e))))
domains<-c(age_group='Age at method initiation',parity_group='Parity at method initiation',residence_group='Residence at interview')
for(k in names(domains))for(lev in levels(e[[k]])){
 key<-paste(k,lev,sep=':')
 scopes[[key]]<-list(domain=unname(domains[k]),label=lev,ix=which(e[[k]]==lev))
}
rows<-list();monthly<-list();max_error<-0
for(key in names(scopes)){
 sc<-scopes[[key]];d<-e[sc$ix,];weights<-W[sc$ix,,drop=FALSE]
 S<-rep(1,B+1);F<-rep(0,B+1);risk_n<-integer(12)
 points<-matrix(0,B+1,13);events_to_month<-integer(12)
 for(t in 1:12){
  risk<-d$entry<t&d$exposure>=t;ending<-risk&d$discontinued&d$exposure==t
  den<-colSums(weights[risk,,drop=FALSE]);stopifnot(all(den>0))
  h<-colSums(weights[ending,,drop=FALSE])/den
  hp<-colSums(weights[ending&d$reason_code==3L,,drop=FALSE])/den
  F<-F+S*hp;S<-S*(1-h);points[,t+1]<-100*F
  risk_n[t]<-sum(risk);events_to_month[t]<-sum(d$target&d$exposure<=t)
 }
 stopifnot(all(points>=-1e-10),all(points<=100+1e-8),all(apply(points,1,function(v)all(diff(v)>=-1e-10))))
 d$stop<-pmin(d$exposure,12)
 d$status<-factor(ifelse(!d$discontinued|d$exposure>12,'censored',ifelse(d$reason_code==3L,'partner','other')),levels=c('censored','partner','other'))
 d$episode<-seq_len(nrow(d))
 sf<-survival::survfit(survival::Surv(entry,stop,status)~1,data=d,weights=wt,id=episode)
 aj<-summary(sf,times=1:12,extend=TRUE)$pstate;colnames(aj)<-sf$states
 err<-max(abs(100*aj[,'partner']-points[1,2:13]));stopifnot(err<1e-8)
 max_error<-max(max_error,err)
 corrected<-sweep(sweep(points[-1,,drop=FALSE],2,points[1,],'-')/(1-epsilon),2,points[1,],'+')
 lo<-pmax(0,apply(corrected,2,quantile,.025,names=FALSE));hi<-pmin(100,apply(corrected,2,quantile,.975,names=FALSE))
 lo[c(TRUE,events_to_month==0)]<-NA_real_;hi[c(TRUE,events_to_month==0)]<-NA_real_
 events<-sum(d$target)
 flag<-if(events<5)'Very sparse; descriptive only'else if(events<30)'Limited event count; interpret cautiously'else'Assess precision using the confidence interval'
 rows[[key]]<-data.frame(country=opt$country,domain=sc$domain,subgroup=sc$label,
  eligible_episodes=nrow(d),episodes_at_month1=risk_n[1],episodes_at_month12=risk_n[12],
  target_endings=events,target_women=length(unique(d$woman_row[d$target])),
  target_psus=length(unique(psu_index[sc$ix][d$target])),
  probability_12=points[1,13],ci_low_12=lo[13],ci_high_12=hi[13],flag=flag)
 monthly[[key]]<-data.frame(country=opt$country,domain=sc$domain,subgroup=sc$label,month=0:12,
  probability=points[1,],ci_low=lo,ci_high=hi,at_risk_n=c(NA_integer_,risk_n))
}
result<-do.call(rbind,rows);mm<-do.call(rbind,monthly)
for(domain in unname(domains)){
 z<-result[result$domain==domain,]
 stopifnot(sum(z$eligible_episodes)==nrow(e),sum(z$target_endings)==sum(e$target))
}
ref<-read_json(opt$reference,simplifyVector=TRUE)$methods[['All modern']]$summary
stopifnot(nrow(e)==ref$eligible_episodes,
 abs(result$probability_12[1]-ref$probability_12)<1e-10,
 abs(result$ci_low_12[1]-ref$ci_low_12)<1e-8,
 abs(result$ci_high_12[1]-ref$ci_high_12)<1e-8)
meta<-list(country=opt$country,outcome='First-year modern-method ending due to partner/spousal disapproval; EC excluded.',
 survey=list(Ethiopia='2024–25',Nigeria='2024',DRC='2023–24')[[opt$country]],
 age_definition='Age at original-method initiation; under-25 includes initiation before age 15 among women aged 15–49 at interview.',
 parity_definition='Number of live births by the month of method initiation, reconstructed from the full birth history. Births in the same month are included; exact ordering within a month is unavailable.',
 residence_definition='Urban/rural residence at interview, which may differ from residence during the episode.',
 estimation='Unadjusted weighted competing-risk life tables with eligible delayed entry and all other original-method endings retained as competing events.',
 uncertainty=paste0(B,' full-frame stratified Rao-Wu n-1 PSU bootstrap replicates, preserving repeated episodes within women. Epsilon-smoothed multipliers and corrected deviations; percentile 95% intervals.'),
 full_frame_psus=nrow(frame),full_frame_strata=length(strata),replicates=B,seed=as.integer(opt$seed),
 sample_flags='Fewer than 5 target endings: very sparse. 5–29: limited. These are descriptive screening rules, not power thresholds.',
 inference='No subgroup hypothesis tests or prospective power calculations performed. Confidence intervals describe precision; neither event counts nor interval overlap establish subgroup differences.',
 validation=list(status='pass',max_Aalen_Johansen_difference_pp=max_error,national_matches_reference=TRUE,
 subgroup_counts_reconcile=TRUE,birth_history_matches_total_births=TRUE,EC_episodes=0L))
dir.create(opt$output,recursive=TRUE,showWarnings=FALSE)
write.csv(result,file.path(opt$output,'subgroup_summary.csv'),row.names=FALSE)
write.csv(mm,file.path(opt$output,'subgroup_monthly.csv'),row.names=FALSE)
write_json(list(metadata=meta,summary=result,monthly=mm),file.path(opt$output,'subgroups.json'),
 auto_unbox=TRUE,pretty=TRUE,na='null',digits=15,dataframe='rows')
cat(opt$country,': ',nrow(e),' eligible modern episodes; ',sum(e$target),' target endings; ',nrow(result)-1,' subgroup estimates; independent checks passed.\n',sep='')
