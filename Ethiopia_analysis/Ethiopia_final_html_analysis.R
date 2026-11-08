# Updated report companion: revised planning and incremental HTML build.
# --run=revised-html requires fitted statistics and the current validated report layout.
# Raw-IR preparation remains a separate mode; this does not freshly render every chapter.
# Parameterized IR preparation: --run=prepare; --validate-input checks inputs only.
# Updated full-frame survey inference and gross/switching planning uncertainty.
# --run=survey-planning uses staged derived episodes, covariates and selected AFT families.
# Updated planning results: output/survey_planning/planning_intervals.csv.
#!/usr/bin/env Rscript
# Ethiopia — numerical source companion to the final HTML
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
COUNTRY <- "Ethiopia"
REPORT_BASENAME <- "Ethiopia_discontinuation_analysis.html"
REPORT_SHA256 <- "4512542014dafde37ea3dea8cc92c0d2fc3c20b6a8d62ef64612cb97310f099c"
RAW_RELATIVE <- "Data/ETIR8AFL.dta"
CORE_MODULES <- c("ethiopia_modern_method_discontinuation.R")
PLANNING_MODULES <- c("ethiopia_modern_method_discontinuation.R", "202_ethiopia_planning_from_ir.R", "171_aft_switching_bridge.R", "179_duration_planning_table_arithmetic.py")
REQUIRED_R_PACKAGES <- c('digest','haven','jsonlite','survey','survival','nnet','ggplot2','grid','gridExtra','parallel','scales','sf','svglite')
BOOTSTRAP_ENV <- c("ETHIOPIA_PLANNING_BOOTSTRAP_REPS", "BOOTSTRAP_REPS", "DESCRIPTIVE_BOOTSTRAP_REPS", "INJECTABLE_FULL_REGIONAL_REPS", "REFERENCE_BOOTSTRAP_REPS", "REFERENCE_MODEL_REPS", "REGIONAL_ACTIONABLE_BOOTSTRAP_REPS", "REGIONAL_ACTIONABLE_METHOD_PAIRWISE_REPS", "REGIONAL_ACTIONABLE_MIX_REPS", "REGIONAL_ACTIONABLE_PAIRWISE_REPS", "REGIONAL_ACTIONABLE_RAW_PAIRWISE_REPS", "REGIONAL_BOOTSTRAP_REPS", "REGIONAL_DETAILED_BOOTSTRAP_REPS", "REGIONAL_METHOD_INTERACTION_REPS", "REGIONAL_METHOD_RISK_REPS", "RISK_STRATA_BOOTSTRAP_REPS")
SECTION_INDEX <- r"-----(section_id	title
overview	overview
initiation	EC-inclusive initiation diagnostic
table711	Revised Table 7.11
time	Discontinuation by time
reasons712	Revised Table 7.12: reasons for discontinuation
transitions	What happens after discontinuation?
action-pathways	From episode evidence to program action
standardized-current-users	Standardized current-user stock-to-outcome pathway
methods	Methods
validation	Validation
future	Additional analyses
presentation-figures	Presentation figures
dhs-711-presentation-table	DHS Table 7.11: 12-month discontinuation by method and reason
twelve-month-three-column-comparison	12-month discontinuation by method and reason definition
other-reasons-count-breakdown	What is inside “Other” discontinuation reasons?
other-reason-followup	What follows discontinuation for each “Other recorded reason”?
selected-reason-descriptive-subgroups	Exploring which groups have higher 12-month discontinuation for selected reasons
method-experience-subgroup-reasons	method-experience-subgroup-reasons
top-three-reasons-by-subgroup-method	top-three-reasons-by-subgroup-method
selected-reason-risk-strata	Do distinct high-, medium-, and low-risk profiles emerge?
method-duration-class-discontinuation	12-month selected-reason discontinuation by method-duration class
short-acting-selected-reason-distribution	Why short-acting methods ended within 12 months
subnational-discontinuation-analysis-extension	Subnational discontinuation analysis_extension
selected-reason-regional-analysis	Regional 12-month discontinuation for reasons other than wanted pregnancy or partner disapproval
regional-episode-mix-and-risk	Regional method mix alongside discontinuation within each method
regional-method-paired-bars	Regional method starts and 12-month discontinuation
expected-user-calculations	Expected-user discontinuation calculations
current-user-reason-planning	Illustrative current-user method endings for reasons other than wanted pregnancy or partner disapproval
current-user-actionable-projection	Illustrative current-user method endings for potentially actionable causes
duration-adjusted-reason-planning	Estimating next-year method endings among current users
updated-subnational-heterogeneity-analyses	Updated subnational heterogeneity analyses
mcpr-2026-retention-scenarios	Illustrative 2026 mCPR and improved continuation
mcpr-2026-method-detail	Illustrative 2026 modern users and mCPR by method
actionable-cause-mcpr-ceiling	Potential mCPR gain by actionable discontinuation cause
historical-duration-aware-planning	Historical duration-aware planning sequence
aft-duration-aware-planning	AFT survival and observed-pathway planning sequence
duration-planning-appendix	Appendix: earlier duration-aware analyses
switching-2026-bridge	Direct modern switching changes the gross user-loss illustration
duration-modern-use-2026-bridge	Elapsed method duration and modern use at year end
duration-aware-cause-pp-matrices	Actionable endings and year-end modern use: method by cause
aft-switching-sensitivity	AFT duration model with observed switching pathways)-----"

# USAGE (relative example locations; provide your own authorized IR file):
#   Rscript Ethiopia_final_html_analysis.R --list
#   Rscript Ethiopia_final_html_analysis.R --validate
#   Rscript Ethiopia_final_html_analysis.R --extract --project-root=analysis_output
#   Rscript Ethiopia_final_html_analysis.R --run=core --project-root=analysis_output --ir-file=data/individual_recode.dta
#   Rscript Ethiopia_final_html_analysis.R --run=MODULE_NAME --project-root=analysis_output --ir-file=data/individual_recode.dta
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
    cat('Options: --list, --validate, --validate-input, --packages, --extract, --run=prepare|core|planning|reference|MODULE[,MODULE], --reconcile\n')
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
  if (identical(selected,'survey-planning')) selected <- c('205_ethiopia_planning_survey_ci.R','206_summarize_planning.R','207_duration_support_ci.R','208_pooled_risk_ci.R')
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
EXTERNAL_INPUTS[["Data/ethiopia_2025_wra_planning_input.csv"]] <- r"-----(country,year,women_15_49,source,source_note
Ethiopia,2025,34057556.066801,UN population data via World Bank WDI,"Frozen unrounded planning denominator underlying the existing 34.06 million WRA estimate; see output/ethiopia_current_user_discontinuation_planning.html for the indicator URL and derivation."
)-----"

# =============================================================================
# ORIGINAL MODULE: 200_reference_analysis_extensions.R
# LANGUAGE: R
MODULES[["200_reference_analysis_extensions.R"]] <- list(
 language="R",
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
# ORIGINAL MODULE: 202_ethiopia_planning_from_ir.R
# LANGUAGE: R
MODULES[["202_ethiopia_planning_from_ir.R"]] <- list(
 language="R",
 packaged_sha256="0612d29b9882df4cd3ce273e203226191a472f0b69d5cebdf0b34ce7dee713f9",
 args=character(),
 code=r"-----(#!/usr/bin/env Rscript
# Rebuild the saved report's FIRST-YEAR planning inputs without slide CSVs.
# The report used rounded current method shares (four decimal places) and
# the 8,611 complete-case, age-at-start 15-49 episode cohort. Preserve those
# choices for reproduction; do not mistake them for the broader DHS cohort.
root<-Sys.getenv('ETHIOPIA_PROJECT_ROOT');stopifnot(nzchar(root))
out<-file.path(root,'output','Supporting_data');dir.create(out,recursive=TRUE,showWarnings=FALSE)
ir<-readRDS(file.path(root,'Data','ET2024DHS__ETIR8ADT__IR_raw.rds'))
e<-readRDS(file.path(root,'Data','Derived','ethiopia_2024_table_7_11_episodes.rds'))
codes<-c(1L,2L,3L,5L,6L,7L,11L,13L,17L,18L)
e<-e[e$method_code%in%codes,];i<-e$woman_row
age<-floor((e$start-as.integer(ir$v011[i]))/12)
births<-as.matrix(ir[i,grep('^b3_',names(ir),value=TRUE)])
parity<-rowSums(!is.na(births)&births<=e$start)
complete<-!is.na(age)&age>=15&age<=49&!is.na(parity)&
 as.integer(ir$v501[i])%in%0:5&as.integer(ir$v106[i])%in%0:3&
 as.integer(ir$v190[i])%in%1:5&as.integer(ir$v025[i])%in%1:2&
 !is.na(ir$v024[i])&!is.na(ir$v021[i])&!is.na(ir$v022[i])
e<-e[complete,];stopifnot(nrow(e)==8611L)
wt<-as.numeric(ir$v005)/1e6;code<-as.integer(ir$v312)
modern<-c(1L,2L,3L,5L,6L,7L,11L,13L,14L,16L,17L,18L)
method<-ifelse(code==3,'Injectables',ifelse(code==11,'Implants',ifelse(code==1,'Pill',
 ifelse(code==2,'IUD',ifelse(code==16,'EC',ifelse(code%in%modern,'Other modern methods',NA_character_))))))
lev<-c('Injectables','Implants','Pill','IUD','EC','Other modern methods')
methodwt<-vapply(lev,function(m)sum(wt[method==m],na.rm=TRUE),0.0)
mix<-round(100*methodwt/sum(methodwt),4)
wra<-read.csv(file.path(root,'Data','ethiopia_2025_wra_planning_input.csv'))$women_15_49[1]
mcpr<-sum(wt[code%in%modern])/sum(wt)
users<-wra*mcpr*mix/100
causes<-list('Method failure'=1L,'Wanted more effective method'=7L,'Changes in menstrual bleeding'=15L,
 'Other side effects/health'=c(4L,5L),'Access/cost/convenience'=c(6L,8L,10L))
groups<-list(Injectables=3L,Implants=11L,Pill=1L,IUD=2L,`Other modern methods`=c(5L,6L,7L,13L,17L,18L))
prob<-function(z){s<-1;f<-numeric(5)
 for(t in 1:12){at<-z$entry<t&z$exposure>=t;den<-sum(z$wt[at]);stopifnot(den>0)
 end<-at&z$discontinued&z$exposure==t
 f<-f+s*vapply(causes,function(c)sum(z$wt[end&z$reason_code%in%c]),0.0)/den
 s<-s*(1-sum(z$wt[end])/den)};100*f}
rows<-list();cr<-list()
for(m in lev){
 p<-if(m=='EC')rep(NA_real_,5) else prob(e[e$method_code%in%groups[[m]],])
 rows[[m]]<-data.frame(method=m,current_mix_pct=mix[m],current_users=users[m],
 actionable_12_month_probability_pct=sum(p),illustrative_actionable_method_endings=users[m]*sum(p)/100)
 if(m!='EC')for(j in seq_along(causes))cr[[length(cr)+1L]]<-data.frame(method=m,actionable_cause=names(causes)[j],
  current_users=users[m],cause_specific_12_month_probability_pct=p[j],illustrative_method_endings=users[m]*p[j]/100,
  observed_first_year_cause_endings_n=sum(e$method_code%in%groups[[m]]&e$discontinued&e$exposure<=12&e$reason_code%in%causes[[j]]))
}
z<-do.call(rbind,rows);q<-do.call(rbind,cr);active<-z$method!='EC'
total<-sum(z$current_users[active]);ending<-sum(z$illustrative_actionable_method_endings[active])
z<-rbind(z,data.frame(method='All modern methods, excluding EC',current_mix_pct=sum(mix[lev!='EC']),
 current_users=total,actionable_12_month_probability_pct=100*ending/total,illustrative_actionable_method_endings=ending))
for(c in names(causes)){loss<-sum(q$illustrative_method_endings[q$actionable_cause==c]);q<-rbind(q,
 data.frame(method='All modern methods, excluding EC',actionable_cause=c,current_users=total,
 cause_specific_12_month_probability_pct=100*loss/total,illustrative_method_endings=loss,observed_first_year_cause_endings_n=NA_integer_))}
write.csv(z,file.path(out,'current_users_actionable_12_month_projection.csv'),row.names=FALSE,na='')
write.csv(q,file.path(out,'current_users_actionable_by_cause.csv'),row.names=FALSE,na='')
stopifnot(abs(sum(q$illustrative_method_endings[q$method!='All modern methods, excluding EC'])-ending)<1e-6)
cat('Rebuilt current-user and cause planning inputs directly from IR and episodes.\n')
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 00_import_ir_dta.R
# LANGUAGE: R
MODULES[["00_import_ir_dta.R"]] <- list(
 language="R",
 packaged_sha256="38e7b5c3930e92ec087428553dcaf7ee639838fe6438af95f141bafd814259bc",
 args=character(),
 code=r"-----(#!/usr/bin/env Rscript
# =============================================================================
# 00. Import the original Ethiopia 2024–25 DHS individual recode (IR) file
# =============================================================================
# Run this ONCE before the calendar and life-table scripts if the project's
# RDS copy is absent. The survey .dta is supplied locally by an authorized DHS
# user; this script does not download restricted microdata from the internet.
#
# Input (one row per interviewed woman): Data/ETIR8AFL.dta
# Output (same rows and variables, with Stata labels preserved):
#   Data/ET2024DHS__ETIR8ADT__IR_raw.rds
#
# Nothing is filtered, reshaped, recoded, or imputed at this step. In particular,
# vcal_1 and vcal_2 remain the original fixed-width 80-character calendar
# strings, including their spaces. Subsequent scripts convert them into
# chronological method-use episodes and, where needed, episode-month rows.
# =============================================================================

script_arg <- grep('^--file=', commandArgs(FALSE), value=TRUE)
default_project <- if(length(script_arg)) normalizePath(file.path(dirname(sub('^--file=', '', script_arg[1])), '..')) else normalizePath('..')
project <- Sys.getenv('ETHIOPIA_PROJECT_ROOT', unset=default_project)
input_dir <- Sys.getenv('ETHIOPIA_INPUT_DIR', unset=file.path(project, 'Data'))
dta_file <- file.path(input_dir, 'ETIR8AFL.dta')
rds_file <- file.path(input_dir, 'ET2024DHS__ETIR8ADT__IR_raw.rds')

# Package setup: haven reads Stata files and retains labelled variables.
# The CRAN installation runs only when haven is missing. A machine without
# internet should install haven beforehand; the survey file itself is local.
if (!requireNamespace("haven", quietly=TRUE)) {
  install.packages("haven", repos="https://cloud.r-project.org")
}
if (!file.exists(dta_file)) stop("DHS IR .dta file not found: ", dta_file)

# Read all women and all columns. as.data.frame removes only tibble row-class
# behavior; haven_labelled column attributes and the calendar strings remain.
ir <- as.data.frame(haven::read_dta(dta_file))
stopifnot(nrow(ir)==21395L, ncol(ir)==6648L,
          !anyDuplicated(ir$caseid),
          all(nchar(ir$vcal_1)==80L),
          all(c("v005","v008","v017","v018","v019","v021","v022",
                "v024","vcal_1","vcal_2") %in% names(ir)))

# The existing RDS was previously copied from the same survey. Verify its
# identity across every variable rather than replacing a known-good local
# source. Delete/rename it explicitly only when intending
# to regenerate it; this script never silently overwrites it.
if (file.exists(rds_file)) {
  existing <- readRDS(rds_file)
  if (!identical(existing, ir)) {
    stop("Existing IR RDS is not identical to the source .dta; inspect before analysis.")
  }
  message("Existing IR RDS is identical to the source .dta in all columns; left unchanged.")
} else {
  saveRDS(ir,rds_file,compress="xz")
  message("Saved lossless IR RDS: ",rds_file)
}
)-----"
)

# =============================================================================
# ORIGINAL MODULE: ethiopia_modern_method_discontinuation.R
# LANGUAGE: R
MODULES[["ethiopia_modern_method_discontinuation.R"]] <- list(
 language="R",
 packaged_sha256="ad52424a3b7fd4cc0aace7a3526937c77e6a9a1e633bd686d74e43ebe9dfbfcc",
 args=character(),
 code=r"-----(#!/usr/bin/env Rscript
# =============================================================================
# Ethiopia DHS 2024-25: modern-method contraceptive discontinuation
# =============================================================================
# Purpose
#   1. Read the lossless RDS copy of the original individual women's IR file.
#      If needed, create it from ETIR8AFL.dta with Code/00_import_ir_dta.R.
#   2. Turn the DHS contraceptive calendar into continuous method-use episodes;
#   3. reproduce published Table 7.11 as a validation check;
#   4. regroup the requested modern methods; and
#   5. estimate cumulative discontinuation at 3, 6, 9, and 12 months.
#
# Estimator
#   The reason-specific results use a weighted multiple-decrement life table.
#   The any-reason result combines all discontinuations into one event and is
#   equivalent to a weighted single-decrement Kaplan-Meier estimator.
#
# Data protection
#   The original IR file is only read. Derived episode files and results are
#   written to the project Data/Derived and Output folders.
#
# Data shape
#   The input .dta/.rds has one row per woman. vcal_1 stores 80 monthly method
#   or reproductive-state characters and vcal_2 stores aligned ending reasons.
#   This script converts each woman's strings directly into chronological
#   continuous runs (one output row per episode). It does not first save a
#   woman-month-long table. Regression script 34 later expands those episodes
#   into one row per observed episode-month at risk.
# =============================================================================

options(stringsAsFactors = FALSE)

# 1. Install any missing CRAN packages, then load them ------------------------
# jsonlite writes machine-readable validation output; survival provides an
# independent Aalen–Johansen check. R's base functions do the calendar parsing.
# CRAN is only used for software packages; the DHS microdata are never fetched.
required_packages <- c("jsonlite", "survival")
missing_packages <- setdiff(required_packages, rownames(installed.packages()))
if (length(missing_packages) > 0L) {
  install.packages(missing_packages, repos = "https://cloud.r-project.org")
}
invisible(lapply(required_packages, library, character.only = TRUE))

# 2. Define project paths and import the original Stata file -----------------
script_arg <- grep('^--file=', commandArgs(FALSE), value=TRUE)
default_project <- if(length(script_arg)) normalizePath(file.path(dirname(sub('^--file=', '', script_arg[1])), '..')) else normalizePath('..')
project <- Sys.getenv('ETHIOPIA_PROJECT_ROOT', unset=default_project)
input_dir <- Sys.getenv('ETHIOPIA_INPUT_DIR', unset=file.path(project, 'Data'))
# Import/verify the actual DHS .dta on every top-level run. The importer reads
# every woman and variable, verifies the calendar fields, and creates the
# lossless RDS cache only when absent. Downstream modules use that cache so
# that they do not independently reload the 153 MB Stata file.
source(file.path(project, "Code", "00_import_ir_dta.R"), local = TRUE)
raw_file <- file.path(input_dir, "ET2024DHS__ETIR8ADT__IR_raw.rds")
derived_dir <- file.path(project, "Data", "Derived")
table_out <- file.path(project, "output", "Supporting_data", "Table_7_11")
modern_out <- file.path(project, "output", "Supporting_data", "Modern_methods")
dir.create(derived_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(table_out, recursive = TRUE, showWarnings = FALSE)
dir.create(modern_out, recursive = TRUE, showWarnings = FALSE)

# 3. Read and verify the individual-level IR data ----------------------------
# This RDS has the same women, variables, labels, and calendar strings as the
# local source .dta. Fail early if the expected survey or calendar structure
# differs, because a shifted calendar character changes every episode date.
if (!file.exists(raw_file)) stop("IR data not found: ", raw_file)
x <- readRDS(raw_file)
stopifnot(
  nrow(x) == 21395L,
  !anyDuplicated(x$caseid),
  all(x$v008 - x$v017 + 1 == x$v019),
  all(nchar(x$vcal_1) == 80L),
  all(c("vcal_1", "vcal_2", "v005") %in% names(x))
)

# 4. Reconstruct episodes and validate the published table -------------------
# DHS calendar characters run from the interview backward. For each woman,
# reverse vcal_1 and the aligned vcal_2 characters so time moves forward;
# retain only v019 valid months; use rle() to find consecutive months in the
# same state. Each run becomes one row with start/end century-month codes.
# The run's reason is the last nonblank reason recorded within that same run.
# Repeating caseid and v005 across rows allows one woman to contribute several
# episodes while preserving a link back to her survey weight and cluster.
out <- table_out
# Native recode codes, not the different codes printed on the questionnaire.
method_codes <- strsplit('123456789WNALCFEMS~','')[[1]]
reason_codes <- c('1'=1L,'2'=2L,'3'=3L,'4'=4L,'5'=5L,'6'=6L,
                  '7'=7L,'8'=8L,'9'=9L,'C'=10L,'F'=11L,'A'=12L,
                  'D'=13L,'M'=15L,'W'=96L,'K'=98L,'?'=99L,' '=0L)
events <- vector('list',nrow(x))
for (i in seq_len(nrow(x))) {
  cal <- rev(strsplit(x$vcal_1[i],'')[[1]])[seq_len(x$v019[i])]
  reason_string <- sprintf('%-80s',x$vcal_2[i])
  reasons <- rev(strsplit(reason_string,'')[[1]])[seq_len(x$v019[i])]
  runs <- rle(cal)
  ends <- cumsum(runs$lengths)
  starts <- ends-runs$lengths+1L
  code <- match(runs$values,method_codes)
  code[runs$values=='0'] <- 0L
  code[runs$values=='B'] <- 81L
  code[runs$values=='T'] <- 82L
  code[runs$values=='P'] <- 83L
  code[runs$values=='?'] <- 99L
  reason_at_end <- unname(reason_codes[reasons[ends]])
  reason <- reason_at_end
  reason_offset <- integer(length(ends))
  for (k in seq_along(ends)) {
    positions <- (starts[k]:ends[k])[reasons[starts[k]:ends[k]]!=' ']
    if(length(positions)) {
      last_reason_position <- tail(positions,1)
      reason[k] <- unname(reason_codes[reasons[last_reason_position]])
      reason_offset[k] <- ends[k]-last_reason_position
    }
  }
  stopifnot(!anyNA(code),!anyNA(reason),!anyNA(reason_at_end))
  events[[i]] <- data.frame(woman_row=i,caseid=x$caseid[i],event_no=seq_along(code),
    wt=as.numeric(x$v005[i])/1e6,interview=as.numeric(x$v008[i]),
    calendar_start=as.numeric(x$v017[i]),region=as.numeric(x$v024[i]),
    start=as.numeric(x$v017[i])+starts-1L,end=as.numeric(x$v017[i])+ends-1L,
    duration=runs$lengths,method_code=code,reason_code=reason,
    reason_at_method_end=reason_at_end,reason_offset=reason_offset,
    next_code=c(code[-1L],NA_integer_),next_duration=c(runs$lengths[-1L],NA_integer_),
    next2_code=c(code,NA_integer_,NA_integer_)[seq_along(code)+2L])
}
events <- do.call(rbind,events)
saveRDS(events,file.path(project,'Data','Derived','ethiopia_2024_calendar_events.rds'))

# Restrict continuous runs to method episodes that overlap the DHS Table 7.11
# 3–62-month observation window. Left-truncated episodes entered use before
# the window began; their completed duration is entry. exposure is the last
# duration month actually observed. The life table uses only duration 1–12.
e <- events[events$method_code %in% c(1:20,99) & events$start!=events$calendar_start,]
e$start_before_interview <- e$interview-e$start
e$end_before_interview <- e$interview-e$end
e <- e[e$start_before_interview>=3 & e$end_before_interview<=62,]
e$entry <- pmax(e$start_before_interview-62,0)
e$exposure <- e$duration-pmax(3-e$end_before_interview,0)
stopifnot(all(e$exposure>e$entry))
# CSPro counts an episode only if it supplies exposure at duration 1-12.
# Late entrants at duration 13 or beyond cannot contribute to this table.
episodes_in_window <- nrow(e)
e <- e[e$entry<12,]
e$method <- 'Other'
e$method[e$method_code==3] <- 'Injectables'
e$method[e$method_code==11] <- 'Implants'
e$method[e$method_code==1] <- 'Pill'
e$method[e$method_code==16] <- 'Emergency contraception'
is_method <- function(z) !is.na(z) & z %in% c(1:20,99)
reason_group <- function(z) {
  result <- rep(9L,length(z))
  map <- c('1'=1L,'2'=2L,'9'=3L,'12'=3L,'13'=3L,'15'=4L,
           '4'=5L,'5'=5L,'7'=6L,'6'=7L,'8'=7L,'10'=7L,'3'=8L)
  for(k in names(map))result[z==as.integer(k)] <- map[[k]]
  result
}
classify <- function(d, recover_reason=TRUE) {
  if(!recover_reason)d$reason_code <- d$reason_at_method_end
  d$discontinued <- d$end_before_interview>3
  d$reason <- ifelse(d$discontinued,reason_group(d$reason_code),0L)
  d$switched <- d$discontinued & (
    (is_method(d$next_code) & d$next_code!=d$method_code) |
    (d$reason_code==7 & !is.na(d$next_code) & d$next_code==0 &
     !is.na(d$next_duration) & d$next_duration==1 & is_method(d$next2_code) &
     d$next2_code!=d$method_code))
  d$boundary_reason <- FALSE
  d$boundary_same_method_switch <- FALSE
  # CSPro treats a recorded reason at exactly interview minus 3 months as
  # a discontinuation, even if the method run continues into excluded months.
  # Its direct-next-month switching test also operates at this boundary.
  for(j in which(d$end_before_interview<=3)) {
    row <- d$woman_row[j]
    p <- x$v018[row]+3L
    code <- substring(x$vcal_2[row],p,p)
    if(nzchar(trimws(code))) {
      rcode <- unname(reason_codes[code])
      d$reason_code[j] <- rcode
      d$reason[j] <- reason_group(rcode)
      d$discontinued[j] <- TRUE
      d$boundary_reason[j] <- TRUE
      c1 <- substring(x$vcal_1[row],p-1,p-1)
      c2 <- substring(x$vcal_1[row],p-2,p-2)
      d$switched[j] <- c1 %in% method_codes |
        (rcode==7 & c1=='0' & c2 %in% method_codes & match(c2,method_codes)!=d$method_code[j])
      d$boundary_same_method_switch[j] <- isTRUE(match(c1,method_codes)==d$method_code[j])
    }
  }
  stopifnot(!anyNA(d$switched),all(d$switched<=d$discontinued))
  d
}
strict <- classify(e,FALSE)
e <- classify(e,TRUE)
e$episode_id <- seq_len(nrow(e))

methods <- c('Injectables','Implants','Pill','Emergency contraception','Other','All methods')
metrics <- c('Method failure','Desire to become pregnant','Other fertility-related reasons',
 'Changes in menstrual bleeding','Other side effects/health concerns','Wanted more effective method',
 'Other method-related reasons','Husband/partner disapproved','Other reasons','Any reason',
 'Switched to another method','Number of episodes of use')
reference <- rbind(c(.8,18.4,4.1,3.6,3.8,5.5,5.1,.6,2.6,44.5,5.1,6198),
 c(.2,6.1,.6,.7,2.3,2.9,2.2,0,1,16,2.6,2526),
 c(3.2,18.7,15.9,2.5,2,14.1,6.4,2.2,2.5,67.4,15.7,944),
 c(.9,5.8,51.4,5.1,7.3,6.1,4.2,0,6.3,87.2,7.6,196),
 c(1.6,9,6,3.4,1.2,6.5,1.4,0,1.9,31.1,10.7,603),
 c(.9,14.6,5.5,2.8,3.2,5.8,4.3,.5,2.2,39.8,5.8,10467))
dimnames(reference) <- list(methods,metrics)

calculate <- function(d) {
  # Multiple-decrement life table. All method episodes still observable at
  # duration t form the denominator. Each reason's monthly weighted endings
  # contribute survival-through-(t-1) × cause-specific monthly hazard to its
  # 12-month cumulative incidence. All endings reduce later risk sets.
  survival <- 1
  cif <- numeric(9)
  sw <- 0
  monthly <- vector('list',12)
  for(t in 1:12) {
    risk <- sum(d$wt[d$entry<t & d$exposure>=t])
    cens <- sum(d$wt[d$entry<t & d$exposure==t & !d$discontinued])
    denominator <- risk
    deaths <- vapply(1:9,function(k)sum(d$wt[d$entry<t & d$exposure==t & d$reason==k]),numeric(1))
    switches <- sum(d$wt[d$entry<t & d$exposure==t & d$switched])
    if(denominator>0) {
      cif <- cif+survival*deaths/denominator
      sw <- sw+survival*switches/denominator
      survival <- survival*(1-sum(deaths)/denominator)
    }
    monthly[[t]] <- data.frame(month=t,risk=risk,censored=cens,denominator=denominator,
      discontinued=sum(deaths),switched=switches,survival=survival,
      t(deaths),t(cif))
  }
  stopifnot(abs(sum(cif)+survival-1)<1e-10, sw<=sum(cif)+1e-10)
  list(rates=c(100*cif,100*(1-survival),100*sw,sum(d$wt)),monthly=do.call(rbind,monthly))
}
calc <- t(vapply(methods,function(m)calculate(if(m=='All methods')e else e[e$method==m,])$rates,numeric(12)))
dimnames(calc) <- list(methods,metrics)
strict_calc <- t(vapply(methods,function(m)calculate(if(m=='All methods')strict else strict[strict$method==m,])$rates,numeric(12)))
dimnames(strict_calc) <- list(methods,metrics)
counts <- do.call(rbind,lapply(methods,function(m) {
 d <- if(m=='All methods')e else e[e$method==m,]
 data.frame(method=m,unweighted_episodes=nrow(d),unweighted_entries_at_zero=sum(d$entry==0),
  weighted_episodes=sum(d$wt),unweighted_women=length(unique(d$caseid)),late_entries=sum(d$entry>0),
  recovered_reason_events=sum(d$end_before_interview>3 & d$reason_code!=d$reason_at_method_end),
  boundary_reason_events=sum(d$boundary_reason),
  boundary_same_method_switches=sum(d$boundary_same_method_switch))
}))
cat('EPISODE COUNTS\n');print(counts,row.names=FALSE)
cat('\nREPLICATED TABLE\n');print(round(calc,3))

# Independent point-estimate check using survival's Aalen-Johansen estimator.
# Unique IDs are episodes here; confidence intervals are not part of this task.
independent_max_error <- 0
for(m in methods) {
  d <- if(m=='All methods')e else e[e$method==m,]
  fit <- survival::survfit(survival::Surv(entry,exposure,factor(reason,levels=0:9))~1,
                           data=d,weights=wt,id=episode_id,se.fit=FALSE)
  p <- summary(fit,times=12,extend=TRUE)$pstate[1,]
  independent_max_error <- max(independent_max_error,max(abs(100*p[-1]-calc[m,1:9])))
}
stopifnot(independent_max_error<1e-8)
rounded <- calc
rounded[,1:11] <- round(rounded[,1:11],1)
rounded[,12] <- round(rounded[,12])
stopifnot(all(rounded==reference))
monthly <- do.call(rbind,lapply(methods,function(m) {
  d <- if(m=='All methods')e else e[e$method==m,]
  cbind(method=m,calculate(d)$monthly)
}))
audit <- list(women_in_IR=nrow(x),calendar_events=nrow(events),
 episodes_intersecting_window=episodes_in_window,first_year_episodes=nrow(e),
 women_contributing=length(unique(e$caseid)),
 reason_recovery_events=sum(e$end_before_interview>3 & e$reason_code!=e$reason_at_method_end),
 reason_recovery_events_first_year=sum(e$end_before_interview>3 & e$reason_code!=e$reason_at_method_end & e$exposure<=12),
 first_year_boundary_same_method_switches=sum(e$boundary_same_method_switch & e$exposure<=12),
 independent_estimator_max_difference_pp=independent_max_error,
 rate_cells_matching=sum(rounded[,1:11]==reference[,1:11]),
 count_cells_matching=sum(rounded[,12]==reference[,12]),
 direct_terminal_reason_rate_cells_matching=sum(round(strict_calc[,1:11],1)==reference[,1:11]))
print(audit)
saveRDS(e,file.path(project,'Data','Derived','ethiopia_2024_table_7_11_episodes.rds'))
jsonlite::write_json(list(methods=methods,metrics=metrics,reference=unname(reference),
 calculated=unname(calc),rounded=unname(rounded),
 strict_terminal_month=unname(strict_calc),counts=counts,monthly_life_tables=monthly,audit=audit,
 reason_recovery_policy='For completed episodes before the censoring boundary, use the latest nonblank recorded reason within the same continuous method run. If none exists, group the completed episode under Other reasons. Do not change the method-run dates.',
 input_file='Data/ET2024DHS__ETIR8ADT__IR_raw.rds',
 report_file=basename(Sys.getenv("ETHIOPIA_DHS_REPORT", unset="")),
 report_location='Table 7.11, printed page 140, PDF page 178',
 created=format(Sys.time(),'%Y-%m-%d %H:%M:%S %Z')),
 file.path(out,'table_7_11_results.json'),pretty=TRUE,digits=12)
capture.output(sessionInfo(),file=file.path(out,'R_session_info.txt'))
cat('\nVALIDATED: all 66 rates and all 6 counts match the published table.\n')


# 5. Apply the requested modern-method grouping and time points --------------
out <- modern_out
base <- readRDS(file.path(derived_dir,'ethiopia_2024_table_7_11_episodes.rds'))
original <- jsonlite::read_json(file.path(table_out,'table_7_11_results.json'),simplifyVector=TRUE)

# DHS recode method codes. Male condom is grouped under Other modern methods.
# Code 17 (other modern) happens to have zero eligible episodes.
group_codes <- list(
  'Injectables'=3L,
  'Implants'=11L,
  'Pill'=1L,
  'Emergency contraception'=16L,
  'Other modern methods'=c(2L,5L,6L,7L,13L,18L,17L))
modern_codes <- unlist(group_codes,use.names=FALSE)
stopifnot(!anyDuplicated(modern_codes))
e <- base[base$method_code %in% modern_codes,]
e$modern_method <- NA_character_
for (name in names(group_codes)) e$modern_method[e$method_code %in% group_codes[[name]]] <- name
stopifnot(!anyNA(e$modern_method),all(e$entry<12),all(e$exposure>e$entry))
e$modern_method <- factor(e$modern_method,levels=names(group_codes))
methods <- c(names(group_codes),'All specified modern methods')
reasons <- c('Method failure','Desire to become pregnant','Other fertility-related reasons',
  'Changes in menstrual bleeding','Other side effects/health concerns',
  'Wanted more effective method','Other method-related reasons',
  'Husband/partner disapproved','Other reasons')
horizons <- c(3L,6L,9L,12L)

# Identify discontinuations followed by a successful move to another modern
# method. This applies the DHS Table 7.11 switching timing rule but restricts
# the destination to the specified modern-method codes: a different modern
# method in the following month, or (when the stated reason was "wanted a more
# effective method") a different modern method after one intervening nonuse
# month. The published DHS switch column is broader because it permits any
# contraceptive destination, including a traditional method.
e$successful_modern_switch <- e$discontinued & (
  (!is.na(e$next_code) & e$next_code %in% modern_codes &
     e$next_code != e$method_code) |
  (e$reason_code == 7L & !is.na(e$next_code) & e$next_code == 0L &
     !is.na(e$next_duration) & e$next_duration == 1L &
     !is.na(e$next2_code) & e$next2_code %in% modern_codes &
     e$next2_code != e$method_code)
)

# Match the special observation-boundary convention used in the replicated
# DHS table. At that boundary the next calendar state is read directly from
# the original calendar string.
boundary_rows <- which(e$boundary_reason)
if (length(boundary_rows)) {
  modern_calendar_codes <- method_codes[modern_codes]
  for (j in boundary_rows) {
    woman <- e$woman_row[j]
    position <- x$v018[woman] + 3L
    next_month_code <- substring(x$vcal_1[woman], position - 1L,
                                 position - 1L)
    month_after_next_code <- substring(x$vcal_1[woman], position - 2L,
                                       position - 2L)
    direct_modern_switch <- next_month_code %in% modern_calendar_codes &&
      match(next_month_code, method_codes) != e$method_code[j]
    one_month_gap_switch <- e$reason_code[j] == 7L &&
      next_month_code == '0' &&
      month_after_next_code %in% modern_calendar_codes &&
      match(month_after_next_code, method_codes) != e$method_code[j]
    e$successful_modern_switch[j] <- direct_modern_switch ||
      one_month_gap_switch
  }
}
stopifnot(!anyNA(e$successful_modern_switch),
          all(e$successful_modern_switch <= e$discontinued))

life_table <- function(d) {
  survival <- 1
  incidence <- numeric(9)
  switching <- 0
  successful_modern_switching <- 0
  ended_without_successful_modern_switch <- 0
  rows <- vector('list',12)
  for (t in 1:12) {
    at_risk <- d$entry<t & d$exposure>=t
    risk <- sum(d$wt[at_risk])
    deaths <- vapply(1:9,function(k)sum(d$wt[at_risk & d$exposure==t & d$reason==k]),numeric(1))
    sw <- sum(d$wt[at_risk & d$exposure==t & d$switched])
    modern_sw <- sum(d$wt[at_risk & d$exposure==t &
                            d$successful_modern_switch])
    non_modern_sw_end <- sum(deaths) - modern_sw
    censored <- sum(d$wt[at_risk & d$exposure==t & !d$discontinued])
    if (risk>0) {
      incidence <- incidence + survival*deaths/risk
      switching <- switching + survival*sw/risk
      successful_modern_switching <- successful_modern_switching +
        survival*modern_sw/risk
      ended_without_successful_modern_switch <-
        ended_without_successful_modern_switch +
        survival*non_modern_sw_end/risk
      survival <- survival*(1-sum(deaths)/risk)
    }
    rows[[t]] <- c(month=t,at_risk=risk,censored=censored,
      discontinued=sum(deaths),survival=survival,any_reason_pct=100*(1-survival),
      switching_pct=100*switching,
      successful_modern_switch_pct=100*successful_modern_switching,
      ended_without_successful_modern_switch_pct=
        100*ended_without_successful_modern_switch,
      setNames(100*incidence,paste0('reason_',1:9,'_pct')))
  }
  z <- as.data.frame(do.call(rbind,rows))
  stopifnot(max(abs(rowSums(z[paste0('reason_',1:9,'_pct')])-z$any_reason_pct))<1e-10)
  stopifnot(max(abs(z$successful_modern_switch_pct +
                      z$ended_without_successful_modern_switch_pct -
                      z$any_reason_pct)) < 1e-10)
  z
}

monthly <- do.call(rbind,lapply(methods,function(m) {
  d <- if (m=='All specified modern methods') e else e[e$modern_method==m,]
  cbind(method=m,life_table(d))
}))
rownames(monthly) <- NULL

revised <- do.call(rbind,lapply(methods,function(m) {
  d <- if (m=='All specified modern methods') e else e[e$modern_method==m,]
  last <- monthly[monthly$method==m & monthly$month==12,]
  values <- as.numeric(last[paste0('reason_',1:9,'_pct')])
  names(values) <- reasons
  data.frame(method=m,as.list(values),any_reason_pct=last$any_reason_pct,
    switched_pct=last$switching_pct,weighted_episodes=sum(d$wt),
    unweighted_episodes=nrow(d),first_month_episodes=sum(d$entry==0),
    women=length(unique(d$caseid)),check.names=FALSE)
}))
rownames(revised) <- NULL

trend <- do.call(rbind,lapply(methods,function(m) {
  d <- if (m=='All specified modern methods') e else e[e$modern_method==m,]
  z <- monthly[monthly$method==m & monthly$month %in% horizons,]
  data.frame(method=m,month=z$month,any_reason_pct=z$any_reason_pct,
    survival_pct=100-z$any_reason_pct,weighted_at_risk=z$at_risk,
    weighted_episodes=sum(d$wt),unweighted_episodes=nrow(d),
    first_month_episodes=sum(d$entry==0),
    discontinued_through_month=vapply(z$month,function(t)sum(d$discontinued & d$exposure<=t),integer(1)))
}))
rownames(trend) <- NULL

# Presentation table that separates successful modern-method switching from
# endings that are not followed by a successful modern switch. The 12-month
# components add exactly to the original-method discontinuation probability.
modern_exit_partition <- do.call(rbind,lapply(methods,function(m) {
  z <- monthly[monthly$method==m & monthly$month %in% c(3L,6L,12L),]
  z <- z[match(c(3L,6L,12L),z$month),]
  data.frame(
    method=m,
    ended_without_successful_modern_switch_3m=
      z$ended_without_successful_modern_switch_pct[z$month==3L],
    ended_without_successful_modern_switch_6m=
      z$ended_without_successful_modern_switch_pct[z$month==6L],
    ended_without_successful_modern_switch_12m=
      z$ended_without_successful_modern_switch_pct[z$month==12L],
    successful_modern_switch_12m=
      z$successful_modern_switch_pct[z$month==12L],
    total_original_method_discontinuation_12m=
      z$any_reason_pct[z$month==12L],
    check.names=FALSE
  )
}))
rownames(modern_exit_partition) <- NULL
stopifnot(max(abs(
  modern_exit_partition$ended_without_successful_modern_switch_12m +
    modern_exit_partition$successful_modern_switch_12m -
    modern_exit_partition$total_original_method_discontinuation_12m
)) < 1e-10)

# The unchanged method rows must reproduce every column of published Table 7.11.
# The newly defined Other modern and All specified modern rows have different
# denominators and therefore cannot be matched to the report's Other/All rows.
shared <- names(group_codes)[1:4]
for (m in shared) {
  row <- revised[revised$method==m,]
  ix <- match(m,original$methods)
  observed <- c(as.numeric(row[reasons]),row$any_reason_pct,row$switched_pct,row$weighted_episodes)
  expected <- as.numeric(original$calculated[ix,])
  stopifnot(max(abs(observed-expected))<1e-8)
  shown <- c(round(observed[1:11],1),round(observed[12]))
  stopifnot(all(shown==as.numeric(original$reference[ix,])))
}

# For any-reason discontinuation, the multiple-decrement total equals an
# ordinary weighted Kaplan-Meier calculation with all reasons as events.
independent_max_difference <- 0
for (m in methods) {
  d <- if (m=='All specified modern methods') e else e[e$modern_method==m,]
  km <- survival::survfit(survival::Surv(entry,exposure,discontinued)~1,
    data=d,weights=wt,id=episode_id,se.fit=FALSE)
  s <- summary(km,times=horizons,extend=TRUE)$surv
  result <- trend$any_reason_pct[trend$method==m]
  independent_max_difference <- max(independent_max_difference,max(abs(100*(1-s)-result)))
}
stopifnot(independent_max_difference<1e-8)

saveRDS(e,file.path(project,'Data','Derived','ethiopia_2024_specified_modern_method_episodes.rds'))
jsonlite::write_json(list(
  survey='Ethiopia DHS 2024-25',
  source_report=Sys.getenv("ETHIOPIA_DHS_REPORT", unset=""),
  source_table='Table 7.11, printed page 140 / PDF page 178',
  method_codes=group_codes,
  methods=methods,reasons=reasons,horizons=horizons,
  revised_table_7_11=revised,milestone_rates=trend,
  modern_exit_partition=modern_exit_partition,
  monthly_life_tables=monthly,
  audit=list(shared_method_rows_matching_all_published_cells=length(shared),
    independent_kaplan_meier_max_difference_percentage_points=independent_max_difference,
    all_modern_group_meaning='All modern methods represented in the requested grouping; excludes traditional methods.'),
  notes=c('Other modern methods contains IUD, male condom, female sterilization, male sterilization, LAM, SDM, and other modern method.',
          'No eligible episodes have other modern method code 17.',
          'Male condom is included in Other modern methods. No eligible female-condom episodes occur in this dataset.',
          'The four unchanged method rows match published Table 7.11 at 12 months. Other modern and All specified modern methods are new groupings without directly matching published rows.',
          'The original Table 7.11 reason-recovery and observation-boundary conventions are retained.'),
  run_time=format(Sys.time(),'%Y-%m-%d %H:%M:%S %Z')),
  file.path(out,'modern_method_discontinuation_results.json'),pretty=TRUE,digits=12)
capture.output(sessionInfo(),file=file.path(out,'R_session_info.txt'))
print(revised,row.names=FALSE)
print(trend[trend$month %in% horizons,c('method','month','any_reason_pct','first_month_episodes')],row.names=FALSE)
cat('Validated four published rows across all Table 7.11 columns. Independent KM difference:',
    independent_max_difference,'percentage points.\n')


# 6. Export concise tables for later analyses and the project HTML -----------
revised_export <- revised
names(revised_export)[names(revised_export) ==
                        "Other method-related reasons"] <-
  "Access, cost, or inconvenience"
write.csv(revised_export,
          file.path(project, "output", "revised_table_7_11.csv"),
          row.names = FALSE, na = "")
write.csv(trend[trend$month %in% horizons, ],
          file.path(project, "output", "discontinuation_by_time.csv"),
          row.names = FALSE, na = "")
write.csv(modern_exit_partition,
          file.path(project, "output",
                    "discontinuation_excluding_successful_modern_switches.csv"),
          row.names = FALSE, na = "")

# Cause-specific cumulative incidence at presentation time points. These are
# probabilities among all eligible episodes, not reason distributions among
# episodes that discontinued. Within each row, the nine reason probabilities
# add to the any-reason probability apart from rounding.
reason_time <- monthly[monthly$month %in% c(3L, 6L, 12L),
  c("method", "month", paste0("reason_", 1:9, "_pct"),
    "any_reason_pct")]
names(reason_time)[match(paste0("reason_", 1:9, "_pct"),
                         names(reason_time))] <- reasons
names(reason_time)[names(reason_time) == "Other method-related reasons"] <-
  "Access, cost, or inconvenience"
names(reason_time)[names(reason_time) == "any_reason_pct"] <- "Any reason"
write.csv(
  reason_time,
  file.path(project, "output",
            "cause_specific_discontinuation_3_6_12.csv"),
  row.names = FALSE, na = ""
)

# 6a. Presentation view: monthly cumulative discontinuation, excluding EC ----
# This view retains the four requested method groups and recomputes the overall
# life table after removing emergency-contraception episodes. It is therefore a
# custom presentation aggregate and is not the published DHS "All methods" row.
if (!requireNamespace("ggplot2", quietly = TRUE)) {
  install.packages("ggplot2", repos = "https://cloud.r-project.org")
}
library(ggplot2)

# Presentation figure for cause-specific cumulative incidence. The detailed
# tables retain all nine Table 7.11 reasons; the figure combines them into five
# legible leadership categories.
reason_plot_rows <- lapply(seq_len(nrow(reason_time)), function(i) {
  data.frame(
    method = reason_time$method[i],
    month = reason_time$month[i],
    reason = c(
      "Fertility-related",
      "Side effects / bleeding",
      "Method, access or effectiveness",
      "Partner disapproval",
      "Other reasons"
    ),
    cumulative_pct = c(
      reason_time[i, "Desire to become pregnant"] +
        reason_time[i, "Other fertility-related reasons"],
      reason_time[i, "Changes in menstrual bleeding"] +
        reason_time[i, "Other side effects/health concerns"],
      reason_time[i, "Method failure"] +
        reason_time[i, "Wanted more effective method"] +
        reason_time[i, "Access, cost, or inconvenience"],
      reason_time[i, "Husband/partner disapproved"],
      reason_time[i, "Other reasons"]
    ),
    stringsAsFactors = FALSE
  )
})
reason_plot_data <- do.call(rbind, reason_plot_rows)

reason_method_order <- c(
  "Injectables", "Implants", "Pill", "Emergency contraception",
  "Other modern methods", "All specified modern methods"
)
reason_family_order <- c(
  "Fertility-related", "Side effects / bleeding",
  "Method, access or effectiveness", "Partner disapproval", "Other reasons"
)
reason_plot_data$method <- factor(
  reason_plot_data$method, levels = rev(reason_method_order)
)
reason_plot_data$month_label <- factor(
  paste(reason_plot_data$month, "months"),
  levels = c("3 months", "6 months", "12 months")
)
reason_plot_data$reason <- factor(
  reason_plot_data$reason, levels = reason_family_order
)

reason_totals <- reason_time[, c("method", "month", "Any reason")]
reason_totals$method <- factor(
  reason_totals$method, levels = rev(reason_method_order)
)
reason_totals$month_label <- factor(
  paste(reason_totals$month, "months"),
  levels = c("3 months", "6 months", "12 months")
)

reason_palette <- c(
  "Fertility-related" = "#168F8F",
  "Side effects / bleeding" = "#D75F4B",
  "Method, access or effectiveness" = "#DDA02B",
  "Partner disapproval" = "#153F5B",
  "Other reasons" = "#707988"
)

reason_time_plot <- ggplot(
  reason_plot_data,
  aes(x = cumulative_pct, y = method, fill = reason)
) +
  geom_col(width = 0.68, color = "white", linewidth = 0.2,
           position = position_stack(reverse = TRUE)) +
  geom_text(
    data = reason_totals,
    aes(x = `Any reason` + 1.0, y = method,
        label = sprintf("%.1f%%", `Any reason`)),
    inherit.aes = FALSE, hjust = 0, color = "#111111",
    fontface = "bold", size = 3.35
  ) +
  facet_wrap(~month_label, nrow = 1) +
  scale_fill_manual(values = reason_palette, name = NULL) +
  scale_x_continuous(
    limits = c(0, 98), breaks = c(0, 25, 50, 75),
    labels = function(z) paste0(z, "%"),
    expand = expansion(mult = c(0, 0))
  ) +
  labs(
    title = "Reasons for discontinuation accumulate across the first year",
    subtitle = paste0(
      "Cause-specific cumulative probability of ending the original method; ",
      "total discontinuation is labeled at the end of each bar"
    ),
    x = "Cumulative probability of discontinuation (%)", y = NULL,
    caption = paste0(
      "Weighted multiple-decrement life-table estimates. Detailed nine-reason ",
      "results appear in the accompanying tables."
    )
  ) +
  guides(fill = guide_legend(nrow = 2, byrow = TRUE)) +
  theme_minimal(base_size = 12) +
  theme(
    plot.title = element_text(size = 20, face = "bold", color = "#153F5B",
                              margin = margin(b = 5)),
    plot.subtitle = element_text(size = 11.5, color = "#53606F",
                                 margin = margin(b = 12)),
    plot.caption = element_text(size = 9, color = "#667684", hjust = 0,
                                margin = margin(t = 10)),
    strip.text = element_text(size = 14, face = "bold", color = "#153F5B",
                              hjust = 0.5, margin = margin(b = 8)),
    axis.text.x = element_text(color = "#111111", size = 10.5),
    axis.text.y = element_text(color = "#111111", size = 10.5),
    axis.title.x = element_text(color = "#111111", face = "bold",
                                margin = margin(t = 9)),
    panel.grid.major.y = element_blank(),
    panel.grid.minor = element_blank(),
    panel.grid.major.x = element_line(color = "#D9E1E6", linewidth = 0.35),
    panel.spacing.x = grid::unit(1.1, "lines"),
    legend.position = "bottom",
    legend.text = element_text(color = "#111111", size = 10),
    legend.key.size = grid::unit(0.8, "lines"),
    legend.spacing.x = grid::unit(0.35, "lines"),
    plot.margin = margin(16, 20, 14, 18)
  )

assets_dir <- file.path(project, "output", "assets")
dir.create(assets_dir, recursive = TRUE, showWarnings = FALSE)
ggsave(
  file.path(assets_dir, "cause_specific_discontinuation_3_6_12.png"),
  reason_time_plot, width = 16, height = 8.4, units = "in", dpi = 220,
  bg = "white"
)

presentation_methods <- c("Injectables", "Implants", "Pill",
                          "Other modern methods")
presentation_monthly <- monthly[monthly$method %in% presentation_methods,
                                c("method", "month", "any_reason_pct")]

including_ec_monthly <- monthly[
  monthly$method == "All specified modern methods",
  c("month", "any_reason_pct")
]
including_ec_monthly$method <-
  "All specified modern methods (including EC)"

no_ec_episodes <- e[as.character(e$modern_method) !=
                      "Emergency contraception", ]
no_ec_monthly <- life_table(no_ec_episodes)[,
  c("month", "any_reason_pct")]
no_ec_monthly$method <- "All specified modern methods (excluding EC)"
presentation_monthly <- rbind(
  presentation_monthly,
  including_ec_monthly[, c("method", "month", "any_reason_pct")],
  no_ec_monthly[, c("method", "month", "any_reason_pct")]
)

presentation_order <- c("Injectables", "Implants", "Pill",
                        "Other modern methods",
                        "All specified modern methods (including EC)",
                        "All specified modern methods (excluding EC)")
presentation_monthly$method <- factor(
  presentation_monthly$method, levels = presentation_order
)

presentation_table <- presentation_monthly[
  presentation_monthly$month %in% c(3L, 6L, 12L), ]
presentation_table <- reshape(
  presentation_table, idvar = "method", timevar = "month",
  direction = "wide"
)
names(presentation_table) <- sub("any_reason_pct\\.", "month_",
                                 names(presentation_table))
presentation_table <- presentation_table[
  match(presentation_order, as.character(presentation_table$method)), ]
presentation_table$weighted_episodes <- c(
  sum(e$wt[as.character(e$modern_method) == "Injectables"]),
  sum(e$wt[as.character(e$modern_method) == "Implants"]),
  sum(e$wt[as.character(e$modern_method) == "Pill"]),
  sum(e$wt[as.character(e$modern_method) == "Other modern methods"]),
  sum(e$wt),
  sum(no_ec_episodes$wt)
)
write.csv(
  presentation_table,
  file.path(project, "output", "discontinuation_presentation_3_6_12.csv"),
  row.names = FALSE, na = ""
)

# Add a month-zero origin so the step curves begin at 0%.
plot_data <- rbind(
  presentation_monthly,
  data.frame(
    method = factor(presentation_order, levels = presentation_order),
    month = 0, any_reason_pct = 0
  )
)
plot_data <- plot_data[order(plot_data$method, plot_data$month), ]

palette <- c(
  "Injectables" = "#0072B2",
  "Implants" = "#CC79A7",
  "Pill" = "#D55E00",
  "Other modern methods" = "#009E73",
  "All specified modern methods (including EC)" = "#727B86",
  "All specified modern methods (excluding EC)" = "#0B3558"
)
checkpoints <- presentation_monthly[
  presentation_monthly$month %in% c(3L, 6L, 12L), ]
injectable_checkpoints <- checkpoints[
  as.character(checkpoints$method) == "Injectables", ]
overall_checkpoints <- checkpoints[
  as.character(checkpoints$method) ==
    "All specified modern methods (excluding EC)", ]
including_checkpoints <- checkpoints[
  as.character(checkpoints$method) ==
    "All specified modern methods (including EC)", ]
checkpoint_boxes <- merge(
  overall_checkpoints[, c("month", "any_reason_pct")],
  including_checkpoints[, c("month", "any_reason_pct")],
  by = "month", suffixes = c("_excluding", "_including")
)
checkpoint_boxes <- merge(
  checkpoint_boxes,
  injectable_checkpoints[, c("month", "any_reason_pct")],
  by = "month"
)
checkpoint_boxes$label <- sprintf(
  "%d MONTHS\nAll incl. EC  %.1f%%\nAll excl. EC  %.1f%%\nInjectables  %.1f%%",
  checkpoint_boxes$month,
  checkpoint_boxes$any_reason_pct_including,
  checkpoint_boxes$any_reason_pct_excluding,
  checkpoint_boxes$any_reason_pct
)

endpoints <- presentation_monthly[presentation_monthly$month == 12L, ]
endpoints$label <- sprintf("%s  %.1f%%", endpoints$method,
                           endpoints$any_reason_pct)
endpoints$label_y <- endpoints$any_reason_pct
endpoints$label_y[as.character(endpoints$method) == "Injectables"] <- 46.2
endpoints$label_y[as.character(endpoints$method) ==
                    "All specified modern methods (including EC)"] <- 41.7
endpoints$label_y[as.character(endpoints$method) ==
                    "All specified modern methods (excluding EC)"] <- 37.8

plot_data$line_emphasis <- ifelse(
  as.character(plot_data$method) ==
    "All specified modern methods (excluding EC)", "Overall excluding EC",
  ifelse(as.character(plot_data$method) ==
           "All specified modern methods (including EC)",
         "Overall including EC", "Individual method")
)

p <- ggplot(plot_data,
            aes(x = month, y = any_reason_pct, color = method,
                group = method)) +
  geom_vline(xintercept = c(3, 6, 12), color = "#0B3558",
             linewidth = 0.35, linetype = "dashed", alpha = 0.35) +
  geom_step(aes(linewidth = line_emphasis, linetype = line_emphasis),
            direction = "hv", show.legend = FALSE) +
  geom_point(data = checkpoints, size = 2.8, shape = 21,
             stroke = 1.1, fill = "white", show.legend = FALSE) +
  geom_label(data = checkpoint_boxes,
             aes(x = month, y = 74, label = label),
             inherit.aes = FALSE, size = 3.1, lineheight = 1.05,
             color = "#263746", fill = "#F5F8FA",
             linewidth = 0.25,
             label.padding = grid::unit(0.25, "lines")) +
  geom_segment(data = endpoints,
               aes(x = 12.05, xend = 12.28,
                   y = any_reason_pct, yend = label_y),
               linewidth = 0.7, show.legend = FALSE) +
  geom_text(data = endpoints,
            aes(x = 12.34, y = label_y, label = label),
            hjust = 0, fontface = "bold", size = 3.4,
            show.legend = FALSE) +
  scale_color_manual(values = palette) +
  scale_linewidth_manual(values = c(
    "Individual method" = 1.05,
    "Overall including EC" = 1.3,
    "Overall excluding EC" = 1.8
  )) +
  scale_linetype_manual(values = c(
    "Individual method" = "solid",
    "Overall including EC" = "22",
    "Overall excluding EC" = "solid"
  )) +
  scale_x_continuous(
    breaks = c(0, 3, 6, 12), labels = c("Start", "3", "6", "12"),
    expand = expansion(mult = c(0, 0))
  ) +
  scale_y_continuous(
    breaks = seq(0, 70, 10), limits = c(0, 82),
    labels = function(z) paste0(z, "%"),
    expand = expansion(mult = c(0, 0))
  ) +
  coord_cartesian(xlim = c(0, 12), clip = "off") +
  labs(
    title = "Nearly four in ten modern-method episodes end within 12 months",
    subtitle = paste0(
      "Cumulative probability of ending the original method; ",
      "overall estimates are shown with and without emergency contraception"
    ),
    x = "Months of method use completed",
    y = "Cumulative probability of discontinuation (%)",
    caption = paste0(
      "Weighted episode-level life-table estimates. Ending the original ",
      "method includes immediate switching to another modern method."
    )
  ) +
  theme_minimal(base_size = 12) +
  theme(
    plot.title = element_text(size = 20, face = "bold", color = "#153B5B"),
    plot.subtitle = element_text(size = 11.5, color = "#4F5E6B"),
    plot.caption = element_text(size = 9, color = "#667684", hjust = 0),
    axis.title = element_text(face = "bold", color = "#263746"),
    axis.text = element_text(color = "#40515F"),
    panel.grid.minor = element_blank(),
    panel.grid.major.x = element_blank(),
    panel.grid.major.y = element_line(color = "#D9E1E6", linewidth = 0.35),
    plot.margin = margin(16, 260, 15, 18),
    legend.position = "none"
  )

assets_dir <- file.path(project, "output", "assets")
dir.create(assets_dir, recursive = TRUE, showWarnings = FALSE)
ggsave(
  file.path(assets_dir, "cumulative_discontinuation_3_6_12.png"),
  p, width = 13.5, height = 7.3, units = "in", dpi = 220,
  bg = "white"
)

cat("\nAnalysis complete. Main outputs are in:\n",
    file.path(project, "output"), "\n")

# 7. Estimate the modern-method initiation mix -------------------------------
# The modular script contains the survey-design estimates, calendar-year
# coverage checks, CSV exports, and publication-style figures.
source(file.path(project, "Code", "02_method_initiation_analysis.R"))

# 8. Reproduce and adapt Table 7.12 reasons for discontinuation ------------
source(file.path(project, "Code", "03_reasons_for_discontinuation_table_7_12.R"))

# 9. Classify post-discontinuation destinations and modern-use retention -----
source(file.path(project, "Code", "04_post_discontinuation_transitions.R"))

# 10. Estimate modern-use exit among a current-user cohort -------------------
source(file.path(project, "Code", "05_current_user_modern_exit.R"))

# 11. Link episode reasons and destinations; construct current-user pathway --
source(file.path(project, "Code", "06_actionable_pathways.R"))

# 12. Standardize current-user pathways to the interview-date stock ----------
source(file.path(project, "Code", "07_standardized_current_user_pathway.R"))
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 02_method_initiation_analysis.R
# LANGUAGE: R
MODULES[["02_method_initiation_analysis.R"]] <- list(
 language="R",
 packaged_sha256="9ecf2815ddd22d2dd0f45f5a0fc6aeeca770d8701108546cbf67149bc3a3bfe2",
 args=character(),
 code=r"-----(
# Full DHS sampling frame, including PSUs with no eligible outcome records.
full_survey_frame <- function(){
 r<-Sys.getenv('ETHIOPIA_PROJECT_ROOT'); stopifnot(nzchar(r))
 x<-readRDS(file.path(r,'Data/ET2024DHS__ETIR8ADT__IR_raw.rds'))
 unique(data.frame(cluster=paste(as.integer(x$v022),as.integer(x$v021),sep=':'),stratum=as.integer(x$v022)))
}
complete_survey_data <- function(d){
 r<-Sys.getenv('ETHIOPIA_PROJECT_ROOT');x<-readRDS(file.path(r,'Data/ET2024DHS__ETIR8ADT__IR_raw.rds'))
 f<-unique(data.frame(v021=as.integer(x$v021),v022=as.integer(x$v022)))
 key<-function(a,b)paste(a,b,sep=':');miss<-f[!key(f$v021,f$v022)%in%key(d$v021,d$v022),]
 if(nrow(miss)){z<-d[rep(1L,nrow(miss)),,drop=FALSE];z$v021<-miss$v021;z$v022<-miss$v022;z$wt<-0;d<-rbind(d,z)}
 d
}
#!/usr/bin/env Rscript
# Ethiopia DHS 2024-25: distribution of observed modern-method initiations.
#
# Universe: contraceptive episodes whose start is observed 3-62 months before
# the woman's interview. Episodes already underway when the recorded calendar
# begins and episodes entering the discontinuation window through delayed entry
# are not initiation events in this period.
# Input lineage: 00_import_ir_dta.R reads the original one-woman-per-row
# ETIR8AFL.dta into an unchanged RDS; ethiopia_modern_method_discontinuation.R
# converts each woman's 80-character calendar to one row per continuous run.
# This script starts from those RUNS, not from a woman-month long file.
#
# Point estimates use v005/1,000,000. Standard errors and 95% confidence
# intervals use Taylor linearization with DHS sampling strata v022 and PSUs
# v021. Women may contribute multiple starts; all their records remain within
# the same PSU, so the PSU-robust design preserves within-woman dependence.

options(stringsAsFactors = FALSE)
options(survey.lonely.psu = "adjust")

required_packages <- c("survey", "ggplot2")
# survey estimates weighted shares and design-based uncertainty from DHS PSU
# and stratum identifiers; ggplot2 writes the figures. Only missing CRAN
# software is downloaded here; the restricted DHS .dta remains local.
missing_packages <- setdiff(required_packages, rownames(installed.packages()))
if (length(missing_packages)) {
  install.packages(missing_packages, repos = "https://cloud.r-project.org")
}
invisible(lapply(required_packages, library, character.only = TRUE))

project <- Sys.getenv("ETHIOPIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
output_dir <- file.path(project, "output")
asset_dir <- file.path(output_dir, "assets")
dir.create(asset_dir, recursive = TRUE, showWarnings = FALSE)

ir <- readRDS(file.path(project, "Data", "ET2024DHS__ETIR8ADT__IR_raw.rds"))
calendar_events <- readRDS(file.path(project, "Data", "Derived", "ethiopia_2024_calendar_events.rds"))

# DHS calendar method codes retained as modern methods for this analysis.
# Male condom (code 5) is part of Other modern methods.
method_codes <- list(
  "Injectables" = 3L,
  "Implants" = 11L,
  "Pill" = 1L,
  "Emergency contraception" = 16L,
  "Other modern methods" = c(2L, 5L, 6L, 7L, 13L, 17L, 18L)
)
method_levels <- names(method_codes)
modern_codes <- unlist(method_codes, use.names = FALSE)

# Select observed episode starts in the same 3-62 month period used by the DHS
# discontinuation table. start != calendar_start excludes left-censored runs
# whose actual initiation occurred before the recorded calendar.
starts <- calendar_events[
  calendar_events$method_code %in% modern_codes &
    calendar_events$start != calendar_events$calendar_start,
]
starts$months_before_interview <- starts$interview - starts$start
starts <- starts[
  starts$months_before_interview >= 3L &
    starts$months_before_interview <= 62L,
]
# Exclude EC later in the dedicated presentation view (script 18). At this
# point, this base initiation cohort includes EC for DHS coding comparison.

starts$method_group <- NA_character_
for (m in method_levels) {
  starts$method_group[starts$method_code %in% method_codes[[m]]] <- m
}
stopifnot(!anyNA(starts$method_group), nrow(starts) == 7859L)
starts$method_group <- factor(starts$method_group, levels = method_levels)

# Convert DHS Century Month Code to Gregorian calendar year and month.
starts$calendar_year <- 1900L + (starts$start - 1L) %/% 12L
starts$calendar_month <- 1L + (starts$start - 1L) %% 12L

# Attach design variables from the woman-level IR record. woman_row is retained
# when the calendar event file is created, avoiding a many-to-many merge.
starts$v021 <- ir$v021[starts$woman_row]
starts$v022 <- ir$v022[starts$woman_row]
stopifnot(!anyNA(starts$v021), !anyNA(starts$v022))

initiation_design <- survey::svydesign(
  ids = ~v021,
  strata = ~v022,
  weights = ~wt,
  data = complete_survey_data(starts),
  nest = TRUE
)
# v005 supplies the woman's weight to every start she contributes. v021 PSUs
# nested in v022 strata account for clustered sampling and repeated starts
# from the same woman when calculating standard errors and intervals.

# Estimate method shares within a supplied survey design. Weighted and raw
# counts are reported alongside design-based standard errors and 95% CIs.
estimate_mix <- function(design, raw_data, period_label) {
  do.call(rbind, lapply(method_levels, function(m) {
    design_m <- update(design, method_indicator = as.numeric(method_group == m))
    fit <- survey::svymean(~method_indicator, design_m, na.rm = TRUE)
    interval <- confint(fit, level = 0.95)
    data.frame(
      period = period_label,
      method = m,
      unweighted_starts = sum(raw_data$method_group == m),
      weighted_starts = sum(raw_data$wt[raw_data$method_group == m]),
      share_pct = 100 * unname(coef(fit)[1]),
      standard_error_pct = 100 * unname(SE(fit)[1]),
      ci_lower_pct = 100 * interval[1],
      ci_upper_pct = 100 * interval[2]
    )
  }))
}

overall_mix <- estimate_mix(initiation_design, starts, "All starts, months 3-62")
# Keep the exported table in the same descending order as the horizontal chart.
overall_mix <- overall_mix[order(overall_mix$share_pct, decreasing = TRUE),]
rownames(overall_mix) <- NULL

years <- sort(unique(starts$calendar_year))
year_mix <- do.call(rbind, lapply(years, function(y) {
  raw_y <- starts[starts$calendar_year == y,]
  estimate_mix(subset(initiation_design, calendar_year == y), raw_y, as.character(y))
}))
year_mix$calendar_year <- as.integer(year_mix$period)

# Identify calendar years covered for every interviewed woman. The edge years
# contain observed starts but are not complete for the full survey sample.
common_first_cmc <- max(ir$v008 - 62L)
common_last_cmc <- min(ir$v008 - 3L)
year_is_complete <- function(y) {
  jan <- (y - 1900L) * 12L + 1L
  dec <- jan + 11L
  jan >= common_first_cmc && dec <= common_last_cmc
}
year_mix$coverage <- ifelse(
  vapply(year_mix$calendar_year, year_is_complete, logical(1)),
  "Complete across all interviews",
  "Partial sample coverage"
)

year_totals <- do.call(rbind, lapply(years, function(y) {
  z <- starts[starts$calendar_year == y,]
  data.frame(
    calendar_year = y,
    coverage = if (year_is_complete(y)) "Complete across all interviews" else "Partial sample coverage",
    unweighted_starts = nrow(z),
    weighted_starts = sum(z$wt),
    contributing_women = length(unique(z$caseid))
  )
}))

# Internal checks: shares sum to 100 within rounding error and the overall
# number of starts equals the entry-at-duration-1 cohort used earlier.
stopifnot(abs(sum(overall_mix$share_pct) - 100) < 1e-8)
stopifnot(all(abs(aggregate(share_pct ~ calendar_year, year_mix, sum)$share_pct - 100) < 1e-8))
stopifnot(sum(overall_mix$unweighted_starts) == nrow(starts))

write.csv(overall_mix, file.path(output_dir, "method_initiation_mix_overall.csv"), row.names = FALSE)
write.csv(year_mix, file.path(output_dir, "method_initiation_mix_by_year.csv"), row.names = FALSE)
write.csv(year_totals, file.path(output_dir, "method_initiation_year_coverage.csv"), row.names = FALSE)
saveRDS(starts, file.path(project, "Data", "Derived", "ethiopia_2024_modern_method_starts.rds"))

# Publication-style figures modeled on the supplied diagnostic example.
palette <- c(
  "Injectables" = "#168f8f",
  "Implants" = "#153f5b",
  "Pill" = "#dda02b",
  "Emergency contraception" = "#d75f4b",
  "Other modern methods" = "#707988"
)

overall_plot_data <- overall_mix
overall_descending <- overall_plot_data$method[order(overall_plot_data$share_pct, decreasing = TRUE)]
# Discrete y-axis levels are drawn from bottom to top, so reverse the desired
# top-to-bottom descending order when setting factor levels.
overall_plot_data$method <- factor(overall_plot_data$method,
                                   levels = rev(overall_descending))
overall_plot <- ggplot(overall_plot_data, aes(x = share_pct, y = method, fill = method)) +
  geom_col(width = 0.72) +
  geom_segment(aes(x = ci_lower_pct, xend = ci_upper_pct, yend = method),
               linewidth = 0.55, color = "#18242d") +
  geom_point(aes(x = ci_lower_pct), size = 1.6, color = "#18242d") +
  geom_point(aes(x = ci_upper_pct), size = 1.6, color = "#18242d") +
  geom_text(aes(x = ci_upper_pct + 0.8, label = sprintf("%.1f%%", share_pct)), hjust = 0,
            size = 4.3, color = "#18242d") +
  scale_fill_manual(values = palette, guide = "none") +
  scale_x_continuous(expand = expansion(mult = c(0, .16))) +
  labs(title = "Overall modern-method initiation mix",
       subtitle = "Observed episode starts 3-62 months before interview; whiskers are design-based 95% CIs",
       x = "Share of weighted modern-method starts (%)", y = NULL) +
  theme_minimal(base_size = 13) +
  theme(plot.title = element_text(face = "bold", color = "#153f5b", size = 18),
        plot.subtitle = element_text(color = "#53606f"),
        axis.text.y = element_text(color = "#18242d", size = 12),
        panel.grid.major.y = element_blank(), panel.grid.minor = element_blank())

year_plot_data <- year_mix
year_plot_data$method <- factor(year_plot_data$method, levels = method_levels)
year_plot_data$year_label <- ifelse(year_plot_data$coverage == "Partial sample coverage",
                                    paste0(year_plot_data$calendar_year, "*"),
                                    as.character(year_plot_data$calendar_year))
year_plot_data$year_label <- factor(year_plot_data$year_label,
                                    levels = unique(year_plot_data$year_label))
year_plot <- ggplot(year_plot_data, aes(x = year_label, y = share_pct, fill = method)) +
  geom_col(width = 0.72, position = position_stack(reverse = TRUE)) +
  scale_fill_manual(values = palette, name = NULL) +
  scale_y_continuous(breaks = seq(0,100,20), expand = expansion(mult = c(0,0))) +
  coord_cartesian(ylim = c(0,100)) +
  labs(title = "Modern-method initiation mix by calendar year",
       subtitle = "Each bar is the weighted distribution of observed starts; * indicates partial survey-sample coverage",
       x = "Calendar year of episode start", y = "Share of weighted starts (%)") +
  theme_minimal(base_size = 13) +
  theme(plot.title = element_text(face = "bold", color = "#153f5b", size = 18),
        plot.subtitle = element_text(color = "#53606f"),
        panel.grid.minor = element_blank(), legend.position = "bottom")

ggsave(file.path(asset_dir, "method_initiation_mix_overall.png"), overall_plot,
       width = 10.5, height = 6.2, dpi = 180, bg = "white")
ggsave(file.path(asset_dir, "method_initiation_mix_by_year.png"), year_plot,
       width = 11.5, height = 6.4, dpi = 180, bg = "white")

capture.output(sessionInfo(), file = file.path(output_dir, "method_initiation_session_info.txt"))
cat("Modern-method starts:", nrow(starts), "from", length(unique(starts$caseid)), "women\n")
print(overall_mix, row.names = FALSE)
print(year_totals, row.names = FALSE)
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 03_reasons_for_discontinuation_table_7_12.R
# LANGUAGE: R
MODULES[["03_reasons_for_discontinuation_table_7_12.R"]] <- list(
 language="R",
 packaged_sha256="f9dbcb84916f51d284a3a28aef805aba6ac386474f47409f33ae76811ccc40eb",
 args=character(),
 code=r"-----(
# Full DHS sampling frame, including PSUs with no eligible outcome records.
full_survey_frame <- function(){
 r<-Sys.getenv('ETHIOPIA_PROJECT_ROOT'); stopifnot(nzchar(r))
 x<-readRDS(file.path(r,'Data/ET2024DHS__ETIR8ADT__IR_raw.rds'))
 unique(data.frame(cluster=paste(as.integer(x$v022),as.integer(x$v021),sep=':'),stratum=as.integer(x$v022)))
}
complete_survey_data <- function(d){
 r<-Sys.getenv('ETHIOPIA_PROJECT_ROOT');x<-readRDS(file.path(r,'Data/ET2024DHS__ETIR8ADT__IR_raw.rds'))
 f<-unique(data.frame(v021=as.integer(x$v021),v022=as.integer(x$v022)))
 key<-function(a,b)paste(a,b,sep=':');miss<-f[!key(f$v021,f$v022)%in%key(d$v021,d$v022),]
 if(nrow(miss)){z<-d[rep(1L,nrow(miss)),,drop=FALSE];z$v021<-miss$v021;z$v022<-miss$v022;z$wt<-0;d<-rbind(d,z)}
 d
}
#!/usr/bin/env Rscript
# Ethiopia DHS 2024-25 Table 7.12: reasons for discontinuation.
#
# Table 7.12 is a weighted percent distribution of recorded discontinuation
# events, not a life table. Following the DHS tabulation program, calendar
# positions v018 through v018+59 are inspected and each nonblank vcal_2 reason
# is classified with the method recorded in vcal_1 in that same month.

options(stringsAsFactors = FALSE)
options(survey.lonely.psu = "adjust")
required_packages <- c("survey", "jsonlite", "ggplot2")
missing_packages <- setdiff(required_packages, rownames(installed.packages()))
if (length(missing_packages)) install.packages(missing_packages, repos = "https://cloud.r-project.org")
invisible(lapply(required_packages, library, character.only = TRUE))

project <- Sys.getenv("ETHIOPIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
output_dir <- file.path(project, "output")
derived_dir <- file.path(project, "Data", "Derived")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
asset_dir <- file.path(output_dir, "assets")
dir.create(asset_dir, recursive = TRUE, showWarnings = FALSE)

ir <- readRDS(file.path(project, "Data", "ET2024DHS__ETIR8ADT__IR_raw.rds"))
ir_v018 <- as.numeric(unclass(ir$v018))
ir_v005 <- as.numeric(unclass(ir$v005))
ir_v021 <- as.numeric(unclass(ir$v021))
ir_v022 <- as.numeric(unclass(ir$v022))
method_characters <- strsplit("123456789WNALCFEMS~", "")[[1]]

# Mapping follows the DHS CSPro Table 7.14/2024-25 Ethiopia Table 7.12 code.
reason_character_map <- c(
  "1"=1L, "2"=2L, "3"=3L, "7"=4L, "M"=5L,
  "4"=6L, "6"=7L, "C"=8L, "8"=9L, "F"=10L,
  "A"=11L, "9"=12L, "D"=13L, "W"=14L, "K"=15L, "?"=99L
)
reason_labels <- c(
  "Became pregnant while using",
  "Wanted to become pregnant",
  "Husband/partner disapproved",
  "Wanted a more effective method",
  "Changes in menstrual bleeding",
  "Other side effects/health concerns",
  "Lack of access/too far",
  "Cost too much",
  "Inconvenient to use",
  "Up to God/fatalistic",
  "Difficult to get pregnant/menopausal",
  "Infrequent sex/husband away",
  "Marital dissolution/separation",
  "Other",
  "Don't know"
)

# Extract the discontinuation events exactly as the published tabulation does.
event_list <- vector("list", nrow(ir))
for (i in seq_len(nrow(ir))) {
  positions <- as.integer(ir_v018[i]) + 0:59
  reason_chars <- substring(sprintf("%-80s", ir$vcal_2[i]), positions, positions)
  keep <- reason_chars != " "
  if (any(keep)) {
    method_chars <- substring(ir$vcal_1[i], positions[keep], positions[keep])
    event_list[[i]] <- data.frame(
      woman_row = i,
      caseid = ir$caseid[i],
      calendar_position = positions[keep],
      method_code = match(method_chars, method_characters),
      reason_code = unname(reason_character_map[reason_chars[keep]]),
      wt = ir_v005[i] / 1e6,
      v021 = ir_v021[i],
      v022 = ir_v022[i]
    )
  }
}
events <- do.call(rbind, event_list)
events <- events[!is.na(events$method_code) & events$reason_code %in% 1:15,]
stopifnot(nrow(events) == 6685L, !anyNA(events$reason_code))
events$reason <- factor(events$reason_code, levels = 1:15, labels = reason_labels)

# Reproduce the method columns printed in the report before regrouping them.
published_method <- function(code) {
  ifelse(code == 2, "IUD",
  ifelse(code == 3, "Injectables",
  ifelse(code == 11, "Implants",
  ifelse(code == 1, "Pill",
  ifelse(code == 5, "Male condom",
  ifelse(code == 16, "Emergency contraception",
  ifelse(code == 8, "Rhythm",
  ifelse(code == 9, "Withdrawal", "Other"))))))))
}
events$published_method <- published_method(events$method_code)
published_methods <- c("IUD", "Injectables", "Implants", "Pill", "Male condom",
                       "Emergency contraception", "Rhythm", "Withdrawal", "Other", "All methods")

weighted_distribution <- function(data) {
  totals <- vapply(1:15, function(k) sum(data$wt[data$reason_code == k]), numeric(1))
  100 * totals / sum(totals)
}
published_calculated <- sapply(published_methods, function(m) {
  z <- if (m == "All methods") events else events[events$published_method == m,]
  weighted_distribution(z)
})
rownames(published_calculated) <- reason_labels
published_counts <- vapply(published_methods, function(m) {
  z <- if (m == "All methods") events else events[events$published_method == m,]
  sum(z$wt)
}, numeric(1))

# Published values transcribed from Ethiopia DHS 2024-25 Table 7.12.
published_reference <- cbind(
  "IUD" = c(0,50.5,0,17.8,14.7,3.1,.4,.2,6.5,1.3,3.3,1.1,.1,.9,0),
  "Injectables" = c(2.1,50.4,.7,11.5,6.7,6.2,3.5,.3,5.6,2.2,.5,6.3,1.7,2.1,.2),
  "Implants" = c(.9,49.3,.2,14.9,4.1,11.8,.9,.2,9.7,.6,.4,2.8,.9,2.9,.5),
  "Pill" = c(6.2,28.8,2.5,22.9,3.3,2.6,.7,.3,7.7,2.4,1,17.5,1.8,1,1.4),
  "Male condom" = c(0,20.2,2.7,6.8,1.1,1.5,.9,0,4.3,8.9,0,51.8,0,0,1.9),
  "Emergency contraception" = c(1,9.2,0,7.1,4.9,8,.6,0,3.5,3.2,0,56,5.8,.4,.2),
  "Rhythm" = c(10.4,48.9,0,13.1,1,.1,0,0,2.5,.7,.5,17.2,5.4,.2,0),
  "Withdrawal" = c(2.2,36.4,0,6.3,0,0,0,0,1.4,0,2.9,21.8,8.1,21.1,0),
  "Other" = c(2.5,29.6,0,46.7,.1,6.7,0,0,0,8.7,0,0,.1,5.3,.4),
  "All methods" = c(2.3,46.7,.8,13.7,5.7,6.9,2.4,.3,6.5,1.9,.6,8.1,1.6,2.1,.4)
)
rownames(published_reference) <- reason_labels
percentage_match <- round(published_calculated, 1) == published_reference
# The released file reproduces all 135 method-specific cells and 149/150 cells
# overall. The report shows 2.4 for all-method lack of access versus 2.5 from
# the released data, alongside the injectable count discrepancy documented below.
stopifnot(sum(percentage_match) == 149L,
          round(published_calculated["Lack of access/too far", "All methods"], 1) == 2.5)

report_counts <- c(118,4689,1654,777,32,175,122,25,64,7656)
names(report_counts) <- published_methods
# All published counts except Injectables and the resulting All-methods total
# match the released file. Their reason percentages nevertheless match exactly.
stopifnot(all(round(published_counts[-c(2,10)]) == report_counts[-c(2,10)]))

# Requested modern-method grouping, consistent with the other project tables.
modern_method_codes <- list(
  "Injectables" = 3L,
  "Implants" = 11L,
  "Pill" = 1L,
  "Emergency contraception" = 16L,
  "Other modern methods" = c(2L,5L,6L,7L,13L,17L,18L)
)
modern_codes <- unlist(modern_method_codes, use.names = FALSE)
modern <- events[events$method_code %in% modern_codes,]
modern$method_group <- NA_character_
for (m in names(modern_method_codes)) {
  modern$method_group[modern$method_code %in% modern_method_codes[[m]]] <- m
}
modern_methods <- c(names(modern_method_codes), "All specified modern methods")
stopifnot(!anyNA(modern$method_group))

modern_table <- sapply(modern_methods, function(m) {
  z <- if (m == "All specified modern methods") modern else modern[modern$method_group == m,]
  weighted_distribution(z)
})
rownames(modern_table) <- reason_labels
modern_counts <- vapply(modern_methods, function(m) {
  z <- if (m == "All specified modern methods") modern else modern[modern$method_group == m,]
  sum(z$wt)
}, numeric(1))
modern_unweighted <- vapply(modern_methods, function(m) {
  z <- if (m == "All specified modern methods") modern else modern[modern$method_group == m,]
  nrow(z)
}, integer(1))
stopifnot(all(abs(colSums(modern_table) - 100) < 1e-8))

# Aggregate the 15 detailed Table 7.12 reasons into the nine reason categories
# used in the Table 7.11 life-table analysis.
aggregated_reason_labels <- c(
  "Method failure",
  "Desire to become pregnant",
  "Other fertility-related reasons",
  "Changes in menstrual bleeding",
  "Other side effects/health concerns",
  "Wanted a more effective method",
  "Access, cost, or inconvenience",
  "Husband/partner disapproved",
  "Other reasons"
)
reason_to_aggregate <- c(
  1L, # Became pregnant while using
  2L, # Wanted to become pregnant
  8L, # Husband/partner disapproved
  6L, # Wanted a more effective method
  4L, # Changes in menstrual bleeding
  5L, # Other side effects/health concerns
  7L, # Lack of access/too far
  7L, # Cost too much
  7L, # Inconvenient to use
  9L, # Up to God/fatalistic
  3L, # Difficult to get pregnant/menopausal
  3L, # Infrequent sex/husband away
  3L, # Marital dissolution/separation
  9L, # Other
  9L  # Don't know
)
modern$aggregated_reason_code <- reason_to_aggregate[modern$reason_code]
aggregated_distribution <- function(data) {
  totals <- vapply(1:9, function(k) sum(data$wt[data$aggregated_reason_code == k]), numeric(1))
  100 * totals / sum(totals)
}
aggregated_table <- sapply(modern_methods, function(m) {
  z <- if (m == "All specified modern methods") modern else modern[modern$method_group == m,]
  aggregated_distribution(z)
})
rownames(aggregated_table) <- aggregated_reason_labels
stopifnot(all(abs(colSums(aggregated_table) - 100) < 1e-8))
aggregate_rank <- order(aggregated_table[,"All specified modern methods"], decreasing = TRUE)
aggregated_table_ranked <- aggregated_table[aggregate_rank,,drop = FALSE]

# Design-based uncertainty for the adapted table. Point estimates remain the
# same weighted column percentages used in the published report.
modern$method_group <- factor(modern$method_group, levels = names(modern_method_codes))
design <- survey::svydesign(ids = ~v021, strata = ~v022, weights = ~wt,
                            data = complete_survey_data(modern), nest = TRUE)
uncertainty <- do.call(rbind, lapply(modern_methods, function(m) {
  dm <- if (m == "All specified modern methods") design else subset(design, method_group == m)
  do.call(rbind, lapply(seq_along(reason_labels), function(k) {
    dk <- update(dm, indicator = as.numeric(reason_code == k))
    fit <- survey::svymean(~indicator, dk, na.rm = TRUE)
    ci <- confint(fit)
    data.frame(method = m, reason = reason_labels[k],
               percent = 100 * unname(coef(fit)[1]),
               standard_error_pct = 100 * unname(SE(fit)[1]),
               ci_lower_pct = 100 * ci[1], ci_upper_pct = 100 * ci[2])
  }))
}))

aggregated_uncertainty <- do.call(rbind, lapply(modern_methods, function(m) {
  dm <- if (m == "All specified modern methods") design else subset(design, method_group == m)
  do.call(rbind, lapply(seq_along(aggregated_reason_labels), function(k) {
    dk <- update(dm, indicator = as.numeric(aggregated_reason_code == k))
    fit <- survey::svymean(~indicator, dk, na.rm = TRUE)
    ci <- confint(fit)
    data.frame(method = m, reason = aggregated_reason_labels[k],
               percent = 100 * unname(coef(fit)[1]),
               standard_error_pct = 100 * unname(SE(fit)[1]),
               ci_lower_pct = 100 * ci[1], ci_upper_pct = 100 * ci[2])
  }))
}))

adapted <- data.frame(reason = reason_labels, modern_table, check.names = FALSE)
write.csv(adapted, file.path(output_dir, "revised_table_7_12_reasons.csv"), row.names = FALSE)
write.csv(data.frame(reason = rownames(aggregated_table_ranked), aggregated_table_ranked,
                     check.names = FALSE),
          file.path(output_dir, "revised_table_7_12_aggregated_reasons.csv"), row.names = FALSE)
write.csv(data.frame(method = modern_methods, unweighted_discontinuations = modern_unweighted,
                     weighted_discontinuations = modern_counts),
          file.path(output_dir, "revised_table_7_12_counts.csv"), row.names = FALSE)
write.csv(uncertainty, file.path(output_dir, "revised_table_7_12_uncertainty.csv"), row.names = FALSE)
write.csv(aggregated_uncertainty,
          file.path(output_dir, "revised_table_7_12_aggregated_uncertainty.csv"), row.names = FALSE)
write.csv(data.frame(reason = reason_labels, published_calculated, check.names = FALSE),
          file.path(output_dir, "table_7_12_published_replication.csv"), row.names = FALSE)
saveRDS(modern, file.path(derived_dir, "ethiopia_2024_modern_method_discontinuations_5yr.rds"))

# Presentation figures: a ranked aggregate view for the primary message and a
# labeled heatmap for method-specific differences.
ranked_plot_data <- data.frame(
  reason = rownames(aggregated_table_ranked),
  percent = aggregated_table_ranked[,"All specified modern methods"]
)
ranked_plot_data$reason <- factor(ranked_plot_data$reason,
                                  levels = rev(ranked_plot_data$reason))
ranked_plot <- ggplot(ranked_plot_data, aes(x = percent, y = reason)) +
  geom_col(width = .72, fill = "#168f8f") +
  geom_text(aes(label = sprintf("%.1f%%", percent)), hjust = -.18,
            color = "#18242d", size = 4.2) +
  scale_x_continuous(expand = expansion(mult = c(0,.15))) +
  labs(title = "Why modern-method episodes were discontinued",
       subtitle = "Weighted distribution across all specified modern methods",
       x = "Share of recorded discontinuations (%)", y = NULL) +
  theme_minimal(base_size = 13) +
  theme(plot.title = element_text(face = "bold", color = "#153f5b", size = 18),
        plot.subtitle = element_text(color = "#53606f"),
        panel.grid.major.y = element_blank(), panel.grid.minor = element_blank(),
        axis.text.y = element_text(color = "#18242d"))

specific_methods <- names(modern_method_codes)
heatmap_data <- expand.grid(reason = rownames(aggregated_table),
                            method = specific_methods,
                            stringsAsFactors = FALSE)
heatmap_data$percent <- as.vector(aggregated_table[,specific_methods,drop=FALSE])
ranked_reasons <- rownames(aggregated_table_ranked)
heatmap_data$reason <- factor(heatmap_data$reason, levels = rev(ranked_reasons))
heatmap_data$method <- factor(heatmap_data$method, levels = specific_methods)
heatmap_plot <- ggplot(heatmap_data, aes(x = method, y = reason, fill = percent)) +
  geom_tile(color = "white", linewidth = 1) +
  geom_text(aes(label = sprintf("%.1f", percent),
                color = percent >= 20), size = 3.8) +
  scale_color_manual(values = c("FALSE"="#18242d", "TRUE"="white"), guide = "none") +
  scale_fill_gradient(low = "#edf4f5", high = "#153f5b", name = "Percent") +
  labs(title = "Reasons for discontinuation differ by method",
       subtitle = "Weighted percentage distribution within each method; columns sum to 100%",
       x = NULL, y = NULL) +
  theme_minimal(base_size = 12) +
  theme(plot.title = element_text(face = "bold", color = "#153f5b", size = 18),
        plot.subtitle = element_text(color = "#53606f"),
        panel.grid = element_blank(), axis.text.x = element_text(angle = 18, hjust = 1),
        legend.position = "right")

ggsave(file.path(asset_dir, "reasons_for_discontinuation_ranked.png"), ranked_plot,
       width = 10.5, height = 6.4, dpi = 180, bg = "white")
ggsave(file.path(asset_dir, "reasons_for_discontinuation_heatmap.png"), heatmap_plot,
       width = 12, height = 7.2, dpi = 180, bg = "white")

audit <- list(
  published_percentage_cells_matching = sum(percentage_match),
  published_percentage_cells_total = length(published_reference),
  released_file_injectable_weighted_count = unname(published_counts["Injectables"]),
  report_injectable_count = unname(report_counts["Injectables"]),
  released_file_all_methods_weighted_count = unname(published_counts["All methods"]),
  report_all_methods_count = unname(report_counts["All methods"]),
  modern_discontinuation_events_unweighted = nrow(modern),
  modern_discontinuation_events_weighted = sum(modern$wt)
)
jsonlite::write_json(audit, file.path(output_dir, "table_7_12_audit.json"),
                     pretty = TRUE, digits = 12, auto_unbox = TRUE)
capture.output(sessionInfo(), file = file.path(output_dir, "table_7_12_session_info.txt"))
cat("Validated", audit$published_percentage_cells_matching, "of",
    audit$published_percentage_cells_total, "published percentage cells.\n")
print(round(modern_table,1))
print(data.frame(method=modern_methods, unweighted=modern_unweighted, weighted=modern_counts), row.names=FALSE)
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 04_post_discontinuation_transitions.R
# LANGUAGE: R
MODULES[["04_post_discontinuation_transitions.R"]] <- list(
 language="R",
 packaged_sha256="af331f736a75c32f53b7d1139acaaef655a82b457d9b4e06147b22d618480015",
 args=character(),
 code=r"-----(#!/usr/bin/env Rscript
# Ethiopia DHS 2024-25: what happens after a modern-method episode ends?
#
# This analysis uses the same five-year discontinuation-event cohort as the
# revised Table 7.12. Each recorded modern-method discontinuation is linked to
# the next (more recent) calendar month. A direct move to another requested
# modern method is a successful switch. Consistent with the DHS switching rule,
# a one-month nonuse gap followed by a different modern method is also retained
# when the recorded reason is "wanted a more effective method." A same-method
# entry in the following month is retained modern use, but is identified as a
# same-method continuation/restart rather than a switch.

options(stringsAsFactors = FALSE)

# 1. Install and load packages ------------------------------------------------
required_packages <- c("jsonlite", "ggplot2")
missing_packages <- setdiff(required_packages, rownames(installed.packages()))
if (length(missing_packages)) {
  install.packages(missing_packages, repos = "https://cloud.r-project.org")
}
invisible(lapply(required_packages, library, character.only = TRUE))

# 2. Read the individual women's recode file ---------------------------------
project <- Sys.getenv("ETHIOPIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
output_dir <- file.path(project, "output")
asset_dir <- file.path(output_dir, "assets")
derived_dir <- file.path(project, "Data", "Derived")
dir.create(asset_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(derived_dir, recursive = TRUE, showWarnings = FALSE)

ir <- readRDS(file.path(project, "Data", "ET2024DHS__ETIR8ADT__IR_raw.rds"))
v018 <- as.numeric(unclass(ir$v018))
v005 <- as.numeric(unclass(ir$v005))

# Native DHS calendar symbols, in their numeric-code order.
method_characters <- strsplit("123456789WNALCFEMS~", "")[[1]]
reason_character_map <- c(
  "1"=1L, "2"=2L, "3"=3L, "7"=4L, "M"=5L,
  "4"=6L, "6"=7L, "C"=8L, "8"=9L, "F"=10L,
  "A"=11L, "9"=12L, "D"=13L, "W"=14L, "K"=15L, "?"=99L
)

# Requested modern-method definition used throughout this project.
modern_codes <- c(1L, 2L, 3L, 5L, 6L, 7L, 11L, 13L, 16L, 17L, 18L)
traditional_codes <- c(8L, 9L, 10L)

method_group <- function(code) {
  ifelse(code == 3L, "Injectables",
  ifelse(code == 11L, "Implants",
  ifelse(code == 1L, "Pill",
  ifelse(code == 16L, "Emergency contraception",
  ifelse(code %in% c(2L,5L,6L,7L,13L,17L,18L),
         "Other modern methods", NA_character_)))))
}

# 3. Extract Table 7.12 discontinuations and their following state -----------
# Calendar strings run from the interview backward in time. Therefore,
# calendar_position - 1 is the month after the recorded discontinuation.
event_list <- vector("list", nrow(ir))
for (i in seq_len(nrow(ir))) {
  positions <- as.integer(v018[i]) + 0:59
  reason_chars <- substring(sprintf("%-80s", ir$vcal_2[i]), positions, positions)
  keep <- reason_chars != " "
  if (any(keep)) {
    p <- positions[keep]
    current_char <- substring(ir$vcal_1[i], p, p)
    next_char <- ifelse(p > 1L, substring(ir$vcal_1[i], p - 1L, p - 1L), NA_character_)
    next2_char <- ifelse(p > 2L, substring(ir$vcal_1[i], p - 2L, p - 2L), NA_character_)
    event_list[[i]] <- data.frame(
      woman_row = i,
      caseid = ir$caseid[i],
      calendar_position = p,
      origin_code = match(current_char, method_characters),
      next_code = match(next_char, method_characters),
      next2_code = match(next2_char, method_characters),
      next_char = next_char,
      reason_code = unname(reason_character_map[reason_chars[keep]]),
      wt = v005[i] / 1e6
    )
  }
}
transitions <- do.call(rbind, event_list)
transitions <- transitions[
  transitions$origin_code %in% modern_codes & transitions$reason_code %in% 1:15,
]
stopifnot(nrow(transitions) == 6548L, abs(sum(transitions$wt) - 7501.658) < 0.001)

transitions$origin <- method_group(transitions$origin_code)

# DHS counts a one-month gap as switching only when the stated reason is
# "wanted a more effective method" and a different method appears thereafter.
special_gap_switch <- transitions$reason_code == 4L &
  transitions$next_char == "0" &
  transitions$next2_code %in% modern_codes &
  transitions$next2_code != transitions$origin_code

direct_modern <- transitions$next_code %in% modern_codes
same_method_restart <- direct_modern & transitions$next_code == transitions$origin_code
successful_switch <- (direct_modern & transitions$next_code != transitions$origin_code) |
  special_gap_switch
destination_code <- ifelse(special_gap_switch, transitions$next2_code, transitions$next_code)

transitions$retention_status <- ifelse(
  direct_modern | special_gap_switch, "Retained modern use", "Modern-use exit"
)
transitions$transition_type <- ifelse(
  successful_switch, "Successful modern-method switch",
  ifelse(same_method_restart, "Same-method continuation/restart", "Modern-use exit")
)
transitions$destination <- ifelse(
  direct_modern | special_gap_switch, method_group(destination_code),
  ifelse(transitions$next_char == "0", "No method",
  ifelse(transitions$next_char %in% c("P", "B", "T"), "Pregnancy/birth/termination",
  ifelse(transitions$next_code %in% traditional_codes, "Traditional method", "Other/unknown state")))
)
stopifnot(!anyNA(transitions$origin), !anyNA(transitions$destination))

origin_levels <- c("Injectables", "Implants", "Pill", "Emergency contraception",
                   "Other modern methods")
destination_levels <- c("Injectables", "Implants", "Pill", "Emergency contraception",
                        "Other modern methods", "No method",
                        "Pregnancy/birth/termination", "Traditional method",
                        "Other/unknown state")

# 4. Weighted transition matrix and summary ----------------------------------
flow <- aggregate(wt ~ origin + destination, transitions, sum)
all_cells <- expand.grid(origin = origin_levels, destination = destination_levels,
                         stringsAsFactors = FALSE)
flow <- merge(all_cells, flow, by = c("origin", "destination"), all.x = TRUE)
flow$wt[is.na(flow$wt)] <- 0
flow$origin <- factor(flow$origin, levels = origin_levels)
flow$destination <- factor(flow$destination, levels = destination_levels)
flow <- flow[order(flow$origin, flow$destination),]
origin_totals <- aggregate(wt ~ origin, flow, sum)
flow$origin_total <- origin_totals$wt[match(flow$origin, origin_totals$origin)]
flow$row_pct <- 100 * flow$wt / flow$origin_total

matrix_pct <- xtabs(row_pct ~ origin + destination, flow)
matrix_weighted <- xtabs(wt ~ origin + destination, flow)
matrix_export <- data.frame(origin_method = rownames(matrix_pct), round(unclass(matrix_pct), 6),
                            weighted_discontinuations = rowSums(matrix_weighted), check.names = FALSE)
write.csv(matrix_export, file.path(output_dir, "post_discontinuation_transition_matrix_percent.csv"),
          row.names = FALSE)
write.csv(data.frame(origin_method = rownames(matrix_weighted), round(unclass(matrix_weighted), 6),
                     check.names = FALSE),
          file.path(output_dir, "post_discontinuation_transition_matrix_weighted.csv"),
          row.names = FALSE)
write.csv(transitions, file.path(output_dir, "post_discontinuation_transition_events.csv"),
          row.names = FALSE)
saveRDS(transitions, file.path(derived_dir, "ethiopia_2024_post_discontinuation_transitions.rds"))

weighted_total <- sum(transitions$wt)
summary_counts <- aggregate(wt ~ transition_type, transitions, sum)
summary_counts$share_pct <- 100 * summary_counts$wt / weighted_total
write.csv(summary_counts, file.path(output_dir, "post_discontinuation_retention_summary.csv"),
          row.names = FALSE)

# 5. Draw a presentation-ready alluvial diagram in base R --------------------
# The custom drawing avoids a package-specific HTML widget and produces a
# portable PNG that renders in the consolidated analysis page and slides.
source_colors <- c(
  "Injectables"="#188f8c", "Implants"="#174866", "Pill"="#dda02d",
  "Emergency contraception"="#d85c48", "Other modern methods"="#717987"
)
destination_colors <- c(
  "Injectables"="#238b76", "Implants"="#2e8f67", "Pill"="#49a377",
  "Emergency contraception"="#70b58d", "Other modern methods"="#93c6a3",
  "No method"="#7b8ea6", "Pregnancy/birth/termination"="#d64a4a",
  "Traditional method"="#e27620", "Other/unknown state"="#a2a8ae"
)

draw_alluvial <- function(filename) {
  png(filename, width = 2600, height = 1500, res = 180, type = "quartz")
  par(mar = c(3, 3, 6, 3), xpd = NA, family = "sans")
  plot.new(); plot.window(xlim = c(-0.08, 1.28), ylim = c(0, 1))

  active_dest <- destination_levels[colSums(matrix_weighted) > 0]
  src_gap <- 0.025; dst_gap <- 0.018
  src_scale <- (0.82 - src_gap * (length(origin_levels) - 1)) / weighted_total
  dst_scale <- (0.82 - dst_gap * (length(active_dest) - 1)) / weighted_total
  src_nodes <- data.frame(name = origin_levels, bottom = NA_real_, top = NA_real_)
  dst_nodes <- data.frame(name = active_dest, bottom = NA_real_, top = NA_real_)
  y <- 0.91
  for (i in seq_along(origin_levels)) {
    h <- origin_totals$wt[match(origin_levels[i], origin_totals$origin)] * src_scale
    src_nodes$top[i] <- y; src_nodes$bottom[i] <- y - h; y <- y - h - src_gap
  }
  dtotal <- colSums(matrix_weighted)[active_dest]
  y <- 0.91
  for (i in seq_along(active_dest)) {
    h <- dtotal[i] * dst_scale
    dst_nodes$top[i] <- y; dst_nodes$bottom[i] <- y - h; y <- y - h - dst_gap
  }

  src_cursor <- setNames(src_nodes$top, src_nodes$name)
  dst_cursor <- setNames(dst_nodes$top, dst_nodes$name)
  bezier_x <- function(t, x0, x1) (1-t)^3*x0 + 3*(1-t)^2*t*(x0+.22) +
    3*(1-t)*t^2*(x1-.22) + t^3*x1
  bezier_y <- function(t, y0, y1) (1-t)^3*y0 + 3*(1-t)^2*t*y0 +
    3*(1-t)*t^2*y1 + t^3*y1
  x0 <- 0.14; x1 <- 0.77
  for (d in active_dest) for (s in origin_levels) {
    w <- matrix_weighted[s, d]
    if (w <= 0) next
    sy_top <- src_cursor[s]; sy_bottom <- sy_top - w * src_scale
    dy_top <- dst_cursor[d]; dy_bottom <- dy_top - w * dst_scale
    tt <- seq(0, 1, length.out = 100)
    xx <- bezier_x(tt, x0, x1)
    polygon(c(xx, rev(xx)),
            c(bezier_y(tt, sy_top, dy_top), rev(bezier_y(tt, sy_bottom, dy_bottom))),
            col = adjustcolor(destination_colors[d], alpha.f = 0.50), border = NA)
    src_cursor[s] <- sy_bottom; dst_cursor[d] <- dy_bottom
  }

  rect(0.10, src_nodes$bottom, 0.14, src_nodes$top,
       col = source_colors[src_nodes$name], border = NA)
  rect(0.77, dst_nodes$bottom, 0.81, dst_nodes$top,
       col = destination_colors[dst_nodes$name], border = NA)
  text(0.085, rowMeans(src_nodes[,c("bottom","top")]),
       labels = paste0(src_nodes$name, "\n", format(round(origin_totals$wt[match(src_nodes$name, origin_totals$origin)]), big.mark=",")),
       adj = 1, cex = 0.78, col = "#18313e", font = 2)
  dest_pct <- 100 * dtotal / weighted_total
  label_y <- rowMeans(dst_nodes[,c("bottom","top")])
  names(label_y) <- dst_nodes$name
  modern_label_y <- c(0.91, 0.865, 0.82, 0.775, 0.73)
  names(modern_label_y) <- origin_levels
  for (d in intersect(origin_levels, dst_nodes$name)) {
    segments(0.81, label_y[d], 0.822, modern_label_y[d], col = "#9aadb4", lwd = 0.8)
    label_y[d] <- modern_label_y[d]
  }
  text(0.825, label_y[dst_nodes$name],
       labels = paste0(dst_nodes$name, "\n", sprintf("%.1f%%", dest_pct[dst_nodes$name])),
       adj = 0, cex = 0.66, col = "#18313e", font = 2)
  text(0.10, 0.96, "DISCONTINUED METHOD", adj = 0, cex = 0.72, font = 2, col = "#5b6c74")
  text(0.77, 0.96, "NEXT STATE", adj = 0, cex = 0.72, font = 2, col = "#5b6c74")

  retained <- sum(transitions$wt[transitions$retention_status == "Retained modern use"])
  switched <- sum(transitions$wt[transitions$transition_type == "Successful modern-method switch"])
  same <- sum(transitions$wt[transitions$transition_type == "Same-method continuation/restart"])
  roundedrectangle <- function(xleft, ybottom, xright, ytop, col, border) {
    rect(xleft, ybottom, xright, ytop, col = col, border = border, lwd = 1.4)
  }
  roundedrectangle(1.03, 0.78, 1.25, 0.90, "#e4f4e9", "#8cc8a0")
  text(1.14, 0.84, paste0("RETAINED MODERN USE\n", sprintf("%.1f%%",100*retained/weighted_total),
                           "  (switches ", sprintf("%.1f%%",100*switched/weighted_total),
                           "; same method ", sprintf("%.1f%%",100*same/weighted_total), ")"),
       cex = 0.56, font = 2, col = "#174866")
  roundedrectangle(1.03, 0.48, 1.25, 0.59, "#fbe2df", "#e9a29a")
  text(1.14, 0.535, paste0("MODERN-USE EXIT\n", sprintf("%.1f%%",100*(weighted_total-retained)/weighted_total)),
       cex = 0.76, font = 2, col = "#174866")
  title(main = "Where women go after a modern-method episode is discontinued",
        sub = paste0("Weighted flows among ", format(round(weighted_total), big.mark=","),
                     " discontinuation events in the five-year calendar"),
        adj = 0.05, cex.main = 1.35, col.main = "#174866", cex.sub = 0.86, col.sub = "#5b6c74")
  mtext("Modern destinations retain women in modern use; no method, pregnancy-related states, and traditional methods are classified as exits.",
        side = 1, line = 1, adj = 0.05, cex = 0.72, col = "#5b6c74")
  dev.off()
}

draw_alluvial(file.path(asset_dir, "post_discontinuation_alluvial.png"))

# 6. Matched month-1 and month-12 presentation figures -----------------------
# For a direct comparison of immediate and 12-month states, restrict both
# figures to discontinuations with all 12 subsequent calendar months observed.
# These figures use literal calendar states. They do not apply the one-month-gap
# switching convention used in the DHS discontinuation table.
matched <- transitions[
  transitions$calendar_position >= v018[transitions$woman_row] + 12L,
]
stopifnot(nrow(matched) == 5118L, abs(sum(matched$wt) - 5830.966889) < 0.001)

calendar_state <- function(character, code) {
  result <- rep("Other/unknown state", length(character))
  result[character == "0"] <- "No method"
  result[character %in% c("P", "B", "T")] <- "Pregnancy/birth/termination"
  result[code %in% traditional_codes] <- "Traditional method"
  modern_state <- method_group(code)
  result[!is.na(modern_state)] <- modern_state[!is.na(modern_state)]
  result
}

matched$month1_state <- calendar_state(matched$next_char, matched$next_code)
matched$month12_char <- mapply(
  function(i, position) substring(ir$vcal_1[i], position - 12L, position - 12L),
  matched$woman_row, matched$calendar_position, USE.NAMES = FALSE
)
matched$month12_code <- match(matched$month12_char, method_characters)
matched$month12_state <- calendar_state(matched$month12_char, matched$month12_code)
stopifnot(!any(matched$month1_state == "Other/unknown state"),
          !any(matched$month12_state == "Other/unknown state"))

matched_destination_levels <- c(
  "Injectables", "Implants", "Pill", "Emergency contraception",
  "Other modern methods", "No method", "Pregnancy/birth/termination",
  "Traditional method"
)

complete_flows <- function(state_variable) {
  z <- aggregate(matched$wt,
    by = list(origin = matched$origin, destination = matched[[state_variable]]), sum)
  names(z)[3] <- "weighted_events"
  all_cells <- expand.grid(origin = origin_levels,
                           destination = matched_destination_levels,
                           stringsAsFactors = FALSE)
  z <- merge(all_cells, z, by = c("origin", "destination"), all.x = TRUE)
  z$weighted_events[is.na(z$weighted_events)] <- 0
  z$origin <- factor(z$origin, levels = origin_levels)
  z$destination <- factor(z$destination, levels = matched_destination_levels)
  z <- z[order(z$origin, z$destination),]
  z$origin_total <- ave(z$weighted_events, z$origin, FUN = sum)
  z$origin_pct <- 100 * z$weighted_events / z$origin_total
  z$overall_pct <- 100 * z$weighted_events / sum(z$weighted_events)
  z
}
matched_month1_flows <- complete_flows("month1_state")
matched_month12_flows <- complete_flows("month12_state")
write.csv(matched_month1_flows,
          file.path(output_dir, "post_discontinuation_matched_month1_flows.csv"),
          row.names = FALSE)
write.csv(matched_month12_flows,
          file.path(output_dir, "post_discontinuation_matched_month12_flows.csv"),
          row.names = FALSE)

# Presentation palette, with a neutral gray for no method. Labels and legends
# keep the figures interpretable without relying on color alone.
okabe_ito <- c(
  "Injectables" = "#108B8D",
  "Implants" = "#153F5B",
  "Pill" = "#DA9A25",
  "Emergency contraception" = "#B85C83",
  "Other modern methods" = "#6B7280",
  "No method" = "#7D8991",
  "Pregnancy/birth/termination" = "#D45A49",
  "Traditional method" = "#7055A4"
)

spread_labels <- function(y, minimum_gap, lower, upper) {
  ordering <- order(y)
  positioned <- y[ordering]
  if (length(positioned) > 1L) {
    for (i in 2:length(positioned)) {
      positioned[i] <- max(positioned[i], positioned[i-1L] + minimum_gap)
    }
    if (tail(positioned, 1) > upper) positioned <- positioned - (tail(positioned, 1) - upper)
    for (i in (length(positioned)-1L):1L) {
      if (i >= 1L) positioned[i] <- min(positioned[i], positioned[i+1L] - minimum_gap)
    }
    if (positioned[1] < lower) positioned <- positioned + (lower - positioned[1])
  }
  result <- numeric(length(y)); result[ordering] <- positioned; result
}

draw_matched_alluvial <- function(filename, flows, right_title, figure_title) {
  total <- sum(flows$weighted_events)
  flow_matrix <- xtabs(weighted_events ~ origin + destination, flows)
  active_destinations <- matched_destination_levels[colSums(flow_matrix) > 0]
  origin_totals <- rowSums(flow_matrix)
  destination_totals <- colSums(flow_matrix)[active_destinations]
  source_gap <- 0.028; destination_gap <- 0.018
  source_scale <- (0.75 - source_gap * (length(origin_levels)-1L)) / total
  destination_scale <- (0.75 - destination_gap * (length(active_destinations)-1L)) / total
  source_nodes <- data.frame(name=origin_levels, bottom=NA_real_, top=NA_real_)
  destination_nodes <- data.frame(name=active_destinations, bottom=NA_real_, top=NA_real_)
  y <- 0.88
  for (i in seq_along(origin_levels)) {
    height <- origin_totals[origin_levels[i]] * source_scale
    source_nodes$top[i] <- y; source_nodes$bottom[i] <- y-height; y <- y-height-source_gap
  }
  y <- 0.88
  for (i in seq_along(active_destinations)) {
    height <- destination_totals[active_destinations[i]] * destination_scale
    destination_nodes$top[i] <- y; destination_nodes$bottom[i] <- y-height
    y <- y-height-destination_gap
  }
  source_cursor <- setNames(source_nodes$top, source_nodes$name)
  destination_cursor <- setNames(destination_nodes$top, destination_nodes$name)
  bezier_x <- function(t,x0,x1) (1-t)^3*x0+3*(1-t)^2*t*(x0+.22)+3*(1-t)*t^2*(x1-.22)+t^3*x1
  bezier_y <- function(t,y0,y1) (1-t)^3*y0+3*(1-t)^2*t*y0+3*(1-t)*t^2*y1+t^3*y1

  png(filename, width=2800, height=1800, res=200, type="quartz")
  par(mar=c(6,3,6,3), xpd=NA, family="sans")
  plot.new(); plot.window(xlim=c(-.10,1.10), ylim=c(-.16,1))
  x0 <- .14; x1 <- .76
  for (destination in active_destinations) for (origin in origin_levels) {
    weight <- flow_matrix[origin,destination]
    if (weight <= 0) next
    source_top <- source_cursor[origin]; source_bottom <- source_top-weight*source_scale
    destination_top <- destination_cursor[destination]
    destination_bottom <- destination_top-weight*destination_scale
    tt <- seq(0,1,length.out=100); xx <- bezier_x(tt,x0,x1)
    polygon(c(xx,rev(xx)),
      c(bezier_y(tt,source_top,destination_top),
        rev(bezier_y(tt,source_bottom,destination_bottom))),
      col=adjustcolor(okabe_ito[destination],alpha.f=.42), border=NA)
    source_cursor[origin] <- source_bottom
    destination_cursor[destination] <- destination_bottom
  }
  rect(.10,source_nodes$bottom,.14,source_nodes$top,
       col=unname(okabe_ito[source_nodes$name]),border=NA)
  rect(.76,destination_nodes$bottom,.80,destination_nodes$top,
       col=unname(okabe_ito[destination_nodes$name]),border=NA)

  source_centers <- rowMeans(source_nodes[,c("bottom","top")])
  destination_centers <- rowMeans(destination_nodes[,c("bottom","top")])
  source_label_y <- spread_labels(source_centers,.052,.08,.88)
  destination_label_y <- spread_labels(destination_centers,.052,.08,.88)
  segments(.10,source_centers,.085,source_label_y,col="#9AA8AD")
  segments(.80,destination_centers,.815,destination_label_y,col="#9AA8AD")
  text(.078,source_label_y,
       paste0(source_nodes$name," (",sprintf("%.1f%%",100*origin_totals[source_nodes$name]/total),")"),
       adj=1,cex=.70,font=2,col="#111111")
  text(.822,destination_label_y,
       paste0(destination_nodes$name," (",sprintf("%.1f%%",100*destination_totals[destination_nodes$name]/total),")"),
       adj=0,cex=.68,font=2,col="#111111")
  text(.10,.93,"DISCONTINUED METHOD\nshare of discontinuation events",adj=0,cex=.68,font=2,col="#5B6C74")
  text(.76,.93,paste0(toupper(right_title),"\nshare of discontinuation events"),adj=0,cex=.68,font=2,col="#5B6C74")
  title(main=figure_title,adj=.05,cex.main=1.25,col.main="#174866")
  mtext(paste0("Matched complete-follow-up cohort: 5,118 events (",
               format(round(total),big.mark=",")," weighted)"),
        side=3,line=.25,adj=.05,cex=.72,col="#5B6C74")
  legend("bottom",inset=c(0,-.04),xpd=NA,ncol=4,bty="n",cex=.63,
         title="Next-state color",fill=unname(okabe_ito[matched_destination_levels]),
         legend=matched_destination_levels,text.col="#111111")
  dev.off()
}

draw_matched_alluvial(
  file.path(asset_dir,"post_discontinuation_alluvial_matched_month1.png"),
  matched_month1_flows, "State one month later",
  "Where women are one month after modern-method discontinuation"
)

draw_matched_alluvial(
  file.path(asset_dir,"post_discontinuation_alluvial_matched_month12.png"),
  matched_month12_flows, "State 12 months later",
  "Where women are 12 months after modern-method discontinuation"
)

# Simplified four-destination versions for a side-by-side leadership slide.
# These retain the discontinued episode as the unit of analysis while making
# the change between the immediate and 12-month states readable at half-slide
# size.
collapse_modern_destinations <- function(flows) {
  z <- flows
  z$destination <- as.character(z$destination)
  z$destination[z$destination %in% origin_levels] <- "Modern method"
  z <- aggregate(weighted_events ~ origin + destination, z, sum)
  z$origin <- factor(z$origin, levels=origin_levels)
  z
}
broad_destination_levels <- c(
  "Modern method","No method","Pregnancy/birth/termination",
  "Traditional method"
)
saved_destination_levels <- matched_destination_levels
matched_destination_levels <- broad_destination_levels
okabe_ito["Modern method"] <- "#0072B2"
draw_matched_alluvial(
  file.path(asset_dir,"post_discontinuation_alluvial_broad_month1.png"),
  collapse_modern_destinations(matched_month1_flows),
  "State one month later", "One month after the episode ended"
)
draw_matched_alluvial(
  file.path(asset_dir,"post_discontinuation_alluvial_broad_month12.png"),
  collapse_modern_destinations(matched_month12_flows),
  "State 12 months later", "Twelve months after the episode ended"
)
matched_destination_levels <- saved_destination_levels

# Collapse specific modern destinations for a cleaner month-12 status chart.
month12_broad <- matched
month12_broad$month12_broad_state <- ifelse(
  month12_broad$month12_state %in% origin_levels,
  "Modern method", month12_broad$month12_state
)
broad_levels <- c("Modern method","No method","Pregnancy/birth/termination","Traditional method")
stacked <- aggregate(wt ~ origin + month12_broad_state, month12_broad, sum)
overall_stacked <- aggregate(wt ~ month12_broad_state, month12_broad, sum)
overall_stacked$origin <- "All discontinued modern methods"
stacked <- rbind(stacked, overall_stacked[,names(stacked)])
stacked$origin_total <- ave(stacked$wt, stacked$origin, FUN=sum)
stacked$pct <- 100*stacked$wt/stacked$origin_total
stacked$month12_broad_state <- factor(stacked$month12_broad_state, levels=broad_levels)
stacked$origin <- factor(stacked$origin,
  levels=c(origin_levels,"All discontinued modern methods"))
write.csv(stacked,file.path(output_dir,"post_discontinuation_month12_stacked_states.csv"),row.names=FALSE)

broad_colors <- c("Modern method"="#0072B2","No method"="#6F6F6F",
                  "Pregnancy/birth/termination"="#D55E00",
                  "Traditional method"="#B79F00")
month12_plot <- ggplot(stacked,aes(x=origin,y=pct,fill=month12_broad_state))+
  geom_col(width=.68,position=position_stack(reverse=TRUE))+
  geom_text(data=stacked[stacked$pct>=5,],
            aes(label=sprintf("%.1f%%",pct)),
            position=position_stack(vjust=.5,reverse=TRUE),
            colour="white",fontface="bold",size=3.4)+
  coord_flip()+
  scale_fill_manual(values=broad_colors,drop=FALSE)+
  scale_y_continuous(breaks=seq(0,100,20),
                     labels=function(z)paste0(z,"%"),
                     expand=expansion(mult=c(0,.004)))+
  labs(title="State 12 months after modern-method discontinuation",
       subtitle="Percent distribution among discontinuations with complete 12-month follow-up; each bar sums to 100%",
       x=NULL,y="Share of discontinuation events",fill="State at month 12")+
  theme_minimal(base_size=12)+
  theme(plot.title=element_text(face="bold",colour="#174866",size=16),
        plot.subtitle=element_text(colour="#5B6C74"),
        legend.position="top",legend.title=element_text(face="bold"),
        panel.grid.major.y=element_blank(),panel.grid.minor=element_blank())
ggsave(file.path(asset_dir,"post_discontinuation_month12_stacked.png"),month12_plot,
       width=12,height=7,dpi=220,bg="white")

# 7. Machine-readable audit ---------------------------------------------------
jsonlite::write_json(list(
  cohort = "Recorded modern-method discontinuations in the Table 7.12 five-year calendar window",
  unweighted_events = nrow(transitions),
  weighted_events = weighted_total,
  definitions = list(
    successful_switch = "Direct next-month move to a different specified modern method, plus the DHS one-month-gap rule when the reason was wanted a more effective method",
    same_method_retention = "The same modern method is recorded in the next month after a discontinuation reason",
    modern_use_exit = "Next state is no method, pregnancy/birth/termination, a traditional method, or another nonmodern/unknown state"
  ),
  transition_summary = summary_counts,
  generated = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")
), file.path(output_dir, "post_discontinuation_transition_audit.json"), pretty = TRUE, digits = 12)

cat("Post-discontinuation transition analysis complete.\n")
print(summary_counts, row.names = FALSE)
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 05_current_user_modern_exit.R
# LANGUAGE: R
MODULES[["05_current_user_modern_exit.R"]] <- list(
 language="R",
 packaged_sha256="f35b5da4571dda64f66fde87ecd6ce0f6748c471d9e10152fdcfd392b3be7cc8",
 args=character(),
 code=r"-----(
# Full DHS sampling frame, including PSUs with no eligible outcome records.
full_survey_frame <- function(){
 r<-Sys.getenv('ETHIOPIA_PROJECT_ROOT'); stopifnot(nzchar(r))
 x<-readRDS(file.path(r,'Data/ET2024DHS__ETIR8ADT__IR_raw.rds'))
 unique(data.frame(cluster=paste(as.integer(x$v022),as.integer(x$v021),sep=':'),stratum=as.integer(x$v022)))
}
complete_survey_data <- function(d){
 r<-Sys.getenv('ETHIOPIA_PROJECT_ROOT');x<-readRDS(file.path(r,'Data/ET2024DHS__ETIR8ADT__IR_raw.rds'))
 f<-unique(data.frame(v021=as.integer(x$v021),v022=as.integer(x$v022)))
 key<-function(a,b)paste(a,b,sep=':');miss<-f[!key(f$v021,f$v022)%in%key(d$v021,d$v022),]
 if(nrow(miss)){z<-d[rep(1L,nrow(miss)),,drop=FALSE];z$v021<-miss$v021;z$v022<-miss$v022;z$wt<-0;d<-rbind(d,z)}
 d
}
#!/usr/bin/env Rscript
# Ethiopia DHS 2024-25: modern-use exits among current users.
#
# Purpose: estimate the probability that a woman who is currently using any
# specified modern method exits modern use during the following 1, 2, 3, or
# 12 months. Modern-to-modern changes remain inside one modern-use spell.
# These probabilities are designed for application to a current-user stock:
# WRA x method-specific prevalence x current-user exit probability.

options(stringsAsFactors = FALSE)
options(survey.lonely.psu = "adjust")

# 1. Install and load packages ------------------------------------------------
required_packages <- c("survey", "ggplot2", "jsonlite")
missing_packages <- setdiff(required_packages, rownames(installed.packages()))
if (length(missing_packages)) {
  install.packages(missing_packages, repos = "https://cloud.r-project.org")
}
invisible(lapply(required_packages, library, character.only = TRUE))

# 2. Read the IR calendar ------------------------------------------------------
project <- Sys.getenv("ETHIOPIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
output_dir <- file.path(project, "output")
asset_dir <- file.path(output_dir, "assets")
derived_dir <- file.path(project, "Data", "Derived")
dir.create(asset_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(derived_dir, recursive = TRUE, showWarnings = FALSE)

ir <- readRDS(file.path(project, "Data", "ET2024DHS__ETIR8ADT__IR_raw.rds"))
v018 <- as.numeric(unclass(ir$v018))
method_characters <- strsplit("123456789WNALCFEMS~", "")[[1]]
modern_codes <- c(1L, 2L, 3L, 5L, 6L, 7L, 11L, 13L, 16L, 17L, 18L)

method_group <- function(code) {
  ifelse(code == 3L, "Injectables",
  ifelse(code == 11L, "Implants",
  ifelse(code == 1L, "Pill",
  ifelse(code == 16L, "Emergency contraception",
  ifelse(code %in% c(2L,5L,6L,7L,13L,17L,18L),
         "Other modern methods", NA_character_)))))
}

# 3. Construct a historical current-user cohort ------------------------------
# Month 15 before interview is the common baseline. Following women through
# month 3 supplies 12 subsequent observed months while retaining the DHS
# exclusion of the three months immediately preceding interview. Each woman
# contributes at most once, matching a current-user stock denominator.
baseline_position <- v018 + 15L
baseline_character <- mapply(
  function(calendar, position) substring(calendar, position, position),
  ir$vcal_1, baseline_position, USE.NAMES = FALSE
)
baseline_code <- match(baseline_character, method_characters)
keep <- baseline_code %in% modern_codes

cohort <- data.frame(
  woman_row = which(keep),
  caseid = ir$caseid[keep],
  wt = as.numeric(unclass(ir$v005[keep])) / 1e6,
  v021 = as.numeric(unclass(ir$v021[keep])),
  v022 = as.numeric(unclass(ir$v022[keep])),
  baseline_code = baseline_code[keep],
  baseline_method = method_group(baseline_code[keep]),
  exit_month = 13L,
  used_one_month_gap_switch_rule = FALSE
)

# Follow the binary modern/nonmodern state month by month. A change between
# modern methods does not end modern use. Consistent with the DHS convention,
# a single nonuse month is bridged when the recorded reason is "wanted a more
# effective method" and it is followed by a different modern method.
for (j in seq_len(nrow(cohort))) {
  i <- cohort$woman_row[j]
  p0 <- baseline_position[i]
  previous_modern_code <- cohort$baseline_code[j]
  month <- 1L
  while (month <= 12L) {
    state_character <- substring(ir$vcal_1[i], p0 - month, p0 - month)
    state_code <- match(state_character, method_characters)
    if (!is.na(state_code) && state_code %in% modern_codes) {
      previous_modern_code <- state_code
      month <- month + 1L
      next
    }
    bridge_gap <- FALSE
    if (state_character == "0" && month < 12L) {
      reason_character <- substring(
        sprintf("%-80s", ir$vcal_2[i]), p0 - (month - 1L), p0 - (month - 1L)
      )
      following_character <- substring(ir$vcal_1[i], p0 - (month + 1L), p0 - (month + 1L))
      following_code <- match(following_character, method_characters)
      bridge_gap <- reason_character == "7" && !is.na(following_code) &&
        following_code %in% modern_codes && following_code != previous_modern_code
    }
    if (bridge_gap) {
      cohort$used_one_month_gap_switch_rule[j] <- TRUE
      month <- month + 1L
      next
    }
    cohort$exit_month[j] <- month
    break
  }
}

for (month in c(1L,2L,3L,12L)) {
  cohort[[paste0("exit_", month)]] <- as.numeric(cohort$exit_month <= month)
}
stopifnot(!anyNA(cohort$baseline_method), all(cohort$exit_month %in% 1:13))

# 4. Weighted survey estimates ------------------------------------------------
design <- survey::svydesign(
  ids = ~v021, strata = ~v022, weights = ~wt,
  data = complete_survey_data(cohort), nest = TRUE
)
method_levels <- c("Injectables", "Implants", "Pill", "Emergency contraception",
                   "Other modern methods", "All specified modern methods")

estimate_rows <- list()
k <- 0L
for (method_name in method_levels) {
  method_design <- if (method_name == "All specified modern methods") {
    design
  } else {
    subset(design, baseline_method == method_name)
  }
  raw <- if (method_name == "All specified modern methods") {
    cohort
  } else {
    cohort[cohort$baseline_method == method_name,]
  }
  for (month in c(1L,2L,3L,12L)) {
    estimate <- survey::svymean(as.formula(paste0("~exit_", month)), method_design, na.rm = TRUE)
    point <- unname(coef(estimate)[1])
    standard_error <- unname(SE(estimate)[1])
    k <- k + 1L
    estimate_rows[[k]] <- data.frame(
      method = method_name,
      month = month,
      unweighted_current_users = nrow(raw),
      weighted_current_users = sum(weights(method_design, "sampling")),
      exit_pct = 100 * point,
      se_pct = 100 * standard_error,
      lower_pct = max(0, 100 * (point - qnorm(.975) * standard_error)),
      upper_pct = min(100, 100 * (point + qnorm(.975) * standard_error))
    )
  }
}
estimates <- do.call(rbind, estimate_rows)

summary_table <- merge(
  estimates[estimates$month == 3, c("method","unweighted_current_users","weighted_current_users",
                                    "exit_pct","se_pct","lower_pct","upper_pct")],
  estimates[estimates$month == 12, c("method","exit_pct")],
  by = "method", suffixes = c("_3m", "_12m")
)
summary_table$share_of_12m_exits_by_3m_pct <-
  100 * summary_table$exit_pct_3m / summary_table$exit_pct_12m

# Contribution to all early exits, based on the DHS current-user method mix.
non_total <- summary_table$method != "All specified modern methods"
summary_table$weighted_early_exits <-
  summary_table$weighted_current_users * summary_table$exit_pct_3m / 100
total_early_exits <- sum(summary_table$weighted_early_exits[non_total])
summary_table$share_of_all_early_exits_pct <- ifelse(
  non_total, 100 * summary_table$weighted_early_exits / total_early_exits, 100
)

write.csv(estimates, file.path(output_dir, "current_user_modern_exit_by_month.csv"),
          row.names = FALSE)
write.csv(summary_table, file.path(output_dir, "current_user_early_exit_summary.csv"),
          row.names = FALSE)
saveRDS(cohort, file.path(derived_dir, "ethiopia_2024_historical_current_modern_users.rds"))

# 5. Figure: probability of exit in the first three months -------------------
plot_data <- estimates[estimates$month <= 3 &
                         estimates$method != "All specified modern methods",]
plot_data$method <- factor(plot_data$method,
  levels = c("Injectables","Implants","Pill","Other modern methods",
             "Emergency contraception"))
plot_data$month_label <- factor(paste0("Month ", plot_data$month),
                                levels = paste0("Month ", 1:3))

early_plot <- ggplot(plot_data, aes(x = method, y = exit_pct, fill = month_label)) +
  geom_col(position = position_dodge(width = .76), width = .68) +
  geom_errorbar(aes(ymin = lower_pct, ymax = upper_pct),
                position = position_dodge(width = .76), width = .16,
                linewidth = .45, colour = "#18313e") +
  scale_fill_manual(values = c("Month 1"="#b9d7d8", "Month 2"="#5ca5a6", "Month 3"="#176f72")) +
  coord_cartesian(ylim = c(0, max(plot_data$upper_pct) * 1.05)) +
  labs(title = "Modern-use exits accumulate during the first three months",
       subtitle = "Current users at baseline; modern-to-modern switches remain in modern use",
       x = NULL, y = "Cumulative modern-use exit (%)", fill = NULL) +
  theme_minimal(base_size = 12) +
  theme(plot.title = element_text(face = "bold", colour = "#174866", size = 16),
        plot.subtitle = element_text(colour = "#5b6c74"),
        axis.text.x = element_text(angle = 20, hjust = 1),
        legend.position = "top", panel.grid.minor = element_blank())
ggsave(file.path(asset_dir, "current_user_early_modern_exit.png"), early_plot,
       width = 11, height = 6.3, dpi = 220, bg = "white")

# 6. Audit --------------------------------------------------------------------
jsonlite::write_json(list(
  baseline = "15 months before interview",
  follow_up = "months 14 through 3 before interview",
  unweighted_current_users = nrow(cohort),
  weighted_current_users = sum(cohort$wt),
  one_month_gap_switches_bridged_unweighted = sum(cohort$used_one_month_gap_switch_rule),
  all_modern_exit_estimates = estimates[estimates$method == "All specified modern methods",],
  interpretation = "First exit from continuous modern use among women using a specified modern method at baseline. Modern-to-modern switches do not end follow-up.",
  generated = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")
), file.path(output_dir, "current_user_modern_exit_audit.json"), pretty = TRUE, digits = 12)

cat("Current-user modern-exit analysis complete.\n")
print(summary_table, row.names = FALSE)
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 06_actionable_pathways.R
# LANGUAGE: R
MODULES[["06_actionable_pathways.R"]] <- list(
 language="R",
 packaged_sha256="5c8be0dcdb97c29d705c65ae5eaa991899b31dc5da87f4f6e0d1f21b5277a79d",
 args=character(),
 code=r"-----(#!/usr/bin/env Rscript
# =============================================================================
# Ethiopia DHS 2024-25: actionable episode pathways and current-user pathways
# =============================================================================
# This script creates four linked products from the individual women's IR file:
#   1. an injectable reason-to-next-month alluvial;
#   2. an injectable heat map linking reason, episode duration, and destination;
#   3. a program-action evidence table; and
#   4. a woman-level historical-landmark pathway from baseline to months 3 and 12.
#
# The episode products are conditional on a recorded episode discontinuation.
# The current-user pathway instead starts with every woman using a specified
# modern method at a common historical landmark, 15 months before interview.
# This leaves 12 observable months while excluding months 0-2 before interview.
# Each woman contributes at most one landmark observation.
# =============================================================================

options(stringsAsFactors = FALSE)

# 1. Packages and paths -------------------------------------------------------
required_packages <- c("ggplot2", "jsonlite")
missing_packages <- setdiff(required_packages, rownames(installed.packages()))
if (length(missing_packages)) {
  install.packages(missing_packages, repos = "https://cloud.r-project.org")
}
invisible(lapply(required_packages, library, character.only = TRUE))

project <- Sys.getenv("ETHIOPIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
output_dir <- file.path(project, "output")
asset_dir <- file.path(output_dir, "assets")
derived_dir <- file.path(project, "Data", "Derived")
dir.create(asset_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(derived_dir, recursive = TRUE, showWarnings = FALSE)

ir <- readRDS(file.path(project, "Data", "ET2024DHS__ETIR8ADT__IR_raw.rds"))
transitions <- readRDS(file.path(derived_dir, "ethiopia_2024_post_discontinuation_transitions.rds"))
v018 <- as.numeric(unclass(ir$v018))

method_characters <- strsplit("123456789WNALCFEMS~", "")[[1]]
modern_codes <- c(1L, 2L, 3L, 5L, 6L, 7L, 11L, 13L, 16L, 17L, 18L)
traditional_codes <- c(8L, 9L, 10L)

method_group <- function(code) {
  ifelse(code == 3L, "Injectables",
  ifelse(code == 11L, "Implants",
  ifelse(code == 1L, "Pill",
  ifelse(code == 16L, "Emergency contraception",
  ifelse(code %in% c(2L,5L,6L,7L,13L,17L,18L),
         "Other modern methods", NA_character_)))))
}

# Seven presentation categories preserve the distinctions requested in the
# project: pregnancy intention versus other fertility reasons, and wanting a
# more effective method versus access/cost/inconvenience.
reason_group <- function(code) {
  ifelse(code == 2L, "Wanted pregnancy",
  ifelse(code %in% c(11L,12L,13L), "Other fertility reasons",
  ifelse(code %in% c(5L,6L), "Bleeding / side effects / health",
  ifelse(code == 4L, "Wanted a more effective method",
  ifelse(code %in% c(7L,8L,9L), "Access / cost / inconvenience",
  ifelse(code == 1L, "Method failure", "Other reasons"))))))
}
reason_levels <- c(
  "Wanted pregnancy", "Other fertility reasons",
  "Bleeding / side effects / health", "Wanted a more effective method",
  "Access / cost / inconvenience", "Method failure", "Other reasons"
)

literal_destination <- function(character, code) {
  result <- rep("Other/unknown", length(character))
  result[character == "0"] <- "No method"
  result[character %in% c("P","B","T")] <- "Pregnancy/birth/termination"
  result[code %in% traditional_codes] <- "Traditional method"
  result[code %in% modern_codes] <- "Modern method"
  result
}
destination_levels <- c(
  "Modern method", "No method", "Pregnancy/birth/termination",
  "Traditional method", "Other/unknown"
)

reason_colors <- c(
  "Wanted pregnancy"="#D55E00", "Other fertility reasons"="#CC79A7",
  "Bleeding / side effects / health"="#E69F00",
  "Wanted a more effective method"="#0072B2",
  "Access / cost / inconvenience"="#56B4E9",
  "Method failure"="#009E73", "Other reasons"="#7A7A7A"
)
destination_colors <- c(
  "Modern method"="#0072B2", "No method"="#6F6F6F",
  "Pregnancy/birth/termination"="#D55E00",
  "Traditional method"="#B79F00", "Other/unknown"="#A7A7A7"
)

spread_labels <- function(y, minimum_gap=.06, lower=.06, upper=.90) {
  o <- order(y); z <- y[o]
  if (length(z) > 1L) {
    for (i in 2:length(z)) z[i] <- max(z[i], z[i-1L] + minimum_gap)
    if (tail(z,1) > upper) z <- z - (tail(z,1)-upper)
    for (i in (length(z)-1L):1L) if (i >= 1L) z[i] <- min(z[i],z[i+1L]-minimum_gap)
    if (z[1] < lower) z <- z + (lower-z[1])
  }
  ans <- numeric(length(y)); ans[o] <- z; ans
}

bezier_x <- function(t,x0,x1) (1-t)^3*x0 + 3*(1-t)^2*t*(x0+.20) +
  3*(1-t)*t^2*(x1-.20) + t^3*x1
bezier_y <- function(t,y0,y1) (1-t)^3*y0 + 3*(1-t)^2*t*y0 +
  3*(1-t)*t^2*y1 + t^3*y1

# 2. Injectable reason-to-destination alluvial -------------------------------
injectable <- transitions[transitions$origin == "Injectables",]
injectable$reason_group <- reason_group(injectable$reason_code)
injectable$next_month_destination <- literal_destination(injectable$next_char,
                                                          injectable$next_code)
stopifnot(nrow(injectable) == 3713L, !anyNA(injectable$reason_group))

reason_flow <- aggregate(wt ~ reason_group + next_month_destination, injectable, sum)
all_reason_cells <- expand.grid(reason_group=reason_levels,
                                next_month_destination=destination_levels,
                                stringsAsFactors=FALSE)
reason_flow <- merge(all_reason_cells, reason_flow,
                     by=c("reason_group","next_month_destination"), all.x=TRUE)
reason_flow$wt[is.na(reason_flow$wt)] <- 0
reason_flow$reason_group <- factor(reason_flow$reason_group, levels=reason_levels)
reason_flow$next_month_destination <- factor(reason_flow$next_month_destination,
                                             levels=destination_levels)
reason_flow <- reason_flow[order(reason_flow$reason_group,
                                 reason_flow$next_month_destination),]
reason_flow$reason_total <- ave(reason_flow$wt, reason_flow$reason_group, FUN=sum)
reason_flow$within_reason_pct <- 100*reason_flow$wt/reason_flow$reason_total
reason_flow$overall_pct <- 100*reason_flow$wt/sum(reason_flow$wt)
write.csv(reason_flow, file.path(output_dir,"injectable_reason_destination_flows.csv"),
          row.names=FALSE)

draw_two_stage_alluvial <- function(filename, flows) {
  M <- xtabs(wt ~ reason_group + next_month_destination, flows)
  left_names <- reason_levels[rowSums(M)>0]
  right_names <- destination_levels[colSums(M)>0]
  total <- sum(M); left_total <- rowSums(M)[left_names]; right_total <- colSums(M)[right_names]
  left_gap <- .022; right_gap <- .030
  left_scale <- (.76-left_gap*(length(left_names)-1))/total
  right_scale <- (.76-right_gap*(length(right_names)-1))/total
  nodes <- function(names, totals, scale, gap) {
    out <- data.frame(name=names,bottom=NA_real_,top=NA_real_); y <- .88
    for (i in seq_along(names)) {
      h <- totals[names[i]]*scale; out$top[i] <- y; out$bottom[i] <- y-h; y <- y-h-gap
    }
    out
  }
  L <- nodes(left_names,left_total,left_scale,left_gap)
  R <- nodes(right_names,right_total,right_scale,right_gap)
  lc <- setNames(L$top,L$name); rc <- setNames(R$top,R$name)
  png(filename,width=3000,height=1700,res=200,type="quartz")
  par(mar=c(6,4,6,4),xpd=NA,family="sans")
  plot.new(); plot.window(xlim=c(-.15,1.18),ylim=c(-.12,1))
  x0 <- .20; x1 <- .78
  for (d in right_names) for (s in left_names) {
    w <- M[s,d]; if (w<=0) next
    st <- lc[s]; sb <- st-w*left_scale; dt <- rc[d]; db <- dt-w*right_scale
    tt <- seq(0,1,length.out=100); xx <- bezier_x(tt,x0,x1)
    polygon(c(xx,rev(xx)),c(bezier_y(tt,st,dt),rev(bezier_y(tt,sb,db))),
            col=adjustcolor(destination_colors[d],alpha.f=.48),border=NA)
    lc[s] <- sb; rc[d] <- db
  }
  rect(.16,L$bottom,.20,L$top,col=unname(reason_colors[L$name]),border=NA)
  rect(.78,R$bottom,.82,R$top,col=unname(destination_colors[R$name]),border=NA)
  ly <- spread_labels(rowMeans(L[,c("bottom","top")]),.063,.05,.90)
  ry <- spread_labels(rowMeans(R[,c("bottom","top")]),.072,.05,.90)
  segments(.16,rowMeans(L[,c("bottom","top")]),.145,ly,col="#A2ADB2")
  segments(.82,rowMeans(R[,c("bottom","top")]),.835,ry,col="#A2ADB2")
  text(.138,ly,paste0(L$name," (",sprintf("%.1f%%",100*left_total[L$name]/total),")"),
       adj=1,cex=.72,font=2,col="#111111")
  text(.842,ry,paste0(R$name," (",sprintf("%.1f%%",100*right_total[R$name]/total),")"),
       adj=0,cex=.75,font=2,col="#111111")
  text(.16,.94,"STATED REASON\nshare of injectable discontinuations",adj=0,
       cex=.72,font=2,col="#5B6C74")
  text(.78,.94,"STATE ONE MONTH LATER\nshare of injectable discontinuations",adj=0,
       cex=.72,font=2,col="#5B6C74")
  title(main="Why injectable episodes end—and what follows next",
        sub=paste0("Weighted flows among ",format(round(total),big.mark=","),
                   " recorded injectable discontinuations"),
        adj=.04,cex.main=1.45,col.main="#174866",cex.sub=.90,col.sub="#5B6C74")
  mtext("The denominator contains discontinued injectable episodes; this figure does not estimate the probability that an injectable user will discontinue.",
        side=1,line=1.6,adj=.04,cex=.76,col="#5B6C74")
  legend("bottom",inset=c(0,-.035),xpd=NA,ncol=4,bty="n",cex=.66,
         title="Ribbon color: state one month later",
         fill=unname(destination_colors[right_names]),legend=right_names)
  dev.off()
}
draw_two_stage_alluvial(file.path(asset_dir,"injectable_reason_destination_alluvial.png"),
                        reason_flow)

# 3. Heat map: reason, observed duration, and next-month destination ---------
# Count consecutive months of the same method moving backward from the month
# carrying the discontinuation reason. This is observed completed duration at
# the event, not a life-table rate.
episode_duration <- integer(nrow(injectable))
for (j in seq_len(nrow(injectable))) {
  i <- injectable$woman_row[j]; p <- injectable$calendar_position[j]
  origin_char <- substring(ir$vcal_1[i],p,p); d <- 1L
  while (p+d <= nchar(ir$vcal_1[i]) && substring(ir$vcal_1[i],p+d,p+d)==origin_char) d <- d+1L
  episode_duration[j] <- d
}
injectable$observed_duration <- episode_duration
injectable$timing_group <- ifelse(episode_duration<=3,"Ended by month 3",
                           ifelse(episode_duration<=12,"Ended in months 4–12","Ended after month 12"))

heat_rows <- list(); h <- 0L
for (reason in reason_levels) {
  z <- injectable[injectable$reason_group==reason,]
  denom <- sum(z$wt)
  measures <- c(
    "Ended by month 3"=sum(z$wt[z$timing_group=="Ended by month 3"])/denom,
    "Ended in months 4–12"=sum(z$wt[z$timing_group=="Ended in months 4–12"])/denom,
    "Ended after month 12"=sum(z$wt[z$timing_group=="Ended after month 12"])/denom,
    "Modern method next month"=sum(z$wt[z$next_month_destination=="Modern method"])/denom,
    "No method next month"=sum(z$wt[z$next_month_destination=="No method"])/denom,
    "Pregnancy-related next month"=sum(z$wt[z$next_month_destination=="Pregnancy/birth/termination"])/denom
  )
  h <- h+1L
  heat_rows[[h]] <- data.frame(reason=reason,measure=names(measures),percent=100*unname(measures))
}
heat <- do.call(rbind,heat_rows)
heat$reason <- factor(heat$reason,levels=rev(reason_levels))
heat$measure <- factor(heat$measure,levels=c(
  "Ended by month 3","Ended in months 4–12","Ended after month 12",
  "Modern method next month","No method next month","Pregnancy-related next month"))
write.csv(heat,file.path(output_dir,"injectable_reason_timing_destination_heatmap.csv"),row.names=FALSE)

heat_plot <- ggplot(heat,aes(x=measure,y=reason,fill=percent))+
  geom_tile(colour="white",linewidth=1.1)+
  geom_text(aes(label=sprintf("%.1f%%",percent)),fontface="bold",size=4.0,
            colour=ifelse(heat$percent>=48,"white","#172B3A"))+
  scale_fill_gradientn(colours=c("#EEF4F5","#9BC9C8","#168C89","#174866"),
                       limits=c(0,max(heat$percent)),name="Percent")+
  scale_x_discrete(labels=c("Ended by\nmonth 3","Ended in\nmonths 4–12",
                            "Ended after\nmonth 12","Modern method\nnext month",
                            "No method\nnext month","Pregnancy-related\nnext month"))+
  labs(title="Injectable discontinuation: timing and immediate destination by reason",
       subtitle="Each cell is a weighted percentage within the stated reason; timing columns and destination columns form separate distributions",
       x=NULL,y=NULL,caption="Observed completed duration among recorded discontinuations; not a life-table discontinuation probability.")+
  theme_minimal(base_size=13)+
  theme(plot.title=element_text(face="bold",colour="#174866",size=18),
        plot.subtitle=element_text(colour="#5B6C74",size=11),
        plot.caption=element_text(colour="#5B6C74",hjust=0),
        axis.text.x=element_text(colour="#172B3A",face="bold",size=10),
        axis.text.y=element_text(colour="#172B3A",size=11),
        panel.grid=element_blank(),legend.position="bottom",
        plot.margin=margin(16,18,16,18))
ggsave(file.path(asset_dir,"injectable_reason_timing_destination_heatmap.png"),heat_plot,
       width=13,height=7.3,dpi=220,bg="white")

# 4. Program-action evidence table ------------------------------------------
reason_dist <- aggregate(wt ~ reason_group,injectable,sum)
reason_dist$share <- 100*reason_dist$wt/sum(reason_dist$wt)
reason_share <- setNames(reason_dist$share,reason_dist$reason_group)
no_method_by_reason <- 100*with(injectable,
  tapply(wt*(next_month_destination=="No method"),reason_group,sum)/tapply(wt,reason_group,sum))
modern_by_reason <- 100*with(injectable,
  tapply(wt*(next_month_destination=="Modern method"),reason_group,sum)/tapply(wt,reason_group,sum))

action_table <- data.frame(
  Evidence=c(
    "Injectable discontinuation is already visible early",
    "Bleeding, side effects, or health concerns",
    "Wanted a more effective method",
    "Access, cost, or inconvenience",
    "Pregnancy intention",
    "No method immediately after an episode ends"
  ),
  Ethiopia_finding=c(
    "16.2% cumulative episode discontinuation by month 3; 44.5% by month 12",
    sprintf("%.1f%% of injectable discontinuations; %.1f%% had no method next month",
            reason_share["Bleeding / side effects / health"],
            no_method_by_reason["Bleeding / side effects / health"]),
    sprintf("%.1f%% of injectable discontinuations; %.1f%% used a modern method next month",
            reason_share["Wanted a more effective method"],
            modern_by_reason["Wanted a more effective method"]),
    sprintf("%.1f%% of injectable discontinuations; %.1f%% had no method next month",
            reason_share["Access / cost / inconvenience"],
            no_method_by_reason["Access / cost / inconvenience"]),
    sprintf("%.1f%% of injectable discontinuations",reason_share["Wanted pregnancy"]),
    "75.5% of matched modern-method discontinuations had no method recorded one month later"
  ),
  Program_response=c(
    "Prioritize follow-up, counseling, and resupply during the first three months",
    "Provide anticipatory counseling, side-effect management, and immediate alternatives",
    "Make same-visit switching easy and preserve uninterrupted modern use",
    "Strengthen commodity availability, reminders, outreach, and convenient reinjection",
    "Distinguish intended fertility exits and connect women to preconception or later postpartum support",
    "Prevent avoidable gaps through rapid switching; use re-entry outreach when a gap occurs"
  ), check.names=FALSE
)
write.csv(action_table,file.path(output_dir,"program_action_evidence_table.csv"),row.names=FALSE)

# 5. Woman-level historical current-user pathway ----------------------------
# Use a fixed baseline 15 months before interview. The next 12 calendar months
# are positions baseline-1 through baseline-12 and end at month 3 before interview.
baseline_position <- v018+15L
baseline_char <- mapply(function(cal,p)substring(cal,p,p),ir$vcal_1,baseline_position,
                        USE.NAMES=FALSE)
baseline_code <- match(baseline_char,method_characters)
keep <- baseline_code %in% modern_codes
rows <- which(keep)

pathway <- data.frame(
  woman_row=rows,caseid=ir$caseid[rows],wt=as.numeric(unclass(ir$v005[rows]))/1e6,
  v021=as.numeric(unclass(ir$v021[rows])),v022=as.numeric(unclass(ir$v022[rows])),
  baseline_code=baseline_code[rows],baseline_method=method_group(baseline_code[rows]),
  month3_status=NA_character_,month12_status=NA_character_,
  first_exit_month=NA_integer_,stringsAsFactors=FALSE
)

for (j in seq_len(nrow(pathway))) {
  i <- pathway$woman_row[j]; p0 <- baseline_position[i]; bcode <- pathway$baseline_code[j]
  chars <- vapply(1:12,function(m)substring(ir$vcal_1[i],p0-m,p0-m),character(1))
  codes <- match(chars,method_characters)
  modern <- !is.na(codes)&codes%in%modern_codes
  bridge <- rep(FALSE,12)
  for (m in 1:11) if (chars[m]=="0") {
    reason_char <- substring(sprintf("%-80s",ir$vcal_2[i]),p0-(m-1L),p0-(m-1L))
    bridge[m] <- reason_char=="7" && !is.na(codes[m+1L]) && codes[m+1L]%in%modern_codes &&
      codes[m+1L]!=if (m==1L) bcode else ifelse(!is.na(codes[m-1L]),codes[m-1L],bcode)
  }
  effective_modern <- modern|bridge
  exit_months <- which(!effective_modern)
  pathway$first_exit_month[j] <- if(length(exit_months))min(exit_months) else 13L

  status_at <- function(t) {
    exited <- any(!effective_modern[1:t])
    changed <- any(codes[1:t][modern[1:t]]!=bcode)|any(bridge[1:t])
    if (!exited) {
      if (changed) "Continuous modern use after switch" else "Continuous baseline method"
    } else if (effective_modern[t]) {
      "Re-entered modern use after exit"
    } else if (chars[t]%in%c("P","B","T")) {
      "Pregnancy/birth/termination"
    } else {
      "Outside modern use"
    }
  }
  pathway$month3_status[j] <- status_at(3L)
  pathway$month12_status[j] <- status_at(12L)
}

path3_levels <- c("Continuous baseline method","Continuous modern use after switch",
                  "Re-entered modern use after exit","Outside modern use",
                  "Pregnancy/birth/termination")
path12_levels <- path3_levels
pathway$baseline_method <- factor(pathway$baseline_method,
  levels=c("Injectables","Implants","Pill","Other modern methods","Emergency contraception"))
pathway$month3_status <- factor(pathway$month3_status,levels=path3_levels)
pathway$month12_status <- factor(pathway$month12_status,levels=path12_levels)
saveRDS(pathway,file.path(derived_dir,"ethiopia_2024_current_user_pathway.rds"))

path_flows <- aggregate(wt ~ baseline_method+month3_status+month12_status,pathway,sum)
path_flows$overall_pct <- 100*path_flows$wt/sum(path_flows$wt)
write.csv(path_flows,file.path(output_dir,"current_user_pathway_flows.csv"),row.names=FALSE)

checkpoint_summary <- rbind(
  transform(aggregate(wt~month3_status,pathway,sum),checkpoint="Month 3",
            state=as.character(month3_status))[,c("checkpoint","state","wt")],
  transform(aggregate(wt~month12_status,pathway,sum),checkpoint="Month 12",
            state=as.character(month12_status))[,c("checkpoint","state","wt")]
)
checkpoint_summary$pct <- 100*checkpoint_summary$wt/ave(checkpoint_summary$wt,
                                                         checkpoint_summary$checkpoint,FUN=sum)
write.csv(checkpoint_summary,file.path(output_dir,"current_user_pathway_checkpoints.csv"),
          row.names=FALSE)

path_colors <- c(
  "Injectables"="#188F8C","Implants"="#174866","Pill"="#DDA02D",
  "Other modern methods"="#56B4E9","Emergency contraception"="#CC79A7",
  "Continuous baseline method"="#009E73",
  "Continuous modern use after switch"="#0072B2",
  "Re-entered modern use after exit"="#56B4E9",
  "Outside modern use"="#6F6F6F","Pregnancy/birth/termination"="#D55E00"
)

make_nodes <- function(names,totals,gap=.025,top=.88,bottom=.10) {
  scale <- (top-bottom-gap*(length(names)-1L))/sum(totals[names])
  out <- data.frame(name=names,bottom=NA_real_,top=NA_real_); y <- top
  for(i in seq_along(names)) {
    h <- totals[names[i]]*scale; out$top[i]<-y; out$bottom[i]<-y-h; y<-y-h-gap
  }
  list(nodes=out,scale=scale)
}

draw_current_user_pathway <- function(filename) {
  total <- sum(pathway$wt)
  Lnames <- levels(pathway$baseline_method)[levels(pathway$baseline_method)%in%as.character(pathway$baseline_method)]
  Mnames <- path3_levels[path3_levels%in%as.character(pathway$month3_status)]
  Rnames <- path12_levels[path12_levels%in%as.character(pathway$month12_status)]
  Ltot <- tapply(pathway$wt,pathway$baseline_method,sum); Mtot <- tapply(pathway$wt,pathway$month3_status,sum)
  Rtot <- tapply(pathway$wt,pathway$month12_status,sum)
  L <- make_nodes(Lnames,Ltot,.025)$nodes; ls <- make_nodes(Lnames,Ltot,.025)$scale
  Mobj <- make_nodes(Mnames,Mtot,.025); M <- Mobj$nodes; ms <- Mobj$scale
  Robj <- make_nodes(Rnames,Rtot,.025); R <- Robj$nodes; rs <- Robj$scale

  LM <- xtabs(wt~baseline_method+month3_status,pathway)
  MR <- xtabs(wt~month3_status+month12_status,pathway)
  lc<-setNames(L$top,L$name); ml<-setNames(M$top,M$name)
  mr<-setNames(M$top,M$name); rc<-setNames(R$top,R$name)
  png(filename,width=3200,height=1800,res=200,type="quartz")
  par(mar=c(5,4,6,4),xpd=NA,family="sans")
  plot.new();plot.window(xlim=c(-.08,1.10),ylim=c(-.08,1))
  draw_link <- function(x0,x1,st,sb,dt,db,col) {
    tt<-seq(0,1,length.out=100);xx<-bezier_x(tt,x0,x1)
    polygon(c(xx,rev(xx)),c(bezier_y(tt,st,dt),rev(bezier_y(tt,sb,db))),
            col=adjustcolor(col,alpha.f=.42),border=NA)
  }
  for(m in Mnames)for(l in Lnames){w<-LM[l,m];if(w<=0)next
    st<-lc[l];sb<-st-w*ls;dt<-ml[m];db<-dt-w*ms
    draw_link(.12,.48,st,sb,dt,db,path_colors[m]);lc[l]<-sb;ml[m]<-db}
  for(r in Rnames)for(m in Mnames){w<-MR[m,r];if(w<=0)next
    st<-mr[m];sb<-st-w*ms;dt<-rc[r];db<-dt-w*rs
    draw_link(.52,.88,st,sb,dt,db,path_colors[r]);mr[m]<-sb;rc[r]<-db}
  rect(.09,L$bottom,.12,L$top,col=unname(path_colors[L$name]),border=NA)
  rect(.48,M$bottom,.52,M$top,col=unname(path_colors[M$name]),border=NA)
  rect(.88,R$bottom,.92,R$top,col=unname(path_colors[R$name]),border=NA)
  label_nodes <- function(nodes,totals,x,adj,segment_from,segment_to,min_gap=.055) {
    centers<-rowMeans(nodes[,c("bottom","top")]);yy<-spread_labels(centers,min_gap,.06,.90)
    segments(segment_from,centers,segment_to,yy,col="#A2ADB2")
    text(x,yy,paste0(nodes$name," (",sprintf("%.1f%%",100*totals[nodes$name]/total),")"),
         adj=adj,cex=.64,font=2,col="#111111")
  }
  label_nodes(L,Ltot,.075,1,.09,.078,.052)
  label_nodes(M,Mtot,.54,0,.52,.535,.061)
  label_nodes(R,Rtot,.94,0,.92,.935,.061)
  text(.09,.94,"BASELINE METHOD\n15 months before interview",adj=0,cex=.70,font=2,col="#5B6C74")
  text(.48,.94,"PATHWAY BY MONTH 3",adj=0,cex=.70,font=2,col="#5B6C74")
  text(.88,.94,"PATHWAY / STATE AT MONTH 12",adj=0,cex=.70,font=2,col="#5B6C74")
  title(main="What happens to historical current modern-method users over 12 months?",
        sub=paste0("One landmark per woman; ",format(nrow(pathway),big.mark=","),
                   " women (",format(round(total),big.mark=",")," weighted)"),
        adj=.04,cex.main=1.35,col.main="#174866",cex.sub=.88,col.sub="#5B6C74")
  mtext("Uninterrupted modern-to-modern switches remain in modern use. Re-entry follows a gross exit. This historical pathway is a prototype for current-stock forecasting.",
        side=1,line=1.2,adj=.04,cex=.73,col="#5B6C74")
  dev.off()
}
draw_current_user_pathway(file.path(asset_dir,"current_user_pathway_3_12_alluvial.png"))

# 6. Consolidated HTML section ----------------------------------------------
escape_html <- function(x) {
  x <- gsub("&","&amp;",x,fixed=TRUE); x <- gsub("<","&lt;",x,fixed=TRUE)
  x <- gsub(">","&gt;",x,fixed=TRUE); x
}
action_rows <- paste0("<tr><th scope=\"row\">",escape_html(action_table$Evidence),
  "</th><td>",escape_html(action_table$Ethiopia_finding),"</td><td>",
  escape_html(action_table$Program_response),"</td></tr>",collapse="")
current3 <- checkpoint_summary[checkpoint_summary$checkpoint=="Month 3",]
current12 <- checkpoint_summary[checkpoint_summary$checkpoint=="Month 12",]

section_html <- paste0(
  '<!-- BEGIN ACTION PATHWAYS -->',
  '<section id="action-pathways"><h2>From episode evidence to program action</h2>',
  '<p>This section combines the timing, stated reason, and post-discontinuation destination analyses. The first two figures remain conditional on an episode having discontinued; the historical current-user pathway uses women as the denominator.</p>',
  '<h3>What programs can do</h3><div class="table-wrap analysis-table" role="region" aria-label="Program action evidence table" tabindex="0"><table><thead><tr><th scope="col">Observed signal</th><th scope="col">Ethiopia 2024–25 finding</th><th scope="col">Potential program response</th></tr></thead><tbody>',action_rows,'</tbody></table></div>',
  '<p class="note">Program responses are hypotheses motivated by the combined evidence; the descriptive calendar analysis does not establish that a specific service failure caused an individual discontinuation.</p>',
  '<h3>Injectables: stated reason and state one month later</h3><div class="figure-grid"><figure><img src="assets/injectable_reason_destination_alluvial.png" alt="Alluvial diagram linking stated reason for injectable discontinuation to the state one month later"><figcaption>Ribbon widths are weighted shares of recorded injectable discontinuations. A modern method next month represents immediate retention; no method identifies an immediate gap. Pregnancy intention remains analytically separate from program-remediable barriers.</figcaption></figure></div>',
  '<h3>Injectables: timing and immediate destination heat map</h3><div class="figure-grid"><figure><img src="assets/injectable_reason_timing_destination_heatmap.png" alt="Heat map of injectable discontinuation timing and next-month destination by reason"><figcaption>The first three columns describe observed episode duration among discontinuations in each reason group. The final three columns describe the next calendar state. Each set should be read separately.</figcaption></figure></div>',
  '<div class="callout"><strong>Interpretation boundary:</strong> duration cells summarize completed discontinued episodes and are not life-table risks. Use the validated life table to report the probability that an episode ends by month 3 or month 12.</div>',
  '<h3>Historical current-user pathway: baseline to months 3 and 12</h3><div class="figure-grid"><figure><img src="assets/current_user_pathway_3_12_alluvial.png" alt="Woman-level alluvial pathway from historical baseline modern-method use to month 3 and month 12"><figcaption>Women using a specified modern method 15 months before interview are followed through month 3 before interview. Direct switches remain in continuous modern use; gross exits that later resume are shown as re-entry.</figcaption></figure></div>',
  '<div class="interpretation"><h3>What this pathway adds</h3><p>Unlike the episode alluvial, this denominator includes continuing users. It therefore estimates the weighted distribution of continuation, uninterrupted switching, gross modern-use exits, re-entry, and endpoint absence among baseline current users. It is a historical landmark prototype; method- and duration-standardized probabilities are the next modeling step before applying results to the interview-date current-user stock.</p><p><strong>Baseline:</strong> one historical landmark per woman at month 15 before interview. <strong>Follow-up:</strong> the subsequent 12 months, ending at month 3 before interview. <strong>Successful switching:</strong> uninterrupted modern-to-modern use, plus the DHS one-month-gap convention when the stated reason is wanting a more effective method and a different modern method follows.</p></div>',
  '<div class="downloads"><a href="program_action_evidence_table.csv">Download program-action table</a><a href="injectable_reason_destination_flows.csv">Download injectable reason flows</a><a href="injectable_reason_timing_destination_heatmap.csv">Download heat-map data</a><a href="current_user_pathway_flows.csv">Download current-user pathway flows</a><a href="current_user_pathway_checkpoints.csv">Download pathway checkpoint estimates</a><a href="../Code/06_actionable_pathways.R">Open documented pathway R code</a></div>',
  '</section><!-- END ACTION PATHWAYS -->'
)

if (identical(Sys.getenv('RENDER_LEGACY_HTML','false'),'true')) {
html_path <- file.path(output_dir,"Ethiopia_discontinuation_analysis.html")
html <- paste(readLines(html_path,warn=FALSE),collapse="\n")
html <- sub('<!-- BEGIN ACTION PATHWAYS -->.*<!-- END ACTION PATHWAYS -->','',html)
html <- sub('<section id="methods">',paste0(section_html,'\n<section id="methods">'),html,fixed=TRUE)
if (!grepl('href="#action-pathways"',html,fixed=TRUE)) {
  html <- sub('<a href="#transitions">Post-discontinuation transitions</a>',
    '<a href="#transitions">Post-discontinuation transitions</a><a href="#action-pathways">Actionable pathways</a>',
    html,fixed=TRUE)
}
writeLines(html,html_path,useBytes=TRUE)
}


# 7. Audit -------------------------------------------------------------------
jsonlite::write_json(list(
  episode_reason_alluvial=list(method="Injectables",unweighted=nrow(injectable),
    weighted=sum(injectable$wt),denominator="recorded discontinued injectable episodes"),
  current_user_pathway=list(baseline="15 months before interview",
    follow_up="months 14 through 3 before interview",unweighted=nrow(pathway),
    weighted=sum(pathway$wt),month3=checkpoint_summary[checkpoint_summary$checkpoint=="Month 3",],
    month12=checkpoint_summary[checkpoint_summary$checkpoint=="Month 12",]),
  generated=format(Sys.time(),"%Y-%m-%d %H:%M:%S %Z")
),file.path(output_dir,"actionable_pathways_audit.json"),pretty=TRUE,digits=12)

cat("Actionable pathway analysis complete.\n")
print(checkpoint_summary,row.names=FALSE)
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 07_standardized_current_user_pathway.R
# LANGUAGE: R
MODULES[["07_standardized_current_user_pathway.R"]] <- list(
 language="R",
 packaged_sha256="50fcee76758b1a2b0a14ce0b4e0cb831d90efb3acc746b23e42c740db25364ef",
 args=character(),
 code=r"-----(#!/usr/bin/env Rscript
# =============================================================================
# Ethiopia DHS 2024-25: standardized current-user stock-to-outcome pathway
# =============================================================================
# Estimand
#   Among women using a modern method at the survey interview, what proportion
#   is expected to experience a gross modern-use exit during the next 12 months,
#   re-enter modern use by month 12, or remain absent at month 12?
#
# Method
#   1. Measure the weighted method-duration distribution of interview-date
#      current modern-method users using v312 and v337.
#   2. From the fixed historical landmark cohort constructed in script 06,
#      estimate 12-month pathway probabilities within method-duration strata.
#   3. Standardize the historical stratum-specific probabilities to the
#      interview-date current-user method-duration distribution.
#
# This produces population proportions per 100 current users. National counts
# require multiplying the probabilities by WRA x mCPR.
# =============================================================================

options(stringsAsFactors=FALSE)
required_packages <- c("jsonlite")
missing_packages <- setdiff(required_packages,rownames(installed.packages()))
if(length(missing_packages))install.packages(missing_packages,repos="https://cloud.r-project.org")
invisible(lapply(required_packages,library,character.only=TRUE))

project <- Sys.getenv("ETHIOPIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
output_dir <- file.path(project,"output")
asset_dir <- file.path(output_dir,"assets")
derived_dir <- file.path(project,"Data","Derived")
ir <- readRDS(file.path(project,"Data","ET2024DHS__ETIR8ADT__IR_raw.rds"))
historical <- readRDS(file.path(derived_dir,"ethiopia_2024_current_user_pathway.rds"))
v018 <- as.numeric(unclass(ir$v018))

# 1. Common analysis categories ---------------------------------------------
model_method <- function(code) {
  ifelse(code==3L,"Injectables",
  ifelse(code==11L,"Implants",
  ifelse(code==1L,"Pill",
  ifelse(code%in%c(2L,5L,6L,7L,13L,16L,17L,18L),
         "Other modern methods including EC",NA_character_))))
}
method_levels <- c("Injectables","Implants","Pill",
                   "Other modern methods including EC")
duration_levels <- c("0–3 months","4–6 months","7–12 months",
                     "13–24 months","25+ months")
duration_group <- function(x) {
  factor(ifelse(x<=3,"0–3 months",
         ifelse(x<=6,"4–6 months",
         ifelse(x<=12,"7–12 months",
         ifelse(x<=24,"13–24 months","25+ months")))),levels=duration_levels)
}

# 2. Interview-date current-user method-duration distribution ----------------
current <- data.frame(
  woman_row=seq_len(nrow(ir)),
  method_code=as.numeric(unclass(ir$v312)),
  duration=as.numeric(unclass(ir$v337)),
  wt=as.numeric(unclass(ir$v005))/1e6,
  v021=as.numeric(unclass(ir$v021)),v022=as.numeric(unclass(ir$v022))
)
current$method <- model_method(current$method_code)
current <- current[!is.na(current$method)&!is.na(current$duration)&current$duration<997,]
current$duration_group <- duration_group(current$duration)
current$method <- factor(current$method,levels=method_levels)
stopifnot(nrow(current)==4154L,!anyNA(current$duration_group))

current_cells <- aggregate(wt~method+duration_group,current,sum)
current_n <- aggregate(woman_row~method+duration_group,current,length)
names(current_n)[3] <- "unweighted_current_users"
current_cells <- merge(current_cells,current_n,by=c("method","duration_group"))
current_cells$current_share <- current_cells$wt/sum(current_cells$wt)
write.csv(current_cells,file.path(output_dir,"current_user_method_duration_distribution.csv"),
          row.names=FALSE)

# 3. Historical method-duration outcome probabilities -----------------------
# Completed duration at the historical landmark is counted backward through
# consecutive months of the same method. At position v018+15 there are at least
# 52 older observed months, so any calendar-left-censored episode necessarily
# belongs to the 25+ group.
historical$baseline_duration <- NA_integer_
for(j in seq_len(nrow(historical))){
  i <- historical$woman_row[j]; p <- v018[i]+15L
  ch <- substring(ir$vcal_1[i],p,p); d <- 1L
  while(p+d<=80L && substring(ir$vcal_1[i],p+d,p+d)==ch)d <- d+1L
  historical$baseline_duration[j] <- d
}
historical$method <- factor(model_method(historical$baseline_code),levels=method_levels)
historical$duration_group <- duration_group(historical$baseline_duration)
historical$outcome <- as.character(historical$month12_status)
historical$outcome[historical$outcome=="Continuous baseline method"] <- "No gross exit: baseline method"
historical$outcome[historical$outcome=="Continuous modern use after switch"] <- "No gross exit: modern switch"
historical$outcome[historical$outcome=="Re-entered modern use after exit"] <- "Gross exit: re-entered by month 12"
historical$outcome[historical$outcome%in%c("Outside modern use","Pregnancy/birth/termination")] <- "Gross exit: net absent at month 12"
outcome_levels <- c("No gross exit: baseline method","No gross exit: modern switch",
                    "Gross exit: re-entered by month 12",
                    "Gross exit: net absent at month 12")
historical$outcome <- factor(historical$outcome,levels=outcome_levels)
stopifnot(!anyNA(historical$outcome),!anyNA(historical$duration_group),!anyNA(historical$method))

# Complete method-duration-outcome grid and weighted conditional proportions.
hagg <- aggregate(wt~method+duration_group+outcome,historical,sum)
hgrid <- expand.grid(method=method_levels,duration_group=duration_levels,
                     outcome=outcome_levels,stringsAsFactors=FALSE)
hagg <- merge(hgrid,hagg,by=c("method","duration_group","outcome"),all.x=TRUE)
hagg$wt[is.na(hagg$wt)] <- 0
hden <- aggregate(wt~method+duration_group,hagg,sum)
names(hden)[3] <- "historical_cell_weight"
hagg <- merge(hagg,hden,by=c("method","duration_group"))
hagg$conditional_probability <- hagg$wt/hagg$historical_cell_weight

hn <- aggregate(woman_row~method+duration_group,historical,length)
names(hn)[3] <- "historical_unweighted_users"
hagg <- merge(hagg,hn,by=c("method","duration_group"))
stopifnot(all(hagg$historical_unweighted_users>=18L),
          all(abs(aggregate(conditional_probability~method+duration_group,hagg,sum)$conditional_probability-1)<1e-10))
write.csv(hagg,file.path(output_dir,"historical_method_duration_pathway_probabilities.csv"),
          row.names=FALSE)

# 4. Direct standardization ---------------------------------------------------
standardized <- merge(current_cells[,c("method","duration_group","current_share")],
                      hagg[,c("method","duration_group","outcome","conditional_probability")],
                      by=c("method","duration_group"))
standardized$contribution <- standardized$current_share*standardized$conditional_probability
standardized_outcomes <- aggregate(contribution~outcome,standardized,sum)
standardized_outcomes$pct <- 100*standardized_outcomes$contribution
standardized_outcomes <- standardized_outcomes[match(outcome_levels,standardized_outcomes$outcome),]
stopifnot(abs(sum(standardized_outcomes$pct)-100)<1e-8)

same_pct <- standardized_outcomes$pct[1]
switch_pct <- standardized_outcomes$pct[2]
reentry_pct <- standardized_outcomes$pct[3]
net_absent_pct <- standardized_outcomes$pct[4]
no_exit_pct <- same_pct+switch_pct
gross_exit_pct <- reentry_pct+net_absent_pct

standardized_summary <- data.frame(
  stage=c("Current users","No gross exit","Gross modern-use exit",
          "Continuous baseline method","Continuous modern use after switch",
          "Re-entered modern use by month 12","Net absent from modern use at month 12"),
  pct=c(100,no_exit_pct,gross_exit_pct,same_pct,switch_pct,reentry_pct,net_absent_pct)
)
write.csv(standardized_summary,file.path(output_dir,"standardized_current_user_pathway_summary.csv"),
          row.names=FALSE)
write.csv(standardized,file.path(output_dir,"standardized_current_user_pathway_contributions.csv"),
          row.names=FALSE)

# 5. Principal alluvial: 100 current users -> gross exit -> endpoint ----------
colors <- c(
  "Current modern-method users"="#174866",
  "No gross exit"="#009E73","Gross modern-use exit"="#D55E00",
  "Continuous baseline method"="#009E73",
  "Continuous modern use after switch"="#0072B2",
  "Re-entered modern use by month 12"="#56B4E9",
  "Net absent from modern use at month 12"="#6F6F6F"
)
bezier_x <- function(t,x0,x1)(1-t)^3*x0+3*(1-t)^2*t*(x0+.17)+3*(1-t)*t^2*(x1-.17)+t^3*x1
bezier_y <- function(t,y0,y1)(1-t)^3*y0+3*(1-t)^2*t*y0+3*(1-t)*t^2*y1+t^3*y1
draw_link <- function(x0,x1,st,sb,dt,db,col){
  tt<-seq(0,1,length.out=120);xx<-bezier_x(tt,x0,x1)
  polygon(c(xx,rev(xx)),c(bezier_y(tt,st,dt),rev(bezier_y(tt,sb,db))),
          col=adjustcolor(col,alpha.f=.52),border=NA)
}

png(file.path(asset_dir,"standardized_current_user_stock_outcome_alluvial.png"),
    width=3000,height=1700,res=200,type="quartz")
par(mar=c(6,5,6,5),xpd=NA,family="sans")
plot.new();plot.window(xlim=c(-.05,1.12),ylim=c(-.08,1))

# Common scale means node heights are proportional to percentage points.
# Gaps are reserved explicitly so the small switch and re-entry nodes do not
# overlap at presentation size.
scale <- .0068; gap_mid <- .06; gap_right <- .020
L <- c(bottom=.13,top=.13+100*scale)
M <- data.frame(name=c("No gross exit","Gross modern-use exit"),bottom=NA,top=NA)
M$top[1]<-.84;M$bottom[1]<-.84-no_exit_pct*scale
M$bottom[2]<-.10;M$top[2]<-.10+gross_exit_pct*scale
R <- data.frame(name=c("Continuous baseline method","Continuous modern use after switch",
                       "Re-entered modern use by month 12","Net absent from modern use at month 12"),
                bottom=NA,top=NA)
R$top[1]<-.84;R$bottom[1]<-.84-same_pct*scale
R$top[2]<-R$bottom[1]-gap_right;R$bottom[2]<-R$top[2]-switch_pct*scale
R$top[3]<-R$bottom[2]-gap_right;R$bottom[3]<-R$top[3]-reentry_pct*scale
R$top[4]<-R$bottom[3]-gap_right;R$bottom[4]<-R$top[4]-net_absent_pct*scale

# Left-to-middle flows.
draw_link(.13,.48,L['top'],L['top']-no_exit_pct*scale,M$top[1],M$bottom[1],colors["No gross exit"])
draw_link(.13,.48,L['top']-no_exit_pct*scale,L['bottom'],M$top[2],M$bottom[2],colors["Gross modern-use exit"])
# Middle-to-right flows.
draw_link(.52,.86,M$top[1],M$top[1]-same_pct*scale,R$top[1],R$bottom[1],colors["Continuous baseline method"])
draw_link(.52,.86,M$bottom[1]+switch_pct*scale,M$bottom[1],R$top[2],R$bottom[2],colors["Continuous modern use after switch"])
draw_link(.52,.86,M$top[2],M$top[2]-reentry_pct*scale,R$top[3],R$bottom[3],colors["Re-entered modern use by month 12"])
draw_link(.52,.86,M$bottom[2]+net_absent_pct*scale,M$bottom[2],R$top[4],R$bottom[4],colors["Net absent from modern use at month 12"])

rect(.09,L['bottom'],.13,L['top'],col=colors["Current modern-method users"],border=NA)
rect(.48,M$bottom,.52,M$top,col=unname(colors[M$name]),border=NA)
rect(.86,R$bottom,.90,R$top,col=unname(colors[R$name]),border=NA)
text(.075,mean(L),"All interview-date current modern-method users (100%)",adj=1,cex=.78,font=2,col="#111111")
text(.535,rowMeans(M[,c("bottom","top")]),paste0(M$name," (",sprintf("%.1f%%",c(no_exit_pct,gross_exit_pct)),")"),adj=0,cex=.79,font=2,col="#111111")
text(.915,rowMeans(R[,c("bottom","top")]),paste0(R$name," (",sprintf("%.1f%%",c(same_pct,switch_pct,reentry_pct,net_absent_pct)),")"),adj=0,cex=.76,font=2,col="#111111")
text(.09,.94,"INTERVIEW-DATE STOCK",adj=0,cex=.72,font=2,col="#5B6C74")
text(.48,.94,"ANY GROSS EXIT DURING 12 MONTHS",adj=0,cex=.72,font=2,col="#5B6C74")
text(.86,.94,"PATHWAY / STATE AT MONTH 12",adj=0,cex=.72,font=2,col="#5B6C74")
title(main="Expected 12-month pathway among interview-date current modern-method users",
      sub="All 4,154 current users define the target stock; historical method-duration probabilities supply the forward outcomes",
      adj=.04,cex.main=1.45,col.main="#174866",cex.sub=.90,col.sub="#5B6C74")
mtext("Gross exit excludes uninterrupted modern-to-modern switching. Net absence includes no modern method and pregnancy-related states at month 12.",
      side=1,line=1.4,adj=.04,cex=.76,col="#5B6C74")
dev.off()

# 6. Add the standardized result to the consolidated HTML -------------------
if (identical(Sys.getenv('RENDER_LEGACY_HTML','false'),'true')) {
html_path <- file.path(output_dir,"Ethiopia_discontinuation_analysis.html")
html <- paste(readLines(html_path,warn=FALSE),collapse="\n")
block <- paste0(
  '<!-- BEGIN STANDARDIZED CURRENT USER -->',
  '<section id="standardized-current-users"><h2>Standardized current-user stock-to-outcome pathway</h2>',
  '<p>This is the principal current-user estimand. Historical 12-month pathway probabilities are estimated within method-duration strata and standardized to the weighted method-duration distribution of women using a modern method at the survey interview.</p>',
  '<div class="figure-grid"><figure><img src="assets/standardized_current_user_stock_outcome_alluvial.png" alt="Standardized alluvial from current modern-method users to gross exit and month-12 outcomes"><figcaption>Percentages are expected outcomes per 100 interview-date current modern-method users. Uninterrupted switching remains modern use. Re-entry follows a gross modern-use exit; net absence is the endpoint outcome most directly linked to the next-year mCPR numerator.</figcaption></figure></div>',
  '<div class="interpretation"><h3>How to interpret the standardized pathway</h3><p><strong>',sprintf('%.1f%%',gross_exit_pct),'</strong> are expected to experience at least one gross modern-use exit during the next 12 months. Of all current users, <strong>',sprintf('%.1f%%',reentry_pct),'</strong> are expected to re-enter modern use by month 12, while <strong>',sprintf('%.1f%%',net_absent_pct),'</strong> are expected to remain absent from modern use at the endpoint. The complementary <strong>',sprintf('%.1f%%',no_exit_pct),'</strong> are expected to remain continuously in modern use, including <strong>',sprintf('%.1f%%',switch_pct),'</strong> who switch methods without a qualifying exit.</p>',
  '<p><strong>Standardization:</strong> historical cells use four method groups and five baseline-duration groups (0–3, 4–6, 7–12, 13–24, and 25+ months). The current-stock weights come from <code>v312</code>, <code>v337</code>, and <code>v005</code>. The smallest historical cell is pill users at 4–6 months (18 women), so cell-specific uncertainty and a pooled-duration sensitivity analysis are required before final external reporting.</p></div>',
  '<div class="downloads"><a href="standardized_current_user_pathway_summary.csv">Download standardized pathway summary</a><a href="current_user_method_duration_distribution.csv">Download current method-duration distribution</a><a href="historical_method_duration_pathway_probabilities.csv">Download historical conditional probabilities</a><a href="standardized_current_user_pathway_contributions.csv">Download standardization contributions</a><a href="../Code/07_standardized_current_user_pathway.R">Open documented standardization code</a></div>',
  '</section><!-- END STANDARDIZED CURRENT USER -->'
)
html <- sub('<!-- BEGIN STANDARDIZED CURRENT USER -->.*<!-- END STANDARDIZED CURRENT USER -->','',html)
html <- sub('<section id="methods">',paste0(block,'\n<section id="methods">'),html,fixed=TRUE)
if(!grepl('href="#standardized-current-users"',html,fixed=TRUE)){
  html <- sub('<a href="#action-pathways">Actionable pathways</a>',
    '<a href="#action-pathways">Actionable pathways</a><a href="#standardized-current-users">Standardized current-user pathway</a>',html,fixed=TRUE)
}
writeLines(html,html_path,useBytes=TRUE)
}


# 7. Audit -------------------------------------------------------------------
jsonlite::write_json(list(
  estimand="Expected 12-month pathway among all interview-date current modern-method users, expressed as percentages",
  current_users=list(unweighted=nrow(current),weighted=sum(current$wt)),
  historical_landmarks=list(unweighted=nrow(historical),weighted=sum(historical$wt)),
  method_groups=method_levels,duration_groups=duration_levels,
  standardized_outcomes=standardized_summary,
  limitations=c("Weighted point estimates only; uncertainty intervals not yet calculated",
    "Smallest historical method-duration cell is pill users at 4–6 months (18 women)",
    "Historical conditional probabilities assume transportability to interview-date current users within method-duration strata",
    "Other modern methods combine low-volume methods and emergency contraception"),
  generated=format(Sys.time(),"%Y-%m-%d %H:%M:%S %Z")
),file.path(output_dir,"standardized_current_user_pathway_audit.json"),pretty=TRUE,digits=12)

cat("Standardized current-user pathway complete.\n")
print(standardized_summary,row.names=FALSE)
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 08_compare_wanted_pregnancy_and_switching.R
# LANGUAGE: R
MODULES[["08_compare_wanted_pregnancy_and_switching.R"]] <- list(
 language="R",
 packaged_sha256="ebb3a8105c3ae451409177126f68361d0b4e5a95e04f56dff2f43757da6a40e7",
 args=character(),
 code=r"-----(#!/usr/bin/env Rscript
# Ethiopia DHS 2024–25 IR calendar: mutually exclusive 12-month reason
# probabilities, plus the overlapping DHS switching indicator.
# Reuses the episode eligibility, weight, reason, and switching classification
# validated against the published DHS Table 7.11 in replicate_table_7_11.R.
project <- Sys.getenv("ETHIOPIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
e <- readRDS(file.path(project, 'Data/Derived/ethiopia_2024_table_7_11_episodes.rds'))
method_groups <- list(
  'Injectables'=3L, 'Implants'=11L, 'Pill'=1L, 'IUD'=2L,
  'Other modern methods'=c(5L,6L,7L,13L,17L,18L),
  'All modern methods'=c(1L,2L,3L,5L,6L,7L,11L,13L,17L,18L))
calculate <- function(d) {
  survival <- 1; causes <- numeric(9); switched <- 0; all <- 0
  for (month in 1:12) {
    at_risk <- d$entry < month & d$exposure >= month
    risk <- sum(d$wt[at_risk])
    if (risk <= 0) next
    ended <- at_risk & d$exposure == month & d$discontinued
    n_ended <- sum(d$wt[ended])
    for (reason in seq_along(causes))
      causes[reason] <- causes[reason] +
        survival * sum(d$wt[ended & d$reason == reason]) / risk
    switched <- switched + survival * sum(d$wt[ended & d$switched]) / risk
    all <- all + survival * n_ended / risk
    survival <- survival * (1 - n_ended/risk)
  }
  stopifnot(abs((all-sum(causes[c(1,2,3,8,9)]))-sum(causes[c(4,5,6,7)]))<1e-10)
  c(all_cause_pct=100*all,
    wanted_to_become_pregnant_pct=100*causes[2],
    partner_disapproved_pct=100*causes[8],
    method_failure_pct=100*causes[1],
    other_fertility_related_pct=100*causes[3],
    excluding_wanted_pregnancy_pct=100*(all-causes[2]),
    excluding_wanted_pregnancy_and_partner_pct=100*(all-causes[2]-causes[8]),
    excluding_pregnancy_fertility_and_partner_pct=
      100*(all-sum(causes[c(1,2,3,8)])),
    excluding_pregnancy_fertility_partner_and_other_pct=
      100*(all-sum(causes[c(1,2,3,8,9)])),
    switched_any_method_pct=100*switched,
    weighted_episodes=sum(d$wt), unweighted_episodes=nrow(d))
}
results <- do.call(rbind, lapply(method_groups, function(codes)
  calculate(e[e$method_code %in% codes,])))
# Published DHS rows match Table 7.11; IUD, Other modern, and pooled all-modern
# are our regroupings and do not have identical rows in that table.
reference <- jsonlite::read_json(file.path(project,'output/Supporting_data/Table_7_11/table_7_11_results.json'),simplifyVector=TRUE)
for (m in c('Injectables','Implants','Pill')) {
  row <- match(m,reference$methods)
  stopifnot(round(results[m,'all_cause_pct'],1)==reference$reference[row,10],
            round(results[m,'wanted_to_become_pregnant_pct'],1)==reference$reference[row,2],
            round(results[m,'partner_disapproved_pct'],1)==reference$reference[row,8],
            round(results[m,'method_failure_pct'],1)==reference$reference[row,1],
            round(results[m,'other_fertility_related_pct'],1)==reference$reference[row,3],
            round(results[m,'switched_any_method_pct'],1)==reference$reference[row,11])
}
stopifnot(all(abs(results[,'all_cause_pct']-results[,'wanted_to_become_pregnant_pct']-
                  results[,'excluding_wanted_pregnancy_pct'])<1e-9),
          all(results[,'excluding_pregnancy_fertility_and_partner_pct']>=0),
          all(results[,'excluding_pregnancy_fertility_and_partner_pct']<=
                results[,'excluding_wanted_pregnancy_and_partner_pct']),
          all(results[,'excluding_pregnancy_fertility_partner_and_other_pct']>=0),
          all(results[,'excluding_pregnancy_fertility_partner_and_other_pct']<=
                results[,'excluding_pregnancy_fertility_and_partner_pct']),
          all(results[,'switched_any_method_pct']<=results[,'all_cause_pct']))
out <- file.path(project,'output/Supporting_data/12_month_nonpregnancy_and_switching.csv')
write.csv(data.frame(method=rownames(results),results,check.names=FALSE),out,row.names=FALSE)
print(round(results,3));cat('Saved:',out,'\n')
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 10_retained_reason_distribution.R
# LANGUAGE: R
MODULES[["10_retained_reason_distribution.R"]] <- list(
 language="R",
 packaged_sha256="d492a2a2485416a8a3df2ba9dc1986d966fcca42c913da03a71cca7ecc01abb8",
 args=character(),
 code=r"-----(#!/usr/bin/env Rscript
# Among the all-modern, EC-excluded 12-month discontinuation cumulative incidence,
# distribute the probability across reasons other than wanted pregnancy and
# husband/partner disapproval. Uses the same DHS Table 7.11 risk sets.
project <- Sys.getenv("ETHIOPIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
d <- readRDS(file.path(project, 'Data/Derived/ethiopia_2024_table_7_11_episodes.rds'))
d <- d[d$method_code %in% c(1L,2L,3L,5L,6L,7L,11L,13L,17L,18L), ]
ir <- readRDS(file.path(project, 'Data/ET2024DHS__ETIR8ADT__IR_raw.rds'))
stratum <- as.integer(ir$v022)
psu <- as.integer(ir$v021)
psu_key <- paste(stratum, psu, sep=':')
clusters <- unique(data.frame(key=psu_key, stratum=stratum))
d$cluster <- match(psu_key[d$woman_row], clusters$key)
names <- c('Method failure', 'Wanted to become pregnant',
  'Other fertility-related reasons', 'Changes in menstrual bleeding',
  'Other side effects or health concerns', 'Wanted a more effective method',
  'Access, cost, or inconvenience', 'Husband/partner disapproved',
  'Other reasons')
K <- nrow(clusters)
risk_by_cluster <- matrix(0, K, 12)
end_by_cluster <- array(0, c(K, 12, 9))
cluster_sum <- function(indices) {
  answer <- numeric(K)
  if (length(indices)) {
    rs <- rowsum(d$wt[indices], d$cluster[indices], reorder=FALSE)
    answer[as.integer(rownames(rs))] <- rs[,1]
  }
  answer
}
for (month in 1:12) {
  at_risk <- d$entry < month & d$exposure >= month
  risk_by_cluster[,month] <- cluster_sum(which(at_risk))
  ended <- at_risk & d$exposure == month & d$discontinued
  for (reason in 1:9)
    end_by_cluster[,month,reason] <- cluster_sum(which(ended & d$reason==reason))
}
end_matrix <- matrix(end_by_cluster, nrow=K, ncol=12*9)
calculate <- function(cluster_multiplier) {
  risks <- as.numeric(crossprod(cluster_multiplier, risk_by_cluster))
  endings <- matrix(as.numeric(crossprod(cluster_multiplier, end_matrix)),
                    nrow=12, ncol=9)
  survival <- 1
  cif <- numeric(9)
  for (month in 1:12) {
    cif <- cif + survival * endings[month,]/risks[month]
    survival <- survival * (1-sum(endings[month,])/risks[month])
  }
  cif
}
cif <- calculate(rep(1,K))
keep <- setdiff(1:9, c(2L,8L))
total <- sum(cif[keep])
result <- data.frame(reason=names[keep],
  twelve_month_cumulative_probability_pct=100*cif[keep],
  share_of_retained_reason_probability_pct=100*cif[keep]/total)

# Rao-Wu style rescaled PSU bootstrap within each v022 stratum. Every episode
# from a woman and every woman in her PSU shares the same replicate multiplier.
# The confidence interval is for the share of the retained 12-month cumulative
# incidence, not a simple binomial fraction of observed discontinued episodes.
cluster_ids_by_stratum <- split(seq_len(K), clusters$stratum)
stopifnot(all(lengths(cluster_ids_by_stratum)>1))
B <- 1000L
set.seed(20261002)
boot_share <- matrix(NA_real_, B, length(keep))
boot_risk <- matrix(NA_real_, B, length(keep))
boot_total <- numeric(B)
for (b in seq_len(B)) {
  multiplier <- numeric(K)
  for (ids in cluster_ids_by_stratum) {
    n <- length(ids)
    draw <- sample.int(n, n-1L, replace=TRUE)
    multiplier[ids] <- n/(n-1) * tabulate(draw, nbins=n)
  }
  cb <- calculate(multiplier)
  boot_share[b,] <- 100*cb[keep]/sum(cb[keep])
  boot_risk[b,] <- 100*cb[keep]
  boot_total[b] <- 100*sum(cb[keep])
}
result$risk_ci_lower_pct <- apply(boot_risk, 2, quantile, probs=.025, names=FALSE)
result$risk_ci_upper_pct <- apply(boot_risk, 2, quantile, probs=.975, names=FALSE)
result$ci_lower_pct <- apply(boot_share, 2, quantile, probs=.025, names=FALSE)
result$ci_upper_pct <- apply(boot_share, 2, quantile, probs=.975, names=FALSE)
events <- d$discontinued & d$exposure<=12 & d$entry<d$exposure
result$unweighted_events <- vapply(keep,
  function(k) sum(events & d$reason==k), integer(1))
result$women <- vapply(keep,
  function(k) length(unique(d$caseid[events & d$reason==k])), integer(1))
result$psus <- vapply(keep,
  function(k) length(unique(d$cluster[events & d$reason==k])), integer(1))
result <- result[order(-result$share_of_retained_reason_probability_pct), ]
row.names(result) <- NULL
comparison <- read.csv(file.path(project,
  'output/Supporting_data/12_month_nonpregnancy_and_switching.csv'))
all_modern <- comparison[comparison$method == 'All modern methods', ]
stopifnot(abs(100*total -
  all_modern$excluding_wanted_pregnancy_and_partner_pct) < 1e-8,
  abs(sum(result$share_of_retained_reason_probability_pct)-100) < 1e-9)
out <- file.path(project,
  'output/Supporting_data/12_month_retained_reason_distribution.csv')
write.csv(result, out, row.names=FALSE)
total_out <- file.path(project,
  'output/Supporting_data/12_month_retained_reason_total.csv')
write.csv(data.frame(twelve_month_cumulative_probability_pct=100*total,
  risk_ci_lower_pct=unname(quantile(boot_total,.025)),
  risk_ci_upper_pct=unname(quantile(boot_total,.975)),
  unweighted_events=sum(events & d$reason %in% keep),
  women=length(unique(d$caseid[events & d$reason %in% keep]))),
  total_out,row.names=FALSE)
print(result, row.names=FALSE)
cat('Retained cumulative probability:', round(100*total,4), '%\nSaved:',out,'\n')
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 12_reason_mix_by_method_restricted.R
# LANGUAGE: R
MODULES[["12_reason_mix_by_method_restricted.R"]] <- list(
 language="R",
 packaged_sha256="3e835fcdbac32bb8685487bf1286e6bd7fbd8fb5850ccf295de662715ff5c778",
 args=character(),
 code=r"-----(#!/usr/bin/env Rscript
# Table 7.12-style weighted reason distributions among observed modern-method
# discontinuations. This is conditional on an episode ending, not a life table.
library(ggplot2)

project <- Sys.getenv("ETHIOPIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
out <- file.path(project, "output")
events <- readRDS(file.path(project, "Data/Derived/ethiopia_2024_modern_method_discontinuations_5yr.rds"))
events <- events[events$method_code != 16, ] # EC is separate from this presentation grouping.
events$method <- ifelse(events$method_code == 3, "Injectables",
                 ifelse(events$method_code == 11, "Implants",
                 ifelse(events$method_code == 1, "Pill",
                 ifelse(events$method_code == 2, "IUD", "Other modern"))))
method_order <- c("Injectables", "Implants", "Pill", "IUD", "Other modern", "All modern")

original_reason <- function(code) {
  ifelse(code == 2, "Wanted pregnancy",
  ifelse(code %in% c(1, 4:9), "Method experience/access",
  ifelse(code == 3, "Partner disapproval", "Other reasons")))
}
restricted_reason <- function(code) {
  ifelse(code == 4, "Wanted more effective",
  ifelse(code %in% 5:6, "Side effects/health",
  ifelse(code %in% 7:9, "Access/cost/inconvenience", "Other/unknown")))
}
experience_reason <- function(code) {
  ifelse(code == 1, "Method failure",
  ifelse(code == 4, "Wanted a more effective method",
  ifelse(code %in% c(5, 6), "Side effects/health",
         "Access/cost/inconvenience")))
}

make_data <- function(d, reason_fun, reason_order) {
  d$reason_group <- reason_fun(d$reason_code)
  pooled <- d
  pooled$method <- "All modern"
  d <- rbind(d, pooled)
  d$method <- factor(d$method, levels = method_order)
  d$reason_group <- factor(d$reason_group, levels = reason_order)
  totals <- aggregate(wt ~ method + reason_group, d, sum)
  denominators <- aggregate(wt ~ method, d, sum)
  counts <- aggregate(woman_row ~ method, d, length)
  names(counts)[2] <- "unweighted_episodes"
  names(denominators)[2] <- "weighted_episodes"
  z <- merge(merge(totals, denominators, by = "method"), counts, by = "method")
  z$percent <- 100 * z$wt / z$weighted_episodes
  stopifnot(all(abs(tapply(z$percent, z$method, sum) - 100) < 1e-9))
  z[order(z$method, z$reason_group), ]
}

all_reason_order <- c("Wanted pregnancy", "Method experience/access", "Partner disapproval", "Other reasons")
all_data <- make_data(events, original_reason, all_reason_order)

# Direct companion to the all-reason figure: remove only the two stated reasons
# the user selected. Method failure and other fertility-related reasons remain.
excluding_wanted_partner <- events[!(events$reason_code %in% c(2L, 3L)), ]
excluding_wanted_partner_data <- make_data(
  excluding_wanted_partner, original_reason,
  c("Method experience/access", "Other reasons"))

# Drill down only among endings in the method-experience/access group. Neither
# wanted pregnancy nor partner disapproval nor residual Other enters this base.
experience <- events[events$reason_code %in% c(1L, 4:9), ]
experience_order <- c("Method failure", "Wanted a more effective method",
                      "Side effects/health", "Access/cost/inconvenience")
experience_data <- make_data(experience, experience_reason, experience_order)

# Exclude pregnancy desire, pregnancy during use (method failure), husband/partner
# disapproval, and the three other fertility-related reasons. Retain residual
# Other/unknown visibly rather than reclassifying it as a service-related exit.
excluded_codes <- c(1L, 2L, 3L, 11L, 12L, 13L)
restricted <- events[!(events$reason_code %in% excluded_codes), ]
restricted_order <- c("Wanted more effective", "Side effects/health",
                      "Access/cost/inconvenience", "Other/unknown")
restricted_data <- make_data(restricted, restricted_reason, restricted_order)

write.csv(all_data[, c("method", "reason_group", "percent", "unweighted_episodes", "weighted_episodes")],
          file.path(out, "reason_mix_by_method_all_discontinued.csv"), row.names = FALSE)
write.csv(excluding_wanted_partner_data[, c("method", "reason_group", "percent", "unweighted_episodes", "weighted_episodes")],
          file.path(out, "reason_mix_by_method_excluding_wanted_pregnancy_partner.csv"), row.names = FALSE)
write.csv(experience_data[, c("method", "reason_group", "percent", "unweighted_episodes", "weighted_episodes")],
          file.path(out, "reason_mix_by_method_experience_access_detail.csv"), row.names = FALSE)
write.csv(restricted_data[, c("method", "reason_group", "percent", "unweighted_episodes", "weighted_episodes")],
          file.path(out, "reason_mix_by_method_nonpregnancy_nonpartner.csv"), row.names = FALSE)

base_plot <- function(z, colors, path) {
  # Reverse levels so the conventional method order reads from top to bottom.
  z$method <- factor(z$method, levels = rev(method_order))
  z$reason_group <- factor(z$reason_group, levels = names(colors))
  # Plot stacked percent with internally centered values when room permits.
  label_data <- z
  label_data$label <- ifelse(label_data$percent >= 5.5, sprintf("%.1f", label_data$percent), "")
  label_data$label_color <- ifelse(as.character(label_data$reason_group) %in%
                                     c("Wanted a more effective method", "Side effects/health"),
                                   "#111111",
                                   ifelse(as.character(label_data$reason_group) %in%
                                            c("Other/unknown", "Other reasons"),
                                          "#17222C", "white"))
  p <- ggplot(z, aes(x = method, y = percent, fill = reason_group)) +
    geom_col(width = 0.60, color = "white", linewidth = 0.5,
             position = position_stack(reverse = TRUE)) +
    geom_text(data = label_data, aes(label = label, color = label_color,
                                     group = reason_group),
              position = position_stack(vjust = 0.5, reverse = TRUE),
              fontface = "bold", size = 5.0, family = "Arial") +
    coord_flip() +
    scale_y_continuous(limits = c(0, 100.001), breaks = seq(0, 100, 20),
                       labels = function(x) as.character(x), expand = c(0, 0)) +
    scale_fill_manual(values = colors, drop = FALSE) +
    scale_color_identity(guide = "none") +
    labs(x = NULL, y = "Share of discontinued episodes (%)", fill = NULL) +
    theme_minimal(base_family = "Arial", base_size = 16) +
    theme(panel.grid.major.y = element_blank(), panel.grid.minor = element_blank(),
          panel.grid.major.x = element_line(color = "#DCE4E7", linewidth = 0.45),
          axis.text.y = element_text(color = "#173845", size = 17, face = "bold"),
          axis.text.x = element_text(color = "#173845", size = 14),
          axis.title.x = element_text(color = "#173845", size = 16, margin = margin(t = 13)),
          legend.position = "bottom", legend.text = element_text(color = "#173845", size = 15),
          legend.key.width = grid::unit(0.48, "cm"),
          plot.margin = margin(18, 24, 18, 18))
  ggplot2::ggsave(path, p, width = 13.8, height = 6.3, units = "in", device = svglite::svglite)
}

base_plot(all_data,
  c("Wanted pregnancy" = "#138D8D", "Method experience/access" = "#153F5B",
    "Partner disapproval" = "#B65F8C", "Other reasons" = "#85909D"),
  file.path(out, "assets", "reason_mix_by_method_all_discontinued.svg"))
base_plot(excluding_wanted_partner_data,
  c("Method experience/access" = "#153F5B", "Other reasons" = "#85909D"),
  file.path(out, "assets", "reason_mix_by_method_excluding_wanted_pregnancy_partner.svg"))
base_plot(experience_data,
  c("Method failure" = "#66519A", "Wanted a more effective method" = "#DA9A25",
    "Side effects/health" = "#D45A49",
    "Access/cost/inconvenience" = "#153F5B"),
  file.path(out, "assets", "reason_mix_by_method_experience_access_detail.svg"))
base_plot(restricted_data,
  c("Wanted more effective" = "#DDA02B", "Side effects/health" = "#D75F4B",
    "Access/cost/inconvenience" = "#153F5B", "Other/unknown" = "#85909D"),
  file.path(out, "assets", "reason_mix_by_method_nonpregnancy_nonpartner.svg"))

cat(sprintf("All modern: %d raw / %.1f weighted discontinued episodes; restricted: %d raw / %.1f weighted.\n",
            nrow(events), sum(events$wt), nrow(restricted), sum(restricted$wt)))
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 14_restricted_discontinuation_curve.R
# LANGUAGE: R
MODULES[["14_restricted_discontinuation_curve.R"]] <- list(
 language="R",
 packaged_sha256="cfe809faf4db219559816f6ba41d3babff04119e91d53198720e38a9131cbf63",
 args=character(),
 code=r"-----(#!/usr/bin/env Rscript
# Monthly competing-risks cumulative incidence after excluding only desire to
# become pregnant and husband/partner disapproval. Uses the DHS-validated
# episode construction and matches column 2 of the comparison table.

project <- Sys.getenv("ETHIOPIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
episodes <- readRDS(file.path(project, 'Data/Derived/ethiopia_2024_table_7_11_episodes.rds'))
groups <- list(
  'Pill'=1L,
  'Other modern methods'=c(5L,6L,7L,13L,17L,18L),
  'Injectables'=3L,
  'All modern methods'=c(1L,2L,3L,5L,6L,7L,11L,13L,17L,18L),
  'IUD'=2L,
  'Implants'=11L
)

one_curve <- function(codes, label) {
  d <- episodes[episodes$method_code %in% codes,]
  survival <- 1
  cumulative <- 0
  out <- data.frame(method=label, month=0L, cumulative_pct=0)
  for (month in 1:12) {
    at_risk <- d$entry < month & d$exposure >= month
    risk <- sum(d$wt[at_risk])
    ended <- at_risk & d$exposure == month & d$discontinued
    all_endings <- sum(d$wt[ended])
    retained_endings <- sum(d$wt[ended & d$reason %in% c(1L,3L,4L,5L,6L,7L,9L)])
    cumulative <- cumulative + survival * retained_endings / risk
    survival <- survival * (1 - all_endings / risk)
    out <- rbind(out, data.frame(method=label, month=month,
                                 cumulative_pct=100*cumulative))
  }
  out
}

curves <- do.call(rbind, Map(one_curve, groups, names(groups)))
reference <- read.csv(file.path(project, 'output/Supporting_data/12_month_nonpregnancy_and_switching.csv'),
                      check.names=FALSE)
for (label in names(groups)) {
  calculated <- curves$cumulative_pct[curves$method==label & curves$month==12L]
  expected <- reference$excluding_wanted_pregnancy_and_partner_pct[reference$method==label]
  stopifnot(length(calculated)==1L, length(expected)==1L,
            abs(calculated-expected)<1e-9)
}

output <- file.path(project, 'output')
write.csv(curves,
          file.path(output, 'presentation_discontinuation_monthly_excluding_wanted_pregnancy_partner.csv'),
          row.names=FALSE)

library(ggplot2)
colors <- c(
  'Pill'='#DA9A25',
  'Injectables'='#108B8D',
  'All modern methods'='#253843',
  'Other modern methods'='#6B7280',
  'IUD'='#D95C47',
  'Implants'='#153F5B'
)
curves$method <- factor(curves$method, levels=names(groups))
ends <- curves[curves$month==12L,]
ends$label <- paste0(as.character(ends$method), '  ', sprintf('%.1f%%',ends$cumulative_pct))
injectable_checkpoints <- curves[curves$method=='Injectables' & curves$month %in% c(3L,6L),]
injectable_checkpoints$label <- sprintf('%.1f%%',injectable_checkpoints$cumulative_pct)

plot <- ggplot(curves, aes(month, cumulative_pct, color=method, group=method)) +
  geom_hline(yintercept=seq(0,50,10), color='#EBEFF2', linewidth=.35) +
  geom_vline(xintercept=c(3,6,12), color='#D4DDE3', linetype='dashed', linewidth=.5) +
  geom_step(linewidth=1.3, direction='hv') +
  geom_text(data=ends, aes(label=label), x=12.2, hjust=0,
            fontface='bold', size=5.2, show.legend=FALSE) +
  geom_label(data=injectable_checkpoints, aes(label=label),
             vjust=-.85, fontface='bold', size=4.7, fill='white',
             linewidth=0, label.padding=unit(.1, 'lines'), show.legend=FALSE) +
  scale_color_manual(values=colors) +
  scale_x_continuous(breaks=c(0,3,6,9,12), limits=c(0,17), expand=c(0,0)) +
  scale_y_continuous(breaks=seq(0,50,10), labels=function(x) paste0(x,'%'),
                     limits=c(0,51), expand=c(0,0)) +
  labs(title='Discontinuation excluding wanted pregnancy and partner disapproval',
       subtitle='Cumulative probability of ending the original method, by month of use',
       x='Months since method initiation',
       y='Cumulative discontinuation probability') +
  theme_minimal(base_family='Arial', base_size=17) +
  theme(
    plot.title=element_text(size=25, face='bold', color='#153F5B', hjust=.5, margin=margin(b=7)),
    plot.subtitle=element_text(size=16, color='#52616E', hjust=.5, margin=margin(b=20)),
    axis.title=element_text(size=18, color='#17222C'),
    axis.text=element_text(size=16, color='#17222C'),
    axis.title.x=element_text(margin=margin(t=16)),
    axis.title.y=element_text(margin=margin(r=15)),
    panel.grid=element_blank(), legend.position='none',
    plot.margin=margin(22,30,22,24)
  )

svg <- file.path(output, 'assets/presentation_discontinuation_curve_excluding_wanted_pregnancy_partner.svg')
png <- file.path(output, 'assets/presentation_discontinuation_curve_excluding_wanted_pregnancy_partner.png')
ggsave(svg, plot, width=15.5, height=8.7, device=svglite::svglite, bg='white')
ggsave(png, plot, width=15.5, height=8.7, dpi=170, bg='white')
print(ends[,c('method','cumulative_pct')],row.names=FALSE)
cat('Saved:',svg,'\n')
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 16_mix_vs_restricted_discontinuation.R
# LANGUAGE: R
MODULES[["16_mix_vs_restricted_discontinuation.R"]] <- list(
 language="R",
 packaged_sha256="2f229ae2e21eba0c71a2779b7b39bd3516e8e497e3383fa58ee82f5e76e21a82",
 args=character(),
 code=r"-----(#!/usr/bin/env Rscript
# Pair the original share of observed method starts with the corrected
# competing-risks 12-month probability that excludes only wanted pregnancy
# and husband/partner disapproval.

project <- Sys.getenv("ETHIOPIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
output <- file.path(project, 'output')
mix <- read.csv(file.path(output, 'presentation_mix_vs_discontinuation.csv'),
                check.names=FALSE)
starts_no_ec <- read.csv(file.path(output,
  'presentation_initiation_overall_excluding_ec.csv'),check.names=FALSE)
reference <- read.csv(file.path(output, 'Supporting_data/12_month_nonpregnancy_and_switching.csv'),
                      check.names=FALSE)

reference_method <- c('Injectables', 'Implants', 'Pill', 'IUD',
                      'Other modern methods')
plot_method <- c('Injectables', 'Implants', 'Pill', 'IUD',
                 'Other modern (excl. EC)')
stopifnot(identical(as.character(mix$method), plot_method))
start_method <- c('Injectables','Implants','Pill','IUD','Other modern')
mix$start_share_pct <- starts_no_ec$share_pct[match(start_method,starts_no_ec$method)]
stopifnot(!anyNA(mix$start_share_pct))
match_index <- match(reference_method, reference$method)
stopifnot(all(!is.na(match_index)))
mix$restricted_12_month_pct <-
  reference$excluding_wanted_pregnancy_and_partner_pct[match_index]
stopifnot(all(abs(mix$restricted_12_month_pct -
  c(25.5390406863256, 9.91396193775474, 46.5647480230008,
    14.9892779629398, 32.4377770103292)) < 1e-8))

write.csv(mix,
  file.path(output, 'presentation_mix_vs_discontinuation_excluding_wanted_pregnancy_partner.csv'),
  row.names=FALSE)

library(ggplot2)
labels <- c('Injectables', 'Implants', 'Pill', 'IUD',
            'Other modern methods')
dat <- data.frame(
  method=rep(labels, each=2),
  series=factor(rep(c('Share of starts excluding EC',
                      '12-month discontinuation'), 5),
                levels=c('12-month discontinuation',
                         'Share of starts excluding EC')),
  value=as.vector(t(cbind(mix$start_share_pct,
                          mix$restricted_12_month_pct)))
)
dat$value_label <- sprintf('%.1f%%', dat$value)
dat$method_y <- rep(rev(seq_along(labels)), each=2)
dat$bar_y <- dat$method_y + ifelse(dat$series=='Share of starts excluding EC', .17, -.17)
dat$ymin <- dat$bar_y - .17
dat$ymax <- dat$bar_y + .17

figure <- ggplot(dat, aes(fill=series)) +
  geom_rect(aes(xmin=0, xmax=value, ymin=ymin, ymax=ymax)) +
  geom_text(aes(x=value+1.1, y=bar_y, label=value_label),
            hjust=0, size=5.2, fontface='bold', color='#17222C') +
  scale_fill_manual(values=c('Share of starts excluding EC'='#DA9A25',
                             '12-month discontinuation'='#153F5B'),
                    breaks=c('Share of starts excluding EC',
                             '12-month discontinuation')) +
  scale_x_continuous(breaks=c(0,20,40,60),
                     labels=function(x) paste0(x,'%'),
                     limits=c(0,70), expand=c(0,0)) +
  scale_y_continuous(breaks=seq_along(labels), labels=rev(labels),
                     limits=c(.4, length(labels)+.6), expand=c(0,0)) +
  labs(title='Injectables dominate starts; pill discontinuation remains highest',
       x=NULL, y=NULL, fill=NULL) +
  theme_minimal(base_family='Arial', base_size=18) +
  theme(
    plot.title=element_text(size=26, face='bold', color='#153F5B',
                            hjust=.5, margin=margin(b=8)),
    plot.title.position='plot',
    panel.grid.major.y=element_blank(),
    panel.grid.minor=element_blank(),
    panel.grid.major.x=element_line(color='#E5EAED', linewidth=.55),
    axis.text.x=element_text(size=16, color='#17222C'),
    axis.text.y=element_text(size=18, color='#17222C'),
    legend.position='bottom',
    legend.text=element_text(size=17, color='#17222C'),
    legend.key.width=grid::unit(.75, 'cm'),
    plot.margin=margin(25,36,18,25)
  )

path <- file.path(output, 'assets/presentation_mix_vs_discontinuation_excluding_wanted_pregnancy_partner')
ggsave(paste0(path, '.svg'), figure, width=15.5, height=8.7,
       device=svglite::svglite, bg='white')
ggsave(paste0(path, '.png'), figure, width=15.5, height=8.7,
       dpi=170, bg='white')
print(mix[,c('method','start_share_pct','restricted_12_month_pct')],row.names=FALSE)
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 18_initiation_mix_excluding_ec.R
# LANGUAGE: R
MODULES[["18_initiation_mix_excluding_ec.R"]] <- list(
 language="R",
 packaged_sha256="6d692b1999eb74e23c3b70779580e70d9b45ea68da30e70a5e05df5e56bc2a5f",
 args=character(),
 code=r"-----(#!/usr/bin/env Rscript
# EC-excluded presentation view of observed contraceptive method starts.
# The original EC-inclusive CSVs and DHS validation products are preserved.

project <- Sys.getenv("ETHIOPIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
out <- file.path(project, 'output')
assets <- file.path(out, 'assets')
overall <- read.csv(file.path(out, 'presentation_initiation_overall.csv'))
annual <- read.csv(file.path(out, 'presentation_initiation_by_year.csv'))

make_view <- function(raw, modern_only=FALSE) {
  dat <- raw[raw$method!='EC', ]
  if (modern_only) dat <- dat[dat$method!='Non-modern methods', ]
  dat$denominator <- ave(dat$weighted_starts, dat$period, FUN=sum)
  dat$share_pct <- 100*dat$weighted_starts/dat$denominator
  stopifnot(all(abs(tapply(dat$share_pct,dat$period,sum)-100)<1e-8))
  dat[,c('period','method','unweighted_starts','weighted_starts',
         'denominator','share_pct')]
}

all_overall <- make_view(overall)
all_annual <- make_view(annual)
modern_overall <- make_view(overall, TRUE)
modern_annual <- make_view(annual, TRUE)

for (item in list(
  list('presentation_initiation_overall_excluding_ec.csv',all_overall),
  list('presentation_initiation_by_year_excluding_ec.csv',all_annual),
  list('presentation_initiation_modern_only_overall_excluding_ec.csv',modern_overall),
  list('presentation_initiation_modern_only_by_year_excluding_ec.csv',modern_annual)
)) write.csv(item[[2]],file.path(out,item[[1]]),row.names=FALSE)

library(ggplot2)
palette <- c('Injectables'='#108B8D','Implants'='#153F5B',
             'Pill'='#DA9A25','IUD'='#D95C47',
             'Other modern'='#6B7280','Non-modern methods'='#A18C6F')
all_order <- c('Injectables','Implants','Pill','IUD',
               'Other modern','Non-modern methods')
modern_order <- all_order[all_order!='Non-modern methods']

overall_plot <- function(data,title,x_label,order) {
  data$method <- factor(data$method, levels=rev(order))
  ggplot(data,aes(x=share_pct,y=method,fill=method)) +
    geom_col(width=.78,show.legend=FALSE) +
    geom_text(aes(label=sprintf('%.1f%%',share_pct)),hjust=-.22,
              size=5.2,color='#17222C') +
    scale_fill_manual(values=palette) +
    scale_x_continuous(breaks=seq(0,70,10),limits=c(0,74),expand=c(0,0)) +
    labs(title=title,x=x_label,y=NULL) +
    theme_minimal(base_family='Arial',base_size=18) +
    theme(plot.title=element_text(size=29,face='bold',hjust=.5,
                                  color='#153F5B',margin=margin(b=25)),
          axis.text=element_text(size=17,color='#17222C'),
          axis.text.y=element_text(size=19),
          axis.title.x=element_text(size=18,color='#17222C',
                                    margin=margin(t=14)),
          panel.grid.major.y=element_blank(),panel.grid.minor=element_blank(),
          panel.grid.major.x=element_line(color='#E5EAED',linewidth=.5),
          plot.margin=margin(24,36,20,25))
}

annual_plot <- function(data,title,y_label,order) {
  data <- data[data$period %in% as.character(2021:2024),]
  data$period <- factor(data$period,levels=as.character(2021:2024))
  data$method <- factor(data$method,levels=order)
  ggplot(data,aes(x=period,y=share_pct,fill=method)) +
    geom_col(width=.64,position=position_stack(reverse=TRUE)) +
    scale_fill_manual(values=palette,breaks=order,name=NULL) +
    scale_y_continuous(breaks=seq(0,100,20),labels=function(x)paste0(x,'%'),
                       expand=c(0,0)) +
    coord_cartesian(ylim=c(0,100)) +
    scale_x_discrete(labels=c('2021','2022','2023','2024\n(partial)')) +
    labs(title=title,x=NULL,y=y_label) +
    theme_minimal(base_family='Arial',base_size=18) +
    theme(plot.title=element_text(size=27,face='bold',hjust=.5,
                                  color='#153F5B',margin=margin(b=25)),
          axis.text=element_text(size=17,color='#17222C'),
          axis.title.y=element_text(size=18,color='#17222C',
                                    margin=margin(r=14)),
          panel.grid.major.x=element_blank(),panel.grid.minor=element_blank(),
          panel.grid.major.y=element_line(color='#E5EAED',linewidth=.5),
          legend.position='bottom',legend.text=element_text(size=16),
          legend.key.width=grid::unit(.8,'cm'),
          plot.margin=margin(24,20,14,20))
}

figures <- list(
  list('presentation_initiation_overall_excluding_ec',
       overall_plot(all_overall,'Overall initiation mix, excluding EC',
                    'Share of contraceptive starts excluding EC (%)',all_order)),
  list('presentation_initiation_by_year_excluding_ec',
       annual_plot(all_annual,'Initiation mix by calendar year, excluding EC',
                   'Share of contraceptive starts excluding EC',all_order)),
  list('presentation_initiation_modern_only_overall_excluding_ec',
       overall_plot(modern_overall,'Modern-method initiation mix, excluding EC',
                    'Share of modern-method starts excluding EC (%)',modern_order)),
  list('presentation_initiation_modern_only_by_year_excluding_ec',
       annual_plot(modern_annual,'Modern-method initiation mix by year, excluding EC',
                   'Share of modern-method starts excluding EC',modern_order))
)
for (entry in figures) {
  base <- file.path(assets,entry[[1]])
  ggsave(paste0(base,'.svg'),entry[[2]],width=15.5,height=8.7,
         device=svglite::svglite,bg='white')
  ggsave(paste0(base,'.png'),entry[[2]],width=15.5,height=8.7,
         dpi=170,bg='white')
}
cat('All contraceptive starts excluding EC: ',
    unique(all_overall$denominator),' weighted; ',
    sum(all_overall$unweighted_starts),' unweighted\n',sep='')
cat('Modern starts excluding EC: ',
    unique(modern_overall$denominator),' weighted; ',
    sum(modern_overall$unweighted_starts),' unweighted\n',sep='')
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 19_mix_vs_allcause_excluding_ec.R
# LANGUAGE: R
MODULES[["19_mix_vs_allcause_excluding_ec.R"]] <- list(
 language="R",
 packaged_sha256="d9e3c102c8476ebe4eedc722c0a02b526294364657ef6e630309c79f6f3a3aea",
 args=character(),
 code=r"-----(#!/usr/bin/env Rscript
# Companion all-reason bars with method-start shares excluding EC.
source(file.path(Sys.getenv("ETHIOPIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE)), 'Code/16_mix_vs_restricted_discontinuation.R'))

dat$value[dat$series=='12-month discontinuation'] <- mix$d12_discontinuation_pct
dat$value_label <- sprintf('%.1f%%',dat$value)
figure$data <- dat
figure$scales$scales <- Filter(function(s) !('x' %in% s$aesthetics),
                               figure$scales$scales)
figure <- figure +
  scale_x_continuous(breaks=c(0,20,40,60,80),
                     labels=function(x)paste0(x,'%'),
                     limits=c(0,80),expand=c(0,0)) +
  labs(title='12-month discontinuation is highest for pills and injectables')

write.csv(mix[,c('method','start_share_pct','d12_discontinuation_pct')],
          file.path(output,'presentation_mix_vs_allcause_discontinuation_excluding_ec.csv'),
          row.names=FALSE)
base <- file.path(output,'assets/presentation_mix_vs_allcause_discontinuation_excluding_ec')
ggsave(paste0(base,'.svg'),figure,width=15.5,height=8.7,
       device=svglite::svglite,bg='white')
ggsave(paste0(base,'.png'),figure,width=15.5,height=8.7,dpi=170,bg='white')
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 21_other_reason_breakdown.R
# LANGUAGE: R
MODULES[["21_other_reason_breakdown.R"]] <- list(
 language="R",
 packaged_sha256="5eeed0b7f1dd09142227a439bd11f7cdd45e316f007ce438d6ff47319c595d32",
 args=character(),
 code=r"-----(#!/usr/bin/env Rscript
# Weighted distributions within the two distinct "Other" reason categories.
# Counts are recorded discontinuation events, not weighted life-table risks.

project <- Sys.getenv("ETHIOPIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
derived <- file.path(project, "Data", "Derived")
output <- file.path(project, "output", "Supporting_data")

summarise_reasons <- function(dat, codes, labels, groups = NULL) {
  rows <- lapply(seq_along(codes), function(i) {
    d <- dat[dat$reason_code == codes[i], ]
    data.frame(
      group = if (is.null(groups)) "Residual Other reasons" else groups[i],
      reason = labels[i],
      unweighted_n = nrow(d),
      weighted_n = sum(d$wt),
      stringsAsFactors = FALSE
    )
  })
  result <- do.call(rbind, rows)
  result$percent_within_other <- 100 * result$weighted_n / sum(result$weighted_n)
  result
}

episodes <- readRDS(file.path(derived, "ethiopia_2024_specified_modern_method_episodes.rds"))
first_year_other <- subset(episodes,
  method_code != 16 & discontinued & exposure <= 12 & entry < exposure &
    reason %in% c(3, 9))
stopifnot(nrow(first_year_other) == 527L)
first_year <- summarise_reasons(
  first_year_other,
  c(9L, 13L, 12L, 96L, 11L, 0L, 98L),
  c("Infrequent sex or husband away", "Marital dissolution or separation",
    "Difficulty becoming pregnant or menopause", "Other, unspecified",
    "Up to God or fatalistic", "Missing or unclassified reason", "Don't know"),
  c(rep("Other fertility-related reasons", 3), rep("Residual Other reasons", 4))
)
stopifnot(sum(first_year$unweighted_n) == nrow(first_year_other),
          abs(sum(first_year$weighted_n) - sum(first_year_other$wt)) < 1e-7)
write.csv(first_year,
  file.path(output, "other_recorded_reasons_first_year_breakdown.csv"),
  row.names = FALSE)

events <- readRDS(file.path(derived, "ethiopia_2024_modern_method_discontinuations_5yr.rds"))
five_year_other <- subset(events, method_code != 16 & aggregated_reason_code == 9)
stopifnot(nrow(five_year_other) == 362L)
five_year <- summarise_reasons(
  five_year_other, c(10L, 14L, 15L),
  c("Up to God or fatalistic", "Other, unspecified", "Don't know")
)
stopifnot(sum(five_year$unweighted_n) == nrow(five_year_other),
          abs(sum(five_year$weighted_n) - sum(five_year_other$wt)) < 1e-7)
write.csv(five_year,
  file.path(output, "other_reasons_five_year_breakdown.csv"),
  row.names = FALSE)
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 23_infrequent_sex_followup_states.R
# LANGUAGE: R
MODULES[["23_infrequent_sex_followup_states.R"]] <- list(
 language="R",
 packaged_sha256="72587107d2ebf708be1fd836ecd6c9abf8b35a4464fa618337522930dde617bc",
 args=character(),
 code=r"-----(
# Full DHS sampling frame, including PSUs with no eligible outcome records.
full_survey_frame <- function(){
 r<-Sys.getenv('ETHIOPIA_PROJECT_ROOT'); stopifnot(nzchar(r))
 x<-readRDS(file.path(r,'Data/ET2024DHS__ETIR8ADT__IR_raw.rds'))
 unique(data.frame(cluster=paste(as.integer(x$v022),as.integer(x$v021),sep=':'),stratum=as.integer(x$v022)))
}
complete_survey_data <- function(d){
 r<-Sys.getenv('ETHIOPIA_PROJECT_ROOT');x<-readRDS(file.path(r,'Data/ET2024DHS__ETIR8ADT__IR_raw.rds'))
 f<-unique(data.frame(v021=as.integer(x$v021),v022=as.integer(x$v022)))
 key<-function(a,b)paste(a,b,sep=':');miss<-f[!key(f$v021,f$v022)%in%key(d$v021,d$v022),]
 if(nrow(miss)){z<-d[rep(1L,nrow(miss)),,drop=FALSE];z$v021<-miss$v021;z$v022<-miss$v022;z$wt<-0;d<-rbind(d,z)}
 d
}
#!/usr/bin/env Rscript
# Monthly calendar states after a modern-method discontinuation recorded as
# "infrequent sex/husband away", compared with other stated reasons.
# The same episodes have all 12 following months observed at every checkpoint.

suppressPackageStartupMessages(library(survey))
options(survey.lonely.psu = "adjust", stringsAsFactors = FALSE)
project <- Sys.getenv("ETHIOPIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
ir <- readRDS(file.path(project, "Data/ET2024DHS__ETIR8ADT__IR_raw.rds"))
episodes <- readRDS(file.path(project,
  "Data/Derived/ethiopia_2024_modern_method_discontinuations_5yr.rds"))
interview_position <- as.numeric(ir$v018[episodes$woman_row])
episodes <- episodes[episodes$method_code != 16L &
  episodes$calendar_position >= interview_position + 12L, ]
stopifnot(nrow(episodes) == 5012L, sum(episodes$reason_code == 12L) == 273L)

method_symbols <- strsplit("123456789WNALCFEMS~", "")[[1]]
ongoing_modern <- c(1L, 2L, 3L, 5L, 6L, 7L, 11L, 13L, 17L, 18L)
traditional <- c(8L, 9L, 10L)
states <- c("No method", "Using original method again",
            "Using a different modern method", "Pregnant",
            "Birth or pregnancy termination", "Traditional method",
            "Emergency contraception", "Other or unknown")

state_at <- function(month) {
  symbol <- substring(ir$vcal_1[episodes$woman_row],
    episodes$calendar_position - month, episodes$calendar_position - month)
  code <- match(symbol, method_symbols)
  state <- rep("Other or unknown", length(symbol))
  state[symbol == "0"] <- "No method"
  state[symbol == "P"] <- "Pregnant"
  state[symbol %in% c("B", "T")] <- "Birth or pregnancy termination"
  state[code %in% traditional] <- "Traditional method"
  state[code == 16L] <- "Emergency contraception"
  state[code %in% ongoing_modern & code == episodes$method_code] <-
    "Using original method again"
  state[code %in% ongoing_modern & code != episodes$method_code] <-
    "Using a different modern method"
  factor(state, levels = states)
}

comparisons <- list(
  "Infrequent sex or husband away" = episodes$reason_code == 12L,
  "All other stated reasons" = episodes$reason_code != 12L,
  "Other reasons excluding wanted pregnancy and partner disapproval" =
    !episodes$reason_code %in% c(12L, 2L, 3L)
)
results <- list()
for (month in c(1L, 3L, 6L, 12L)) {
  episodes$state <- state_at(month)
  episodes$no_method <- as.numeric(episodes$state == "No method")
  design <- svydesign(ids = ~v021, strata = ~v022, weights = ~wt,
                      data = complete_survey_data(episodes), nest = TRUE)
  for (label in names(comparisons)) {
    selected <- comparisons[[label]]
    sub <- episodes[selected, ]
    totals <- tapply(sub$wt, sub$state, sum)
    totals[is.na(totals)] <- 0
    shares <- 100 * totals / sum(sub$wt)
    design$variables$in_scope<-c(selected,rep(FALSE,nrow(design$variables)-length(selected)))
    ci <- 100 * confint(svymean(~no_method, subset(design, in_scope)))
    results[[length(results) + 1L]] <- data.frame(
      month_after_stop = month,
      comparison = label,
      unweighted_episodes = nrow(sub),
      distinct_women = length(unique(sub$woman_row)),
      weighted_episodes = sum(sub$wt),
      no_method_pct = shares["No method"],
      no_method_ci_lower = ci[1L],
      no_method_ci_upper = ci[2L],
      original_method_again_pct = shares["Using original method again"],
      different_modern_method_pct = shares["Using a different modern method"],
      pregnant_pct = shares["Pregnant"],
      birth_or_termination_pct = shares["Birth or pregnancy termination"],
      traditional_method_pct = shares["Traditional method"],
      emergency_contraception_pct = shares["Emergency contraception"],
      other_unknown_pct = shares["Other or unknown"],
      row.names = NULL
    )
  }
}
result <- do.call(rbind, results)
percentage_columns <- c("no_method_pct", "original_method_again_pct",
  "different_modern_method_pct", "pregnant_pct", "birth_or_termination_pct",
  "traditional_method_pct", "emergency_contraception_pct", "other_unknown_pct")
stopifnot(all(abs(rowSums(result[percentage_columns]) - 100) < 1e-8),
  all(result$other_unknown_pct == 0),
  all(result$unweighted_episodes[result$comparison ==
    "Infrequent sex or husband away"] == 273L))
write.csv(result, file.path(project, "output/Supporting_data",
  "infrequent_sex_followup_states_months_1_3_6_12.csv"), row.names = FALSE)
print(result[c("month_after_stop", "comparison", "unweighted_episodes",
  "no_method_pct", "original_method_again_pct",
  "different_modern_method_pct", "pregnant_pct")], row.names = FALSE)
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 25_other_recorded_reason_followup.R
# LANGUAGE: R
MODULES[["25_other_recorded_reason_followup.R"]] <- list(
 language="R",
 packaged_sha256="ee698a938297bfa7a57a35022f8c5c0d634ba256bfb542328c5d5710a04097ff",
 args=character(),
 code=r"-----(#!/usr/bin/env Rscript
# Fixed-cohort calendar states after first-year modern-method endings coded
# within the broad "Other recorded reasons" life-table category.
options(stringsAsFactors = FALSE)
project <- Sys.getenv("ETHIOPIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
ir <- readRDS(file.path(project, "Data/ET2024DHS__ETIR8ADT__IR_raw.rds"))
episodes <- readRDS(file.path(project,
  "Data/Derived/ethiopia_2024_specified_modern_method_episodes.rds"))
episodes <- subset(episodes, method_code != 16 & discontinued &
  exposure <= 12 & entry < exposure & reason_code %in%
  c(9L, 13L, 12L, 11L, 96L, 0L, 98L))
stopifnot(nrow(episodes) == 527L)
episodes <- subset(episodes, end_before_interview >= 12)
stopifnot(nrow(episodes) == 417L)

labels <- c(
  "Infrequent sex or husband away",
  "Marital dissolution or separation",
  "Difficulty becoming pregnant or menopause",
  "Up to God or fatalistic",
  "Other, unspecified, missing, or don't know"
)
episodes$reason_subgroup <- labels[match(episodes$reason_code,
  c(9L, 13L, 12L, 11L, 96L))]
episodes$reason_subgroup[episodes$reason_code %in% c(0L, 98L)] <- labels[5L]
stopifnot(!anyNA(episodes$reason_subgroup))

method_symbols <- strsplit("123456789WNALCFEMS~", "")[[1L]]
modern <- c(1L, 2L, 3L, 5L, 6L, 7L, 11L, 13L, 17L, 18L)
traditional <- c(8L, 9L, 10L)
last_method_position <- as.integer(ir$v018[episodes$woman_row]) +
  episodes$end_before_interview
last_symbol <- substring(ir$vcal_1[episodes$woman_row],
  last_method_position, last_method_position)
stopifnot(all(match(last_symbol, method_symbols) == episodes$method_code))

get_state <- function(month) {
  symbol <- substring(ir$vcal_1[episodes$woman_row],
    last_method_position - month, last_method_position - month)
  code <- match(symbol, method_symbols)
  state <- rep("Unknown", length(code))
  state[symbol == "0"] <- "No method"
  state[symbol %in% c("P", "B", "T")] <- "Pregnant, birth, or termination"
  state[code %in% traditional] <- "Traditional method"
  state[code == 16L] <- "Emergency contraception"
  state[code %in% modern & code == episodes$method_code] <-
    "Original method again"
  state[code %in% modern & code != episodes$method_code] <-
    "Different modern method"
  stopifnot(!any(state == "Unknown"))
  state
}

states <- c("No method", "Original method again", "Different modern method",
  "Traditional method", "Emergency contraception",
  "Pregnant, birth, or termination")
rows <- list()
for (label in labels) {
  sub <- episodes[episodes$reason_subgroup == label, ]
  for (month in c(1L, 3L, 6L, 12L)) {
    state <- get_state(month)[episodes$reason_subgroup == label]
    weighted <- vapply(states,
      function(s) sum(sub$wt[state == s]), numeric(1L))
    shares <- 100 * weighted / sum(sub$wt)
    row <- data.frame(
      reason_subgroup = label,
      month_after_stop = month,
      unweighted_episodes = nrow(sub),
      distinct_women = length(unique(sub$woman_row)),
      weighted_episodes = sum(sub$wt),
      weighted_share_within_other = 100 * sum(sub$wt) / sum(episodes$wt),
      no_method_pct = shares[1L],
      original_method_again_pct = shares[2L],
      different_modern_method_pct = shares[3L],
      traditional_method_pct = shares[4L],
      emergency_contraception_pct = shares[5L],
      pregnant_birth_or_termination_pct = shares[6L],
      row.names = NULL
    )
    rows[[length(rows) + 1L]] <- row
  }
}
result <- do.call(rbind, rows)
stopifnot(all(abs(rowSums(result[grepl("_pct$", names(result))]) - 100) < 1e-8),
  sum(result$unweighted_episodes[result$month_after_stop == 1L]) == 417L,
  abs(sum(result$weighted_share_within_other[result$month_after_stop == 1L]) - 100) < 1e-8)
out <- file.path(project, "output/Supporting_data",
  "other_recorded_reason_followup_states_1_3_6_12.csv")
write.csv(result, out, row.names = FALSE)
print(result[, c("reason_subgroup", "month_after_stop", "unweighted_episodes",
  "weighted_share_within_other", "no_method_pct", "original_method_again_pct",
  "different_modern_method_pct", "pregnant_birth_or_termination_pct")],
  row.names = FALSE)
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 31_method_experience_12_month_detail.R
# LANGUAGE: R
MODULES[["31_method_experience_12_month_detail.R"]] <- list(
 language="R",
 packaged_sha256="c90d841b7053a0ebfe5dd06593456a01db7cb4431b6b325b42fc1e2e8def87d0",
 args=character(),
 code=r"-----(#!/usr/bin/env Rscript
# Four cause-specific 12-month cumulative incidences underlying the
# method-experience/access segment of the presentation life table.
project <- Sys.getenv("ETHIOPIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
d <- readRDS(file.path(project, "Data/Derived/ethiopia_2024_table_7_11_episodes.rds"))
method_codes <- list(
  "Pill" = 1L,
  "Injectables" = 3L,
  "Other modern methods" = c(5L, 6L, 7L, 13L, 17L, 18L),
  "IUD" = 2L,
  "Implants" = 11L,
  "All modern methods" = c(1L, 2L, 3L, 5L, 6L, 7L, 11L, 13L, 17L, 18L)
)
detail <- function(e) {
  survival <- 1
  incidence <- numeric(9)
  for (month in 1:12) {
    at_risk <- e$entry < month & e$exposure >= month
    risk <- sum(e$wt[at_risk])
    ended <- at_risk & e$exposure == month & e$discontinued
    cause <- vapply(1:9, function(k) sum(e$wt[ended & e$reason == k]), numeric(1))
    incidence <- incidence + survival * cause / risk
    survival <- survival * (1 - sum(cause) / risk)
  }
  p <- 100 * incidence
  c(method_failure_pp = p[1], wanted_more_effective_pp = p[6],
    side_effects_health_pp = p[4] + p[5],
    access_cost_inconvenience_pp = p[7])
}
rows <- lapply(names(method_codes), function(method) {
  e <- d[d$method_code %in% method_codes[[method]], ]
  p <- detail(e)
  data.frame(method = method, t(p),
             total_method_experience_access_pp = sum(p),
             eligible_episodes_n = nrow(e), weighted_eligible_episodes = sum(e$wt),
             check.names = FALSE)
})
out <- do.call(rbind, rows)
rownames(out) <- NULL
baseline <- read.csv(file.path(project, "output/presentation_discontinuation_probability_excluding_pregnancy_partner.csv"))
check <- baseline$method_experience_or_access_percentage_points[match(out$method, baseline$method)]
stopifnot(all(abs(out$total_method_experience_access_pp - check) < 1e-7))
for (name in c("method_failure", "wanted_more_effective", "side_effects_health", "access_cost_inconvenience")) {
  out[[paste0(name, "_share_pct")]] <- 100 * out[[paste0(name, "_pp")]] / out$total_method_experience_access_pp
}
stopifnot(all(abs(rowSums(out[grep("_share_pct$", names(out))]) - 100) < 1e-8))
path <- file.path(project, "output/presentation_method_experience_12_month_detail.csv")
write.csv(out, path, row.names = FALSE)
print(out[, c("method", "method_failure_pp", "wanted_more_effective_pp",
              "side_effects_health_pp", "access_cost_inconvenience_pp",
              "total_method_experience_access_pp")], row.names = FALSE)
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 34_selected_reason_regression.R
# LANGUAGE: R
MODULES[["34_selected_reason_regression.R"]] <- list(
 language="R",
 packaged_sha256="c9a8ac56b5c58de0ca29560cd57a9ed1de9c962542ca2f54b5f365523d584adc",
 args=character(),
 code=r"-----(
# Algebraically identical monthly multinomial prediction, with the design
# matrix constructed once instead of once per duration month.
fast_survey_cif<-function(model,x,weights,event){
 x$month<-factor(1,levels=1:12)
 X<-model.matrix(delete.response(terms(model)),data=x,contrasts.arg=model$contrasts)
 b<-coef(model);eta<-X[,colnames(b),drop=FALSE]%*%t(b)
 S<-rep(1,nrow(x));F<-numeric(nrow(x));j<-match(event,rownames(b))
 for(t in 1:12){off<-if(t==1)rep(0,nrow(b))else b[,paste0('month',t)];ee<-exp(sweep(eta,2,off,'+'));den<-1+rowSums(ee);F<-F+S*ee[,j]/den;S<-S/den}
 100*weighted.mean(F,weights)
}

# Full DHS sampling frame, including PSUs with no eligible outcome records.
full_survey_frame <- function(){
 r<-Sys.getenv('ETHIOPIA_PROJECT_ROOT'); stopifnot(nzchar(r))
 x<-readRDS(file.path(r,'Data/ET2024DHS__ETIR8ADT__IR_raw.rds'))
 unique(data.frame(cluster=paste(as.integer(x$v022),as.integer(x$v021),sep=':'),stratum=as.integer(x$v022)))
}
complete_survey_data <- function(d){
 r<-Sys.getenv('ETHIOPIA_PROJECT_ROOT');x<-readRDS(file.path(r,'Data/ET2024DHS__ETIR8ADT__IR_raw.rds'))
 f<-unique(data.frame(v021=as.integer(x$v021),v022=as.integer(x$v022)))
 key<-function(a,b)paste(a,b,sep=':');miss<-f[!key(f$v021,f$v022)%in%key(d$v021,d$v022),]
 if(nrow(miss)){z<-d[rep(1L,nrow(miss)),,drop=FALSE];z$v021<-miss$v021;z$v022<-miss$v022;z$wt<-0;d<-rbind(d,z)}
 d
}
#!/usr/bin/env Rscript
# Survey-weighted episode-month competing-risk regression for modern-method
# discontinuation for any reason except wanted pregnancy or partner disapproval.
# The original method ending remains the event, whether or not the woman switches.
# Input: the validated Table 7.11 episode RDS made from the IR calendar by
# ethiopia_modern_method_discontinuation.R. The original .dta is imported to
# the woman-level RDS by 00_import_ir_dta.R; see Code/README.md for run order.
# Output: descriptive life tables, adjusted risks, and regression CSVs.
# nnet::multinom fits the three-category monthly outcome. Install from CRAN
# only if unavailable; downloading a package does not download DHS microdata.
if (!requireNamespace("nnet", quietly=TRUE)) {
  install.packages("nnet", repos="https://cloud.r-project.org")
}

project <- Sys.getenv("ETHIOPIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
out <- file.path(project, "output")
d <- readRDS(file.path(project, "Data/Derived/ethiopia_2024_table_7_11_episodes.rds"))
# Emergency contraception and traditional methods are outside this model's
# ongoing modern-method scope. The IR file supplies woman-level covariates and
# PSU/stratum identifiers through the retained woman_row key.
d <- d[d$method_code %in% c(1L, 2L, 3L, 5L, 6L, 7L, 11L, 13L, 17L, 18L), ]
ir <- readRDS(file.path(project, "Data/ET2024DHS__ETIR8ADT__IR_raw.rds"))
i <- d$woman_row

age <- floor((d$start - as.integer(ir$v011[i])) / 12)
birth_columns <- grep("^b3_", names(ir), value = TRUE)
births <- as.matrix(ir[i, birth_columns])
parity <- rowSums(!is.na(births) & births <= d$start)
education <- as.integer(ir$v106[i])
wealth <- as.integer(ir$v190[i])
residence <- as.integer(ir$v025[i])
region <- as.integer(ir$v024[i])
psu <- as.integer(ir$v021[i])
stratum <- as.integer(ir$v022[i])
complete <- !is.na(age) & age >= 15 & age <= 49 & !is.na(parity) &
  !is.na(education) & education %in% 0:3 &
  !is.na(wealth) & wealth %in% 1:5 &
  !is.na(residence) & residence %in% 1:2 &
  !is.na(region) & !is.na(psu) & !is.na(stratum)
d <- d[complete, ]
# The complete-case restriction applies to the model only; descriptive DHS
# life tables elsewhere retain otherwise eligible episodes without these
# covariates. Age and parity refer to episode start; education, wealth,
# residence, and region come from the interview and may have changed earlier.
i <- i[complete]
age <- age[complete]
parity <- parity[complete]
education <- education[complete]
wealth <- wealth[complete]
residence <- residence[complete]
region <- region[complete]
psu <- psu[complete]
stratum <- stratum[complete]

d$method_group <- factor(ifelse(d$method_code == 1L, "Pill",
  ifelse(d$method_code == 3L, "Injectables",
  ifelse(d$method_code == 11L, "Implants",
  ifelse(d$method_code == 2L, "IUD", "Other modern")))),
  levels = c("Injectables", "Implants", "Pill", "IUD", "Other modern"))
d$age_group <- cut(age, c(14, 19, 24, 34, 49),
  labels = c("15–19", "20–24", "25–34", "35–49"))
d$parity_group <- factor(ifelse(parity == 0, "0",
  ifelse(parity <= 2, "1–2", "3+")), levels = c("0", "1–2", "3+"))
d$education <- factor(ifelse(education == 0, "None",
  ifelse(education == 1, "Primary", "Secondary+")),
  levels = c("None", "Primary", "Secondary+"))
d$wealth_group <- factor(ifelse(wealth <= 2, "Poorest 40%",
  ifelse(wealth == 3, "Middle 20%", "Richest 40%")),
  levels = c("Poorest 40%", "Middle 20%", "Richest 40%"))
d$residence <- factor(ifelse(residence == 1, "Urban", "Rural"),
  levels = c("Rural", "Urban"))
d$region <- factor(region)
d$start_year <- factor((d$start - 1L) %/% 12L + 1900L)
d$cluster <- paste(stratum, psu, sep = ":")

observed_months <- pmax(0L, pmin(12L, d$exposure) - d$entry)
# Convert episode-level data to LONG episode-month data: an episode observed
# from duration month entry+1 through min(exposure,12) contributes one row for
# each such month. No row is created before delayed entry or after censoring.
# episode_index retains the parent episode so its weight and characteristics
# can be repeated; month is the month of method-use duration, not calendar year.
episode_index <- rep(seq_len(nrow(d)), observed_months)
month <- unlist(Map(function(first, n) seq.int(first + 1L, length.out = n),
                    d$entry, observed_months), use.names = FALSE)
person <- d[episode_index, c("wt", "method_group", "age_group", "parity_group",
                             "education", "wealth_group", "residence", "region",
                             "start_year", "cluster")]
person$month <- factor(month, levels = 1:12)
ended <- d$discontinued[episode_index] & month == d$exposure[episode_index]
# Code the monthly response as continue until the final observed month;
# classify that final month as selected ending or excluded competing ending.
# Wanted pregnancy and partner disapproval are NOT deleted from the initial
# cohort. They leave the risk set only when the original method ends.
person$outcome <- factor(ifelse(!ended, "continue",
  ifelse(d$reason[episode_index] %in% c(2L, 8L), "excluded", "selected")),
  levels = c("continue", "selected", "excluded"))
stopifnot(nrow(d) == 8611L, nrow(person) == 70691L,
          sum(person$outcome == "selected") == 1837L,
          sum(person$outcome == "excluded") == 1039L)

formula <- outcome ~ month + method_group + age_group + parity_group +
  education + wealth_group + residence + region + start_year
fit <- nnet::multinom(formula, data = person, weights = person$wt,
                     maxit = 250, trace = FALSE, MaxNWts = 10000)
# This is an adjusted association model for monthly event probabilities. The
# method indicator, duration month, demographics, region, and start year enter
# together; it is not a simple binary regression among discontinued episodes.
if (fit$convergence != 0L) stop("Multinomial model did not converge")

standard <- d[d$entry == 0L, ]
predict_risk <- function(model, variable = NULL, level = NULL,
                         standard_weights = standard$wt) {x<-standard;if(!is.null(variable))x[[variable]]<-factor(level,levels=levels(x[[variable]]));fast_survey_cif(model,x,standard_weights,'selected')}

variables <- c("method_group", "age_group", "parity_group", "education", "wealth_group", "residence")
rows <- lapply(variables, function(variable) {
  do.call(rbind, lapply(levels(standard[[variable]]), function(level) {
    data.frame(group = variable, level = level,
               adjusted_12_month_probability_pct = predict_risk(fit, variable, level),
               unweighted_observed_starts = sum(standard[[variable]] == level),
               weighted_observed_starts = sum(standard$wt[standard[[variable]] == level]))
  }))
})
margins <- do.call(rbind, rows)
rownames(margins) <- NULL
overall <- predict_risk(fit)

# Descriptive competing-risk life table on the same complete-case cohort. The
# initial eligible denominator includes endings from both cause groups; at each
# month every ending removes its episode from subsequent risk sets.
life_table_selected <- function(episodes) {
  survival <- 1
  incidence <- 0
  for (t in 1:12) {
    at_risk <- episodes$entry < t & episodes$exposure >= t
    denominator <- sum(episodes$wt[at_risk])
    all_end <- at_risk & episodes$discontinued & episodes$exposure == t
    selected_end <- all_end & !(episodes$reason %in% c(2L, 8L))
    incidence <- incidence + survival * sum(episodes$wt[selected_end]) / denominator
    survival <- survival * (1 - sum(episodes$wt[all_end]) / denominator)
  }
  100 * incidence
}
margins$unadjusted_12_month_probability_pct <- vapply(seq_len(nrow(margins)),
  function(j) life_table_selected(d[d[[margins$group[j]]] == margins$level[j], ]),
  numeric(1))
margins$unweighted_eligible_episodes <- vapply(seq_len(nrow(margins)),
  function(j) sum(d[[margins$group[j]]] == margins$level[j]), integer(1))
margins$weighted_eligible_episodes <- vapply(seq_len(nrow(margins)),
  function(j) sum(d$wt[d[[margins$group[j]]] == margins$level[j]]), numeric(1))
unadjusted_overall <- life_table_selected(d)
write.csv(margins, file.path(out, "presentation_selected_reason_predictor_margins_preliminary.csv"), row.names = FALSE)
write.csv(data.frame(unweighted_episodes = nrow(d),
                     weighted_episodes = sum(d$wt),
                     unweighted_observed_starts = nrow(standard),
                     at_risk_episode_months = nrow(person),
                     first_year_selected_endings = sum(person$outcome == "selected"),
                     first_year_excluded_endings = sum(person$outcome == "excluded"),
                     unadjusted_overall_pct = unadjusted_overall,
                     model_adjusted_overall_pct = overall),
          file.path(out, "presentation_selected_reason_regression_audit.csv"), row.names = FALSE)

# Rescaled PSU bootstrap within the original DHS strata. The multiplier is
# shared by every episode-month from every woman in a sampled PSU. The same
# replicate weights standardize the predicted risk over observed starts.
bootstrap_reps <- as.integer(Sys.getenv("BOOTSTRAP_REPS", "0"))
if (bootstrap_reps > 0L) {
  # Resample DHS PSUs within v022 strata. All episode-months of a woman, and
  # all women in a sampled PSU, receive the same replicate multiplier. This
  # preserves within-woman and within-cluster dependence in the intervals.
  library(parallel)
  cluster_frame <- full_survey_frame()
  clusters_by_stratum <- split(cluster_frame$cluster, cluster_frame$stratum)
  stopifnot(all(lengths(clusters_by_stratum) > 1L))
  margin_keys <- paste(margins$group, margins$level, sep = "::")
  one_replicate <- function(rep_no) {
    set.seed(20261004L + rep_no)
    multiplier <- setNames(numeric(nrow(cluster_frame)), cluster_frame$cluster)
    for (ids in clusters_by_stratum) {
      n <- length(ids)
      draw <- sample.int(n, n - 1L, replace = TRUE)
      multiplier[ids] <- n / (n - 1) * tabulate(draw, nbins = n)
    }
    bootstrap_weights <- person$wt * multiplier[person$cluster]
    standard_weights <- standard$wt * multiplier[standard$cluster]
    person$boot_wt <- bootstrap_weights
    model <- tryCatch(nnet::multinom(formula, data = person,
      weights = boot_wt, maxit = 250, trace = FALSE,
      MaxNWts = 10000), error = function(error) {
        message(sprintf("Bootstrap %d: %s", rep_no, conditionMessage(error)))
        NULL
      })
    if (is.null(model) || model$convergence != 0L) {
      if (!is.null(model)) message(sprintf("Bootstrap %d: convergence %d", rep_no, model$convergence))
      return(rep(NA_real_, length(margin_keys) + 1L))
    }
    c(overall = predict_risk(model, standard_weights = standard_weights),
      vapply(seq_len(nrow(margins)), function(j)
        predict_risk(model, margins$group[j], margins$level[j], standard_weights),
        numeric(1)))
  }
  cores <- min(4L, parallel::detectCores())
  boot <- parallel::mclapply(seq_len(bootstrap_reps), one_replicate,
                             mc.cores = cores, mc.preschedule = FALSE)
  boot <- do.call(rbind, boot)
  names <- c("overall", margin_keys)
  colnames(boot) <- names
  write.csv(data.frame(replicate = seq_len(nrow(boot)), boot, check.names = FALSE),
            file.path(out, "presentation_selected_reason_regression_bootstrap.csv"),
            row.names = FALSE)
  valid <- complete.cases(boot)
  if (sum(valid) < ceiling(0.95 * bootstrap_reps))
    stop(sprintf("Only %d of %d bootstrap fits converged", sum(valid), bootstrap_reps))
  ci <- apply(boot[valid, -1L, drop = FALSE], 2, quantile,
              probs = c(0.025, 0.975), names = FALSE)
  margins$ci_low <- ci[1, ]
  margins$ci_high <- ci[2, ]
  write.csv(margins,
    file.path(out, "presentation_selected_reason_predictor_margins.csv"),
    row.names = FALSE)
  write.csv(margins[, c("group", "level", "unweighted_eligible_episodes",
                       "weighted_eligible_episodes", "unadjusted_12_month_probability_pct",
                       "adjusted_12_month_probability_pct", "ci_low", "ci_high")],
    file.path(out, "presentation_selected_reason_unadjusted_vs_adjusted.csv"),
    row.names = FALSE)
  overall_ci <- quantile(boot[valid, 1L], c(0.025, 0.975), names = FALSE)
  write.csv(data.frame(overall_pct = overall, ci_low = overall_ci[1],
                       ci_high = overall_ci[2], bootstrap_reps = sum(valid)),
    file.path(out, "presentation_selected_reason_regression_overall.csv"),
    row.names = FALSE)
  cat(sprintf("Bootstrap converged: %d/%d; overall 95%% CI %.2f–%.2f%%\n",
    sum(valid), bootstrap_reps, overall_ci[1], overall_ci[2]))
}
cat(sprintf("Adjusted overall selected-cause 12-month probability: %.2f%%\n", overall))
cat(sprintf("Unadjusted overall selected-cause 12-month probability: %.2f%%\n", unadjusted_overall))
print(margins, row.names = FALSE)
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 36_selected_reason_contrasts.R
# LANGUAGE: R
MODULES[["36_selected_reason_contrasts.R"]] <- list(
 language="R",
 packaged_sha256="9be67af72781e5dec7677de3aebfb6b5f6fbc29442b78c3c78feb6bbce04aacb",
 args=character(),
 code=r"-----(#!/usr/bin/env Rscript
# Directly compare model-standardized 12-month cumulative probabilities.
project <- Sys.getenv("ETHIOPIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
out <- file.path(project, "output")
m <- read.csv(file.path(out, "presentation_selected_reason_predictor_margins.csv"),
              check.names = FALSE, stringsAsFactors = FALSE)
b <- read.csv(file.path(out, "presentation_selected_reason_regression_bootstrap.csv"),
              check.names = FALSE, stringsAsFactors = FALSE)

contrasts <- list()
omnibus <- list()
for (group in unique(m$group)) {
  x <- m[m$group == group, ]
  keys <- paste(group, x$level, sep = "::")
  replicate_margins <- as.matrix(b[, keys, drop = FALSE])
  storage.mode(replicate_margins) <- "numeric"
  stopifnot(all(complete.cases(replicate_margins)))
  for (i in seq_len(nrow(x) - 1L)) {
    for (j in (i + 1L):nrow(x)) {
      delta <- x$adjusted_12_month_probability_pct[i] -
        x$adjusted_12_month_probability_pct[j]
      draws <- replicate_margins[, i] - replicate_margins[, j]
      ci <- quantile(draws, c(0.025, 0.975), names = FALSE)
      contrasts[[length(contrasts) + 1L]] <- data.frame(
        group = group, level_1 = x$level[i], level_2 = x$level[j],
        adjusted_difference_percentage_points = delta,
        ci_low = ci[1], ci_high = ci[2],
        nominal_95_pct_ci_excludes_zero = ci[1] > 0 | ci[2] < 0)
    }
  }
  point_differences <- x$adjusted_12_month_probability_pct[-1L] -
    x$adjusted_12_month_probability_pct[1L]
  boot_differences <- replicate_margins[, -1L, drop = FALSE] -
    replicate_margins[, 1L]
  cov_matrix <- cov(boot_differences)
  if (length(point_differences) == 1L)
    cov_matrix <- matrix(cov_matrix, nrow = 1L)
  statistic <- drop(t(point_differences) %*% solve(cov_matrix) %*%
                      point_differences)
  omnibus[[length(omnibus) + 1L]] <- data.frame(
    group = group, levels = nrow(x), wald_chisq = statistic,
    degrees_of_freedom = nrow(x) - 1L,
    approximate_p_value = pchisq(statistic, df = nrow(x) - 1L,
                                 lower.tail = FALSE))
}
write.csv(do.call(rbind, contrasts),
  file.path(out, "presentation_selected_reason_pairwise_contrasts.csv"),
  row.names = FALSE)
write.csv(do.call(rbind, omnibus),
  file.path(out, "presentation_selected_reason_omnibus_tests.csv"),
  row.names = FALSE)
print(do.call(rbind, omnibus), row.names = FALSE)
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 37_selected_reason_regional_analysis.R
# LANGUAGE: R
MODULES[["37_selected_reason_regional_analysis.R"]] <- list(
 language="R",
 packaged_sha256="20cfae09065c145a8c45663f26cd98fbf4ba2d9364d7283d8c23c342befd6269",
 args=character(),
 code=r"-----(
# Full DHS sampling frame, including PSUs with no eligible outcome records.
full_survey_frame <- function(){
 r<-Sys.getenv('ETHIOPIA_PROJECT_ROOT'); stopifnot(nzchar(r))
 x<-readRDS(file.path(r,'Data/ET2024DHS__ETIR8ADT__IR_raw.rds'))
 unique(data.frame(cluster=paste(as.integer(x$v022),as.integer(x$v021),sep=':'),stratum=as.integer(x$v022)))
}
complete_survey_data <- function(d){
 r<-Sys.getenv('ETHIOPIA_PROJECT_ROOT');x<-readRDS(file.path(r,'Data/ET2024DHS__ETIR8ADT__IR_raw.rds'))
 f<-unique(data.frame(v021=as.integer(x$v021),v022=as.integer(x$v022)))
 key<-function(a,b)paste(a,b,sep=':');miss<-f[!key(f$v021,f$v022)%in%key(d$v021,d$v022),]
 if(nrow(miss)){z<-d[rep(1L,nrow(miss)),,drop=FALSE];z$v021<-miss$v021;z$v022<-miss$v022;z$wt<-0;d<-rbind(d,z)}
 d
}
#!/usr/bin/env Rscript
# Region-specific selected-reason cumulative incidence from the same model and
# complete-case cohort as the national adjusted regression. The two companion
# reason tables use observed first-year endings in that same cohort.
project <- Sys.getenv("ETHIOPIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
out <- file.path(project, "output")
Sys.setenv(BOOTSTRAP_REPS = "0")
invisible(capture.output(source(file.path(project, "Code/34_selected_reason_regression.R"),
                                local = TRUE)))

region_labels <- c(
  `1` = "Tigray", `2` = "Afar", `3` = "Amhara", `4` = "Oromia",
  `5` = "Somali", `6` = "Benishangul-Gumuz", `7` = "Central Ethiopia",
  `8` = "Sidama", `9` = "South West Ethiopia", `10` = "South Ethiopia",
  `12` = "Gambella", `13` = "Harari", `14` = "Addis Ababa", `15` = "Dire Dawa")
codes <- levels(d$region)
stopifnot(all(codes %in% names(region_labels)))
region_name <- unname(region_labels[codes])

at_end <- d$discontinued & d$entry < d$exposure & d$exposure <= 12L
selected_end <- at_end & !(d$reason %in% c(2L, 8L))
excluded_end <- at_end & d$reason %in% c(2L, 8L)
experience <- selected_end & d$reason %in% c(1L, 4L, 5L, 6L, 7L)
other <- selected_end & d$reason %in% c(3L, 9L)
stopifnot(sum(selected_end) == 1837L, sum(excluded_end) == 1039L,
          sum(experience) + sum(other) == sum(selected_end))

region_rates <- do.call(rbind, lapply(seq_along(codes), function(j) {
  in_region <- d$region == codes[j]
  data.frame(region_code = as.integer(codes[j]), region = region_name[j],
    unweighted_eligible_episodes = sum(in_region),
    weighted_eligible_episodes = sum(d$wt[in_region]),
    unweighted_selected_endings_12 = sum(in_region & selected_end),
    weighted_selected_endings_12 = sum(d$wt[in_region & selected_end]),
    unweighted_excluded_endings_12 = sum(in_region & excluded_end),
    unadjusted_12_month_probability_pct = life_table_selected(d[in_region, ]),
    adjusted_12_month_probability_pct = predict_risk(fit, "region", codes[j]),
    eligible_psus = length(unique(d$cluster[in_region])),
    selected_ending_psus = length(unique(d$cluster[in_region & selected_end])))
}))

# Stratified PSU bootstrap. The same multiplier applies to every episode from
# every woman in a sampled PSU, preserving repeated episodes and clustering.
B <- as.integer(Sys.getenv("REGIONAL_BOOTSTRAP_REPS", "160"))
if (B > 0L) {
  library(parallel)
  cluster_frame <- full_survey_frame()
  clusters_by_stratum <- split(cluster_frame$cluster, cluster_frame$stratum)
  stopifnot(all(lengths(clusters_by_stratum) > 1L))
  one_replicate <- function(rep_no) {
    set.seed(20261005L + rep_no)
    multiplier <- setNames(numeric(nrow(cluster_frame)), cluster_frame$cluster)
    for (ids in clusters_by_stratum) {
      n <- length(ids)
      draw <- sample.int(n, n - 1L, replace = TRUE)
      multiplier[ids] <- n / (n - 1L) * tabulate(draw, nbins = n)
    }
    p <- person
    p$boot_wt <- p$wt * multiplier[p$cluster]
    standard_weights <- standard$wt * multiplier[standard$cluster]
    model <- tryCatch(nnet::multinom(formula, data = p, weights = boot_wt,
      maxit = 250, trace = FALSE, MaxNWts = 10000),
      error = function(error) NULL)
    if (is.null(model) || model$convergence != 0L)
      return(rep(NA_real_, length(codes)))
    vapply(codes, function(code)
      predict_risk(model, "region", code, standard_weights), numeric(1))
  }
  boot <- parallel::mclapply(seq_len(B), one_replicate,
    mc.cores = min(4L, parallel::detectCores()), mc.preschedule = FALSE)
  boot <- do.call(rbind, boot)
  colnames(boot) <- region_name
  write.csv(data.frame(replicate = seq_len(B), boot, check.names = FALSE),
            file.path(out, "presentation_selected_reason_regional_bootstrap.csv"),
            row.names = FALSE)
  valid <- complete.cases(boot)
  if (sum(valid) < ceiling(.95 * B))
    stop(sprintf("Only %d/%d regional bootstrap fits converged", sum(valid), B))
  ci <- apply(boot[valid, , drop = FALSE], 2, quantile,
              probs = c(.025, .975), names = FALSE)
  region_rates$adjusted_ci_low <- ci[1, ]
  region_rates$adjusted_ci_high <- ci[2, ]
  region_rates$bootstrap_replicates <- sum(valid)
}
write.csv(region_rates,
          file.path(out, "presentation_selected_reason_regional_rates.csv"),
          row.names = FALSE)

round_to_100 <- function(weights) {
  stopifnot(sum(weights) > 0)
  values <- round(100 * weights / sum(weights), 1)
  values[length(values)] <- round(100 - sum(values[-length(values)]), 1)
  stopifnot(abs(sum(values) - 100) < 1e-8)
  values
}
profiles <- function(scope, name) {
  in_scope <- if (is.na(scope)) rep(TRUE, nrow(d)) else d$region == scope
  retained <- in_scope & selected_end
  exp_end <- in_scope & experience
  selected_weights <- c(
    method_experience_or_access = sum(d$wt[exp_end]),
    other_recorded_reasons = sum(d$wt[in_scope & other]))
  exp_weights <- c(
    method_failure = sum(d$wt[exp_end & d$reason == 1L]),
    wanted_more_effective = sum(d$wt[exp_end & d$reason == 6L]),
    side_effects_or_health = sum(d$wt[exp_end & d$reason %in% c(4L, 5L)]),
    access_cost_inconvenience = sum(d$wt[exp_end & d$reason == 7L]))
  selected_pct <- round_to_100(selected_weights)
  exp_pct <- round_to_100(exp_weights)
  list(
    selected = data.frame(region = name,
      unweighted_selected_endings = sum(retained),
      weighted_selected_endings = sum(d$wt[retained]),
      unweighted_method_experience_endings = sum(exp_end),
      unweighted_other_endings = sum(in_scope & other),
      method_experience_or_access_pct = selected_pct[1],
      other_recorded_reasons_pct = selected_pct[2]),
    experience = data.frame(region = name,
      unweighted_method_experience_endings = sum(exp_end),
      weighted_method_experience_endings = sum(d$wt[exp_end]),
      n_failure = sum(exp_end & d$reason == 1L),
      n_more_effective = sum(exp_end & d$reason == 6L),
      n_side_effects_or_health = sum(exp_end & d$reason %in% c(4L, 5L)),
      n_access_cost_inconvenience = sum(exp_end & d$reason == 7L),
      method_failure_pct = exp_pct[1],
      wanted_more_effective_pct = exp_pct[2],
      side_effects_or_health_pct = exp_pct[3],
      access_cost_inconvenience_pct = exp_pct[4]))
}
all_profiles <- c(list(profiles(NA, "All modern")),
                  lapply(seq_along(codes), function(j)
                    profiles(codes[j], region_name[j])))
selected_profile <- do.call(rbind, lapply(all_profiles, `[[`, "selected"))
experience_profile <- do.call(rbind, lapply(all_profiles, `[[`, "experience"))
rownames(selected_profile) <- NULL
rownames(experience_profile) <- NULL
stopifnot(all(abs(selected_profile$method_experience_or_access_pct +
              selected_profile$other_recorded_reasons_pct - 100) < 1e-8),
          all(abs(rowSums(experience_profile[,
              grepl("_pct$", names(experience_profile))]) - 100) < 1e-8))
write.csv(selected_profile,
          file.path(out, "presentation_selected_reason_regional_reason_profile.csv"),
          row.names = FALSE)
write.csv(experience_profile,
          file.path(out, "presentation_selected_reason_regional_method_experience_profile.csv"),
          row.names = FALSE)
cat(sprintf("%d eligible episodes; %d selected first-year endings; %d method-experience endings.\n",
    nrow(d), sum(selected_end), sum(experience)))
print(region_rates[, c("region", "unweighted_eligible_episodes",
   "unweighted_selected_endings_12", "unadjusted_12_month_probability_pct",
   "adjusted_12_month_probability_pct")], row.names = FALSE)
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 39_selected_reason_other_breakdown.R
# LANGUAGE: R
MODULES[["39_selected_reason_other_breakdown.R"]] <- list(
 language="R",
 packaged_sha256="b24261ad6564e635df3545a4e6be189e70a35b7426723d111d573a34380a0b32",
 args=character(),
 code=r"-----(#!/usr/bin/env Rscript
# Source the common complete-case cohort, then audit the first-year residual
# and fertility-related reasons grouped as "Other" in the regional tables.
project <- Sys.getenv("ETHIOPIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
Sys.setenv(BOOTSTRAP_REPS = "0")
invisible(capture.output(source(file.path(project,
  "Code/34_selected_reason_regression.R"), local = TRUE)))
other <- d$discontinued & d$entry < d$exposure & d$exposure <= 12L &
  d$reason %in% c(3L, 9L)
codes <- c(9L, 13L, 12L, 96L, 11L, 0L, 98L)
labels <- c("Infrequent sex or husband away",
            "Marital dissolution or separation",
            "Difficulty becoming pregnant or menopause",
            "Other, unspecified", "Up to God or fatalistic",
            "Missing or unclassified reason", "Don't know")
result <- data.frame(reason_code = codes, reason = labels,
  unweighted_n = vapply(codes, function(code)
    sum(other & d$reason_code == code), integer(1)),
  weighted_n = vapply(codes, function(code)
    sum(d$wt[other & d$reason_code == code]), numeric(1)))
result$percent_within_other <- round(100 * result$weighted_n /
                                       sum(result$weighted_n), 1)
stopifnot(sum(result$unweighted_n) == sum(other))
write.csv(result, file.path(project, "output",
  "presentation_selected_reason_regional_other_breakdown.csv"), row.names = FALSE)
print(result, row.names = FALSE)
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 40_unadjusted_selected_regional_ci.R
# LANGUAGE: R
MODULES[["40_unadjusted_selected_regional_ci.R"]] <- list(
 language="R",
 packaged_sha256="2727eb71c10e4fa92250ccae54cba26b344f704f237764e776101af8a906bdc2",
 args=character(),
 code=r"-----(
# Full DHS sampling frame, including PSUs with no eligible outcome records.
full_survey_frame <- function(){
 r<-Sys.getenv('ETHIOPIA_PROJECT_ROOT'); stopifnot(nzchar(r))
 x<-readRDS(file.path(r,'Data/ET2024DHS__ETIR8ADT__IR_raw.rds'))
 unique(data.frame(cluster=paste(as.integer(x$v022),as.integer(x$v021),sep=':'),stratum=as.integer(x$v022)))
}
complete_survey_data <- function(d){
 r<-Sys.getenv('ETHIOPIA_PROJECT_ROOT');x<-readRDS(file.path(r,'Data/ET2024DHS__ETIR8ADT__IR_raw.rds'))
 f<-unique(data.frame(v021=as.integer(x$v021),v022=as.integer(x$v022)))
 key<-function(a,b)paste(a,b,sep=':');miss<-f[!key(f$v021,f$v022)%in%key(d$v021,d$v022),]
 if(nrow(miss)){z<-d[rep(1L,nrow(miss)),,drop=FALSE];z$v021<-miss$v021;z$v022<-miss$v022;z$wt<-0;d<-rbind(d,z)}
 d
}
#!/usr/bin/env Rscript
# Design-based uncertainty for the unadjusted competing-risk life tables.
# Resample PSUs within survey strata; all episodes from a woman/PSU move together.
project <- Sys.getenv("ETHIOPIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
out <- file.path(project, "output")
Sys.setenv(BOOTSTRAP_REPS = "0")
invisible(capture.output(source(file.path(project, "Code/34_selected_reason_regression.R"), local = TRUE)))
rates_path <- file.path(out, "presentation_selected_reason_regional_rates.csv")
rates <- read.csv(rates_path, check.names = FALSE)
frame <- full_survey_frame()
ids_by_stratum <- split(seq_len(nrow(frame)), frame$stratum)
stopifnot(all(lengths(ids_by_stratum) > 1L))
d$ci <- match(d$cluster, frame$cluster)
K <- nrow(frame)
regions <- c("All modern", rates$region)
codes <- c(NA_integer_, rates$region_code)

# Each cell holds the survey-weighted risk set or ending weight contributed by a
# PSU in one month. Left-truncated episodes enter in their observed calendar month.
arrays <- lapply(codes, function(code) {
  scope <- if (is.na(code)) rep(TRUE, nrow(d)) else as.integer(as.character(d$region)) == code
  risk <- all <- selected <- matrix(0, K, 12L)
  for (t in seq_len(12L)) {
    at_risk <- scope & d$entry < t & d$exposure >= t
    ended <- at_risk & d$discontinued & d$exposure == t
    picked <- ended & !(d$reason %in% c(2L, 8L))
    for (spec in list(list(mask = at_risk, target = "risk"),
                      list(mask = ended, target = "all"),
                      list(mask = picked, target = "selected"))) {
      z <- rowsum(d$wt[spec$mask], d$ci[spec$mask], reorder = FALSE)
      if (nrow(z)) {
        ix <- as.integer(rownames(z))
        if (spec$target == "risk") risk[ix, t] <- z[, 1]
        if (spec$target == "all") all[ix, t] <- z[, 1]
        if (spec$target == "selected") selected[ix, t] <- z[, 1]
      }
    }
  }
  list(risk = risk, all = all, selected = selected)
})

cif <- function(a, multiplier) {
  R <- as.numeric(crossprod(multiplier, a$risk))
  A <- as.numeric(crossprod(multiplier, a$all))
  D <- as.numeric(crossprod(multiplier, a$selected))
  if (any(R <= 0) || any(A > R + 1e-6)) return(NA_real_)
  survival <- 1
  cumulative <- 0
  for (t in seq_len(12L)) {
    cumulative <- cumulative + survival * D[t] / R[t]
    survival <- survival * (1 - A[t] / R[t])
  }
  100 * cumulative
}
point <- vapply(arrays, cif, numeric(1), multiplier = rep(1, K))
stopifnot(abs(point[1] - life_table_selected(d)) < 1e-6,
          all(abs(point[-1] - rates$unadjusted_12_month_probability_pct) < 1e-6))

B <- 10000L
draws <- matrix(NA_real_, B, length(regions), dimnames = list(NULL, regions))
for (b in seq_len(B)) {
  set.seed(20261006L + b)
  mult <- numeric(K)
  for (ids in ids_by_stratum) {
    n <- length(ids)
    mult[ids] <- n / (n - 1L) * tabulate(sample.int(n, n - 1L, replace = TRUE), nbins = n)
  }
  draws[b, ] <- vapply(arrays, cif, numeric(1), multiplier = mult)
}
valid <- colSums(!is.na(draws))
stopifnot(all(valid >= ceiling(.95 * B)))
ci <- apply(draws, 2, quantile, probs = c(.025, .975), na.rm = TRUE)
write.csv(data.frame(replicate = seq_len(B), draws, check.names = FALSE),
          file.path(out, "presentation_selected_reason_regional_unadjusted_bootstrap.csv"),
          row.names = FALSE)
rates$unadjusted_ci_low <- ci[1, -1]
rates$unadjusted_ci_high <- ci[2, -1]
rates$unadjusted_bootstrap_replicates <- valid[-1]
write.csv(rates, rates_path, row.names = FALSE)
write.csv(data.frame(overall_unadjusted_pct = point[1],
                     ci_low = ci[1, 1], ci_high = ci[2, 1],
                     bootstrap_replicates = valid[1]),
          file.path(out, "presentation_selected_reason_regional_unadjusted_overall_ci.csv"),
          row.names = FALSE)
cat(sprintf("Unadjusted national: %.1f%% (95%% CI %.1f–%.1f); %d PSUs, %d draws.\n",
            point[1], ci[1, 1], ci[2, 1], K, B))
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 42_regional_method_mix_diagnostic.R
# LANGUAGE: R
MODULES[["42_regional_method_mix_diagnostic.R"]] <- list(
 language="R",
 packaged_sha256="253ce868a60d5ec27fc83f6a80b6d380704ae5353866258b4c96f5ac545a1544",
 args=character(),
 code=r"-----(
# Full DHS sampling frame, including PSUs with no eligible outcome records.
full_survey_frame <- function(){
 r<-Sys.getenv('ETHIOPIA_PROJECT_ROOT'); stopifnot(nzchar(r))
 x<-readRDS(file.path(r,'Data/ET2024DHS__ETIR8ADT__IR_raw.rds'))
 unique(data.frame(cluster=paste(as.integer(x$v022),as.integer(x$v021),sep=':'),stratum=as.integer(x$v022)))
}
complete_survey_data <- function(d){
 r<-Sys.getenv('ETHIOPIA_PROJECT_ROOT');x<-readRDS(file.path(r,'Data/ET2024DHS__ETIR8ADT__IR_raw.rds'))
 f<-unique(data.frame(v021=as.integer(x$v021),v022=as.integer(x$v022)))
 key<-function(a,b)paste(a,b,sep=':');miss<-f[!key(f$v021,f$v022)%in%key(d$v021,d$v022),]
 if(nrow(miss)){z<-d[rep(1L,nrow(miss)),,drop=FALSE];z$v021<-miss$v021;z$v022<-miss$v022;z$wt<-0;d<-rbind(d,z)}
 d
}
#!/usr/bin/env Rscript
# Exploratory descriptive decomposition of Tigray–Amhara selected-cause
# discontinuation. This does not edit the working HTML or presentation.
# Run after 00_import_ir_dta.R and ethiopia_modern_method_discontinuation.R.
# Script 34 loads the episode file and IR covariates, fits the discrete-time
# competing-event model, and leaves its complete-case episode frame as d.
# Here the outcome is a 12-month ending for any reason OTHER THAN wanted
# pregnancy or husband/partner disapproval; those two endings still compete.
project <- Sys.getenv("ETHIOPIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
Sys.setenv(BOOTSTRAP_REPS = "0")
invisible(capture.output(source(file.path(project, "Code/34_selected_reason_regression.R"), local = TRUE)))
out <- file.path(project, "output")
# Focus on the Tigray–Amhara contrast. Pool IUD with other modern because
# the separate cells are too small. The method mix below is the weighted share
# of eligible life-table episodes, NOT the share of observed new starts.
codes <- c(Tigray = 1L, Amhara = 3L)
methods <- c("Injectables", "Implants", "Pill", "Other modern")
d <- d[as.integer(as.character(d$region)) %in% codes, ]
d$four <- ifelse(as.character(d$method_group) %in% c("IUD", "Other modern"),
                 "Other modern", as.character(d$method_group))
d$region_name <- names(codes)[match(as.integer(as.character(d$region)), codes)]
frame <- full_survey_frame()
# Give each distinct PSU one matrix row. We retain its parent DHS stratum so
# bootstrap resampling can occur within strata, not across the whole country.
frame$ci <- seq_len(nrow(frame))
d$ci <- match(d$cluster, frame$cluster)
ids_by_stratum <- split(frame$ci, frame$stratum)
stopifnot(all(lengths(ids_by_stratum) > 1L))
K <- nrow(frame)

cells <- list()
for (r in names(codes)) for (m in methods) {
  z <- d[d$region_name == r & d$four == m, ]
  count <- numeric(K)
  x <- rowsum(z$wt, z$ci, reorder = FALSE)
  count[as.integer(rownames(x))] <- x[, 1]
  risk <- endings <- selected <- matrix(0, K, 12L)
  # For each duration month, sum survey weights by PSU for (a) episodes at
  # risk, (b) all original-method endings, and (c) selected-cause endings.
  # The compact K × 12 matrices make each bootstrap replicate fast.
  for (t in seq_len(12L)) {
    at_risk <- z$entry < t & z$exposure >= t
    ended <- at_risk & z$discontinued & z$exposure == t
    masks <- list(at_risk, ended, ended & !(z$reason %in% c(2L, 8L)))
    targets <- list(risk, endings, selected)
    for (j in seq_along(masks)) {
      x <- rowsum(z$wt[masks[[j]]], z$ci[masks[[j]]], reorder = FALSE)
      if (nrow(x)) targets[[j]][as.integer(rownames(x)), t] <- x[, 1]
    }
    risk <- targets[[1]]; endings <- targets[[2]]; selected <- targets[[3]]
  }
  cells[[paste(r, m, sep = "|")]] <- list(n = nrow(z),
    selected_n = sum(z$discontinued & z$exposure <= 12L &
      z$entry < z$exposure & !(z$reason %in% c(2L, 8L))),
    count = count, risk = risk, endings = endings, selected = selected)
}

cif <- function(cell, mult) {
  # Cause-specific cumulative incidence: at month t, add survival through
  # t-1 times the selected monthly hazard. All-cause endings update survival,
  # so excluded reasons act as competing events rather than being censored.
  R <- as.numeric(crossprod(mult, cell$risk))
  A <- as.numeric(crossprod(mult, cell$endings))
  D <- as.numeric(crossprod(mult, cell$selected))
  if (any(R <= 0) || any(A > R + 1e-6)) return(NA_real_)
  survival <- 1; cumulative <- 0
  for (t in seq_len(12L)) {
    cumulative <- cumulative + survival * D[t] / R[t]
    survival <- survival * (1 - A[t] / R[t])
  }
  100 * cumulative
}

estimate <- function(mult) {
  # p = each region's weighted episode method mix; q = 12-month selected-cause
  # risk within each method. Sum p*q for the own-mix comparison, then repeat
  # with the two-region average mix as a common standard. The symmetric
  # split allocates the gap into method-composition and within-method terms.
  p <- q <- matrix(NA_real_, 2L, 4L,
                   dimnames = list(names(codes), methods))
  for (r in names(codes)) {
    counts <- vapply(methods, function(m)
      sum(cells[[paste(r, m, sep = "|")]]$count * mult), numeric(1))
    p[r, ] <- counts / sum(counts)
    for (m in methods) q[r, m] <- cif(cells[[paste(r, m, sep = "|")]], mult)
  }
  own <- rowSums(p * q)
  common <- colMeans(p)
  c(mix = sum((p["Tigray", ] - p["Amhara", ]) *
                (q["Tigray", ] + q["Amhara", ]) / 2),
    within = sum((q["Tigray", ] - q["Amhara", ]) * common),
    Tigray_own = own["Tigray"], Amhara_own = own["Amhara"],
    Tigray_common = sum(common * q["Tigray", ]),
    Amhara_common = sum(common * q["Amhara", ]),
    injectable_gap = q["Tigray", "Injectables"] - q["Amhara", "Injectables"])
}

point <- estimate(rep(1, K))
B <- 2000L
draws <- matrix(NA_real_, B, length(point), dimnames = list(NULL, names(point)))
# Rao–Wu-style rescaled PSU bootstrap within each stratum. Multipliers are
# shared across every episode in a sampled PSU, preserving repeated women.
for (b in seq_len(B)) {
  set.seed(20261004L + b)
  mult <- numeric(K)
  for (ids in ids_by_stratum) {
    n <- length(ids)
    mult[ids] <- n / (n - 1L) *
      tabulate(sample.int(n, n - 1L, replace = TRUE), nbins = n)
  }
  draws[b, ] <- estimate(mult)
}
ci <- apply(draws, 2L, quantile, probs = c(.025, .975), na.rm = TRUE)
summary <- data.frame(metric = names(point), estimate = unname(point),
                      ci_low = ci[1, ], ci_high = ci[2, ],
                      valid_draws = colSums(!is.na(draws)))
write.csv(summary, file.path(out, "regional_method_mix_diagnostic_summary.csv"), row.names = FALSE)
# Export method-specific shares, counts, and risks so the diagnostic page can
# be checked without reading coefficients from the decomposition itself.
rows <- do.call(rbind, lapply(names(codes), function(r) {
  counts <- vapply(methods, function(m) sum(cells[[paste(r, m, sep = "|")]]$count), numeric(1))
  do.call(rbind, lapply(methods, function(m) {
    x <- cells[[paste(r, m, sep = "|")]]
    data.frame(region = r, method = m, unweighted_episodes = x$n,
               selected_endings = x$selected_n,
               weighted_method_mix_pct = 100 * counts[m] / sum(counts),
               selected_cause_12_month_pct = cif(x, rep(1, K)))
  }))
}))
write.csv(rows, file.path(out, "regional_method_mix_diagnostic_cells.csv"), row.names = FALSE)
print(summary, row.names = FALSE)
print(rows, row.names = FALSE)
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 43_injectable_regional_reason_ci.R
# LANGUAGE: R
MODULES[["43_injectable_regional_reason_ci.R"]] <- list(
 language="R",
 packaged_sha256="e3ede2d71726f2de96a7cf52b4f7e8a921cdecef091b4e5de7ad14606b2d970c",
 args=character(),
 code=r"-----(
# Full DHS sampling frame, including PSUs with no eligible outcome records.
full_survey_frame <- function(){
 r<-Sys.getenv('ETHIOPIA_PROJECT_ROOT'); stopifnot(nzchar(r))
 x<-readRDS(file.path(r,'Data/ET2024DHS__ETIR8ADT__IR_raw.rds'))
 unique(data.frame(cluster=paste(as.integer(x$v022),as.integer(x$v021),sep=':'),stratum=as.integer(x$v022)))
}
complete_survey_data <- function(d){
 r<-Sys.getenv('ETHIOPIA_PROJECT_ROOT');x<-readRDS(file.path(r,'Data/ET2024DHS__ETIR8ADT__IR_raw.rds'))
 f<-unique(data.frame(v021=as.integer(x$v021),v022=as.integer(x$v022)))
 key<-function(a,b)paste(a,b,sep=':');miss<-f[!key(f$v021,f$v022)%in%key(d$v021,d$v022),]
 if(nrow(miss)){z<-d[rep(1L,nrow(miss)),,drop=FALSE];z$v021<-miss$v021;z$v022<-miss$v022;z$wt<-0;d<-rbind(d,z)}
 d
}
#!/usr/bin/env Rscript
# Survey-cluster bootstrap for the exploratory Tigray/Amhara injectable plots.
# Wanted pregnancy and husband/partner disapproval remain competing endings.
project <- Sys.getenv("ETHIOPIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
out <- file.path(project, "output")
Sys.setenv(BOOTSTRAP_REPS = "0")
invisible(capture.output(source(file.path(project, "Code/34_selected_reason_regression.R"), local = TRUE)))
d <- d[as.integer(as.character(d$region)) %in% c(1L, 3L) &
       d$method_group == "Injectables", ]
d$region_name <- ifelse(as.integer(as.character(d$region)) == 1L, "Tigray", "Amhara")
frame <- full_survey_frame()
frame$ci <- seq_len(nrow(frame))
d$ci <- match(d$cluster, frame$cluster)
ids_by_stratum <- split(frame$ci, frame$stratum)
stopifnot(all(lengths(ids_by_stratum) > 1L))
K <- nrow(frame)
reasons <- list(
  `Access, cost or inconvenience` = 7L,
  `Bleeding or other side effects` = c(4L, 5L),
  `Other fertility-related` = 3L,
  `Wanted more effective method` = 6L,
  `Method failure or other recorded` = c(1L, 9L))

summarize_psu <- function(z, mask) {
  answer <- numeric(K)
  x <- rowsum(z$wt[mask], z$ci[mask], reorder = FALSE)
  if (nrow(x)) answer[as.integer(rownames(x))] <- x[, 1]
  answer
}
build <- function(region) {
  z <- d[d$region_name == region, ]
  R <- A <- matrix(0, K, 12L)
  D <- array(0, c(K, 12L, length(reasons)), dimnames = list(NULL,NULL,names(reasons)))
  for (t in 1:12) {
    at <- z$entry < t & z$exposure >= t
    end <- at & z$discontinued & z$exposure == t
    R[,t] <- summarize_psu(z, at)
    A[,t] <- summarize_psu(z, end)
    for (j in seq_along(reasons))
      D[,t,j] <- summarize_psu(z, end & z$reason %in% reasons[[j]])
  }
  list(n = nrow(z), R = R, A = A, D = D)
}
arrays <- lapply(c("Tigray","Amhara"), build)
names(arrays) <- c("Tigray","Amhara")
estimate <- function(x, mult) {
  R <- as.numeric(crossprod(mult, x$R))
  A <- as.numeric(crossprod(mult, x$A))
  D <- sapply(seq_along(reasons), function(j)
    as.numeric(crossprod(mult, x$D[,,j])))
  if (any(R <= 0) || any(A > R + 1e-6)) return(rep(NA_real_, 8L))
  S <- 1; cif <- numeric(length(reasons)); timed <- numeric(3)
  for (t in 1:12) {
    cif <- cif + S * D[t,] / R[t]
    S <- S * (1 - A[t]/R[t])
    if (t %in% c(3L,6L,12L)) timed[match(t,c(3L,6L,12L))] <- sum(cif)
  }
  100*c(setNames(timed,paste0("Month ",c(3,6,12))),
        setNames(cif,names(reasons)))
}
labels <- names(estimate(arrays[[1]], rep(1,K)))
point <- sapply(arrays, estimate, mult = rep(1,K))
B <- 4000L
draws <- array(NA_real_, c(B,length(labels),2L),
               dimnames=list(NULL,labels,names(arrays)))
for (b in 1:B) {
  set.seed(20261004L+b)
  mult <- numeric(K)
  for (ids in ids_by_stratum) {
    n <- length(ids)
    mult[ids] <- n/(n-1L) * tabulate(sample.int(n,n-1L,replace=TRUE),nbins=n)
  }
  for (r in seq_along(arrays)) draws[b,,r] <- estimate(arrays[[r]],mult)
}
rows <- do.call(rbind,lapply(seq_along(arrays),function(r)
  do.call(rbind,lapply(seq_along(labels),function(j){
    x <- draws[,j,r]
    ci <- quantile(x,c(.025,.975),na.rm=TRUE)
    data.frame(region=names(arrays)[r],measure=labels[j],
      estimate_pct=point[j,r],ci_low=ci[1],ci_high=ci[2],
      valid_draws=sum(!is.na(x)),episodes=arrays[[r]]$n,
      observed_endings=if(j>3)sum(d$region_name==names(arrays)[r] &
        d$discontinued & d$exposure<=12 & d$entry<d$exposure &
        d$reason %in% reasons[[j-3]]) else NA_integer_)
  }))))
write.csv(rows,file.path(out,"injectable_tigray_amhara_timing_reason_ci.csv"),row.names=FALSE)
differences <- do.call(rbind,lapply(seq_along(labels),function(j){
  x <- draws[,j,1]-draws[,j,2]
  ci <- quantile(x,c(.025,.975),na.rm=TRUE)
  data.frame(measure=labels[j],gap_tigray_minus_amhara_pp=
    point[j,1]-point[j,2],ci_low=ci[1],ci_high=ci[2],
    valid_draws=sum(!is.na(x)))
}))
write.csv(differences,file.path(out,"injectable_tigray_amhara_gap_ci.csv"),row.names=FALSE)
cat("PSUs:", K, "; Bootstrap draws:",B,"\n")
print(rows,row.names=FALSE)
print(differences,row.names=FALSE)
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 44_selected_region_method_ci.R
# LANGUAGE: R
MODULES[["44_selected_region_method_ci.R"]] <- list(
 language="R",
 packaged_sha256="e78e093da6a27c04b48a7b8e79c20d8fbe64b6701b927385932e48945f87c8b0",
 args=character(),
 code=r"-----(
# Full DHS sampling frame, including PSUs with no eligible outcome records.
full_survey_frame <- function(){
 r<-Sys.getenv('ETHIOPIA_PROJECT_ROOT'); stopifnot(nzchar(r))
 x<-readRDS(file.path(r,'Data/ET2024DHS__ETIR8ADT__IR_raw.rds'))
 unique(data.frame(cluster=paste(as.integer(x$v022),as.integer(x$v021),sep=':'),stratum=as.integer(x$v022)))
}
complete_survey_data <- function(d){
 r<-Sys.getenv('ETHIOPIA_PROJECT_ROOT');x<-readRDS(file.path(r,'Data/ET2024DHS__ETIR8ADT__IR_raw.rds'))
 f<-unique(data.frame(v021=as.integer(x$v021),v022=as.integer(x$v022)))
 key<-function(a,b)paste(a,b,sep=':');miss<-f[!key(f$v021,f$v022)%in%key(d$v021,d$v022),]
 if(nrow(miss)){z<-d[rep(1L,nrow(miss)),,drop=FALSE];z$v021<-miss$v021;z$v022<-miss$v022;z$wt<-0;d<-rbind(d,z)}
 d
}
#!/usr/bin/env Rscript
# Exploratory region-by-method selected-cause 12-month life tables with
# survey-stratified PSU bootstrap intervals. Does not edit the working HTML.
project <- Sys.getenv("ETHIOPIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
out <- file.path(project, "output")
Sys.setenv(BOOTSTRAP_REPS = "0")
invisible(capture.output(source(file.path(project,"Code/34_selected_reason_regression.R"),local=TRUE)))
names_region <- c(`1`="Tigray",`2`="Afar",`3`="Amhara",`4`="Oromia",
 `5`="Somali",`6`="Benishangul-Gumuz",`7`="Central Ethiopia",`8`="Sidama",
 `9`="South West Ethiopia",`10`="South Ethiopia",`12`="Gambella",
 `13`="Harari",`14`="Addis Ababa",`15`="Dire Dawa")
methods <- c("Injectables","Pill","Implants")
B <- 1200L

make_array <- function(z, cluster_ids, K) {
  R <- A <- D <- matrix(0,K,12L)
  sum_to_cluster <- function(mask) {
    ans <- numeric(K)
    if(any(mask)) {
      x <- rowsum(z$wt[mask],cluster_ids[mask],reorder=FALSE)
      ans[as.integer(rownames(x))] <- x[,1]
    }
    ans
  }
  for(t in 1:12){
    risk <- z$entry<t & z$exposure>=t
    ending <- risk & z$discontinued & z$exposure==t
    selected <- ending & !(z$reason%in%c(2L,8L))
    R[,t] <- sum_to_cluster(risk)
    A[,t] <- sum_to_cluster(ending)
    D[,t] <- sum_to_cluster(selected)
  }
  list(R=R,A=A,D=D)
}
cif <- function(a,mult) {
  R <- as.numeric(crossprod(mult,a$R))
  A <- as.numeric(crossprod(mult,a$A))
  D <- as.numeric(crossprod(mult,a$D))
  if(any(R<=0) || any(A>R+1e-6))return(NA_real_)
  S <- 1; P <- 0
  for(t in 1:12){P <- P+S*D[t]/R[t];S <- S*(1-A[t]/R[t])}
  100*P
}
results <- list(); j <- 0L
for(code in names(names_region)) {
  z <- d[as.character(d$region)==code,]
  frame <- full_survey_frame()
  K <- nrow(frame)
  ids <- match(z$cluster,frame$cluster)
  strata <- split(seq_len(K),frame$stratum)
  stopifnot(all(lengths(strata)>1L))
  cells <- lapply(methods,function(m){
    zz <- z[z$method_group==m,]
    make_array(zz,ids[z$method_group==m],K)
  })
  names(cells) <- methods
  point <- vapply(cells,cif,numeric(1),mult=rep(1,K))
  draws <- matrix(NA_real_,B,length(methods),dimnames=list(NULL,methods))
  for(b in 1:B){
    set.seed(20261005L+as.integer(code)*100000L+b)
    mult <- numeric(K)
    for(g in strata){n<-length(g);mult[g]<-n/(n-1L)*
      tabulate(sample.int(n,n-1L,replace=TRUE),nbins=n)}
    draws[b,] <- vapply(cells,cif,numeric(1),mult=mult)
  }
  for(m in methods){
    zz <- z[z$method_group==m,]
    end <- zz$discontinued & zz$exposure<=12L & zz$entry<zz$exposure &
      !(zz$reason%in%c(2L,8L))
    v <- draws[,m]; ci <- if(sum(is.finite(v))>=B*.9)
      quantile(v,c(.025,.975),na.rm=TRUE) else c(NA_real_,NA_real_)
    j<-j+1L;results[[j]]<-data.frame(region=names_region[[code]],region_code=as.integer(code),
      method=m,eligible_episodes=nrow(zz),selected_first_year_endings=sum(end),
      estimate_pct=point[m],ci_low=ci[1],ci_high=ci[2],
      valid_draws=sum(is.finite(v)))
  }
}
result <- do.call(rbind,results)
rownames(result)<-NULL
write.csv(result,file.path(out,"selected_reason_region_method_ci_preview.csv"),row.names=FALSE)
print(result,row.names=FALSE)
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 45_injectable_region_checkpoints.R
# LANGUAGE: R
MODULES[["45_injectable_region_checkpoints.R"]] <- list(
 language="R",
 packaged_sha256="d1e3bb0b7bd35863e28a052ad3c057d1b17a7a1ad3d057c4469f5c979b7deccc",
 args=character(),
 code=r"-----(
# Full DHS sampling frame, including PSUs with no eligible outcome records.
full_survey_frame <- function(){
 r<-Sys.getenv('ETHIOPIA_PROJECT_ROOT'); stopifnot(nzchar(r))
 x<-readRDS(file.path(r,'Data/ET2024DHS__ETIR8ADT__IR_raw.rds'))
 unique(data.frame(cluster=paste(as.integer(x$v022),as.integer(x$v021),sep=':'),stratum=as.integer(x$v022)))
}
complete_survey_data <- function(d){
 r<-Sys.getenv('ETHIOPIA_PROJECT_ROOT');x<-readRDS(file.path(r,'Data/ET2024DHS__ETIR8ADT__IR_raw.rds'))
 f<-unique(data.frame(v021=as.integer(x$v021),v022=as.integer(x$v022)))
 key<-function(a,b)paste(a,b,sep=':');miss<-f[!key(f$v021,f$v022)%in%key(d$v021,d$v022),]
 if(nrow(miss)){z<-d[rep(1L,nrow(miss)),,drop=FALSE];z$v021<-miss$v021;z$v022<-miss$v022;z$wt<-0;d<-rbind(d,z)}
 d
}
#!/usr/bin/env Rscript
# Survey-weighted selected-cause injectable discontinuation at 3, 6, 9, 12
# months by region, with stratified PSU bootstrap intervals and sample audit.
# Inputs and lineage: 00_import_ir_dta.R imports the woman-level .dta;
# ethiopia_modern_method_discontinuation.R converts calendar strings into
# method episodes; 34_selected_reason_regression.R attaches covariates and
# survey-design identifiers. This script uses that complete-case episode frame
# and does not reshape the original .dta again. See Code/README.md.
project <- Sys.getenv("ETHIOPIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
out <- file.path(project, "output")
# Source 34 with its optional model bootstrap disabled. Its fitted model is
# not used here: we need the shared cleaned episode frame d. The checkpoint
# estimates below are DESCRIPTIVE weighted life-table estimates, not adjusted
# regression predictions.
Sys.setenv(BOOTSTRAP_REPS = "0")
invisible(capture.output(source(file.path(project,"Code/34_selected_reason_regression.R"),local=TRUE)))
region_names <- c(`1`="Tigray",`2`="Afar",`3`="Amhara",`4`="Oromia",
 `5`="Somali",`6`="Benishangul-Gumuz",`7`="Central Ethiopia",`8`="Sidama",
 `9`="South West Ethiopia",`10`="South Ethiopia",`12`="Gambella",
 `13`="Harari",`14`="Addis Ababa",`15`="Dire Dawa")
d <- d[d$method_group=="Injectables",]
checkpoints <- c(3L,6L,9L,12L)
B <- 3000L

aggregate_cluster <- function(z,idx,mask,K) {
  # Sum the individual DHS weights within each PSU for one monthly risk or
  # ending indicator; the same PSU index is used in every bootstrap draw.
  result <- numeric(K)
  if(any(mask)) {
    r <- rowsum(z$wt[mask],idx[mask],reorder=FALSE)
    result[as.integer(rownames(r))] <- r[,1]
  }
  result
}
curve <- function(R,A,D,mult) {
  # R = weight still at risk, A = weight ending for ANY reason, and D = weight
  # ending for a selected reason in each duration month. The selected monthly
  # hazard enters cumulative incidence only after survival through prior
  # months; all endings remove episodes from subsequent risk sets.
  risk <- as.numeric(crossprod(mult,R))
  all <- as.numeric(crossprod(mult,A))
  selected <- as.numeric(crossprod(mult,D))
  if(any(risk<=0) || any(all>risk+1e-6)) return(rep(NA_real_,4L))
  S <- 1; F <- 0; result <- numeric(4L)
  for(t in 1:12) {
    F <- F+S*selected[t]/risk[t]
    S <- S*(1-all[t]/risk[t])
    if(t%in%checkpoints) result[match(t,checkpoints)] <- 100*F
  }
  result
}

rows <- list(); audits <- list(); krow <- 0L
for(code in names(region_names)) {
  # Build region-specific PSU × month matrices. Women may contribute multiple
  # injectable episodes; keeping them in the same PSU preserves dependence.
  z <- d[as.character(d$region)==code,]
  frame <- full_survey_frame()
  K <- nrow(frame); idx <- match(z$cluster,frame$cluster)
  strata <- split(seq_len(K),frame$stratum)
  stopifnot(all(lengths(strata)>1L))
  R <- A <- D <- matrix(0,K,12L)
  for(t in 1:12) {
    at <- z$entry<t & z$exposure>=t
    ending <- at & z$discontinued & z$exposure==t
    selected <- ending & !(z$reason%in%c(2L,8L))
    R[,t] <- aggregate_cluster(z,idx,at,K)
    A[,t] <- aggregate_cluster(z,idx,ending,K)
    D[,t] <- aggregate_cluster(z,idx,selected,K)
  }
  point <- curve(R,A,D,rep(1,K))
  draws <- matrix(NA_real_,B,4L)
  # Resample PSUs within DHS strata, using the rescaled bootstrap multiplier.
  # The 2.5th and 97.5th percentiles of valid draws form the 95% interval.
  for(b in seq_len(B)) {
    set.seed(20261005L+as.integer(code)*100000L+b)
    mult <- numeric(K)
    for(ids in strata) {
      n <- length(ids)
      mult[ids] <- n/(n-1L)*tabulate(sample.int(n,n-1L,replace=TRUE),nbins=n)
    }
    draws[b,] <- curve(R,A,D,mult)
  }
  selected <- z$discontinued & z$entry<z$exposure &
    !(z$reason%in%c(2L,8L))
  for(j in seq_along(checkpoints)) {
    t <- checkpoints[j]
    ci <- if(sum(is.finite(draws[,j]))>=.9*B)
      quantile(draws[,j],c(.025,.975),na.rm=TRUE) else c(NA_real_,NA_real_)
    krow<-krow+1L
    rows[[krow]] <- data.frame(region=region_names[[code]],region_code=as.integer(code),
      month=t,rate_pct=point[j],ci_low=ci[1],ci_high=ci[2],
      valid_draws=sum(is.finite(draws[,j])),eligible_episodes=nrow(z),
      unique_women=length(unique(z$caseid)),survey_psus=K,
      selected_endings_through_month=sum(selected & z$exposure<=t),
      all_endings_through_month=sum(z$discontinued & z$entry<z$exposure & z$exposure<=t),
      episodes_at_risk_month=sum(z$entry<t & z$exposure>=t))
  }
  selected12 <- selected & z$exposure<=12
  # Precision audit: counts of eligible episodes, distinct women, PSUs,
  # observed selected endings, effective weighted episode size, and the
  # largest PSU's contribution to weighted first-year selected endings.
  cluster_ends <- rowsum(as.numeric(selected12)*z$wt,idx,reorder=FALSE)
  e <- numeric(K);e[as.integer(rownames(cluster_ends))]<-cluster_ends[,1]
  audits[[code]] <- data.frame(region=region_names[[code]],eligible_episodes=nrow(z),
    unique_women=length(unique(z$caseid)),survey_psus=K,
    selected_first_year_endings=sum(selected12),
    weighted_episodes=sum(z$wt),
    kish_episode_n=sum(z$wt)^2/sum(z$wt^2),
    max_psu_share_selected_weight=if(sum(e)>0)max(e)/sum(e) else NA_real_)
}
result <- do.call(rbind,rows);rownames(result)<-NULL
audit <- do.call(rbind,audits);rownames(audit)<-NULL
write.csv(result,file.path(out,"injectable_region_3_6_9_12_selected_ci.csv"),row.names=FALSE)
write.csv(audit,file.path(out,"injectable_region_selected_precision_audit.csv"),row.names=FALSE)
print(result,row.names=FALSE)
print(audit,row.names=FALSE)
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 46_regional_modern_start_mix.R
# LANGUAGE: R
MODULES[["46_regional_modern_start_mix.R"]] <- list(
 language="R",
 packaged_sha256="5b23039da7f5fedb719f85621495fbb6096d22a977bb11c51bbaa3aad36891bf",
 args=character(),
 code=r"-----(#!/usr/bin/env Rscript
# Observed modern-method starts by region, aligned with the EC-excluded
# initiation-mix figures. These are starts, not all episodes at risk.
# The input RDS was made by 02_method_initiation_analysis.R after the raw .dta
# was imported and its calendar converted to chronological method-use runs.
# That upstream script keeps only runs whose true start appears within the
# observed 3–62-month calendar window. This supplemental table uses a MODERN-
# ONLY denominator; the paired-bar regional plots in script 47 instead use
# all contraceptive starts other than EC, including traditional methods.
# Base R is sufficient here; there are no packages to install or download.
project <- Sys.getenv("ETHIOPIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
starts <- readRDS(file.path(project, "Data/Derived/ethiopia_2024_modern_method_starts.rds"))
# Emergency contraception is an episodic method and is excluded from the
# ongoing-method mix used in the presentation and regional figures.
starts <- starts[starts$method_code != 16L, ]
# Regroup native DHS method codes into the five non-EC modern categories.
method <- ifelse(starts$method_code == 3L, "Injectables",
          ifelse(starts$method_code == 11L, "Implants",
          ifelse(starts$method_code == 1L, "Pill",
          ifelse(starts$method_code == 2L, "IUD", "Other modern"))))
region_names <- c(`1`="Tigray",`2`="Afar",`3`="Amhara",`4`="Oromia",
                  `5`="Somali",`6`="Benishangul-Gumuz",`7`="Central Ethiopia",
                  `8`="Sidama",`9`="South West Ethiopia",`10`="South Ethiopia",
                  `12`="Gambella",`13`="Harari",`14`="Addis Ababa",`15`="Dire Dawa")
starts$region_name <- unname(region_names[as.character(starts$region)])
stopifnot(!anyNA(starts$region_name), nrow(starts) == 7699L)
starts$method_name <- method
methods <- c("Injectables", "Implants", "Pill", "IUD", "Other modern")
result <- do.call(rbind, lapply(names(region_names), function(code) {
  z <- starts[as.character(starts$region) == code, ]
  denom <- sum(z$wt)
  # Within each region, divide each method's weighted starts by that region's
  # weighted starts across all five modern groups. Raw N is supplied for
  # precision review but does not replace the survey-weighted denominator.
  do.call(rbind, lapply(methods, function(m) {
    q <- z[z$method_name == m, ]
    data.frame(region=unname(region_names[code]), method=m,
               unweighted_region_starts=nrow(z), unweighted_method_starts=nrow(q),
               weighted_region_starts=denom, weighted_method_starts=sum(q$wt),
               share_pct=100*sum(q$wt)/denom)
  }))
}))
stopifnot(all(abs(aggregate(share_pct ~ region, result, sum)$share_pct - 100) < 1e-8))
write.csv(result, file.path(project, "output/regional_modern_start_mix_excluding_ec.csv"), row.names=FALSE)
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 47_regional_mix_vs_allcause_method_panels.R
# LANGUAGE: R
MODULES[["47_regional_mix_vs_allcause_method_panels.R"]] <- list(
 language="R",
 packaged_sha256="1c8be9dc4753c5445ec636f8fc77897c7d1111d91f15ced149460c2081848c6d",
 args=character(),
 code=r"-----(#!/usr/bin/env Rscript
# Five regional companions to the presentation's paired-bar method figure.
# Amber: share of all observed contraceptive starts, excluding EC, in a region.
# Navy: all-cause 12-month discontinuation of the named original method.
# Run after the validated calendar-to-episode and national figure scripts;
# the source .dta import and calendar transformation are explained in
# 00_import_ir_dta.R and ethiopia_modern_method_discontinuation.R.
# These bars are descriptive; region-method uncertainty is not plotted here.
# The separate injectable heatmap uses a narrower selected-reason outcome.

# Packages: ggplot2 draws the paired bars and svglite writes editable SVG.
# CRAN is contacted only if a package is missing. DHS microdata are never
# downloaded by this or any of the package-installation lines.
for (package in c("ggplot2","svglite")) {
  if (!requireNamespace(package,quietly=TRUE)) {
    install.packages(package,repos="https://cloud.r-project.org")
  }
}
project <- Sys.getenv("ETHIOPIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
out <- file.path(project, "output")
assets <- file.path(out, "assets")
dir.create(assets, recursive=TRUE, showWarnings=FALSE)
events <- readRDS(file.path(project, "Data/Derived/ethiopia_2024_calendar_events.rds"))
ir <- readRDS(file.path(project, "Data/ET2024DHS__ETIR8ADT__IR_raw.rds"))
episodes <- readRDS(file.path(project, "Data/Derived/ethiopia_2024_table_7_11_episodes.rds"))
# events: one row per continuous calendar state/method run; ir: one row per
# woman; episodes: method-use runs eligible for the Table 7.11 life table.
# The original .dta is never altered, and no woman-month long file is created
# in this script. The episode files already retain woman_row for joining back
# to the IR region and survey variables.
region_names <- c(`1`="Tigray",`2`="Afar",`3`="Amhara",`4`="Oromia",
                  `5`="Somali",`6`="Benishangul-Gumuz",`7`="Central Ethiopia",
                  `8`="Sidama",`9`="South West Ethiopia",`10`="South Ethiopia",
                  `12`="Gambella",`13`="Harari",`14`="Addis Ababa",`15`="Dire Dawa")
methods <- list(Injectables=3L, Implants=11L, Pill=1L, IUD=2L,
                `Other modern`=c(5L,6L,7L,13L,17L,18L))
# Method codes are DHS recode values. Other modern excludes both IUD and EC.
# The starting-share denominator below also includes traditional codes 8–10;
# they have no paired blue bar because only modern methods are plotted.
method_code <- function(code) {
  for (name in names(methods)) if (code %in% methods[[name]]) return(name)
  NA_character_
}

# 1. Select OBSERVED starts: only runs that begin inside months 3–62 before
# interview. Left-censored runs may enter the life table but are not new starts.
# Divide each method's weighted starts by all contraceptive starts in that
# region after removing EC, matching the national presentation's gold bars.
starts <- events[events$start != events$calendar_start &
                 events$interview-events$start >= 3L &
                 events$interview-events$start <= 62L &
                 events$method_code %in% c(unlist(methods,use.names=FALSE),8L,9L,10L), ]
stopifnot(nrow(starts)==7900L)
starts$method <- vapply(starts$method_code, method_code, character(1))
starts$region <- unname(region_names[as.character(starts$region)])
stopifnot(!anyNA(starts$region))

episodes <- episodes[episodes$method_code %in% unlist(methods,use.names=FALSE), ]
# 2. Prepare the life-table cohort. Unlike the start cohort above, these
# episodes include delayed entry for method runs that began earlier. Region is
# read from the linked woman-level IR record; the episode weight is v005/1e6.
episodes$method <- vapply(episodes$method_code, method_code, character(1))
# v024 is a haven_labelled numeric variable. as.vector() drops only its label
# class, leaving the original numeric codes; recent haven/vctrs versions reject
# direct as.integer()/as.character() on the labelled object.
episodes$region <- unname(region_names[as.character(as.integer(as.vector(ir$v024[episodes$woman_row])))])
stopifnot(!anyNA(episodes$region))

life_table <- function(x) {
  # In month t of original-method use, denominator = total survey weight of
  # episodes under observation and still at risk. Numerator = weighted method
  # endings for ANY reason in that month. Multiply 1-hazard through 12 months
  # and subtract from 1 for the cumulative all-cause probability. Immediate
  # switching still ends the original method. Return NA when a tiny regional
  # method cell has no observable denominator for a needed month.
  survival <- 1
  for (month in 1:12) {
    at_risk <- x$entry < month & x$exposure >= month
    denom <- sum(x$wt[at_risk])
    if (denom <= 0) return(NA_real_)
    endings <- at_risk & x$discontinued & x$exposure == month
    survival <- survival * (1-sum(x$wt[endings])/denom)
  }
  100*(1-survival)
}

rows <- do.call(rbind,lapply(names(region_names),function(code) {
  # 3. Cross region and method. Export both raw N and weighted percentages so
  # that suppressed, unstable region-method rates can be audited later.
  region <- unname(region_names[code])
  s <- starts[starts$region==region, ]
  do.call(rbind,lapply(names(methods),function(method) {
    sm <- s[!is.na(s$method) & s$method==method, ]
    e <- episodes[episodes$region==region & episodes$method==method, ]
    data.frame(region=region,method=method,
               unweighted_all_starts=nrow(s),
               unweighted_method_starts=nrow(sm),
               weighted_start_share_pct=100*sum(sm$wt)/sum(s$wt),
               eligible_episodes=nrow(e),
               first_year_endings=sum(e$discontinued & e$entry<e$exposure & e$exposure<=12L),
               all_cause_12_month_pct=life_table(e))
  }))
}))
national <- read.csv(file.path(out,"presentation_mix_vs_allcause_discontinuation_excluding_ec.csv"))
# 4. Verify that pooling the regional source records reproduces every value
# in the validated national paired-bar input before making regional figures.
for (method in names(methods)) {
  national_name <- if (method=="Other modern") "Other modern (excl. EC)" else method
  reference <- national[national$method==national_name, ]
  stopifnot(nrow(reference)==1L,
    abs(100*sum(starts$wt[starts$method==method],na.rm=TRUE)/sum(starts$wt)-
        reference$start_share_pct)<1e-8,
    abs(life_table(episodes[episodes$method==method, ])-
        reference$d12_discontinuation_pct)<1e-8)
}
write.csv(rows,file.path(out,"regional_mix_vs_allcause_method_panels.csv"),row.names=FALSE)

# 5. Render one figure per method, following the national slide: touching
# amber/navy bars, the same two hex colors, light vertical grid, one-decimal
# value labels, and a national benchmark row above the regional rows.
library(ggplot2)
for (method in names(methods)) {
  z <- rows[rows$method==method, ]
  z <- z[order(-z$weighted_start_share_pct), ]
  national_name <- if (method=="Other modern") "Other modern (excl. EC)" else method
  reference <- national[national$method==national_name, ]
  national_row <- z[1L, ]
  national_row$region <- "National"
  national_row$weighted_start_share_pct <- reference$start_share_pct
  national_row$all_cause_12_month_pct <- reference$d12_discontinuation_pct
  national_row$eligible_episodes <- nrow(episodes[episodes$method==method, ])
  national_row$first_year_endings <- sum(episodes$method==method &
    episodes$discontinued & episodes$entry<episodes$exposure & episodes$exposure<=12L)
  z <- rbind(national_row,z)
  z$region <- factor(z$region,levels=rev(z$region))
  z$rate_ok <- (as.character(z$region)=="National") |
    (!is.na(z$all_cause_12_month_pct) &
     z$eligible_episodes>=30L & z$first_year_endings>=10L)
  # The count threshold is a conservative DISPLAY rule, not a formal
  # confidence-interval criterion. All IUD regional cells and many
  # other-modern cells fail it; keep their observed start-share bars but do
  # not imply a stable regional discontinuation probability with a blue bar.
  plot_rows <- rbind(
    data.frame(region=z$region,series="Share of starts excluding EC",
               value=z$weighted_start_share_pct,visible=TRUE),
    data.frame(region=z$region,series="12-month discontinuation",
               value=z$all_cause_12_month_pct,visible=z$rate_ok))
  plot_rows <- plot_rows[plot_rows$visible & !is.na(plot_rows$value), ]
  plot_rows$series <- factor(plot_rows$series,
    levels=c("Share of starts excluding EC","12-month discontinuation"))
  plot_rows$label <- sprintf("%.1f%%",plot_rows$value)
  plot_rows$region_y <- as.numeric(plot_rows$region)
  plot_rows$bar_y <- plot_rows$region_y +
    ifelse(plot_rows$series=="Share of starts excluding EC",.17,-.17)
  plot_rows$ymin <- plot_rows$bar_y-.17
  plot_rows$ymax <- plot_rows$bar_y+.17
  max_value <- max(plot_rows$value)
  ceiling <- max(80,ceiling((max_value+7)/20)*20)
  # The x-axis is in percent; extend it only as needed to fit the value label.
  # Region order is descending gold-bar share, with National held at the top.
  figure <- ggplot(plot_rows,aes(fill=series))+
    geom_hline(yintercept=length(levels(z$region))-.5,
               color="#C4D0D5",linewidth=.7)+
    geom_rect(aes(xmin=0,xmax=value,ymin=ymin,ymax=ymax))+
    geom_text(aes(x=value+1.1,y=bar_y,label=label),hjust=0,
              size=4.25,fontface="bold",color="#17222C")+
    scale_fill_manual(values=c("Share of starts excluding EC"="#DA9A25",
                               "12-month discontinuation"="#153F5B"),
                      breaks=c("Share of starts excluding EC","12-month discontinuation"),
                      drop=FALSE)+
    scale_x_continuous(breaks=seq(0,ceiling,20),
                       labels=function(x)paste0(x,"%"),
                       limits=c(0,ceiling),expand=c(0,0))+
    scale_y_continuous(breaks=seq_along(levels(z$region)),
                       labels=levels(z$region),
                       limits=c(.4,length(levels(z$region))+.6),expand=c(0,0))+
    labs(title=paste0(method,": method starts and 12-month discontinuation by region"),
         x=NULL,y=NULL,fill=NULL,
         caption="National benchmark at top. Share denominator: all observed starts excluding EC. Regional rates withheld when <30 episodes or <10 first-year endings.")+
    theme_minimal(base_family="Arial",base_size=16)+
    theme(plot.title=element_text(size=23,face="bold",color="#153F5B",hjust=.5,
                                  margin=margin(b=10)),
          plot.title.position="plot",panel.grid.major.y=element_blank(),
          panel.grid.minor=element_blank(),
          panel.grid.major.x=element_line(color="#E5EAED",linewidth=.55),
          axis.text.x=element_text(size=14,color="#17222C"),
          axis.text.y=element_text(size=15,color="#17222C"),
          legend.position="bottom",legend.text=element_text(size=15,color="#17222C"),
          legend.key.width=grid::unit(.75,"cm"),
          plot.caption=element_text(size=12,color="#52616E",hjust=0,
                                    margin=margin(t=8)),
          plot.margin=margin(23,35,16,24))
  if (method=="IUD") figure <- figure +
    geom_rect(data=data.frame(series="12-month discontinuation",
                              xmin=0,xmax=0,ymin=0,ymax=0),
              aes(xmin=xmin,xmax=xmax,ymin=ymin,ymax=ymax,fill=series),
              inherit.aes=FALSE,show.legend=TRUE)+
    annotate("text",x=43,y=8,label="Regional discontinuation rates\nare too sparse to display reliably",
             size=6,color="#52616E",lineheight=1.2)
  base <- file.path(assets,paste0("regional_mix_vs_allcause_",gsub(" ","_",tolower(method))))
  ggsave(paste0(base,".svg"),figure,width=15.5,height=10.8,
         device=svglite::svglite,bg="white")
  ggsave(paste0(base,".png"),figure,width=15.5,height=10.8,
         dpi=145,bg="white")
}
print(rows[,c("region","method","unweighted_method_starts","eligible_episodes",
             "first_year_endings","weighted_start_share_pct","all_cause_12_month_pct")],row.names=FALSE)
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 49_rebuild_presentation_figures_tables.R
# LANGUAGE: R
MODULES[["49_rebuild_presentation_figures_tables.R"]] <- list(
 language="R",
 packaged_sha256="7bf05569eac28136761bc468417da5dfca85bd20e77aade725860c9d89e53c17",
 args=character(),
 code=r"-----(#!/usr/bin/env Rscript
# Rebuild the 14 presentation figures that previously had no saved generator,
# plus the two numerical appendix tables. Run after the calendar/life-table
# scripts. Outputs go to output/reproduced_figures/ so the working HTML and
# PPTX are not silently changed. Every number below is read from an analysis
# CSV or explicitly marked as an illustrative label. No DHS microdata are
# stored in the figure folder. See Code/README.md for the source-data lineage.

project <- Sys.getenv("ETHIOPIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
out <- file.path(project, "output")
dest <- file.path(out, "reproduced_figures")
dir.create(dest, recursive = TRUE, showWarnings = FALSE)
options(stringsAsFactors = FALSE)
if (!requireNamespace("svglite",quietly=TRUE))
  install.packages("svglite",repos="https://cloud.r-project.org")
png_type <- if (capabilities("aqua")) "quartz" else "cairo"
# Match the palette in Code/04_post_discontinuation_transitions.R and the
# presentation's analytical charts. A state keeps the same color throughout.
navy <- "#153F5B"; teal <- "#108B8D"; amber <- "#DA9A25"
coral <- "#D45A49"; slate <- "#7D8991"; violet <- "#7055A4"
ink <- "#18313E"; pale <- "#E7EFF2"; grid <- "#D8E2E6"

read_output <- function(name) {
  file <- file.path(out, name)
  if (!file.exists(file)) stop("Required analysis output is missing: ", file)
  read.csv(file, check.names = FALSE, stringsAsFactors = FALSE)
}
canvas <- function(name, width=1800, height=900, expr) {
  png(file.path(dest, name), width=width, height=height, res=150, type=png_type)
  par(mar=c(0,0,0,0), family="sans", xaxs="i", yaxs="i")
  plot.new(); plot.window(xlim=c(0,100), ylim=c(0,100), xaxs="i", yaxs="i")
  rect(0,0,100,100,col="white",border=NA)
  force(expr)
  dev.off()
}
label <- function(x,y,s,size=1,col=ink,font=1,adj=c(0,0.5))
  text(x,y,s,cex=size,col=col,font=font,adj=adj)
rule <- function(x0,y0,x1,y1,col=grid,lwd=1) segments(x0,y0,x1,y1,col=col,lwd=lwd)
title <- function(s) label(4,92,s,1.85,navy,2)

# 1. Presentation curve from the same weighted episode life table used in the
#    published Table 7.11 validation. This is any-reason original-method exit.
monthly <- read_output("presentation_discontinuation_monthly.csv")
svglite::svglite(file.path(dest,"presentation_discontinuation_clean_curve.svg"),width=13,height=6.5)
par(mar=c(5,5,3,9),family="sans")
methods <- unique(monthly$method)
palette <- setNames(c(teal,amber,navy,"#22835A",violet,"#516975")[seq_along(methods)],methods)
plot(0,0,type="n",xlim=c(0,12),ylim=c(0,80),xlab="Months of method use",
     ylab="Cumulative probability of discontinuation (%)",axes=FALSE)
axis(1,at=c(0,3,6,9,12));axis(2,at=seq(0,80,20),las=1)
abline(h=seq(0,80,20),col=grid,lwd=.8)
for(m in methods){d<-monthly[monthly$method==m,];lines(d$month,d$cumulative_pct,col=palette[[m]],lwd=3,type="s")}
legend("topright",inset=c(-.36,0),xpd=TRUE,legend=methods,col=palette,lwd=3,bty="n",cex=.9)
box(bty="l",col=grid);dev.off()

# 2. Reason-specific 12-month cumulative incidence. The heights are shares of
#    ALL eligible episodes, not a distribution conditional on discontinuation.
reasons <- read_output("presentation_discontinuation_probability_by_reason.csv")
long <- data.frame(method=rep(reasons$method,4),
 reason=rep(c("Wanted pregnancy","Method experience / access","Partner disapproval","Other"),each=nrow(reasons)),
 value=c(reasons$wanted_pregnancy,reasons$method_experience_or_access,
         reasons$partner_disapproval,reasons$other_reasons))
svglite::svglite(file.path(dest,"presentation_discontinuation_probability_by_reason.svg"),width=12,height=6.5)
par(mar=c(5,12,3,3),family="sans")
mm<-reasons$method; yy<-rev(seq_along(mm));plot(0,0,type="n",xlim=c(0,76),ylim=c(.4,length(mm)+.6),axes=FALSE,
 xlab="",ylab="")
axis(1,at=seq(0,70,10));axis(2,at=yy,labels=mm,las=1,tick=FALSE,cex.axis=.95)
abline(v=seq(0,70,10),col=grid,lwd=.7)
cols<-c("#168C91","#2D7185","#BD749C","#9AA8AE")
for(i in seq_along(mm)){ vals<-as.numeric(reasons[i,c("wanted_pregnancy","method_experience_or_access","partner_disapproval","other_reasons")]);
 left<-0;for(j in seq_along(vals)){if(vals[j]>0)rect(left,yy[i]-.32,left+vals[j],yy[i]+.32,col=cols[j],border=NA);left<-left+vals[j]}
 text(left+1,yy[i],sprintf("%.1f",left),adj=0,cex=.85,font=2,col=navy)}
legend("topright",legend=unique(long$reason),fill=cols,bty="n",cex=.75)
box(bty="l",col=grid);dev.off()

# 3. Regional chart: weighted life-table estimates and survey confidence
#    intervals on the left, recorded first-year reason composition on right.
regional <- read_output("presentation_regional_discontinuation.csv")
profile <- read_output("presentation_regional_reason_profile_aggregate.csv")
regional <- regional[order(-regional$rate),]
canvas("presentation_regional_discontinuation.png",1600,900,{
 title("Regional variation in 12-month modern-method discontinuation")
 label(22,84,"Ending the original method (%)",1.15,navy,2)
 label(65,84,"Reasons among first-year discontinuations (%)",1.15,navy,2)
 reasons4<-c("Wanted to become pregnant","Method experience or access","Husband/partner disapproved","Other")
 y<-seq(76,13,length.out=nrow(regional))
 for(k in seq_along(regional$region)){
  z<-regional[k,]; yy<-y[k];label(4,yy,z$region,1.0,ink,if(k<=2)2 else 1)
  rule(20,yy,45,yy,col="#F1F5F6")
  xx<-function(v)20+(v/70)*25
  rule(xx(z$lo),yy,xx(z$hi),yy,col="#97ADBA",lwd=2)
  points(xx(z$rate),yy,pch=19,col=teal,cex=1.1)
  label(47,yy,sprintf("%.1f",z$rate),.94,navy,2)
  rr<-profile[profile$region==z$region,]
  for(j in seq_along(reasons4)){
   p<-rr$percent[match(reasons4[j],rr$reason)]
   if(length(p)==0||is.na(p))p<-0
   x0<-57+(j-1)*10; rect(x0,yy-2,x0+9.6,yy+2,col=colorRampPalette(c("#EAF4F5",teal))(101)[min(101,1+round(p*1.6))],border="white")
   label(x0+4.8,yy,sprintf("%.1f",p),.78,if(p>35)"white" else ink,2,c(.5,.5))
  }
 }
 for(v in c(0,20,40,60))label(20+v/70*25,9,as.character(v),.82,slate,1,c(.5,.5))
 for(j in seq_along(reasons4))label(57+(j-1)*10+4.8,79.5,c("Pregnancy","Experience / access","Partner","Other")[j],.84,ink,2,c(.5,.5))
 rule(20+38.9/70*25,13,20+38.9/70*25,76,col=teal,lwd=1.5)
 label(20+38.9/70*25,80,"National 38.9",.8,teal,2,c(.5,.5))
})

# 4. Two-stage alluvial. The curved ribbons are drawn from the weighted
#    origin-to-destination flow CSV. The source labels are methods; destination
#    labels are next-month or month-12 states. The same function handles three
#    distinct cohorts and does not relabel them as equivalent.
flow_colors <- c("Injectables"=teal,"Implants"=navy,"Pill"=amber,
 "Emergency contraception"="#B45D83","Other modern methods"="#6C7381",
 "No method"=slate,"Pregnancy/birth/termination"=coral,"Traditional method"=violet)

# Reconstruct the matched follow-up cohorts directly from the derived event
# records and each woman's original calendar. The original calendar position
# minus k denotes k months after the recorded method ending. This replaces
# historical CSVs whose generation code was not saved.
ir_flow<-readRDS(file.path(project,"Data/ET2024DHS__ETIR8ADT__IR_raw.rds"))
events_flow<-readRDS(file.path(project,
  "Data/Derived/ethiopia_2024_post_discontinuation_transitions.rds"))
events_flow<-events_flow[events_flow$calendar_position>=
  as.numeric(ir_flow$v018[events_flow$woman_row])+12L,]
stopifnot(nrow(events_flow)==5118L)
symbol_to_code<-function(z)match(z,strsplit("123456789WNALCFEMS~","")[[1]])
fine_state<-function(z){
 code<-symbol_to_code(z)
 s<-rep("Other/unknown",length(z))
 s[z=="0"]<-"No method"
 s[z%in%c("P","B","T")]<-"Pregnancy/birth/termination"
 s[code%in%c(8L,9L,10L)]<-"Traditional method"
 s[code==3L]<-"Injectables";s[code==11L]<-"Implants";s[code==1L]<-"Pill"
 s[code==16L]<-"Emergency contraception"
 s[code%in%c(2L,5L,6L,7L,13L,17L,18L)]<-"Other modern methods"
 stopifnot(!any(s=="Other/unknown"))
 s
}
for(k in c(1L,3L,12L)){
 pos<-events_flow$calendar_position-k
 char<-mapply(function(i,p)substring(ir_flow$vcal_1[i],p,p),
               events_flow$woman_row,pos,USE.NAMES=FALSE)
 events_flow[[paste0("month",k,"_fine")]]<-fine_state(char)
 events_flow[[paste0("month",k)]]<-ifelse(
   events_flow[[paste0("month",k,"_fine")]]%in%
   c("Injectables","Implants","Pill","Emergency contraception","Other modern methods"),
   "Modern method",events_flow[[paste0("month",k,"_fine")]])
}
make_flows<-function(cohort,when){
 a<-aggregate(cohort$wt,list(origin=cohort$origin,
  destination=cohort[[paste0("month",when,"_fine")]]),sum)
 names(a)[3]<-"weighted_events";a
}
make_paths<-function(cohort){
 a<-aggregate(cohort$wt,list(month1=cohort$month1,
  month3=cohort$month3,month12=cohort$month12),sum)
 names(a)[4]<-"weighted_events"
 a$share_pct<-100*a$weighted_events/sum(a$weighted_events);a
}
exclude_wanted<-events_flow[events_flow$reason_code!=2L,]
# The historical `nonpreg` graphics also excluded method failure (reason 1),
# so retain that exact cohort definition despite the shorthand filename.
nonpreg<-events_flow[!events_flow$reason_code%in%c(1L,2L),]
flow_exclude<-make_flows(exclude_wanted,1L)
flow_nonpreg1<-make_flows(nonpreg,1L)
flow_nonpreg12<-make_flows(nonpreg,12L)
path_exclude<-make_paths(exclude_wanted)
for(pair in list(
 c("post_discontinuation_exclude_wanted_matched_month1_flows.csv","flow_exclude"),
 c("post_discontinuation_nonpreg_matched_month1_flows.csv","flow_nonpreg1"),
 c("post_discontinuation_nonpreg_matched_month12_flows.csv","flow_nonpreg12"),
 c("post_discontinuation_month1_3_12_exclude_wanted_paths.csv","path_exclude"))){
 write.csv(get(pair[2]),file.path(dest,pair[1]),row.names=FALSE)
 old<-read_output(pair[1]);new<-get(pair[2])
 keys<-setdiff(names(new),c("weighted_events","share_pct"))
 # Older flow files may include extra zero cells; compare all nonzero cells.
 old<-old[old$weighted_events>0,];new<-new[new$weighted_events>0,]
 join<-merge(new,old,by=keys,suffixes=c(".new",".old"),all=TRUE)
 stopifnot(!anyNA(join$weighted_events.new),!anyNA(join$weighted_events.old),
           max(abs(join$weighted_events.new-join$weighted_events.old))<1e-6)
}
draw_ribbon <- function(x0,x1,a0,a1,b0,b1,color,alpha=.47){
 t<-seq(0,1,length.out=45);ease<-3*t*t-2*t*t*t
 xx<-x0+(x1-x0)*t;top<-a1+(b1-a1)*ease;bot<-a0+(b0-a0)*ease
 polygon(c(xx,rev(xx)),c(top,rev(bot)),col=adjustcolor(color,alpha.f=alpha),border=NA)
}
two_stage <- function(file,name,heading){
 d<-read.csv(file.path(dest,file),check.names=FALSE)
 names(d)[1:3]<-c("origin","destination","weighted_events")
 origins<-c("Injectables","Implants","Pill","Emergency contraception","Other modern methods")
 destinations<-c(origins,"No method","Pregnancy/birth/termination","Traditional method")
 d<-d[d$origin%in%origins & d$destination%in%destinations,]
 total<-sum(d$weighted_events);os<-tapply(d$weighted_events,d$origin,sum);ds<-tapply(d$weighted_events,d$destination,sum)
 canvas(name,3000,1400,{
 label(27,92,"DISCONTINUED METHOD",1.05,slate,2,c(.5,.5))
 label(72,92,heading,1.05,slate,2,c(.5,.5))
 place<-function(sums,order){n<-length(order);gap<-2.2;usable<-75-gap*(n-1);
   starts<-numeric(n);names(starts)<-order;end<-starts;cur<-84
   for(m in order){h<-usable*ifelse(is.na(sums[m]),0,sums[m])/sum(sums);starts[m]<-cur-h;end[m]<-cur;cur<-starts[m]-gap}
   list(lo=starts,hi=end)}
 a<-place(os,origins);b<-place(ds,destinations)
 apos<-a$lo;bpos<-b$lo
 for(i in seq_len(nrow(d))){r<-d[i,]
   # Gaps leave less vertical room than 75 on each side. Scale each ribbon
   # endpoint to that side's usable area, exactly matching node heights.
   ha<-(75-2.2*(length(origins)-1))*r$weighted_events/total
   hb<-(75-2.2*(length(destinations)-1))*r$weighted_events/total
   ai<-apos[r$origin];bi<-bpos[r$destination]
   draw_ribbon(36,67,ai,ai+ha,bi,bi+hb,flow_colors[[r$destination]],.38)
   apos[r$origin]<-ai+ha;bpos[r$destination]<-bi+hb}
 for(m in origins){rect(33,a$lo[m],36,a$hi[m],col=flow_colors[[m]],border=NA)
   label(31.5,mean(c(a$lo[m],a$hi[m])),sprintf("%s (%.1f%%)",m,100*os[m]/total),.78,ink,2,c(1,.5))}
 for(m in destinations){if(is.na(ds[m])||ds[m]==0)next
   rect(67,b$lo[m],70,b$hi[m],col=flow_colors[[m]],border=NA)
   label(71.2,mean(c(b$lo[m],b$hi[m])),sprintf("%s (%.1f%%)",m,100*ds[m]/total),.78,ink,2)}
 })
}
two_stage("post_discontinuation_exclude_wanted_matched_month1_flows.csv",
 "presentation_exclude_wanted_alluvial_month1_v40.png","STATE ONE MONTH LATER")
two_stage("post_discontinuation_nonpreg_matched_month1_flows.csv",
 "presentation_nonpreg_alluvial_month1_v38.png","STATE ONE MONTH LATER")
two_stage("post_discontinuation_nonpreg_matched_month12_flows.csv",
 "presentation_nonpreg_alluvial_month12_v38.png","STATE 12 MONTHS LATER")

# 5. Linked three-timepoint alluvial. These are the same episodes represented
#    in the exclude-wanted month-one flow above; verify before drawing.
path<-path_exclude
one<-flow_exclude
stopifnot(abs(sum(path$weighted_events)-sum(one$weighted_events))<.01)
states<-c("Modern method","No method","Pregnancy/birth/termination","Traditional method")
state_cols<-c(teal,slate,coral,violet);names(state_cols)<-states
canvas("presentation_month1_3_12_exclude_wanted_slide_v42.png",3200,1500,{
 for(k in 1:3)label(c(15,49,83)[k],93,c("MONTH 1","MONTH 3","MONTH 12")[k],1.3,slate,2,c(.5,.5))
 total<-sum(path$weighted_events);ys<-list()
 for(k in 1:3){s<-tapply(path$weighted_events,path[[k]],sum);cur<-85; lo<-hi<-setNames(numeric(4),states)
  for(st in states){h<-(72-2.2*3)*s[st]/total;lo[st]<-cur-h;hi[st]<-cur;cur<-lo[st]-2.2}
  ys[[k]]<-list(lo=lo,hi=hi,share=s)
 }
 # Keep each month-1/month-3/month-12 path intact across both ribbon spans.
 # The same middle-node slot is used for its incoming and outgoing ribbon.
 path_order<-order(match(path$month3,states),match(path$month1,states),
                  match(path$month12,states))
 spans<-vector("list",3)
 for(k in 1:3){
   cursor<-ys[[k]]$lo
   low<-high<-numeric(nrow(path))
   for(i in path_order){st<-path[[k]][i];h<-(72-2.2*3)*path$weighted_events[i]/total
     low[i]<-cursor[st];high[i]<-cursor[st]+h;cursor[st]<-high[i]}
   spans[[k]]<-list(lo=low,hi=high)
 }
 for(step in 1:2){x0<-c(19,53)[step];x1<-c(44,78)[step]
  for(i in path_order)draw_ribbon(x0,x1,
   spans[[step]]$lo[i],spans[[step]]$hi[i],
   spans[[step+1]]$lo[i],spans[[step+1]]$hi[i],
   state_cols[[path[[step+1]][i]]],.38)
 }
 for(k in 1:3){x<-c(10,44,78)[k];z<-ys[[k]]
  for(st in states){rect(x,z$lo[st],x+9,z$hi[st],col=state_cols[[st]],border=NA)
   pct<-100*z$share[st]/total
   if(st %in% c("Modern method","No method"))
     label(x+4.5,mean(c(z$lo[st],z$hi[st])),sprintf("%s\n%.1f%%",st,pct),.82,"white",2,c(.5,.5))
   else label(x+10.3,mean(c(z$lo[st],z$hi[st])),
              sprintf("%s %.1f%%",if(st=="Traditional method")"Traditional" else "Pregnancy/birth",pct),
              .68,state_cols[[st]],2)
  }
 }
})

# 6. Explanatory slides are ILLUSTRATIONS, not measured trajectory clusters.
#    Encode every label and state run explicitly to keep their construction
#    reproducible without implying that their proportions came from the IR.
canvas("presentation_regional_diagnostic.png",1600,900,{
 title("Explaining regional differences in discontinuation")
 label(8,78,"Question",1.2,navy,2);label(52,78,"Modeling approach",1.2,navy,2)
 q<-c("Is the gap driven by which methods women start,\nor by continuation within each method?",
      "How much of the remaining gap reflects age,\nparity, wealth and other characteristics?",
      "Do service conditions help explain the\nvariation that remains?")
 m<-c("Kitagawa-style decomposition separates\nmethod mix from within-method risk.",
      "Survey-weighted event-history model plus\nnonlinear Oaxaca-Blinder standardization.",
      "Multilevel region and cluster effects, then link\nresidual patterns to service conditions.")
 for(i in 1:3){y<-68-(i-1)*25;rule(4,y+7,96,y+7);label(5,y,sprintf("%02d",i),1.45,teal,2)
  label(11,y,q[i],.84,ink,1);label(52,y,m[i],.84,ink,1)}
})
canvas("presentation_regional_typology.png",1600,900,{
 title("mCPR and discontinuation together define four regional profiles")
 box<-function(x,y,w,h,head,sub,body){rect(x,y,x+w,y+h,col="#F4F8F9",border=grid)
  label(x+2,y+h-6,head,1.02,navy,2);label(x+2,y+h-13,sub,.83,slate)
  label(x+2,y+h-23,body,.79,ink)}
 box(16,51,38,31,"Improve access and retention","Low use, high discontinuation","Expand access and reduce method exits.")
 box(54,51,38,31,"Reduce method loss","High use, high discontinuation","Strengthen choice, switching and follow-up.")
 box(16,20,38,31,"Build demand and access","Low use, low discontinuation","Address barriers to starting modern use.")
 box(54,20,38,31,"Maintain continuity","High use, low discontinuation","Protect services and study what works.")
 text(5,51,"Discontinuation",srt=90,cex=1.14,col=navy,font=2)
 label(14,79,"Higher",.83,slate,2,c(1,.5))
 label(14,23,"Lower",.83,slate,2,c(1,.5))
 label(35,15,"Lower modern use",.84,slate,2,c(.5,.5))
 label(73,15,"Higher modern use",.84,slate,2,c(.5,.5))
 label(54,9,"Modern contraceptive prevalence (mCPR)",1.08,navy,2,c(.5,.5))
})

# Draw 60-month illustrative sequences using explicit state runs. The two
# percentages on the bridge come from the matched, exclude-wanted cohort,
# not from the illustrative example woman. Month-12 no method can be read from
# the three-checkpoint paths; uninterrupted no method requires checking every
# subsequent calendar character from month 1 through month 12.
mono<-function(x,y,states,width=.76,height=4){
 for(i in seq_along(states))rect(x+(i-1)*width,y,x+i*width-.08,y+height,
   col=c("A"=teal,"B"=navy,"N"="#A5B1B8","P"=coral)[states[i]],border=NA)
}
bridge_num<-sum(path$weighted_events[path$month12=="No method"])/sum(path$weighted_events)*100
all_twelve_no<-vapply(seq_len(nrow(exclude_wanted)),function(i){
 pos<-exclude_wanted$calendar_position[i]-seq_len(12L)
 all(substring(ir_flow$vcal_1[exclude_wanted$woman_row[i]],pos,pos)=="0")
},logical(1))
always_no<-100*sum(exclude_wanted$wt[all_twelve_no])/sum(exclude_wanted$wt)
stopifnot(abs(always_no-36.669)<.01)
canvas("presentation_trajectory_bridge_v43.png",1280,720,{
 title("The month-12 endpoint does not reveal the full pathway")
 label(5,73,sprintf("%.1f%%",bridge_num),2.1,navy,2)
 label(5,65,"No method recorded at month 12",.98,ink)
 label(52,73,sprintf("%.1f%%",always_no),2.1,navy,2)
 label(52,65,"No method recorded in every month 1-12",.98,ink)
 label(5,55,"The figures describe the same cohort; the difference signals intervening states.",.86,slate)
 rule(5,50,95,50)
 label(5,43,"A five-year calendar shows the sequence around each event",1.23,navy,2)
 mono(22,33,c(rep("N",6),rep("A",17),rep("N",3),rep("B",15),rep("P",9),rep("N",5),rep("A",5)),.95,4.5)
 label(5,35,"Illustrative woman",.9,ink,2)
 label(5,22,"A woman-level view identifies sustained use, switching, brief gaps and repeated stops.",1.08,navy,2)
 label(5,13,"Estimate how common each pattern is and where it concentrates.",1.05,navy,2)
})
canvas("presentation_trajectory_profiles_v43.png",1280,720,{
 title("Six candidate trajectories across five years")
 label(4,84,"Illustrative monthly patterns; cluster sizes have not been estimated",.88,slate)
 profiles<-list(
  c(rep("A",60)),c(rep("A",24),rep("B",36)),
  c(rep("A",20),rep("N",4),rep("B",36)),
  c(rep("A",14),rep("N",5),rep("B",14),rep("N",5),rep("A",12),rep("B",10)),
  c(rep("A",12),rep("N",48)),c(rep("N",25),rep("P",9),rep("N",25),"A"))
 nm<-c("Stable modern use","Switch with continuity","Brief gap and return",
       "Repeated churn","Early exit","Predominant nonuse")
 sub<-c("Continued protection","Method changes without a gap",
        "Short interruption, then modern use","Several stops and restarts",
        "Long period without a method","Little modern-method exposure")
 for(j in 1:5)label(25+(j-.5)*12.6,81,paste("YEAR",j),.74,slate,2,c(.5,.5))
 for(i in 1:6){y<-74-(i-1)*11;label(4,y+2.8,nm[i],.84,ink,2)
  label(4,y-.7,sub[i],.66,slate);mono(25,y,profiles[[i]],1.05,5)}
 for(j in 1:4){x<-25+(j-1)*17;rect(x,7,x+1.2,9,col=c(teal,navy,"#A5B1B8",coral)[j],border=NA)
  label(x+1.6,8,c("Modern A","Modern B","No method","Pregnancy / birth")[j],.66,slate)}
 label(4,3,"Illustrative candidate profiles; classify women using a common observed calendar window.",.68,slate)
})

# 7. mCPR explanation panels. The scale figure reads measured survey mCPR and
#    the standardized current-user pathway CSV; the other panels contain
#    explicit explanatory categories, not estimated counts.
canvas("presentation_mcpr_entry_retention_v46.png",1441,810,{
 title("Sustained mCPR growth depends on entry and retention")
 rule(4,84,96,84)
 label(5,75,"WOMEN EXPOSED TO FUTURE EXIT",.9,slate,2)
 label(53,75,"YEAR-END STATUS",.9,slate,2)
 label(6,65,"Current modern users",1.25,navy,2)
 label(6,59,"Already in the modern-user stock",.92,slate)
 label(6,48,"New and returning users",1.25,teal,2)
 label(6,42,"Enter modern use during the year",.92,slate)
 label(54,65,"Still using a modern method",1.25,navy,2)
 label(54,59,"Continuation, modern switch or re-entry",.9,ink)
 label(54,48,"Outside modern use",1.25,coral,2)
 label(54,42,"Exit without re-entry by year end",.9,ink)
 arrows(37,58,50,58,length=.12,col=teal,lwd=1.6)
 rule(4,34,96,34)
 label(5,26,"Ending an original method does not always remove a woman from mCPR.",1.1,navy,2)
 label(5,18,"A modern-to-modern switch remains in the numerator.",.94,ink)
 label(5,9,"Respect pregnancy intentions; focus support on unwanted gaps in modern use.",1.0,teal,2)
})
sp<-read_output("standardized_current_user_pathway_summary.csv")
get<-function(s)sp$pct[match(s,sp$stage)]
wt_flow<-as.numeric(ir_flow$v005)/1e6
modern_interview_codes<-c(1L,2L,3L,5L,6L,7L,11L,13L,14L,16L,17L,18L)
mcpr<-round(100*sum(wt_flow[as.numeric(ir_flow$v312)%in%modern_interview_codes])/
              sum(wt_flow),1)
stopifnot(mcpr==22.7)
per_million<-1e6*mcpr/100
canvas("presentation_mcpr_current_user_scale_v46.png",1441,810,{
 title("Scaling current-user pathways to women of reproductive age")
 label(5,77,"ETHIOPIA 2024–25 SURVEY BASELINE",.9,slate,2)
 label(5,65,sprintf("%.1f%%",mcpr),2.4,navy,2)
 label(30,65,"mCPR among women 15–49",1.16,ink)
 label(5,56,sprintf("≈%s modern users per 1 million women",format(round(per_million),big.mark=",")),1.25,navy,2)
 rule(5,49,95,49)
 label(5,42,"STANDARDIZED 12-MONTH PATHWAY FOR CURRENT USERS",.9,slate,2)
 vals<-c(get("No gross exit"),get("Re-entered modern use by month 12"),get("Net absent from modern use at month 12"))
 cols<-c(teal,amber,coral);left<-5
 for(j in 1:3){right<-left+90*vals[j]/100;rect(left,29,right,37,col=cols[j],border=NA)
  label((left+right)/2,33,sprintf("%.1f%%",vals[j]),.9,"white",2,c(.5,.5));left<-right}
 labs<-c("No gross exit","Exited then returned","Outside modern use at month 12")
 for(j in 1:3){x<-c(5,36,68)[j];label(x,20,sprintf("≈%s",format(round(per_million*vals[j]/100,-3),big.mark=",")),1.05,cols[j],2)
  label(x,13,labs[j],.8,ink)}
 label(5,6,"Planning scenario per million WRA; new entrants and population change are not included.",.76,slate)
})
canvas("presentation_mcpr_method_reason_v46.png",1441,810,{
 title("Estimate modern-use exits by method and reason")
 label(5,78,"BY ORIGINATING METHOD",.94,slate,2)
 label(53,78,"BY STATED REASON",.94,slate,2)
 for(i in 1:5){y<-69-(i-1)*9;rule(5,y-4,47,y-4)
  label(5,y,c("Injectables","Implants","Pill","IUD","Other modern methods")[i],1.03,navy,2)}
 label(53,69,"POTENTIALLY ADDRESSABLE (ASSESS INDIVIDUALLY)",.80,teal,2)
 rr<-c("Side effects / health","Access / cost / convenience",
       "Wanted a more effective method","Method failure / pregnancy while using")
 for(i in 1:4)label(54,62-(i-1)*6,rr[i],.84,ink)
 rule(53,41,96,41)
 label(53,37,"CONTEXT TO ASSESS",.80,amber,2)
 label(54,31,"Husband/partner disapproved",.84,ink)
 label(54,26,"Other reasons",.84,ink)
 rule(53,22,96,22)
 label(53,18,"PREFERENCE TO RESPECT",.80,coral,2)
 label(54,13,"Wanted to become pregnant",.84,ink)
 label(5,19,"Show exits and year-end nonuse for each method.",.78,ink)
 rule(4,10,96,10)
 label(5,5,"Report counts by method, reason, cohort and timing.",.86,navy,2)
})

# 8. Appendix tables. Recalculate from the interview-date current-method
#    distribution and the method-specific competing-risk life table. The
#    population denominator is an explicit external 2025 WRA input documented
#    in ethiopia_current_user_discontinuation_planning.html (UN/WDI age shares).
#    Applying first-year episode risk to prevalent users is a PLANNING
#    ASSUMPTION, not an estimate of their actual prospective risk.
wra_input<-read.csv(file.path(project,"Data/ethiopia_2025_wra_planning_input.csv"))
stopifnot(nrow(wra_input)==1L,wra_input$country=="Ethiopia",wra_input$year==2025L)
wra_2025<-wra_input$women_15_49[1]
ir <- readRDS(file.path(project,"Data/ET2024DHS__ETIR8ADT__IR_raw.rds"))
wt <- as.numeric(ir$v005)/1e6
code <- as.numeric(ir$v312)
modern_codes <- c(1L,2L,3L,5L,6L,7L,11L,13L,14L,16L,17L,18L)
mcpr_unrounded <- sum(wt[code %in% modern_codes])/sum(wt)
method <- ifelse(code==3L,"Injectables",ifelse(code==11L,"Implants",
          ifelse(code==1L,"Pill",ifelse(code==2L,"IUD",
          ifelse(code==16L,"EC",ifelse(code%in%modern_codes,
                 "Other modern methods",NA_character_))))))
method_order <- c("Injectables","Implants","Pill","IUD","EC","Other modern methods")
method_wt <- vapply(method_order,function(m)sum(wt[method==m],na.rm=TRUE),numeric(1))
mix <- round(100*method_wt/sum(method_wt),4)
episodes <- readRDS(file.path(project,
  "Data/Derived/ethiopia_2024_table_7_11_episodes.rds"))
episode_codes <- list("Injectables"=3L,"Implants"=11L,"Pill"=1L,"IUD"=2L,
                      "Other modern methods"=c(5L,6L,7L,13L,17L,18L))
life_probs <- function(e){
  survival<-1; incidence<-numeric(9)
  for(month in 1:12){
    at_risk<-e$entry<month & e$exposure>=month
    risk<-sum(e$wt[at_risk])
    if(risk<=0)next
    ended<-at_risk & e$exposure==month & e$discontinued
    causes<-vapply(1:9,function(k)sum(e$wt[ended & e$reason==k]),numeric(1))
    incidence<-incidence+survival*causes/risk
    survival<-survival*(1-sum(causes)/risk)
  }
  100*incidence
}
life<-lapply(episode_codes,function(codes)
  life_probs(episodes[episodes$method_code %in% codes,]))
method_tab <- data.frame(method=method_order,current_mix_pct=unname(mix),
  current_users=wra_2025*mcpr_unrounded*unname(mix)/100,
  initiation_based_d12_pct=NA_real_,planning_discontinuations=NA_real_)
for(i in seq_len(nrow(method_tab))){
  if(method_tab$method[i]=="EC")next
  p<-life[[method_tab$method[i]]]
  method_tab$initiation_based_d12_pct[i]<-sum(p)
  method_tab$planning_discontinuations[i]<-method_tab$current_users[i]*sum(p)/100
}
stopifnot(abs(mcpr_unrounded-.2272869)<.00001,
          abs(sum(method_tab$current_users)-7740836)<3)

# Seven reason groups used on the appendix slide. The life-table increments
# are cause-specific cumulative incidences, so their sum equals all-cause
# discontinuation within each method before rounding.
reason_names <- c("Wanted to become pregnant","Wanted a more effective method",
 "Other","Side effects / health","Access / cost / convenience",
 "Method failure / pregnancy while using","Husband/partner disapproved")
method_reason <- do.call(rbind,lapply(seq_len(nrow(method_tab)),function(i){
  m<-method_tab$method[i]
  if(m=="EC")return(NULL)
  z<-life[[m]]
  p<-c(z[2],z[6],z[3]+z[9],z[4]+z[5],z[7],z[1],z[8])
  stopifnot(abs(sum(p)-sum(z))<1e-6)
  data.frame(method=m,reason=reason_names,current_users=method_tab$current_users[i],
             cause_specific_d12_pct=p,
             planning_discontinuations=method_tab$current_users[i]*p/100)
}))
# Preserve the nine original Table 7.11 cause groups for method-level planning
# tables. Aggregating them into seven slide groups would conceal bleeding and
# other fertility-related reasons, which are essential to the requested cut.
detailed_reason_names <- c("Method failure / pregnancy while using",
 "Wanted to become pregnant","Other fertility-related reasons",
 "Changes in menstrual bleeding","Other side effects / health concerns",
 "Wanted a more effective method","Access / cost / inconvenience",
 "Husband/partner disapproved","Other recorded reasons")
method_reason_detailed <- do.call(rbind,lapply(seq_len(nrow(method_tab)),function(i){
  m<-method_tab$method[i]
  if(m=="EC")return(NULL)
  p<-life[[m]]
  data.frame(method=m,reason=detailed_reason_names,
    current_users=method_tab$current_users[i],
    cause_specific_d12_pct=p,
    planning_discontinuations=method_tab$current_users[i]*p/100)
}))
stopifnot(abs(sum(method_reason_detailed$planning_discontinuations)-
              sum(method_tab$planning_discontinuations,na.rm=TRUE))<.01)
reason_tab<-aggregate(planning_discontinuations~reason,method_reason,sum)
reason_tab$share_of_planning_total_pct<-100*reason_tab$planning_discontinuations/
  sum(reason_tab$planning_discontinuations)
reason_tab<-reason_tab[match(reason_names,reason_tab$reason),]
stopifnot(abs(sum(method_tab$planning_discontinuations,na.rm=TRUE)-
              sum(reason_tab$planning_discontinuations))<.01)
write.csv(method_tab,file.path(dest,"slide_24_method_planning_table.csv"),row.names=FALSE)
write.csv(reason_tab,file.path(dest,"slide_26_reason_planning_table.csv"),row.names=FALSE)
write.csv(method_reason,file.path(dest,"slide_26_method_by_reason_calculation.csv"),row.names=FALSE)
write.csv(method_reason_detailed,file.path(dest,"method_by_nine_reasons_planning_table.csv"),row.names=FALSE)
write.csv(read_output("reason_mix_by_method_all_discontinued.csv"),
          file.path(dest,"slide_25_reasons_by_method_table.csv"),row.names=FALSE)
figure_files<-sort(list.files(dest,pattern="\\.(png|svg)$"))
table_files<-sort(list.files(dest,pattern="\\.csv$"))
preview<-c('<!doctype html><html lang="en"><meta charset="utf-8">',
 '<title>Rebuilt Ethiopia presentation figures and tables</title>',
 '<style>body{font:17px/1.45 system-ui,sans-serif;color:#26323c;max-width:1200px;margin:2rem auto;padding:0 1rem}h1,h2{color:#173f5b}figure{margin:2rem 0;border-top:1px solid #d8e2e6;padding-top:1rem}img{max-width:100%;height:auto}figcaption{font-weight:650;margin-bottom:.7rem}a{color:#118f92}</style>',
 '<h1>Rebuilt presentation figures and tables</h1>',
 '<p>Generated by Code/49_rebuild_presentation_figures_tables.R from the Ethiopia DHS calendar, derived life-table files and documented external WRA input. These review copies do not alter the deck or working HTML.</p>',
 '<h2>Figures</h2>')
for(f in figure_files)preview<-c(preview,sprintf('<figure><figcaption>%s</figcaption><img src="%s" alt="Rebuilt figure"></figure>',f,f))
preview<-c(preview,'<h2>Tables and calculation files</h2><ul>',
  sprintf('<li><a href="%s">%s</a></li>',table_files,table_files),'</ul></html>')
writeLines(preview,file.path(dest,"index.html"))
cat("Rebuilt 14 figure assets and appendix calculations in",dest,"\n")
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 51_duration_adjusted_reason_projection.R
# LANGUAGE: R
MODULES[["51_duration_adjusted_reason_projection.R"]] <- list(
 language="R",
 packaged_sha256="c945cd4be5e54b072a5b6c6d057a48d5a222030a90c482855c8885bf3752bd5d",
 args=character(),
 code=r"-----(#!/usr/bin/env Rscript
# Ethiopia DHS 2024-25: exploratory next-12-month original-method endings by
# reason among women currently using a modern method (emergency contraception
# excluded). This is a landmark standardization, not a first-year life table.
#
# Data lineage:
#   - Read original IR .rds, produced from the ETIR8ADT .dta file by the
#     documented import pipeline. No package installation is required here.
#   - Read the historical current-user landmark cohort created in Code/06:
#     one woman using a modern method 15 months before interview, with all
#     subsequent 12 months observable in the contraceptive calendar.
#   - Read complete modern-method endings and recorded calendar reasons from
#     Code/04. A recorded end of the original method is counted even when a
#     woman immediately switches to another modern method.
#   - Use current method (v312), current duration (v337), and sample weight
#     (v005) to standardize historical 12-month reason probabilities to the
#     interview-date current-user stock. The WRA denominator and current-user
#     method counts come from Code/49's frozen planning inputs.
#
# Wanted pregnancy and partner disapproval are competing endings. They stay
# in the baseline denominator and are omitted only from the selected outcome.
# To avoid unsupported fine-duration cells for IUD/other modern methods, this
# first-pass analysis uses two prespecified duration groups: 0-12 and 13+
# months. It reports raw historical cell sizes and events for precision review.

project <- Sys.getenv("ETHIOPIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
out <- file.path(project, "output")
support <- file.path(out, "Supporting_data")
ir <- readRDS(file.path(project,"Data/ET2024DHS__ETIR8ADT__IR_raw.rds"))
historical <- readRDS(file.path(project,"Data/Derived/ethiopia_2024_current_user_pathway.rds"))
ends <- readRDS(file.path(project,"Data/Derived/ethiopia_2024_post_discontinuation_transitions.rds"))
method_tab <- read.csv(file.path(out,"reproduced_figures/slide_24_method_planning_table.csv"))
comparison <- read.csv(file.path(support,"12_month_three_column_comparison.csv"),check.names=FALSE)

method_name <- function(code) {
  ifelse(code==3L,"Injectables",ifelse(code==11L,"Implants",
  ifelse(code==1L,"Pill",ifelse(code==2L,"IUD",
  ifelse(code==16L,"EC",ifelse(code%in%c(5L,6L,7L,13L,14L,17L,18L),
         "Other modern methods",NA_character_))))))
}
method_levels <- c("Injectables","Implants","Pill","IUD","Other modern methods")
duration_group <- function(months) ifelse(months<=12L,"0-12 months","13+ months")
duration_levels <- c("0-12 months","13+ months")
reason_levels <- c("Method failure / pregnancy while using",
 "Wanted to become pregnant","Other fertility-related reasons",
 "Changes in menstrual bleeding","Other side effects / health concerns",
 "Wanted a more effective method","Access / cost / inconvenience",
 "Husband/partner disapproved","Other recorded reasons")
reason_group <- function(code) {
  if(is.na(code))return(9L)
  if(code==1L)return(1L)
  if(code==2L)return(2L)
  if(code%in%c(11L,12L,13L))return(3L)
  if(code==5L)return(4L)
  if(code==6L)return(5L)
  if(code==4L)return(6L)
  if(code%in%c(7L,8L,9L))return(7L)
  if(code==3L)return(8L)
  9L
}

# Recover the reason character if an original-method ending is visible in
# vcal_1 but absent from the prebuilt transition file. Blank/unknown reason
# remains in Other recorded reasons; do not infer a substantive cause.
reason_char_map <- c("1"=1L,"2"=2L,"3"=3L,"7"=4L,"M"=5L,"4"=6L,
 "6"=7L,"C"=8L,"8"=9L,"F"=10L,"A"=11L,"9"=12L,
 "D"=13L,"W"=14L,"K"=15L)
v018 <- as.integer(ir$v018)
by_woman <- split(ends,as.character(ends$woman_row))
historical$method <- method_name(historical$baseline_code)
historical <- historical[historical$method%in%method_levels,]
historical$duration <- NA_integer_
historical$reason9 <- NA_integer_ # NA means still using original method at 12 months
historical$reason_source <- "No ending"

for(j in seq_len(nrow(historical))){
  w <- historical$woman_row[j]
  p <- v018[w]+15L
  original_char <- substring(ir$vcal_1[w],p,p)
  d <- 1L
  while(p+d<=80L && substring(ir$vcal_1[w],p+d,p+d)==original_char)d<-d+1L
  historical$duration[j] <- d
  # Find the first calendar month when the original method has changed.
  future_positions <- p-seq_len(12L)
  future_chars <- substring(ir$vcal_1[w],future_positions,future_positions)
  changed <- which(future_chars!=original_char)
  direct_end <- if(length(changed))p-changed[1L]+1L else -Inf
  # A recorded same-method stop/restart also ends the original episode.
  z <- by_woman[[as.character(w)]]
  if(!is.null(z)){
    z <- z[z$origin_code==historical$baseline_code[j] &
           z$calendar_position<=p & z$calendar_position>=p-11L,]
  }
  if(!is.null(z) && nrow(z) && max(z$calendar_position)>=direct_end){
    first <- z[which.max(z$calendar_position),]
    historical$reason9[j] <- reason_group(first$reason_code)
    historical$reason_source[j] <- "Recorded transition"
  } else if(is.finite(direct_end)) {
    ch <- substring(ir$vcal_2[w],direct_end,direct_end)
    code <- unname(reason_char_map[ch])
    historical$reason9[j] <- reason_group(code)
    historical$reason_source[j] <- if(is.na(code))"Calendar change, reason missing" else "Calendar change, reason recorded"
  }
}
historical$duration_group <- duration_group(historical$duration)
stopifnot(!anyNA(historical$duration_group),all(historical$reason9[!is.na(historical$reason9)]%in%1:9))

# Interview-date current stock. Every ongoing-method user in these five groups
# has a valid current duration in v337. Use within-method duration shares, so
# the population counts reproduce Code/49's method totals exactly.
code <- as.integer(ir$v312)
current <- data.frame(method=method_name(code),duration=as.integer(ir$v337),
                      wt=as.numeric(ir$v005)/1e6)
current <- current[current$method%in%method_levels,]
stopifnot(nrow(current)==4104L,!anyNA(current$duration),all(current$duration<997))
current$duration_group <- duration_group(current$duration)

current_cells <- aggregate(wt~method+duration_group,current,sum)
current_n <- aggregate(rep(1,nrow(current)),by=current[c("method","duration_group")],FUN=sum)
names(current_n)[3] <- "current_unweighted_users"
current_cells <- merge(current_cells,current_n,by=c("method","duration_group"))
method_weights <- aggregate(wt~method,current_cells,sum)
names(method_weights)[2] <- "method_weight"
current_cells <- merge(current_cells,method_weights,by="method")
current_cells$current_duration_share <- current_cells$wt/current_cells$method_weight

# Direct reason-specific next-12-month probabilities within each historical
# method-duration landmark cell. A wanted-pregnancy or partner ending counts
# as a competing outcome in the denominator, never as a selected event.
historical_cells <- do.call(rbind,lapply(method_levels,function(m)
  do.call(rbind,lapply(duration_levels,function(g){
    h <- historical[historical$method==m & historical$duration_group==g,]
    den <- sum(h$wt)
    data.frame(method=m,duration_group=g,reason=reason_levels,
      historical_unweighted_users=nrow(h),historical_weighted_users=den,
      unweighted_events=vapply(1:9,function(k)sum(h$reason9==k,na.rm=TRUE),integer(1)),
      probability=vapply(1:9,function(k)sum(h$wt[h$reason9==k],na.rm=TRUE)/den,numeric(1)))
  }))))
stopifnot(all(historical_cells$historical_unweighted_users>=20L),
          all(historical_cells$probability>=0),
          all(aggregate(probability~method+duration_group,historical_cells,sum)$probability<=1+1e-10))

standardized <- merge(historical_cells,current_cells[c("method","duration_group",
 "current_duration_share","current_unweighted_users")],by=c("method","duration_group"))
standardized$contribution <- standardized$current_duration_share*standardized$probability
standardized <- merge(standardized,method_tab[c("method","current_users")],by="method")
standardized$planning_users <- standardized$current_users*standardized$contribution
method_reason <- aggregate(cbind(contribution,planning_users)~method+reason,standardized,sum)
method_reason$probability_pct <- 100*method_reason$contribution
names(method_reason)[names(method_reason)=="planning_users"] <- "illustrative_users"
method_reason$contribution <- NULL
method_reason <- method_reason[order(match(method_reason$method,method_levels),
                                     match(method_reason$reason,reason_levels)),]
method_reason$retained <- !method_reason$reason%in%
 c("Wanted to become pregnant","Husband/partner disapproved")

method_summary <- do.call(rbind,lapply(method_levels,function(m){
  q <- method_reason[method_reason$method==m & method_reason$retained,]
  z <- method_tab[method_tab$method==m,]
  data.frame(method=m,current_users=z$current_users,
    selected_reason_probability_pct=sum(q$probability_pct),
    illustrative_endings=sum(q$illustrative_users),
    historical_unweighted_users=sum(historical$method==m),
    current_unweighted_users=sum(current$method==m))
}))
all_current <- sum(method_summary$current_users)
all_endings <- sum(method_summary$illustrative_endings)
combined <- aggregate(illustrative_users~reason,method_reason,sum)
combined$probability_pct <- combined$illustrative_users/all_current*100
combined$retained <- !combined$reason%in%
 c("Wanted to become pregnant","Husband/partner disapproved")
combined <- combined[match(reason_levels,combined$reason),]
stopifnot(abs(sum(combined$illustrative_users[combined$retained])-all_endings)<.01)

write.csv(current_cells,file.path(support,"duration_adjusted_current_method_duration_cells.csv"),row.names=FALSE)
write.csv(historical_cells,file.path(support,"duration_adjusted_historical_reason_cells.csv"),row.names=FALSE)
write.csv(standardized,file.path(support,"duration_adjusted_reason_standardization.csv"),row.names=FALSE)
write.csv(method_reason,file.path(support,"duration_adjusted_method_reason.csv"),row.names=FALSE)
write.csv(method_summary,file.path(support,"duration_adjusted_method_summary.csv"),row.names=FALSE)
write.csv(combined,file.path(support,"duration_adjusted_all_modern_reason.csv"),row.names=FALSE)
cat("Historical landmark users:",nrow(historical),"; current users:",nrow(current),"\n")
print(table(historical$method,historical$duration_group))
print(table(historical$reason_source))
print(method_summary,row.names=FALSE)
cat("Combined selected-reason probability:",100*all_endings/all_current,"percent\n")
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 53_descriptive_selected_reason_subgroups.R
# LANGUAGE: R
MODULES[["53_descriptive_selected_reason_subgroups.R"]] <- list(
 language="R",
 packaged_sha256="7303a78804bfd3a98b26bb547eac6d808dee0fd3daad633bf398637367e4775d",
 args=character(),
 code=r"-----(
# Full DHS sampling frame, including PSUs with no eligible outcome records.
full_survey_frame <- function(){
 r<-Sys.getenv('ETHIOPIA_PROJECT_ROOT'); stopifnot(nzchar(r))
 x<-readRDS(file.path(r,'Data/ET2024DHS__ETIR8ADT__IR_raw.rds'))
 unique(data.frame(cluster=paste(as.integer(x$v022),as.integer(x$v021),sep=':'),stratum=as.integer(x$v022)))
}
complete_survey_data <- function(d){
 r<-Sys.getenv('ETHIOPIA_PROJECT_ROOT');x<-readRDS(file.path(r,'Data/ET2024DHS__ETIR8ADT__IR_raw.rds'))
 f<-unique(data.frame(v021=as.integer(x$v021),v022=as.integer(x$v022)))
 key<-function(a,b)paste(a,b,sep=':');miss<-f[!key(f$v021,f$v022)%in%key(d$v021,d$v022),]
 if(nrow(miss)){z<-d[rep(1L,nrow(miss)),,drop=FALSE];z$v021<-miss$v021;z$v022<-miss$v022;z$wt<-0;d<-rbind(d,z)}
 d
}
#!/usr/bin/env Rscript
# Exploratory 12-month selected-reason discontinuation life tables by subgroup.
# The outcome is ending an original modern method for any recorded reason
# except wanted pregnancy or husband/partner disapproval. Those two endings
# remain competing events in each monthly risk set. EC is excluded.
#
# Start with the validated episode-level .rds reconstructed from the IR
# calendar. Link the woman-level IR file with woman_row. Compute age and live
# birth parity at episode start. Marital status, education, wealth and
# residence are observed at interview, possibly after an episode ended; their
# descriptive associations are therefore not historical causal exposures.
# Output one-way design-bootstrap intervals and screened two-way estimates.

project <- Sys.getenv("ETHIOPIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
out <- file.path(project,"output","Supporting_data")
e <- readRDS(file.path(project,"Data/Derived/ethiopia_2024_table_7_11_episodes.rds"))
ir <- readRDS(file.path(project,"Data/ET2024DHS__ETIR8ADT__IR_raw.rds"))
e <- e[e$method_code%in%c(1L,2L,3L,5L,6L,7L,11L,13L,17L,18L),]
i <- e$woman_row
age <- floor((e$start-as.integer(ir$v011[i]))/12)
birth_cols <- grep("^b3_",names(ir),value=TRUE)
births <- as.matrix(ir[i,birth_cols])
parity <- rowSums(!is.na(births) & births<=e$start)
marital <- as.integer(ir$v501[i])
education <- as.integer(ir$v106[i])
wealth <- as.integer(ir$v190[i])
residence <- as.integer(ir$v025[i])
region <- as.integer(ir$v024[i])
psu <- as.integer(ir$v021[i])
stratum <- as.integer(ir$v022[i])
complete <- !is.na(age)&age>=15&age<=49&!is.na(parity)&
  !is.na(marital)&marital%in%0:5&
  !is.na(education)&education%in%0:3&
  !is.na(wealth)&wealth%in%1:5&
  !is.na(residence)&residence%in%1:2&
  !is.na(region)&!is.na(psu)&!is.na(stratum)
e <- e[complete,]
age <- age[complete];parity <- parity[complete];marital <- marital[complete]
education <- education[complete];wealth <- wealth[complete]
residence <- residence[complete];region <- region[complete]
psu <- psu[complete];stratum <- stratum[complete]
stopifnot(nrow(e)==8611L)

e$method_group <- factor(ifelse(e$method_code==3L,"Injectables",
  ifelse(e$method_code==11L,"Implants",ifelse(e$method_code==1L,"Pill",
  ifelse(e$method_code==2L,"IUD","Other modern")))),
  levels=c("Injectables","Implants","Pill","IUD","Other modern"))
e$age_group <- cut(age,c(14,19,24,34,49),labels=c("15-19","20-24","25-34","35-49"))
e$parity_group <- factor(ifelse(parity==0,"0",ifelse(parity<=2,"1-2",
  ifelse(parity==3,"3","4+"))),levels=c("0","1-2","3","4+"))
e$marital_group <- factor(ifelse(marital==0,"Never in union",
  ifelse(marital%in%c(1L,2L),"Married/living together","Formerly in union")),
  levels=c("Never in union","Married/living together","Formerly in union"))
e$education <- factor(ifelse(education==0,"None",ifelse(education==1,"Primary","Secondary+")),
  levels=c("None","Primary","Secondary+"))
e$wealth_group <- factor(ifelse(wealth<=2,"Poorest 40%",ifelse(wealth==3,"Middle 20%","Richest 40%")),
  levels=c("Poorest 40%","Middle 20%","Richest 40%"))
e$residence <- factor(ifelse(residence==1,"Urban","Rural"),levels=c("Rural","Urban"))
e$cluster <- paste(stratum,psu,sep=":")
e$stratum <- stratum
e$selected_event <- e$discontinued & !(e$reason%in%c(2L,8L)) &
  e$exposure<=12L & e$entry<e$exposure

life <- function(d,weights=d$wt){
  survival <- 1;incidence <- 0
  if(!nrow(d)||sum(weights)<=0)return(NA_real_)
  for(t in 1:12){
    risk <- d$entry<t & d$exposure>=t
    den <- sum(weights[risk])
    if(den<=0)return(NA_real_)
    ending <- risk & d$discontinued & d$exposure==t
    selected <- ending & !(d$reason%in%c(2L,8L))
    incidence <- incidence+survival*sum(weights[selected])/den
    survival <- survival*(1-sum(weights[ending])/den)
  }
  100*incidence
}

one_variables <- c("age_group","parity_group","marital_group","education",
                   "wealth_group","residence","method_group")
one <- do.call(rbind,lapply(one_variables,function(variable)
  do.call(rbind,lapply(levels(e[[variable]]),function(level){
    z <- e[e[[variable]]==level,]
    data.frame(characteristic=variable,level=level,
      eligible_episodes=nrow(z),weighted_episodes=sum(z$wt),
      selected_endings=sum(z$selected_event),
      unadjusted_12_month_probability_pct=life(z))
  }))))
rownames(one)<-NULL

# Stratified rescaled PSU bootstrap: every episode of each woman in a PSU
# receives the same replicate multiplier. The bootstrap preserves the DHS
# clustering and permits repeated episodes without treating them as unrelated.
reps <- as.integer(Sys.getenv("DESCRIPTIVE_BOOTSTRAP_REPS","300"))
if(reps<100L)stop("Use at least 100 bootstrap replicates")
frame <- full_survey_frame()
by_stratum <- split(frame$cluster,frame$stratum)
stopifnot(all(lengths(by_stratum)>1L))
keys <- paste(one$characteristic,one$level,sep="::")
boot <- matrix(NA_real_,nrow=reps,ncol=nrow(one),dimnames=list(NULL,keys))
for(b in seq_len(reps)){
  set.seed(20261005L+b)
  multiplier <- setNames(numeric(nrow(frame)),frame$cluster)
  for(ids in by_stratum){
    n <- length(ids);draw <- sample.int(n,n-1L,replace=TRUE)
    multiplier[ids] <- n/(n-1L)*tabulate(draw,nbins=n)
  }
  w <- e$wt*multiplier[e$cluster]
  for(j in seq_len(nrow(one))){
    index <- e[[one$characteristic[j]]]==one$level[j]
    boot[b,j] <- life(e[index,],w[index])
  }
}
one$ci_low <- vapply(seq_len(ncol(boot)),function(j)
  unname(quantile(boot[,j],.025,na.rm=TRUE)),numeric(1))
one$ci_high <- vapply(seq_len(ncol(boot)),function(j)
  unname(quantile(boot[,j],.975,na.rm=TRUE)),numeric(1))
one$valid_bootstrap_reps <- colSums(!is.na(boot))
stopifnot(all(one$valid_bootstrap_reps>=.95*reps))

# Two-way exploration. Keep all combinations in the file but mark cells that
# fail a prespecified screen (<100 eligible episodes or <20 selected endings).
# These are point estimates only; they are not adjusted effects or formal
# interaction tests. The screen avoids ranking tiny cells as top populations.
combos <- list(c("age_group","parity_group"),c("age_group","method_group"),
               c("parity_group","method_group"))
two <- do.call(rbind,lapply(combos,function(v){
  grid <- expand.grid(level_1=levels(e[[v[1]]]),level_2=levels(e[[v[2]]]),
                      stringsAsFactors=FALSE)
  do.call(rbind,lapply(seq_len(nrow(grid)),function(j){
    a<-grid$level_1[j];b<-grid$level_2[j]
    z<-e[e[[v[1]]]==a & e[[v[2]]]==b,]
    n_event<-sum(z$selected_event)
    display <- nrow(z)>=100L && n_event>=20L
    data.frame(characteristic_1=v[1],level_1=a,
      characteristic_2=v[2],level_2=b,
      eligible_episodes=nrow(z),weighted_episodes=sum(z$wt),
      selected_endings=n_event,
      meets_display_threshold=display,
      unadjusted_12_month_probability_pct=if(display)life(z)else NA_real_)
  }))
}))

write.csv(e,file.path(out,"selected_reason_exploratory_episode_covariates.csv"),row.names=FALSE)
write.csv(one,file.path(out,"selected_reason_descriptive_one_way.csv"),row.names=FALSE)
write.csv(two,file.path(out,"selected_reason_descriptive_two_way.csv"),row.names=FALSE)
write.csv(data.frame(eligible_episodes=nrow(e),weighted_episodes=sum(e$wt),
  selected_endings=sum(e$selected_event),overall_12_month_probability_pct=life(e),
  bootstrap_reps=reps),file.path(out,"selected_reason_descriptive_audit.csv"),row.names=FALSE)
cat("Eligible episodes:",nrow(e),"; selected first-year endings:",sum(e$selected_event),"\n")
cat("Overall selected-reason 12-month probability:",round(life(e),2),"percent\n")
cat("Two-way cells retained:",sum(two$meets_display_threshold),"of",nrow(two),"\n")
print(one,row.names=FALSE)
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 54_extended_selected_reason_regression.R
# LANGUAGE: R
MODULES[["54_extended_selected_reason_regression.R"]] <- list(
 language="R",
 packaged_sha256="30d7f80d7013cda73fba6314ba32cfe9034390e1c4a7822061d204b3cb97505d",
 args=character(),
 code=r"-----(#!/usr/bin/env Rscript
# Exploratory extension of Code/34's survey-weighted three-outcome episode-month
# model. Adds interview-date marital status and separates parity into 0, 1-2,
# 3, and 4+ live births at method start. The selected outcome remains original
# modern-method discontinuation for any reason except wanted pregnancy and
# husband/partner disapproval; both excluded endings are competing events.
#
# Outputs are adjusted point estimates only. Do not attach the earlier model's
# bootstrap intervals or p-values to this different specification. Marital
# status is measured at interview, possibly after the historical episode, so
# its coefficient is descriptive and cannot establish a baseline causal effect.

project <- Sys.getenv("ETHIOPIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
out <- file.path(project,"output","Supporting_data")
if(!requireNamespace("nnet",quietly=TRUE))
  install.packages("nnet",repos="https://cloud.r-project.org")
e <- read.csv(file.path(out,"selected_reason_exploratory_episode_covariates.csv"))
for(v in c("method_group","age_group","parity_group","marital_group",
           "education","wealth_group","residence"))e[[v]]<-factor(e[[v]])
e$method_group <- factor(e$method_group,levels=c("Injectables","Implants","Pill","IUD","Other modern"))
e$age_group <- factor(e$age_group,levels=c("15-19","20-24","25-34","35-49"))
e$parity_group <- factor(e$parity_group,levels=c("0","1-2","3","4+"))
e$marital_group <- factor(e$marital_group,
  levels=c("Never in union","Married/living together","Formerly in union"))
e$education <- factor(e$education,levels=c("None","Primary","Secondary+"))
e$wealth_group <- factor(e$wealth_group,levels=c("Poorest 40%","Middle 20%","Richest 40%"))
e$residence <- factor(e$residence,levels=c("Rural","Urban"))
e$region <- factor(e$region)
e$start_year <- factor((e$start-1L)%/%12L+1900L)
observed_months <- pmax(0L,pmin(12L,e$exposure)-e$entry)
index <- rep(seq_len(nrow(e)),observed_months)
month <- unlist(Map(function(first,n)seq.int(first+1L,length.out=n),
                    e$entry,observed_months),use.names=FALSE)
person <- e[index,c("wt","method_group","age_group","parity_group",
                    "marital_group","education","wealth_group","residence",
                    "region","start_year")]
person$month <- factor(month,levels=1:12)
ended <- e$discontinued[index] & month==e$exposure[index]
person$outcome <- factor(ifelse(!ended,"continue",
  ifelse(e$reason[index]%in%c(2L,8L),"excluded","selected")),
  levels=c("continue","selected","excluded"))
stopifnot(nrow(e)==8611L,nrow(person)==70691L,
          sum(person$outcome=="selected")==1837L,
          sum(person$outcome=="excluded")==1039L)

formula <- outcome ~ month + method_group + age_group + parity_group +
  marital_group + education + wealth_group + residence + region + start_year
fit <- nnet::multinom(formula,data=person,weights=person$wt,
                     maxit=300,trace=FALSE,MaxNWts=10000)
if(fit$convergence!=0L)stop("Extended multinomial model did not converge")
standard <- e[e$entry==0L,]
predict_risk <- function(variable=NULL,level=NULL){
  x <- standard
  if(!is.null(variable))x[[variable]]<-factor(level,levels=levels(x[[variable]]))
  survival <- rep(1,nrow(x)); incidence <- numeric(nrow(x))
  for(t in 1:12){
    x$month<-factor(t,levels=1:12)
    p<-predict(fit,newdata=x,type="probs")
    incidence<-incidence+survival*p[,"selected"]
    survival<-survival*p[,"continue"]
  }
  100*weighted.mean(incidence,standard$wt)
}
variables<-c("age_group","parity_group","marital_group","education",
             "wealth_group","residence","method_group")
adjusted<-do.call(rbind,lapply(variables,function(v)
  do.call(rbind,lapply(levels(e[[v]]),function(level)
    data.frame(characteristic=v,level=level,
      adjusted_12_month_probability_pct=predict_risk(v,level))))))
descriptive<-read.csv(file.path(out,"selected_reason_descriptive_one_way.csv"))
adjusted<-merge(descriptive,adjusted,by=c("characteristic","level"),sort=FALSE)
adjusted<-adjusted[order(match(adjusted$characteristic,variables),
                         match(adjusted$level,unlist(lapply(variables,
                           function(v)levels(e[[v]]))))),]
overall<-predict_risk()
saveRDS(fit,file.path(out,"selected_reason_extended_model.rds"))
write.csv(adjusted,file.path(out,"selected_reason_extended_regression_margins.csv"),row.names=FALSE)
write.csv(data.frame(eligible_episodes=nrow(e),episode_months=nrow(person),
  first_year_selected_endings=sum(person$outcome=="selected"),
  first_year_excluded_endings=sum(person$outcome=="excluded"),
  observed_starts=nrow(standard),adjusted_overall_pct=overall,
  uncertainty="Not calculated for extended specification"),
  file.path(out,"selected_reason_extended_regression_audit.csv"),row.names=FALSE)
cat("Extended model converged; adjusted overall selected-reason risk:",round(overall,2),"percent\n")
print(adjusted[,c("characteristic","level","unadjusted_12_month_probability_pct",
                   "adjusted_12_month_probability_pct")],row.names=FALSE)
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 56_crossvalidated_selected_reason_risk_strata.R
# LANGUAGE: R
MODULES[["56_crossvalidated_selected_reason_risk_strata.R"]] <- list(
 language="R",
 packaged_sha256="38809759a4ebaa1e409858ad73694884852b9cbf22f0135874af26aad923752d",
 args=character(),
 code=r"-----(
# Full DHS sampling frame, including PSUs with no eligible outcome records.
full_survey_frame <- function(){
 r<-Sys.getenv('ETHIOPIA_PROJECT_ROOT'); stopifnot(nzchar(r))
 x<-readRDS(file.path(r,'Data/ET2024DHS__ETIR8ADT__IR_raw.rds'))
 unique(data.frame(cluster=paste(as.integer(x$v022),as.integer(x$v021),sep=':'),stratum=as.integer(x$v022)))
}
complete_survey_data <- function(d){
 r<-Sys.getenv('ETHIOPIA_PROJECT_ROOT');x<-readRDS(file.path(r,'Data/ET2024DHS__ETIR8ADT__IR_raw.rds'))
 f<-unique(data.frame(v021=as.integer(x$v021),v022=as.integer(x$v022)))
 key<-function(a,b)paste(a,b,sep=':');miss<-f[!key(f$v021,f$v022)%in%key(d$v021,d$v022),]
 if(nrow(miss)){z<-d[rep(1L,nrow(miss)),,drop=FALSE];z$v021<-miss$v021;z$v022<-miss$v022;z$wt<-0;d<-rbind(d,z)}
 d
}
#!/usr/bin/env Rscript
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

project <- Sys.getenv("ETHIOPIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
out <- file.path(project,"output","Supporting_data")
if(!requireNamespace("nnet",quietly=TRUE))
  install.packages("nnet",repos="https://cloud.r-project.org")
e <- read.csv(file.path(out,"selected_reason_exploratory_episode_covariates.csv"))
e$method_group <- factor(e$method_group,
  levels=c("Injectables","Implants","Pill","IUD","Other modern"))
e$age_group <- factor(e$age_group,levels=c("15-19","20-24","25-34","35-49"))
e$parity_group <- factor(e$parity_group,levels=c("0","1-2","3","4+"))
e$cluster <- as.character(e$cluster)
e$stratum <- as.integer(e$stratum)
stopifnot(nrow(e)==8611L)

life <- function(d,w=d$wt){
  if(!nrow(d)||sum(w)<=0)return(NA_real_)
  survival <- 1;incidence <- 0
  for(t in 1:12){
    risk<-d$entry<t & d$exposure>=t
    den<-sum(w[risk]);if(den<=0)return(NA_real_)
    end<-risk & d$discontinued & d$exposure==t
    selected<-end & !(d$reason%in%c(2L,8L))
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
  ifelse(e$reason[index]%in%c(2L,8L),"excluded","selected")),
  levels=c("continue","selected","excluded"))
stopifnot(nrow(person)==70691L)
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
reps<-as.integer(Sys.getenv("RISK_STRATA_BOOTSTRAP_REPS","400"))
if(reps<100L)stop("Use at least 100 bootstrap replicates")
cluster_frame<-full_survey_frame()
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
                     "marital_group","education","wealth_group","residence")
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
              "education","wealth_group","residence","entry","exposure",
              "discontinued","reason","selected_event","oof_selected_risk_pct",
              "risk_stratum")],
  file.path(out,"selected_reason_oof_episode_scores.csv"),row.names=FALSE)
write.csv(risk_rows,file.path(out,"selected_reason_crossvalidated_risk_strata.csv"),row.names=FALSE)
write.csv(differences,file.path(out,"selected_reason_risk_strata_differences.csv"),row.names=FALSE)
write.csv(profile,file.path(out,"selected_reason_risk_strata_profiles.csv"),row.names=FALSE)
write.csv(data.frame(eligible_episodes=nrow(e),weighted_episodes=sum(e$wt),
  risk_cut_lower_middle_pct=cut1,risk_cut_middle_higher_pct=cut2,
  folds=5,bootstrap_reps=reps,primary_predictors="Method, age and parity at episode start",
  note="Fixed-cutpoint bootstrap intervals do not include model-training uncertainty"),
  file.path(out,"selected_reason_risk_strata_audit.csv"),row.names=FALSE)
cat("Out-of-fold cut-points:",round(cut1,2),round(cut2,2),"percent\n")
print(risk_rows,row.names=FALSE)
print(differences,row.names=FALSE)
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 58_selected_reason_by_method_duration_class.R
# LANGUAGE: R
MODULES[["58_selected_reason_by_method_duration_class.R"]] <- list(
 language="R",
 packaged_sha256="d2f1d8830193a11eecadafeb66294b33423739cd17f25d933e5ec062f776b1ac",
 args=character(),
 code=r"-----(
# Full DHS sampling frame, including PSUs with no eligible outcome records.
full_survey_frame <- function(){
 r<-Sys.getenv('ETHIOPIA_PROJECT_ROOT'); stopifnot(nzchar(r))
 x<-readRDS(file.path(r,'Data/ET2024DHS__ETIR8ADT__IR_raw.rds'))
 unique(data.frame(cluster=paste(as.integer(x$v022),as.integer(x$v021),sep=':'),stratum=as.integer(x$v022)))
}
complete_survey_data <- function(d){
 r<-Sys.getenv('ETHIOPIA_PROJECT_ROOT');x<-readRDS(file.path(r,'Data/ET2024DHS__ETIR8ADT__IR_raw.rds'))
 f<-unique(data.frame(v021=as.integer(x$v021),v022=as.integer(x$v022)))
 key<-function(a,b)paste(a,b,sep=':');miss<-f[!key(f$v021,f$v022)%in%key(d$v021,d$v022),]
 if(nrow(miss)){z<-d[rep(1L,nrow(miss)),,drop=FALSE];z$v021<-miss$v021;z$v022<-miss$v022;z$wt<-0;d<-rbind(d,z)}
 d
}
#!/usr/bin/env Rscript
# Grouped modern-method 12-month competing-risk life tables. All eligible
# original-method episodes enter the risk set; wanted pregnancy and husband/
# partner disapproval remain competing endings, not sample exclusions.
# Emergency contraception was excluded upstream from the analysis cohort.
project <- Sys.getenv("ETHIOPIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
e <- read.csv(file.path(project,"output/Supporting_data",
                        "selected_reason_exploratory_episode_covariates.csv"))
e$duration_class <- ifelse(e$method_code %in% c(1L,3L,5L),
  "Short-acting reversible",ifelse(e$method_code %in% c(2L,11L),
  "Long-acting reversible (implant/IUD)","Other modern, mixed"))
categories <- c("Short-acting reversible","Long-acting reversible (implant/IUD)",
                "Other modern, mixed")
life <- function(d,w=d$wt){
  survival <- 1; incidence <- 0
  for(t in 1:12){
    risk <- d$entry<t & d$exposure>=t
    den <- sum(w[risk]); if(den<=0)return(NA_real_)
    ending <- risk & d$discontinued & d$exposure==t
    selected <- ending & !(d$reason%in%c(2L,8L))
    incidence <- incidence+survival*sum(w[selected])/den
    survival <- survival*(1-sum(w[ending])/den)
  }
  100*incidence
}
frame <- full_survey_frame()
clusters_by_stratum <- split(frame$cluster,frame$stratum)
reps <- 400L
boot <- matrix(NA_real_,reps,length(categories))
for(b in seq_len(reps)){
  set.seed(20261006L+b)
  multiplier <- setNames(numeric(nrow(frame)),frame$cluster)
  for(ids in clusters_by_stratum){
    n <- length(ids); draw <- sample.int(n,n-1L,replace=TRUE)
    multiplier[ids] <- n/(n-1L)*tabulate(draw,nbins=n)
  }
  w <- e$wt*multiplier[e$cluster]
  for(j in seq_along(categories)){
    take <- e$duration_class==categories[j]
    boot[b,j] <- life(e[take,],w[take])
  }
}
result <- do.call(rbind,lapply(seq_along(categories),function(j){
  d <- e[e$duration_class==categories[j],]
  data.frame(category=categories[j],eligible_episodes=nrow(d),
    weighted_episodes=sum(d$wt),selected_endings=sum(d$selected_event),
    probability_12_month_pct=life(d),
    ci_low=unname(quantile(boot[,j],.025,na.rm=TRUE)),
    ci_high=unname(quantile(boot[,j],.975,na.rm=TRUE)))
}))
write.csv(result,file.path(project,"output/Supporting_data",
                           "selected_reason_by_method_duration_class.csv"),row.names=FALSE)
print(result,row.names=FALSE)
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 60_short_acting_selected_reason_distribution.R
# LANGUAGE: R
MODULES[["60_short_acting_selected_reason_distribution.R"]] <- list(
 language="R",
 packaged_sha256="adaf214568debe01ef557c520734996107dc392887e95417e115126a2ff85a65",
 args=character(),
 code=r"-----(
# Full DHS sampling frame, including PSUs with no eligible outcome records.
full_survey_frame <- function(){
 r<-Sys.getenv('ETHIOPIA_PROJECT_ROOT'); stopifnot(nzchar(r))
 x<-readRDS(file.path(r,'Data/ET2024DHS__ETIR8ADT__IR_raw.rds'))
 unique(data.frame(cluster=paste(as.integer(x$v022),as.integer(x$v021),sep=':'),stratum=as.integer(x$v022)))
}
complete_survey_data <- function(d){
 r<-Sys.getenv('ETHIOPIA_PROJECT_ROOT');x<-readRDS(file.path(r,'Data/ET2024DHS__ETIR8ADT__IR_raw.rds'))
 f<-unique(data.frame(v021=as.integer(x$v021),v022=as.integer(x$v022)))
 key<-function(a,b)paste(a,b,sep=':');miss<-f[!key(f$v021,f$v022)%in%key(d$v021,d$v022),]
 if(nrow(miss)){z<-d[rep(1L,nrow(miss)),,drop=FALSE];z$v021<-miss$v021;z$v022<-miss$v022;z$wt<-0;d<-rbind(d,z)}
 d
}
#!/usr/bin/env Rscript
# Survey-weighted distribution of recorded reasons among selected first-year
# endings of short-acting reversible original methods. This conditional
# distribution is distinct from a reason-specific cumulative incidence.
project <- Sys.getenv("ETHIOPIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
support <- file.path(project,"output/Supporting_data")
all_episodes <- read.csv(file.path(support,"selected_reason_exploratory_episode_covariates.csv"))
all_episodes <- all_episodes[all_episodes$method_code %in% c(1L,3L,5L),]
e <- all_episodes[all_episodes$selected_event,]
reasons <- c(
  "1"="Method failure / pregnancy while using",
  "3"="Other fertility-related reasons",
  "4"="Changes in menstrual bleeding",
  "5"="Other side effects / health concerns",
  "6"="Wanted a more effective method",
  "7"="Access / cost / inconvenience",
  "9"="Other recorded reasons")
stopifnot(nrow(e)==1537L,all(as.character(e$reason)%in%names(reasons)))
codes <- as.integer(names(reasons))
share <- function(w) {
  total <- sum(w)
  vapply(codes,function(code)100*sum(w[e$reason==code])/total,numeric(1))
}
estimate <- share(e$wt)
# Resample the complete short-acting design frame. PSUs with no selected
# ending still matter for survey-design variance in this subpopulation.
frame <- full_survey_frame()
by_stratum <- split(frame$cluster,frame$stratum)
reps <- 400L
boot <- matrix(NA_real_,reps,length(codes))
for(b in seq_len(reps)) {
  set.seed(20261006L+1000L+b)
  mult <- setNames(numeric(nrow(frame)),frame$cluster)
  for(ids in by_stratum){
    n <- length(ids); draw <- sample.int(n,n-1L,replace=TRUE)
    mult[ids] <- n/(n-1L)*tabulate(draw,nbins=n)
  }
  boot[b,] <- share(e$wt*mult[e$cluster])
}
result <- data.frame(reason_code=codes,reason=unname(reasons),
  unweighted_endings=as.integer(table(factor(e$reason,levels=codes))),
  weighted_endings=vapply(codes,function(code)sum(e$wt[e$reason==code]),numeric(1)),
  weighted_share_pct=estimate,
  ci_low=apply(boot,2,quantile,.025,na.rm=TRUE,names=FALSE),
  ci_high=apply(boot,2,quantile,.975,na.rm=TRUE,names=FALSE))
result <- result[order(-result$weighted_share_pct),]
stopifnot(abs(sum(result$weighted_share_pct)-100)<1e-8)
write.csv(result,file.path(support,"short_acting_selected_reason_distribution.csv"),row.names=FALSE)
cat("Short-acting selected first-year endings: N=",nrow(e),
    "; weighted N=",round(sum(e$wt),1),"\n",sep="")
print(result,row.names=FALSE)
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 63_regional_episode_mix_vs_selected_risk.R
# LANGUAGE: R
MODULES[["63_regional_episode_mix_vs_selected_risk.R"]] <- list(
 language="R",
 packaged_sha256="50a23dec7bde0cc69dc366166c4b6a78c7a7736304adafa870775f481db723d9",
 args=character(),
 code=r"-----(#!/usr/bin/env Rscript
# Matched-cohort regional comparison. Left share: weighted eligible original-
# method episodes of that method / all weighted eligible modern episodes in
# the region. Right risk: 12-month competing-risk cumulative incidence of
# original-method ending for reasons other than wanted pregnancy or partner
# disapproval among that method's eligible episodes. EC excluded upstream.
project <- Sys.getenv("ETHIOPIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
out <- file.path(project,"output")
e <- read.csv(file.path(out,"Supporting_data",
                        "selected_reason_exploratory_episode_covariates.csv"))
regions <- read.csv(file.path(out,"presentation_selected_reason_regional_rates.csv"))
region_names <- setNames(regions$region,regions$region_code)
methods <- c("Injectables","Implants","Pill","IUD","Other modern")
life <- function(d){
  if(!nrow(d))return(NA_real_)
  survival <- 1; incidence <- 0
  for(t in 1:12){
    risk <- d$entry<t & d$exposure>=t
    den <- sum(d$wt[risk]);if(den<=0)return(NA_real_)
    end <- risk & d$discontinued & d$exposure==t
    selected <- end & !(d$reason%in%c(2L,8L))
    incidence <- incidence+survival*sum(d$wt[selected])/den
    survival <- survival*(1-sum(d$wt[end])/den)
  }
  100*incidence
}
make <- function(z,name){
  total <- sum(z$wt)
  do.call(rbind,lapply(methods,function(method){
    x <- z[z$method_group==method,]
    data.frame(region=name,method=method,eligible_episodes=nrow(x),
      weighted_episodes=sum(x$wt),
      share_of_region_eligible_episodes_pct=100*sum(x$wt)/total,
      selected_first_year_endings=sum(x$selected_event),
      selected_reason_12_month_probability_pct=life(x),
      display_risk=nrow(x)>=30L && sum(x$selected_event)>=10L)
  }))
}
result <- rbind(make(e,"National"),do.call(rbind,lapply(seq_len(nrow(regions)),function(i){
  code <- regions$region_code[i]
  make(e[e$region==code,],region_names[as.character(code)])
})))
rownames(result)<-NULL
stopifnot(nrow(result)==75L)
check <- read.csv(file.path(out,"selected_reason_region_method_screen.csv"))
for(i in seq_len(nrow(check))){
  name <- region_names[as.character(check$region[i])]
  x <- result[result$region==name & result$method==check$method[i],]
  same_rate <- is.na(check$rate[i]) ||
               (!is.na(x$selected_reason_12_month_probability_pct) &&
                abs(x$selected_reason_12_month_probability_pct-check$rate[i])<1e-8)
  if(nrow(x)!=1L || x$eligible_episodes!=check$n[i] || !same_rate)
    stop("Mismatch: ",name," ",check$method[i]," N=",x$eligible_episodes,
         " vs ",check$n[i],"; rate=",x$selected_reason_12_month_probability_pct,
         " vs ",check$rate[i])
}
write.csv(result,file.path(out,"regional_episode_mix_vs_selected_method_rates.csv"),row.names=FALSE)
cat("Regional matched-cohort estimates written. Displayable rate cells:",
    sum(result$display_risk & result$region!="National"),"of 70.\n")
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 68_binary_marital_four_parity_selected_regression.R
# LANGUAGE: R
MODULES[["68_binary_marital_four_parity_selected_regression.R"]] <- list(
 language="R",
 packaged_sha256="a2ad4a7345765e78019bc0582063eba3d72c0b60276dd6ef1894cf73ec7e95a8",
 args=character(),
 code=r"-----(#!/usr/bin/env Rscript
# Preview model requested 2026-10-06. This leaves the working HTML and earlier
# regression files untouched. Original-method modern episodes (excluding EC)
# enter a three-outcome discrete-time competing-event model: continue, selected
# reason ending, wanted-pregnancy/partner-disapproval ending. Selected reasons
# include all recorded reasons except the latter two. Survey weights enter the
# model and standardization. Marital status is v501 at interview, not at start.
project <- Sys.getenv("ETHIOPIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
out <- file.path(project, "output", "Supporting_data")
if (!requireNamespace("nnet", quietly = TRUE))
  stop("nnet is required; install.packages('nnet')")
e <- read.csv(file.path(out, "selected_reason_exploratory_episode_covariates.csv"))
ir <- readRDS(file.path(project, "Data/ET2024DHS__ETIR8ADT__IR_raw.rds"))
i <- e$woman_row
birth_cols <- grep("^b3_", names(ir), value = TRUE)
births <- as.matrix(ir[i, birth_cols])
parity <- rowSums(!is.na(births) & births <= e$start)
marital <- as.integer(ir$v501[i])
stopifnot(!anyNA(parity), all(marital %in% 0:5))
e$parity_group <- factor(ifelse(parity == 0, "0",
  ifelse(parity <= 2, "1–2", ifelse(parity <= 4, "3–4", "5+"))),
  levels = c("0", "1–2", "3–4", "5+"))
e$marital_group <- factor(ifelse(marital %in% c(1L, 2L), "Married/living together",
  "Not married/living together"),
  levels = c("Married/living together", "Not married/living together"))
e$method_group <- factor(e$method_group,
  levels = c("Injectables", "Implants", "Pill", "IUD", "Other modern"))
e$age_group <- factor(e$age_group,
  levels = c("15-19", "20-24", "25-34", "35-49"))
e$education <- factor(e$education, levels = c("None", "Primary", "Secondary+"))
e$wealth_group <- factor(e$wealth_group,
  levels = c("Poorest 40%", "Middle 20%", "Richest 40%"))
e$residence <- factor(e$residence, levels = c("Rural", "Urban"))
e$region <- factor(e$region)
e$start_year <- factor((e$start - 1L) %/% 12L + 1900L)
observed_months <- pmax(0L, pmin(12L, e$exposure) - e$entry)
index <- rep(seq_len(nrow(e)), observed_months)
month <- unlist(Map(function(first, n) seq.int(first + 1L, length.out = n),
                    e$entry, observed_months), use.names = FALSE)
person <- e[index, c("wt", "method_group", "age_group", "parity_group",
  "marital_group", "education", "wealth_group", "residence", "region",
  "start_year", "cluster")]
person$month <- factor(month, levels = 1:12)
ended <- e$discontinued[index] & month == e$exposure[index]
person$outcome <- factor(ifelse(!ended, "continue",
  ifelse(e$reason[index] %in% c(2L, 8L), "excluded", "selected")),
  levels = c("continue", "selected", "excluded"))
stopifnot(nrow(e) == 8611L, nrow(person) == 70691L,
  sum(person$outcome == "selected") == 1837L,
  sum(person$outcome == "excluded") == 1039L)
model_formula <- outcome ~ month + method_group + age_group + parity_group +
  marital_group + education + wealth_group + residence + region + start_year
fit <- nnet::multinom(model_formula, data = person, weights = person$wt,
  maxit = 300, trace = FALSE, MaxNWts = 10000)
if (fit$convergence != 0L) stop("Model did not converge")
standard <- e[e$entry == 0L, ]
predict_risk <- function(model, variable = NULL, level = NULL,
                         weights = standard$wt) {
  x <- standard
  if (!is.null(variable))
    x[[variable]] <- factor(level, levels = levels(x[[variable]]))
  survival <- rep(1, nrow(x))
  incidence <- numeric(nrow(x))
  for (t in 1:12) {
    x$month <- factor(t, levels = 1:12)
    p <- predict(model, newdata = x, type = "probs")
    incidence <- incidence + survival * p[, "selected"]
    survival <- survival * p[, "continue"]
  }
  100 * weighted.mean(incidence, weights)
}
life_table <- function(episodes) {
  survival <- 1
  incidence <- 0
  for (t in 1:12) {
    at_risk <- episodes$entry < t & episodes$exposure >= t
    denom <- sum(episodes$wt[at_risk])
    if (denom == 0) return(NA_real_)
    ending <- at_risk & episodes$discontinued & episodes$exposure == t
    selected <- ending & !(episodes$reason %in% c(2L, 8L))
    incidence <- incidence + survival * sum(episodes$wt[selected]) / denom
    survival <- survival * (1 - sum(episodes$wt[ending]) / denom)
  }
  100 * incidence
}
variables <- c("age_group", "parity_group", "marital_group", "education",
  "wealth_group", "residence", "method_group", "region")
rows <- lapply(variables, function(variable) {
  do.call(rbind, lapply(levels(e[[variable]]), function(level) {
    sub <- e[e[[variable]] == level, ]
    data.frame(characteristic = variable, level = level,
      eligible_episodes = nrow(sub),
      selected_first_year_endings = sum(sub$discontinued &
        sub$reason %in% setdiff(unique(e$reason), c(2L, 8L)) &
        sub$exposure <= 12),
      unadjusted_12_month_probability_pct = life_table(sub),
      adjusted_12_month_probability_pct = predict_risk(fit, variable, level))
  }))
})
margins <- do.call(rbind, rows)
rownames(margins) <- NULL
overall <- predict_risk(fit)
write.csv(margins,
  file.path(out, "selected_reason_binary_marital_four_parity_margins.csv"),
  row.names = FALSE)
write.csv(data.frame(eligible_episodes = nrow(e),
  observed_starts = nrow(standard), episode_months = nrow(person),
  selected_first_year_endings = sum(person$outcome == "selected"),
  excluded_first_year_endings = sum(person$outcome == "excluded"),
  unadjusted_overall_pct = life_table(e), adjusted_overall_pct = overall,
  convergence = fit$convergence),
  file.path(out, "selected_reason_binary_marital_four_parity_audit.csv"),
  row.names = FALSE)
saveRDS(fit, file.path(out, "selected_reason_binary_marital_four_parity_model.rds"))
cat(sprintf("New specification converged; adjusted overall %.2f%%\n", overall))
print(margins, row.names = FALSE)
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 70_four_marital_four_parity_selected_regression.R
# LANGUAGE: R
MODULES[["70_four_marital_four_parity_selected_regression.R"]] <- list(
 language="R",
 packaged_sha256="dc79530abc2c134414b75d28a5418c5cc0bf62e2dafc0c0588d0ef46c446ccb7",
 args=character(),
 code=r"-----(
# Algebraically identical monthly multinomial prediction, with the design
# matrix constructed once instead of once per duration month.
fast_survey_cif<-function(model,x,weights,event){
 x$month<-factor(1,levels=1:12)
 X<-model.matrix(delete.response(terms(model)),data=x,contrasts.arg=model$contrasts)
 b<-coef(model);eta<-X[,colnames(b),drop=FALSE]%*%t(b)
 S<-rep(1,nrow(x));F<-numeric(nrow(x));j<-match(event,rownames(b))
 for(t in 1:12){off<-if(t==1)rep(0,nrow(b))else b[,paste0('month',t)];ee<-exp(sweep(eta,2,off,'+'));den<-1+rowSums(ee);F<-F+S*ee[,j]/den;S<-S/den}
 100*weighted.mean(F,weights)
}

# Full DHS sampling frame, including PSUs with no eligible outcome records.
full_survey_frame <- function(){
 r<-Sys.getenv('ETHIOPIA_PROJECT_ROOT'); stopifnot(nzchar(r))
 x<-readRDS(file.path(r,'Data/ET2024DHS__ETIR8ADT__IR_raw.rds'))
 unique(data.frame(cluster=paste(as.integer(x$v022),as.integer(x$v021),sep=':'),stratum=as.integer(x$v022)))
}
complete_survey_data <- function(d){
 r<-Sys.getenv('ETHIOPIA_PROJECT_ROOT');x<-readRDS(file.path(r,'Data/ET2024DHS__ETIR8ADT__IR_raw.rds'))
 f<-unique(data.frame(v021=as.integer(x$v021),v022=as.integer(x$v022)))
 key<-function(a,b)paste(a,b,sep=':');miss<-f[!key(f$v021,f$v022)%in%key(d$v021,d$v022),]
 if(nrow(miss)){z<-d[rep(1L,nrow(miss)),,drop=FALSE];z$v021<-miss$v021;z$v022<-miss$v022;z$wt<-0;d<-rbind(d,z)}
 d
}
#!/usr/bin/env Rscript
# Four-category marital model requested 2026-10-06. This leaves the working HTML and earlier
# regression files untouched. Original-method modern episodes (excluding EC)
# enter a three-outcome discrete-time competing-event model: continue, selected
# reason ending, wanted-pregnancy/partner-disapproval ending. Selected reasons
# include all recorded reasons except the latter two. Survey weights enter the
# model and standardization. Marital status is v501 at interview, not at start.
project <- Sys.getenv("ETHIOPIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
out <- file.path(project, "output", "Supporting_data")
if (!requireNamespace("nnet", quietly = TRUE))
  stop("nnet is required; install.packages('nnet')")
e <- read.csv(file.path(out, "selected_reason_exploratory_episode_covariates.csv"))
ir <- readRDS(file.path(project, "Data/ET2024DHS__ETIR8ADT__IR_raw.rds"))
i <- e$woman_row
birth_cols <- grep("^b3_", names(ir), value = TRUE)
births <- as.matrix(ir[i, birth_cols])
parity <- rowSums(!is.na(births) & births <= e$start)
marital <- as.integer(ir$v501[i])
stopifnot(!anyNA(parity), all(marital %in% 0:5))
e$parity_group <- factor(ifelse(parity == 0, "0",
  ifelse(parity <= 2, "1–2", ifelse(parity <= 4, "3–4", "5+"))),
  levels = c("0", "1–2", "3–4", "5+"))
e$marital_group <- factor(ifelse(marital == 0L, "Never in union",
  ifelse(marital == 2L, "Living together",
  ifelse(marital == 1L, "Married", "Divorced/widowed/separated"))),
  levels = c("Never in union", "Living together", "Married",
             "Divorced/widowed/separated"))
e$method_group <- factor(e$method_group,
  levels = c("Injectables", "Implants", "Pill", "IUD", "Other modern"))
e$age_group <- factor(e$age_group,
  levels = c("15-19", "20-24", "25-34", "35-49"))
e$education <- factor(e$education, levels = c("None", "Primary", "Secondary+"))
e$wealth_group <- factor(e$wealth_group,
  levels = c("Poorest 40%", "Middle 20%", "Richest 40%"))
e$residence <- factor(e$residence, levels = c("Rural", "Urban"))
e$region <- factor(e$region)
e$start_year <- factor((e$start - 1L) %/% 12L + 1900L)
observed_months <- pmax(0L, pmin(12L, e$exposure) - e$entry)
index <- rep(seq_len(nrow(e)), observed_months)
month <- unlist(Map(function(first, n) seq.int(first + 1L, length.out = n),
                    e$entry, observed_months), use.names = FALSE)
person <- e[index, c("wt", "method_group", "age_group", "parity_group",
  "marital_group", "education", "wealth_group", "residence", "region",
  "start_year", "cluster")]
person$month <- factor(month, levels = 1:12)
ended <- e$discontinued[index] & month == e$exposure[index]
person$outcome <- factor(ifelse(!ended, "continue",
  ifelse(e$reason[index] %in% c(2L, 8L), "excluded", "selected")),
  levels = c("continue", "selected", "excluded"))
stopifnot(nrow(e) == 8611L, nrow(person) == 70691L,
  sum(person$outcome == "selected") == 1837L,
  sum(person$outcome == "excluded") == 1039L)
model_formula <- outcome ~ month + method_group + age_group + parity_group +
  marital_group + education + wealth_group + residence + region + start_year
fit <- nnet::multinom(model_formula, data = person, weights = person$wt,
  maxit = 300, trace = FALSE, MaxNWts = 10000)
if (fit$convergence != 0L) stop("Model did not converge")
standard <- e[e$entry == 0L, ]
predict_risk <- function(model, variable = NULL, level = NULL,
                         weights = standard$wt) {x<-standard;if(!is.null(variable))x[[variable]]<-factor(level,levels=levels(x[[variable]]));fast_survey_cif(model,x,weights,'selected')}
life_table <- function(episodes) {
  survival <- 1
  incidence <- 0
  for (t in 1:12) {
    at_risk <- episodes$entry < t & episodes$exposure >= t
    denom <- sum(episodes$wt[at_risk])
    if (denom == 0) return(NA_real_)
    ending <- at_risk & episodes$discontinued & episodes$exposure == t
    selected <- ending & !(episodes$reason %in% c(2L, 8L))
    incidence <- incidence + survival * sum(episodes$wt[selected]) / denom
    survival <- survival * (1 - sum(episodes$wt[ending]) / denom)
  }
  100 * incidence
}
variables <- c("age_group", "parity_group", "marital_group", "education",
  "wealth_group", "residence", "method_group", "region")
rows <- lapply(variables, function(variable) {
  do.call(rbind, lapply(levels(e[[variable]]), function(level) {
    sub <- e[e[[variable]] == level, ]
    data.frame(characteristic = variable, level = level,
      eligible_episodes = nrow(sub),
      selected_first_year_endings = sum(sub$discontinued &
        sub$reason %in% setdiff(unique(e$reason), c(2L, 8L)) &
        sub$exposure <= 12),
      unadjusted_12_month_probability_pct = life_table(sub),
      adjusted_12_month_probability_pct = predict_risk(fit, variable, level))
  }))
})
margins <- do.call(rbind, rows)
rownames(margins) <- NULL
overall <- predict_risk(fit)
write.csv(margins,
  file.path(out, "selected_reason_four_marital_four_parity_margins.csv"),
  row.names = FALSE)
write.csv(data.frame(eligible_episodes = nrow(e),
  observed_starts = nrow(standard), episode_months = nrow(person),
  selected_first_year_endings = sum(person$outcome == "selected"),
  excluded_first_year_endings = sum(person$outcome == "excluded"),
  unadjusted_overall_pct = life_table(e), adjusted_overall_pct = overall,
  convergence = fit$convergence),
  file.path(out, "selected_reason_four_marital_four_parity_audit.csv"),
  row.names = FALSE)
saveRDS(fit, file.path(out, "selected_reason_four_marital_four_parity_model.rds"))
cat(sprintf("New specification converged; adjusted overall %.2f%%\n", overall))
print(margins, row.names = FALSE)

# Stratified rescaled PSU bootstrap for design-based percentile intervals.
# Resampling a PSU moves all of its women's episodes and episode-month rows
# together, preserving repeated episodes within women.
reps <- as.integer(Sys.getenv("BOOTSTRAP_REPS", "0"))
if (reps > 0L) {
  cluster_frame <- full_survey_frame()
  clusters_by_stratum <- split(cluster_frame$cluster, cluster_frame$stratum)
  stopifnot(all(lengths(clusters_by_stratum) > 1L))
  one_bootstrap <- function(rep_no) {
    set.seed(20261006L + rep_no)
    multiplier <- setNames(numeric(nrow(cluster_frame)), cluster_frame$cluster)
    for (ids in clusters_by_stratum) {
      n <- length(ids)
      draws <- sample.int(n, n - 1L, replace = TRUE)
      multiplier[ids] <- n / (n - 1) * tabulate(draws, nbins = n)
    }
    boot_wt <- person$wt * multiplier[person$cluster]
    standard_wt <- standard$wt * multiplier[standard$cluster]
    boot_data <- person
    boot_data$boot_wt <- boot_wt
    m <- tryCatch(nnet::multinom(model_formula, data = boot_data, weights = boot_wt, summ=2,
      maxit = 300, trace = FALSE, MaxNWts = 10000), error = function(err) {
        message(sprintf("Bootstrap %d error: %s", rep_no, conditionMessage(err)))
        NULL
      })
    if (!is.null(m) && m$convergence != 0L)
      message(sprintf("Bootstrap %d convergence code: %d", rep_no, m$convergence))
    if (is.null(m) || m$convergence != 0L)
      return(rep(NA_real_, nrow(margins) + 1L))
    c(predict_risk(m, weights = standard_wt),
      vapply(seq_len(nrow(margins)), function(j)
        predict_risk(m, margins$characteristic[j], margins$level[j],
          weights = standard_wt), numeric(1)))
  }
  boot <- do.call(rbind, parallel::mclapply(seq_len(reps), one_bootstrap,
    mc.cores = min(4L, parallel::detectCores()), mc.preschedule = FALSE))
  valid <- complete.cases(boot)
  if (sum(valid) < ceiling(.95 * reps))
    stop(sprintf("Only %d/%d bootstrap models converged", sum(valid), reps))
  column_names <- c("overall", paste(margins$characteristic, margins$level, sep="::"))
  colnames(boot) <- column_names
  write.csv(data.frame(replicate = seq_len(reps), boot, check.names = FALSE),
    file.path(out, "selected_reason_four_marital_four_parity_bootstrap.csv"),
    row.names = FALSE)
  bounds <- apply(boot[valid, -1L, drop = FALSE], 2, quantile,
    probs = c(.025, .975), names = FALSE)
  margins$ci_low <- bounds[1, ]
  margins$ci_high <- bounds[2, ]
  write.csv(margins,
    file.path(out, "selected_reason_four_marital_four_parity_margins.csv"),
    row.names = FALSE)
  overall_bounds <- quantile(boot[valid, 1L], probs = c(.025, .975), names = FALSE)
  write.csv(data.frame(estimate = overall, ci_low = overall_bounds[1],
    ci_high = overall_bounds[2], valid_reps = sum(valid), requested_reps = reps),
    file.path(out, "selected_reason_four_marital_four_parity_overall_ci.csv"),
    row.names = FALSE)
  cat(sprintf("Bootstrap converged: %d/%d; overall CI %.2f–%.2f%%\n",
    sum(valid), reps, overall_bounds[1], overall_bounds[2]))
}
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 72_five_wealth_four_marital_selected_regression.R
# LANGUAGE: R
MODULES[["72_five_wealth_four_marital_selected_regression.R"]] <- list(
 language="R",
 packaged_sha256="f348c95871ec41d85f3bd251c0af0976c6860b354fc0226836b6bb24a6d8ff74",
 args=character(),
 code=r"-----(
# Algebraically identical monthly multinomial prediction, with the design
# matrix constructed once instead of once per duration month.
fast_survey_cif<-function(model,x,weights,event){
 x$month<-factor(1,levels=1:12)
 X<-model.matrix(delete.response(terms(model)),data=x,contrasts.arg=model$contrasts)
 b<-coef(model);eta<-X[,colnames(b),drop=FALSE]%*%t(b)
 S<-rep(1,nrow(x));F<-numeric(nrow(x));j<-match(event,rownames(b))
 for(t in 1:12){off<-if(t==1)rep(0,nrow(b))else b[,paste0('month',t)];ee<-exp(sweep(eta,2,off,'+'));den<-1+rowSums(ee);F<-F+S*ee[,j]/den;S<-S/den}
 100*weighted.mean(F,weights)
}

# Full DHS sampling frame, including PSUs with no eligible outcome records.
full_survey_frame <- function(){
 r<-Sys.getenv('ETHIOPIA_PROJECT_ROOT'); stopifnot(nzchar(r))
 x<-readRDS(file.path(r,'Data/ET2024DHS__ETIR8ADT__IR_raw.rds'))
 unique(data.frame(cluster=paste(as.integer(x$v022),as.integer(x$v021),sep=':'),stratum=as.integer(x$v022)))
}
complete_survey_data <- function(d){
 r<-Sys.getenv('ETHIOPIA_PROJECT_ROOT');x<-readRDS(file.path(r,'Data/ET2024DHS__ETIR8ADT__IR_raw.rds'))
 f<-unique(data.frame(v021=as.integer(x$v021),v022=as.integer(x$v022)))
 key<-function(a,b)paste(a,b,sep=':');miss<-f[!key(f$v021,f$v022)%in%key(d$v021,d$v022),]
 if(nrow(miss)){z<-d[rep(1L,nrow(miss)),,drop=FALSE];z$v021<-miss$v021;z$v022<-miss$v022;z$wt<-0;d<-rbind(d,z)}
 d
}
#!/usr/bin/env Rscript
# Five-wealth-quintile sensitivity model requested 2026-10-06. This leaves the working HTML and earlier
# regression files untouched. Original-method modern episodes (excluding EC)
# enter a three-outcome discrete-time competing-event model: continue, selected
# reason ending, wanted-pregnancy/partner-disapproval ending. Selected reasons
# include all recorded reasons except the latter two. Survey weights enter the
# model and standardization. Marital status is v501 at interview, not at start.
project <- Sys.getenv("ETHIOPIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
out <- file.path(project, "output", "Supporting_data")
if (!requireNamespace("nnet", quietly = TRUE))
  stop("nnet is required; install.packages('nnet')")
e <- read.csv(file.path(out, "selected_reason_exploratory_episode_covariates.csv"))
ir <- readRDS(file.path(project, "Data/ET2024DHS__ETIR8ADT__IR_raw.rds"))
i <- e$woman_row
birth_cols <- grep("^b3_", names(ir), value = TRUE)
births <- as.matrix(ir[i, birth_cols])
parity <- rowSums(!is.na(births) & births <= e$start)
marital <- as.integer(ir$v501[i])
stopifnot(!anyNA(parity), all(marital %in% 0:5))
e$parity_group <- factor(ifelse(parity == 0, "0",
  ifelse(parity <= 2, "1–2", ifelse(parity <= 4, "3–4", "5+"))),
  levels = c("0", "1–2", "3–4", "5+"))
e$marital_group <- factor(ifelse(marital == 0L, "Never in union",
  ifelse(marital == 2L, "Living together",
  ifelse(marital == 1L, "Married", "Divorced/widowed/separated"))),
  levels = c("Never in union", "Living together", "Married",
             "Divorced/widowed/separated"))
e$method_group <- factor(e$method_group,
  levels = c("Injectables", "Implants", "Pill", "IUD", "Other modern"))
e$age_group <- factor(e$age_group,
  levels = c("15-19", "20-24", "25-34", "35-49"))
e$education <- factor(e$education, levels = c("None", "Primary", "Secondary+"))
wealth <- as.integer(ir$v190[i])
stopifnot(all(wealth %in% 1:5))
e$wealth_group <- factor(c("Poorest", "Poorer", "Middle", "Richer", "Richest")[wealth],
  levels = c("Poorest", "Poorer", "Middle", "Richer", "Richest"))
e$residence <- factor(e$residence, levels = c("Rural", "Urban"))
e$region <- factor(e$region)
e$start_year <- factor((e$start - 1L) %/% 12L + 1900L)
observed_months <- pmax(0L, pmin(12L, e$exposure) - e$entry)
index <- rep(seq_len(nrow(e)), observed_months)
month <- unlist(Map(function(first, n) seq.int(first + 1L, length.out = n),
                    e$entry, observed_months), use.names = FALSE)
person <- e[index, c("wt", "method_group", "age_group", "parity_group",
  "marital_group", "education", "wealth_group", "residence", "region",
  "start_year", "cluster")]
person$month <- factor(month, levels = 1:12)
ended <- e$discontinued[index] & month == e$exposure[index]
person$outcome <- factor(ifelse(!ended, "continue",
  ifelse(e$reason[index] %in% c(2L, 8L), "excluded", "selected")),
  levels = c("continue", "selected", "excluded"))
stopifnot(nrow(e) == 8611L, nrow(person) == 70691L,
  sum(person$outcome == "selected") == 1837L,
  sum(person$outcome == "excluded") == 1039L)
model_formula <- outcome ~ month + method_group + age_group + parity_group +
  marital_group + education + wealth_group + residence + region + start_year
fit <- nnet::multinom(model_formula, data = person, weights = person$wt,
  maxit = 300, trace = FALSE, MaxNWts = 10000)
if (fit$convergence != 0L) stop("Model did not converge")
standard <- e[e$entry == 0L, ]
predict_risk <- function(model, variable = NULL, level = NULL,
                         weights = standard$wt) {x<-standard;if(!is.null(variable))x[[variable]]<-factor(level,levels=levels(x[[variable]]));fast_survey_cif(model,x,weights,'selected')}
life_table <- function(episodes) {
  survival <- 1
  incidence <- 0
  for (t in 1:12) {
    at_risk <- episodes$entry < t & episodes$exposure >= t
    denom <- sum(episodes$wt[at_risk])
    if (denom == 0) return(NA_real_)
    ending <- at_risk & episodes$discontinued & episodes$exposure == t
    selected <- ending & !(episodes$reason %in% c(2L, 8L))
    incidence <- incidence + survival * sum(episodes$wt[selected]) / denom
    survival <- survival * (1 - sum(episodes$wt[ending]) / denom)
  }
  100 * incidence
}
variables <- c("age_group", "parity_group", "marital_group", "education",
  "wealth_group", "residence", "method_group", "region")
rows <- lapply(variables, function(variable) {
  do.call(rbind, lapply(levels(e[[variable]]), function(level) {
    sub <- e[e[[variable]] == level, ]
    data.frame(characteristic = variable, level = level,
      eligible_episodes = nrow(sub),
      selected_first_year_endings = sum(sub$discontinued &
        sub$reason %in% setdiff(unique(e$reason), c(2L, 8L)) &
        sub$exposure <= 12),
      unadjusted_12_month_probability_pct = life_table(sub),
      adjusted_12_month_probability_pct = predict_risk(fit, variable, level))
  }))
})
margins <- do.call(rbind, rows)
rownames(margins) <- NULL
overall <- predict_risk(fit)
write.csv(margins,
  file.path(out, "selected_reason_five_wealth_four_marital_four_parity_margins.csv"),
  row.names = FALSE)
write.csv(data.frame(eligible_episodes = nrow(e),
  observed_starts = nrow(standard), episode_months = nrow(person),
  selected_first_year_endings = sum(person$outcome == "selected"),
  excluded_first_year_endings = sum(person$outcome == "excluded"),
  unadjusted_overall_pct = life_table(e), adjusted_overall_pct = overall,
  convergence = fit$convergence),
  file.path(out, "selected_reason_five_wealth_four_marital_four_parity_audit.csv"),
  row.names = FALSE)
saveRDS(fit, file.path(out, "selected_reason_five_wealth_four_marital_four_parity_model.rds"))
cat(sprintf("New specification converged; adjusted overall %.2f%%\n", overall))
print(margins, row.names = FALSE)

# Stratified rescaled PSU bootstrap for design-based percentile intervals.
# Resampling a PSU moves all of its women's episodes and episode-month rows
# together, preserving repeated episodes within women.
reps <- as.integer(Sys.getenv("BOOTSTRAP_REPS", "0"))
if (reps > 0L) {
  cluster_frame <- full_survey_frame()
  clusters_by_stratum <- split(cluster_frame$cluster, cluster_frame$stratum)
  stopifnot(all(lengths(clusters_by_stratum) > 1L))
  one_bootstrap <- function(rep_no) {
    set.seed(20261006L + rep_no)
    multiplier <- setNames(numeric(nrow(cluster_frame)), cluster_frame$cluster)
    for (ids in clusters_by_stratum) {
      n <- length(ids)
      draws <- sample.int(n, n - 1L, replace = TRUE)
      multiplier[ids] <- n / (n - 1) * tabulate(draws, nbins = n)
    }
    boot_wt <- person$wt * multiplier[person$cluster]
    standard_wt <- standard$wt * multiplier[standard$cluster]
    boot_data <- person
    boot_data$boot_wt <- boot_wt
    m <- tryCatch(nnet::multinom(model_formula, data = boot_data, weights = boot_wt, summ=2,
      maxit = 300, trace = FALSE, MaxNWts = 10000), error = function(err) {
        message(sprintf("Bootstrap %d error: %s", rep_no, conditionMessage(err)))
        NULL
      })
    if (!is.null(m) && m$convergence != 0L)
      message(sprintf("Bootstrap %d convergence code: %d", rep_no, m$convergence))
    if (is.null(m) || m$convergence != 0L)
      return(rep(NA_real_, nrow(margins) + 1L))
    c(predict_risk(m, weights = standard_wt),
      vapply(seq_len(nrow(margins)), function(j)
        predict_risk(m, margins$characteristic[j], margins$level[j],
          weights = standard_wt), numeric(1)))
  }
  boot <- do.call(rbind, parallel::mclapply(seq_len(reps), one_bootstrap,
    mc.cores = min(4L, parallel::detectCores()), mc.preschedule = FALSE))
  valid <- complete.cases(boot)
  if (sum(valid) < ceiling(.95 * reps))
    stop(sprintf("Only %d/%d bootstrap models converged", sum(valid), reps))
  column_names <- c("overall", paste(margins$characteristic, margins$level, sep="::"))
  colnames(boot) <- column_names
  write.csv(data.frame(replicate = seq_len(reps), boot, check.names = FALSE),
    file.path(out, "selected_reason_five_wealth_four_marital_four_parity_bootstrap.csv"),
    row.names = FALSE)
  bounds <- apply(boot[valid, -1L, drop = FALSE], 2, quantile,
    probs = c(.025, .975), names = FALSE)
  margins$ci_low <- bounds[1, ]
  margins$ci_high <- bounds[2, ]
  write.csv(margins,
    file.path(out, "selected_reason_five_wealth_four_marital_four_parity_margins.csv"),
    row.names = FALSE)
  overall_bounds <- quantile(boot[valid, 1L], probs = c(.025, .975), names = FALSE)
  write.csv(data.frame(estimate = overall, ci_low = overall_bounds[1],
    ci_high = overall_bounds[2], valid_reps = sum(valid), requested_reps = reps),
    file.path(out, "selected_reason_five_wealth_four_marital_four_parity_overall_ci.csv"),
    row.names = FALSE)
  cat(sprintf("Bootstrap converged: %d/%d; overall CI %.2f–%.2f%%\n",
    sum(valid), reps, overall_bounds[1], overall_bounds[2]))
}
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 75_injectable_only_full_selected_regression.R
# LANGUAGE: R
MODULES[["75_injectable_only_full_selected_regression.R"]] <- list(
 language="R",
 packaged_sha256="07a56ddc6500c9d037f97f7b55f2412a08f94f75823ccad5970285df32880eea",
 args=character(),
 code=r"-----(
# Algebraically identical monthly multinomial prediction, with the design
# matrix constructed once instead of once per duration month.
fast_survey_cif<-function(model,x,weights,event){
 x$month<-factor(1,levels=1:12)
 X<-model.matrix(delete.response(terms(model)),data=x,contrasts.arg=model$contrasts)
 b<-coef(model);eta<-X[,colnames(b),drop=FALSE]%*%t(b)
 S<-rep(1,nrow(x));F<-numeric(nrow(x));j<-match(event,rownames(b))
 for(t in 1:12){off<-if(t==1)rep(0,nrow(b))else b[,paste0('month',t)];ee<-exp(sweep(eta,2,off,'+'));den<-1+rowSums(ee);F<-F+S*ee[,j]/den;S<-S/den}
 100*weighted.mean(F,weights)
}

# Full DHS sampling frame, including PSUs with no eligible outcome records.
full_survey_frame <- function(){
 r<-Sys.getenv('ETHIOPIA_PROJECT_ROOT'); stopifnot(nzchar(r))
 x<-readRDS(file.path(r,'Data/ET2024DHS__ETIR8ADT__IR_raw.rds'))
 unique(data.frame(cluster=paste(as.integer(x$v022),as.integer(x$v021),sep=':'),stratum=as.integer(x$v022)))
}
complete_survey_data <- function(d){
 r<-Sys.getenv('ETHIOPIA_PROJECT_ROOT');x<-readRDS(file.path(r,'Data/ET2024DHS__ETIR8ADT__IR_raw.rds'))
 f<-unique(data.frame(v021=as.integer(x$v021),v022=as.integer(x$v022)))
 key<-function(a,b)paste(a,b,sep=':');miss<-f[!key(f$v021,f$v022)%in%key(d$v021,d$v022),]
 if(nrow(miss)){z<-d[rep(1L,nrow(miss)),,drop=FALSE];z$v021<-miss$v021;z$v022<-miss$v022;z$wt<-0;d<-rbind(d,z)}
 d
}
#!/usr/bin/env Rscript
# Injectable-only sensitivity model. This leaves the working HTML and full-method model
# untouched. Original-method injectable episodes
# enter a three-outcome discrete-time competing-event model: continue, selected
# reason ending, wanted-pregnancy/partner-disapproval ending. Selected reasons
# include all recorded reasons except the latter two. Survey weights enter the
# model and standardization. Marital status is v501 at interview, not at start.
project <- Sys.getenv("ETHIOPIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
out <- file.path(project, "output", "Supporting_data")
if (!requireNamespace("nnet", quietly = TRUE))
  stop("nnet is required; install.packages('nnet')")
e <- read.csv(file.path(out, "selected_reason_exploratory_episode_covariates.csv"))
ir <- readRDS(file.path(project, "Data/ET2024DHS__ETIR8ADT__IR_raw.rds"))
i <- e$woman_row
birth_cols <- grep("^b3_", names(ir), value = TRUE)
births <- as.matrix(ir[i, birth_cols])
parity <- rowSums(!is.na(births) & births <= e$start)
marital <- as.integer(ir$v501[i])
stopifnot(!anyNA(parity), all(marital %in% 0:5))
e$parity_group <- factor(ifelse(parity == 0, "0",
  ifelse(parity <= 2, "1–2", ifelse(parity <= 4, "3–4", "5+"))),
  levels = c("0", "1–2", "3–4", "5+"))
e$marital_group <- factor(ifelse(marital == 0L, "Never in union",
  ifelse(marital == 2L, "Living together",
  ifelse(marital == 1L, "Married", "Divorced/widowed/separated"))),
  levels = c("Never in union", "Living together", "Married",
             "Divorced/widowed/separated"))
e$method_group <- factor(e$method_group,
  levels = c("Injectables", "Implants", "Pill", "IUD", "Other modern"))
# Restrict at the episode level before constructing person-months and risk sets.
e <- droplevels(e[e$method_group == "Injectables", ])
e$age_group <- factor(e$age_group,
  levels = c("15-19", "20-24", "25-34", "35-49"))
e$education <- factor(e$education, levels = c("None", "Primary", "Secondary+"))
e$wealth_group <- factor(e$wealth_group,
  levels = c("Poorest 40%", "Middle 20%", "Richest 40%"))
e$residence <- factor(e$residence, levels = c("Rural", "Urban"))
e$region <- factor(e$region)
e$start_year <- factor((e$start - 1L) %/% 12L + 1900L)
observed_months <- pmax(0L, pmin(12L, e$exposure) - e$entry)
index <- rep(seq_len(nrow(e)), observed_months)
month <- unlist(Map(function(first, n) seq.int(first + 1L, length.out = n),
                    e$entry, observed_months), use.names = FALSE)
person <- e[index, c("wt", "age_group", "parity_group",
  "marital_group", "education", "wealth_group", "residence", "region",
  "start_year", "cluster")]
person$month <- factor(month, levels = 1:12)
ended <- e$discontinued[index] & month == e$exposure[index]
person$outcome <- factor(ifelse(!ended, "continue",
  ifelse(e$reason[index] %in% c(2L, 8L), "excluded", "selected")),
  levels = c("continue", "selected", "excluded"))
stopifnot(nrow(e) > 3000L, nrow(person) > 25000L,
  sum(person$outcome == "selected") > 500L,
  sum(person$outcome == "excluded") > 500L)
model_formula <- outcome ~ month + age_group + parity_group +
  marital_group + education + wealth_group + residence + region + start_year
fit <- nnet::multinom(model_formula, data = person, weights = person$wt,
  maxit = 300, trace = FALSE, MaxNWts = 10000)
if (fit$convergence != 0L) stop("Model did not converge")
standard <- e[e$entry == 0L, ]
predict_risk <- function(model, variable = NULL, level = NULL,
                         weights = standard$wt) {x<-standard;if(!is.null(variable))x[[variable]]<-factor(level,levels=levels(x[[variable]]));fast_survey_cif(model,x,weights,'selected')}
life_table <- function(episodes) {
  survival <- 1
  incidence <- 0
  for (t in 1:12) {
    at_risk <- episodes$entry < t & episodes$exposure >= t
    denom <- sum(episodes$wt[at_risk])
    if (denom == 0) return(NA_real_)
    ending <- at_risk & episodes$discontinued & episodes$exposure == t
    selected <- ending & !(episodes$reason %in% c(2L, 8L))
    incidence <- incidence + survival * sum(episodes$wt[selected]) / denom
    survival <- survival * (1 - sum(episodes$wt[ending]) / denom)
  }
  100 * incidence
}
variables <- c("age_group", "parity_group", "marital_group", "education",
  "wealth_group", "residence", "region")
rows <- lapply(variables, function(variable) {
  do.call(rbind, lapply(levels(e[[variable]]), function(level) {
    sub <- e[e[[variable]] == level, ]
    data.frame(characteristic = variable, level = level,
      eligible_episodes = nrow(sub),
      selected_first_year_endings = sum(sub$discontinued &
        sub$reason %in% setdiff(unique(e$reason), c(2L, 8L)) &
        sub$exposure <= 12),
      unadjusted_12_month_probability_pct = life_table(sub),
      adjusted_12_month_probability_pct = predict_risk(fit, variable, level))
  }))
})
margins <- do.call(rbind, rows)
rownames(margins) <- NULL
overall <- predict_risk(fit)
write.csv(margins,
  file.path(out, "injectable_selected_reason_four_marital_four_parity_margins.csv"),
  row.names = FALSE)
write.csv(data.frame(eligible_episodes = nrow(e),
  observed_starts = nrow(standard), episode_months = nrow(person),
  selected_first_year_endings = sum(person$outcome == "selected"),
  excluded_first_year_endings = sum(person$outcome == "excluded"),
  unadjusted_overall_pct = life_table(e), adjusted_overall_pct = overall,
  convergence = fit$convergence),
  file.path(out, "injectable_selected_reason_four_marital_four_parity_audit.csv"),
  row.names = FALSE)
saveRDS(fit, file.path(out, "injectable_selected_reason_four_marital_four_parity_model.rds"))
cat(sprintf("Injectable-only specification converged; adjusted overall %.2f%%\n", overall))
print(margins, row.names = FALSE)

# Stratified rescaled PSU bootstrap for design-based percentile intervals.
# Resampling a PSU moves all of its women's episodes and episode-month rows
# together, preserving repeated episodes within women.
reps <- as.integer(Sys.getenv("BOOTSTRAP_REPS", "0"))
if (reps > 0L) {
  cluster_frame <- full_survey_frame()
  clusters_by_stratum <- split(cluster_frame$cluster, cluster_frame$stratum)
  stopifnot(all(lengths(clusters_by_stratum) > 1L))
  one_bootstrap <- function(rep_no) {
    set.seed(20261006L + rep_no)
    multiplier <- setNames(numeric(nrow(cluster_frame)), cluster_frame$cluster)
    for (ids in clusters_by_stratum) {
      n <- length(ids)
      draws <- sample.int(n, n - 1L, replace = TRUE)
      multiplier[ids] <- n / (n - 1) * tabulate(draws, nbins = n)
    }
    boot_wt <- person$wt * multiplier[person$cluster]
    standard_wt <- standard$wt * multiplier[standard$cluster]
    boot_data <- person
    boot_data$boot_wt <- boot_wt
    m <- tryCatch(nnet::multinom(model_formula, data = boot_data, weights = boot_wt, summ=2,
      maxit = 300, trace = FALSE, MaxNWts = 10000), error = function(err) {
        message(sprintf("Bootstrap %d error: %s", rep_no, conditionMessage(err)))
        NULL
      })
    if (!is.null(m) && m$convergence != 0L)
      message(sprintf("Bootstrap %d convergence code: %d", rep_no, m$convergence))
    if (is.null(m) || m$convergence != 0L)
      return(rep(NA_real_, nrow(margins) + 1L))
    c(predict_risk(m, weights = standard_wt),
      vapply(seq_len(nrow(margins)), function(j)
        predict_risk(m, margins$characteristic[j], margins$level[j],
          weights = standard_wt), numeric(1)))
  }
  boot <- do.call(rbind, parallel::mclapply(seq_len(reps), one_bootstrap,
    mc.cores = min(4L, parallel::detectCores()), mc.preschedule = FALSE))
  valid <- complete.cases(boot)
  if (sum(valid) < ceiling(.95 * reps))
    stop(sprintf("Only %d/%d bootstrap models converged", sum(valid), reps))
  column_names <- c("overall", paste(margins$characteristic, margins$level, sep="::"))
  colnames(boot) <- column_names
  write.csv(data.frame(replicate = seq_len(reps), boot, check.names = FALSE),
    file.path(out, "injectable_selected_reason_four_marital_four_parity_bootstrap.csv"),
    row.names = FALSE)
  bounds <- apply(boot[valid, -1L, drop = FALSE], 2, quantile,
    probs = c(.025, .975), names = FALSE)
  margins$ci_low <- bounds[1, ]
  margins$ci_high <- bounds[2, ]
  write.csv(margins,
    file.path(out, "injectable_selected_reason_four_marital_four_parity_margins.csv"),
    row.names = FALSE)
  overall_bounds <- quantile(boot[valid, 1L], probs = c(.025, .975), names = FALSE)
  write.csv(data.frame(estimate = overall, ci_low = overall_bounds[1],
    ci_high = overall_bounds[2], valid_reps = sum(valid), requested_reps = reps),
    file.path(out, "injectable_selected_reason_four_marital_four_parity_overall_ci.csv"),
    row.names = FALSE)
  cat(sprintf("Bootstrap converged: %d/%d; overall CI %.2f–%.2f%%\n",
    sum(valid), reps, overall_bounds[1], overall_bounds[2]))
}
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 77_pill_only_full_selected_regression.R
# LANGUAGE: R
MODULES[["77_pill_only_full_selected_regression.R"]] <- list(
 language="R",
 packaged_sha256="36641cb3ff61bb22fd6b742c2298e40b2e876ae5eaf1042e04a8fe4aa3acfca1",
 args=character(),
 code=r"-----(
# Algebraically identical monthly multinomial prediction, with the design
# matrix constructed once instead of once per duration month.
fast_survey_cif<-function(model,x,weights,event){
 x$month<-factor(1,levels=1:12)
 X<-model.matrix(delete.response(terms(model)),data=x,contrasts.arg=model$contrasts)
 b<-coef(model);eta<-X[,colnames(b),drop=FALSE]%*%t(b)
 S<-rep(1,nrow(x));F<-numeric(nrow(x));j<-match(event,rownames(b))
 for(t in 1:12){off<-if(t==1)rep(0,nrow(b))else b[,paste0('month',t)];ee<-exp(sweep(eta,2,off,'+'));den<-1+rowSums(ee);F<-F+S*ee[,j]/den;S<-S/den}
 100*weighted.mean(F,weights)
}

# Full DHS sampling frame, including PSUs with no eligible outcome records.
full_survey_frame <- function(){
 r<-Sys.getenv('ETHIOPIA_PROJECT_ROOT'); stopifnot(nzchar(r))
 x<-readRDS(file.path(r,'Data/ET2024DHS__ETIR8ADT__IR_raw.rds'))
 unique(data.frame(cluster=paste(as.integer(x$v022),as.integer(x$v021),sep=':'),stratum=as.integer(x$v022)))
}
complete_survey_data <- function(d){
 r<-Sys.getenv('ETHIOPIA_PROJECT_ROOT');x<-readRDS(file.path(r,'Data/ET2024DHS__ETIR8ADT__IR_raw.rds'))
 f<-unique(data.frame(v021=as.integer(x$v021),v022=as.integer(x$v022)))
 key<-function(a,b)paste(a,b,sep=':');miss<-f[!key(f$v021,f$v022)%in%key(d$v021,d$v022),]
 if(nrow(miss)){z<-d[rep(1L,nrow(miss)),,drop=FALSE];z$v021<-miss$v021;z$v022<-miss$v022;z$wt<-0;d<-rbind(d,z)}
 d
}
#!/usr/bin/env Rscript
# Pill-only sensitivity model. This leaves the working HTML and full-method model
# untouched. Original-method pill episodes
# enter a three-outcome discrete-time competing-event model: continue, selected
# reason ending, wanted-pregnancy/partner-disapproval ending. Selected reasons
# include all recorded reasons except the latter two. Survey weights enter the
# model and standardization. Marital status is v501 at interview, not at start.
project <- Sys.getenv("ETHIOPIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
out <- file.path(project, "output", "Supporting_data")
if (!requireNamespace("nnet", quietly = TRUE))
  stop("nnet is required; install.packages('nnet')")
e <- read.csv(file.path(out, "selected_reason_exploratory_episode_covariates.csv"))
ir <- readRDS(file.path(project, "Data/ET2024DHS__ETIR8ADT__IR_raw.rds"))
i <- e$woman_row
birth_cols <- grep("^b3_", names(ir), value = TRUE)
births <- as.matrix(ir[i, birth_cols])
parity <- rowSums(!is.na(births) & births <= e$start)
marital <- as.integer(ir$v501[i])
stopifnot(!anyNA(parity), all(marital %in% 0:5))
e$parity_group <- factor(ifelse(parity == 0, "0",
  ifelse(parity <= 2, "1–2", ifelse(parity <= 4, "3–4", "5+"))),
  levels = c("0", "1–2", "3–4", "5+"))
e$marital_group <- factor(ifelse(marital == 0L, "Never in union",
  ifelse(marital == 2L, "Living together",
  ifelse(marital == 1L, "Married", "Divorced/widowed/separated"))),
  levels = c("Never in union", "Living together", "Married",
             "Divorced/widowed/separated"))
e$method_group <- factor(e$method_group,
  levels = c("Injectables", "Implants", "Pill", "IUD", "Other modern"))
# Restrict at the episode level before constructing person-months and risk sets.
e <- droplevels(e[e$method_group == "Pill", ])
e$age_group <- factor(e$age_group,
  levels = c("15-19", "20-24", "25-34", "35-49"))
e$education <- factor(e$education, levels = c("None", "Primary", "Secondary+"))
e$wealth_group <- factor(e$wealth_group,
  levels = c("Poorest 40%", "Middle 20%", "Richest 40%"))
e$residence <- factor(e$residence, levels = c("Rural", "Urban"))
e$region <- factor(e$region)
e$start_year <- factor((e$start - 1L) %/% 12L + 1900L)
observed_months <- pmax(0L, pmin(12L, e$exposure) - e$entry)
index <- rep(seq_len(nrow(e)), observed_months)
month <- unlist(Map(function(first, n) seq.int(first + 1L, length.out = n),
                    e$entry, observed_months), use.names = FALSE)
person <- e[index, c("wt", "age_group", "parity_group",
  "marital_group", "education", "wealth_group", "residence", "region",
  "start_year", "cluster")]
person$month <- factor(month, levels = 1:12)
ended <- e$discontinued[index] & month == e$exposure[index]
person$outcome <- factor(ifelse(!ended, "continue",
  ifelse(e$reason[index] %in% c(2L, 8L), "excluded", "selected")),
  levels = c("continue", "selected", "excluded"))
stopifnot(nrow(e) > 700L, nrow(person) > 4000L,
  sum(person$outcome == "selected") > 300L)
model_formula <- outcome ~ month + age_group + parity_group +
  marital_group + education + wealth_group + residence + region + start_year
fit <- nnet::multinom(model_formula, data = person, weights = person$wt,
  maxit = 300, trace = FALSE, MaxNWts = 10000)
if (fit$convergence != 0L) stop("Model did not converge")
standard <- e[e$entry == 0L, ]
predict_risk <- function(model, variable = NULL, level = NULL,
                         weights = standard$wt) {x<-standard;if(!is.null(variable))x[[variable]]<-factor(level,levels=levels(x[[variable]]));fast_survey_cif(model,x,weights,'selected')}
life_table <- function(episodes) {
  survival <- 1
  incidence <- 0
  for (t in 1:12) {
    at_risk <- episodes$entry < t & episodes$exposure >= t
    denom <- sum(episodes$wt[at_risk])
    if (denom == 0) return(NA_real_)
    ending <- at_risk & episodes$discontinued & episodes$exposure == t
    selected <- ending & !(episodes$reason %in% c(2L, 8L))
    incidence <- incidence + survival * sum(episodes$wt[selected]) / denom
    survival <- survival * (1 - sum(episodes$wt[ending]) / denom)
  }
  100 * incidence
}
variables <- c("age_group", "parity_group", "marital_group", "education",
  "wealth_group", "residence", "region")
rows <- lapply(variables, function(variable) {
  do.call(rbind, lapply(levels(e[[variable]]), function(level) {
    sub <- e[e[[variable]] == level, ]
    data.frame(characteristic = variable, level = level,
      eligible_episodes = nrow(sub),
      selected_first_year_endings = sum(sub$discontinued &
        sub$reason %in% setdiff(unique(e$reason), c(2L, 8L)) &
        sub$exposure <= 12),
      unadjusted_12_month_probability_pct = life_table(sub),
      adjusted_12_month_probability_pct = predict_risk(fit, variable, level))
  }))
})
margins <- do.call(rbind, rows)
rownames(margins) <- NULL
overall <- predict_risk(fit)
write.csv(margins,
  file.path(out, "pill_selected_reason_four_marital_four_parity_margins.csv"),
  row.names = FALSE)
write.csv(data.frame(eligible_episodes = nrow(e),
  observed_starts = nrow(standard), episode_months = nrow(person),
  selected_first_year_endings = sum(person$outcome == "selected"),
  excluded_first_year_endings = sum(person$outcome == "excluded"),
  unadjusted_overall_pct = life_table(e), adjusted_overall_pct = overall,
  convergence = fit$convergence),
  file.path(out, "pill_selected_reason_four_marital_four_parity_audit.csv"),
  row.names = FALSE)
saveRDS(fit, file.path(out, "pill_selected_reason_four_marital_four_parity_model.rds"))
cat(sprintf("Pill-only specification converged; adjusted overall %.2f%%\n", overall))
print(margins, row.names = FALSE)

# Stratified rescaled PSU bootstrap for design-based percentile intervals.
# Resampling a PSU moves all of its women's episodes and episode-month rows
# together, preserving repeated episodes within women.
reps <- as.integer(Sys.getenv("BOOTSTRAP_REPS", "0"))
if (reps > 0L) {
  # Sample the original survey PSU frame, not only PSUs that contributed a pill
  # episode. Restriction to pill users can leave a single contributing PSU in
  # a stratum, while the original design still contains other PSUs.
  cluster_frame <- full_survey_frame()
  clusters_by_stratum <- split(cluster_frame$cluster, cluster_frame$stratum)
  stopifnot(all(lengths(clusters_by_stratum) > 1L))
  one_bootstrap <- function(rep_no) {
    set.seed(20261006L + rep_no)
    multiplier <- setNames(numeric(nrow(cluster_frame)), cluster_frame$cluster)
    for (ids in clusters_by_stratum) {
      n <- length(ids)
      draws <- sample.int(n, n - 1L, replace = TRUE)
      multiplier[ids] <- n / (n - 1) * tabulate(draws, nbins = n)
    }
    boot_wt <- person$wt * multiplier[person$cluster]
    standard_wt <- standard$wt * multiplier[standard$cluster]
    boot_data <- person
    boot_data$boot_wt <- boot_wt
    m <- tryCatch(nnet::multinom(model_formula, data = boot_data, weights = boot_wt, summ=2,
      maxit = 300, trace = FALSE, MaxNWts = 10000), error = function(err) {
        message(sprintf("Bootstrap %d error: %s", rep_no, conditionMessage(err)))
        NULL
      })
    if (!is.null(m) && m$convergence != 0L)
      message(sprintf("Bootstrap %d convergence code: %d", rep_no, m$convergence))
    if (is.null(m) || m$convergence != 0L)
      return(rep(NA_real_, nrow(margins) + 1L))
    c(predict_risk(m, weights = standard_wt),
      vapply(seq_len(nrow(margins)), function(j)
        predict_risk(m, margins$characteristic[j], margins$level[j],
          weights = standard_wt), numeric(1)))
  }
  boot <- do.call(rbind, parallel::mclapply(seq_len(reps), one_bootstrap,
    mc.cores = min(4L, parallel::detectCores()), mc.preschedule = FALSE))
  valid <- complete.cases(boot)
  if (sum(valid) < ceiling(.95 * reps))
    stop(sprintf("Only %d/%d bootstrap models converged", sum(valid), reps))
  column_names <- c("overall", paste(margins$characteristic, margins$level, sep="::"))
  colnames(boot) <- column_names
  write.csv(data.frame(replicate = seq_len(reps), boot, check.names = FALSE),
    file.path(out, "pill_selected_reason_four_marital_four_parity_bootstrap.csv"),
    row.names = FALSE)
  bounds <- apply(boot[valid, -1L, drop = FALSE], 2, quantile,
    probs = c(.025, .975), names = FALSE)
  margins$ci_low <- bounds[1, ]
  margins$ci_high <- bounds[2, ]
  write.csv(margins,
    file.path(out, "pill_selected_reason_four_marital_four_parity_margins.csv"),
    row.names = FALSE)
  overall_bounds <- quantile(boot[valid, 1L], probs = c(.025, .975), names = FALSE)
  write.csv(data.frame(estimate = overall, ci_low = overall_bounds[1],
    ci_high = overall_bounds[2], valid_reps = sum(valid), requested_reps = reps),
    file.path(out, "pill_selected_reason_four_marital_four_parity_overall_ci.csv"),
    row.names = FALSE)
  cat(sprintf("Bootstrap converged: %d/%d; overall CI %.2f–%.2f%%\n",
    sum(valid), reps, overall_bounds[1], overall_bounds[2]))
}
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 79_age_15_19_selected_by_method.R
# LANGUAGE: R
MODULES[["79_age_15_19_selected_by_method.R"]] <- list(
 language="R",
 packaged_sha256="cd316e8cbd3eba0e39111a8bdac2e7c8af9677bf0dde04fbbff3d144314c279c",
 args=character(),
 code=r"-----(
# Full DHS sampling frame, including PSUs with no eligible outcome records.
full_survey_frame <- function(){
 r<-Sys.getenv('ETHIOPIA_PROJECT_ROOT'); stopifnot(nzchar(r))
 x<-readRDS(file.path(r,'Data/ET2024DHS__ETIR8ADT__IR_raw.rds'))
 unique(data.frame(cluster=paste(as.integer(x$v022),as.integer(x$v021),sep=':'),stratum=as.integer(x$v022)))
}
complete_survey_data <- function(d){
 r<-Sys.getenv('ETHIOPIA_PROJECT_ROOT');x<-readRDS(file.path(r,'Data/ET2024DHS__ETIR8ADT__IR_raw.rds'))
 f<-unique(data.frame(v021=as.integer(x$v021),v022=as.integer(x$v022)))
 key<-function(a,b)paste(a,b,sep=':');miss<-f[!key(f$v021,f$v022)%in%key(d$v021,d$v022),]
 if(nrow(miss)){z<-d[rep(1L,nrow(miss)),,drop=FALSE];z$v021<-miss$v021;z$v022<-miss$v022;z$wt<-0;d<-rbind(d,z)}
 d
}
#!/usr/bin/env Rscript
# Descriptive 12-month selected-reason cumulative incidence for method episodes
# begun at ages 15–19. Wanted pregnancy and partner disapproval remain competing
# endings. Resample DHS PSUs within strata for uncertainty; resample the full
# eligible-episode survey PSU frame so sparse method cells do not redefine it.
project <- Sys.getenv("ETHIOPIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
path <- file.path(project, "output/Supporting_data")
e <- read.csv(file.path(path, "selected_reason_exploratory_episode_covariates.csv"))
frame <- full_survey_frame()
frame$idx <- seq_len(nrow(frame))
e$idx <- frame$idx[match(e$cluster, frame$cluster)]
stopifnot(!anyNA(e$idx), all(table(frame$stratum) > 1L))
groups <- c("All modern", "Injectables", "Implants", "Pill", "IUD", "Other modern")
K <- nrow(frame)
arrays <- lapply(groups, function(group) {
  scope <- e$age_group == "15-19" &
    (group == "All modern" | e$method_group == group)
  risk <- all <- selected <- matrix(0, K, 12L)
  for (t in 1:12) {
    at <- scope & e$entry < t & e$exposure >= t
    end <- at & e$discontinued & e$exposure == t
    pick <- end & !(e$reason %in% c(2L, 8L))
    for (entry in list(list(mask = at, target = "risk"),
                       list(mask = end, target = "all"),
                       list(mask = pick, target = "selected"))) {
      z <- rowsum(e$wt[entry$mask], e$idx[entry$mask], reorder = FALSE)
      if (nrow(z)) {
        id <- as.integer(rownames(z))
        if (entry$target == "risk") risk[id, t] <- z[, 1]
        if (entry$target == "all") all[id, t] <- z[, 1]
        if (entry$target == "selected") selected[id, t] <- z[, 1]
      }
    }
  }
  list(scope = scope, risk = risk, all = all, selected = selected)
})
cif <- function(a, multiplier) {
  R <- as.numeric(crossprod(multiplier, a$risk))
  A <- as.numeric(crossprod(multiplier, a$all))
  D <- as.numeric(crossprod(multiplier, a$selected))
  if (any(R <= 0) || any(A > R + 1e-6)) return(NA_real_)
  survival <- 1
  incidence <- 0
  for (t in 1:12) {
    incidence <- incidence + survival * D[t] / R[t]
    survival <- survival * (1 - A[t] / R[t])
  }
  100 * incidence
}
point <- vapply(arrays, cif, numeric(1), multiplier = rep(1, K))
B <- 1000L
draws <- matrix(NA_real_, B, length(groups), dimnames = list(NULL, groups))
by_stratum <- split(frame$idx, frame$stratum)
for (b in seq_len(B)) {
  set.seed(20261006L + b)
  mult <- numeric(K)
  for (ids in by_stratum) {
    n <- length(ids)
    mult[ids] <- n / (n - 1L) * tabulate(sample.int(n, n - 1L,
      replace = TRUE), nbins = n)
  }
  draws[b, ] <- vapply(arrays, cif, numeric(1), multiplier = mult)
}
result <- data.frame(method = groups,
  eligible_episodes = vapply(arrays, function(a) sum(a$scope), integer(1)),
  weighted_episodes = vapply(arrays, function(a) sum(e$wt[a$scope]), numeric(1)),
  selected_first_year_endings = vapply(arrays, function(a)
    sum(a$scope & e$discontinued & e$exposure <= 12L &
          e$entry < e$exposure & !(e$reason %in% c(2L, 8L))), integer(1)),
  probability_pct = point,
  ci_low = apply(draws, 2, quantile, .025, na.rm = TRUE),
  ci_high = apply(draws, 2, quantile, .975, na.rm = TRUE),
  valid_replicates = colSums(!is.na(draws)))
write.csv(result, file.path(path, "selected_reason_age_15_19_by_method.csv"),
  row.names = FALSE)
print(result, row.names = FALSE)
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 80_descriptive_characteristics_selected_reasons.R
# LANGUAGE: R
MODULES[["80_descriptive_characteristics_selected_reasons.R"]] <- list(
 language="R",
 packaged_sha256="821feedd076c9562f5c34bb407b90459db72b743e83e65e96da70be12944cab2",
 args=character(),
 code=r"-----(
# Full DHS sampling frame, including PSUs with no eligible outcome records.
full_survey_frame <- function(){
 r<-Sys.getenv('ETHIOPIA_PROJECT_ROOT'); stopifnot(nzchar(r))
 x<-readRDS(file.path(r,'Data/ET2024DHS__ETIR8ADT__IR_raw.rds'))
 unique(data.frame(cluster=paste(as.integer(x$v022),as.integer(x$v021),sep=':'),stratum=as.integer(x$v022)))
}
complete_survey_data <- function(d){
 r<-Sys.getenv('ETHIOPIA_PROJECT_ROOT');x<-readRDS(file.path(r,'Data/ET2024DHS__ETIR8ADT__IR_raw.rds'))
 f<-unique(data.frame(v021=as.integer(x$v021),v022=as.integer(x$v022)))
 key<-function(a,b)paste(a,b,sep=':');miss<-f[!key(f$v021,f$v022)%in%key(d$v021,d$v022),]
 if(nrow(miss)){z<-d[rep(1L,nrow(miss)),,drop=FALSE];z$v021<-miss$v021;z$v022<-miss$v022;z$wt<-0;d<-rbind(d,z)}
 d
}
#!/usr/bin/env Rscript
# Descriptive subgroup table for 12-month original-method endings for any
# recorded reason except wanted pregnancy and husband/partner disapproval.
# Rates are weighted competing-risk cumulative incidences; the seven reason
# shares divide reason-specific 12-month cumulative incidences by the
# selected-reason total, so they decompose that same 12-month probability.
project <- Sys.getenv("ETHIOPIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
out <- file.path(project, "output/Supporting_data")
e <- read.csv(file.path(out, "selected_reason_exploratory_episode_covariates.csv"))
ir <- readRDS(file.path(project, "Data/ET2024DHS__ETIR8ADT__IR_raw.rds"))
i <- e$woman_row
births <- as.matrix(ir[i, grep("^b3_", names(ir), value = TRUE)])
parity <- rowSums(!is.na(births) & births <= e$start)
marital <- as.integer(ir$v501[i])
wealth <- as.integer(ir$v190[i])
e$parity_four <- factor(ifelse(parity == 0, "0", ifelse(parity <= 2,
  "1–2", ifelse(parity <= 4, "3–4", "5+"))),
  levels = c("0", "1–2", "3–4", "5+"))
e$marital_four <- factor(ifelse(marital == 0L, "Never in union",
  ifelse(marital == 2L, "Living together", ifelse(marital == 1L,
  "Married", "Divorced/widowed/separated"))),
  levels = c("Never in union", "Living together", "Married",
             "Divorced/widowed/separated"))
e$wealth_five <- factor(c("Poorest", "Poorer", "Middle", "Richer",
  "Richest")[wealth], levels = c("Poorest", "Poorer", "Middle",
                               "Richer", "Richest"))
e$age_group <- factor(e$age_group,
  levels = c("15-19", "20-24", "25-34", "35-49"))
e$education <- factor(e$education,
  levels = c("None", "Primary", "Secondary+"))
e$residence <- factor(e$residence, levels = c("Rural", "Urban"))
variables <- c(age_group = "Age at method start",
  parity_four = "Live births at method start",
  marital_four = "Marital status at interview",
  education = "Education at interview",
  wealth_five = "Wealth quintile at interview",
  residence = "Residence at interview")
reason_names <- c("Method failure", "Other fertility-related",
  "Bleeding changes", "Side effects/health", "Wanted more effective method",
  "Access/cost/inconvenience", "Other recorded")
reason_codes <- c(1L, 3L, 4L, 5L, 6L, 7L, 9L)
frame <- full_survey_frame()
frame$idx <- seq_len(nrow(frame))
e$idx <- frame$idx[match(e$cluster, frame$cluster)]
K <- nrow(frame)
stopifnot(nrow(e) == 8611L, !anyNA(e$idx),
  all(table(frame$stratum) > 1L))

# Accumulate weighted risk sets and event totals by PSU and duration month.
# Delayed-entry episodes contribute only after the month they entered view.
make_arrays <- function(scope) {
  risk <- all <- selected <- matrix(0, K, 12L)
  reason <- array(0, dim = c(K, 12L, length(reason_codes)))
  for (t in 1:12) {
    at <- scope & e$entry < t & e$exposure >= t
    ending <- at & e$discontinued & e$exposure == t
    picked <- ending & !(e$reason %in% c(2L, 8L))
    for (spec in list(list(mask = at, target = "risk"),
                      list(mask = ending, target = "all"),
                      list(mask = picked, target = "selected"))) {
      z <- rowsum(e$wt[spec$mask], e$idx[spec$mask], reorder = FALSE)
      if (nrow(z)) {
        j <- as.integer(rownames(z))
        if (spec$target == "risk") risk[j, t] <- z[, 1]
        if (spec$target == "all") all[j, t] <- z[, 1]
        if (spec$target == "selected") selected[j, t] <- z[, 1]
      }
    }
    for (r in seq_along(reason_codes)) {
      mask <- ending & e$reason == reason_codes[r]
      z <- rowsum(e$wt[mask], e$idx[mask], reorder = FALSE)
      if (nrow(z)) reason[as.integer(rownames(z)), t, r] <- z[, 1]
    }
  }
  list(risk = risk, all = all, selected = selected, reason = reason)
}
cif <- function(a, multiplier) {
  R <- as.numeric(crossprod(multiplier, a$risk))
  A <- as.numeric(crossprod(multiplier, a$all))
  D <- as.numeric(crossprod(multiplier, a$selected))
  if (any(R <= 0) || any(A > R + 1e-6)) return(NA_real_)
  surv <- 1
  inc <- 0
  for (t in 1:12) {
    inc <- inc + surv * D[t] / R[t]
    surv <- surv * (1 - A[t] / R[t])
  }
  100 * inc
}
cause_cif <- function(a, multiplier) {
  R <- as.numeric(crossprod(multiplier, a$risk))
  A <- as.numeric(crossprod(multiplier, a$all))
  inc <- numeric(length(reason_codes))
  surv <- 1
  for (t in 1:12) {
    for (r in seq_along(reason_codes)) {
      D <- sum(multiplier * a$reason[, t, r])
      inc[r] <- inc[r] + surv * D / R[t]
    }
    surv <- surv * (1 - A[t] / R[t])
  }
  100 * inc
}
cells <- do.call(rbind, lapply(names(variables), function(variable)
  do.call(rbind, lapply(levels(e[[variable]]), function(level)
    data.frame(variable = variable, characteristic = variables[[variable]],
      group = level, stringsAsFactors = FALSE)))))
arrays <- lapply(seq_len(nrow(cells)), function(j)
  make_arrays(e[[cells$variable[j]]] == cells$group[j]))
point <- vapply(arrays, cif, numeric(1), multiplier = rep(1, K))

# Rescaled stratified PSU bootstrap. All episodes of a woman/PSU move together.
B <- 1000L
draws <- matrix(NA_real_, B, nrow(cells))
by_stratum <- split(frame$idx, frame$stratum)
for (b in seq_len(B)) {
  set.seed(20261006L + b)
  mult <- numeric(K)
  for (ids in by_stratum) {
    n <- length(ids)
    mult[ids] <- n / (n - 1L) * tabulate(sample.int(n, n - 1L,
      replace = TRUE), nbins = n)
  }
  draws[b, ] <- vapply(arrays, cif, numeric(1), multiplier = mult)
}
cells$eligible_episodes <- vapply(seq_len(nrow(cells)), function(j)
  sum(e[[cells$variable[j]]] == cells$group[j]), integer(1))
cells$weighted_episodes <- vapply(seq_len(nrow(cells)), function(j)
  sum(e$wt[e[[cells$variable[j]]] == cells$group[j]]), numeric(1))
cells$rate_pct <- point
cells$ci_low <- apply(draws, 2, quantile, .025, na.rm = TRUE)
cells$ci_high <- apply(draws, 2, quantile, .975, na.rm = TRUE)
cells$valid_replicates <- colSums(!is.na(draws))
stopifnot(all(cells$valid_replicates >= .95 * B))

# Normalize the seven reason-specific life-table contributions to the
# selected-reason probability. Balanced one-decimal rounding makes each
# subgroup's seven displayed shares sum to 100.0%.
round_to_100 <- function(pct) {
  low <- floor(pct * 10) / 10
  remainder <- as.integer(round((100 - sum(low)) * 10))
  if (remainder > 0L) {
    priority <- order(pct - low, decreasing = TRUE)
    low[priority[seq_len(remainder)]] <- low[priority[seq_len(remainder)]] + .1
  }
  stopifnot(abs(sum(low) - 100) < 1e-6)
  low
}
reason_rows <- vector("list", nrow(cells))
for (j in seq_len(nrow(cells))) {
  scope <- e[[cells$variable[j]]] == cells$group[j]
  ending <- scope & e$discontinued & e$entry < e$exposure &
    e$exposure <= 12L & !(e$reason %in% c(2L, 8L))
  cells$selected_endings_n[j] <- sum(ending)
  cells$selected_endings_weighted[j] <- sum(e$wt[ending])
  cause_pct <- cause_cif(arrays[[j]], rep(1, K))
  stopifnot(abs(sum(cause_pct) - cells$rate_pct[j]) < 1e-6)
  share <- round_to_100(100 * cause_pct / sum(cause_pct))
  order_ix <- order(-share, seq_along(share))
  reason_rows[[j]] <- data.frame(variable = cells$variable[j],
    characteristic = cells$characteristic[j], group = cells$group[j],
    rank = seq_along(order_ix), reason = reason_names[order_ix],
    cause_specific_12_month_probability_pct = cause_pct[order_ix],
    share_pct = share[order_ix])
}
reason_mix <- do.call(rbind, reason_rows)
rownames(reason_mix) <- NULL
write.csv(cells, file.path(out,
  "selected_reason_descriptive_characteristics_rates.csv"), row.names = FALSE)
write.csv(reason_mix, file.path(out,
  "selected_reason_descriptive_characteristics_reason_mix.csv"), row.names = FALSE)
print(cells[, c("characteristic", "group", "eligible_episodes",
  "selected_endings_n", "rate_pct", "ci_low", "ci_high")], row.names = FALSE)
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 82_descriptive_characteristics_method_experience_reasons.R
# LANGUAGE: R
MODULES[["82_descriptive_characteristics_method_experience_reasons.R"]] <- list(
 language="R",
 packaged_sha256="834c9fee506b2722967819d4029dd0c3a96e557f1533c45e34bce9098c8afe95",
 args=character(),
 code=r"-----(
# Full DHS sampling frame, including PSUs with no eligible outcome records.
full_survey_frame <- function(){
 r<-Sys.getenv('ETHIOPIA_PROJECT_ROOT'); stopifnot(nzchar(r))
 x<-readRDS(file.path(r,'Data/ET2024DHS__ETIR8ADT__IR_raw.rds'))
 unique(data.frame(cluster=paste(as.integer(x$v022),as.integer(x$v021),sep=':'),stratum=as.integer(x$v022)))
}
complete_survey_data <- function(d){
 r<-Sys.getenv('ETHIOPIA_PROJECT_ROOT');x<-readRDS(file.path(r,'Data/ET2024DHS__ETIR8ADT__IR_raw.rds'))
 f<-unique(data.frame(v021=as.integer(x$v021),v022=as.integer(x$v022)))
 key<-function(a,b)paste(a,b,sep=':');miss<-f[!key(f$v021,f$v022)%in%key(d$v021,d$v022),]
 if(nrow(miss)){z<-d[rep(1L,nrow(miss)),,drop=FALSE];z$v021<-miss$v021;z$v022<-miss$v022;z$wt<-0;d<-rbind(d,z)}
 d
}
#!/usr/bin/env Rscript
# Descriptive subgroup table for 12-month original-method endings for any
# recorded reason except wanted pregnancy, husband/partner disapproval, other fertility-related, and other recorded reasons.
# Rates are weighted competing-risk cumulative incidences; the seven reason
# shares divide reason-specific 12-month cumulative incidences by the
# selected-reason total, so they decompose that same 12-month probability.
project <- Sys.getenv("ETHIOPIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
out <- file.path(project, "output/Supporting_data")
e <- read.csv(file.path(out, "selected_reason_exploratory_episode_covariates.csv"))
ir <- readRDS(file.path(project, "Data/ET2024DHS__ETIR8ADT__IR_raw.rds"))
i <- e$woman_row
births <- as.matrix(ir[i, grep("^b3_", names(ir), value = TRUE)])
parity <- rowSums(!is.na(births) & births <= e$start)
marital <- as.integer(ir$v501[i])
wealth <- as.integer(ir$v190[i])
e$parity_four <- factor(ifelse(parity == 0, "0", ifelse(parity <= 2,
  "1–2", ifelse(parity <= 4, "3–4", "5+"))),
  levels = c("0", "1–2", "3–4", "5+"))
e$marital_four <- factor(ifelse(marital == 0L, "Never in union",
  ifelse(marital == 2L, "Living together", ifelse(marital == 1L,
  "Married", "Divorced/widowed/separated"))),
  levels = c("Never in union", "Living together", "Married",
             "Divorced/widowed/separated"))
e$wealth_five <- factor(c("Poorest", "Poorer", "Middle", "Richer",
  "Richest")[wealth], levels = c("Poorest", "Poorer", "Middle",
                               "Richer", "Richest"))
e$age_group <- factor(e$age_group,
  levels = c("15-19", "20-24", "25-34", "35-49"))
e$education <- factor(e$education,
  levels = c("None", "Primary", "Secondary+"))
e$residence <- factor(e$residence, levels = c("Rural", "Urban"))
variables <- c(age_group = "Age at method start",
  parity_four = "Live births at method start",
  marital_four = "Marital status at interview",
  education = "Education at interview",
  wealth_five = "Wealth quintile at interview",
  residence = "Residence at interview")
reason_names <- c("Method failure", "Bleeding changes", "Side effects/health",
  "Wanted more effective method", "Access/cost/inconvenience")
reason_codes <- c(1L, 4L, 5L, 6L, 7L)
frame <- full_survey_frame()
frame$idx <- seq_len(nrow(frame))
e$idx <- frame$idx[match(e$cluster, frame$cluster)]
K <- nrow(frame)
stopifnot(nrow(e) == 8611L, !anyNA(e$idx),
  all(table(frame$stratum) > 1L))

# Accumulate weighted risk sets and event totals by PSU and duration month.
# Delayed-entry episodes contribute only after the month they entered view.
make_arrays <- function(scope) {
  risk <- all <- selected <- matrix(0, K, 12L)
  reason <- array(0, dim = c(K, 12L, length(reason_codes)))
  for (t in 1:12) {
    at <- scope & e$entry < t & e$exposure >= t
    ending <- at & e$discontinued & e$exposure == t
    picked <- ending & !(e$reason %in% c(2L, 3L, 8L, 9L))
    for (spec in list(list(mask = at, target = "risk"),
                      list(mask = ending, target = "all"),
                      list(mask = picked, target = "selected"))) {
      z <- rowsum(e$wt[spec$mask], e$idx[spec$mask], reorder = FALSE)
      if (nrow(z)) {
        j <- as.integer(rownames(z))
        if (spec$target == "risk") risk[j, t] <- z[, 1]
        if (spec$target == "all") all[j, t] <- z[, 1]
        if (spec$target == "selected") selected[j, t] <- z[, 1]
      }
    }
    for (r in seq_along(reason_codes)) {
      mask <- ending & e$reason == reason_codes[r]
      z <- rowsum(e$wt[mask], e$idx[mask], reorder = FALSE)
      if (nrow(z)) reason[as.integer(rownames(z)), t, r] <- z[, 1]
    }
  }
  list(risk = risk, all = all, selected = selected, reason = reason)
}
cif <- function(a, multiplier) {
  R <- as.numeric(crossprod(multiplier, a$risk))
  A <- as.numeric(crossprod(multiplier, a$all))
  D <- as.numeric(crossprod(multiplier, a$selected))
  if (any(R <= 0) || any(A > R + 1e-6)) return(NA_real_)
  surv <- 1
  inc <- 0
  for (t in 1:12) {
    inc <- inc + surv * D[t] / R[t]
    surv <- surv * (1 - A[t] / R[t])
  }
  100 * inc
}
cause_cif <- function(a, multiplier) {
  R <- as.numeric(crossprod(multiplier, a$risk))
  A <- as.numeric(crossprod(multiplier, a$all))
  inc <- numeric(length(reason_codes))
  surv <- 1
  for (t in 1:12) {
    for (r in seq_along(reason_codes)) {
      D <- sum(multiplier * a$reason[, t, r])
      inc[r] <- inc[r] + surv * D / R[t]
    }
    surv <- surv * (1 - A[t] / R[t])
  }
  100 * inc
}
cells <- do.call(rbind, lapply(names(variables), function(variable)
  do.call(rbind, lapply(levels(e[[variable]]), function(level)
    data.frame(variable = variable, characteristic = variables[[variable]],
      group = level, stringsAsFactors = FALSE)))))
arrays <- lapply(seq_len(nrow(cells)), function(j)
  make_arrays(e[[cells$variable[j]]] == cells$group[j]))
point <- vapply(arrays, cif, numeric(1), multiplier = rep(1, K))

# Rescaled stratified PSU bootstrap. All episodes of a woman/PSU move together.
B <- 1000L
draws <- matrix(NA_real_, B, nrow(cells))
by_stratum <- split(frame$idx, frame$stratum)
for (b in seq_len(B)) {
  set.seed(20261007L + b)
  mult <- numeric(K)
  for (ids in by_stratum) {
    n <- length(ids)
    mult[ids] <- n / (n - 1L) * tabulate(sample.int(n, n - 1L,
      replace = TRUE), nbins = n)
  }
  draws[b, ] <- vapply(arrays, cif, numeric(1), multiplier = mult)
}
cells$eligible_episodes <- vapply(seq_len(nrow(cells)), function(j)
  sum(e[[cells$variable[j]]] == cells$group[j]), integer(1))
cells$weighted_episodes <- vapply(seq_len(nrow(cells)), function(j)
  sum(e$wt[e[[cells$variable[j]]] == cells$group[j]]), numeric(1))
cells$rate_pct <- point
cells$ci_low <- apply(draws, 2, quantile, .025, na.rm = TRUE)
cells$ci_high <- apply(draws, 2, quantile, .975, na.rm = TRUE)
cells$valid_replicates <- colSums(!is.na(draws))
stopifnot(all(cells$valid_replicates >= .95 * B))

# Normalize the five reason-specific life-table contributions to the
# selected-reason probability. Balanced one-decimal rounding makes each
# subgroup's five displayed shares sum to 100.0%.
round_to_100 <- function(pct) {
  low <- floor(pct * 10) / 10
  remainder <- as.integer(round((100 - sum(low)) * 10))
  if (remainder > 0L) {
    priority <- order(pct - low, decreasing = TRUE)
    low[priority[seq_len(remainder)]] <- low[priority[seq_len(remainder)]] + .1
  }
  stopifnot(abs(sum(low) - 100) < 1e-6)
  low
}
reason_rows <- vector("list", nrow(cells))
for (j in seq_len(nrow(cells))) {
  scope <- e[[cells$variable[j]]] == cells$group[j]
  ending <- scope & e$discontinued & e$entry < e$exposure &
    e$exposure <= 12L & !(e$reason %in% c(2L, 3L, 8L, 9L))
  cells$selected_endings_n[j] <- sum(ending)
  cells$selected_endings_weighted[j] <- sum(e$wt[ending])
  cause_pct <- cause_cif(arrays[[j]], rep(1, K))
  stopifnot(abs(sum(cause_pct) - cells$rate_pct[j]) < 1e-6)
  share <- round_to_100(100 * cause_pct / sum(cause_pct))
  order_ix <- order(-share, seq_along(share))
  reason_rows[[j]] <- data.frame(variable = cells$variable[j],
    characteristic = cells$characteristic[j], group = cells$group[j],
    rank = seq_along(order_ix), reason = reason_names[order_ix],
    cause_specific_12_month_probability_pct = cause_pct[order_ix],
    share_pct = share[order_ix])
}
reason_mix <- do.call(rbind, reason_rows)
rownames(reason_mix) <- NULL
write.csv(cells, file.path(out,
  "method_experience_descriptive_characteristics_rates.csv"), row.names = FALSE)
write.csv(reason_mix, file.path(out,
  "method_experience_descriptive_characteristics_reason_mix.csv"), row.names = FALSE)
print(cells[, c("characteristic", "group", "eligible_episodes",
  "selected_endings_n", "rate_pct", "ci_low", "ci_high")], row.names = FALSE)
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 84_method_experience_age_timepoints.R
# LANGUAGE: R
MODULES[["84_method_experience_age_timepoints.R"]] <- list(
 language="R",
 packaged_sha256="7fa899ccb4056b94d33039bc9262286756244905911ff91721f18241fd467e0a",
 args=character(),
 code=r"-----(#!/usr/bin/env Rscript
# A compact, descriptive example for the subgroup-reason section. These are
# survey-weighted competing-risk life-table point estimates by age at method
# start. The selected outcome excludes wanted pregnancy, partner disapproval,
# other fertility-related, and other recorded reasons; all endings still reduce
# the original-method continuation probability. Interval estimates for the
# 12-month selected outcome are produced separately in script 82.
project <- Sys.getenv("ETHIOPIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
out <- file.path(project, "output", "Supporting_data")
e <- read.csv(file.path(out, "selected_reason_exploratory_episode_covariates.csv"))
excluded <- c(2L, 3L, 8L, 9L)
groups <- c("15-19", "20-24", "25-34", "35-49")
rows <- list()
for (g in groups) {
  d <- e[e$age_group == g, ]
  survival <- 1
  selected_cif <- 0
  side_cif <- 0
  for (month in 1:12) {
    risk <- d$entry < month & d$exposure >= month
    denominator <- sum(d$wt[risk])
    ending <- risk & d$discontinued & d$exposure == month
    selected <- ending & !(d$reason %in% excluded)
    bleeding_or_health <- ending & d$reason %in% c(4L, 5L)
    selected_cif <- selected_cif + survival * sum(d$wt[selected]) / denominator
    side_cif <- side_cif + survival * sum(d$wt[bleeding_or_health]) / denominator
    survival <- survival * (1 - sum(d$wt[ending]) / denominator)
    if (month %in% c(3L, 6L, 12L)) {
      rows[[length(rows) + 1L]] <- data.frame(
        age_at_start = g, month = month, eligible_episodes = nrow(d),
        retained_reason_pct = 100 * selected_cif,
        bleeding_or_health_pct = 100 * side_cif,
        original_method_continuation_pct = 100 * survival)
    }
  }
}
result <- do.call(rbind, rows)
write.csv(result, file.path(out, "method_experience_age_timepoints.csv"),
          row.names = FALSE)
print(result, row.names = FALSE)
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 86_top_three_reasons_by_subgroup_and_method.R
# LANGUAGE: R
MODULES[["86_top_three_reasons_by_subgroup_and_method.R"]] <- list(
 language="R",
 packaged_sha256="132854e97e27255cabbfa5cacf4ba2faba09595627dcb2f2a96ce3dcc71b6dc4",
 args=character(),
 code=r"-----(#!/usr/bin/env Rscript
# Descriptive rankings of the five retained 12-month reason-specific
# cumulative incidences, by covariate group and original modern method.
# Wanted pregnancy, partner disapproval, other fertility-related and other
# recorded endings remain competing events. The table reports an all-modern
# panel plus injectable, pill and IUD panels; EC is absent from this cohort.
project <- Sys.getenv("ETHIOPIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
out <- file.path(project, "output", "Supporting_data")
e <- read.csv(file.path(out, "selected_reason_exploratory_episode_covariates.csv"))
ir <- readRDS(file.path(project, "Data/ET2024DHS__ETIR8ADT__IR_raw.rds"))
i <- e$woman_row
births <- as.matrix(ir[i, grep("^b3_", names(ir), value = TRUE)])
parity <- rowSums(!is.na(births) & births <= e$start)
marital <- as.integer(ir$v501[i])
wealth <- as.integer(ir$v190[i])
e$parity_four <- factor(ifelse(parity == 0, "0", ifelse(parity <= 2,
  "1–2", ifelse(parity <= 4, "3–4", "5+"))),
  levels = c("0", "1–2", "3–4", "5+"))
e$marital_four <- factor(ifelse(marital == 0L, "Never in union",
  ifelse(marital == 2L, "Living together", ifelse(marital == 1L,
  "Married", "Divorced/widowed/separated"))),
  levels = c("Never in union", "Living together", "Married",
             "Divorced/widowed/separated"))
e$wealth_five <- factor(c("Poorest", "Poorer", "Middle", "Richer",
  "Richest")[wealth], levels = c("Poorest", "Poorer", "Middle",
                             "Richer", "Richest"))
e$age_group <- factor(e$age_group,
  levels = c("15-19", "20-24", "25-34", "35-49"))
e$education <- factor(e$education,
  levels = c("None", "Primary", "Secondary+"))
e$residence <- factor(e$residence, levels = c("Rural", "Urban"))
variables <- c(age_group = "Age at method start",
  parity_four = "Live births at method start",
  marital_four = "Marital status at interview",
  education = "Education at interview",
  wealth_five = "Wealth quintile at interview",
  residence = "Residence at interview")
reason_names <- c("Method failure", "Bleeding changes",
  "Side effects/health", "Wanted more effective method",
  "Access/cost/inconvenience")
reason_codes <- c(1L, 4L, 5L, 6L, 7L)
excluded <- c(2L, 3L, 8L, 9L)

estimate <- function(d) {
  n <- nrow(d)
  observed <- d$discontinued & d$entry < d$exposure &
    d$exposure <= 12 & !(d$reason %in% excluded)
  events <- sum(observed)
  if (n == 0L) return(list(n = 0L, events = 0L,
    total = NA_real_, causes = rep(NA_real_, length(reason_codes))))
  survival <- 1
  causes <- numeric(length(reason_codes))
  for (t in 1:12) {
    risk <- d$entry < t & d$exposure >= t
    denominator <- sum(d$wt[risk])
    if (denominator <= 0) return(list(n = n, events = events,
      total = NA_real_, causes = rep(NA_real_, length(reason_codes))))
    ending <- risk & d$discontinued & d$exposure == t
    for (j in seq_along(reason_codes))
      causes[j] <- causes[j] + survival *
        sum(d$wt[ending & d$reason == reason_codes[j]]) / denominator
    survival <- survival * (1 - sum(d$wt[ending]) / denominator)
  }
  list(n = n, events = events, total = 100 * sum(causes),
       causes = 100 * causes)
}

rows <- list()
for (method in c("All modern", "Injectables", "Pill", "IUD")) {
  method_scope <- if (method == "All modern") rep(TRUE, nrow(e)) else
    e$method_group == method
  for (variable in c("overall", names(variables))) {
    levels_to_run <- if (variable == "overall") "All episodes" else
      levels(e[[variable]])
    for (level in levels_to_run) {
      scope <- method_scope & if (variable == "overall") rep(TRUE, nrow(e)) else
        e[[variable]] == level
      d <- e[scope, ]
      z <- estimate(d)
      share <- if (is.finite(z$total) && z$total > 0)
        100 * z$causes / z$total else rep(NA_real_, length(reason_codes))
      ranking <- order(-z$causes, seq_along(z$causes), na.last = TRUE)
      status <- if (z$events < 10L) "Withhold" else
        if (z$events < 30L) "Sparse" else "Display"
      for (rank in 1:3) {
        j <- ranking[rank]
        rows[[length(rows) + 1L]] <- data.frame(
          method = method, variable = variable,
          characteristic = if (variable == "overall") "Overall" else
            variables[[variable]], group = level,
          eligible_episodes = z$n, retained_endings = z$events,
          retained_12_month_probability_pct = z$total,
          status = status, rank = rank, reason = reason_names[j],
          reason_12_month_probability_pct = z$causes[j],
          share_of_retained_12_month_probability_pct = share[j])
      }
    }
  }
}
result <- do.call(rbind, rows)
stopifnot(nrow(result) == 23L * 4L * 3L,
  all(result$method[result$rank == 1] %in%
      c("All modern", "Injectables", "Pill", "IUD")))
write.csv(result, file.path(out, "top_three_retained_reasons_by_subgroup_method.csv"),
          row.names = FALSE)
print(with(subset(result, rank == 1),
  table(method, status)))
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 88_direct_next_month_modern_switch_life_table.R
# LANGUAGE: R
MODULES[["88_direct_next_month_modern_switch_life_table.R"]] <- list(
 language="R",
 packaged_sha256="249e49c2d1d873dc1d63eb7f2a77cac6179a724d672559d1d3c91bb9c62127c6",
 args=character(),
 code=r"-----(#!/usr/bin/env Rscript
# Direct modern-to-modern switching within 12 months of a modern-method start.
# Mirrors the weighted monthly multiple-decrement risk sets used to replicate
# Ethiopia DHS 2024-25 Table 7.11, but counts a switch only when a different
# modern method is recorded in the immediately following calendar month.
# The DHS published switching column is broader: it permits traditional-method
# destinations and the special one-month gap after "wanted more effective".

project <- Sys.getenv("ETHIOPIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
source_file <- file.path(project, 'Data/Derived/ethiopia_2024_table_7_11_episodes.rds')
raw_file <- file.path(project, 'Data/ET2024DHS__ETIR8ADT__IR_raw.rds')
out_file <- file.path(project, 'output/Supporting_data/direct_next_month_modern_switch_life_table.csv')
e <- readRDS(source_file)
x <- readRDS(raw_file)

# DHS contraceptive-calendar recode. The positions in this string correspond to
# the integer method_code values already assigned in the replicated episode set.
method_chars <- strsplit('123456789WNALCFEMS~', '')[[1]]
modern_codes <- c(1L,2L,3L,5L,6L,7L,11L,13L,17L,18L)
ec_code <- 16L

# Exclude emergency contraception from the primary risk set, consistent with
# the project’s main modern-method discontinuation analysis. Also require a
# non-EC modern destination for the primary estimate. Sensitivities below show
# how the estimate changes when EC is permitted as a destination or origin.
assign_switch <- function(d, destination_codes) {
  d$direct_modern_switch <- d$discontinued & !is.na(d$next_code) &
    d$next_code %in% destination_codes & d$next_code != d$method_code

  # Match the report-replication convention at the observation boundary:
  # the next calendar month must be read from the original vcal_1 string.
  for (j in which(d$boundary_reason)) {
    woman <- d$woman_row[j]
    position <- x$v018[woman] + 3L
    following_char <- substring(x$vcal_1[woman], position - 1L, position - 1L)
    following_code <- match(following_char, method_chars)
    d$direct_modern_switch[j] <- !is.na(following_code) &&
      following_code %in% destination_codes &&
      following_code != d$method_code[j]
  }
  stopifnot(!anyNA(d$direct_modern_switch),
            all(!d$direct_modern_switch | d$discontinued))
  d
}

life_table <- function(d) {
  survival <- 1
  switch_cif <- 0
  any_cif <- 0
  rows <- vector('list', 12L)
  for (month in 1:12) {
    risk_set <- d$entry < month & d$exposure >= month
    event_now <- risk_set & d$exposure == month & d$discontinued
    risk <- sum(d$wt[risk_set])
    all_endings <- sum(d$wt[event_now])
    direct_switches <- sum(d$wt[event_now & d$direct_modern_switch])
    if (risk > 0) {
      switch_cif <- switch_cif + survival * direct_switches / risk
      any_cif <- any_cif + survival * all_endings / risk
      survival <- survival * (1 - all_endings / risk)
    }
    rows[[month]] <- data.frame(month=month, weighted_at_risk=risk,
      weighted_all_endings=all_endings,
      weighted_direct_modern_switches=direct_switches,
      direct_modern_switch_cumulative_pct=100*switch_cif,
      any_reason_cumulative_pct=100*any_cif,
      remaining_original_method_pct=100*survival)
  }
  z <- do.call(rbind, rows)
  stopifnot(max(abs(z$any_reason_cumulative_pct +
                    z$remaining_original_method_pct - 100)) < 1e-8,
            all(z$direct_modern_switch_cumulative_pct <=
                z$any_reason_cumulative_pct + 1e-8))
  z
}

group <- function(z) {
  ifelse(z==3L,'Injectables',
  ifelse(z==11L,'Implants',
  ifelse(z==1L,'Pill',
  ifelse(z==2L,'IUD','Other modern'))))
}

primary <- assign_switch(e[e$method_code %in% modern_codes, ], modern_codes)
primary$method_group <- group(primary$method_code)
groups <- c('Injectables','Implants','Pill','IUD','Other modern')
output <- do.call(rbind, lapply(c('All modern excluding EC', groups), function(g) {
  d <- if (g=='All modern excluding EC') primary else
    primary[primary$method_group==g, ]
  z <- life_table(d)
  data.frame(group=g, eligible_episodes=nrow(d),
    weighted_eligible_episodes=sum(d$wt),
    observed_direct_switches_through_12m=sum(d$direct_modern_switch &
      d$discontinued & d$exposure<=12L),
    weighted_observed_direct_switches_through_12m=sum(d$wt[
      d$direct_modern_switch & d$discontinued & d$exposure<=12L]),
    direct_modern_switch_12m_pct=tail(z$direct_modern_switch_cumulative_pct,1),
    any_reason_12m_pct=tail(z$any_reason_cumulative_pct,1),
    dhs_broad_switch_12m_pct={
      broad <- d
      broad$direct_modern_switch <- broad$switched
      tail(life_table(broad)$direct_modern_switch_cumulative_pct,1)
    })
}))

# Sensitivities: EC is an eligible modern destination only; or both an eligible
# origin and destination. Primary results above are unaffected by these rows.
ec_destination <- assign_switch(e[e$method_code %in% modern_codes, ],
                               c(modern_codes,ec_code))
ec_both <- assign_switch(e[e$method_code %in% c(modern_codes,ec_code), ],
                         c(modern_codes,ec_code))
for (label in c('Non-EC origins, EC destination allowed',
                'EC origin and destination allowed')) {
  d <- if (label=='Non-EC origins, EC destination allowed') ec_destination else ec_both
  z <- life_table(d)
  output <- rbind(output, data.frame(group=label,
    eligible_episodes=nrow(d), weighted_eligible_episodes=sum(d$wt),
    observed_direct_switches_through_12m=sum(d$direct_modern_switch &
      d$discontinued & d$exposure<=12L),
    weighted_observed_direct_switches_through_12m=sum(d$wt[
      d$direct_modern_switch & d$discontinued & d$exposure<=12L]),
    direct_modern_switch_12m_pct=tail(z$direct_modern_switch_cumulative_pct,1),
    any_reason_12m_pct=tail(z$any_reason_cumulative_pct,1),
    dhs_broad_switch_12m_pct=NA_real_))
}

dir.create(dirname(out_file), recursive=TRUE, showWarnings=FALSE)
write.csv(output, out_file, row.names=FALSE)
print(output, row.names=FALSE, digits=5)
cat('Saved:',out_file,'\n')

# Stratified PSU bootstrap for the main all-modern estimate. Resampling whole
# PSUs retains multiple episodes from the same woman together. The bootstrap
# is descriptive survey uncertainty; it does not address calendar recall or
# method/reason misclassification. Each stratum contributes its original
# number of PSUs on every draw.
set.seed(20261012)
primary$stratum <- x$v022[primary$woman_row]
primary$psu <- x$v021[primary$woman_row]
primary$cluster <- paste(primary$stratum, primary$psu, sep=':')
psus_by_stratum <- split(unique(primary[c('stratum','cluster')])$cluster,
                         unique(primary[c('stratum','cluster')])$stratum)
cluster_index <- match(primary$cluster, unique(primary$cluster))
cluster_names <- unique(primary$cluster)
bootstrap <- replicate(500L, {
  sampled <- unlist(lapply(psus_by_stratum, function(psus)
    sample(psus, length(psus), replace=TRUE)), use.names=FALSE)
  multiplicity <- tabulate(match(sampled, cluster_names), nbins=length(cluster_names))
  d <- primary
  d$wt <- d$wt * multiplicity[cluster_index]
  tail(life_table(d)$direct_modern_switch_cumulative_pct, 1)
})
interval <- quantile(bootstrap, c(.025,.975), names=FALSE)
cat(sprintf('All modern excluding EC, direct next-month modern switch: %.4f%%; PSU bootstrap 95%% interval %.4f–%.4f%%\n',
            output$direct_modern_switch_12m_pct[1], interval[1], interval[2]))
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 90_regional_method_experience_detailed.R
# LANGUAGE: R
MODULES[["90_regional_method_experience_detailed.R"]] <- list(
 language="R",
 packaged_sha256="23e13476389012e7f9774b7557fa7d36cd6cb26a7a679f074f2c1edf5842acee",
 args=character(),
 code=r"-----(
# Full DHS sampling frame, including PSUs with no eligible outcome records.
full_survey_frame <- function(){
 r<-Sys.getenv('ETHIOPIA_PROJECT_ROOT'); stopifnot(nzchar(r))
 x<-readRDS(file.path(r,'Data/ET2024DHS__ETIR8ADT__IR_raw.rds'))
 unique(data.frame(cluster=paste(as.integer(x$v022),as.integer(x$v021),sep=':'),stratum=as.integer(x$v022)))
}
complete_survey_data <- function(d){
 r<-Sys.getenv('ETHIOPIA_PROJECT_ROOT');x<-readRDS(file.path(r,'Data/ET2024DHS__ETIR8ADT__IR_raw.rds'))
 f<-unique(data.frame(v021=as.integer(x$v021),v022=as.integer(x$v022)))
 key<-function(a,b)paste(a,b,sep=':');miss<-f[!key(f$v021,f$v022)%in%key(d$v021,d$v022),]
 if(nrow(miss)){z<-d[rep(1L,nrow(miss)),,drop=FALSE];z$v021<-miss$v021;z$v022<-miss$v022;z$wt<-0;d<-rbind(d,z)}
 d
}
#!/usr/bin/env Rscript
# Regional 12-month discontinuation for the seven detailed reasons retained in
# the updated subnational analysis, plus a row-normalized reason heatmap.
#
# Input: the complete-case episode CSV used for the presentation's regional
# selected-reason regression and forest plot. It derives from the Ethiopia
# 2024–25 IR calendar after the R scripts documented in Code/README.md.
# Each row is an original modern-method episode, excluding emergency
# contraception. A woman can contribute more than one episode.
#
# The first-year event is an original-method ending for one of these seven
# detailed calendar reasons: method failure, wanting a more effective method,
# bleeding changes, other side effects/health concerns, lack of access,
# cost, or inconvenience. Wanted pregnancy, husband/partner disapproval,
# other fertility-related reasons, and residual other/unknown reasons are
# competing endings. They enter the initial risk set and leave it when the
# episode ends; they are neither deleted nor censored at that event.
#
# Region is recorded at interview and may differ from residence at the
# historical episode start. The rate is an unadjusted, survey-weighted
# competing-risk cumulative incidence. The heatmap shares divide the seven
# reason-specific cumulative incidences by their sum within each region;
# therefore, each displayed row adds to 100%. These are NOT simple shares of
# raw observed endings. No package installation or DHS microdata download is
# performed by this script.

project <- Sys.getenv("ETHIOPIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
out <- file.path(project, "output")
support <- file.path(out, "Supporting_data")
e <- read.csv(file.path(support,
  "selected_reason_exploratory_episode_covariates.csv"),
  stringsAsFactors = FALSE)
stopifnot(nrow(e) == 8611L, all(e$method_code != 16L),
          !anyNA(e[, c("wt", "region", "cluster", "stratum", "entry",
                        "exposure", "discontinued", "reason_code")]))

region_labels <- c(
  `1` = "Tigray", `2` = "Afar", `3` = "Amhara", `4` = "Oromia",
  `5` = "Somali", `6` = "Benishangul-Gumuz", `7` = "Central Ethiopia",
  `8` = "Sidama", `9` = "South West Ethiopia", `10` = "South Ethiopia",
  `12` = "Gambella", `13` = "Harari", `14` = "Addis Ababa",
  `15` = "Dire Dawa")
region_codes <- as.integer(names(region_labels))
stopifnot(identical(sort(unique(e$region)), sort(region_codes)))

# Native calendar reason codes are retained by the episode constructor.
# Codes 4 and 5 both belong to the stated side-effect/health family; code 5
# has no retained first-year events in this extract. Code 15 is bleeding.
reasons <- list(
  "Method failure" = 1L,
  "Wanted more effective method" = 7L,
  "Changes in menstrual bleeding" = 15L,
  "Other side effects/health" = c(4L, 5L),
  "Lack of access/too far" = 6L,
  "Cost too much" = 8L,
  "Inconvenient to use" = 10L)
retained_codes <- unlist(reasons, use.names = FALSE)
Kcause <- length(reasons)
stopifnot(length(unique(retained_codes)) == length(retained_codes))

# A PSU is unique within its DHS stratum. All of a woman's episodes stay in
# the same PSU when bootstrapping; the same multiplier is used at every month.
frame <- full_survey_frame()
frame$idx <- seq_len(nrow(frame))
e$psu_idx <- frame$idx[match(e$cluster, frame$cluster)]
Kpsu <- nrow(frame)
by_stratum <- split(frame$idx, frame$stratum)
stopifnot(all(lengths(by_stratum) > 1L), !anyNA(e$psu_idx))

event_12 <- e$discontinued & e$entry < e$exposure & e$exposure <= 12L
retained_12 <- event_12 & e$reason_code %in% retained_codes
stopifnot(sum(retained_12) == 1321L,
          all(e$reason[retained_12] %in% c(1L, 4L, 5L, 6L, 7L)))

fill_psu <- function(target, mask, month) {
  if (!any(mask)) return(target)
  z <- rowsum(e$wt[mask], e$psu_idx[mask], reorder = FALSE)
  target[as.integer(rownames(z)), month] <- z[, 1L]
  target
}

make_arrays <- function(scope) {
  risk <- all <- matrix(0, nrow = Kpsu, ncol = 12L)
  cause <- array(0, dim = c(Kpsu, 12L, Kcause))
  for (t in seq_len(12L)) {
    at <- scope & e$entry < t & e$exposure >= t
    ending <- at & e$discontinued & e$exposure == t
    risk <- fill_psu(risk, at, t)
    all <- fill_psu(all, ending, t)
    for (j in seq_len(Kcause)) {
      mask <- ending & e$reason_code %in% reasons[[j]]
      cause[, , j] <- fill_psu(cause[, , j], mask, t)
    }
  }
  list(risk = risk, all = all, cause = cause)
}

# Aalen–Johansen/multiple-decrement life-table accumulation. Every kind of
# ending reduces survival before the next month. Delayed-entry episodes join
# the risk set only after their observed entry duration.
estimate <- function(a, multiplier) {
  R <- as.numeric(crossprod(multiplier, a$risk))
  A <- as.numeric(crossprod(multiplier, a$all))
  if (any(R <= 0) || any(A > R + 1e-7))
    return(rep(NA_real_, Kcause + 1L))
  survival <- 1
  incidence <- numeric(Kcause)
  for (t in seq_len(12L)) {
    D <- as.numeric(crossprod(multiplier, a$cause[, t, ]))
    incidence <- incidence + survival * D / R[t]
    survival <- survival * (1 - A[t] / R[t])
  }
  100 * c(total = sum(incidence), incidence)
}

codes <- c(NA_integer_, region_codes)
names(codes) <- c("All modern", unname(region_labels))
arrays <- lapply(codes, function(code)
  make_arrays(if (is.na(code)) rep(TRUE, nrow(e)) else e$region == code))
point <- t(vapply(arrays, estimate, numeric(Kcause + 1L),
                  multiplier = rep(1, Kpsu)))
colnames(point) <- c("total", names(reasons))
stopifnot(all(abs(rowSums(point[, -1L, drop = FALSE]) - point[, 1L]) < 1e-8),
          all(point[, 1L] > 0))

# Stratified rescaled PSU bootstrap for uncertainty. Entire PSUs are sampled
# within each stratum, so repeated episodes and months remain together.
B <- as.integer(Sys.getenv("REGIONAL_DETAILED_BOOTSTRAP_REPS", "1500"))
if (B < 100L) stop("Use at least 100 bootstrap replicates")
draws <- array(NA_real_, dim = c(B, length(codes), Kcause + 1L))
for (b in seq_len(B)) {
  set.seed(20261018L + b)
  multiplier <- numeric(Kpsu)
  for (ids in by_stratum) {
    n <- length(ids)
    multiplier[ids] <- n / (n - 1L) *
      tabulate(sample.int(n, n - 1L, replace = TRUE), nbins = n)
  }
  draws[b, , ] <- t(vapply(arrays, estimate, numeric(Kcause + 1L),
                           multiplier = multiplier))
}
valid <- apply(!is.na(draws[, , 1L]), 2, sum)
stopifnot(all(valid >= .95 * B))

round_to_100 <- function(raw) {
  low <- floor(raw * 10) / 10
  remainder <- as.integer(round((100 - sum(low)) * 10))
  if (remainder > 0L) {
    priority <- order(raw - low, decreasing = TRUE)
    low[priority[seq_len(remainder)]] <-
      low[priority[seq_len(remainder)]] + .1
  }
  stopifnot(abs(sum(low) - 100) < 1e-6)
  low
}

rate_rows <- vector("list", length(codes))
reason_rows <- vector("list", length(codes))
for (j in seq_along(codes)) {
  scope <- if (is.na(codes[j])) rep(TRUE, nrow(e)) else e$region == codes[j]
  ci <- quantile(draws[, j, 1L], c(.025, .975), na.rm = TRUE,
                 names = FALSE)
  rate_rows[[j]] <- data.frame(
    region_code = codes[j], region = names(codes)[j],
    eligible_episodes_n = sum(scope),
    eligible_episodes_weighted = sum(e$wt[scope]),
    selected_endings_n = sum(scope & retained_12),
    selected_endings_weighted = sum(e$wt[scope & retained_12]),
    eligible_psus = length(unique(e$cluster[scope])),
    selected_ending_psus = length(unique(e$cluster[scope & retained_12])),
    selected_reason_12_month_probability_pct = point[j, 1L],
    ci_low = ci[1L], ci_high = ci[2L],
    valid_bootstrap_replicates = valid[j],
    precision_flag = if (sum(scope & retained_12) < 30L) "Sparse: fewer than 30 selected endings" else "",
    stringsAsFactors = FALSE)
  raw_share <- 100 * point[j, -1L] / point[j, 1L]
  shown_share <- round_to_100(raw_share)
  for (k in seq_len(Kcause)) {
    in_reason <- scope & retained_12 & e$reason_code %in% reasons[[k]]
    share_draw <- 100 * draws[, j, k + 1L] / draws[, j, 1L]
    reason_rows[[j]][[k]] <- data.frame(
      region_code = codes[j], region = names(codes)[j],
      reason = names(reasons)[k],
      observed_endings_n = sum(in_reason),
      observed_endings_weighted = sum(e$wt[in_reason]),
      cause_specific_12_month_probability_pct = point[j, k + 1L],
      share_of_selected_12_month_probability_pct = raw_share[k],
      displayed_share_pct = shown_share[k],
      share_ci_low = quantile(share_draw, .025, na.rm = TRUE, names = FALSE),
      share_ci_high = quantile(share_draw, .975, na.rm = TRUE, names = FALSE),
      precision_flag = if (sum(in_reason) < 10L) "Sparse reason cell: fewer than 10 endings" else "",
      stringsAsFactors = FALSE)
  }
  reason_rows[[j]] <- do.call(rbind, reason_rows[[j]])
}
rates <- do.call(rbind, rate_rows)
reason_mix <- do.call(rbind, reason_rows)
rownames(rates) <- rownames(reason_mix) <- NULL
stopifnot(all(abs(tapply(reason_mix$displayed_share_pct,
                         reason_mix$region, sum) - 100) < 1e-6))

write.csv(rates, file.path(out, "updated_regional_retained_reason_rates.csv"),
          row.names = FALSE)
write.csv(reason_mix,
          file.path(out, "updated_regional_retained_reason_heatmap.csv"),
          row.names = FALSE)
cat(sprintf("%d eligible episodes; %d first-year retained-reason endings; %d bootstrap replicates.\n",
  nrow(e), sum(retained_12), B))
print(rates[, c("region", "eligible_episodes_n", "selected_endings_n",
  "selected_reason_12_month_probability_pct", "ci_low", "ci_high")],
  row.names = FALSE)
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 91_plot_regional_method_experience_detailed.R
# LANGUAGE: R
MODULES[["91_plot_regional_method_experience_detailed.R"]] <- list(
 language="R",
 packaged_sha256="b5ffd7a0d02026b75745967c8223520cb8773df290b07d4eeb322d344117b29e",
 args=character(),
 code=r"-----(#!/usr/bin/env Rscript
# Presentation-style display of the updated regional competing-risk estimates.
# Run Code/90_regional_method_experience_detailed.R first. The left panel is
# the 12-month cumulative incidence of the seven retained calendar reasons.
# The right panel groups access, cost, and inconvenience into one category,
# then divides each grouped cause-specific incidence by that total; rows add
# to 100%. Sparse reason cells are shown for transparency, not ranking.

project <- Sys.getenv("ETHIOPIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
out <- file.path(project, "output")
assets <- file.path(out, "assets")
dir.create(assets, showWarnings = FALSE, recursive = TRUE)
rates <- read.csv(file.path(out, "updated_regional_retained_reason_rates.csv"),
                  stringsAsFactors = FALSE)
mix <- read.csv(file.path(out, "updated_regional_retained_reason_heatmap.csv"),
                stringsAsFactors = FALSE)
national <- rates[rates$region == "All modern", ]
regional <- rates[rates$region != "All modern", ]
regional <- regional[order(-regional$selected_reason_12_month_probability_pct), ]
stopifnot(nrow(regional) == 14L, nrow(mix) == 15L * 7L)

navy <- "#153e56"
teal <- "#108d94"
gridline <- "#d8e3e8"
ci_col <- "#91aebd"
group_names <- c("Method failure", "Wanted more effective method",
                 "Changes in menstrual bleeding", "Other side effects/health",
                 "Access/cost/convenience")
group_sources <- list(
  "Method failure" = "Method failure",
  "Wanted more effective method" = "Wanted more effective method",
  "Changes in menstrual bleeding" = "Changes in menstrual bleeding",
  "Other side effects/health" = "Other side effects/health",
  "Access/cost/convenience" = c("Lack of access/too far", "Cost too much", "Inconvenient to use"))
headings <- c("Method\nfailure", "Wanted a more\neffective method",
              "Bleeding\nchanges", "Other side\neffects / health",
              "Access / cost /\nconvenience")
round_to_100 <- function(raw) {
  low <- floor(raw * 10) / 10
  remainder <- as.integer(round((100 - sum(low)) * 10))
  if (remainder > 0L) {
    priority <- order(raw - low, decreasing = TRUE)
    low[priority[seq_len(remainder)]] <-
      low[priority[seq_len(remainder)]] + .1
  }
  stopifnot(abs(sum(low) - 100) < 1e-6)
  low
}
grouped <- do.call(rbind, lapply(unique(mix$region), function(region) {
  piece <- mix[mix$region == region, ]
  cif <- vapply(group_sources, function(src)
    sum(piece$cause_specific_12_month_probability_pct[piece$reason %in% src]),
    numeric(1L))
  counts <- vapply(group_sources, function(src)
    sum(piece$observed_endings_n[piece$reason %in% src]), integer(1L))
  raw <- cif / sum(cif) * 100
  data.frame(region = region, reason = group_names,
             observed_endings_n = counts,
             cause_specific_12_month_probability_pct = as.numeric(cif),
             share_of_selected_12_month_probability_pct = as.numeric(raw),
             displayed_share_pct = as.numeric(round_to_100(raw)),
             stringsAsFactors = FALSE)
}))
stopifnot(all(abs(tapply(grouped$displayed_share_pct,
                         grouped$region, sum) - 100) < 1e-6))
write.csv(grouped, file.path(out, "updated_regional_retained_reason_heatmap_grouped.csv"),
          row.names = FALSE)

draw <- function() {
  library(grid)
  grid.newpage()
  grid.rect(gp = gpar(fill = "white", col = NA))
  grid.text("Subnational analysis shows that Tigray has the highest",
            x = .025, y = .955, just = "left",
            gp = gpar(col = navy, fontsize = 20, fontface = "bold", fontfamily = "Georgia"))
  grid.text("12-month discontinuation for method experience or access",
            x = .025, y = .918, just = "left",
            gp = gpar(col = navy, fontsize = 20, fontface = "bold", fontfamily = "Georgia"))
  grid.text("Ending the original method (%)",
            x = .277, y = .846, just = "center",
            gp = gpar(col = navy, fontsize = 12.5, fontface = "bold"))
  grid.text("Reasons among selected first-year discontinuations (%)",
            x = .764, y = .846, just = "center",
            gp = gpar(col = navy, fontsize = 12.5, fontface = "bold"))

  left <- .205; right <- .402
  hleft <- .642; hright <- .985
  xval <- function(v) left + pmax(0, pmin(35, v)) / 35 * (right - left)
  ys <- seq(.720, .185, length.out = 14)
  box_h <- .034
  for (tick in seq(0, 35, 5)) {
    grid.lines(x = rep(xval(tick), 2), y = c(.17, .741),
               gp = gpar(col = gridline, lwd = .7))
    grid.text(as.character(tick), x = xval(tick), y = .148,
              gp = gpar(col = "#405765", fontsize = 10))
  }
  grid.lines(x = rep(xval(national$selected_reason_12_month_probability_pct), 2),
             y = c(.17, .755), gp = gpar(col = teal, lwd = 1.7, lty = 2))
  grid.text(sprintf("National %.1f", national$selected_reason_12_month_probability_pct),
            x = xval(national$selected_reason_12_month_probability_pct), y = .781,
            gp = gpar(col = teal, fontsize = 11, fontface = "bold"))
  for (k in seq_along(group_names)) {
    center <- hleft + (k - .5) * (hright - hleft) / 5
    grid.text(headings[k], x = center, y = .775,
              gp = gpar(col = "#1d303b", fontsize = 9.4, fontface = "bold"))
  }

  vals <- matrix(NA_real_, 14, 5)
  for (i in seq_len(14)) {
    region <- regional$region[i]
    record <- regional[i, ]
    y <- ys[i]
    sparse <- record$selected_endings_n < 30
    label <- if (sparse) paste0(region, " (30 episodes)") else region
    grid.text(label, x = .025, y = y, just = "left",
              gp = gpar(col = "#20333e", fontsize = 11.4,
                        fontface = if (sparse) "bold" else "plain"))
    grid.lines(x = c(xval(record$ci_low), xval(record$ci_high)), y = c(y, y),
               gp = gpar(col = ci_col, lwd = 1.5))
    grid.circle(x = xval(record$selected_reason_12_month_probability_pct),
                y = y, r = unit(3.6, "pt"), gp = gpar(fill = teal, col = teal))
    grid.text(sprintf("%.1f", record$selected_reason_12_month_probability_pct),
              x = .427, y = y, gp = gpar(col = navy, fontsize = 11.5,
                                         fontface = "bold"))
    grid.text(if (sparse) paste0(region, " (5 events)") else region,
              x = .635, y = y, just = "right",
              gp = gpar(col = "#20333e", fontsize = 9.8,
                        fontface = if (sparse) "bold" else "plain"))
    for (k in seq_along(group_names)) {
      cell <- grouped[grouped$region == region & grouped$reason == group_names[k], ]
      stopifnot(nrow(cell) == 1L)
      p <- cell$displayed_share_pct
      vals[i, k] <- p
      center <- hleft + (k - .5) * (hright - hleft) / 5
      w <- (hright - hleft) / 5 - .001
      shade <- pmin(1, p / 40)
      fill <- grDevices::colorRampPalette(c("#e8f3f4", "#108d94"))(101)[floor(shade * 100) + 1]
      grid.rect(x = center, y = y, width = w, height = box_h,
                gp = gpar(fill = fill, col = "white", lwd = .6))
      grid.text(sprintf("%.1f", p), x = center, y = y,
                gp = gpar(col = if (shade > .57) "white" else "#1f3039",
                          fontsize = 10.0, fontface = "bold"))
    }
  }
  stopifnot(all(abs(rowSums(vals) - 100) < 1e-6))
  grid.text("Access/cost/convenience combines lack of access, cost too much, and inconvenient to use.",
            x = .506, y = .107, just = "left",
            gp = gpar(col = "#52666f", fontsize = 9.1))
  grid.text("Somali has only 5 retained endings; its reason shares are too imprecise for ranking. Rows sum to 100%.",
            x = .506, y = .080, just = "left",
            gp = gpar(col = "#52666f", fontsize = 9.1))
}

png(file.path(assets, "updated_regional_retained_reason_forest_heatmap.png"),
    width = 2400, height = 1350, res = 150, type = "quartz")
draw(); dev.off()
svglite::svglite(file.path(assets, "updated_regional_retained_reason_forest_heatmap.svg"),
                 width = 16, height = 9)
draw(); dev.off()
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 93_regional_starts_vs_selected_risk_preview.R
# LANGUAGE: R
MODULES[["93_regional_starts_vs_selected_risk_preview.R"]] <- list(
 language="R",
 packaged_sha256="2836a336065172a489604f9f51ce1bae137fb06d6ce9d48c0dd230e84c59c9e8",
 args=character(),
 code=r"-----(#!/usr/bin/env Rscript
# Preview only: regional share of all observed contraceptive method starts
# alongside the cause-specific 12-month probability of ending each named
# modern method for method experience or access. This does not edit the
# consolidated HTML or presentation.
#
# The two bars have different denominators:
#   amber = starts of that method / all contraceptive starts in the region,
#           including traditional starts but excluding emergency contraception;
#   navy  = 12-month cumulative incidence of the seven retained reasons among
#           all eligible episodes of that original modern method.
# Wanted pregnancy, partner disapproval, and circumstantial/unresolved reasons
# remain competing endings in the navy life table. One woman may contribute
# several episodes, and region is region at interview. The source episode CSV
# is the complete-case cohort used for the regional regression. For regional
# navy bars, a transparent display rule suppresses cells with <30 eligible
# episodes or <10 observed selected first-year endings. The CSV retains all.

project <- Sys.getenv("ETHIOPIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
out <- file.path(project, "output")
assets <- file.path(out, "assets")
dir.create(assets, showWarnings = FALSE, recursive = TRUE)

starts <- read.csv(file.path(out, "regional_mix_vs_allcause_method_panels.csv"),
                   stringsAsFactors = FALSE)
national_starts <- read.csv(file.path(out,
  "presentation_mix_vs_allcause_discontinuation_excluding_ec.csv"),
  stringsAsFactors = FALSE)
e <- read.csv(file.path(out, "Supporting_data",
  "selected_reason_exploratory_episode_covariates.csv"),
  stringsAsFactors = FALSE)
stopifnot(nrow(e) == 8611L, nrow(starts) == 14L * 5L)

regions <- c(`1` = "Tigray", `2` = "Afar", `3` = "Amhara", `4` = "Oromia",
             `5` = "Somali", `6` = "Benishangul-Gumuz", `7` = "Central Ethiopia",
             `8` = "Sidama", `9` = "South West Ethiopia", `10` = "South Ethiopia",
             `12` = "Gambella", `13` = "Harari", `14` = "Addis Ababa",
             `15` = "Dire Dawa")
methods <- list(Injectables = 3L, Implants = 11L, Pill = 1L, IUD = 2L,
                `Other modern` = c(5L, 6L, 7L, 13L, 17L, 18L))
retained <- c(1L, 4L, 5L, 6L, 7L, 8L, 10L, 15L)

selected_life_table <- function(x) {
  survival <- 1
  selected <- 0
  for (t in seq_len(12L)) {
    at <- x$entry < t & x$exposure >= t
    denom <- sum(x$wt[at])
    if (denom <= 0) return(NA_real_)
    ended <- at & x$discontinued & x$exposure == t
    target <- ended & x$reason_code %in% retained
    selected <- selected + survival * sum(x$wt[target]) / denom
    survival <- survival * (1 - sum(x$wt[ended]) / denom)
  }
  100 * selected
}

make_row <- function(region, method, scope, share, all_starts_n,
                     method_starts_n) {
  x <- e[scope & e$method_code %in% methods[[method]], ]
  first_year <- x$discontinued & x$entry < x$exposure &
    x$exposure <= 12L & x$reason_code %in% retained
  rate <- selected_life_table(x)
  data.frame(region = region, method = method,
             unweighted_all_starts = all_starts_n,
             unweighted_method_starts = method_starts_n,
             weighted_start_share_pct = share,
             eligible_episodes = nrow(x),
             selected_first_year_endings = sum(first_year),
             selected_12_month_pct = rate,
             rate_displayed = !is.na(rate) & nrow(x) >= 30L &
               sum(first_year) >= 10L)
}

rows <- list()
for (method in names(methods)) {
  label <- if (method == "Other modern") "Other modern (excl. EC)" else method
  ns <- national_starts[national_starts$method == label, ]
  stopifnot(nrow(ns) == 1L)
  rows[[length(rows) + 1L]] <- make_row("National", method,
    rep(TRUE, nrow(e)), ns$start_share_pct, NA_integer_, NA_integer_)
  for (code in names(regions)) {
    name <- unname(regions[[code]])
    s <- starts[starts$region == name & starts$method == method, ]
    stopifnot(nrow(s) == 1L)
    rows[[length(rows) + 1L]] <- make_row(name, method,
      e$region == as.integer(code), s$weighted_start_share_pct,
      s$unweighted_all_starts, s$unweighted_method_starts)
  }
}
result <- do.call(rbind, rows)
rownames(result) <- NULL
write.csv(result, file.path(out,
  "regional_starts_vs_selected_discontinuation_preview.csv"), row.names = FALSE)

print(result[, c("region", "method", "unweighted_method_starts",
                 "eligible_episodes", "selected_first_year_endings",
                 "weighted_start_share_pct", "selected_12_month_pct",
                 "rate_displayed")], row.names = FALSE)

# Use one fixed regional order in every panel, matching the preceding
# all-modern regional rate figure. This makes regions comparable across methods.
library(ggplot2)
regional_rates <- read.csv(file.path(out,
  "updated_regional_retained_reason_rates.csv"), stringsAsFactors = FALSE)
regional_rates <- regional_rates[regional_rates$region != "All modern", ]
region_order <- regional_rates$region[
  order(-regional_rates$selected_reason_12_month_probability_pct)]
display_order <- c("National", region_order)

for (method in names(methods)) {
  z <- result[result$method == method, ]
  z <- z[match(display_order, z$region), ]
  stopifnot(identical(z$region, display_order))
  z$y <- rev(seq_len(nrow(z)))
  bar <- rbind(
    data.frame(region = z$region, y = z$y,
      series = "Share of all method starts", value = z$weighted_start_share_pct,
      shown = TRUE),
    data.frame(region = z$region, y = z$y,
      series = "12-month discontinuation: method experience/access",
      value = z$selected_12_month_pct, shown = z$rate_displayed)
  )
  bar$series <- factor(bar$series,
    levels = c("Share of all method starts",
               "12-month discontinuation: method experience/access"))
  bar$bar_y <- bar$y + ifelse(bar$series == "Share of all method starts", -.17, .17)
  bar$ymin <- bar$bar_y - .17
  bar$ymax <- bar$bar_y + .17
  drawn <- bar[bar$shown & is.finite(bar$value), ]
  withheld <- bar[!bar$shown & bar$series ==
    "12-month discontinuation: method experience/access", ]
  withheld$label <- "Insufficient data"
  title <- paste0(method, ": method starts and 12-month discontinuation by region")
  figure <- ggplot(drawn, aes(fill = series)) +
    geom_hline(yintercept = max(z$y) - .5, color = "#b9cbd3", linewidth = .6) +
    geom_rect(aes(xmin = 0, xmax = value, ymin = ymin, ymax = ymax)) +
    geom_text(aes(x = value + 1, y = bar_y, label = sprintf("%.1f", value)),
              hjust = 0, size = 3.35, fontface = "bold", color = "#152530") +
    geom_text(data = withheld, inherit.aes = FALSE,
              aes(x = 1, y = bar_y, label = label),
              hjust = 0, size = 2.9, color = "#73838b") +
    scale_fill_manual(values = c("Share of all method starts" = "#DA9A25",
      "12-month discontinuation: method experience/access" = "#153F5B"), drop = FALSE) +
    scale_x_continuous(breaks = seq(0, 80, 20), limits = c(0, 85),
                       expand = expansion(mult = c(0, 0))) +
    scale_y_continuous(breaks = z$y, labels = z$region,
      limits = c(.4, max(z$y) + .65), expand = expansion(mult = c(0, 0))) +
    labs(title = title, x = "Percent", y = NULL, fill = NULL,
         caption = paste(
           "Amber: method's share of all observed contraceptive starts in the region, including traditional starts and excluding EC.",
           "Navy: 12-month probability of ending that original method for method experience or access.",
           "Rates are withheld with fewer than 30 eligible episodes or 10 first-year selected endings.",
           sep = "\n")) +
    theme_minimal(base_family = "Arial", base_size = 13) +
    theme(plot.title = element_text(face = "bold", color = "#153F5B",
                                    size = 20, hjust = .5, margin = margin(b = 14)),
          plot.title.position = "plot",
          panel.grid.major.y = element_blank(),
          panel.grid.minor = element_blank(),
          panel.grid.major.x = element_line(color = "#e3e9ed", linewidth = .5),
          axis.text.y = element_text(color = "#17222C", size = 12),
          axis.text.x = element_text(color = "#17222C", size = 11),
          axis.title.x = element_text(color = "#17222C", size = 12),
          legend.position = "bottom",
          legend.text = element_text(color = "#17222C", size = 12),
          plot.caption = element_text(color = "#536772", size = 9.5,
                                      hjust = 0, margin = margin(t = 12)),
          plot.margin = margin(18, 30, 15, 18))
  base <- file.path(assets, paste0("preview_regional_starts_vs_selected_",
                    gsub(" ", "_", tolower(method))))
  ggsave(paste0(base, ".png"), figure, width = 14, height = 9,
         dpi = 150, bg = "white")
  ggsave(paste0(base, ".svg"), figure, width = 14, height = 9,
         device = svglite::svglite, bg = "white")
}
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 95_regional_actionable_timepoints.R
# LANGUAGE: R
MODULES[["95_regional_actionable_timepoints.R"]] <- list(
 language="R",
 packaged_sha256="f8d8fe362e7b92e9877fcc4a6b89321d82289a1ec1b917a8557b4d6d590ccd65",
 args=character(),
 code=r"-----(
# Full DHS sampling frame, including PSUs with no eligible outcome records.
full_survey_frame <- function(){
 r<-Sys.getenv('ETHIOPIA_PROJECT_ROOT'); stopifnot(nzchar(r))
 x<-readRDS(file.path(r,'Data/ET2024DHS__ETIR8ADT__IR_raw.rds'))
 unique(data.frame(cluster=paste(as.integer(x$v022),as.integer(x$v021),sep=':'),stratum=as.integer(x$v022)))
}
complete_survey_data <- function(d){
 r<-Sys.getenv('ETHIOPIA_PROJECT_ROOT');x<-readRDS(file.path(r,'Data/ET2024DHS__ETIR8ADT__IR_raw.rds'))
 f<-unique(data.frame(v021=as.integer(x$v021),v022=as.integer(x$v022)))
 key<-function(a,b)paste(a,b,sep=':');miss<-f[!key(f$v021,f$v022)%in%key(d$v021,d$v022),]
 if(nrow(miss)){z<-d[rep(1L,nrow(miss)),,drop=FALSE];z$v021<-miss$v021;z$v022<-miss$v022;z$wt<-0;d<-rbind(d,z)}
 d
}
#!/usr/bin/env Rscript
# Regional cumulative discontinuation at 3, 6, 9, and 12 months for the
# narrower method-experience/access outcome. The source episode cohort and
# retained native calendar reason codes match Code/90. All nonretained method
# endings remain competing events. The month-specific risk set accommodates
# episodes already in progress when the calendar window begins.
#
# Stratified PSU bootstrap intervals retain all episodes from a woman/PSU
# together. Input data already comes from the documented calendar and IR
# import pipeline; this script does not download DHS data or install packages.

project <- Sys.getenv("ETHIOPIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
out <- file.path(project, "output")
e <- read.csv(file.path(out, "Supporting_data",
  "selected_reason_exploratory_episode_covariates.csv"),
  stringsAsFactors = FALSE)
previous <- read.csv(file.path(out,
  "updated_regional_retained_reason_rates.csv"), stringsAsFactors = FALSE)
stopifnot(nrow(e) == 8611L, nrow(previous) == 15L)

regions <- c(`1` = "Tigray", `2` = "Afar", `3` = "Amhara", `4` = "Oromia",
             `5` = "Somali", `6` = "Benishangul-Gumuz", `7` = "Central Ethiopia",
             `8` = "Sidama", `9` = "South West Ethiopia", `10` = "South Ethiopia",
             `12` = "Gambella", `13` = "Harari", `14` = "Addis Ababa",
             `15` = "Dire Dawa")
codes <- c(NA_integer_, as.integer(names(regions)))
names(codes) <- c("National", unname(regions))
months <- c(3L, 6L, 9L, 12L)
retained <- c(1L, 4L, 5L, 6L, 7L, 8L, 10L, 15L)

frame <- full_survey_frame()
frame$id <- seq_len(nrow(frame))
e$id <- frame$id[match(e$cluster, frame$cluster)]
groups <- split(frame$id, frame$stratum)
stopifnot(!anyNA(e$id), all(lengths(groups) > 1L))
K <- nrow(frame)

fill <- function(a, mask, t) {
  if (!any(mask)) return(a)
  z <- rowsum(e$wt[mask], e$id[mask], reorder = FALSE)
  a[as.integer(rownames(z)), t] <- z[, 1L]
  a
}
array_for <- function(scope) {
  risk <- ended <- selected <- matrix(0, K, 12L)
  for (t in seq_len(12L)) {
    at <- scope & e$entry < t & e$exposure >= t
    stop <- at & e$discontinued & e$exposure == t
    chosen <- stop & e$reason_code %in% retained
    risk <- fill(risk, at, t)
    ended <- fill(ended, stop, t)
    selected <- fill(selected, chosen, t)
  }
  list(risk = risk, ended = ended, selected = selected)
}
arrays <- lapply(codes, function(code)
  array_for(if (is.na(code)) rep(TRUE, nrow(e)) else e$region == code))

cif <- function(a, mult) {
  R <- as.numeric(crossprod(mult, a$risk))
  A <- as.numeric(crossprod(mult, a$ended))
  D <- as.numeric(crossprod(mult, a$selected))
  if (any(R <= 0) || any(A > R + 1e-7)) return(rep(NA_real_, 4L))
  s <- 1; f <- 0; values <- numeric(12L)
  for (t in seq_len(12L)) {
    f <- f + s * D[t] / R[t]
    s <- s * (1 - A[t] / R[t])
    values[t] <- 100 * f
  }
  values[months]
}
point <- t(vapply(arrays, cif, numeric(4L), mult = rep(1, K)))
colnames(point) <- paste0("m", months)
stopifnot(all(diff(point[1L, ]) >= 0), all(point >= 0))
for (j in seq_along(codes)) {
  old <- previous[previous$region == if (j == 1L) "All modern" else names(codes)[j], ]
  stopifnot(nrow(old) == 1L,
    abs(point[j, 4L] - old$selected_reason_12_month_probability_pct) < 1e-8)
}

B <- 1500L
boot <- array(NA_real_, c(B, length(codes), 4L))
for (b in seq_len(B)) {
  set.seed(20261019L + b)
  mult <- numeric(K)
  for (ids in groups) {
    n <- length(ids)
    mult[ids] <- n / (n - 1L) *
      tabulate(sample.int(n, n - 1L, replace = TRUE), nbins = n)
  }
  boot[b, , ] <- t(vapply(arrays, cif, numeric(4L), mult = mult))
}
stopifnot(all(apply(!is.na(boot), c(2, 3), sum) >= .95 * B))

rows <- list()
for (j in seq_along(codes)) {
  scope <- if (is.na(codes[j])) rep(TRUE, nrow(e)) else e$region == codes[j]
  for (k in seq_along(months)) {
    t <- months[k]
    chosen <- scope & e$discontinued & e$entry < e$exposure &
      e$exposure <= t & e$reason_code %in% retained
    ci <- quantile(boot[, j, k], c(.025, .975), na.rm = TRUE,
                   names = FALSE)
    rows[[length(rows) + 1L]] <- data.frame(
      region_code = codes[j], region = names(codes)[j], month = t,
      eligible_episodes_n = sum(scope),
      selected_endings_by_month_n = sum(chosen),
      cumulative_probability_pct = point[j, k],
      ci_low = ci[1L], ci_high = ci[2L],
      sparse = sum(chosen) < 30L,
      stringsAsFactors = FALSE)
  }
}
result <- do.call(rbind, rows)
rownames(result) <- NULL
stopifnot(nrow(result) == 60L,
          all(abs(result$cumulative_probability_pct[result$month == 12L] -
                    point[, 4L]) < 1e-8))
write.csv(result, file.path(out,
  "regional_actionable_discontinuation_3_6_9_12_months.csv"), row.names = FALSE)
print(result[, c("region", "month", "cumulative_probability_pct",
                 "ci_low", "ci_high", "selected_endings_by_month_n")],
      row.names = FALSE)
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 96_plot_regional_actionable_timepoints.R
# LANGUAGE: R
MODULES[["96_plot_regional_actionable_timepoints.R"]] <- list(
 language="R",
 packaged_sha256="435cbad4d8d22a538ed7c27b4fb8bfee07c87fd2c32945a6f2d00ae5671ac4b1",
 args=character(),
 code=r"-----(#!/usr/bin/env Rscript
# Static companion to the interactive regional time-point preview. Source CSV
# is generated by Code/95_regional_actionable_timepoints.R. Use a single fixed
# 0–30% color scale across all regions and months; columns are cumulative and
# must not be summed. This is a review preview, not a PowerPoint edit.

project <- Sys.getenv("ETHIOPIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
out <- file.path(project, "output")
assets <- file.path(out, "assets")
dir.create(assets, showWarnings = FALSE, recursive = TRUE)
d <- read.csv(file.path(out,
  "regional_actionable_discontinuation_3_6_9_12_months.csv"),
  stringsAsFactors = FALSE)
stopifnot(nrow(d) == 60L)
last <- d[d$month == 12L & d$region != "National", ]
ordered <- c("National", last$region[order(-last$cumulative_probability_pct)])
months <- c(3L, 6L, 9L, 12L)
navy <- "#153e56"; teal <- "#108d94"
palette <- grDevices::colorRampPalette(c("#f1f7f8", "#b9dddd", "#108d94"))(301)

draw <- function() {
  library(grid)
  grid.newpage()
  grid.rect(gp = gpar(fill = "white", col = NA))
  grid.text("When method experience or access discontinuation accumulates",
            x = .035, y = .953, just = "left",
            gp = gpar(col = navy, fontsize = 22, fontface = "bold",
                      fontfamily = "Georgia"))
  grid.text("Cumulative probability of ending the original modern method (%)",
            x = .035, y = .908, just = "left",
            gp = gpar(col = "#425e69", fontsize = 12))
  x0 <- .33; x1 <- .94; w <- (x1 - x0) / 4
  ys <- seq(.777, .18, length.out = 15)
  for (k in seq_along(months)) {
    grid.text(paste0(months[k], " months"), x = x0 + (k - .5) * w,
              y = .837, gp = gpar(col = navy, fontsize = 13.2,
                                    fontface = "bold"))
  }
  for (j in seq_along(ordered)) {
    region <- ordered[j]
    y <- ys[j]
    sparse <- region == "Somali"
    label <- if (region == "National") "National benchmark" else
      if (sparse) "Somali (5 first-year events)" else region
    grid.text(label, x = .035, y = y, just = "left",
              gp = gpar(col = navy, fontsize = 12,
                        fontface = if (j == 1L || sparse) "bold" else "plain"))
    if (j == 1L) {
      grid.lines(x = c(.035, .94), y = rep(y - .025, 2),
                 gp = gpar(col = "#b8cbd2", lwd = 1.1))
    }
    for (k in seq_along(months)) {
      row <- d[d$region == region & d$month == months[k], ]
      stopifnot(nrow(row) == 1L)
      value <- row$cumulative_probability_pct
      shade <- max(0, min(300, round(value / 30 * 300)))
      fill <- palette[shade + 1L]
      xx <- x0 + (k - .5) * w
      grid.rect(x = xx, y = y, width = w - .003, height = .034,
                gp = gpar(fill = fill, col = "white", lwd = .6))
      grid.text(sprintf("%.1f", value), x = xx, y = y,
                gp = gpar(col = if (value >= 18) "white" else "#18333d",
                          fontsize = 11.5, fontface = "bold"))
    }
  }
  grid.text("Colors use the same 0–30% scale throughout. Columns are cumulative probabilities, not values to add together.",
            x = .035, y = .099, just = "left",
            gp = gpar(col = "#536873", fontsize = 10.1))
  grid.text("Somali has only 30 eligible episodes and 5 selected endings by 12 months; its pattern is too imprecise for comparison.",
            x = .035, y = .071, just = "left",
            gp = gpar(col = "#536873", fontsize = 10.1))
}

png(file.path(assets, "preview_regional_actionable_timepoint_heatmap.png"),
    width = 2400, height = 1350, res = 150, type = "quartz")
draw(); dev.off()
svglite::svglite(file.path(assets,
  "preview_regional_actionable_timepoint_heatmap.svg"),
  width = 16, height = 9)
draw(); dev.off()
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 98_preview_actionable_heatmap_locator.R
# LANGUAGE: R
MODULES[["98_preview_actionable_heatmap_locator.R"]] <- list(
 language="R",
 packaged_sha256="da0e52965d81b8b544686f7304a7fdb7659b772b5de72d7acafef294bef5f807",
 args=character(),
 code=r"-----(#!/usr/bin/env Rscript
# Review-only 16:9 layout: four cumulative-risk time points, their early share,
# and a labeled 2025 Ethiopia regional locator. Does not edit working HTML/PPTX.
library(ggplot2); library(sf); library(grid); library(gridExtra)
project <- Sys.getenv("ETHIOPIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
out <- file.path(project,'output'); assets <- file.path(out,'assets')
d <- read.csv(file.path(out,'regional_actionable_discontinuation_3_6_9_12_months.csv'))
g <- st_read(file.path(out,'Supporting_data','ethiopia_adm1_hdx_2025.geojson'),quiet=TRUE)
g$adm1_name[g$adm1_name=='Gambela'] <- 'Gambella'
stopifnot(nrow(g)==14, setequal(g$adm1_name,unique(d$region[d$region!='National'])))
last <- d[d$month==12 & d$region!='National',]
ord <- c('National',last$region[order(-last$cumulative_probability_pct)])
navy <- '#173e57'; dark <- '#17252d'
pal <- c('#edf8f7','#a8d4d2','#108B8D') # exact injectable teal from the presentation
# First-three-month share = F(3) / F(12), using the same selected-reason
# cumulative probabilities in each region. It is not an additional risk.
wide <- reshape(d[,c('region','month','cumulative_probability_pct')],
                idvar='region',timevar='month',direction='wide')
wide$early_share <- 100*wide$cumulative_probability_pct.3/wide$cumulative_probability_pct.12
stopifnot(all(is.finite(wide$early_share)))
h <- d[,c('region','month','cumulative_probability_pct')]
h$col <- paste0(h$month,' months')
h$value <- h$cumulative_probability_pct
h$is_share <- FALSE
share <- data.frame(region=wide$region,col='First 3 months\nshare of 12-month total',
                    value=wide$early_share,is_share=TRUE)
h <- rbind(h[,c('region','col','value','is_share')],share)
h$col <- factor(h$col,levels=c('3 months','6 months','9 months','12 months',
                  'First 3 months\nshare of 12-month total'))
h$region <- factor(h$region,levels=rev(ord))
h$shade <- ifelse(h$is_share,NA,h$value)
h$label <- sprintf('%.1f',h$value)
heat <- ggplot(h,aes(x=col,y=region)) +
 geom_tile(aes(fill=shade),width=.98,height=.88,color='white',linewidth=.8) +
 geom_text(aes(label=label),size=4.0,color=dark,fontface='plain') +
 scale_fill_gradientn(colors=pal,limits=c(0,30),oob=scales::squish,
                      na.value='#eef0f1',guide='none') +
 scale_x_discrete(position='top') +
 labs(title='Cumulative discontinuation probability',
      subtitle='Method experience or access reasons · modern-method episodes · percent',x=NULL,y=NULL) +
 theme_minimal(base_size=13) +
 theme(panel.grid=element_blank(),plot.title=element_text(face='bold',size=16,color=navy),
       plot.subtitle=element_text(size=10.5,color='#4e6570'),
       axis.text.x.top=element_text(face='bold',size=9.8,color=navy,margin=margin(b=5),lineheight=.95),
       axis.text.y=element_text(size=10.4,color=navy),axis.text.x.bottom=element_blank(),
       plot.margin=margin(8,8,2,8))
# Map shading uses exactly the same scale as the heatmap's 12-month column.
g$prob <- last$cumulative_probability_pct[match(g$adm1_name,last$region)]
gp <- st_transform(g,3857)
cent <- suppressWarnings(st_point_on_surface(gp)); pts <- st_coordinates(cent)
lab <- data.frame(name=gp$adm1_name,x=pts[,1],y=pts[,2])
small <- c('Addis Ababa','Dire Dawa','Harari','Sidama','Central Ethiopia')
big <- lab[!lab$name %in% small,]
big$label <- big$name
big$label[big$name=='Benishangul-Gumuz'] <- 'Benishangul-\nGumuz'
big$label[big$name=='South West Ethiopia'] <- 'South West\nEthiopia'
# External callouts for the five smallest regions keep full names legible.
call <- lab[match(small,lab$name),]
call$lx <- c(4150000,4790000,4840000,3880000,4490000)
call$ly <- c(1080000,1165000,1000000,945000,615000)
call$label <- c('Addis Ababa','Dire Dawa','Harari','Central Ethiopia','Sidama')
call$hjust <- c(1,0,0,1,0)
map <- ggplot() + geom_sf(data=gp,aes(fill=prob),color='white',linewidth=.55) +
 geom_text(data=big,aes(x=x,y=y,label=label),size=2.9,color=dark,
           fontface='plain',lineheight=.9) +
 geom_segment(data=call,aes(x=x,y=y,xend=lx,yend=ly),
              color='#536e7c',linewidth=.28) +
 geom_point(data=call,aes(x=x,y=y),color=navy,size=.8) +
 geom_text(data=call,aes(x=lx,y=ly,label=label,hjust=hjust),
           size=2.8,color=dark,fontface='plain',show.legend=FALSE) +
 scale_fill_gradientn(colors=pal,limits=c(0,30),oob=scales::squish,
                      name='12-month risk',breaks=c(0,10,20,30),
                      labels=function(z)paste0(z,'%')) +
 coord_sf(xlim=c(3650000,5400000),ylim=c(365000,1700000),expand=FALSE,clip='off') +
 labs(title='Where are the regions?',subtitle='Shading shows 12-month risk') +
 theme_void(base_size=12) +
 theme(plot.title=element_text(face='bold',size=16,color=navy),
       plot.subtitle=element_text(size=10.5,color='#4e6570'),
       legend.position='bottom',legend.title=element_text(size=9.5,face='plain'),
       legend.text=element_text(size=8.8),legend.key.width=unit(.55,'cm'),
       plot.margin=margin(8,8,2,10))
heading <- textGrob('Where does potentially actionable discontinuation occur?',
 x=unit(.015,'npc'),just='left',gp=gpar(fontfamily='Georgia',fontface='bold',fontsize=24,col=navy))
subhead <- textGrob('Regional probability at 3, 6, 9, and 12 months, alongside an Ethiopia locator map',
 x=unit(.015,'npc'),just='left',gp=gpar(fontsize=12,col='#4e6570'))
foot <- textGrob('Early share = 3-month cumulative probability ÷ 12-month cumulative probability. Somali: 30 eligible episodes and 5 selected endings; interpret cautiously. Map: 2025 HDX ADM1 v04.',
 x=unit(.015,'npc'),just='left',gp=gpar(fontsize=9.2,col='#526873'))
layout <- arrangeGrob(heading,subhead,arrangeGrob(heat,map,ncol=2,widths=c(2.0,1)),foot,
                      ncol=1,heights=unit(c(.47,.32,6.8,.32),'in'))
png(file.path(assets,'preview_actionable_heatmap_with_locator.png'),width=2400,height=1350,res=150,type='quartz')
grid.draw(layout);dev.off()
svglite::svglite(file.path(assets,'preview_actionable_heatmap_with_locator.svg'),width=16,height=9)
grid.draw(layout);dev.off()
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 99_leadership_regional_timing_locator.R
# LANGUAGE: R
MODULES[["99_leadership_regional_timing_locator.R"]] <- list(
 language="R",
 packaged_sha256="95106a98043ed44c3c68bab3004a5d13ea5addd75f0bc2b94ea2ece151598474",
 args=character(),
 code=r"-----(#!/usr/bin/env Rscript
# Leadership view: all 14 survey regions plus national benchmark. Somali is
# displayed last and excluded from rank ordering because only 5 events occurred.
library(ggplot2); library(sf); library(grid); library(gridExtra)
project <- Sys.getenv("ETHIOPIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
out <- file.path(project,'output'); assets <- file.path(out,'assets')
d <- read.csv(file.path(out,'regional_actionable_discontinuation_3_6_9_12_months.csv'))
g <- st_read(file.path(out,'Supporting_data','ethiopia_adm1_hdx_2025.geojson'),quiet=TRUE)
g$adm1_name[g$adm1_name=='Gambela'] <- 'Gambella'
stopifnot(nrow(g)==14, setequal(g$adm1_name,unique(d$region[d$region!='National'])))
last <- d[d$month==12 & d$region!='National',]
last <- last[last$region!='Somali',] # Five selected endings: do not rank Somali.
ranked <- last$region[order(-last$cumulative_probability_pct)]
selected <- c('National',ranked,'Somali')
stopifnot(length(selected)==15L, setequal(selected,unique(d$region)))
navy <- '#173e57'; ink <- '#17252d'
pal <- c('#edf8f7','#a8d4d2','#108B8D')
wide <- reshape(d[,c('region','month','cumulative_probability_pct')],idvar='region',timevar='month',direction='wide')
wide$early_share <- 100*wide$cumulative_probability_pct.3/wide$cumulative_probability_pct.12
h <- d[d$region %in% selected,c('region','month','cumulative_probability_pct')]
h$col <- paste0(h$month,' months');h$value <- h$cumulative_probability_pct;h$is_share <- FALSE
share <- data.frame(region=wide$region[wide$region %in% selected],
 col='First 3 months\nshare of 12-month total',value=wide$early_share[wide$region %in% selected],is_share=TRUE)
h <- rbind(h[,c('region','col','value','is_share')],share)
h$col <- factor(h$col,levels=c('3 months','6 months','9 months','12 months','First 3 months\nshare of 12-month total'))
h$region <- factor(h$region,levels=rev(selected))
h$shade <- ifelse(h$is_share,NA,h$value)
h$label <- sprintf('%.1f',h$value)
heat <- ggplot(h,aes(x=col,y=region)) +
 geom_tile(aes(fill=shade),width=.98,height=.88,color='white',linewidth=.8) +
 geom_text(aes(label=label),size=4.25,color=ink,fontface='plain') +
 scale_fill_gradientn(colors=pal,limits=c(0,30),oob=scales::squish,na.value='#eceff0',guide='none') +
 scale_x_discrete(position='top') +
 scale_y_discrete(labels=function(z) ifelse(z=='Somali','Somali†',z)) +
 labs(x=NULL,y=NULL) +
 theme_minimal(base_size=16) +
 theme(panel.grid=element_blank(),axis.text.x.top=element_text(face='bold',size=10.8,color=navy,lineheight=.95,margin=margin(b=7)),
 axis.text.y=element_text(size=10.8,color=navy),axis.text.x.bottom=element_blank(),
 plot.margin=margin(8,10,2,8))
gp <- st_transform(g,3857)
cent <- suppressWarnings(st_point_on_surface(gp));pts <- st_coordinates(cent)
lab <- data.frame(name=gp$adm1_name,x=pts[,1],y=pts[,2])
small <- c('Addis Ababa','Dire Dawa','Harari','Sidama','Central Ethiopia')
big <- lab[!lab$name %in% small,]
big$label <- big$name
big$label[big$name=='Benishangul-Gumuz'] <- 'Benishangul-\nGumuz'
big$label[big$name=='South West Ethiopia'] <- 'South West\nEthiopia'
call <- lab[match(small,lab$name),]
call$lx <- c(4150000,4790000,4840000,4490000,3880000)
call$ly <- c(1080000,1165000,1000000,615000,945000)
call$label <- call$name;call$hjust <- c(1,0,0,0,1)
map <- ggplot() + geom_sf(data=gp,fill='#e5eaed',color='white',linewidth=.6) +
 geom_text(data=big,aes(x=x,y=y,label=label),size=3.7,color=ink,fontface='plain',lineheight=.9) +
 geom_segment(data=call,aes(x=x,y=y,xend=lx,yend=ly),color='#657983',linewidth=.33) +
 geom_point(data=call,aes(x=x,y=y),color=navy,size=1) +
 geom_text(data=call,aes(x=lx,y=ly,label=label,hjust=hjust),size=3.5,color=ink,fontface='plain',show.legend=FALSE) +
 coord_sf(xlim=c(3650000,5400000),ylim=c(365000,1700000),expand=FALSE,clip='off') +
 theme_void() + theme(plot.margin=margin(4,8,2,10))
heading <- textGrob('Method experience or access discontinuation varies across regions and often occurs early.',
 x=unit(.018,'npc'),just='left',gp=gpar(fontfamily='Georgia',fontface='bold',fontsize=22.5,col=navy))
subhead <- textGrob('Cumulative probability (%) for all 14 regions and the national benchmark; regions ordered by 12-month estimate',
 x=unit(.018,'npc'),just='left',gp=gpar(fontsize=11.4,col='#4e6570'))
foot <- textGrob('First-three-month share = 3-month probability ÷ 12-month probability. † Somali displayed last, not ranked (5 selected endings). Confidence intervals are in the accompanying table. Boundaries: HDX ADM1 v04.',
 x=unit(.018,'npc'),just='left',gp=gpar(fontsize=10.0,col='#526873'))
layout <- arrangeGrob(heading,subhead,arrangeGrob(heat,map,ncol=2,widths=c(1.75,1)),foot,
 ncol=1,heights=unit(c(.53,.37,6.75,.28),'in'))
png(file.path(assets,'leadership_regional_actionable_timing_locator.png'),width=2400,height=1350,res=150,type='quartz')
grid.draw(layout);dev.off()
svglite::svglite(file.path(assets,'leadership_regional_actionable_timing_locator.svg'),width=16,height=9)
grid.draw(layout);dev.off()
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 100_regional_initiation_mix_stacked.R
# LANGUAGE: R
MODULES[["100_regional_initiation_mix_stacked.R"]] <- list(
 language="R",
 packaged_sha256="952af5552b045a3e8906e199167a66e8a22f007c413fd06c8917207dca2e5677",
 args=character(),
 code=r"-----(#!/usr/bin/env Rscript
# Reproduce the regional method-initiation mix shown in the working HTML.
# Input is the previously parsed DHS monthly contraceptive calendar, one row
# per continuous method-use run. A start is counted only when it begins within
# months 3–62 before interview; a run already underway at the calendar's left
# edge is not an observed initiation. All seven categories from the original
# presentation initiation slide are retained, including EC and traditional
# methods. The denominator is ALL observed contraceptive method starts within
# each region, not all women or all episodes contributing to a life table.
# Survey weights (v005/1e6) were attached to the run-level RDS upstream.
# Base R handles the tabulation; ggplot2 creates the static presentation chart.

project <- Sys.getenv("ETHIOPIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
output <- file.path(project, "output")
assets <- file.path(output, "assets")
dir.create(assets, recursive=TRUE, showWarnings=FALSE)
events <- readRDS(file.path(project, "Data/Derived/ethiopia_2024_calendar_events.rds"))
codes <- c(1L,2L,3L,5L,6L,7L,8L,9L,10L,11L,13L,16L,17L,18L)
starts <- events[events$start != events$calendar_start &
                 events$interview-events$start >= 3L &
                 events$interview-events$start <= 62L &
                 events$method_code %in% codes, ]
stopifnot(nrow(starts)==8060L)
region_names <- c(`1`="Tigray",`2`="Afar",`3`="Amhara",`4`="Oromia",
                  `5`="Somali",`6`="Benishangul-Gumuz",`7`="Central Ethiopia",
                  `8`="Sidama",`9`="South West Ethiopia",`10`="South Ethiopia",
                  `12`="Gambella",`13`="Harari",`14`="Addis Ababa",`15`="Dire Dawa")
starts$region_name <- unname(region_names[as.character(starts$region)])
stopifnot(!anyNA(starts$region_name), length(unique(starts$region_name))==14L)
starts$method_name <- ifelse(starts$method_code==3L,"Injectables",
                      ifelse(starts$method_code==11L,"Implants",
                      ifelse(starts$method_code==1L,"Pill",
                      ifelse(starts$method_code==2L,"IUD",
                      ifelse(starts$method_code==16L,"EC",
                      ifelse(starts$method_code %in% c(8L,9L,10L),"Non-modern methods",
                             "Other modern"))))))
methods <- c("Injectables","Implants","Pill","IUD","EC","Other modern","Non-modern methods")
make_row <- function(z,region,method) {
  q <- z[z$method_name==method,]
  data.frame(region=region,method=method,
             unweighted_region_starts=nrow(z),unweighted_method_starts=nrow(q),
             weighted_region_starts=sum(z$wt),weighted_method_starts=sum(q$wt),
             share_pct=100*sum(q$wt)/sum(z$wt))
}
regions <- c("National",unname(region_names))
result <- do.call(rbind,lapply(regions,function(region) {
  z <- if(region=="National") starts else starts[starts$region_name==region,]
  do.call(rbind,lapply(methods,function(method) make_row(z,region,method)))
}))
stopifnot(all(abs(aggregate(share_pct~region,result,sum)$share_pct-100)<1e-8))
write.csv(result,file.path(output,"regional_all_method_initiation_mix.csv"),row.names=FALSE)

if(!requireNamespace("ggplot2",quietly=TRUE))
  stop("ggplot2 is required to render the regional stacked-bar figure")
library(ggplot2)
palette <- c(Injectables="#108B8D",Implants="#153F5B",Pill="#DA9A25",
             IUD="#D95C47",EC="#B5598A",`Other modern`="#6B7280",
             `Non-modern methods`="#A18C6F")
# Place national at the top; sort regions by injectable share to reveal pattern.
injectable <- result[result$method=="Injectables" & result$region!="National",]
region_order <- c("National",injectable$region[order(-injectable$share_pct)])
result$region <- factor(result$region,levels=rev(region_order))
result$method <- factor(result$method,levels=methods)
result$label <- ifelse(result$share_pct>=9,sprintf("%.0f",result$share_pct),"")
result$label_color <- ifelse(as.character(result$method) %in% c("Pill","IUD","Non-modern methods"),
                             "#122a39","#ffffff")
result$x_mid <- NA_real_
for(region in region_order) {
  ix <- which(as.character(result$region)==region)
  result$x_mid[ix] <- cumsum(result$share_pct[ix])-result$share_pct[ix]/2
}
plot <- ggplot(result,aes(x=share_pct,y=region,fill=method)) +
  geom_col(width=.71,color="white",linewidth=.3,position=position_stack(reverse=TRUE)) +
  geom_text(aes(x=x_mid,label=label,color=label_color),
            size=3.45,fontface="plain",show.legend=FALSE) +
  scale_color_identity() +
  scale_fill_manual(values=palette,breaks=methods,drop=FALSE,
                    guide=guide_legend(nrow=2,byrow=TRUE)) +
  scale_x_continuous(breaks=c(0,25,50,75,100),
                     labels=function(x) paste0(x,"%"),expand=c(0,0)) +
  coord_cartesian(xlim=c(0,100),clip="off") +
  labs(title="Method initiation mix varies across Ethiopia's regions",
       subtitle="Share of observed contraceptive method starts within each region",
       x="Share of method starts",y=NULL,fill=NULL,
       caption="National uses all 8,060 observed starts. Region is recorded at interview; Somali has only 29 starts.\nEC and non-modern methods are shown to match the original initiation slide; discontinuation analyses exclude EC.") +
  theme_minimal(base_family="Arial",base_size=13) +
  theme(plot.title=element_text(face="bold",size=20,color="#153F5B",margin=margin(b=5)),
        plot.subtitle=element_text(size=12.5,color="#36505D",margin=margin(b=17)),
        axis.text.y=element_text(size=12.3,color="#18313E"),
        axis.text.x=element_text(size=10.7,color="#18313E"),
        axis.title.x=element_text(size=11.5,color="#18313E",margin=margin(t=9)),
        panel.grid.major.y=element_blank(),panel.grid.minor=element_blank(),
        panel.grid.major.x=element_line(color="#E0E8EB",linewidth=.4),
        legend.position="bottom",legend.text=element_text(size=11.2,color="#18313E"),
        legend.key.width=grid::unit(0.55,"cm"),legend.key.height=grid::unit(0.38,"cm"),
        plot.caption=element_text(size=9,color="#5B6C74",hjust=0,margin=margin(t=16)),
        plot.margin=margin(18,24,14,15))
ggsave(file.path(assets,"regional_all_method_initiation_mix.svg"),plot,
       width=13.4,height=9.3,units="in",bg="white")
ggsave(file.path(assets,"regional_all_method_initiation_mix.png"),plot,
       width=13.4,height=9.3,units="in",dpi=180,bg="white")
# A dedicated widescreen version keeps the stacked bars and region names
# readable in the 16:9 presentation without stretching the analysis figure.
slide_plot <- plot +
  labs(subtitle=NULL,
       caption="Each row: weighted share of observed starts. Somali has only 29 starts. Region is measured at interview.") +
  theme(plot.title=element_text(size=21,margin=margin(b=8)),
        axis.text.y=element_text(size=10.7),axis.text.x=element_text(size=9.5),
        axis.title.x=element_text(size=10.5),
        legend.text=element_text(size=9.8),
        plot.caption=element_text(size=8.1,margin=margin(t=7)),
        plot.margin=margin(12,18,10,10))
ggsave(file.path(assets,"regional_all_method_initiation_mix_slide.png"),slide_plot,
       width=13.3333,height=7.5,units="in",dpi=180,bg="white")
cat("Saved regional seven-category initiation mix,",nrow(starts),"observed starts.\n")
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 103_preview_regional_method_discontinuation_heatmap.R
# LANGUAGE: R
MODULES[["103_preview_regional_method_discontinuation_heatmap.R"]] <- list(
 language="R",
 packaged_sha256="8a310b7b2a21e5c33889783db7b8bfbfb5f4919cc0a6613b630965871b175f88",
 args=character(),
 code=r"-----(#!/usr/bin/env Rscript
# Companion to the regional seven-category initiation-mix chart.
# Uses the previously calculated, survey-weighted all-cause 12-month
# life-table probabilities by original method and region. The national
# benchmark comes from the presentation's EC-excluded all-cause method table.
# Sparse region-method cells (<30 eligible episodes or <10 first-year endings)
# are withheld from the chart. This is a display rule, not a significance test.

project <- Sys.getenv("ETHIOPIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
out <- file.path(project,"output")
assets <- file.path(out,"assets")
source <- read.csv(file.path(out,"regional_mix_vs_allcause_method_panels.csv"))
national <- read.csv(file.path(out,"presentation_mix_vs_allcause_discontinuation_excluding_ec.csv"))
mix <- read.csv(file.path(out,"regional_all_method_initiation_mix.csv"))
methods <- c("Injectables","Implants","Pill")
region_order <- mix[mix$method=="Injectables" & mix$region!="National",]
region_order <- c("National",region_order$region[order(-region_order$share_pct)])
cells <- source[source$method %in% methods,]
cells$rate <- cells$all_cause_12_month_pct
cells$display <- cells$eligible_episodes>=30L & cells$first_year_endings>=10L
bench <- data.frame(region="National",method=methods,
                    eligible_episodes=NA_integer_,first_year_endings=NA_integer_,
                    rate=national$d12_discontinuation_pct[match(methods,national$method)],
                    display=TRUE)
cells <- rbind(cells[,names(bench)],bench)
cells$region <- factor(cells$region,levels=rev(region_order))
cells$method <- factor(cells$method,levels=methods)
cells$fill_rate <- ifelse(cells$display,cells$rate,NA_real_)
cells$label <- ifelse(cells$display,sprintf("%.1f%%",cells$rate),"—")
write.csv(cells,file.path(out,"regional_top_three_allcause_discontinuation_heatmap.csv"),row.names=FALSE)

library(ggplot2)
p <- ggplot(cells,aes(x=method,y=region)) +
  geom_tile(aes(fill=fill_rate),width=.97,height=.86,color="white",linewidth=1.3) +
  geom_text(aes(label=label),size=4.2,color="#18313E") +
  scale_fill_gradient(low="#E5F2F2",high="#108B8D",limits=c(0,100),na.value="#EDF1F2",
                      name="12-month probability") +
  scale_x_discrete(position="top") +
  labs(title="12-month discontinuation varies by method and region",
       subtitle="Probability of ending the original method for any reason",
       x=NULL,y=NULL,
       caption="National benchmark at top. Dash: fewer than 30 eligible episodes or 10 first-year endings.\nMethod ending can include a switch to another contraceptive method. Region is measured at interview.") +
  theme_minimal(base_family="Arial",base_size=12) +
  theme(plot.title=element_text(face="bold",size=20,color="#153F5B",margin=margin(b=5)),
        plot.subtitle=element_text(size=12,color="#36505D",margin=margin(b=15)),
        axis.text.x=element_text(size=12,face="bold",color="#18313E",margin=margin(b=8)),
        axis.text.y=element_text(size=11.5,color="#18313E"),
        axis.ticks=element_blank(),panel.grid=element_blank(),
        legend.position="bottom",legend.text=element_text(size=10),
        plot.caption=element_text(size=9,color="#5B6C74",hjust=0,margin=margin(t=12)),
        plot.margin=margin(12,15,10,15))
ggsave(file.path(assets,"regional_top_three_allcause_discontinuation_heatmap.svg"),p,
       width=9.5,height=9.1,units="in",bg="white")
ggsave(file.path(assets,"regional_top_three_allcause_discontinuation_heatmap.png"),p,
       width=9.5,height=9.1,units="in",dpi=170,bg="white")
cat("Saved regional method-rate heatmap preview;",sum(!cells$display),"sparse cells withheld.\n")
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 105_regional_actionable_method_pair_preview.R
# LANGUAGE: R
MODULES[["105_regional_actionable_method_pair_preview.R"]] <- list(
 language="R",
 packaged_sha256="74f0a23fb874266f2054dbe6e3ab4c11c895514666a70e683961d0175faf4e07",
 args=character(),
 code=r"-----(#!/usr/bin/env Rscript
# Regional counterpart to the national paired-bar slide, restricted to
# program-actionable method experience or access endings.
#
# Amber denominator: all observed contraceptive method starts in each region
# (the seven-category EC-inclusive initiation-mix cohort shown on the new
# regional stacked-bar slide). Navy denominator: all eligible episodes of the
# original modern method in the discontinuation life table, excluding EC.
# Wanted pregnancy, partner disapproval, and circumstantial/other endings
# remain competing events in the monthly risk sets. They are not deleted.
# A method ending can include switching to another contraceptive method.
# This script produces a data CSV and three preview figures. No PPTX is edited.

project <- Sys.getenv("ETHIOPIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
out <- file.path(project,"output")
assets <- file.path(out,"assets")
e <- read.csv(file.path(out,"Supporting_data/selected_reason_exploratory_episode_covariates.csv"))
mix <- read.csv(file.path(out,"regional_all_method_initiation_mix.csv"))
stopifnot(nrow(e)==8611L)
methods <- list(Injectables=3L,Implants=11L,Pill=1L,IUD=2L,
                `Other modern`=c(5L,6L,7L,13L,17L,18L))
region_names <- c(`1`="Tigray",`2`="Afar",`3`="Amhara",`4`="Oromia",
                  `5`="Somali",`6`="Benishangul-Gumuz",`7`="Central Ethiopia",
                  `8`="Sidama",`9`="South West Ethiopia",`10`="South Ethiopia",
                  `12`="Gambella",`13`="Harari",`14`="Addis Ababa",`15`="Dire Dawa")
actionable <- c(1L,4L,5L,6L,7L,8L,10L,15L)
life_table <- function(x) {
  S <- 1
  F <- 0
  for(t in 1:12) {
    at <- x$entry<t & x$exposure>=t
    R <- sum(x$wt[at])
    if(R<=0) return(NA_real_)
    ending <- at & x$discontinued & x$exposure==t
    D <- sum(x$wt[ending])
    Dc <- sum(x$wt[ending & x$reason_code %in% actionable])
    F <- F+S*Dc/R
    S <- S*(1-D/R)
  }
  100*F
}
rows <- list()
for(region in c("National",unname(region_names))) {
  scope <- if(region=="National") rep(TRUE,nrow(e)) else e$region==as.integer(names(region_names)[match(region,region_names)])
  for(method in names(methods)) {
    x <- e[scope & e$method_code %in% methods[[method]],]
    selected <- x$discontinued & x$entry<x$exposure & x$exposure<=12L &
                x$reason_code %in% actionable
    m <- mix[mix$region==region & mix$method==method,]
    stopifnot(nrow(m)==1L)
    rows[[length(rows)+1L]] <- data.frame(region=region,method=method,
      observed_starts_n=m$unweighted_region_starts,
      method_starts_n=m$unweighted_method_starts,
      share_all_starts_pct=m$share_pct,
      eligible_episodes_n=nrow(x),actionable_first_year_endings_n=sum(selected),
      actionable_12_month_probability_pct=life_table(x))
  }
}
res <- do.call(rbind,rows)
res$display_rate <- res$region=="National" |
  (res$eligible_episodes_n>=30L & res$actionable_first_year_endings_n>=10L)
write.csv(res,file.path(out,"regional_actionable_method_starts_and_rates.csv"),row.names=FALSE)

library(ggplot2)
for(method in c("Injectables","Implants","Pill")) {
  z <- res[res$method==method,]
  # In each view, national stays first and regions are ranked by actionable
  # discontinuation; Somali remains last because its evidence is too sparse.
  eligible <- z[z$region!="National" & z$display_rate,]
  withheld <- z[z$region!="National" & !z$display_rate,]
  order <- c("National",eligible$region[order(-eligible$actionable_12_month_probability_pct)],
             withheld$region)
  z$y <- length(order)+1L-match(z$region,order)
  bars <- rbind(
    data.frame(region=z$region,y=z$y,metric="Share of all method starts",
               pct=z$share_all_starts_pct,show=TRUE),
    data.frame(region=z$region,y=z$y,
               metric="12-month potentially actionable discontinuation",
               pct=z$actionable_12_month_probability_pct,show=z$display_rate))
  bars$metric <- factor(bars$metric,levels=c("Share of all method starts",
                          "12-month potentially actionable discontinuation"))
  bars$bar_y <- bars$y+ifelse(bars$metric=="Share of all method starts",.17,-.17)
  bars$ymin <- bars$bar_y-.15
  bars$ymax <- bars$bar_y+.15
  drawn <- bars[bars$show & is.finite(bars$pct),]
  missing <- bars[!bars$show & bars$metric=="12-month potentially actionable discontinuation",]
  p <- ggplot(drawn,aes(fill=metric))+
    geom_hline(yintercept=max(z$y)-.5,color="#B8C9CE",linewidth=.5)+
    geom_rect(aes(xmin=0,xmax=pct,ymin=ymin,ymax=ymax))+
    geom_text(aes(x=pct+1,y=bar_y,label=sprintf("%.1f",pct)),
              hjust=0,size=3.1,color="#182A34")+
    geom_text(data=missing,inherit.aes=FALSE,
              aes(x=1,y=bar_y,label="Insufficient data"),
              hjust=0,size=2.8,color="#60747D")+
    scale_fill_manual(values=c("Share of all method starts"="#DA9A25",
                   "12-month potentially actionable discontinuation"="#153F5B"),drop=FALSE)+
    scale_x_continuous(breaks=c(0,20,40,60,80),limits=c(0,85),expand=c(0,0))+
    scale_y_continuous(breaks=z$y,labels=z$region,
                       limits=c(.4,max(z$y)+.58),expand=c(0,0))+
    labs(title=paste0(method,": starts and potentially actionable discontinuation by region"),
         x="Percent",y=NULL,fill=NULL,
         caption="Amber: share of all observed method starts. Navy: 12-month probability of ending this original method for method experience or access.\nRates with fewer than 30 eligible episodes or 10 actionable endings are withheld. Region is measured at interview.")+
    theme_minimal(base_family="Arial",base_size=12)+
    theme(plot.title=element_text(face="bold",size=19,color="#153F5B",margin=margin(b=8)),
          axis.text.y=element_text(size=11.5,color="#18313E"),
          axis.text.x=element_text(size=10,color="#18313E"),
          axis.title.x=element_text(size=10.5,color="#18313E"),
          panel.grid.major.y=element_blank(),panel.grid.minor=element_blank(),
          panel.grid.major.x=element_line(color="#E1E8EB"),
          legend.position="bottom",legend.text=element_text(size=10),
          plot.caption=element_text(size=8,color="#5B6C74",hjust=0,margin=margin(t=8)),
          plot.margin=margin(12,22,8,10))
  stem <- paste0("regional_actionable_paired_",tolower(method))
  ggsave(file.path(assets,paste0(stem,".svg")),p,width=13.33,height=7.5,units="in",bg="white")
  ggsave(file.path(assets,paste0(stem,".png")),p,width=13.33,height=7.5,units="in",dpi=180,bg="white")
}
cat("Saved actionable paired-bar previews and source CSV.\n")
print(res[res$region=="National",c("method","share_all_starts_pct","actionable_12_month_probability_pct")])
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 108_regional_actionable_reason_mix_by_method.R
# LANGUAGE: R
MODULES[["108_regional_actionable_reason_mix_by_method.R"]] <- list(
 language="R",
 packaged_sha256="50adace7f250f4d3abce2b6f1d847af59b390447e640cd931e04aac16931d605",
 args=character(),
 code=r"-----(#!/usr/bin/env Rscript
# Five method-specific regional heatmaps of first-year, program-actionable
# original-method endings. This uses the same complete-case episode cohort,
# reason codes, survey weights, delayed-entry risk sets, and multiple-decrement
# calculation as 90_regional_method_experience_detailed.R. All other original-
# method endings remain competing events. Each displayed row divides its five
# cause-specific 12-month incidences by their sum; it therefore adds to 100%.
# Do not interpret these percentages as the risk among all method episodes or
# as the fraction of women who stopped modern contraception.

project <- Sys.getenv("ETHIOPIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
out <- file.path(project, "output")
assets <- file.path(out, "assets")
e <- read.csv(file.path(out, "Supporting_data",
                        "selected_reason_exploratory_episode_covariates.csv"))
stopifnot(nrow(e) == 8611L, all(e$method_code != 16L))

methods <- list(Injectables = 3L, Implants = 11L, Pill = 1L, IUD = 2L,
                `Other modern` = c(5L, 6L, 7L, 13L, 17L, 18L))
regions <- c(`1` = "Tigray", `2` = "Afar", `3` = "Amhara", `4` = "Oromia",
             `5` = "Somali", `6` = "Benishangul-Gumuz",
             `7` = "Central Ethiopia", `8` = "Sidama",
             `9` = "South West Ethiopia", `10` = "South Ethiopia",
             `12` = "Gambella", `13` = "Harari", `14` = "Addis Ababa",
             `15` = "Dire Dawa")
reason_codes <- list(`Method failure` = 1L,
  `Wanted more effective method` = 7L,
  `Changes in menstrual bleeding` = 15L,
  `Other side effects/health` = c(4L, 5L),
  `Access/cost/convenience` = c(6L, 8L, 10L))
actionable <- unlist(reason_codes, use.names = FALSE)
stopifnot(length(unique(actionable)) == length(actionable))

round_to_100 <- function(x) {
  low <- floor(x * 10) / 10
  rem <- as.integer(round((100 - sum(low)) * 10))
  if (rem > 0L) {
    order <- order(x - low, decreasing = TRUE)
    low[order[seq_len(rem)]] <- low[order[seq_len(rem)]] + 0.1
  }
  stopifnot(abs(sum(low) - 100) < 1e-7)
  low
}

estimate <- function(z) {
  incidence <- setNames(numeric(length(reason_codes)), names(reason_codes))
  survival <- 1
  for (t in 1:12) {
    at <- z$entry < t & z$exposure >= t
    risk <- sum(z$wt[at])
    if (risk <= 0) return(rep(NA_real_, length(reason_codes)))
    ending <- at & z$discontinued & z$exposure == t
    all_endings <- sum(z$wt[ending])
    for (j in seq_along(reason_codes)) {
      cj <- ending & z$reason_code %in% reason_codes[[j]]
      incidence[j] <- incidence[j] + survival * sum(z$wt[cj]) / risk
    }
    survival <- survival * (1 - all_endings / risk)
  }
  100 * incidence
}

rows <- list()
for (method in names(methods)) {
  for (region in c("National", unname(regions))) {
    in_region <- if (region == "National") rep(TRUE, nrow(e)) else
      e$region == as.integer(names(regions)[match(region, regions)])
    z <- e[in_region & e$method_code %in% methods[[method]], ]
    ending <- z$discontinued & z$entry < z$exposure & z$exposure <= 12L &
      z$reason_code %in% actionable
    cif <- if (nrow(z)) estimate(z) else rep(NA_real_, length(reason_codes))
    total <- sum(cif)
    raw <- if (is.finite(total) && total > 0) cif / total * 100 else
      rep(NA_real_, length(cif))
    shown <- if (all(is.finite(raw))) round_to_100(raw) else raw
    # Regional rows need at least 30 eligible episodes AND 10 actionable
    # first-year endings. The national IUD row is reported descriptively but
    # flagged because it has fewer than 30 observed actionable endings.
    status <- if (nrow(z) == 0L || sum(ending) == 0L) "No events" else if (
      region != "National" && (nrow(z) < 30L || sum(ending) < 10L))
      "Insufficient regional data" else if (sum(ending) < 30L)
      "Limited precision" else "Display"
    for (j in seq_along(reason_codes)) {
      rows[[length(rows) + 1L]] <- data.frame(
        method = method, region = region, reason = names(reason_codes)[j],
        eligible_episodes_n = nrow(z), actionable_endings_n = sum(ending),
        reason_endings_n = sum(ending & z$reason_code %in% reason_codes[[j]]),
        cause_specific_12_month_probability_pct = cif[j],
        share_of_actionable_probability_pct = raw[j],
        displayed_share_pct = shown[j], status = status)
    }
  }
}
result <- do.call(rbind, rows)
rownames(result) <- NULL
for (method in names(methods)) {
  z <- result[result$method == method & result$status %in%
    c("Display", "Limited precision"), ]
  stopifnot(all(abs(tapply(z$displayed_share_pct, z$region, sum) - 100) < 1e-7))
}
write.csv(result, file.path(out, "regional_actionable_reason_mix_by_method.csv"),
          row.names = FALSE)

library(grid)
navy <- "#153e56"
teal <- "#108d94"
light <- "#e8f3f4"
gold <- "#DA9A25"
gold_light <- "#FFF6E4"
grey <- "#eef2f3"
dark <- "#20333e"
heads <- c("Method\nfailure", "Wanted a more\neffective method",
           "Bleeding\nchanges", "Other side\neffects / health",
           "Access / cost /\nconvenience")
method_stems <- c(Injectables = "injectables", Implants = "implants",
                  Pill = "pill", IUD = "iud", `Other modern` = "other_modern")
# Keep the regional order from the existing all-modern heatmap for easy
# comparison across methods. Somali stays last because its overall cell is
# already sparse.
existing <- read.csv(file.path(out, "updated_regional_retained_reason_rates.csv"))
regional <- existing[existing$region != "All modern", ]
regional <- regional[order(-regional$selected_reason_12_month_probability_pct), ]
order_regions <- c("National", setdiff(regional$region, "Somali"), "Somali")
stopifnot(length(order_regions) == 15L)

draw <- function(method) {
  d <- result[result$method == method, ]
  grid.newpage()
  grid.rect(gp = gpar(fill = "white", col = NA))
  grid.text(paste0(method, ": reasons for potentially actionable first-year endings"),
            x = .035, y = .944, just = "left",
            gp = gpar(col = navy, fontsize = 22.5, fontface = "bold",
                      fontfamily = "Georgia"))
  grid.text("Share of the 12-month actionable discontinuation probability (%)",
            x = .035, y = .899, just = "left",
            gp = gpar(col = navy, fontsize = 13.5))
  xname <- .055; left <- .300; right <- .975
  grid.text("Region", x = xname, y = .806, just = "left",
            gp = gpar(col = navy, fontsize = 13.5, fontface = "bold"))
  for (j in seq_along(heads)) {
    x <- left + (j - .5) * (right - left) / 5
    grid.text(heads[j], x = x, y = .806,
              gp = gpar(col = dark, fontsize = 12.8, fontface = "bold"))
  }
  ys <- seq(.740, .150, length.out = length(order_regions))
  for (i in seq_along(order_regions)) {
    region <- order_regions[i]
    z <- d[d$region == region, ]
    stopifnot(nrow(z) == 5L)
    y <- ys[i]
    valid <- z$status[1] %in% c("Display", "Limited precision")
    small <- z$eligible_episodes_n[1] < 30L ||
      z$actionable_endings_n[1] < 30L
    label <- if (small) paste0(region, " *") else region
    grid.text(label, x = xname, y = y, just = "left",
              gp = gpar(col = dark, fontsize = 14.6,
                        fontface = if (region == "National") "bold" else "plain"))
    for (j in 1:5) {
      x <- left + (j - .5) * (right - left) / 5
      width <- (right - left) / 5 - .003
      v <- z$displayed_share_pct[j]
      shade <- if (valid) pmin(1, v / 50) else 0
      ramp <- if (region == "National") c(gold_light, gold) else c(light, teal)
      fill <- if (valid) grDevices::colorRampPalette(ramp)(101)[
        floor(shade * 100) + 1L] else grey
      grid.rect(x = x, y = y, width = width, height = .036,
                gp = gpar(fill = fill, col = "white", lwd = .5))
      if (valid) grid.text(sprintf("%.1f", v), x = x, y = y,
                           gp = gpar(col = "#101a20", fontsize = 14.1))
    }
    if (!valid) grid.text("Insufficient regional data", x = (left + right)/2,
                          y = y, gp = gpar(col = "#5b6970", fontsize = 11.5))
    if (region == "National")
      grid.lines(x = c(.045, .979), y = c(y - .023, y - .023),
                 gp = gpar(col = "#b7cbd1", lwd = 1.2))
  }
  notes <- c(
    "Gold = national benchmark. * Fewer than 30 eligible episodes or 30 actionable first-year endings; interpret cautiously.",
    "Gray rows have fewer than 30 eligible episodes or 10 actionable endings; percentages are withheld. Shown rows sum to 100%.",
    "Other side effects/health: other side effects or health concerns; menstrual bleeding changes are shown separately.",
    "Access/cost/convenience: lack of access or too far, cost too much, and inconvenient to use."
  )
  for (k in seq_along(notes))
    grid.text(notes[k], x = .052, y = c(.110, .086, .062, .038)[k],
              just = "left", gp = gpar(col = "#52666f", fontsize = 13.0))
}
for (method in names(methods)) {
  stem <- paste0("regional_actionable_reason_heatmap_", method_stems[[method]])
  svglite::svglite(file.path(assets, paste0(stem, ".svg")),
                   width = 16, height = 9)
  draw(method); dev.off()
  png(file.path(assets, paste0(stem, ".png")), width = 2400,
      height = 1350, res = 150, type = "quartz")
  draw(method); dev.off()
}
print(unique(result[, c("method", "region", "eligible_episodes_n",
                        "actionable_endings_n", "status")]))
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 112_regional_actionable_adjusted_models.R
# LANGUAGE: R
MODULES[["112_regional_actionable_adjusted_models.R"]] <- list(
 language="R",
 packaged_sha256="d4090bb54ac64b905859892a3df755c6f9576d58755817037004bb419d2f6925",
 args=character(),
 code=r"-----(
# Algebraically identical monthly multinomial prediction, with the design
# matrix constructed once instead of once per duration month.
fast_survey_cif<-function(model,x,weights,event){
 x$month<-factor(1,levels=1:12)
 X<-model.matrix(delete.response(terms(model)),data=x,contrasts.arg=model$contrasts)
 b<-coef(model);eta<-X[,colnames(b),drop=FALSE]%*%t(b)
 S<-rep(1,nrow(x));F<-numeric(nrow(x));j<-match(event,rownames(b))
 for(t in 1:12){off<-if(t==1)rep(0,nrow(b))else b[,paste0('month',t)];ee<-exp(sweep(eta,2,off,'+'));den<-1+rowSums(ee);F<-F+S*ee[,j]/den;S<-S/den}
 100*weighted.mean(F,weights)
}

# Full DHS sampling frame, including PSUs with no eligible outcome records.
full_survey_frame <- function(){
 r<-Sys.getenv('ETHIOPIA_PROJECT_ROOT'); stopifnot(nzchar(r))
 x<-readRDS(file.path(r,'Data/ET2024DHS__ETIR8ADT__IR_raw.rds'))
 unique(data.frame(cluster=paste(as.integer(x$v022),as.integer(x$v021),sep=':'),stratum=as.integer(x$v022)))
}
complete_survey_data <- function(d){
 r<-Sys.getenv('ETHIOPIA_PROJECT_ROOT');x<-readRDS(file.path(r,'Data/ET2024DHS__ETIR8ADT__IR_raw.rds'))
 f<-unique(data.frame(v021=as.integer(x$v021),v022=as.integer(x$v022)))
 key<-function(a,b)paste(a,b,sep=':');miss<-f[!key(f$v021,f$v022)%in%key(d$v021,d$v022),]
 if(nrow(miss)){z<-d[rep(1L,nrow(miss)),,drop=FALSE];z$v021<-miss$v021;z$v022<-miss$v022;z$wt<-0;d<-rbind(d,z)}
 d
}
#!/usr/bin/env Rscript
# First regression comparison for regional, potentially actionable
# original-modern-method discontinuation during months 1–12.
#
# The unit is an episode-month from the same EC-excluded complete-case cohort
# used in the regional descriptive figures. A month has one of three mutually
# exclusive outcomes: continuing the original method, ending for one of the
# eight recorded method-experience/access codes below, or ending for any other
# reason. The latter endings are competing events, not exclusions or censoring.
# Episodes that began before the observed calendar enter at their observed
# duration. A woman may contribute multiple episodes; the supplied PSU/stratum
# fields permit design-based bootstrap uncertainty in a subsequent run.
#
# This first run produces point estimates only. Do not interpret observed
# differences as statistically significant without survey-design intervals.
# No DHS data download or package installation is performed here.

project <- Sys.getenv("ETHIOPIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
support <- file.path(project, "output", "Supporting_data")
if (!requireNamespace("nnet", quietly = TRUE))
  stop("Install the nnet package before running this script")
e <- read.csv(file.path(support,
  "selected_reason_exploratory_episode_covariates.csv"))
ir <- readRDS(file.path(project, "Data/ET2024DHS__ETIR8ADT__IR_raw.rds"))
stopifnot(nrow(e) == 8611L, all(e$method_code != 16L),
          !anyNA(e[, c("wt", "entry", "exposure", "discontinued",
                       "reason_code", "region", "cluster", "stratum")]))

region_labels <- c(
  `1` = "Tigray", `2` = "Afar", `3` = "Amhara", `4` = "Oromia",
  `5` = "Somali", `6` = "Benishangul-Gumuz",
  `7` = "Central Ethiopia", `8` = "Sidama",
  `9` = "South West Ethiopia", `10` = "South Ethiopia",
  `12` = "Gambella", `13` = "Harari", `14` = "Addis Ababa",
  `15` = "Dire Dawa")
actionable <- c(1L, 4L, 5L, 6L, 7L, 8L, 10L, 15L)
e$region <- factor(e$region, levels = as.integer(names(region_labels)))
e$method_group <- factor(e$method_group,
  levels = c("Injectables", "Implants", "Pill", "IUD", "Other modern"))
e$age_group <- factor(e$age_group,
  levels = c("15-19", "20-24", "25-34", "35-49"))
e$education <- factor(e$education,
  levels = c("None", "Primary", "Secondary+"))
e$residence <- factor(e$residence, levels = c("Rural", "Urban"))

# Parity is reconstructed at the episode start month from birth dates. The
# four categories and four marital categories match the latest full model.
i <- e$woman_row
birth_cols <- grep("^b3_", names(ir), value = TRUE)
births <- as.matrix(ir[i, birth_cols])
parity <- rowSums(!is.na(births) & births <= e$start)
marital <- as.integer(ir$v501[i])
wealth <- as.integer(ir$v190[i])
stopifnot(!anyNA(parity), all(marital %in% 0:5), all(wealth %in% 1:5))
e$parity_group <- factor(ifelse(parity == 0, "0",
  ifelse(parity <= 2, "1–2", ifelse(parity <= 4, "3–4", "5+"))),
  levels = c("0", "1–2", "3–4", "5+"))
e$marital_group <- factor(ifelse(marital == 0L, "Never in union",
  ifelse(marital == 2L, "Living together",
  ifelse(marital == 1L, "Married", "Divorced/widowed/separated"))),
  levels = c("Never in union", "Living together", "Married",
             "Divorced/widowed/separated"))
e$wealth_group <- factor(
  c("Poorest", "Poorer", "Middle", "Richer", "Richest")[wealth],
  levels = c("Poorest", "Poorer", "Middle", "Richer", "Richest"))
e$start_year <- factor((e$start - 1L) %/% 12L + 1900L)

# Expand each episode into observed exposure months, keeping its DHS weight.
observed_months <- pmax(0L, pmin(12L, e$exposure) - e$entry)
index <- rep(seq_len(nrow(e)), observed_months)
month <- unlist(Map(function(first, n) seq.int(first + 1L, length.out = n),
  e$entry, observed_months), use.names = FALSE)
person <- e[index, c("wt", "method_group", "age_group", "parity_group",
  "marital_group", "education", "wealth_group", "residence", "region",
  "start_year", "cluster", "stratum")]
person$month <- factor(month, levels = 1:12)
ended <- e$discontinued[index] & month == e$exposure[index]
person$outcome <- factor(ifelse(!ended, "continue",
  ifelse(e$reason_code[index] %in% actionable, "actionable", "competing")),
  levels = c("continue", "actionable", "competing"))
stopifnot(nrow(person) == 70691L,
          sum(person$outcome == "actionable") == 1321L)

# Model A standardizes each region to the same observed-start method mix;
# Model B also adjusts for measured composition and calendar start year.
# This is model-based standardization, not an exact decomposition of the raw
# DHS-style life-table gap. Both fits retain late entries in their month-of-use
# risk sets, exactly as the DHS discontinuation table does.
f_method <- outcome ~ month + method_group + region
f_full <- outcome ~ month + method_group + region + age_group + parity_group +
  marital_group + education + wealth_group + residence + start_year
fit_model <- function(formula) {
  m <- nnet::multinom(formula, data = person, weights = person$wt,
    maxit = 300, trace = FALSE, MaxNWts = 10000)
  if (m$convergence != 0L) stop("Multinomial model did not converge")
  m
}
fit_method <- fit_model(f_method)
fit_full <- fit_model(f_full)

# Give each region the same national distribution of observed method starts.
# The common baseline reference uses episodes observed from initiation to
# avoid treating late-entry survivors as if sampled at method initiation.
# Late entries remain in model fitting at their observed duration months.
# A method-only standardized rate still reflects regional differences within
# methods; the fully adjusted rate additionally standardizes age at start,
# parity at start, marital status/education/wealth/residence at interview,
# and method-start year. These are descriptive adjusted associations.
standard <- e[e$entry == 0L, ]
stopifnot(nrow(standard) > 0L)
predict_risk <- function(model, region_code, weights = standard$wt) {x<-standard;if(!is.null(region_code))x$region<-factor(region_code,levels=levels(e$region));fast_survey_cif(model,x,weights,'actionable')}

unadjusted <- read.csv(file.path(project, "output",
  "updated_regional_retained_reason_rates.csv"))
rows <- lapply(levels(e$region), function(code) {
  label <- unname(region_labels[code])
  z <- unadjusted[unadjusted$region == label, ]
  stopifnot(nrow(z) == 1L)
  data.frame(region = label,
    eligible_episodes_n = z$eligible_episodes_n,
    actionable_endings_n = z$selected_endings_n,
    unadjusted_12_month_pct = z$selected_reason_12_month_probability_pct,
    unadjusted_ci_low = z$ci_low, unadjusted_ci_high = z$ci_high,
    method_standardized_12_month_pct = predict_risk(fit_method, code),
    fully_adjusted_12_month_pct = predict_risk(fit_full, code),
    suppress_for_sparse_events = z$selected_endings_n < 10L)
})
regional <- do.call(rbind, rows)
write.csv(regional, file.path(support,
  "regional_actionable_first_model_point_estimates.csv"), row.names = FALSE)
saveRDS(fit_method, file.path(support,
  "regional_actionable_method_standardized_model.rds"))
saveRDS(fit_full, file.path(support,
  "regional_actionable_full_model.rds"))
print(regional[, c("region", "eligible_episodes_n", "actionable_endings_n",
  "unadjusted_12_month_pct", "method_standardized_12_month_pct",
  "fully_adjusted_12_month_pct", "suppress_for_sparse_events")],
  row.names = FALSE)

# Optional survey-design uncertainty. Resample PSUs within DHS strata and
# refit both models. Every episode from one woman remains in its sampled PSU;
# use the same multiplier for the episode-month likelihood and the national
# standardization population. Percentile intervals describe design variation
# in the adjusted regional probabilities, not causal regional effects.
B <- as.integer(Sys.getenv("REGIONAL_ACTIONABLE_BOOTSTRAP_REPS", "120"))
if (B > 0L) {
  frame <- full_survey_frame()
  by_stratum <- split(frame$cluster, frame$stratum)
  stopifnot(all(lengths(by_stratum) > 1L))
  one_replicate <- function(b) {
    set.seed(20261020L + b)
    multiplier <- setNames(numeric(nrow(frame)), frame$cluster)
    for (ids in by_stratum) {
      n <- length(ids)
      multiplier[as.character(ids)] <- n / (n - 1L) *
        tabulate(sample.int(n, n - 1L, replace = TRUE), nbins = n)
    }
    p <- person
    p$boot_weight <- p$wt * multiplier[as.character(p$cluster)]
    std_weight <- standard$wt * multiplier[as.character(standard$cluster)]
    fit_once <- function(formula) {
      m <- tryCatch(nnet::multinom(formula, data = p,
        weights = boot_weight, maxit = 300, trace = FALSE,
        MaxNWts = 10000), error = function(err) {
          if (b == 1L) message("Bootstrap fit error: ", conditionMessage(err))
          NULL
        })
      if (is.null(m)) return(NULL)
      if (m$convergence != 0L) {
        if (b == 1L) message("Bootstrap convergence code: ", m$convergence)
        return(NULL)
      }
      m
    }
    method <- fit_once(f_method)
    full <- fit_once(f_full)
    if (is.null(method) || is.null(full))
      return(rep(NA_real_, 2L * nrow(regional) + 2L))
    c(vapply(levels(e$region), function(code)
      predict_risk(method, code, std_weight), numeric(1)),
      vapply(levels(e$region), function(code)
        predict_risk(full, code, std_weight), numeric(1)),
      predict_risk(method, NULL, std_weight),
      predict_risk(full, NULL, std_weight))
  }
  draws <- parallel::mclapply(seq_len(B), one_replicate,
    mc.cores = min(4L, parallel::detectCores()),
    mc.preschedule = FALSE)
  draws <- do.call(rbind, draws)
  valid <- complete.cases(draws)
  if (sum(valid) < ceiling(.90 * B))
    stop(sprintf("Only %d of %d bootstrap refits converged", sum(valid), B))
  colnames(draws) <- c(paste0("method::", regional$region),
                      paste0("full::", regional$region),
                      "method::National", "full::National")
  write.csv(data.frame(replicate = seq_len(B), draws, check.names = FALSE),
    file.path(support, "regional_actionable_adjusted_bootstrap.csv"),
    row.names = FALSE)
  bounds <- apply(draws[valid, , drop = FALSE], 2, quantile,
    probs = c(.025, .975), names = FALSE)
  regional$method_ci_low <- bounds[1, seq_len(nrow(regional))]
  regional$method_ci_high <- bounds[2, seq_len(nrow(regional))]
  regional$full_ci_low <- bounds[1, nrow(regional) + seq_len(nrow(regional))]
  regional$full_ci_high <- bounds[2, nrow(regional) + seq_len(nrow(regional))]
  regional$valid_bootstrap_replicates <- sum(valid)
  national_bounds <- data.frame(
    region = "National",
    method_ci_low = bounds[1, "method::National"],
    method_ci_high = bounds[2, "method::National"],
    full_ci_low = bounds[1, "full::National"],
    full_ci_high = bounds[2, "full::National"],
    valid_bootstrap_replicates = sum(valid))
  write.csv(national_bounds, file.path(support,
    "regional_actionable_national_adjusted_bootstrap_ci.csv"),
    row.names = FALSE)
  write.csv(regional, file.path(support,
    "regional_actionable_first_model_point_estimates.csv"), row.names = FALSE)
  cat(sprintf("Survey-stratified PSU bootstrap: %d/%d valid refits\n",
    sum(valid), B))
  print(regional[, c("region", "method_standardized_12_month_pct",
    "method_ci_low", "method_ci_high", "fully_adjusted_12_month_pct",
    "full_ci_low", "full_ci_high")], row.names = FALSE)
}
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 114_regional_actionable_sample_audit.R
# LANGUAGE: R
MODULES[["114_regional_actionable_sample_audit.R"]] <- list(
 language="R",
 packaged_sha256="6dee6dd7803730e89fbb8089ae6c4c92bbb860e2e1cfdb09852ec30750d2f15b",
 args=character(),
 code=r"-----(#!/usr/bin/env Rscript
# Pre-model sample audit for 12-month, program-actionable discontinuation.
# This script only reads existing data and counts episodes/events. It does not
# fit or refit a regression, calculate a p-value, or alter the working HTML.

project <- if (exists("project_root", inherits = TRUE)) project_root else {
  configured <- Sys.getenv("ETHIOPIA_PROJECT_ROOT", unset = "")
  if (nzchar(configured)) normalizePath(configured) else normalizePath("..")
}
input_dir <- if (exists("input_dir", inherits = TRUE)) input_dir else
  Sys.getenv("ETHIOPIA_INPUT_DIR", unset = file.path(project, "Data"))
output_dir <- if (exists("output_dir", inherits = TRUE)) output_dir else
  Sys.getenv("ETHIOPIA_OUTPUT_DIR", unset = file.path(project, "output", "Supporting_data"))
episode_file <- file.path(output_dir,
  "selected_reason_exploratory_episode_covariates.csv")
ir_file <- file.path(input_dir, "ET2024DHS__ETIR8ADT__IR_raw.rds")
stopifnot(file.exists(episode_file), file.exists(ir_file))
e <- read.csv(episode_file)
ir <- readRDS(ir_file)
stopifnot(nrow(e) == 8611L, all(e$method_code != 16L))

actionable_codes <- c(1L, 4L, 5L, 6L, 7L, 8L, 10L, 15L)
e$actionable12 <- e$discontinued & e$exposure <= 12L &
  e$reason_code %in% actionable_codes
i <- e$woman_row
births <- as.matrix(ir[i, grep("^b3_", names(ir), value = TRUE)])
parity <- rowSums(!is.na(births) & births <= e$start)
e$parity_four <- ifelse(parity == 0, "0", ifelse(parity <= 2, "1-2",
  ifelse(parity <= 4, "3-4", "5+")))
marital <- as.integer(ir$v501[i])
e$marital_four <- ifelse(marital == 0L, "Never in union",
  ifelse(marital == 2L, "Living together",
  ifelse(marital == 1L, "Married", "Divorced/widowed/separated")))
e$wealth_five <- c("Poorest", "Poorer", "Middle", "Richer", "Richest")[
  as.integer(ir$v190[i])]
e$start_year <- (e$start - 1L) %/% 12L + 1900L

region_labels <- c(`1` = "Tigray", `2` = "Afar", `3` = "Amhara",
  `4` = "Oromia", `5` = "Somali", `6` = "Benishangul-Gumuz",
  `7` = "Central Ethiopia", `8` = "Sidama",
  `9` = "South West Ethiopia", `10` = "South Ethiopia",
  `12` = "Gambella", `13` = "Harari", `14` = "Addis Ababa",
  `15` = "Dire Dawa")
e$region_name <- unname(region_labels[as.character(e$region)])

count_cells <- function(data, variables) {
  key <- interaction(data[variables], drop = TRUE, sep = " | ")
  groups <- split(seq_len(nrow(data)), key)
  do.call(rbind, lapply(groups, function(ix) {
    out <- data[ix[1], variables, drop = FALSE]
    out$eligible_episodes <- length(ix)
    out$actionable_first_year_endings <- sum(data$actionable12[ix])
    out$distinct_women <- length(unique(data$woman_row[ix]))
    out$distinct_psus <- length(unique(data$cluster[ix]))
    out
  }))
}

variables <- c("region_name", "method_group", "age_group", "parity_four",
  "marital_four", "education", "wealth_five", "residence", "start_year")
national <- do.call(rbind, lapply(variables[-1], function(v) {
  z <- count_cells(e, v)
  names(z)[1] <- "category"
  z$variable <- v
  z[, c("variable", "category", "eligible_episodes",
    "actionable_first_year_endings", "distinct_women", "distinct_psus")]
}))
regional <- count_cells(e, "region_name")
region_method <- count_cells(e, c("region_name", "method_group"))
regional$review_flag <- regional$actionable_first_year_endings < 30L
region_method$review_flag <- region_method$eligible_episodes < 30L |
  region_method$actionable_first_year_endings < 10L

out <- output_dir
write.csv(national, file.path(out, "regional_actionable_sample_audit_national.csv"),
  row.names = FALSE)
write.csv(regional, file.path(out, "regional_actionable_sample_audit_regions.csv"),
  row.names = FALSE)
write.csv(region_method,
  file.path(out, "regional_actionable_sample_audit_region_method.csv"),
  row.names = FALSE)

cat("Eligible episodes:", nrow(e), "\n")
cat("First-year actionable endings:", sum(e$actionable12), "\n")
cat("Women:", length(unique(e$woman_row)), "PSUs:",
  length(unique(e$cluster)), "\n")
cat("Observed from method start:", sum(e$entry == 0L), "\n")
cat("Delayed entry:", sum(e$entry > 0L), "\n")
cat("\nRegional counts and review flags:\n")
print(regional[, c("region_name", "eligible_episodes",
  "actionable_first_year_endings", "review_flag")], row.names = FALSE)
cat("\nFlags are review prompts, not a formal power calculation.\n")
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 115_dhs_late_entry_reconciliation.R
# LANGUAGE: R
MODULES[["115_dhs_late_entry_reconciliation.R"]] <- list(
 language="R",
 packaged_sha256="a354e80ef6e20427bef5408395514e0fdb01bde895d1c3d87fb3e5ca50e6515e",
 args=character(),
 code=r"-----(#!/usr/bin/env Rscript
# Read-only numeric reconciliation of the published-DHS-style late-entry cohort
# and the saved program-actionable regional results. Does not fit a model.
project <- Sys.getenv("ETHIOPIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
out <- file.path(project, "output")
full <- readRDS(file.path(project, "Data/Derived",
  "ethiopia_2024_table_7_11_episodes.rds"))
modern <- read.csv(file.path(out, "Supporting_data",
  "selected_reason_exploratory_episode_covariates.csv"))
validation <- jsonlite::fromJSON(file.path(project, "output/Supporting_data/Table_7_11",
  "table_7_11_results.json"))
regions <- read.csv(file.path(out,
  "updated_regional_retained_reason_rates.csv"))
timing <- read.csv(file.path(out,
  "regional_actionable_discontinuation_3_6_9_12_months.csv"))
method <- read.csv(file.path(out,
  "regional_actionable_method_starts_and_rates.csv"))
reason_mix <- read.csv(file.path(out,
  "regional_actionable_reason_mix_by_method.csv"))

labels <- c(`1` = "Tigray", `2` = "Afar", `3` = "Amhara",
  `4` = "Oromia", `5` = "Somali", `6` = "Benishangul-Gumuz",
  `7` = "Central Ethiopia", `8` = "Sidama",
  `9` = "South West Ethiopia", `10` = "South Ethiopia",
  `12` = "Gambella", `13` = "Harari", `14` = "Addis Ababa",
  `15` = "Dire Dawa")
actionable <- c(1L, 4L, 5L, 6L, 7L, 8L, 10L, 15L)

# Multiple-decrement life table: late entrants contribute only after their
# observed entry duration; all original-method endings reduce survival.
cif <- function(x, horizon = 12L, target = actionable) {
  S <- 1; F <- 0
  for (t in seq_len(horizon)) {
    at <- x$entry < t & x$exposure >= t
    risk <- sum(x$wt[at])
    if (risk <= 0) return(NA_real_)
    ended <- at & x$discontinued & x$exposure == t
    F <- F + S * sum(x$wt[ended & x$reason_code %in% target]) / risk
    S <- S * (1 - sum(x$wt[ended]) / risk)
  }
  100 * F
}

stopifnot(nrow(full) == 9068L, sum(full$entry > 0L) == 1008L,
  abs(sum(full$wt) - 10466.942406) < 1e-5,
  sum(full$entry < 1L & full$exposure >= 1L) == 8060L,
  nrow(modern) == 8611L, sum(modern$entry > 0L) == 963L,
  validation$audit$rate_cells_matching == 66L,
  validation$audit$count_cells_matching == 6L)

observed <- numeric(); saved <- numeric(); names_out <- character()
record <- function(label, actual, published) {
  names_out <<- c(names_out, label)
  observed <<- c(observed, actual)
  saved <<- c(saved, published)
}
record("National 12-month", cif(modern),
  regions$selected_reason_12_month_probability_pct[regions$region == "All modern"])
for (month in c(3L, 6L, 9L, 12L)) {
  row <- timing[timing$region == "National" & timing$month == month, ]
  stopifnot(nrow(row) == 1L)
  record(paste("National", month, "month"), cif(modern, month),
    row$cumulative_probability_pct)
}
for (code in names(labels)) {
  name <- labels[[code]]
  z <- modern[modern$region == as.integer(code), ]
  record(paste(name, "12-month"), cif(z),
    regions$selected_reason_12_month_probability_pct[regions$region == name])
  for (month in c(3L, 6L, 9L, 12L)) {
    row <- timing[timing$region == name & timing$month == month, ]
    stopifnot(nrow(row) == 1L)
    record(paste(name, month, "month"), cif(z, month),
      row$cumulative_probability_pct)
  }
}
for (m in unique(method$method)) {
  z <- modern[modern$method_group == m, ]
  row <- method[method$region == "National" & method$method == m, ]
  stopifnot(nrow(row) == 1L)
  record(paste(m, "national 12-month"), cif(z),
    row$actionable_12_month_probability_pct)
}
for (j in seq_len(nrow(method))) {
  row <- method[j, ]
  if (row$region == "National" ||
      !is.finite(row$actionable_12_month_probability_pct)) next
  code <- names(labels)[labels == row$region]
  stopifnot(length(code) == 1L)
  z <- modern[modern$region == as.integer(code) &
    modern$method_group == row$method, ]
  if (nrow(z) == 0L) next
  actual <- cif(z)
  if (is.finite(actual)) record(paste(row$region, row$method, "12-month"),
    actual, row$actionable_12_month_probability_pct)
}
reason_codes <- list(`Method failure` = 1L,
  `Wanted more effective method` = 7L,
  `Changes in menstrual bleeding` = 15L,
  `Other side effects/health` = c(4L, 5L),
  `Access/cost/convenience` = c(6L, 8L, 10L))
for (j in seq_len(nrow(reason_mix))) {
  row <- reason_mix[j, ]
  if (!is.finite(row$cause_specific_12_month_probability_pct)) next
  if (row$region == "National") z <- modern else {
    code <- names(labels)[labels == row$region]
    stopifnot(length(code) == 1L)
    z <- modern[modern$region == as.integer(code), ]
  }
  z <- z[z$method_group == row$method, ]
  if (!nrow(z)) next
  actual <- cif(z, target = reason_codes[[row$reason]])
  if (is.finite(actual)) record(
    paste(row$region, row$method, row$reason), actual,
    row$cause_specific_12_month_probability_pct)
}
checks <- data.frame(result = names_out, recalculated_pct = observed,
  saved_pct = saved, difference_pp = observed - saved)
stopifnot(all(is.finite(checks$difference_pp)),
  max(abs(checks$difference_pp)) < 1e-8)
write.csv(checks, file.path(out, "Supporting_data",
  "dhs_late_entry_reconciliation.csv"), row.names = FALSE)
cat("PASS: Table 7.11 cohort has", nrow(full), "episodes,",
  sum(full$entry > 0L), "late entries,",
  round(sum(full$wt)), "weighted episodes; all 66 published rate cells",
  "and six counts match at report precision.\n")
cat("PASS:", nrow(checks), "saved actionable rates match the",
  "delayed-entry competing-risk life table; maximum absolute difference",
  format(max(abs(checks$difference_pp)), scientific = TRUE), "pp.\n")
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 117_export_regional_actionable_model_results.R
# LANGUAGE: R
MODULES[["117_export_regional_actionable_model_results.R"]] <- list(
 language="R",
 packaged_sha256="ab20180e0b9b2f0b7c4becff3299581b512309188acc96dc974e91edaf1d42ab",
 args=character(),
 code=r"-----(#!/usr/bin/env Rscript
# Export the already-fitted regional actionable-ending models for review.
# This script does not refit models or alter the working analysis/deck.

library(nnet)
project <- Sys.getenv("ETHIOPIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
support <- file.path(project, "output", "Supporting_data")
e <- read.csv(file.path(support, "selected_reason_exploratory_episode_covariates.csv"))
ir <- readRDS(file.path(project, "Data", "ET2024DHS__ETIR8ADT__IR_raw.rds"))
method <- readRDS(file.path(support,
  "regional_actionable_method_standardized_model_iud_sidama_ref.rds"))
full <- readRDS(file.path(support,
  "regional_actionable_full_model_iud_sidama_age25_34_urban_ref.rds"))
saved <- read.csv(file.path(support, "regional_actionable_first_model_point_estimates.csv"))
national_ci <- read.csv(file.path(support,
  "regional_actionable_national_adjusted_bootstrap_ci.csv"))
stopifnot(nrow(national_ci) == 1L, national_ci$region == "National",
  national_ci$valid_bootstrap_replicates >= 108L)
raw <- read.csv(file.path(project, "output", "updated_regional_retained_reason_rates.csv"))
raw_national <- raw[raw$region == "All modern", ]
stopifnot(nrow(raw_national) == 1L,
  identical(saved$region, raw$region[raw$region != "All modern"]))
stopifnot(nrow(e) == 8611L, method$convergence == 0L, full$convergence == 0L)

regions <- c(`1`="Tigray", `2`="Afar", `3`="Amhara", `4`="Oromia",
  `5`="Somali", `6`="Benishangul-Gumuz", `7`="Central Ethiopia",
  `8`="Sidama", `9`="South West Ethiopia", `10`="South Ethiopia",
  `12`="Gambella", `13`="Harari", `14`="Addis Ababa", `15`="Dire Dawa")
e$region <- factor(e$region, levels=method$xlevels$region)
e$method_group <- factor(e$method_group, levels=method$xlevels$method_group)
e$age_group <- factor(e$age_group, levels=full$xlevels$age_group)
births <- as.matrix(ir[e$woman_row, grep("^b3_", names(ir), value=TRUE)])
parity <- rowSums(!is.na(births) & births <= e$start)
e$parity_group <- factor(ifelse(parity == 0, "0", ifelse(parity <= 2,
  "1–2", ifelse(parity <= 4, "3–4", "5+"))), levels=full$xlevels$parity_group)
marital <- as.integer(ir$v501[e$woman_row])
e$marital_group <- factor(ifelse(marital == 0, "Never in union",
  ifelse(marital == 2, "Living together", ifelse(marital == 1, "Married",
  "Divorced/widowed/separated"))), levels=full$xlevels$marital_group)
e$education <- factor(e$education, levels=full$xlevels$education)
e$wealth_group <- factor(c("Poorest", "Poorer", "Middle", "Richer", "Richest")
  [as.integer(ir$v190[e$woman_row])], levels=full$xlevels$wealth_group)
e$residence <- factor(e$residence, levels=full$xlevels$residence)
e$start_year <- factor((e$start - 1L) %/% 12L + 1900L,
  levels=full$xlevels$start_year)
standard <- e[e$entry == 0L, ]
stopifnot(nrow(standard) == 7648L,
  !anyNA(standard[, setdiff(names(full$xlevels), "month")]))

predict_12 <- function(model, x, weights=standard$wt) {
  survival <- rep(1, nrow(x))
  incidence <- rep(0, nrow(x))
  for (t in 1:12) {
    x$month <- factor(t, levels=1:12)
    p <- predict(model, newdata=x, type="probs")
    incidence <- incidence + survival * p[, "actionable"]
    survival <- survival * p[, "continue"]
  }
  100 * weighted.mean(incidence, weights)
}

region_codes <- names(regions)[match(saved$region, regions)]
region_predictions <- lapply(region_codes, function(code) {
  x <- standard
  x$region <- factor(code, levels=levels(e$region))
  c(method=predict_12(method, x), full=predict_12(full, x))
})
region_predictions <- do.call(rbind, region_predictions)
cat(sprintf("Largest change in a saved adjusted regional estimate: %.4f percentage points\n",
  max(abs(region_predictions[, "method"] - saved$method_standardized_12_month_pct),
      abs(region_predictions[, "full"] - saved$fully_adjusted_12_month_pct))))
stopifnot(max(abs(region_predictions[, "method"] -
    saved$method_standardized_12_month_pct),
  abs(region_predictions[, "full"] -
    saved$fully_adjusted_12_month_pct)) < 0.1)
pred <- data.frame(region=c("National", saved$region),
  eligible_episodes_n=c(nrow(e), saved$eligible_episodes_n),
  actionable_endings_n=c(1321L, saved$actionable_endings_n),
  unadjusted_pct=c(raw_national$selected_reason_12_month_probability_pct,
    saved$unadjusted_12_month_pct),
  unadjusted_ci_low=c(raw_national$ci_low, saved$unadjusted_ci_low),
  unadjusted_ci_high=c(raw_national$ci_high, saved$unadjusted_ci_high),
  method_adjusted_pct=c(predict_12(method, standard),
    region_predictions[, "method"]),
  full_adjusted_pct=c(predict_12(full, standard),
    region_predictions[, "full"]),
  method_ci_low=c(national_ci$method_ci_low, saved$method_ci_low),
  method_ci_high=c(national_ci$method_ci_high, saved$method_ci_high),
  full_ci_low=c(national_ci$full_ci_low, saved$full_ci_low),
  full_ci_high=c(national_ci$full_ci_high, saved$full_ci_high),
  preliminary_bootstrap_replicates=c(national_ci$valid_bootstrap_replicates,
    saved$valid_bootstrap_replicates))
for (j in seq_len(nrow(saved))) {
  code <- names(regions)[match(saved$region[j], regions)]
  x <- standard
  x$region <- factor(code, levels=levels(e$region))
  stopifnot(abs(predict_12(method, x) - pred$method_adjusted_pct[j+1L]) < 1e-8,
    abs(predict_12(full, x) - pred$full_adjusted_pct[j+1L]) < 1e-8)
}

extract <- function(model, model_name) {
  b <- coef(model)
  stopifnot(nrow(b) == 2L, identical(rownames(b), c("actionable", "competing")))
  out <- list()
  add <- function(variable, level, ref, column) {
    k <- length(out) + 1L
    if (ref) {
      out[[k]] <<- data.frame(model=model_name, variable=variable, category=level,
        term=NA_character_, reference=TRUE, actionable_logodds=NA_real_, actionable_rrr=1,
        competing_logodds=NA_real_, competing_rrr=1)
    } else {
      stopifnot(column %in% colnames(b))
      out[[k]] <<- data.frame(model=model_name, variable=variable, category=level,
        term=column, reference=FALSE, actionable_logodds=b["actionable", column],
        actionable_rrr=exp(b["actionable", column]),
        competing_logodds=b["competing", column],
        competing_rrr=exp(b["competing", column]))
    }
  }
  add("Intercept", "Baseline category profile", FALSE, "(Intercept)")
  for (v in names(model$xlevels)) {
    for (k in seq_along(model$xlevels[[v]])) {
      lev <- model$xlevels[[v]][k]
      label <- if (v == "region") unname(regions[lev]) else lev
      if (v == "month") label <- paste0("Month ", lev)
      add(v, label, k == 1L, paste0(v, lev))
    }
  }
  do.call(rbind, out)
}
coefficients <- rbind(extract(method, "Method + duration + region"),
  extract(full, "Full model"))
write.csv(coefficients, file.path(support,
  "regional_actionable_two_model_coefficients.csv"), row.names=FALSE)
write.csv(pred, file.path(support,
  "regional_actionable_two_model_probabilities.csv"), row.names=FALSE)
cat(sprintf("Exported %d coefficient/reference rows and %d probability rows.\n",
  nrow(coefficients), nrow(pred)))
print(pred[, c("region", "method_adjusted_pct", "full_adjusted_pct")], row.names=FALSE)
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 119_regional_actionable_design_pvalues.R
# LANGUAGE: R
MODULES[["119_regional_actionable_design_pvalues.R"]] <- list(
 language="R",
 packaged_sha256="4294388b7f3b87cdaee794f5991a8a9ddfbe7978658d29f6d550e4b348d33a57",
 args=character(),
 code=r"-----(
# Full DHS sampling frame, including PSUs with no eligible outcome records.
full_survey_frame <- function(){
 r<-Sys.getenv('ETHIOPIA_PROJECT_ROOT'); stopifnot(nzchar(r))
 x<-readRDS(file.path(r,'Data/ET2024DHS__ETIR8ADT__IR_raw.rds'))
 unique(data.frame(cluster=paste(as.integer(x$v022),as.integer(x$v021),sep=':'),stratum=as.integer(x$v022)))
}
complete_survey_data <- function(d){
 r<-Sys.getenv('ETHIOPIA_PROJECT_ROOT');x<-readRDS(file.path(r,'Data/ET2024DHS__ETIR8ADT__IR_raw.rds'))
 f<-unique(data.frame(v021=as.integer(x$v021),v022=as.integer(x$v022)))
 key<-function(a,b)paste(a,b,sep=':');miss<-f[!key(f$v021,f$v022)%in%key(d$v021,d$v022),]
 if(nrow(miss)){z<-d[rep(1L,nrow(miss)),,drop=FALSE];z$v021<-miss$v021;z$v022<-miss$v022;z$wt<-0;d<-rbind(d,z)}
 d
}
#!/usr/bin/env Rscript
# Design-based Wald p-values for the two SAVED multinomial regional models.
# Uses a Taylor/sandwich variance: weighted episode-month scores are summed
# within DHS PSUs, centered within DHS strata, and premultiplied/postmultiplied
# by the model's observed weighted Hessian. Multiple episodes and months from
# one woman remain inside the same PSU. No model is refitted here.

source(file.path(Sys.getenv("ETHIOPIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE)), "Code/117_export_regional_actionable_model_results.R"))
stopifnot(all(c("cluster", "stratum") %in% names(e)))
observed_months <- pmax(0L, pmin(12L, e$exposure) - e$entry)
index <- rep(seq_len(nrow(e)), observed_months)
month <- unlist(Map(function(first, n) seq.int(first + 1L, length.out=n),
  e$entry, observed_months), use.names=FALSE)
person <- e[index, c("wt", "method_group", "age_group", "parity_group",
  "marital_group", "education", "wealth_group", "residence", "region",
  "start_year", "cluster", "stratum")]
person$month <- factor(month, levels=1:12)
ended <- e$discontinued[index] & month == e$exposure[index]
actionable <- c(1L, 4L, 5L, 6L, 7L, 8L, 10L, 15L)
person$outcome <- factor(ifelse(!ended, "continue",
  ifelse(e$reason_code[index] %in% actionable, "actionable", "competing")),
  levels=c("continue", "actionable", "competing"))
stopifnot(nrow(person) == 70691L,
  sum(person$outcome == "actionable") == 1321L)

design_variance <- function(model, name) {
  X <- model.matrix(stats::delete.response(terms(model)), data=person)
  b <- coef(model)
  stopifnot(identical(colnames(X), colnames(b)), nrow(b) == 2L)
  p <- predict(model, newdata=person, type="probs")
  stopifnot(max(abs(p - model$fitted.values)) < 1e-8)
  w <- person$wt
  a <- p[, "actionable"]
  c <- p[, "competing"]
  ya <- as.numeric(person$outcome == "actionable")
  yc <- as.numeric(person$outcome == "competing")
  qa <- w * (ya - a)
  qc <- w * (yc - c)
  # Negative weighted expected Hessian, with blocks in coefficient-row order.
  Haa <- crossprod(X, X * (w * a * (1 - a)))
  Hcc <- crossprod(X, X * (w * c * (1 - c)))
  Hac <- -crossprod(X, X * (w * a * c))
  H <- rbind(cbind(Haa, Hac), cbind(Hac, Hcc))
  Hinv <- chol2inv(chol(H))
  score <- cbind(X * qa, X * qc)
  scores <- rowsum(score, group=person$cluster, reorder=FALSE)
  frame <- full_survey_frame()
  U <- matrix(0,nrow(frame),ncol(scores));U[match(rownames(scores),frame$cluster),]<-scores
  M <- matrix(0, ncol(U), ncol(U))
  for (ids in split(seq_len(nrow(U)), frame$stratum)) {
    n <- length(ids)
    centered <- sweep(U[ids, , drop=FALSE], 2,
      colMeans(U[ids, , drop=FALSE]), "-")
    M <- M + n / (n - 1L) * crossprod(centered)
  }
  V <- Hinv %*% M %*% Hinv
  se <- sqrt(pmax(0, diag(V)))
  beta <- c(b["actionable", ], b["competing", ])
  df <- nrow(U) - length(unique(frame$stratum))
  tvalue <- beta / se
  pvalue <- 2 * pt(-abs(tvalue), df=df)
  stopifnot(all(is.finite(se)), all(se > 0), all(is.finite(pvalue)))
  term <- rep(colnames(X), 2L)
  outcome <- rep(rownames(b), each=ncol(X))
  data.frame(model=name, outcome=outcome, term=term, beta=beta,
    exponentiated_beta=exp(beta), design_se=se, design_df=df,
    t_statistic=tvalue, p_value=pvalue, ci_low=exp(beta-qt(.975,df)*se),ci_high=exp(beta+qt(.975,df)*se),
    significant_at_05=pvalue < .05)
}

result <- rbind(
  design_variance(method, "Method + duration + region"),
  design_variance(full, "Full model"))
path <- file.path(support, "regional_actionable_two_model_design_pvalues.csv")
write.csv(result, path, row.names=FALSE)
cat("Saved design-based coefficient p-values:", path, "\n")
print(result[result$model == "Full model" &
  grepl("^region", result$term) & result$outcome == "actionable",
  c("term", "exponentiated_beta", "design_se", "p_value")], row.names=FALSE)
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 120_relevel_regional_actionable_models.R
# LANGUAGE: R
MODULES[["120_relevel_regional_actionable_models.R"]] <- list(
 language="R",
 packaged_sha256="79f278b22fe2c67eccddd593080fbf0985729b2a0708feb4caef07894263ed93",
 args=character(),
 code=r"-----(#!/usr/bin/env Rscript
# Refit the two existing multinomial episode-month models with presentation
# reference categories. Releveling changes coefficients, not fitted risks.
# The original model objects and working HTML/PPTX remain untouched.

project <- Sys.getenv("ETHIOPIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
support <- file.path(project, "output", "Supporting_data")
stopifnot(requireNamespace("nnet", quietly=TRUE))
e <- read.csv(file.path(support,
  "selected_reason_exploratory_episode_covariates.csv"))
ir <- readRDS(file.path(project, "Data/ET2024DHS__ETIR8ADT__IR_raw.rds"))
old_method <- readRDS(file.path(support,
  "regional_actionable_method_standardized_model.rds"))
old_full <- readRDS(file.path(support,
  "regional_actionable_full_model.rds"))
stopifnot(nrow(e) == 8611L, all(e$method_code != 16L))

# Put the requested reference category first. Other categories retain their
# previous order, so only the coefficient contrasts change.
front <- function(x, reference) factor(x,
  levels=c(reference, setdiff(levels(factor(x)), reference)))
e$region <- front(factor(e$region, levels=old_method$xlevels$region), "8")
e$method_group <- front(factor(e$method_group,
  levels=old_method$xlevels$method_group), "IUD")
e$age_group <- front(factor(e$age_group,
  levels=old_full$xlevels$age_group), "25-34")
births <- as.matrix(ir[e$woman_row, grep("^b3_", names(ir), value=TRUE)])
parity <- rowSums(!is.na(births) & births <= e$start)
e$parity_group <- factor(ifelse(parity == 0, "0", ifelse(parity <= 2,
  "1–2", ifelse(parity <= 4, "3–4", "5+"))),
  levels=old_full$xlevels$parity_group)
marital <- as.integer(ir$v501[e$woman_row])
e$marital_group <- factor(ifelse(marital == 0, "Never in union",
  ifelse(marital == 2, "Living together", ifelse(marital == 1,
  "Married", "Divorced/widowed/separated"))),
  levels=old_full$xlevels$marital_group)
e$education <- factor(e$education, levels=old_full$xlevels$education)
e$wealth_group <- factor(c("Poorest", "Poorer", "Middle", "Richer", "Richest")
  [as.integer(ir$v190[e$woman_row])], levels=old_full$xlevels$wealth_group)
e$residence <- front(factor(e$residence,
  levels=old_full$xlevels$residence), "Urban")
e$start_year <- factor((e$start - 1L) %/% 12L + 1900L,
  levels=old_full$xlevels$start_year)

observed_months <- pmax(0L, pmin(12L, e$exposure) - e$entry)
index <- rep(seq_len(nrow(e)), observed_months)
month <- unlist(Map(function(first, n) seq.int(first + 1L, length.out=n),
  e$entry, observed_months), use.names=FALSE)
person <- e[index, c("wt", "method_group", "age_group", "parity_group",
  "marital_group", "education", "wealth_group", "residence", "region",
  "start_year")]
person$month <- factor(month, levels=1:12)
ended <- e$discontinued[index] & month == e$exposure[index]
actionable <- c(1L, 4L, 5L, 6L, 7L, 8L, 10L, 15L)
person$outcome <- factor(ifelse(!ended, "continue",
  ifelse(e$reason_code[index] %in% actionable, "actionable", "competing")),
  levels=c("continue", "actionable", "competing"))
stopifnot(nrow(person) == 70691L,
  sum(person$outcome == "actionable") == 1321L,
  !anyNA(person))

fit <- function(formula) {
  m <- nnet::multinom(formula, data=person, weights=person$wt,
    maxit=300, trace=FALSE, MaxNWts=10000)
  stopifnot(m$convergence == 0L)
  m
}
method <- fit(outcome ~ month + method_group + region)
full <- fit(outcome ~ month + method_group + region + age_group +
  parity_group + marital_group + education + wealth_group + residence +
  start_year)
stopifnot(identical(method$xlevels$method_group[1], "IUD"),
  identical(method$xlevels$region[1], "8"),
  identical(full$xlevels$age_group[1], "25-34"),
  identical(full$xlevels$residence[1], "Urban"))

# Predictions are invariant to a change of reference category, apart from
# numerical optimizer tolerance. Check all episode-month fitted probabilities.
d_method <- max(abs(predict(method, person, type="probs") -
  predict(old_method, person, type="probs")))
d_full <- max(abs(predict(full, person, type="probs") -
  predict(old_full, person, type="probs")))
cat(sprintf("Maximum absolute fitted-probability difference: model 1 %.7g; model 2 %.7g\n",
  d_method, d_full))
stopifnot(d_method < 0.002, d_full < 0.002)
saveRDS(method, file.path(support,
  "regional_actionable_method_standardized_model_iud_sidama_ref.rds"))
saveRDS(full, file.path(support,
  "regional_actionable_full_model_iud_sidama_age25_34_urban_ref.rds"))
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 122_matched_cohort_regional_raw_for_visual.R
# LANGUAGE: R
MODULES[["122_matched_cohort_regional_raw_for_visual.R"]] <- list(
 language="R",
 packaged_sha256="a66576e4c7cb21ca695fc47e765adf633625260c8caeceea4043213bc02f6cd3",
 args=character(),
 code=r"-----(#!/usr/bin/env Rscript
# Preview comparison only: calculate unadjusted, weighted 12-month competing-risk
# probabilities among the same episodes observed from method start that form the
# standardization reference for the adjusted model. All ending reasons reduce
# survival; only method-experience/access reasons count toward the target CIF.
project <- Sys.getenv("ETHIOPIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
support <- file.path(project, "output", "Supporting_data")
e <- read.csv(file.path(support,
  "selected_reason_exploratory_episode_covariates.csv"))
e <- e[e$entry == 0L, ]
stopifnot(nrow(e) == 7648L)
actionable <- c(1L, 4L, 5L, 6L, 7L, 8L, 10L, 15L)
labels <- c(`1`="Tigray", `2`="Afar", `3`="Amhara", `4`="Oromia",
  `5`="Somali", `6`="Benishangul-Gumuz", `7`="Central Ethiopia",
  `8`="Sidama", `9`="South West Ethiopia", `10`="South Ethiopia",
  `12`="Gambella", `13`="Harari", `14`="Addis Ababa", `15`="Dire Dawa")
estimate <- function(z) {
  surv <- 1; cif <- 0
  for (t in 1:12) {
    at <- z$exposure >= t
    ending <- at & z$discontinued & z$exposure == t
    risk <- sum(z$wt[at])
    stopifnot(risk > 0)
    all <- sum(z$wt[ending]) / risk
    selected <- sum(z$wt[ending & z$reason_code %in% actionable]) / risk
    cif <- cif + surv * selected
    surv <- surv * (1 - all)
  }
  100 * cif
}
rows <- lapply(c(NA_integer_, as.integer(names(labels))), function(code) {
  z <- if (is.na(code)) e else e[e$region == code, ]
  data.frame(region=if (is.na(code)) "National" else labels[as.character(code)],
    observed_start_episodes_n=nrow(z), matched_unadjusted_pct=estimate(z))
})
raw <- do.call(rbind, rows)
adjusted <- read.csv(file.path(support,
  "regional_actionable_two_model_probabilities.csv"))
result <- merge(raw, adjusted[, c("region", "full_adjusted_pct")], by="region",
  sort=FALSE)
result <- result[match(raw$region, result$region), ]
stopifnot(nrow(result) == 15L, !anyNA(result),
  abs(result$matched_unadjusted_pct[result$region=="National"] - 17) < 3)
write.csv(result, file.path(support,
  "regional_actionable_matched_raw_vs_full_adjusted_preview.csv"),
  row.names=FALSE)
print(result, row.names=FALSE)
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 126_regional_own_mix_model_predictions.R
# LANGUAGE: R
MODULES[["126_regional_own_mix_model_predictions.R"]] <- list(
 language="R",
 packaged_sha256="58af09899e92c1051c8957674492a6f54dd5b78cacc332645387871c3f8b63b6",
 args=character(),
 code=r"-----(#!/usr/bin/env Rscript
# Model 2 predicted 12-month actionable-ending risk averaged over observed
# method starts actually recorded in each region. This retains each region's
# method and measured covariate mix. It is distinct from common-mix predictions.
project <- Sys.getenv("ETHIOPIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
library(nnet)
support <- file.path(project, "output", "Supporting_data")
e <- read.csv(file.path(support, "selected_reason_exploratory_episode_covariates.csv"))
ir <- readRDS(file.path(project, "Data", "ET2024DHS__ETIR8ADT__IR_raw.rds"))
model <- readRDS(file.path(support,
  "regional_actionable_full_model_iud_sidama_age25_34_urban_ref.rds"))
comparison <- read.csv(file.path(support,
  "regional_actionable_two_model_probabilities.csv"))
matched <- read.csv(file.path(support,
  "regional_actionable_matched_raw_vs_full_adjusted_preview.csv"))
stopifnot(nrow(e) == 8611L, model$convergence == 0L)
regions <- c(`1`="Tigray", `2`="Afar", `3`="Amhara", `4`="Oromia",
  `5`="Somali", `6`="Benishangul-Gumuz", `7`="Central Ethiopia",
  `8`="Sidama", `9`="South West Ethiopia", `10`="South Ethiopia",
  `12`="Gambella", `13`="Harari", `14`="Addis Ababa", `15`="Dire Dawa")
e$region <- factor(e$region, levels=model$xlevels$region)
e$method_group <- factor(e$method_group, levels=model$xlevels$method_group)
e$age_group <- factor(e$age_group, levels=model$xlevels$age_group)
births <- as.matrix(ir[e$woman_row, grep("^b3_", names(ir), value=TRUE)])
parity <- rowSums(!is.na(births) & births <= e$start)
e$parity_group <- factor(ifelse(parity==0, "0", ifelse(parity<=2,
  "1–2", ifelse(parity<=4, "3–4", "5+"))), levels=model$xlevels$parity_group)
marital <- as.integer(ir$v501[e$woman_row])
e$marital_group <- factor(ifelse(marital==0, "Never in union",
  ifelse(marital==2, "Living together", ifelse(marital==1, "Married",
  "Divorced/widowed/separated"))), levels=model$xlevels$marital_group)
e$education <- factor(e$education, levels=model$xlevels$education)
e$wealth_group <- factor(c("Poorest", "Poorer", "Middle", "Richer", "Richest")
  [as.integer(ir$v190[e$woman_row])], levels=model$xlevels$wealth_group)
e$residence <- factor(e$residence, levels=model$xlevels$residence)
e$start_year <- factor((e$start - 1L) %/% 12L + 1900L,
  levels=model$xlevels$start_year)
starts <- e[e$entry==0L, ]
stopifnot(nrow(starts)==7648L,
  !anyNA(starts[, setdiff(names(model$xlevels), "month")]))
predict_12 <- function(x) {
  s <- rep(1, nrow(x)); f <- rep(0, nrow(x))
  for (t in 1:12) {
    x$month <- factor(t, levels=1:12)
    p <- predict(model, newdata=x, type="probs")
    f <- f + s * p[, "actionable"]
    s <- s * p[, "continue"]
  }
  100 * weighted.mean(f, x$wt)
}
codes <- c(NA_character_, names(regions))
labels <- c("National", unname(regions))
rows <- lapply(seq_along(codes), function(j) {
  x <- if (is.na(codes[j])) starts else starts[
    as.character(starts$region)==codes[j], ]
  old <- comparison[comparison$region==labels[j], ]
  raw <- matched[matched$region==labels[j], ]
  stopifnot(nrow(x)>0L, nrow(old)==1L, nrow(raw)==1L,
    nrow(x)==raw$observed_start_episodes_n)
  data.frame(region=labels[j], observed_start_episodes_n=nrow(x),
    observed_start_weighted=sum(x$wt),
    dhs_style_raw_pct=old$unadjusted_pct,
    matched_start_raw_pct=raw$matched_unadjusted_pct,
    model2_own_region_mix_pct=predict_12(x),
    model2_common_mix_pct=old$full_adjusted_pct)
})
result <- do.call(rbind, rows)
stopifnot(nrow(result)==15L, all(is.finite(result$model2_own_region_mix_pct)))
write.csv(result, file.path(support,
  "regional_actionable_model2_own_mix_vs_common_mix.csv"), row.names=FALSE)
print(result[, c("region", "observed_start_episodes_n", "matched_start_raw_pct",
  "model2_own_region_mix_pct", "model2_common_mix_pct")], row.names=FALSE)
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 129_test_regional_actionable_differences.R
# LANGUAGE: R
MODULES[["129_test_regional_actionable_differences.R"]] <- list(
 language="R",
 packaged_sha256="26bb80dfa55bdef753864b114f8795921c2dae01f23d9580ec254b29c9b9922d",
 args=character(),
 code=r"-----(
# Algebraically identical monthly multinomial prediction, with the design
# matrix constructed once instead of once per duration month.
fast_survey_cif<-function(model,x,weights,event){
 x$month<-factor(1,levels=1:12)
 X<-model.matrix(delete.response(terms(model)),data=x,contrasts.arg=model$contrasts)
 b<-coef(model);eta<-X[,colnames(b),drop=FALSE]%*%t(b)
 S<-rep(1,nrow(x));F<-numeric(nrow(x));j<-match(event,rownames(b))
 for(t in 1:12){off<-if(t==1)rep(0,nrow(b))else b[,paste0('month',t)];ee<-exp(sweep(eta,2,off,'+'));den<-1+rowSums(ee);F<-F+S*ee[,j]/den;S<-S/den}
 100*weighted.mean(F,weights)
}

# Full DHS sampling frame, including PSUs with no eligible outcome records.
full_survey_frame <- function(){
 r<-Sys.getenv('ETHIOPIA_PROJECT_ROOT'); stopifnot(nzchar(r))
 x<-readRDS(file.path(r,'Data/ET2024DHS__ETIR8ADT__IR_raw.rds'))
 unique(data.frame(cluster=paste(as.integer(x$v022),as.integer(x$v021),sep=':'),stratum=as.integer(x$v022)))
}
complete_survey_data <- function(d){
 r<-Sys.getenv('ETHIOPIA_PROJECT_ROOT');x<-readRDS(file.path(r,'Data/ET2024DHS__ETIR8ADT__IR_raw.rds'))
 f<-unique(data.frame(v021=as.integer(x$v021),v022=as.integer(x$v022)))
 key<-function(a,b)paste(a,b,sep=':');miss<-f[!key(f$v021,f$v022)%in%key(d$v021,d$v022),]
 if(nrow(miss)){z<-d[rep(1L,nrow(miss)),,drop=FALSE];z$v021<-miss$v021;z$v022<-miss$v022;z$wt<-0;d<-rbind(d,z)}
 d
}
#!/usr/bin/env Rscript
# First regression comparison for regional, potentially actionable
# original-modern-method discontinuation during months 1–12.
#
# The unit is an episode-month from the same EC-excluded complete-case cohort
# used in the regional descriptive figures. A month has one of three mutually
# exclusive outcomes: continuing the original method, ending for one of the
# eight recorded method-experience/access codes below, or ending for any other
# reason. The latter endings are competing events, not exclusions or censoring.
# Episodes that began before the observed calendar enter at their observed
# duration. A woman may contribute multiple episodes; the supplied PSU/stratum
# fields permit design-based bootstrap uncertainty in a subsequent run.
#
# This first run produces point estimates only. Do not interpret observed
# differences as statistically significant without survey-design intervals.
# No DHS data download or package installation is performed here.

project <- Sys.getenv("ETHIOPIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
support <- file.path(project, "output", "Supporting_data")
if (!requireNamespace("nnet", quietly = TRUE))
  stop("Install the nnet package before running this script")
e <- read.csv(file.path(support,
  "selected_reason_exploratory_episode_covariates.csv"))
ir <- readRDS(file.path(project, "Data/ET2024DHS__ETIR8ADT__IR_raw.rds"))
stopifnot(nrow(e) == 8611L, all(e$method_code != 16L),
          !anyNA(e[, c("wt", "entry", "exposure", "discontinued",
                       "reason_code", "region", "cluster", "stratum")]))

region_labels <- c(
  `1` = "Tigray", `2` = "Afar", `3` = "Amhara", `4` = "Oromia",
  `5` = "Somali", `6` = "Benishangul-Gumuz",
  `7` = "Central Ethiopia", `8` = "Sidama",
  `9` = "South West Ethiopia", `10` = "South Ethiopia",
  `12` = "Gambella", `13` = "Harari", `14` = "Addis Ababa",
  `15` = "Dire Dawa")
actionable <- c(1L, 4L, 5L, 6L, 7L, 8L, 10L, 15L)
e$region <- factor(e$region, levels = as.integer(names(region_labels)))
e$method_group <- factor(e$method_group,
  levels = c("Injectables", "Implants", "Pill", "IUD", "Other modern"))
e$age_group <- factor(e$age_group,
  levels = c("15-19", "20-24", "25-34", "35-49"))
e$education <- factor(e$education,
  levels = c("None", "Primary", "Secondary+"))
e$residence <- factor(e$residence, levels = c("Rural", "Urban"))

# Parity is reconstructed at the episode start month from birth dates. The
# four categories and four marital categories match the latest full model.
i <- e$woman_row
birth_cols <- grep("^b3_", names(ir), value = TRUE)
births <- as.matrix(ir[i, birth_cols])
parity <- rowSums(!is.na(births) & births <= e$start)
marital <- as.integer(ir$v501[i])
wealth <- as.integer(ir$v190[i])
stopifnot(!anyNA(parity), all(marital %in% 0:5), all(wealth %in% 1:5))
e$parity_group <- factor(ifelse(parity == 0, "0",
  ifelse(parity <= 2, "1–2", ifelse(parity <= 4, "3–4", "5+"))),
  levels = c("0", "1–2", "3–4", "5+"))
e$marital_group <- factor(ifelse(marital == 0L, "Never in union",
  ifelse(marital == 2L, "Living together",
  ifelse(marital == 1L, "Married", "Divorced/widowed/separated"))),
  levels = c("Never in union", "Living together", "Married",
             "Divorced/widowed/separated"))
e$wealth_group <- factor(
  c("Poorest", "Poorer", "Middle", "Richer", "Richest")[wealth],
  levels = c("Poorest", "Poorer", "Middle", "Richer", "Richest"))
e$start_year <- factor((e$start - 1L) %/% 12L + 1900L)

# Expand each episode into observed exposure months, keeping its DHS weight.
observed_months <- pmax(0L, pmin(12L, e$exposure) - e$entry)
index <- rep(seq_len(nrow(e)), observed_months)
month <- unlist(Map(function(first, n) seq.int(first + 1L, length.out = n),
  e$entry, observed_months), use.names = FALSE)
person <- e[index, c("wt", "method_group", "age_group", "parity_group",
  "marital_group", "education", "wealth_group", "residence", "region",
  "start_year", "cluster", "stratum")]
person$month <- factor(month, levels = 1:12)
ended <- e$discontinued[index] & month == e$exposure[index]
person$outcome <- factor(ifelse(!ended, "continue",
  ifelse(e$reason_code[index] %in% actionable, "actionable", "competing")),
  levels = c("continue", "actionable", "competing"))
stopifnot(nrow(person) == 70691L,
          sum(person$outcome == "actionable") == 1321L)

# Inferential bootstrap for direct differences in the fully adjusted
# 12-month cumulative incidence. The same replicate PSU weights are applied
# to model fitting and to the common observed-start reference population.
# All episodes from a sampled woman stay in the same sampled PSU. Endings for
# reasons outside the actionable set remain competing events in the outcome.
# This standalone script writes new draws and does not overwrite the 120-draw
# preliminary regression estimates or the working presentation files.
B <- as.integer(Sys.getenv("REGIONAL_ACTIONABLE_PAIRWISE_REPS", "1000"))
if (!is.finite(B) || B < 500L)
  stop("Use at least 500 survey-stratified PSU bootstrap refits")
standard <- e[e$entry == 0L, ]
stopifnot(nrow(standard) == 7648L)
full_formula <- outcome ~ month + method_group + region + age_group +
  parity_group + marital_group + education + wealth_group + residence +
  start_year

predict_risk <- function(model, region_code, weights) {x<-standard;if(!is.null(region_code))x$region<-factor(region_code,levels=levels(e$region));fast_survey_cif(model,x,weights,'actionable')}

frame <- full_survey_frame()
by_stratum <- split(frame$cluster, frame$stratum)
stopifnot(all(lengths(by_stratum) > 1L))
region_codes <- levels(e$region)
one_replicate <- function(b) {
  set.seed(20261020L + b)
  multiplier <- setNames(numeric(nrow(frame)), frame$cluster)
  for (ids in by_stratum) {
    n <- length(ids)
    multiplier[as.character(ids)] <- n / (n - 1L) *
      tabulate(sample.int(n, n - 1L, replace = TRUE), nbins = n)
  }
  p <- person
  p$boot_weight <- p$wt * multiplier[as.character(p$cluster)]
  std_weight <- standard$wt * multiplier[as.character(standard$cluster)]
  model <- tryCatch(nnet::multinom(full_formula, data = p,
    weights = boot_weight, maxit = 300, trace = FALSE,
    MaxNWts = 10000), error = function(err) NULL)
  if (is.null(model) || model$convergence != 0L)
    return(rep(NA_real_, length(region_codes) + 1L))
  c(vapply(region_codes, function(code)
    predict_risk(model, code, std_weight), numeric(1)),
    predict_risk(model, NULL, std_weight))
}

draws <- parallel::mclapply(seq_len(B), one_replicate,
  mc.cores = min(4L, parallel::detectCores()), mc.preschedule = FALSE)
draws <- do.call(rbind, draws)
colnames(draws) <- c(paste0("full::", unname(region_labels[region_codes])),
  "full::National")
valid <- complete.cases(draws)
if (sum(valid) < ceiling(.95 * B))
  stop(sprintf("Only %d of %d full-model bootstrap refits converged",
    sum(valid), B))
write.csv(data.frame(replicate = seq_len(B), draws, check.names = FALSE),
  file.path(support, "regional_actionable_full_model_pairwise_bootstrap.csv"),
  row.names = FALSE)
cat(sprintf("Full-model regional comparison: %d/%d valid design-bootstrap refits\n",
  sum(valid), B))
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 130_regional_actionable_raw_pairwise_bootstrap.R
# LANGUAGE: R
MODULES[["130_regional_actionable_raw_pairwise_bootstrap.R"]] <- list(
 language="R",
 packaged_sha256="086f21da98d10bc09b85268ed86e7943ee4a06e571dec0afec92740cbf87866b",
 args=character(),
 code=r"-----(
# Full DHS sampling frame, including PSUs with no eligible outcome records.
full_survey_frame <- function(){
 r<-Sys.getenv('ETHIOPIA_PROJECT_ROOT'); stopifnot(nzchar(r))
 x<-readRDS(file.path(r,'Data/ET2024DHS__ETIR8ADT__IR_raw.rds'))
 unique(data.frame(cluster=paste(as.integer(x$v022),as.integer(x$v021),sep=':'),stratum=as.integer(x$v022)))
}
complete_survey_data <- function(d){
 r<-Sys.getenv('ETHIOPIA_PROJECT_ROOT');x<-readRDS(file.path(r,'Data/ET2024DHS__ETIR8ADT__IR_raw.rds'))
 f<-unique(data.frame(v021=as.integer(x$v021),v022=as.integer(x$v022)))
 key<-function(a,b)paste(a,b,sep=':');miss<-f[!key(f$v021,f$v022)%in%key(d$v021,d$v022),]
 if(nrow(miss)){z<-d[rep(1L,nrow(miss)),,drop=FALSE];z$v021<-miss$v021;z$v022<-miss$v022;z$wt<-0;d<-rbind(d,z)}
 d
}
#!/usr/bin/env Rscript
# Regional cumulative discontinuation at 3, 6, 9, and 12 months for the
# narrower method-experience/access outcome. The source episode cohort and
# retained native calendar reason codes match Code/90. All nonretained method
# endings remain competing events. The month-specific risk set accommodates
# episodes already in progress when the calendar window begins.
#
# Stratified PSU bootstrap intervals retain all episodes from a woman/PSU
# together. Input data already comes from the documented calendar and IR
# import pipeline; this script does not download DHS data or install packages.

project <- Sys.getenv("ETHIOPIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
out <- file.path(project, "output")
e <- read.csv(file.path(out, "Supporting_data",
  "selected_reason_exploratory_episode_covariates.csv"),
  stringsAsFactors = FALSE)
previous <- read.csv(file.path(out,
  "updated_regional_retained_reason_rates.csv"), stringsAsFactors = FALSE)
stopifnot(nrow(e) == 8611L, nrow(previous) == 15L)

regions <- c(`1` = "Tigray", `2` = "Afar", `3` = "Amhara", `4` = "Oromia",
             `5` = "Somali", `6` = "Benishangul-Gumuz", `7` = "Central Ethiopia",
             `8` = "Sidama", `9` = "South West Ethiopia", `10` = "South Ethiopia",
             `12` = "Gambella", `13` = "Harari", `14` = "Addis Ababa",
             `15` = "Dire Dawa")
codes <- c(NA_integer_, as.integer(names(regions)))
names(codes) <- c("National", unname(regions))
months <- c(3L, 6L, 9L, 12L)
retained <- c(1L, 4L, 5L, 6L, 7L, 8L, 10L, 15L)

frame <- full_survey_frame()
frame$id <- seq_len(nrow(frame))
e$id <- frame$id[match(e$cluster, frame$cluster)]
groups <- split(frame$id, frame$stratum)
stopifnot(!anyNA(e$id), all(lengths(groups) > 1L))
K <- nrow(frame)

fill <- function(a, mask, t) {
  if (!any(mask)) return(a)
  z <- rowsum(e$wt[mask], e$id[mask], reorder = FALSE)
  a[as.integer(rownames(z)), t] <- z[, 1L]
  a
}
array_for <- function(scope) {
  risk <- ended <- selected <- matrix(0, K, 12L)
  for (t in seq_len(12L)) {
    at <- scope & e$entry < t & e$exposure >= t
    stop <- at & e$discontinued & e$exposure == t
    chosen <- stop & e$reason_code %in% retained
    risk <- fill(risk, at, t)
    ended <- fill(ended, stop, t)
    selected <- fill(selected, chosen, t)
  }
  list(risk = risk, ended = ended, selected = selected)
}
arrays <- lapply(codes, function(code)
  array_for(if (is.na(code)) rep(TRUE, nrow(e)) else e$region == code))

cif <- function(a, mult) {
  R <- as.numeric(crossprod(mult, a$risk))
  A <- as.numeric(crossprod(mult, a$ended))
  D <- as.numeric(crossprod(mult, a$selected))
  if (any(R <= 0) || any(A > R + 1e-7)) return(rep(NA_real_, 4L))
  s <- 1; f <- 0; values <- numeric(12L)
  for (t in seq_len(12L)) {
    f <- f + s * D[t] / R[t]
    s <- s * (1 - A[t] / R[t])
    values[t] <- 100 * f
  }
  values[months]
}
point <- t(vapply(arrays, cif, numeric(4L), mult = rep(1, K)))
colnames(point) <- paste0("m", months)
stopifnot(all(diff(point[1L, ]) >= 0), all(point >= 0))
for (j in seq_along(codes)) {
  old <- previous[previous$region == if (j == 1L) "All modern" else names(codes)[j], ]
  stopifnot(nrow(old) == 1L,
    abs(point[j, 4L] - old$selected_reason_12_month_probability_pct) < 1e-8)
}

B <- as.integer(Sys.getenv("REGIONAL_ACTIONABLE_RAW_PAIRWISE_REPS", "10000"))
boot <- array(NA_real_, c(B, length(codes), 4L))
for (b in seq_len(B)) {
  set.seed(20261019L + b)
  mult <- numeric(K)
  for (ids in groups) {
    n <- length(ids)
    mult[ids] <- n / (n - 1L) *
      tabulate(sample.int(n, n - 1L, replace = TRUE), nbins = n)
  }
  boot[b, , ] <- t(vapply(arrays, cif, numeric(4L), mult = mult))
}
stopifnot(all(apply(!is.na(boot), c(2, 3), sum) >= .95 * B))

# Save the 12-month estimates jointly for direct regional contrasts. Reusing
# the same PSU resample for every region preserves their design covariance.
draws_12 <- boot[, , 4L]
colnames(draws_12) <- names(codes)
write.csv(data.frame(replicate = seq_len(B), draws_12,
  check.names = FALSE), file.path(out, "Supporting_data",
  "regional_actionable_raw_pairwise_bootstrap.csv"), row.names = FALSE)
draws_3 <- boot[, , 1L]
colnames(draws_3) <- names(codes)
write.csv(data.frame(replicate = seq_len(B), draws_3,
  check.names = FALSE), file.path(out, "Supporting_data",
  "regional_actionable_raw_pairwise_3_month_bootstrap.csv"), row.names = FALSE)
cat(sprintf("Raw regional comparison: %d/%d valid 12-month draws\n",
  sum(complete.cases(draws_12)), B))
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 131_summarize_regional_actionable_pairwise_tests.R
# LANGUAGE: R
MODULES[["131_summarize_regional_actionable_pairwise_tests.R"]] <- list(
 language="R",
 packaged_sha256="c8d37024205dbe4118b407f9852c730c9bb0b064d601404b171b37101cae989b",
 args=character(),
 code=r"-----(#!/usr/bin/env Rscript
# Test whether 12-month cumulative incidence of potentially actionable
# original-modern-method discontinuation differs across Ethiopia regions.
# The observed estimates use the DHS-style delayed-entry competing-risk life
# table. The fully adjusted estimates use the already documented Model 2 and
# a common observed-start reference population. Each survey-stratified PSU
# bootstrap replicate contains all regions, so a pairwise difference is
# calculated within the same replicate and preserves design covariance.
# This script uses bootstrap standard errors for Wald p-values and applies
# Holm correction across all 91 regional pairs. Its percentile intervals are
# pointwise, not familywise-adjusted, and are reported alongside Holm p-values.

project <- Sys.getenv("ETHIOPIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
support <- file.path(project, "output", "Supporting_data")
prob <- read.csv(file.path(support,
  "regional_actionable_two_model_probabilities.csv"), check.names = FALSE)
raw_boot <- read.csv(file.path(support,
  "regional_actionable_raw_pairwise_bootstrap.csv"), check.names = FALSE)
full_boot <- read.csv(file.path(support,
  "regional_actionable_full_model_pairwise_bootstrap.csv"),
  check.names = FALSE)
method_boot <- read.csv(file.path(support,
  "regional_actionable_method_model_pairwise_bootstrap.csv"),
  check.names = FALSE)
regions <- prob$region[prob$region != "National"]
stopifnot(length(regions) == 14L, nrow(raw_boot) >= 10000L,
  nrow(full_boot) >= 500L, nrow(method_boot) >= 500L,
  all(regions %in% names(raw_boot)),
  all(paste0("full::", regions) %in% names(full_boot)),
  all(paste0("method::", regions) %in% names(method_boot)))

point_raw <- setNames(prob$unadjusted_pct[prob$region != "National"],
  regions)
point_full <- setNames(prob$full_adjusted_pct[prob$region != "National"],
  regions)
point_method <- setNames(prob$method_adjusted_pct[prob$region != "National"],
  regions)
draw_raw <- as.matrix(raw_boot[, regions, drop = FALSE])
draw_raw<-draw_raw[complete.cases(draw_raw),,drop=FALSE]
stopifnot(nrow(draw_raw)>=.95*nrow(raw_boot))
draw_full <- as.matrix(full_boot[, paste0("full::", regions),
  drop = FALSE])
colnames(draw_full) <- regions
draw_full <- draw_full[complete.cases(draw_full), , drop = FALSE]
stopifnot(nrow(draw_full) >= .95 * nrow(full_boot))
draw_method <- as.matrix(method_boot[, paste0("method::", regions),
  drop = FALSE])
colnames(draw_method) <- regions
draw_method <- draw_method[complete.cases(draw_method), , drop = FALSE]
stopifnot(nrow(draw_method) >= .95 * nrow(method_boot))

pair_table <- function(point, draws, model) {
  pairs <- combn(regions, 2L, simplify = FALSE)
  rows <- lapply(pairs, function(pair) {
    high <- pair[which.max(point[pair])]
    low <- pair[which.min(point[pair])]
    difference <- unname(point[high] - point[low])
    replicate_difference <- draws[, high] - draws[, low]
    se <- sd(replicate_difference)
    ci <- unname(quantile(replicate_difference, c(.025, .975)))
    data.frame(model = model, higher_region = high, lower_region = low,
      higher_rate_pct = unname(point[high]),
      lower_rate_pct = unname(point[low]),
      difference_pp = difference, ci_low_pp = ci[1L],
      ci_high_pp = ci[2L], bootstrap_se_pp = se,
      p_value = 2 * pnorm(-abs(difference / se)),
      valid_bootstrap_replicates = length(replicate_difference))
  })
  tab <- do.call(rbind, rows)
  tab$holm_p <- p.adjust(tab$p_value, method = "holm")
  # The displayed familywise interval uses Bonferroni's conservative critical
  # value for the same 91-comparison family. Holm-adjusted p-values are also
  # retained; they may flag slightly more contrasts than these intervals.
  critical <- qnorm(1 - .05 / (2 * nrow(tab)))
  tab$familywise_ci_low_pp <- tab$difference_pp -
    critical * tab$bootstrap_se_pp
  tab$familywise_ci_high_pp <- tab$difference_pp +
    critical * tab$bootstrap_se_pp
  tab$significant_5pct <- tab$holm_p < .05
  tab <- tab[order(tab$holm_p, tab$p_value), ]
  rownames(tab) <- NULL
  stopifnot(nrow(tab) == 91L)
  tab
}

global_test <- function(point, draws, model, excluded = character()) {
  in_scope <- setdiff(regions, excluded)
  reference <- "Sidama"
  others <- setdiff(in_scope, reference)
  differences <- unname(point[others] - point[reference])
  boot_differences <- sweep(draws[, others, drop = FALSE], 1L,
    draws[, reference], FUN = "-")
  variance <- cov(boot_differences)
  statistic <- as.numeric(t(differences) %*% solve(variance, differences))
  data.frame(model = model,
    comparison = if (length(excluded))
      "Sensitivity: omit Somali (five selected endings)" else
      "All 14 regions",
    regions_tested = length(in_scope), degrees_of_freedom = length(others),
    wald_chisq = statistic,
    p_value = pchisq(statistic, df = length(others), lower.tail = FALSE),
    valid_bootstrap_replicates = nrow(draws))
}

raw <- pair_table(point_raw, draw_raw, "Observed")
method <- pair_table(point_method, draw_method, "Model 1: method and duration")
full <- pair_table(point_full, draw_full, "Fully adjusted Model 2")
global <- rbind(global_test(point_raw, draw_raw, "Observed"),
  global_test(point_raw, draw_raw, "Observed", "Somali"),
  global_test(point_method, draw_method, "Model 1: method and duration"),
  global_test(point_method, draw_method, "Model 1: method and duration",
    "Somali"),
  global_test(point_full, draw_full, "Fully adjusted Model 2"),
  global_test(point_full, draw_full, "Fully adjusted Model 2", "Somali"))
write.csv(raw, file.path(support,
  "regional_actionable_raw_pairwise_tests.csv"), row.names = FALSE)
write.csv(method, file.path(support,
  "regional_actionable_method_pairwise_tests.csv"), row.names = FALSE)
write.csv(full, file.path(support,
  "regional_actionable_full_pairwise_tests.csv"), row.names = FALSE)
write.csv(global, file.path(support,
  "regional_actionable_global_tests.csv"), row.names = FALSE)

# The earlier presentation intervals used 120 refits. Replace them with the
# matching 1,000-refit percentile intervals so the chart, tables, and direct
# tests all draw uncertainty from the same survey-design bootstrap runs.
percentile_ci <- function(boot, column) {
  unname(quantile(boot[[column]], c(.025, .975), na.rm = TRUE))
}
for (i in seq_len(nrow(prob))) {
  name <- prob$region[i]
  m <- percentile_ci(method_boot, paste0("method::", name))
  f <- percentile_ci(full_boot, paste0("full::", name))
  prob$method_ci_low[i] <- m[1L]
  prob$method_ci_high[i] <- m[2L]
  prob$full_ci_low[i] <- f[1L]
  prob$full_ci_high[i] <- f[2L]
  prob$preliminary_bootstrap_replicates[i] <- min(
    sum(is.finite(method_boot[[paste0("method::", name)]])),
    sum(is.finite(full_boot[[paste0("full::", name)]])))
}
write.csv(prob, file.path(support,
  "regional_actionable_two_model_probabilities.csv"), row.names = FALSE)
saved <- read.csv(file.path(support,
  "regional_actionable_first_model_point_estimates.csv"))
for (i in seq_len(nrow(saved))) {
  match_row <- prob[prob$region == saved$region[i], ]
  stopifnot(nrow(match_row) == 1L)
  for (column in c("method_ci_low", "method_ci_high", "full_ci_low",
                   "full_ci_high"))
    saved[[column]][i] <- match_row[[column]]
  saved$valid_bootstrap_replicates[i] <-
    match_row$preliminary_bootstrap_replicates
}
write.csv(saved, file.path(support,
  "regional_actionable_first_model_point_estimates.csv"), row.names = FALSE)
national <- prob[prob$region == "National", ]
write.csv(data.frame(region = "National",
  method_ci_low = national$method_ci_low,
  method_ci_high = national$method_ci_high,
  full_ci_low = national$full_ci_low,
  full_ci_high = national$full_ci_high,
  valid_bootstrap_replicates = national$preliminary_bootstrap_replicates),
  file.path(support,
    "regional_actionable_national_adjusted_bootstrap_ci.csv"),
  row.names = FALSE)
cat("Global tests:\n")
print(global, row.names = FALSE)
cat("Holm-significant observed contrasts:", sum(raw$significant_5pct), "\n")
print(raw[raw$significant_5pct,
  c("higher_region", "lower_region", "difference_pp", "holm_p")],
  row.names = FALSE)
cat("Holm-significant method-and-duration contrasts:",
  sum(method$significant_5pct), "\n")
print(method[method$significant_5pct,
  c("higher_region", "lower_region", "difference_pp", "holm_p")],
  row.names = FALSE)
cat("Holm-significant fully adjusted contrasts:",
  sum(full$significant_5pct), "\n")
print(full[full$significant_5pct,
  c("higher_region", "lower_region", "difference_pp", "holm_p")],
  row.names = FALSE)
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 133_test_regional_actionable_method_mix_differences.R
# LANGUAGE: R
MODULES[["133_test_regional_actionable_method_mix_differences.R"]] <- list(
 language="R",
 packaged_sha256="e527f4f937ad93cfe98ef6f985006594bea8b5a2bffd9a6c8184cdb0ffea249b",
 args=character(),
 code=r"-----(
# Algebraically identical monthly multinomial prediction, with the design
# matrix constructed once instead of once per duration month.
fast_survey_cif<-function(model,x,weights,event){
 x$month<-factor(1,levels=1:12)
 X<-model.matrix(delete.response(terms(model)),data=x,contrasts.arg=model$contrasts)
 b<-coef(model);eta<-X[,colnames(b),drop=FALSE]%*%t(b)
 S<-rep(1,nrow(x));F<-numeric(nrow(x));j<-match(event,rownames(b))
 for(t in 1:12){off<-if(t==1)rep(0,nrow(b))else b[,paste0('month',t)];ee<-exp(sweep(eta,2,off,'+'));den<-1+rowSums(ee);F<-F+S*ee[,j]/den;S<-S/den}
 100*weighted.mean(F,weights)
}

# Full DHS sampling frame, including PSUs with no eligible outcome records.
full_survey_frame <- function(){
 r<-Sys.getenv('ETHIOPIA_PROJECT_ROOT'); stopifnot(nzchar(r))
 x<-readRDS(file.path(r,'Data/ET2024DHS__ETIR8ADT__IR_raw.rds'))
 unique(data.frame(cluster=paste(as.integer(x$v022),as.integer(x$v021),sep=':'),stratum=as.integer(x$v022)))
}
complete_survey_data <- function(d){
 r<-Sys.getenv('ETHIOPIA_PROJECT_ROOT');x<-readRDS(file.path(r,'Data/ET2024DHS__ETIR8ADT__IR_raw.rds'))
 f<-unique(data.frame(v021=as.integer(x$v021),v022=as.integer(x$v022)))
 key<-function(a,b)paste(a,b,sep=':');miss<-f[!key(f$v021,f$v022)%in%key(d$v021,d$v022),]
 if(nrow(miss)){z<-d[rep(1L,nrow(miss)),,drop=FALSE];z$v021<-miss$v021;z$v022<-miss$v022;z$wt<-0;d<-rbind(d,z)}
 d
}
#!/usr/bin/env Rscript
# First regression comparison for regional, potentially actionable
# original-modern-method discontinuation during months 1–12.
#
# The unit is an episode-month from the same EC-excluded complete-case cohort
# used in the regional descriptive figures. A month has one of three mutually
# exclusive outcomes: continuing the original method, ending for one of the
# eight recorded method-experience/access codes below, or ending for any other
# reason. The latter endings are competing events, not exclusions or censoring.
# Episodes that began before the observed calendar enter at their observed
# duration. A woman may contribute multiple episodes; the supplied PSU/stratum
# fields permit design-based bootstrap uncertainty in a subsequent run.
#
# This first run produces point estimates only. Do not interpret observed
# differences as statistically significant without survey-design intervals.
# No DHS data download or package installation is performed here.

project <- Sys.getenv("ETHIOPIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
support <- file.path(project, "output", "Supporting_data")
if (!requireNamespace("nnet", quietly = TRUE))
  stop("Install the nnet package before running this script")
e <- read.csv(file.path(support,
  "selected_reason_exploratory_episode_covariates.csv"))
ir <- readRDS(file.path(project, "Data/ET2024DHS__ETIR8ADT__IR_raw.rds"))
stopifnot(nrow(e) == 8611L, all(e$method_code != 16L),
          !anyNA(e[, c("wt", "entry", "exposure", "discontinued",
                       "reason_code", "region", "cluster", "stratum")]))

region_labels <- c(
  `1` = "Tigray", `2` = "Afar", `3` = "Amhara", `4` = "Oromia",
  `5` = "Somali", `6` = "Benishangul-Gumuz",
  `7` = "Central Ethiopia", `8` = "Sidama",
  `9` = "South West Ethiopia", `10` = "South Ethiopia",
  `12` = "Gambella", `13` = "Harari", `14` = "Addis Ababa",
  `15` = "Dire Dawa")
actionable <- c(1L, 4L, 5L, 6L, 7L, 8L, 10L, 15L)
e$region <- factor(e$region, levels = as.integer(names(region_labels)))
e$method_group <- factor(e$method_group,
  levels = c("Injectables", "Implants", "Pill", "IUD", "Other modern"))
e$age_group <- factor(e$age_group,
  levels = c("15-19", "20-24", "25-34", "35-49"))
e$education <- factor(e$education,
  levels = c("None", "Primary", "Secondary+"))
e$residence <- factor(e$residence, levels = c("Rural", "Urban"))

# Parity is reconstructed at the episode start month from birth dates. The
# four categories and four marital categories match the latest full model.
i <- e$woman_row
birth_cols <- grep("^b3_", names(ir), value = TRUE)
births <- as.matrix(ir[i, birth_cols])
parity <- rowSums(!is.na(births) & births <= e$start)
marital <- as.integer(ir$v501[i])
wealth <- as.integer(ir$v190[i])
stopifnot(!anyNA(parity), all(marital %in% 0:5), all(wealth %in% 1:5))
e$parity_group <- factor(ifelse(parity == 0, "0",
  ifelse(parity <= 2, "1–2", ifelse(parity <= 4, "3–4", "5+"))),
  levels = c("0", "1–2", "3–4", "5+"))
e$marital_group <- factor(ifelse(marital == 0L, "Never in union",
  ifelse(marital == 2L, "Living together",
  ifelse(marital == 1L, "Married", "Divorced/widowed/separated"))),
  levels = c("Never in union", "Living together", "Married",
             "Divorced/widowed/separated"))
e$wealth_group <- factor(
  c("Poorest", "Poorer", "Middle", "Richer", "Richest")[wealth],
  levels = c("Poorest", "Poorer", "Middle", "Richer", "Richest"))
e$start_year <- factor((e$start - 1L) %/% 12L + 1900L)

# Expand each episode into observed exposure months, keeping its DHS weight.
observed_months <- pmax(0L, pmin(12L, e$exposure) - e$entry)
index <- rep(seq_len(nrow(e)), observed_months)
month <- unlist(Map(function(first, n) seq.int(first + 1L, length.out = n),
  e$entry, observed_months), use.names = FALSE)
person <- e[index, c("wt", "method_group", "age_group", "parity_group",
  "marital_group", "education", "wealth_group", "residence", "region",
  "start_year", "cluster", "stratum")]
person$month <- factor(month, levels = 1:12)
ended <- e$discontinued[index] & month == e$exposure[index]
person$outcome <- factor(ifelse(!ended, "continue",
  ifelse(e$reason_code[index] %in% actionable, "actionable", "competing")),
  levels = c("continue", "actionable", "competing"))
stopifnot(nrow(person) == 70691L,
          sum(person$outcome == "actionable") == 1321L)

# Inferential bootstrap for direct differences in the method-and-duration adjusted
# 12-month cumulative incidence. The same replicate PSU weights are applied
# to model fitting and to the common observed-start reference population.
# All episodes from a sampled woman stay in the same sampled PSU. Endings for
# reasons outside the actionable set remain competing events in the outcome.
# This standalone script writes new draws and does not overwrite the 120-draw
# preliminary regression estimates or the working presentation files.
B <- as.integer(Sys.getenv("REGIONAL_ACTIONABLE_METHOD_PAIRWISE_REPS", "1000"))
if (!is.finite(B) || B < 500L)
  stop("Use at least 500 survey-stratified PSU bootstrap refits")
standard <- e[e$entry == 0L, ]
stopifnot(nrow(standard) == 7648L)
model_formula <- outcome ~ month + method_group + region

predict_risk <- function(model, region_code, weights) {x<-standard;if(!is.null(region_code))x$region<-factor(region_code,levels=levels(e$region));fast_survey_cif(model,x,weights,'actionable')}

frame <- full_survey_frame()
by_stratum <- split(frame$cluster, frame$stratum)
stopifnot(all(lengths(by_stratum) > 1L))
region_codes <- levels(e$region)
one_replicate <- function(b) {
  set.seed(20261020L + b)
  multiplier <- setNames(numeric(nrow(frame)), frame$cluster)
  for (ids in by_stratum) {
    n <- length(ids)
    multiplier[as.character(ids)] <- n / (n - 1L) *
      tabulate(sample.int(n, n - 1L, replace = TRUE), nbins = n)
  }
  p <- person
  p$boot_weight <- p$wt * multiplier[as.character(p$cluster)]
  std_weight <- standard$wt * multiplier[as.character(standard$cluster)]
  model <- tryCatch(nnet::multinom(model_formula, data = p,
    weights = boot_weight, maxit = 300, trace = FALSE,
    MaxNWts = 10000), error = function(err) NULL)
  if (is.null(model) || model$convergence != 0L)
    return(rep(NA_real_, length(region_codes) + 1L))
  c(vapply(region_codes, function(code)
    predict_risk(model, code, std_weight), numeric(1)),
    predict_risk(model, NULL, std_weight))
}

draws <- parallel::mclapply(seq_len(B), one_replicate,
  mc.cores = min(4L, parallel::detectCores()), mc.preschedule = FALSE)
draws <- do.call(rbind, draws)
colnames(draws) <- c(paste0("method::", unname(region_labels[region_codes])),
  "method::National")
valid <- complete.cases(draws)
if (sum(valid) < ceiling(.95 * B))
  stop(sprintf("Only %d of %d method-model bootstrap refits converged",
    sum(valid), B))
write.csv(data.frame(replicate = seq_len(B), draws, check.names = FALSE),
  file.path(support, "regional_actionable_method_model_pairwise_bootstrap.csv"),
  row.names = FALSE)
cat(sprintf("Method-and-duration regional comparison: %d/%d valid design-bootstrap refits\n",
  sum(valid), B))
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 134_regional_actionable_all_region_method_mix.R
# LANGUAGE: R
MODULES[["134_regional_actionable_all_region_method_mix.R"]] <- list(
 language="R",
 packaged_sha256="ebd32b18f082c7b3902d436923760ee706478c4eab584e76dc46feafc209ac60",
 args=character(),
 code=r"-----(
# Full DHS sampling frame, including PSUs with no eligible outcome records.
full_survey_frame <- function(){
 r<-Sys.getenv('ETHIOPIA_PROJECT_ROOT'); stopifnot(nzchar(r))
 x<-readRDS(file.path(r,'Data/ET2024DHS__ETIR8ADT__IR_raw.rds'))
 unique(data.frame(cluster=paste(as.integer(x$v022),as.integer(x$v021),sep=':'),stratum=as.integer(x$v022)))
}
complete_survey_data <- function(d){
 r<-Sys.getenv('ETHIOPIA_PROJECT_ROOT');x<-readRDS(file.path(r,'Data/ET2024DHS__ETIR8ADT__IR_raw.rds'))
 f<-unique(data.frame(v021=as.integer(x$v021),v022=as.integer(x$v022)))
 key<-function(a,b)paste(a,b,sep=':');miss<-f[!key(f$v021,f$v022)%in%key(d$v021,d$v022),]
 if(nrow(miss)){z<-d[rep(1L,nrow(miss)),,drop=FALSE];z$v021<-miss$v021;z$v022<-miss$v022;z$wt<-0;d<-rbind(d,z)}
 d
}
#!/usr/bin/env Rscript
# Compare each Ethiopian region's modeled 12-month actionable original-method
# discontinuation probability under its own modern-method start mix and under
# the same national modern-method start mix. This is a model-based accounting
# identity, not an exact decomposition of the DHS-style observed life table.
#
# Cohort: 8,611 complete-case, EC-excluded modern-method episodes for model
# fitting; 7,648 observed starts for the own/common mix comparison. Late-entry
# episodes contribute only their observed months to the fitted model. Other
# discontinuation reasons remain competing events. Method mix is estimated
# from the same 7,648 observed starts, not from all-method starts or survey-date
# current users. Region is measured at interview.
#
# Model: survey-weighted discrete-time multinomial regression with additive
# method, duration-month, and region terms. It assumes a common regional logit
# shift across methods; it does not estimate region-by-method interactions.
# Bootstrap: Rao-Wu rescaled PSU sampling within DHS strata, keeping all
# episode-months from one woman together. Uses the same seeds and fitting
# formula as Code/133, so common-mix draws can be cross-checked exactly.

project <- Sys.getenv("ETHIOPIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
support <- file.path(project, "output", "Supporting_data")
if (!requireNamespace("nnet", quietly = TRUE)) stop("Install R package nnet")
e <- read.csv(file.path(support,
  "selected_reason_exploratory_episode_covariates.csv"))
stopifnot(nrow(e) == 8611L, all(e$method_code != 16L))
region_labels <- c(`1`="Tigray", `2`="Afar", `3`="Amhara", `4`="Oromia",
  `5`="Somali", `6`="Benishangul-Gumuz", `7`="Central Ethiopia",
  `8`="Sidama", `9`="South West Ethiopia", `10`="South Ethiopia",
  `12`="Gambella", `13`="Harari", `14`="Addis Ababa", `15`="Dire Dawa")
methods <- c("Injectables", "Implants", "Pill", "IUD", "Other modern")
actionable <- c(1L, 4L, 5L, 6L, 7L, 8L, 10L, 15L)
e$region <- factor(e$region, levels=as.integer(names(region_labels)))
e$method_group <- factor(e$method_group, levels=methods)
standard <- e[e$entry == 0L, ]
stopifnot(nrow(standard) == 7648L)

observed_months <- pmax(0L, pmin(12L, e$exposure) - e$entry)
index <- rep(seq_len(nrow(e)), observed_months)
month <- unlist(Map(function(first, n) seq.int(first + 1L, length.out=n),
  e$entry, observed_months), use.names=FALSE)
person <- e[index, c("wt", "region", "method_group", "cluster", "stratum")]
person$month <- factor(month, levels=1:12)
ended <- e$discontinued[index] & month == e$exposure[index]
person$outcome <- factor(ifelse(!ended, "continue",
  ifelse(e$reason_code[index] %in% actionable, "actionable", "competing")),
  levels=c("continue", "actionable", "competing"))
stopifnot(nrow(person) == 70691L, sum(person$outcome == "actionable") == 1321L)

region_codes <- levels(e$region)
grid <- expand.grid(region=region_codes, method_group=methods,
  month=as.character(1:12), KEEP.OUT.ATTRS=FALSE,
  stringsAsFactors=FALSE)
grid$region <- factor(grid$region, levels=region_codes)
grid$method_group <- factor(grid$method_group, levels=methods)
grid$month <- factor(grid$month, levels=1:12)

calculate <- function(model, std_weight) {
  # Directly estimate one cumulative incidence per region and method. Since
  # Model 1 contains only region, method and month, no other episode profile
  # is needed to compute the predicted risk for a region-method combination.
  p <- predict(model, newdata=grid, type="probs")
  risk <- matrix(NA_real_, length(region_codes), length(methods),
    dimnames=list(unname(region_labels[region_codes]), methods))
  for (ri in seq_along(region_codes)) for (mi in seq_along(methods)) {
    at <- which(grid$region == region_codes[ri] &
      grid$method_group == methods[mi])
    at <- at[order(as.integer(grid$month[at]))]
    survival <- 1; incidence <- 0
    for (j in at) {
      incidence <- incidence + survival * p[j, "actionable"]
      survival <- survival * p[j, "continue"]
    }
    risk[ri, mi] <- 100 * incidence
  }
  count <- matrix(0, length(region_codes), length(methods),
    dimnames=dimnames(risk))
  for (ri in seq_along(region_codes)) for (mi in seq_along(methods))
    count[ri, mi] <- sum(std_weight[standard$region == region_codes[ri] &
      standard$method_group == methods[mi]])
  national_share <- colSums(count) / sum(count)
  own_share <- count / rowSums(count)
  own <- rowSums(own_share * risk)
  common <- as.vector(risk %*% national_share)
  names(common) <- names(own)
  national <- sum(rowSums(count) * own) / sum(count)
  stopifnot(abs(national - sum(national_share *
    colSums(count * risk) / colSums(count))) < 1e-9)
  list(own=own, common=common, mix_effect=own-common,
    own_gap=own-national, common_gap=common-national,
    national=national, risk=risk, own_share=own_share,
    national_share=national_share,
    count=count)
}

fit <- readRDS(file.path(support,
  "regional_actionable_method_standardized_model.rds"))
point <- calculate(fit, standard$wt)
legacy <- read.csv(file.path(support,
  "regional_actionable_two_model_probabilities.csv"))
for (ri in seq_along(region_codes)) {
  old <- legacy$method_adjusted_pct[legacy$region == names(point$common)[ri]]
  # Presentation coefficients were refit with different reference categories;
  # optimizer tolerance can change a reported percentage by a few hundredths.
  if (length(old) != 1L || abs(old-point$common[ri]) > .1)
    stop(sprintf("Common-mix mismatch for %s: old=%g new=%g",
      names(point$common)[ri], old, point$common[ri]))
}

frame <- full_survey_frame()
by_stratum <- split(frame$cluster, frame$stratum)
stopifnot(all(lengths(by_stratum) > 1L))
B <- as.integer(Sys.getenv("REGIONAL_ACTIONABLE_MIX_REPS", "1000"))
if (!is.finite(B) || B < 100L) stop("Set at least 100 bootstrap replicates")
one_replicate <- function(b) {
  set.seed(20261020L + b)
  multiplier <- setNames(numeric(nrow(frame)), frame$cluster)
  for (ids in by_stratum) {
    n <- length(ids)
    multiplier[as.character(ids)] <- n/(n-1L) *
      tabulate(sample.int(n, n-1L, replace=TRUE), nbins=n)
  }
  p <- person
  p$boot_weight <- p$wt * multiplier[as.character(p$cluster)]
  std_weight <- standard$wt * multiplier[as.character(standard$cluster)]
  model <- tryCatch(nnet::multinom(
    outcome ~ month + method_group + region, data=p,
    weights=boot_weight, maxit=300, trace=FALSE, MaxNWts=10000),
    error=function(err) NULL)
  if (is.null(model) || model$convergence != 0L)
    return(rep(NA_real_, 5L*length(region_codes)+1L+
      2L*length(region_codes)*length(methods)))
  v <- calculate(model, std_weight)
  c(v$own, v$common, v$mix_effect, v$own_gap, v$common_gap,
    v$national, as.vector(t(v$risk)), as.vector(t(v$own_share)))
}
draws <- parallel::mclapply(seq_len(B), one_replicate,
  mc.cores=min(4L, parallel::detectCores()), mc.preschedule=FALSE)
draws <- do.call(rbind, draws)
colnames(draws) <- c(paste0("own::", names(point$own)),
  paste0("common::", names(point$common)),
  paste0("mix::", names(point$mix_effect)),
  paste0("own_gap::", names(point$own_gap)),
  paste0("common_gap::", names(point$common_gap)), "national",
  unlist(lapply(names(point$own), function(r) paste0("risk::", r, "::", methods))),
  unlist(lapply(names(point$own), function(r) paste0("share::", r, "::", methods))))
if (sum(complete.cases(draws)) < .95*B)
  stop("Too few survey-design bootstrap refits converged")

# The first 1,000 common-mix refits use the same resampling seed, formula and
# standard population as Code/133. An exact match audits this extension.
existing <- read.csv(file.path(support,
  "regional_actionable_method_model_pairwise_bootstrap.csv"),
  check.names=FALSE)
if (nrow(existing) >= B) for (name in names(point$common)) {
  difference <- max(abs(draws[, paste0("common::",name)] -
    existing[[paste0("method::",name)]][seq_len(B)]), na.rm=TRUE)
  if (!is.finite(difference) || difference > 1e-6)
    stop(sprintf("Bootstrap mismatch for %s: %.8f", name, difference))
}

ci <- function(column) as.numeric(quantile(draws[, column],
  c(.025,.975), na.rm=TRUE))
rows <- lapply(seq_along(region_codes), function(i) {
  name <- names(point$own)[i]
  data.frame(region=name,
    observed_start_n=sum(standard$region == region_codes[i]),
    selected_endings_n=sum(e$region == region_codes[i] & e$discontinued &
      e$exposure <= 12 & e$reason_code %in% actionable),
    model_own_mix_pct=point$own[i],
    own_ci_low=ci(paste0("own::",name))[1],
    own_ci_high=ci(paste0("own::",name))[2],
    model_common_mix_pct=point$common[i],
    common_ci_low=ci(paste0("common::",name))[1],
    common_ci_high=ci(paste0("common::",name))[2],
    mix_effect_pp=point$mix_effect[i],
    mix_ci_low=ci(paste0("mix::",name))[1],
    mix_ci_high=ci(paste0("mix::",name))[2],
    common_gap_from_national_pp=point$common_gap[i],
    common_gap_ci_low=ci(paste0("common_gap::",name))[1],
    common_gap_ci_high=ci(paste0("common_gap::",name))[2],
    sparse_cell=any(point$count[i,] < 30),
    valid_draws=sum(is.finite(draws[, paste0("common::",name)])))
})
summary <- do.call(rbind, rows)
mix <- do.call(rbind, lapply(seq_along(region_codes), function(i)
  data.frame(region=names(point$own)[i], method=methods,
    observed_start_n=as.numeric(sapply(methods, function(m)
      sum(standard$region==region_codes[i] & standard$method_group==m))),
    weighted_starts=as.numeric(point$count[i,]),
    weighted_start_share_pct=100*point$own_share[i,],
    model_method_risk_pct=point$risk[i,], row.names=NULL)))
mix <- rbind(data.frame(region="National", method=methods,
  observed_start_n=as.numeric(table(standard$method_group)),
  weighted_starts=as.numeric(colSums(point$count)),
  weighted_start_share_pct=100*point$national_share,
  model_method_risk_pct=NA_real_), mix)
write.csv(summary, file.path(support,
  "regional_actionable_all_region_method_mix_comparison.csv"), row.names=FALSE)
write.csv(mix, file.path(support,
  "regional_actionable_all_region_method_mix_cells.csv"), row.names=FALSE)
write.csv(data.frame(replicate=seq_len(B), draws, check.names=FALSE),
  file.path(support,
    "regional_actionable_all_region_method_mix_bootstrap.csv"),
  row.names=FALSE)
cat("Valid refits:",sum(complete.cases(draws)),"/",B,"\n")
cat("National modeled risk:",point$national,"\n")
print(summary[,c("region","observed_start_n","model_own_mix_pct",
  "model_common_mix_pct","mix_effect_pp","common_gap_from_national_pp",
  "sparse_cell")],row.names=FALSE)
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 138_regional_actionable_3_month_pairwise_tests.R
# LANGUAGE: R
MODULES[["138_regional_actionable_3_month_pairwise_tests.R"]] <- list(
 language="R",
 packaged_sha256="8aa18e1bd9b454499622350ab1063b2aeaab8605a65d0d2d3d6bf6fdf0dc822a",
 args=character(),
 code=r"-----(#!/usr/bin/env Rscript
# Pairwise tests of unadjusted 3-month cumulative incidence of discontinuation
# due to potentially actionable reasons. Same 8,611 eligible modern-method
# episodes, competing-event life table, survey weights, and stratified PSU
# bootstrap as the 12-month regional test in Code/130 and Code/131.
project <- Sys.getenv("ETHIOPIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
out <- file.path(project, "output")
support <- file.path(out, "Supporting_data")
points <- read.csv(file.path(out,
  "regional_actionable_discontinuation_3_6_9_12_months.csv"))
points <- points[points$month == 3L & points$region != "National", ]
draws <- read.csv(file.path(support,
  "regional_actionable_raw_pairwise_3_month_bootstrap.csv"),
  check.names = FALSE)
regions <- points$region
stopifnot(length(regions) == 14L, nrow(draws) == 10000L,
  all(regions %in% names(draws)))
point <- setNames(points$cumulative_probability_pct, regions)
pairs <- combn(regions, 2L, simplify = FALSE)
results <- do.call(rbind, lapply(pairs, function(pair) {
  higher <- pair[which.max(point[pair])]
  lower <- pair[which.min(point[pair])]
  difference <- unname(point[higher] - point[lower])
  bootstrap_difference <- draws[[higher]] - draws[[lower]]
  bootstrap_difference <- bootstrap_difference[is.finite(bootstrap_difference)]
  se <- sd(bootstrap_difference)
  interval <- unname(quantile(bootstrap_difference, c(.025, .975)))
  data.frame(higher_region = higher, lower_region = lower,
    higher_rate_pct = unname(point[higher]),
    lower_rate_pct = unname(point[lower]),
    difference_pp = difference, ci_low_pp = interval[1L],
    ci_high_pp = interval[2L], bootstrap_se_pp = se,
    p_value = 2 * pnorm(-abs(difference / se)),
    valid_bootstrap_replicates = length(bootstrap_difference))
}))
results$holm_p <- p.adjust(results$p_value, method = "holm")
results$significant_5pct <- results$holm_p < .05
results <- results[order(results$holm_p, results$p_value), ]
rownames(results) <- NULL
stopifnot(nrow(results) == 91L)
write.csv(results, file.path(support,
  "regional_actionable_raw_3_month_pairwise_tests.csv"), row.names = FALSE)
cat("Holm-significant three-month pairs:", sum(results$significant_5pct), "\n")
print(results[results$significant_5pct,
  c("higher_region", "lower_region", "higher_rate_pct", "lower_rate_pct",
    "difference_pp", "ci_low_pp", "ci_high_pp", "holm_p")], row.names = FALSE)
cat("Lowest adjusted p-values:\n")
print(head(results[, c("higher_region", "lower_region", "difference_pp",
  "p_value", "holm_p")], 10L), row.names = FALSE)
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 139_plot_regional_actionable_three_comparisons.R
# LANGUAGE: R
MODULES[["139_plot_regional_actionable_three_comparisons.R"]] <- list(
 language="R",
 packaged_sha256="cd81cdada0025899e1a1868e39bca00ea9c75a185b72675e51df6ffbad4a640b",
 args=character(),
 code=r"-----(#!/usr/bin/env Rscript
# Presentation view of three distinct regional comparisons for 12-month
# actionable discontinuation. The figure displays three policy-relevant pairs
# that pass Holm correction in at least one analysis. It does not claim that
# the change between panels is a formal decomposition of the observed gap.
project <- Sys.getenv("ETHIOPIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
support <- file.path(project, "output", "Supporting_data")
assets <- file.path(project, "output", "assets")
dir.create(assets, recursive=TRUE, showWarnings=FALSE)
if (!requireNamespace("ggplot2", quietly=TRUE) ||
    !requireNamespace("svglite", quietly=TRUE))
  stop("R packages ggplot2 and svglite are required")
library(ggplot2)

raw <- read.csv(file.path(support,
  "regional_actionable_raw_pairwise_tests.csv"))
mix <- read.csv(file.path(support,
  "regional_actionable_pairwise_shared_method_mix.csv"))
full <- read.csv(file.path(support,
  "regional_actionable_full_pairwise_tests.csv"))
pairs <- list(c("Tigray","Amhara"), c("Tigray","Addis Ababa"),
  c("Central Ethiopia","Amhara"))
pair_names <- c("Tigray vs Amhara", "Tigray vs Addis Ababa",
  "Central Ethiopia vs Amhara")
panel_names <- c("Observed", "Same method mix",
  "Same methods + characteristics")
rows <- list()
for (i in seq_along(pairs)) {
  a <- pairs[[i]][1]; b <- pairs[[i]][2]
  r <- raw[raw$higher_region == a & raw$lower_region == b, ]
  f <- full[full$higher_region == a & full$lower_region == b, ]
  m <- mix[mix$region_a %in% c(a,b) & mix$region_b %in% c(a,b), ]
  stopifnot(nrow(r)==1L,nrow(f)==1L,nrow(m)==1L)
  sign <- if (m$region_a == a) 1 else -1
  rows[[length(rows)+1L]] <- data.frame(pair=pair_names[i],
    stage=panel_names[1], gap=r$difference_pp, low=r$ci_low_pp,
    high=r$ci_high_pp, holm_p=r$holm_p)
  rows[[length(rows)+1L]] <- data.frame(pair=pair_names[i],
    stage=panel_names[2], gap=sign*m$pair_shared_mix_gap_pp,
    low=if (sign==1) m$shared_gap_ci_low else -m$shared_gap_ci_high,
    high=if (sign==1) m$shared_gap_ci_high else -m$shared_gap_ci_low,
    holm_p=m$holm_p)
  rows[[length(rows)+1L]] <- data.frame(pair=pair_names[i],
    stage=panel_names[3], gap=f$difference_pp, low=f$ci_low_pp,
    high=f$ci_high_pp, holm_p=f$holm_p)
}
d <- do.call(rbind,rows)
d$pair <- factor(d$pair,levels=rev(pair_names))
d$stage <- factor(d$stage,levels=panel_names)
d$significant <- factor(ifelse(d$holm_p<.05,"Passes correction",
  "Does not pass correction"),
  levels=c("Passes correction","Does not pass correction"))
d$label <- sprintf("%.1f",d$gap)
write.csv(d,file.path(support,
  "regional_actionable_three_comparison_highlights.csv"),row.names=FALSE)

cols <- c("Observed"="#D99A20", "Same method mix"="#108C90",
  "Same methods + characteristics"="#173E5B")
g <- ggplot(d,aes(x=gap,y=pair,color=stage))+
  geom_vline(xintercept=0,color="#B9C7CF",linewidth=.55)+
  geom_segment(aes(x=low,xend=high,yend=pair),linewidth=1.1)+
  geom_point(aes(shape=significant),size=3.9,stroke=1.2,fill="white")+
  geom_text(aes(x=17.3,label=label),hjust=0,color="#173E5B",
    fontface="bold",size=4.3,show.legend=FALSE)+
  facet_grid(~stage)+
  scale_color_manual(values=cols,guide="none")+
  scale_shape_manual(values=c("Passes correction"=16,
    "Does not pass correction"=1),name=NULL)+
  scale_x_continuous(limits=c(-1,20),breaks=c(0,5,10,15),
    expand=expansion(mult=0))+
  labs(title="Two regional gaps persist across all three comparisons",
    subtitle="12-month discontinuation for potentially actionable reasons · percentage-point gap",
    x="Higher region minus lower region (percentage points)",y=NULL,
    caption=paste("Bars: pointwise 95% survey-bootstrap intervals. Filled circles: Holm-adjusted p < 0.05 across 91 pairs.",
      "Observed = DHS-style life table; same method mix = pair-specific Model 1 standardization;",
      "full adjustment = Model 2 on one common observed-start reference population. Panels are not an exact decomposition.",
      sep="\n"))+
  theme_minimal(base_size=14)+
  theme(plot.background=element_rect(fill="white",color=NA),
    panel.background=element_rect(fill="white",color=NA),
    panel.grid.major.y=element_blank(),panel.grid.minor=element_blank(),
    panel.grid.major.x=element_line(color="#E4EBEF",linewidth=.45),
    strip.text=element_text(face="bold",color="#173E5B",size=13),
    strip.background=element_rect(fill="#F0F5F7",color=NA),
    axis.text.y=element_text(color="#173E5B",face="bold",size=11),
    axis.text.x=element_text(color="#344F60"),
    axis.title.x=element_text(color="#173E5B",margin=margin(t=9)),
    plot.title=element_text(face="bold",color="#173E5B",size=21),
    plot.subtitle=element_text(color="#344F60",size=12),
    plot.caption=element_text(color="#536B79",size=9,hjust=0,
      margin=margin(t=12)),
    legend.position="top",legend.justification="left",
    panel.spacing.x=grid::unit(1.1,"lines"),
    plot.margin=margin(18,30,15,20))
ggsave(file.path(assets,"regional_actionable_three_comparisons.png"),
  g,width=15,height=6.2,dpi=200,bg="white")
ggsave(file.path(assets,"regional_actionable_three_comparisons.svg"),
  g,width=15,height=6.2,device=svglite::svglite,bg="white")
print(d[,c("pair","stage","gap","low","high","holm_p")],row.names=FALSE)
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 141_regional_method_interaction_actionable.R
# LANGUAGE: R
MODULES[["141_regional_method_interaction_actionable.R"]] <- list(
 language="R",
 packaged_sha256="c3886aa805782eb73eeeae74f2e2a3cdeac337ee9a26e3b348a2f2e865ee64a8",
 args=character(),
 code=r"-----(
# Full DHS sampling frame, including PSUs with no eligible outcome records.
full_survey_frame <- function(){
 r<-Sys.getenv('ETHIOPIA_PROJECT_ROOT'); stopifnot(nzchar(r))
 x<-readRDS(file.path(r,'Data/ET2024DHS__ETIR8ADT__IR_raw.rds'))
 unique(data.frame(cluster=paste(as.integer(x$v022),as.integer(x$v021),sep=':'),stratum=as.integer(x$v022)))
}
complete_survey_data <- function(d){
 r<-Sys.getenv('ETHIOPIA_PROJECT_ROOT');x<-readRDS(file.path(r,'Data/ET2024DHS__ETIR8ADT__IR_raw.rds'))
 f<-unique(data.frame(v021=as.integer(x$v021),v022=as.integer(x$v022)))
 key<-function(a,b)paste(a,b,sep=':');miss<-f[!key(f$v021,f$v022)%in%key(d$v021,d$v022),]
 if(nrow(miss)){z<-d[rep(1L,nrow(miss)),,drop=FALSE];z$v021<-miss$v021;z$v022<-miss$v022;z$wt<-0;d<-rbind(d,z)}
 d
}
#!/usr/bin/env Rscript
# Focused region-by-method analysis of 12-month modern-method discontinuation
# for potentially actionable reasons. Other endings are competing events.
# Four regions and three methods were prespecified from the earlier regional
# comparison and sample-size audit. This is a new focused model, not the
# earlier all-region Model 2. Delayed entries enter at observed duration.
project <- Sys.getenv("ETHIOPIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
support <- file.path(project,"output","Supporting_data")
stopifnot(requireNamespace("nnet",quietly=TRUE))
e <- read.csv(file.path(support,
  "selected_reason_exploratory_episode_covariates.csv"))
ir <- readRDS(file.path(project,"Data/ET2024DHS__ETIR8ADT__IR_raw.rds"))
region_codes <- c("Tigray"=1L,"Amhara"=3L,
  "Central Ethiopia"=7L,"Addis Ababa"=14L)
method_names <- c("Injectables","Implants","Pill")
actionable <- c(1L,4L,5L,6L,7L,8L,10L,15L)
stopifnot(nrow(e)==8611L,all(e$method_code!=16L))
e <- e[e$region %in% region_codes &
  e$method_group %in% method_names,]
stopifnot(nrow(e)==2726L)
e$region_name <- factor(names(region_codes)[match(e$region,region_codes)],
  levels=names(region_codes))
e$method_group <- factor(e$method_group,levels=method_names)
e$age_group <- factor(e$age_group,
  levels=c("15-19","20-24","25-34","35-49"))
e$education <- factor(e$education,
  levels=c("None","Primary","Secondary+"))
e$residence <- factor(e$residence,levels=c("Rural","Urban"))
i <- e$woman_row
births <- as.matrix(ir[i,grep("^b3_",names(ir),value=TRUE)])
parity <- rowSums(!is.na(births)&births<=e$start)
marital <- as.integer(ir$v501[i])
wealth <- as.integer(ir$v190[i])
stopifnot(!anyNA(parity),all(marital %in% 0:5),all(wealth %in% 1:5))
e$parity_group <- factor(ifelse(parity==0,"0",
  ifelse(parity<=2,"1-2",ifelse(parity<=4,"3-4","5+"))),
  levels=c("0","1-2","3-4","5+"))
e$marital_group <- factor(ifelse(marital==0L,"Never in union",
  ifelse(marital==2L,"Living together",
  ifelse(marital==1L,"Married","Divorced/widowed/separated"))),
  levels=c("Never in union","Living together","Married",
    "Divorced/widowed/separated"))
e$wealth_group <- factor(c("Poorest","Poorer","Middle","Richer","Richest")[wealth],
  levels=c("Poorest","Poorer","Middle","Richer","Richest"))
e$start_year <- factor((e$start-1L)%/%12L+1900L)
exposure_months <- pmax(0L,pmin(12L,e$exposure)-e$entry)
idx <- rep(seq_len(nrow(e)),exposure_months)
mo <- unlist(Map(function(first,n)seq.int(first+1L,length.out=n),
  e$entry,exposure_months),use.names=FALSE)
person <- e[idx,c("wt","region_name","method_group","age_group",
  "parity_group","marital_group","education","wealth_group","residence",
  "start_year","cluster","stratum")]
person$month <- factor(mo,levels=1:12)
ended <- e$discontinued[idx]&mo==e$exposure[idx]
person$outcome <- factor(ifelse(!ended,"continue",
  ifelse(e$reason_code[idx] %in% actionable,"actionable","competing")),
  levels=c("continue","actionable","competing"))
formula <- outcome ~ month + region_name*method_group + age_group +
  parity_group + marital_group + education + wealth_group + residence +
  start_year
reference <- e[e$entry==0L,]
stopifnot(nrow(reference)==2462L)
grid <- expand.grid(region=names(region_codes),method=method_names,
  stringsAsFactors=FALSE)
times <- c(3L,6L,12L)
predict_one <- function(model,region,method,weights) {
  x <- reference
  x$region_name <- factor(region,levels=levels(e$region_name))
  x$method_group <- factor(method,levels=method_names)
  survival <- rep(1,nrow(x)); incidence <- rep(0,nrow(x))
  answer <- numeric(length(times))
  for(t in 1:12) {
    x$month <- factor(t,levels=1:12)
    p <- predict(model,newdata=x,type="probs")
    incidence <- incidence+survival*p[,"actionable"]
    survival <- survival*p[,"continue"]
    if(t %in% times)
      answer[match(t,times)] <- 100*weighted.mean(incidence,weights)
  }
  answer
}
calculate <- function(model,weights) {
  result <- unlist(lapply(seq_len(nrow(grid)),function(j)
    predict_one(model,grid$region[j],grid$method[j],weights)))
  names(result) <- unlist(lapply(seq_len(nrow(grid)),function(j)
    paste(grid$region[j],grid$method[j],times,sep="::")))
  result
}
fit <- nnet::multinom(formula,data=person,weights=person$wt,
  maxit=400,trace=FALSE,MaxNWts=10000)
stopifnot(fit$convergence==0L)
point <- calculate(fit,reference$wt)
saveRDS(fit,file.path(support,
  "regional_actionable_focused_method_interaction_model.rds"))
result <- do.call(rbind,lapply(seq_len(nrow(grid)),function(j)
  data.frame(region=grid$region[j],method=grid$method[j],month=times,
    adjusted_probability_pct=as.numeric(point[paste(
      grid$region[j],grid$method[j],times,sep="::")]))))
result$eligible_episodes_n <- mapply(function(r,m)
  sum(e$region_name==r&e$method_group==m),result$region,result$method)
result$actionable_endings_12m_n <- mapply(function(r,m)
  sum(e$region_name==r&e$method_group==m&e$discontinued&
    e$exposure<=12L&e$reason_code %in% actionable),
  result$region,result$method)
B <- as.integer(Sys.getenv("REGIONAL_METHOD_INTERACTION_REPS","500"))
if(B==0L) {print(result,row.names=FALSE);quit(save="no")}
stopifnot(is.finite(B),B>=300L)
frame <- full_survey_frame()
by_stratum <- split(frame$cluster,frame$stratum)
stopifnot(all(lengths(by_stratum)>1L))
replicate_once <- function(b) {
  set.seed(20261021L+b)
  mult <- setNames(numeric(nrow(frame)),frame$cluster)
  for(ids in by_stratum) {
    n <- length(ids)
    mult[as.character(ids)] <- n/(n-1L)*
      tabulate(sample.int(n,n-1L,replace=TRUE),nbins=n)
  }
  p <- person
  p$boot_weight <- p$wt*mult[as.character(p$cluster)]
  w <- reference$wt*mult[as.character(reference$cluster)]
  model <- tryCatch(nnet::multinom(formula,data=p,weights=boot_weight,
    maxit=400,trace=FALSE,MaxNWts=10000),error=function(err)NULL)
  if(is.null(model)||model$convergence!=0L)
    return(rep(NA_real_,length(point)))
  calculate(model,w)
}
draws <- parallel::mclapply(seq_len(B),replicate_once,
  mc.cores=min(4L,parallel::detectCores()),mc.preschedule=FALSE)
draws <- do.call(rbind,draws)
colnames(draws) <- names(point)
draws <- draws[complete.cases(draws),,drop=FALSE]
stopifnot(nrow(draws)>=.9*B)
write.csv(data.frame(replicate=seq_len(nrow(draws)),draws,check.names=FALSE),
  file.path(support,"regional_actionable_focused_method_interaction_bootstrap.csv"),
  row.names=FALSE)
for(j in seq_len(nrow(result))) {
  key <- paste(result$region[j],result$method[j],result$month[j],sep="::")
  ci <- quantile(draws[,key],c(.025,.975),names=FALSE)
  result$ci_low[j] <- ci[1]; result$ci_high[j] <- ci[2]
}
write.csv(result,file.path(support,
  "regional_actionable_focused_method_interaction_probabilities.csv"),
  row.names=FALSE)
pairs <- list(c("Tigray","Amhara"),c("Tigray","Addis Ababa"),
  c("Central Ethiopia","Amhara"))
tests <- list()
for(pair in pairs) for(m in c("Implants","Pill")) {
  a <- pair[1];b <- pair[2]
  keys <- paste(c(a,b,a,b),c("Injectables","Injectables",m,m),
    "12",sep="::")
  q <- point[keys]
  inj_gap <- unname(q[1]-q[2])
  other_gap <- unname(q[3]-q[4])
  replicate_difference <- (draws[,keys[1]]-draws[,keys[2]])-
    (draws[,keys[3]]-draws[,keys[4]])
  se <- sd(replicate_difference)
  ci <- quantile(replicate_difference,c(.025,.975),names=FALSE)
  tests[[length(tests)+1L]] <- data.frame(region_a=a,region_b=b,
    comparator_method=m,injectable_gap_pp=inj_gap,
    comparator_gap_pp=other_gap,gap_difference_pp=inj_gap-other_gap,
    ci_low_pp=ci[1],ci_high_pp=ci[2],
    bootstrap_se_pp=se,p_value=2*pnorm(-abs((inj_gap-other_gap)/se)))
}
tests <- do.call(rbind,tests)
tests$holm_p <- p.adjust(tests$p_value,"holm")
tests$significant_5pct <- tests$holm_p<.05
write.csv(tests,file.path(support,
  "regional_actionable_focused_method_interaction_tests.csv"),
  row.names=FALSE)
cat("Valid survey bootstrap refits:",nrow(draws),"of",B,"\n")
print(result,row.names=FALSE)
print(tests,row.names=FALSE)
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 142_plot_regional_method_interaction_actionable.R
# LANGUAGE: R
MODULES[["142_plot_regional_method_interaction_actionable.R"]] <- list(
 language="R",
 packaged_sha256="68a0334ac6d4d3f4d9dc8cd92048e35dc241d0d8fdeba5741b4e49d3a0bf0d61",
 args=character(),
 code=r"-----(#!/usr/bin/env Rscript
# Show fully adjusted, survey-bootstrap 12-month actionable discontinuation
# risks for the four prespecified regions and three main methods.
project <- Sys.getenv("ETHIOPIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
support <- file.path(project,"output","Supporting_data")
assets <- file.path(project,"output","assets")
stopifnot(requireNamespace("ggplot2",quietly=TRUE),
  requireNamespace("svglite",quietly=TRUE))
library(ggplot2)
d <- read.csv(file.path(support,
  "regional_actionable_focused_method_interaction_probabilities.csv"))
d <- d[d$month==12L,]
d$method <- factor(d$method,levels=c("Injectables","Implants","Pill"))
d$region <- factor(d$region,
  levels=rev(c("Tigray","Central Ethiopia","Amhara","Addis Ababa")))
d$sparse <- d$actionable_endings_12m_n<30L |
  d$eligible_episodes_n<100L
d$label <- sprintf("%.1f%%",d$adjusted_probability_pct)
cols <- c("Injectables"="#108C90","Implants"="#173E5B","Pill"="#D99A20")
g <- ggplot(d,aes(x=adjusted_probability_pct,y=region,color=method))+
  geom_segment(aes(x=ci_low,xend=ci_high,yend=region),linewidth=1.25)+
  geom_point(aes(shape=sparse),size=4.2,stroke=1.3,fill="white")+
  geom_text(aes(x=pmax(ci_high+1.5,adjusted_probability_pct+3),label=label),
    color="#173E5B",size=4.1,
    fontface="bold",hjust=0,show.legend=FALSE)+
  facet_grid(~method)+
  scale_color_manual(values=cols,guide="none")+
  scale_shape_manual(values=c("FALSE"=16,"TRUE"=1),
    name=NULL,labels=c("FALSE"="Adequate count",
      "TRUE"="Fewer than 30 endings or 100 episodes"))+
  scale_x_continuous(limits=c(0,80),breaks=c(0,20,40,60,80),
    expand=expansion(mult=0))+
  labs(title="Adjusted discontinuation by method and region",
    subtitle="Adjusted 12-month probability of ending for a potentially actionable reason",
    x="Probability (%)",y=NULL,
    caption=paste("Whiskers: pointwise 95% survey-bootstrap intervals. Hollow markers flag sparse region-method cells.",
      "Full competing-event model includes region × method, month, age and parity at start, marital status, education, wealth, residence, and start year.",
      "All predictions use the same observed-start profile from the four regions and three methods. EC is excluded.",
      sep="\n"))+
  theme_minimal(base_size=14)+
  theme(plot.background=element_rect(fill="white",color=NA),
    panel.background=element_rect(fill="white",color=NA),
    panel.grid.major.y=element_blank(),panel.grid.minor=element_blank(),
    panel.grid.major.x=element_line(color="#E2E9ED",linewidth=.5),
    strip.background=element_rect(fill="#F0F5F7",color=NA),
    strip.text=element_text(face="bold",color="#173E5B",size=15),
    axis.text.y=element_text(color="#173E5B",face="bold",size=12),
    axis.text.x=element_text(color="#536B79",size=11),
    axis.title.x=element_text(color="#173E5B",size=13,margin=margin(t=10)),
    plot.title=element_text(face="bold",color="#173E5B",size=21),
    plot.subtitle=element_text(color="#344F60",size=13),
    plot.caption=element_text(color="#536B79",size=9,hjust=0,
      margin=margin(t=13)),
    legend.position="top",legend.justification="left",
    panel.spacing.x=grid::unit(1.1,"lines"),
    plot.margin=margin(18,28,15,18))
ggsave(file.path(assets,"regional_actionable_method_interaction_12month.png"),
  g,width=15,height=6.4,dpi=200,bg="white")
ggsave(file.path(assets,"regional_actionable_method_interaction_12month.svg"),
  g,width=15,height=6.4,device=svglite::svglite,bg="white")
cat("Saved plot\n")
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 144_global_regional_method_interaction_test.R
# LANGUAGE: R
MODULES[["144_global_regional_method_interaction_test.R"]] <- list(
 language="R",
 packaged_sha256="92959541f76443752e241dd05f2c413ef0e46a09a7c07e50520dcc6c5b6902bd",
 args=character(),
 code=r"-----(#!/usr/bin/env Rscript
# Survey-bootstrap Wald test of six prespecified risk-scale contrasts:
# for each selected region pair, its injectable 12-month gap minus the
# corresponding implant or pill gap. This tests effect modification jointly.
project <- Sys.getenv("ETHIOPIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
support <- file.path(project,"output","Supporting_data")
point <- read.csv(file.path(support,
  "regional_actionable_focused_method_interaction_tests.csv"))
boot <- read.csv(file.path(support,
  "regional_actionable_focused_method_interaction_bootstrap.csv"),
  check.names=FALSE)
stopifnot(nrow(point)==6L,nrow(boot)>=450L)
draw <- sapply(seq_len(nrow(point)),function(i) {
  a <- point$region_a[i]; b <- point$region_b[i]
  m <- point$comparator_method[i]
  boot[[paste(a,"Injectables","12",sep="::")]]-
    boot[[paste(b,"Injectables","12",sep="::")]]-
    boot[[paste(a,m,"12",sep="::")]]+
    boot[[paste(b,m,"12",sep="::")]]
})
delta <- point$gap_difference_pp
v <- cov(draw)
statistic <- as.numeric(t(delta)%*%solve(v,delta))
result <- data.frame(contrast_count=length(delta),
  wald_chisq=statistic,degrees_of_freedom=length(delta),
  p_value=pchisq(statistic,df=length(delta),lower.tail=FALSE),
  valid_bootstrap_replicates=nrow(boot))
write.csv(result,file.path(support,
  "regional_actionable_focused_method_interaction_global_test.csv"),
  row.names=FALSE)
print(result,row.names=FALSE)
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 145_test_actionable_regional_rates_injectables_implants.R
# LANGUAGE: R
MODULES[["145_test_actionable_regional_rates_injectables_implants.R"]] <- list(
 language="R",
 packaged_sha256="0d752e9df1961c62e627ec5800f5732fa1ebc8307141eb68b10a9b04c9e730d7",
 args=character(),
 code=r"-----(
# Full DHS sampling frame, including PSUs with no eligible outcome records.
full_survey_frame <- function(){
 r<-Sys.getenv('ETHIOPIA_PROJECT_ROOT'); stopifnot(nzchar(r))
 x<-readRDS(file.path(r,'Data/ET2024DHS__ETIR8ADT__IR_raw.rds'))
 unique(data.frame(cluster=paste(as.integer(x$v022),as.integer(x$v021),sep=':'),stratum=as.integer(x$v022)))
}
complete_survey_data <- function(d){
 r<-Sys.getenv('ETHIOPIA_PROJECT_ROOT');x<-readRDS(file.path(r,'Data/ET2024DHS__ETIR8ADT__IR_raw.rds'))
 f<-unique(data.frame(v021=as.integer(x$v021),v022=as.integer(x$v022)))
 key<-function(a,b)paste(a,b,sep=':');miss<-f[!key(f$v021,f$v022)%in%key(d$v021,d$v022),]
 if(nrow(miss)){z<-d[rep(1L,nrow(miss)),,drop=FALSE];z$v021<-miss$v021;z$v022<-miss$v022;z$wt<-0;d<-rbind(d,z)}
 d
}
#!/usr/bin/env Rscript
# Design-based comparisons of observed 12-month discontinuation probabilities
# for potentially actionable reasons, separately for injectables and implants.
# The denominator is every eligible episode of the named original modern method.
# All other method endings remain competing events; right censoring and delayed
# entry follow the existing DHS-style life-table calculations. Resampling occurs
# within survey strata at PSU level and retains repeated episodes from women.
project <- Sys.getenv("ETHIOPIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
out <- file.path(project, "output")
support <- file.path(out, "Supporting_data")
e <- read.csv(file.path(support,
  "selected_reason_exploratory_episode_covariates.csv"))
stopifnot(nrow(e) == 8611L, !anyNA(e[, c("region", "method_group",
  "stratum", "cluster", "wt", "entry", "exposure", "reason_code")]))
regions <- c(`1`="Tigray", `2`="Afar", `3`="Amhara", `4`="Oromia",
  `5`="Somali", `6`="Benishangul-Gumuz", `7`="Central Ethiopia",
  `8`="Sidama", `9`="South West Ethiopia", `10`="South Ethiopia",
  `12`="Gambella", `13`="Harari", `14`="Addis Ababa", `15`="Dire Dawa")
methods <- c("Injectables", "Implants")
actionable <- c(1L, 4L, 5L, 6L, 7L, 8L, 10L, 15L)
frame <- full_survey_frame()
frame$id <- seq_len(nrow(frame))
key <- function(s, c) paste(s, c, sep="::")
e$id <- frame$id[match(key(e$stratum, e$cluster),
  key(frame$stratum, frame$cluster))]
stopifnot(!anyNA(e$id))
groups <- split(frame$id, frame$stratum)
stopifnot(all(lengths(groups)>1L))
K <- nrow(frame)

fill <- function(a, mask, t) {
  if (!any(mask)) return(a)
  z <- rowsum(e$wt[mask], e$id[mask], reorder=FALSE)
  a[as.integer(rownames(z)), t] <- z[, 1L]
  a
}
array_for <- function(scope) {
  risk <- ended <- selected <- matrix(0, K, 12L)
  for (t in 1:12) {
    at <- scope & e$entry < t & e$exposure >= t
    stop <- at & e$discontinued & e$exposure == t
    chosen <- stop & e$reason_code %in% actionable
    risk <- fill(risk, at, t)
    ended <- fill(ended, stop, t)
    selected <- fill(selected, chosen, t)
  }
  list(risk=risk, ended=ended, selected=selected)
}
cif <- function(a, mult) {
  R <- as.numeric(crossprod(mult, a$risk))
  A <- as.numeric(crossprod(mult, a$ended))
  D <- as.numeric(crossprod(mult, a$selected))
  if (any(R<=0) || any(A>R+1e-7)) return(NA_real_)
  survival <- 1; incidence <- 0
  for (t in 1:12) {
    incidence <- incidence+survival*D[t]/R[t]
    survival <- survival*(1-A[t]/R[t])
  }
  100*incidence
}
cell_names <- unlist(lapply(methods, function(method)
  paste(method, unname(regions), sep="::")))
arrays <- setNames(lapply(cell_names, function(nm) {
  p <- strsplit(nm, "::", fixed=TRUE)[[1]]
  code <- as.integer(names(regions)[match(p[2], regions)])
  array_for(e$method_group==p[1] & e$region==code)
}), cell_names)
point <- vapply(arrays, cif, numeric(1), mult=rep(1, K))
old <- read.csv(file.path(out, "regional_actionable_method_starts_and_rates.csv"))
for (nm in cell_names) {
  p <- strsplit(nm, "::", fixed=TRUE)[[1]]
  check <- old[old$method==p[1] & old$region==p[2],]
  stopifnot(nrow(check)==1L,
    abs(point[nm]-check$actionable_12_month_probability_pct)<1e-8)
}
counts <- do.call(rbind,lapply(cell_names,function(nm) {
  p <- strsplit(nm,"::",fixed=TRUE)[[1]]
  code <- as.integer(names(regions)[match(p[2],regions)])
  z <- e[e$method_group==p[1] & e$region==code,]
  selected <- z$discontinued & z$entry<z$exposure &
    z$exposure<=12L & z$reason_code %in% actionable
  data.frame(method=p[1],region=p[2],eligible_episodes_n=nrow(z),
    actionable_endings_n=sum(selected),
    distinct_psus=length(unique(z$id)),
    estimate_pct=unname(point[nm]))
}))
counts$tested <- counts$eligible_episodes_n>=100L &
  counts$actionable_endings_n>=10L
counts$flag <- ifelse(counts$tested & counts$actionable_endings_n<30L,
  "Exploratory: 10–29 endings",ifelse(counts$tested,"Tested",
  "Descriptive only: <100 episodes or <10 endings"))
cat("Tested regions by method:\n")
print(table(counts$method,counts$tested))
B <- as.integer(Sys.getenv("REGIONAL_METHOD_RISK_REPS", "5000"))
stopifnot(B>=1000L)
boot <- matrix(NA_real_, B, length(cell_names),dimnames=list(NULL,cell_names))
for (b in seq_len(B)) {
  set.seed(20261022L+b)
  mult <- numeric(K)
  for (ids in groups) {
    n <- length(ids)
    mult[ids] <- n/(n-1L)*
      tabulate(sample.int(n,n-1L,replace=TRUE),nbins=n)
  }
  boot[b,] <- vapply(arrays,cif,numeric(1),mult=mult)
}
for (j in seq_len(nrow(counts))) {
  nm <- paste(counts$method[j],counts$region[j],sep="::")
  x <- boot[,nm]; x <- x[is.finite(x)]
  counts$valid_bootstrap_draws[j] <- length(x)
  if (length(x)>=.9*B) {
    ci <- quantile(x,c(.025,.975),names=FALSE)
    counts$ci_low[j] <- ci[1];counts$ci_high[j] <- ci[2]
  } else {
    counts$ci_low[j] <- counts$ci_high[j] <- NA_real_
  }
}
stopifnot(all(counts$valid_bootstrap_draws[counts$tested]>=.95*B))
write.csv(counts,file.path(support,
  "regional_actionable_injectable_implant_rates.csv"),row.names=FALSE)
write.csv(data.frame(replicate=seq_len(B),boot,check.names=FALSE),
  file.path(support,
    "regional_actionable_injectable_implant_bootstrap.csv"),row.names=FALSE)

global <- list(); pairs <- list()
for (method in methods) {
  eligible <- counts$region[counts$method==method & counts$tested]
  cols <- paste(method,eligible,sep="::")
  draws <- boot[,cols,drop=FALSE]
  draws <- draws[complete.cases(draws),,drop=FALSE]
  stopifnot(nrow(draws)>=.95*B)
  # A single region is the reference only to construct a full-rank vector
  # of rate contrasts. The omnibus null is equality across all tested regions.
  ref <- paste(method,"Amhara",sep="::")
  stopifnot(ref %in% cols)
  other <- setdiff(cols,ref)
  contrasts <- sweep(draws[,other,drop=FALSE],1,draws[,ref],"-")
  delta <- point[other]-point[ref]
  V <- cov(contrasts)
  stat <- as.numeric(crossprod(delta,solve(V,delta)))
  global[[method]] <- data.frame(method=method,
    tested_regions=length(eligible),
    contrast_df=length(other),wald_chisq=stat,
    p_value=pchisq(stat,df=length(other),lower.tail=FALSE),
    valid_bootstrap_draws=nrow(draws),
    criterion="At least 100 eligible episodes and 10 first-year actionable endings")
  combinations <- combn(eligible,2,simplify=FALSE)
  method_pairs <- do.call(rbind,lapply(combinations,function(pair) {
    a <- paste(method,pair[1],sep="::")
    b <- paste(method,pair[2],sep="::")
    difference <- unname(point[a]-point[b])
    d <- draws[,a]-draws[,b]
    se <- sd(d)
    ci <- quantile(d,c(.025,.975),names=FALSE)
    data.frame(method=method,region_a=pair[1],region_b=pair[2],
      rate_a_pct=unname(point[a]),rate_b_pct=unname(point[b]),
      difference_pp=difference,ci_low_pp=ci[1],ci_high_pp=ci[2],
      bootstrap_se_pp=se,p_value=2*pnorm(-abs(difference/se)),
      valid_bootstrap_draws=nrow(draws))
  }))
  method_pairs$holm_p <- p.adjust(method_pairs$p_value,"holm")
  method_pairs$significant_5pct <- method_pairs$holm_p<.05
  pairs[[method]] <- method_pairs[order(method_pairs$holm_p),]
}
global <- do.call(rbind,global);pairs <- do.call(rbind,pairs)
global$holm_p_across_methods <- p.adjust(global$p_value,"holm")
# The two methods were named in the question, so control the family across
# every tested region pair from both methods (66 injectable + 55 implant).
pairs$holm_p <- p.adjust(pairs$p_value,"holm")
pairs$significant_5pct <- pairs$holm_p<.05
pairs <- pairs[order(pairs$method,pairs$holm_p),]
write.csv(global,file.path(support,
  "regional_actionable_injectable_implant_global_tests.csv"),row.names=FALSE)
write.csv(pairs,file.path(support,
  "regional_actionable_injectable_implant_pairwise_tests.csv"),row.names=FALSE)
cat("Global tests:\n");print(global,row.names=FALSE)
cat("Holm-significant pairs:\n")
print(pairs[pairs$significant_5pct,],row.names=FALSE)
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 146_plot_actionable_regional_injectables_implants.R
# LANGUAGE: R
MODULES[["146_plot_actionable_regional_injectables_implants.R"]] <- list(
 language="R",
 packaged_sha256="0ea20f2919825e56487b36ec1d04c18171937c07dbca7bb7a1e09ae3d1a0131e",
 args=character(),
 code=r"-----(#!/usr/bin/env Rscript
# Presentation-readable comparison of observed method-specific regional risks.
project <- Sys.getenv("ETHIOPIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
support <- file.path(project,"output","Supporting_data")
assets <- file.path(project,"output","assets")
stopifnot(requireNamespace("ggplot2",quietly=TRUE),
  requireNamespace("svglite",quietly=TRUE))
library(ggplot2)
d <- read.csv(file.path(support,
  "regional_actionable_injectable_implant_rates.csv"))
tests <- read.csv(file.path(support,
  "regional_actionable_injectable_implant_global_tests.csv"))
national <- read.csv(file.path(project,"output",
  "regional_actionable_method_starts_and_rates.csv"))
order <- d$region[d$method=="Injectables" & d$tested]
order <- order[order(d$estimate_pct[d$method=="Injectables" & d$tested],
  decreasing=TRUE)]
order <- c(order,"Dire Dawa","Somali")
stopifnot(length(unique(order))==14L)
d$position <- length(order)+1L-match(d$region,order)
d$limited <- d$actionable_endings_n<30L
d$method <- factor(d$method,levels=c("Injectables","Implants"))
facet_names <- c("Injectables"=sprintf("Injectables  |  global p = %.3f",
  tests$holm_p_across_methods[tests$method=="Injectables"]),
  "Implants"=sprintf("Implants  |  global p = %.3f",
  tests$holm_p_across_methods[tests$method=="Implants"]))
ref <- national[national$region=="National" &
  national$method %in% c("Injectables","Implants"),
  c("method","actionable_12_month_probability_pct")]
ref$method <- factor(ref$method,levels=levels(d$method))
cols <- c("Injectables"="#108C90","Implants"="#173E5B")
g <- ggplot(d,aes(x=estimate_pct,y=position,color=method))+
  geom_vline(data=ref,aes(xintercept=actionable_12_month_probability_pct),
    color="#9CAAB2",linetype="dashed",linewidth=.7,inherit.aes=FALSE)+
  geom_segment(data=subset(d,tested),
    aes(x=ci_low,xend=ci_high,yend=position),linewidth=1.1)+
  geom_point(data=subset(d,tested),aes(shape=limited),
    size=3.1,stroke=1.2,fill="white")+
  geom_text(data=subset(d,tested),
    aes(x=pmax(ci_high+1,estimate_pct+2),label=sprintf("%.1f",estimate_pct)),
    color="#173E5B",size=3.45,hjust=0,show.legend=FALSE)+
  geom_text(data=subset(d,!tested),aes(x=2,label="Sparse"),
    color="#7A8991",size=3.3,hjust=0,show.legend=FALSE)+
  facet_grid(~method,labeller=as_labeller(facet_names))+
  scale_color_manual(values=cols,guide="none")+
  scale_shape_manual(values=c("FALSE"=16,"TRUE"=1),name=NULL,
    labels=c("FALSE"="30+ observed endings",
      "TRUE"="10–29 observed endings"))+
  scale_x_continuous(limits=c(0,48),breaks=c(0,10,20,30,40),
    expand=expansion(mult=0))+
  scale_y_continuous(breaks=seq_along(order),labels=rev(order),
    limits=c(.5,length(order)+.5),expand=expansion(mult=0))+
  labs(title="Actionable discontinuation differs across regions for injectables",
    subtitle="Observed 12-month probability among eligible episodes of each original method",
    x="12-month probability (%)",y=NULL,
    caption=paste("Horizontal lines: pointwise 95% survey-stratified PSU bootstrap intervals; dashed line: national method-specific probability.",
      "Sparse cells (<100 episodes or <10 actionable first-year endings) are omitted from formal tests.",
      "Global p-values use a 5,000-replicate survey bootstrap Wald test and Holm correction across the two methods.",sep="\n"))+
  theme_minimal(base_size=13)+
  theme(plot.background=element_rect(fill="white",color=NA),
    panel.background=element_rect(fill="white",color=NA),
    panel.grid.major.y=element_blank(),panel.grid.minor=element_blank(),
    panel.grid.major.x=element_line(color="#E2E9ED",linewidth=.5),
    strip.background=element_rect(fill="#EFF4F6",color=NA),
    strip.text=element_text(face="bold",color="#173E5B",size=14),
    axis.text.y=element_text(color="#173E5B",size=11),
    axis.text.x=element_text(color="#536B79",size=10),
    axis.title.x=element_text(color="#173E5B",size=12),
    plot.title=element_text(face="bold",color="#173E5B",size=20),
    plot.subtitle=element_text(color="#344F60",size=12),
    plot.caption=element_text(color="#536B79",size=9,hjust=0,
      margin=margin(t=12)),
    legend.position="top",legend.justification="left",
    panel.spacing.x=grid::unit(1.2,"lines"),
    plot.margin=margin(15,20,10,15))
ggsave(file.path(assets,
  "regional_actionable_injectable_implant_12month_tests.png"),
  g,width=15,height=8.8,dpi=200,bg="white")
ggsave(file.path(assets,
  "regional_actionable_injectable_implant_12month_tests.svg"),
  g,width=15,height=8.8,device=svglite::svglite,bg="white")
cat("Saved regional method-specific test figure\n")
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 148_injectable_actionable_fully_adjusted_regional_tests.R
# LANGUAGE: R
MODULES[["148_injectable_actionable_fully_adjusted_regional_tests.R"]] <- list(
 language="R",
 packaged_sha256="94726f09de4536f982e797318dc574cf045e78e3ae6e676a2df710bb018161ef",
 args=character(),
 code=r"-----(
# Full DHS sampling frame, including PSUs with no eligible outcome records.
full_survey_frame <- function(){
 r<-Sys.getenv('ETHIOPIA_PROJECT_ROOT'); stopifnot(nzchar(r))
 x<-readRDS(file.path(r,'Data/ET2024DHS__ETIR8ADT__IR_raw.rds'))
 unique(data.frame(cluster=paste(as.integer(x$v022),as.integer(x$v021),sep=':'),stratum=as.integer(x$v022)))
}
complete_survey_data <- function(d){
 r<-Sys.getenv('ETHIOPIA_PROJECT_ROOT');x<-readRDS(file.path(r,'Data/ET2024DHS__ETIR8ADT__IR_raw.rds'))
 f<-unique(data.frame(v021=as.integer(x$v021),v022=as.integer(x$v022)))
 key<-function(a,b)paste(a,b,sep=':');miss<-f[!key(f$v021,f$v022)%in%key(d$v021,d$v022),]
 if(nrow(miss)){z<-d[rep(1L,nrow(miss)),,drop=FALSE];z$v021<-miss$v021;z$v022<-miss$v022;z$wt<-0;d<-rbind(d,z)}
 d
}
#!/usr/bin/env Rscript
# Fully adjusted region-specific 12-month actionable-discontinuation risks for
# injectable episodes, with survey-stratified PSU bootstrap tests. This is the
# third stage of the previous comparison sequence. Stage 2 (common method mix)
# is algebraically identical to Stage 1 within a single injectable method.
project <- Sys.getenv("ETHIOPIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
support <- file.path(project,"output","Supporting_data")
stopifnot(requireNamespace("nnet",quietly=TRUE))
all_e <- read.csv(file.path(support,
  "selected_reason_exploratory_episode_covariates.csv"))
ir <- readRDS(file.path(project,"Data/ET2024DHS__ETIR8ADT__IR_raw.rds"))
counts <- read.csv(file.path(support,
  "regional_actionable_injectable_implant_rates.csv"))
included <- counts$region[counts$method=="Injectables" & counts$tested]
region_labels <- c(`1`="Tigray",`2`="Afar",`3`="Amhara",`4`="Oromia",
  `5`="Somali",`6`="Benishangul-Gumuz",`7`="Central Ethiopia",
  `8`="Sidama",`9`="South West Ethiopia",`10`="South Ethiopia",
  `12`="Gambella",`13`="Harari",`14`="Addis Ababa",`15`="Dire Dawa")
region_codes <- as.integer(names(region_labels)[region_labels %in% included])
stopifnot(length(region_codes)==12L, nrow(all_e)==8611L)
e <- all_e[all_e$method_group=="Injectables" &
  all_e$region %in% region_codes,]
stopifnot(nrow(e)==4706L)
e$region <- factor(e$region,levels=region_codes)
e$age_group <- factor(e$age_group,
  levels=c("15-19","20-24","25-34","35-49"))
e$education <- factor(e$education,
  levels=c("None","Primary","Secondary+"))
e$residence <- factor(e$residence,levels=c("Rural","Urban"))
i <- e$woman_row
births <- as.matrix(ir[i,grep("^b3_",names(ir),value=TRUE)])
parity <- rowSums(!is.na(births) & births<=e$start)
marital <- as.integer(ir$v501[i]);wealth <- as.integer(ir$v190[i])
stopifnot(!anyNA(parity),all(marital %in% 0:5),all(wealth %in% 1:5))
e$parity_group <- factor(ifelse(parity==0,"0",
  ifelse(parity<=2,"1-2",ifelse(parity<=4,"3-4","5+"))),
  levels=c("0","1-2","3-4","5+"))
e$marital_group <- factor(ifelse(marital==0L,"Never in union",
  ifelse(marital==2L,"Living together",
  ifelse(marital==1L,"Married","Divorced/widowed/separated"))),
  levels=c("Never in union","Living together","Married",
    "Divorced/widowed/separated"))
e$wealth_group <- factor(c("Poorest","Poorer","Middle","Richer","Richest")[wealth],
  levels=c("Poorest","Poorer","Middle","Richer","Richest"))
e$start_year <- factor((e$start-1L)%/%12L+1900L)
exposure <- pmax(0L,pmin(12L,e$exposure)-e$entry)
index <- rep(seq_len(nrow(e)),exposure)
month <- unlist(Map(function(first,n)seq.int(first+1L,length.out=n),
  e$entry,exposure),use.names=FALSE)
person <- e[index,c("wt","region","age_group","parity_group",
  "marital_group","education","wealth_group","residence","start_year",
  "cluster","stratum")]
person$month <- factor(month,levels=1:12)
ended <- e$discontinued[index] & month==e$exposure[index]
actionable <- c(1L,4L,5L,6L,7L,8L,10L,15L)
person$outcome <- factor(ifelse(!ended,"continue",
  ifelse(e$reason_code[index] %in% actionable,"actionable","competing")),
  levels=c("continue","actionable","competing"))
reference <- e[e$entry==0L,]
stopifnot(nrow(reference)==4156L)
formula <- outcome ~ month + region + age_group + parity_group +
  marital_group + education + wealth_group + residence + start_year
fit <- nnet::multinom(formula,data=person,weights=person$wt,
  maxit=400,trace=FALSE,MaxNWts=10000)
stopifnot(fit$convergence==0L)
saveRDS(fit,file.path(support,
  "regional_actionable_injectable_full_model.rds"))

# The fitted model has a region main effect. Cache reference-profile design
# matrices for months 1–12 once; regional differences are coefficient offsets.
base <- reference
base$region <- factor(region_codes[1],levels=region_codes)
rhs <- delete.response(terms(formula))
baseX <- lapply(1:12,function(t) {
  base$month <- factor(t,levels=1:12)
  model.matrix(rhs,base)
})
row0 <- base[1,,drop=FALSE]
row0$month <- factor(1,levels=1:12)
x0 <- model.matrix(rhs,row0)[1,]
offsets <- lapply(region_codes,function(code) {
  row0$region <- factor(code,levels=region_codes)
  model.matrix(rhs,row0)[1,]-x0
})
names(offsets) <- as.character(region_codes)
predict_risks <- function(model,weights) {
  beta <- coef(model)
  if (!is.matrix(beta) ||
      !identical(rownames(beta),c("actionable","competing")) ||
      !identical(colnames(beta),colnames(baseX[[1]])))
    return(rep(NA_real_,length(region_codes)))
  A <- sapply(baseX,function(x)as.vector(x%*%beta["actionable",]))
  C <- sapply(baseX,function(x)as.vector(x%*%beta["competing",]))
  vapply(region_codes,function(code) {
    off <- offsets[[as.character(code)]]
    a0 <- sum(off*beta["actionable",])
    c0 <- sum(off*beta["competing",])
    survival <- rep(1,nrow(reference))
    incidence <- rep(0,nrow(reference))
    for (t in 1:12) {
      a <- exp(A[,t]+a0); c <- exp(C[,t]+c0)
      denom <- 1+a+c
      incidence <- incidence+survival*a/denom
      survival <- survival/denom
    }
    100*weighted.mean(incidence,weights)
  },numeric(1))
}
point <- predict_risks(fit,reference$wt)
names(point) <- unname(region_labels[as.character(region_codes)])
stopifnot(all(is.finite(point)),all(point>0),all(point<100))
cat("Point estimates:\n");print(point)
B <- as.integer(Sys.getenv("INJECTABLE_FULL_REGIONAL_REPS","500"))
if (B==0L) quit(save="no")
stopifnot(B>=300L)
frame <- full_survey_frame()
frame$id <- seq_len(nrow(frame))
key <- function(s,c)paste(s,c,sep="::")
person$id <- frame$id[match(key(person$stratum,person$cluster),
  key(frame$stratum,frame$cluster))]
reference$id <- frame$id[match(key(reference$stratum,reference$cluster),
  key(frame$stratum,frame$cluster))]
stopifnot(!anyNA(person$id),!anyNA(reference$id))
groups <- split(frame$id,frame$stratum)
stopifnot(all(lengths(groups)>1L))
one <- function(b) {
  set.seed(20261023L+b)
  mult <- numeric(nrow(frame))
  for (ids in groups) {
    n <- length(ids)
    mult[ids] <- n/(n-1L)*
      tabulate(sample.int(n,n-1L,replace=TRUE),nbins=n)
  }
  p <- person
  p$boot_weight <- p$wt*mult[p$id]
  w <- reference$wt*mult[reference$id]
  model <- tryCatch(nnet::multinom(formula,data=p,weights=boot_weight,summ=2,
    maxit=400,trace=FALSE,MaxNWts=10000),error=function(err)NULL)
  if (is.null(model) || model$convergence!=0L)
    return(rep(NA_real_,length(point)))
  predict_risks(model,w)
}
prior <- NULL
prior_path <- file.path(support,
  "regional_actionable_injectable_full_bootstrap.csv")
if (Sys.getenv("INJECTABLE_FULL_REGIONAL_RESUME", "0")=="1" &&
    file.exists(prior_path)) {
  saved <- read.csv(prior_path,check.names=FALSE)
  stopifnot(all(names(point) %in% names(saved)),nrow(saved)<B)
  prior <- as.matrix(saved[,names(point),drop=FALSE])
}
first <- if(is.null(prior)) 1L else nrow(prior)+1L
new_draws <- parallel::mclapply(seq.int(first,B),one,
  mc.cores=min(4L,parallel::detectCores()),mc.preschedule=FALSE)
new_draws <- do.call(rbind,new_draws)
draws <- if(is.null(prior)) new_draws else rbind(prior,new_draws)
colnames(draws) <- names(point)
draws <- draws[complete.cases(draws),,drop=FALSE]
stopifnot(nrow(draws)>=.9*B)
write.csv(data.frame(replicate=seq_len(nrow(draws)),draws,check.names=FALSE),
  file.path(support,"regional_actionable_injectable_full_bootstrap.csv"),
  row.names=FALSE)
results <- data.frame(region=names(point),
  adjusted_probability_pct=as.numeric(point),
  ci_low=apply(draws,2,quantile,.025),
  ci_high=apply(draws,2,quantile,.975),
  eligible_episodes_n=vapply(names(point),function(nm)
    sum(unname(region_labels[as.character(e$region)])==nm),integer(1)),
  actionable_endings_n=vapply(names(point),function(nm) {
    z <- e[unname(region_labels[as.character(e$region)])==nm,]
    sum(z$discontinued & z$entry<z$exposure & z$exposure<=12L &
      z$reason_code %in% actionable)
  },integer(1)))
write.csv(results,file.path(support,
  "regional_actionable_injectable_full_probabilities.csv"),row.names=FALSE)
ref <- "Amhara"
other <- setdiff(names(point),ref)
contrast_draws <- sweep(draws[,other,drop=FALSE],1,draws[,ref],"-")
delta <- point[other]-point[ref]
V <- cov(contrast_draws)
stat <- as.numeric(crossprod(delta,solve(V,delta)))
global <- data.frame(method="Injectables",
  model="Fully adjusted injectable-only",
  regions_tested=length(point),wald_chisq=stat,df=length(other),
  p_value=pchisq(stat,df=length(other),lower.tail=FALSE),
  valid_bootstrap_draws=nrow(draws))
write.csv(global,file.path(support,
  "regional_actionable_injectable_full_global_test.csv"),row.names=FALSE)
pairs <- do.call(rbind,lapply(combn(names(point),2,simplify=FALSE),
  function(pair) {
    a <- pair[1];b <- pair[2]
    d <- draws[,a]-draws[,b]
    difference <- point[a]-point[b]
    ci <- quantile(d,c(.025,.975),names=FALSE)
    data.frame(region_a=a,region_b=b,
      rate_a_pct=unname(point[a]),rate_b_pct=unname(point[b]),
      difference_pp=unname(difference),ci_low_pp=ci[1],ci_high_pp=ci[2],
      bootstrap_se_pp=sd(d),
      p_value=2*pnorm(-abs(difference/sd(d))))
  }))
pairs$holm_p <- p.adjust(pairs$p_value,"holm")
pairs$significant_5pct <- pairs$holm_p<.05
pairs <- pairs[order(pairs$holm_p),]
write.csv(pairs,file.path(support,
  "regional_actionable_injectable_full_pairwise_tests.csv"),row.names=FALSE)
cat("Valid bootstrap refits:",nrow(draws),"of",B,"\n")
print(global,row.names=FALSE)
cat("Holm-significant adjusted pairs:\n")
print(pairs[pairs$significant_5pct,],row.names=FALSE)
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 149_plot_injectable_three_stage_regional_tests.R
# LANGUAGE: R
MODULES[["149_plot_injectable_three_stage_regional_tests.R"]] <- list(
 language="R",
 packaged_sha256="293ffa05430272fda8e5c0a6bd47acf91380b523d28970560286cc0984a0040b",
 args=character(),
 code=r"-----(#!/usr/bin/env Rscript
# Observed and fully adjusted injectable risks; the middle method-mix stage
# equals observed within a single original method and is explained in HTML.
project <- Sys.getenv("ETHIOPIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
support <- file.path(project,"output","Supporting_data")
assets <- file.path(project,"output","assets")
stopifnot(requireNamespace("ggplot2",quietly=TRUE),
  requireNamespace("svglite",quietly=TRUE))
library(ggplot2)
raw <- read.csv(file.path(support,
  "regional_actionable_injectable_implant_rates.csv"))
raw <- raw[raw$method=="Injectables" & raw$tested,]
adjusted <- read.csv(file.path(support,
  "regional_actionable_injectable_full_probabilities.csv"))
stopifnot(nrow(raw)==12L,nrow(adjusted)==12L,
  setequal(raw$region,adjusted$region))
one <- data.frame(region=raw$region,stage="Observed",
  estimate=raw$estimate_pct,lower=raw$ci_low,upper=raw$ci_high)
two <- data.frame(region=adjusted$region,stage="Fully adjusted",
  estimate=adjusted$adjusted_probability_pct,
  lower=adjusted$ci_low,upper=adjusted$ci_high)
d <- rbind(one,two)
national <- read.csv(file.path(project,"output",
  "regional_actionable_method_starts_and_rates.csv"))
national <- national$actionable_12_month_probability_pct[
  national$region=="National" & national$method=="Injectables"]
stopifnot(length(national)==1L,is.finite(national))
raw_pairs <- read.csv(file.path(support,
  "regional_actionable_injectable_implant_pairwise_tests.csv"))
raw_pairs <- raw_pairs[raw_pairs$method=="Injectables",]
adjusted_pairs <- read.csv(file.path(support,
  "regional_actionable_injectable_full_pairwise_tests.csv"))
stopifnot(nrow(raw_pairs)==66L,nrow(adjusted_pairs)==66L)
raw_sig <- raw_pairs[p.adjust(raw_pairs$p_value,method="holm")<.05,]
adjusted_sig <- adjusted_pairs[adjusted_pairs$holm_p<.05,]
stopifnot(nrow(raw_sig)>0L,nrow(adjusted_sig)>0L)
raw_regions <- unique(c(raw_sig$region_a,raw_sig$region_b))
adjusted_regions <- unique(c(adjusted_sig$region_a,adjusted_sig$region_b))
d$significant <- ifelse(d$stage=="Observed",
  d$region %in% raw_regions,d$region %in% adjusted_regions)
order <- raw$region[order(raw$estimate_pct,decreasing=TRUE)]
d$position <- length(order)+1L-match(d$region,order)
d$position <- d$position+ifelse(d$stage=="Observed",.14,-.14)
d$stage <- factor(d$stage,levels=c("Observed","Fully adjusted"))
cols <- c("Observed"="#DA9A25","Fully adjusted"="#173E5B")
g <- ggplot(d,aes(x=estimate,y=position,color=stage))+
  geom_vline(xintercept=national,linetype="dotted",
    color="#607987",linewidth=.85)+
  geom_segment(aes(x=lower,xend=upper,yend=position),linewidth=1.1)+
  geom_point(size=3.1)+
  geom_text(data=d[d$significant,],aes(x=upper+1.0,label="*"),
    fontface="bold",size=5.4,show.legend=FALSE)+
  annotate("text",x=national+.5,y=length(order)+.51,
    label=sprintf("National %.1f%%",national),hjust=0,vjust=1,
    color="#465F6D",size=3.7)+
  scale_color_manual(values=cols,name=NULL)+
  scale_y_continuous(breaks=seq_along(order),labels=rev(order),
    limits=c(.4,length(order)+.6),expand=expansion(mult=0))+
  scale_x_continuous(limits=c(0,42),breaks=c(0,10,20,30,40),
    expand=expansion(mult=0))+
  labs(title="Where does injectable discontinuation differ by region?",
    subtitle="12-month probability of ending injectable use for a potentially actionable reason",
    x="12-month probability (%)",y=NULL,
    caption=paste("Dotted line: national observed injectable rate (18.8%). Whiskers: pointwise 95% survey-bootstrap intervals.",
      paste0('* Significant after Holm correction across 66 pairs: observed, ',paste(paste(raw_sig$region_a,raw_sig$region_b,sep='–'),collapse='; '),'; adjusted, ',paste(paste(adjusted_sig$region_a,adjusted_sig$region_b,sep='–'),collapse='; '),'.'),
      "Stars mark members of those pairs, not differences from the national line. The method-mix stage equals observed for injectables.",sep="\n"))+
  theme_minimal(base_size=14)+
  theme(plot.background=element_rect(fill="white",color=NA),
    panel.background=element_rect(fill="white",color=NA),
    panel.grid.major.y=element_blank(),panel.grid.minor=element_blank(),
    panel.grid.major.x=element_line(color="#E2E9ED",linewidth=.5),
    axis.text.y=element_text(color="#173E5B",size=12),
    axis.text.x=element_text(color="#536B79",size=11),
    axis.title.x=element_text(color="#173E5B",size=13),
    plot.title=element_text(face="bold",color="#173E5B",size=21),
    plot.subtitle=element_text(color="#344F60",size=13),
    plot.caption=element_text(color="#536B79",size=10.2,hjust=0,
      margin=margin(t=12)),
    legend.position="top",legend.justification="left",
    legend.text=element_text(size=12),
    plot.margin=margin(18,24,12,18))
ggsave(file.path(assets,
  "regional_actionable_injectable_three_stage_tests.png"),
  g,width=12.8,height=8.4,dpi=200,bg="white")
ggsave(file.path(assets,
  "regional_actionable_injectable_three_stage_tests.svg"),
  g,width=12.8,height=8.4,device=svglite::svglite,bg="white")
ggsave(file.path(assets,
  "regional_actionable_injectable_three_stage_tests_slide.png"),
  g,width=13.333,height=7.5,dpi=200,bg="white")
cat("Saved injectable stage comparison figure\n")
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 163_ethiopia_current_user_switch_duration.R
# LANGUAGE: R
MODULES[["163_ethiopia_current_user_switch_duration.R"]] <- list(
 language="R",
 packaged_sha256="9b37c87c625660e0dc6d3f09ee57d188c5325667df5fb06da8cc38d47711eb4f",
 args=character(),
 code=r"-----(#!/usr/bin/env Rscript
# Ethiopia DHS 2024–25: transparent bridges from original-method endings to
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

root <- Sys.getenv("ETHIOPIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
out <- file.path(root,'output/Supporting_data')
data_dir <- file.path(root,'Data/Derived')
ir <- readRDS(file.path(root,'Data/ET2024DHS__ETIR8ADT__IR_raw.rds'))
episodes <- readRDS(file.path(data_dir,'ethiopia_2024_specified_modern_method_episodes.rds'))
calendar <- readRDS(file.path(data_dir,'ethiopia_2024_calendar_events.rds'))
raw_users <- read.csv(file.path(out,'current_users_actionable_12_month_projection.csv'))
raw_users$method[raw_users$method=='Other modern methods'] <- 'Other modern'
users <- data.frame(method=raw_users$method,current_users_2025=raw_users$current_users,
  actionable_first_year_risk_pct=raw_users$actionable_12_month_probability_pct,
  illustrative_original_method_endings=raw_users$illustrative_actionable_method_endings)
users <- users[users$method %in% c('Injectables','Implants','Pill','IUD','Other modern','EC'),]
raw_cause <- read.csv(file.path(out,'current_users_actionable_by_cause.csv'))
raw_cause$method[raw_cause$method=='Other modern methods'] <- 'Other modern'
base <- data.frame(method=raw_cause$method,reason=raw_cause$actionable_cause,
  illustrative_users=raw_cause$illustrative_method_endings)
base <- base[base$method %in% c('Injectables','Implants','Pill','IUD','Other modern'),]
wra_2025 <- read.csv(file.path(root,'Data/ethiopia_2025_wra_planning_input.csv'))$women_15_49[1]
mcpr_2025 <- 100*sum(users$current_users_2025)/wra_2025
wra_2026 <- 35016171
scenario <- data.frame(scenario=c('Status quo','UN annual change','Track20/FP2030 recent change'),
  mcpr_2026_pct=mcpr_2025+c(0,0.8,0.7),wra_2026=rep(wra_2026,3))
scenario$usual_users_2026 <- scenario$mcpr_2026_pct*scenario$wra_2026/100
stopifnot(nrow(ir)==21395L,all(c('method','current_users_2025','illustrative_original_method_endings') %in% names(users)))

modern <- c(1L,2L,3L,5L,6L,7L,11L,13L,17L,18L)
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
write.csv(bridge,file.path(out,'ethiopia_switch_bridge_by_method.csv'),row.names=FALSE)

cause_bridge <- do.call(rbind,lapply(methods,function(m)do.call(rbind,lapply(causes,function(cause){
  d <- endings[endings$method==m & endings$cause==cause,]
  projected <- base$illustrative_users[base$method==m & base$reason==cause]
  stopifnot(length(projected)==1L)
  frac <- if(nrow(d)>0)sum(d$wt[d$direct_modern])/sum(d$wt) else 0
  data.frame(method=m,reason=cause,observed_endings_n=nrow(d),
    illustrative_original_method_endings=projected,direct_modern_switch_pct=100*frac,
    illustrative_direct_modern_switchers=projected*frac,
    illustrative_not_directly_switching=projected*(1-frac))
}))))
# Reconcile cause-specific allocations to each method's independently
# estimated switching total while retaining the observed relative pattern.
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
write.csv(cause_bridge,file.path(out,'ethiopia_switch_bridge_by_method_cause.csv'),row.names=FALSE)

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
    direct_switch=direct,modern_at_month12=modern12,
    actionable_nonmodern_at_month12=action & !modern12,
    actionable_modern_at_month12=action & modern12,
    cause=ifelse(action,cause_group(a$reason_code),NA_character_))
}
landmarks <- do.call(rbind,records[!vapply(records,is.null,logical(1))])
landmarks$duration_bin <- cut(landmarks$duration_completed,bins,labels=bin_labels)
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
write.csv(duration_bins,file.path(out,'ethiopia_duration_landmark_support_and_risks.csv'),row.names=FALSE)

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
write.csv(duration,file.path(out,'ethiopia_duration_aware_current_user_bridge.csv'),row.names=FALSE)

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
write.csv(cause_duration,file.path(out,'ethiopia_duration_aware_current_user_by_cause.csv'),row.names=FALSE)

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
write.csv(scenario_bridge,file.path(out,'ethiopia_switch_duration_mcpr_scenarios.csv'),row.names=FALSE)
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
write.csv(long_sensitivity,file.path(out,'ethiopia_duration_61plus_sensitivity.csv'),row.names=FALSE)
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
# ORIGINAL MODULE: 165_duration_aware_cause_pp_tables.R
# LANGUAGE: R
MODULES[["165_duration_aware_cause_pp_tables.R"]] <- list(
 language="R",
 packaged_sha256="b7823767b2fb15ff204c155c43f1434dc90517ff53eb351781969c5b5c31faa7",
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
country <- "Ethiopia"
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
# ORIGINAL MODULE: 166_model_based_duration_method_preview.R
# LANGUAGE: R
MODULES[["166_model_based_duration_method_preview.R"]] <- list(
 language="R",
 packaged_sha256="02e24afb29ecf36e564c063b4fb405e0db9ff524ec1176f36613849dda648536",
 args=character(),
 code=r"-----(#!/usr/bin/env Rscript
# Preview only. Estimate next-12-month potentially actionable original-method
# ending risks for current Ethiopia modern-method users, conditional on the
# elapsed duration already accrued. This does not replace existing tables.
#
# Two survey-weighted parametric AFT models estimate cause-specific hazards:
# actionable ending versus all other original-method endings. The models use
# modern method as a predictor and elapsed episode time as the survival clock.
# Competing hazards are integrated over each current user's next 12 months.
# This is a descriptive model-based comparison, not a causal program effect.

root <- Sys.getenv("ETHIOPIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
support <- file.path(root,'output/Supporting_data')
e <- readRDS(file.path(root,'Data/Derived/ethiopia_2024_specified_modern_method_episodes.rds'))
ir <- readRDS(file.path(root,'Data/ET2024DHS__ETIR8ADT__IR_raw.rds'))
stocks <- read.csv(file.path(support,'current_users_actionable_12_month_projection.csv'))
landmark <- read.csv(file.path(support,'ethiopia_duration_aware_current_user_bridge.csv'))
wra26 <- 35016171

modern_codes <- c(1L,2L,3L,5L,6L,7L,11L,13L,17L,18L)
methods <- c('Injectables','Implants','Pill','IUD','Other modern')
method_group <- function(z) ifelse(z==3L,'Injectables',ifelse(z==11L,'Implants',
  ifelse(z==1L,'Pill',ifelse(z==2L,'IUD','Other modern'))))
actionable_codes <- c(1L,4L,5L,6L,7L,8L,10L,15L)

# Only spells whose start is visible can support a time-from-start survival
# model. Other endings stay as competing events; they are not dropped.
e <- e[e$entry==0L & e$method_code %in% modern_codes & e$exposure>0L,]
e$method <- factor(method_group(e$method_code),levels=methods)
e$action_event <- as.integer(e$discontinued & e$reason_code %in% actionable_codes)
e$other_event <- as.integer(e$discontinued & !e$reason_code %in% actionable_codes)
stopifnot(nrow(e)>7000,all(e$action_event+e$other_event<=1L),
  all(e$exposure>=1L),max(e$exposure)<=60L)

suppressPackageStartupMessages(library(survival))
fit_candidates <- function(event){
  choices <- c('weibull','loglogistic','lognormal','exponential')
  fits <- lapply(choices,function(d)survreg(
    as.formula(paste0('Surv(exposure,',event,')~method')),
    data=e,weights=wt,dist=d,control=survreg.control(maxiter=100)))
  aic <- vapply(fits,AIC,0.0)
  names(aic) <- choices
  best <- which.min(aic)
  list(fit=fits[[best]],distribution=choices[best],aic=aic)
}
model_a <- fit_candidates('action_event')
model_o <- fit_candidates('other_event')
fit_a <- model_a$fit;fit_o <- model_o$fit
stopifnot(fit_a$iter<100,fit_o$iter<100)

# Model-specific cumulative hazards. The selected AFT distribution is
# compared across Weibull, log-logistic, log-normal and exponential by AIC.
models <- lapply(methods,function(m){
  d <- data.frame(method=factor(m,levels=methods))
  c(mu_a=as.numeric(predict(fit_a,newdata=d,type='lp')),
    scale_a=fit_a$scale,
    mu_o=as.numeric(predict(fit_o,newdata=d,type='lp')),
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
    all <- da+do
    event <- s*(-expm1(-all))
    if(all>0){risk_a <- risk_a+event*da/all;risk_o <- risk_o+event*do/all}
    s <- s*exp(-all)
  }
  c(actionable=risk_a,other=risk_o,any=risk_a+risk_o)
}

current <- ir[as.numeric(ir$v313)==3 & as.numeric(ir$v312) %in% modern_codes,]
current$method <- method_group(as.integer(current$v312))
current$elapsed <- as.integer(current$v337)
current$wt <- as.numeric(current$v005)/1e6
stopifnot(!anyNA(current$elapsed),all(current$elapsed>=0),
  all(current$method %in% methods))
stocks$method[stocks$method=='Other modern methods'] <- 'Other modern'

rows <- lapply(methods,function(m){
  d <- current[current$method==m,]
  ages <- sort(unique(d$elapsed))
  risk <- vapply(ages,function(a)unname(next12(a,models[[m]])[1]),0.0)
  probability <- weighted.mean(risk[match(d$elapsed,ages)],d$wt)
  duration_weight <- tapply(d$wt,d$elapsed,sum)
  duration_weight <- duration_weight[order(as.numeric(names(duration_weight)))]
  median_duration <- as.numeric(names(duration_weight)[which(cumsum(duration_weight)>=sum(duration_weight)/2)[1]])
  stock <- stocks$current_users[stocks$method==m]
  first <- stocks$actionable_12_month_probability_pct[stocks$method==m]
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
dest <- file.path(support,'ethiopia_survival_model_duration_by_method_PREVIEW.csv')
write.csv(out,dest,row.names=FALSE)
fit_report <- data.frame(distribution=names(model_a$aic),
  actionable_aic=as.numeric(model_a$aic),other_aic=as.numeric(model_o$aic),
  selected_actionable=names(model_a$aic)==model_a$distribution,
  selected_other=names(model_o$aic)==model_o$distribution)
write.csv(fit_report,file.path(support,'ethiopia_survival_model_duration_fit_PREVIEW.csv'),row.names=FALSE)
print(out[,c('method','current_users_2025','first_year_actionable_risk_pct',
  'modeled_first_year_actionable_risk_pct',
  'historical_landmark_next12_risk_pct','survival_model_next12_risk_pct',
  'survival_model_original_method_endings','gross_mcpr_equivalent_pp')],row.names=FALSE)
cat('\nSaved preview:',dest,'\n')
cat('Selected AFT distributions:',model_a$distribution,'for actionable,',
  model_o$distribution,'for other endings\n')
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 168_survival_duration_method_cause.R
# LANGUAGE: R
MODULES[["168_survival_duration_method_cause.R"]] <- list(
 language="R",
 packaged_sha256="5ebca9bca53147dc9498f4451aacd3c94f4dbc0a7f90eabb945314ad7800b8b4",
 args=character(),
 code=r"-----(#!/usr/bin/env Rscript
# Sensitivity analysis: distribute the previously modeled next-year actionable
# original-method endings over the five established program-actionable causes.
# This is a calibrated cause-specific survival decomposition. It does not
# estimate modern-use exits or an intervention effect.
source(file.path(Sys.getenv("ETHIOPIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE)), 'Code/166_model_based_duration_method_preview.R'), local=TRUE)
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
write.csv(rows,file.path(support,'ethiopia_survival_model_duration_by_method_cause_PREVIEW.csv'),row.names=FALSE)
write.csv(data.frame(cause=causes,distribution=vapply(fitted,`[[`,'','dist'),
  event_n=vapply(fitted,`[[`,0L,'events'),aic=vapply(fitted,`[[`,0.0,'aic')),
  file.path(support,'ethiopia_survival_model_cause_fit_PREVIEW.csv'),row.names=FALSE)
print(rows[,c('method','reason','conditional_next12_risk_pct',
  'modeled_original_method_endings','gross_mcpr_equivalent_pp','cause_event_n')],row.names=FALSE)
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 171_aft_switching_bridge.R
# LANGUAGE: R
MODULES[["171_aft_switching_bridge.R"]] <- list(
 language="R",
 packaged_sha256="76bb261929bb667a7c27943728fe7fc8ff450d3637a0a073b0c7dbc9eb8e28c7",
 args=character(),
 code=r"-----(#!/usr/bin/env Rscript
# Ethiopia sensitivity analysis: combine AFT next-12-month cause-specific
# original-method ending risks with observed post-ending method pathways.
# The AFT model alone does not predict switching or modern use at year end.
# This hybrid borrows weighted DHS calendar transition fractions conditional on
# original method, actionable cause, and elapsed-duration bin. Sparse cells
# use an explicitly reported fallback. It is descriptive, not causal.
root <- Sys.getenv("ETHIOPIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
outdir <- file.path(root,'output/Supporting_data')
source(file.path(root,'Code/163_ethiopia_current_user_switch_duration.R'),local=TRUE)
historical <- duration
historical_causes <- cause_duration
source(file.path(root,'Code/168_survival_duration_method_cause.R'),local=TRUE)
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
write.csv(bridge,file.path(outdir,'ethiopia_aft_switching_by_method_cause.csv'),row.names=FALSE)
write.csv(support,file.path(outdir,'ethiopia_aft_switching_transition_support.csv'),row.names=FALSE)
method_summary <- aggregate(bridge[c('model_original_method_endings',
  'hybrid_direct_modern_switches','hybrid_modern_at_year_end',
  'hybrid_nonmodern_at_year_end','hybrid_year_end_nonmodern_mcpr_pp')],
  by=list(method=bridge$method),FUN=sum)
method_summary <- method_summary[match(methods,method_summary$method),]
method_summary$current_users_2025 <- aft_methods$current_users_2025
method_summary$conditional_next12_risk_pct <- aft_methods$survival_model_next12_risk_pct
write.csv(method_summary,file.path(outdir,'ethiopia_aft_switching_by_method.csv'),row.names=FALSE)
compare <- data.frame(method=methods,
  historical_original_method_endings=historical$projected_actionable_original_method_endings,
  aft_original_method_endings=method_summary$model_original_method_endings,
  historical_nonmodern_at_year_end=historical$projected_nonmodern_at_month12_after_actionable,
  aft_hybrid_nonmodern_at_year_end=method_summary$hybrid_nonmodern_at_year_end,
  historical_mcpr_pp=historical$descriptive_nonmodern_at_month12_pp,
  aft_hybrid_mcpr_pp=method_summary$hybrid_year_end_nonmodern_mcpr_pp)
write.csv(compare,file.path(outdir,'ethiopia_aft_vs_historical_switching_comparison.csv'),row.names=FALSE)
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
# ORIGINAL MODULE: create_ppt_figures.R
# LANGUAGE: R
MODULES[["create_ppt_figures.R"]] <- list(
 language="R",
 packaged_sha256="6a22c8333830c474602a1a7707fa82aa2804ae545be94d4025295cda3dd6be72",
 args=character(),
 code=r"-----(#!/usr/bin/env Rscript
# Presentation-compatible raster versions of the episode-level charts.
# These use the same CSV estimates shown in the project HTML.
options(stringsAsFactors = FALSE)
project <- Sys.getenv("ETHIOPIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
out <- file.path(project, 'output', 'assets')
dir.create(out, recursive=TRUE, showWarnings=FALSE)
if (!requireNamespace('ggplot2', quietly=TRUE)) install.packages('ggplot2', repos='https://cloud.r-project.org')
library(ggplot2)
navy <- '#133E5C'; teal <- '#138F8B'; green <- '#2C8C67'; blue <- '#2D75B5'
gold <- '#E0A124'; coral <- '#D65F49'; slate <- '#526574'; light <- '#E8EFF2'
base_theme <- theme_minimal(base_size=18) + theme(
  text=element_text(family='Helvetica'), plot.title=element_blank(),
  plot.subtitle=element_blank(), panel.grid.minor=element_blank(),
  panel.grid.major.y=element_blank(), panel.grid.major.x=element_line(color=light, linewidth=.5),
  axis.title=element_text(face='bold', color='#172B3A'), axis.text=element_text(color='#172B3A'),
  legend.position='bottom', legend.title=element_blank(), plot.margin=margin(15,55,15,15))

# Slide 5
x <- read.csv(file.path(project,'output','method_initiation_mix_overall.csv'))
x$method <- factor(x$method, levels=x$method[order(x$share_pct)])
p <- ggplot(x,aes(method,share_pct)) + geom_col(fill=teal,width=.68) + coord_flip() +
  geom_text(aes(label=sprintf('%.1f%%',share_pct)),hjust=-.12,fontface='bold',size=6) +
  scale_y_continuous(limits=c(0,70),breaks=seq(0,70,10),labels=function(z)paste0(z,'%'),expand=c(0,0)) +
  labs(x=NULL,y='Share of modern-method starts') + base_theme
ggsave(file.path(out,'ppt_initiation_mix.png'),p,width=10,height=5.7,dpi=200,bg='white')

# Slide 6
x <- read.csv(file.path(project,'output','discontinuation_excluding_successful_modern_switches.csv'),check.names=FALSE)
names(x) <- c('method','without3','without6','without12','switch12','total12')
# Emergency contraception is a one-time method, so its episode ending is not
# comparable with cessation of an ongoing method. Keep its result in the
# appendix/source table, but exclude it from this pooled continuation figure.
# The pooled row below is recomputed from all specified modern-method episodes
# except EC using the same competing-risk life-table estimator.
x <- x[!x$method %in% c('Emergency contraception','All specified modern methods'),]
x <- rbind(x,data.frame(
  method='All modern methods (excluding EC)',without3=NA_real_,without6=NA_real_,
  without12=33.566097760996,switch12=5.522221105712,
  total12=39.088318866709))
x$method <- factor(x$method,levels=rev(c('Injectables','Implants','Pill','Other modern methods','All modern methods (excluding EC)')))
long <- rbind(data.frame(method=x$method,outcome='Ended without successful modern switch',value=x$without12,total12=x$total12),
              data.frame(method=x$method,outcome='Successful modern switch',value=x$switch12,total12=x$total12))
long$outcome <- factor(long$outcome,levels=c('Ended without successful modern switch','Successful modern switch'))
p <- ggplot(long,aes(method,value,fill=outcome)) +
  geom_col(width=.68,position=position_stack(reverse=TRUE)) + coord_flip() +
  geom_text(data=long[long$value>=4,],aes(label=sprintf('%.1f%%',value)),position=position_stack(vjust=.5,reverse=TRUE),color='white',fontface='bold',size=5.2) +
  geom_text(data=transform(long[long$value<4,],label_y=total12+1),aes(y=label_y,label=sprintf('%.1f%%',value)),position='identity',hjust=0,color='#172B3A',fontface='bold',size=5.0) +
  scale_fill_manual(values=c(coral,teal)) + scale_y_continuous(limits=c(0,100),breaks=seq(0,100,20),labels=function(z)paste0(z,'%'),expand=c(0,0)) +
  labs(x=NULL,y='Cumulative probability by 12 months') + base_theme
ggsave(file.path(out,'ppt_switch_partition.png'),p,width=10.5,height=5.7,dpi=200,bg='white')

# Slide 7
x <- read.csv(file.path(project,'output','discontinuation_presentation_3_6_12.csv'),check.names=FALSE)
x <- x[x$method!='All specified modern methods (including EC)',]
x$method[x$method=='All specified modern methods (excluding EC)'] <- 'All modern, excluding EC'
long <- do.call(rbind,lapply(seq_len(nrow(x)),function(i)data.frame(method=x$method[i],month=c(0,3,6,12),value=c(0,x$month_3[i],x$month_6[i],x$month_12[i]))))
cols <- c('Pill'=gold,'Injectables'=teal,'Other modern methods'=blue,'Implants'=green,'All modern, excluding EC'=navy)
p <- ggplot(long,aes(month,value,color=method,group=method)) + geom_line(linewidth=1.5) + geom_point(size=3.5) +
  scale_color_manual(values=cols) + scale_x_continuous(breaks=c(0,3,6,12),labels=c('Start','3','6','12')) +
  scale_y_continuous(limits=c(0,80),breaks=seq(0,80,10),labels=function(z)paste0(z,'%'),expand=c(0,0)) +
  labs(x='Months of method use completed',y='Episodes ending the original method') + base_theme + theme(panel.grid.major.y=element_line(color=light,linewidth=.5),panel.grid.major.x=element_blank())
ggsave(file.path(out,'ppt_discontinuation_timing.png'),p,width=10.5,height=5.7,dpi=200,bg='white')

# Slide 8
x <- read.csv(file.path(project,'output','discontinuation_excluding_successful_modern_switches.csv'),check.names=FALSE)
names(x) <- c('method','without3','without6','without12','switch12','total12')
x <- x[x$method!='Emergency contraception',]
x$share <- 100*x$without3/x$without12
x$method <- factor(x$method,levels=x$method[order(x$share)])
p <- ggplot(x,aes(method,share)) + geom_col(fill=blue,width=.68) + coord_flip() +
  geom_text(aes(label=sprintf('%.0f%%',share)),hjust=-.15,fontface='bold',size=6) +
  scale_y_continuous(limits=c(0,60),breaks=seq(0,60,10),labels=function(z)paste0(z,'%'),expand=c(0,0)) +
  labs(x=NULL,y='Share of 12-month episode endings occurring by month 3') + base_theme
ggsave(file.path(out,'ppt_early_endings.png'),p,width=9.5,height=5.7,dpi=200,bg='white')

# Slide 9
x <- read.csv(file.path(project,'output','revised_table_7_12_aggregated_reasons.csv'),check.names=FALSE)
x$value <- x[['All specified modern methods']]
x$reason[x$reason=='Other side effects/health concerns'] <- 'Side effects / health concerns'
x$reason[x$reason=='Other fertility-related reasons'] <- 'Other fertility reasons'
x$reason <- factor(x$reason,levels=x$reason[order(x$value)])
p <- ggplot(x,aes(reason,value)) + geom_col(fill=navy,width=.68) + coord_flip() +
  geom_text(aes(label=sprintf('%.1f%%',value)),hjust=-.12,fontface='bold',size=5.5) +
  scale_y_continuous(limits=c(0,55),breaks=seq(0,50,10),labels=function(z)paste0(z,'%'),expand=c(0,0)) +
  labs(x=NULL,y='Share of discontinued episodes') + base_theme
ggsave(file.path(out,'ppt_reasons_ranked.png'),p,width=10,height=5.7,dpi=200,bg='white')

# Slide 5, second panel: initiation mix over complete calendar years
x <- read.csv(file.path(project,'output','method_initiation_mix_by_year.csv'),check.names=FALSE)
x <- x[x$coverage=='Complete across all interviews',]
x$method <- factor(x$method,levels=c('Injectables','Implants','Pill','Other modern methods','Emergency contraception'))
method_cols <- c('Injectables'=teal,'Implants'=navy,'Pill'=gold,'Other modern methods'=blue,'Emergency contraception'='#B85C83')
p <- ggplot(x,aes(factor(calendar_year),share_pct,fill=method)) +
  geom_col(width=.72) + scale_fill_manual(values=method_cols) +
  scale_y_continuous(limits=c(0,100),breaks=seq(0,100,20),labels=function(z)paste0(z,'%'),expand=c(0,0)) +
  labs(x='Calendar year',y='Share of modern-method starts') + base_theme +
  theme(panel.grid.major.y=element_line(color=light,linewidth=.5),panel.grid.major.x=element_blank(),legend.text=element_text(size=12))
ggsave(file.path(out,'ppt_initiation_by_year.png'),p,width=10,height=5.7,dpi=200,bg='white')
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 41_unadjusted_selected_regional_pairwise.py
# LANGUAGE: Python
MODULES[["41_unadjusted_selected_regional_pairwise.py"]] <- list(
  language="Python",
  original_sha256="521035d8f841ac9caa4347f464bf5089a9e599da7eab3e48bdb74cb68ea3f0c6",
  packaged_sha256="828376308ddcee4cebcce3aa544dcd8235c28cecee09a97e91937e94bc8b9e5c",
  args=character(),
  code=r"-----(#!/usr/bin/env python3
"""All design-bootstrap pairwise tests of regional 12-month selected-cause CIFs."""
from __future__ import annotations

import csv
from itertools import combinations
import os
from pathlib import Path

PROJECT = Path(os.environ['ETHIOPIA_PROJECT_ROOT'])
OUT = PROJECT / 'output'
RATES = OUT / 'presentation_selected_reason_regional_rates.csv'
BOOT = OUT / 'presentation_selected_reason_regional_unadjusted_bootstrap.csv'
DEST = OUT / 'presentation_selected_reason_regional_unadjusted_pairwise.csv'


def read(path):
    with path.open(newline='') as f:
        return list(csv.DictReader(f))


def quantile(values, q):
    values = sorted(values)
    pos = (len(values)-1) * q
    lo = int(pos)
    return values[lo] + (values[min(lo+1, len(values)-1)]-values[lo]) * (pos-lo)


rates = read(RATES)
draws = read(BOOT)
assert len(rates) == 14 and len(draws) == 10000
ordered = sorted((r for r in rates if r['region'] != 'Somali'),
                 key=lambda r: -float(r['unadjusted_12_month_probability_pct']))
ordered += [next(r for r in rates if r['region'] == 'Somali')]
out = []
for first, second in combinations(ordered, 2):
    name1, name2 = first['region'], second['region']
    difference = (float(first['unadjusted_12_month_probability_pct']) -
                  float(second['unadjusted_12_month_probability_pct']))
    samples = [float(b[name1])-float(b[name2]) for b in draws
               if b[name1] and b[name2]]
    assert len(samples) >= 9500
    # Null-center the paired bootstrap differences. The same survey PSU draw is
    # used for both regions, so this captures their design covariance.
    exceedances = sum(abs(value-difference) >= abs(difference) for value in samples)
    p_value = (exceedances + 1) / (len(samples) + 1)
    out.append(dict(
        region_1=name1, region_2=name2,
        n_1=int(first['unweighted_eligible_episodes']),
        n_2=int(second['unweighted_eligible_episodes']),
        rate_1_pct=float(first['unadjusted_12_month_probability_pct']),
        rate_2_pct=float(second['unadjusted_12_month_probability_pct']),
        difference_percentage_points=difference,
        pointwise_ci_low=quantile(samples, .025),
        pointwise_ci_high=quantile(samples, .975),
        unadjusted_p=p_value,
        valid_bootstrap_replicates=len(samples),
    ))

# Holm step-down controls familywise error over every one of the 91 pairs.
ranked = sorted(range(len(out)), key=lambda i: out[i]['unadjusted_p'])
running = 0.0
for position, index in enumerate(ranked):
    running = max(running, min(1.0, (len(out)-position)*out[index]['unadjusted_p']))
    out[index]['holm_adjusted_p'] = running
    out[index]['holm_significant_05'] = running < .05
assert len(out) == 91

with DEST.open('w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=list(out[0]))
    writer.writeheader()
    writer.writerows(out)

print(f'{DEST}: {len(out)} comparisons; '
      f'{sum(r["holm_significant_05"] for r in out)} significant after Holm adjustment')
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 136_regional_actionable_pairwise_shared_mix.py
# LANGUAGE: Python
MODULES[["136_regional_actionable_pairwise_shared_mix.py"]] <- list(
  language="Python",
  original_sha256="2b6b789096c72dde0948396a0e62b3da71e3643e3be242e26e0e55c0885aa577",
  packaged_sha256="bf7fa866b43adaef574ca40c338a1641264dd673b8aa2d38469139b49e61d9b4",
  args=character(),
  code=r"-----(#!/usr/bin/env python3
"""Pair-specific method standardization for every Ethiopian regional pair.

Within each pair, give both regions the arithmetic mean of their two
survey-weighted method-start distributions, preserving each region's fitted
method-specific risk. This is an exact symmetric decomposition of the two
Model-1 own-mix rates, not of the raw DHS life-table rates.
"""
import csv
import itertools
import math
import os
from pathlib import Path

ROOT = Path(os.environ['ETHIOPIA_PROJECT_ROOT'])
SUPPORT = ROOT / 'output' / 'Supporting_data'
METHODS = ('Injectables', 'Implants', 'Pill', 'IUD', 'Other modern')

def read(name):
    with (SUPPORT / name).open(newline='') as f:
        return list(csv.DictReader(f))

def quantile(values, p):
    values = sorted(values)
    h = (len(values)-1)*p
    i = int(h)
    return values[i] + (values[min(i+1,len(values)-1)]-values[i])*(h-i)

cells = read('regional_actionable_all_region_method_mix_cells.csv')
boot = read('regional_actionable_all_region_method_mix_bootstrap.csv')
regions = sorted({x['region'] for x in cells} - {'National'})
assert len(regions) == 14 and len(boot) == 1000
cell = {(x['region'],x['method']): x for x in cells}

def values(region, draw=None):
    if draw is None:
        p = [float(cell[region,m]['weighted_start_share_pct'])/100 for m in METHODS]
        q = [float(cell[region,m]['model_method_risk_pct']) for m in METHODS]
    else:
        p = [float(draw[f'share::{region}::{m}']) for m in METHODS]
        q = [float(draw[f'risk::{region}::{m}']) for m in METHODS]
    return p,q

def compare(a,b,draw=None):
    pa,qa = values(a,draw)
    pb,qb = values(b,draw)
    common = [(x+y)/2 for x,y in zip(pa,pb)]
    own_a = sum(x*y for x,y in zip(pa,qa))
    own_b = sum(x*y for x,y in zip(pb,qb))
    shared_a = sum(x*y for x,y in zip(common,qa))
    shared_b = sum(x*y for x,y in zip(common,qb))
    own_gap = own_a-own_b
    shared_gap = shared_a-shared_b
    mix_component = own_gap-shared_gap
    direct_mix = sum((x-y)*(u+v)/2 for x,y,u,v in zip(pa,pb,qa,qb))
    assert abs(mix_component-direct_mix) < 1e-8
    return own_a,own_b,shared_a,shared_b,own_gap,shared_gap,mix_component

rows=[]
for a,b in itertools.combinations(regions,2):
    point=compare(a,b)
    samples=[]
    for draw in boot:
        try:
            sample=compare(a,b,draw)
            if all(math.isfinite(v) for v in sample):
                samples.append(sample)
        except (ValueError,KeyError):
            pass
    assert len(samples) >= 950, (a,b,len(samples))
    gap_draws=[s[5] for s in samples]
    mean=sum(gap_draws)/len(gap_draws)
    se=math.sqrt(sum((v-mean)**2 for v in gap_draws)/(len(gap_draws)-1))
    pval=math.erfc(abs(point[5]/se)/math.sqrt(2)) if se>0 else 1.0
    row=dict(region_a=a,region_b=b,
        region_a_observed_starts=sum(int(cell[a,m]['observed_start_n']) for m in METHODS),
        region_b_observed_starts=sum(int(cell[b,m]['observed_start_n']) for m in METHODS),
        own_mix_a_pct=point[0],own_mix_b_pct=point[1],
        pair_shared_mix_a_pct=point[2],pair_shared_mix_b_pct=point[3],
        own_mix_gap_pp=point[4],pair_shared_mix_gap_pp=point[5],
        shared_gap_ci_low=quantile(gap_draws,.025),
        shared_gap_ci_high=quantile(gap_draws,.975),
        method_mix_component_pp=point[6],
        mix_component_ci_low=quantile([s[6] for s in samples],.025),
        mix_component_ci_high=quantile([s[6] for s in samples],.975),
        unadjusted_p=pval,bootstrap_se_pp=se,valid_bootstrap_draws=len(samples))
    rows.append(row)

# Holm familywise correction across all 91 two-sided pairwise tests.
order=sorted(range(len(rows)),key=lambda i: rows[i]['unadjusted_p'])
running=0.0
for rank,i in enumerate(order):
    running=max(running,(len(rows)-rank)*rows[i]['unadjusted_p'])
    rows[i]['holm_p']=min(1.0,running)
    rows[i]['significant_5pct']=rows[i]['holm_p']<.05
    rows[i]['significant_10pct']=rows[i]['holm_p']<.10

path=SUPPORT/'regional_actionable_pairwise_shared_method_mix.csv'
with path.open('w',newline='') as f:
    writer=csv.DictWriter(f,fieldnames=list(rows[0]))
    writer.writeheader()
    writer.writerows(rows)
print(path)
print('Significant after Holm at 5%:',sum(r['significant_5pct'] for r in rows))
for r in rows:
    if r['significant_10pct']:
        print(r['region_a'],r['region_b'],round(r['pair_shared_mix_gap_pp'],2),round(r['holm_p'],3))
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 153_current_user_actionable_projection.py
# LANGUAGE: Python
MODULES[["153_current_user_actionable_projection.py"]] <- list(
  language="Python",
  original_sha256="f9b8915105c864bb2c3fc2710885dc12942bf368f896cf61d62585d804d43b09",
  packaged_sha256="9d543b28121e6a623e4a17c0e8fc80d818cfec3a8f249085888e64246d64a172",
  args=character(),
  code=r"-----(#!/usr/bin/env python3
"""Recalculate the original user-count slide using actionable 12-month risks.

This preserves the slide's survey-date current-user method mix and substitutes
national method-specific first-year competing-risk cumulative incidences for
potentially actionable reasons. The resulting counts are a planning illustration,
not a prospective forecast for users who have already spent time on a method.
"""
import csv
import os
from pathlib import Path

ROOT = Path(os.environ['ETHIOPIA_PROJECT_ROOT'])
METHODS = ROOT / 'output/reproduced_figures/slide_24_method_planning_table.csv'
RISKS = ROOT / 'output/regional_actionable_method_starts_and_rates.csv'
OUTPUT = ROOT / 'output/Supporting_data/current_users_actionable_12_month_projection.csv'

with METHODS.open(newline='') as f:
    methods = list(csv.DictReader(f))
with RISKS.open(newline='') as f:
    risks = {
        row['method']: float(row['actionable_12_month_probability_pct'])
        for row in csv.DictReader(f) if row['region'] == 'National'
    }

assert len(methods) == 6
assert set(risks) == {'Injectables', 'Implants', 'Pill', 'IUD', 'Other modern'}
records = []
for row in methods:
    method = row['method']
    users = float(row['current_users'])
    mix = float(row['current_mix_pct'])
    if method == 'EC':
        records.append((method, mix, users, '', ''))
        continue
    risk_key = 'Other modern' if method == 'Other modern methods' else method
    risk = risks[risk_key]
    records.append((method, mix, users, risk, users * risk / 100))

total_mix = sum(row[1] for row in records if row[0] != 'EC')
total_users = sum(row[2] for row in records if row[0] != 'EC')
total_endings = sum(row[4] for row in records if row[0] != 'EC')
total_risk = 100 * total_endings / total_users
assert 7_674_000 < total_users < 7_676_000
assert abs(total_endings - 1_241_693.4830428765) < 1
records.append(('All modern methods, excluding EC', total_mix, total_users,
                total_risk, total_endings))

with OUTPUT.open('w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['method', 'current_mix_pct', 'current_users',
                     'actionable_12_month_probability_pct',
                     'illustrative_actionable_method_endings'])
    writer.writerows(records)
print(OUTPUT)
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 154_current_user_actionable_by_cause.py
# LANGUAGE: Python
MODULES[["154_current_user_actionable_by_cause.py"]] <- list(
  language="Python",
  original_sha256="7d213d54b8173e378485c2b6a812b2c64e31dc6ff4aed78a82eb9c20ecb26939",
  packaged_sha256="5231f5cf8ad89854208032c4c6e02298de09cbf7e27aa73c2aa21080d57b1d56",
  args=character(),
  code=r"-----(#!/usr/bin/env python3
"""Apply five matched actionable cause-specific risks to current users.

The cause-specific probabilities come from the same 8,611-episode calendar
cohort and competing-risk life table as the actionable method totals. This is
essential: the older nine-reason planning CSV uses a different analysis cohort
and its cause-specific rows do not sum to the newer actionable method rates.
"""
import csv
import json
import os
from pathlib import Path

ROOT = Path(os.environ['ETHIOPIA_PROJECT_ROOT'])
OUT = ROOT / 'output'
PROJECTION = OUT / 'Supporting_data/current_users_actionable_12_month_projection.csv'
REASONS = OUT / 'regional_actionable_reason_mix_by_method.csv'
CSV_OUT = OUT / 'Supporting_data/current_users_actionable_by_cause.csv'
JSON_OUT = OUT / 'Supporting_data/current_users_actionable_slides.json'

with PROJECTION.open(newline='') as f:
    projection = list(csv.DictReader(f))
with REASONS.open(newline='') as f:
    reasons = list(csv.DictReader(f))

order = [
    'Method failure', 'Wanted more effective method',
    'Changes in menstrual bleeding', 'Other side effects/health',
    'Access/cost/convenience',
]
methods = ['Injectables', 'Implants', 'Pill', 'IUD', 'Other modern methods']
rows = []
slide_rows = []
national = [r for r in reasons if r['region'] == 'National']
for method in methods:
    p = next(r for r in projection if r['method'] == method)
    user_count = float(p['current_users'])
    key = 'Other modern' if method == 'Other modern methods' else method
    rs = [r for r in national if r['method'] == key]
    assert len(rs) == 5
    rs.sort(key=lambda r: order.index(r['reason']))
    probabilities = {}
    endings = {}
    event_n = {}
    for r in rs:
        cause = r['reason']
        risk = float(r['cause_specific_12_month_probability_pct'])
        count = user_count * risk / 100
        probabilities[cause] = risk
        endings[cause] = count
        event_n[cause] = int(r['reason_endings_n'])
        rows.append((method, cause, user_count, risk, count, event_n[cause]))
    assert abs(sum(probabilities.values()) - float(p['actionable_12_month_probability_pct'])) < 1e-9
    assert abs(sum(endings.values()) - float(p['illustrative_actionable_method_endings'])) < 1e-6
    slide_rows.append(dict(method=method, current_users=user_count,
                           total_risk=sum(probabilities.values()),
                           total_endings=sum(endings.values()),
                           probabilities=probabilities, endings=endings,
                           observed_cause_endings_n=event_n))

total_users = sum(r['current_users'] for r in slide_rows)
total_endings = {cause: sum(r['endings'][cause] for r in slide_rows) for cause in order}
total_probabilities = {cause: 100 * total_endings[cause] / total_users for cause in order}
assert abs(sum(total_endings.values()) - float(projection[-1]['illustrative_actionable_method_endings'])) < 1e-6
total = dict(method='All modern methods, excluding EC', current_users=total_users,
             total_risk=sum(total_probabilities.values()),
             total_endings=sum(total_endings.values()),
             probabilities=total_probabilities, endings=total_endings)
for cause in order:
    rows.append((total['method'], cause, total_users, total_probabilities[cause],
                 total_endings[cause], ''))

with CSV_OUT.open('w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['method', 'actionable_cause', 'current_users',
                     'cause_specific_12_month_probability_pct',
                     'illustrative_method_endings', 'observed_first_year_cause_endings_n'])
    writer.writerows(rows)
JSON_OUT.write_text(json.dumps(dict(causes=order, methods=slide_rows,
                                    total=total), indent=2))
print(CSV_OUT)
print(JSON_OUT)
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 158_national_actionable_cause_probabilities.py
# LANGUAGE: Python
MODULES[["158_national_actionable_cause_probabilities.py"]] <- list(
  language="Python",
  original_sha256="82a19094e486332fc6ae2af83ebc8386367a49e90a7b8f003a2b2b159f9f895b",
  packaged_sha256="12fa35d138943239da163ca628d9077096033c5008e178e7c4c5e7d33cce135b",
  args=character(),
  code=r"-----(#!/usr/bin/env python3
"""Reproduce the national 17% episode life table by five actionable causes.

This is the all-modern episode analysis, not the current-user method-mix
weighted projection. Other original-method endings remain competing events.
"""
import csv
import os
from pathlib import Path

ROOT = Path(os.environ['ETHIOPIA_PROJECT_ROOT'])
INPUT = ROOT / 'output/Supporting_data/selected_reason_exploratory_episode_covariates.csv'
OUTPUT = ROOT / 'output/Supporting_data/national_actionable_cause_probabilities.csv'
CAUSES = [
    ('Method failure', {1}),
    ('Wanted more effective method', {7}),
    ('Changes in menstrual bleeding', {15}),
    ('Other side effects/health', {4, 5}),
    ('Access/cost/convenience', {6, 8, 10}),
]
with INPUT.open(newline='') as f:
    z = [dict(entry=int(r['entry']), exposure=int(r['exposure']),
              wt=float(r['wt']), discontinued=r['discontinued'] == 'TRUE',
              reason=int(r['reason_code'])) for r in csv.DictReader(f)]
assert len(z) == 8611
incidence = {name: 0.0 for name, _ in CAUSES}
survival = 1.0
for month in range(1, 13):
    at_risk = [r for r in z if r['entry'] < month <= r['exposure']]
    risk_weight = sum(r['wt'] for r in at_risk)
    endings = [r for r in at_risk if r['discontinued'] and r['exposure'] == month]
    all_ending_weight = sum(r['wt'] for r in endings)
    for name, codes in CAUSES:
        cause_weight = sum(r['wt'] for r in endings if r['reason'] in codes)
        incidence[name] += survival * cause_weight / risk_weight
    survival *= 1 - all_ending_weight / risk_weight
total = 100 * sum(incidence.values())
assert abs(total - 16.9781693158385) < 1e-9
with OUTPUT.open('w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['cause', 'national_episode_12_month_probability_pct',
                     'share_of_actionable_probability_pct'])
    for name, _ in CAUSES:
        prob = 100 * incidence[name]
        writer.writerow([name, prob, 100 * prob / total])
    writer.writerow(['Total actionable', total, 100])
print(OUTPUT)
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 179_duration_planning_table_arithmetic.py
# LANGUAGE: Python
MODULES[["179_duration_planning_table_arithmetic.py"]] <- list(
  language="Python",
  original_sha256="1d2d5a30ca6f07f17c931307e3aa6354b138e3c37f0f34c614163a30eef3ce67",
  packaged_sha256="5be2ad6fd6770ee5a9521683574c14a07ebe32a16907bc5850f8b437d89d5adf",
  args=character(),
  code=r"-----(import csv
import json
import os
from pathlib import Path
ROOT = Path(os.environ['ETHIOPIA_PROJECT_ROOT'])
DATA = ROOT / 'output/Supporting_data'
def rows(name):
    with (DATA / name).open(newline='') as f:
        return list(csv.DictReader(f))

def number(x): return f'{float(x):,.0f}'
def pct(x): return f'{float(x):.1f}'
def rate(x): return f'{float(x):.2f}%'
def pp(x): return f'{float(x):+.2f} pp'

base_users = rows('current_users_actionable_12_month_projection.csv')
users = {r['method'].replace('Other modern methods','Other modern'): float(r['current_users'])
         for r in base_users if r['method'] != 'All modern methods, excluding EC'}
methods = ['Injectables','Implants','Pill','IUD','Other modern']
causes = ['Method failure','Wanted more effective method','Changes in menstrual bleeding',
          'Other side effects/health','Access/cost/convenience']
mix = {r['method'].replace('Other modern methods','Other modern'): float(r['current_mix_pct'])
       for r in base_users if r['method'] != 'All modern methods, excluding EC'}
total_users = sum(users.values())
non_ec_users = sum(users[m] for m in methods)
wra = 35016171.0
scenarios = rows('ethiopia_switch_duration_mcpr_scenarios.csv')

historical_method = {r['method']: r for r in rows('ethiopia_duration_aware_current_user_bridge.csv')}
historical_cause = {(r['method'],r['reason']): r for r in rows('ethiopia_duration_aware_current_user_by_cause.csv')}
aft_method = {r['method']: r for r in rows('ethiopia_aft_switching_by_method.csv')}
aft_cause = {(r['method'],r['reason']): r for r in rows('ethiopia_aft_switching_by_method_cause.csv')}

approaches = [
    dict(key='Historical duration-aware',method=historical_method,cause=historical_cause,
         gross_col='projected_actionable_original_method_endings',
         net_col='projected_nonmodern_at_month12_after_actionable',
         cause_net_col='projected_nonmodern_at_month12',
         risk_col='actionable_ending_risk_next12_pct',
         method_source='Ethiopia DHS calendar method-by-duration landmarks; 61+ month current users use the 37–60 month risk.',
         cause_source='Historical method, elapsed duration, reason and observed 12-month post-ending method pathways.'),
    dict(key='AFT survival + pathways',method=aft_method,cause=aft_cause,
         gross_col='model_original_method_endings',net_col='hybrid_nonmodern_at_year_end',
         cause_net_col='hybrid_nonmodern_at_year_end',risk_col='conditional_next12_risk_pct',
         method_source='Survey-weighted method-only AFT risks conditional on elapsed use, combined with observed post-ending pathways.',
         cause_source='Cause-specific AFT ending patterns plus observed switching and restarting pathways; exploratory hybrid.'),
]

def make_tables(a):
    name=a['key']; mrows=a['method']; crows=a['cause']; net={m:float(mrows[m][a['net_col']]) for m in methods}
    gross={m:float(mrows[m][a['gross_col']]) for m in methods}
    total_net=sum(net.values()); total_gross=sum(gross.values())
    assert abs(sum(float(crows[(m,c)][a['cause_net_col']]) for m in methods for c in causes)-total_net)<1e-4
    assert abs(total_net - (620701.415776095 if name.startswith('Historical') else 635220.577160201))<1e-3
    net_pp=100*total_net/wra
    cause_sum={c:sum(float(crows[(m,c)][a['cause_net_col']]) for m in methods) for c in causes}
    is_aft=name.startswith('AFT')
    label='AFT + pathways' if is_aft else 'Historical duration-aware'
    method_table=[
        [('Method',),('Current mix','(%)'),('Current','users'),('Actionable ending','risk (%)'),('Nonmodern at','year end')]
    ]
    for m in methods:
        method_table.append([('Other modern methods' if m=='Other modern' else m,),
            (pct(mix[m]),),(number(users[m]),),(pct(mrows[m][a['risk_col']]),),(number(net[m]),)])
    method_table.append([('EC',),(pct(mix['EC']),),(number(users['EC']),),('Not applied',),('Not estimated',)])
    method_table.append([('Current-user mix total, excluding EC',),(pct(sum(mix[m] for m in methods)),),
        (number(non_ec_users),),(pct(100*total_gross/non_ec_users),),(number(total_net),)])

    cause_table=[[('Method',),('Current','users'),('Method','failure'),('Wanted more','effective'),
                  ('Bleeding','changes'),('Other side effects','health'),('Access / cost /','convenience'),
                  ('Nonmodern at','year end')]]
    for m in methods:
        cause_table.append([('Other modern methods' if m=='Other modern' else m,), (number(users[m]),),
            *((number(crows[(m,c)][a['cause_net_col']]),) for c in causes),(number(net[m]),)])
    cause_table.append([('All methods, excluding EC',),(number(non_ec_users),),
        *((number(cause_sum[c]),) for c in causes),(number(total_net),)])

    scenario_table=[[('Scenario',),('2025 DHS mCPR',),('Change to 2026',),('Illustrative 2026 mCPR',)],
      [('Status quo',),('22.73%',),('0 pp',),('22.73%',)],
      [('UN annual change',),('22.73%',),('+0.8 pp',),('23.53%',)],
      [('Track20/FP2030 recent change',),('22.73%',),('+0.7 pp',),('23.43%',)]]

    mcpr_table=[[('Different mCPR growth scenarios',),('2026 users, usual endings',),('2026 mCPR',),
                 ('2026 users if retained',),('Revised 2026 mCPR',),('Difference',)]]
    by_method_tables=[]
    for idx,s in enumerate(scenarios):
        usual=float(s['usual_users_2026']); mcpr=float(s['mcpr_2026_pct'])
        retained=usual+total_net
        label_s=['Status quo','UN annual change','Track20/FP2030'][idx]
        mcpr_table.append([(label_s,),(number(usual),),(rate(mcpr),),(number(retained),),
                           (rate(100*retained/wra),),(pp(net_pp),)])
        by_method=[[('Method',),('2025 users',),('2026 users',),('Year-end loss','averted'),
                    ('2026 if averted',),('2026 mCPR',),('mCPR if averted',)]]
        for m in methods+['EC']:
            usual_method=usual*users[m]/total_users
            impact=net.get(m,0.)
            by_method.append([(m,),(number(users[m]),),(number(usual_method),),
                (number(impact) if m!='EC' else '—',),(number(usual_method+impact),),
                (rate(100*usual_method/wra),),(rate(100*(usual_method+impact)/wra),)])
        by_method.append([('All modern',),(number(total_users),),(number(usual),),(number(total_net),),
            (number(retained),),(rate(mcpr),),(rate(100*retained/wra),)])
        by_method_tables.append(by_method)

    pp_table=[[('Method','measure'),('Method','failure'),('Want more','effective'),
               ('Bleeding','changes'),('Other side effects','health'),('Access / cost /','convenience'),
               ('All actionable','causes')]]
    for m in methods:
        pp_table.append([(m,),*((number(crows[(m,c)][a['cause_net_col']]),) for c in causes),
                         (number(net[m]),)])
    pp_table.extend([
      [('Estimated nonmodern','at year end'),*((number(cause_sum[c]),) for c in causes),(number(total_net),)],
      [('2026 women','aged 15–49'),*((number(wra),) for _ in causes),(number(wra),)],
      [('Maximum mCPR','equivalent'),*((f'{100*cause_sum[c]/wra:.2f} pp',) for c in causes),
       (f'{net_pp:.2f} pp',)]
    ])

    table_map={47:method_table,48:cause_table,49:scenario_table,50:mcpr_table,
               51:by_method_tables[0],52:by_method_tables[1],53:by_method_tables[2],54:pp_table}
    detail=f'{number(total_gross)} projected actionable original-method endings; {number(total_net)} are nonmodern at year end after observed switching/restarting pathways.'
    if is_aft:
        foot_m=('Ending risk: two survey-weighted, method-only AFT models estimate actionable and other-ending hazards. '
                'The 12-month actionable probability is conditional on months already used. Year-end counts add observed switching/restarting pathways; EC excluded.')
        foot_c=('Cause probability: cause-specific AFT patterns allocate the actionable ending risk across five reasons. '
                'The year-end nonmodern probability then applies observed switching/restarting pathways by method, duration and cause.')
        foot_by_method=(f'Year-end loss averted: current users × AFT actionable ending probability conditional on elapsed use '
                        f'× observed chance of no modern use at month 12 ({number(total_net)} total).')
    else:
        foot_m=('Ending risk: weighted 12-month actionable ending probability from historical calendar landmarks, matched '
                'by method and elapsed-use band; other endings compete. The 61+ month group uses the 37–60-month risk. '
                'Year-end counts account for observed switching/restarting; EC excluded.')
        foot_c=('Cause probability: share of matched historical method-duration landmarks ending for that actionable '
                'reason and not using a modern method at month 12. Applied to the current-user method-duration mix.')
        foot_by_method=(f'Year-end loss averted: current users × historical method-duration probability of an actionable '
                        f'ending followed by no modern use at month 12 ({number(total_net)} total).')
    foot_gain=f'{number(total_net)} ÷ 35,016,171 projected 2026 women aged 15–49 = +{net_pp:.2f} pp.'
    texts={
      47:[f'{label}: actionable endings',
          '2025 current users; next 12 months conditional on time already used',foot_m],
      48:[f'{label}: year-end loss by cause',
          f'Projected current users; {number(total_net)} nonmodern at year end after actionable endings',
          'Each cause count uses current users × the method- and cause-specific year-end nonmodern probability.',
          foot_c],
      49:[f'{label}: common 2026 mCPR baselines',
          '2025 women aged 15–49: 34.06 million     Current modern users: 7.74 million',
          'UN: 28.5% in 2026 minus 27.7% in 2025. Track20/FP2030: recent +0.7-point annual change extrapolated to 2026.',
          'All scenarios use the same unrounded DHS 2024–25 all-women mCPR baseline (22.7287%).'],
      50:[f'{label}: mCPR if year-end loss avoided',
          '2026 women aged 15–49: 35.02 million     Year-end nonmodern after actionable endings',
          foot_gain,detail],
      51:[f'{label}: no-growth mCPR by method',
          'No change from the 2025 DHS all-women mCPR',
          'Each method’s mCPR = method users ÷ 35,016,171 projected 2026 women aged 15–49.',
          foot_by_method],
      52:[f'{label}: UN-growth mCPR by method',
          '+0.8 percentage points applied to the 2025 DHS mCPR',
          'Each method’s mCPR = method users ÷ 35,016,171 projected 2026 women aged 15–49.',
          foot_by_method],
      53:[f'{label}: Track20-growth mCPR by method',
          '+0.7 percentage points applied to the 2025 DHS mCPR',
          'Each method’s mCPR = method users ÷ 35,016,171 projected 2026 women aged 15–49.',
          foot_by_method],
      54:[f'{label}: mCPR equivalent by actionable cause',
          'Ethiopia | year-end nonmodern users after actionable original-method endings',
          'Each cause: projected year-end nonmodern users ÷ 35,016,171 projected 2026 women aged 15–49.',
          f'Potential mCPR-equivalent ceiling is {net_pp:.2f} pp. Switching and restarting are reflected in the year-end counts; this is not a predicted program effect.',
          foot_c],
    }
    return table_map,texts,net_pp,total_net

result = {}
for approach in approaches:
    tables, texts, impact, retained = make_tables(approach)
    result[approach['key']] = dict(tables=tables, texts=texts, impact_pp=impact, retained=retained)
(DATA / 'final_duration_planning_tables.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
)-----"
)

MODULES[["203_allcause_survey_inference.R"]] <- list(
 language="R",
 packaged_sha256="4c313957197ed1f1b1414ea8d6704278790f9cb4f65dab4b3b3d65b32cd1a0ca",
 args=character(),
 code=r"-----(# Reconstruct the early all-cause adjusted subgroup view and regional life
# tables with full-frame design inference. Inputs are project parameters.
root<-Sys.getenv('ETHIOPIA_PROJECT_ROOT');stopifnot(nzchar(root))
s<-readLines(file.path(root,'Code/34_selected_reason_regression.R'));ix<-grep('^fit <- nnet',s)[1];eval(parse(text=s[1:(ix-1)]))
person$ended<-as.integer(ended)
form<-ended~month+method_group+age_group+parity_group+education+wealth_group+residence+region
fit<-glm(form,data=person,weights=wt,family=quasibinomial())
X<-model.matrix(fit);p<-fitted(fit);H<-crossprod(X,X*(person$wt*p*(1-p)));Hinv<-solve(H)
frame<-full_survey_frame();score<-rowsum(X*(person$wt*(person$ended-p)),person$cluster,reorder=FALSE)
U<-matrix(0,nrow(frame),ncol(X));U[match(rownames(score),frame$cluster),]<-score
var_if<-function(v){ans<-0;for(g in split(seq_len(nrow(frame)),frame$stratum))ans<-ans+length(g)/(length(g)-1)*sum((v[g]-mean(v[g]))^2);ans}
df<-nrow(frame)-length(unique(frame$stratum));critical<-qt(.975,df)
standard<-d;den<-sum(standard$wt)
margin<-function(variable,level){
 x<-standard;if(!is.null(variable))x[[variable]]<-factor(level,levels=levels(x[[variable]]))
 S<-rep(1,nrow(x));D<-matrix(0,nrow(x),ncol(X));for(t in 1:12){x$month<-factor(t,levels=1:12);xx<-model.matrix(delete.response(terms(fit)),x,contrasts.arg=fit$contrasts);pt<-plogis(xx%*%coef(fit));S<-S*(1-as.numeric(pt));D<-D+xx*as.numeric(pt)}
 risk<-100*(1-S);mean<-weighted.mean(risk,standard$wt);grad<-100*colSums(D*(S*standard$wt))/den
 emp<-rowsum(standard$wt*(risk-mean)/den,standard$cluster,reorder=FALSE);v<-as.numeric(U%*%Hinv%*%grad);v[match(rownames(emp),frame$cluster)]<-v[match(rownames(emp),frame$cluster)]+emp[,1]
 se<-sqrt(var_if(v));c(probability=mean,ci_low=max(0,mean-critical*se),ci_high=min(100,mean+critical*se),se=se)
}
old<-read.csv(file.path(out,'presentation_discontinuation_predictor_margins.csv'))
z<-t(mapply(margin,old$group,old$level));cat('Largest reconstruction difference (pp):',max(abs(z[,'probability']-old$probability)),'\n');stopifnot(max(abs(z[,'probability']-old$probability))<.11)
old$probability<-z[,'probability'];old$ci_low<-z[,'ci_low'];old$ci_high<-z[,'ci_high'];old$se<-z[,'se'];old$design_df<-df
write.csv(old,file.path(out,'presentation_discontinuation_predictor_margins.csv'),row.names=FALSE)
# Full-frame influence variance of each raw all-cause cumulative incidence.
raw<-read.csv(file.path(out,'presentation_regional_discontinuation.csv'))
regions<-c(`1`='Tigray',`2`='Afar',`3`='Amhara',`4`='Oromia',`5`='Somali',`6`='Benishangul-Gumuz',`7`='Central Ethiopia',`8`='Sidama',`9`='South West Ethiopia',`10`='South Ethiopia',`12`='Gambella',`13`='Harari',`14`='Addis Ababa',`15`='Dire Dawa')
for(i in seq_len(nrow(raw))){q<-d[as.character(d$region)==names(regions)[match(raw$region[i],regions)],];rr<-aa<-matrix(0,nrow(frame),12)
 for(t in 1:12){at<-q$entry<t&q$exposure>=t;end<-at&q$discontinued&q$exposure==t;for(k in 1:2){use<-if(k==1)at else end;if(any(use)){v<-rowsum(q$wt[use],q$cluster[use],reorder=FALSE);ix<-match(rownames(v),frame$cluster);if(k==1)rr[ix,t]<-v[,1]else aa[ix,t]<-v[,1]}}}
 R<-colSums(rr);A<-colSums(aa);h<-A/R;S<-prod(1-h);influence<-as.numeric(100*(aa%*%(S/(1-h)/R)-rr%*%(S/(1-h)*A/R^2)))
 rate<-100*(1-S);stopifnot(abs(rate-raw$rate[i])<1e-7);se<-sqrt(var_if(influence));raw$se[i]<-se;raw$lo[i]<-max(0,rate-critical*se);raw$hi[i]<-min(100,rate+critical*se)
}
write.csv(raw,file.path(out,'presentation_regional_discontinuation.csv'),row.names=FALSE)
saveRDS(fit,file.path(out,'Supporting_data/allcause_monthly_logistic_model.rds'))
cat('All-cause inference uses',nrow(frame),'PSUs;',df,'design degrees of freedom.\n')
)-----"
)

MODULES[["204_regional_reason_precision.R"]] <- list(
 language="R",
 packaged_sha256="1ec97820036ebaccd19d65b0045c406c4927695f30653ef24463ff683792c825",
 args=character(),
 code=r"-----(root<-Sys.getenv('ETHIOPIA_PROJECT_ROOT');ir<-readRDS(file.path(root,'Data/ET2024DHS__ETIR8ADT__IR_raw.rds'));e<-read.csv(file.path(root,'output/Supporting_data/selected_reason_exploratory_episode_covariates.csv'));frame<-unique(data.frame(cluster=paste(as.integer(ir$v022),as.integer(ir$v021),sep=':'),stratum=as.integer(ir$v022)));df<-nrow(frame)-length(unique(frame$stratum));crit<-qt(.975,df)
regions<-c(`1`='Tigray',`2`='Afar',`3`='Amhara',`4`='Oromia',`5`='Somali',`6`='Benishangul-Gumuz',`7`='Central Ethiopia',`8`='Sidama',`9`='South West Ethiopia',`10`='South Ethiopia',`12`='Gambella',`13`='Harari',`14`='Addis Ababa',`15`='Dire Dawa');groups<-list('Wanted to become pregnant'=2L,'Method experience or access'=c(1L,4L,5L,6L,7L),'Husband/partner disapproved'=8L,'Other'=c(3L,9L));file<-file.path(root,'output/presentation_regional_reason_precision.csv');old<-read.csv(file)
for(i in seq_len(nrow(old))){code<-names(regions)[match(old$region[i],regions)];q<-e[e$region==code&e$discontinued&e$entry<e$exposure&e$exposure<=12,];yes<-q$reason%in%groups[[old$reason[i]]];p<-sum(q$wt*yes)/sum(q$wt);stopifnot(abs(100*p-old$percent[i])<1e-7);ss<-rowsum(q$wt*(yes-p)/sum(q$wt),q$cluster,reorder=FALSE);v<-numeric(nrow(frame));v[match(rownames(ss),frame$cluster)]<-ss[,1];V<-0;for(g in split(seq_len(nrow(frame)),frame$stratum))V<-V+length(g)/(length(g)-1)*sum((v[g]-mean(v[g]))^2);se<-100*sqrt(V);old$se_pct[i]<-se;if(old$n_reason_events[i]>=10){old$ci_low_pct[i]<-max(0,100*p-crit*se);old$ci_high_pct[i]<-min(100,100*p+crit*se)}}
write.csv(old,file,row.names=FALSE,na='');cat('Updated full-frame survey intervals for',nrow(old),'regional reason-share cells.\n')
)-----"
)

MODULES[["205_ethiopia_planning_survey_ci.R"]] <- list(
 language="R",
 packaged_sha256="1ddedff575bc5336d7f5862f49ac3eec99fe05e2aad8322c80bd7493f9343043",
 args=character(),
 code=r"-----(#!/usr/bin/env Rscript
# Survey-design inference for Ethiopia planning scenarios. All inputs are parameters.
# Positive PSU multiplier bootstrap within strata: normalized Gamma shape
# (n-2)/n has mean 1, variance 1 and covariance -1/(n-1), matching
# Rao-Wu rescaled PSU weights. Positive multipliers retain sparse landmark
# denominators rather than discarding non-estimable zero-weight replicates.
# Fixed population and growth assumptions; uncertainty includes IR sampling,
# current-use composition, empirical risks, fitted AFT parameters and pathways.
# AFT intervals condition on the previously selected distribution families.
root<-normalizePath(Sys.getenv('ETHIOPIA_PROJECT_ROOT'));out<-file.path(root,'output/survey_planning');dir.create(out,recursive=TRUE,showWarnings=FALSE)
B<-as.integer(Sys.getenv('ETHIOPIA_PLANNING_BOOTSTRAP_REPS','500'));cores<-4L
suppressPackageStartupMessages(library(survival))
ir<-readRDS(file.path(root,'Data/ET2024DHS__ETIR8ADT__IR_raw.rds'))
e_all<-readRDS(file.path(root,'Data/Derived/ethiopia_2024_specified_modern_method_episodes.rds'))
e<-read.csv(file.path(root,'output/Supporting_data/selected_reason_exploratory_episode_covariates.csv'))
e_all$method_group<-ifelse(e_all$method_code==3,'Injectables',ifelse(e_all$method_code==11,'Implants',ifelse(e_all$method_code==1,'Pill',ifelse(e_all$method_code==2,'IUD','Other modern'))))
cal<-readRDS(file.path(root,'Data/Derived/ethiopia_2024_calendar_events.rds'))
sup<-file.path(root,'output/Supporting_data')
script_file<-sub('^--file=','',grep('^--file=',commandArgs(FALSE),value=TRUE)[1])
signature<-unname(tools::md5sum(c(script_file,file.path(root,'Data/ET2024DHS__ETIR8ADT__IR_raw.rds'),file.path(root,'Data/Derived/ethiopia_2024_specified_modern_method_episodes.rds'),file.path(root,'Data/Derived/ethiopia_2024_calendar_events.rds'),file.path(sup,'ethiopia_planning_population.csv'),file.path(sup,'ethiopia_survival_model_duration_fit_PREVIEW.csv'),file.path(sup,'ethiopia_survival_model_cause_fit_PREVIEW.csv'))))
cache_signature<-file.path(out,'cache_signature.rds')
if(file.exists(cache_signature)){if(!identical(signature,readRDS(cache_signature)))stop('Inputs or code changed. Use a fresh output directory for bootstrap results.')}else{
 if(length(list.files(file.path(out,'replicates'))))stop('Unversioned bootstrap cache: use a fresh output directory.')
 saveRDS(signature,cache_signature)
}

pop<-read.csv(file.path(sup,'ethiopia_planning_population.csv'))
w25<-pop$women_15_49[pop$year==2025];w26<-pop$women_15_49[pop$year==2026]
w24<-pop$women_15_49[pop$year==2024]
methods<-c('Injectables','Implants','Pill','IUD','Other modern')
causes<-c('Method failure','Wanted more effective method','Changes in menstrual bleeding','Other side effects/health','Access/cost/convenience')
codes<-list(1L,7L,15L,c(4L,5L),c(6L,8L,10L)); action<-unlist(codes)
modern<-c(1L,2L,3L,5L,6L,7L,11L,13L,17L,18L)
endpoint_modern<-c(modern,14L,16L)
method_group<-function(x)ifelse(x==3,'Injectables',ifelse(x==11,'Implants',ifelse(x==1,'Pill',ifelse(x==2,'IUD','Other modern'))))
cause_group<-function(x){z<-rep(NA_integer_,length(x));for(j in 1:5)z[x %in% codes[[j]]]<-j;z}
wt<-as.numeric(ir$v005)/1e6;psu<-as.numeric(ir$v021);stratum<-as.numeric(ir$v022)
frame<-unique(data.frame(psu,stratum)); stopifnot(!anyDuplicated(frame$psu))
strata<-split(seq_len(nrow(frame)),frame$stratum);stopifnot(all(lengths(strata)>1))
psu_index<-match(psu,frame$psu)
u<-as.numeric(ir$v313)==3;umethod<-method_group(as.numeric(ir$v312));umethod[as.numeric(ir$v312)==16]<-'EC'
uindex<-which(u & as.numeric(ir$v312) %in% c(modern,14L))
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
ai_index<-lapply(methods,function(m)which(current$method==m & as.numeric(ir$v312[current$woman]) %in% modern));names(ai_index)<-methods
land_index<-lapply(methods,function(m)lapply(1:8,function(b)which(land$method==m & land$bin %in% if(b==8)c(6,7)else b)));names(land_index)<-methods
# Fit data and fixed selected families (model-selection uncertainty is not included).
af<-e_all[e_all$entry==0 & e_all$exposure>0 & e_all$method_code %in% modern,];af$method<-factor(af$method_group,levels=methods)
af$action_event<-as.integer(af$discontinued & af$reason_code %in% action)
af$other_event<-as.integer(af$discontinued & !af$reason_code %in% action)
for(j in 1:5)af[[paste0('cause',j)]]<-as.integer(af$discontinued & af$reason_code %in% codes[[j]])
fam<-read.csv(file.path(sup,'ethiopia_survival_model_duration_fit_PREVIEW.csv'));cfam<-read.csv(file.path(sup,'ethiopia_survival_model_cause_fit_PREVIEW.csv'))
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
 mcpr<-100*sum(iw[u])/sum(iw);mix<-round(100*vapply(c(methods,'EC'),function(m)sum(iw[u & umethod==m])/sum(iw[u]),0.0),4)/100
 stock<-w25*mcpr/100*mix
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
href<-read.csv(file.path(sup,'ethiopia_duration_aware_current_user_bridge.csv'));aref<-read.csv(file.path(sup,'ethiopia_aft_switching_by_method.csv'))
stopifnot(max(abs(rowSums(point$counts[2,,])-href$projected_actionable_original_method_endings[match(methods,href$method)]))<.1,
 max(abs(rowSums(point$counts[3,,])-aref$model_original_method_endings[match(methods,aref$method)])/pmax(1,aref$model_original_method_endings[match(methods,aref$method)]))<.02)
# The current-user duration mixture includes all recorded modern methods
# except EC, including the single other-modern code-14 current user.
cat('Point totals:',apply(point$counts,1,sum),'\n');flush.console()
checkpoint<-file.path(out,'replicates');dir.create(checkpoint,showWarnings=FALSE)
one<-function(b){dest<-file.path(checkpoint,sprintf('rep_%04d.rds',b));if(file.exists(dest))return(readRDS(dest));set.seed(20261105L+b)
 mult<-numeric(nrow(frame));for(ids in strata){n<-length(ids);g<-rgamma(n,shape=(n-2)/n);mult[ids]<-n*g/sum(g)}
 v<-tryCatch(measure(mult,b),error=function(e)list(error=conditionMessage(e)));saveRDS(v,dest);v}
if(B>0){draws<-parallel::mclapply(seq_len(B),one,mc.cores=cores,mc.preschedule=FALSE);valid<-!vapply(draws,function(x)!is.null(x$error),FALSE)
 cat('Valid',sum(valid),'of',B,'\n');stopifnot(mean(valid)>=.95);saveRDS(draws,file.path(out,'planning_replicates.rds'))}
saveRDS(list(wra2024=w24,wra2025=w25,wra2026=w26,psus=nrow(frame),strata=length(strata),replicates=B,methods=methods,causes=causes,definitions=c('Gross: every actionable original-method ending treated as year-end loss','Switching sensitivity: EC included in modern use at year end; support assessed on unique episodes','AFT uncertainty conditional on selected distribution families','Population and growth scenarios fixed')),file.path(out,'planning_metadata.rds'))
)-----"
)

MODULES[["206_summarize_planning.R"]] <- list(
 language="R",
 packaged_sha256="a2b9328ae101622860ff5c0a93abe29aad92291a8bb2caabb72ffafe99d9c26a",
 args=character(),
 code=r"-----(o<-file.path(Sys.getenv('ETHIOPIA_PROJECT_ROOT'),'output/survey_planning');p<-readRDS(file.path(o,'planning_point.rds'));d<-readRDS(file.path(o,'planning_replicates.rds'));meta<-readRDS(file.path(o,'planning_metadata.rds'))
metrics<-function(x){
 x$counts<-abind::abind(x$counts,x$counts[1,,,drop=FALSE]-x$counts[6,,,drop=FALSE],x$counts[2,,,drop=FALSE]-x$counts[4,,,drop=FALSE],x$counts[3,,,drop=FALSE]-x$counts[5,,,drop=FALSE],along=1)
 y<-c(stock_no_ec=sum(x$stock[meta$methods]),mcpr2024=x$mcpr,mcpr2025=x$mcpr,users2025=sum(x$stock),users2024=sum(x$users2024))
 for(m in c(meta$methods,'EC'))y[paste('stock',m,sep='|')]<-x$stock[m]
 for(i in 1:11)for(m in c(meta$methods,'Total'))for(c in c(meta$causes,'Total')){
  mi<-if(m=='Total')1:5 else match(m,meta$methods);ci<-if(c=='Total')1:5 else match(c,meta$causes)
  v<-sum(x$counts[i,mi,ci]);s<-if(m=='Total')sum(x$stock[meta$methods])else x$stock[m]
  key<-paste(i,m,c,sep='|');y[paste0('count|',key)]<-v;y[paste0('pp|',key)]<-100*v/meta$wra2026;y[paste0('risk|',key)]<-100*v/s
 }
 base<-x$mcpr+c(0,.8,.7)
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

MODULES[["207_duration_support_ci.R"]] <- list(
 language="R",
 packaged_sha256="f9640ae894ff8ea74cfa39ad89dae70c23a3d63f409348be5aa1001d53d1f6bf",
 args=character(),
 code=r"-----(root<-Sys.getenv('ETHIOPIA_PROJECT_ROOT');out<-file.path(root,'output/survey_planning');ir<-readRDS(file.path(root,'Data/ET2024DHS__ETIR8ADT__IR_raw.rds'));frame<-unique(data.frame(psu=as.numeric(ir$v021),stratum=as.numeric(ir$v022)));si<-match(as.numeric(ir$v021),frame$psu);groups<-split(seq_len(nrow(frame)),frame$stratum);w<-as.numeric(ir$v005)/1e6
m<-ifelse(ir$v312==3,'Injectables',ifelse(ir$v312==11,'Implants',ifelse(ir$v312==1,'Pill',ifelse(ir$v312==2,'IUD','Other modern'))));use<-ir$v313==3&ir$v312!=16;age<-as.numeric(ir$v337);methods<-c('Injectables','Implants','Pill','IUD','Other modern','Total')
calc<-function(mult)vapply(methods,function(j){z<-use&(j=='Total'|m==j);100*sum(w[z]*mult[si[z]]*(age[z]>60))/sum(w[z]*mult[si[z]])},0.0)
point<-calc(rep(1,nrow(frame)));d<-sapply(1:500,function(b){set.seed(20261105+b);mult<-numeric(nrow(frame));for(ids in groups){n<-length(ids);g<-rgamma(n,shape=(n-2)/n);mult[ids]<-n*g/sum(g)};calc(mult)})
r<-data.frame(key=paste0('duration61|',methods),estimate=point,lower=apply(d,1,quantile,.025),upper=apply(d,1,quantile,.975));old<-read.csv(file.path(out,'planning_intervals.csv'));old<-old[!grepl('^duration61[|]',old$key),];write.csv(rbind(old,r),file.path(out,'planning_intervals.csv'),row.names=FALSE)
)-----"
)

MODULES[["208_pooled_risk_ci.R"]] <- list(
 language="R",
 packaged_sha256="74f85ef6ffa2568b3832652e7b4585d2f7be06e178bbf14464ccd31ee973a67a",
 args=character(),
 code=r"-----(root<-Sys.getenv('ETHIOPIA_PROJECT_ROOT');out<-file.path(root,'output/survey_planning');ir<-readRDS(file.path(root,'Data/ET2024DHS__ETIR8ADT__IR_raw.rds'));e<-read.csv(file.path(root,'output/Supporting_data/selected_reason_exploratory_episode_covariates.csv'));frame<-unique(data.frame(psu=as.numeric(ir$v021),stratum=as.numeric(ir$v022)));ix<-match(as.numeric(ir$v021[e$woman_row]),frame$psu);groups<-split(seq_len(nrow(frame)),frame$stratum);codes<-list(1,7,15,c(4,5),c(6,8,10));causes<-c('Method failure','Wanted more effective method','Changes in menstrual bleeding','Other side effects/health','Access/cost/convenience')
calc<-function(mult){w<-e$wt*mult[ix];S<-1;F<-numeric(5);for(t in 1:12){at<-e$entry<t&e$exposure>=t;end<-at&e$discontinued&e$exposure==t;den<-sum(w[at]);F<-F+S*vapply(codes,function(cc)sum(w[end&e$reason_code%in%cc])/den,0.0);S<-S*(1-sum(w[end])/den)};100*F}
p<-calc(rep(1,nrow(frame)));d<-sapply(1:500,function(b){set.seed(20261105+b);mult<-numeric(nrow(frame));for(ids in groups){n<-length(ids);g<-rgamma(n,shape=(n-2)/n);mult[ids]<-n*g/sum(g)};calc(mult)});dp<-rbind(d,colSums(d));pp<-c(p,sum(p));ds<-100*sweep(d,2,colSums(d),'/');point<-100*p/sum(p)
r<-data.frame(key=c(paste0('pooled_firstyear|',c(causes,'Total')),paste0('pooled_share|',causes)),estimate=c(pp,point),lower=c(apply(dp,1,quantile,.025),apply(ds,1,quantile,.025)),upper=c(apply(dp,1,quantile,.975),apply(ds,1,quantile,.975)));old<-read.csv(file.path(out,'planning_intervals.csv'));old<-old[!grepl('^pooled_',old$key),];write.csv(rbind(old,r),file.path(out,'planning_intervals.csv'),row.names=FALSE)
)-----"
)

MODULES[["209_finalize_regional_inference.R"]] <- list(
 language="R",
 packaged_sha256="19dd59ad48bb70e4f043774ff58efaa11c65b6da67f3fe9e01de49ea961b2896",
 args=character(),
 code=r"-----(# Synchronize completed full-frame bootstrap draws with the existing report
# summaries. It never changes cohort or model specifications.
root<-Sys.getenv('ETHIOPIA_PROJECT_ROOT');s<-file.path(root,'output/Supporting_data')
a<-read.csv(file.path(s,'regional_actionable_adjusted_bootstrap.csv'),check.names=FALSE);stopifnot(nrow(a)>=500)
full<-a[,c('replicate',grep('^full::',names(a),value=TRUE)),drop=FALSE];write.csv(full,file.path(s,'regional_actionable_full_model_pairwise_bootstrap.csv'),row.names=FALSE)
p<-read.csv(file.path(s,'regional_actionable_first_model_point_estimates.csv'));r<-read.csv(file.path(root,'output/updated_regional_retained_reason_rates.csv'));i<-match(p$region,r$region);p$unadjusted_ci_low<-r$ci_low[i];p$unadjusted_ci_high<-r$ci_high[i];write.csv(p,file.path(s,'regional_actionable_first_model_point_estimates.csv'),row.names=FALSE)
source(file.path(root,'Code/120_relevel_regional_actionable_models.R'))
source(file.path(root,'Code/119_regional_actionable_design_pvalues.R'))
source(file.path(root,'Code/131_summarize_regional_actionable_pairwise_tests.R'))
)-----"
)

EXTERNAL_INPUTS[["output/Supporting_data/ethiopia_planning_population.csv"]] <- r"-----(year,women_15_49
2024,34057556
2025,34057556
2026,35016171
)-----"


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


MODULES[["210_prepare_analysis_inputs.R"]] <- list(language="R", packaged_sha256="ca9d607b0f797cd62a5402c77264a52ae6bb4f72d3f1cdae13654d67e53306ae", args=character(), code=r"-----(#!/usr/bin/env Rscript
# Data preparation only; no regression fitting or bootstrap is run.
project<-Sys.getenv('ETHIOPIA_PROJECT_ROOT');stopifnot(nzchar(project))
derived<-file.path(project,'Data','Derived');prefix<-'ethiopia'

# Reuse the original initiation-cohort preparation unchanged.
local({

# Full DHS sampling frame, including PSUs with no eligible outcome records.
full_survey_frame <- function(){
 r<-Sys.getenv('ETHIOPIA_PROJECT_ROOT'); stopifnot(nzchar(r))
 x<-readRDS(file.path(r,'Data/ET2024DHS__ETIR8ADT__IR_raw.rds'))
 unique(data.frame(cluster=paste(as.integer(x$v022),as.integer(x$v021),sep=':'),stratum=as.integer(x$v022)))
}
complete_survey_data <- function(d){
 r<-Sys.getenv('ETHIOPIA_PROJECT_ROOT');x<-readRDS(file.path(r,'Data/ET2024DHS__ETIR8ADT__IR_raw.rds'))
 f<-unique(data.frame(v021=as.integer(x$v021),v022=as.integer(x$v022)))
 key<-function(a,b)paste(a,b,sep=':');miss<-f[!key(f$v021,f$v022)%in%key(d$v021,d$v022),]
 if(nrow(miss)){z<-d[rep(1L,nrow(miss)),,drop=FALSE];z$v021<-miss$v021;z$v022<-miss$v022;z$wt<-0;d<-rbind(d,z)}
 d
}
#!/usr/bin/env Rscript
# Ethiopia DHS 2024-25: distribution of observed modern-method initiations.
#
# Universe: contraceptive episodes whose start is observed 3-62 months before
# the woman's interview. Episodes already underway when the recorded calendar
# begins and episodes entering the discontinuation window through delayed entry
# are not initiation events in this period.
# Input lineage: 00_import_ir_dta.R reads the original one-woman-per-row
# ETIR8AFL.dta into an unchanged RDS; ethiopia_modern_method_discontinuation.R
# converts each woman's 80-character calendar to one row per continuous run.
# This script starts from those RUNS, not from a woman-month long file.
#
# Point estimates use v005/1,000,000. Standard errors and 95% confidence
# intervals use Taylor linearization with DHS sampling strata v022 and PSUs
# v021. Women may contribute multiple starts; all their records remain within
# the same PSU, so the PSU-robust design preserves within-woman dependence.

options(stringsAsFactors = FALSE)
options(survey.lonely.psu = "adjust")

required_packages <- c("survey", "ggplot2")
# survey estimates weighted shares and design-based uncertainty from DHS PSU
# and stratum identifiers; ggplot2 writes the figures. Only missing CRAN
# software is downloaded here; the restricted DHS .dta remains local.
missing_packages <- setdiff(required_packages, rownames(installed.packages()))
if (length(missing_packages)) {
  install.packages(missing_packages, repos = "https://cloud.r-project.org")
}
invisible(lapply(required_packages, library, character.only = TRUE))

project <- Sys.getenv("ETHIOPIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
output_dir <- file.path(project, "output")
asset_dir <- file.path(output_dir, "assets")
dir.create(asset_dir, recursive = TRUE, showWarnings = FALSE)

ir <- readRDS(file.path(project, "Data", "ET2024DHS__ETIR8ADT__IR_raw.rds"))
calendar_events <- readRDS(file.path(project, "Data", "Derived", "ethiopia_2024_calendar_events.rds"))

# DHS calendar method codes retained as modern methods for this analysis.
# Male condom (code 5) is part of Other modern methods.
method_codes <- list(
  "Injectables" = 3L,
  "Implants" = 11L,
  "Pill" = 1L,
  "Emergency contraception" = 16L,
  "Other modern methods" = c(2L, 5L, 6L, 7L, 13L, 17L, 18L)
)
method_levels <- names(method_codes)
modern_codes <- unlist(method_codes, use.names = FALSE)

# Select observed episode starts in the same 3-62 month period used by the DHS
# discontinuation table. start != calendar_start excludes left-censored runs
# whose actual initiation occurred before the recorded calendar.
starts <- calendar_events[
  calendar_events$method_code %in% modern_codes &
    calendar_events$start != calendar_events$calendar_start,
]
starts$months_before_interview <- starts$interview - starts$start
starts <- starts[
  starts$months_before_interview >= 3L &
    starts$months_before_interview <= 62L,
]
# Exclude EC later in the dedicated presentation view (script 18). At this
# point, this base initiation cohort includes EC for DHS coding comparison.

starts$method_group <- NA_character_
for (m in method_levels) {
  starts$method_group[starts$method_code %in% method_codes[[m]]] <- m
}
stopifnot(!anyNA(starts$method_group), nrow(starts) == 7859L)
starts$method_group <- factor(starts$method_group, levels = method_levels)

# Convert DHS Century Month Code to Gregorian calendar year and month.
starts$calendar_year <- 1900L + (starts$start - 1L) %/% 12L
starts$calendar_month <- 1L + (starts$start - 1L) %% 12L

# Attach design variables from the woman-level IR record. woman_row is retained
# when the calendar event file is created, avoiding a many-to-many merge.
starts$v021 <- ir$v021[starts$woman_row]
starts$v022 <- ir$v022[starts$woman_row]
stopifnot(!anyNA(starts$v021), !anyNA(starts$v022))


saveRDS(starts,file.path(project,'Data/Derived/ethiopia_2024_modern_method_starts.rds'))
})

# Reuse the original recorded-reason preparation and published checks.
local({

# Full DHS sampling frame, including PSUs with no eligible outcome records.
full_survey_frame <- function(){
 r<-Sys.getenv('ETHIOPIA_PROJECT_ROOT'); stopifnot(nzchar(r))
 x<-readRDS(file.path(r,'Data/ET2024DHS__ETIR8ADT__IR_raw.rds'))
 unique(data.frame(cluster=paste(as.integer(x$v022),as.integer(x$v021),sep=':'),stratum=as.integer(x$v022)))
}
complete_survey_data <- function(d){
 r<-Sys.getenv('ETHIOPIA_PROJECT_ROOT');x<-readRDS(file.path(r,'Data/ET2024DHS__ETIR8ADT__IR_raw.rds'))
 f<-unique(data.frame(v021=as.integer(x$v021),v022=as.integer(x$v022)))
 key<-function(a,b)paste(a,b,sep=':');miss<-f[!key(f$v021,f$v022)%in%key(d$v021,d$v022),]
 if(nrow(miss)){z<-d[rep(1L,nrow(miss)),,drop=FALSE];z$v021<-miss$v021;z$v022<-miss$v022;z$wt<-0;d<-rbind(d,z)}
 d
}
#!/usr/bin/env Rscript
# Ethiopia DHS 2024-25 Table 7.12: reasons for discontinuation.
#
# Table 7.12 is a weighted percent distribution of recorded discontinuation
# events, not a life table. Following the DHS tabulation program, calendar
# positions v018 through v018+59 are inspected and each nonblank vcal_2 reason
# is classified with the method recorded in vcal_1 in that same month.

options(stringsAsFactors = FALSE)
options(survey.lonely.psu = "adjust")
required_packages <- c("survey", "jsonlite", "ggplot2")
missing_packages <- setdiff(required_packages, rownames(installed.packages()))
if (length(missing_packages)) install.packages(missing_packages, repos = "https://cloud.r-project.org")
invisible(lapply(required_packages, library, character.only = TRUE))

project <- Sys.getenv("ETHIOPIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
output_dir <- file.path(project, "output")
derived_dir <- file.path(project, "Data", "Derived")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
asset_dir <- file.path(output_dir, "assets")
dir.create(asset_dir, recursive = TRUE, showWarnings = FALSE)

ir <- readRDS(file.path(project, "Data", "ET2024DHS__ETIR8ADT__IR_raw.rds"))
ir_v018 <- as.numeric(unclass(ir$v018))
ir_v005 <- as.numeric(unclass(ir$v005))
ir_v021 <- as.numeric(unclass(ir$v021))
ir_v022 <- as.numeric(unclass(ir$v022))
method_characters <- strsplit("123456789WNALCFEMS~", "")[[1]]

# Mapping follows the DHS CSPro Table 7.14/2024-25 Ethiopia Table 7.12 code.
reason_character_map <- c(
  "1"=1L, "2"=2L, "3"=3L, "7"=4L, "M"=5L,
  "4"=6L, "6"=7L, "C"=8L, "8"=9L, "F"=10L,
  "A"=11L, "9"=12L, "D"=13L, "W"=14L, "K"=15L, "?"=99L
)
reason_labels <- c(
  "Became pregnant while using",
  "Wanted to become pregnant",
  "Husband/partner disapproved",
  "Wanted a more effective method",
  "Changes in menstrual bleeding",
  "Other side effects/health concerns",
  "Lack of access/too far",
  "Cost too much",
  "Inconvenient to use",
  "Up to God/fatalistic",
  "Difficult to get pregnant/menopausal",
  "Infrequent sex/husband away",
  "Marital dissolution/separation",
  "Other",
  "Don't know"
)

# Extract the discontinuation events exactly as the published tabulation does.
event_list <- vector("list", nrow(ir))
for (i in seq_len(nrow(ir))) {
  positions <- as.integer(ir_v018[i]) + 0:59
  reason_chars <- substring(sprintf("%-80s", ir$vcal_2[i]), positions, positions)
  keep <- reason_chars != " "
  if (any(keep)) {
    method_chars <- substring(ir$vcal_1[i], positions[keep], positions[keep])
    event_list[[i]] <- data.frame(
      woman_row = i,
      caseid = ir$caseid[i],
      calendar_position = positions[keep],
      method_code = match(method_chars, method_characters),
      reason_code = unname(reason_character_map[reason_chars[keep]]),
      wt = ir_v005[i] / 1e6,
      v021 = ir_v021[i],
      v022 = ir_v022[i]
    )
  }
}
events <- do.call(rbind, event_list)
events <- events[!is.na(events$method_code) & events$reason_code %in% 1:15,]
stopifnot(nrow(events) == 6685L, !anyNA(events$reason_code))
events$reason <- factor(events$reason_code, levels = 1:15, labels = reason_labels)

# Reproduce the method columns printed in the report before regrouping them.
published_method <- function(code) {
  ifelse(code == 2, "IUD",
  ifelse(code == 3, "Injectables",
  ifelse(code == 11, "Implants",
  ifelse(code == 1, "Pill",
  ifelse(code == 5, "Male condom",
  ifelse(code == 16, "Emergency contraception",
  ifelse(code == 8, "Rhythm",
  ifelse(code == 9, "Withdrawal", "Other"))))))))
}
events$published_method <- published_method(events$method_code)
published_methods <- c("IUD", "Injectables", "Implants", "Pill", "Male condom",
                       "Emergency contraception", "Rhythm", "Withdrawal", "Other", "All methods")

weighted_distribution <- function(data) {
  totals <- vapply(1:15, function(k) sum(data$wt[data$reason_code == k]), numeric(1))
  100 * totals / sum(totals)
}
published_calculated <- sapply(published_methods, function(m) {
  z <- if (m == "All methods") events else events[events$published_method == m,]
  weighted_distribution(z)
})
rownames(published_calculated) <- reason_labels
published_counts <- vapply(published_methods, function(m) {
  z <- if (m == "All methods") events else events[events$published_method == m,]
  sum(z$wt)
}, numeric(1))

# Published values transcribed from Ethiopia DHS 2024-25 Table 7.12.
published_reference <- cbind(
  "IUD" = c(0,50.5,0,17.8,14.7,3.1,.4,.2,6.5,1.3,3.3,1.1,.1,.9,0),
  "Injectables" = c(2.1,50.4,.7,11.5,6.7,6.2,3.5,.3,5.6,2.2,.5,6.3,1.7,2.1,.2),
  "Implants" = c(.9,49.3,.2,14.9,4.1,11.8,.9,.2,9.7,.6,.4,2.8,.9,2.9,.5),
  "Pill" = c(6.2,28.8,2.5,22.9,3.3,2.6,.7,.3,7.7,2.4,1,17.5,1.8,1,1.4),
  "Male condom" = c(0,20.2,2.7,6.8,1.1,1.5,.9,0,4.3,8.9,0,51.8,0,0,1.9),
  "Emergency contraception" = c(1,9.2,0,7.1,4.9,8,.6,0,3.5,3.2,0,56,5.8,.4,.2),
  "Rhythm" = c(10.4,48.9,0,13.1,1,.1,0,0,2.5,.7,.5,17.2,5.4,.2,0),
  "Withdrawal" = c(2.2,36.4,0,6.3,0,0,0,0,1.4,0,2.9,21.8,8.1,21.1,0),
  "Other" = c(2.5,29.6,0,46.7,.1,6.7,0,0,0,8.7,0,0,.1,5.3,.4),
  "All methods" = c(2.3,46.7,.8,13.7,5.7,6.9,2.4,.3,6.5,1.9,.6,8.1,1.6,2.1,.4)
)
rownames(published_reference) <- reason_labels
percentage_match <- round(published_calculated, 1) == published_reference
# The released file reproduces all 135 method-specific cells and 149/150 cells
# overall. The report shows 2.4 for all-method lack of access versus 2.5 from
# the released data, alongside the injectable count discrepancy documented below.
stopifnot(sum(percentage_match) == 149L,
          round(published_calculated["Lack of access/too far", "All methods"], 1) == 2.5)

report_counts <- c(118,4689,1654,777,32,175,122,25,64,7656)
names(report_counts) <- published_methods
# All published counts except Injectables and the resulting All-methods total
# match the released file. Their reason percentages nevertheless match exactly.
stopifnot(all(round(published_counts[-c(2,10)]) == report_counts[-c(2,10)]))

# Requested modern-method grouping, consistent with the other project tables.
modern_method_codes <- list(
  "Injectables" = 3L,
  "Implants" = 11L,
  "Pill" = 1L,
  "Emergency contraception" = 16L,
  "Other modern methods" = c(2L,5L,6L,7L,13L,17L,18L)
)
modern_codes <- unlist(modern_method_codes, use.names = FALSE)
modern <- events[events$method_code %in% modern_codes,]
modern$method_group <- NA_character_
for (m in names(modern_method_codes)) {
  modern$method_group[modern$method_code %in% modern_method_codes[[m]]] <- m
}
modern_methods <- c(names(modern_method_codes), "All specified modern methods")
stopifnot(!anyNA(modern$method_group))

modern_table <- sapply(modern_methods, function(m) {
  z <- if (m == "All specified modern methods") modern else modern[modern$method_group == m,]
  weighted_distribution(z)
})
rownames(modern_table) <- reason_labels
modern_counts <- vapply(modern_methods, function(m) {
  z <- if (m == "All specified modern methods") modern else modern[modern$method_group == m,]
  sum(z$wt)
}, numeric(1))
modern_unweighted <- vapply(modern_methods, function(m) {
  z <- if (m == "All specified modern methods") modern else modern[modern$method_group == m,]
  nrow(z)
}, integer(1))
stopifnot(all(abs(colSums(modern_table) - 100) < 1e-8))

# Aggregate the 15 detailed Table 7.12 reasons into the nine reason categories
# used in the Table 7.11 life-table analysis.
aggregated_reason_labels <- c(
  "Method failure",
  "Desire to become pregnant",
  "Other fertility-related reasons",
  "Changes in menstrual bleeding",
  "Other side effects/health concerns",
  "Wanted a more effective method",
  "Access, cost, or inconvenience",
  "Husband/partner disapproved",
  "Other reasons"
)
reason_to_aggregate <- c(
  1L, # Became pregnant while using
  2L, # Wanted to become pregnant
  8L, # Husband/partner disapproved
  6L, # Wanted a more effective method
  4L, # Changes in menstrual bleeding
  5L, # Other side effects/health concerns
  7L, # Lack of access/too far
  7L, # Cost too much
  7L, # Inconvenient to use
  9L, # Up to God/fatalistic
  3L, # Difficult to get pregnant/menopausal
  3L, # Infrequent sex/husband away
  3L, # Marital dissolution/separation
  9L, # Other
  9L  # Don't know
)
modern$aggregated_reason_code <- reason_to_aggregate[modern$reason_code]
aggregated_distribution <- function(data) {
  totals <- vapply(1:9, function(k) sum(data$wt[data$aggregated_reason_code == k]), numeric(1))
  100 * totals / sum(totals)
}
aggregated_table <- sapply(modern_methods, function(m) {
  z <- if (m == "All specified modern methods") modern else modern[modern$method_group == m,]
  aggregated_distribution(z)
})
rownames(aggregated_table) <- aggregated_reason_labels
stopifnot(all(abs(colSums(aggregated_table) - 100) < 1e-8))
aggregate_rank <- order(aggregated_table[,"All specified modern methods"], decreasing = TRUE)
aggregated_table_ranked <- aggregated_table[aggregate_rank,,drop = FALSE]

# Design-based uncertainty for the adapted table. Point estimates remain the
# same weighted column percentages used in the published report.
modern$method_group <- factor(modern$method_group, levels = names(modern_method_codes))

saveRDS(modern,file.path(project,'Data/Derived/ethiopia_2024_modern_method_discontinuations_5yr.rds'))
})

# Preserve the existing legacy covariate file expected by downstream modules.
local({

# Full DHS sampling frame, including PSUs with no eligible outcome records.
full_survey_frame <- function(){
 r<-Sys.getenv('ETHIOPIA_PROJECT_ROOT'); stopifnot(nzchar(r))
 x<-readRDS(file.path(r,'Data/ET2024DHS__ETIR8ADT__IR_raw.rds'))
 unique(data.frame(cluster=paste(as.integer(x$v022),as.integer(x$v021),sep=':'),stratum=as.integer(x$v022)))
}
complete_survey_data <- function(d){
 r<-Sys.getenv('ETHIOPIA_PROJECT_ROOT');x<-readRDS(file.path(r,'Data/ET2024DHS__ETIR8ADT__IR_raw.rds'))
 f<-unique(data.frame(v021=as.integer(x$v021),v022=as.integer(x$v022)))
 key<-function(a,b)paste(a,b,sep=':');miss<-f[!key(f$v021,f$v022)%in%key(d$v021,d$v022),]
 if(nrow(miss)){z<-d[rep(1L,nrow(miss)),,drop=FALSE];z$v021<-miss$v021;z$v022<-miss$v022;z$wt<-0;d<-rbind(d,z)}
 d
}
#!/usr/bin/env Rscript
# Exploratory 12-month selected-reason discontinuation life tables by subgroup.
# The outcome is ending an original modern method for any recorded reason
# except wanted pregnancy or husband/partner disapproval. Those two endings
# remain competing events in each monthly risk set. EC is excluded.
#
# Start with the validated episode-level .rds reconstructed from the IR
# calendar. Link the woman-level IR file with woman_row. Compute age and live
# birth parity at episode start. Marital status, education, wealth and
# residence are observed at interview, possibly after an episode ended; their
# descriptive associations are therefore not historical causal exposures.
# Output one-way design-bootstrap intervals and screened two-way estimates.

project <- Sys.getenv("ETHIOPIA_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
out <- file.path(project,"output","Supporting_data")
e <- readRDS(file.path(project,"Data/Derived/ethiopia_2024_table_7_11_episodes.rds"))
ir <- readRDS(file.path(project,"Data/ET2024DHS__ETIR8ADT__IR_raw.rds"))
e <- e[e$method_code%in%c(1L,2L,3L,5L,6L,7L,11L,13L,17L,18L),]
i <- e$woman_row
age <- floor((e$start-as.integer(ir$v011[i]))/12)
birth_cols <- grep("^b3_",names(ir),value=TRUE)
births <- as.matrix(ir[i,birth_cols])
parity <- rowSums(!is.na(births) & births<=e$start)
marital <- as.integer(ir$v501[i])
education <- as.integer(ir$v106[i])
wealth <- as.integer(ir$v190[i])
residence <- as.integer(ir$v025[i])
region <- as.integer(ir$v024[i])
psu <- as.integer(ir$v021[i])
stratum <- as.integer(ir$v022[i])
complete <- !is.na(age)&age>=15&age<=49&!is.na(parity)&
  !is.na(marital)&marital%in%0:5&
  !is.na(education)&education%in%0:3&
  !is.na(wealth)&wealth%in%1:5&
  !is.na(residence)&residence%in%1:2&
  !is.na(region)&!is.na(psu)&!is.na(stratum)
e <- e[complete,]
age <- age[complete];parity <- parity[complete];marital <- marital[complete]
education <- education[complete];wealth <- wealth[complete]
residence <- residence[complete];region <- region[complete]
psu <- psu[complete];stratum <- stratum[complete]
stopifnot(nrow(e)==8611L)

e$method_group <- factor(ifelse(e$method_code==3L,"Injectables",
  ifelse(e$method_code==11L,"Implants",ifelse(e$method_code==1L,"Pill",
  ifelse(e$method_code==2L,"IUD","Other modern")))),
  levels=c("Injectables","Implants","Pill","IUD","Other modern"))
e$age_group <- cut(age,c(14,19,24,34,49),labels=c("15-19","20-24","25-34","35-49"))
e$parity_group <- factor(ifelse(parity==0,"0",ifelse(parity<=2,"1-2",
  ifelse(parity==3,"3","4+"))),levels=c("0","1-2","3","4+"))
e$marital_group <- factor(ifelse(marital==0,"Never in union",
  ifelse(marital%in%c(1L,2L),"Married/living together","Formerly in union")),
  levels=c("Never in union","Married/living together","Formerly in union"))
e$education <- factor(ifelse(education==0,"None",ifelse(education==1,"Primary","Secondary+")),
  levels=c("None","Primary","Secondary+"))
e$wealth_group <- factor(ifelse(wealth<=2,"Poorest 40%",ifelse(wealth==3,"Middle 20%","Richest 40%")),
  levels=c("Poorest 40%","Middle 20%","Richest 40%"))
e$residence <- factor(ifelse(residence==1,"Urban","Rural"),levels=c("Rural","Urban"))
e$cluster <- paste(stratum,psu,sep=":")
e$stratum <- stratum
e$selected_event <- e$discontinued & !(e$reason%in%c(2L,8L)) &
  e$exposure<=12L & e$entry<e$exposure

write.csv(e,file.path(out,'selected_reason_exploratory_episode_covariates.csv'),row.names=FALSE)
# Full/main model categories are saved separately; no legacy definitions change.
i<-e$woman_row
births<-as.matrix(ir[i,grep('^b3_',names(ir),value=TRUE)])
p<-rowSums(!is.na(births)&births<=e$start);m<-as.integer(ir$v501[i]);wealth<-as.integer(ir$v190[i])
e$parity_group<-factor(ifelse(p==0,'0',ifelse(p<=2,'1–2',ifelse(p<=4,'3–4','5+'))),levels=c('0','1–2','3–4','5+'))
e$marital_group<-factor(ifelse(m==0,'Never in union',ifelse(m==2,'Living together',ifelse(m==1,'Married','Divorced/widowed/separated'))),levels=c('Never in union','Living together','Married','Divorced/widowed/separated'))
e$wealth_group<-factor(c('Poorest','Poorer','Middle','Richer','Richest')[wealth],levels=c('Poorest','Poorer','Middle','Richer','Richest'))
e$start_year<-factor((e$start-1L)%/%12L+1900L)
saveRDS(e,file.path(project,'Data/Derived/ethiopia_2024_full_model_episode_covariates.rds'))
n<-pmin(12L,e$exposure)-e$entry;ix<-rep(seq_len(nrow(e)),n)
month<-unlist(Map(function(entry,n)seq.int(entry+1L,length.out=n),e$entry,n),use.names=FALSE)
person<-e[ix,c('wt','method_group','age_group','parity_group','marital_group','education','wealth_group','residence','region','start_year','cluster','stratum')]
person$month<-factor(month,levels=1:12)
ended<-e$discontinued[ix]&month==e$exposure[ix]
person$outcome<-factor(ifelse(!ended,'continue',ifelse(e$reason_code[ix]%in%c(1L,4L,5L,6L,7L,8L,10L,15L),'actionable','competing')),levels=c('continue','actionable','competing'))
stopifnot(nrow(e)==8611L,nrow(person)==70691L,sum(person$outcome=='actionable')==1321L)
saveRDS(person,file.path(project,'Data/Derived/ethiopia_2024_person_month.rds'))
})
ir<-readRDS(file.path(project,'Data/ET2024DHS__ETIR8ADT__IR_raw.rds'))

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
      "annual_change_pp": -0.8952185369339283
    },
    {
      "scenario": "9-year DHS trend",
      "annual_change_pp": -0.2412568024003963
    },
    {
      "scenario": "FPET-informed growth",
      "annual_change_pp": 0.7
    }
  ],
  "rates_from": {
    "dhs2016": 24.9,
    "dhs2019": 28.1,
    "dhs2025": 22.72868877839643,
    "fpet2024": 31,
    "fpet2025": 31.7
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
    "title": "First-year: common mCPR growth assumptions",
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
    "title": "First-year: status quo by method",
    "kind": "method_scenario",
    "approach": 1,
    "scenario": 1
  },
  {
    "title": "First-year: illustrative +0.8 pp by method",
    "kind": "method_scenario",
    "approach": 1,
    "scenario": 2
  },
  {
    "title": "First-year: illustrative +0.7 pp by method",
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
    "title": "Historical duration-aware: common mCPR growth assumptions",
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
    "title": "Historical duration-aware: status quo by method",
    "kind": "method_scenario",
    "approach": 2,
    "scenario": 1
  },
  {
    "title": "Historical duration-aware: illustrative +0.8 pp by method",
    "kind": "method_scenario",
    "approach": 2,
    "scenario": 2
  },
  {
    "title": "Historical duration-aware: illustrative +0.7 pp by method",
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
    "title": "AFT survival: common mCPR growth assumptions",
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
    "title": "AFT survival: status quo by method",
    "kind": "method_scenario",
    "approach": 3,
    "scenario": 1
  },
  {
    "title": "AFT survival: illustrative +0.8 pp by method",
    "kind": "method_scenario",
    "approach": 3,
    "scenario": 2
  },
  {
    "title": "AFT survival: illustrative +0.7 pp by method",
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
    "title": "Historical sensitivity: common mCPR growth assumptions",
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
    "title": "Historical sensitivity: status quo by method",
    "kind": "method_scenario",
    "approach": 4,
    "scenario": 1
  },
  {
    "title": "Historical sensitivity: illustrative +0.8 pp by method",
    "kind": "method_scenario",
    "approach": 4,
    "scenario": 2
  },
  {
    "title": "Historical sensitivity: illustrative +0.7 pp by method",
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
    "title": "AFT sensitivity: common mCPR growth assumptions",
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
    "title": "AFT sensitivity: status quo by method",
    "kind": "method_scenario",
    "approach": 5,
    "scenario": 1
  },
  {
    "title": "AFT sensitivity: illustrative +0.8 pp by method",
    "kind": "method_scenario",
    "approach": 5,
    "scenario": 2
  },
  {
    "title": "AFT sensitivity: illustrative +0.7 pp by method",
    "kind": "method_scenario",
    "approach": 5,
    "scenario": 3
  },
  {
    "title": "AFT sensitivity: mCPR equivalent by cause",
    "kind": "cause_pp",
    "approach": 5,
    "scenario": null
  },
  {
    "title": "Sensitivity: how the year-end mCPR equivalent changes"
  }
])--------"
REVISION_HELPERS <- list(
  "300_revised_planning.R" = r"--------(#!/usr/bin/env Rscript
# Usage: Rscript compute_scenarios.R SAVED_STATISTICS_DIR DHS_ESTIMATES_CSV OUTPUT_DIR
# Reuses existing aggregate point estimates and survey bootstrap draws. No models
# are refit and no original analysis inputs, user counts or risks are modified.
suppressPackageStartupMessages(library(jsonlite))
a<-commandArgs(trailingOnly=TRUE);stopifnot(length(a)==3)
stats<-a[1];dhsfile<-a[2];outdir<-a[3]
dir.create(outdir,recursive=TRUE,showWarnings=FALSE)
meta<-fromJSON(file.path(stats,"metadata.json"))
old<-read.csv(file.path(stats,"planning_intervals.csv"),check.names=FALSE)
point<-readRDS(file.path(stats,"planning_point.rds"))
reps<-readRDS(file.path(stats,"planning_replicates.rds"))
verified<-fromJSON(dhsfile)
p<-c('2025'=point$mcpr,'2019'=verified$rates_from$dhs2019,'2016'=verified$rates_from$dhs2016)
rates<-c((point$mcpr-round(p['2019'],1))/6,(point$mcpr-round(p['2016'],1))/9,verified$rates_from$fpet2025-verified$rates_from$fpet2024)
names(rates)<-NULL
labels<-c("6-year DHS trend","9-year DHS trend","FPET-informed growth")
get_updates<-function(x){
 v<-numeric();put<-function(k,z)v[k]<<-unname(z)
 put("without_direct|1",sum(x$counts[1,,])-sum(x$counts[6,,]))
 for(j in 1:3){
  p25<-x$mcpr;p26<-x$mcpr+rates[j]
  put(paste0("projectedmcpr2025|",j),p25)
  put(paste0("projectedusers2025|",j),p25/100*meta$wra2025)
  put(paste0("base|",j),p26)
  put(paste0("baseusers|",j),p26/100*meta$wra2026)
  for(ap in seq_len(dim(x$counts)[1]))for(m in c(meta$methods,"EC","Total")){
   share<-if(m=="Total")1 else x$mix[m]
   retained<-if(m=="Total")sum(x$counts[ap,,]) else if(m=="EC")0 else sum(x$counts[ap,m,])
   usual<-p26/100*meta$wra2026*share
   key<-paste(j,ap,m,sep="|")
   put(paste0("usualusers|",key),usual)
   put(paste0("usualmcpr|",key),p26*share)
   put(paste0("retainedusers|",key),usual+retained)
   put(paste0("retainedmcpr|",key),100*(usual+retained)/meta$wra2026)
  }
 }
 v
}
vp<-get_updates(point)
vr<-vapply(reps,get_updates,numeric(length(vp)))
rownames(vr)<-names(vp)
ci<-t(apply(vr,1,quantile,c(.025,.975),na.rm=TRUE))
updated<-data.frame(key=names(vp),estimate=as.numeric(vp),lower=ci[,1],upper=ci[,2],row.names=NULL)
result<-rbind(old[!old$key%in%updated$key,],updated)
fixed<-grepl("^(count|pp|risk|stock)[|]|^stock_no_ec$|^users2025$|^mcpr2025$",old$key)
before<-old[fixed,];after<-result[match(old$key[fixed],result$key),]
rownames(before)<-NULL;rownames(after)<-NULL
stopifnot(identical(before,after))
write.csv(result,file.path(outdir,"revised_planning_intervals.csv"),row.names=FALSE)
summary<-data.frame(scenario=labels,annual_change_pp=rates,
 mcpr2025=point$mcpr,mcpr2026=point$mcpr+rates,
 users2025=point$mcpr/100*meta$wra2025,
 users2026=(point$mcpr+rates)/100*meta$wra2026)
write.csv(summary,file.path(outdir,"scenario_summary.csv"),row.names=FALSE)
write_json(list(scenarios=summary,wra2024=meta$wra2024,wra2025=meta$wra2025,
 wra2026=meta$wra2026,methods=meta$methods,causes=meta$causes,
 reference_mcpr2025=point$mcpr,reference_users2025=sum(point$stock),
 reference_stock=as.list(point$stock),replicates=length(reps),
 fixed_retention_totals=sapply(seq_len(dim(point$counts)[1]),function(ap)sum(point$counts[ap,,])),
 rates_from=list(dhs2016=round(p["2016"],1),dhs2019=round(p["2019"],1),dhs2025=point$mcpr,
 fpet2024=31.0,fpet2025=31.7)),
 file.path(outdir,"revision_inputs.json"),auto_unbox=TRUE,pretty=TRUE,digits=15)
cat("Preserved",sum(fixed),"retention/risk/reference-user statistics and",length(reps),"bootstrap replicates.\n")
print(summary,row.names=FALSE)
)--------",
  "301_revised_tables.py" = r"--------(from pathlib import Path
import sys
# Tables are revised directly in the HTML renderer.
print("Using the supplied country table structure.")
)--------",
  "302_revised_html.py" = r"--------("""Incremental revised planning renderer. Other chapters use the supplied layout."""
from pathlib import Path
from lxml import html
import csv,json,copy,sys
stats,schema,base,target=map(Path,sys.argv[1:])
meta=json.loads((stats/'revision_inputs.json').read_text())
D={r['key']:{k:float(r[k])for k in ['estimate','lower','upper']}for r in csv.DictReader((stats/'revised_planning_intervals.csv').open())}
specs=json.loads(schema.read_text());doc=html.parse(str(base))
labels=[f'{s["scenario"]}\n({s["annual_change_pp"]:+.2f} pp/year)'.replace('(-','(−')for s in meta['scenarios']]
short=[s['scenario']for s in meta['scenarios']]
def value(key,kind='num'):
    x=D[key];digits=0 if kind=='num'else 2
    f=lambda v:f'{v:,.{digits}f}'
    suffix='%'if kind=='pct'else' pp'if kind=='pp'else''
    return f(x['estimate'])+suffix+'\n('+f(x['lower'])+'–'+f(x['upper'])+')'
def plain(cell):return ''.join(cell.itertext()).replace('\u00a0',' ')
def lines(cell):
    c=copy.deepcopy(cell)
    for br in c.xpath('.//br'):br.tail='\n'+(br.tail or'')
    return ''.join(c.itertext())
def set_cell(cell,text):
    for ch in list(cell):cell.remove(ch)
    s=text.split('\n');cell.text=s[0]
    for tail in s[1:]:br=html.Element('br');br.tail=tail;cell.append(br)
def new_title(s):
    prefix=s['title'].split(':')[0]
    if s.get('kind')=='baseline':return prefix+': mCPR growth scenarios'
    if s.get('kind')=='method_scenario':return prefix+': '+short[s['scenario']-1]+' by method'
    return s['title']
lookup={title:s for s in specs for title in [s['title'],new_title(s)]}
updated=[]
for article in doc.xpath('//article[contains(@class,"duration-slide")]'):
    heading=article.find('h3')
    if heading is None:continue
    s=lookup.get(heading.text_content())
    if not s:continue
    kind=s.get('kind');ap=s.get('approach')
    special=s['title']=='Sensitivity: how the year-end mCPR equivalent changes'
    if kind not in ['baseline','scenario','method_scenario']and not special:continue
    table=article.xpath('.//table')[0];rr=table.xpath('.//tr');rows=[[lines(c)for c in r]for r in rr]
    if kind=='baseline':
        rows=[['Different mCPR\ngrowth scenarios','2025 survey\nmCPR','Projected 2026\nmCPR']]+[[labels[j-1],value('mcpr2025','pct'),value(f'base|{j}','pct')]for j in range(1,4)]
    elif kind=='scenario':
        for j in range(1,4):
            k=f'{j}|{ap}|Total';rows[j]=[labels[j-1],value('usualusers|'+k),value('usualmcpr|'+k,'pct'),value('retainedusers|'+k),value('retainedmcpr|'+k,'pct'),value(f'pp|{ap}|Total|Total','pp')]
    elif kind=='method_scenario':
        j=s['scenario']
        for ri,m in enumerate(meta['methods']+['EC','Total'],1):
            key=f'{j}|{ap}|{m}'
            for ci,k,typ in [(2,'usualusers|'+key,'num'),(4,'retainedusers|'+key,'num'),(5,'usualmcpr|'+key,'pct'),(6,'retainedmcpr|'+key,'pct')]:rows[ri][ci]=value(k,typ)
    else:
        for j in range(1,4):rows[j]=[labels[j-1],value(f'base|{j}','pct'),value('count|1|Total|Total'),value('without_direct|1'),value('count|4|Total|Total'),value('pp|4|Total|Total','pp')]
    assert len(rows)==len(rr)
    for row,vals in zip(rr,rows):
        assert len(row)==len(vals)
        for cell,v in zip(row,vals):set_cell(cell,v)
    heading.text=new_title(s)
    if kind=='baseline':
        note=article.xpath('./p[contains(@class,"note")]')[0]
        note.text=('All scenarios use the 2024–25 DHS as the 2025 baseline. DHS trends annualize changes over 2019–2025 '
                   f'({meta["scenarios"][0]["annual_change_pp"]:+.2f} pp/year) and 2016–2025 ({meta["scenarios"][1]["annual_change_pp"]:+.2f} pp/year). '
                   f'FPET-informed growth extends its published 2024–2025 increment ({meta["scenarios"][2]["annual_change_pp"]:+.2f} pp/year). '
                   'The 2026 values add one annual increment to the DHS baseline. Retained-user counts and pp gains stay fixed. '
                   '95% CIs use 500 stratified PSU bootstrap replicates and condition on fixed growth rates and population. '
                   'Calculations use unrounded estimates. The FPET-informed scenario is not an official 2026 FPET forecast.')
    updated.append(heading.text_content())
assert len(updated)>=26,len(updated)
target.write_text(html.tostring(doc,encoding='unicode',doctype='<!DOCTYPE html>'))
print('Updated',len(updated),'planning articles; other chapters and figures retained.')
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
