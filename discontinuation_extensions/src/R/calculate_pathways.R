#!/usr/bin/env Rscript
suppressPackageStartupMessages(library(jsonlite))
args <- commandArgs(TRUE)
if(length(args)!=4L) stop('Supply calendar input, country, survey label, aggregate output.')
calendar <- readRDS(args[1])
modern <- c(1L,2L,3L,5L,6L,7L,11L,13L,14L,15L,16L,17L,18L,19L,20L)
actionable <- c(1L,4L,5L,6L,7L,8L,10L,15L)
state <- function(code) {
  ifelse(code %in% modern, 'Modern method',
    ifelse(code==0L,'No method',
      ifelse(code %in% c(81L,82L,83L),'Pregnancy/birth/termination',
        ifelse(code %in% c(8L,9L,10L,12L),'Traditional method','Other/unknown'))))
}
eligible <- calendar$method_code %in% setdiff(modern,16L) &
  calendar$reason_code %in% actionable &
  calendar$interview-calendar$end >= 3L & calendar$interview-calendar$end <= 62L
endings <- calendar[eligible,]
cohort <- endings[endings$end+12L <= endings$interview-3L,]
cohort$origin <- ifelse(cohort$method_code==3L,'Injectables',
  ifelse(cohort$method_code==11L,'Implants',
    ifelse(cohort$method_code==1L,'Pill',
      ifelse(cohort$method_code==2L,'IUD','Other modern'))))
stopifnot(nrow(cohort)>0, !any(cohort$method_code==16L),
  !any(cohort$reason_code==3L), !anyDuplicated(paste(cohort$woman_row,cohort$event_no)))
times <- c(1L,3L,6L,12L)
by_woman <- split(seq_len(nrow(calendar)),calendar$woman_row)
for (t in times) cohort[[paste0('month',t)]] <- NA_character_
for (w in unique(cohort$woman_row)) {
  timeline <- calendar[by_woman[[as.character(w)]],]
  timeline <- timeline[order(timeline$start),]
  rows <- which(cohort$woman_row==w)
  for(t in times) {
    date <- cohort$end[rows]+t
    j <- findInterval(date,timeline$start)
    stopifnot(all(j>0), all(timeline$end[j]>=date), !anyNA(timeline$method_code[j]))
    cohort[[paste0('month',t)]][rows] <- state(timeline$method_code[j])
  }
}
cols <- paste0('month',times)
stopifnot(!anyNA(cohort[,cols]))
paths <- aggregate(cohort$wt,cohort[,c('origin',cols)],sum)
names(paths)[ncol(paths)] <- 'weight'
paths$share <- 100*paths$weight/sum(cohort$wt)
stopifnot(abs(sum(paths$share)-100)<1e-9)
shares <- do.call(rbind,lapply(times,function(t) {
  direct <- aggregate(cohort$wt,list(state=cohort[[paste0('month',t)]]),sum)
  names(direct)[2] <- 'weight'
  reconstructed <- aggregate(paths$weight,list(state=paths[[paste0('month',t)]]),sum)
  stopifnot(identical(direct$state,reconstructed$state),
    max(abs(direct$weight-reconstructed$x))<1e-8)
  direct$share <- 100*direct$weight/sum(cohort$wt)
  direct$month <- t
  direct
}))
origins <- aggregate(cohort$wt,list(method=cohort$origin),sum)
names(origins)[2] <- 'weight'
origins$share <- 100*origins$weight/sum(cohort$wt)
origin_reconstructed <- aggregate(paths$weight,list(method=paths$origin),sum)
stopifnot(identical(origins$method,origin_reconstructed$method),
  max(abs(origins$weight-origin_reconstructed$x))<1e-8)
out <- list(country=args[2],survey=args[3],
  definition='Observed actionable modern-method endings at any duration; original EC excluded. Complete twelve-month follow-up, with the last three pre-interview months excluded.',
  actionable_codes=actionable,eligible_endings=nrow(endings),endings=nrow(cohort),
  women=length(unique(cohort$woman_row)),weighted_endings=sum(cohort$wt),
  times=times,endpoint_EC_included_as_modern=TRUE,
  paths=paths,shares=shares,origins=origins,
  validation=list(complete_followup=TRUE,all_margins_reconcile=TRUE,
    actionable_only=TRUE,partner_disapproval_excluded=TRUE,original_EC_excluded=TRUE))
write_json(out,args[4],pretty=TRUE,auto_unbox=TRUE,digits=15,na='null',dataframe='rows')
cat(args[2],nrow(cohort),'endings;',length(unique(cohort$woman_row)),
  'women; weighted shares reconcile at every snapshot.\n')
