#!/usr/bin/env Rscript
# Portable design tests; no survey microdata are needed.
file<-sub('^--file=','',grep('^--file=',commandArgs(FALSE),value=TRUE)[1])
source(file.path(dirname(dirname(normalizePath(file))),'survey_design.R'))
set.seed(20261121)
ir<-data.frame(caseid=1:120,v005=runif(120,.3,2)*1e6,v021=rep(1:24,each=5),v022=rep(1:6,each=20))
dhs_set_context(ir=ir)
f<-data.frame(woman_row=1:120,wt=ir$v005/1e6,cluster=ir$v021,stratum=ir$v022,x=rnorm(120),y=rep(c(0,1,1,0,1),24))
frame<-dhs_frame(ir);d<-dhs_design(f,frame);domain<-f$cluster%in%c(1,2,5,9,10)
z<-dhs_percentage(d,f$y,domain);p<-weighted.mean(f$y[domain],f$wt[domain])
stopifnot(abs(z['percent']-100*p)<1e-10)
u<-rowsum(f$wt*as.numeric(domain)*(f$y-p)/sum(f$wt[domain]),f$cluster)[,1]
v<-sum(vapply(split(seq_len(nrow(frame)),frame$stratum),function(i){n<-length(i);n/(n-1)*sum((u[i]-mean(u[i]))^2)},0.0))
stopifnot(abs(z['se_pct']-100*sqrt(v))<1e-10)
q<-f[domain,];zz<-dhs_percentage(dhs_design(q,frame),q$y)
stopifnot(max(abs(z-zz))<1e-10)
# A woman's repeated records carry the identical base weight and survey IDs.
e<-f[rep(1:120,each=2),];e$time<-rexp(nrow(e),.2);e$event<-rbinom(nrow(e),1,.6)
ce<-dhs_calendar_records(e,ir)
stopifnot(identical(ce$wt,as.numeric(ir$v005[ce$woman_row])/1e6),all(ce$v021==ir$v021[ce$woman_row]))
bad<-ce;bad$wt[1]<-bad$wt[1]+1
stopifnot(inherits(try(dhs_calendar_records(bad,ir),silent=TRUE),'try-error'))
# Binary regression point estimates agree; the covariance uses the survey design.
g<-dhs_binary_fit(y~x,f,frame);ordinary<-glm(y~x,f,weights=wt,family=quasibinomial())
stopifnot(inherits(g,'svyglm'),max(abs(coef(g)-coef(ordinary)))<1e-8)
X<-model.matrix(ordinary);pr<-fitted(ordinary);H<-crossprod(X,X*(f$wt*pr*(1-pr)))
score<-rowsum(X*(f$wt*(f$y-pr)),f$cluster);meat<-dhs_psu_variance(score,frame)
stopifnot(max(abs(vcov(g)-solve(H)%*%meat%*%solve(H)))<1e-6)
# AFT survey and weighted likelihood points agree with identical records/family.
a<-dhs_aft_fit(survival::Surv(time,event)~x,e,weights=wt,dist='weibull',control=survival::survreg.control())
b<-survival::survreg(survival::Surv(time,event)~x,e,weights=wt,dist='weibull')
stopifnot(inherits(a,'svysurvreg'),max(abs(coef(a)-coef(b)))<1e-8,all(is.finite(vcov(a))))
stopifnot(abs(a$scale-b$scale)<1e-10,abs(dhs_aft_aic(a)-AIC(b))<1e-8)
for(family in c('lognormal','loglogistic','exponential')){
 survey_fit<-dhs_aft_fit(survival::Surv(time,event)~x,e,weights=wt,dist=family,control=survival::survreg.control())
 likelihood_fit<-survival::survreg(survival::Surv(time,event)~x,e,weights=wt,dist=family)
 stopifnot(max(abs(coef(survey_fit)-coef(likelihood_fit)))<1e-8,
   abs(survey_fit$scale-likelihood_fit$scale)<1e-10,
   abs(dhs_aft_aic(survey_fit)-AIC(likelihood_fit))<1e-8)
}
# Full-frame multinomial sandwich agrees with independent stratum-centred scores.
f$outcome<-factor(rep(c('continue','actionable','competing'),40),levels=c('continue','actionable','competing'))
m<-nnet::multinom(outcome~x,f,weights=wt,trace=FALSE,Hess=TRUE,maxit=500)
z<-dhs_multinom_summary(m,f)
stopifnot(all(is.finite(z$standard.errors)),max(abs(z$coefficients-coef(m)))<1e-12)
X<-model.matrix(m);pr<-predict(m,type='probs');lev<-m$lev[-1L]
scores<-do.call(cbind,lapply(lev,function(k)X*(f$wt*(as.numeric(f$outcome==k)-pr[,k]))))
U<-matrix(0,nrow(frame),ncol(scores))
index<-match(paste(f$stratum,f$cluster),paste(frame$stratum,frame$cluster))
aggregated<-rowsum(scores,index,reorder=FALSE)
U[as.integer(rownames(aggregated)),]<-aggregated
manual_meat<-matrix(0,ncol(U),ncol(U))
for(ids in split(seq_len(nrow(frame)),frame$stratum)){
 centred<-sweep(U[ids,,drop=FALSE],2,colMeans(U[ids,,drop=FALSE]),'-')
 manual_meat<-manual_meat+length(ids)/(length(ids)-1)*crossprod(centred)
}
bread<-MASS::ginv(m$Hessian)
stopifnot(max(abs(z$covariance-bread%*%manual_meat%*%bread))<1e-8)
cat('PASS: full-frame domain inference, repeated-record inheritance, svyglm and svysurvreg point equivalence, and multinomial design covariance.\n')
protected<-dhs_multinom_fit(outcome~x,f,weights=wt,trace=FALSE,Hess=TRUE,maxit=500)
stopifnot(max(abs(vcov(protected)-z$covariance))<1e-8,
 max(abs(summary(protected)$standard.errors-z$standard.errors))<1e-8)
refit<-dhs_multinom_fit(outcome~x,f,weights=wt,trace=FALSE,Hess=FALSE,maxit=500)
stopifnot(inherits(try(vcov(refit),silent=TRUE),'try-error'))
cat('PASS: multinomial objects retain design covariance and reject naive Hessian inference.\n')
# Refits preserve the supplied PSU multiplier instead of replacing it with the
# woman's base weight. This is essential for joint planning uncertainty.
f$rep_weight<-f$wt*rep(c(.4,1.8,1.1,.7),each=30)
options(dhs.replication=TRUE)
weighted_refit<-dhs_multinom_fit(outcome~x,f,weights=rep_weight,trace=FALSE,Hess=FALSE,maxit=500)
independent_refit<-nnet::multinom(outcome~x,f,weights=rep_weight,trace=FALSE,Hess=FALSE,maxit=500)
e$rep_weight<-e$wt*rep(c(.4,1.8,1.1,.7),each=60)
aft_refit<-dhs_aft_fit(survival::Surv(time,event)~x,e,weights=rep_weight,dist='weibull',control=survival::survreg.control())
independent_aft<-survival::survreg(survival::Surv(time,event)~x,e,weights=rep_weight,dist='weibull')
options(dhs.replication=FALSE)
stopifnot(max(abs(coef(weighted_refit)-coef(independent_refit)))<1e-10,
 max(abs(coef(aft_refit)-coef(independent_aft)))<1e-10)
# PSU labels may repeat in different strata; nesting must remain explicit.
nested_ir<-ir;nested_ir$v021<-rep(rep(1:4,each=5),6)
nested<-f;nested$cluster<-nested_ir$v021
nested_design<-dhs_design(nested,dhs_frame(nested_ir))
stopifnot(abs(dhs_percentage(nested_design,nested$y)['percent']-100*weighted.mean(nested$y,nested$wt))<1e-10)
# Older prepared records can carry an explicitly nested key. Recover its
# verified stratum, but never guess a missing stratum from an unlinked record.
legacy<-data.frame(wt=f$wt,cluster=paste(ir$v022,ir$v021,sep=':'))
attached<-dhs_attach_design(legacy)
stopifnot(identical(attached$cluster,as.character(ir$v021)),
 identical(attached$stratum,as.character(ir$v022)),
 inherits(try(dhs_attach_design(data.frame(wt=1,cluster=1)),silent=TRUE),'try-error'))
cat('PASS: PSU-multiplier refits retain their weights and repeated PSU labels are nested within strata.\n')
# A genuinely new DRC build must initialize from the supplied Stata IR before
# its lossless RDS has been created by calendar preparation.
cold_root<-tempfile('survey-input-test-');dir.create(cold_root)
cold_input<-file.path(cold_root,'individual_recode.dta')
haven::write_dta(ir,cold_input)
prior_context<-.dhs_context;prior_input<-Sys.getenv('DRC_IR_FILE',unset=NA_character_)
.dhs_context<-new.env(parent=emptyenv())
Sys.setenv(DRC_IR_FILE=cold_input)
dhs_set_context(country='DRC',root=cold_root)
stopifnot(!file.exists(file.path(cold_root,'Data/ir.rds')),
 identical(dhs_context()$frame,dhs_frame(ir)))
.dhs_context<-prior_context
if(is.na(prior_input))Sys.unsetenv('DRC_IR_FILE')else Sys.setenv(DRC_IR_FILE=prior_input)
unlink(cold_root,recursive=TRUE)
cat('PASS: cold DRC preparation initializes its design directly from the supplied IR.\n')
# Standalone bundles carry exactly the same design implementation.
repo<-dirname(dirname(normalizePath(file)))
canonical<-paste(readLines(file.path(repo,'survey_design.R'),warn=FALSE),collapse='\n')
trim<-function(x)sub('[\r\n]+$','',x)
for(country in c('Ethiopia','Nigeria','DRC')) {
 env<-new.env();sys.source(file.path(repo,paste0(country,'_analysis'),paste0(country,'_final_html_analysis.R')),env)
 stopifnot(identical(trim(env$MODULES[['dhs_survey_tools.R']]$code),trim(canonical)))
}
for(state in c('Kano','Kaduna','Lagos')) {
 text<-paste(readLines(file.path(repo,'Nigeria_analysis/Kano_Kaduna_Lagos',paste0(state,'_discontinuation_analysis.R')),warn=FALSE),collapse='\n')
 start<-regexpr('# DHS design utilities.',text,fixed=TRUE)[1]
 end<-regexpr('REPORT_STATE <-',text,fixed=TRUE)[1]
 stopifnot(start>0,end>start,identical(trim(substr(text,start,end-1L)),trim(canonical)))
}
env<-new.env();sys.source(file.path(repo,'discontinuation_extensions/run_analysis.R'),env)
stopifnot(identical(trim(env$EXTENSION_FILES[['src/R/dhs_survey_tools.R']]),trim(canonical)))
cat('PASS: national, state and extensions bundles share the identical design implementation.\n')
