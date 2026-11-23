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
 stopifnot(start>0)
 # The user-facing state setting also appears above the shared implementation.
 fragment<-substring(text,start)
 end<-regexpr('REPORT_STATE <-',fragment,fixed=TRUE)[1]
 stopifnot(end>0,identical(trim(substr(fragment,1L,end-1L)),trim(canonical)))
}
env<-new.env();sys.source(file.path(repo,'discontinuation_extensions/run_analysis.R'),env)
stopifnot(identical(trim(env$EXTENSION_FILES[['src/R/dhs_survey_tools.R']]),trim(canonical)))
cat('PASS: national, state and extensions bundles share the identical design implementation.\n')

# Dependency declarations include every namespaced package in the country modules.
# This check parses code and tests setup behavior without accessing IR or CRAN.
base_packages <- rownames(installed.packages(priority='base'))
for (country in c('Ethiopia','Nigeria','DRC')) {
  env <- new.env()
  path <- file.path(repo,paste0(country,'_analysis'),paste0(country,'_final_html_analysis.R'))
  sys.source(path,env)
  code <- c(lapply(env$MODULES,function(z)if(z$language=='R')z$code else ''),
            env$REPORT_FILES[grepl('[.]R$',names(env$REPORT_FILES))])
  used <- unique(unlist(lapply(code,function(txt) {
    parsed <- getParseData(parse(text=txt,keep.source=TRUE))
    parsed$text[parsed$token=='SYMBOL_PACKAGE']
  })))
  stopifnot(all(used %in% c(env$REQUIRED_R_PACKAGES,base_packages)))
  header <- paste(readLines(path,n=16L,warn=FALSE),collapse=' ')
  stopifnot(grepl('Individual Recode',header,fixed=TRUE),
            grepl('vcal_1',header,fixed=TRUE),grepl('vcal_2',header,fixed=TRUE),
            grepl('episode-level',header,fixed=TRUE))
  env$setup_analysis_packages(c('stats','tools'),install_missing=FALSE)
  stopifnot(inherits(try(env$setup_analysis_packages(
    'unavailable_dependency_test_only',install_missing=FALSE),silent=TRUE),'try-error'))
}
cat('PASS: country data headers, complete namespace dependency declarations and non-installing setup checks.\n')

# Behavioral checks for the separate absorbing permanent-method destination.
for(country in c('Ethiopia','Nigeria','DRC')){
 bundle<-new.env();sys.source(file.path(repo,paste0(country,'_analysis'),paste0(country,'_final_html_analysis.R')),bundle)
 text<-bundle$MODULES[['transition_model.R']]$code;env<-new.env(parent=globalenv())
 for(expr in parse(text=text))if(is.call(expr)&&as.character(expr[[1]])[1]=='<-'&&is.call(expr[[3]])&&identical(expr[[3]][[1]],as.name('function')))eval(expr,env)
 env$states<-c('Modern','Nonmodern','Pregnancy-related');env$methods<-c('Injectables','Implants','Pill','IUD','Other modern');env$model_methods<-env$methods[env$methods!='IUD'];env$causes<-c('Method failure','Wanted more effective method','Changes in menstrual bleeding','Other side effects/health','Access/cost/convenience')
 env$data.table<-data.table::data.table;env$rbindlist<-data.table::rbindlist
 env$initial_probs<-function(f,d)matrix(rep(c(.3,.5,.2),each=nrow(d)),nrow(d),dimnames=list(NULL,c('Modern','Nonmodern','Pregnancy-related')))
 env$increment<-function(t,mu,ls,family)list(h=mu)
 gr<-data.frame(gid=1:2,method=env$methods[1:2],cause=env$causes[1:2],end_duration=c(5,12))
 tmp<-gr;tmp$state_duration<-1;tmp$post_month<-1
 fits<-setNames(lapply(env$states,function(s){X<-if('from'%in%names(formals(env$design)))env$design(tmp,s)else env$design(tmp);p<-ncol(X);b1<-b2<-numeric(p);b1[1]<-.1;b2[1]<-.2;list(par=c(b1,0,b2,0),p=p,columns=colnames(X),dest=setdiff(env$states,s),family='lognormal')}),env$states)
 model<-list(initial=structure(list(),permanent_probability=0),permanent_monthly_probability=0,transitions=fits)
 z<-env$endpoint_prob(model,gr,12);P<-matrix(0,3,3)
 for(i in 1:3){j<-setdiff(1:3,i);P[i,i]<-exp(-.3);P[i,j]<-(-expm1(-.3))*c(.1,.2)/.3}
 pi<-c(.3,.5,.2);expected<-pi[1];for(t in 2:12){pi<-as.numeric(pi%*%P);expected<-c(expected,pi[1])}
 stopifnot(max(abs(z$p_modern[z$gid==1]-expected))<1e-10,all(z$p_permanent==0))
 attr(model$initial,'permanent_probability')<-1;z<-env$endpoint_prob(model,gr,12);stopifnot(all(z$p_modern==1),all(z$p_permanent==1))
 attr(model$initial,'permanent_probability')<-.02;model$permanent_monthly_probability<-.01;z<-env$endpoint_prob(model,gr,12)
 stopifnot(max(abs(z$p_permanent-(1-.98*.99^(z$horizon-1))))<1e-10,all(z$p_modern>=z$p_permanent),all(z$p_modern<=1+1e-10))
 model$permanent_monthly_probability<-1;z<-env$endpoint_prob(model,gr,12);stopifnot(all(z$p_permanent[z$horizon>=2]==1))
 stopifnot(!grepl("if('risk_strata'%in%tasks) {",bundle$MODULES[['200_reference_analysis_extensions.R']]$code,fixed=TRUE))
 if(exists('REVISION_HELPERS',bundle,inherits=FALSE))stopifnot(all(vapply(names(bundle$REVISION_HELPERS),function(name)identical(bundle$REVISION_HELPERS[[name]],bundle$MODULES[[name]]$code),FALSE)))
 # The pooled uptake probability is a full-frame survey percentage.
 env$dhs_context<-function()list(frame=dhs_frame(ir))
 env$dhs_design<-dhs_design;env$dhs_percentage<-dhs_percentage
 uptake_records<-data.frame(wt=c(1,4,2),psu=ir$v021[c(1,6,11)],stratum=ir$v022[c(1,6,11)],permanent_entry=c(FALSE,TRUE,FALSE))
 stopifnot(abs(env$permanent_rate(uptake_records)-4/7)<1e-10)
 cat(country,': absorbing permanence, mass conservation, full-frame uptake ratios and retired branch checks pass.\n')
}
