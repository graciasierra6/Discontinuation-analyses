# DHS design utilities. Inputs are supplied by the calling analysis.
# No finite population correction: use the with-replacement PSU approximation.
dhs_require_survey <- function() {
  if (!requireNamespace('survey', quietly=TRUE)) stop('Install the survey package before estimation.')
}

dhs_frame <- function(ir) {
  required <- c('v005','v021','v022')
  if (!all(required %in% names(ir))) stop('IR data require v005, v021 and v022.')
  w <- as.numeric(ir$v005)/1e6
  if (anyNA(w) || any(!is.finite(w)) || any(w<=0)) stop('Invalid DHS sampling weights.')
  f <- unique(data.frame(cluster=as.character(ir$v021), stratum=as.character(ir$v022)))
  if (anyNA(f) || any(f$cluster=='') || any(f$stratum=='')) stop('Missing survey identifiers.')
  f[order(f$stratum,f$cluster),,drop=FALSE]
}

dhs_design <- function(data, frame, weight='wt', cluster='cluster', stratum='stratum') {
  dhs_require_survey()
  data <- as.data.frame(data)
  if (!all(c(weight,cluster,stratum)%in%names(data))) stop('Analysis records lack survey design variables.')
  f <- unique(data.frame(.dhs_psu=as.character(frame$cluster),.dhs_stratum=as.character(frame$stratum)))
  if (anyNA(f) || anyDuplicated(paste(f$.dhs_stratum,f$.dhs_psu,sep=':'))) stop('Invalid full survey frame.')
  data$.dhs_w <- as.numeric(data[[weight]])
  data$.dhs_psu <- as.character(data[[cluster]])
  data$.dhs_stratum <- as.character(data[[stratum]])
  if (anyNA(data[,c('.dhs_w','.dhs_psu','.dhs_stratum')]) || any(!is.finite(data$.dhs_w)) || any(data$.dhs_w<0)) stop('Invalid analysis design values.')
  key <- function(s,p) paste(s,p,sep=':')
  fk <- key(f$.dhs_stratum,f$.dhs_psu); dk <- key(data$.dhs_stratum,data$.dhs_psu)
  if (any(!dk%in%fk)) stop('Analysis PSU is absent from the supplied full frame.')
  data$.dhs_record <- TRUE
  absent <- which(!fk%in%dk)
  if (length(absent)) {
    if (!nrow(data)) stop('An empty domain cannot be estimated.')
    pad <- data[rep(1L,length(absent)),,drop=FALSE]
    pad$.dhs_w <- 0; pad$.dhs_record <- FALSE
    pad$.dhs_psu <- f$.dhs_psu[absent]; pad$.dhs_stratum <- f$.dhs_stratum[absent]
    data <- rbind(data,pad)
  }
  # Explicit policy: singleton strata are an error, never silently dropped or
  # treated as certainty PSUs. Resolve any such survey-specific case explicitly.
  if (any(table(f$.dhs_stratum)<2L)) stop('Singleton survey stratum: specify a documented survey-specific treatment.')
  design <- survey::svydesign(ids=~.dhs_psu,strata=~.dhs_stratum,weights=~.dhs_w,
                    data=data,nest=TRUE)
  # degf() excludes zero-weight placeholder PSUs. Retain the documented
  # full-frame degrees of freedom for domain intervals and model tests.
  attr(design,'dhs_design_df') <- nrow(f)-length(unique(f$.dhs_stratum))
  design
}

dhs_percentage <- function(design, indicator, domain=NULL) {
  n <- sum(design$variables$.dhs_record)
  if (length(indicator)!=n) stop('Indicator length does not match the analysis records.')
  if (is.null(domain)) domain <- rep(TRUE,n)
  if (length(domain)!=n || anyNA(domain)) stop('Invalid descriptive domain.')
  domain <- as.logical(domain)
  raw_w <- weights(design)[design$variables$.dhs_record]
  valid <- domain & !is.na(indicator)
  if (any(!as.numeric(indicator[valid])%in%c(0,1))) stop('Percentage indicators must be binary.')
  if (!any(valid) || sum(raw_w[valid])<=0) return(c(percent=NA_real_,se_pct=NA_real_,ci_low_pct=NA_real_,ci_high_pct=NA_real_,unweighted_n=sum(valid),weighted_n=sum(raw_w[valid]),design_df=attr(design,'dhs_design_df')))
  design$variables$.dhs_indicator <- 0
  design$variables$.dhs_domain <- FALSE
  at <- which(design$variables$.dhs_record)
  design$variables$.dhs_indicator[at] <- as.numeric(indicator)
  design$variables$.dhs_domain[at] <- valid
  # svyratio keeps the full survey frame for domain inference. Its point
  # estimate is the same weighted proportion as svymean on the domain.
  design$variables$.dhs_num <- ifelse(design$variables$.dhs_domain,design$variables$.dhs_indicator,0)
  fit <- survey::svyratio(~.dhs_num,~.dhs_domain,design,na.rm=TRUE)
  p <- as.numeric(coef(fit)); se <- as.numeric(survey::SE(fit)); df <- attr(design,'dhs_design_df')
  critical <- qt(.975,df)
  interval <- p+c(-1,1)*critical*se
  # With no observed variation, a zero-width Wald interval is misleading.
  # Preserve the point/SE but leave uncertainty bounds unreported.
  if (p<=0 || p>=1) interval <- c(NA_real_,NA_real_)
  c(percent=100*p,se_pct=100*se,ci_low_pct=100*max(0,interval[1]),
    ci_high_pct=100*min(1,interval[2]),unweighted_n=sum(valid),
    weighted_n=sum(raw_w[valid]),design_df=df)
}

dhs_psu_variance <- function(influence, frame) {
  # influence contains already-weighted sums, one row per original-frame PSU.
  # survey::svyrecvar supplies the stratified design covariance, not a naive
  # model Hessian or an independent-record variance.
  f <- data.frame(wt=1,cluster=as.character(frame$cluster),stratum=as.character(frame$stratum))
  if (nrow(as.matrix(influence))!=nrow(f)) stop('Influence rows do not match the full PSU frame.')
  d <- dhs_design(f,f)
  survey::svyrecvar(as.matrix(influence),d$cluster,d$strata,d$fpc,lonely.psu='fail')
}

dhs_binary_fit <- function(formula, data, frame, weight='wt') {
  # Padding has zero weight but retains full-frame design degrees of freedom.
  # Keep actual analysis rows for downstream prediction/score calculations.
  data <- dhs_attach_design(data,check_weights=FALSE)
  frame <- dhs_context()$frame
  design <- dhs_design(data,frame,weight=weight)
  fit <- survey::svyglm(formula,design=design,subset=.dhs_record,
                         family=quasibinomial(),rescale=FALSE,
                         control=glm.control(maxit=100L,epsilon=1e-10))
  fit$df.residual <- attr(design,'dhs_design_df')-fit$rank+1L
  fit
}

dhs_current_duration <- function(ir, rows) {
  elapsed <- as.numeric(ir$v337[rows])
  special <- elapsed==95L
  if (any(special,na.rm=TRUE)) {
    if (!'v317'%in%names(ir)) stop('v317 is needed to resolve all-calendar current use.')
    elapsed[special] <- as.numeric(ir$v008[rows[special]])-as.numeric(ir$v317[rows[special]])
  }
  if (anyNA(elapsed) || any(!is.finite(elapsed)) || any(elapsed<0) || any(as.numeric(ir$v337[rows])%in%c(96L,997L,998L,999L))) stop('Unresolved current-use duration: do not treat special DHS codes as exact months.')
  elapsed
}

# One context per analysis subprocess; restricted records stay in memory.
.dhs_context <- new.env(parent=emptyenv())
dhs_set_context <- function(country=NULL, root=NULL, ir=NULL) {
  if (!is.null(country)) .dhs_context$country <- country
  if (!is.null(root)) .dhs_context$root <- root
  if (!is.null(ir)) {
    stopifnot(all(c('v005','v021','v022') %in% names(ir)))
    .dhs_context$ir <- as.data.frame(ir[,intersect(c('caseid','v005','v021','v022','v008','v317','v337'),names(ir)),drop=FALSE])
    .dhs_context$frame <- dhs_frame(ir)
    .dhs_context$woman_design <- dhs_design(data.frame(wt=as.numeric(ir$v005)/1e6,cluster=as.character(ir$v021),stratum=as.character(ir$v022)),.dhs_context$frame)
  }
  invisible(NULL)
}
dhs_context <- function() {
  if (!exists('ir',.dhs_context,inherits=FALSE)) {
    if (!exists('root',.dhs_context,inherits=FALSE)) stop('Initialize the DHS analysis context.')
    raw <- switch(.dhs_context$country,Ethiopia='Data/ET2024DHS__ETIR8ADT__IR_raw.rds',
                  Nigeria='Data/raw_dhs_ir/NG2024DHS__NGIR8BDT__IR_raw.rds',DRC='Data/ir.rds')
    staged <- file.path(.dhs_context$root,raw)
    if(file.exists(staged)) {
      ir <- readRDS(staged)
    } else if(identical(.dhs_context$country,'DRC')) {
      # DRC's preparation stage creates its lossless RDS after expanding the
      # calendar. Its supplied/staged IR is already available at that point.
      input <- Sys.getenv('DRC_IR_FILE',unset=file.path(.dhs_context$root,'Data/CDIR81FL.dta'))
      if(!file.exists(input)||!requireNamespace('haven',quietly=TRUE))
        stop('Supply the authorized DRC IR input before calendar preparation.')
      ir <- as.data.frame(haven::read_dta(input))
    } else stop('The prepared IR input is missing; run input preparation first.')
    dhs_set_context(ir=ir)
  }
  .dhs_context
}
# Calendar records inherit their woman's original design identifiers.
# A supplied estimation weight may be a resampling weight and is preserved.
dhs_attach_design <- function(data, ir=NULL, check_weights=TRUE) {
  data <- as.data.frame(data)
  if (is.null(ir)) ir <- dhs_context()$ir
  id <- if ('woman_row'%in%names(data)) data$woman_row else if ('woman'%in%names(data)) data$woman else NULL
  if (is.null(id) && 'caseid'%in%names(data) && 'caseid'%in%names(ir)) id <- match(data$caseid,ir$caseid)
  if (!is.null(id)) {
    if(anyNA(id)||any(id<1L|id>nrow(ir))||any(id!=as.integer(id)))stop('Invalid woman-to-calendar linkage.')
    data$cluster <- as.character(ir$v021[id]);data$stratum <- as.character(ir$v022[id])
    base_weight <- as.numeric(ir$v005[id])/1e6
    if (check_weights && 'wt'%in%names(data) && any(abs(as.numeric(data$wt)-base_weight)>1e-10))
      stop('Calendar base weights differ from the linked woman weights.')
    if(!'wt'%in%names(data))data$wt <- base_weight
    data$dhs_base_weight <- base_weight
    data$woman_id <- if('caseid'%in%names(ir))as.character(ir$caseid[id])else as.character(id)
  } else {
    if(!'cluster'%in%names(data))stop('Calendar records require woman linkage or PSU/stratum identifiers.')
    # Older modules store the nested PSU key instead of the original numeric ID.
    nested <- paste(as.character(ir$v022),as.character(ir$v021),sep=':')
    if(any(grepl(':',as.character(data$cluster),fixed=TRUE))) {
      at<-match(as.character(data$cluster),nested)
      if(anyNA(at))stop('Unrecognized nested PSU key.')
      data$cluster<-as.character(ir$v021[at])
      if('stratum'%in%names(data)&&any(as.character(data$stratum)!=as.character(ir$v022[at])))
        stop('Nested PSU key and stratum disagree.')
      data$stratum<-as.character(ir$v022[at])
    }
    if(!'stratum'%in%names(data))stop('Unlinked calendar records require explicit strata or a verified nested PSU key.')
  }
  data
}

# Point AFT fits use survey linearization; bootstrap refits can use the weighted
# likelihood because joint uncertainty is taken from the stratified PSU replicates.
dhs_aft_fit <- function(formula, data, weights, dist, control, ...) {
  supplied <- as.numeric(eval(substitute(weights),envir=data,enclos=parent.frame()))
  if(length(supplied)!=nrow(data)||anyNA(supplied)||any(supplied<0))stop('Invalid AFT estimation weights.')
  data <- dhs_attach_design(data,check_weights=FALSE)
  data$.aft_weight <- supplied
  data <- data[supplied>0,,drop=FALSE]
  if(isTRUE(getOption('dhs.replication',FALSE))) {
    return(survival::survreg(formula,data=data,weights=.aft_weight,dist=dist,control=control,...))
  }
  design <- dhs_design(data,dhs_context()$frame,weight='.aft_weight')
  fit <- do.call(survey::svysurvreg,list(formula=formula,design=design,
       subset=quote(.dhs_record),dist=dist,control=control,...))
  # svysurvreg deliberately removes its likelihood. Preserve the previous
  # weighted pseudo-AIC only for the separate, conditional family comparison;
  # do not restore it as a survey-model likelihood or use it for uncertainty.
  likelihood_fit <- survival::survreg(formula,data=data,weights=.aft_weight,
                                      dist=dist,control=control,...)
  if(max(abs(coef(fit)-coef(likelihood_fit)))>1e-6 ||
       abs(fit$scale-likelihood_fit$scale)>1e-6)
    stop('Survey and weighted AFT point fits do not agree.')
  fit$dhs_weighted_aic <- stats::AIC(likelihood_fit)
  fit$call$design <- quote(design)
  attr(fit,'dhs_design_df') <- attr(design,'dhs_design_df')
  fit
}
dhs_aft_aic <- function(fit) {
  if(inherits(fit,'svysurvreg')) {
    if(is.null(fit$dhs_weighted_aic))stop('Weighted family-comparison score is absent.')
    return(fit$dhs_weighted_aic)
  }
  stats::AIC(fit)
}

# Weighted multinomial coefficients with full-frame stratified PSU covariance.
# Retains the likelihood Hessian as the derivative; never reports it as survey variance.
dhs_multinom_summary <- function(fit, data, frame=NULL) {
  data <- dhs_attach_design(data,check_weights=FALSE)
  if(is.null(frame))frame<-dhs_context()$frame
  X<-model.matrix(delete.response(terms(fit)),data,contrasts.arg=fit$contrasts)
  p<-predict(fit,newdata=data,type='probs')
  if(is.null(dim(p)))stop('Use svyglm for binary models.')
  lev<-fit$lev[-1L];y<-model.response(model.frame(terms(fit),data))
  w<-if('fit_weight'%in%names(data))data$fit_weight else data$wt
  score<-do.call(cbind,lapply(lev,function(k)X*(w*(as.numeric(y==k)-p[,k]))))
  H<-fit$Hessian
  if(is.null(H))H<-getFromNamespace('multinomHess','nnet')(fit,Z=X,probs=p)
  expected<-unlist(lapply(lev,function(k)paste(k,colnames(X),sep=':')))
  if(!is.null(colnames(H))&&!identical(colnames(H),expected))stop('Multinomial score ordering differs from the Hessian.')
  key<-function(s,p)paste(s,p,sep=':')
  keys<-key(frame$stratum,frame$cluster);at<-match(key(data$stratum,data$cluster),keys)
  if(anyNA(at))stop('Model records do not match the original survey frame.')
  U<-matrix(0,nrow(frame),ncol(score));z<-rowsum(score,at,reorder=FALSE);U[as.integer(rownames(z)),]<-z
  bread<-MASS::ginv(H);V<-bread%*%dhs_psu_variance(U,frame)%*%bread
  co<-coef(fit);se<-matrix(sqrt(pmax(diag(V),0)),nrow=nrow(co),byrow=TRUE,dimnames=dimnames(co))
  list(coefficients=co,standard.errors=se,covariance=V,
       design_df=nrow(frame)-length(unique(frame$stratum)),inference='Full-frame stratified PSU sandwich')
}

dhs_calendar_records <- function(data, ir) {
  if(!'woman_row'%in%names(data))stop('Calendar records require woman_row.')
  id<-data$woman_row
  if(anyNA(id)||any(id<1L|id>nrow(ir)))stop('Invalid calendar woman indices.')
  w<-as.numeric(ir$v005[id])/1e6
  if('wt'%in%names(data)&&any(abs(as.numeric(data$wt)-w)>1e-10))stop('Calendar weight inheritance failed.')
  data$wt<-w;data$v021<-as.numeric(ir$v021[id]);data$v022<-as.numeric(ir$v022[id])
  data$woman_id<-as.character(ir$caseid[id])
  attr(data,'dhs_ir_design')<-as.data.frame(ir[,intersect(c('caseid','v005','v021','v022'),names(ir)),drop=FALSE])
  data
}

# Preserve survey covariance on fitted multinomial objects so subsequent
# summary()/vcov() calls cannot silently fall back to independent-record errors.
dhs_multinom_fit <- function(formula, data, weights, ...) {
  supplied<-as.numeric(eval(substitute(weights),envir=data,enclos=parent.frame()))
  if(length(supplied)!=nrow(data)||anyNA(supplied)||any(supplied<0))stop('Invalid multinomial estimation weights.')
  data<-dhs_attach_design(data,check_weights=FALSE);data$.dhs_fit_weight<-supplied
  fit<-nnet::multinom(formula,data=data,weights=.dhs_fit_weight,...)
  if(!is.null(fit$Hessian)&&!isTRUE(getOption('dhs.replication',FALSE))) {
    data$fit_weight<-supplied
    z<-dhs_multinom_summary(fit,data)
    fit$dhs_survey_vcov<-z$covariance;fit$dhs_design_df<-z$design_df
  }
  fit$dhs_inference<-if(is.null(fit$dhs_survey_vcov))'Stratified PSU refits required; ordinary Hessian inference disabled'else'Full-frame stratified PSU sandwich'
  class(fit)<-c('dhs_multinom',class(fit));fit
}
vcov.dhs_multinom <- function(object, ...) {
  if(is.null(object$dhs_survey_vcov))stop('This prediction/refit model has no point survey covariance. Use its stratified-PSU replicate inference.')
  object$dhs_survey_vcov
}
summary.dhs_multinom <- function(object, ...) {
  if(is.null(object$dhs_survey_vcov))stop('This prediction/refit model requires its stratified-PSU replicate inference.')
  getS3method('summary','multinom',envir=asNamespace('nnet'))(object,...)
}
