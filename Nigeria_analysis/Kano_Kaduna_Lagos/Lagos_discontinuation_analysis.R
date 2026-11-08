#!/usr/bin/env Rscript
# State discontinuation analysis, Nigeria DHS 2024.
# Standalone numerical source for the current combined three-state report.
# Required input: the full authorized women's IR file, not a state-only subset.
# No personal locations, credentials, or survey microdata are embedded.
# Run with --help for parameterized input and output options.

REPORT_STATE <- "Lagos"
ANALYSIS_VERSION <- "three-state-2024-2025-pooled-v1"

parse_options <- function(a) {
  out <- list()
  for (s in a) {
    if (!startsWith(s, "--")) stop("Use named --option=value arguments.")
    p <- strsplit(substring(s, 3), "=", fixed = TRUE)[[1]]
    out[[p[1]]] <- if (length(p) == 1L) TRUE else paste(p[-1L], collapse = "=")
  }
  allowed <- c("help", "ir-file", "output-dir", "cache-dir", "bootstrap-replicates",
               "planning-replicates", "cores", "validate-input", "no-cache",
               "expected-ir-sha256", "reference-html", "wra-growth-factor")
  if (length(setdiff(names(out), allowed))) stop("Unknown command-line option.")
  out
}

options <- parse_options(commandArgs(trailingOnly = TRUE))
if (isTRUE(options$help)) {
  cat(paste0(
    "State discontinuation analysis: ", REPORT_STATE, "\n\n",
    "Rscript STATE_discontinuation_analysis.R ",
    "--ir-file=INPUT_IR --output-dir=OUTPUT_DIRECTORY\n\n",
    "--ir-file                 Full Nigeria 2024 IR .rds or .dta; alternatively DHS_IR_FILE\n",
    "--output-dir              Project-relative or caller-supplied output directory\n",
    "--cache-dir               Optional shared aggregate cache for the three scripts\n",
    "--bootstrap-replicates    Descriptive survey replicates; default 999\n",
    "--planning-replicates     Planning survey replicates; default 999\n",
    "--cores                   Parallel planning workers; default 2\n",
    "--validate-input          Check IR without running analysis\n",
    "--no-cache                Force a fresh reconstruction and analysis\n",
    "--expected-ir-sha256      Optional input checksum to enforce\n",
    "--reference-html          Optional current combined report for table reconciliation\n",
    "--wra-growth-factor       Fixed 2025/2024 WRA ratio; default 57393553/55819549.5\n\n",
    "Outputs are aggregate CSV/JSON tables and SVG figures. Existing HTML and PPTX\n",
    "are never overwritten. These scripts do not author native PowerPoint slides.\n"))
  quit(status = 0L)
}

packages <- c("haven", "jsonlite", "survival", "digest", "svglite")
if (!is.null(options[["reference-html"]])) packages <- c(packages, "xml2")
missing <- packages[!vapply(packages, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing)) stop(paste("Install required R packages:", paste(missing, collapse = ", ")))
suppressPackageStartupMessages(library(survival))
input_file <- options[["ir-file"]]
if (is.null(input_file)) input_file <- Sys.getenv("DHS_IR_FILE", unset = "")
if (!nzchar(input_file) || !file.exists(input_file)) stop("Supply an existing --ir-file or DHS_IR_FILE.")
out <- options[["output-dir"]]
if (is.null(out)) out <- file.path("output", tolower(REPORT_STATE))
dir.create(out, recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(out, "validation"), showWarnings = FALSE)
dir.create(file.path(out, "tables"), showWarnings = FALSE)
dir.create(file.path(out, "figures"), showWarnings = FALSE)
integer_option <- function(name, default, minimum = 0L) {
  value <- if (is.null(options[[name]])) default else suppressWarnings(as.integer(options[[name]]))
  if (length(value) != 1L || is.na(value) || value < minimum) stop(paste("Invalid", name))
  value
}
B_DESC <- integer_option("bootstrap-replicates", 999L, 199L)
B_PLAN <- integer_option("planning-replicates", 999L)
if (B_PLAN > 0L && B_PLAN < 199L) stop("Use at least 199 planning replicates, or 0 for point-only checks.")
CORES <- integer_option("cores", 2L, 1L)
WRA_FACTOR <- if (is.null(options[["wra-growth-factor"]])) 57393553 / 55819549.5 else as.numeric(options[["wra-growth-factor"]])
if (!is.finite(WRA_FACTOR) || WRA_FACTOR <= 0) stop("Invalid WRA growth factor.")
input_sha <- digest::digest(file = input_file, algo = "sha256", serialize = FALSE)
if (!is.null(options[["expected-ir-sha256"]]) && input_sha != options[["expected-ir-sha256"]]) stop("IR checksum mismatch.")
x <- tryCatch(if (grepl("[.]dta$", input_file, ignore.case = TRUE)) as.data.frame(haven::read_dta(input_file)) else readRDS(input_file),
              error = function(e) stop("Cannot read supplied IR file."))
required <- c("caseid", "v005", "v008", "v017", "v018", "v019", "v021", "v022", "v024",
              "sstate1", "v312", "v313", "v337", "vcal_1", "vcal_2", "v012")
if (!is.data.frame(x) || !all(required %in% names(x))) stop("Required IR variables are missing.")
if (nrow(x) != 39050L || anyDuplicated(x$caseid)) stop("The input does not match the validated 2024 IR release.")
stopifnot(all(nchar(x$vcal_1) == 80L), all(as.numeric(x$v005) > 0),
          all(as.numeric(x$v012) >= 15 & as.numeric(x$v012) <= 49),
          !anyNA(x[c("v021", "v022", "sstate1", "v313")]))
input_audit <- list(input_sha256 = input_sha, survey = "Nigeria DHS 2024",
                    interviewed_women = nrow(x), valid_calendar_strings = TRUE,
                    unique_woman_ids = TRUE, required_fields_present = TRUE)
jsonlite::write_json(input_audit, file.path(out, "validation", "input_checks.json"), auto_unbox = TRUE, pretty = TRUE)
if (isTRUE(options[["validate-input"]])) { cat("Input validation passed.\n"); quit(status = 0L) }

# The two verified state growth scenarios are fixed annual percentage-point
# changes. No state FPET annual trend is imputed. The 2024 baseline is freshly
# computed from this IR and checked against the values used in the report.
growth_values <- data.frame(state = c("Kano", "Kaduna", "Lagos"),
  dhs2013 = c(0.40105622257234697, 19.440316709608698, 24.8283538255228),
  dhs2018 = c(4.52846023863148, 12.1951018347418, 20.0459324167367),
  dhs2024 = c(7.274615237585929, 10.2196273356621, 25.284294431460303))
growth_inputs <- lapply(seq_len(nrow(growth_values)), function(i) {
  r <- growth_values[i, ]
  list(recent_growth = (r$dhs2024 - r$dhs2018) / 6,
       long_growth = (r$dhs2024 - r$dhs2013) / 11,
       scenarios = list(list(name = "Recent DHS trend (2018–2024)", growth = (r$dhs2024 - r$dhs2018) / 6),
                        list(name = "Longer-term DHS trend (2013–2024)", growth = (r$dhs2024 - r$dhs2013) / 11)))
})
names(growth_inputs) <- growth_values$state

prepare_calendar <- function(x,support) {
# In both vcal fields character position is month. Reverse the stored order
# to work chronologically. The case-specific v019 tells us how many months are
# valid. A maximal continuous run of one vcal_1 character is one episode.
method_codes <- strsplit('123456789WNALCFEMS~','')[[1]]
reason_codes <- c('1'=1L,'2'=2L,'3'=3L,'4'=4L,'5'=5L,'6'=6L,
                  '7'=7L,'8'=8L,'9'=9L,'C'=10L,'F'=11L,'A'=12L,
                  'D'=13L,'M'=15L,'W'=96L,'K'=98L,'?'=99L,' '=0L)
events <- vector('list',nrow(x))
for(i in seq_len(nrow(x))){
  months <- as.integer(x$v019[i])
  cal <- rev(strsplit(x$vcal_1[i],'')[[1]])[seq_len(months)]
  reason_string <- sprintf('%-80s',x$vcal_2[i])
  reasons <- rev(strsplit(reason_string,'')[[1]])[seq_len(months)]
  runs <- rle(cal)
  ends <- cumsum(runs$lengths)
  starts <- ends-runs$lengths+1L
  codes <- match(runs$values,method_codes)
  codes[runs$values=='0'] <- 0L
  codes[runs$values=='B'] <- 81L
  codes[runs$values=='T'] <- 82L
  codes[runs$values=='P'] <- 83L
  codes[runs$values=='?'] <- 99L
  reason_at_end <- unname(reason_codes[reasons[ends]])
  reason <- reason_at_end
  offset <- integer(length(ends))
  for(k in seq_along(ends)){
    pos <- (starts[k]:ends[k])[reasons[starts[k]:ends[k]]!=' ']
    if(length(pos)){
      last <- tail(pos,1)
      reason[k] <- unname(reason_codes[reasons[last]])
      offset[k] <- ends[k]-last
    }
  }
  stopifnot(!anyNA(codes),!anyNA(reason),!anyNA(reason_at_end))
  events[[i]] <- data.frame(woman_row=i,caseid=x$caseid[i],
    event_no=seq_along(codes),wt=as.numeric(x$v005[i])/1e6,
    interview=as.numeric(x$v008[i]),calendar_start=as.numeric(x$v017[i]),
    zone=as.integer(x$v024[i]),state=as.integer(x$sstate1[i]),
    start=as.numeric(x$v017[i])+starts-1L,end=as.numeric(x$v017[i])+ends-1L,
    duration=runs$lengths,method_code=codes,reason_code=reason,
    reason_at_method_end=reason_at_end,reason_offset=offset,
    next_code=c(codes[-1L],NA_integer_),
    next_duration=c(runs$lengths[-1L],NA_integer_),
    next2_code=c(codes,NA_integer_,NA_integer_)[seq_along(codes)+2L])
}
events <- do.call(rbind,events)

# Each use episode may enter the 3–62-month observation window after it began.
# Retain late entrants with their correct duration of entry. An episode only
# contributes to a first-year life table when entry < 12 completed months.
e <- events[events$method_code %in% c(1:20,99) &
              events$start!=events$calendar_start,]
e$start_before_interview <- e$interview-e$start
e$end_before_interview <- e$interview-e$end
e <- e[e$start_before_interview>=3 & e$end_before_interview<=62,]
e$entry <- pmax(e$start_before_interview-62,0)
e$exposure <- e$duration-pmax(3-e$end_before_interview,0)
stopifnot(all(e$exposure>e$entry))
e <- e[e$entry<12,]
# The published "Other" row groups codes 10, 13, 14, 17, and 18. Code 6
# contributes to the all-methods total but not to that printed row.
e$method <- 'Unlisted'
e$method[e$method_code %in% c(10L,13L,14L,17L,18L)] <- 'Other'
e$method[e$method_code==2] <- 'IUD'
e$method[e$method_code==3] <- 'Injectables'
e$method[e$method_code==11] <- 'Implants'
e$method[e$method_code==1] <- 'Pill'
e$method[e$method_code==5] <- 'Male condom'
e$method[e$method_code==16] <- 'Emergency contraception'
e$method[e$method_code==8] <- 'Rhythm'
e$method[e$method_code==9] <- 'Withdrawal'

# Nine mutually exclusive DHS reason groups. Code 2 is wanted pregnancy;
# code 3 is partner disapproval. Codes 9/12/13 are other fertility-related.
reason_group <- function(z){
  result <- rep(9L,length(z))
  mapping <- c('1'=1L,'2'=2L,'9'=3L,'12'=3L,'13'=3L,'15'=4L,
               '4'=5L,'5'=5L,'7'=6L,'6'=7L,'8'=7L,'10'=7L,'3'=8L)
  for(k in names(mapping))result[z==as.integer(k)] <- mapping[[k]]
  result
}
is_method <- function(z)!is.na(z) & z %in% c(1:20,99)
classify <- function(d){
  d$discontinued <- d$end_before_interview>3
  d$reason <- ifelse(d$discontinued,reason_group(d$reason_code),0L)
  d$switched <- d$discontinued & (
    (is_method(d$next_code) & d$next_code!=d$method_code) |
    (d$reason_code==7L & !is.na(d$next_code) & d$next_code==0L &
     !is.na(d$next_duration) & d$next_duration==1L &
     is_method(d$next2_code) & d$next2_code!=d$method_code))
  d$boundary_reason <- FALSE
  for(j in which(d$end_before_interview<=3)){
    row <- d$woman_row[j]
    p <- as.integer(x$v018[row])+3L
    character <- substring(x$vcal_2[row],p,p)
    if(nzchar(trimws(character))){
      rcode <- unname(reason_codes[character])
      d$reason_code[j] <- rcode
      d$reason[j] <- reason_group(rcode)
      d$discontinued[j] <- TRUE
      d$boundary_reason[j] <- TRUE
      next1 <- substring(x$vcal_1[row],p-1L,p-1L)
      next2 <- substring(x$vcal_1[row],p-2L,p-2L)
      d$switched[j] <- next1 %in% method_codes ||
        (rcode==7L && next1=='0' && next2 %in% method_codes &&
         match(next2,method_codes)!=d$method_code[j])
    }
  }
  stopifnot(!anyNA(d$switched),all(d$switched<=d$discontinued))
  d
}
e <- classify(e)
e$episode_id <- seq_len(nrow(e))

# DHS weighted multiple-decrement life table. The sum of reason-specific
# cumulative incidences equals the any-reason probability at every month.
life_table <- function(d){
  survival <- 1
  cif <- numeric(9)
  switched <- 0
  out <- vector('list',12)
  for(t in 1:12){
    at_risk <- d$entry<t & d$exposure>=t
    risk <- sum(d$wt[at_risk])
    ending <- at_risk & d$exposure==t & d$discontinued
    cause <- vapply(1:9,function(k)sum(d$wt[ending & d$reason==k]),numeric(1))
    sw <- sum(d$wt[ending & d$switched])
    if(risk>0){
      cif <- cif+survival*cause/risk
      switched <- switched+survival*sw/risk
      survival <- survival*(1-sum(cause)/risk)
    }
    out[[t]] <- data.frame(month=t,weighted_at_risk=risk,
      weighted_ending=sum(cause),any_reason_pct=100*(1-survival),
      switching_pct=100*switched,t(100*cif))
  }
  z <- do.call(rbind,out)
  names(z)[6:14] <- paste0('reason_',1:9,'_pct')
  stopifnot(max(abs(rowSums(z[paste0('reason_',1:9,'_pct')])-z$any_reason_pct))<1e-8)
  z
}

published_methods <- c('IUD','Injectables','Implants','Pill','Male condom',
                       'Emergency contraception','Rhythm','Withdrawal','Other','All methods')
results <- do.call(rbind,lapply(published_methods,function(m){
  d <- if(m=='All methods')e else e[e$method==m,]
  z <- life_table(d)
  last <- z[z$month==12,]
  data.frame(method=m,as.list(last[paste0('reason_',1:9,'_pct')]),
    any_reason_pct=last$any_reason_pct,switching_pct=last$switching_pct,
    weighted_episodes=sum(d$wt),unweighted_episodes=nrow(d),
    women=length(unique(d$caseid)),late_entries=sum(d$entry>0))
}))
reference <- rbind(
 c(.9,5.3,.3,2.1,5.3,.9,1.2,.4,0,16.3,0,199),
 c(1.9,13.3,2.7,11.4,9.9,2.4,4.1,3.1,3.1,51.9,2.9,2164),
 c(.3,4.2,.5,3,7.1,.9,.7,.5,.8,18.1,.7,2228),
 c(3.7,12.2,6.1,7.2,9.6,8.6,5.8,2.4,1,56.4,4.1,1012),
 c(1.2,8.5,11.6,.1,.2,3.1,4.3,2.1,1.9,33,2.7,1509),
 c(1.2,8.3,11.9,2.2,5.4,6.5,3.2,1.3,2.5,42.6,4.3,273),
 c(2.6,13.8,3,.1,.2,3.5,.8,1.4,.5,26.1,1.3,520),
 c(3,10.9,5.5,.2,.4,6.3,1,1.8,1.5,30.6,4.2,1542),
 c(3,7.7,5.4,2.3,.6,23,2.2,1.6,7.6,53.3,16.8,1207),
 c(1.9,9.3,4.7,4,4.8,5.7,2.7,1.8,2.3,37.2,4.1,10708))
rounded <- cbind(round(as.matrix(results[,2:12]),1),
                 round(results$weighted_episodes))
matching <- rounded==reference
audit <- data.frame(method=published_methods,
  rate_cells_matching=rowSums(matching[,1:11]),
  episode_count_matching=matching[,12],
  max_rate_abs_difference_pp=apply(abs(rounded[,1:11]-reference[,1:11]),1,max),
  weighted_episodes=results$weighted_episodes,
  unweighted_episodes=results$unweighted_episodes,
  late_entries=results$late_entries)
write.csv(results,file.path(support,'nigeria_table_7_12_replicated.csv'),row.names=FALSE)
write.csv(audit,file.path(support,'nigeria_table_7_12_validation.csv'),row.names=FALSE)
monthly <- do.call(rbind,lapply(published_methods,function(m){
  d <- if(m=='All methods')e else e[e$method==m,]
  cbind(method=m,life_table(d))
}))
write.csv(monthly,file.path(support,'nigeria_table_7_12_monthly.csv'),row.names=FALSE)


cat('Exact published rate cells:',sum(matching[,1:11]),'of',length(matching[,1:11]),'\n')
cat('Exact published episode counts:',sum(matching[,12]),'of',nrow(matching),'\n')
if(!all(matching))stop('Nigeria Table 7.12 replication does not yet match every published cell.')

  list(e=e,events=events,controls=list(rate_cells=sum(matching[,1:11]),episode_counts=sum(matching[,12])))
}


describe_states <- function(x,e,B,support) {
# State estimates use the same reconstructed episodes and raw cause codes as
# the national validation above. All other endings remain competing events.
modern <- c(1L,2L,3L,5L,6L,7L,11L,13L,14L,15L,17L,18L,19L,20L)
method_names <- c('Injectables','Implants','Pill','IUD','Other modern')
start_names <- c('Injectables','Implants','Pill','IUD','EC','Other modern','Non-modern methods')
methods <- function(code){v<-rep('Other modern',length(code));v[code==3]<-'Injectables';v[code==11]<-'Implants';v[code==1]<-'Pill';v[code==2]<-'IUD';v}
start_method <- function(code){v<-methods(code);v[!code %in% c(modern,16L)]<-'Non-modern methods';v[code==16L]<-'EC';v}
cause_codes <- list(1L,7L,15L,c(4L,5L),c(6L,8L,10L))
cause_names <- c('Method failure','Wanted a more effective method','Bleeding changes','Other side effects/health','Access/cost/convenience')
action <- unlist(cause_codes);stopifnot(!3L %in% action)
state_map <- c(Kano=16L,Kaduna=15L,Lagos=33L)
e$state_name <- names(state_map)[match(as.numeric(x$sstate1[e$woman_row]),state_map)]
e$method_group<-methods(e$method_code);e$start_method<-start_method(e$method_code)

# Rao-Wu rescaled PSU bootstrap: all survey PSUs, including PSUs with no use
# episodes, are sampled within v022 strata. Every episode of a woman receives
# her PSU's multiplier. Normalized v005 weights are retained in all estimates.
frame<-data.frame(cluster=as.integer(x$v021),stratum=as.integer(x$v022),wt=as.numeric(x$v005)/1e6)
key<-paste(frame$stratum,frame$cluster,sep=':');psu<-unique(frame[c('stratum','cluster')]);psukey<-paste(psu$stratum,psu$cluster,sep=':')
frame$psu<-match(key,psukey);e$psu<-frame$psu[e$woman_row]
stopifnot(B>=199L)
set.seed(20241107L);mult<-matrix(1,nrow(psu),B+1L)
for(h in unique(psu$stratum)){
 ix<-which(psu$stratum==h);n<-length(ix);stopifnot(n>=2L)
 for(b in seq_len(B)) mult[ix,b+1L]<-tabulate(sample.int(n,n-1L,replace=TRUE),nbins=n)*n/(n-1L)
}
wm<-function(d)mult[d$psu,,drop=FALSE]*d$wt
ci<-function(v)as.numeric(quantile(v[-1L],c(.025,.975),na.rm=TRUE,names=FALSE))
ratio<-function(d,selected){w<-wm(d);den<-colSums(w);v<-100*colSums(w[selected,,drop=FALSE])/den;list(value=v[1],low=ci(v)[1],high=ci(v)[2])}
lt<-function(d){
 w<-wm(d);surv<-rep(1,B+1L);cf<-matrix(0,5,B+1L);curve<-vector('list',13)
 curve[[1]]<-data.frame(month=0,percent=0,low=0,high=0)
 for(t in 1:12){
  at<-d$entry<t&d$exposure>=t;ev<-at&d$discontinued&d$exposure==t
  risk<-colSums(w[at,,drop=FALSE]);ends<-colSums(w[ev,,drop=FALSE]);haz<-ifelse(risk>0,ends/risk,0)
  for(k in 1:5){z<-colSums(w[ev&d$reason_code %in% cause_codes[[k]],,drop=FALSE]);cf[k,]<-cf[k,]+surv*ifelse(risk>0,z/risk,0)}
  surv<-surv*(1-haz);v<-100*(1-surv);ints<-ci(v)
  curve[[t+1L]]<-data.frame(month=t,percent=v[1],low=ints[1],high=ints[2])
 }
 curve<-do.call(rbind,curve);tot<-colSums(cf)*100
 shares<-100*sweep(cf,2,colSums(cf),'/');ncause<-sapply(cause_codes,function(a)sum(d$discontinued&d$exposure<=12&d$reason_code %in% a))
 comp<-do.call(rbind,lapply(1:5,function(k){v<-shares[k,];i<-ci(v);data.frame(reason=cause_names[k],percent=v[1],low=if(ncause[k]>0)i[1]else NA_real_,high=if(ncause[k]>0)i[2]else NA_real_,unweighted_endings=ncause[k],cif_percent=100*cf[k,1])}))
 list(curve=curve,actionable=as.list(c(percent=tot[1],low=ci(tot)[1],high=ci(tot)[2])),composition=comp)
}
# Reason-distribution window matches the presentation: recorded endings in
# the 60 calendar months preceding interview, rather than only first-year ends.
reason_map<-c('1'=1L,'2'=2L,'3'=3L,'7'=4L,'M'=5L,'4'=6L,'6'=7L,'C'=8L,'8'=9L,'F'=10L,'A'=11L,'9'=12L,'D'=13L,'W'=14L,'K'=15L,'?'=16L)
method_chars<-strsplit('123456789WNALCFEMS~','')[[1]]
parts<-vector('list',nrow(x))
for(i in seq_len(nrow(x))){
 pos<-as.integer(x$v018[i])+0:59;chars<-substring(sprintf('%-80s',x$vcal_2[i]),pos,pos);keep<-chars!=' '
 if(any(keep))parts[[i]]<-data.frame(woman_row=i,method_code=match(substring(x$vcal_1[i],pos[keep],pos[keep]),method_chars),reason_code=unname(reason_map[chars[keep]]),wt=as.numeric(x$v005[i])/1e6,psu=frame$psu[i])
}
ev<-do.call(rbind,parts);ev<-ev[!is.na(ev$method_code)&!is.na(ev$reason_code),]
# Published Table 7.13 control values, all methods, 16 detailed categories.
published_reason<-c(6.2,34,3.7,12.5,8,11.5,1.5,.8,4.1,1.7,.4,10.1,1.3,3.2,.6,.4)
reason_check<-round(sapply(1:16,function(k)100*sum(ev$wt[ev$reason_code==k])/sum(ev$wt)),1)
stopifnot(max(abs(reason_check-published_reason))<=.2)
write.csv(data.frame(reason_code=1:16,computed=reason_check,published=published_reason),file.path(support,'national_reason_validation.csv'),row.names=FALSE)
ev<-ev[ev$method_code %in% modern,];ev$state_name<-names(state_map)[match(as.numeric(x$sstate1[ev$woman_row]),state_map)]
reason7<-list(2L,5:6,4L,7:9,1L,3L,10:16)
label7<-c('Wanted to become pregnant','Side effects/health','Wanted a more effective method','Access/cost/convenience','Method failure','Partner/spousal disapproval','Other reasons')
groups4<-list(2L,c(1L,4:9),3L,10:16)
label4<-c('Wanted pregnancy / not a program failure','Potentially actionable','Partner/spousal disapproval','Circumstantial/other')
output<-list();audit<-list()
for(state in names(state_map)){
 cat('State:',state,'\n')
 ix<-as.numeric(x$sstate1)==state_map[[state]];cur<-frame[ix,];cur$modern<-as.numeric(x$v313[ix])==3
 mc<-ratio(cur,cur$modern)
 ds<-e[!is.na(e$state_name)&e$state_name==state&e$method_code %in% modern,]
 starts<-e[!is.na(e$state_name)&e$state_name==state&e$entry==0L,]
 mix<-do.call(rbind,lapply(start_names,function(m){r<-ratio(starts,starts$start_method==m);data.frame(method=m,as.data.frame(r),n=sum(starts$start_method==m))}))
 curve<-list();rates<-list()
 for(m in c('All modern',method_names)){
  d<-if(m=='All modern')ds else ds[ds$method_group==m,];r<-lt(d);n1<-sum(d$entry<1&d$exposure>=1)
  flag<-if(n1<125)'suppressed'else if(n1<250)'limited'else 'standard'
  curve[[m]]<-r$curve
  rates[[m]]<-data.frame(method=m,n_episodes=nrow(d),n_month1=n1,n_month12=sum(d$entry<12&d$exposure>=12),first_year_endings=sum(d$discontinued&d$exposure<=12),rate=r$curve$percent[13],low=r$curve$low[13],high=r$curve$high[13],status=flag)
 }
 rates<-do.call(rbind,rates);rownames(rates)<-NULL
 first<-lt(ds);nact<-sum(ds$discontinued&ds$exposure<=12&ds$reason_code %in% action)
 reasons<-ev[!is.na(ev$state_name)&ev$state_name==state,]
 rr<-do.call(rbind,lapply(1:7,function(k){r<-ratio(reasons,reasons$reason_code %in% reason7[[k]]);data.frame(reason=label7[k],as.data.frame(r))}))
 gg<-do.call(rbind,lapply(1:4,function(k){r<-ratio(reasons,reasons$reason_code %in% groups4[[k]]);data.frame(group=label4[k],as.data.frame(r))}))
 stopifnot(abs(sum(mix$value)-100)<1e-8,abs(sum(rr$value)-100)<1e-8,abs(sum(gg$value)-100)<1e-8,abs(sum(first$composition$percent)-100)<1e-8)
 # All observed actionable events exclude raw partner code 3, including all
 # reason-specific probabilities used to normalize the first-year composition.
 stopifnot(!any(ds$reason_code==3 & ds$reason_code %in% action))
 output[[state]]<-list(mcpr=mc,ir_women=nrow(cur),survey_psus=length(unique(cur$psu)),modern_episodes=nrow(ds),women_with_episodes=length(unique(ds$caseid)),starts_n=nrow(starts),starts_weighted=sum(starts$wt),initiation=mix,rates=rates,curves=curve,reason_endings_n=nrow(reasons),reasons=rr,groups=gg,actionable=first$actionable,actionable_endings_n=nact,actionable_event_psus=length(unique(ds$psu[ds$discontinued&ds$exposure<=12&ds$reason_code %in% action])),actionable_composition=first$composition)
 audit[[state]]<-data.frame(state=state,n_women=nrow(cur),modern_episodes=nrow(ds),modern_starts_n1=rates$n_month1[1],actionable_endings=nact,mcpr=mc$value)
}
# National modern first-year risk and five-year reason controls against the
# existing validated national calculations are retained independently.
nat<-e[e$method_code %in% modern,];natw<-lt(nat)
stopifnot(abs(natw$curve$percent[13]-38.0)<2,abs(natw$actionable$percent-21.419905478236)<1e-7)
res<-list(country='Nigeria',survey='2024 DHS',replicates=B,states=output,metadata=list(risk_window='3–62 months before interview; delayed entry and right censoring retained',reasons_window='Recorded modern-method endings in the five-year calendar; no first-year duration restriction',actionable_codes=action,partner_code=3,national_all_cause=natw$curve$percent[13],national_actionable=natw$actionable$percent,full_survey_psus=nrow(psu),full_survey_strata=length(unique(psu$stratum))))

out<-list()
for(state in names(c(Kano=16L,Kaduna=15L,Lagos=33L))){
 code<-c(Kano=16L,Kaduna=15L,Lagos=33L)[state]
 d<-e[as.integer(x$sstate1[e$woman_row])==code&e$method_code%in%modern,]
 w<-mult[d$psu,,drop=FALSE]*d$wt;s<-rep(1,B+1L);cf<-rep(0,B+1L)
 rows<-list(data.frame(month=0,all=0,all_low=0,all_high=0,actionable=0,actionable_low=0,actionable_high=0,n_risk=nrow(d)))
 for(t in 1:12){
  risk<-d$entry<t&d$exposure>=t;end<-risk&d$discontinued&d$exposure==t
  den<-colSums(w[risk,,drop=FALSE]);nend<-colSums(w[end,,drop=FALSE]);act<-colSums(w[end&d$reason_code%in%action,,drop=FALSE])
  cf<-cf+s*ifelse(den>0,act/den,0);s<-s*(1-ifelse(den>0,nend/den,0));all<-100*(1-s);ac<-100*cf
  rows[[t+1L]]<-data.frame(month=t,all=all[1],all_low=ci(all)[1],all_high=ci(all)[2],actionable=ac[1],actionable_low=ci(ac)[1],actionable_high=ci(ac)[2],n_risk=sum(risk))
 }
 z<-do.call(rbind,rows);stopifnot(abs(z$all[13]-res$states[[state]]$rates$rate[1])<1e-8,abs(z$actionable[13]-res$states[[state]]$actionable$percent)<1e-8,abs(z$actionable_low[13]-res$states[[state]]$actionable$low)<1e-8)
 out[[state]]<-z
}

  list(findings=res,timing=out)
}


plan_states <- function(x,e,cal,B,cores,factor) {
states<-c('Kano','Kaduna','Lagos');statecodes<-c(16,15,33);modern<-c(1,2,3,5,6,7,11,13,14,15,17,18,19,20)
codes<-list(1L,7L,15L,c(4L,5L),c(6L,8L,10L));action<-unlist(codes);stopifnot(!3L %in% action)
causes<-c('Method failure','Wanted a more effective method','Bleeding changes','Other side effects/health','Access/cost/convenience')
approaches<-c('First-year probability','Historical duration-aware','AFT survival')
wra_growth<-factor
wt<-as.numeric(x$v005)/1e6;cluster<-as.integer(x$v021);stratum<-as.integer(x$v022)
frame<-unique(data.frame(cluster,stratum));key<-paste(stratum,cluster);fkey<-paste(frame$stratum,frame$cluster);psuid<-match(key,fkey)
strata<-split(seq_len(nrow(frame)),frame$stratum);stopifnot(all(lengths(strata)>1))
# Use the same full-frame bootstrap weights as the descriptive report, so
# the first-year probability and its confidence interval agree across tables.
set.seed(20241107L);bootstrap_mult<-matrix(1,nrow(frame),B+1L)
for(h in unique(frame$stratum)){ix<-which(frame$stratum==h);n<-length(ix);for(b in seq_len(B))bootstrap_mult[ix,b+1L]<-tabulate(sample.int(n,n-1L,replace=TRUE),nbins=n)*n/(n-1L)}
state<-states[match(as.numeric(x$sstate1),statecodes)]
e$state<-state[e$woman_row];e$psu<-psuid[e$woman_row];e<-e[!is.na(e$state)&e$method_code %in% modern,]
cal$state<-state[cal$woman_row];cal$psu<-psuid[cal$woman_row]
# Current users exclude EC for ending-risk calculations; official mCPR includes it.
current<-data.frame(woman=which(!is.na(state)&as.numeric(x$v313)==3&as.numeric(x$v312)%in%modern))
current$state<-state[current$woman];current$elapsed<-as.numeric(x$v337[current$woman]);current$wt<-wt[current$woman];current$psu<-psuid[current$woman]
stopifnot(all(is.finite(current$elapsed)),all(current$elapsed>=0),all(current$elapsed<=95))
bins<-c(-1,3,6,12,24,36,48,60,Inf);blabel<-c('0–3','4–6','7–12','13–24','25–36','37–48','49–60','61+')
current$bin<-as.integer(cut(current$elapsed,bins))
# Complete 12-month historical landmark follow-up. A method ending counts as
# a gross loss irrespective of switching or restarting afterwards.
spells<-cal[!is.na(cal$state)&cal$method_code%in%modern&cal$start>cal$calendar_start,]
records<-vector('list',nrow(spells))
for(i in seq_len(nrow(spells))){
 a<-spells[i,];last<-min(a$end,a$interview-15L);if(last<a$start)next
 t<-seq.int(a$start,last);j<-which(vapply(codes,function(cc)a$reason_code%in%cc,FALSE))
 cause<-if(length(j))j else NA_integer_
 records[[i]]<-data.frame(woman=a$woman_row,episode=i,state=a$state,psu=a$psu,elapsed=t-a$start,wt=a$wt,cause=ifelse(a$end<t+12L,cause,NA_integer_))
}
land<-do.call(rbind,records);land$bin<-as.integer(cut(land$elapsed,bins))
land_index<-list();support<-list()
for(s in states)for(b in 1:8){
 selected<-if(b==8)c(6,7)else b
 z<-which(land$state==s&land$bin%in%selected);n<-length(unique(land$episode[z]));pooling<-if(b==8)'37–60-month proxy for 61+'else 'same duration bin'
 while(n<25 && length(selected)<7){selected<-sort(unique(pmax(1,pmin(7,c(selected,selected-1,selected+1)))));z<-which(land$state==s&land$bin%in%selected);n<-length(unique(land$episode[z]));pooling<-'duration bins pooled until at least 25 unique episodes'}
 stopifnot(n>0);land_index[[paste(s,b)]]<-z
 support[[paste(s,b)]]<-data.frame(state=s,current_duration=blabel[b],historical_bins=paste(blabel[selected],collapse='; '),unique_episodes=n,unique_women=length(unique(land$woman[z])),landmarks=length(z),actionable_ending_episodes=length(unique(land$episode[z[!is.na(land$cause[z])]])),pooling=pooling)
}

af<-e[e$entry==0&e$exposure>0,];af$state<-factor(af$state,levels=states)
af$action<-as.integer(af$discontinued&af$reason_code%in%action);af$other<-as.integer(af$discontinued&!af$reason_code%in%action)
for(j in 1:5)af[[paste0('cause',j)]]<-as.integer(af$discontinued&af$reason_code%in%codes[[j]])
event_vars<-c('action','other',paste0('cause',1:5))
# Match the national selected AFT family. State effects vary, while lognormal
# scale is shared across the three states; methods are pooled, no interaction.
cumhaz<-function(t,mu,scale)-pnorm((log(t)-mu)/scale,lower.tail=FALSE,log.p=TRUE)
measure<-function(mult){
 iw<-wt*mult[psuid];ew<-e$wt*mult[e$psu];cw<-current$wt*mult[current$psu];lw<-land$wt*mult[land$psu]
 risks<-array(0,c(3,3,5),dimnames=list(approaches,states,causes));pp<-risks;stock<-numeric(3);names(stock)<-states
 fits<-lapply(event_vars,function(ev){
  d<-af;d$fw<-d$wt*mult[d$psu];d<-d[d$fw>0,]
  active<-states[vapply(states,function(s)sum(d[[ev]][d$state==s])>0,FALSE)]
  d<-d[d$state%in%active,];d$state<-droplevels(d$state)
  form<-as.formula(paste0('Surv(exposure,',ev,')~',if(length(active)>1)'state'else '1'))
  fit<-suppressWarnings(survreg(form,data=d,weights=fw,dist='lognormal',control=survreg.control(maxiter=300)))
  if(fit$iter>=300||any(!is.finite(coef(fit)))||!is.finite(fit$scale))stop('AFT convergence')
  attr(fit,'active')<-active;fit
 })
 for(s in states){
  ii<-which(state==s);p24<-100*sum(iw[ii][as.numeric(x$v313[ii])==3])/sum(iw[ii])
  frac<-sum(iw[ii][as.numeric(x$v313[ii])==3&as.numeric(x$v312[ii])%in%modern])/sum(iw[ii][as.numeric(x$v313[ii])==3])
  stock[s]<-1000*p24*frac # observed 2024 non-EC users per 100,000 2024 WRA
  de<-which(e$state==s);surv<-1;v<-numeric(5)
  for(t in 1:12){at<-de[e$entry[de]<t&e$exposure[de]>=t];den<-sum(ew[at]);if(den<=0)next
   ending<-at[e$discontinued[at]&e$exposure[at]==t];h<-vapply(codes,function(cc)sum(ew[ending[e$reason_code[ending]%in%cc]])/den,0.0)
   v<-v+surv*h;surv<-surv*(1-sum(ew[ending])/den)}
  risks[1,s,]<-v
  ci<-which(current$state==s);ctotal<-sum(cw[ci]);for(b in 1:8){share<-sum(cw[ci[current$bin[ci]==b]])/ctotal;if(share==0)next
   z<-land_index[[paste(s,b)]];den<-sum(lw[z]);if(den<=0)stop('Empty historical bootstrap cell')
   for(j in 1:5)risks[2,s,j]<-risks[2,s,j]+share*sum(lw[z][!is.na(land$cause[z])&land$cause[z]==j])/den}
  ages<-0:(max(current$elapsed[ci])+12L)
  hh<-sapply(fits,function(f){if(!s%in%attr(f,'active'))return(rep(0,length(ages)-1L));mu<-as.numeric(predict(f,newdata=data.frame(state=factor(s,levels=attr(f,'active'))),type='lp'));pmax(diff(cumhaz(ages,mu,f$scale)),0)})
  for(a in unique(current$elapsed[ci])){
   share<-sum(cw[ci[current$elapsed[ci]==a]])/ctotal;if(share==0)next
   h<-hh[a+1:12,,drop=FALSE];total<-rowSums(h[,1:2,drop=FALSE]);sv<-c(1,exp(-cumsum(total)))[1:12]
   pa<-sv*(-expm1(-total))*ifelse(total>0,h[,1]/total,0)
   cs<-h[,3:7,drop=FALSE]/pmax(rowSums(h[,3:7,drop=FALSE]),1e-300)
   risks[3,s,]<-risks[3,s,]+share*colSums(pa*cs)
  }
  pp[,s,]<-risks[,s,]*stock[s]/(1000*wra_growth)
 }
 stopifnot(all(is.finite(risks)),all(risks>=0),all(apply(risks,c(1,2),sum)<=1+1e-8))
 list(risk=risks,pp=pp,stock=stock)
}

point<-measure(rep(1,nrow(frame)))
cat('Planning point estimates computed.\n');flush.console()
one<-function(b)tryCatch(measure(bootstrap_mult[,b+1L]),error=function(e)list(error=conditionMessage(e)))
res<-if(B>0L) {
 if(.Platform$OS.type=='windows'||cores==1L)lapply(seq_len(B),one) else parallel::mclapply(seq_len(B),one,mc.cores=cores,mc.preschedule=TRUE)
} else list()
valid<-if(B>0L)!vapply(res,function(z)!is.null(z$error),FALSE)else logical()
if(B>0L&&mean(valid)<.95)stop('Fewer than 95% of planning bootstrap replicates converged.')
if(B>0L&&any(!valid))warning('Some planning replicates failed; joint summaries retain matching replicate indices.')
list(point=point,draws=res[valid],valid_indices=which(valid),support=do.call(rbind,support),requested_replicates=B)
}


summary_value <- function(value, draws) {
  q <- if (length(draws)) as.numeric(quantile(draws, c(.025, .975), names = FALSE)) else c(NA_real_, NA_real_)
  list(value = as.numeric(value), low = q[1], high = q[2])
}

prepare_display <- function(x, plan, growth, factor) {
  states <- c("Kano", "Kaduna", "Lagos"); codes <- c(16L, 15L, 33L)
  wt <- as.numeric(x$v005)/1e6
  frame <- unique(data.frame(cluster = as.integer(x$v021), stratum = as.integer(x$v022)))
  psu <- match(paste(as.integer(x$v022), as.integer(x$v021)), paste(frame$stratum, frame$cluster))
  B <- plan$requested_replicates
  set.seed(20241107L); mult <- matrix(1, nrow(frame), B + 1L)
  for (h in unique(frame$stratum)) {
    ii <- which(frame$stratum == h); n <- length(ii)
    if (B) for (b in seq_len(B)) mult[ii,b+1L] <- tabulate(sample.int(n,n-1L,replace=TRUE),nbins=n)*n/(n-1L)
  }
  keep <- c(1L, plan$valid_indices + 1L); mult <- mult[,keep,drop=FALSE]
  result <- list()
  for (i in seq_along(states)) {
    s <- states[i]; sel <- as.numeric(x$sstate1) == codes[i]
    ww <- mult[psu[sel],,drop=FALSE] * wt[sel]
    p24 <- 100 * colSums(ww[as.numeric(x$v313[sel])==3,,drop=FALSE])/colSums(ww)
    stopifnot(abs(p24[1]-growth_values$dhs2024[i])<1e-8)
    stock <- c(plan$point$stock[s], vapply(plan$draws, function(z)z$stock[s], 0.0))
    total <- p24*1000
    ec <- pmax(0,total-stock); if (ec[1]<1e-8) ec[1] <- 0
    z <- list(baseline2024=summary_value(p24[1],p24[-1L]),
              reference2024=summary_value(p24[1],p24[-1L]),
              current_total=summary_value(total[1],total[-1L]),
              current_non_ec=summary_value(stock[1],stock[-1L]),
              current_ec=summary_value(ec[1],ec[-1L]),approaches=list())
    for (approach in dimnames(plan$point$risk)[[1]]) {
      pr <- sum(plan$point$risk[approach,s,]); rp <- vapply(plan$draws,function(d)sum(d$risk[approach,s,]),0.0)
      ending <- pr*stock[1]; be <- rp*stock[-1L]
      pp <- 100*ending/(100000*factor); bp <- 100*be/(100000*factor)
      ca <- list()
      for (cause in dimnames(plan$point$risk)[[3]]) {
        rv <- plan$point$risk[approach,s,cause]
        rb <- vapply(plan$draws,function(d)d$risk[approach,s,cause],0.0)
        ev <- rv*stock[1]; eb <- rb*stock[-1L]
        ca[[cause]] <- list(risk=summary_value(100*rv,100*rb),endings=summary_value(ev,eb),
                           pp=summary_value(100*ev/(100000*factor),100*eb/(100000*factor)))
      }
      scenarios <- lapply(growth[[s]]$scenarios,function(sc) {
        m25 <- p24+sc$growth; users <- m25*1000*factor
        list(name=sc$name,growth=sc$growth,mcpr2025=summary_value(m25[1],m25[-1L]),
             users_usual=summary_value(users[1],users[-1L]),
             users_retained=summary_value(users[1]+ending,users[-1L]+be),
             mcpr_retained=summary_value(m25[1]+pp,m25[-1L]+bp))
      })
      z$approaches[[approach]] <- list(risk=summary_value(100*pr,100*rp),
          endings=summary_value(ending,be),pp=summary_value(pp,bp),causes=ca,scenarios=scenarios)
      stopifnot(abs(sum(vapply(ca,function(c)c$pp$value,0.0))-pp)<1e-9,
                abs(sum(vapply(ca,function(c)c$endings$value,0.0))-ending)<1e-7)
      for (sc in scenarios) stopifnot(abs(sc$mcpr_retained$value-sc$mcpr2025$value-pp)<1e-9,
          abs(100*sc$users_retained$value/(100000*factor)-sc$mcpr_retained$value)<1e-9)
    }
    result[[s]] <- z
  }
  list(states=result,reference_year=2024L,outcome_year=2025L,reference_wra=100000,
       outcome_wra=100000*factor,wra_growth_factor=factor,
       bootstrap_replicates=length(plan$draws))
}

fmt <- function(x,d=1L) formatC(x,format="f",digits=d,big.mark=",")
stat <- function(v,unit="",digits=2L) {
  if (!is.finite(v$low)||!is.finite(v$high)) return(paste0(fmt(v$value,digits),unit," (interval not computed)"))
  paste0(fmt(v$value,digits),unit,"\n(",fmt(v$low,digits),"–",fmt(v$high,digits),")")
}
interval <- function(value,low,high) paste0(fmt(value),"% (",fmt(low),"–",fmt(high),")")
method_sparse <- function(r) r$n_month1<25L | r$first_year_endings<5L
method_flag <- function(r) ifelse(method_sparse(r),"‡",ifelse(r$n_month1<125L,"†",ifelse(r$n_month1<250L,"*","")))

display_tables <- function(state,d,t,q,factor,growth) {
  k <- tolower(state); tabs <- list()
  add <- function(suffix,header,rows) {
    m <- rbind(header,do.call(rbind,rows)); storage.mode(m) <- "character"
    tabs[[paste0(k,"-",suffix)]] <<- m
  }
  add("initiation",c("Method","Share, % (95% CI)","Observed starts"),
      lapply(seq_len(nrow(d$initiation)),function(i){r<-d$initiation[i,];c(r$method,interval(r$value,r$low,r$high),r$n)}))
  add("starts-risk",c("Time since method start","All-cause cumulative discontinuation, % (95% CI)","Episodes exposed at that month"),
      lapply(c(3,6,9,12),function(m){r<-t[t$month==m,];c(paste(m,"months"),interval(r$all,r$all_low,r$all_high),r$n_risk)}))
  r <- d$reasons[order(-d$reasons$value),]
  add("all-reasons",c("Stated reason","Share, % (95% CI)"),lapply(seq_len(nrow(r)),function(i)c(r$reason[i],interval(r$value[i],r$low[i],r$high[i]))))
  r <- d$groups
  add("groups",c("Reason group","Share, % (95% CI)"),lapply(seq_len(nrow(r)),function(i)c(r$group[i],interval(r$value[i],r$low[i],r$high[i]))))
  add("actionable-timing",c("Time since method start","Actionable cumulative discontinuation, % (95% CI)","Episodes exposed at that month"),
      lapply(c(3,6,9,12),function(m){r<-t[t$month==m,];c(paste(m,"months"),interval(r$actionable,r$actionable_low,r$actionable_high),r$n_risk)}))
  r <- d$actionable_composition[order(-d$actionable_composition$percent),]
  add("actionable-reasons",c("Actionable cause","Share, % (95% CI)","Observed first-year endings"),
      lapply(seq_len(nrow(r)),function(i)c(r$reason[i],interval(r$percent[i],r$low[i],r$high[i]),r$unweighted_endings[i])))
  add("growth",c("Different mCPR\ngrowth scenarios","Annual change\n(pp/year)","2024 DHS\nmCPR","Projected 2025\nmCPR"),
      lapply(growth$scenarios,function(sc)c(sc$name,sprintf("%+.2f",sc$growth),paste0(fmt(d$mcpr$value,2),"%"),paste0(fmt(d$mcpr$value+sc$growth,2),"%"))))
  cause_order <- names(q$approaches[[1]]$causes)
  heads <- c("Method\nfailure","Want more\neffective","Bleeding\nchanges","Other side\neffects/health","Access/cost/\nconvenience")
  marks <- d$actionable_composition$unweighted_endings[match(cause_order,d$actionable_composition$reason)]<10
  heads[marks] <- sub("^([^/[:space:]]+)","\\1†",heads[marks])
  for (i in seq_along(q$approaches)) {
    a <- q$approaches[[i]]; prefix <- c("firstyear","historical","aft")[i]
    add(paste0(prefix,"-users"),c("User group","2024 observed\nusers","Potentially actionable\ndiscontinuation","Users ending\noriginal method","mCPR equivalent\n(pp)"),list(
      c("Modern methods\n(excluding EC)",stat(q$current_non_ec,"",0),stat(a$risk,"%",1),stat(a$endings,"",0),stat(a$pp," pp")),
      c("EC (outside ending analysis)",if(q$current_ec$value==0)"0\n(none observed)"else stat(q$current_ec,"",0),"Not applied","Not estimated","Not estimated"),
      c("All modern users",stat(q$current_total,"",0),"See non-EC risk",stat(a$endings,"",0),stat(a$pp," pp"))))
    add(paste0(prefix,"-causeusers"),c("Measure",heads,"All actionable\ncauses"),list(
      c("Potentially actionable\ndiscontinuation (%)",vapply(a$causes,function(c)stat(c$risk,"%",1),""),stat(a$risk,"%",1)),
      c("Users ending\noriginal method",vapply(a$causes,function(c)stat(c$endings,"",0),""),stat(a$endings,"",0))))
    add(paste0(prefix,"-scenarios"),c("Different mCPR\ngrowth scenarios","2025 users\nusual scenario","2025\nmCPR","2025 users\nif retained","mCPR\nif retained","Increase\n(pp)"),
      lapply(a$scenarios,function(sc)c(sc$name,stat(sc$users_usual,"",0),stat(sc$mcpr2025,"%",2),stat(sc$users_retained,"",0),stat(sc$mcpr_retained,"%",2),stat(a$pp," pp"))))
    add(paste0(prefix,"-causepp"),c("Measure",heads,"All actionable\ncauses"),list(
      c("Users ending\noriginal method",vapply(a$causes,function(c)stat(c$endings,"",0),""),stat(a$endings,"",0)),
      c("2025 women aged\n15–49 (fixed)",rep(fmt(100000*factor,0),6)),
      c("mCPR increase (pp)",vapply(a$causes,function(c)stat(c$pp," pp"),""),stat(a$pp," pp"))))
  }
  r <- d$rates[-1,]
  add("method-rates-exploratory",c("Method","Month-1 episodes","First-year endings","12-month rate, % (95% CI)","Precision"),
      lapply(seq_len(nrow(r)),function(i){v<-r[i,];c(paste0(v$method,method_flag(v)),v$n_month1,v$first_year_endings,
       if(method_sparse(v))"Insufficient data"else interval(v$rate,v$low,v$high),
       if(method_sparse(v))"Very sparse"else if(v$n_month1<125)"Exploratory only"else"Interpret cautiously")}))
  stopifnot(length(tabs)==20L)
  tabs
}

plot_outputs <- function(state,d,t,folder) {
  C <- c(navy="#173F59",teal="#108B8D",gold="#DA9A25",coral="#E65845",gray="#87939F",pink="#BD5A8D",brown="#A48B68",purple="#6553A1")
  mc <- c(Injectables=C["teal"],Implants=C["navy"],Pill=C["gold"],IUD=C["coral"],EC=C["pink"],"Other modern"=C["gray"],"Non-modern methods"=C["brown"])
  names(mc) <- c("Injectables","Implants","Pill","IUD","EC","Other modern","Non-modern methods")
  open_svg <- function(name) {svglite::svglite(file.path(folder,paste0(name,".svg")),width=13.333,height=7.5,bg="white");par(family="Arial",cex=1.2,col.axis="#17232C",col.lab="#17232C",las=1)}
  bars <- function(file,labels,values,colors,title) {
    open_svg(file);par(mar=c(4,16,5,3));n<-length(values)
    y<-barplot(rev(values),names.arg=rev(labels),horiz=TRUE,col=rev(colors),border=NA,xlim=c(0,max(60,ceiling(max(values)/20)*20)),cex.names=1.0,xlab="Percent",main=paste(state,title,sep=": "))
    text(rev(values)+.8,y,labels=fmt(rev(values)),pos=4,cex=1.05);dev.off()
  }
  bars("initiation_mix",d$initiation$method,d$initiation$value,mc[d$initiation$method],"Method initiation mix")
  for (kind in c("all","actionable")) {
    open_svg(paste0("pooled_",kind,"_timing"));par(mar=c(5,6,5,3))
    v<-t[[kind]];lo<-t[[paste0(kind,"_low")]];hi<-t[[paste0(kind,"_high")]]
    col<-if(kind=="all")C["navy"]else C["teal"];upper<-if(kind=="all") 80 else 60
    plot(t$month,v,type="n",xaxt="n",xlim=c(0,12),ylim=c(0,upper),xaxs="i",yaxs="i",xlab="Months since method initiation",ylab="Cumulative discontinuation (%)",
         main=paste(state,if(kind=="all")"All-cause modern-method discontinuation"else"Potentially actionable discontinuation",sep=": "))
    axis(1,at=c(0,3,6,9,12),labels=c("0","3","6","9","12"));abline(h=seq(0,upper,10),col="#E0E7EC")
    lines(t$month,v,type="s",col=col,lwd=3)
    ii<-match(c(3,6,9,12),t$month);arrows(t$month[ii],lo[ii],t$month[ii],hi[ii],angle=90,code=3,length=.07,col=col)
    legend("topleft",sprintf("12 months: %.1f%% (95%% CI %.1f–%.1f%%)",v[13],lo[13],hi[13]),bty="n",text.col=col,cex=1)
    dev.off()
  }
  r<-d$reasons[order(-d$reasons$value),];rc<-c("Wanted to become pregnant"=C["teal"],"Side effects/health"=C["coral"],"Wanted a more effective method"=C["gold"],"Access/cost/convenience"=C["navy"],"Method failure"=C["purple"],"Partner/spousal disapproval"=C["pink"],"Other reasons"=C["gray"]);names(rc)<-c("Wanted to become pregnant","Side effects/health","Wanted a more effective method","Access/cost/convenience","Method failure","Partner/spousal disapproval","Other reasons")
  bars("all_recorded_reasons",r$reason,r$value,rc[r$reason],"Reasons among five-year recorded endings")
  bars("four_reason_groups",d$groups$group,d$groups$value,C[c("teal","navy","pink","gray")],"Four distinct reason groups")
  r<-d$actionable_composition[order(-d$actionable_composition$percent),];ac<-setNames(C[c("purple","gold","coral","navy","teal")],d$actionable_composition$reason)
  bars("actionable_reason_composition",r$reason,r$percent,ac[r$reason],"Reasons among actionable first-year endings")
  open_svg("exploratory_method_curves");par(mar=c(5,6,5,3));plot(c(0,12),c(0,100),type="n",xaxt="n",xaxs="i",yaxs="i",xlab="Months since method initiation",ylab="Cumulative discontinuation (%)",main=paste(state,"Exploratory method-specific curves",sep=": "));axis(1,at=c(0,3,6,9,12));abline(h=seq(0,100,20),col="#E0E7EC")
  r<-d$rates[-1,];r<-r[!method_sparse(r),];r<-r[order(-r$rate),]
  for(i in seq_len(nrow(r)))lines(d$curves[[r$method[i]]]$month,d$curves[[r$method[i]]]$percent,type="s",col=mc[r$method[i]],lwd=3)
  legend("topleft",paste0(r$method,method_flag(r),": ",fmt(r$rate),"%"),col=mc[r$method],lwd=3,bty="n",cex=1)
  dev.off()
}

# A state-specific entry point deliberately retains the full survey frame and
# the joint three-state AFT fit. Only aggregate outputs for REPORT_STATE are exported.
script_arg <- grep("^--file=",commandArgs(),value=TRUE)
code_signature <- if(length(script_arg)) {
  code <- readLines(sub("^--file=","",script_arg[1]),warn=FALSE)
  code <- sub('^REPORT_STATE <- .*$', 'REPORT_STATE <- "STATE"',code)
  digest::digest(paste(code,collapse="\n"),algo="sha256",serialize=FALSE)
} else ANALYSIS_VERSION
key <- digest::digest(list(version=ANALYSIS_VERSION,code=code_signature,input=input_sha,
                           descriptive_replicates=B_DESC,planning_replicates=B_PLAN,wra_factor=WRA_FACTOR),algo="sha256")
cache_dir <- options[["cache-dir"]];if(is.null(cache_dir))cache_dir<-file.path(out,".aggregate_cache")
dir.create(cache_dir,recursive=TRUE,showWarnings=FALSE);cache_file<-file.path(cache_dir,paste0(key,".rds"))
if(file.exists(cache_file)&&!isTRUE(options[["no-cache"]])) {
  bundle<-readRDS(cache_file);stopifnot(identical(bundle$key,key));cat("Using matching aggregate analysis cache.\n")
} else {
  cat("Reconstructing the full calendar and validating national controls.\n")
  prepared<-prepare_calendar(x,file.path(out,"validation"))
  cat("Computing weighted descriptive estimates and pooled timing.\n")
  descriptive<-describe_states(x,prepared$e,B_DESC,file.path(out,"validation"))
  cat("Fitting duration-aware planning calculations and survey replicates.\n")
  planning<-plan_states(x,prepared$e,prepared$events,B_PLAN,CORES,WRA_FACTOR)
  display<-prepare_display(x,planning,growth_inputs,WRA_FACTOR)
  bundle<-list(key=key,descriptive=descriptive,display=display,
               historical_support=planning$support,national_controls=prepared$controls,
               planning_valid_replicates=length(planning$draws))
  saveRDS(bundle,cache_file)
  rm(prepared,descriptive,planning,display);gc(verbose=FALSE)
}
d<-bundle$descriptive$findings$states[[REPORT_STATE]]
t<-bundle$descriptive$timing[[REPORT_STATE]]
q<-bundle$display$states[[REPORT_STATE]]
tables<-display_tables(REPORT_STATE,d,t,q,WRA_FACTOR,growth_inputs[[REPORT_STATE]])
for(name in names(tables))write.table(tables[[name]],file.path(out,"tables",paste0(name,".csv")),sep=",",row.names=FALSE,col.names=FALSE,quote=TRUE,na="")
write.csv(t,file.path(out,"pooled_monthly_discontinuation.csv"),row.names=FALSE)
write.csv(d$rates,file.path(out,"method_samples_and_analytic_rates.csv"),row.names=FALSE)
write.csv(bundle$historical_support[bundle$historical_support$state==REPORT_STATE,],file.path(out,"historical_duration_support.csv"),row.names=FALSE)
write.csv(growth_values[growth_values$state==REPORT_STATE,],file.path(out,"growth_baselines.csv"),row.names=FALSE)
jsonlite::write_json(list(state=REPORT_STATE,descriptive=d,timing=t,planning=q,
  reference_year=2024L,outcome_year=2025L,reference_wra=100000,outcome_wra=100000*WRA_FACTOR),
  file.path(out,"analysis_results.json"),pretty=TRUE,auto_unbox=TRUE,na="null",digits=12)
plot_outputs(REPORT_STATE,d,t,file.path(out,"figures"))

checks<-list(national_rate_cells=110L,national_episode_counts=10L,
             actionable_excludes_partner_disapproval=TRUE,modern_risks_exclude_ec=TRUE,
             mcpr_includes_ec=TRUE,full_survey_frame=TRUE,timing_ticks=c(0,3,6,9,12),
             displayed_tables=length(tables),reference_year=2024L,outcome_year=2025L,
             historical_and_aft_switching_deduction=FALSE,
             state_counts_normalized_per_100000_wra_2024=TRUE,
             descriptive_bootstrap_replicates=B_DESC,planning_valid_replicates=bundle$planning_valid_replicates)
if(!is.null(options[["reference-html"]])) {
  doc<-xml2::read_html(options[["reference-html"]]);normalize<-function(x)gsub("[[:space:]\u00a0]+","",x,perl=TRUE)
  reconciliation<-list()
  for(sid in names(tables)) {
    section<-xml2::xml_find_all(doc,paste0('//*[@id="',sid,'"]//table'))
    stopifnot(length(section)==1L)
    rows<-xml2::xml_find_all(section,".//tr")
    saved<-lapply(rows,function(r)xml2::xml_text(xml2::xml_find_all(r,"./th|./td")))
    fresh<-tables[[sid]]
    match<-length(saved)==nrow(fresh)&&all(lengths(saved)==ncol(fresh))
    if(match)match<-identical(unname(normalize(as.vector(t(do.call(rbind,saved))))),unname(normalize(as.vector(t(fresh)))))
    reconciliation[[sid]]<-list(match=match,rows=nrow(fresh),columns=ncol(fresh))
  }
  jsonlite::write_json(reconciliation,file.path(out,"validation","html_table_reconciliation.json"),pretty=TRUE,auto_unbox=TRUE)
  checks$html_tables_matching<-sum(vapply(reconciliation,function(x)x$match,FALSE))
  if(checks$html_tables_matching!=20L)stop("Some regenerated tables differ from the supplied HTML; inspect the reconciliation output.")
}
manifest<-list(analysis_version=ANALYSIS_VERSION,state=REPORT_STATE,input_sha256=input_sha,
               code_sha256=code_signature,seed=20241107L,checks=checks,
               packages=setNames(lapply(packages,function(p)as.character(packageVersion(p))),packages),
               r_version=as.character(getRversion()),
               assumptions=c("2024 observed non-EC current-user cohort held fixed across 2025 growth scenarios",
                 "2025 WRA growth uses the fixed national UN ratio as a state assumption",
                 "Gross actionable original-method endings; switching and restarting not deducted",
                 "AFT includes state effects and a common lognormal scale across the three states",
                 "Historical bins pool adjacent durations; longest durations use a shorter-duration proxy",
                 "Growth and population uncertainty are excluded from survey confidence intervals"))
jsonlite::write_json(manifest,file.path(out,"validation","analysis_manifest.json"),pretty=TRUE,auto_unbox=TRUE)
cat(REPORT_STATE,"complete. Aggregate tables, figures and validation checks saved.\n")

