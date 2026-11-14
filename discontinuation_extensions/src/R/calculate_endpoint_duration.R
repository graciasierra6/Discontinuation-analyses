#!/usr/bin/env Rscript
suppressPackageStartupMessages(library(jsonlite))
args<-commandArgs(TRUE)
if(length(args)!=5L)stop('Supply calendar, IR, alluvial reference, continuity reference, and aggregate output.')
calendar<-readRDS(args[1]);ir<-readRDS(args[2]);ref<-read_json(args[3],simplifyVector=TRUE)
continuity<-read_json(args[4],simplifyVector=FALSE)
modern<-c(1L,2L,3L,5L,6L,7L,11L,13L,14L,15L,16L,17L,18L,19L,20L)
action<-c(1L,4L,5L,6L,7L,8L,10L,15L)
keep<-calendar$method_code%in%setdiff(modern,16L)&calendar$reason_code%in%action&
 calendar$interview-calendar$end>=3L&calendar$interview-calendar$end<=62L&
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
stopifnot(!anyNA(monthly),all(monthly%in%c(modern,0L,8L,9L,10L,12L,81L,82L,83L)))
im<-matrix(monthly%in%modern,nrow(d),12L)
nm<-monthly==0L;total_nm<-rowSums(nm)
outcome<-ifelse(rowSums(im)==12L,1L,ifelse(im[,12],2L,ifelse(nm[,12],3L,
 ifelse(monthly[,12]%in%c(81L,82L,83L),4L,5L))))
bin<-as.integer(cut(total_nm,breaks=c(-1,0,1,3,6,12),labels=FALSE))
labels<-c('Modern use recorded in every month',
 'Modern at month 12 after earlier months outside modern use',
 'No method at month 12','Pregnancy/birth/termination at month 12','Traditional method at month 12')
bins<-c('0 months','1 month','2–3 months','4–6 months','7–12 months')
stopifnot(!anyNA(bin),all(outcome%in%1:5))
cell<-outcome+(bin-1L)*5L
months_outside_modern<-rowSums(!im)
group7<-ifelse(im[,12],ifelse(months_outside_modern==0L,1L,
 ifelse(months_outside_modern==1L,2L,ifelse(months_outside_modern<=5L,3L,4L))),
 ifelse(nm[,12],5L,ifelse(monthly[,12]%in%c(81L,82L,83L),6L,7L)))
stopifnot(all(group7%in%1:7),all(months_outside_modern[im[,12]]<=11L))
design<-cbind(vapply(1:25,function(k)as.numeric(cell==k),numeric(nrow(d))),
 vapply(1:7,function(k)as.numeric(group7==k),numeric(nrow(d))))
estimate<-function(weight)100*as.numeric(crossprod(weight,design))/sum(weight)
allpoint<-estimate(d$wt);point<-matrix(allpoint[1:25],5,5)
counts<-matrix(tabulate(cell,nbins=25),5,5)
structural<-matrix(FALSE,5,5);structural[1,2:5]<-TRUE;structural[3,1]<-TRUE
stopifnot(all(counts[structural]==0L),abs(sum(point)-100)<1e-8,sum(counts)==nrow(d))
if(!is.null(continuity$cohorts)){
 prior<-continuity$cohorts[[1]]$metrics
 prior_values<-setNames(vapply(prior,function(x)x$estimate,0),vapply(prior,function(x)x$key,''))
}else{
 stopifnot(continuity$country==ref$country,continuity$endings==nrow(d),
  continuity$women==length(unique(d$woman_row)))
 pooled<-continuity$rows[[1]]
 prior_values<-setNames(vapply(pooled$cells,function(x)x$share,0),
  c('modern_all12','modern12_after_outside','no_method12','pregnancy12','traditional12'))
 prior_values['modern12']<-pooled$modern12
 direct_nm<-vapply(list(total_nm==0L,total_nm==1L,total_nm>=2L),
  function(z)100*sum(d$wt[z])/sum(d$wt),0)
 prior_values[c('no_method_zero','no_method_exactly_one','no_method_two_plus')]<-direct_nm
 stopifnot(all(vapply(pooled$cells,function(x)x$endings,0)==rowSums(counts)))
}
getprior<-function(key)unname(prior_values[key])
for(t in ref$times)stopifnot(abs(100*sum(d$wt[im[,t]])/sum(d$wt)-
 ref$shares$share[ref$shares$month==t&ref$shares$state=='Modern method'])<1e-8)
for(j in 1:5)stopifnot(abs(sum(point[j,])-getprior(c('modern_all12','modern12_after_outside',
 'no_method12','pregnancy12','traditional12')[j]))<1e-8)
stopifnot(abs(sum(point[,1])-getprior('no_method_zero'))<1e-8,
 abs(sum(point[,2])-getprior('no_method_exactly_one'))<1e-8,
 abs(sum(point[,3:5])-getprior('no_method_two_plus'))<1e-8)
frame<-unique(data.frame(stratum=as.integer(ir$v022),psu=as.integer(ir$v021)))
frame$key<-paste(frame$stratum,frame$psu,sep=':')
index<-match(paste(as.integer(ir$v022[d$woman_row]),as.integer(ir$v021[d$woman_row]),sep=':'),frame$key)
strata<-split(seq_len(nrow(frame)),frame$stratum)
stopifnot(!anyNA(index),all(lengths(strata)>1))
B<-1999L;set.seed(20261113L);boot<-matrix(NA_real_,B,32)
for(b in 1:B){
 mult<-numeric(nrow(frame))
 for(ids in strata){n<-length(ids);mult[ids]<-n/(n-1)*tabulate(sample.int(n,n-1,replace=TRUE),nbins=n)}
 weight<-d$wt*mult[index];stopifnot(sum(weight)>0)
 boot[b,]<-estimate(weight)
}
limits<-apply(boot,2,quantile,c(.025,.975),names=FALSE)
rows<-lapply(1:5,function(j){
 ids<-j+5L*(0:4)
 cells<-data.frame(months=bins,share=point[j,],observed_endings=counts[j,],
  structural_zero=structural[j,],ci_low=limits[1,ids],ci_high=limits[2,ids])
 cells$ci_low[counts[j,]==0L]<-NA_real_;cells$ci_high[counts[j,]==0L]<-NA_real_
 list(outcome=labels[j],share=sum(point[j,]),observed_endings=sum(counts[j,]),cells=cells)
})
seven_names<-c('Modern use in every recorded month',
 'Modern at month 12 after 1 month outside modern use',
 'Modern at month 12 after 2–5 months outside modern use',
 'Modern at month 12 after 6–11 months outside modern use',
 'No method at month 12','Pregnancy/birth/termination at month 12','Traditional method at month 12')
seven<-data.frame(group=seven_names,share=allpoint[26:32],observed_endings=tabulate(group7,nbins=7),
 ci_low=limits[1,26:32],ci_high=limits[2,26:32])
seven$ci_low[seven$observed_endings==0L]<-NA_real_;seven$ci_high[seven$observed_endings==0L]<-NA_real_
stopifnot(abs(sum(seven$share)-100)<1e-8,
 abs(sum(seven$share[1:4])-getprior('modern12'))<1e-8,
 abs(sum(seven$share[2:4])-getprior('modern12_after_outside'))<1e-8,
 max(abs(seven$share[5:7]-vapply(c('no_method12','pregnancy12','traditional12'),getprior,0)))<1e-8)
json<-list(country=ref$country,survey=ref$survey,endings=nrow(d),women=length(unique(d$woman_row)),
 rows=rows,column_totals=data.frame(months=bins,share=colSums(point),observed_endings=colSums(counts)),
 endpoint_interruption_distribution=list(groups=seven,
  duration_definition='For histories in modern use at month twelve, count total months outside modern use during months one to twelve; these include no method, traditional use, or pregnancy-related records and need not be consecutive.',
  validation=list(mutually_exclusive_and_exhaustive=TRUE,all_groups_sum_100=TRUE,
   modern_and_other_endpoints_match_existing_figure=TRUE)),
 definitions=list('Every cell is a weighted percentage of the full eligible ending cohort, not a within-row percentage.',
 'Total no-method months are calendar code zero; pregnancy-related and traditional-use months are excluded.',
 'Counts are total months in the following year, not necessarily consecutive months.',
 'The zero-month column can include pregnancy-related or traditional use; it does not imply uninterrupted modern use.',
 'All potentially actionable original modern-method endings at any use duration with complete twelve-month follow-up; original EC excluded and partner disapproval excluded.',
 'Subsequent EC counts as modern use. Row and column totals are calculated before rounding.'),
 inference=list(replicates=B,psus=nrow(frame),strata=length(strata),
 method='Full-frame stratified Rao-Wu n-1 PSU bootstrap, keeping all women and repeated ending histories together.'),
 validation=list(same_alluvial_cohort=TRUE,all_months_available=TRUE,row_totals_match_existing_outcomes=TRUE,
 column_totals_reconcile_with_nonuse_categories=TRUE,all_cells_sum_100=TRUE))
write_json(json,args[5],pretty=TRUE,auto_unbox=TRUE,digits=15,dataframe='rows',na='null')
colnames(point)<-bins;rownames(point)<-labels
print(round(cbind(point,Total=rowSums(point)),4));cat('Column totals:\n');print(colSums(point))
cat('Unweighted cell counts:\n');print(counts)
cat('Seven-category endpoint and interruption distribution:\n');print(seven,row.names=FALSE)
