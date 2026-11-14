#!/usr/bin/env Rscript
# Partner/spousal-disapproval cumulative incidence from supplied DHS episodes.
# Authorized IR and prepared episode inputs are runtime parameters.
args <- commandArgs(TRUE)
opt <- list(replicates='1999', seed='20261112')
for (a in args) {
  if (!grepl('^--[^=]+=.+$',a)) stop('Use --name=value arguments.')
  k <- sub('^--([^=]+)=.*$','\\1',a)
  opt[[k]] <- sub('^--[^=]+=','',a)
}
stopifnot(all(c('country','ir','episodes','output') %in% names(opt)))
suppressPackageStartupMessages({library(jsonlite);library(survival);library(digest)})
country <- opt$country
stopifnot(country %in% c('Ethiopia','Nigeria','DRC'))
B <- as.integer(opt$replicates);seed <- as.integer(opt$seed)
stopifnot(B>=999L)
out <- opt$output;dir.create(out,recursive=TRUE,showWarnings=FALSE)
ir <- readRDS(opt$ir);e0 <- readRDS(opt$episodes)
modern <- c(1L,2L,3L,5L,6L,7L,11L,13L,14L,15L,17L,18L,19L,20L)
actionable <- c(1L,4L,5L,6L,7L,8L,10L,15L)
e <- e0[e0$method_code %in% modern & e0$entry<12L & e0$exposure>e0$entry,]
stopifnot(nrow(e)>0, !any(e$method_code==16L), !anyNA(e$reason_code),
          all(e$entry>=0),all(e$exposure>e$entry),all(e$woman_row>=1L),all(e$woman_row<=nrow(ir)))
stopifnot(all(as.character(e$caseid)==as.character(ir$caseid[e$woman_row])))
w <- as.numeric(ir$v005)/1e6
stopifnot(max(abs(w[e$woman_row]-e$wt))<1e-12)
e$method_group <- ifelse(e$method_code==3,'Injectables',ifelse(e$method_code==11,'Implants',
                  ifelse(e$method_code==1,'Pill',ifelse(e$method_code==2,'IUD','Other modern'))))
e$partner_event <- e$discontinued & e$exposure<=12 & e$reason_code==3L
psu <- as.numeric(ir$v021);stratum <- as.numeric(ir$v022)
stopifnot(!anyNA(psu),!anyNA(stratum))
frame <- unique(data.frame(psu=psu,stratum=stratum))
frame$key <- paste(frame$stratum,frame$psu,sep=':')
groups <- split(seq_len(nrow(frame)),frame$stratum)
stopifnot(!anyDuplicated(frame$key),all(lengths(groups)>1L))
ep_psu <- match(paste(stratum[e$woman_row],psu[e$woman_row],sep=':'),frame$key)
stopifnot(!anyNA(ep_psu))
expected <- list(Ethiopia=c(8682L,797L,27L),Nigeria=c(8341L,1380L,74L),DRC=c(4146L,778L,51L))[[country]]
stopifnot(identical(c(nrow(e),nrow(frame),length(groups)),expected))

# All sampled PSUs participate, including PSUs with no eligible episodes.
# Smoothed Rao-Wu n-1 resampling preserves sparse risk-set support. The tiny
# epsilon is removed from replicate deviations when computing intervals.
epsilon <- 1e-4
mult <- matrix(1,nrow(frame),B+1L)
set.seed(seed)
for(ids in groups){
  n <- length(ids)
  for(b in seq_len(B)) {
    raw <- n/(n-1)*tabulate(sample.int(n,n-1,replace=TRUE),nbins=n)
    mult[ids,b+1L] <- epsilon+(1-epsilon)*raw
  }
}
weights <- mult[ep_psu,,drop=FALSE]*e$wt
methods <- c('All modern','Injectables','Implants','Pill','IUD','Other modern')
code_names <- c('5'='Male condom','6'='Female sterilization','7'='Male sterilization',
                '13'='LAM','14'='Female condom','15'='Foam or jelly',
                '17'='Other modern method','18'='Standard days method','19'='Other specified modern method 19','20'='Other specified modern method 20')
detail_codes <- sort(unique(e$method_code[e$method_group=='Other modern']))
detail_names <- setNames(detail_codes,paste0('Detail: ',unname(code_names[as.character(detail_codes)])))
stopifnot(!anyNA(names(detail_names)))
methods <- c(methods,names(detail_names))
all_results <- list();monthly_rows <- list();summary_rows <- list();timing_rows <- list()
validation_error <- 0
point_only <- function(d){
  survival <- 1;cif <- c(partner=0,actionable=0,other=0);records <- list()
  for(t in 1:12){
    risk <- d$entry<t & d$exposure>=t;den <- sum(d$wt[risk])
    ev <- risk & d$exposure==t & d$discontinued
    if(den>0){
      h <- c(partner=sum(d$wt[ev & d$reason_code==3]),
             actionable=sum(d$wt[ev & d$reason_code %in% actionable]),
             other=sum(d$wt[ev & !d$reason_code %in% c(3,actionable)]))/den
      cif <- cif+survival*h;survival <- survival*(1-sum(h))
    }
    records[[t]] <- c(month=t,cif,all=1-survival)
  }
  as.data.frame(do.call(rbind,records))
}
for(method in methods){
  ix <- if(method=='All modern')seq_len(nrow(e))else if(method %in% names(detail_names))which(e$method_code==detail_names[[method]])else which(e$method_group==method)
  d <- e[ix,];W <- weights[ix,,drop=FALSE]
  # Reason composition has an observed-ending denominator, distinct from CIF.
  endings <- d$discontinued & d$exposure<=12
  weighted_all <- sum(d$wt[endings]);weighted_partner <- sum(d$wt[d$partner_event])
  share <- if(weighted_all>0)100*weighted_partner/weighted_all else NA_real_
  share_lo <- share_hi <- NA_real_
  if(sum(d$partner_event)>0L){
    rep_share <- 100*colSums(W[d$partner_event,,drop=FALSE])/colSums(W[endings,,drop=FALSE])
    corrected_share <- share+(rep_share[-1]-share)/(1-epsilon)
    share_lo <- max(0,unname(quantile(corrected_share,.025)))
    share_hi <- min(100,unname(quantile(corrected_share,.975)))
  }
  composition <- data.frame(weighted_first_year_all_endings=weighted_all,
    weighted_first_year_partner_endings=weighted_partner,
    partner_share_of_first_year_endings=share,share_ci_low=share_lo,share_ci_high=share_hi)
  support_n <- vapply(1:12,function(t)sum(d$entry<t & d$exposure>=t),0L)
  if(any(support_n==0L)){
    stopifnot(method %in% names(detail_names))
    sm <- data.frame(country=country,method=method,eligible_episodes=nrow(d),weighted_episodes=sum(d$wt),
                     month1_episodes=support_n[1],month12_episodes=support_n[12],late_entries=sum(d$entry>0),
                     first_year_all_endings=sum(d$discontinued & d$exposure<=12),partner_endings=sum(d$partner_event),
                     partner_women=length(unique(d$woman_row[d$partner_event])),
                     partner_psus=length(unique(ep_psu[ix][d$partner_event])),
                     probability_12=NA_real_,ci_low_12=NA_real_,ci_high_12=NA_real_,
                     flag='Insufficient risk-set support for a full-year estimate')
    sm <- cbind(sm,composition)
    mm <- data.frame(country=country,method=method,month=0:12,probability=c(0,rep(NA_real_,12)),
                     ci_low=NA_real_,ci_high=NA_real_,at_risk_n=c(NA_integer_,support_n),
                     observed_partner_endings_to_month=c(0L,vapply(1:12,function(t)sum(d$partner_event & d$exposure<=t),0L)))
    all_results[[method]] <- list(summary=sm,monthly=mm,timing=data.frame(),check=list(full_year_estimable=FALSE))
    summary_rows[[method]]<-sm;monthly_rows[[method]]<-mm
    next
  }
  S <- rep(1,B+1L);F <- rep(0,B+1L)
  estimates <- matrix(0,B+1L,13L)
  at_risk_n <- cumulative_events <- integer(12L)
  for(t in 1:12){
    risk <- d$entry<t & d$exposure>=t
    ev <- risk & d$exposure==t & d$discontinued
    pe <- ev & d$reason_code==3L
    den <- colSums(W[risk,,drop=FALSE])
    all_ends <- colSums(W[ev,,drop=FALSE]);partner_ends <- colSums(W[pe,,drop=FALSE])
    supported <- den>0
    stopifnot(all(supported | S<1e-10))
    h <- hp <- rep(0,B+1L)
    h[supported] <- all_ends[supported]/den[supported]
    hp[supported] <- partner_ends[supported]/den[supported]
    F <- F+S*hp;S <- S*(1-h)
    estimates[,t+1L] <- 100*F
    at_risk_n[t] <- sum(risk)
    cumulative_events[t] <- sum(d$partner_event & d$exposure<=t)
  }
  stopifnot(all(is.finite(estimates)),all(estimates>=-1e-10),all(estimates<=100+1e-8),
            all(apply(estimates,1,function(z)all(diff(z)>=-1e-10))))
  # Independently check weighted Aalen-Johansen with a separate survival engine.
  d$stop <- pmin(d$exposure,12)
  d$status <- factor(ifelse(!d$discontinued | d$exposure>12,'censored',
                     ifelse(d$reason_code==3L,'partner',ifelse(d$reason_code %in% actionable,'actionable','other'))),
                     levels=c('censored','partner','actionable','other'))
  d$unique_episode <- seq_len(nrow(d))
  observed_states <- c('censored',setdiff(unique(as.character(d$status)),'censored'))
  d$status <- factor(d$status,levels=observed_states)
  aj_partner <- rep(0,12)
  if(length(observed_states)>1L){
    sf <- survival::survfit(survival::Surv(entry,stop,status)~1,data=d,weights=wt,id=unique_episode)
    aj <- summary(sf,times=1:12,extend=TRUE)$pstate
    colnames(aj) <- sf$states
    if('partner' %in% sf$states)aj_partner <- 100*aj[,'partner']
  }
  independent <- point_only(d)
  err <- max(abs(aj_partner-estimates[1,2:13]),
             abs(100*independent$partner-estimates[1,2:13]),
             abs(rowSums(independent[c('partner','actionable','other')])-independent$all))
  validation_error <- max(validation_error,err)
  stopifnot(err<1e-8)
  corrected <- sweep(sweep(estimates[-1,,drop=FALSE],2,estimates[1,],'-')/(1-epsilon),2,estimates[1,],'+')
  lo <- pmax(0,apply(corrected,2,quantile,.025,names=FALSE))
  hi <- pmin(100,apply(corrected,2,quantile,.975,names=FALSE))
  # An all-zero empirical bootstrap does not establish a zero population risk.
  lo[c(TRUE,cumulative_events==0)] <- NA_real_;hi[c(TRUE,cumulative_events==0)] <- NA_real_
  n_events <- sum(d$partner_event)
  flag <- if(n_events==0)'No observed partner-disapproval endings'else
          if(n_events<5L || at_risk_n[1]<25L)'Very sparse; descriptive only'else
          if(n_events<30L || at_risk_n[1]<250L)'Limited support; interpret cautiously'else'Event count >=30; assess precision using CI'
  sm <- data.frame(country=country,method=method,eligible_episodes=nrow(d),
                   weighted_episodes=sum(d$wt),month1_episodes=at_risk_n[1],
                   month12_episodes=at_risk_n[12],late_entries=sum(d$entry>0),
                   first_year_all_endings=sum(d$discontinued & d$exposure<=12),
                   partner_endings=n_events,partner_women=length(unique(d$woman_row[d$partner_event])),
                   partner_psus=length(unique(ep_psu[ix][d$partner_event])),
                   probability_12=estimates[1,13],ci_low_12=lo[13],ci_high_12=hi[13],flag=flag)
  sm <- cbind(sm,composition)
  mm <- data.frame(country=country,method=method,month=0:12,probability=estimates[1,],
                   ci_low=lo,ci_high=hi,at_risk_n=c(NA_integer_,at_risk_n),
                   observed_partner_endings_to_month=c(0L,cumulative_events))
  increments <- diff(c(0,estimates[1,c(4,7,10,13)]))
  shares <- if(estimates[1,13]>0)100*increments/estimates[1,13]else rep(NA_real_,4)
  if(n_events>0)stopifnot(abs(sum(shares)-100)<1e-8)
  tt <- data.frame(country=country,method=method,period=c('Months 1–3','Months 4–6','Months 7–9','Months 10–12'),
                   probability_increment_pp=increments,share_first_year_probability=shares)
  all_results[[method]] <- list(summary=sm,monthly=mm,timing=tt,
                               check=list(all_reason_12=100*independent$all[12],actionable_12=100*independent$actionable[12]))
  summary_rows[[method]]<-sm;monthly_rows[[method]]<-mm;timing_rows[[method]]<-tt
}
meta <- list(country=country,survey=list(Ethiopia='2024–25',Nigeria='2024',DRC='2023–24')[[country]],
             definition='Original modern-method ending attributed to husband/partner disapproval; EC excluded.',
             event_code=3L,excluded_EC_code=16L,modern_codes=modern,
             competing_events='Every other observed original-method ending, including wanted pregnancy, method failure and actionable causes.',
             observation_window='3–62 months before each interview; known-start episodes and eligible delayed entry retained; first-year duration 1–12 months.',
             risk_rule='entry < month and exposure >= month; all observed endings reduce original-method survival.',
             reason_share_definition='Weighted partner-disapproval endings divided by all weighted observed first-year modern-method endings, including other/unknown/missing reasons; EC excluded. This conditional distribution is not a life-table probability.',
             full_frame_psus=nrow(frame),full_frame_strata=length(groups),interviewed_women=nrow(ir),
             replicates=B,seed=seed,bootstrap='Full-frame stratified Rao-Wu n-1 PSU bootstrap; epsilon-smoothed multipliers with corrected deviations.',
             epsilon=epsilon,CI='Percentile 95% interval. No empirical CI reported at horizons with zero observed target events.',
             flags='Descriptive flags: no events; very sparse if <5 target endings or <25 month-1 episodes; limited if <30 target endings or <250 month-1 episodes. These are screening rules, not universal precision thresholds.',
             other_modern_codes=detail_codes,detail_methods=as.list(detail_names),
             input_checksums=list(ir_sha256=digest(file=opt$ir,algo='sha256'),episodes_sha256=digest(file=opt$episodes,algo='sha256')),
             validation=list(status='pass',max_Aalen_Johansen_absolute_difference_pp=validation_error,
                             EC_episodes=0L,other_endings_retained=TRUE,full_survey_frame=TRUE,
                             reference_all_reason_12=all_results[['All modern']]$check$all_reason_12,
                             reference_actionable_12=all_results[['All modern']]$check$actionable_12))
write.csv(do.call(rbind,summary_rows),file.path(out,'method_summary.csv'),row.names=FALSE)
write.csv(do.call(rbind,monthly_rows),file.path(out,'monthly_probabilities.csv'),row.names=FALSE)
write.csv(do.call(rbind,timing_rows),file.path(out,'timing_composition.csv'),row.names=FALSE)
jsonlite::write_json(list(metadata=meta,methods=all_results),file.path(out,'results.json'),
                     auto_unbox=TRUE,pretty=TRUE,na='null',digits=15,dataframe='rows')
cat(country,': ',nrow(e),' modern episodes; ',sum(e$partner_event),' partner-disapproval endings; ',
    round(all_results[['All modern']]$summary$probability_12,3),'% by 12 months. ',B,' joint survey replicates.\n',sep='')
