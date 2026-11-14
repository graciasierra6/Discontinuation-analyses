#!/usr/bin/env Rscript
suppressPackageStartupMessages(library(jsonlite))
args<-commandArgs(TRUE)
if(length(args)!=4L)stop('Supply calendar input, IR input, alluvial aggregates, aggregate output.')
calendar<-readRDS(args[1]);ir<-readRDS(args[2]);ref<-read_json(args[3],simplifyVector=TRUE)
modern<-c(1L,2L,3L,5L,6L,7L,11L,13L,14L,15L,16L,17L,18L,19L,20L)
actionable<-c(1L,4L,5L,6L,7L,8L,10L,15L)
keep<-calendar$method_code %in% setdiff(modern,16L) & calendar$reason_code %in% actionable &
 calendar$interview-calendar$end>=3L & calendar$interview-calendar$end<=62L &
 calendar$end+12L<=calendar$interview-3L
d<-calendar[keep,]
stopifnot(nrow(d)==ref$endings,length(unique(d$woman_row))==ref$women,
 all(as.character(d$caseid)==as.character(ir$caseid[d$woman_row])),
 max(abs(d$wt-as.numeric(ir$v005[d$woman_row])/1e6))<1e-12)
monthly<-matrix(NA_integer_,nrow(d),12L)
bywoman<-split(seq_len(nrow(calendar)),calendar$woman_row)
for(w in unique(d$woman_row)){
 timeline<-calendar[bywoman[[as.character(w)]],];timeline<-timeline[order(timeline$start),]
 rows<-which(d$woman_row==w)
 for(t in 1:12){date<-d$end[rows]+t;j<-findInterval(date,timeline$start)
  stopifnot(all(j>0),all(timeline$end[j]>=date));monthly[rows,t]<-timeline$method_code[j]}
}
stopifnot(!anyNA(monthly),all(monthly %in% c(modern,0L,8L,9L,10L,12L,81L,82L,83L)))
is_modern<-matrix(monthly %in% modern,nrow(d),12L)
every_month<-rowSums(is_modern)==12L
outcome<-ifelse(every_month,1L,ifelse(is_modern[,12],2L,
 ifelse(monthly[,12]==0L,3L,ifelse(monthly[,12]%in%c(81L,82L,83L),4L,5L))))
causes<-list('All actionable endings'=actionable,'Bleeding changes'=15L,
 'Other side effects/health'=c(4L,5L),'Access/cost/convenience'=c(6L,8L,10L),
 'Wanted a more effective method'=7L,'Method failure'=1L)
names_out<-c('Modern method in all 12 months','Modern use at month 12 after an interruption',
 'No method at month 12','Pregnancy/birth/termination at month 12','Traditional method at month 12')
denom<-vapply(causes,function(codes)sum(d$wt[d$reason_code%in%codes]),0)
point<-t(vapply(causes,function(codes){z<-d$reason_code%in%codes
 vapply(1:5,function(k)100*sum(d$wt[z&outcome==k])/sum(d$wt[z]),0)},numeric(5)))
stopifnot(max(abs(rowSums(point)-100))<1e-8,
 max(abs(colSums(point[-1,,drop=FALSE]*denom[-1])/denom[1]-point[1,]))<1e-8)
frame<-unique(data.frame(stratum=as.integer(ir$v022),psu=as.integer(ir$v021)))
frame$key<-paste(frame$stratum,frame$psu,sep=':')
index<-match(paste(as.integer(ir$v022[d$woman_row]),as.integer(ir$v021[d$woman_row]),sep=':'),frame$key)
strata<-split(seq_len(nrow(frame)),frame$stratum)
stopifnot(!anyNA(index),all(lengths(strata)>1))
B<-1999L;set.seed(20261115L);boot<-array(NA_real_,c(B,length(causes),5L))
for(b in seq_len(B)){
 mult<-numeric(nrow(frame))
 for(ids in strata){n<-length(ids);mult[ids]<-n/(n-1)*tabulate(sample.int(n,n-1,replace=TRUE),nbins=n)}
 w<-d$wt*mult[index]
 for(j in seq_along(causes)){z<-d$reason_code%in%causes[[j]];den<-sum(w[z]);stopifnot(den>0)
  boot[b,j,]<-vapply(1:5,function(k)100*sum(w[z&outcome==k])/den,0)}
}
summary<-lapply(seq_along(causes),function(j){
 z<-d$reason_code%in%causes[[j]]
 cells<-data.frame(outcome=names_out,share=point[j,],
  endings=vapply(1:5,function(k)sum(z&outcome==k),0L),
  ci_low=apply(boot[,j,,drop=FALSE],3,quantile,.025,names=FALSE),
  ci_high=apply(boot[,j,,drop=FALSE],3,quantile,.975,names=FALSE))
 cells$ci_low[cells$endings==0L]<-NA_real_
 cells$ci_high[cells$endings==0L]<-NA_real_
 list(reason=names(causes)[j],endings=sum(z),women=length(unique(d$woman_row[z])),
  weighted_endings=denom[j],modern12=point[j,1]+point[j,2],cells=cells)
})
stopifnot(sum(vapply(summary[-1],function(x)x$endings,0L))==nrow(d))
json<-list(country=ref$country,survey=ref$survey,endings=nrow(d),women=length(unique(d$woman_row)),rows=summary,
 definitions=list('Within-reason weighted shares: each row sums to 100%.',
 'All original methods pooled; actionable endings with complete follow-up; original EC excluded.',
 'Modern in all 12 months allows switches between modern methods; subsequent EC included.',
 'Earlier months outside modern use can include pregnancy-related or traditional-use records.',
 'Method failure establishes pregnancy at the original ending.'),
 inference=list(replicates=B,psus=nrow(frame),strata=length(strata),
 method='Full-frame stratified Rao-Wu n-1 PSU bootstrap, retaining all episodes from each woman together.'),
 validation=list(same_cohort_as_alluvial=TRUE,each_row_sums_100=TRUE,reasons_partition_cohort=TRUE,
 reason_weighted_average_reproduces_overall=TRUE))
write_json(json,args[4],pretty=TRUE,auto_unbox=TRUE,digits=15,dataframe='rows',na='null')
for(x in summary){cat(x$reason,'N=',x$endings,'\n');print(x$cells[,c('outcome','share')],row.names=FALSE)}
