# Import the original woman-level IR file and reconstruct chronological runs.
# No precomputed episode files or national-report project are required.
prepare_ir <- function(input, country, destination) {
  required <- c('caseid','v000','v005','v008','v011','v012','v017','v018',
                'v019','v021','v022','v024','v025','v201','vcal_1','vcal_2')
  if(country=='Nigeria') required <- c(required,'sstate')
  ext <- tolower(tools::file_ext(input))
  if(!ext %in% c('dta','rds') || !file.exists(input))
    stop('Supply an existing authorized IR .dta or lossless .rds input.',call.=FALSE)
  x <- tryCatch(if(ext=='dta') as.data.frame(haven::read_dta(input)) else readRDS(input),
                error=function(e)stop('Could not import the supplied IR input.',call.=FALSE))
  if(!is.data.frame(x) || !all(required %in% names(x)))
    stop('IR input is missing required variables.',call.=FALSE)
  expected <- list(Ethiopia=c(21395L,797L,27L),Nigeria=c(39050L,1380L,74L),
                   DRC=c(27583L,778L,51L))[[country]]
  phase <- c(Ethiopia='ET8',Nigeria='NG8',DRC='CD8')[[country]]
  frame <- unique(data.frame(psu=as.integer(x$v021),stratum=as.integer(x$v022)))
  stopifnot(nrow(x)==expected[1],nrow(frame)==expected[2],
    length(unique(frame$stratum))==expected[3],all(as.character(x$v000)==phase),
    !anyDuplicated(x$caseid),!anyNA(x$caseid),!anyNA(frame),
    all(table(frame$stratum)>1L),all(as.numeric(x$v005)>0),
    all(as.numeric(x$v012) %in% 15:49),
    all(as.numeric(x$v008)-as.numeric(x$v017)+1==as.numeric(x$v019)),
    all(as.numeric(x$v018)+as.numeric(x$v019)==81),
    all(nchar(x$vcal_1)==80L),all(nchar(x$vcal_2)<=80L),
    !anyNA(x$vcal_1),!anyNA(x$vcal_2),
    length(grep('^b3_[0-9]+$',names(x)))>0)
  if(is.null(attr(x$v024,'labels'))) stop('Retain original geography value labels.')
  if(country=='Nigeria' && is.null(attr(x$sstate,'labels')))
    stop('Retain original state value labels.')
  method_chars <- strsplit('123456789WNALCFEMS~','')[[1]]
  reason_codes <- c('1'=1L,'2'=2L,'3'=3L,'4'=4L,'5'=5L,'6'=6L,
    '7'=7L,'8'=8L,'9'=9L,'C'=10L,'F'=11L,'A'=12L,'D'=13L,
    'M'=15L,'W'=96L,'K'=98L,'?'=99L,' '=0L)
  events <- vector('list',nrow(x))
  for(i in seq_len(nrow(x))) {
    # Stored calendars run backwards in time. Pad reason strings on the right;
    # stripping their spaces would destroy alignment with calendar months.
    n <- as.integer(x$v019[i])
    cal <- rev(strsplit(x$vcal_1[i],'')[[1]])[seq_len(n)]
    why <- rev(strsplit(sprintf('%-80s',x$vcal_2[i]),'')[[1]])[seq_len(n)]
    runs <- rle(cal);ends <- cumsum(runs$lengths)
    starts <- ends-runs$lengths+1L
    code <- match(runs$values,method_chars)
    code[runs$values=='0']<-0L;code[runs$values=='B']<-81L
    code[runs$values=='T']<-82L;code[runs$values=='P']<-83L
    code[runs$values=='?']<-99L
    at_end <- unname(reason_codes[why[ends]])
    reason <- at_end;offset <- integer(length(ends))
    # Preserve the established reason recovery convention: use the last
    # nonblank reason recorded inside the same uninterrupted method run.
    for(k in seq_along(ends)) {
      pos <- (starts[k]:ends[k])[why[starts[k]:ends[k]]!=' ']
      if(length(pos)) {
        last <- tail(pos,1);reason[k]<-unname(reason_codes[why[last]])
        offset[k]<-ends[k]-last
      }
    }
    stopifnot(!anyNA(code),!anyNA(reason),!anyNA(at_end))
    events[[i]] <- data.frame(woman_row=i,caseid=x$caseid[i],event_no=seq_along(code),
      wt=as.numeric(x$v005[i])/1e6,interview=as.numeric(x$v008[i]),
      calendar_start=as.numeric(x$v017[i]),region=as.integer(x$v024[i]),
      start=as.numeric(x$v017[i])+starts-1L,end=as.numeric(x$v017[i])+ends-1L,
      duration=runs$lengths,method_code=code,reason_code=reason,
      reason_at_method_end=at_end,reason_offset=offset,
      next_code=c(code[-1L],NA_integer_),next_duration=c(runs$lengths[-1L],NA_integer_),
      next2_code=c(code,NA_integer_,NA_integer_)[seq_along(code)+2L])
  }
  events <- do.call(rbind,events)
  e <- events[events$method_code %in% c(1:20,99) &
                events$start!=events$calendar_start,]
  e$start_before_interview <- e$interview-e$start
  e$end_before_interview <- e$interview-e$end
  e <- e[e$start_before_interview>=3 & e$end_before_interview<=62,]
  e$entry <- pmax(e$start_before_interview-62,0)
  e$exposure <- e$duration-pmax(3-e$end_before_interview,0)
  stopifnot(all(e$exposure>e$entry))
  e <- e[e$entry<12,]
  reason_group <- function(z) {
    out <- rep(9L,length(z))
    map <- c('1'=1L,'2'=2L,'9'=3L,'12'=3L,'13'=3L,'15'=4L,
      '4'=5L,'5'=5L,'7'=6L,'6'=7L,'8'=7L,'10'=7L,'3'=8L)
    for(k in names(map))out[z==as.integer(k)]<-map[[k]]
    out
  }
  is_method <- function(z)!is.na(z)&z %in% c(1:20,99)
  e$discontinued <- e$end_before_interview>3
  e$reason <- ifelse(e$discontinued,reason_group(e$reason_code),0L)
  e$switched <- e$discontinued & (
    (is_method(e$next_code)&e$next_code!=e$method_code) |
    (e$reason_code==7L & !is.na(e$next_code)&e$next_code==0L &
     !is.na(e$next_duration)&e$next_duration==1L &
     is_method(e$next2_code)&e$next2_code!=e$method_code))
  e$boundary_reason <- FALSE
  # Preserve the report-matching convention at interview minus three months.
  for(j in which(e$end_before_interview<=3)) {
    row <- e$woman_row[j];p <- as.integer(x$v018[row])+3L
    ch <- substring(x$vcal_2[row],p,p)
    if(nzchar(trimws(ch))) {
      rc<-unname(reason_codes[ch]);e$reason_code[j]<-rc
      e$reason[j]<-reason_group(rc);e$discontinued[j]<-TRUE
      e$boundary_reason[j]<-TRUE
      c1<-substring(x$vcal_1[row],p-1L,p-1L)
      c2<-substring(x$vcal_1[row],p-2L,p-2L)
      e$switched[j]<-c1 %in% method_chars |
        (rc==7L & c1=='0' & c2 %in% method_chars & match(c2,method_chars)!=e$method_code[j])
    }
  }
  e$episode_id<-seq_len(nrow(e))
  stopifnot(!anyNA(e$reason_code),!anyNA(e$switched),all(e$switched<=e$discontinued))
  dir.create(destination,recursive=TRUE,showWarnings=FALSE)
  saveRDS(x,file.path(destination,'ir.rds'))
  saveRDS(events,file.path(destination,'calendar.rds'))
  saveRDS(e,file.path(destination,'episodes.rds'))
  # The validation record contains counts and an integrity digest, never a path.
  jsonlite::write_json(list(country=country,women=nrow(x),psus=nrow(frame),
    strata=length(unique(frame$stratum)),calendar_runs=nrow(events),episodes=nrow(e),
    input_sha256=digest::digest(file=input,algo='sha256'),
    unique_women=TRUE,calendar_alignment=TRUE,original_input_modified=FALSE),
    file.path(destination,'input_validation.json'),auto_unbox=TRUE,pretty=TRUE)
  message(country,': IR imported; calendars and eligible episodes reconstructed.')
}
