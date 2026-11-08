# Updated report companion: revised planning and incremental HTML build.
# --run=revised-html requires fitted statistics and the current validated report layout.
# Raw-IR preparation remains a separate mode; this does not freshly render every chapter.
# Parameterized IR preparation: --run=prepare; --validate-input checks inputs only.
# Updated survey-design and planning inference. Use --run=survey-update after core inputs and derived episodes are available.
# New planning tables are derived from output/survey_planning/planning_intervals.csv.
#!/usr/bin/env Rscript
# Nigeria — numerical source companion to the final HTML
# Parameterized inputs and project-relative outputs; no survey microdata embedded.
# Original analysis definitions and numerical expressions are retained.
# Historical variants are distinct modules, not a single interchangeable model.
RECONCILIATION_CODE <- r"-----(#!/usr/bin/env python3
"""Reconcile saved HTML with aggregate numerical outputs, without editing it.

All locations are parameters. Saved-output matches are NOT fresh reproduction.
Inference about candidate sources never counts as end-to-end verification.
"""
import argparse,csv,hashlib,json,re,math
from pathlib import Path
from collections import Counter
from urllib.parse import unquote,urlsplit
from lxml import html


def norm(x):
    return re.sub(r'\s+',' ',str(x).replace('\u00a0',' ')).strip().casefold()

def variants(x):
    s=norm(x);out={s}
    try:
        v=float(s)
        if math.isfinite(v):
            for n in range(7):
                out.update((f'{v:.{n}f}',f'{v:,.{n}f}',f'{v:.{n}f}%'))
        else:out.update(('','—','–','na','nan'))
    except ValueError:pass
    return out

def table_rows(el):
    return [[norm(c.text_content()) for c in row.xpath('./th|./td')]
            for row in el.xpath('./thead/tr|./tbody/tr|./tr|./tfoot/tr')]

def csv_read(path):
    try:
        with path.open(encoding='utf-8-sig',newline='') as f:
            rows=list(csv.reader(f))
        return rows if rows and all(len(r)==len(rows[0]) for r in rows) else []
    except (UnicodeError,csv.Error):return []

def compare(a,b):
    if len(a)!=len(b):return False
    for x,y in zip(a,b):
        if len(x)!=len(y):return False
        for v,w in zip(x,y):
            if v==w:continue
            try:
                if math.isnan(float(v)) and math.isnan(float(w)):continue
                if math.isclose(float(v),float(w),rel_tol=1e-10,abs_tol=1e-10):continue
            except ValueError:pass
            return False
    return True

_indices={}
def candidate_rows(row,source):
    key=id(source)
    if key not in _indices:
        ix={}
        for i,r in enumerate(source[1:]):
            for t in set(norm(x) for x in r):
                if t and not re.fullmatch(r'[-+\d.eE,%]+',t):ix.setdefault(t,set()).add(i)
        _indices[key]=ix
    ix=_indices[key]
    available=[ix[t] for t in row if t in ix]
    return sorted(set.intersection(*available)) if available else range(len(source)-1)

def match_rows(body,source):
    """Require one consistent column projection and every displayed row.
    This is a candidate, not proof of the statistical meaning of a column.
    """
    data=source[1:]
    if not body or not data or any(len(r)!=len(body[0]) for r in body):return None
    if len(body[0])>len(source[0]):return None
    # Try source rows matching every first displayed cell; avoid one-number tables.
    if len(body[0])<2:return None
    poss=[]
    for ri in candidate_rows(body[0],source):
        row=data[ri]
        vs=[variants(x) for x in row]
        cols=[[i for i,v in enumerate(vs) if token in v] for token in body[0]]
        if all(cols):poss.append((ri,cols))
    if len(poss)>40:return None
    import itertools
    for ri,cols in poss:
        if math.prod(map(len,cols))>1000:continue
        for mapping in itertools.product(*cols):
            if len(set(mapping))<len(mapping):continue
            indices=[]
            for row in body:
                found=next((i for i in candidate_rows(row,source) if all(t in variants(data[i][j]) for t,j in zip(row,mapping))),None)
                if found is None:break
                indices.append(found)
            if len(indices)==len(body):return dict(columns=[source[0][j] for j in mapping],source_rows=[i+2 for i in indices])
    return None

def write_csv(path,rows,fields):
    with path.open('w',newline='',encoding='utf-8') as f:
        w=csv.DictWriter(f,fieldnames=fields);w.writeheader();w.writerows(rows)

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--country',required=True)
    ap.add_argument('--report-html',type=Path,required=True)
    ap.add_argument('--project-root',type=Path,required=True)
    ap.add_argument('--fresh-root',type=Path)
    ap.add_argument('--output-dir',type=Path,required=True)
    ap.add_argument('--strict',action='store_true')
    a=ap.parse_args();a.output_dir.mkdir(parents=True,exist_ok=True)
    doc=html.fromstring(a.report_html.read_text());sections=doc.xpath('//section')
    source_files=list((a.project_root/'output/Supporting_data').glob('*.csv'))
    saved={p.name:csv_read(p) for p in source_files}
    saved={n:r for n,r in saved.items() if r and len(r)<10000}
    compared={};fresh_rows=[]
    for name,rows in saved.items():
        fresh=a.fresh_root/'output/Supporting_data'/name if a.fresh_root else None
        status='not_recomputed'
        if fresh and fresh.exists():status='fresh_matches_saved' if compare(rows,csv_read(fresh)) else 'fresh_differs_from_saved'
        compared[name]=status
        fresh_rows.append(dict(file=name,status=status))
    inventory=[];bindings=[]
    for i,t in enumerate(doc.xpath('//table'),1):
        ancestors=t.xpath('ancestor::section[1]');sid=ancestors[0].get('id','') if ancestors else '(outside section)'
        rows=table_rows(t);body=rows[1:];tokens={x for r in body for x in r if x and not re.fullmatch(r'[\d.,%+−–—-]+',x)}
        candidates=[]
        if body and tokens:
            for name,src in saved.items():
                # Cheap filter on text labels before cell-by-cell checks.
                labels={norm(x) for row in src[1:] for x in row if not re.fullmatch(r'[-+\d.eE]+',x)}
                if not tokens.intersection(labels):continue
                binding=match_rows(body,src)
                if binding:candidates.append((name,binding))
        status='unmapped'
        if candidates:status='candidate_saved_output_match'
        inventory.append(dict(table=i,section=sid,rows=len(body),columns=len(rows[0]) if rows else 0,
                              status=status,candidate_sources='; '.join(n for n,_ in candidates),
                              fresh_candidate_matches=sum(compared[n]=='fresh_matches_saved' for n,_ in candidates)))
        bindings.append(dict(table=i,section=sid,candidates=[dict(file=n,**b) for n,b in candidates]))
    assets=[]
    for src in dict.fromkeys(doc.xpath('//img/@src')):
        u=urlsplit(src)
        if u.scheme or u.netloc:status='external_or_embedded';digest=''
        else:
            p=a.report_html.parent/unquote(u.path)
            status='present' if p.is_file() else 'missing'
            digest=hashlib.sha256(p.read_bytes()).hexdigest() if p.is_file() else ''
        assets.append(dict(asset=src,status=status,sha256=digest,recomputed='not_verified'))
    ids=Counter(doc.xpath('//@id'))
    issues=[]
    if a.country=='DRC':
        issues += [dict(section='method-duration-class-discontinuation',issue='Original grouping uses Pill/Injectables only for short acting; condoms are omitted relative to Ethiopia.',status='definition_discrepancy'),
                   dict(section='selected-reason-risk-strata',issue='Original DRC bands are in-sample predictions; Ethiopia uses held-out PSU predictions.',status='method_discrepancy'),
                   dict(section='historical-duration-aware-planning',issue='Three tables are present; Ethiopia contains eight. Same section names do not establish coverage.',status='coverage_discrepancy')]
    if a.country=='Nigeria':issues += [dict(section='regional-actionable-method-mix-decomposition',issue='Original code pools IUD with other modern and uses a different cohort/estimator from the Ethiopia pairwise shared-mix analysis.',status='method_discrepancy'),dict(section='three-approach-planning',issue='Saved planning uses projected 2025 stock and 2026 scenarios; earlier requested 2024 to 2025 horizon needs resolution.',status='horizon_review')]
    issues += [dict(section='historical-duration-aware-planning; aft-duration-aware-planning',issue='mCPR equivalents use year-end nonmodern counts with observed switching/restarting; distinguish from gross actionable original-method endings.',status='estimand_review')]
    summary=dict(country=a.country,report_sha256=hashlib.sha256(a.report_html.read_bytes()).hexdigest(),
      sections=len(sections),tables=len(inventory),images=len(assets),missing_images=sum(x['status']=='missing' for x in assets),
      table_candidate_matches=sum(bool(x['candidate_sources']) for x in inventory),
      fresh_outputs_matching=sum(v=='fresh_matches_saved' for v in compared.values()),
      fresh_outputs_differing=sum(v=='fresh_differs_from_saved' for v in compared.values()),
      duplicate_ids=[k for k,v in ids.items() if v>1],
      numerical_reproduction_complete=False,html_regeneration_complete=False,
      explanation='Candidate cell matches are provenance leads, not validation. Unmapped tables, figures, inference and scientific definitions still require review. No report was edited.')
    (a.output_dir/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
    (a.output_dir/'candidate_bindings.json').write_text(json.dumps(bindings,indent=2)+'\n')
    write_csv(a.output_dir/'tables.csv',inventory,['table','section','rows','columns','status','candidate_sources','fresh_candidate_matches'])
    write_csv(a.output_dir/'assets.csv',assets,['asset','status','sha256','recomputed'])
    write_csv(a.output_dir/'fresh_outputs.csv',fresh_rows,['file','status'])
    write_csv(a.output_dir/'definition_issues.csv',issues,['section','issue','status'])
    print(json.dumps(summary,indent=2))
    if a.strict:raise SystemExit(2)
if __name__=='__main__':main()
)-----"
COUNTRY <- "Nigeria"
REPORT_BASENAME <- "Nigeria_discontinuation_analysis.html"
REPORT_SHA256 <- "dfa858a4bb20cab9391dbd4333c2b58dbfa28af99c0a06cd71a8d209fb760b4b"
RAW_RELATIVE <- "Data/raw_dhs_ir/NG2024DHS__NGIR8BDT__IR_raw.rds"
CORE_MODULES <- c("01_nigeria_calendar_life_table.R")
PLANNING_MODULES <- c("01_nigeria_calendar_life_table.R", "02_nigeria_descriptive_analyses.R", "08_nigeria_population_and_planning.R", "22_nigeria_landmark_support.R", "23_nigeria_current_user_switch_and_duration.R", "91_nigeria_aft_switching_bridge.R", "95_build_duration_planning_data.py")
REQUIRED_R_PACKAGES <- c('digest','haven','jsonlite','survey','survival','nnet','ggplot2','grid','gridExtra','parallel','scales','sf','svglite')
BOOTSTRAP_ENV <- c("NIGERIA_PLANNING_BOOTSTRAP_REPS", "BOOTSTRAP_REPS", "NIGERIA_ALL_REASON_BOOTSTRAP_REPS", "NIGERIA_ALL_REASON_MODEL_BOOTSTRAP_REPS", "NIGERIA_BOOTSTRAP_REPS", "NIGERIA_METHOD_ZONE_REPS", "NIGERIA_MODEL_BOOTSTRAP_REPS", "NIGERIA_SELECTED_BOOTSTRAP_REPS", "NIGERIA_SELECTED_MODEL_BOOTSTRAP_REPS", "NIGERIA_SUBGROUP_BOOTSTRAP_REPS", "REFERENCE_BOOTSTRAP_REPS", "REFERENCE_MODEL_REPS", "RISK_STRATA_BOOTSTRAP_REPS")
SECTION_INDEX <- r"-----(section_id	title
methodology	What each probability measures
current-use	Current modern use and implications for user-loss planning
initiation	Entry methods set the denominator for future retention risk
dhs-712	The calendar reconstruction matches published Table 7.12
dhs-713	Reasons among recorded modern-method discontinuations
all-cause	All-reason discontinuation comes first
regional-method-paired-bars	Method starts and all-reason discontinuation by zone
all-reason-users	Illustrative current-user endings for all reasons
twelve-month-three-column-comparison	12-month discontinuation by method and reason definition
all-reason-transitions	What follows an all-reason discontinuation?
selected-reasons	The intermediate selected-reason measure
selected-models	Who is more likely to discontinue for a selected reason?
selected-reason-transitions	What follows discontinuation for a selected reason?
selected-followup	What happened after selected-reason discontinuation?
other-reasons-count-breakdown	What falls under “Other” reasons?
other-reason-followup	What follows an “Other” ending?
selected-reason-descriptive-subgroups	Unadjusted 12-month selected-reason discontinuation by subgroup
method-experience-subgroup-reasons	Method experience and access reasons within subgroups
top-three-reasons-by-subgroup-method	Top three actionable reasons by subgroup and method
selected-reason-risk-strata	Cross-validated lower, middle and higher risk bands
method-duration-class-discontinuation	Selected-reason risk by method-duration class
short-acting-selected-reason-distribution	Why short-acting modern methods ended within 12 months
selected-reason-regional-analysis	Selected-reason discontinuation across Nigeria’s six zones
selected-reason-regional-adjusted	Observed and adjusted 12-month probabilities by zone
selected-reason-regional-reason-heatmap	Reason mix among selected discontinuations by zone
regional-episode-mix-and-risk	Episode method mix and within-method selected-reason risk
national	Method starts and 12-month actionable risk
post-ending	Modern use after an actionable method ending
timing	Actionable discontinuation accumulates during the first year
zone-rates	Potentially actionable risk differs across the six zones
zone-reasons	The mix of actionable reasons varies by zone
method-mix	Entry method mix is different across the six zones
methods-by-zone	Within-method risk shows where method mix cannot explain the whole pattern
method-reasons	Reasons within each method and zone
action-pathways	From injectable endings to program action
models	Adjustment helps separate composition from zone differences
subgroups	Observed actionable risk by subgroup
pairwise	Which zone contrasts survive statistical testing?
method-zone-regressions	Within-method comparisons across Nigeria’s six zones
regional-actionable-method-mix-decomposition	How much of each zone gap reflects method mix?
regional-analyses	Regional analyses
population	Nigeria population and mCPR inputs
user-projections	Illustrative current-user method endings
current-user-reason-planning	Illustrative first-year method endings by selected reason
duration-adjusted-reason-planning	Next-year original-method endings among current users
standardized-current-users	Expected pathway among current modern users
mcpr-scenarios	Illustrative 2026 mCPR scenarios
method-level-mcpr-scenarios	2026 mCPR scenarios by current method
three-approach-planning	Three approaches to actionable discontinuation and mCPR
historical-duration-aware-planning	Historical duration-aware planning
aft-duration-aware-planning	AFT survival and observed pathways
duration-planning-appendix	Earlier switching and duration-aware analyses
switch-bridge	Direct modern switching reduces the gross user-loss illustration
duration-bridge	Accounting for elapsed use and modern status at year end
duration-aware-cause-pp-matrices	Actionable endings and year-end modern use: method by cause)-----"

# USAGE (relative example locations; provide your own authorized IR file):
#   Rscript Nigeria_final_html_analysis.R --list
#   Rscript Nigeria_final_html_analysis.R --validate
#   Rscript Nigeria_final_html_analysis.R --extract --project-root=analysis_output
#   Rscript Nigeria_final_html_analysis.R --run=core --project-root=analysis_output --ir-file=data/individual_recode.dta
#   Rscript Nigeria_final_html_analysis.R --run=MODULE_NAME --project-root=analysis_output --ir-file=data/individual_recode.dta
#
# --reconcile --report-html=report.html --project-root=analysis_output
# optionally takes --fresh-root for independently rebuilt outputs. It writes
# a table/figure inventory and discrepancy records; candidate matches are NOT
# a complete validation or report renderer. Requires Python with lxml.
# Numerical execution does not require an existing HTML. Legacy in-place HTML
# updates in the two early Ethiopia modules are disabled unless explicitly set
# with RENDER_LEGACY_HTML=true. No statistical expression is changed by that guard.
# --verify-planning --report-html=report.html --project-root=analysis_output
# --fresh-root=rebuilt_output verifies and renders the historical/AFT tables only.
# --run=planning rebuilds the saved three-approach planning outputs from the IR
# plus frozen aggregate population inputs. It does not regenerate the full HTML.
# --run also accepts a comma-separated ordered list of module filenames.
# --auxiliary-dir can supply other inputs in the original project-relative
# structure (Data/..., output/Supporting_data/...). Nothing is downloaded.
# --overwrite permits replacing extracted code or aggregate input files.
# --python selects the interpreter for the explicitly identified Python helpers.
# --bootstrap-reps overrides recognized bootstrap environment settings; omit it
# to retain each module's historical default. Model resampling can be lengthy.
#
# AUDIT UPDATE: --run=reference runs the shared reference-alignment module after
# --run=core. It writes separate outputs and never alters checked HTML or PPTX.
# REFERENCE_TASKS selects descriptive,risk_strata,models,pathways.
# REFERENCE_MODEL_SPECS selects individual model IDs. For diagnostic runs use
# REFERENCE_BOOTSTRAP_REPS=0 and REFERENCE_MODEL_REPS=0; those runs emit no CIs.
# Corrected coverage: native reason groups; condoms in short-acting methods;
# five method categories in shared-mix comparisons; held-out PSU risk groups;
# full method-by-subgroup reasons; 15-49-at-start model cohort; model variants.
# IMPORTANT: archived modules retain prior report definitions for provenance.
# New outputs require reconciliation before claiming that final reports agree.
# Syntax validation is not proof of full statistical/report replication.
# This file is an executable SOURCE COLLECTION, not an automatic replay of
# every historical model variant. Source modules remain separate because the
# final report accumulated different outcomes, cohorts, and specifications.
# Select the modules needed in dependency order; their actual source() calls
# and input/output filenames are preserved. The core alias builds calendar
# episodes and published-table validation, with the original country checks.
# Detailed analysis modules require the upstream derived files they read.
# RDS/DTA microdata, maps, and fitted model objects are NOT embedded.
# Only the small, frozen external population inputs used by the report are
# embedded. Provide a replacement via --auxiliary-dir to change those inputs.
# Python helpers are included where original numerical arithmetic was Python;
# they are not represented as original R code. HTML/PPTX layout assembly is
# outside this numerical source collection. This file does not edit either
# checked final document or promise pixel-identical HTML regeneration.

stopifnot(getRversion() >= '4.0.0')
MODULES <- list()
EXTERNAL_INPUTS <- list()

parse_options <- function(args) {
  out <- list(); i <- 1L
  while (i <= length(args)) {
    a <- args[i]
    if (!startsWith(a, '--')) stop('Expected a named --option.')
    a <- substring(a, 3L)
    if (grepl('=', a, fixed=TRUE)) {
      k <- sub('=.*$', '', a); out[[k]] <- substring(a, nchar(k) + 2L)
    } else if (a %in% c('list','validate','extract','overwrite','help','packages','reconcile','verify-planning','validate-input')) {
      out[[a]] <- TRUE
    } else {
      if (i == length(args)) stop('Missing option value.')
      i <- i + 1L; out[[a]] <- args[i]
    }
    i <- i + 1L
  }
  allowed <- c('list','validate','extract','overwrite','help','packages','run',
               'project-root','ir-file','auxiliary-dir','python','bootstrap-reps','reconcile','report-html','fresh-root','audit-output','verify-planning','expected-ir-sha256','validate-input','statistics-dir','base-html','revision-inputs')
  if (length(setdiff(names(out), allowed))) stop('Unrecognized option.')
  out
}

list_modules <- function() {
  cat(COUNTRY, ': numerical modules accompanying ', REPORT_BASENAME, '\n', sep='')
  for (name in names(MODULES)) {
    cat(sprintf('  %-65s %s\n', name, MODULES[[name]]$language))
  }
  cat('\nCore alias: ', paste(CORE_MODULES, collapse=', '), '\n', sep='')
  cat('Use --run=filename or an ordered comma-separated list. Use --validate to parse all R sources.\n')
}

write_checked <- function(text, path, overwrite=FALSE) {
  dir.create(dirname(path), recursive=TRUE, showWarnings=FALSE)
  text <- sub('[\r\n]+$', '', text)
  if (file.exists(path)) {
    old <- paste(readLines(path, warn=FALSE, encoding='UTF-8'), collapse='\n')
    if (identical(sub('[\r\n]+$', '', old), text)) return(invisible(path))
    if (!overwrite) stop('Destination already contains a different file: ', basename(path),
                         '. Use a new project root or --overwrite.')
  }
  writeLines(enc2utf8(text), path, useBytes=TRUE)
  invisible(path)
}

extract_sources <- function(root, overwrite=FALSE, aux='') {
  dir.create(root, recursive=TRUE, showWarnings=FALSE)
  root <- normalizePath(root, mustWork=TRUE)
  for (name in names(MODULES)) {
    write_checked(MODULES[[name]]$code, file.path(root,'Code',name), overwrite)
  }
  # User-supplied auxiliary inputs take precedence over frozen external inputs.
  if (nzchar(aux)) {
    if (!dir.exists(aux)) stop('Auxiliary input directory does not exist.')
    aux <- normalizePath(aux, mustWork=TRUE)
    files <- list.files(aux, recursive=TRUE, all.files=TRUE, full.names=FALSE,
                        include.dirs=FALSE, no..=TRUE)
    for (rel in files) {
      dest <- file.path(root,rel); src <- file.path(aux,rel)
      dir.create(dirname(dest), recursive=TRUE, showWarnings=FALSE)
      if (file.exists(dest) && !overwrite && tools::md5sum(src) != tools::md5sum(dest))
        stop('Different auxiliary destination exists: ', basename(dest))
      if (!file.exists(dest) || overwrite) {
        if (!file.copy(src,dest,overwrite=overwrite)) stop('Could not copy auxiliary file.')
      }
    }
  }
  for (rel in names(EXTERNAL_INPUTS)) {
    target <- file.path(root,rel)
    if (!file.exists(target)) write_checked(EXTERNAL_INPUTS[[rel]],target,FALSE)
  }
  dir.create(file.path(root,'output','Supporting_data'),recursive=TRUE,showWarnings=FALSE)
  dir.create(file.path(root,'Data','Derived'),recursive=TRUE,showWarnings=FALSE)
  write_checked(SECTION_INDEX, file.path(root,'Code','report_section_index.tsv'), overwrite)
  manifest <- data.frame(module=names(MODULES),
    language=vapply(MODULES,function(z)z$language,''),
    sha256=vapply(names(MODULES),function(n)digest::digest(file=file.path(root,'Code',n),algo='sha256'),''))
  write.table(manifest,file.path(root,'Code','numerical_source_manifest.tsv'),
              sep='\t',quote=FALSE,row.names=FALSE)
  root
}

prepare_ir <- function(root, ir_file) {
  if (!nzchar(ir_file)) return(invisible(NULL))
  if (!file.exists(ir_file)) stop('The supplied IR input file does not exist.')
  ir_file <- normalizePath(ir_file,mustWork=TRUE)
  ext <- tolower(tools::file_ext(ir_file))
  if (COUNTRY %in% c('Ethiopia','DRC') && ext != 'dta')
    stop('This country core uses a labelled Stata .dta IR input.')
  if (COUNTRY == 'Nigeria' && !ext %in% c('dta','rds'))
    stop('Nigeria IR input must be .dta or .rds.')
  if (COUNTRY == 'DRC') {
    Sys.setenv(DRC_IR_FILE=ir_file)
    return(invisible(NULL))
  }
  target <- file.path(root,RAW_RELATIVE)
  dir.create(dirname(target),recursive=TRUE,showWarnings=FALSE)
  if (COUNTRY == 'Nigeria' && ext == 'dta') {
    if (!requireNamespace('haven',quietly=TRUE)) stop('Install R package haven first.')
    incoming <- as.data.frame(haven::read_dta(ir_file))
    if (file.exists(target)) {
      if (!identical(readRDS(target), incoming)) stop('Cached IR differs from supplied IR.')
    } else saveRDS(incoming,target)
  } else if (file.exists(target)) {
    if (unname(tools::md5sum(target)) != unname(tools::md5sum(ir_file)))
      stop('Cached IR differs from supplied IR; choose a new project root.')
  } else if (!file.copy(ir_file,target,overwrite=FALSE)) stop('Could not stage supplied IR.')
  invisible(NULL)
}

main <- function() {
  opt <- parse_options(commandArgs(trailingOnly=TRUE))
  if (identical(opt$run,"build-html")) opt$run <- "revised-html"
  if (identical(opt$run,"build-planning")) opt$run <- "revised-planning"
  if (isTRUE(opt$help)) cat("Build modes: --run=build-html|build-planning, --statistics-dir, --base-html, --revision-inputs. See the revised README for the build boundary.\n")
  if (!is.null(opt$run) && opt$run %in% c("revised-html","revised-planning")) return(run_revised_report(opt))
  if (isTRUE(opt$reconcile) || isTRUE(opt[['verify-planning']])) {
    if (is.null(opt[['report-html']]) || is.null(opt[['project-root']]))
      stop('Reconciliation requires --report-html and --project-root.')
    python <- if(!is.null(opt$python))opt$python else Sys.getenv('PYTHON',unset='python3')
    tmp <- tempfile(fileext='.py');on.exit(unlink(tmp),add=TRUE)
    writeLines(if(isTRUE(opt[['verify-planning']])) MODULES[['201_verify_planning_html.py']]$code else RECONCILIATION_CODE,tmp,useBytes=TRUE)
    dest <- if(!is.null(opt[['audit-output']]))opt[['audit-output']] else
      file.path(dirname(opt[['report-html']]),'reconciliation')
    args <- c(tmp,'--country',COUNTRY,'--report-html',opt[['report-html']],'--output-dir',dest)
    if(!isTRUE(opt[['verify-planning']]))args<-c(args,'--project-root',opt[['project-root']])
    if(isTRUE(opt[['verify-planning']]) && is.null(opt[['fresh-root']]))stop('Planning verification requires --fresh-root.')
    if(!is.null(opt[['fresh-root']]))args<-c(args,'--fresh-root',opt[['fresh-root']])
    result<-system2(python,shQuote(args))
    if(result!=0L)stop('Reconciliation audit failed.')
    return(invisible(NULL))
  }
  if (!length(opt) || isTRUE(opt$help)) {
    cat('Portable numerical source collection for ', COUNTRY, '.\n',sep='')
    cat('Options: --list, --validate, --validate-input, --packages, --extract, --run=core|planning|survey-update|reference|MODULE[,MODULE], --reconcile\n')
    cat('Inputs: --project-root, --ir-file, --auxiliary-dir; optional --expected-ir-sha256, --python and --bootstrap-reps.\n')
    cat('No analyses run without --run. Original modules and supplied inputs determine the outputs.\n')
    return(invisible(NULL))
  }
  if (isTRUE(opt$list)) list_modules()
  if (isTRUE(opt$packages)) cat(paste(REQUIRED_R_PACKAGES,collapse=', '),'\n')
  if (isTRUE(opt[['validate']])) {
    rnames <- names(MODULES)[vapply(MODULES,function(z)z$language=='R',FALSE)]
    for (name in rnames) {
      tryCatch(parse(text=MODULES[[name]]$code,keep.source=FALSE),
               error=function(e)stop('R parsing failed for ',name,': ',conditionMessage(e)))
    }
    cat('Parsed ',length(rnames),' embedded R modules successfully.\n',sep='')
  }
  if (!isTRUE(opt$extract) && is.null(opt$run) && !isTRUE(opt[['validate-input']])) return(invisible(NULL))
  root <- if (!is.null(opt[['project-root']])) opt[['project-root']] else
    Sys.getenv('ANALYSIS_ROOT',unset=file.path('analysis_output',tolower(COUNTRY)))
  aux <- if (!is.null(opt[['auxiliary-dir']])) opt[['auxiliary-dir']] else ''
  if(!requireNamespace('digest',quietly=TRUE))stop('Install R package digest first.')
  root <- extract_sources(root,isTRUE(opt$overwrite),aux)
  do.call(Sys.setenv,setNames(list(root),paste0(toupper(COUNTRY),'_PROJECT_ROOT')))
  data <- if(COUNTRY=='Nigeria') file.path(root,'Data','raw_dhs_ir') else file.path(root,'Data')
  do.call(Sys.setenv,setNames(list(data),paste0(toupper(COUNTRY),'_INPUT_DIR')))
  ir <- if(!is.null(opt[['ir-file']])) opt[['ir-file']] else Sys.getenv('DHS_IR_FILE',unset='')
  if (nzchar(ir)) ir <- normalizePath(ir,mustWork=TRUE)
  validation <- NULL
  if (nzchar(ir)) {
    expected <- if(!is.null(opt[['expected-ir-sha256']]))opt[['expected-ir-sha256']]else''
    validation <- read_validated_ir(ir,expected)
  } else if (isTRUE(opt[['validate-input']]) || identical(opt$run,'prepare')) {
    stop('Supply --ir-file or DHS_IR_FILE for input preparation.',call.=FALSE)
  }
  prepare_ir(root,ir)
  if(!is.null(validation))write_ir_validation(root,validation)
  if(isTRUE(opt[['validate-input']]) && is.null(opt$run)) {
    cat('IR input validated; no analyses run.\n');return(invisible(NULL))
  }
  Sys.setenv(ANALYSIS_COUNTRY=COUNTRY)
  if(nzchar(ir)) Sys.setenv(DHS_IR_FILE=ir)
  if (!is.null(opt[['bootstrap-reps']])) {
    reps <- suppressWarnings(as.integer(opt[['bootstrap-reps']]))
    if (is.na(reps) || reps<1L) stop('bootstrap-reps must be a positive integer.')
    for (env in BOOTSTRAP_ENV) do.call(Sys.setenv,setNames(list(as.character(reps)),env))
  }
  cat('Extracted ',length(MODULES),' modules and the report section index.\n',sep='')
  if (is.null(opt$run)) return(invisible(NULL))
  selected <- strsplit(opt$run,',',fixed=TRUE)[[1]]
  preparing <- identical(selected,'prepare')
  if (preparing) selected <- c(CORE_MODULES,'210_prepare_analysis_inputs.R')
  if (identical(selected,'core')) selected <- CORE_MODULES
  if (identical(selected,'reference')) selected <- '200_reference_analysis_extensions.R'
  if (identical(selected,'planning')) selected <- PLANNING_MODULES
  if (identical(selected,'survey-update')) selected <- c('02_nigeria_descriptive_analyses.R','12_nigeria_all_reason_bridge.R','03_nigeria_zone_models.R','04_nigeria_subgroups_and_tests.R','13_nigeria_all_reason_models.R','17_nigeria_selected_reason_models.R','26_nigeria_actionable_method_zone_models.R','29_zone_method_mix_decomposition.R','37_nigeria_selected_reason_extensions.R','42_nigeria_crossvalidated_selected_risk_strata.R','203_nigeria_planning_survey_ci.R','204_summarize_planning.R')
  if (any(!selected %in% names(MODULES))) stop('Unknown module; use --list for filenames.')
  if (!nzchar(ir) && any(selected %in% CORE_MODULES))
    stop('Supply --ir-file or DHS_IR_FILE before running the core analysis.')
  python <- if (!is.null(opt$python)) opt$python else Sys.getenv('PYTHON',unset='python3')
  original_wd <- getwd(); on.exit(setwd(original_wd),add=TRUE)
  setwd(file.path(root,'Code'))
  log_dir <- file.path(root,'output','logs'); dir.create(log_dir,recursive=TRUE,showWarnings=FALSE)
  for (name in selected) {
    spec <- MODULES[[name]]
    exe <- if (spec$language=='R') file.path(R.home('bin'),'Rscript') else python
    argv <- c(shQuote(file.path(root,'Code',name)),spec$args)
    if ('--project-root' %in% spec$args) argv <- c(argv,shQuote(root))
    cat('Running ',name,'\n',sep='')
    log_file <- file.path(log_dir,paste0(name,'.log'))
    status <- system2(exe,argv,stdout=log_file,stderr=log_file)
    # Log paths are replaced with parameter labels; source-data rows are never printed here.
    log <- readLines(log_file,warn=FALSE)
    log <- gsub(root,'<PROJECT_ROOT>',log,fixed=TRUE)
    if (nzchar(ir)) log <- gsub(normalizePath(ir,mustWork=FALSE),'<IR_FILE>',log,fixed=TRUE)
    writeLines(log,log_file,useBytes=TRUE)
    if (!identical(status,0L)) stop('Module failed: ',name,'. See its log for missing inputs or model diagnostics.')
    cat('Completed ',name,'\n',sep='')
  }
  if(preparing) {
    if(!identical(digest::digest(file=ir,algo='sha256'),validation$sha256))
      stop('The source IR file changed during preparation.',call.=FALSE)
    complete_preparation_audit(root,validation)
  }
  invisible(NULL)
}

# Frozen aggregate external population input used for the final report.
EXTERNAL_INPUTS[["output/Supporting_data/nigeria_wpp2024_wra_2024_2026.csv"]] <- r"-----(year,women_15_49,source
2024,55819549.5,"UN World Population Prospects 2024, female single ages, medium variant, 1 July"
2025,57393553.0,"UN World Population Prospects 2024, female single ages, medium variant, 1 July"
2026,59000784.5,"UN World Population Prospects 2024, female single ages, medium variant, 1 July"
)-----"

# Frozen published aggregate validation reference; no microdata.
EXTERNAL_INPUTS[["output/Supporting_data/nigeria_published_table_7_13_reason_distribution.csv"]] <- r"-----(reason,IUD,Injectables,Implants,Pill,Male condom,Emergency contraception,Rhythm,Withdrawal,Other,All methods
Became pregnant while using,1.7,4.4,1.4,7.2,4.7,6.5,12.3,14.7,6.1,6.2
Wanted to become pregnant,35.6,34.7,41.8,27.7,28.4,26.5,49.1,39.3,24.2,34.0
Husband/partner disapproved,2.1,4.3,2.4,3.9,5.5,1.9,3.0,4.3,2.6,3.7
Wanted a more effective method,3.1,5.0,4.4,11.9,9.4,15.9,14.6,17.5,34.1,12.5
Changes in menstrual bleeding,2.7,16.7,10.9,10.4,0.1,3.8,1.3,0.4,4.0,8.0
Other side effects/health concerns,24.8,17.5,24.3,16.4,1.4,9.4,0.5,0.7,1.4,11.5
Lack of access/too far,0.0,2.3,0.7,2.7,2.0,2.4,1.4,0.5,0.8,1.5
Cost too much,0.0,1.4,0.4,2.5,0.7,0.3,0.0,0.0,0.0,0.8
Inconvenient to use,10.8,3.5,3.9,4.6,9.5,3.5,0.4,2.7,2.9,4.1
Up to God/fatalistic,1.8,1.3,0.4,0.7,1.5,1.6,0.3,2.2,5.3,1.7
Difficult to get pregnant/menopausal,5.6,0.0,0.1,0.5,0.4,0.0,0.9,0.9,0.4,0.4
Infrequent sex/husband away,5.5,4.3,2.4,9.1,27.8,22.4,12.9,13.8,9.6,10.1
Marital dissolution/separation,0.0,0.8,1.2,0.6,4.1,3.2,1.8,1.1,0.2,1.3
Other,6.2,3.1,4.1,1.1,2.5,0.6,0.7,1.5,7.7,3.2
Don’t know,0.0,0.5,0.8,0.5,1.2,0.5,0.3,0.4,0.3,0.6
Missing,0.0,0.3,0.6,0.1,0.7,1.4,0.4,0.0,0.3,0.4
)-----"

# =============================================================================
# ORIGINAL MODULE: 200_reference_analysis_extensions.R
# LANGUAGE: R
MODULES[["200_reference_analysis_extensions.R"]] <- list(
  language="R",
  original_sha256="b42549fa5545c5225a7cc1c299954ae15ed5c680f59729fd1a93c6ca17ea015e",
  packaged_sha256="b42549fa5545c5225a7cc1c299954ae15ed5c680f59729fd1a93c6ca17ea015e",
  args=character(),
  code=r"-----(#!/usr/bin/env Rscript
# Reference-aligned numerical analyses for Ethiopia, Nigeria, and DRC.
# This module supplements the archived country modules; it never edits HTML/PPTX.
# Native calendar reason codes are used throughout, not the recoded nine groups.
# Statistical reference: the Ethiopia final HTML and its numerical source modules.
# Country differences in geography, source labels and population are retained.
# Run after the country's calendar module. Supply ANALYSIS_COUNTRY and its
# COUNTRY_PROJECT_ROOT; DHS_IR_FILE can override the staged IR input.
# REFERENCE_TASKS: descriptive,risk_strata,models,pathways (default: all four).
# REFERENCE_BOOTSTRAP_REPS and REFERENCE_MODEL_REPS default to 400.
# Fewer than 100 replicates is diagnostic only: no CIs or p-values are emitted.
# REFERENCE_MODEL_SPECS can select a comma-separated subset of model IDs below.
# Results go to output/reference_alignment, separately from existing report data.

country <- Sys.getenv('ANALYSIS_COUNTRY')
if (!country %in% c('Ethiopia','Nigeria','DRC')) stop('Set ANALYSIS_COUNTRY.')
root <- Sys.getenv(paste0(toupper(country),'_PROJECT_ROOT'))
if (!nzchar(root)) stop('Set the country project root.')
out <- file.path(root,'output','reference_alignment')
dir.create(out,recursive=TRUE,showWarnings=FALSE)
tasks <- strsplit(Sys.getenv('REFERENCE_TASKS','descriptive,risk_strata,models,pathways'),',',fixed=TRUE)[[1]]
B <- as.integer(Sys.getenv('REFERENCE_BOOTSTRAP_REPS','400'))
MB <- as.integer(Sys.getenv('REFERENCE_MODEL_REPS','400'))
stopifnot(is.finite(B),B>=0,is.finite(MB),MB>=0)
emit <- function(x,name) write.csv(x,file.path(out,paste0(name,'.csv')),row.names=FALSE,na='')
input <- function(rel) file.path(root,rel)
config <- switch(country,
 Ethiopia=list(ir='Data/ET2024DHS__ETIR8ADT__IR_raw.rds',
  episodes='Data/Derived/ethiopia_2024_specified_modern_method_episodes.rds',
  calendar='Data/Derived/ethiopia_2024_calendar_events.rds'),
 Nigeria=list(ir='Data/raw_dhs_ir/NG2024DHS__NGIR8BDT__IR_raw.rds',
  episodes='Data/Derived/nigeria_2024_modern_episodes.rds',
  calendar='Data/Derived/nigeria_2024_calendar_events.rds'),
 DRC=list(ir='Data/CDIR81FL.dta',episodes='Data/Derived/drc_2023_24_modern_episodes.rds',
  calendar='Data/Derived/drc_2023_24_calendar_events.rds'))
ir_file <- Sys.getenv('DHS_IR_FILE',unset=Sys.getenv(paste0(toupper(country),'_IR_FILE'),unset=input(config$ir)))
ir <- if (tolower(tools::file_ext(ir_file))=='rds') readRDS(ir_file) else as.data.frame(haven::read_dta(ir_file))
e <- readRDS(input(config$episodes)); cal <- readRDS(input(config$calendar))
e <- e[e$method_code!=16L,] # EC is not a continuing-method risk denominator.
stopifnot(all(e$entry<e$exposure),all(e$wt>0),!anyNA(e$reason_code))
modern <- sort(unique(e$method_code))
method_name <- function(z) ifelse(z==3,'Injectables',ifelse(z==11,'Implants',
 ifelse(z==1,'Pill',ifelse(z==2,'IUD',ifelse(z==16,'EC','Other modern')))))
method_levels <- c('Injectables','Implants','Pill','IUD','Other modern')
cause_codes <- list('Method failure'=1L,'Wanted more effective method'=7L,
 'Changes in menstrual bleeding'=15L,'Other side effects/health'=c(4L,5L),
 'Access/cost/convenience'=c(6L,8L,10L))
actionable <- unlist(cause_codes,use.names=FALSE)
all_reason_codes <- c(cause_codes,list('Wanted pregnancy'=2L,'Partner disapproval'=3L,
 'Other fertility-related'=c(9L,12L,13L),
 'Other recorded'=c(0L,11L,96L,98L,99L)))
native_map <- c('1'=1L,'2'=2L,'3'=3L,'4'=4L,'5'=5L,'6'=6L,'7'=7L,'8'=8L,'9'=9L,
 'C'=10L,'F'=11L,'A'=12L,'D'=13L,'M'=15L,'W'=96L,'K'=98L,'?'=99L,' '=0L)
event_flag <- function(x,scope) switch(scope,all=rep(TRUE,nrow(x)),
 selected=!(x$reason_code %in% c(2L,3L)),actionable=x$reason_code %in% actionable)
e$method_group <- factor(method_name(e$method_code),levels=method_levels)
wi <- e$woman_row
e$stratum <- as.integer(ir$v022[wi]); e$cluster <- paste(e$stratum,as.integer(ir$v021[wi]),sep=':')
if(country=='Ethiopia') {
 region_labels <- c('1'='Tigray','2'='Afar','3'='Amhara','4'='Oromia','5'='Somali',
  '6'='Benishangul-Gumuz','7'='Central Ethiopia','8'='Sidama','9'='South West Ethiopia',
  '10'='South Ethiopia','12'='Gambella','13'='Harari','14'='Addis Ababa','15'='Dire Dawa')
 e$region <- factor(unname(region_labels[as.character(as.integer(ir$v024[wi]))]))
} else e$region <- factor(if(country=='DRC') as.character(e$province) else as.character(e$zone_name))
e$age_start <- floor((e$start-as.numeric(ir$v011[wi]))/12)
births <- as.matrix(ir[wi,grep('^b3_',names(ir),value=TRUE)])
e$parity_start <- rowSums(!is.na(births)&births<=e$start)
e$age <- cut(e$age_start,c(14,19,24,34,49),labels=c('15-19','20-24','25-34','35-49'))
e$parity <- factor(ifelse(e$parity_start==0,'0',ifelse(e$parity_start<=2,'1-2',
 ifelse(e$parity_start<=4,'3-4','5+'))),levels=c('0','1-2','3-4','5+'))
e$parity_legacy <- factor(ifelse(e$parity_start==0,'0',ifelse(e$parity_start<=2,'1-2',
 ifelse(e$parity_start==3,'3','4+'))),levels=c('0','1-2','3','4+'))
m <- as.integer(ir$v501[wi]); ed <- as.integer(ir$v106[wi]); w <- as.integer(ir$v190[wi]); res <- as.integer(ir$v025[wi])
e$marital <- factor(ifelse(m==0,'Never in union',ifelse(m==1,'Married',ifelse(m==2,
 'Living together',ifelse(m%in%3:5,'Formerly in union',NA)))),
 levels=c('Never in union','Living together','Married','Formerly in union'))
e$marital_legacy <- factor(ifelse(m==0,'Never in union',ifelse(m%in%c(1,2),
 'Married/living together',ifelse(m%in%3:5,'Formerly in union',NA))))
e$education <- factor(ifelse(ed==0,'None',ifelse(ed==1,'Primary',ifelse(ed%in%c(2,3),'Secondary+',NA))))
e$wealth <- factor(c('Poorest','Poorer','Middle','Richer','Richest')[w],
 levels=c('Poorest','Poorer','Middle','Richer','Richest'))
e$wealth_three <- factor(ifelse(w<=2,'Poorest 40%',ifelse(w==3,'Middle 20%','Richest 40%')),
 levels=c('Poorest 40%','Middle 20%','Richest 40%'))
e$residence <- factor(ifelse(res==1,'Urban',ifelse(res==2,'Rural',NA)),levels=c('Urban','Rural'))
e$start_year <- factor((e$start-1L)%/%12L+1900L)
e$duration_class <- ifelse(e$method_code%in%c(1L,3L,5L),'Short-acting reversible',
 ifelse(e$method_code%in%c(2L,11L),'Long-acting reversible','Other modern, mixed'))
covars <- c('age','parity','marital','education','wealth','residence','region','method_group','start_year','stratum','cluster')
complete <- complete.cases(e[,covars])
d <- droplevels(e[complete,])
emit(data.frame(country=country,full_modern_episodes=nrow(e),complete_age15_49_episodes=nrow(d),
 age_below15=sum(e$age_start<15,na.rm=TRUE),age_missing=sum(is.na(e$age_start)),
 other_missing=sum(!complete & !is.na(e$age)),late_entry_full=sum(e$entry>0),
 late_entry_complete=sum(d$entry>0),non_ec_modern_codes=paste(modern,collapse=',')), 'cohort_audit')
saveRDS(d,file.path(out,'reference_episode_covariates.rds'))

# Multiple-decrement life table: all endings reduce survival, whatever the
# selected cause. Do not delete competing endings from starting risk sets.
cif <- function(x,weights=x$wt,horizons=c(3L,6L,9L,12L),codes=all_reason_codes) {
 s<-1; val<-setNames(numeric(length(codes)),names(codes)); ans<-matrix(NA_real_,length(horizons),length(codes),dimnames=list(horizons,names(codes)))
 for(t in 1:max(horizons)) {
  at<-x$entry<t & x$exposure>=t;den<-sum(weights[at]);ended<-at & x$discontinued & x$exposure==t
  if(den<=0) {if(s>1e-12)break} else {
   for(j in seq_along(codes))val[j]<-val[j]+s*sum(weights[ended & x$reason_code%in%codes[[j]]])/den
   s<-s*(1-sum(weights[ended])/den)
  }
  if(t%in%horizons)ans[as.character(t),]<-100*val
 }
 ans
}
design <- function(x) {
 frame<-unique(x[,c('cluster','stratum')]);frame$id<-seq_len(nrow(frame))
 list(frame=frame,groups=split(frame$id,frame$stratum),id=match(x$cluster,frame$cluster))
}
resample_psu <- function(des,b) {
 set.seed(20261031L+b); mult<-numeric(nrow(des$frame))
 for(ids in des$groups) {
  n<-length(ids);mult[ids]<-if(n==1L)1 else n/(n-1)*tabulate(sample.int(n,n-1,replace=TRUE),nbins=n)
 }
 mult
}
design_d<-design(d)
emit(data.frame(stratum=names(design_d$groups),psus=lengths(design_d$groups),
 singleton_treated_as_certainty=lengths(design_d$groups)==1L),'design_support')
ci <- function(z,nreps) if(nreps>=100 && sum(is.finite(z))>=max(80,.8*nreps))
 unname(quantile(z,c(.025,.975),na.rm=TRUE)) else c(NA_real_,NA_real_)

if('descriptive'%in%tasks) {
 scopes<-list('Overall::All modern'=seq_len(nrow(d)))
 for(v in c('age','parity','parity_legacy','marital','marital_legacy','education','wealth','wealth_three','residence','method_group','region','duration_class'))
  for(level in unique(as.character(d[[v]])))scopes[[paste(v,level,sep='::')]]<-which(d[[v]]==level)
 for(pair in list(c('age','parity'),c('age','method_group'),c('parity','method_group')))
  for(a in levels(d[[pair[1]]]))for(b in levels(d[[pair[2]]]))
   scopes[[paste('combination',pair[1],a,pair[2],b,sep='::')]]<-which(d[[pair[1]]]==a&d[[pair[2]]]==b)
 for(m in method_levels)for(v in c('age','parity','marital','education','wealth','residence','region'))
  for(level in levels(d[[v]]))scopes[[paste('method_subgroup',m,v,level,sep='::')]]<-which(d$method_group==m & d[[v]]==level)
 scopes<-scopes[lengths(scopes)>0]
 rows<-list();top<-list()
 for(key in names(scopes)) {
  x<-d[scopes[[key]],];z<-cif(x); events<-x$discontinued & x$entry<x$exposure & x$exposure<=12
  for(h in rownames(z)) {
   all<-sum(z[h,]);sel<-sum(z[h,!colnames(z)%in%c('Wanted pregnancy','Partner disapproval')]);act<-sum(z[h,names(cause_codes)])
   rows[[length(rows)+1L]]<-data.frame(scope=key,month=as.integer(h),episodes=nrow(x),weighted_episodes=sum(x$wt),
    selected_endings=sum(events & event_flag(x,'selected')),actionable_endings=sum(events & event_flag(x,'actionable')),
    all_reason_pct=all,selected_pct=sel,actionable_pct=act)
  }
  risks<-z['12',names(cause_codes)]; denom<-sum(risks)
  for(j in seq_along(risks))top[[length(top)+1L]]<-data.frame(scope=key,cause=names(risks)[j],
   cause_cif_pct=risks[j],share_of_actionable_cif_pct=if(is.finite(denom)&&denom>0)100*risks[j]/denom else NA_real_,
   rank=if(all(is.finite(risks)))rank(-risks,ties.method='first')[j] else NA_integer_,
   actionable_endings=sum(events & event_flag(x,'actionable')),withhold=sum(events & event_flag(x,'actionable'))<10,
   sparse=sum(events & event_flag(x,'actionable'))<30)
 }
 estimates<-do.call(rbind,rows);reason_table<-do.call(rbind,top)
 estimates$ci_low<-estimates$ci_high<-NA_real_;estimates$ci_outcome<-'selected';estimates$bootstrap_valid<-0L
 aggregate_keys<-names(scopes)[!grepl('^(combination|method_subgroup)::',names(scopes))]
 boots<-array(NA_real_,c(B,length(aggregate_keys),4),dimnames=list(NULL,aggregate_keys,c(3,6,9,12)))
 for(b in seq_len(B)) {
  weights<-d$wt*resample_psu(design_d,b)[design_d$id]
  for(key in aggregate_keys) {
   ix<-scopes[[key]];z<-cif(d[ix,],weights[ix]);boots[b,key,]<-rowSums(z[,!colnames(z)%in%c('Wanted pregnancy','Partner disapproval'),drop=FALSE])
  }
 }
 for(key in aggregate_keys)for(h in c(3,6,9,12)) {
  ix<-which(estimates$scope==key&estimates$month==h);z<-boots[,key,as.character(h)];bounds<-ci(z,B)
  estimates$ci_low[ix]<-bounds[1];estimates$ci_high[ix]<-bounds[2];estimates$bootstrap_valid[ix]<-sum(is.finite(z))
 }
 estimates$combination_display<-!grepl('^combination::',estimates$scope)|(estimates$episodes>=100 & estimates$selected_endings>=20)
 emit(estimates,'selected_subgroups_and_timepoints');emit(reason_table,'actionable_cause_risks_and_shares')
 emit(reason_table[reason_table$rank<=3 & !is.na(reason_table$rank),],'top_three_by_method_subgroup')
 # Full eligible modern episodes (including starts before age 15) for DHS-scope curves.
 fullscopes<-c(list(National=seq_len(nrow(e))),split(seq_len(nrow(e)),e$method_group),split(seq_len(nrow(e)),e$region))
 full<-do.call(rbind,lapply(names(fullscopes),function(key) {
  z<-cif(e[fullscopes[[key]],]);data.frame(scope=key,month=as.integer(rownames(z)),
   all_reason_pct=rowSums(z),selected_pct=rowSums(z[,!colnames(z)%in%c('Wanted pregnancy','Partner disapproval'),drop=FALSE]),
   actionable_pct=rowSums(z[,names(cause_codes),drop=FALSE]))
 }))
 emit(full,'full_modern_timepoints')
 # Five-year reason distribution: inspect v018 ... v018+59 directly, as the
 # reference table does. Do not substitute calendar run ends or the first year.
 rec<-list();k<-0L;chars<-strsplit('123456789WNALCFEMS~','')[[1]]
 for(i in seq_len(nrow(ir))) {
  pos<-as.integer(ir$v018[i])+0:59
  rc<-substring(sprintf('%-80s',ir$vcal_2[i]),pos,pos);mc<-substring(ir$vcal_1[i],pos,pos)
  methods<-match(mc,chars);reason<-unname(native_map[rc]);take<-rc!=' '&methods%in%modern&!is.na(reason)&reason>0
  if(any(take)){k<-k+1L;rec[[k]]<-data.frame(method=method_name(methods[take]),reason_code=reason[take],wt=as.numeric(ir$v005[i])/1e6)}
 }
 recorded<-do.call(rbind,rec);rr<-aggregate(wt~method+reason_code,recorded,sum)
 rr$share_pct<-100*rr$wt/ave(rr$wt,rr$method,FUN=sum);emit(rr,'five_year_recorded_reason_distribution')
 # Calendar observed starts are a separate denominator, retaining non-modern starts.
 starts<-cal[cal$method_code%in%1:18 & cal$start>cal$calendar_start &
  cal$interview-cal$start>=3 & cal$interview-cal$start<=62,]
 starts$method<-ifelse(starts$method_code%in%c(8,9),'Non-modern methods',method_name(starts$method_code))
 starts$region<-as.character(haven::as_factor(ir$v024[starts$woman_row]))
 mix<-aggregate(wt~region+method,starts,sum);mix$share_all_starts_pct<-100*mix$wt/ave(mix$wt,mix$region,FUN=sum)
 emit(mix,'initiation_mix_by_region')
}

person_months <- function(x,scope) {
 n<-pmax(0L,pmin(12L,x$exposure)-x$entry);idx<-rep(seq_len(nrow(x)),n)
 month<-unlist(Map(function(a,n)seq.int(a+1L,length.out=n),x$entry,n),use.names=FALSE)
 p<-x[idx,];p$episode_index<-idx;p$month<-factor(month,levels=1:12)
 ended<-x$discontinued[idx]&month==x$exposure[idx]
 p$outcome<-factor(ifelse(!ended,'continue',ifelse(event_flag(x,scope)[idx],'target','competing')),
  levels=if(scope=='all')c('continue','target') else c('continue','target','competing'))
 p
}
fit_model <- function(formula,p,w=p$wt) {
 p$fit_weight<-w
 fit<-nnet::multinom(formula,data=p,weights=fit_weight,trace=FALSE,maxit=500,MaxNWts=30000,Hess=FALSE)
 if(fit$convergence!=0L)stop('Model did not converge')
 fit
}
risk_individual <- function(fit,x,horizon=12L) {
 s<-rep(1,nrow(x));v<-numeric(nrow(x))
 for(t in 1:horizon) {
  x$month<-factor(t,levels=1:12);p<-predict(fit,newdata=x,type='probs')
  if(is.null(dim(p))) {
   if(length(fit$lev)==2L)p<-cbind(continue=1-p,target=p) else
    p<-matrix(p,nrow=1,dimnames=list(NULL,fit$lev))
  }
  v<-v+s*p[,'target'];s<-s*p[,'continue']
 }
 100*v
}

if('risk_strata'%in%tasks) {
 # Match Ethiopia 56: method + age + legacy parity, held-out PSUs, ALL eligible
 # complete-case episodes, rather than full-model in-sample observed starters.
 des<-design_d;set.seed(20261005L);fold<-integer(nrow(des$frame))
 for(ids in des$groups)fold[ids]<-sample(rep(1:5,length.out=length(ids)))
 x<-d;x$fold<-fold[des$id];p<-person_months(x,'selected');scores<-rep(NA_real_,nrow(x))
 f<-outcome~month+method_group+age+parity_legacy
 for(k in 1:5) {
  fit<-fit_model(f,p[p$fold!=k,]);ix<-which(x$fold==k);scores[ix]<-risk_individual(fit,x[ix,])
 }
 wq<-function(q){o<-order(scores);scores[o][which(cumsum(x$wt[o])/sum(x$wt)>=q)[1L]]}
 cuts<-c(wq(1/3),wq(2/3));stopifnot(all(is.finite(scores)),cuts[1]<cuts[2])
 x$risk_band<-factor(ifelse(scores<=cuts[1],'Lower',ifelse(scores<=cuts[2],'Middle','Higher')),levels=c('Lower','Middle','Higher'))
 bands<-do.call(rbind,lapply(levels(x$risk_band),function(k){z<-x[x$risk_band==k,];v<-cif(z,horizons=12)
  data.frame(band=k,episodes=nrow(z),mean_oof_predicted_pct=weighted.mean(scores[x$risk_band==k],z$wt),
   observed_selected_pct=sum(v[,!colnames(v)%in%c('Wanted pregnancy','Partner disapproval')]),lower_cut=cuts[1],upper_cut=cuts[2])}))
 boot<-matrix(NA_real_,B,3)
 for(b in seq_len(B)){ww<-x$wt*resample_psu(des,b)[des$id];for(j in 1:3){ix<-which(x$risk_band==levels(x$risk_band)[j]);v<-cif(x[ix,],ww[ix],12);boot[b,j]<-sum(v[,!colnames(v)%in%c('Wanted pregnancy','Partner disapproval')])}}
 bands$ci_low<-vapply(1:3,function(j)ci(boot[,j],B)[1],0.0);bands$ci_high<-vapply(1:3,function(j)ci(boot[,j],B)[2],0.0)
 bands$uncertainty<-'PSU bootstrap with held-out scores fixed; excludes training uncertainty'
 emit(bands,'crossvalidated_risk_bands')
 prof<-list()
 for(v in c('method_group','age','parity_legacy','marital','education','wealth','residence','region'))for(k in levels(x$risk_band))for(level in levels(x[[v]])) {
  z<-x[x$risk_band==k,];prof[[length(prof)+1L]]<-data.frame(band=k,covariate=v,category=level,
   episodes=sum(z[[v]]==level),share_pct=100*sum(z$wt[z[[v]]==level])/sum(z$wt))
 }
 emit(do.call(rbind,prof),'crossvalidated_risk_band_profiles')
}

# Model families retain the precise distinction between all/selected/actionable
# endings. Five wealth levels and the earlier three-level variant are separate.
specs<-list(
 all_full=list(scope='all',method=NULL,rhs='month+method_group+region+age+parity+marital+education+wealth+residence+start_year'),
 selected_legacy=list(scope='selected',method=NULL,rhs='month+method_group+region+age+parity_legacy+marital_legacy+education+wealth_three+residence+start_year'),
 selected_three_wealth=list(scope='selected',method=NULL,rhs='month+method_group+region+age+parity+marital+education+wealth_three+residence+start_year'),
 selected_full=list(scope='selected',method=NULL,rhs='month+method_group+region+age+parity+marital+education+wealth+residence+start_year'),
 selected_injectables=list(scope='selected',method='Injectables',rhs='month+region+age+parity+marital+education+wealth_three+residence+start_year'),
 selected_pill=list(scope='selected',method='Pill',rhs='month+region+age+parity+marital+education+wealth_three+residence+start_year'),
 actionable_method_mix=list(scope='actionable',method=NULL,rhs='month+method_group+region'),
 actionable_full=list(scope='actionable',method=NULL,rhs='month+method_group+region+age+parity+marital+education+wealth+residence+start_year'),
 actionable_injectables_duration=list(scope='actionable',method='Injectables',rhs='month+region'),
 actionable_implants_duration=list(scope='actionable',method='Implants',rhs='month+region'),
 actionable_injectables=list(scope='actionable',method='Injectables',rhs='month+region+age+parity+marital+education+wealth+residence+start_year'),
 actionable_implants=list(scope='actionable',method='Implants',rhs='month+region+age+parity+marital+education+wealth+residence+start_year'),
 actionable_interaction=list(scope='actionable',method=NULL,rhs='month+method_group*region+age+parity+marital+education+wealth+residence+start_year'))

if('models'%in%tasks) {
 requested<-strsplit(Sys.getenv('REFERENCE_MODEL_SPECS',paste(names(specs),collapse=',')),',',fixed=TRUE)[[1]]
 if(any(!requested%in%names(specs)))stop('Unknown reference model ID')
 status<-list()
 for(id in requested) {
  sp<-specs[[id]];x<-if(is.null(sp$method))d else droplevels(d[d$method_group==sp$method,])
  p<-person_months(x,sp$scope);f<-as.formula(paste('outcome~',sp$rhs))
  # Explicitly remove a constant covariate only when the country/method has no
  # variation. Record it as a non-estimable contrast, never an inferred effect.
  vars<-setdiff(all.vars(f),c('outcome','month'));constant<-vars[vapply(vars,function(v)length(unique(p[[v]]))<2,TRUE)]
  if(length(constant))for(v in constant)f<-update(f,paste('.~.-',v))
  fit<-tryCatch(fit_model(f,p),error=function(err)err)
  if(inherits(fit,'error')){status[[id]]<-data.frame(model=id,status='not_estimable',detail=conditionMessage(fit));next}
  ref<-x[x$entry==0,];regions<-levels(x$region);des<-design(x)
  beta<-coef(fit);if(is.null(dim(beta)))beta<-matrix(beta,nrow=1,dimnames=list('target',names(beta)))
  coeff<-data.frame(outcome=rep(rownames(beta),each=ncol(beta)),term=rep(colnames(beta),times=nrow(beta)),
   log_odds=as.vector(t(beta)),odds_ratio=exp(as.vector(t(beta))))
  coeff$ci_low<-coeff$ci_high<-coeff$p_value<-NA_real_
  predict_region<-function(model,weights=ref$wt,own=FALSE){
   vapply(c('National',regions),function(r){
    take<-if(own && r!='National')which(ref$region==r) else seq_len(nrow(ref));z<-ref[take,]
    if(!nrow(z)||sum(weights[take])<=0)return(NA_real_)
    if(r!='National')z$region<-factor(r,levels=regions)
    weighted.mean(risk_individual(model,z),weights[take])
   },0.0)
  }
  point<-predict_region(fit);own<-predict_region(fit,own=TRUE)
  bounds<-matrix(NA_real_,MB,length(point));betaboot<-matrix(NA_real_,MB,nrow(coeff))
  pairs<-combn(regions,2,simplify=FALSE)
  # Model-1 symmetric pair mix: five method categories, observed-start shares.
  mixcalc<-function(model,weights=ref$wt){
   methods<-levels(x$method_group);share<-risk<-matrix(0,length(regions),length(methods),dimnames=list(regions,methods))
   for(r in regions)for(m in methods){
    share[r,m]<-sum(weights[ref$region==r & ref$method_group==m]);z<-ref[1,,drop=FALSE]
    z$region<-factor(r,levels=regions);z$method_group<-factor(m,levels=methods)
    risk[r,m]<-risk_individual(model,z)
   }
   share<-share/rowSums(share)
   ans<-do.call(rbind,lapply(pairs,function(ab){a<-ab[1];b<-ab[2];common<-(share[a,]+share[b,])/2
    ga<-sum(common*risk[a,]);gb<-sum(common*risk[b,]);own_gap<-sum(share[a,]*risk[a,])-sum(share[b,]*risk[b,])
    data.frame(region_a=a,region_b=b,shared_a_pct=ga,shared_b_pct=gb,shared_gap_pp=ga-gb,
     own_modeled_gap_pp=own_gap,mix_component_pp=own_gap-(ga-gb))}))
   list(table=ans,share=share,risk=risk)
  }
  mixpoint<-if(id=='actionable_method_mix')mixcalc(fit) else NULL
  mixboot<-matrix(NA_real_,MB,length(pairs))
  for(b in seq_len(MB)) {
   mult<-resample_psu(des,b);ww<-x$wt*mult[des$id];pw<-ww[p$episode_index];rw<-ww[x$entry==0]
   fm<-tryCatch(fit_model(f,p,pw),error=function(err)NULL)
   if(is.null(fm))next
   bounds[b,]<-tryCatch(predict_region(fm,rw),error=function(err)rep(NA_real_,length(point)))
   bb<-coef(fm);if(is.null(dim(bb)))bb<-matrix(bb,nrow=1,dimnames=list('target',names(bb)))
   if(identical(dimnames(bb),dimnames(beta)))betaboot[b,]<-as.vector(t(bb))
   if(!is.null(mixpoint))mixboot[b,]<-tryCatch(mixcalc(fm,rw)$table$shared_gap_pp,error=function(err)rep(NA_real_,length(pairs)))
  }
  margins<-data.frame(region=names(point),common_profile_pct=as.numeric(point),own_profile_pct=as.numeric(own),
   ci_low=apply(bounds,2,function(z)ci(z,MB)[1]),ci_high=apply(bounds,2,function(z)ci(z,MB)[2]),
   valid_bootstrap=colSums(is.finite(bounds)),bootstrap_reps=MB)
  margins$episodes<-vapply(margins$region,function(r)sum(r=='National'|as.character(x$region)==r),0L)
  margins$target_events<-vapply(margins$region,function(r)sum((r=='National'|as.character(x$region)==r)&x$discontinued&x$exposure<=12&event_flag(x,sp$scope)),0L)
  margins$sparse<-margins$target_events<30
  emit(margins,paste0(id,'_regional_probabilities'))
  contrasts<-do.call(rbind,lapply(seq_along(pairs),function(k){a<-pairs[[k]][1];b<-pairs[[k]][2]
   dif<-point[a]-point[b];z<-bounds[,match(a,names(point))]-bounds[,match(b,names(point))];qq<-ci(z,MB)
   data.frame(region_a=a,region_b=b,difference_pp=unname(dif),ci_low=qq[1],ci_high=qq[2],
    p_value=if(all(is.finite(qq)))2*pnorm(-abs(dif/sd(z,na.rm=TRUE))) else NA_real_,
    sparse=any(margins$sparse[margins$region%in%c(a,b)]))}))
  contrasts$holm_p<-p.adjust(contrasts$p_value,method='holm');contrasts$significant_05<-contrasts$holm_p<.05
  contrasts$significant_10<-contrasts$holm_p<.10;emit(contrasts,paste0(id,'_pairwise'))
  for(j in seq_len(nrow(coeff))){qq<-ci(betaboot[,j],MB);coeff$ci_low[j]<-exp(qq[1]);coeff$ci_high[j]<-exp(qq[2]);
   if(all(is.finite(qq)))coeff$p_value[j]<-2*pnorm(-abs(coeff$log_odds[j]/sd(betaboot[,j],na.rm=TRUE)))}
  coeff$precision_flag<-!is.finite(coeff$odds_ratio)|abs(coeff$log_odds)>10
  emit(coeff,paste0(id,'_coefficients'))
  # Covariate probabilities are point estimates; uncertainty is explicitly
  # restricted to region and coefficients in this extension.
  profile<-list()
  for(v in setdiff(all.vars(f),c('outcome','month','start_year','region')))for(lev in levels(ref[[v]])) {
   z<-ref;z[[v]]<-factor(lev,levels=levels(ref[[v]]));profile[[length(profile)+1L]]<-data.frame(covariate=v,category=lev,
    adjusted_pct=weighted.mean(risk_individual(fit,z),ref$wt),episodes=sum(x[[v]]==lev),
    target_events=sum(x[[v]]==lev & x$discontinued & x$exposure<=12 & event_flag(x,sp$scope)))
  }
  if(length(profile))emit(do.call(rbind,profile),paste0(id,'_subgroup_probabilities'))
  if(!is.null(mixpoint)) {
   mt<-mixpoint$table;mt$ci_low<-apply(mixboot,2,function(z)ci(z,MB)[1]);mt$ci_high<-apply(mixboot,2,function(z)ci(z,MB)[2])
   mt$p_value<-vapply(seq_len(nrow(mt)),function(j)if(is.finite(mt$ci_low[j]))2*pnorm(-abs(mt$shared_gap_pp[j]/sd(mixboot[,j],na.rm=TRUE))) else NA_real_,0.0)
   mt$holm_p<-p.adjust(mt$p_value,method='holm');emit(mt,'pair_specific_shared_method_mix')
   emit(data.frame(region=rep(rownames(mixpoint$share),each=ncol(mixpoint$share)),method=rep(colnames(mixpoint$share),nrow(mixpoint$share)),
    observed_start_share=as.vector(t(mixpoint$share)),method_specific_predicted_pct=as.vector(t(mixpoint$risk))),'shared_mix_cells')
  }
  status[[id]]<-data.frame(model=id,status='estimated',detail=paste('Formula:',paste(deparse(f),collapse=' '),
   '; constant terms omitted:',paste(constant,collapse=','),'; bootstrap replicates:',MB))
  saveRDS(fit,file.path(out,paste0(id,'_fit.rds')))
 }
 emit(do.call(rbind,status),'model_execution_status')
}

if('pathways'%in%tasks) {
 # Common 12-month observable cohort; the same endings appear at months 1/3/12.
 ends<-e[e$discontinued & e$exposure<=12 & e$end+12<=e$interview-3,]
 state<-function(code,original)ifelse(code==original,'Same original method',ifelse(code%in%modern,
  'Other continuing modern method',ifelse(code==16,'EC',ifelse(code%in%c(8,9),
  'Traditional method',ifelse(code%in%c(81,82,83),'Pregnancy/birth/termination','No method')))))
 codes_at<-function(w,cmc) {
  pos<-as.integer(ir$v018[w])+as.integer(ir$v008[w])-cmc
  cc<-substring(ir$vcal_1[w],pos,pos);mc<-match(cc,strsplit('123456789WNALCFEMS~','')[[1]])
  mc[cc=='0']<-0;mc[cc=='B']<-81;mc[cc=='T']<-82;mc[cc=='P']<-83;mc
 }
 for(t in c(1,3,12))ends[[paste0('month',t)]]<-state(codes_at(ends$woman_row,ends$end+t),ends$method_code)
 flows<-list();dist<-list()
 for(scope in c('all','selected','actionable')) {
  z<-ends[event_flag(ends,scope),];z$method<-as.character(z$method_group)
  for(m in c('All modern',method_levels)) {
   a<-if(m=='All modern')z else z[z$method==m,];if(!nrow(a))next
   f<-aggregate(wt~month1+month3+month12,a,sum);f$scope<-scope;f$method<-m;f$share_pct<-100*f$wt/sum(a$wt)
   flows[[length(flows)+1L]]<-f
   for(t in c(1,3,12)){r<-aggregate(a$wt,list(state=a[[paste0('month',t)]]),sum);names(r)[2]<-'weight'
    r$scope<-scope;r$method<-m;r$month<-t;r$share_pct<-100*r$weight/sum(a$wt);dist[[length(dist)+1L]]<-r}
  }
 }
 emit(do.call(rbind,flows),'post_ending_alluvial_flows');emit(do.call(rbind,dist),'post_ending_states')
 # Historical 15-month landmark, two duration bands, selected ending by reason:
 # the early Ethiopia planning analysis. A different multi-landmark, finer-band
 # analysis is preserved in the original duration-aware modules.
 landmarks<-list();chars<-strsplit('123456789WNALCFEMS~','')[[1]]
 for(i in seq_len(nrow(ir))) {
  p<-as.integer(ir$v018[i])+15L;if(p>80)next
  orig<-substring(ir$vcal_1[i],p,p);mc<-match(orig,chars);if(!mc%in%modern)next
  dur<-1L;while(p+dur<=80 && substring(ir$vcal_1[i],p+dur,p+dur)==orig)dur<-dur+1L
  after<-substring(ir$vcal_1[i],p-1:12,p-1:12);change<-which(after!=orig)
  event<-if(length(change))min(change) else NA_integer_
  # Nonblank reason at a same-method month is also a recorded ending.
  reasonchars<-substring(sprintf('%-80s',ir$vcal_2[i]),p-0:11,p-0:11)
  recorded<-which(reasonchars!=' ')
  if(length(recorded))event<-min(c(event,recorded),na.rm=TRUE)
  reason<-if(is.na(event))NA_integer_ else unname(native_map[reasonchars[event]])
  if(!is.na(event)&&is.na(reason))reason<-99L
  landmarks[[length(landmarks)+1L]]<-data.frame(woman_row=i,method=method_name(mc),duration=dur,
   duration_band=ifelse(dur<=12,'0-12','13+'),wt=as.numeric(ir$v005[i])/1e6,
   reason_code=reason,month12_modern=match(after[12],chars)%in%c(modern,16L))
 }
 land<-do.call(rbind,landmarks);current<-data.frame(method=method_name(as.integer(ir$v312)),
  duration=as.numeric(ir$v337),wt=as.numeric(ir$v005)/1e6,modern=as.integer(ir$v313)==3 & as.integer(ir$v312)%in%modern)
 current<-current[current$modern & is.finite(current$duration)&current$duration<997,]
 current$duration_band<-ifelse(current$duration<=12,'0-12','13+')
 probs<-list()
 for(m in method_levels)for(band in c('0-12','13+')) {
  z<-land[land$method==m & land$duration_band==band,];cur<-current[current$method==m,]
  share<-if(nrow(cur))sum(cur$wt[cur$duration_band==band])/sum(cur$wt) else NA_real_
  for(reason in names(all_reason_codes))probs[[length(probs)+1L]]<-data.frame(method=m,duration_band=band,reason=reason,
   historical_women=nrow(z),current_duration_share=share,
   ending_probability=if(nrow(z))sum(z$wt[!is.na(z$reason_code)&z$reason_code%in%all_reason_codes[[reason]]])/sum(z$wt) else NA_real_)
 }
 probs<-do.call(rbind,probs);probs$standardized_contribution<-probs$current_duration_share*probs$ending_probability
 emit(probs,'fixed_landmark_selected_reason_planning')
 agg<-aggregate(standardized_contribution~method+reason,probs,sum,na.action=na.pass)
 emit(agg,'fixed_landmark_method_reason_probabilities')
}
emit(data.frame(country=country,tasks=paste(tasks,collapse=','),descriptive_reps=B,model_reps=MB,
 inference_available=B>=100,model_inference_available=MB>=100,
 outputs_update_final_reports=FALSE), 'execution_settings')
cat('Reference-aligned tasks completed for ',country,'.\n',sep='')
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 201_verify_planning_html.py
# LANGUAGE: Python
MODULES[["201_verify_planning_html.py"]] <- list(
  language="Python",
  original_sha256="dd7600bad84be2898f4324c71c67f6ceffa9b8d9335c6f6315ccd83e0bc50853",
  packaged_sha256="dd7600bad84be2898f4324c71c67f6ceffa9b8d9335c6f6315ccd83e0bc50853",
  args=character(),
  code=r"-----(#!/usr/bin/env python3
"""Rebuild duration-planning tables from freshly computed aggregate results.

This verifies only the named planning sections, not the complete report.
All locations are parameters. The saved HTML is read-only.
"""
import argparse,csv,json,re
from pathlib import Path
from html import escape
from lxml import html

def norm(x):return re.sub(r'\s+',' ',str(x)).strip()
def rows(t):return [[norm(c.text_content()) for c in r.xpath('./th|./td')] for r in t.xpath('./thead/tr|./tbody/tr|./tr')]
def matrix(x):return [[norm(' '.join(str(v) for v in c) if isinstance(c,list) else c) for c in r] for r in x]
def numbers(cell):return re.findall(r'[-+]?\d[\d,]*(?:\.\d+)?',cell.replace('−','-'))
def render(table):return '<table>'+''.join('<tr>'+''.join(f'<{"th" if i==0 else "td"}>{escape(v)}</{"th" if i==0 else "td"}>' for v in r)+'</tr>' for i,r in enumerate(table))+'</table>'

def main():
 ap=argparse.ArgumentParser();ap.add_argument('--country',required=True);ap.add_argument('--fresh-root',type=Path,required=True);ap.add_argument('--report-html',type=Path,required=True);ap.add_argument('--output-dir',type=Path,required=True);a=ap.parse_args()
 out=a.output_dir;out.mkdir(parents=True,exist_ok=True);doc=html.fromstring(a.report_html.read_text());sup=a.fresh_root/'output/Supporting_data'
 ids=['historical-duration-aware-planning','aft-duration-aware-planning'];blocks=[]
 if a.country=='Ethiopia':
  data=json.loads((sup/'final_duration_planning_tables.json').read_text())
  for key in ['Historical duration-aware','AFT survival + pathways']:
   blocks.append([matrix(t) for k,t in sorted(data[key]['tables'].items(),key=lambda z:int(z[0]))])
 elif a.country=='Nigeria':
  data=json.loads((a.fresh_root/'output/nigeria_duration_planning_tables.json').read_text());blocks=[[matrix(s['table']) for s in b['slides']] for b in data['blocks']]
 else:
  import pandas as pd
  for approach in ['Historical duration-aware','AFT plus observed pathways']:
   tables=[]
   for stem in ['by_method','by_method_cause','scenarios']:
    df=pd.read_csv(sup/f'drc_2026_planning_{stem}.csv');df=df[df.approach==approach].copy()
    for c in df:
     if pd.api.types.is_float_dtype(df[c]):df[c]=df[c].map(lambda v:'—' if pd.isna(v) else f'{v:,.1f}')
     elif pd.api.types.is_integer_dtype(df[c]):df[c]=df[c].map(lambda v:f'{v:,}')
    tables.append(rows(html.fromstring(df.to_html(index=False))))
   blocks.append(tables)
 audit=[];page=['<!doctype html><html lang="en"><meta charset="utf-8"><title>Rebuilt planning tables</title><style>body{font:16px Arial;margin:36px;color:#153f5b}table{border-collapse:collapse;width:100%;margin:20px 0 40px}th{background:#153f5b;color:white}th,td{padding:10px;border-bottom:1px solid #ddd;text-align:right}th:first-child,td:first-child{text-align:left}tr:nth-child(even){background:#edf5f5}</style>',f'<h1>{escape(a.country)}: rebuilt duration-planning tables</h1><p>Generated from recalculated aggregate outputs. This is a reconciliation preview, not a replacement for the full report.</p>']
 for sid,block in zip(ids,blocks):
  target=doc.xpath('//*[@id=$id]',id=sid)[0];actual=target.xpath('.//table');page.append(f'<h2>{escape(sid.replace("-"," "))}</h2>')
  if len(block)!=len(actual):raise ValueError(f'Table count mismatch for {sid}')
  for i,(expected,table) in enumerate(zip(block,actual),1):
   actualrows=rows(table);shape=len(actualrows)==len(expected) and all(len(x)==len(y) for x,y in zip(actualrows,expected))
   # Cell-by-cell, not comparison of totals alone. Header word changes separately recorded.
   diffs=[]
   if shape:
    for ri,(ar,er) in enumerate(zip(actualrows[1:],expected[1:]),1):
     for ci,(av,ev) in enumerate(zip(ar,er)):
      if numbers(av)!=numbers(ev):diffs.append(f'row {ri}, column {ci+1}: {av} versus {ev}')
   else:diffs=['Different dimensions']
   labels=shape and actualrows==expected
   audit.append(dict(section=sid,table=i,numeric_cells_match=shape and not diffs,all_text_matches=labels,differences='; '.join(diffs)))
   page.append(f'<h3>Table {i}</h3>'+render(expected))
 (out/'rebuilt_duration_planning.html').write_text('\n'.join(page)+ '</html>')
 with (out/'planning_html_checks.csv').open('w',newline='') as f:
  w=csv.DictWriter(f,fieldnames=list(audit[0]));w.writeheader();w.writerows(audit)
 print(json.dumps({'country':a.country,'tables_checked':len(audit),'numeric_matches':sum(x['numeric_cells_match'] for x in audit),'text_matches':sum(x['all_text_matches'] for x in audit)},indent=2))
 if not all(x['numeric_cells_match'] for x in audit):raise SystemExit(2)
if __name__=='__main__':main()
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 01_nigeria_calendar_life_table.R
# LANGUAGE: R
MODULES[["01_nigeria_calendar_life_table.R"]] <- list(
  language="R",
  original_sha256="ad1e23657d3b1475145818b8003cdd06d3879647a46c215ec70895983cd5538a",
  packaged_sha256="ad1e23657d3b1475145818b8003cdd06d3879647a46c215ec70895983cd5538a",
  args=character(),
  code=r"-----(#!/usr/bin/env Rscript
# Nigeria DHS 2024: reconstruct contraceptive episodes and validate Table 7.12.
# Input is the authorized IR recode already available in the Nigeria project.
# One woman contributes zero or more calendar method-use episodes. The DHS
# 3–62-month window and left entry are retained; multiple-decrement estimates
# keep every ending reason as a competing event. This script never edits input.

options(stringsAsFactors=FALSE)
script_arg <- grep('^--file=', commandArgs(FALSE), value=TRUE)
default_root <- if(length(script_arg)) normalizePath(file.path(dirname(sub('^--file=', '', script_arg[1])), '..')) else normalizePath('..')
root <- Sys.getenv('NIGERIA_PROJECT_ROOT', unset=default_root)
input_dir <- Sys.getenv('NIGERIA_INPUT_DIR', unset=file.path(root, 'Data/raw_dhs_ir'))
source_rds <- file.path(input_dir, 'NG2024DHS__NGIR8BDT__IR_raw.rds')
derived <- file.path(root,'Data/Derived')
support <- file.path(root,'output/Supporting_data')
dir.create(derived,recursive=TRUE,showWarnings=FALSE)
dir.create(support,recursive=TRUE,showWarnings=FALSE)
x <- readRDS(source_rds)
stopifnot(nrow(x)==39050L,!anyDuplicated(x$caseid),
          all(as.numeric(x$v008)-as.numeric(x$v017)+1==as.numeric(x$v019)),
          all(nchar(x$vcal_1)==80L),
          all(c('vcal_1','vcal_2','v005','v021','v022','v024','sstate') %in% names(x)))

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
    zone=as.integer(x$v024[i]),state=as.integer(x$sstate[i]),
    start=as.numeric(x$v017[i])+starts-1L,end=as.numeric(x$v017[i])+ends-1L,
    duration=runs$lengths,method_code=codes,reason_code=reason,
    reason_at_method_end=reason_at_end,reason_offset=offset,
    next_code=c(codes[-1L],NA_integer_),
    next_duration=c(runs$lengths[-1L],NA_integer_),
    next2_code=c(codes,NA_integer_,NA_integer_)[seq_along(codes)+2L])
}
events <- do.call(rbind,events)
saveRDS(events,file.path(derived,'nigeria_2024_calendar_events.rds'))

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
saveRDS(e,file.path(derived,'nigeria_2024_table_7_12_episodes.rds'))

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
cat('Women:',nrow(x),'episodes:',nrow(e),'weighted:',sum(e$wt),'\n')
print(audit,row.names=FALSE)
cat('Exact published rate cells:',sum(matching[,1:11]),'of',length(matching[,1:11]),'\n')
cat('Exact published episode counts:',sum(matching[,12]),'of',nrow(matching),'\n')
if(!all(matching))stop('Nigeria Table 7.12 replication does not yet match every published cell.')
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 02_nigeria_descriptive_analyses.R
# LANGUAGE: R
MODULES[["02_nigeria_descriptive_analyses.R"]] <- list(
 language="R",
 packaged_sha256="627ef35a223ae45af96554b96669554e9eb671cfe59b9beccdd01dedfb1aa994",
 args=character(),
 code=r"-----(#!/usr/bin/env Rscript
# Nigeria DHS 2024 descriptive analysis. Run after 01_nigeria_calendar_life_table.R.
# No package download is needed. The source IR recode stays unchanged.
# The outcome is cessation of the ORIGINAL modern method within 12 months for
# one of eight potentially actionable calendar reason codes. All other endings
# remain competing events. Emergency contraception is excluded because it is
# an episodic intervention, although it remains in official mCPR tabulations.
# Six geopolitical zones (v024) are the primary subnational geography.

root <- Sys.getenv("NIGERIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
full_ir <- readRDS(file.path(root,'Data/raw_dhs_ir/NG2024DHS__NGIR8BDT__IR_raw.rds'))
full_frame <- unique(data.frame(cluster=as.numeric(full_ir$v021),stratum=as.numeric(full_ir$v022)))

support <- file.path(root,'output/Supporting_data')
derived <- file.path(root,'Data/Derived')
e <- readRDS(file.path(derived,'nigeria_2024_table_7_12_episodes.rds'))
ir <- readRDS(file.path(Sys.getenv("NIGERIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE)), 'Data/raw_dhs_ir/NG2024DHS__NGIR8BDT__IR_raw.rds'))
stopifnot(nrow(ir)==39050L,nrow(e)==11210L)

zone_names <- c('North West','North East','North Central','South East','South South','South West')
e$zone_name <- zone_names[e$zone]
e$cluster <- as.numeric(ir$v021[e$woman_row])
e$stratum <- as.numeric(ir$v022[e$woman_row])
e$method_group <- 'Other modern'
e$method_group[e$method_code==1] <- 'Pill'
e$method_group[e$method_code==2] <- 'IUD'
e$method_group[e$method_code==3] <- 'Injectables'
e$method_group[e$method_code==11] <- 'Implants'
modern_codes <- c(1L,2L,3L,5L,6L,7L,11L,13L,14L,15L,17L,18L,19L,20L)
e <- e[e$method_code %in% modern_codes,]
stopifnot(!any(e$method_code==16L),all(e$zone %in% 1:6))
saveRDS(e,file.path(derived,'nigeria_2024_modern_episodes.rds'))

reason_codes <- list('Method failure'=1L,'Wanted more effective method'=7L,
  'Changes in menstrual bleeding'=15L,'Other side effects/health'=c(4L,5L),
  'Access/cost/convenience'=c(6L,8L,10L))
actionable <- unlist(reason_codes,use.names=FALSE)
stopifnot(length(unique(actionable))==8L)
months <- c(3L,6L,9L,12L)

# Weighted multiple-decrement life table. A woman can contribute several
# episodes; all her episodes share her survey weight and PSU in the bootstrap.
estimate <- function(d, multipliers=NULL) {
  if(is.null(multipliers)) w <- d$wt else w <- d$wt*multipliers[as.character(d$cluster)]
  s <- 1; any <- 0; action <- 0
  cause <- setNames(numeric(length(reason_codes)),names(reason_codes))
  rows <- vector('list',12)
  for(t in 1:12) {
    at <- d$entry<t & d$exposure>=t
    risk <- sum(w[at]); stopifnot(risk>0)
    ended <- at & d$exposure==t & d$discontinued
    all_h <- sum(w[ended])/risk
    chosen <- ended & d$reason_code %in% actionable
    a_h <- sum(w[chosen])/risk
    for(j in seq_along(reason_codes))
      cause[j] <- cause[j]+s*sum(w[ended & d$reason_code %in% reason_codes[[j]]])/risk
    any <- any+s*all_h; action <- action+s*a_h
    s <- s*(1-all_h)
    rows[[t]] <- data.frame(month=t,weighted_at_risk=risk,
      all_reason_pct=100*any,actionable_pct=100*action)
  }
  list(monthly=do.call(rbind,rows),causes=100*cause)
}

scopes <- list('National'=rep(TRUE,nrow(e)))
for(z in seq_along(zone_names)) scopes[[zone_names[z]]] <- e$zone==z
methods <- c('Injectables','Implants','Pill','IUD','Other modern')
for(m in methods) scopes[[paste0('National: ',m)]] <- e$method_group==m
for(z in zone_names) for(m in methods)
  scopes[[paste0(z,': ',m)]] <- e$zone_name==z & e$method_group==m

times <- list(); reasons <- list()
for(label in names(scopes)) {
  d <- e[scopes[[label]],]
  if(!nrow(d)) next
  fit <- estimate(d)
  t <- fit$monthly[fit$monthly$month %in% months,]
  t$scope <- label; t$eligible_episodes_n <- nrow(d)
  t$weighted_episodes <- sum(d$wt)
  t$actionable_endings_n <- sum(d$discontinued & d$exposure<=12 &
    d$reason_code %in% actionable)
  t$limited_precision <- t$actionable_endings_n<30L
  times[[label]] <- t
  total <- sum(fit$causes)
  reasons[[label]] <- data.frame(scope=label,reason=names(fit$causes),
    cause_specific_12_month_pct=unname(fit$causes),
    share_among_actionable_pct=if(total>0)100*unname(fit$causes)/total else NA_real_,
    eligible_episodes_n=nrow(d),
    actionable_endings_n=t$actionable_endings_n[1],
    limited_precision=t$actionable_endings_n[1]<30L)
}
times <- do.call(rbind,times); reasons <- do.call(rbind,reasons)
rownames(times) <- rownames(reasons) <- NULL
stopifnot(max(abs(aggregate(share_among_actionable_pct~scope,reasons,sum)$share_among_actionable_pct-100))<1e-6)

# Stratified PSU bootstrap, preserving the original sample design. The
# percentile intervals describe sampling uncertainty; sparse zone x method
# cells are flagged for caution regardless of their numerical interval.
frame <- full_frame; frame$id <- seq_len(nrow(frame))
stopifnot(!anyDuplicated(frame$cluster))
groups <- split(frame$id,frame$stratum)
stopifnot(all(lengths(groups)>1L))
B <- as.integer(Sys.getenv('NIGERIA_BOOTSTRAP_REPS','300'))
focus <- names(scopes)
boot <- array(NA_real_,c(B,length(focus),4L),
  dimnames=list(NULL,focus,as.character(months)))
for(b in seq_len(B)) {
  set.seed(20261021L+b)
  mult <- numeric(nrow(frame))
  for(ids in groups) {
    n <- length(ids)
    mult[ids] <- n/(n-1)*tabulate(sample.int(n,n-1,replace=TRUE),nbins=n)
  }
  lookup <- setNames(mult,frame$cluster)
  for(j in seq_along(focus)) {
    d <- e[scopes[[focus[j]]],]
    fit <- tryCatch(estimate(d,lookup),error=function(err)NULL)
    if(!is.null(fit))boot[b,j,] <- fit$monthly$actionable_pct[months]
  }
}
for(j in seq_along(focus))for(k in seq_along(months)) {
  z <- boot[,j,k]; z <- z[is.finite(z)]
  if(length(z)<.9*B)stop('Too few valid bootstrap estimates: ',focus[j])
  sel <- times$scope==focus[j] & times$month==months[k]
  times$ci_low[sel] <- quantile(z,.025)
  times$ci_high[sel] <- quantile(z,.975)
}
write.csv(times,file.path(support,'nigeria_actionable_timepoints.csv'),row.names=FALSE)
write.csv(reasons,file.path(support,'nigeria_actionable_reason_mix.csv'),row.names=FALSE)
saveRDS(boot,file.path(derived,'nigeria_actionable_bootstrap.rds'))

# Observed modern-method starts: entry=0 corresponds to an observed start.
# These shares condition on modern starts and are retained for modeling and
# audit purposes. Presentation gold bars instead use ALL observed method
# starts from Code/15, matching the Ethiopia initiation-mix denominator.
# EC is omitted from ongoing-method risk.
starts <- e[e$entry==0L,]
start_rows <- list()
for(z in c('National',zone_names)) {
  d <- if(z=='National')starts else starts[starts$zone_name==z,]
  denom <- sum(d$wt)
  for(m in methods) {
    q <- d[d$method_group==m,]
    start_rows[[length(start_rows)+1L]] <- data.frame(scope=z,method=m,
      starts_n=nrow(q),weighted_starts=sum(q$wt),
      start_share_pct=100*sum(q$wt)/denom,
      actionable_12_month_pct=times$actionable_pct[
        times$scope==paste0(z,if(z=='National')': ' else ': ',m) & times$month==12][1])
  }
}
mix <- do.call(rbind,start_rows)
write.csv(mix,file.path(support,'nigeria_zone_modern_method_start_mix.csv'),row.names=FALSE)

# Survey-weighted all-women mCPR and current method shares. DHS v313=3 is
# modern use (including EC); numbers of users require a separate population
# denominator, so this script reports percentages only.
current <- data.frame(wt=as.numeric(ir$v005)/1e6,
  modern=as.numeric(ir$v313)==3,method=as.numeric(ir$v312),
  zone=zone_names[as.numeric(ir$v024)])
current_rows <- list()
for(z in c('National',zone_names)) {
  d <- if(z=='National')current else current[current$zone==z,]
  modern_users <- d[d$modern,]
  current_rows[[z]] <- data.frame(scope=z,women_n=nrow(d),
    modern_users_n=nrow(modern_users),
    all_women_mcpr_pct=100*sum(d$wt[d$modern])/sum(d$wt),
    ec_share_of_modern_users_pct=100*sum(modern_users$wt[modern_users$method==16])/
      sum(modern_users$wt))
}
write.csv(do.call(rbind,current_rows),
  file.path(support,'nigeria_current_use_mcpr.csv'),row.names=FALSE)
# Published Table 7.3, all-women total: mCPR 13.1%, sample 39,050. Its
# method columns are verified to one decimal before any user-count analysis.
published_use <- c(`Female sterilization`=.3,IUD=.6,Injectables=2.7,
  Implants=4.0,Pill=1.1,`Male condom`=3.0,EC=.4,LAM=.9,
  `Other modern`=.1)
current_codes <- list(`Female sterilization`=6L,IUD=2L,Injectables=3L,
  Implants=11L,Pill=1L,`Male condom`=5L,EC=16L,LAM=13L,
  `Other modern`=c(7L,14L,18L))
use_audit <- do.call(rbind,lapply(names(published_use),function(name){
  val <- 100*sum(current$wt[current$method %in% current_codes[[name]]])/
    sum(current$wt)
  data.frame(method=name,reconstructed_pct=val,
    published_rounded_pct=published_use[[name]],
    matches=round(val,1)==published_use[[name]])
}))
stopifnot(all(use_audit$matches),
  round(current_rows$National$all_women_mcpr_pct,1)==13.1)
write.csv(use_audit,file.path(support,'nigeria_table_7_3_current_use_validation.csv'),
  row.names=FALSE)
cat('Modern episodes:',nrow(e),'National actionable 12-month rate:',
    round(times$actionable_pct[times$scope=='National' & times$month==12],2),'\n')
print(times[times$month==12 & times$scope %in% c('National',zone_names),
  c('scope','eligible_episodes_n','actionable_endings_n','actionable_pct','ci_low','ci_high')],
  row.names=FALSE)
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 03_nigeria_zone_models.R
# LANGUAGE: R
MODULES[["03_nigeria_zone_models.R"]] <- list(
 language="R",
 packaged_sha256="da1f279a5c3ae4973349b323e41e8ae1d080620fe6c45d30793f0adf71cb3c04",
 args=character(),
 code=r"-----(#!/usr/bin/env Rscript
# Nigeria DHS 2024: adjusted zone comparison for actionable discontinuation.
# Run after scripts 01 and 02. Unit of fitting is the episode-month. Outcomes
# are continuation, actionable discontinuation, and another competing ending.
# Therefore pregnancy intentions, partner disapproval, other fertility reasons,
# and unresolved reasons remain in the starting cohort and leave at their end.
# The two multinomial discrete-time models mirror the Ethiopia specification:
# A: month of method use, method, zone; B: A plus measured characteristics.
# Method use month is elapsed duration since the ORIGINAL method began, not
# duration at interview. Both models retain delayed-entry episodes for fitting.
# Adjusted zone probabilities predict a 12-month first-year trajectory on the
# SAME observed-start national episodes with each zone assigned in turn. This
# is common-composition standardization, not each zone's actual observed mix.

root <- Sys.getenv("NIGERIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
full_ir <- readRDS(file.path(root,'Data/raw_dhs_ir/NG2024DHS__NGIR8BDT__IR_raw.rds'))
full_frame <- unique(data.frame(cluster=as.numeric(full_ir$v021),stratum=as.numeric(full_ir$v022)))

support <- file.path(root,'output/Supporting_data')
derived <- file.path(root,'Data/Derived')
if(!requireNamespace('nnet',quietly=TRUE))stop('nnet package is required')
e <- readRDS(file.path(derived,'nigeria_2024_modern_episodes.rds'))
ir <- readRDS(file.path(Sys.getenv("NIGERIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE)), 'Data/raw_dhs_ir/NG2024DHS__NGIR8BDT__IR_raw.rds'))
times <- read.csv(file.path(support,'nigeria_actionable_timepoints.csv'))
actionable <- c(1L,4L,5L,6L,7L,8L,10L,15L)
e$zone_name <- factor(e$zone_name,
  levels=c('North West','North East','North Central','South East','South South','South West'))
e$method_group <- factor(e$method_group,
  levels=c('IUD','Injectables','Implants','Pill','Other modern'))
e$age_at_start <- (e$start-as.numeric(ir$v011[e$woman_row]))/12
stopifnot(all(e$age_at_start>=10),all(e$age_at_start<50))
# A small number of calendar episodes began before age 15, although every
# respondent was 15–49 at interview. Retain them in an honestly labeled group.
e$age_group <- factor(ifelse(e$age_at_start<20,'Under 20',
  ifelse(e$age_at_start<25,'20–24',ifelse(e$age_at_start<35,'25–34','35–49'))),
  levels=c('25–34','Under 20','20–24','35–49'))
bcols <- grep('^b3_',names(ir),value=TRUE)
b <- as.matrix(ir[e$woman_row,bcols])
parity <- rowSums(!is.na(b) & b<=e$start)
e$parity_group <- factor(ifelse(parity==0,'0',ifelse(parity<=2,'1–2',
  ifelse(parity<=4,'3–4','5+'))),levels=c('0','1–2','3–4','5+'))
marital <- as.numeric(ir$v501[e$woman_row])
e$marital_group <- factor(ifelse(marital==0,'Never in union',
  ifelse(marital==1,'Married',ifelse(marital==2,'Living together',
  'Formerly in union'))),
  levels=c('Married','Never in union','Living together','Formerly in union'))
educ <- as.numeric(ir$v106[e$woman_row])
e$education <- factor(ifelse(educ==0,'None',ifelse(educ==1,'Primary',
  ifelse(educ %in% c(2,3),'Secondary or higher',NA_character_))),
  levels=c('None','Primary','Secondary or higher'))
e$wealth <- factor(c('Poorest','Poorer','Middle','Richer','Richest')[
  as.numeric(ir$v190[e$woman_row])],
  levels=c('Poorest','Poorer','Middle','Richer','Richest'))
e$residence <- factor(ifelse(as.numeric(ir$v025[e$woman_row])==1,'Urban','Rural'),
  levels=c('Urban','Rural'))
# Very recent 2024 starts contribute only 50 episodes and no observed
# actionable endings in the DHS window. A separate 2024 indicator therefore
# perfectly separates the event outcome. Pool 2023 and 2024 starts so the
# cohort term remains estimable while retaining all eligible episodes.
year <- (e$start-1L)%/%12L+1900L
e$start_year <- factor(ifelse(year>=2023,'2023–24',as.character(year)))
complete <- complete.cases(e[,c('method_group','zone_name','age_group',
  'parity_group','marital_group','education','wealth','residence','start_year')])
cat('Complete-case episodes:',sum(complete),'of',nrow(e),'\n')
e <- e[complete,]
saveRDS(e,file.path(derived,'nigeria_2024_model_episode_covariates.rds'))

observed_months <- pmax(0L,pmin(12L,e$exposure)-e$entry)
idx <- rep(seq_len(nrow(e)),observed_months)
month <- unlist(Map(function(first,n)seq.int(first+1L,length.out=n),
  e$entry,observed_months),use.names=FALSE)
person <- e[idx,c('wt','cluster','stratum','method_group','zone_name',
  'age_group','parity_group','marital_group','education','wealth',
  'residence','start_year')]
person$month <- factor(month,levels=1:12)
end <- e$discontinued[idx] & month==e$exposure[idx]
person$outcome <- factor(ifelse(!end,'continue',
  ifelse(e$reason_code[idx] %in% actionable,'actionable','competing')),
  levels=c('continue','actionable','competing'))
stopifnot(!anyNA(person),nrow(person)>40000)
saveRDS(person,file.path(derived,'nigeria_2024_person_month.rds'))

f1 <- outcome~month+method_group+zone_name
f2 <- outcome~month+method_group+zone_name+age_group+parity_group+
  marital_group+education+wealth+residence+start_year
fit <- function(formula,data,wts,with_hessian=TRUE){
  data$fit_weight <- wts
  m <- nnet::multinom(formula,data=data,weights=fit_weight,trace=FALSE,
    maxit=350,MaxNWts=10000,Hess=with_hessian)
  m$call$formula <- formula
  if(m$convergence!=0L)stop('Model did not converge')
  m
}
model1 <- fit(f1,person,person$wt)
model2 <- fit(f2,person,person$wt)
saveRDS(model1,file.path(derived,'nigeria_actionable_zone_model_1.rds'))
saveRDS(model2,file.path(derived,'nigeria_actionable_zone_model_2.rds'))

# The common reference is modern episodes observed from initiation, thus its
# covariates represent the cohort to whom first-year predictions apply.
standard <- e[e$entry==0L,]
predict_cif <- function(model,zone,reference=standard,weights=reference$wt){
  d <- reference
  if(!is.null(zone) && !is.na(zone))
    d$zone_name <- factor(zone,levels=levels(e$zone_name))
  survival <- rep(1,nrow(d)); cumulative <- numeric(nrow(d))
  for(t in 1:12){
    d$month <- factor(t,levels=1:12)
    p <- predict(model,newdata=d,type='probs')
    cumulative <- cumulative+survival*p[,'actionable']
    survival <- survival*p[,'continue']
  }
  100*weighted.mean(cumulative,weights)
}
zones <- levels(e$zone_name)
point <- do.call(rbind,lapply(zones,function(z){
  raw <- times[times$scope==z & times$month==12,]
  data.frame(zone=z,eligible_episodes_n=raw$eligible_episodes_n,
    actionable_endings_n=raw$actionable_endings_n,
    unadjusted_pct=raw$actionable_pct,unadjusted_low=raw$ci_low,
    unadjusted_high=raw$ci_high,
    model_1_common_mix_pct=predict_cif(model1,z),
    model_2_common_mix_pct=predict_cif(model2,z))
}))
national <- times[times$scope=='National' & times$month==12,]
point <- rbind(data.frame(zone='National',
  eligible_episodes_n=national$eligible_episodes_n,
  actionable_endings_n=national$actionable_endings_n,
  unadjusted_pct=national$actionable_pct,
  unadjusted_low=national$ci_low,
  unadjusted_high=national$ci_high,
  model_1_common_mix_pct=predict_cif(model1,NULL),
  model_2_common_mix_pct=predict_cif(model2,NULL)),point)
write.csv(point,file.path(support,'nigeria_actionable_zone_adjusted_rates.csv'),
  row.names=FALSE)

# Model coefficients are odds ratios for each non-continuation event versus
# continuing that same episode-month. Wald p-values here use model Hessian;
# survey-design bootstrap intervals are calculated for the zone probabilities
# below. Coefficients should be read as associations, not causal effects.
coefficient_table <- function(model,name){
  s <- summary(model)
  z <- s$coefficients/s$standard.errors
  p <- 2*pnorm(-abs(z))
  rows <- list()
  for(outcome in rownames(s$coefficients))for(v in colnames(s$coefficients)){
    beta <- s$coefficients[outcome,v]; se <- s$standard.errors[outcome,v]
    rows[[length(rows)+1L]] <- data.frame(model=name,outcome=outcome,
      covariate=v,odds_ratio=exp(beta),ci_low=exp(beta-1.96*se),
      ci_high=exp(beta+1.96*se),p_value=p[outcome,v])
  }
  do.call(rbind,rows)
}
coef <- rbind(coefficient_table(model1,'Method + duration'),
  coefficient_table(model2,'Full'))
write.csv(coef,file.path(support,'nigeria_actionable_zone_model_odds_ratios.csv'),
  row.names=FALSE)

# Optional stratified PSU bootstrap for adjusted probability intervals.
# It refits both models with the same resampled clusters. Minimum 90% valid
# refits required. Set NIGERIA_MODEL_BOOTSTRAP_REPS=0 to skip while prototyping.
B <- as.integer(Sys.getenv('NIGERIA_MODEL_BOOTSTRAP_REPS','500'))
if(B>0L){
  frame <- full_frame; frame$id<-seq_len(nrow(frame))
  groups <- split(frame$id,frame$stratum)
  stopifnot(!anyDuplicated(frame$cluster),all(lengths(groups)>1L))
  one <- function(b){
    set.seed(20261025L+b)
    mult <- numeric(nrow(frame))
    for(ids in groups){
      n<-length(ids)
      mult[ids]<-n/(n-1)*tabulate(sample.int(n,n-1,replace=TRUE),nbins=n)
    }
    lookup<-setNames(mult,frame$cluster)
    w<-person$wt*lookup[as.character(person$cluster)]
    sw<-standard$wt*lookup[as.character(standard$cluster)]
    # The Hessian is required for the single fitted coefficient table, but
    # not for bootstrap predictions. Omitting it avoids repeated unnecessary
    # matrix calculations while preserving the same fitted probabilities.
    m1<-tryCatch(fit(f1,person,w,FALSE),error=function(err)NULL)
    m2<-tryCatch(fit(f2,person,w,FALSE),error=function(err)NULL)
    if(is.null(m1)||is.null(m2))return(rep(NA_real_,14L))
    c(vapply(c(NA_character_,zones),function(z)predict_cif(m1,z,standard,sw),numeric(1)),
      vapply(c(NA_character_,zones),function(z)predict_cif(m2,z,standard,sw),numeric(1)))
  }
  draws<-parallel::mclapply(seq_len(B),one,
    mc.cores=min(4L,parallel::detectCores()),mc.preschedule=FALSE)
  draws<-do.call(rbind,draws)
  valid<-complete.cases(draws)
  if(sum(valid)<ceiling(.9*B))stop('Too few successful model bootstrap refits')
  colnames(draws)<-c(paste0('model1:',point$zone),paste0('model2:',point$zone))
  write.csv(draws,file.path(support,'nigeria_actionable_zone_model_bootstrap.csv'),
    row.names=FALSE)
  ci<-apply(draws[valid,,drop=FALSE],2,quantile,c(.025,.975),na.rm=TRUE)
  point$model_1_low<-ci[1,1:7]; point$model_1_high<-ci[2,1:7]
  point$model_2_low<-ci[1,8:14]; point$model_2_high<-ci[2,8:14]
  write.csv(point,file.path(support,'nigeria_actionable_zone_adjusted_rates.csv'),
    row.names=FALSE)
}
print(point,row.names=FALSE)

source(file.path(root,"Code","202_nigeria_survey_coefficients.R"),local=TRUE)
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 04_nigeria_subgroups_and_tests.R
# LANGUAGE: R
MODULES[["04_nigeria_subgroups_and_tests.R"]] <- list(
 language="R",
 packaged_sha256="8e7bcf518ece45fef6359d0e80875e9a75ac7cf7985dca7dd549fbffee77cb34",
 args=character(),
 code=r"-----(#!/usr/bin/env Rscript
# Nigeria DHS 2024 subgroup and zone-pairwise analysis. Run after 01–03.
# Each subgroup rate is a weighted cumulative incidence among its eligible
# modern method episodes, with all non-actionable endings as competing events.
# Zone pairwise tests compare differences in 12-month percentage points.
# Holm adjustment controls family-wise error across all 15 zone pairs per
# comparison stage. PSU bootstraps are stratified and keep all woman episodes
# together. They remain exploratory for small method-specific cells.

root <- Sys.getenv("NIGERIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
full_ir <- readRDS(file.path(root,'Data/raw_dhs_ir/NG2024DHS__NGIR8BDT__IR_raw.rds'))
full_frame <- unique(data.frame(cluster=as.numeric(full_ir$v021),stratum=as.numeric(full_ir$v022)))

support <- file.path(root,'output/Supporting_data')
derived <- file.path(root,'Data/Derived')
e <- readRDS(file.path(derived,'nigeria_2024_model_episode_covariates.rds'))
reasons <- list('Method failure'=1L,'Wanted more effective method'=7L,
 'Changes in menstrual bleeding'=15L,'Other side effects/health'=c(4L,5L),
 'Access/cost/convenience'=c(6L,8L,10L))
actionable <- unlist(reasons,use.names=FALSE)
life <- function(d,w=d$wt){
 s<-1; f<-0; cause<-numeric(length(reasons))
 for(t in 1:12){
  at<-d$entry<t & d$exposure>=t
  risk<-sum(w[at]); if(risk<=0)return(rep(NA_real_,1+length(reasons)))
  end<-at & d$exposure==t & d$discontinued
  for(j in seq_along(reasons))cause[j]<-cause[j]+s*sum(w[end & d$reason_code %in% reasons[[j]]])/risk
  f<-f+s*sum(w[end & d$reason_code %in% actionable])/risk
  s<-s*(1-sum(w[end])/risk)
 }
 c(total=100*f,setNames(100*cause,names(reasons)))
}
covariates <- c('age_group','parity_group','marital_group','education',
 'wealth','residence','method_group','zone_name')
frame<-full_frame; frame$id<-seq_len(nrow(frame))
groups<-split(frame$id,frame$stratum)
stopifnot(!anyDuplicated(frame$cluster),all(lengths(groups)>1L))
B<-as.integer(Sys.getenv('NIGERIA_SUBGROUP_BOOTSTRAP_REPS','250'))
scopes<-list()
for(v in covariates)for(value in levels(e[[v]]))
 scopes[[paste(v,value,sep='::')]]<-which(e[[v]]==value)
point<-lapply(names(scopes),function(key){
 idx<-scopes[[key]]; d<-e[idx,]; x<-life(d)
 data.frame(covariate=strsplit(key,'::',fixed=TRUE)[[1]][1],
   category=strsplit(key,'::',fixed=TRUE)[[1]][2],
   eligible_episodes_n=nrow(d),weighted_episodes=sum(d$wt),
   actionable_endings_n=sum(d$discontinued & d$exposure<=12 &
     d$reason_code %in% actionable),
   actionable_12_month_pct=x[1],as.list(x[-1]),
   limited_precision=sum(d$discontinued & d$exposure<=12 &
     d$reason_code %in% actionable)<30L)
})
point<-do.call(rbind,point)
draw<-matrix(NA_real_,B,nrow(point))
for(b in seq_len(B)){
 set.seed(20261101L+b)
 mult<-numeric(nrow(frame))
 for(ids in groups){n<-length(ids);mult[ids]<-n/(n-1)*
   tabulate(sample.int(n,n-1,replace=TRUE),nbins=n)}
 lookup<-setNames(mult,frame$cluster)
 for(j in seq_along(scopes)){
  d<-e[scopes[[j]],]
  draw[b,j]<-life(d,d$wt*lookup[as.character(d$cluster)])[1]
 }
}
ci<-apply(draw,2,quantile,c(.025,.975),na.rm=TRUE)
point$ci_low<-ci[1,];point$ci_high<-ci[2,]
write.csv(point,file.path(support,'nigeria_actionable_subgroup_rates_reasons.csv'),
 row.names=FALSE)

# Convert the saved bootstrap trajectories to design-based contrasts. A
# two-sided normal statistic uses the PSU-bootstrap SE for each difference;
# report both raw and Holm-adjusted p-values. This is descriptive inference.
raw<-readRDS(file.path(derived,'nigeria_actionable_bootstrap.rds'))
modfile<-file.path(support,'nigeria_actionable_zone_model_bootstrap.csv')
if(file.exists(modfile)) {
  modeldraw<-read.csv(modfile,check.names=FALSE)
} else {
  modeldraw<-NULL
}
rates<-read.csv(file.path(support,'nigeria_actionable_zone_adjusted_rates.csv'))
zones<-rates$zone[rates$zone!='National']
pairs<-combn(zones,2,simplify=FALSE)
rows<-list()
for(stage in c('Unadjusted','Method adjusted','Fully adjusted')){
 if(stage!='Unadjusted' && is.null(modeldraw))next
 for(pair in pairs){
  a<-pair[1];b<-pair[2]
  if(stage=='Unadjusted'){
    v<-raw[,a,'12']-raw[,b,'12']
    diff<-rates$unadjusted_pct[rates$zone==a]-rates$unadjusted_pct[rates$zone==b]
  }else{
    stem<-if(stage=='Method adjusted')'model1:' else 'model2:'
    v<-modeldraw[[paste0(stem,a)]]-modeldraw[[paste0(stem,b)]]
    col<-if(stage=='Method adjusted')'model_1_common_mix_pct' else
      'model_2_common_mix_pct'
    diff<-rates[[col]][rates$zone==a]-rates[[col]][rates$zone==b]
  }
  v<-v[is.finite(v)]
  se<-sd(v)
  rows[[length(rows)+1L]]<-data.frame(stage=stage,zone_a=a,zone_b=b,
    difference_pp=diff,se_pp=se,ci_low=diff-1.96*se,
    ci_high=diff+1.96*se,p_value=2*pnorm(-abs(diff/se)),
    bootstrap_replicates=length(v))
 }
}
tests<-do.call(rbind,rows)
tests$p_holm<-ave(tests$p_value,tests$stage,FUN=function(p)p.adjust(p,'holm'))
tests$significant_5pct<-tests$p_holm<.05
tests$significant_10pct<-tests$p_holm<.10
write.csv(tests,file.path(support,'nigeria_zone_pairwise_three_stages.csv'),
 row.names=FALSE)
cat('Subgroups:',nrow(point),' pairwise rows:',nrow(tests),'\n')
print(aggregate(significant_5pct~stage,tests,sum),row.names=FALSE)
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 08_nigeria_population_and_planning.R
# LANGUAGE: R
MODULES[["08_nigeria_population_and_planning.R"]] <- list(
  language="R",
  original_sha256="806433f8204aefbda17806f6e4b34ebda4dc81720d17e7acdd9fc8ad7d7b9767",
  packaged_sha256="806433f8204aefbda17806f6e4b34ebda4dc81720d17e7acdd9fc8ad7d7b9767",
  args=character(),
  code=r"-----(#!/usr/bin/env Rscript
# Nigeria DHS 2024 current-use method mix and an illustrative 2024–26
# planning bridge. WRA comes from UN WPP 2024 medium variant (female single
# ages 15–49, mid-year). Pair the 2024 survey mCPR/mix with 2024 WRA first;
# then project both WRA and mCPR forward rather than calling 2025 observed.
# First-year episode risks are applied to the estimated current-user stock
# only as a transparent illustrative upper bound, not a duration-adjusted
# forecast of current-user discontinuation or loss of all modern use.
root <- Sys.getenv("NIGERIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
out <- file.path(root,'output/Supporting_data')
ir <- readRDS(file.path(Sys.getenv("NIGERIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE)), 'Data/raw_dhs_ir/NG2024DHS__NGIR8BDT__IR_raw.rds'))
e <- readRDS(file.path(root,'Data/Derived/nigeria_2024_modern_episodes.rds'))
times <- read.csv(file.path(out,'nigeria_actionable_timepoints.csv'))
reasons <- read.csv(file.path(out,'nigeria_actionable_reason_mix.csv'))
wra <- read.csv(file.path(out,'nigeria_wpp2024_wra_2024_2026.csv'))
stopifnot(all(c(2024,2025,2026) %in% wra$year),nrow(ir)==39050L)
modern <- as.numeric(ir$v313)==3
code <- as.numeric(ir$v312)
method <- rep(NA_character_,length(code))
method[code==3] <- 'Injectables';method[code==11] <- 'Implants'
method[code==1] <- 'Pill';method[code==2] <- 'IUD'
method[code==16] <- 'EC'
method[modern & is.na(method)] <- 'Other modern'
stopifnot(all(!is.na(method[modern])),all(is.na(method[!modern])))
wt <- as.numeric(ir$v005)/1e6
mcpr <- 100*sum(wt[modern])/sum(wt)
stopifnot(round(mcpr,1)==13.1)
lev <- c('Injectables','Implants','Pill','IUD','Other modern','EC')
mix <- data.frame(method=lev,weighted_users=vapply(lev,function(m)sum(wt[method==m],na.rm=TRUE),0.0))
mix$share_current_modern_pct <- 100*mix$weighted_users/sum(mix$weighted_users)
mix$current_method_prevalence_pct <- mcpr*mix$share_current_modern_pct/100
stopifnot(abs(sum(mix$share_current_modern_pct)-100)<1e-8)
w24 <- wra$women_15_49[wra$year==2024]
w25 <- wra$women_15_49[wra$year==2025]
w26 <- wra$women_15_49[wra$year==2026]
current_users_2024 <- w24*mcpr/100
mix$current_users_2024 <- current_users_2024*mix$share_current_modern_pct/100

# Source for the 0.4 percentage-point annual trend: Track20/FP2030 Nigeria
# 2025 indicator brief gives all-women mCPR 13.2% in 2024 and 13.6% in 2025.
# It is used here as a scenario increment, not as a 2026 prediction.
scenarios <- data.frame(scenario=c('No further growth in 2026','DHS anchored +0.4 pp/year','FP2030 2025 level +0.4 pp'),
  mcpr_2024_pct=rep(mcpr,3),
  mcpr_2025_pct=rep(mcpr+0.4,3),
  mcpr_2026_pct=c(mcpr+0.4,mcpr+0.8,14.0))
scenarios$wra_2024 <- w24;scenarios$wra_2025 <- w25;scenarios$wra_2026 <- w26
scenarios$current_users_2024 <- current_users_2024
scenarios$current_users_2025 <- w25*scenarios$mcpr_2025_pct/100
scenarios$usual_users_2026 <- w26*scenarios$mcpr_2026_pct/100

# The user-count slide applies each method's first-year actionable probability
# to estimated users in 2025. Cause-specific risks sum to method total.
central <- scenarios[scenarios$scenario=='DHS anchored +0.4 pp/year',]
mix$current_users_2025 <- central$current_users_2025*mix$share_current_modern_pct/100
mix$actionable_first_year_risk_pct <- NA_real_
for(i in seq_len(nrow(mix))){
  m <- mix$method[i]
  if(m!='EC') mix$actionable_first_year_risk_pct[i] <- times$actionable_pct[times$scope==paste0('National: ',m) & times$month==12]
}
mix$illustrative_original_method_endings <- mix$current_users_2025*mix$actionable_first_year_risk_pct/100
mix$illustrative_original_method_endings[is.na(mix$illustrative_original_method_endings)] <- 0
cause <- reasons[grepl('^National: ',reasons$scope),]
cause$method <- sub('^National: ','',cause$scope)
cause <- merge(cause,mix[,c('method','current_users_2025')],by='method')
cause$illustrative_users <- cause$current_users_2025*cause$cause_specific_12_month_pct/100
stopifnot(max(abs(aggregate(illustrative_users~method,cause,sum)$illustrative_users -
  mix$illustrative_original_method_endings[match(aggregate(illustrative_users~method,cause,sum)$method,mix$method)]))<1)

# A first-month switch to another modern method is not an immediate exit from
# modern contraceptive use. This descriptive bridge is from episode endings,
# without claiming to identify modern use at year-end.
modern_codes <- c(1L,2L,3L,5L,6L,7L,11L,13L,14L,15L,17L,18L,19L,20L)
e$modern_next <- e$next_code %in% modern_codes
e$modern_next[is.na(e$modern_next)] <- FALSE
e$actionable <- e$discontinued & e$reason_code %in% c(1L,4L,5L,6L,7L,8L,10L,15L)
e$eligible_event <- e$actionable & e$exposure<=12
switch_share <- data.frame(method=c('All modern',lev[lev!='EC']),share_immediate_modern_pct=NA_real_,
  actionable_events_n=NA_integer_)
for(i in seq_len(nrow(switch_share))){
  d <- if(i==1) e else e[e$method_group==switch_share$method[i],]
  a <- d[d$eligible_event,]
  switch_share$actionable_events_n[i] <- nrow(a)
  switch_share$share_immediate_modern_pct[i] <- if(nrow(a))100*sum(a$wt[a$modern_next])/sum(a$wt) else NA_real_
}

gross <- sum(mix$illustrative_original_method_endings)
net_immediate <- sum(mix$illustrative_original_method_endings[1:5]*
  (1-switch_share$share_immediate_modern_pct[match(mix$method[1:5],switch_share$method)]/100))
scenarios$illustrative_gross_endings <- gross
scenarios$illustrative_after_immediate_switch <- net_immediate
scenarios$no_gross_endings_users_2026 <- scenarios$usual_users_2026+gross
scenarios$no_gross_endings_mcpr_2026_pct <- 100*scenarios$no_gross_endings_users_2026/scenarios$wra_2026
scenarios$gross_ceiling_gain_pp <- scenarios$no_gross_endings_mcpr_2026_pct-scenarios$mcpr_2026_pct
scenarios$no_non_switch_endings_users_2026 <- scenarios$usual_users_2026+net_immediate
scenarios$no_non_switch_endings_mcpr_2026_pct <- 100*scenarios$no_non_switch_endings_users_2026/scenarios$wra_2026
scenarios$non_switch_ceiling_gain_pp <- scenarios$no_non_switch_endings_mcpr_2026_pct-scenarios$mcpr_2026_pct

write.csv(mix,file.path(out,'nigeria_current_users_by_method_and_actionable_projection.csv'),row.names=FALSE)
write.csv(cause,file.path(out,'nigeria_current_users_actionable_by_cause.csv'),row.names=FALSE)
write.csv(switch_share,file.path(out,'nigeria_actionable_immediate_modern_switch_share.csv'),row.names=FALSE)
write.csv(scenarios,file.path(out,'nigeria_2026_mcpr_scenarios.csv'),row.names=FALSE)
cat('WRA 2024',w24,'users 2024',current_users_2024,'WRA 2025',w25,
  'WRA 2026',w26,'DHS 2024 mCPR',mcpr,'gross illustrative endings',gross,
  'after immediate switch',net_immediate,'\n')
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 09_nigeria_post_discontinuation_pathways.R
# LANGUAGE: R
MODULES[["09_nigeria_post_discontinuation_pathways.R"]] <- list(
  language="R",
  original_sha256="0432d66d7c32bcadf3c0dd63e80b5eb84a0a7b79ed6bf0f3d251fca49679d058",
  packaged_sha256="0432d66d7c32bcadf3c0dd63e80b5eb84a0a7b79ed6bf0f3d251fca49679d058",
  args=character(),
  code=r"-----(#!/usr/bin/env Rscript
# Descriptive status one and twelve months after an observed actionable
# original-method ending. This is a follow-up cohort, not a competing-risk
# life-table estimate. Only events with the respective follow-up month
# observable in the DHS calendar contribute at that checkpoint.
root <- Sys.getenv("NIGERIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
out <- file.path(root,'output/Supporting_data')
e <- readRDS(file.path(root,'Data/Derived/nigeria_2024_modern_episodes.rds'))
all <- readRDS(file.path(root,'Data/Derived/nigeria_2024_calendar_events.rds'))
modern <- c(1L,2L,3L,5L,6L,7L,11L,13L,14L,15L,17L,18L,19L,20L)
eligible <- e[e$discontinued & e$exposure<=12 & e$reason_code %in% c(1L,4L,5L,6L,7L,8L,10L,15L),]
stopifnot(nrow(eligible)>1000L)
status <- function(z,original) {
  if(is.na(z)) return('Unobserved')
  if(z %in% modern) return(if(z==original) 'Same modern method' else 'Different modern method')
  if(z %in% c(8L,9L,10L,12L,99L)) return('Traditional/other method')
  if(z %in% c(81L,82L,83L)) return('Pregnant, birth or termination')
  if(z==0L) return('No method recorded')
  'Other/unknown'
}
rows <- list()
inds <- split(seq_len(nrow(all)),all$woman_row)
code_at <- function(d,i,k){
  a <- all[inds[[as.character(d$woman_row[i])]],]
  pick <- which(a$start<=d$end[i]+k & a$end>=d$end[i]+k)
  if(length(pick)!=1L)stop('Calendar timeline is not uniquely partitioned')
  a$method_code[pick]
}
for(k in c(1L,12L)){
  d <- eligible[eligible$end+k<=eligible$interview,]
  # Calendar events partition each woman's observed months.
  next_code <- vapply(seq_len(nrow(d)),function(i)code_at(d,i,k),integer(1))
  d$status <- mapply(status,next_code,d$method_code)
  tab <- aggregate(d$wt,list(status=d$status),sum)
  tab$month_after_ending <- k
  tab$percent <- 100*tab$x/sum(d$wt)
  tab$observed_ending_events_n <- nrow(d)
  tab$weighted_ending_events <- sum(d$wt)
  names(tab)[names(tab)=='x'] <- 'weighted_events'
  rows[[as.character(k)]] <- tab
}
z <- do.call(rbind,rows);z <- z[,c('month_after_ending','status','weighted_events','percent','observed_ending_events_n','weighted_ending_events')]
write.csv(z,file.path(out,'nigeria_actionable_post_ending_pathways.csv'),row.names=FALSE)
# The joint table keeps only endings observed for a full 12 months. Its rows
# therefore describe real transitions in one common cohort; the marginal
# one-month table above has a larger observation window and a different base.
d <- eligible[eligible$end+12L<=eligible$interview,]
code1 <- vapply(seq_len(nrow(d)),function(i)code_at(d,i,1L),integer(1))
code12 <- vapply(seq_len(nrow(d)),function(i)code_at(d,i,12L),integer(1))
d$status_month_1 <- mapply(status,code1,d$method_code)
d$status_month_12 <- mapply(status,code12,d$method_code)
joint <- aggregate(d$wt,list(month_1=d$status_month_1,month_12=d$status_month_12),sum)
names(joint)[3] <- 'weighted_events'
joint$share_of_common_cohort_pct <- 100*joint$weighted_events/sum(d$wt)
joint$observed_ending_events_n <- nrow(d)
write.csv(joint,file.path(out,'nigeria_actionable_post_ending_transitions.csv'),row.names=FALSE)
print(z)

# Ethiopia's earlier pathway slides follow endings for any reason other than
# wanted pregnancy and partner disapproval. Reproduce that broader intermediate
# cohort separately so it is not confused with the actionable-only follow-up.
eligible <- e[e$discontinued & e$exposure<=12 &
  !(e$reason_code %in% c(2L,3L)),]
stopifnot(nrow(eligible)>1000L)
rows <- list()
for(k in c(1L,12L)){
  d <- eligible[eligible$end+k<=eligible$interview,]
  next_code <- vapply(seq_len(nrow(d)),function(i)code_at(d,i,k),integer(1))
  d$status <- mapply(status,next_code,d$method_code)
  tab <- aggregate(d$wt,list(status=d$status),sum)
  tab$month_after_ending <- k
  tab$percent <- 100*tab$x/sum(d$wt)
  tab$observed_ending_events_n <- nrow(d)
  tab$weighted_ending_events <- sum(d$wt)
  names(tab)[names(tab)=='x'] <- 'weighted_events'
  rows[[as.character(k)]] <- tab
}
selected <- do.call(rbind,rows)
selected <- selected[,c('month_after_ending','status','weighted_events','percent',
  'observed_ending_events_n','weighted_ending_events')]
write.csv(selected,file.path(out,'nigeria_selected_reason_post_ending_pathways.csv'),row.names=FALSE)
print(selected)
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 12_nigeria_all_reason_bridge.R
# LANGUAGE: R
MODULES[["12_nigeria_all_reason_bridge.R"]] <- list(
 language="R",
 packaged_sha256="9c504dcb9e6d8bd21ec7e7c1374726f15fd71588b84587d2960dd64541f4d945",
 args=character(),
 code=r"-----(#!/usr/bin/env Rscript
# Reproduce the Ethiopia presentation's sequence for the Nigeria modern-method
# cohort: all-cause first-year risk, a selected-reason intermediate estimate
# (wanted pregnancy and partner disapproval remain competing events), and then
# the narrower potentially actionable cause set. The same episodes, weights,
# delayed entry, and multiple-decrement life-table denominator are used at all
# three stages. This is separate from the official all-methods Table 7.12 row.
root <- Sys.getenv("NIGERIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
full_ir <- readRDS(file.path(root,'Data/raw_dhs_ir/NG2024DHS__NGIR8BDT__IR_raw.rds'))
full_frame <- unique(data.frame(cluster=as.numeric(full_ir$v021),stratum=as.numeric(full_ir$v022)))

support <- file.path(root,'output/Supporting_data')
e <- readRDS(file.path(root,'Data/Derived/nigeria_2024_modern_episodes.rds'))
zones <- c('North West','North East','North Central','South East','South South','South West')
methods <- c('Injectables','Implants','Pill','IUD','Other modern')
labels <- c('Method failure','Wanted pregnancy','Other fertility-related',
  'Changes in menstrual bleeding','Other side effects/health',
  'Wanted more effective method','Access/cost/convenience',
  'Partner disapproved','Other recorded reasons')
actionable_ids <- c(1L,4L,5L,6L,7L)
selected_ids <- setdiff(1:9,c(2L,8L))
scopes <- list(National=rep(TRUE,nrow(e)))
for(z in zones)scopes[[z]] <- e$zone_name==z
for(m in methods)scopes[[paste0('National: ',m)]] <- e$method_group==m
for(z in zones)for(m in methods)scopes[[paste0(z,': ',m)]] <-
  e$zone_name==z & e$method_group==m

estimate <- function(d,w=d$wt){
  survival <- 1
  cif <- numeric(9)
  rows <- vector('list',12)
  for(t in 1:12){
    at <- d$entry<t & d$exposure>=t
    risk <- sum(w[at])
    if(risk<=0){
      rows[[t]] <- data.frame(month=t,all_reason_pct=100*sum(cif),
        selected_reason_pct=100*sum(cif[selected_ids]),
        actionable_pct=100*sum(cif[actionable_ids]))
      next
    }
    ended <- at & d$exposure==t & d$discontinued
    hazard <- vapply(1:9,function(k)sum(w[ended & d$reason==k])/risk,numeric(1))
    cif <- cif+survival*hazard
    survival <- survival*(1-sum(hazard))
    rows[[t]] <- data.frame(month=t,all_reason_pct=100*sum(cif),
      selected_reason_pct=100*sum(cif[selected_ids]),
      actionable_pct=100*sum(cif[actionable_ids]))
  }
  list(monthly=do.call(rbind,rows),causes=100*cif)
}

time_rows <- list(); reason_rows <- list()
for(scope in names(scopes)){
  d <- e[scopes[[scope]],]
  if(!nrow(d))next
  fit <- estimate(d)
  t <- fit$monthly[fit$monthly$month %in% c(3,6,9,12),]
  t$scope <- scope
  t$eligible_episodes_n <- nrow(d)
  t$weighted_episodes <- sum(d$wt)
  t$all_reason_endings_n <- sum(d$discontinued & d$exposure<=12)
  time_rows[[scope]] <- t
  total <- sum(fit$causes)
  reason_rows[[scope]] <- data.frame(scope=scope,reason=labels,
    cause_specific_12_month_pct=fit$causes,
    share_among_all_discontinuation_pct=if(total>0)100*fit$causes/total else NA_real_,
    eligible_episodes_n=nrow(d),all_reason_endings_n=t$all_reason_endings_n[1])
}
times <- do.call(rbind,time_rows)
reason <- do.call(rbind,reason_rows)
rownames(times) <- rownames(reason) <- NULL

# Survey-design intervals for the all-cause geographic comparison. Resample
# PSUs within strata; all episodes contributed by a woman move together.
frame <- full_frame; frame$id <- seq_len(nrow(frame))
groups <- split(frame$id,frame$stratum)
stopifnot(!anyDuplicated(frame$cluster),all(lengths(groups)>1L))
B <- as.integer(Sys.getenv('NIGERIA_ALL_REASON_BOOTSTRAP_REPS','300'))
draws <- matrix(NA_real_,B,length(zones)+1L,
  dimnames=list(NULL,c('National',zones)))
selected_draws <- draws
for(b in seq_len(B)){
  set.seed(20261022L+b)
  mult <- numeric(nrow(frame))
  for(ids in groups){
    n <- length(ids)
    mult[ids] <- n/(n-1)*tabulate(sample.int(n,n-1,replace=TRUE),nbins=n)
  }
  lookup <- setNames(mult,frame$cluster)
  for(z in colnames(draws)){
    d <- e[scopes[[z]],]
    v <- estimate(d,d$wt*lookup[as.character(d$cluster)])$monthly
    draws[b,z] <- v$all_reason_pct[12]
    selected_draws[b,z] <- v$selected_reason_pct[12]
  }
}
for(z in colnames(draws)){
  selected <- times$scope==z & times$month==12
  times$all_reason_ci_low[selected] <- quantile(draws[,z],.025,na.rm=TRUE)
  times$all_reason_ci_high[selected] <- quantile(draws[,z],.975,na.rm=TRUE)
  times$selected_reason_ci_low[selected] <- quantile(selected_draws[,z],.025,na.rm=TRUE)
  times$selected_reason_ci_high[selected] <- quantile(selected_draws[,z],.975,na.rm=TRUE)
}
write.csv(times,file.path(support,'nigeria_modern_all_reason_timepoints.csv'),row.names=FALSE)
write.csv(reason,file.path(support,'nigeria_modern_all_reason_reason_mix.csv'),row.names=FALSE)
cat('National all-cause / selected / actionable:',
  unlist(times[times$scope=='National' & times$month==12,
    c('all_reason_pct','selected_reason_pct','actionable_pct')]),'\n')
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 13_nigeria_all_reason_models.R
# LANGUAGE: R
MODULES[["13_nigeria_all_reason_models.R"]] <- list(
 language="R",
 packaged_sha256="aff12d8e00e73d846029b09cd2047ff339b2a23ff93a7150a3027c9881690906",
 args=character(),
 code=r"-----(#!/usr/bin/env Rscript
# All-reason counterpart of the Nigeria actionable episode-month models.
# Every observed modern-method month contributes until its original-method
# ending or censoring. The binary event is ANY ending, including desired
# pregnancy, partner disapproval and method-related reasons. This supports the
# opening all-cause subgroup and regional slides used in Ethiopia before the
# presentation narrows to selected/program-actionable causes.
root <- Sys.getenv("NIGERIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
full_ir <- readRDS(file.path(root,'Data/raw_dhs_ir/NG2024DHS__NGIR8BDT__IR_raw.rds'))
full_frame <- unique(data.frame(cluster=as.numeric(full_ir$v021),stratum=as.numeric(full_ir$v022)))

derived <- file.path(root,'Data/Derived')
support <- file.path(root,'output/Supporting_data')
e <- readRDS(file.path(derived,'nigeria_2024_model_episode_covariates.rds'))
person <- readRDS(file.path(derived,'nigeria_2024_person_month.rds'))
person$ended <- as.integer(person$outcome!='continue')
stopifnot(nrow(e)==8341L,all(person$ended %in% 0:1))

f1 <- ended~month+method_group+zone_name
f2 <- ended~month+method_group+zone_name+age_group+parity_group+
  marital_group+education+wealth+residence+start_year
fit <- function(formula,wts){
  person$fit_weight <- wts
  suppressWarnings(glm(formula,data=person,family=binomial(),weights=fit_weight,
    control=glm.control(maxit=75)))
}
m1 <- fit(f1,person$wt)
m2 <- fit(f2,person$wt)
if(!m1$converged||!m2$converged)stop('All-reason model did not converge')
saveRDS(m1,file.path(derived,'nigeria_all_reason_model_1.rds'))
saveRDS(m2,file.path(derived,'nigeria_all_reason_model_2.rds'))

standard <- e[e$entry==0L,]
zones <- levels(e$zone_name)
groups <- list('National'=rep(TRUE,nrow(standard)))
for(z in zones)groups[[z]] <- rep(TRUE,nrow(standard))
predict_risk <- function(model,d,weights=d$wt){
  survival <- rep(1,nrow(d))
  for(t in 1:12){
    d$month <- factor(t,levels=1:12)
    p <- predict(model,newdata=d,type='response')
    survival <- survival*(1-p)
  }
  100*weighted.mean(1-survival,weights)
}
zone_prediction <- function(model,zone,weights=standard$wt){
  d <- standard
  if(zone!='National')d$zone_name <- factor(zone,levels=zones)
  predict_risk(model,d,weights)
}
all_times <- read.csv(file.path(support,'nigeria_modern_all_reason_timepoints.csv'))
zone_rows <- do.call(rbind,lapply(c('National',zones),function(z){
  raw <- all_times[all_times$scope==z & all_times$month==12,]
  data.frame(zone=z,eligible_episodes_n=raw$eligible_episodes_n,
    unadjusted_pct=raw$all_reason_pct,
    unadjusted_low=raw$all_reason_ci_low,
    unadjusted_high=raw$all_reason_ci_high,
    model_1_pct=zone_prediction(m1,z),model_2_pct=zone_prediction(m2,z))
}))

# Adjusted subgroup probabilities are marginal predictions for the common
# observed-start cohort with the named covariate set to each category. They
# describe model-adjusted associations, not a causal change to those women.
subgroups <- c('age_group','parity_group','marital_group','education',
  'wealth','residence')
subgroup_rows <- list()
for(v in subgroups)for(level in levels(e[[v]])){
  d <- standard
  d[[v]] <- factor(level,levels=levels(e[[v]]))
  subgroup_rows[[length(subgroup_rows)+1L]] <- data.frame(
    covariate=v,category=level,adjusted_12_month_pct=predict_risk(m2,d))
}
subgroup_rows <- do.call(rbind,subgroup_rows)

# Stratified PSU bootstrap for standardized zone and subgroup intervals. Each
# sampled PSU carries all episodes contributed by women in that cluster.
B <- as.integer(Sys.getenv('NIGERIA_ALL_REASON_MODEL_BOOTSTRAP_REPS','300'))
frame <- full_frame;frame$id <- seq_len(nrow(frame))
strata <- split(frame$id,frame$stratum)
stopifnot(!anyDuplicated(frame$cluster),all(lengths(strata)>1L))
zone_draws <- matrix(NA_real_,B,nrow(zone_rows)*2L)
subgroup_draws <- matrix(NA_real_,B,nrow(subgroup_rows))
for(b in seq_len(B)){
  set.seed(20261023L+b)
  mult <- numeric(nrow(frame))
  for(ids in strata){
    n <- length(ids)
    mult[ids] <- n/(n-1)*tabulate(sample.int(n,n-1,replace=TRUE),nbins=n)
  }
  lookup <- setNames(mult,frame$cluster)
  pw <- person$wt*lookup[as.character(person$cluster)]
  sw <- standard$wt*lookup[as.character(standard$cluster)]
  a <- tryCatch(fit(f1,pw),error=function(err)NULL)
  bfit <- tryCatch(fit(f2,pw),error=function(err)NULL)
  if(is.null(a)||is.null(bfit)||!a$converged||!bfit$converged)next
  for(j in seq_len(nrow(zone_rows))){
    z <- zone_rows$zone[j]
    zone_draws[b,j] <- zone_prediction(a,z,sw)
    zone_draws[b,j+nrow(zone_rows)] <- zone_prediction(bfit,z,sw)
  }
  for(j in seq_len(nrow(subgroup_rows))){
    d <- standard
    v <- subgroup_rows$covariate[j]
    d[[v]] <- factor(subgroup_rows$category[j],levels=levels(e[[v]]))
    subgroup_draws[b,j] <- predict_risk(bfit,d,sw)
  }
}
if(sum(complete.cases(zone_draws))<ceiling(.9*B))stop('Too few all-reason model bootstrap refits')
for(j in seq_len(nrow(zone_rows))){
  zone_rows$model_1_low[j] <- quantile(zone_draws[,j],.025,na.rm=TRUE)
  zone_rows$model_1_high[j] <- quantile(zone_draws[,j],.975,na.rm=TRUE)
  k <- j+nrow(zone_rows)
  zone_rows$model_2_low[j] <- quantile(zone_draws[,k],.025,na.rm=TRUE)
  zone_rows$model_2_high[j] <- quantile(zone_draws[,k],.975,na.rm=TRUE)
}
for(j in seq_len(nrow(subgroup_rows))){
  subgroup_rows$ci_low[j] <- quantile(subgroup_draws[,j],.025,na.rm=TRUE)
  subgroup_rows$ci_high[j] <- quantile(subgroup_draws[,j],.975,na.rm=TRUE)
}
write.csv(zone_rows,file.path(support,'nigeria_all_reason_zone_models.csv'),row.names=FALSE)
write.csv(subgroup_rows,file.path(support,'nigeria_all_reason_adjusted_subgroups.csv'),row.names=FALSE)
cat('All-reason adjusted zone/subgroup output saved:',nrow(zone_rows),nrow(subgroup_rows),'rows\n')
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 15_nigeria_initiation_mix.R
# LANGUAGE: R
MODULES[["15_nigeria_initiation_mix.R"]] <- list(
  language="R",
  original_sha256="98fc88f596b7ad0010eca101cf8da3b4795327341b055a102cc505a40db2d33e",
  packaged_sha256="98fc88f596b7ad0010eca101cf8da3b4795327341b055a102cc505a40db2d33e",
  args=character(),
  code=r"-----(#!/usr/bin/env Rscript
# Nigeria counterpart of the Ethiopia initiation-mix diagnostic. These are
# weighted, observed calendar starts, not current use (v312) and not a life-
# table denominator. The 2024 calendar year is incomplete under the DHS
# 3–62-month analysis window and is therefore flagged rather than interpreted
# as a complete annual trend.
root <- Sys.getenv("NIGERIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
e <- readRDS(file.path(root,'Data/Derived/nigeria_2024_table_7_12_episodes.rds'))
e <- e[e$entry==0L,]
modern <- c(1L,2L,3L,5L,6L,7L,11L,13L,14L,15L,17L,18L,19L,20L)
e$method_start <- 'Non-modern methods'
e$method_start[e$method_code %in% modern] <- 'Other modern'
e$method_start[e$method_code==1L] <- 'Pill'
e$method_start[e$method_code==2L] <- 'IUD'
e$method_start[e$method_code==3L] <- 'Injectables'
e$method_start[e$method_code==11L] <- 'Implants'
e$method_start[e$method_code==16L] <- 'Emergency contraception'
e$year <- (e$start-1L)%/%12L+1900L
methods <- c('Injectables','Implants','Pill','IUD','Emergency contraception',
  'Other modern','Non-modern methods')
scope <- c('Overall',as.character(2021:2024))
rows <- list()
for(s in scope){
  d <- if(s=='Overall')e else e[e$year==as.integer(s),]
  total <- sum(d$wt)
  for(m in methods){
    selected <- d$method_start==m
    rows[[length(rows)+1L]] <- data.frame(scope=s,method=m,
      start_share_pct=100*sum(d$wt[selected])/total,
      weighted_starts=sum(d$wt[selected]),observed_starts_n=sum(selected),
      denominator_weighted_starts=total,denominator_observed_starts_n=nrow(d),
      incomplete_year=s=='2024')
  }
}
z <- do.call(rbind,rows)
stopifnot(max(abs(aggregate(start_share_pct~scope,z,sum)$start_share_pct-100))<1e-8)
write.csv(z,file.path(root,'output/Supporting_data/nigeria_initiation_mix_overall_by_year.csv'),row.names=FALSE)

# For the regional presentation, use the same denominator as Ethiopia's
# regional initiation-mix and paired start-share figures: ALL observed method
# starts in that geography. This includes non-modern methods and EC. It is
# deliberately distinct from the modern-method episode cohort used for the
# discontinuation probabilities on the paired bars.
zone_names <- c('North West','North East','North Central','South East',
  'South South','South West')
e$zone_name <- zone_names[e$zone]
zone_rows <- list()
for (zone in c('National',zone_names)) {
  d <- if (zone=='National') e else e[e$zone_name==zone,]
  denominator <- sum(d$wt)
  for (method in methods) {
    selected <- d$method_start==method
    zone_rows[[length(zone_rows)+1L]] <- data.frame(
      scope=zone, method=method, start_share_pct=100*sum(d$wt[selected])/denominator,
      weighted_starts=sum(d$wt[selected]), observed_starts_n=sum(selected),
      denominator_weighted_starts=denominator,
      denominator_observed_starts_n=nrow(d))
  }
}
zone_mix <- do.call(rbind,zone_rows)
stopifnot(max(abs(aggregate(start_share_pct~scope,zone_mix,sum)$start_share_pct-100))<1e-8)
write.csv(zone_mix,file.path(root,'output/Supporting_data/nigeria_zone_all_method_start_mix.csv'),row.names=FALSE)
print(z[z$scope=='Overall',c('method','start_share_pct')],row.names=FALSE)
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 17_nigeria_selected_reason_models.R
# LANGUAGE: R
MODULES[["17_nigeria_selected_reason_models.R"]] <- list(
 language="R",
 packaged_sha256="d62de81080f6ad5412bf11142d6f54c395530cedc6abada99ea0eae860fbb06c",
 args=character(),
 code=r"-----(#!/usr/bin/env Rscript
# Ethiopia-style selected-reason counterpart for Nigeria. The event is ending
# for any recorded reason except wanted pregnancy (calendar code 2) or partner
# disapproval (code 3). Those two endings remain competing events: they are in
# the initial episode cohort and leave the risk set when they occur.
root <- Sys.getenv("NIGERIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
full_ir <- readRDS(file.path(root,'Data/raw_dhs_ir/NG2024DHS__NGIR8BDT__IR_raw.rds'))
full_frame <- unique(data.frame(cluster=as.numeric(full_ir$v021),stratum=as.numeric(full_ir$v022)))

derived <- file.path(root,'Data/Derived')
support <- file.path(root,'output/Supporting_data')
if(!requireNamespace('nnet',quietly=TRUE))stop('nnet package is required')
e <- readRDS(file.path(derived,'nigeria_2024_model_episode_covariates.rds'))
person <- readRDS(file.path(derived,'nigeria_2024_person_month.rds'))
observed_months <- pmax(0L,pmin(12L,e$exposure)-e$entry)
idx <- rep(seq_len(nrow(e)),observed_months)
month <- unlist(Map(function(first,n)seq.int(first+1L,length.out=n),
  e$entry,observed_months),use.names=FALSE)
stopifnot(length(idx)==nrow(person),length(month)==nrow(person))
end <- e$discontinued[idx] & month==e$exposure[idx]
person$selected_outcome <- factor(ifelse(!end,'continue',
  ifelse(e$reason_code[idx] %in% c(2L,3L),'competing','selected')),
  levels=c('continue','selected','competing'))
stopifnot(!anyNA(person$selected_outcome))

f1 <- selected_outcome~month+method_group+zone_name
f2 <- selected_outcome~month+method_group+zone_name+age_group+parity_group+
  marital_group+education+wealth+residence+start_year
fit <- function(formula,weights){
  person$fit_weight <- weights
  m <- nnet::multinom(formula,data=person,weights=fit_weight,trace=FALSE,
    maxit=350,MaxNWts=10000)
  if(m$convergence!=0L)stop('Selected-reason model failed to converge')
  m
}
m1 <- fit(f1,person$wt)
m2 <- fit(f2,person$wt)
saveRDS(m1,file.path(derived,'nigeria_selected_reason_model_1.rds'))
saveRDS(m2,file.path(derived,'nigeria_selected_reason_model_2.rds'))

reference <- e[e$entry==0L,]
zones <- levels(e$zone_name)
predict_cif <- function(model,data=reference,weights=data$wt){
  d <- data
  survival <- rep(1,nrow(d)); risk <- numeric(nrow(d))
  for(t in 1:12){
    d$month <- factor(t,levels=1:12)
    prob <- predict(model,newdata=d,type='probs')
    risk <- risk+survival*prob[,'selected']
    survival <- survival*prob[,'continue']
  }
  100*weighted.mean(risk,weights)
}
zone_prediction <- function(model,z,weights=reference$wt){
  d <- reference
  if(z!='National')d$zone_name <- factor(z,levels=zones)
  predict_cif(model,d,weights)
}
all_times <- read.csv(file.path(support,'nigeria_modern_all_reason_timepoints.csv'))
zone_rows <- do.call(rbind,lapply(c('National',zones),function(z){
  raw <- all_times[all_times$scope==z & all_times$month==12,]
  data.frame(zone=z,eligible_episodes_n=raw$eligible_episodes_n,
    unadjusted_pct=raw$selected_reason_pct,
    unadjusted_low=raw$selected_reason_ci_low,
    unadjusted_high=raw$selected_reason_ci_high,
    model_1_pct=zone_prediction(m1,z),model_2_pct=zone_prediction(m2,z))
}))
subgroup_vars <- c('age_group','parity_group','marital_group','education',
  'wealth','residence')
subgroup_rows <- list()
for(v in subgroup_vars)for(level in levels(e[[v]])){
  d <- reference
  d[[v]] <- factor(level,levels=levels(e[[v]]))
  subgroup_rows[[length(subgroup_rows)+1L]] <- data.frame(
    covariate=v,category=level,adjusted_12_month_pct=predict_cif(m2,d))
}
subgroup_rows <- do.call(rbind,subgroup_rows)

# Survey-design uncertainty: resample PSUs within each sample stratum and
# retain all episodes from every sampled PSU, including repeated respondents.
B <- as.integer(Sys.getenv('NIGERIA_SELECTED_MODEL_BOOTSTRAP_REPS','300'))
frame <- full_frame;frame$id <- seq_len(nrow(frame))
strata <- split(frame$id,frame$stratum)
stopifnot(!anyDuplicated(frame$cluster),all(lengths(strata)>1L))
zone_draws <- matrix(NA_real_,B,nrow(zone_rows)*2L)
subgroup_draws <- matrix(NA_real_,B,nrow(subgroup_rows))
one <- function(b){
 Z<-rep(NA_real_,nrow(zone_rows)*2L); S<-rep(NA_real_,nrow(subgroup_rows))
  set.seed(20261024L+b)
  mult <- numeric(nrow(frame))
  for(ids in strata){
    n <- length(ids)
    mult[ids] <- n/(n-1)*tabulate(sample.int(n,n-1,replace=TRUE),nbins=n)
  }
  lookup <- setNames(mult,frame$cluster)
  pw <- person$wt*lookup[as.character(person$cluster)]
  sw <- reference$wt*lookup[as.character(reference$cluster)]
  a <- tryCatch(fit(f1,pw),error=function(err)NULL)
  bfit <- tryCatch(fit(f2,pw),error=function(err)NULL)
  if(is.null(a)||is.null(bfit))return(list(Z=Z,S=S))
  for(j in seq_len(nrow(zone_rows))){
    z <- zone_rows$zone[j]
    Z[j] <- zone_prediction(a,z,sw)
    Z[j+nrow(zone_rows)] <- zone_prediction(bfit,z,sw)
  }
  for(j in seq_len(nrow(subgroup_rows))){
    d <- reference
    v <- subgroup_rows$covariate[j]
    d[[v]] <- factor(subgroup_rows$category[j],levels=levels(e[[v]]))
    S[j] <- predict_cif(bfit,d,sw)
  }
return(list(Z=Z,S=S))
}
drawlist<-parallel::mclapply(seq_len(B),one,mc.cores=4L,mc.preschedule=FALSE)
zone_draws<-do.call(rbind,lapply(drawlist,`[[`,"Z"));subgroup_draws<-do.call(rbind,lapply(drawlist,`[[`,"S"))

if(sum(complete.cases(zone_draws))<ceiling(.9*B))stop('Too few selected-reason bootstrap refits')
for(j in seq_len(nrow(zone_rows))){
  zone_rows$model_1_low[j] <- quantile(zone_draws[,j],.025,na.rm=TRUE)
  zone_rows$model_1_high[j] <- quantile(zone_draws[,j],.975,na.rm=TRUE)
  k <- j+nrow(zone_rows)
  zone_rows$model_2_low[j] <- quantile(zone_draws[,k],.025,na.rm=TRUE)
  zone_rows$model_2_high[j] <- quantile(zone_draws[,k],.975,na.rm=TRUE)
}
for(j in seq_len(nrow(subgroup_rows))){
  subgroup_rows$ci_low[j] <- quantile(subgroup_draws[,j],.025,na.rm=TRUE)
  subgroup_rows$ci_high[j] <- quantile(subgroup_draws[,j],.975,na.rm=TRUE)
}
write.csv(zone_rows,file.path(support,'nigeria_selected_reason_zone_models.csv'),row.names=FALSE)
write.csv(subgroup_rows,file.path(support,'nigeria_selected_reason_adjusted_subgroups.csv'),row.names=FALSE)
cat('Selected-reason adjusted zone/subgroup output saved:',nrow(zone_rows),nrow(subgroup_rows),'rows\n')
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 22_nigeria_landmark_support.R
# LANGUAGE: R
MODULES[["22_nigeria_landmark_support.R"]] <- list(
  language="R",
  original_sha256="e3bceabf4adf1d6171f3f54bfac7b5287b8e5046fc4dd62911fb303160b7ec87",
  packaged_sha256="e3bceabf4adf1d6171f3f54bfac7b5287b8e5046fc4dd62911fb303160b7ec87",
  args=character(),
  code=r"-----(#!/usr/bin/env Rscript
# Audit historical landmarks available for a prospective 12-month trajectory.
# A landmark is a month of current modern use at an observed duration since
# starting the original method, with 12 further calendar months observed.
root <- Sys.getenv("NIGERIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
events <- readRDS(file.path(root,'Data/Derived/nigeria_2024_calendar_events.rds'))
ir <- readRDS(file.path(root,'Data/raw_dhs_ir/NG2024DHS__NGIR8BDT__IR_raw.rds'))
modern <- c(1L,2L,3L,5L,6L,7L,11L,13L,14L,15L,17L,18L,19L,20L)
grp <- function(code) ifelse(code==3L,'Injectables',ifelse(code==11L,'Implants',ifelse(code==1L,'Pill',ifelse(code==2L,'IUD','Other modern'))))
br <- c(-1,3,6,12,24,36,48,60,Inf)
labs <- c('0–3','4–6','7–12','13–24','25–36','37–48','49–60','61+')
current <- ir[as.numeric(ir$v313)==3 & as.numeric(ir$v312)!=16,]
current$method <- grp(as.integer(current$v312))
current$bin <- cut(as.numeric(current$v337),br,labels=labs)
cat('CURRENT USERS BY METHOD AND DURATION\n')
print(with(current,table(method,bin)),quote=FALSE)
valid <- events[events$method_code %in% modern & events$start>events$calendar_start,]
land <- vector('list',nrow(valid))
for(i in seq_len(nrow(valid))){
  a <- valid[i,]
  ts <- seq.int(a$start,min(a$end,a$interview-15L))
  ts <- ts[ts>=a$calendar_start]
  if(length(ts)==0L) next
  land[[i]] <- data.frame(method=grp(a$method_code),duration=ts-a$start+1L,wt=a$wt)
}
land <- do.call(rbind,land[!vapply(land,is.null,logical(1))])
land$bin <- cut(land$duration-1L,br,labels=labs)
cat('HISTORICAL OBSERVED LANDMARKS WITH FOLLOW-UP\n')
print(with(land,table(method,bin)),quote=FALSE)
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 23_nigeria_current_user_switch_and_duration.R
# LANGUAGE: R
MODULES[["23_nigeria_current_user_switch_and_duration.R"]] <- list(
  language="R",
  original_sha256="f20383478e7b82fb7c7020c5d4243efec5179f553dd9bedb784cd59b4b311c6b",
  packaged_sha256="f20383478e7b82fb7c7020c5d4243efec5179f553dd9bedb784cd59b4b311c6b",
  args=character(),
  code=r"-----(#!/usr/bin/env Rscript
# Nigeria DHS 2024: transparent bridges from original-method endings to
# modern-use status among projected current users. This script does not
# estimate a causal effect of preventing discontinuation.
#
# Bridge A retains the earlier first-year life-table estimates, applies them
# to projected 2025 current-user counts, and subtracts observed direct
# modern-to-modern switches. It is illustrative because current users have
# already accrued varying months on their methods.
#
# Bridge B emulates a 12-month follow-up from historical calendar months in
# which a woman was using a modern method. Matching on method and elapsed
# duration, it estimates the chance that her original method ends for an
# actionable reason, that she immediately switches, and whether she uses any
# modern method 12 months after that landmark. It standardizes these risks to
# the weighted duration distribution of DHS 2024 current users, then applies
# them to the projected 2025 stock. This is descriptive and makes a strong
# stationarity assumption when transported from history to 2025–26.

root <- Sys.getenv("NIGERIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
out <- file.path(root,'output/Supporting_data')
data_dir <- file.path(root,'Data/Derived')
ir <- readRDS(file.path(root,'Data/raw_dhs_ir/NG2024DHS__NGIR8BDT__IR_raw.rds'))
episodes <- readRDS(file.path(data_dir,'nigeria_2024_modern_episodes.rds'))
calendar <- readRDS(file.path(data_dir,'nigeria_2024_calendar_events.rds'))
users <- read.csv(file.path(out,'nigeria_current_users_by_method_and_actionable_projection.csv'))
scenario <- read.csv(file.path(out,'nigeria_2026_mcpr_scenarios.csv'))
stopifnot(nrow(ir)==39050L,all(c('method','current_users_2025','illustrative_original_method_endings') %in% names(users)))

modern <- c(1L,2L,3L,5L,6L,7L,11L,13L,14L,15L,17L,18L,19L,20L)
methods <- c('Injectables','Implants','Pill','IUD','Other modern')
causes <- c('Method failure','Wanted more effective method','Changes in menstrual bleeding',
            'Other side effects/health','Access/cost/convenience')
method_group <- function(z) ifelse(z==3L,'Injectables',ifelse(z==11L,'Implants',
  ifelse(z==1L,'Pill',ifelse(z==2L,'IUD','Other modern'))))
cause_group <- function(z) ifelse(z==1L,causes[1],ifelse(z==7L,causes[2],
  ifelse(z==15L,causes[3],ifelse(z %in% c(4L,5L),causes[4],
  ifelse(z %in% c(6L,8L,10L),causes[5],NA_character_)))))
roundint <- function(z) as.integer(round(z))

# A. Projected 2025 stock × original-method life-table risk. The direct
# switch fraction is measured among observed actionable first-year endings.
episodes$actionable <- episodes$discontinued & episodes$exposure<=12 &
  episodes$reason_code %in% c(1L,4L,5L,6L,7L,8L,10L,15L)
endings <- episodes[episodes$actionable,]
endings$method <- method_group(endings$method_code)
endings$cause <- cause_group(endings$reason_code)
endings$direct_modern <- endings$next_code %in% modern
endings$direct_modern[is.na(endings$direct_modern)] <- FALSE
stopifnot(!anyNA(endings$cause))
bridge <- users[match(methods,users$method),c('method','current_users_2025',
  'actionable_first_year_risk_pct','illustrative_original_method_endings')]
bridge$observed_actionable_endings_n <- NA_integer_
bridge$direct_modern_switch_pct <- NA_real_
bridge$illustrative_direct_modern_switchers <- NA_real_
bridge$illustrative_not_directly_switching <- NA_real_
for(i in seq_len(nrow(bridge))){
  d <- endings[endings$method==bridge$method[i],]
  bridge$observed_actionable_endings_n[i] <- nrow(d)
  bridge$direct_modern_switch_pct[i] <- 100*sum(d$wt[d$direct_modern])/sum(d$wt)
  bridge$illustrative_direct_modern_switchers[i] <- bridge$illustrative_original_method_endings[i]*
    bridge$direct_modern_switch_pct[i]/100
  bridge$illustrative_not_directly_switching[i] <- bridge$illustrative_original_method_endings[i]-
    bridge$illustrative_direct_modern_switchers[i]
}
write.csv(bridge,file.path(out,'nigeria_switch_bridge_by_method.csv'),row.names=FALSE)

cause_bridge <- do.call(rbind,lapply(methods,function(m)do.call(rbind,lapply(causes,function(cause){
  d <- endings[endings$method==m & endings$cause==cause,]
  base <- read.csv(file.path(out,'nigeria_current_users_actionable_by_cause.csv'))
  projected <- base$illustrative_users[base$method==m & base$reason==cause]
  stopifnot(length(projected)==1L)
  frac <- if(nrow(d)>0)sum(d$wt[d$direct_modern])/sum(d$wt) else 0
  data.frame(method=m,reason=cause,observed_endings_n=nrow(d),
    illustrative_original_method_endings=projected,direct_modern_switch_pct=100*frac,
    illustrative_direct_modern_switchers=projected*frac,
    illustrative_not_directly_switching=projected*(1-frac))
}))))
# Calibrate the cause-specific allocations to the independently estimated
# method total, so every cause table reconciles exactly to the bridge above.
# This preserves the relative observed switching pattern across causes.
for(m in methods){
  ix <- which(cause_bridge$method==m)
  target <- bridge$illustrative_direct_modern_switchers[bridge$method==m]
  allocated <- sum(cause_bridge$illustrative_direct_modern_switchers[ix])
  if(allocated>0){
    cause_bridge$illustrative_direct_modern_switchers[ix] <-
      cause_bridge$illustrative_direct_modern_switchers[ix]*target/allocated
  }
  cause_bridge$illustrative_not_directly_switching[ix] <-
    cause_bridge$illustrative_original_method_endings[ix]-
    cause_bridge$illustrative_direct_modern_switchers[ix]
  cause_bridge$direct_modern_switch_pct[ix] <-
    100*cause_bridge$illustrative_direct_modern_switchers[ix]/
    cause_bridge$illustrative_original_method_endings[ix]
}
write.csv(cause_bridge,file.path(out,'nigeria_switch_bridge_by_method_cause.csv'),row.names=FALSE)

# B. The retrospective calendar is recorded in month units. A landmark can
# be used only if a full 12 future calendar months are visible and the
# original modern-method start is visible (not left censored at calendar start).
# Follow-up uses months t+1 through t+12. At month 12, modern-to-modern
# switchers and later modern restarters are both counted as modern users.
by_woman <- split(seq_len(nrow(calendar)),calendar$woman_row)
eligible_spells <- calendar[calendar$method_code %in% modern &
  calendar$start>calendar$calendar_start,]
bins <- c(-1,3,6,12,24,36,48,60,Inf)
bin_labels <- c('0–3','4–6','7–12','13–24','25–36','37–48','49–60','61+')
records <- vector('list',nrow(eligible_spells))
for(i in seq_len(nrow(eligible_spells))){
  a <- eligible_spells[i,]
  last <- min(a$end,a$interview-15L)
  if(last<a$start) next
  landmark <- seq.int(a$start,last)
  future <- landmark+12L
  person_events <- calendar[by_woman[[as.character(a$woman_row)]],]
  next_event <- findInterval(future,person_events$start)
  stopifnot(all(next_event>0L),all(person_events$end[next_event]>=future))
  code12 <- person_events$method_code[next_event]
  action <- a$end<future & a$reason_code %in% c(1L,4L,5L,6L,7L,8L,10L,15L)
  direct <- action & a$next_code %in% modern
  direct[is.na(direct)] <- FALSE
  modern12 <- code12 %in% modern
  records[[i]] <- data.frame(woman_row=a$woman_row,method=method_group(a$method_code),
    duration_completed=landmark-a$start,wt=a$wt,actionable=action,
    ending_reason_code=ifelse(a$end<future,a$reason_code,NA_integer_),
    direct_switch=direct,modern_at_month12=modern12,
    actionable_nonmodern_at_month12=action & !modern12,
    actionable_modern_at_month12=action & modern12,
    cause=ifelse(action,cause_group(a$reason_code),NA_character_))
}
landmarks <- do.call(rbind,records[!vapply(records,is.null,logical(1))])
landmarks$duration_bin <- cut(landmarks$duration_completed,bins,labels=bin_labels)
saveRDS(landmarks,file.path(data_dir,'nigeria_historical_duration_landmarks.rds'))
stopifnot(nrow(landmarks)>50000L,!anyNA(landmarks$duration_bin),
  all(landmarks$direct_switch<=landmarks$actionable),
  all(landmarks$actionable_nonmodern_at_month12+landmarks$actionable_modern_at_month12==landmarks$actionable))

current <- ir[as.numeric(ir$v313)==3 & as.numeric(ir$v312)!=16,]
current$method <- method_group(as.integer(current$v312))
current$duration_completed <- as.numeric(current$v337)
current$duration_bin <- cut(current$duration_completed,bins,labels=bin_labels)
current$wt <- as.numeric(current$v005)/1e6
stopifnot(!anyNA(current$duration_bin),all(current$method %in% methods))

# No landmark with elapsed duration 61+ can have a complete following year
# inside the recorded calendar. The main scenario assigns the observed 37–60
# month risk to these long-duration users. This is an explicit extrapolation.
# We also retain the share of projected users who require that extrapolation.
outcome_cols <- c('actionable','direct_switch','actionable_nonmodern_at_month12',
                  'actionable_modern_at_month12','modern_at_month12')
estimate_bin <- function(d){
  c(n_landmarks=nrow(d),n_women=length(unique(d$woman_row)),
    setNames(vapply(outcome_cols,function(k)sum(d$wt*as.numeric(d[[k]]))/sum(d$wt),0.0),outcome_cols))
}
bin_rows <- list()
for(m in methods)for(b in bin_labels[1:7]){
  d <- landmarks[landmarks$method==m & landmarks$duration_bin==b,]
  cc <- current[current$method==m & current$duration_bin==b,]
  z <- estimate_bin(d)
  bin_rows[[length(bin_rows)+1L]] <- data.frame(method=m,duration_bin=b,
    current_users_n=nrow(cc),current_weight=sum(cc$wt),as.list(z),
    proxy_for_61plus=FALSE)
}
for(m in methods){
  d <- landmarks[landmarks$method==m & landmarks$duration_bin %in% c('37–48','49–60'),]
  cc <- current[current$method==m & current$duration_bin=='61+',]
  z <- estimate_bin(d)
  bin_rows[[length(bin_rows)+1L]] <- data.frame(method=m,duration_bin='61+',
    current_users_n=nrow(cc),current_weight=sum(cc$wt),as.list(z),
    proxy_for_61plus=TRUE)
}
duration_bins <- do.call(rbind,bin_rows)
write.csv(duration_bins,file.path(out,'nigeria_duration_landmark_support_and_risks.csv'),row.names=FALSE)

duration <- do.call(rbind,lapply(methods,function(m){
  z <- duration_bins[duration_bins$method==m,]
  stock <- users$current_users_2025[users$method==m]
  shares <- z$current_weight/sum(z$current_weight)
  risk <- function(k)sum(shares*z[[k]])
  gross <- stock*risk('actionable')
  direct <- stock*risk('direct_switch')
  modern_after <- stock*risk('actionable_modern_at_month12')
  nonmodern_after <- stock*risk('actionable_nonmodern_at_month12')
  data.frame(method=m,current_users_2025=stock,current_users_n=sum(z$current_users_n),
    current_users_61plus_n=z$current_users_n[z$duration_bin=='61+'],
    current_users_61plus_share_pct=100*shares[z$duration_bin=='61+'],
    actionable_ending_risk_next12_pct=100*risk('actionable'),
    projected_actionable_original_method_endings=gross,
    projected_direct_modern_switchers=direct,
    projected_not_directly_switching=gross-direct,
    projected_modern_at_month12_after_actionable=modern_after,
    projected_nonmodern_at_month12_after_actionable=nonmodern_after,
    descriptive_nonmodern_at_month12_pp=100*nonmodern_after/scenario$wra_2026[1])
}))
stopifnot(max(abs(duration$projected_actionable_original_method_endings-
    duration$projected_modern_at_month12_after_actionable-
    duration$projected_nonmodern_at_month12_after_actionable))<1e-5)
write.csv(duration,file.path(out,'nigeria_duration_aware_current_user_bridge.csv'),row.names=FALSE)

# Cause-specific endpoints use the same current-user duration weights.
cause_duration <- do.call(rbind,lapply(methods,function(m)do.call(rbind,lapply(causes,function(cause){
  current_bins <- duration_bins[duration_bins$method==m,]
  shares <- current_bins$current_weight/sum(current_bins$current_weight)
  results <- matrix(NA_real_,nrow=length(bin_labels),ncol=3)
  for(j in seq_along(bin_labels)){
    b <- bin_labels[j]
    observed_bins <- if(b=='61+') c('37–48','49–60') else b
    d <- landmarks[landmarks$method==m & landmarks$duration_bin %in% observed_bins,]
    flag <- !is.na(d$cause) & d$cause==cause
    results[j,] <- c(sum(d$wt*flag),sum(d$wt*flag*d$direct_switch),
      sum(d$wt*flag*(!d$modern_at_month12)))/sum(d$wt)
  }
  risk <- colSums(results*shares)
  stock <- users$current_users_2025[users$method==m]
  data.frame(method=m,reason=cause,current_users_2025=stock,
    projected_actionable_original_method_endings=stock*risk[1],
    projected_direct_modern_switchers=stock*risk[2],
    projected_nonmodern_at_month12=stock*risk[3])
}))))
for(m in methods){
  a <- cause_duration[cause_duration$method==m,]
  b <- duration[duration$method==m,]
  stopifnot(abs(sum(a$projected_actionable_original_method_endings)-b$projected_actionable_original_method_endings)<1e-5,
            abs(sum(a$projected_nonmodern_at_month12)-b$projected_nonmodern_at_month12)<1e-5)
}
write.csv(cause_duration,file.path(out,'nigeria_duration_aware_current_user_by_cause.csv'),row.names=FALSE)

scenario_bridge <- scenario[,c('scenario','mcpr_2026_pct','usual_users_2026','wra_2026')]
scenario_bridge$first_year_gross_endings <- sum(bridge$illustrative_original_method_endings)
scenario_bridge$first_year_not_directly_switching <- sum(bridge$illustrative_not_directly_switching)
scenario_bridge$duration_aware_actionable_endings <- sum(duration$projected_actionable_original_method_endings)
scenario_bridge$duration_aware_not_directly_switching <- sum(duration$projected_not_directly_switching)
scenario_bridge$duration_aware_nonmodern_at_month12 <- sum(duration$projected_nonmodern_at_month12_after_actionable)
scenario_bridge$descriptive_nonmodern_at_month12_pp <-
  100*scenario_bridge$duration_aware_nonmodern_at_month12/scenario_bridge$wra_2026
scenario_bridge$illustrative_mcpr_if_all_endpoint_users_retained <-
  scenario_bridge$mcpr_2026_pct+scenario_bridge$descriptive_nonmodern_at_month12_pp
write.csv(scenario_bridge,file.path(out,'nigeria_switch_duration_mcpr_scenarios.csv'),row.names=FALSE)
# Sensitivity to the unsupported 61+ duration group: replace its proxy with
# either the observed 37–48 or 49–60 month risk (the main estimate pools both).
long_sensitivity <- do.call(rbind,lapply(c('37–48','49–60'),function(proxy){
  total <- 0
  for(m in methods){
    z <- duration_bins[duration_bins$method==m,]
    shares <- z$current_weight/sum(z$current_weight)
    z$actionable_nonmodern_at_month12[z$duration_bin=='61+'] <-
      z$actionable_nonmodern_at_month12[z$duration_bin==proxy]
    total <- total + users$current_users_2025[users$method==m]*
      sum(shares*z$actionable_nonmodern_at_month12)
  }
  data.frame(proxy_for_61plus=proxy,projected_nonmodern_at_month12=total,
    illustrative_pp=100*total/scenario$wra_2026[1])
}))
write.csv(long_sensitivity,file.path(out,'nigeria_duration_61plus_sensitivity.csv'),row.names=FALSE)
cat('Historical landmarks:',nrow(landmarks),'from',length(unique(landmarks$woman_row)),
  'women. Current non-EC modern users:',nrow(current),'\n')
print(duration[,c('method','current_users_61plus_share_pct','actionable_ending_risk_next12_pct',
  'projected_actionable_original_method_endings','projected_nonmodern_at_month12_after_actionable')],row.names=FALSE)
print(scenario_bridge[,c('scenario','first_year_gross_endings','first_year_not_directly_switching',
  'duration_aware_actionable_endings','duration_aware_nonmodern_at_month12',
  'descriptive_nonmodern_at_month12_pp')],row.names=FALSE)
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 25_duration_aware_cause_pp_tables.R
# LANGUAGE: R
MODULES[["25_duration_aware_cause_pp_tables.R"]] <- list(
  language="R",
  original_sha256="f86676c094610444737b95e1fb33d544963c976dda20f4567209f48808eb79c1",
  packaged_sha256="f86676c094610444737b95e1fb33d544963c976dda20f4567209f48808eb79c1",
  args=character(),
  code=r"-----(# Recreate the method-by-cause percentage-point matrix from the duration-aware
# current-user analysis. The source CSV contains survey-derived projections of
# women who end their current method for an actionable reason and are not using
# any modern method 12 months after the current-use landmark. It has already
# accounted for subsequent modern switching and restarting.
#
# Run with Rscript from any directory. No extra packages are required.

args <- commandArgs(trailingOnly = FALSE)
file_arg <- args[grepl("^--file=", args)]
if (length(file_arg) != 1) stop("Run this file with Rscript")
script_path <- normalizePath(gsub("~\\+~", " ", sub("^--file=", "", file_arg)))
project <- dirname(dirname(script_path))
country <- "Nigeria"
support <- file.path(project, "output", "Supporting_data")

# Read the duration-aware projected counts and projected 2026 population.
cause_file <- file.path(support, paste0(tolower(country), "_duration_aware_current_user_by_cause.csv"))
scenario_file <- file.path(support, paste0(tolower(country), "_switch_duration_mcpr_scenarios.csv"))
causes <- read.csv(cause_file, check.names = FALSE, stringsAsFactors = FALSE)
scenarios <- read.csv(scenario_file, check.names = FALSE, stringsAsFactors = FALSE)
stopifnot(nrow(scenarios) >= 1, length(unique(scenarios$wra_2026)) == 1)
wra_2026 <- scenarios$wra_2026[1]

# Each cell's mCPR equivalent is its year-end count divided by women aged
# 15-49 in 2026. This is a descriptive maximum under perfect prevention of
# the associated ending, not a causal estimate of an intervention's effect.
causes$year_end_nonmodern <- as.numeric(causes$projected_nonmodern_at_month12)
causes$mcpr_equivalent_pp <- 100 * causes$year_end_nonmodern / wra_2026
causes$wra_2026 <- wra_2026
stopifnot(abs(sum(causes$year_end_nonmodern) -
              scenarios$duration_aware_nonmodern_at_month12[1]) < 1e-5)
stopifnot(abs(sum(causes$mcpr_equivalent_pp) -
              scenarios$descriptive_nonmodern_at_month12_pp[1]) < 1e-8)

out <- causes[c("method", "reason", "year_end_nonmodern", "mcpr_equivalent_pp", "wra_2026")]
output_file <- file.path(support, paste0(tolower(country), "_duration_aware_cause_pp_matrix.csv"))
write.csv(out, output_file, row.names = FALSE)
message("Saved ", output_file)
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 26_nigeria_actionable_method_zone_models.R
# LANGUAGE: R
MODULES[["26_nigeria_actionable_method_zone_models.R"]] <- list(
 language="R",
 packaged_sha256="87d3118103e0f2a3b857ea5b6c1af46ffb4dda68b9369dc6eca9f960acbe094b",
 args=character(),
 code=r"-----(#!/usr/bin/env Rscript
# Nigeria DHS 2024: within-method zone differences in first-year discontinuation
# for potentially actionable reasons. This is the Nigeria counterpart of the
# Ethiopia injectable/implant regional tests. Run scripts 01 and 03 first.
#
# Each risk set comprises eligible episodes of the stated original modern
# method. At an ending, actionable causes are the event of interest; every
# other reason is a competing event. Episodes observed after method initiation
# enter the monthly life table at their first observed month. The adjusted
# multinomial model uses one row per observed episode-month and includes month
# since method initiation, zone, age and parity at start, marital status,
# education, wealth, residence, and calendar start-year cohort. Region-specific
# predictions apply each zone coefficient to the same national distribution of
# observed-start episodes of that method. This standardizes composition but
# does not assume a program intervention or identify a causal zone effect.
#
# Survey uncertainty comes from resampling PSUs within DHS strata. Every
# episode from a selected PSU stays together, preserving repeated episodes
# from the same woman. Holm correction controls the 15 pairwise tests within
# each method and, separately, all 30 tests across the two methods.

root <- Sys.getenv("NIGERIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
full_ir <- readRDS(file.path(root,'Data/raw_dhs_ir/NG2024DHS__NGIR8BDT__IR_raw.rds'))
full_frame <- unique(data.frame(cluster=as.numeric(full_ir$v021),stratum=as.numeric(full_ir$v022)))

derived <- file.path(root, 'Data/Derived')
support <- file.path(root, 'output/Supporting_data')
stopifnot(requireNamespace('nnet', quietly=TRUE))
all_e <- readRDS(file.path(derived,'nigeria_2024_model_episode_covariates.rds'))
all_p <- readRDS(file.path(derived,'nigeria_2024_person_month.rds'))
zones <- c('North West','North East','North Central','South East',
           'South South','South West')
methods <- c('Injectables','Implants')
actionable <- c(1L,4L,5L,6L,7L,8L,10L,15L)
frame <- full_frame
frame$id <- seq_len(nrow(frame))
key <- function(s,c)paste(s,c,sep='::')
frame_key <- key(frame$stratum,frame$cluster)
all_e$psu_id <- frame$id[match(key(all_e$stratum,all_e$cluster),frame_key)]
all_p$psu_id <- frame$id[match(key(all_p$stratum,all_p$cluster),frame_key)]
stopifnot(!anyNA(all_e$psu_id),!anyNA(all_p$psu_id))
groups <- split(frame$id,frame$stratum)
stopifnot(all(lengths(groups)>1L))
K <- nrow(frame)
B <- as.integer(Sys.getenv('NIGERIA_METHOD_ZONE_REPS','400'))
stopifnot(B>=300L)

resample <- function(b) {
  set.seed(20261027L+b)
  mult <- numeric(K)
  for(ids in groups) {
    n <- length(ids)
    mult[ids] <- n/(n-1L)*
      tabulate(sample.int(n,n-1L,replace=TRUE),nbins=n)
  }
  mult
}
mults <- lapply(seq_len(B),resample)
formula <- outcome~month+zone_name+age_group+parity_group+
  marital_group+education+wealth+residence+start_year

get_method <- function(method) {
  e <- all_e[all_e$method_group==method,]
  p <- all_p[all_p$method_group==method,]
  e$zone_name <- factor(as.character(e$zone_name),levels=zones)
  p$zone_name <- factor(as.character(p$zone_name),levels=zones)
  ref <- e[e$entry==0L,]
  stopifnot(nrow(e)>1500,nrow(ref)>1200,
            all(table(e$zone_name)>=100))
  counts <- do.call(rbind,lapply(zones,function(z) {
    x <- e[e$zone_name==z,]
    selected <- x$discontinued & x$entry<x$exposure &
      x$exposure<=12L & x$reason_code %in% actionable
    data.frame(method=method,zone=z,eligible_episodes_n=nrow(x),
      actionable_endings_n=sum(selected),
      distinct_psus=length(unique(x$psu_id)))
  }))
  stopifnot(all(counts$actionable_endings_n>=20))

  # Cache weighted monthly risk sets by PSU. This is the same competing-risk
  # life-table formula used for the all-modern and Ethiopia method estimates.
  arrays <- lapply(zones,function(z) {
    risk <- ended <- chosen <- matrix(0,K,12L)
    scope <- e$zone_name==z
    for(t in 1:12) {
      at <- scope & e$entry<t & e$exposure>=t
      stop <- at & e$discontinued & e$exposure==t
      selected <- stop & e$reason_code %in% actionable
      for(item in c('risk','ended','chosen')) {
        mask <- switch(item,risk=at,ended=stop,chosen=selected)
        if(any(mask)) {
          sums <- rowsum(e$wt[mask],e$psu_id[mask],reorder=FALSE)
          target <- get(item)
          target[as.integer(rownames(sums)),t] <- sums[,1L]
          assign(item,target)
        }
      }
    }
    list(risk=risk,ended=ended,chosen=chosen)
  })
  names(arrays) <- zones
  cif <- function(a,mult) {
    R <- as.numeric(crossprod(mult,a$risk))
    E <- as.numeric(crossprod(mult,a$ended))
    C <- as.numeric(crossprod(mult,a$chosen))
    if(any(R<=0) || any(E>R+1e-6))return(NA_real_)
    s <- 1; f <- 0
    for(t in 1:12) {
      f <- f+s*C[t]/R[t]
      s <- s*(1-E[t]/R[t])
    }
    100*f
  }
  raw <- vapply(arrays,cif,numeric(1),mult=rep(1,K))
  raw_draws <- do.call(rbind,parallel::mclapply(mults,function(mult)
    vapply(arrays,cif,numeric(1),mult=mult),
    mc.cores=min(4L,parallel::detectCores()),mc.preschedule=FALSE))
  colnames(raw_draws) <- zones

  fit <- function(w) {
    p$boot_weight <- w
    out <- tryCatch(nnet::multinom(formula,data=p,weights=boot_weight,
      maxit=400,MaxNWts=10000,trace=FALSE,Hess=FALSE),
      error=function(err)NULL)
    if(is.null(out) || out$convergence!=0L)return(NULL)
    out
  }
  model <- fit(p$wt)
  if(is.null(model))stop('Full model did not converge for ',method)
  saveRDS(model,file.path(derived,
    paste0('nigeria_actionable_',tolower(method),'_zone_full_model.rds')))
  rhs <- delete.response(terms(formula))
  baseline <- ref
  baseline$zone_name <- factor(zones[1],levels=zones)
  X <- lapply(1:12,function(t) {
    baseline$month <- factor(t,levels=1:12)
    model.matrix(rhs,baseline)
  })
  one <- baseline[1,,drop=FALSE]
  one$month <- factor(1,levels=1:12)
  x0 <- model.matrix(rhs,one)[1,]
  offsets <- lapply(zones,function(z) {
    one$zone_name <- factor(z,levels=zones)
    model.matrix(rhs,one)[1,]-x0
  })
  predict_cif <- function(fit,weights) {
    beta <- coef(fit)
    if(!is.matrix(beta) ||
       !identical(rownames(beta),c('actionable','competing')) ||
       !identical(colnames(beta),colnames(X[[1]])))
       return(rep(NA_real_,length(zones)))
    A <- sapply(X,function(x)as.vector(x%*%beta['actionable',]))
    C <- sapply(X,function(x)as.vector(x%*%beta['competing',]))
    vapply(offsets,function(off) {
      a0 <- sum(off*beta['actionable',])
      c0 <- sum(off*beta['competing',])
      survival <- rep(1,nrow(ref))
      incidence <- rep(0,nrow(ref))
      for(t in 1:12) {
        aa <- exp(A[,t]+a0); cc <- exp(C[,t]+c0)
        denom <- 1+aa+cc
        incidence <- incidence+survival*aa/denom
        survival <- survival/denom
      }
      100*weighted.mean(incidence,weights)
    },numeric(1))
  }
  adjusted <- predict_cif(model,ref$wt)
  names(adjusted) <- zones
  adj_draws <- do.call(rbind,parallel::mclapply(seq_len(B),function(b) {
    mult <- mults[[b]]
    bm <- fit(p$wt*mult[p$psu_id])
    if(is.null(bm))return(rep(NA_real_,length(zones)))
    predict_cif(bm,ref$wt*mult[ref$psu_id])
  },mc.cores=min(4L,parallel::detectCores()),mc.preschedule=FALSE))
  colnames(adj_draws) <- zones
  valid <- complete.cases(adj_draws)
  cat(method,':',sum(valid),'of',B,'valid bootstrap refits\n')
  if(sum(valid)<ceiling(.9*B))stop('Insufficient bootstrap refits: ',method)
  write.csv(data.frame(replicate=seq_len(B),raw_draws,
    check.names=FALSE),file.path(support,paste0(
    'nigeria_actionable_',tolower(method),'_zone_raw_bootstrap.csv')),
    row.names=FALSE)
  write.csv(data.frame(replicate=seq_len(B),adj_draws,
    check.names=FALSE),file.path(support,paste0(
    'nigeria_actionable_',tolower(method),'_zone_full_bootstrap.csv')),
    row.names=FALSE)
  ci <- function(draws) {
    t(apply(draws,2,quantile,c(.025,.975),na.rm=TRUE))
  }
  rci <- ci(raw_draws); aci <- ci(adj_draws[valid,,drop=FALSE])
  point <- transform(counts,
    unadjusted_pct=as.numeric(raw[zones]),
    unadjusted_low=rci[,1],unadjusted_high=rci[,2],
    adjusted_pct=as.numeric(adjusted[zones]),
    adjusted_low=aci[,1],adjusted_high=aci[,2],
    valid_adjusted_bootstrap=sum(valid),
    precision_flag=ifelse(actionable_endings_n<30,
      'Exploratory: fewer than 30 actionable endings',''))
  pair_table <- function(stage,estimate,draws) {
    d <- draws[complete.cases(draws),,drop=FALSE]
    out <- do.call(rbind,lapply(combn(zones,2,simplify=FALSE),
      function(pair) {
        delta <- unname(estimate[pair[1]]-estimate[pair[2]])
        bd <- d[,pair[1]]-d[,pair[2]]
        se <- sd(bd)
        interval <- quantile(bd,c(.025,.975),names=FALSE)
        data.frame(method=method,stage=stage,zone_a=pair[1],
          zone_b=pair[2],difference_pp=delta,
          ci_low_pp=interval[1],ci_high_pp=interval[2],
          bootstrap_se_pp=se,p_value=2*pnorm(-abs(delta/se)),
          valid_bootstrap_draws=nrow(d))
      }))
    out$holm_p_within_method <- p.adjust(out$p_value,'holm')
    out$significant_5pct <- out$holm_p_within_method<.05
    out
  }
  pairs <- rbind(pair_table('Unadjusted',raw,raw_draws),
    pair_table('Fully adjusted',adjusted,adj_draws))
  global <- function(stage,estimate,draws) {
    d <- draws[complete.cases(draws),,drop=FALSE]
    ref <- zones[1]
    other <- zones[-1]
    contrast <- sweep(d[,other,drop=FALSE],1,d[,ref],'-')
    delta <- estimate[other]-estimate[ref]
    V <- cov(contrast)
    stat <- as.numeric(crossprod(delta,solve(V,delta)))
    data.frame(method=method,stage=stage,zones_tested=length(zones),
      wald_chisq=stat,df=length(other),
      p_value=pchisq(stat,df=length(other),lower.tail=FALSE),
      valid_bootstrap_draws=nrow(d))
  }
  list(point=point,pairs=pairs,
    global=rbind(global('Unadjusted',raw,raw_draws),
                 global('Fully adjusted',adjusted,adj_draws)))
}

out <- lapply(methods,get_method)
points <- do.call(rbind,lapply(out,`[[`,'point'))
pairs <- do.call(rbind,lapply(out,`[[`,'pairs'))
global <- do.call(rbind,lapply(out,`[[`,'global'))
for(stage in unique(pairs$stage)) {
  k <- pairs$stage==stage
  pairs$holm_p_across_methods[k] <- p.adjust(pairs$p_value[k],'holm')
}
write.csv(points,file.path(support,
  'nigeria_actionable_injectable_implant_zone_probabilities.csv'),row.names=FALSE)
write.csv(pairs,file.path(support,
  'nigeria_actionable_injectable_implant_zone_pairwise.csv'),row.names=FALSE)
write.csv(global,file.path(support,
  'nigeria_actionable_injectable_implant_zone_global.csv'),row.names=FALSE)
print(points,row.names=FALSE)
print(global,row.names=FALSE)
cat('Holm-significant within-method pairs:\n')
print(pairs[pairs$significant_5pct,],row.names=FALSE)
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 29_zone_method_mix_decomposition.R
# LANGUAGE: R
MODULES[["29_zone_method_mix_decomposition.R"]] <- list(
 language="R",
 packaged_sha256="7b15e1d652f97fe428bc1485734de0475bb692351e9ec34e3abb766bbdbea8d5",
 args=character(),
 code=r"-----(#!/usr/bin/env Rscript
# Nigeria DHS 2024: descriptive, symmetric decomposition of each pair of six
# zones. The denominator is eligible modern-method episodes excluding EC.
# Potentially actionable method endings are the event; all other endings are
# competing events. Weighted method shares use eligible episodes, including
# late-entry episodes. The constructed weighted mixture is not identical to
# the pooled life-table rate and should be labeled as such.
root <- Sys.getenv("NIGERIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
full_ir <- readRDS(file.path(root,'Data/raw_dhs_ir/NG2024DHS__NGIR8BDT__IR_raw.rds'))
full_frame <- unique(data.frame(cluster=as.numeric(full_ir$v021),stratum=as.numeric(full_ir$v022)))

d <- readRDS(file.path(root,'Data/Derived/nigeria_2024_modern_episodes.rds'))
d$four <- ifelse(d$method_group %in% c('IUD','Other modern'),
                 'IUD + other modern',d$method_group)
zones <- c('North Central','North East','North West','South East','South South','South West')
methods <- c('Injectables','Implants','Pill','IUD + other modern')
actionable <- c(1L,4L,5L,6L,7L,8L,10L,15L)
psu <- full_frame
psu$id <- seq_len(nrow(psu))
d$id <- match(d$cluster,psu$cluster)
ids <- split(psu$id,psu$stratum)
K <- nrow(psu)
cells <- list()
for(z in zones) for(m in methods){
  x <- d[d$zone_name==z & d$four==m,]
  count <- numeric(K)
  a <- rowsum(x$wt,x$id,reorder=FALSE)
  count[as.integer(rownames(a))] <- a[,1]
  risk <- all <- selected <- matrix(0,K,12)
  for(t in 1:12){
    at <- x$entry<t & x$exposure>=t
    end <- at & x$discontinued & x$exposure==t
    for(label in c('risk','all','selected')){
      mask <- switch(label,risk=at,all=end,
                     selected=end & x$reason_code %in% actionable)
      a <- rowsum(x$wt[mask],x$id[mask],reorder=FALSE)
      if(nrow(a)){
        mat <- get(label)
        mat[as.integer(rownames(a)),t] <- a[,1]
        assign(label,mat)
      }
    }
  }
  cells[[paste(z,m,sep='|')]] <- list(n=nrow(x),count=count,
     risk=risk,all=all,selected=selected,
     actionable_n=sum(x$discontinued & x$exposure<=12 &
       x$entry<x$exposure & x$reason_code %in% actionable))
}
cif <- function(cell,mult){
  R <- as.vector(crossprod(mult,cell$risk))
  A <- as.vector(crossprod(mult,cell$all))
  D <- as.vector(crossprod(mult,cell$selected))
  if(any(R<=0) || any(A>R+1e-6)) return(NA_real_)
  s <- 1; q <- 0
  for(t in 1:12){q <- q+s*D[t]/R[t];s <- s*(1-A[t]/R[t])}
  100*q
}
estimate <- function(mult){
  p <- q <- matrix(NA_real_,length(zones),length(methods),
                   dimnames=list(zones,methods))
  for(z in zones){
    n <- sapply(methods,function(m) sum(cells[[paste(z,m,sep='|')]]$count*mult))
    p[z,] <- n/sum(n)
    q[z,] <- sapply(methods,function(m) cif(cells[[paste(z,m,sep='|')]],mult))
  }
  out <- c()
  for(pair in combn(zones,2,simplify=FALSE)){
    a <- pair[1]; b <- pair[2]; key <- paste(a,b,sep=' vs ')
    mix <- sum((p[a,]-p[b,])*(q[a,]+q[b,])/2)
    within <- sum((q[a,]-q[b,])*(p[a,]+p[b,])/2)
    out[paste(key,'gap',sep='|')] <- mix+within
    out[paste(key,'mix',sep='|')] <- mix
    out[paste(key,'within',sep='|')] <- within
  }
  list(values=out,p=p,q=q)
}
point <- estimate(rep(1,K))
B <- as.integer(Sys.getenv('BOOTSTRAP_REPS','500'))
draws <- matrix(NA_real_,B,length(point$values),dimnames=list(NULL,names(point$values)))
for(b in seq_len(B)){
  set.seed(20261027+b)
  mult <- numeric(K)
  for(group in ids){
    n <- length(group)
    if(n>1) mult[group] <- n/(n-1)*tabulate(sample(group,n-1,replace=TRUE),nbins=K)[group]
    else mult[group] <- 1
  }
  draws[b,] <- estimate(mult)$values
}
lo <- apply(draws,2,quantile,probs=.025,na.rm=TRUE)
hi <- apply(draws,2,quantile,probs=.975,na.rm=TRUE)
pieces <- strsplit(names(point$values),'|',fixed=TRUE)
summary <- data.frame(pair=sapply(pieces,`[`,1),component=sapply(pieces,`[`,2),
 estimate_pp=as.vector(point$values),ci_low_pp=as.vector(lo),
 ci_high_pp=as.vector(hi),valid_draws=colSums(is.finite(draws)))
detail <- do.call(rbind,lapply(zones,function(z)
  do.call(rbind,lapply(methods,function(m)
    data.frame(zone=z,method=m,episode_share_pct=100*point$p[z,m],
      actionable_risk_pct=point$q[z,m],
      episodes_n=cells[[paste(z,m,sep='|')]]$n,
      actionable_endings_n=cells[[paste(z,m,sep='|')]]$actionable_n)))))
stopifnot(all(abs(rowSums(point$p)-1)<1e-10))
out <- file.path(root,'output/Supporting_data')
write.csv(summary,file.path(out,'nigeria_actionable_zone_method_mix_decomposition.csv'),row.names=FALSE)
write.csv(detail,file.path(out,'nigeria_actionable_zone_method_mix_cells.csv'),row.names=FALSE)
cat('Wrote',nrow(summary),'decomposition rows and',nrow(detail),'cells\n')
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 34_nigeria_historical_current_user_pathways.R
# LANGUAGE: R
MODULES[["34_nigeria_historical_current_user_pathways.R"]] <- list(
  language="R",
  original_sha256="893c5c21009af098f15c556ea5b7853550dd3627f727889dc0c31df74cf3a015",
  packaged_sha256="893c5c21009af098f15c556ea5b7853550dd3627f727889dc0c31df74cf3a015",
  args=character(),
  code=r"-----(#!/usr/bin/env Rscript
# Nigeria DHS 2024 historical current-user pathway and direct standardization.
# One woman using a modern method 15 months before interview contributes one
# landmark. The following 12 observed calendar months end 3 months before
# interview. Uninterrupted switching stays in continuous modern use; a later
# return after a nonmodern month is re-entry. This historical association is
# not an observed 2025-26 forecast. EC is included here because DHS counts it
# in interview-date modern use; it is grouped with other modern methods, and
# the separate original-method discontinuation life tables continue to omit EC.
root <- Sys.getenv("NIGERIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
out <- file.path(root,'output/Supporting_data')
ir <- readRDS(file.path(root,'Data/raw_dhs_ir/NG2024DHS__NGIR8BDT__IR_raw.rds'))
cal <- readRDS(file.path(root,'Data/Derived/nigeria_2024_calendar_events.rds'))
modern <- c(1L,2L,3L,5L,6L,7L,11L,13L,14L,15L,16L,17L,18L,19L,20L)
group <- function(z) ifelse(z==3L,'Injectables',ifelse(z==11L,'Implants',
  ifelse(z==1L,'Pill','Other modern including EC')))
durlev <- c('0–3 months','4–6 months','7–12 months','13–24 months','25+ months')
durgroup <- function(x) factor(ifelse(x<=3,durlev[1],ifelse(x<=6,durlev[2],
  ifelse(x<=12,durlev[3],ifelse(x<=24,durlev[4],durlev[5])))),levels=durlev)
events <- split(seq_len(nrow(cal)),cal$woman_row)
baseline_month <- as.integer(ir$v008)-15L
rows <- vector('list',nrow(ir)); k <- 0L
for(i in seq_len(nrow(ir))){
  a <- cal[events[[as.character(i)]],]
  if(!nrow(a))next
  bi <- which(a$start<=baseline_month[i] & a$end>=baseline_month[i])
  if(length(bi)!=1L)next
  b <- a$method_code[bi]
  if(!(b %in% modern))next
  follow <- baseline_month[i]+1:12
  ix <- findInterval(follow,a$start)
  stopifnot(all(ix>0L),all(a$end[ix]>=follow))
  codes <- a$method_code[ix]
  effective <- codes %in% modern
  # DHS one-month gap convention: a single no-method month between different
  # modern methods is a continuous switch when prior ending reason is 7.
  for(t in 1:11)if(codes[t]==0L){
    prev <- if(t==1L)b else codes[t-1L]
    subsequent <- codes[t+1L]
    prior_event <- which(a$end==follow[t]-1L & a$method_code==prev)
    if(length(prior_event)==1L && prev %in% modern && subsequent %in% modern &&
       subsequent!=prev && a$reason_code[prior_event]==7L)effective[t]<-TRUE
  }
  status <- function(t){
    exited <- any(!effective[1:t])
    changed <- any(codes[1:t][codes[1:t]%in%modern]!=b) ||
      any(effective[1:t] & !(codes[1:t]%in%modern))
    if(!exited)return(if(changed)'Continuous modern use after switch'
                      else 'Continuous baseline method')
    if(effective[t])return('Re-entered modern use after exit')
    if(codes[t]%in%c(81L,82L,83L))return('Pregnancy/birth/termination')
    'Outside modern use'
  }
  k<-k+1L
  rows[[k]]<-data.frame(woman_row=i,wt=as.numeric(ir$v005[i])/1e6,
    cluster=as.integer(ir$v021[i]),stratum=as.integer(ir$v022[i]),
    baseline_method=group(b),baseline_duration=baseline_month[i]-a$start[bi]+1L,
    month3_status=status(3L),month12_status=status(12L),
    any_gross_exit=any(!effective),stringsAsFactors=FALSE)
}
h <- do.call(rbind,rows[seq_len(k)])
h$duration_group <- durgroup(h$baseline_duration)
h$outcome <- ifelse(h$month12_status=='Continuous baseline method','No gross exit: baseline method',
 ifelse(h$month12_status=='Continuous modern use after switch','No gross exit: modern switch',
 ifelse(h$month12_status=='Re-entered modern use after exit','Gross exit: re-entered by month 12',
        'Gross exit: net absent at month 12')))
stopifnot(nrow(h)>2000L,!anyNA(h$duration_group),!anyNA(h$outcome))
saveRDS(h,file.path(root,'Data/Derived/nigeria_historical_current_user_pathways.rds'))
flows <- aggregate(wt~baseline_method+month3_status+month12_status,h,sum)
flows$pct <- 100*flows$wt/sum(flows$wt)
write.csv(flows,file.path(out,'nigeria_current_user_pathway_flows.csv'),row.names=FALSE)
current <- data.frame(method_code=as.integer(ir$v312),
 duration=as.numeric(ir$v337),wt=as.numeric(ir$v005)/1e6,
 modern=as.integer(ir$v313)==3)
current <- current[current$modern & current$method_code %in% modern &
 is.finite(current$duration) & current$duration<997,]
current$method <- group(current$method_code)
current$duration_group <- durgroup(current$duration)
current_cells <- aggregate(wt~method+duration_group,current,sum)
names(current_cells)[3]<-'current_weight'
current_cells$current_share <- current_cells$current_weight/sum(current_cells$current_weight)
write.csv(current_cells,file.path(out,'nigeria_current_user_method_duration_distribution.csv'),row.names=FALSE)
historical <- aggregate(wt~baseline_method+duration_group+outcome,h,sum)
historical_n <- aggregate(woman_row~baseline_method+duration_group,h,length)
names(historical_n)[3]<-'historical_n'
historical <- merge(historical,historical_n,by=c('baseline_method','duration_group'))
den <- aggregate(wt~baseline_method+duration_group,h,sum)
names(den)[3]<-'historical_weight'
historical <- merge(historical,den,by=c('baseline_method','duration_group'))
historical$conditional_probability <- historical$wt/historical$historical_weight
write.csv(historical,file.path(out,'nigeria_historical_method_duration_pathway_probabilities.csv'),row.names=FALSE)
standard <- merge(current_cells[,c('method','duration_group','current_share')],
 historical[,c('baseline_method','duration_group','outcome','conditional_probability','historical_n')],
 by.x=c('method','duration_group'),by.y=c('baseline_method','duration_group'))
stopifnot(nrow(standard)>0,all(current_cells$current_share>0),
 all(paste(current_cells$method,current_cells$duration_group)%in%
     paste(standard$method,standard$duration_group)))
standard$contribution <- standard$current_share*standard$conditional_probability
summary <- aggregate(contribution~outcome,standard,sum)
summary$pct <- 100*summary$contribution
stopifnot(abs(sum(summary$pct)-100)<1e-8)
write.csv(standard,file.path(out,'nigeria_standardized_current_user_pathway_contributions.csv'),row.names=FALSE)
write.csv(summary,file.path(out,'nigeria_standardized_current_user_pathway_summary.csv'),row.names=FALSE)
cat('Historical women',nrow(h),'current modern users',nrow(current),
    'smallest historical cell',min(historical_n$historical_n),'\n')
print(summary)
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 35_nigeria_alluvial_figures.R
# LANGUAGE: R
MODULES[["35_nigeria_alluvial_figures.R"]] <- list(
  language="R",
  original_sha256="22fdb192d06b81108fb4a07f313fdfda386c25531ce429e93154a4bf6a3c82ec",
  packaged_sha256="22fdb192d06b81108fb4a07f313fdfda386c25531ce429e93154a4bf6a3c82ec",
  args=character(),
  code=r"-----(#!/usr/bin/env Rscript
# Nigeria DHS 2024 alluvial figures parallel to Ethiopia's episode and
# historical-current-user pathway displays. Every figure has a stated cohort:
# first-year injectable actionable endings with month 1 observed; a fixed
# historical modern-user cohort observed for 12 months; or that cohort's
# conditional outcomes standardized to the interview-date current-user mix.
root <- Sys.getenv("NIGERIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
support <- file.path(root,'output/Supporting_data')
assets <- file.path(root,'output/assets')
dir.create(assets,recursive=TRUE,showWarnings=FALSE)
e <- readRDS(file.path(root,'Data/Derived/nigeria_2024_modern_episodes.rds'))
cal <- readRDS(file.path(root,'Data/Derived/nigeria_2024_calendar_events.rds'))
h <- readRDS(file.path(root,'Data/Derived/nigeria_historical_current_user_pathways.rds'))
std <- read.csv(file.path(support,'nigeria_standardized_current_user_pathway_summary.csv'))
modern <- c(1L,2L,3L,5L,6L,7L,11L,13L,14L,15L,16L,17L,18L,19L,20L)
reason <- function(z) ifelse(z==1L,'Method failure',ifelse(z==7L,
 'Wanted more effective method',ifelse(z==15L,'Changes in menstrual bleeding',
 ifelse(z%in%c(4L,5L),'Other side effects/health','Access/cost/convenience'))))
status <- function(code,original) ifelse(code%in%modern,
 ifelse(code==original,'Same modern method','Different modern method'),
 ifelse(code==0L,'No method recorded',ifelse(code%in%c(81L,82L,83L),
 'Pregnancy, birth or termination',ifelse(code%in%c(8L,9L,10L,12L,99L),
 'Traditional/other method','Other/unknown'))))
rows <- split(seq_len(nrow(cal)),cal$woman_row)
injectable <- e[e$method_group=='Injectables' & e$discontinued &
 e$exposure<=12 & e$reason_code%in%c(1L,4L,5L,6L,7L,8L,10L,15L) &
 e$end+1<=e$interview,]
code1 <- vapply(seq_len(nrow(injectable)),function(i){
 a<-cal[rows[[as.character(injectable$woman_row[i])]],]
 j<-which(a$start<=injectable$end[i]+1 & a$end>=injectable$end[i]+1)
 stopifnot(length(j)==1L)
 a$method_code[j]
},integer(1))
injectable$reason_label <- reason(injectable$reason_code)
injectable$destination <- status(code1,injectable$method_code)
injectable$duration_group <- cut(injectable$exposure,c(0,3,6,12),
 labels=c('1–3 months','4–6 months','7–12 months'))
flows <- aggregate(wt~reason_label+destination,injectable,sum)
flows$pct <- 100*flows$wt/sum(flows$wt)
write.csv(flows,file.path(support,'nigeria_injectable_reason_destination_flows.csv'),row.names=FALSE)
timing <- aggregate(wt~reason_label+duration_group+destination,injectable,sum)
timing$pct_of_injectable_actionable_endings <- 100*timing$wt/sum(injectable$wt)
write.csv(timing,file.path(support,'nigeria_injectable_reason_timing_destination.csv'),row.names=FALSE)

palette <- c('Method failure'='#85909D','Wanted more effective method'='#DA9A25',
 'Changes in menstrual bleeding'='#D45A49','Other side effects/health'='#108B8D',
 'Access/cost/convenience'='#153F5B','Same modern method'='#108B8D',
 'Different modern method'='#153F5B','No method recorded'='#85909D',
 'Pregnancy, birth or termination'='#D45A49','Traditional/other method'='#DA9A25',
 'Other/unknown'='#B8BEC5','Injectables'='#108B8D','Implants'='#153F5B',
 'Pill'='#DA9A25','Other modern including EC'='#85909D',
 'Continuous baseline method'='#108B8D',
 'Continuous modern use after switch'='#153F5B',
 'Re-entered modern use after exit'='#DA9A25',
 'Outside modern use'='#85909D',
 'Pregnancy/birth/termination'='#D45A49',
 'No gross exit'='#108B8D','Gross modern-use exit'='#D45A49',
 'Gross exit: net absent at month 12'='#85909D',
 'Gross exit: re-entered by month 12'='#DA9A25',
 'No gross exit: baseline method'='#108B8D',
 'No gross exit: modern switch'='#153F5B')
bezier <- function(t,a,b) (1-t)^3*a+3*(1-t)^2*t*a+3*(1-t)*t^2*b+t^3*b
link <- function(x0,x1,top0,bot0,top1,bot1,col){
 t<-seq(0,1,length.out=90);x<-bezier(t,x0,x1)
 yt<-bezier(t,top0,top1);yb<-bezier(t,bot0,bot1)
 polygon(c(x,rev(x)),c(yt,rev(yb)),col=adjustcolor(col,alpha.f=.46),border=NA)
}
nodes <- function(labels,totals,top=.87,bottom=.10,gap=.028){
 scale<-(top-bottom-gap*(length(labels)-1))/sum(totals[labels])
 z<-data.frame(name=labels,top=NA_real_,bottom=NA_real_)
 y<-top
 for(i in seq_along(labels)){z$top[i]<-y;z$bottom[i]<-y-totals[labels[i]]*scale;y<-z$bottom[i]-gap}
 list(data=z,scale=scale)
}
draw <- function(mat1,mat2=NULL,file,title,subtitle,headers){
 # mat1: left-to-middle weighted flow matrix; optional mat2: middle-to-right.
 Lnames<-rownames(mat1);Mnames<-colnames(mat1)
 Ltot<-rowSums(mat1);Mtot<-colSums(mat1)
 L<-nodes(Lnames,Ltot,.84,.12,.030);M<-nodes(Mnames,Mtot,.84,.12,.030)
 if(!is.null(mat2)){
  stopifnot(max(abs(rowSums(mat2)-Mtot))<1e-6)
  Rnames<-colnames(mat2);Rtot<-colSums(mat2);R<-nodes(Rnames,Rtot,.84,.12,.030)
 }
 png(file,width=3200,height=1700,res=200,type='quartz')
 par(mar=c(4,3,5,3),family='sans',xpd=NA)
 plot.new();plot.window(xlim=c(-.27,1.28),ylim=c(0,1))
 xL<-c(.10,.13);xM<-if(is.null(mat2))c(.82,.85) else c(.48,.52)
 left<-setNames(L$data$top,Lnames);mid<-setNames(M$data$top,Mnames)
 for(m in Mnames)for(l in Lnames){w<-mat1[l,m];if(w<=0)next
  a<-left[l];b<-a-w*L$scale;c<-mid[m];d<-c-w*M$scale
  link(xL[2],xM[1],a,b,c,d,palette[m]);left[l]<-b;mid[m]<-d}
 if(!is.null(mat2)){
  xR<-c(.88,.92);mid<-setNames(M$data$top,Mnames);right<-setNames(R$data$top,Rnames)
  for(r in Rnames)for(m in Mnames){w<-mat2[m,r];if(w<=0)next
   a<-mid[m];b<-a-w*M$scale;c<-right[r];d<-c-w*R$scale
   link(xM[2],xR[1],a,b,c,d,palette[r]);mid[m]<-b;right[r]<-d}
 }
 rect(xL[1],L$data$bottom,xL[2],L$data$top,col=palette[Lnames],border=NA)
 rect(xM[1],M$data$bottom,xM[2],M$data$top,col=palette[Mnames],border=NA)
 if(!is.null(mat2))rect(xR[1],R$data$bottom,xR[2],R$data$top,col=palette[Rnames],border=NA)
 label <- function(dat,tot,x,adj){
  y<-rowMeans(dat[,c('top','bottom')]);
  text(x,y,paste0(dat$name,'  ',sprintf('%.1f%%',100*tot[dat$name]/sum(tot))),
   adj=adj,cex=.64,col='#17222C')
 }
 label(L$data,Ltot,.08,1)
 label(M$data,Mtot,xM[2]+.015,0)
 if(!is.null(mat2))label(R$data,Rtot,.94,0)
 text(xL[1],.93,headers[1],adj=0,cex=.77,font=2,col='#153F5B')
 text(xM[1],.93,headers[2],adj=0,cex=.77,font=2,col='#153F5B')
 if(!is.null(mat2))text(xR[1],.93,headers[3],adj=0,cex=.77,font=2,col='#153F5B')
 title(main=title,sub=subtitle,adj=.02,cex.main=1.3,col.main='#153F5B',
       cex.sub=.88,col.sub='#506879')
 dev.off()
}
reasons <- c('Method failure','Wanted more effective method','Changes in menstrual bleeding',
 'Other side effects/health','Access/cost/convenience')
dest <- c('Different modern method','Same modern method','No method recorded',
 'Pregnancy, birth or termination','Traditional/other method','Other/unknown')
observed_mat<-xtabs(wt~reason_label+destination,injectable)
mat<-matrix(0,length(reasons),length(dest),dimnames=list(reasons,dest))
mat[rownames(observed_mat),colnames(observed_mat)]<-observed_mat
mat<-mat[,colSums(mat)>0,drop=FALSE]
draw(mat,file=file.path(assets,'nigeria_injectable_reason_destination_alluvial.png'),
 title='Why injectable episodes end and what follows one month later',
 subtitle=paste(format(nrow(injectable),big.mark=','),'observed first-year actionable endings; weighted shares'),
 headers=c('RECORDED REASON','STATE ONE MONTH LATER'))

method_names<-c('Injectables','Implants','Pill','Other modern including EC')
path_names<-c('Continuous baseline method','Continuous modern use after switch',
 'Re-entered modern use after exit','Outside modern use','Pregnancy/birth/termination')
left<-xtabs(wt~baseline_method+month3_status,h)[method_names,path_names,drop=FALSE]
right<-xtabs(wt~month3_status+month12_status,h)[path_names,path_names,drop=FALSE]
draw(left,right,file=file.path(assets,'nigeria_current_user_pathway_3_12_alluvial.png'),
 title='Historical current users over 12 months',
 subtitle=paste(format(nrow(h),big.mark=','),'women using a modern method 15 months before interview'),
 headers=c('BASELINE METHOD','PATHWAY BY MONTH 3','STATE AT MONTH 12'))

outcomes<-c('No gross exit: baseline method','No gross exit: modern switch',
 'Gross exit: re-entered by month 12','Gross exit: net absent at month 12')
v<-setNames(std$pct,std$outcome)[outcomes]
mid<-c('No gross exit','Gross modern-use exit')
a<-matrix(c(v[1]+v[2],v[3]+v[4]),1,2,
 dimnames=list('Current modern-method users',mid))
b<-matrix(0,2,4,dimnames=list(mid,outcomes))
b[1,1:2]<-v[1:2];b[2,3:4]<-v[3:4]
palette['Current modern-method users']<-'#153F5B'
draw(a,b,file=file.path(assets,'nigeria_standardized_current_user_stock_alluvial.png'),
 title='Expected pathways per 100 interview-date current modern users',
 subtitle='Historical method-duration probabilities standardized to the DHS 2024 current-user stock',
 headers=c('CURRENT USER STOCK','ANY GROSS EXIT','STATE AT MONTH 12'))

# Repeat the Ethiopia method-to-follow-up displays for Nigeria. These figures
# condition on an observed first-year original-method ending with the required
# follow-up month recorded. They are reason/status distributions, not life-table
# probabilities and not current-user forecasts. Each month has its own cohort.
palette[c('Other modern','IUD')]<-c('#85909D','#D45A49')
origin <- c('Injectables','Implants','Pill','IUD','Other modern')
for (reason_set in c('all','selected')) for (follow_month in c(1L,12L)) {
  f <- e[e$discontinued & e$exposure<=12 & e$end+follow_month<=e$interview,]
  if(reason_set=='selected') f<-f[!(f$reason_code%in%c(2L,3L)),]
  f<-f[f$method_group%in%origin,]
  code <- vapply(seq_len(nrow(f)),function(i){
    z<-cal[rows[[as.character(f$woman_row[i])]],]
    j<-which(z$start<=f$end[i]+follow_month & z$end>=f$end[i]+follow_month)
    stopifnot(length(j)==1L)
    z$method_code[j]
  },integer(1))
  f$destination<-status(code,f$method_code)
  tab<-xtabs(wt~method_group+destination,f)
  mat<-matrix(0,length(origin),length(dest),dimnames=list(origin,dest))
  mat[rownames(tab),colnames(tab)]<-tab
  mat<-mat[,colSums(mat)>0,drop=FALSE]
  name<-sprintf('nigeria_%s_reason_method_to_month_%02d_alluvial.png',reason_set,follow_month)
  set_label<-if(reason_set=='all')'all recorded reasons' else 'reasons other than wanted pregnancy or partner disapproval'
  draw(mat,file=file.path(assets,name),
    title=paste('Modern-method endings and status',paste0(follow_month,' month',if(follow_month>1)'s' else ''),'later'),
    subtitle=paste(format(nrow(f),big.mark=','),'observed first-year endings for',set_label,'with follow-up'),
    headers=c('ORIGINAL METHOD',paste('STATE',paste0(follow_month,' MONTH',if(follow_month>1)'S' else ''),'LATER')))
  z<-as.data.frame(tab);names(z)<-c('method','destination','weighted_endings')
  z$reason_set<-reason_set;z$follow_month<-follow_month;z$observed_endings_n<-nrow(f)
  write.csv(z,file.path(support,sub('\\.png$','.csv',name)),row.names=FALSE)
}
cat('Created seven alluvial PNGs and source flow tables\n')
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 37_nigeria_selected_reason_extensions.R
# LANGUAGE: R
MODULES[["37_nigeria_selected_reason_extensions.R"]] <- list(
 language="R",
 packaged_sha256="9c53719bf39bcb9c801d76c2482c1225970177ad21dff443781a741cd2bb030d",
 args=character(),
 code=r"-----(#!/usr/bin/env Rscript
# Nigeria DHS 2024 selected-reason exploratory analyses mirroring Ethiopia's
# descriptive subgroups, method-duration classes, reason rankings and regional
# method-mix panels. Eligible denominator: all modern-method episodes except
# EC. Wanted pregnancy (code 2) and partner disapproval (code 3) stay in the
# competing-risk life table; they are excluded only as events of interest.
# Survey weights enter every monthly hazard. Intervals resample PSUs within
# DHS strata, keeping repeated episodes of a woman together. Age and parity
# refer to episode start; other demographic covariates refer to interview.
root <- Sys.getenv("NIGERIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
full_ir <- readRDS(file.path(root,'Data/raw_dhs_ir/NG2024DHS__NGIR8BDT__IR_raw.rds'))
full_frame <- unique(data.frame(cluster=as.numeric(full_ir$v021),stratum=as.numeric(full_ir$v022)))

out <- file.path(root,'output/Supporting_data')
d <- readRDS(file.path(root,'Data/Derived/nigeria_2024_model_episode_covariates.rds'))
selected_codes <- list('Method failure'=1L,
 'Other fertility-related'=c(9L,12L,13L),
 'Changes in menstrual bleeding'=15L,
 'Other side effects/health'=c(4L,5L),
 'Wanted more effective method'=7L,
 'Access/cost/convenience'=c(6L,8L,10L),
 'Other recorded reasons'=c(11L,96L,98L,99L,0L))
all_selected <- unlist(selected_codes,use.names=FALSE)
stopifnot(!anyDuplicated(all_selected),
 all(d$reason_code[d$discontinued & !(d$reason_code %in% c(2L,3L))] %in% all_selected))
life <- function(x,w=x$wt){
  s<-1;v<-setNames(numeric(length(selected_codes)),names(selected_codes))
  for(t in 1:12){
    at<-x$entry<t & x$exposure>=t;den<-sum(w[at])
    if(den<=0)return(rep(NA_real_,length(v)+1))
    ended<-at & x$discontinued & x$exposure==t
    for(j in seq_along(selected_codes))
      v[j]<-v[j]+s*sum(w[ended & x$reason_code %in% selected_codes[[j]]])/den
    s<-s*(1-sum(w[ended])/den)
  }
  c(total=100*sum(v),100*v)
}
selected_n <- function(x)sum(x$discontinued & x$exposure<=12 &
 x$entry<x$exposure & x$reason_code %in% all_selected)
d$duration_class <- ifelse(d$method_code%in%c(1L,3L,5L),'Short-acting reversible',
 ifelse(d$method_code%in%c(2L,11L),'Long-acting reversible','Other modern, mixed'))
fields<-c('age_group','parity_group','marital_group','education','wealth',
          'residence','method_group','zone_name','duration_class')
scopes<-list('Overall::All modern'=seq_len(nrow(d)))
for(f in fields){
  lev<-if(is.factor(d[[f]]))levels(d[[f]]) else unique(d[[f]])
  for(v in lev)scopes[[paste(f,v,sep='::')]]<-which(d[[f]]==v)
}
for(z in levels(d$zone_name))for(m in levels(d$method_group))
  scopes[[paste('zone_method',z,m,sep='::')]]<-which(d$zone_name==z & d$method_group==m)
for(m in c('Injectables','Pill','IUD'))for(f in fields[1:6]){
  lev<-levels(d[[f]])
  for(v in lev)scopes[[paste('method_subgroup',m,f,v,sep='::')]]<-
    which(d$method_group==m & d[[f]]==v)
}
estimate <- function(key,idx,weights=NULL){
 x<-d[idx,];w<-if(is.null(weights))x$wt else weights[idx]
 v<-life(x,w)
 parts<-strsplit(key,'::',fixed=TRUE)[[1]]
 outrow<-data.frame(scope=key,variable=parts[1],category=paste(parts[-1],collapse=' / '),
    eligible_episodes_n=nrow(x),weighted_episodes=sum(x$wt),
    selected_endings_n=selected_n(x),selected_12_month_pct=v[1],
    stringsAsFactors=FALSE)
 for(j in seq_along(selected_codes)){
   name<-names(selected_codes)[j]
   outrow[[paste0('cause_',j,'_pct')]]<-v[j+1]
   outrow[[paste0('share_',j,'_pct')]]<-if(is.finite(v[1]) && v[1]>0)100*v[j+1]/v[1] else NA_real_
 }
 outrow
}
point<-do.call(rbind,lapply(names(scopes),function(key)estimate(key,scopes[[key]])))
rownames(point)<-NULL
point$limited_precision<-point$selected_endings_n<30L
point$withhold_reason_rank<-point$selected_endings_n<10L
stopifnot(max(abs(rowSums(point[paste0('cause_',1:7,'_pct')])-point$selected_12_month_pct),na.rm=TRUE)<1e-7,
 max(abs(rowSums(point[paste0('share_',1:7,'_pct')])-100),na.rm=TRUE)<1e-7)
# CIs for national, one-way, zone and method-duration category rates. The
# many small method-by-subgroup reason cells are descriptive only.
ci_keys<-names(scopes)[!grepl('^(zone_method|method_subgroup)::',names(scopes))]
frame<-full_frame;groups<-split(frame$cluster,frame$stratum)
stopifnot(!anyDuplicated(frame$cluster),all(lengths(groups)>1))
B<-as.integer(Sys.getenv('NIGERIA_SELECTED_BOOTSTRAP_REPS','300'))
boot<-matrix(NA_real_,B,length(ci_keys),dimnames=list(NULL,ci_keys))
for(b in seq_len(B)){
 set.seed(20261028L+b)
 mult<-setNames(numeric(nrow(frame)),frame$cluster)
 for(ids in groups){n<-length(ids);mult[as.character(ids)]<-n/(n-1)*
   tabulate(sample.int(n,n-1,replace=TRUE),nbins=n)}
 weights<-d$wt*mult[as.character(d$cluster)]
 for(j in seq_along(ci_keys)){
   ix<-scopes[[ci_keys[j]]]
   boot[b,j]<-tryCatch(life(d[ix,],weights[ix])[1],error=function(err)NA_real_)
 }
}
point$ci_low<-NA_real_;point$ci_high<-NA_real_;point$valid_bootstrap<-NA_integer_
for(key in ci_keys){
 x<-boot[,key];x<-x[is.finite(x)];ix<-which(point$scope==key)
 if(length(x)>=.8*B){point$ci_low[ix]<-quantile(x,.025);point$ci_high[ix]<-quantile(x,.975)}
 point$valid_bootstrap[ix]<-length(x)
}
write.csv(point,file.path(out,'nigeria_selected_reason_extensions.csv'),row.names=FALSE)
# Formal raw zone contrasts use paired differences from the same survey-cluster
# bootstrap draws; Holm controls the 15 simultaneous zone comparisons.
zones<-levels(d$zone_name)
pairs<-combn(zones,2,simplify=FALSE)
zone_pairs<-do.call(rbind,lapply(pairs,function(pair){
 a<-paste0('zone_name::',pair[1]);b<-paste0('zone_name::',pair[2])
 x<-boot[,a]-boot[,b];x<-x[is.finite(x)]
 est<-point$selected_12_month_pct[point$scope==a]-point$selected_12_month_pct[point$scope==b]
 se<-sd(x)
 data.frame(zone_a=pair[1],zone_b=pair[2],difference_pp=est,
  se_pp=se,ci_low=quantile(x,.025),ci_high=quantile(x,.975),
  p_value=2*pnorm(-abs(est/se)),valid_bootstrap=length(x))
}))
zone_pairs$p_holm<-p.adjust(zone_pairs$p_value,method='holm')
zone_pairs$significant_5pct<-zone_pairs$p_holm<.05
zone_pairs$significant_10pct<-zone_pairs$p_holm<.10
write.csv(zone_pairs,file.path(out,'nigeria_selected_reason_zone_pairwise.csv'),row.names=FALSE)
# The two raw 'other' families are distinguishable in the original calendar.
ends<-d[d$discontinued & d$exposure<=12 & d$entry<d$exposure,]
other<-ends[ends$reason_code%in%c(9L,11L,12L,13L,96L,98L,99L,0L),]
other_breakdown<-aggregate(wt~reason_code,other,sum)
other_n<-aggregate(woman_row~reason_code,other,length)
names(other_n)[2]<-'endings_n'
other_breakdown<-merge(other_breakdown,other_n,by='reason_code')
other_breakdown$group<-ifelse(other_breakdown$reason_code%in%c(9L,12L,13L),
 'Other fertility-related','Other recorded reasons')
write.csv(other_breakdown,file.path(out,'nigeria_other_reason_code_breakdown.csv'),row.names=FALSE)
cat('Wrote',nrow(point),'selected-reason rows; bootstrapped',length(ci_keys),
    'aggregate scopes with',B,'replicates\n')
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 38_nigeria_other_reason_followup.R
# LANGUAGE: R
MODULES[["38_nigeria_other_reason_followup.R"]] <- list(
  language="R",
  original_sha256="7563925b7cd91bb3f8b195294616cd79623b25fbd74acfb92a19b13f52ac1164",
  packaged_sha256="7563925b7cd91bb3f8b195294616cd79623b25fbd74acfb92a19b13f52ac1164",
  args=character(),
  code=r"-----(#!/usr/bin/env Rscript
# Decompose residual 12-month modern-method endings and their observed status
# one and twelve months later. This is a conditional ending cohort, distinct
# from cause-specific cumulative incidence in the episode risk set.
root<-Sys.getenv("NIGERIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE));out<-file.path(root,'output/Supporting_data')
d<-readRDS(file.path(root,'Data/Derived/nigeria_2024_modern_episodes.rds'))
cal<-readRDS(file.path(root,'Data/Derived/nigeria_2024_calendar_events.rds'))
modern<-c(1L,2L,3L,5L,6L,7L,11L,13L,14L,15L,16L,17L,18L,19L,20L)
other_codes<-c(9L,11L,12L,13L,96L,98L,99L,0L)
label<-function(code)ifelse(code==9L,'Infrequent sex / husband away',
 ifelse(code==11L,'Up to God / fatalistic',
 ifelse(code==12L,'Difficult to get pregnant / menopausal',
 ifelse(code==13L,'Marital dissolution / separation',
 ifelse(code==96L,'Other specified',
 ifelse(code==98L,'Do not know',
 ifelse(code==99L,'Missing / unknown','Unspecified')))))))
status<-function(code,origin)ifelse(code%in%modern,
 ifelse(code==origin,'Same modern method','Different modern method'),
 ifelse(code==0L,'No method recorded',ifelse(code%in%c(81L,82L,83L),
 'Pregnancy, birth or termination','Traditional/other/unknown')))
ix<-split(seq_len(nrow(cal)),cal$woman_row)
z<-d[d$discontinued & d$entry<d$exposure & d$exposure<=12 &
 d$reason_code%in%other_codes,]
z$reason_label<-label(z$reason_code)
all<-list();n<-0L
for(k in c(1L,12L)){
 q<-z[z$end+k<=z$interview,]
 code<-vapply(seq_len(nrow(q)),function(i){
  a<-cal[ix[[as.character(q$woman_row[i])]],]
  pick<-which(a$start<=q$end[i]+k & a$end>=q$end[i]+k)
  stopifnot(length(pick)==1L)
  a$method_code[pick]
 },integer(1))
 q$destination<-status(code,q$method_code)
 tab<-aggregate(q$wt,list(reason_code=q$reason_code,reason=q$reason_label,
   month_after_ending=rep(k,nrow(q)),destination=q$destination),sum)
 names(tab)[5]<-'weighted_endings'
 count<-aggregate(q$woman_row,list(reason_code=q$reason_code,reason=q$reason_label,
   month_after_ending=rep(k,nrow(q)),destination=q$destination),length)
 names(count)[5]<-'endings_n'
 tab<-merge(tab,count,by=c('reason_code','reason','month_after_ending','destination'))
 denom<-aggregate(weighted_endings~reason_code+reason+month_after_ending,tab,sum)
 names(denom)[4]<-'denom_weighted'
 tab<-merge(tab,denom,by=c('reason_code','reason','month_after_ending'))
 tab$share_within_reason_pct<-100*tab$weighted_endings/tab$denom_weighted
 all[[as.character(k)]]<-tab
}
result<-do.call(rbind,all)
write.csv(result,file.path(out,'nigeria_other_reason_followup.csv'),row.names=FALSE)
cat('Other first-year endings',nrow(z),'follow-up rows',nrow(result),'\n')
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 40_nigeria_selected_current_user_planning.R
# LANGUAGE: R
MODULES[["40_nigeria_selected_current_user_planning.R"]] <- list(
  language="R",
  original_sha256="03d384508bfc9040a08f7535ec49a516dea510769c9400a3adf8bef06723758b",
  packaged_sha256="03d384508bfc9040a08f7535ec49a516dea510769c9400a3adf8bef06723758b",
  args=character(),
  code=r"-----(#!/usr/bin/env Rscript
# Parallel first-year and duration-aware 2025-current-user illustrations for
# seven selected discontinuation reasons (all except wanted pregnancy and
# partner disapproval). These are original-method endings, not necessarily
# exits from modern use. Historical duration risks are not causal forecasts.
root<-Sys.getenv("NIGERIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE));out<-file.path(root,'output/Supporting_data')
users<-read.csv(file.path(out,'nigeria_current_users_by_method_and_actionable_projection.csv'))
selected<-read.csv(file.path(out,'nigeria_selected_reason_extensions.csv'),check.names=FALSE)
landmarks<-readRDS(file.path(root,'Data/Derived/nigeria_historical_duration_landmarks.rds'))
duration<-read.csv(file.path(out,'nigeria_duration_landmark_support_and_risks.csv'))
methods<-c('Injectables','Implants','Pill','IUD','Other modern')
reason<-list('Method failure'=1L,'Other fertility-related'=c(9L,12L,13L),
 'Changes in menstrual bleeding'=15L,'Other side effects/health'=c(4L,5L),
 'Wanted more effective method'=7L,'Access/cost/convenience'=c(6L,8L,10L),
 'Other recorded reasons'=c(11L,96L,98L,99L,0L))
labels<-c('0–3','4–6','7–12','13–24','25–36','37–48','49–60','61+')
rows<-list()
for(m in methods){
 stock<-users$current_users_2025[users$method==m]
 first<-selected[selected$scope==paste0('method_group::',m),]
 stopifnot(length(stock)==1L,nrow(first)==1L)
 bins<-duration[duration$method==m,]
 shares<-bins$current_weight/sum(bins$current_weight)
 for(j in seq_along(reason)){
   event<-reason[[j]]
   probs<-numeric(length(labels));support_n<-integer(length(labels))
   for(k in seq_along(labels)){
     target<-if(labels[k]=='61+')c('37–48','49–60') else labels[k]
     x<-landmarks[landmarks$method==m & landmarks$duration_bin%in%target,]
     support_n[k]<-nrow(x)
     probs[k]<-sum(x$wt*(x$ending_reason_code%in%event))/sum(x$wt)
   }
   risk<-sum(shares*probs)
   rows[[length(rows)+1L]]<-data.frame(method=m,reason=names(reason)[j],
     current_users_2025=stock,first_year_cause_risk_pct=first[[paste0('cause_',j,'_pct')]],
     first_year_illustrative_endings=stock*first[[paste0('cause_',j,'_pct')]]/100,
     duration_aware_next12_risk_pct=100*risk,
     duration_aware_illustrative_endings=stock*risk,
     minimum_historical_bin_landmarks=min(support_n),
     current_stock_61plus_share_pct=100*shares[labels=='61+'])
 }
}
result<-do.call(rbind,rows)
stopifnot(nrow(result)==35L)
write.csv(result,file.path(out,'nigeria_selected_current_user_method_reason_planning.csv'),row.names=FALSE)
totals<-aggregate(cbind(first_year_illustrative_endings,duration_aware_illustrative_endings)~method,
 result,sum)
total<-colSums(totals[,2:3])
cat('First-year illustrative selected endings',round(total[1]),
    'duration-aware selected endings',round(total[2]),'\n')
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 42_nigeria_crossvalidated_selected_risk_strata.R
# LANGUAGE: R
MODULES[["42_nigeria_crossvalidated_selected_risk_strata.R"]] <- list(
 language="R",
 packaged_sha256="da6678ab2cae3e3d6ae7aae4807665d418c9ac0291c19357ca7f7ff1b15050ea",
 args=character(),
 code=r"-----(#!/usr/bin/env Rscript
# Out-of-fold risk stratification for 12-month discontinuation of the original
# modern method for any reason except wanted pregnancy or partner disapproval.
# The two excluded endings are competing events. This is an EPISODE-level
# risk-profile analysis, not woman-level sequence clustering.
#
# Predictive covariates are deliberately restricted to characteristics known
# at method start: original method, age group, and live-birth parity group.
# Interview-date marital status, wealth, education, region and residence are
# profiled after the risk strata are formed; they cannot generate a high-risk
# label mechanically and may have changed since an earlier episode.
#
# Five folds are assigned by DHS PSU within each stratum. Each episode's risk
# comes from a model that did not see its PSU. Observed selected-reason 12-month
# cumulative incidence is then estimated within the held-out risk strata with
# delayed entry and all competing endings retained. Stratified PSU bootstrap
# intervals hold the fitted scores and cut-points fixed; they do not include
# model-training uncertainty, which requires a nested bootstrap.

project <- Sys.getenv("NIGERIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
out <- file.path(project,"output","Supporting_data")
if(!requireNamespace("nnet",quietly=TRUE))
  install.packages("nnet",repos="https://cloud.r-project.org")
e <- readRDS(file.path(project,"Data/Derived/nigeria_2024_model_episode_covariates.rds"))
e$selected_event <- e$discontinued & e$exposure<=12 & e$entry<e$exposure & !(e$reason_code%in%c(2L,3L))
e$method_group <- factor(e$method_group,
  levels=c("Injectables","Implants","Pill","IUD","Other modern"))
e$age_group <- factor(e$age_group,levels=levels(e$age_group))
e$parity_group <- factor(e$parity_group,levels=levels(e$parity_group))
e$cluster <- as.character(e$cluster)
e$stratum <- as.integer(e$stratum)
stopifnot(nrow(e)==8341L)

life <- function(d,w=d$wt){
  if(!nrow(d)||sum(w)<=0)return(NA_real_)
  survival <- 1;incidence <- 0
  for(t in 1:12){
    risk<-d$entry<t & d$exposure>=t
    den<-sum(w[risk]);if(den<=0)return(NA_real_)
    end<-risk & d$discontinued & d$exposure==t
    selected<-end & !(d$reason_code%in%c(2L,3L))
    incidence<-incidence+survival*sum(w[selected])/den
    survival<-survival*(1-sum(w[end])/den)
  }
  100*incidence
}

# Assign every PSU in the same DHS stratum to one validation fold.
cluster_frame <- unique(e[c("cluster","stratum")])
set.seed(20261005L)
cluster_frame$fold <- NA_integer_
for(s in unique(cluster_frame$stratum)){
  rows<-which(cluster_frame$stratum==s)
  cluster_frame$fold[rows] <- sample(rep(1:5,length.out=length(rows)))
}
e$fold <- cluster_frame$fold[match(e$cluster,cluster_frame$cluster)]
stopifnot(!anyNA(e$fold),all(table(e$fold)>1000L))

# Expand every episode over its observed at-risk months; repeated rows retain
# the same woman's sample weight and validation fold.
nmonths <- pmax(0L,pmin(12L,e$exposure)-e$entry)
index <- rep(seq_len(nrow(e)),nmonths)
month <- unlist(Map(function(first,n)seq.int(first+1L,length.out=n),
                    e$entry,nmonths),use.names=FALSE)
person <- e[index,c("wt","method_group","age_group","parity_group","fold")]
person$month <- factor(month,levels=1:12)
ended <- e$discontinued[index] & month==e$exposure[index]
person$outcome <- factor(ifelse(!ended,"continue",
  ifelse(e$reason_code[index]%in%c(2L,3L),"excluded","selected")),
  levels=c("continue","selected","excluded"))
stopifnot(nrow(person)>50000L)
formula <- outcome ~ month + method_group + age_group + parity_group

predict_cif <- function(fit,x){
  survival<-rep(1,nrow(x));incidence<-numeric(nrow(x))
  for(t in 1:12){
    x$month<-factor(t,levels=1:12)
    p<-predict(fit,newdata=x,type="probs")
    incidence<-incidence+survival*p[,"selected"]
    survival<-survival*p[,"continue"]
  }
  100*incidence
}
e$oof_selected_risk_pct <- NA_real_
for(f in 1:5){
  fit<-nnet::multinom(formula,data=person[person$fold!=f,],
    weights=person$wt[person$fold!=f],maxit=250,trace=FALSE,MaxNWts=10000)
  if(fit$convergence!=0L)stop("Fold ",f," failed to converge")
  held<-which(e$fold==f)
  e$oof_selected_risk_pct[held]<-predict_cif(fit,e[held,])
}
stopifnot(!anyNA(e$oof_selected_risk_pct))

weighted_quantile <- function(x,w,p){
  o<-order(x); x<-x[o];w<-w[o]
  x[which(cumsum(w)/sum(w)>=p)[1L]]
}
cut1<-weighted_quantile(e$oof_selected_risk_pct,e$wt,1/3)
cut2<-weighted_quantile(e$oof_selected_risk_pct,e$wt,2/3)
stopifnot(cut1<cut2)
e$risk_stratum <- factor(ifelse(e$oof_selected_risk_pct<=cut1,"Lower",
  ifelse(e$oof_selected_risk_pct<=cut2,"Middle","Higher")),
  levels=c("Lower","Middle","Higher"))
levels_risk<-levels(e$risk_stratum)

# Bootstrap realized (held-out) life-table rates and direct risk differences.
reps<-as.integer(Sys.getenv("RISK_STRATA_BOOTSTRAP_REPS","300"))
if(reps<100L)stop("Use at least 100 bootstrap replicates")
full_ir <- readRDS(file.path(project,'Data/raw_dhs_ir/NG2024DHS__NGIR8BDT__IR_raw.rds'))
cluster_frame <- unique(data.frame(cluster=as.character(full_ir$v021),stratum=as.numeric(full_ir$v022)))
clusters_by_stratum<-split(cluster_frame$cluster,cluster_frame$stratum)
stopifnot(all(lengths(clusters_by_stratum)>1L))
boot<-matrix(NA_real_,nrow=reps,ncol=3,dimnames=list(NULL,levels_risk))
for(b in seq_len(reps)){
  set.seed(20261005L+1000L+b)
  mult<-setNames(numeric(nrow(cluster_frame)),cluster_frame$cluster)
  for(ids in clusters_by_stratum){
    n<-length(ids);draw<-sample.int(n,n-1L,replace=TRUE)
    mult[ids]<-n/(n-1L)*tabulate(draw,nbins=n)
  }
  w<-e$wt*mult[e$cluster]
  for(j in seq_along(levels_risk)){
    take<-e$risk_stratum==levels_risk[j]
    boot[b,j]<-life(e[take,],w[take])
  }
}
stopifnot(all(colSums(!is.na(boot))>=.95*reps))
risk_rows<-do.call(rbind,lapply(levels_risk,function(g){
  z<-e[e$risk_stratum==g,]
  bb<-boot[,g]
  data.frame(risk_stratum=g,eligible_episodes=nrow(z),
    weighted_episodes=sum(z$wt),weighted_share_pct=100*sum(z$wt)/sum(e$wt),
    selected_endings=sum(z$selected_event),
    predicted_risk_median_pct=weighted_quantile(z$oof_selected_risk_pct,z$wt,.5),
    observed_12_month_probability_pct=life(z),
    ci_low=unname(quantile(bb,.025,na.rm=TRUE)),
    ci_high=unname(quantile(bb,.975,na.rm=TRUE)))
}))
differences<-data.frame(comparison=c("Middle minus Lower","Higher minus Middle","Higher minus Lower"),
  estimate_pp=c(diff(risk_rows$observed_12_month_probability_pct),
                risk_rows$observed_12_month_probability_pct[3]-risk_rows$observed_12_month_probability_pct[1]),
  ci_low=NA_real_,ci_high=NA_real_)
bd<-cbind(boot[,2]-boot[,1],boot[,3]-boot[,2],boot[,3]-boot[,1])
differences$ci_low<-apply(bd,2,quantile,.025,na.rm=TRUE,names=FALSE)
differences$ci_high<-apply(bd,2,quantile,.975,na.rm=TRUE,names=FALSE)

# Describe the distribution of each characteristic within a stratum. These
# profile shares are not adjusted effects. Age, parity, and method created the
# risk score; their enrichment is therefore partly mechanical. Interview-date
# variables did not enter the score, but may have changed after method start.
profile_variables<-c("method_group","age_group","parity_group",
                     "marital_group","education","wealth","residence")
profile<-do.call(rbind,lapply(profile_variables,function(v){
  do.call(rbind,lapply(levels_risk,function(g){
    z<-e[e$risk_stratum==g,];den<-sum(z$wt)
    lev<-sort(unique(as.character(e[[v]])))
    do.call(rbind,lapply(lev,function(l){
      a<-z[as.character(z[[v]])==l,]
      data.frame(characteristic=v,level=l,risk_stratum=g,
        unweighted_episodes=nrow(a),weighted_share_within_stratum_pct=100*sum(a$wt)/den)
    }))
  }))
}))

write.csv(e[,c("woman_row","episode_id","wt","cluster","stratum","fold",
              "method_group","age_group","parity_group","marital_group",
              "education","wealth","residence","entry","exposure",
              "discontinued","reason_code","selected_event","oof_selected_risk_pct",
              "risk_stratum")],
  file.path(out,"nigeria_selected_reason_oof_episode_scores.csv"),row.names=FALSE)
write.csv(risk_rows,file.path(out,"nigeria_selected_reason_crossvalidated_risk_strata.csv"),row.names=FALSE)
write.csv(differences,file.path(out,"nigeria_selected_reason_risk_strata_differences.csv"),row.names=FALSE)
write.csv(profile,file.path(out,"nigeria_selected_reason_risk_strata_profiles.csv"),row.names=FALSE)
write.csv(data.frame(eligible_episodes=nrow(e),weighted_episodes=sum(e$wt),
  risk_cut_lower_middle_pct=cut1,risk_cut_middle_higher_pct=cut2,
  folds=5,bootstrap_reps=reps,primary_predictors="Method, age and parity at episode start",
  note="Fixed-cutpoint bootstrap intervals do not include model-training uncertainty"),
  file.path(out,"nigeria_selected_reason_risk_strata_audit.csv"),row.names=FALSE)
cat("Out-of-fold cut-points:",round(cut1,2),round(cut2,2),"percent\n")
print(risk_rows,row.names=FALSE)
print(differences,row.names=FALSE)
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 44_nigeria_replication_figures.R
# LANGUAGE: R
MODULES[["44_nigeria_replication_figures.R"]] <- list(
  language="R",
  original_sha256="f2394cf4bee2b3bd23bb7da6dc713abdb8830ecb77352f3060faf6a64a598743",
  packaged_sha256="f2394cf4bee2b3bd23bb7da6dc713abdb8830ecb77352f3060faf6a64a598743",
  args=character(),
  code=r"-----(#!/usr/bin/env Rscript
# Reproduce the principal figure families in the Ethiopia working HTML using
# Nigeria DHS 2024 estimates already saved by the documented analysis scripts.
# No figures or estimates are copied from Ethiopia.
suppressPackageStartupMessages({library(ggplot2);library(svglite)})
root <- file.path(Sys.getenv("NIGERIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE)), 'output')
dat <- file.path(root, 'Supporting_data')
assets <- file.path(root, 'assets')
dir.create(assets, recursive=TRUE, showWarnings=FALSE)
read <- function(x) read.csv(file.path(dat, x), check.names=FALSE, stringsAsFactors=FALSE)
navy <- '#153F5B'; teal <- '#108B8D'; gold <- '#DA9A25'; red <- '#D45A49'; gray <- '#85909D'
zones <- c('North West','North East','North Central','South East','South South','South West')
methods <- c('Injectables','Implants','Pill','IUD','Other modern')
base <- theme_minimal(base_family='Arial', base_size=13)+theme(plot.title=element_text(family='Georgia',face='bold',size=19,color=navy),plot.subtitle=element_text(size=11,color=navy),panel.grid.minor=element_blank(),panel.grid.major.y=element_blank(),axis.title.y=element_blank(),legend.position='bottom',plot.margin=margin(20,22,20,22))
save <- function(p, name, w=11.5,h=6.5) {
 ggsave(file.path(assets,name),p,width=w,height=h,device=svglite::svglite,bg='white')
 ggsave(file.path(assets,sub('\\.svg$','.png',name)),p,width=w,height=h,dpi=150,bg='white')
}

# Overall and zone method-start mix: denominator includes every recorded method
# start, including emergency contraception and non-modern methods.
mix <- read('nigeria_zone_all_method_start_mix.csv')
mix$method <- factor(mix$method, levels=c('Injectables','Implants','Pill','IUD','Other modern','Non-modern methods','Emergency contraception'))
mix$scope <- factor(mix$scope, levels=rev(c('National',zones)))
pal <- c('Injectables'=teal,'Implants'=navy,'Pill'=gold,'IUD'=red,'Other modern'=gray,'Non-modern methods'='#A48865','Emergency contraception'='#B65F8C')
mix_plot <- ggplot(mix,aes(x=scope,y=start_share_pct,fill=method))+geom_col(width=.70)+scale_fill_manual(values=pal,drop=FALSE)+scale_y_continuous(limits=c(0,101),breaks=seq(0,100,20),expand=expansion(mult=c(0,0)))+labs(title='Method starts differ across Nigeria’s six zones',subtitle='Weighted share of all method starts, national benchmark first',x=NULL,y='Percent of observed starts',fill=NULL)+coord_flip()+base+theme(legend.text=element_text(size=11))
save(mix_plot,'nigeria_regional_method_start_mix.svg',12,6)

# Cumulative incidence lines keep excluded endings as competing events.
times <- read('nigeria_modern_all_reason_timepoints.csv')
curve <- subset(times, scope %in% c('National',paste0('National: ',methods)))
curve$Method <- ifelse(curve$scope=='National','All modern',sub('National: ','',curve$scope))
curve$month <- as.numeric(curve$month)
starts <- curve[match(c('National',paste0('National: ',methods)),curve$scope),,drop=FALSE]
starts$month <- 0; starts$all_reason_pct <- 0; starts$selected_reason_pct <- 0; starts$actionable_pct <- 0
curve <- rbind(starts,curve)
curve$Method <- factor(curve$Method,levels=c('All modern',methods))
cpal <- c('All modern'='#334957','Injectables'=teal,'Implants'=navy,'Pill'=gold,'IUD'=red,'Other modern'=gray)
for (measure in c('all_reason_pct','selected_reason_pct','actionable_pct')) {
 ttl <- switch(measure,all_reason_pct='All-reason discontinuation accumulates during year one',selected_reason_pct='Selected-reason discontinuation accumulates during year one',actionable_pct='Actionable discontinuation accumulates during year one')
 p <- ggplot(curve,aes(x=month,y=.data[[measure]],color=Method,group=Method))+geom_step(linewidth=1.15)+geom_point(data=subset(curve,month==12),size=2.8)+scale_color_manual(values=cpal)+scale_x_continuous(breaks=c(0,3,6,9,12),limits=c(0,12))+scale_y_continuous(labels=function(x)paste0(x,'%'),limits=c(0,max(curve[[measure]],na.rm=TRUE)*1.10))+labs(title=ttl,subtitle='Weighted cumulative probability of ending the original modern method',x='Months since method start',y='Cumulative discontinuation probability',color=NULL)+base
 save(p,paste0('nigeria_',measure,'_method_curves.svg'),11.7,6.3)
}

# Analog of the presentation slide with a method's share of starts and risk.
start <- subset(mix,scope=='National' & as.character(method) %in% methods)
ec_starts <- subset(mix,scope=='National' & as.character(method)=='Emergency contraception')$weighted_starts
start$start_share_pct <- 100*start$weighted_starts/(start$denominator_weighted_starts-ec_starts)
risk <- subset(times,month==12 & scope %in% paste0('National: ',methods))
risk$method <- sub('National: ','',risk$scope)
paired <- merge(start[,c('method','start_share_pct')],risk[,c('method','all_reason_pct','actionable_pct')],by='method')
paired$method <- factor(as.character(paired$method),levels=rev(methods))
for (measure in c('all_reason_pct','actionable_pct')) {
 d <- rbind(data.frame(method=paired$method,type='Share of all method starts',pct=paired$start_share_pct),data.frame(method=paired$method,type='12-month discontinuation',pct=paired[[measure]]))
 d$type <- factor(d$type,levels=c('Share of all method starts','12-month discontinuation'))
 p <- ggplot(d,aes(x=method,y=pct,fill=type))+geom_col(position=position_dodge2(width=.72,padding=0),width=.72)+geom_text(aes(label=sprintf('%.1f',pct)),position=position_dodge2(width=.72,padding=0),hjust=-.12,size=3.7,color='black')+scale_fill_manual(values=c('Share of all method starts'=gold,'12-month discontinuation'=navy))+scale_y_continuous(limits=c(0,max(d$pct)*1.18),breaks=seq(0,100,20))+coord_flip()+labs(title=if(measure=='all_reason_pct')'Starts and all-reason discontinuation by method' else 'Starts and actionable discontinuation by method',subtitle='Start-share denominator excludes EC; 12-month risk is among episodes of that method',x=NULL,y='Percent',fill=NULL)+base
 save(p,paste0('nigeria_national_start_vs_',measure,'.svg'),11.5,6)
}

# Actionable timing heatmap with an explicit early-share column.
tt <- read('nigeria_actionable_timepoints.csv');tt <- subset(tt,scope %in% c('National',zones));tt$scope <- factor(tt$scope,levels=rev(c('National',zones)))
wide <- reshape(tt[,c('scope','month','actionable_pct')],idvar='scope',timevar='month',direction='wide')
wide$early <- 100*wide[['actionable_pct.3']]/wide[['actionable_pct.12']]
long <- rbind(data.frame(scope=wide$scope,month='First 3 of 12 months',pct=wide$early),do.call(rbind,lapply(c(3,6,9,12),function(m)data.frame(scope=wide$scope,month=paste(m,'months'),pct=wide[[paste0('actionable_pct.',m)]]))))
long$month <- factor(long$month,levels=c('3 months','6 months','9 months','12 months','First 3 of 12 months'))
heat <- ggplot(long,aes(month,scope,fill=pct))+geom_tile(color='white',linewidth=2)+geom_text(aes(label=sprintf('%.1f',pct)),size=4,color='black')+scale_fill_gradient(low='#E8F1F3',high=teal)+scale_x_discrete(position='top')+labs(title='Actionable discontinuation accumulates at different rates',subtitle='Cumulative probability by month; final column is the share of the 12-month risk occurring by month 3',x=NULL,y=NULL,fill='Percent')+base+theme(panel.grid=element_blank(),axis.text.x=element_text(face='plain'),legend.position='none')
save(heat,'nigeria_actionable_zone_timing_heatmap.svg',12,5.7)

# Zone reason mix: each row is conditional on an actionable ending and sums to 100.
rmix <- read('nigeria_actionable_reason_mix.csv');rmix <- subset(rmix,scope %in% c('National',zones));rmix$scope <- factor(rmix$scope,levels=rev(c('National',zones)))
rmix$reason <- factor(rmix$reason,levels=c('Method failure','Wanted more effective method','Changes in menstrual bleeding','Other side effects/health','Access/cost/convenience'))
reasons <- ggplot(rmix,aes(reason,scope,fill=share_among_actionable_pct))+geom_tile(color='white',linewidth=2)+geom_text(aes(label=sprintf('%.0f',share_among_actionable_pct)),size=3.7,color='black')+scale_fill_gradient(low='#E8F1F3',high=teal)+scale_x_discrete(position='top',labels=function(x)gsub(' ','\n',x,fixed=TRUE))+labs(title='Reasons differ across zones',subtitle='Share among first-year potentially actionable discontinuations; rows total 100%',x=NULL,y=NULL,fill='Percent')+base+theme(panel.grid=element_blank(),axis.text.x=element_text(size=10),legend.position='none')
save(reasons,'nigeria_actionable_zone_reason_heatmap.svg',12,5.7)

# Regional observed and fully adjusted rates; every displayed CI is survey-bootstrap.
ad <- read('nigeria_actionable_zone_adjusted_rates.csv');ad <- subset(ad,zone %in% c('National',zones));ad$zone <- factor(ad$zone,levels=rev(c('National',zones)))
dd <- rbind(data.frame(zone=ad$zone,type='Observed',rate=ad$unadjusted_pct,low=ad$unadjusted_low,high=ad$unadjusted_high),data.frame(zone=ad$zone,type='Fully adjusted',rate=ad$model_2_common_mix_pct,low=ad$model_2_low,high=ad$model_2_high))
dd$type <- factor(dd$type,levels=c('Observed','Fully adjusted'))
forest <- ggplot(dd,aes(rate,zone,color=type))+geom_errorbar(aes(xmin=low,xmax=high),orientation='y',position=position_dodge(width=.5),width=.16,linewidth=.75)+geom_point(position=position_dodge(width=.5),size=2.8)+scale_color_manual(values=c('Observed'=gold,'Fully adjusted'=navy))+scale_x_continuous(limits=c(max(0,min(dd$low)-2),max(dd$high)+2),labels=function(x)paste0(x,'%'))+labs(title='Observed and adjusted actionable discontinuation',subtitle='12-month regional probabilities with 95% survey-bootstrap intervals',x='Probability of ending the original modern method',y=NULL,color=NULL)+base
save(forest,'nigeria_actionable_zone_observed_adjusted.svg',12,6)

# Selected-reason regional risk and conditional reason mix. These seven reason
# shares sum to 100 within each zone and are a different denominator from risk.
sel <- read('nigeria_selected_reason_extensions.csv')
sel <- subset(sel,variable=='zone_name')
sel$category <- factor(sel$category,levels=rev(zones))
sforest <- ggplot(sel,aes(selected_12_month_pct,category))+geom_errorbar(aes(xmin=ci_low,xmax=ci_high),orientation='y',width=.18,color=teal,linewidth=.8)+geom_point(size=3,color=teal)+scale_x_continuous(labels=function(x)paste0(x,'%'))+labs(title='Selected-reason discontinuation by zone',subtitle='Unadjusted 12-month probability and 95% survey-bootstrap interval',x='Probability of ending the original method',y=NULL)+base
save(sforest,'nigeria_selected_reason_zone_forest.svg',11.5,5.8)
reason_labels <- c('Method failure','Other fertility-related','Bleeding','Other side effects/health','More effective method','Access/cost/convenience','Other recorded')
sr <- do.call(rbind,lapply(seq_along(reason_labels),function(i)data.frame(zone=sel$category,reason=reason_labels[i],pct=sel[[paste0('share_',i,'_pct')]])))
sr$reason <- factor(sr$reason,levels=reason_labels)
sh <- ggplot(sr,aes(reason,zone,fill=pct))+geom_tile(color='white',linewidth=1.8)+geom_text(aes(label=sprintf('%.0f',pct)),size=3.1,color='black')+scale_fill_gradient(low='#E8F1F3',high=teal)+scale_x_discrete(position='top',labels=function(x)gsub(' ','\n',x,fixed=TRUE))+labs(title='Reasons within selected discontinuations',subtitle='Shares conditional on selected ending; each zone row sums to 100%',x=NULL,y=NULL,fill='Percent')+base+theme(panel.grid=element_blank(),axis.text.x=element_text(size=9),legend.position='none')
save(sh,'nigeria_selected_reason_zone_heatmap.svg',12,5.8)

sm <- read('nigeria_selected_reason_zone_models.csv');sm<-subset(sm,zone%in%c('National',zones));sm$zone<-factor(sm$zone,levels=rev(c('National',zones)))
sd <- rbind(data.frame(zone=sm$zone,type='Observed',rate=sm$unadjusted_pct,low=sm$unadjusted_low,high=sm$unadjusted_high),
 data.frame(zone=sm$zone,type='Method adjusted',rate=sm$model_1_pct,low=sm$model_1_low,high=sm$model_1_high),
 data.frame(zone=sm$zone,type='Fully adjusted',rate=sm$model_2_pct,low=sm$model_2_low,high=sm$model_2_high))
sd$type<-factor(sd$type,levels=c('Observed','Method adjusted','Fully adjusted'))
sp<-ggplot(sd,aes(rate,zone,color=type))+geom_errorbar(aes(xmin=low,xmax=high),orientation='y',position=position_dodge(width=.62),width=.12,linewidth=.6)+geom_point(position=position_dodge(width=.62),size=2.6)+scale_color_manual(values=c('Observed'=gold,'Method adjusted'=teal,'Fully adjusted'=navy))+scale_x_continuous(labels=function(x)paste0(x,'%'))+labs(title='Selected-reason risk after adjustment',subtitle='Regional estimates; adjusted intervals use 80 bootstrap refits and remain preliminary',x='12-month original-method discontinuation probability',y=NULL,color=NULL)+base
save(sp,'nigeria_selected_reason_zone_adjusted.svg',12,6)

# All-reason month-12 status by original method, a companion to the alluvial.
follow <- read('nigeria_all_reason_method_to_month_12_alluvial.csv')
follow$method<-factor(follow$method,levels=rev(methods))
follow$destination<-factor(follow$destination,levels=c('No method recorded','Different modern method','Same modern method','Pregnancy, birth or termination','Traditional/other method','Other/unknown'))
follow$share<-ave(follow$weighted_endings,follow$method,FUN=function(x)100*x/sum(x))
fpal<-c('No method recorded'='#85909D','Different modern method'=navy,'Same modern method'=teal,'Pregnancy, birth or termination'=red,'Traditional/other method'=gold,'Other/unknown'='#B8BEC5')
fp<-ggplot(follow,aes(method,share,fill=destination))+geom_col(width=.69)+scale_fill_manual(values=fpal,drop=TRUE)+scale_y_continuous(limits=c(0,101),breaks=seq(0,100,20))+coord_flip()+labs(title='Modern use varies 12 months after an all-reason ending',subtitle='Weighted share among observed first-year endings with 12-month follow-up',x=NULL,y='Percent of observed endings',fill=NULL)+base+theme(legend.text=element_text(size=10))
save(fp,'nigeria_all_reason_month12_followup_stacked.svg',11.8,6)

# Injectable reason, timing, and next-month destination. Row percentages are
# conditional on the named reason and add to 100 before rounding.
inj <- read('nigeria_injectable_reason_timing_destination.csv')
tim<-aggregate(wt~reason_label+duration_group,inj,sum)
tim$share<-ave(tim$wt,tim$reason_label,FUN=function(x)100*x/sum(x))
dest1<-aggregate(wt~reason_label+destination,inj,sum)
dest1$share<-ave(dest1$wt,dest1$reason_label,FUN=function(x)100*x/sum(x))
no<-subset(dest1,destination=='No method recorded')
no<-merge(data.frame(reason_label=unique(tim$reason_label)),no[,c('reason_label','share')],by='reason_label',all.x=TRUE)
no$share[is.na(no$share)]<-0
no$duration_group<-'No method one month later'
ih<-rbind(tim[,c('reason_label','duration_group','share')],no[,c('reason_label','duration_group','share')])
ih$duration_group<-factor(ih$duration_group,levels=c('1–3 months','4–6 months','7–12 months','No method one month later'))
ih$reason_label<-factor(ih$reason_label,levels=rev(c('Method failure','Wanted more effective method','Changes in menstrual bleeding','Other side effects/health','Access/cost/convenience')))
ip<-ggplot(ih,aes(duration_group,reason_label,fill=share))+geom_tile(color='white',linewidth=2)+geom_text(aes(label=sprintf('%.0f',share)),size=4,color='black')+scale_fill_gradient(low='#E8F1F3',high=teal)+scale_x_discrete(position='top',labels=c('1–3\nmonths','4–6\nmonths','7–12\nmonths','No method\nnext month'))+labs(title='Injectable ending timing and next-month nonuse by reason',subtitle='First three columns sum to 100 within reason; final column is a separate next-month outcome',x=NULL,y=NULL,fill='Percent')+base+theme(panel.grid=element_blank(),legend.position='none')
save(ip,'nigeria_injectable_reason_timing_destination_heatmap.svg',12,5.5)
cat('Created Nigeria figures in',assets,'\n')
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 70_modern_five_year_reasons.R
# LANGUAGE: R
MODULES[["70_modern_five_year_reasons.R"]] <- list(
  language="R",
  original_sha256="3dcf3ea84c4d8dd75c9c25d05507e97931fcbf5e531deeb528d6715a516edbef",
  packaged_sha256="3dcf3ea84c4d8dd75c9c25d05507e97931fcbf5e531deeb528d6715a516edbef",
  args=character(),
  code=r"-----(#!/usr/bin/env Rscript
# Match Ethiopia's five-year reason-distribution denominator: observed endings
# of modern-method episodes, excluding emergency contraception. Reconstruct
# the published all-method column first as a validation control.
root <- Sys.getenv("NIGERIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
x <- readRDS(file.path(root,'Data/raw_dhs_ir/NG2024DHS__NGIR8BDT__IR_raw.rds'))
method_chars <- strsplit('123456789WNALCFEMS~','')[[1]]
reason_map <- c('1'=1L,'2'=2L,'3'=3L,'7'=4L,'M'=5L,
                '4'=6L,'6'=7L,'C'=8L,'8'=9L,'F'=10L,
                'A'=11L,'9'=12L,'D'=13L,'W'=14L,'K'=15L,'?'=16L)
reason_labels <- c('Became pregnant while using','Wanted to become pregnant',
  'Husband/partner disapproved','Wanted a more effective method',
  'Changes in menstrual bleeding','Other side effects/health concerns',
  'Lack of access/too far','Cost too much','Inconvenient to use',
  'Up to God/fatalistic','Difficult to get pregnant/menopausal',
  'Infrequent sex/husband away','Marital dissolution/separation','Other',
  'Don’t know','Missing')
pieces <- vector('list',nrow(x))
for(i in seq_len(nrow(x))){
  pos <- as.integer(x$v018[i]) + 0:59
  chars <- substring(sprintf('%-80s',x$vcal_2[i]),pos,pos)
  keep <- chars!=' '
  if(any(keep))pieces[[i]] <- data.frame(
    method_code=match(substring(x$vcal_1[i],pos[keep],pos[keep]),method_chars),
    reason_code=unname(reason_map[chars[keep]]),
    wt=as.numeric(x$v005[i])/1e6)
}
ev <- do.call(rbind,pieces)
ev <- ev[!is.na(ev$method_code)&!is.na(ev$reason_code),]
published <- read.csv(file.path(root,'output/Supporting_data/nigeria_published_table_7_13_reason_distribution.csv'),check.names=FALSE)
all_dist <- vapply(1:16,function(k)100*sum(ev$wt[ev$reason_code==k])/sum(ev$wt),numeric(1))
check <- data.frame(reason=reason_labels,computed=round(all_dist,1),published=published[['All methods']])
print(check,row.names=FALSE)
cat('All-method endings:',nrow(ev),'weighted:',sum(ev$wt),'\n')
if(max(abs(check$computed-check$published))>0.2)stop('All-method DHS validation failed')
modern_codes <- c(1L,2L,3L,5L,6L,7L,11L,13L,14L,15L,17L,18L,19L,20L)
ev <- ev[ev$method_code %in% modern_codes,]
ev$method <- ifelse(ev$method_code==3,'Injectables',
  ifelse(ev$method_code==11,'Implants',
  ifelse(ev$method_code==1,'Pill',
  ifelse(ev$method_code==2,'IUD','Other modern'))))
ev$group <- ifelse(ev$reason_code==2,'Wanted pregnancy',
  ifelse(ev$reason_code %in% c(1,4:9),'Method experience/access',
  ifelse(ev$reason_code==3,'Partner disapproval','Other reasons')))
groups <- c('Wanted pregnancy','Method experience/access','Partner disapproval','Other reasons')
out <- do.call(rbind,lapply(c('All modern','Injectables','Implants','Pill','IUD','Other modern'),function(m){
  d <- if(m=='All modern')ev else ev[ev$method==m,]
  data.frame(method=m,reason_group=groups,
    percent=vapply(groups,function(g)100*sum(d$wt[d$group==g])/sum(d$wt),numeric(1)),
    unweighted_endings=nrow(d),weighted_endings=sum(d$wt))
}))
stopifnot(all(abs(tapply(out$percent,out$method,sum)-100)<1e-8))
dest <- file.path(root,'output/Supporting_data/nigeria_modern_five_year_reason_distribution.csv')
write.csv(out,dest,row.names=FALSE)
seven <- c('Wanted to become pregnant'=2,
  'Bleeding / other health'=NA,
  'Wanted a more effective method'=4,
  'Access / cost / convenience'=NA,
  'Method failure'=1,
  'Partner disapproval'=3,
  'Other recorded reasons'=NA)
seven_percent <- vapply(names(seven),function(label){
  codes <- switch(label,
    'Bleeding / other health'=5:6,
    'Access / cost / convenience'=7:9,
    'Other recorded reasons'=10:16,
    seven[[label]])
  100*sum(ev$wt[ev$reason_code %in% codes])/sum(ev$wt)
},numeric(1))
seven_out <- data.frame(reason=names(seven),percent=unname(seven_percent),
  unweighted_endings=nrow(ev),weighted_endings=sum(ev$wt))
stopifnot(abs(sum(seven_out$percent)-100)<1e-8)
write.csv(seven_out,file.path(root,'output/Supporting_data/nigeria_modern_five_year_reason_distribution_seven.csv'),row.names=FALSE)
print(seven_out,row.names=FALSE)
print(out[out$method=='All modern',],row.names=FALSE)
cat(dest,'\n')
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 89_nigeria_aft_duration_by_method.R
# LANGUAGE: R
MODULES[["89_nigeria_aft_duration_by_method.R"]] <- list(
  language="R",
  original_sha256="158523d270b12c8419c73c92dbcc8c634065b910bb868f2add188e1eb786fd52",
  packaged_sha256="158523d270b12c8419c73c92dbcc8c634065b910bb868f2add188e1eb786fd52",
  args=character(),
  code=r"-----(#!/usr/bin/env Rscript
# Nigeria DHS 2024: next-12-month actionable original-method ending risk
# conditional on a current user's elapsed method duration. Other endings
# compete. This is a descriptive AFT sensitivity analysis, not a forecast.

root <- Sys.getenv("NIGERIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
support <- file.path(root, 'output/Supporting_data')
e <- readRDS(file.path(root, 'Data/Derived/nigeria_2024_modern_episodes.rds'))
ir <- readRDS(file.path(root, 'Data/raw_dhs_ir/NG2024DHS__NGIR8BDT__IR_raw.rds'))
stocks <- read.csv(file.path(support, 'nigeria_current_users_by_method_and_actionable_projection.csv'))
landmark <- read.csv(file.path(support, 'nigeria_duration_aware_current_user_bridge.csv'))
wra26 <- read.csv(file.path(support, 'nigeria_2026_mcpr_scenarios.csv'))$wra_2026[1]

modern_codes <- c(1L,2L,3L,5L,6L,7L,11L,13L,14L,15L,17L,18L,19L,20L)
methods <- c('Injectables','Implants','Pill','IUD','Other modern')
method_group <- function(z) ifelse(z==3L,'Injectables',ifelse(z==11L,'Implants',
  ifelse(z==1L,'Pill',ifelse(z==2L,'IUD','Other modern'))))
actionable_codes <- c(1L,4L,5L,6L,7L,8L,10L,15L)

# AFT time from method start is identified only for visible starts. Episodes
# whose use began before calendar observation stay in descriptive life tables.
e <- e[e$entry==0L & e$method_code %in% modern_codes & e$exposure>0L,]
e$method <- factor(method_group(e$method_code),levels=methods)
e$action_event <- as.integer(e$discontinued & e$reason_code %in% actionable_codes)
e$other_event <- as.integer(e$discontinued & !e$reason_code %in% actionable_codes)
stopifnot(nrow(e)==7520L,all(e$action_event+e$other_event<=1L),
  all(e$exposure>=1L),max(e$exposure)<=72L)

suppressPackageStartupMessages(library(survival))
fit_candidates <- function(event){
  choices <- c('weibull','loglogistic','lognormal','exponential')
  fits <- lapply(choices,function(d)survreg(
    as.formula(paste0('Surv(exposure,',event,')~method')),
    data=e,weights=wt,dist=d,control=survreg.control(maxiter=100)))
  aic <- vapply(fits,AIC,0.0); names(aic) <- choices
  best <- which.min(aic)
  list(fit=fits[[best]],distribution=choices[best],aic=aic)
}
model_a <- fit_candidates('action_event')
model_o <- fit_candidates('other_event')
fit_a <- model_a$fit; fit_o <- model_o$fit
stopifnot(fit_a$iter<100,fit_o$iter<100)
models <- lapply(methods,function(m){
  d <- data.frame(method=factor(m,levels=methods))
  c(mu_a=as.numeric(predict(fit_a,newdata=d,type='lp')),
    scale_a=fit_a$scale,mu_o=as.numeric(predict(fit_o,newdata=d,type='lp')),
    scale_o=fit_o$scale)
})
names(models) <- methods
cumhaz <- function(t,mu,scale,dist){
  if(t<=0)return(0)
  if(dist=='weibull')return((t/exp(mu))^(1/scale))
  if(dist=='exponential')return(t/exp(mu))
  if(dist=='loglogistic')return(log1p(exp((log(t)-mu)/scale)))
  if(dist=='lognormal')return(-pnorm((log(t)-mu)/scale,lower.tail=FALSE,log.p=TRUE))
  stop('Unsupported AFT distribution')
}
next12 <- function(age,par){
  s <- 1; risk_a <- 0; risk_o <- 0
  for(t in seq.int(age+1,age+12)){
    da <- cumhaz(t,par['mu_a'],par['scale_a'],model_a$distribution)-
      cumhaz(t-1,par['mu_a'],par['scale_a'],model_a$distribution)
    do <- cumhaz(t,par['mu_o'],par['scale_o'],model_o$distribution)-
      cumhaz(t-1,par['mu_o'],par['scale_o'],model_o$distribution)
    total <- da+do
    event <- s*(-expm1(-total))
    if(total>0){risk_a <- risk_a+event*da/total;risk_o <- risk_o+event*do/total}
    s <- s*exp(-total)
  }
  c(actionable=risk_a,other=risk_o,any=risk_a+risk_o)
}

current <- ir[as.numeric(ir$v313)==3 & as.numeric(ir$v312) %in% modern_codes,]
current$method <- method_group(as.integer(current$v312))
current$elapsed <- as.integer(current$v337)
current$wt <- as.numeric(current$v005)/1e6
stopifnot(!anyNA(current$elapsed),all(current$elapsed>=0),
  all(current$method %in% methods))
rows <- lapply(methods,function(m){
  d <- current[current$method==m,]
  ages <- sort(unique(d$elapsed))
  risk <- vapply(ages,function(a)unname(next12(a,models[[m]])[1]),0.0)
  probability <- weighted.mean(risk[match(d$elapsed,ages)],d$wt)
  duration_weight <- tapply(d$wt,d$elapsed,sum)
  duration_weight <- duration_weight[order(as.numeric(names(duration_weight)))]
  median_duration <- as.numeric(names(duration_weight)[which(cumsum(duration_weight)>=sum(duration_weight)/2)[1]])
  stock <- stocks$current_users_2025[stocks$method==m]
  first <- stocks$actionable_first_year_risk_pct[stocks$method==m]
  old <- landmark$actionable_ending_risk_next12_pct[landmark$method==m]
  stopifnot(length(stock)==1L,length(first)==1L,length(old)==1L)
  data.frame(method=m,eligible_starts_n=sum(e$method==m),
    actionable_events_n=sum(e$method==m & e$action_event==1L),
    current_users_n=nrow(d),current_users_2025=stock,
    weighted_current_user_duration_median=median_duration,
    current_user_weight_share_duration_over60_pct=100*sum(d$wt[d$elapsed>60])/sum(d$wt),
    first_year_actionable_risk_pct=first,
    modeled_first_year_actionable_risk_pct=100*unname(next12(0,models[[m]])[1]),
    historical_landmark_next12_risk_pct=old,
    survival_model_next12_risk_pct=100*probability,
    survival_model_original_method_endings=stock*probability,
    gross_mcpr_equivalent_pp=100*stock*probability/wra26)
})
out <- do.call(rbind,rows)
out <- rbind(out,data.frame(method='All modern (EC excluded)',
  eligible_starts_n=sum(out$eligible_starts_n),
  actionable_events_n=sum(out$actionable_events_n),
  current_users_n=sum(out$current_users_n),
  current_users_2025=sum(out$current_users_2025),
  weighted_current_user_duration_median=NA_real_,
  current_user_weight_share_duration_over60_pct=100*sum(current$wt[current$elapsed>60])/sum(current$wt),
  first_year_actionable_risk_pct=weighted.mean(out$first_year_actionable_risk_pct,out$current_users_2025),
  modeled_first_year_actionable_risk_pct=weighted.mean(out$modeled_first_year_actionable_risk_pct,out$current_users_2025),
  historical_landmark_next12_risk_pct=weighted.mean(out$historical_landmark_next12_risk_pct,out$current_users_2025),
  survival_model_next12_risk_pct=weighted.mean(out$survival_model_next12_risk_pct,out$current_users_2025),
  survival_model_original_method_endings=sum(out$survival_model_original_method_endings),
  gross_mcpr_equivalent_pp=sum(out$gross_mcpr_equivalent_pp)))
stopifnot(all(is.finite(out$survival_model_next12_risk_pct)),
  all(out$survival_model_next12_risk_pct>=0 & out$survival_model_next12_risk_pct<=100))
write.csv(out,file.path(support,'nigeria_survival_model_duration_by_method.csv'),row.names=FALSE)
fit_report <- data.frame(distribution=names(model_a$aic),
  actionable_aic=as.numeric(model_a$aic),other_aic=as.numeric(model_o$aic),
  selected_actionable=names(model_a$aic)==model_a$distribution,
  selected_other=names(model_o$aic)==model_o$distribution)
write.csv(fit_report,file.path(support,'nigeria_survival_model_duration_fit.csv'),row.names=FALSE)
cat('Nigeria AFT gross original-method endings',sum(out$survival_model_original_method_endings[1:5]),'\n')
cat('Selected AFT distributions:',model_a$distribution,'for actionable,',model_o$distribution,'for other endings\n')
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 90_nigeria_aft_duration_by_method_cause.R
# LANGUAGE: R
MODULES[["90_nigeria_aft_duration_by_method_cause.R"]] <- list(
  language="R",
  original_sha256="40195f4a4cec99c244a718eccfeafa1539829ee3c58aa4bf0d454f3e2f8e83f2",
  packaged_sha256="40195f4a4cec99c244a718eccfeafa1539829ee3c58aa4bf0d454f3e2f8e83f2",
  args=character(),
  code=r"-----(#!/usr/bin/env Rscript
# Nigeria DHS 2024 sensitivity analysis: distribute the previously modeled next-year actionable
# original-method endings over the five established program-actionable causes.
# This is a calibrated cause-specific survival decomposition. It does not
# estimate modern-use exits or an intervention effect.
source(file.path(Sys.getenv("NIGERIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE)), 'Code/89_nigeria_aft_duration_by_method.R'), local=TRUE)
causes <- c('Method failure','Wanted more effective method',
  'Changes in menstrual bleeding','Other side effects/health',
  'Access/cost/convenience')
cause_codes <- list(c(1L),c(7L),c(15L),c(4L,5L),c(6L,8L,10L))
names(cause_codes) <- causes

# Each cause is an event in its own time-to-event fit. All other endings and
# survey censoring remain in the risk set until the corresponding time.
# Separate cause hazards are normalized to the master actionable hazard from
# script 166 so the cause-specific projections exactly reconcile to it.
fit_cause <- function(codes){
  e$cause_event <- as.integer(e$discontinued & e$reason_code %in% codes)
  choices <- c('weibull','loglogistic','lognormal','exponential')
  fits <- lapply(choices,function(d)tryCatch(survreg(
    Surv(exposure,cause_event)~method,data=e,weights=wt,dist=d,
    control=survreg.control(maxiter=100)),error=function(x)NULL))
  aic <- vapply(fits,function(f)if(is.null(f)) Inf else AIC(f),0.0)
  ix <- which.min(aic)
  stopifnot(is.finite(aic[ix]))
  list(fit=fits[[ix]],dist=choices[ix],aic=aic[ix],events=sum(e$cause_event))
}
fitted <- lapply(cause_codes,fit_cause)
cause_par <- lapply(methods,function(m){
  d <- data.frame(method=factor(m,levels=methods))
  lapply(fitted,function(f)c(mu=as.numeric(predict(f$fit,newdata=d,type='lp')),
                             scale=f$fit$scale))
})
names(cause_par) <- methods

next12_causes <- function(age,method){
  par <- models[[method]]
  result <- setNames(numeric(length(causes)),causes)
  survival <- 1
  for(t in seq.int(age+1,age+12)){
    ha <- cumhaz(t,par['mu_a'],par['scale_a'],model_a$distribution)-
      cumhaz(t-1,par['mu_a'],par['scale_a'],model_a$distribution)
    ho <- cumhaz(t,par['mu_o'],par['scale_o'],model_o$distribution)-
      cumhaz(t-1,par['mu_o'],par['scale_o'],model_o$distribution)
    raw <- vapply(seq_along(causes),function(j){
      p <- cause_par[[method]][[j]]
      cumhaz(t,p['mu'],p['scale'],fitted[[j]]$dist)-
        cumhaz(t-1,p['mu'],p['scale'],fitted[[j]]$dist)
    },0.0)
    stopifnot(all(raw>=-1e-10))
    raw <- pmax(raw,0)
    shares <- if(sum(raw)>0) raw/sum(raw) else rep(1/length(raw),length(raw))
    total <- ha+ho
    action_month <- survival*(-expm1(-total))*ha/total
    result <- result+action_month*shares
    survival <- survival*exp(-total)
  }
  stopifnot(abs(sum(result)-unname(next12(age,par)[1]))<1e-8)
  result
}

rows <- do.call(rbind,lapply(methods,function(m){
  d <- current[current$method==m,]
  ages <- sort(unique(d$elapsed))
  risks <- sapply(ages,function(a)next12_causes(a,m))
  if(is.null(dim(risks))) risks <- matrix(risks,nrow=length(causes))
  person_risk <- risks[,match(d$elapsed,ages),drop=FALSE]
  risk <- as.numeric(person_risk %*% d$wt/sum(d$wt))
  stock <- out$current_users_2025[out$method==m]
  data.frame(method=m,reason=causes,current_users_2025=stock,
    conditional_next12_risk_pct=100*risk,
    modeled_original_method_endings=stock*risk,
    gross_mcpr_equivalent_pp=100*stock*risk/wra26,
    cause_event_n=vapply(cause_codes,function(z)sum(e$method==m &
      e$discontinued & e$reason_code %in% z),0L))
}))
for(m in methods){
  a <- rows[rows$method==m,]
  b <- out[out$method==m,]
  stopifnot(abs(sum(a$modeled_original_method_endings)-
    b$survival_model_original_method_endings)<1e-5)
}
write.csv(rows,file.path(support,'nigeria_survival_model_duration_by_method_cause.csv'),row.names=FALSE)
write.csv(data.frame(cause=causes,distribution=vapply(fitted,`[[`,'','dist'),
  event_n=vapply(fitted,`[[`,0L,'events'),aic=vapply(fitted,`[[`,0.0,'aic')),
  file.path(support,'nigeria_survival_model_cause_fit.csv'),row.names=FALSE)
print(rows[,c('method','reason','conditional_next12_risk_pct',
  'modeled_original_method_endings','gross_mcpr_equivalent_pp','cause_event_n')],row.names=FALSE)
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 91_nigeria_aft_switching_bridge.R
# LANGUAGE: R
MODULES[["91_nigeria_aft_switching_bridge.R"]] <- list(
  language="R",
  original_sha256="4d2acbd3332a50766a00a534d0188940006b41698762d06be5c83e789e8bda5d",
  packaged_sha256="4d2acbd3332a50766a00a534d0188940006b41698762d06be5c83e789e8bda5d",
  args=character(),
  code=r"-----(#!/usr/bin/env Rscript
# Nigeria sensitivity analysis: combine AFT next-12-month cause-specific
# original-method ending risks with observed post-ending method pathways.
# The AFT model alone does not predict switching or modern use at year end.
# This hybrid borrows weighted DHS calendar transition fractions conditional on
# original method, actionable cause, and elapsed-duration bin. Sparse cells
# use an explicitly reported fallback. It is descriptive, not causal.
root <- Sys.getenv("NIGERIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
outdir <- file.path(root,'output/Supporting_data')
source(file.path(root,'Code/90_nigeria_aft_duration_by_method_cause.R'),local=TRUE)
landmarks <- readRDS(file.path(root,'Data/Derived/nigeria_historical_duration_landmarks.rds'))
historical <- read.csv(file.path(outdir,'nigeria_duration_aware_current_user_bridge.csv'))
historical_causes <- read.csv(file.path(outdir,'nigeria_duration_aware_current_user_by_cause.csv'))
bins <- c(-1,3,6,12,24,36,48,60,Inf)
bin_labels <- c('0–3','4–6','7–12','13–24','25–36','37–48','49–60','61+')
aft_causes <- rows
aft_methods <- out[out$method %in% methods,]

weighted_fraction <- function(d,flag){
  denom <- sum(d$wt)
  if(nrow(d)==0 || denom<=0)return(NA_real_)
  sum(d$wt*flag)/denom
}
transition <- function(m,c,b){
  use_bins <- if(b=='61+') c('37–48','49–60') else b
  exact <- landmarks[!is.na(landmarks$cause) & landmarks$method==m &
    landmarks$duration_bin %in% use_bins & landmarks$cause==c,]
  level <- 'method × cause × duration'
  d <- exact
  if(nrow(d)<10){
    d <- landmarks[!is.na(landmarks$cause) & landmarks$method==m & landmarks$cause==c,]
    level <- 'method × cause pooled over duration'
  }
  if(nrow(d)<10){
    d <- landmarks[!is.na(landmarks$cause) & landmarks$cause==c,]
    level <- 'cause pooled over methods and duration'
  }
  stopifnot(nrow(d)>0)
  c(direct=weighted_fraction(d,d$direct_switch),
    nonmodern=weighted_fraction(d,!d$modern_at_month12),
    n=nrow(d),level=level)
}

result <- list(); support <- list()
for(m in methods){
  people <- current[current$method==m,]
  people$duration_bin <- cut(people$elapsed,bins,labels=bin_labels)
  stopifnot(!anyNA(people$duration_bin))
  stock <- aft_methods$current_users_2025[aft_methods$method==m]
  all_weight <- sum(people$wt)
  for(c in causes){
    gross <- direct <- nonmodern <- 0
    for(b in bin_labels){
      sub <- people[people$duration_bin==b,]
      if(nrow(sub)==0)next
      ages <- sort(unique(sub$elapsed))
      risk <- vapply(ages,function(a)unname(next12_causes(a,m)[c]),0.0)
      contribution <- stock*sum(sub$wt*risk[match(sub$elapsed,ages)])/all_weight
      tr <- transition(m,c,b)
      gross <- gross+contribution
      direct <- direct+contribution*as.numeric(tr['direct'])
      nonmodern <- nonmodern+contribution*as.numeric(tr['nonmodern'])
      support[[length(support)+1L]] <- data.frame(method=m,reason=c,duration_bin=b,
        projected_endings=contribution,transition_source=unname(tr['level']),
        observed_actionable_endings_n=as.integer(tr['n']),
        observed_direct_switch_fraction=as.numeric(tr['direct']),
        observed_nonmodern_at_year_end_fraction=as.numeric(tr['nonmodern']))
    }
    result[[length(result)+1L]] <- data.frame(method=m,reason=c,
      current_users_2025=stock,model_original_method_endings=gross,
      hybrid_direct_modern_switches=direct,
      hybrid_modern_at_year_end=gross-nonmodern,
      hybrid_nonmodern_at_year_end=nonmodern,
      hybrid_year_end_nonmodern_mcpr_pp=100*nonmodern/wra26,
      gross_method_ending_mcpr_pp=100*gross/wra26)
  }
}
bridge <- do.call(rbind,result)
support <- do.call(rbind,support)
for(m in methods){
  a <- bridge[bridge$method==m,]
  b <- aft_methods[aft_methods$method==m,]
  stopifnot(abs(sum(a$model_original_method_endings)-
    b$survival_model_original_method_endings)<1e-5,
    all(a$hybrid_nonmodern_at_year_end>=0),
    all(a$hybrid_nonmodern_at_year_end<=a$model_original_method_endings))
}
write.csv(bridge,file.path(outdir,'nigeria_aft_switching_by_method_cause.csv'),row.names=FALSE)
write.csv(support,file.path(outdir,'nigeria_aft_switching_transition_support.csv'),row.names=FALSE)
method_summary <- aggregate(bridge[c('model_original_method_endings',
  'hybrid_direct_modern_switches','hybrid_modern_at_year_end',
  'hybrid_nonmodern_at_year_end','hybrid_year_end_nonmodern_mcpr_pp')],
  by=list(method=bridge$method),FUN=sum)
method_summary <- method_summary[match(methods,method_summary$method),]
method_summary$current_users_2025 <- aft_methods$current_users_2025
method_summary$conditional_next12_risk_pct <- aft_methods$survival_model_next12_risk_pct
write.csv(method_summary,file.path(outdir,'nigeria_aft_switching_by_method.csv'),row.names=FALSE)
compare <- data.frame(method=methods,
  historical_original_method_endings=historical$projected_actionable_original_method_endings,
  aft_original_method_endings=method_summary$model_original_method_endings,
  historical_nonmodern_at_year_end=historical$projected_nonmodern_at_month12_after_actionable,
  aft_hybrid_nonmodern_at_year_end=method_summary$hybrid_nonmodern_at_year_end,
  historical_mcpr_pp=historical$descriptive_nonmodern_at_month12_pp,
  aft_hybrid_mcpr_pp=method_summary$hybrid_year_end_nonmodern_mcpr_pp)
write.csv(compare,file.path(outdir,'nigeria_aft_vs_historical_switching_comparison.csv'),row.names=FALSE)
cat('AFT original endings',sum(method_summary$model_original_method_endings),
  '\nHybrid direct switches',sum(method_summary$hybrid_direct_modern_switches),
  '\nHybrid nonmodern at year end',sum(method_summary$hybrid_nonmodern_at_year_end),
  '\nHybrid year-end mCPR pp',sum(method_summary$hybrid_year_end_nonmodern_mcpr_pp),
  '\nSparse/fallback transition cells',sum(support$transition_source!='method × cause × duration'),
  'of',nrow(support),'\n')
print(compare,row.names=FALSE)
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 08a_extract_nigeria_wpp_population.py
# LANGUAGE: Python
MODULES[["08a_extract_nigeria_wpp_population.py"]] <- list(
  language="Python",
  original_sha256="1a1f737183c672910feca8b6fef8fabdff43066abbf2a79380a32d0eb3a10b41",
  packaged_sha256="967828c11743b6c9718585493a84d17db7387244c127dc1cfaf7bb0b32a76cef",
  args=character(),
  code=r"-----("""Extract Nigeria women aged 15–49 from the UN WPP 2024 medium variant.

Input is the official UN female single-age workbook already in the user's data
folder. The workbook reports thousands at 1 July, so sum ages 15–49 and
multiply by 1,000. Preserve fractional people for exact reproducibility;
tables round to whole women.
"""
import csv
import os
from pathlib import Path
import openpyxl

source = Path(os.environ['NIGERIA_PROJECT_ROOT']) / 'Data/References/WPP2024_POP_F01_3_POPULATION_SINGLE_AGE_FEMALE.xlsx'
out = Path(os.environ['NIGERIA_PROJECT_ROOT']) / 'output/Supporting_data/nigeria_wpp2024_wra_2024_2026.csv'
sheet = openpyxl.load_workbook(source, read_only=True, data_only=True)['Medium variant']
header = next(sheet.iter_rows(min_row=17,max_row=17,values_only=True))
assert header[5]=='ISO3 Alpha-code' and header[10]=='Year' and header[26]==15 and header[60]==49
rows=[]
for row in sheet.iter_rows(min_row=18, values_only=True):
    if row[5]=='NGA' and row[10] in (2024,2025,2026):
        rows.append({'year':row[10],'women_15_49':sum(float(row[11+a]) for a in range(15,50))*1000,
                     'source':'UN World Population Prospects 2024, female single ages, medium variant, 1 July'})
assert len(rows)==3
with out.open('w',newline='') as f:
    writer=csv.DictWriter(f,fieldnames=rows[0].keys());writer.writeheader();writer.writerows(rows)
print(rows)
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 16_nigeria_all_reason_current_user_bridge.py
# LANGUAGE: Python
MODULES[["16_nigeria_all_reason_current_user_bridge.py"]] <- list(
  language="Python",
  original_sha256="a2a5f2793676b5ae39bd4cd10fccc95b593f9a378f1cfd36720f1d2ab43bbd36",
  packaged_sha256="a2a5f2793676b5ae39bd4cd10fccc95b593f9a378f1cfd36720f1d2ab43bbd36",
  args=character(),
  code=r"-----(#!/usr/bin/env python3
"""Build the Ethiopia-style all-reason current-user planning bridge.

This is an illustration, not a next-year forecast: first-year probabilities
after method initiation are applied to the estimated 2025 current-user stock.
Method endings include switching and do not equal losses from modern use.
"""
import csv
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SUP = ROOT / "output/Supporting_data"


def read(name):
    with (SUP / name).open(newline="") as stream:
        return list(csv.DictReader(stream))


def write(name, rows, fields):
    with (SUP / name).open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


times = read("nigeria_modern_all_reason_timepoints.csv")
reasons = read("nigeria_modern_all_reason_reason_mix.csv")
users = read("nigeria_current_users_by_method_and_actionable_projection.csv")
methods = ["Injectables", "Implants", "Pill", "IUD", "Other modern"]
cause_names = [r["reason"] for r in reasons if r["scope"] == "National"]
summary = []
causes = []
for method in methods:
    user = next(r for r in users if r["method"] == method)
    life = next(r for r in times if r["scope"] == "National: " + method and r["month"] == "12")
    count = float(user["current_users_2025"])
    total = float(life["all_reason_pct"])
    summary.append({
        "method": method,
        "current_users_2025": count,
        "all_reason_first_year_risk_pct": total,
        "illustrative_original_method_endings": count * total / 100,
    })
    for reason in cause_names:
        entry = next(r for r in reasons if r["scope"] == "National: " + method and r["reason"] == reason)
        probability = float(entry["cause_specific_12_month_pct"])
        causes.append({
            "method": method,
            "reason": reason,
            "current_users_2025": count,
            "cause_specific_first_year_risk_pct": probability,
            "illustrative_original_method_endings": count * probability / 100,
        })
    cause_total = sum(float(r["illustrative_original_method_endings"]) for r in causes if r["method"] == method)
    assert abs(cause_total - summary[-1]["illustrative_original_method_endings"]) < 1e-6

write("nigeria_current_users_all_reason_projection.csv", summary, list(summary[0]))
write("nigeria_current_users_all_reason_by_cause.csv", causes, list(causes[0]))
print("All-reason illustrative original-method endings:", round(sum(r["illustrative_original_method_endings"] for r in summary)))
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 95_build_duration_planning_data.py
# LANGUAGE: Python
MODULES[["95_build_duration_planning_data.py"]] <- list(
  language="Python",
  original_sha256="4810707d5e0f27b2d90b24e9014ff7cecd89ee5aa18435e08e5a3219090fdd21",
  packaged_sha256="0739af4266246c1aaeef664e1fab5786c27657f767e08a1b87ed3e76f27577a7",
  args=character(),
  code=r"-----(#!/usr/bin/env python3
"""Build Nigeria counterparts to Ethiopia's historical/AFT planning tables."""
import csv
import json
from decimal import Decimal, ROUND_HALF_UP
import os
from pathlib import Path

root = Path(os.environ['NIGERIA_PROJECT_ROOT'])
support = root / 'output/Supporting_data'
out = root / 'output/nigeria_duration_planning_tables.json'

def read(name):
    with (support / name).open(newline='') as f:
        return list(csv.DictReader(f))

def f(row, key): return float(row[key])
def integer(x):
    return f"{int(Decimal(str(x)).quantize(Decimal('1'), rounding=ROUND_HALF_UP)):,}"
def percent(x, places=1): return f'{x:.{places}f}%'
def pp(x): return f'+{x:.2f} pp'

stocks = {r['method']: r for r in read('nigeria_current_users_by_method_and_actionable_projection.csv')}
scenarios = read('nigeria_2026_mcpr_scenarios.csv')
historical = {r['method']: r for r in read('nigeria_duration_aware_current_user_bridge.csv')}
historical_cause = {(r['method'], r['reason']): r for r in read('nigeria_duration_aware_current_user_by_cause.csv')}
aft = {r['method']: r for r in read('nigeria_aft_switching_by_method.csv')}
aft_cause = {(r['method'], r['reason']): r for r in read('nigeria_aft_switching_by_method_cause.csv')}
methods = ['Injectables', 'Implants', 'Pill', 'IUD', 'Other modern']
causes = ['Method failure', 'Wanted more effective method', 'Changes in menstrual bleeding',
          'Other side effects/health', 'Access/cost/convenience']
wra = f(scenarios[0], 'wra_2026')
current_total = sum(f(stocks[m], 'current_users_2025') for m in methods + ['EC'])
no_ec_total = sum(f(stocks[m], 'current_users_2025') for m in methods)

def build(label, method_data, cause_data, risk_col, net_col, cause_net_col,
          gross_col, historical_mode):
    net = {m: f(method_data[m], net_col) for m in methods}
    gross = {m: f(method_data[m], gross_col) for m in methods}
    total_net = sum(net.values())
    total_gross = sum(gross.values())
    assert abs(total_net - sum(f(cause_data[m, c], cause_net_col)
                               for m in methods for c in causes)) < 1e-4
    cause_total = {c: sum(f(cause_data[m, c], cause_net_col) for m in methods)
                   for c in causes}
    impact = 100 * total_net / wra
    prefix = 'Historical duration-aware' if historical_mode else 'AFT + observed pathways'
    method_table = [[
        'Method', 'Current mix (%)', 'Projected 2025 users',
        'Actionable ending risk (%)', 'Nonmodern at year end']]
    for m in methods:
        method_table.append([m, f(stocks[m], 'share_current_modern_pct'),
                             f(stocks[m], 'current_users_2025'),
                             f(method_data[m], risk_col), net[m]])
    method_table.append(['EC', f(stocks['EC'], 'share_current_modern_pct'),
                         f(stocks['EC'], 'current_users_2025'), 'Not applied', 'Not estimated'])
    method_table.append(['Current-user mix total, excluding EC',
                         sum(f(stocks[m], 'share_current_modern_pct') for m in methods),
                         no_ec_total, 100 * total_gross / no_ec_total, total_net])

    cause_table = [[
        'Method', 'Projected 2025 users', 'Method failure', 'Wanted more effective',
        'Bleeding changes', 'Other side effects / health',
        'Access / cost / convenience', 'Nonmodern at year end']]
    for m in methods:
        cause_table.append([m, f(stocks[m], 'current_users_2025'),
                            *(f(cause_data[m, c], cause_net_col) for c in causes), net[m]])
    cause_table.append(['All methods, excluding EC', no_ec_total,
                        *(cause_total[c] for c in causes), total_net])

    baseline_table = [['Scenario', '2024 DHS mCPR', 'Projected 2025 mCPR',
                       'Illustrative 2026 mCPR']]
    for s in scenarios:
        baseline_table.append([s['scenario'], f(s, 'mcpr_2024_pct'),
                               f(s, 'mcpr_2025_pct'), f(s, 'mcpr_2026_pct')])
    scenario_table = [['Different mCPR growth scenarios', '2026 users, usual endings',
                       '2026 mCPR', '2026 users if retained', 'Revised 2026 mCPR',
                       'Difference']]
    method_scenarios = []
    for s in scenarios:
        usual = f(s, 'usual_users_2026')
        retained = usual + total_net
        scenario_table.append([s['scenario'], usual, f(s, 'mcpr_2026_pct'),
                               retained, 100 * retained / wra, impact])
        t = [['Method', 'Projected 2025 users', '2026 users', 'Year-end loss averted',
              '2026 if averted', '2026 mCPR', 'mCPR if averted']]
        for m in methods + ['EC']:
            usual_m = usual * f(stocks[m], 'current_users_2025') / current_total
            add = net.get(m, 0)
            t.append([m, f(stocks[m], 'current_users_2025'), usual_m,
                      add if m != 'EC' else '—', usual_m + add,
                      100 * usual_m / wra, 100 * (usual_m + add) / wra])
        t.append(['All modern', current_total, usual, total_net,
                  retained, f(s, 'mcpr_2026_pct'), 100 * retained / wra])
        method_scenarios.append(t)
    pp_table = [['Method / measure', 'Method failure', 'Want more effective',
                 'Bleeding changes', 'Other side effects / health',
                 'Access / cost / convenience', 'All actionable causes']]
    for m in methods:
        pp_table.append([m, *(f(cause_data[m, c], cause_net_col) for c in causes),
                         net[m]])
    pp_table.append(['Estimated nonmodern at year end',
                     *(cause_total[c] for c in causes), total_net])
    pp_table.append(['2026 women aged 15–49', *(wra for _ in causes), wra])
    pp_table.append(['Maximum mCPR equivalent',
                     *(100 * cause_total[c] / wra for c in causes), impact])

    if historical_mode:
        prob = ('Weighted 12-month actionable ending probability from historical '
                'method-duration calendar landmarks. The 61+ month current-user '
                'band uses observed 37–60-month risks. Year-end nonmodern counts '
                'include observed switching and restarting pathways.')
        caveat = ('Historical, descriptive projection; results assume past '
                  'method-duration and post-ending patterns apply to projected 2025 users.')
    else:
        prob = ('Two survey-weighted, method-only AFT models estimate actionable '
                'and other-ending hazards. Cause-specific AFT patterns split the '
                'actionable risk; observed post-ending pathways determine year-end '
                'nonmodern use.')
        caveat = ('Exploratory hybrid; 73 of 200 method × cause × duration transition '
                  'cells needed pooled fallback estimates. IUD cause fits have as '
                  'few as one observed event. No uncertainty interval is available.')

    raw = [method_table, cause_table, baseline_table, scenario_table,
           *method_scenarios, pp_table]
    kinds = ['method', 'cause', 'baseline', 'scenario',
             'method_scenario', 'method_scenario', 'method_scenario', 'cause_pp']
    titles = [f'{prefix}: actionable endings', f'{prefix}: year-end loss by cause',
              f'{prefix}: common 2026 mCPR baselines',
              f'{prefix}: mCPR if year-end loss avoided',
              f'{prefix}: no-growth mCPR by method',
              f'{prefix}: DHS-growth mCPR by method',
              f'{prefix}: FP2030-growth mCPR by method',
              f'{prefix}: mCPR equivalent by actionable cause']
    subtitle = [
        'Projected 2025 current users; next 12 months conditional on time already used',
        f'Projected 2025 current users; {integer(total_net)} nonmodern at year end',
        '2024 DHS baseline; projected 2025 and illustrative 2026 mCPR scenarios',
        f'{integer(total_net)} year-end nonmodern users after actionable endings',
        'No further mCPR growth in 2026',
        'DHS-anchored +0.4 percentage points per year',
        'FP2030 2025 modeled level +0.4 percentage points in 2026',
        'Year-end nonmodern users after actionable original-method endings']
    notes = [
        prob + ' ' + caveat + ' EC has no continuing-use risk.',
        ('Each cause count = projected 2025 users × the method- and cause-specific '
         'probability of an actionable ending followed by no modern use at year end. ' + caveat),
        ('The three mCPR baselines use Nigeria DHS 2024 all-women mCPR, Nigeria '
         '2025/2026 women aged 15–49 projections, and stated annual changes. '
         'These are planning scenarios, not observed 2026 outcomes.'),
        (f'{integer(total_net)} ÷ {integer(wra)} projected 2026 women aged 15–49 '
         f'= {pp(impact)}. Counts are calculated before rounding. ' + caveat),
        *[(f'Each mCPR contribution = method users ÷ {integer(wra)} projected 2026 '
           'women aged 15–49. Year-end loss averted uses ' + prob + ' ' + caveat)
          for _ in range(3)],
        (f'Each cause mCPR equivalent = year-end nonmodern users ÷ {integer(wra)} '
         'projected 2026 women aged 15–49. ' + caveat),
    ]

    def display(kind, table):
        result = []
        for i, row in enumerate(table):
            if i == 0:
                result.append([str(x) for x in row]); continue
            formatted = []
            for j, val in enumerate(row):
                if isinstance(val, str): formatted.append(val)
                elif kind == 'method' and j in (1, 3): formatted.append(f'{val:.1f}')
                elif kind == 'baseline' and j >= 1: formatted.append(percent(val, 2))
                elif kind == 'scenario' and j in (2, 4): formatted.append(percent(val, 2))
                elif kind == 'scenario' and j == 5: formatted.append(pp(val))
                elif kind == 'method_scenario' and j in (5, 6): formatted.append(percent(val, 2))
                elif kind == 'cause_pp' and i == len(table)-1 and j >= 1:
                    formatted.append(f'{val:.2f} pp')
                else: formatted.append(integer(val))
            result.append(formatted)
        return result
    slides = [dict(title=titles[i], subtitle=subtitle[i], kind=kinds[i],
                   table=display(kinds[i], raw[i]), note=notes[i]) for i in range(8)]
    return dict(label=label, total_gross=total_gross, total_net=total_net,
                mcpr_equivalent_pp=impact, slides=slides)

blocks = [build('historical', historical, historical_cause,
                'actionable_ending_risk_next12_pct',
                'projected_nonmodern_at_month12_after_actionable',
                'projected_nonmodern_at_month12',
                'projected_actionable_original_method_endings', True),
          build('aft', aft, aft_cause, 'conditional_next12_risk_pct',
                'hybrid_nonmodern_at_year_end', 'hybrid_nonmodern_at_year_end',
                'model_original_method_endings', False)]
out.write_text(json.dumps(dict(country='Nigeria', wra_2026=wra,
                               current_users_2025=current_total,
                               blocks=blocks), indent=2))
print(out)
for block in blocks:
    print(block['label'], 'gross', integer(block['total_gross']),
          'year-end nonmodern', integer(block['total_net']),
          'mCPR equivalent', pp(block['mcpr_equivalent_pp']))

# Reconcile final presentation labels, without altering arithmetic.

labels = {'DHS anchored +0.4 pp/year': 'Track20 growth (+0.4 pp)',
          'FP2030 2025 level +0.4 pp': 'UN growth (about +0.5 pp)',
          'Actionable ending risk (%)': 'Potentially actionable discontinuation (%)'}
def final_labels(value):
    if isinstance(value,str): return labels.get(value,value)
    if isinstance(value,list): return [final_labels(x) for x in value]
    if isinstance(value,dict): return {k:final_labels(v) for k,v in value.items()}
    return value
out.write_text(json.dumps(final_labels(json.loads(out.read_text())),indent=2))
)-----"
)

MODULES[["202_nigeria_survey_coefficients.R"]] <- list(
 language="R",
 packaged_sha256="e7da5a9c883391c8ae52256769c1e5d08c72e11dd41755b566825734caf1d4b1",
 args=character(),
 code=r"-----(suppressPackageStartupMessages(library(nnet))
root<-Sys.getenv("NIGERIA_PROJECT_ROOT");out<-file.path(root,"output/Supporting_data")
p<-readRDS(file.path(root,'Data/Derived/nigeria_2024_person_month.rds'))
ir<-readRDS(file.path(root,'Data/raw_dhs_ir/NG2024DHS__NGIR8BDT__IR_raw.rds'))
f<-unique(data.frame(cluster=as.numeric(ir$v021),stratum=as.numeric(ir$v022)))
g<-split(seq_len(nrow(f)),f$stratum);df<-nrow(f)-length(g)
rows<-list()
for(k in 1:2){
 m<-readRDS(file.path(root,paste0('Data/Derived/nigeria_actionable_zone_model_',k,'.rds')))
 X<-model.matrix(delete.response(terms(m)),p,contrasts.arg=m$contrasts)
 pr<-predict(m,newdata=p,type='probs');lev<-m$lev[-1]
 score<-do.call(cbind,lapply(lev,function(y)X*(p$wt*(as.numeric(p$outcome==y)-pr[,y]))))
 expected<-unlist(lapply(lev,function(y)paste(y,colnames(X),sep=':')))
 stopifnot(identical(colnames(m$Hessian),expected))
 s<-matrix(0,nrow(f),ncol(score));a<-rowsum(score,p$cluster);s[match(rownames(a),f$cluster),]<-a
 meat<-matrix(0,ncol(s),ncol(s));for(ids in g){z<-s[ids,,drop=FALSE];z<-sweep(z,2,colMeans(z));meat<-meat+length(ids)/(length(ids)-1)*crossprod(z)}
 bread<-MASS::ginv(m$Hessian);v<-bread%*%meat%*%bread;se<-sqrt(pmax(diag(v),0));be<-as.vector(t(coef(m)));crit<-qt(.975,df)
 rows[[k]]<-data.frame(model=if(k==1)'Method + duration'else'Full',outcome=rep(lev,each=ncol(X)),covariate=rep(colnames(X),length(lev)),odds_ratio=exp(be),ci_low=exp(be-crit*se),ci_high=exp(be+crit*se),p_value=2*pt(-abs(be/se),df),survey_se=se,design_df=df)
 saveRDS(v,file.path(out,paste0('model_',k,'_survey_vcov.rds')))
}
write.csv(do.call(rbind,rows),file.path(out,'nigeria_actionable_zone_model_odds_ratios.csv'),row.names=FALSE)
cat('Full-frame cluster/strata sandwich:',nrow(f),'PSUs;',length(g),'strata;',df,'degrees of freedom\n')
)-----"
)

MODULES[["203_nigeria_planning_survey_ci.R"]] <- list(
 language="R",
 packaged_sha256="ac0d61fa27e3a7c8cf1ebb7d2dba85ab8c301bd15c844bebfd70a1f04bc68d26",
 args=character(),
 code=r"-----(#!/usr/bin/env Rscript
# Survey-design inference for Nigeria planning scenarios. All inputs are parameters.
# Fixed population and growth assumptions; uncertainty includes IR sampling,
# current-use composition, empirical risks, fitted AFT parameters and pathways.
# AFT intervals condition on the previously selected distribution families.
root<-normalizePath(Sys.getenv('NIGERIA_PROJECT_ROOT'));out<-file.path(root,'output/survey_planning');dir.create(out,recursive=TRUE,showWarnings=FALSE)
B<-as.integer(Sys.getenv('NIGERIA_PLANNING_BOOTSTRAP_REPS','500'));cores<-4L
suppressPackageStartupMessages(library(survival))
ir<-readRDS(file.path(root,'Data/raw_dhs_ir/NG2024DHS__NGIR8BDT__IR_raw.rds'))
e<-readRDS(file.path(root,'Data/Derived/nigeria_2024_modern_episodes.rds'))
cal<-readRDS(file.path(root,'Data/Derived/nigeria_2024_calendar_events.rds'))
sup<-file.path(root,'output/Supporting_data')
script_file<-sub('^--file=','',grep('^--file=',commandArgs(FALSE),value=TRUE)[1])
signature<-unname(tools::md5sum(c(script_file,file.path(root,'Data/raw_dhs_ir/NG2024DHS__NGIR8BDT__IR_raw.rds'),file.path(root,'Data/Derived/nigeria_2024_modern_episodes.rds'),file.path(root,'Data/Derived/nigeria_2024_calendar_events.rds'),file.path(sup,'nigeria_wpp2024_wra_2024_2026.csv'),file.path(sup,'nigeria_survival_model_duration_fit.csv'),file.path(sup,'nigeria_survival_model_cause_fit.csv'))))
cache_signature<-file.path(out,'cache_signature.rds')
if(file.exists(cache_signature)){if(!identical(signature,readRDS(cache_signature)))stop('Inputs or code changed. Use a fresh output directory for bootstrap results.')}else{
 if(length(list.files(file.path(out,'replicates'))))stop('Unversioned bootstrap cache: use a fresh output directory.')
 saveRDS(signature,cache_signature)
}

pop<-read.csv(file.path(sup,'nigeria_wpp2024_wra_2024_2026.csv'))
w25<-pop$women_15_49[pop$year==2025];w26<-pop$women_15_49[pop$year==2026]
w24<-pop$women_15_49[pop$year==2024]
methods<-c('Injectables','Implants','Pill','IUD','Other modern')
causes<-c('Method failure','Wanted more effective method','Changes in menstrual bleeding','Other side effects/health','Access/cost/convenience')
codes<-list(1L,7L,15L,c(4L,5L),c(6L,8L,10L)); action<-unlist(codes)
modern<-c(1L,2L,3L,5L,6L,7L,11L,13L,14L,15L,17L,18L,19L,20L)
endpoint_modern<-c(modern,16L)
method_group<-function(x)ifelse(x==3,'Injectables',ifelse(x==11,'Implants',ifelse(x==1,'Pill',ifelse(x==2,'IUD','Other modern'))))
cause_group<-function(x){z<-rep(NA_integer_,length(x));for(j in 1:5)z[x %in% codes[[j]]]<-j;z}
wt<-as.numeric(ir$v005)/1e6;psu<-as.numeric(ir$v021);stratum<-as.numeric(ir$v022)
frame<-unique(data.frame(psu,stratum)); stopifnot(!anyDuplicated(frame$psu))
strata<-split(seq_len(nrow(frame)),frame$stratum);stopifnot(all(lengths(strata)>1))
psu_index<-match(psu,frame$psu)
u<-as.numeric(ir$v313)==3;umethod<-method_group(as.numeric(ir$v312));umethod[as.numeric(ir$v312)==16]<-'EC'
uindex<-which(u & as.numeric(ir$v312) %in% modern)
current<-data.frame(woman=uindex,method=umethod[uindex],elapsed=as.numeric(ir$v337[uindex]),wt=wt[uindex])
stopifnot(all(is.finite(current$elapsed)),all(current$elapsed>=0))
bins<-c(-1,3,6,12,24,36,48,60,Inf);blabel<-c('0–3','4–6','7–12','13–24','25–36','37–48','49–60','61+')
current$bin<-as.integer(cut(current$elapsed,bins))
# Reconstruct historical landmarks with an explicit year-end modern-use definition.
bywoman<-split(seq_len(nrow(cal)),cal$woman_row)
spells<-cal[cal$method_code %in% modern & cal$start>cal$calendar_start,]
records<-vector('list',nrow(spells))
for(i in seq_len(nrow(spells))){a<-spells[i,];last<-min(a$end,a$interview-15L);if(last<a$start)next
 t<-seq.int(a$start,last);future<-t+12L;timeline<-cal[bywoman[[as.character(a$woman_row)]],]
 code<-timeline$method_code[findInterval(future,timeline$start)]
 ended<-a$end<future & a$reason_code %in% action
 records[[i]]<-data.frame(woman=a$woman_row,episode=i,method=method_group(a$method_code),elapsed=t-a$start,wt=a$wt,
 cause=ifelse(ended,cause_group(a$reason_code),NA_integer_),net=ended & !code %in% endpoint_modern,
 net_legacy=ended & !code %in% modern, direct=ended & timeline$method_code[findInterval(a$end+1L,timeline$start)] %in% endpoint_modern)
}
land<-do.call(rbind,records);land$bin<-as.integer(cut(land$elapsed,bins))
# 61+ months has no direct complete-follow-up support; preserve documented proxy.
ci_index<-lapply(methods,function(m)which(current$method==m));names(ci_index)<-methods
land_index<-lapply(methods,function(m)lapply(1:8,function(b)which(land$method==m & land$bin %in% if(b==8)c(6,7)else b)));names(land_index)<-methods
# Fit data and fixed selected families (model-selection uncertainty is not included).
af<-e[e$entry==0 & e$exposure>0,];af$method<-factor(af$method_group,levels=methods)
af$action_event<-as.integer(af$discontinued & af$reason_code %in% action)
af$other_event<-as.integer(af$discontinued & !af$reason_code %in% action)
for(j in 1:5)af[[paste0('cause',j)]]<-as.integer(af$discontinued & af$reason_code %in% codes[[j]])
fam<-read.csv(file.path(sup,'nigeria_survival_model_duration_fit.csv'));cfam<-read.csv(file.path(sup,'nigeria_survival_model_cause_fit.csv'))
dists<-c(fam$distribution[fam$selected_actionable],fam$distribution[fam$selected_other],cfam$distribution[match(causes,cfam$cause)])
events<-c('action_event','other_event',paste0('cause',1:5));stopifnot(length(dists)==7,!anyNA(dists))
maxage<-max(current$elapsed)+12L;time<-0:maxage
cumhaz<-function(t,mu,sc,dist){
 if(dist=='weibull')return((t/exp(mu))^(1/sc))
 if(dist=='exponential')return(t/exp(mu))
 if(dist=='loglogistic')return(log1p(exp((log(t)-mu)/sc)))
 if(dist=='lognormal')return(-pnorm((log(t)-mu)/sc,lower.tail=FALSE,log.p=TRUE))
 stop('Unknown family')}
transition_index<-list();support<-list()
for(m in methods)for(b in 1:8)for(j in 1:5){
 z<-which(land$method==m & land$bin %in% (if(b==8)c(6,7)else b) & land$cause==j)
 # Use unique episodes, not repeated landmarks, to assess support.
 n<-length(unique(land$episode[z]));level<-'method × cause × duration'
 if(n<10){z<-which(land$method==m & land$cause==j);n<-length(unique(land$episode[z]));level<-'method × cause'}
 if(n<10){z<-which(land$cause==j);n<-length(unique(land$episode[z]));level<-'cause pooled over methods'}
 stopifnot(n>0);key<-paste(m,b,j,sep='|');transition_index[[key]]<-z
 support[[key]]<-data.frame(method=m,duration_bin=blabel[b],cause=causes[j],unique_episodes=n,unique_women=length(unique(land$woman[z])),landmarks=length(z),pooling=level)
}
write.csv(do.call(rbind,support),file.path(out,'switching_support.csv'),row.names=FALSE)
measure<-function(mult,replicate=0L){
 iw<-wt*mult[psu_index];ew<-e$wt*mult[psu_index[e$woman_row]];lw<-land$wt*mult[psu_index[land$woman]];cw<-current$wt*mult[psu_index[current$woman]]
 mcpr<-100*sum(iw[u])/sum(iw);mix<-vapply(c(methods,'EC'),function(m)sum(iw[u & umethod==m])/sum(iw[u]),0.0)
 stock<-w25*(mcpr+.4)/100*mix
 # Main gross estimates, year-end switching sensitivities, and direct-switch diagnostics.
 result<-array(0,c(8,5,5),dimnames=list(c('First-year gross','Historical gross','AFT gross','Historical switching','AFT switching','First-year direct switches','Historical direct switches','AFT direct switches'),methods,causes))
 risk<-result
 for(m in methods){d<-which(e$method_group==m);surv<-1;v<-numeric(5)
  for(t in 1:12){at<-d[e$entry[d]<t & e$exposure[d]>=t];den<-sum(ew[at]);if(den<=0)next
   end<-at[e$discontinued[at] & e$exposure[at]==t];h<-vapply(codes,function(cc)sum(ew[end[e$reason_code[end] %in% cc]])/den,0.0)
   v<-v+surv*h;surv<-surv*(1-sum(ew[end])/den)}
  risk[1,m,]<-v
  ends<-d[e$discontinued[d] & e$exposure[d]<=12 & e$reason_code[d] %in% action]
  denend<-sum(ew[ends]);target<-if(denend>0)sum(v)*sum(ew[ends][e$next_code[ends] %in% endpoint_modern])/denend else 0
  raw<-vapply(1:5,function(j){ii<-ends[e$reason_code[ends] %in% codes[[j]]];den<-sum(ew[ii]);if(den>0)v[j]*sum(ew[ii][e$next_code[ii] %in% endpoint_modern])/den else 0},0)
  risk[6,m,]<-if(sum(raw)>0)raw*target/sum(raw) else raw
  ix<-ci_index[[m]];cwtotal<-sum(cw[ix]);for(b in 1:8){share<-sum(cw[ix[current$bin[ix]==b]])/cwtotal;if(share==0)next
   z<-land_index[[m]][[b]];den<-sum(lw[z]);if(den<=0)stop('Empty landmark cell')
   for(j in 1:5){risk[2,m,j]<-risk[2,m,j]+share*sum(lw[z][!is.na(land$cause[z]) & land$cause[z]==j])/den
    risk[4,m,j]<-risk[4,m,j]+share*sum(lw[z][!is.na(land$cause[z]) & land$cause[z]==j & land$net[z]])/den
    risk[7,m,j]<-risk[7,m,j]+share*sum(lw[z][!is.na(land$cause[z]) & land$cause[z]==j & land$direct[z]])/den}}
 }
 aw<-af$wt*mult[psu_index[af$woman_row]]
 fits<-lapply(seq_along(events),function(j){ad<-af[aw>0,];ad$fw<-aw[aw>0];active<-methods[vapply(methods,function(m)sum(ad[[events[j]]][ad$method==m]),0)>0];ad<-ad[ad$method %in% active,];ad$method<-droplevels(ad$method);fit<-suppressWarnings(survreg(as.formula(paste0('Surv(exposure,',events[j],')~method')),data=ad,weights=fw,dist=dists[j],control=survreg.control(maxiter=500)));if(fit$iter>=500||any(!is.finite(coef(fit))))stop(paste('AFT convergence failure',events[j],dists[j]));attr(fit,'active_methods')<-active;fit})
 for(m in methods){nd<-data.frame(method=factor(m,levels=methods));hh<-sapply(seq_along(fits),function(j){f<-fits[[j]];if(!m %in% attr(f,'active_methods'))return(rep(0,length(time)-1));mu<-as.numeric(predict(f,newdata=nd,type='lp'));diff(cumhaz(time,mu,f$scale,dists[j]))})
  ix<-ci_index[[m]];den<-sum(cw[ix]);for(age in unique(current$elapsed[ix])){z<-ix[current$elapsed[ix]==age];share<-sum(cw[z])/den;if(share==0)next
   h<-hh[age+1:12,,drop=FALSE];total<-h[,1]+h[,2];s<-c(1,exp(-cumsum(total)))[1:12];monthly<-s*(-expm1(-total))*ifelse(total>0,h[,1]/total,0)
   hcause<-pmax(h[,3:7,drop=FALSE],0);cs<-hcause/pmax(rowSums(hcause),1e-300);if(any(!is.finite(cs)))stop('Invalid cause split')
   v<-colSums(monthly*cs);risk[3,m,]<-risk[3,m,]+share*v
   b<-as.integer(cut(age,bins));for(j in 1:5){q<-transition_index[[paste(m,b,j,sep='|')]];fraction<-sum(lw[q]*land$net[q])/sum(lw[q]);risk[5,m,j]<-risk[5,m,j]+share*v[j]*fraction;risk[8,m,j]<-risk[8,m,j]+share*v[j]*sum(lw[q]*land$direct[q])/sum(lw[q])}}
 }
 for(m in methods)result[,m,]<-risk[,m,]*stock[m]
 stopifnot(all(is.finite(result)),all(result>=0),all(apply(risk,c(1,2),sum)<=1+1e-8))
 list(counts=result,risk=risk,mcpr=mcpr,mix=mix,stock=stock,users2024=w24*mcpr/100*mix)
}
point<-measure(rep(1,nrow(frame)));saveRDS(point,file.path(out,'planning_point.rds'))
# Preserve and verify gross estimands before running resampling.
href<-read.csv(file.path(sup,'nigeria_duration_aware_current_user_bridge.csv'));aref<-read.csv(file.path(sup,'nigeria_aft_switching_by_method.csv'))
stopifnot(max(abs(rowSums(point$counts[2,,])-href$projected_actionable_original_method_endings[match(methods,href$method)]))<.1,
 max(abs(rowSums(point$counts[3,,])-aref$model_original_method_endings[match(methods,aref$method)]))<.1)
cat('Point totals:',apply(point$counts,1,sum),'\n');flush.console()
checkpoint<-file.path(out,'replicates');dir.create(checkpoint,showWarnings=FALSE)
one<-function(b){dest<-file.path(checkpoint,sprintf('rep_%04d.rds',b));if(file.exists(dest))return(readRDS(dest));set.seed(20261105L+b)
 mult<-numeric(nrow(frame));for(ids in strata){n<-length(ids);mult[ids]<-n/(n-1)*tabulate(sample.int(n,n-1,replace=TRUE),nbins=n)}
 v<-tryCatch(measure(mult,b),error=function(e)list(error=conditionMessage(e)));saveRDS(v,dest);v}
if(B>0){draws<-parallel::mclapply(seq_len(B),one,mc.cores=cores,mc.preschedule=FALSE);valid<-!vapply(draws,function(x)!is.null(x$error),FALSE)
 cat('Valid',sum(valid),'of',B,'\n');stopifnot(mean(valid)>=.95);saveRDS(draws,file.path(out,'planning_replicates.rds'))}
saveRDS(list(wra2024=w24,wra2025=w25,wra2026=w26,psus=nrow(frame),strata=length(strata),replicates=B,methods=methods,causes=causes,definitions=c('Gross: every actionable original-method ending treated as year-end loss','Switching sensitivity: EC included in modern use at year end; support assessed on unique episodes','AFT uncertainty conditional on selected distribution families','Population and growth scenarios fixed')),file.path(out,'planning_metadata.rds'))
)-----"
)

MODULES[["204_summarize_planning.R"]] <- list(
 language="R",
 packaged_sha256="0b74caa7a9797f39c1c0e9f2291dfc4e7cab73de20c633bd2a92da5948515ef0",
 args=character(),
 code=r"-----(o<-file.path(Sys.getenv("NIGERIA_PROJECT_ROOT"),"output/survey_planning");p<-readRDS(file.path(o,'planning_point.rds'));d<-readRDS(file.path(o,'planning_replicates.rds'));meta<-readRDS(file.path(o,'planning_metadata.rds'))
metrics<-function(x){
 x$counts<-abind::abind(x$counts,x$counts[1,,,drop=FALSE]-x$counts[6,,,drop=FALSE],x$counts[2,,,drop=FALSE]-x$counts[4,,,drop=FALSE],x$counts[3,,,drop=FALSE]-x$counts[5,,,drop=FALSE],along=1)
 y<-c(stock_no_ec=sum(x$stock[meta$methods]),mcpr2024=x$mcpr,mcpr2025=x$mcpr+.4,users2025=sum(x$stock),users2024=sum(x$users2024))
 for(m in c(meta$methods,'EC'))y[paste('stock',m,sep='|')]<-x$stock[m]
 for(i in 1:11)for(m in c(meta$methods,'Total'))for(c in c(meta$causes,'Total')){
  mi<-if(m=='Total')1:5 else match(m,meta$methods);ci<-if(c=='Total')1:5 else match(c,meta$causes)
  v<-sum(x$counts[i,mi,ci]);s<-if(m=='Total')sum(x$stock[meta$methods])else x$stock[m]
  key<-paste(i,m,c,sep='|');y[paste0('count|',key)]<-v;y[paste0('pp|',key)]<-100*v/meta$wra2026;y[paste0('risk|',key)]<-100*v/s
 }
 base<-c(x$mcpr+.4,x$mcpr+.8,14.0)
 for(j in 1:3){y[paste0('base|',j)]<-base[j];y[paste0('baseusers|',j)]<-base[j]/100*meta$wra2026
  for(i in 1:11)for(m in c(meta$methods,'EC','Total')){
   mix<-if(m=='Total')1 else x$mix[m];add<-if(m=='Total')sum(x$counts[i,,])else if(m=='EC')0 else sum(x$counts[i,m,]);b<-base[j]*mix;key<-paste(j,i,m,sep='|')
   y[paste0('usualusers|',key)]<-b/100*meta$wra2026;y[paste0('retainedusers|',key)]<-b/100*meta$wra2026+add
   y[paste0('usualmcpr|',key)]<-b;y[paste0('retainedmcpr|',key)]<-b+100*add/meta$wra2026
  }
 }
 y
}
pt<-metrics(p);ds<-vapply(d,metrics,pt);lo<-apply(ds,1,quantile,.025);hi<-apply(ds,1,quantile,.975)
write.csv(data.frame(key=names(pt),estimate=unname(pt),lower=unname(lo),upper=unname(hi)),file.path(o,'planning_intervals.csv'),row.names=FALSE)
jsonlite::write_json(meta,file.path(o,'metadata.json'),auto_unbox=TRUE,pretty=TRUE)
cat('95% intervals for',length(pt),'metrics from',ncol(ds),'valid replicates\n')
)-----"
)


# Parameterized input/preparation helpers
# Parameterized, local-file input validation. No API calls are made.
read_validated_ir <- function(ir_file, expected_sha256='') {
  for (pkg in c('haven','jsonlite','digest'))
    if (!requireNamespace(pkg, quietly=TRUE)) stop('Install required R package: ',pkg,call.=FALSE)
  if (!nzchar(ir_file) || !file.exists(ir_file))
    stop('Supply an existing authorized IR file with --ir-file or DHS_IR_FILE.',call.=FALSE)
  ext <- tolower(tools::file_ext(ir_file))
  allowed <- if(COUNTRY=='Ethiopia') 'dta' else c('dta','rds')
  if (!ext %in% allowed) stop('Unsupported input format for this country.',call.=FALSE)
  sha <- digest::digest(file=ir_file, algo='sha256')
  if (nzchar(expected_sha256) && (!grepl('^[a-fA-F0-9]{64}$',expected_sha256) ||
      !identical(tolower(expected_sha256),sha)))
    stop('Input SHA-256 does not match --expected-ir-sha256.',call.=FALSE)
  x <- tryCatch(if(ext=='dta') as.data.frame(haven::read_dta(ir_file)) else readRDS(ir_file),
    error=function(e)stop('Cannot read the supplied IR file; verify format and integrity.',call.=FALSE))
  if (!is.data.frame(x)) stop('IR input must be a woman-level data frame.',call.=FALSE)
  expected <- if(COUNTRY=='Ethiopia') c(21395L,6648L,797L,27L) else c(39050L,6411L,1380L,74L)
  required <- c('caseid','v000','v005','v008','v011','v012','v017','v018','v019',
                'v021','v022','v024','v025','v106','v190','v312','v313','v337',
                'v501','vcal_1','vcal_2')
  if(COUNTRY=='Nigeria') required<-c(required,'sstate')
  missing <- setdiff(required,names(x))
  if(length(missing))stop('Required IR variables missing: ',paste(missing,collapse=', '),call.=FALSE)
  if(anyDuplicated(names(x)) || anyDuplicated(x$caseid) || anyNA(x$caseid))
    stop('IR variables and woman identifiers must be unique and nonmissing.',call.=FALSE)
  if(nrow(x)!=expected[1] || ncol(x)!=expected[2])
    stop('IR dimensions differ from the validated country release; review before analysis.',call.=FALSE)
  num <- function(k)as.numeric(x[[k]])
  if(!all(as.character(x$v000)==if(COUNTRY=='Ethiopia')'ET8'else'NG8'))
    stop('Wrong country/recode phase.',call.=FALSE)
  keys<-c('v005','v008','v011','v012','v017','v018','v019','v021','v022','v024')
  if(any(vapply(keys,function(k)any(!is.finite(num(k))),FALSE)))
    stop('Nonfinite required dates, weights or survey-design fields.',call.=FALSE)
  stopifnot(all(num('v005')>0),all(num('v012')%in%15:49),
    all(num('v019')>=1 & num('v019')<=80),
    all(num('v008')-num('v017')+1==num('v019')),
    all(num('v018')+num('v019')==81),
    is.character(x$vcal_1),is.character(x$vcal_2),
    !anyNA(x$vcal_1),!anyNA(x$vcal_2),all(nchar(x$vcal_1)==80L),
    all(nchar(x$vcal_2)<=80L),length(grep('^b3_',names(x)))>0)
  f<-unique(data.frame(psu=num('v021'),stratum=num('v022')))
  stopifnot(nrow(f)==expected[3],length(unique(f$stratum))==expected[4],
    !anyDuplicated(f$psu),all(table(f$stratum)>1))
  if(COUNTRY=='Nigeria')stopifnot(all(num('v024')%in%1:6))
  # Never trim, reverse, filter or impute the raw input here.
  list(data=x,sha256=sha,format=ext,rows=nrow(x),columns=ncol(x),
       psus=nrow(f),strata=length(unique(f$stratum)))
}

write_ir_validation <- function(root, v) {
  dest<-file.path(root,'output','validation');dir.create(dest,recursive=TRUE,showWarnings=FALSE)
  fields<-list(country=COUNTRY,input_parameter='--ir-file or DHS_IR_FILE',
    format=v$format,sha256=v$sha256,women=v$rows,variables=v$columns,
    psus=v$psus,strata=v$strata,calendar_alignment='passed',unique_women='passed',
    source_file_modified=FALSE,api_used=FALSE,
    validated_utc=format(Sys.time(),'%Y-%m-%dT%H:%M:%SZ',tz='UTC'))
  jsonlite::write_json(fields,file.path(dest,'input_validation.json'),auto_unbox=TRUE,pretty=TRUE)
  packages<-c('haven','jsonlite','digest','survey','survival','nnet','ggplot2')
  vers<-vapply(packages,function(p)if(requireNamespace(p,quietly=TRUE))
    as.character(utils::packageVersion(p))else'not installed','')
  write.csv(data.frame(package=c('R',packages),version=c(as.character(getRversion()),vers)),
    file.path(dest,'software_versions.csv'),row.names=FALSE)
}

complete_preparation_audit <- function(root, v) {
  prefix<-if(COUNTRY=='Ethiopia')'ethiopia'else'nigeria'
  derived<-file.path(root,'Data','Derived')
  load<-function(name)readRDS(file.path(derived,name))
  events<-load(paste0(prefix,'_2024_calendar_events.rds'))
  ep<-load(if(COUNTRY=='Ethiopia')'ethiopia_2024_table_7_11_episodes.rds'else'nigeria_2024_table_7_12_episodes.rds')
  months<-load(paste0(prefix,'_2024_calendar_months.rds'))
  cov<-load(if(COUNTRY=='Ethiopia')'ethiopia_2024_full_model_episode_covariates.rds'else'nigeria_2024_model_episode_covariates.rds')
  person<-load(paste0(prefix,'_2024_person_month.rds'))
  frame<-load(paste0(prefix,'_2024_full_survey_frame.rds'))
  stopifnot(nrow(months)==sum(as.integer(v$data$v019)),
    nrow(months)==sum(events$duration),all(ep$entry<ep$exposure),
    all(ep$entry<12),!anyDuplicated(ep$episode_id),
    nrow(frame)==v$psus,length(unique(frame$stratum))==v$strata,
    all(ep$wt==as.numeric(v$data$v005[ep$woman_row])/1e6),
    sum(person$outcome=='actionable')>0,
    !anyNA(person[,c('wt','cluster','stratum','month','outcome')]))
  for_month<-if(COUNTRY=='Ethiopia')cov else cov
  stopifnot(nrow(person)==sum(pmin(12L,for_month$exposure)-for_month$entry))
  # Every retained episode-month uses the original woman's weight; other
  # endings remain competing events. Calendar nonuse is not a method episode.
  if(COUNTRY=='Ethiopia'){
    audit<-jsonlite::read_json(file.path(root,'output/Supporting_data/Table_7_11/table_7_11_results.json'))$audit
    stopifnot(audit$rate_cells_matching==66,audit$count_cells_matching==6,
      nrow(events)==89220,nrow(ep)==9068,nrow(cov)==8611,nrow(person)==70691,
      sum(person$outcome=='actionable')==1321)
    validated_cells<-66L;validated_counts<-6L
  }else{
    audit<-read.csv(file.path(root,'output/Supporting_data/nigeria_table_7_12_validation.csv'))
    stopifnot(sum(audit$rate_cells_matching)==110,all(audit$episode_count_matching),
      nrow(events)==163203,nrow(ep)==11210,nrow(cov)==8341,nrow(person)==69445)
    validated_cells<-110L;validated_counts<-10L
  }
  files<-list.files(derived,pattern='\\.rds$',full.names=TRUE)
  hashes<-data.frame(file=paste0('Data/Derived/',basename(files)),
    sha256=vapply(files,function(f)digest::digest(file=f,algo='sha256'),''))
  dest<-file.path(root,'output/validation')
  write.csv(hashes,file.path(dest,'derived_file_checksums.csv'),row.names=FALSE)
  result<-list(country=COUNTRY,input_sha256=v$sha256,
    calendar_runs=nrow(events),calendar_months=nrow(months),
    published_table_episodes=nrow(ep),model_episodes=nrow(cov),
    model_episode_months=nrow(person),psus=nrow(frame),strata=v$strata,
    dhs_rate_cells_matching=validated_cells,dhs_episode_counts_matching=validated_counts,
    input_preparation_complete=TRUE,full_html_regeneration=FALSE,
    html_and_pptx_modified=FALSE)
  jsonlite::write_json(result,file.path(dest,'preparation_validation.json'),
    auto_unbox=TRUE,pretty=TRUE,digits=15)
  cat('Preparation passed: ',nrow(events),' calendar runs; ',nrow(ep),
      ' published-table episodes; ',nrow(cov),' model episodes.\n',sep='')
}


MODULES[["210_prepare_analysis_inputs.R"]] <- list(language="R", packaged_sha256="7c971daf985e31ccbb3fdefa9857fb8ae4a3ccbe0353b772fda53be2d8ddc23f", args=character(), code=r"-----(#!/usr/bin/env Rscript
# Reuse existing country data definitions; stop before fitting any model.
root<-Sys.getenv('NIGERIA_PROJECT_ROOT');stopifnot(nzchar(root))
derived<-file.path(root,'Data','Derived');prefix<-'nigeria'

local({
#!/usr/bin/env Rscript
# Nigeria DHS 2024 descriptive analysis. Run after 01_nigeria_calendar_life_table.R.
# No package download is needed. The source IR recode stays unchanged.
# The outcome is cessation of the ORIGINAL modern method within 12 months for
# one of eight potentially actionable calendar reason codes. All other endings
# remain competing events. Emergency contraception is excluded because it is
# an episodic intervention, although it remains in official mCPR tabulations.
# Six geopolitical zones (v024) are the primary subnational geography.

root <- Sys.getenv("NIGERIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
full_ir <- readRDS(file.path(root,'Data/raw_dhs_ir/NG2024DHS__NGIR8BDT__IR_raw.rds'))
full_frame <- unique(data.frame(cluster=as.numeric(full_ir$v021),stratum=as.numeric(full_ir$v022)))

support <- file.path(root,'output/Supporting_data')
derived <- file.path(root,'Data/Derived')
e <- readRDS(file.path(derived,'nigeria_2024_table_7_12_episodes.rds'))
ir <- readRDS(file.path(Sys.getenv("NIGERIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE)), 'Data/raw_dhs_ir/NG2024DHS__NGIR8BDT__IR_raw.rds'))
stopifnot(nrow(ir)==39050L,nrow(e)==11210L)

zone_names <- c('North West','North East','North Central','South East','South South','South West')
e$zone_name <- zone_names[e$zone]
e$cluster <- as.numeric(ir$v021[e$woman_row])
e$stratum <- as.numeric(ir$v022[e$woman_row])
e$method_group <- 'Other modern'
e$method_group[e$method_code==1] <- 'Pill'
e$method_group[e$method_code==2] <- 'IUD'
e$method_group[e$method_code==3] <- 'Injectables'
e$method_group[e$method_code==11] <- 'Implants'
modern_codes <- c(1L,2L,3L,5L,6L,7L,11L,13L,14L,15L,17L,18L,19L,20L)
e <- e[e$method_code %in% modern_codes,]
stopifnot(!any(e$method_code==16L),all(e$zone %in% 1:6))
saveRDS(e,file.path(derived,'nigeria_2024_modern_episodes.rds'))

})
local({
#!/usr/bin/env Rscript
# Nigeria DHS 2024: adjusted zone comparison for actionable discontinuation.
# Run after scripts 01 and 02. Unit of fitting is the episode-month. Outcomes
# are continuation, actionable discontinuation, and another competing ending.
# Therefore pregnancy intentions, partner disapproval, other fertility reasons,
# and unresolved reasons remain in the starting cohort and leave at their end.
# The two multinomial discrete-time models mirror the Ethiopia specification:
# A: month of method use, method, zone; B: A plus measured characteristics.
# Method use month is elapsed duration since the ORIGINAL method began, not
# duration at interview. Both models retain delayed-entry episodes for fitting.
# Adjusted zone probabilities predict a 12-month first-year trajectory on the
# SAME observed-start national episodes with each zone assigned in turn. This
# is common-composition standardization, not each zone's actual observed mix.

root <- Sys.getenv("NIGERIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
full_ir <- readRDS(file.path(root,'Data/raw_dhs_ir/NG2024DHS__NGIR8BDT__IR_raw.rds'))
full_frame <- unique(data.frame(cluster=as.numeric(full_ir$v021),stratum=as.numeric(full_ir$v022)))

support <- file.path(root,'output/Supporting_data')
derived <- file.path(root,'Data/Derived')
if(!requireNamespace('nnet',quietly=TRUE))stop('nnet package is required')
e <- readRDS(file.path(derived,'nigeria_2024_modern_episodes.rds'))
ir <- readRDS(file.path(Sys.getenv("NIGERIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE)), 'Data/raw_dhs_ir/NG2024DHS__NGIR8BDT__IR_raw.rds'))
actionable <- c(1L,4L,5L,6L,7L,8L,10L,15L)
e$zone_name <- factor(e$zone_name,
  levels=c('North West','North East','North Central','South East','South South','South West'))
e$method_group <- factor(e$method_group,
  levels=c('IUD','Injectables','Implants','Pill','Other modern'))
e$age_at_start <- (e$start-as.numeric(ir$v011[e$woman_row]))/12
stopifnot(all(e$age_at_start>=10),all(e$age_at_start<50))
# A small number of calendar episodes began before age 15, although every
# respondent was 15–49 at interview. Retain them in an honestly labeled group.
e$age_group <- factor(ifelse(e$age_at_start<20,'Under 20',
  ifelse(e$age_at_start<25,'20–24',ifelse(e$age_at_start<35,'25–34','35–49'))),
  levels=c('25–34','Under 20','20–24','35–49'))
bcols <- grep('^b3_',names(ir),value=TRUE)
b <- as.matrix(ir[e$woman_row,bcols])
parity <- rowSums(!is.na(b) & b<=e$start)
e$parity_group <- factor(ifelse(parity==0,'0',ifelse(parity<=2,'1–2',
  ifelse(parity<=4,'3–4','5+'))),levels=c('0','1–2','3–4','5+'))
marital <- as.numeric(ir$v501[e$woman_row])
e$marital_group <- factor(ifelse(marital==0,'Never in union',
  ifelse(marital==1,'Married',ifelse(marital==2,'Living together',
  'Formerly in union'))),
  levels=c('Married','Never in union','Living together','Formerly in union'))
educ <- as.numeric(ir$v106[e$woman_row])
e$education <- factor(ifelse(educ==0,'None',ifelse(educ==1,'Primary',
  ifelse(educ %in% c(2,3),'Secondary or higher',NA_character_))),
  levels=c('None','Primary','Secondary or higher'))
e$wealth <- factor(c('Poorest','Poorer','Middle','Richer','Richest')[
  as.numeric(ir$v190[e$woman_row])],
  levels=c('Poorest','Poorer','Middle','Richer','Richest'))
e$residence <- factor(ifelse(as.numeric(ir$v025[e$woman_row])==1,'Urban','Rural'),
  levels=c('Urban','Rural'))
# Very recent 2024 starts contribute only 50 episodes and no observed
# actionable endings in the DHS window. A separate 2024 indicator therefore
# perfectly separates the event outcome. Pool 2023 and 2024 starts so the
# cohort term remains estimable while retaining all eligible episodes.
year <- (e$start-1L)%/%12L+1900L
e$start_year <- factor(ifelse(year>=2023,'2023–24',as.character(year)))
complete <- complete.cases(e[,c('method_group','zone_name','age_group',
  'parity_group','marital_group','education','wealth','residence','start_year')])
cat('Complete-case episodes:',sum(complete),'of',nrow(e),'\n')
e <- e[complete,]
saveRDS(e,file.path(derived,'nigeria_2024_model_episode_covariates.rds'))

observed_months <- pmax(0L,pmin(12L,e$exposure)-e$entry)
idx <- rep(seq_len(nrow(e)),observed_months)
month <- unlist(Map(function(first,n)seq.int(first+1L,length.out=n),
  e$entry,observed_months),use.names=FALSE)
person <- e[idx,c('wt','cluster','stratum','method_group','zone_name',
  'age_group','parity_group','marital_group','education','wealth',
  'residence','start_year')]
person$month <- factor(month,levels=1:12)
end <- e$discontinued[idx] & month==e$exposure[idx]
person$outcome <- factor(ifelse(!end,'continue',
  ifelse(e$reason_code[idx] %in% actionable,'actionable','competing')),
  levels=c('continue','actionable','competing'))
stopifnot(!anyNA(person),nrow(person)>40000)
saveRDS(person,file.path(derived,'nigeria_2024_person_month.rds'))

})
ir<-readRDS(file.path(root,'Data/raw_dhs_ir/NG2024DHS__NGIR8BDT__IR_raw.rds'))

# Save an explicit month-level calendar alongside the original run-level data.
# Nonuse, pregnancy, births and terminations remain in this broad calendar.
# Only method-use episodes enter discontinuation denominators.
cal <- readRDS(file.path(derived,paste0(prefix,'_2024_calendar_events.rds')))
w <- rep(seq_len(nrow(cal)),cal$duration)
offset <- sequence(cal$duration)-1L
cmc <- as.integer(cal$start[w]+offset)
wr <- cal$woman_row[w]
position <- as.integer(ir$v018[wr]+ir$v008[wr]-cmc)
stopifnot(all(position>=1L & position<=80L))
month_data <- data.frame(woman_row=wr,calendar_month_cmc=cmc,
 calendar_position=position,method_code=cal$method_code[w],
 method_character=substring(ir$vcal_1[wr],position,position),
 reason_character=substring(sprintf('%-80s',ir$vcal_2[wr]),position,position),
 wt=as.numeric(ir$v005[wr])/1e6,cluster=as.numeric(ir$v021[wr]),
 stratum=as.numeric(ir$v022[wr]))
# Assert exact character alignment, rather than checking row counts alone.
chars<-strsplit('123456789WNALCFEMS~','')[[1]]
expected_code<-match(month_data$method_character,chars)
for(pair in list(c('0',0L),c('B',81L),c('T',82L),c('P',83L),c('?',99L)))
 expected_code[month_data$method_character==pair[1]]<-as.integer(pair[2])
stopifnot(!anyNA(expected_code),all(expected_code==month_data$method_code),
 all(tabulate(month_data$woman_row,nbins=nrow(ir))==as.integer(ir$v019)))
saveRDS(month_data,file.path(derived,paste0(prefix,'_2024_calendar_months.rds')))
frame<-unique(data.frame(cluster=as.numeric(ir$v021),stratum=as.numeric(ir$v022)))
saveRDS(frame,file.path(derived,paste0(prefix,'_2024_full_survey_frame.rds')))
current<-which(as.integer(ir$v313)==3L)
current_users<-data.frame(woman_row=current,method_code=as.integer(ir$v312[current]),
 elapsed_months=as.numeric(ir$v337[current]),wt=as.numeric(ir$v005[current])/1e6,
 cluster=as.numeric(ir$v021[current]),stratum=as.numeric(ir$v022[current]),
 region=as.integer(ir$v024[current]))
saveRDS(current_users,file.path(derived,paste0(prefix,'_2024_current_modern_users.rds')))
cat('Created source-aligned calendar months, full survey frame and current-user inputs.\n')
)-----")

# Register labelled-variable conversions in every fresh module subprocess.
for (module_name in names(MODULES)) if(MODULES[[module_name]]$language=='R') {
  MODULES[[module_name]]$code <- paste0("if(!requireNamespace('haven',quietly=TRUE))stop('Install R package haven first.')\n", MODULES[[module_name]]$code)
}

# Execute only when called as the command-line entry point.

# Latest revision calculations and incremental report rendering.
REVISED_GROWTH_ASSUMPTIONS <- r"--------({
  "scenarios": [
    {
      "scenario": "6-year DHS trend",
      "annual_change_pp": 0.4318981911348668
    },
    {
      "scenario": "11-year DHS trend",
      "annual_change_pp": 0.1777353742882184
    },
    {
      "scenario": "FPET-informed growth",
      "annual_change_pp": 0.4
    }
  ],
  "rates_from": {
    "dhs2013": 11.149075984364499,
    "dhs2018": 10.5127759547257,
    "dhs2024": 13.104165101534901,
    "fpet2024": 13.2,
    "fpet2025": 13.6
  }
})--------"
REVISED_TABLE_SCHEMA <- r"--------([
  {
    "title": "First-year: actionable discontinuation and mCPR",
    "kind": "method",
    "approach": 1,
    "scenario": null
  },
  {
    "title": "First-year: users by method and cause",
    "kind": "cause",
    "approach": 1,
    "scenario": null
  },
  {
    "title": "First-year: mCPR growth scenarios",
    "kind": "baseline",
    "approach": 1,
    "scenario": 3
  },
  {
    "title": "First-year: mCPR if actionable losses are avoided",
    "kind": "scenario",
    "approach": 1,
    "scenario": 3
  },
  {
    "title": "First-year: 6-year DHS trend by method",
    "kind": "method_scenario",
    "approach": 1,
    "scenario": 1
  },
  {
    "title": "First-year: 11-year DHS trend by method",
    "kind": "method_scenario",
    "approach": 1,
    "scenario": 2
  },
  {
    "title": "First-year: FPET-informed growth by method",
    "kind": "method_scenario",
    "approach": 1,
    "scenario": 3
  },
  {
    "title": "First-year: mCPR equivalent by cause",
    "kind": "cause_pp",
    "approach": 1,
    "scenario": null
  },
  {
    "title": "Historical duration-aware: actionable discontinuation and mCPR",
    "kind": "method",
    "approach": 2,
    "scenario": null
  },
  {
    "title": "Historical duration-aware: users by method and cause",
    "kind": "cause",
    "approach": 2,
    "scenario": null
  },
  {
    "title": "Historical duration-aware: mCPR growth scenarios",
    "kind": "baseline",
    "approach": 2,
    "scenario": 3
  },
  {
    "title": "Historical duration-aware: mCPR if actionable losses are avoided",
    "kind": "scenario",
    "approach": 2,
    "scenario": 3
  },
  {
    "title": "Historical duration-aware: 6-year DHS trend by method",
    "kind": "method_scenario",
    "approach": 2,
    "scenario": 1
  },
  {
    "title": "Historical duration-aware: 11-year DHS trend by method",
    "kind": "method_scenario",
    "approach": 2,
    "scenario": 2
  },
  {
    "title": "Historical duration-aware: FPET-informed growth by method",
    "kind": "method_scenario",
    "approach": 2,
    "scenario": 3
  },
  {
    "title": "Historical duration-aware: mCPR equivalent by cause",
    "kind": "cause_pp",
    "approach": 2,
    "scenario": null
  },
  {
    "title": "AFT survival: actionable discontinuation and mCPR",
    "kind": "method",
    "approach": 3,
    "scenario": null
  },
  {
    "title": "AFT survival: users by method and cause",
    "kind": "cause",
    "approach": 3,
    "scenario": null
  },
  {
    "title": "AFT survival: mCPR growth scenarios",
    "kind": "baseline",
    "approach": 3,
    "scenario": 3
  },
  {
    "title": "AFT survival: mCPR if actionable losses are avoided",
    "kind": "scenario",
    "approach": 3,
    "scenario": 3
  },
  {
    "title": "AFT survival: 6-year DHS trend by method",
    "kind": "method_scenario",
    "approach": 3,
    "scenario": 1
  },
  {
    "title": "AFT survival: 11-year DHS trend by method",
    "kind": "method_scenario",
    "approach": 3,
    "scenario": 2
  },
  {
    "title": "AFT survival: FPET-informed growth by method",
    "kind": "method_scenario",
    "approach": 3,
    "scenario": 3
  },
  {
    "title": "AFT survival: mCPR equivalent by cause",
    "kind": "cause_pp",
    "approach": 3,
    "scenario": null
  },
  {
    "title": "Historical sensitivity: actionable discontinuation and mCPR",
    "kind": "method",
    "approach": 4,
    "scenario": null
  },
  {
    "title": "Historical sensitivity: users by method and cause",
    "kind": "cause",
    "approach": 4,
    "scenario": null
  },
  {
    "title": "Historical sensitivity: mCPR growth scenarios",
    "kind": "baseline",
    "approach": 4,
    "scenario": 3
  },
  {
    "title": "Historical sensitivity: mCPR if actionable losses are avoided",
    "kind": "scenario",
    "approach": 4,
    "scenario": 3
  },
  {
    "title": "Historical sensitivity: 6-year DHS trend by method",
    "kind": "method_scenario",
    "approach": 4,
    "scenario": 1
  },
  {
    "title": "Historical sensitivity: 11-year DHS trend by method",
    "kind": "method_scenario",
    "approach": 4,
    "scenario": 2
  },
  {
    "title": "Historical sensitivity: FPET-informed growth by method",
    "kind": "method_scenario",
    "approach": 4,
    "scenario": 3
  },
  {
    "title": "Historical sensitivity: mCPR equivalent by cause",
    "kind": "cause_pp",
    "approach": 4,
    "scenario": null
  },
  {
    "title": "AFT sensitivity: actionable discontinuation and mCPR",
    "kind": "method",
    "approach": 5,
    "scenario": null
  },
  {
    "title": "AFT sensitivity: users by method and cause",
    "kind": "cause",
    "approach": 5,
    "scenario": null
  },
  {
    "title": "AFT sensitivity: mCPR growth scenarios",
    "kind": "baseline",
    "approach": 5,
    "scenario": 3
  },
  {
    "title": "AFT sensitivity: mCPR if actionable losses are avoided",
    "kind": "scenario",
    "approach": 5,
    "scenario": 3
  },
  {
    "title": "AFT sensitivity: 6-year DHS trend by method",
    "kind": "method_scenario",
    "approach": 5,
    "scenario": 1
  },
  {
    "title": "AFT sensitivity: 11-year DHS trend by method",
    "kind": "method_scenario",
    "approach": 5,
    "scenario": 2
  },
  {
    "title": "AFT sensitivity: FPET-informed growth by method",
    "kind": "method_scenario",
    "approach": 5,
    "scenario": 3
  },
  {
    "title": "AFT sensitivity: mCPR equivalent by cause",
    "kind": "cause_pp",
    "approach": 5,
    "scenario": null
  }
])--------"
REVISION_HELPERS <- list(
  "300_revised_planning.R" = r"--------(#!/usr/bin/env Rscript
# Usage: compute_2025.R SAVED_STATS_DIR VERIFIED_GROWTH_JSON OUTPUT_DIR
# Reuses saved point estimates and 500 survey bootstrap draws. Models are not refitted.
a<-commandArgs(TRUE);stopifnot(length(a)==3)
suppressPackageStartupMessages(library(jsonlite))
point<-readRDS(file.path(a[1],'planning_point.rds'));reps<-readRDS(file.path(a[1],'planning_replicates.rds'));meta<-readRDS(file.path(a[1],'planning_metadata.rds'))
outdir<-a[3];dir.create(outdir,recursive=TRUE,showWarnings=FALSE)
verified<-fromJSON(a[2]);rates<-verified$scenarios$annual_change_pp
labels<-verified$scenarios$scenario
meta$epsilon<-0
metrics<-function(x){
 counts<-x$risk
 for(m in meta$methods)counts[,m,]<-x$risk[,m,]*x$users2024[m]
 counts<-abind::abind(counts,counts[1,,,drop=FALSE]-counts[6,,,drop=FALSE],counts[2,,,drop=FALSE]-counts[4,,,drop=FALSE],counts[3,,,drop=FALSE]-counts[5,,,drop=FALSE],along=1)
 y<-c(stock_no_ec=sum(x$users2024[meta$methods]),mcpr2024=x$mcpr,users2024=sum(x$users2024))
 for(m in c(meta$methods,'EC'))y[paste('stock',m,sep='|')]<-x$users2024[m]
 for(i in 1:11)for(m in c(meta$methods,'Total'))for(ca in c(meta$causes,'Total')){
  mi<-if(m=='Total')1:5 else match(m,meta$methods);ci<-if(ca=='Total')1:5 else match(ca,meta$causes)
  v<-sum(counts[i,mi,ci]);stock<-if(m=='Total')sum(x$users2024[meta$methods])else x$users2024[m];key<-paste(i,m,ca,sep='|')
  y[paste0('count|',key)]<-v;y[paste0('pp|',key)]<-100*v/meta$wra2025;y[paste0('risk|',key)]<-100*v/stock
 }
 for(j in 1:3){base<-x$mcpr+rates[j];y[paste0('base|',j)]<-base;y[paste0('baseusers|',j)]<-base/100*meta$wra2025
  for(i in 1:5)for(m in c(meta$methods,'EC','Total')){
   share<-if(m=='Total')1 else x$mix[m];add<-if(m=='Total')sum(counts[i,,])else if(m=='EC')0 else sum(counts[i,m,]);usual<-base*share
   key<-paste(j,i,m,sep='|');y[paste0('usualusers|',key)]<-usual/100*meta$wra2025;y[paste0('retainedusers|',key)]<-usual/100*meta$wra2025+add
   y[paste0('usualmcpr|',key)]<-usual;y[paste0('retainedmcpr|',key)]<-usual+100*add/meta$wra2025
  }
 }
 for(i in 1:5)for(m in c(meta$methods,'Total'))for(ca in c(meta$causes,'Total')){
  base<-if(i==4)2 else if(i==5)3 else i;key<-paste(i,m,ca,sep='|');den<-y[paste0('count|',base,'|',m,'|',ca)]
  y[paste0('fraction|',key)]<-if(den>0)100*y[paste0('count|',key)]/den else 0
 }
 copykeys<-names(y)[grepl('^(count|pp|stock|base|usualusers|retainedusers|usualmcpr|retainedmcpr)[|]',names(y))]
 for(k in copykeys)y[paste0('legacy_',k)]<-y[k]
 y['legacy_stock|Total']<-sum(x$users2024)
 y
}
pt<-metrics(point);ds<-vapply(reps,metrics,pt);ds<-pt+(ds-pt)/(1-meta$epsilon)
lo<-apply(ds,1,quantile,.025);hi<-apply(ds,1,quantile,.975);lo<-pmax(0,pmin(lo,pt));hi<-pmax(hi,pt)
pct<-grepl('^(risk|usualmcpr|retainedmcpr)[|]',names(pt));hi[pct]<-pmin(100,hi[pct])
write.csv(data.frame(key=names(pt),estimate=unname(pt),lower=unname(lo),upper=unname(hi)),file.path(outdir,'revised_planning_intervals.csv'),row.names=FALSE)
write.csv(data.frame(key=names(pt),estimate=unname(pt),lower=unname(lo),upper=unname(hi)),file.path(outdir,'planning_intervals.csv'),row.names=FALSE)
meta$reference_year<-2024;meta$outcome_year<-2025;meta$definitions[4]<-'Observed 2024 current-user cohort; 2025 mCPR under recent DHS, longer-term DHS, or FPET-informed annual change. Growth and population assumptions are fixed.'
write_json(meta,file.path(outdir,'metadata.json'),auto_unbox=TRUE,pretty=TRUE)
summary<-data.frame(scenario=labels,annual_change_pp=rates,mcpr2024=point$mcpr,mcpr2025=point$mcpr+rates,users2024=sum(point$users2024),users2025=(point$mcpr+rates)/100*meta$wra2025)
write.csv(summary,file.path(outdir,'scenario_summary.csv'),row.names=FALSE)
jsonlite::write_json(list(scenarios=summary,reference_year=2024,outcome_year=2025,wra2024=meta$wra2024,wra2025=meta$wra2025,methods=meta$methods,causes=meta$causes,replicates=length(reps),rates_from=verified$rates_from,reference_stock=as.list(point$users2024),ending_totals=sapply(1:5,function(i)pt[paste0('count|',i,'|Total|Total')]),pp_totals=sapply(1:5,function(i)pt[paste0('pp|',i,'|Total|Total')])),file.path(outdir,'revision_inputs.json'),auto_unbox=TRUE,pretty=TRUE,digits=15)
stopifnot(!anyNA(pt),all(pt[grepl('^(count|pp)[|]',names(pt))]>=-1e-6))
cat('2025 mCPR gains (gross first-year / historical / AFT; switching historical / AFT):\n');print(sapply(1:5,function(i)pt[paste0('pp|',i,'|Total|Total')]))
print(summary)
)--------",
  "301_revised_tables.py" = r"--------(#!/usr/bin/env python3
"""Usage: build_tables.py REVISED_STATS_DIR ORIGINAL_SPECS_JSON OUTPUT_DIR"""
from pathlib import Path
import sys,csv,json,copy
stats,oldfile,out=map(Path,sys.argv[1:]);out.mkdir(exist_ok=True,parents=True)
meta=json.loads((stats/'revision_inputs.json').read_text());D={r['key']:{k:float(r[k]) for k in ['estimate','lower','upper']} for r in csv.DictReader((stats/'revised_planning_intervals.csv').open())}
methods=meta['methods'];causes=meta['causes'];old=json.loads(oldfile.read_text())
labels=[f'6-year DHS trend\n({meta["scenarios"][0]["annual_change_pp"]:+.2f} pp/year)',f'11-year DHS trend\n({meta["scenarios"][1]["annual_change_pp"]:+.2f} pp/year)',f'FPET-informed growth\n({meta["scenarios"][2]["annual_change_pp"]:+.2f} pp/year)']
short=['6-year DHS trend','11-year DHS trend','FPET-informed growth']
def val(key,kind='num',deck=False):
 x=D[key];scale=1000 if deck and kind=='num' else 1;digits=(1 if deck else 0) if kind=='num' else 1 if kind=='risk' else 2
 def f(y):return '<0.01' if kind=='pp' and 0<y<.005 else '<0.1' if kind=='num' and deck and 0<y/scale<.05 else f'{y/scale:,.{digits}f}'
 suffix=' pp' if kind=='pp' else '%' if kind in ['risk','pct'] else ''
 v=f(x['estimate'])+suffix
 if x['estimate']==x['lower']==x['upper']==0:return v+'\n(CI unavailable†)'
 if not deck and abs(x['upper']-x['lower'])>1e-10:v+='\n('+f(x['lower'])+'–'+f(x['upper'])+')'
 return v
def make(sp,deck):
 s=copy.deepcopy(sp);a=s['approach'];kind=s['kind'];base=2 if a==4 else 3 if a==5 else a;label=s['title'].split(':')[0]
 s['subtitle']='Users in thousands; point estimates' if deck else 'Numbers of women; estimates (95% survey intervals)'
 c=lambda m,ca:val(f'count|{a}|{m}|{ca}',deck=deck)
 pp=lambda m,ca:val(f'pp|{a}|{m}|{ca}','pp',deck)
 stock=lambda m:val('users2024' if m=='Total' else 'stock|'+m,deck=deck)
 name=lambda m:m
 heads=['Method / measure','Method\nfailure','Want more\neffective','Bleeding\nchanges','Other side\neffects/health','Access/cost/\nconvenience','All actionable\ncauses']
 if kind=='method':
  s['table']=[['Method','2024 survey\ncurrent users','Original-method ending\nprobability' if a>3 else 'Actionable ending\nprobability','Year-end losses\nafter switching' if a>3 else 'Users ending\noriginal method','mCPR equivalent']]
  for m in methods:s['table'].append([name(m),stock(m),val(f'risk|{base}|{m}|Total','risk',deck),c(m,'Total'),pp(m,'Total')])
  s['table'].append(['EC',stock('EC'),'Not applied','Not estimated','Not estimated'])
  s['table'].append(['Current-user mix\nexcluding EC',val('stock_no_ec',deck=deck),val(f'risk|{base}|Total|Total','risk',deck),c('Total','Total'),pp('Total','Total')])
 elif kind in ['cause','cause_pp']:
  s['table']=[heads]+[[name(m),*[c(m,ca) for ca in causes],c(m,'Total')] for m in methods]
  s['table'].append(['Year-end losses' if a>3 else 'Users ending method',*[c('Total',ca) for ca in causes],c('Total','Total')])
  if kind=='cause_pp':
   pop=meta['wra2025']/1000 if deck else meta['wra2025']
   s['table'].append(['2025 women aged\n15–49 (fixed)',*[f'{pop:,.1f}']*6]);s['table'].append(['mCPR increase (pp)',*[pp('Total',ca) for ca in causes],pp('Total','Total')])
 elif kind=='baseline':
  s['title']=label+': mCPR growth scenarios';s['subtitle']='2024 survey baseline and projected 2025 mCPR under three annual-change assumptions'
  s['table']=[['Different mCPR\ngrowth scenarios','Annual change\n(pp/year)','2024 survey\nmCPR','Projected 2025\nmCPR']]+[[labels[j-1],f'{meta["scenarios"][j-1]["annual_change_pp"]:+.2f}',val('mcpr2024','pct',deck),val(f'base|{j}','pct',deck)] for j in range(1,4)]
 elif kind=='scenario':
  s['table']=[['Different mCPR\ngrowth scenarios','2025 users\nusual scenario','2025\nmCPR','2025 users\nif retained','mCPR\nif retained','Increase\n(pp)']]
  for j in range(1,4):
   k=f'{j}|{a}|Total';s['table'].append([labels[j-1],val('usualusers|'+k,deck=deck),val('usualmcpr|'+k,'pct',deck),val('retainedusers|'+k,deck=deck),val('retainedmcpr|'+k,'pct',deck),pp('Total','Total')])
 elif kind=='method_scenario':
  j=s['scenario'];s['title']=label+': '+short[j-1]+' by method'
  s['table']=[['Method','2024 survey\nusers','2025 users\nusual scenario','Losses\navoided','2025 users\nif retained','2025\nmCPR','mCPR\nif retained']]
  for m in methods+['EC','Total']:
   k=f'{j}|{a}|{m}';s['table'].append(['All modern' if m=='Total' else name(m),stock(m),val('usualusers|'+k,deck=deck),'Not estimated' if m=='EC' else c(m,'Total'),val('retainedusers|'+k,deck=deck),val('usualmcpr|'+k,'pct',deck),val('retainedmcpr|'+k,'pct',deck)])
 else:raise ValueError(kind)
 definitions={1:'First-year: weighted actionable cumulative incidence in months 1–12 after initiation, applied to observed 2024 current users. Elapsed use is not incorporated.',2:'Historical: observed next-12-month actionable ending probability at current elapsed duration. The 61+ month group uses 37–60-month experience.',3:'AFT: seven weighted models predict next-12-month actionable endings conditional on elapsed use. Actionable and other endings compete, and five cause models allocate actionable endings.'}
 s['note']=definitions[base]
 s['note']+=(' Sensitivity: year-end losses deduct modern-to-modern switches and later restarters; EC counts as modern at year end.' if a>3 else ' Every actionable original-method ending is treated as a lost user. Switching/restarting is not deducted.')
 s['note']+=' Partner/spousal disapproval is excluded. The observed 2024 cohort is fixed across scenarios. Population and growth assumptions are fixed.'
 if not deck:s['note']+=' 95% intervals use 500 stratified PSU bootstrap draws; AFT families are fixed. CI bounds are not additive.'
 if base==3:s['note']+=' Sparse IUD causes have only 1–11 observed training events.'
 if a>3:s['note']+=' Sparse pathway cells use documented pooling.'
 if kind=='method':s['note']+=' Total ending probability averages method-specific risks using the 2024 current-user mix, excluding EC.'
 if kind=='baseline':s['note']=f'Recent annual change = (2024 DHS {meta["rates_from"]["dhs2024"]:.4f}% − 2018 DHS {meta["rates_from"]["dhs2018"]:.4f}%)/6. Longer-term change = (2024 DHS − 2013 DHS {meta["rates_from"]["dhs2013"]:.4f}%)/11. FPET-informed change = {meta["rates_from"]["fpet2025"]:.1f}% − {meta["rates_from"]["fpet2024"]:.1f}%. Each is added once to the 2024 DHS baseline. Growth assumptions are fixed.'

 return s
for deck in [True,False]:(out/('planning_slides.json' if deck else 'planning_html.json')).write_text(json.dumps([make(s,deck) for s in old],indent=2))
print('Built 40 Nigeria tables for 2024-to-2025, including both switching sensitivity sets.')
)--------",
  "302_revised_html.py" = r"--------("""Update Nigeria planning chapters from an observed 2024 cohort to 2025.

Usage: update_html.py SOURCE_HTML STATS_DIR HTML_SPECS OUTPUT_HTML
"""
from pathlib import Path
from lxml import html
from html import escape
import json,csv,re,copy,sys
source,stats,specfile,target=map(Path,sys.argv[1:]);doc=html.parse(str(source))
meta=json.loads((stats/'revision_inputs.json').read_text());spec=json.loads(specfile.read_text())
D={r['key']:{k:float(r[k])for k in ['estimate','lower','upper']}for r in csv.DictReader((stats/'planning_intervals.csv').open())}
methods=meta['methods'];causes=meta['causes'];oldids=set(doc.xpath('//section/@id'))
def sec(sid):return doc.xpath(f'//section[@id="{sid}"]')[0]
def table(rows):
 return '<div class="tablewrap"><table class="survey-table"><thead><tr>'+''.join('<th>'+escape(str(v)).replace('\n','<br>')+'</th>'for v in rows[0])+'</tr></thead><tbody>'+''.join('<tr>'+''.join(('<th scope="row">'if j==0 else'<td>')+escape(str(v)).replace('\n','<br>')+('</th>'if j==0 else'</td>')for j,v in enumerate(row))+'</tr>'for row in rows[1:])+'</tbody></table></div>'
def article(s,ci=True):
 s=copy.deepcopy(s)
 if not ci:
  s['table']=[[re.sub(r'\n\([^\n]*[–−][^\n]*\)|\n\(CI unavailable†\)','',v)for v in row]for row in s['table']]
  s['subtitle']=s['subtitle'].replace('estimates (95% survey intervals)','point estimates')
  s['note']=re.sub(r' 95% intervals use.*?CI bounds are not additive\.','',s['note'])
 return '<article class="duration-slide"><h3>'+escape(s['title'])+'</h3><p>'+escape(s['subtitle'])+'</p>'+table(s['table'])+'<p class="note">'+escape(s['note'])+'</p></article>'
def reset(sid,title,markup):
 s=sec(sid);s.clear();s.set('id',sid);s.set('class','analysis-section duration-block');h=html.Element('h2');h.text=title;s.append(h)
 for x in html.fragments_fromstring(markup):
  if isinstance(x,str):s.text=(s.text or'')+x
  else:s.append(x)
 return s
def val(key,kind='num'):
 x=D[key];digits=0 if kind=='num'else 1 if kind=='risk'else 2
 f=lambda v:f'{v:,.{digits}f}'
 suffix=' pp'if kind=='pp'else'%'if kind in ['risk','pct']else''
 return f(x['estimate'])+suffix+'\n('+f(x['lower'])+'–'+f(x['upper'])+')'
count=lambda a,m='Total',c='Total':val(f'count|{a}|{m}|{c}')
pp=lambda a,m='Total',c='Total':val(f'pp|{a}|{m}|{c}','pp')
def matrix(a,as_pp=False):return table([['Method / measure',*causes,'All actionable causes']]+[[m,*[(pp(a,m,c)if as_pp else count(a,m,c))for c in causes],pp(a,m)if as_pp else count(a,m)]for m in methods+['Total']])
reset('user-projections','First-year actionable discontinuation: 2024 users followed to 2025',article(spec[0])+article(spec[1]))
reset('mcpr-scenarios','First-year approach: 2025 mCPR under three growth scenarios',article(spec[2])+article(spec[3])+article(spec[7]))
reset('method-level-mcpr-scenarios','First-year approach: 2025 mCPR scenarios by method',''.join(article(s)for s in spec[4:7]))
rows=[['Approach (no switching adjustment)','Actionable original-method endings (95% CI)','2025 mCPR increase (95% CI)']]
for a,name in [(1,'First-year probability'),(2,'Historical duration-aware'),(3,'AFT survival')]:rows.append([name,count(a),pp(a)])
reset('three-approach-planning','Three approaches: observed 2024 users followed to 2025',
 '<p>All three main calculations concern potentially actionable endings of original modern methods, excluding EC and partner/spousal disapproval. The reference stock is the observed 2024 DHS all-women prevalence and method distribution multiplied by 2024 UN women aged 15–49. The historical and AFT probabilities use the observed 2024 elapsed-duration distribution. Each scenario projects usual-condition 2025 mCPR by adding one annual growth increment to the 2024 DHS baseline. Additional retained users are added to that usual-condition 2025 stock. The same observed 2024 cohort is fixed across scenarios. Every pp contribution divides the retained count by 57,393,553 projected women ages 15–49 in 2025, multiplied by 100. Main tables treat every actionable ending as a user lost and do not deduct switching or restarting. EC remains in baseline mCPR and contributes no retention increment.</p>'+table(rows)+
 '<p class="note">Intervals use the existing 500 full-frame stratified PSU bootstrap replicates. They propagate survey sampling, prevalence, method mix, duration, historical risks, fitted AFT curves and observed pathways. Population, secular-growth assumptions and selected AFT families remain fixed. These are conditional scenarios, not estimates of intervention effectiveness.</p>')
for sid,title,part,a in [('historical-duration-aware-planning','Historical duration-aware approach: 2025 mCPR without switching deduction',spec[8:16],2),('aft-duration-aware-planning','AFT survival approach: 2025 mCPR without switching deduction',spec[16:24],3)]:
 reset(sid,title,''.join(article(s,False)for s in part)+'<h3>Additional detail: 2025 mCPR percentage-point equivalent by method and cause (95% CI)</h3>'+matrix(a,True))
for sid,title,part in [('historical-switching-sensitivity','Historical switching sensitivity: 2024 users followed to 2025',spec[24:32]),('aft-switching-sensitivity','AFT switching sensitivity: 2024 users followed to 2025',spec[32:40])]:reset(sid,title,''.join(article(s)for s in part))
# Keep the complementary pathway diagnostics, with the same rebased counts.
rows=[['Method','Observed 2024 users','Gross actionable endings','Direct modern switches','Without direct switch']]
for m in methods+['Total']:rows.append([m,val('stock_no_ec'if m=='Total'else'stock|'+m),count(1,m),count(6,m),count(9,m)])
reset('switch-bridge','Sensitivity: direct switching only, 2024 to 2025','<p>Direct switching means modern use in the next recorded month. Later restarting is not deducted here. EC counts as modern at destination.</p>'+table(rows)+'<h3>Direct switches by cause (95% CI)</h3>'+matrix(6)+'<h3>2025 mCPR equivalent if endings without a direct switch were losses (95% CI)</h3>'+matrix(9,True))
rows=[['Current method','Gross actionable endings','Direct switches','Modern at year end after ending','Outside modern use at year end']]
for m in methods+['Total']:rows.append([m,count(2,m),count(7,m),count(10,m),count(4,m)])
reset('duration-bridge','Sensitivity: historical duration and modern use in 2025',table(rows)+'<h3>Outside modern use at year end by cause (95% CI)</h3>'+matrix(4)+article(spec[27]))
reset('duration-aware-cause-pp-matrices','Sensitivity: historical year-end loss by method and cause, 2025',matrix(4)+'<h3>2025 percentage-point equivalents (95% CI)</h3>'+matrix(4,True))
rows=[['Current method','AFT actionable endings','Direct switches','Modern at year end after ending','Outside modern use at year end']]
for m in methods+['Total']:rows.append([m,count(3,m),count(8,m),count(11,m),count(5,m)])
reset('duration-planning-appendix','Sensitivity: AFT pathway diagnostics, 2024 to 2025','<p>Original-method ending probabilities are unchanged. Year-end modern-use status comes from observed calendar pathways, including EC. User counts now start from observed 2024 users.</p>'+table(rows)+'<h3>AFT original-method endings by cause (95% CI)</h3>'+matrix(3)+'<h3>Direct switches by cause (95% CI)</h3>'+matrix(8)+'<h3>Outside modern use at year end by cause (95% CI)</h3>'+matrix(5))
for sid in ['switch-bridge','duration-bridge','duration-aware-cause-pp-matrices','duration-planning-appendix']:
 sec(sid).append(html.fragment_fromstring('<p class="note">Counts use the observed 2024 current-user cohort. All 2025 pp equivalents divide by 57,393,553 projected women ages 15–49. Intervals use 500 stratified PSU bootstrap draws, conditional on fixed population and growth assumptions.</p>'))
# Two-year reference table is replaced by a single one-year projection.
rows=[['Year','Women aged 15–49'],['2024',f'{meta["wra2024"]:,.0f}'],['2025',f'{meta["wra2025"]:,.0f}']]
growth=[['Year','Growth scenario','All-women mCPR (95% survey CI)','Women ages 15–49','Modern users (95% survey CI)'],['2024','Observed DHS baseline',val('mcpr2024','pct'),f'{meta["wra2024"]:,.0f}',val('users2024')]]
for j,s in enumerate(meta['scenarios'],1):growth.append(['2025',s['scenario']+f' ({s["annual_change_pp"]:+.2f} pp/year)',val(f'base|{j}','pct'),f'{meta["wra2025"]:,.0f}',val(f'baseusers|{j}')])
reset('population','Nigeria population and 2025 mCPR inputs','<p>All scenarios start from the 2024 DHS all-women mCPR of 13.104165%. Recent growth annualizes the 2018–2024 difference over six years. Longer-term growth annualizes the 2013–2024 difference over eleven years. FPET-informed growth applies the modeled 2024–2025 change of +0.40 pp. Each adds one annual increment to the 2024 DHS baseline. UN populations supply the 2024 current-user scale and the 2025 outcome denominator.</p>'+table(rows)+'<h3>Observed 2024 baseline and usual-condition 2025 scenarios</h3>'+table(growth)+'<p class="note">The retention calculation uses observed 2024 users, not projected 2025 users. Current method and elapsed-duration profiles remain those observed in the 2024 DHS. Those probabilities and the 2024 cohort remain fixed across scenarios. Survey intervals condition on fixed growth and population assumptions.</p>')
# A historical illustrative pathway is not a forecast of a particular cohort.
for p in sec('action-pathways').xpath('.//p'):
 if '2025–26' in p.text_content():p.text=p.text_content().replace('2025–26','2024–25')
# Complete left navigation, retaining section anchors.
aside=doc.find('.//aside');aside.clear();strong=html.Element('strong');strong.text='Nigeria discontinuation';aside.append(strong)
for s in doc.xpath('//main/section[@id]'):
 h=s.find('.//h2')
 if h is not None:
  a=html.Element('a',href='#'+s.get('id'));a.text=h.text_content();aside.append(a)
assert oldids==set(doc.xpath('//section/@id'))
text=html.tostring(doc,encoding='unicode',doctype='<!doctype html>')
visible=' '.join(doc.xpath('//body//text()[not(ancestor::script) and not(ancestor::style)]'))
stale=re.search(r'2026|2025–26',visible)
assert not stale,visible[max(0,stale.start()-160):stale.start()+220]if stale else''
target.write_text(text);print('Updated all main and sensitivity planning sets; preserved',len(oldids),'sections.')
)--------",
  "303_validate_revised.py" = r"--------("""Validate the incremental report build; do not claim a fresh full rebuild."""
from pathlib import Path
from lxml import html,etree
import sys,json,csv,hashlib,re
country,base,target,stats,out=sys.argv[1:]
base,target,stats,out=map(Path,[base,target,stats,out]);a=html.parse(str(base));b=html.parse(str(target))
ids=lambda d:set(d.xpath('//section/@id'))
assert ids(a)==ids(b),'Section coverage changed'
assert a.xpath('//img/@src')==b.xpath('//img/@src'),'Unrequested figure changes'
assert len(b.xpath('//img'))==len(a.xpath('//img'))
assert b.xpath('//*[@id="four-reason-groups"]'),'Partner/spousal classification block missing'
groups=b.xpath('//*[@id="four-reason-groups"]//tr')
assert any('Partner/spousal' in r.text_content()for r in groups)
scan=re.sub(r'data:[^;]+;base64,[A-Za-z0-9+/=]+','[embedded figure]',target.read_text())
assert not re.search(r'/(?:Users|Volumes)/|file:/{2,}|[A-Z]:\\',scan,re.I),'Personal path in report'
md=json.loads((stats/'revision_inputs.json').read_text())
assert len(md['scenarios'])==3
D={r['key']:float(r['estimate'])for r in csv.DictReader((stats/'revised_planning_intervals.csv').open())}
methods=md['methods'];causes=md['causes'];year=2026 if country=='Ethiopia' else 2025
for ap in range(1,6):
    total=D[f'count|{ap}|Total|Total']
    assert abs(total-sum(D[f'count|{ap}|{m}|{c}']for m in methods for c in causes))<1e-5
    assert abs(D[f'pp|{ap}|Total|Total']-100*total/md['wra'+str(year)])<1e-8
    for j in range(1,4):
        k=f'{j}|{ap}|Total'
        assert abs(D['retainedmcpr|'+k]-D['usualmcpr|'+k]-D[f'pp|{ap}|Total|Total'])<1e-8
def tables(d):
    return [[[re.sub(r'\s+','',c.text_content())for c in r.xpath('./th|./td')]for r in t.xpath('.//tr')]for t in d.xpath('//table')]
old,new=tables(a),tables(b)
same=sum(x==y for x,y in zip(old,new))
warnings=[]
def first_number(s):
    m=re.search(r'[-−]?\d[\d,]*(?:\.\d+)?',s)
    return float(m[0].replace(',','').replace('−','-'))if m else None
for article in b.xpath('//article[contains(@class,"duration-slide")]'):
    heading=article.find('h3');title=heading.text_content()if heading is not None else''
    if not title.endswith('by method'):continue
    for tr in article.xpath('.//table//tbody/tr'):
        cells=[c.text_content()for c in tr]
        if len(cells)!=7:continue
        usual,retained,loss=[first_number(cells[i])for i in [2,4,3]]
        if None in [usual,retained,loss]:continue
        delta=retained-usual-loss
        if abs(delta)>2:
            warnings.append(dict(table=title,row=cells[0],projected_users=usual,displayed_retained_users=loss,
                                 displayed_total=retained,displayed_count_discrepancy=delta,
                                 action='Preserved from the input report; reconcile fitted-output versions before treating the full report as mathematically reconciled.'))
result=dict(status='pass_with_existing_report_warnings'if warnings else'pass',country=country,reference_year=2025 if country=='Ethiopia' else 2024,outcome_year=year,
 sections=len(ids(b)),tables=len(new),base_tables=len(old),tables_matching_input_report=same,
 figures_preserved=len(b.xpath('//img')),incremental_build=True,full_raw_ir_to_all_chapters_verified=False,
 planning_arithmetic_input_vectors='pass',existing_report_arithmetic_warnings=warnings,
 base_report_sha256=hashlib.sha256(base.read_bytes()).hexdigest(),
 output_sha256=hashlib.sha256(target.read_bytes()).hexdigest(),
 scope='Planning arithmetic is rebuilt from supplied fitted estimates and bootstrap draws. Unchanged chapters and figures are preserved from the supplied validated HTML layout; they are not freshly recomputed by this command.')
(out/'revised_build_validation.json').write_text(json.dumps(result,indent=2))
print(json.dumps({k:v for k,v in result.items()if k not in ['scope','base_report_sha256','output_sha256']}))
)--------"
)
# Incremental report build: recalculates revised planning from fitted numerical
# outputs and applies the revision to an existing validated report layout.
# Unchanged analytical chapters and figures come from that report. This is not
# a fresh raw-IR rebuild of every chapter or an embedded snapshot replay.
run_revised_report <- function(opt) {
  if (!requireNamespace("jsonlite",quietly=TRUE) || !requireNamespace("digest",quietly=TRUE))
    stop("Install jsonlite and digest.")
  root <- opt[["project-root"]]
  if (is.null(root)) root <- file.path("analysis_output",tolower(COUNTRY),"revised")
  dir.create(root,recursive=TRUE,showWarnings=FALSE);root<-normalizePath(root,mustWork=TRUE)
  script_arg<-grep("^--file=",commandArgs(),value=TRUE)
  script_folder<-if(length(script_arg))dirname(sub("^--file=","",script_arg[1]))else"."
  stats <- opt[["statistics-dir"]]
  if(is.null(stats))stats<-file.path(script_folder,"revision_inputs")
  if (is.null(stats)||!dir.exists(stats)) stop("Supply --statistics-dir with fitted point estimates and survey bootstrap draws.")
  stats<-normalizePath(stats,mustWork=TRUE)
  required<-c("planning_point.rds","planning_replicates.rds",if(COUNTRY=="Ethiopia")"metadata.json"else"planning_metadata.rds")
  if(COUNTRY=="Ethiopia")required<-c(required,"planning_intervals.csv")
  if(!all(file.exists(file.path(stats,required))))stop("The numerical input directory is incomplete.")
  if(length(readRDS(file.path(stats,"planning_replicates.rds")))!=500L)
    stop("The saved-report revision requires the validated 500-replicate numerical output.")
  build<-file.path(root,"build");result<-file.path(root,"output");code<-file.path(root,"Code")
  for(d in c(build,result,code))dir.create(d,recursive=TRUE,showWarnings=FALSE)
  for(n in names(REVISION_HELPERS))writeLines(REVISION_HELPERS[[n]],file.path(code,n),useBytes=TRUE)
  assumptions<-opt[["revision-inputs"]]
  if(is.null(assumptions)) {assumptions<-file.path(build,"growth_assumptions.json");writeLines(REVISED_GROWTH_ASSUMPTIONS,assumptions,useBytes=TRUE)}
  if(!file.exists(assumptions))stop("Revision assumptions file does not exist.")
  schema<-file.path(build,"table_schema.json");writeLines(REVISED_TABLE_SCHEMA,schema,useBytes=TRUE)
  python<-if(!is.null(opt$python))opt$python else Sys.getenv("PYTHON",unset="python3")
  run<-function(exe,args) {
    status<-system2(exe,shQuote(args))
    if(!identical(status,0L))stop("Revised build failed; no checked report was overwritten.")
  }
  run(file.path(R.home("bin"),"Rscript"),c(file.path(code,"300_revised_planning.R"),stats,assumptions,build))
  if(identical(opt$run,"revised-planning"))return(invisible(NULL))
  template<-opt[["base-html"]]
  if(is.null(template)) {
    template<-file.path(script_folder,REPORT_BASENAME)
  }
  if(!file.exists(template))stop("Supply --base-html with the latest validated report layout.")
  template<-normalizePath(template,mustWork=TRUE)
  target<-file.path(result,REPORT_BASENAME)
  if(identical(normalizePath(target,mustWork=FALSE),template))stop("Build output must differ from the input report.")
  run(python,c(file.path(code,"301_revised_tables.py"),build,schema,build))
  if(COUNTRY=="Ethiopia") {
    run(python,c(file.path(code,"302_revised_html.py"),build,schema,template,target))
  } else if(COUNTRY=="Nigeria") {
    run(python,c(file.path(code,"302_revised_html.py"),template,build,file.path(build,"planning_html.json"),target))
  } else {
    run(python,c(file.path(code,"302_revised_html.py"),template,template,build,file.path(build,"planning_html.json"),target))
  }
  run(python,c(file.path(code,"303_validate_revised.py"),COUNTRY,template,target,build,result))
  cat("Revised HTML build completed. Review output/revised_build_validation.json for its scope.\n")
}

REQUIRED_R_PACKAGES <- unique(c(REQUIRED_R_PACKAGES,"abind"))
for (n in names(REVISION_HELPERS)) MODULES[[n]] <- list(language=if(grepl("[.]R$",n))"R"else"Python",args=character(),code=REVISION_HELPERS[[n]])

if (sys.nframe() == 0L) main()
