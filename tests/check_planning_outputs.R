#!/usr/bin/env Rscript
# Validate aggregate planning estimates without reading restricted survey records.
a<-commandArgs(TRUE);opt<-list()
for(x in a){stopifnot(grepl('^--[^=]+=.+$',x));opt[[sub('^--([^=]+)=.*$','\\1',x)]]<-sub('^--[^=]+=','',x)}
if(is.null(opt[['statistics-dir']]))stop('Supply --statistics-dir and optionally --table-dir.')
s<-opt[['statistics-dir']];t<-if(is.null(opt[['table-dir']]))s else opt[['table-dir']]
p<-readRDS(file.path(s,'planning_point.rds'));draws<-readRDS(file.path(s,'planning_replicates.rds'));meta<-readRDS(file.path(s,'planning_metadata.rds'))
stopifnot(length(draws)==500L,meta$replicates==500L,!('Permanent methods'%in%meta$methods),length(meta$methods)==5L,length(meta$causes)==5L,!any(grepl('partner|spous',meta$causes,ignore.case=TRUE)))
stopifnot(meta$reference_year%in%c(2024L,2025L),meta$outcome_year==meta$reference_year+1L)
baseline<-meta[[paste0('wra',meta$reference_year)]]
outcome<-meta[[paste0('wra',meta$outcome_year)]]
check<-function(x){
 stopifnot(is.null(x$error),identical(dim(x$risk),c(9L,5L,5L)),identical(dim(x$counts),c(9L,5L,5L)),all(is.finite(x$counts)),all(x$counts>=0),all(is.finite(x$risk)),all(x$risk>=0),all(apply(x$risk,c(1,2),sum)<=1+1e-8),'Permanent methods'%in%names(x$stock),abs(sum(x$mix)-1)<1e-10,abs(sum(x$stock)-baseline*x$mcpr/100)<1e-5)
 for(m in meta$methods)stopifnot(max(abs(x$counts[,m,]-x$risk[,m,]*x$stock[m]))<1e-5)
 for(pair in list(c(4L,2L),c(5L,3L),c(9L,3L),c(6L,1L),c(7L,2L),c(8L,3L)))stopifnot(all(x$counts[pair[1],,]<=x$counts[pair[2],,]+1e-5))
 invisible(TRUE)
}
check(p);invisible(lapply(draws,check))
f<-file.path(t,'planning_intervals.csv');if(!file.exists(f))f<-file.path(s,'planning_intervals.csv')
d<-read.csv(f);value<-setNames(d$estimate,d$key)
counts<-abind::abind(p$counts[1:8,,,drop=FALSE],p$counts[1,,,drop=FALSE]-p$counts[6,,,drop=FALSE],p$counts[2,,,drop=FALSE]-p$counts[4,,,drop=FALSE],p$counts[3,,,drop=FALSE]-p$counts[5,,,drop=FALSE],p$counts[9,,,drop=FALSE],p$counts[3,,,drop=FALSE]-p$counts[9,,,drop=FALSE],along=1)
for(i in 1:13)for(m in c(meta$methods,'Total'))for(cause in c(meta$causes,'Total')){
 mi<-if(m=='Total')1:5 else match(m,meta$methods);ci<-if(cause=='Total')1:5 else match(cause,meta$causes);v<-sum(counts[i,mi,ci]);k<-paste(i,m,cause,sep='|')
 stopifnot(abs(value[paste0('count|',k)]-v)<1e-5,abs(value[paste0('pp|',k)]-100*v/outcome)<1e-10)
}
for(j in 1:3)for(i in 1:13){
 key<-paste(j,i,'Total',sep='|');add<-sum(counts[i,,]);b<-value[paste0('base|',j)]
 stopifnot(abs(value[paste0('usualusers|',key)]-b/100*outcome)<1e-5,abs(value[paste0('retainedusers|',key)]-value[paste0('usualusers|',key)]-add)<1e-5,abs(value[paste0('retainedmcpr|',key)]-value[paste0('usualmcpr|',key)]-100*add/outcome)<1e-10)
 for(v in c('usualusers','retainedusers','usualmcpr','retainedmcpr')){
  parts<-value[paste0(v,'|',j,'|',i,'|',c(meta$methods,'EC','Permanent methods'))]
  stopifnot(!anyNA(parts),abs(sum(parts)-value[paste0(v,'|',key)])<1e-5)
 }
}
cat('PASS: 500 survey replicates; permanent stock retained without a stopping risk; method/cause totals; outcome-year denominators; all three growth scenarios.\n')
