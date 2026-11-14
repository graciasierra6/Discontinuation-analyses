#!/usr/bin/env Rscript
suppressPackageStartupMessages(library(jsonlite))
args<-commandArgs(TRUE)
if(length(args)!=4L)stop('Supply calendar input, IR input, alluvial aggregates, aggregate output.')
calendar<-readRDS(args[1]);ir<-readRDS(args[2]);ref<-read_json(args[3],simplifyVector=TRUE)
modern<-c(1L,2L,3L,5L,6L,7L,11L,13L,14L,15L,16L,17L,18L,19L,20L)
action<-c(1L,4L,5L,6L,7L,8L,10L,15L)
keep<-calendar$method_code %in% setdiff(modern,16L) & calendar$reason_code %in% action &
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
 z<-which(d$woman_row==w)
 for(t in 1:12){date<-d$end[z]+t;j<-findInterval(date,timeline$start)
  stopifnot(all(j>0),all(timeline$end[j]>=date));monthly[z,t]<-timeline$method_code[j]}
}
stopifnot(!anyNA(monthly))
is_modern<-matrix(monthly %in% modern,nrow(d),12L)
first<-apply(is_modern,1,function(x){hit<-which(x);if(length(hit))hit[1]else 13L})
destination_code<-rep(NA_integer_,nrow(d))
yes<-which(first<=12L);destination_code[yes]<-monthly[cbind(yes,first[yes])]
method_group<-function(x)ifelse(x==3L,'Injectables',ifelse(x==11L,'Implants',
 ifelse(x==1L,'Pill',ifelse(x==2L,'IUD','Other modern'))))
origin<-method_group(d$method_code)
destination<-ifelse(first<=12L,method_group(destination_code),'No modern return')
for(k in unique(origin))stopifnot(abs(100*sum(d$wt[origin==k])/sum(d$wt)-
 ref$origins$share[ref$origins$method==k])<1e-8)
for(t in c(1L,3L,6L,12L))stopifnot(abs(100*sum(d$wt[is_modern[,t]])/sum(d$wt)-
 ref$shares$share[ref$shares$month==t & ref$shares$state=='Modern method'])<1e-8)
origins<-c('All actionable endings','Injectables','Implants','Pill','IUD','Other modern')
destinations<-c('Injectables','Implants','Pill','IUD','Other modern','No modern return')
point<-matrix(0,length(origins),length(destinations));counts<-point
for(j in seq_along(origins)){
 z<-if(j==1L)rep(TRUE,nrow(d))else origin==origins[j]
 stopifnot(sum(z)>0)
 for(k in seq_along(destinations)){
  hit<-z&destination==destinations[k]
  point[j,k]<-100*sum(d$wt[hit])/sum(d$wt[z]);counts[j,k]<-sum(hit)
 }
}
stopifnot(max(abs(rowSums(point)-100))<1e-8,sum(counts[-1,])==nrow(d))
frame<-unique(data.frame(stratum=as.integer(ir$v022),psu=as.integer(ir$v021)))
frame$key<-paste(frame$stratum,frame$psu,sep=':')
index<-match(paste(as.integer(ir$v022[d$woman_row]),as.integer(ir$v021[d$woman_row]),sep=':'),frame$key)
strata<-split(seq_len(nrow(frame)),frame$stratum)
stopifnot(!anyNA(index),all(lengths(strata)>1))
B<-1999L;set.seed(20261116L);boot<-array(NA_real_,c(B,length(origins),length(destinations)))
for(b in seq_len(B)){
 mult<-numeric(nrow(frame))
 for(ids in strata){n<-length(ids);mult[ids]<-n/(n-1)*tabulate(sample.int(n,n-1,replace=TRUE),nbins=n)}
 weight<-d$wt*mult[index]
 for(j in seq_along(origins)){
  z<-if(j==1L)rep(TRUE,nrow(d))else origin==origins[j];den<-sum(weight[z])
  if(den>0)boot[b,j,]<-vapply(destinations,function(k)100*sum(weight[z&destination==k])/den,0)
 }
}
rows<-lapply(seq_along(origins),function(j){
 z<-if(j==1L)rep(TRUE,nrow(d))else origin==origins[j]
 empty_draws<-sum(!is.finite(boot[,j,1]))
 interval<-function(x,p)if(empty_draws>0)NA_real_ else unname(quantile(x,p))
 cells<-data.frame(destination=destinations,share=point[j,],endings=as.integer(counts[j,]),
  ci_low=apply(boot[,j,,drop=FALSE],3,interval,p=.025),
  ci_high=apply(boot[,j,,drop=FALSE],3,interval,p=.975))
 cells$ci_low[cells$endings==0L]<-NA_real_;cells$ci_high[cells$endings==0L]<-NA_real_
 cells$ci_status<-ifelse(cells$endings==0L,'Not estimated: no observed endings',
  if(empty_draws>0)'Not estimated: sparse original-method row has empty bootstrap draws'else 'Estimated')
 list(origin=origins[j],endings=sum(z),women=length(unique(d$woman_row[z])),
  empty_bootstrap_draws=empty_draws,cells=cells)
})
first_preg<-apply(matrix(monthly %in% c(81L,82L,83L),nrow(d),12L),1,function(x){hit<-which(x);if(length(hit))hit[1]else 13L})
first_preg[d$reason_code==1L]<-0L
out<-list(country=ref$country,survey=ref$survey,endings=nrow(d),women=length(unique(d$woman_row)),
 first_modern_endings=length(yes),first_modern_share=100*sum(d$wt[first<=12L])/sum(d$wt),
 modern12_share=100*sum(d$wt[is_modern[,12]])/sum(d$wt),rows=rows,
 first_modern_after_pregnancy_share=100*sum(d$wt[first<=12L & first_preg<first])/sum(d$wt),
 definitions=list('Each row includes all actionable endings for that original method with complete follow-up.',
 'Columns show the first modern method recorded in the twelve following months; pregnancy does not terminate observation.',
 'No-modern-return means no modern method in any of the twelve following months, not merely nonuse at month twelve.',
 'Original EC is excluded; subsequent EC is grouped with Other modern.',
 'Same-group destinations can include a restart. Other-to-other can involve different specific methods.',
 'Return does not imply use continues to month twelve.'),
 inference=list(replicates=B,psus=nrow(frame),strata=length(strata),
 method='Full-frame stratified Rao-Wu n-1 PSU bootstrap, retaining all episodes from each woman together.'),
 validation=list(same_cohort_as_alluvial=TRUE,all_rows_sum_100=TRUE,original_method_rows_partition_cohort=TRUE))
write_json(out,args[4],pretty=TRUE,auto_unbox=TRUE,digits=15,dataframe='rows',na='null')
for(r in rows){cat(r$origin,'N=',r$endings,'\n');print(r$cells[,c('destination','share','endings')],row.names=FALSE)}
cat('First modern resumption:',out$first_modern_share,'%; month twelve modern:',out$modern12_share,'%\n')
