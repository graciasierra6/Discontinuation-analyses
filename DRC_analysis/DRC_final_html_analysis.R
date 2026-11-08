# Updated report companion: revised planning and incremental HTML build.
# --run=revised-html requires fitted statistics and the current validated report layout.
# Raw-IR preparation remains a separate mode; this does not freshly render every chapter.
# Corrected DHS Table 7.14 five-year reason window; first-year rates unchanged.
# Updated full-frame inference and five planning sets with 95% intervals.
# --run=survey-update rebuilds active numerical outputs from a supplied IR file.
# Parameterized IR preparation: --run=prepare; --validate-input checks inputs only.
#!/usr/bin/env Rscript
# DRC — numerical source companion to the final HTML
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
                   dict(section='historical-duration-aware-planning',issue='Confirm all eight current planning tables against the active survey-update numerical outputs; saved-cell matches alone do not validate inference.',status='verification_scope')]
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
COUNTRY <- "DRC"
REPORT_BASENAME <- "DRC_discontinuation_analysis.html"
REPORT_SHA256 <- "1f871b9d7c937713cc95311ef4b57601647ca57463b91e3f02ce7405de69e1ca"
RAW_RELATIVE <- "Data/CDIR81FL.dta"
CORE_MODULES <- c("01_drc_calendar_life_table.R")
PLANNING_MODULES <- c("01_drc_calendar_life_table.R", "02_drc_descriptive_analyses.R", "05_drc_current_user_planning.R", "06_drc_historical_landmarks.R", "07_drc_duration_aware_planning.R", "08_drc_aft_duration_by_method_cause.R", "12_drc_2026_planning.py", "203_build_drc_planning_tables.py")
REQUIRED_R_PACKAGES <- c('digest','haven','jsonlite','survey','survival','nnet','ggplot2','grid','gridExtra','parallel','scales','sf','svglite','abind','MASS')
BOOTSTRAP_ENV <- c("DRC_PLANNING_BOOTSTRAP_REPS","DRC_BOOTSTRAP_REPS", "DRC_MODEL_BOOTSTRAP_REPS", "DRC_SELECTED_BOOTSTRAP_REPS", "DRC_SELECTED_MODEL_BOOTSTRAP_REPS", "DRC_SUBGROUP_BOOTSTRAP_REPS", "REFERENCE_BOOTSTRAP_REPS", "REFERENCE_MODEL_REPS")
SECTION_INDEX <- r"-----(section_id	title
overview	Modern-method discontinuation
initiation	EC-inclusive initiation diagnostic
table711	DRC DHS Table 7.13
time	Discontinuation by time
reasons712	DRC DHS Table 7.13: reasons for discontinuation
transitions	What happens after discontinuation?
action-pathways	From episode evidence to program action
standardized-current-users	Standardized current-user stock-to-outcome pathway
methods	Methods
validation	Validation
future	Additional analyses
presentation-figures	Presentation figures
dhs-711-presentation-table	DRC DHS Table 7.13: 12-month discontinuation by method and reason
twelve-month-three-column-comparison	12-month discontinuation by method and reason definition
other-reasons-count-breakdown	What is inside “Other” discontinuation reasons?
other-reason-followup	What follows discontinuation for each “Other recorded reason”?
selected-reason-descriptive-subgroups	Exploring which groups have higher 12-month discontinuation for selected reasons
method-experience-subgroup-reasons	Reasons by covariate subgroup
top-three-reasons-by-subgroup-method	Top three reasons by subgroup and original method
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
#   Rscript DRC_final_html_analysis.R --list
#   Rscript DRC_final_html_analysis.R --validate
#   Rscript DRC_final_html_analysis.R --extract --project-root=analysis_output
#   Rscript DRC_final_html_analysis.R --run=core --project-root=analysis_output --ir-file=data/individual_recode.dta
#   Rscript DRC_final_html_analysis.R --run=MODULE_NAME --project-root=analysis_output --ir-file=data/individual_recode.dta
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
  manifest<-data.frame(module=names(MODULES),
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
  if(COUNTRY=='DRC')Sys.setenv(DRC_IR_FILE=target)
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
    cat('Options: --list, --validate, --validate-input, --packages, --extract, --run=prepare|survey-update|survey-planning|core|reference|MODULE[,MODULE], --reconcile\n')
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
  validation<-NULL
  if(nzchar(ir)) {
    expected<-if(!is.null(opt[['expected-ir-sha256']]))opt[['expected-ir-sha256']]else''
    validation<-read_validated_ir(ir,expected)
  } else if(isTRUE(opt[['validate-input']]) || identical(opt$run,'prepare')) {
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
  preparing<-identical(selected,'prepare')
  if(preparing)selected<-c(CORE_MODULES,'210_prepare_analysis_inputs.R')
  if (identical(selected,'core')) selected <- CORE_MODULES
  if (identical(selected,'reference')) selected <- '200_reference_analysis_extensions.R'
  if(length(selected)==1L && selected %in% c('planning','survey-update')) {
    selected <- c("01_drc_calendar_life_table.R","210_prepare_analysis_inputs.R","02_drc_descriptive_analyses.R","17_drc_selected_reason_subgroups.R","214_fit_point_models.R","211_full_frame_survey_inference.R","05_drc_current_user_planning.R","06_drc_historical_landmarks.R","07_drc_duration_aware_planning.R","08_drc_aft_duration_by_method_cause.R","212_planning_survey_ci.R","213_summarize_planning.R","216_reconcile_reason_distributions.R")
    # Point-only legacy tables are immediately followed by full-frame inference.
    Sys.setenv(DRC_BOOTSTRAP_REPS='0',DRC_SELECTED_BOOTSTRAP_REPS='0')
  }
  if(identical(selected,'survey-planning'))selected<-c('212_planning_survey_ci.R','213_summarize_planning.R')
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
EXTERNAL_INPUTS[["output/Supporting_data/drc_wpp2024_wra_2024_2026.csv"]] <- r"-----(year,women_15_49
2024,24386254.5
2025,25246885.0
2026,26146676.5
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
# ORIGINAL MODULE: 203_build_drc_planning_tables.py
# LANGUAGE: Python
MODULES[["203_build_drc_planning_tables.py"]] <- list(
  language="Python",
  original_sha256="bb583191cf956a6df223d8b06e81973f3d7c5c1de69744183718a9d0494c4ef5",
  packaged_sha256="bb583191cf956a6df223d8b06e81973f3d7c5c1de69744183718a9d0494c4ef5",
  args=c("--project-root"),
  code=r"-----(#!/usr/bin/env python3
"""Regenerate the 24 DRC planning tables; no PowerPoint dependency or edits.
Arithmetic and rounding follow the saved DRC presentation.
"""
import argparse,json
from pathlib import Path
METHODS=['Injectables','Implants','Pill','IUD','Other modern']
CAUSES=['Method failure','Wanted more effective method','Changes in menstrual bleeding','Other side effects/health','Access/cost/convenience']
CASES=['No further growth in 2026','UN growth (+0.5 pp)','Track20 growth (+0.4 pp)']
def build(root):
 b=json.loads((root/'output/Supporting_data/drc_2026_planning_bundle.json').read_text())
 s=lambda a,c:next(z for z in b['scenarios'] if z['approach']==a and z['scenario']==c)
 m=lambda a,k:next(z for z in b['methods'] if z['approach']==a and z['method']==k)
 cause=lambda a,k,r:next(z for z in b['causes'] if z['approach']==a and z['method']==k and z['reason']==r)
 first='First-year life table';sc=s(first,CASES[0]);stock=sc['projected_current_users_2025'];wra=sc['wra_2026'];mix=b['current_mix']
 num=lambda x:f'{x:,.0f}';pct=lambda x:f'{x:.1f}%';pp=lambda x:f'{x:.2f} pp'
 users=lambda k:stock*mix[k]/100
 gain=lambda a,k:m(a,k)['retained_modern_users_2026_illustration']
 ending=lambda a,k:m(a,k)['projected_actionable_original_method_endings']
 head=['Method failure','Want more effective','Bleeding changes','Other health','Access / cost']
 blocks=[]
 for approach in [first,'Historical duration-aware','AFT plus observed pathways']:
  risk=[['Method','Current mix','Current users','12-month risk' if approach==first else 'Actionable ending risk','Original-method endings' if approach==first else 'Nonmodern at year end']]
  for k in METHODS:risk.append([k,pct(mix[k]),num(users(k)),pct(100*ending(approach,k)/users(k)),num(gain(approach,k))])
  risk.append(['Emergency contraception',pct(mix['Emergency contraception']),num(users('Emergency contraception')),'—','—'])
  risk.append(['All modern','100.0%',num(stock),pct(100*sum(ending(approach,k) for k in METHODS)/sum(users(k) for k in METHODS)),num(sum(gain(approach,k) for k in METHODS))])
  def cause_table(in_pp=False):
   table=[['Method']+([] if in_pp else ['Current users'])+head+['All actionable' if approach==first or in_pp else 'Nonmodern at year end']];tot=[0]*5
   for k in METHODS:
    vals=[cause(approach,k,r)['retained_modern_users_2026_illustration'] for r in CAUSES];tot=[x+y for x,y in zip(tot,vals)]
    f=(lambda x:f'{100*x/wra:.2f}') if in_pp else num
    table.append([k]+([] if in_pp else [num(users(k))])+[f(x) for x in vals]+[f(sum(vals))])
   table.append(['All methods']+([] if in_pp else [num(sum(users(k) for k in METHODS))])+[f(x) for x in tot]+[f(sum(tot))]);return table
  baseline=[['Scenario','Projected 2025 mCPR','Change to 2026','Illustrative 2026 mCPR']]
  impact=[['Growth case','Usual 2026 users','Usual mCPR','Users if retained','mCPR if retained','Difference']]
  bymethod=[]
  for c in CASES:
   z=s(approach,c);baseline.append([c,pct(z['projected_mcpr_2025_pct']),'+0.0 pp' if c==CASES[0] else '+0.5 pp' if c==CASES[1] else '+0.4 pp',pct(z['usual_mcpr_2026_pct'])])
   impact.append([c,num(z['usual_modern_users_2026']),pct(z['usual_mcpr_2026_pct']),num(z['usual_modern_users_2026']+z['retained_modern_users_2026_illustration']),pct(z['mcpr_if_retained_2026_pct']),pp(z['mcpr_equivalent_pp'])])
   t=[['Method','2025 users','2026 usual users','Endings counted' if approach==first else 'Year-end loss counted','2026 if retained','Usual mCPR','If retained']]
   for k in METHODS+['Emergency contraception']:
    u=z['usual_modern_users_2026']*mix[k]/100;g=0 if k=='Emergency contraception' else gain(approach,k)
    t.append([k,num(users(k)),num(u),num(g),num(u+g),pct(100*u/wra),pct(100*(u+g)/wra)])
   t.append(['All modern',num(stock),num(z['usual_modern_users_2026']),num(z['retained_modern_users_2026_illustration']),num(z['usual_modern_users_2026']+z['retained_modern_users_2026_illustration']),pct(z['usual_mcpr_2026_pct']),pct(z['mcpr_if_retained_2026_pct'])]);bymethod.append(t)
  blocks.append({'approach':approach,'tables':[risk,cause_table(),baseline,impact,*bymethod,cause_table(True)],'wra_2026':wra,'gain_pp':s(approach,CASES[0])['mcpr_equivalent_pp']})
 return blocks
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--project-root',type=Path,required=True);a=p.parse_args();blocks=build(a.project_root)
 (a.project_root/'output/Supporting_data/drc_planning_display_tables.json').write_text(json.dumps(blocks,indent=2)+'\n')
 print('Rebuilt 24 DRC planning tables.')
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 01_drc_calendar_life_table.R
# LANGUAGE: R
MODULES[["01_drc_calendar_life_table.R"]] <- list(
  language="R",
  original_sha256="57a544023a2f2a725c6993479d25d2c0e25db8d2d25eec565e66e1f964c20eb2",
  packaged_sha256="57a544023a2f2a725c6993479d25d2c0e25db8d2d25eec565e66e1f964c20eb2",
  args=character(),
  code=r"-----(#!/usr/bin/env Rscript
# DRC DHS 2023–24: reconstruct contraceptive episodes and validate Table 7.13.
# Input is the authorized DRC IR recode supplied through a runtime parameter.
# One woman contributes zero or more calendar method-use episodes. The DHS
# 3–62-month window and left entry are retained; multiple-decrement estimates
# keep every ending reason as a competing event. This script never edits input.

options(stringsAsFactors=FALSE)
script_arg <- grep('^--file=', commandArgs(FALSE), value=TRUE)
default_root <- if(length(script_arg)) normalizePath(file.path(dirname(sub('^--file=', '', script_arg[1])), '..')) else normalizePath('..')
root <- Sys.getenv('DRC_PROJECT_ROOT', unset=default_root)
input_dir <- Sys.getenv('DRC_INPUT_DIR', unset=file.path(root, 'Data'))
source_dta <- Sys.getenv('DRC_IR_FILE', unset=file.path(input_dir, 'CDIR81FL.dta'))
derived <- file.path(root,'Data/Derived')
support <- file.path(root,'output/Supporting_data')
dir.create(derived,recursive=TRUE,showWarnings=FALSE)
dir.create(support,recursive=TRUE,showWarnings=FALSE)
x <- haven::read_dta(source_dta)
x <- as.data.frame(x)
stopifnot(nrow(x)==27583L,!anyDuplicated(x$caseid),
          all(as.numeric(x$v008)-as.numeric(x$v017)+1==as.numeric(x$v019)),
          all(nchar(x$vcal_1)==80L),
          all(c('vcal_1','vcal_2','v005','v021','v022','v024') %in% names(x)))

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
    zone=as.integer(x$v024[i]),state=as.integer(x$v024[i]),
    start=as.numeric(x$v017[i])+starts-1L,end=as.numeric(x$v017[i])+ends-1L,
    duration=runs$lengths,method_code=codes,reason_code=reason,
    reason_at_method_end=reason_at_end,reason_offset=offset,
    next_code=c(codes[-1L],NA_integer_),
    next_duration=c(runs$lengths[-1L],NA_integer_),
    next2_code=c(codes,NA_integer_,NA_integer_)[seq_along(codes)+2L])
}
events <- do.call(rbind,events)
saveRDS(events,file.path(derived,'drc_2023_24_calendar_events.rds'))

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
e$method[e$method_code %in% c(2L,6L,7L,10L,13L,14L,17L)] <- 'Other'
e$method[e$method_code==3] <- 'Injectables'
e$method[e$method_code==11] <- 'Implants'
e$method[e$method_code==1] <- 'Pill'
e$method[e$method_code==5] <- 'Male condom'
e$method[e$method_code==16] <- 'Emergency contraception'
e$method[e$method_code==8] <- 'Rhythm'
e$method[e$method_code==9] <- 'Withdrawal'
e$method[e$method_code==18L] <- 'SDM/LAM/other'

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
saveRDS(e,file.path(derived,'drc_2023_24_table_7_13_episodes.rds'))

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

published_methods <- c('Injectables','Implants','Pill','Male condom',
                       'Emergency contraception','SDM/LAM/other','Rhythm','Withdrawal','Other','All methods')
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
 c(1.4,18.2,3.7,13.4,15.7,8.0,5.1,0.9,1.5,67.7,4.2,820),
 c(0.1,7.4,3.6,4.6,9.8,0.7,0.9,1.4,1.8,30.2,1.0,1122),
 c(2.6,13.5,6.1,13.7,10.9,4.0,3.9,3.5,5.4,63.6,3.2,637),
 c(0.7,10.9,16.5,1.4,1.5,6.1,4.6,9.1,2.8,53.5,4.5,1031),
 c(2.0,9.6,12.3,4.8,4.0,2.8,5.2,0.4,0.2,41.4,2.8,445),
 c(5.2,20.7,9.0,2.1,1.0,6.9,2.3,4.0,3.5,54.8,4.0,498),
 c(5.5,19.0,11.3,1.2,0.2,2.5,1.8,3.6,2.6,47.5,1.1,2436),
 c(5.1,19.3,11.1,1.1,0.6,6.4,2.2,8.5,4.5,58.8,3.9,1488),
 c(1.5,13.8,9.5,2.6,1.6,9.1,0.6,4.6,4.5,47.8,10.6,1158),
 c(3.1,15.5,9.6,3.8,4.0,4.8,2.5,4.4,3.1,50.7,3.6,9636))
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
write.csv(results,file.path(support,'drc_table_7_13_replicated.csv'),row.names=FALSE)
write.csv(audit,file.path(support,'drc_table_7_13_validation.csv'),row.names=FALSE)
monthly <- do.call(rbind,lapply(published_methods,function(m){
  d <- if(m=='All methods')e else e[e$method==m,]
  cbind(method=m,life_table(d))
}))
write.csv(monthly,file.path(support,'drc_table_7_13_monthly.csv'),row.names=FALSE)
cat('Women:',nrow(x),'episodes:',nrow(e),'weighted:',sum(e$wt),'\n')
print(audit,row.names=FALSE)
cat('Exact published rate cells:',sum(matching[,1:11]),'of',length(matching[,1:11]),'\n')
cat('Exact published episode counts:',sum(matching[,12]),'of',nrow(matching),'\n')
if(!all(matching))warning('DRC Table 7.13 differs from published cells; audit required before downstream use.')
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 02_drc_descriptive_analyses.R
# LANGUAGE: R
MODULES[["02_drc_descriptive_analyses.R"]] <- list(
  language="R",
  original_sha256="4263cbbda74f8321d844a22ed4dee1ec2dfd32edaa6a6401e15bfc09e75a0edb",
  packaged_sha256="4263cbbda74f8321d844a22ed4dee1ec2dfd32edaa6a6401e15bfc09e75a0edb",
  args=character(),
  code=r"-----(#!/usr/bin/env Rscript
# DRC 2023-24 DHS contraceptive-calendar analysis. Input locations are configurable.
args<-grep('^--file=',commandArgs(FALSE),value=TRUE)
default_root<-if(length(args)) normalizePath(file.path(dirname(sub('^--file=','',args[1])),'..')) else normalizePath('..')
root<-Sys.getenv('DRC_PROJECT_ROOT',unset=default_root)
derived<-file.path(root,'Data','Derived');support<-file.path(root,'output','Supporting_data')
dir.create(support,recursive=TRUE,showWarnings=FALSE)
e<-readRDS(file.path(derived,'drc_2023_24_table_7_13_episodes.rds'))
ir<-haven::read_dta(Sys.getenv('DRC_IR_FILE',unset=file.path(root,'Data','CDIR81FL.dta')),
 col_select=c(caseid,v005,v021,v022,v024,v025,v312,v313,v106,v190,v201,v501,v008,v011))
ir<-as.data.frame(ir)
province_labels<-names(attr(ir$v024,'labels')); province_codes<-as.integer(attr(ir$v024,'labels'))
province_names<-c('Kinshasa','Kongo Central','Kwango','Kwilu','Mai-Ndombe','Équateur','Nord-Ubangi','Sud-Ubangi','Mongala','Tshuapa','Tshopo','Bas-Uélé','Haut-Uélé','Ituri','Nord-Kivu','Sud-Kivu','Maniema','Haut-Katanga','Haut-Lomami','Lualaba','Tanganyika','Lomami','Sankuru','Kasaï Oriental','Kasaï','Kasaï Central')
stopifnot(identical(province_codes,1:26))
modern_codes<-c(1L,2L,3L,5L,6L,7L,11L,13L,14L,15L,17L,18L,19L,20L)
causes<-list('Method failure'=1L,'Wanted more effective method'=7L,'Changes in menstrual bleeding'=15L,
 'Other side effects/health'=c(4L,5L),'Access/cost/convenience'=c(6L,8L,10L))
actionable<-unlist(causes,use.names=FALSE)
e<-e[e$method_code%in%modern_codes,]
e$province<-province_names[e$zone]
e$cluster<-as.numeric(ir$v021[e$woman_row]);e$stratum<-as.numeric(ir$v022[e$woman_row])
e$method_group<-'Other modern'
e$method_group[e$method_code==1L]<-'Pill'
e$method_group[e$method_code==2L]<-'IUD'
e$method_group[e$method_code==3L]<-'Injectables'
e$method_group[e$method_code==11L]<-'Implants'
e$action_event<-e$discontinued & e$exposure<=12L & e$reason_code%in%actionable
saveRDS(e,file.path(derived,'drc_2023_24_modern_episodes.rds'))

life<-function(d,w=d$wt){
 s<-1;all<-0;act<-0;cv<-setNames(numeric(length(causes)),names(causes));out<-vector('list',12L)
 for(t in seq_len(12L)){
  at<-d$entry<t & d$exposure>=t;risk<-sum(w[at]);if(risk<=0)return(NULL)
  end<-at & d$exposure==t & d$discontinued
  h_all<-sum(w[end])/risk; h_act<-sum(w[end & d$reason_code%in%actionable])/risk
  for(j in seq_along(causes)) cv[j]<-cv[j]+s*sum(w[end & d$reason_code%in%causes[[j]]])/risk
  all<-all+s*h_all;act<-act+s*h_act;s<-s*(1-h_all)
  out[[t]]<-data.frame(month=t,all_reason_pct=100*all,actionable_pct=100*act,survival_pct=100*s)
 }
 list(monthly=do.call(rbind,out),causes=100*cv)
}
scopes<-list(National=rep(TRUE,nrow(e)))
for(i in 1:26) scopes[[province_names[i]]]<-e$zone==i
for(m in c('Injectables','Implants','Pill','IUD','Other modern'))scopes[[paste0('National: ',m)]]<-e$method_group==m
for(i in 1:26)for(m in c('Injectables','Implants','Pill','IUD','Other modern'))scopes[[paste0(province_names[i],': ',m)]]<-e$zone==i & e$method_group==m
rows<-list();rr<-list();kk<-0L
for(label in names(scopes)){
 d<-e[scopes[[label]],];if(!nrow(d))next
 z<-life(d);if(is.null(z))next
 kk<-kk+1L;v<-z$monthly[z$monthly$month%in%c(3L,6L,9L,12L),]
 v$scope<-label;v$eligible_episodes_n<-nrow(d);v$weighted_episodes<-sum(d$wt)
 v$actionable_endings_n<-sum(d$action_event);v$limited_precision<-sum(d$action_event)<30L
 rows[[kk]]<-v
 total<-sum(z$causes)
 rr[[kk]]<-data.frame(scope=label,reason=names(z$causes),cause_specific_12_month_pct=unname(z$causes),
 share_among_actionable_pct=if(total>0)100*unname(z$causes)/total else NA_real_,
 eligible_episodes_n=nrow(d),actionable_endings_n=sum(d$action_event),limited_precision=sum(d$action_event)<30L)
}
times<-do.call(rbind,rows);reasons<-do.call(rbind,rr);rownames(times)<-rownames(reasons)<-NULL
stopifnot(abs(sum(reasons$cause_specific_12_month_pct[reasons$scope=='National'])-times$actionable_pct[times$scope=='National' & times$month==12])<1e-8)

# Stratified PSU bootstrap for national, province, and national-method rates.
focus<-c('National',province_names,paste0('National: ',c('Injectables','Implants','Pill','IUD','Other modern')))
frame <- full_survey_frame();frame$id<-seq_len(nrow(frame))
stopifnot(!anyDuplicated(frame$cluster));groups<-split(frame$id,frame$stratum)
B<-as.integer(Sys.getenv('DRC_BOOTSTRAP_REPS',unset='250'))
draw<-array(NA_real_,c(B,length(focus),4L,2L),dimnames=list(NULL,focus,c('3','6','9','12'),c('all','actionable')))
for(b in seq_len(B)){
 set.seed(20261029+b);mult<-numeric(nrow(frame))
 for(ids in groups){n<-length(ids);mult[ids]<-if(n>1) n/(n-1)*tabulate(sample.int(n,n-1,replace=TRUE),nbins=n) else 1}
 lookup<-setNames(mult,frame$cluster)
 for(j in seq_along(focus)){
  d<-e[scopes[[focus[j]]],];if(!nrow(d))next
  fit<-life(d,d$wt*lookup[as.character(d$cluster)])
  if(is.null(fit))next
  at<-fit$monthly[c(3,6,9,12),]
  draw[b,j,,1]<-at$all_reason_pct;draw[b,j,,2]<-at$actionable_pct
 }
}
for(j in seq_along(focus))for(k in 1:4){
 sel<-times$scope==focus[j] & times$month==c(3,6,9,12)[k]
 for(q in 1:2){nm<-if(q==1)'all_reason' else 'actionable';v<-draw[,j,k,q];v<-v[is.finite(v)]
  if(length(v)>=.8*B){times[sel,paste0(nm,'_ci_low')]<-unname(quantile(v,.025));times[sel,paste0(nm,'_ci_high')]<-unname(quantile(v,.975))}
 }
}
saveRDS(draw,file.path(derived,'drc_actionable_bootstrap.rds'))
write.csv(times,file.path(support,'drc_modern_timepoints.csv'),row.names=FALSE)
write.csv(reasons,file.path(support,'drc_actionable_reasons.csv'),row.names=FALSE)

# Initiation shares use observed modern starts. EC and traditional methods are
# shown separately in the full start mix; ongoing-method risk excludes EC.
all_e<-readRDS(file.path(derived,'drc_2023_24_table_7_13_episodes.rds'))
starts<-all_e[all_e$entry==0L,]
starts$province<-province_names[starts$zone]
starts$method_start<-'Other modern'
starts$method_start[starts$method_code==1L]<-'Pill'
starts$method_start[starts$method_code==2L]<-'IUD'
starts$method_start[starts$method_code==3L]<-'Injectables'
starts$method_start[starts$method_code==11L]<-'Implants'
starts$method_start[starts$method_code==16L]<-'Emergency contraception'
starts$method_start[!starts$method_code%in%c(modern_codes,16L)]<-'Non-modern methods'
start_rows<-list();kk<-0
for(scope in c('National',province_names)){
 d<-if(scope=='National') starts else starts[starts$province==scope,]
 for(m in c('Injectables','Implants','Pill','IUD','Emergency contraception','Other modern','Non-modern methods')){
  kk<-kk+1L;q<-d[d$method_start==m,]
  start_rows[[kk]]<-data.frame(scope=scope,method=m,observed_starts_n=nrow(q),weighted_starts=sum(q$wt),share_of_all_starts_pct=100*sum(q$wt)/sum(d$wt))
 }
}
start_mix<-do.call(rbind,start_rows);write.csv(start_mix,file.path(support,'drc_method_start_mix.csv'),row.names=FALSE)
stopifnot(max(abs(aggregate(share_of_all_starts_pct~scope,start_mix,sum)$share_of_all_starts_pct-100))<1e-8)

# Interview-date current use and method distribution: woman-level weighted.
ir$wt<-as.numeric(ir$v005)/1e6
ir$method_group<-'Other modern'
ir$method_group[as.numeric(ir$v312)==1L]<-'Pill'
ir$method_group[as.numeric(ir$v312)==2L]<-'IUD'
ir$method_group[as.numeric(ir$v312)==3L]<-'Injectables'
ir$method_group[as.numeric(ir$v312)==11L]<-'Implants'
ir$method_group[as.numeric(ir$v312)==16L]<-'Emergency contraception'
ir$modern<-as.numeric(ir$v313)==3L
mcpr<-100*sum(ir$wt[ir$modern])/sum(ir$wt)
current<-ir[ir$modern,]
current_mix<-do.call(rbind,lapply(c('Injectables','Implants','Pill','IUD','Emergency contraception','Other modern'),function(m){
 q<-current[current$method_group==m,]
 data.frame(method=m,current_users_n=nrow(q),weighted_current_users=sum(q$wt),share_of_current_modern_users_pct=100*sum(q$wt)/sum(current$wt),all_women_method_prevalence_pct=100*sum(q$wt)/sum(ir$wt),all_women_mcpr_pct=mcpr)
}))
write.csv(current_mix,file.path(support,'drc_current_use_mcpr.csv'),row.names=FALSE)
cat('Modern eligible episodes',nrow(e),'weighted',sum(e$wt),'actionable endings',sum(e$action_event),'mCPR',mcpr,'\n')
cat('Provinces with <30 actionable endings:',sum(times$limited_precision[times$month==12 & times$scope%in%province_names]),'of 26\n')
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 04_drc_province_models.R
# LANGUAGE: R
MODULES[["04_drc_province_models.R"]] <- list(
  language="R",
  original_sha256="c31215b5a72dd88a3e34809161cbf4b16581136ab82e267531cb18b33a051886",
  packaged_sha256="c31215b5a72dd88a3e34809161cbf4b16581136ab82e267531cb18b33a051886",
  args=character(),
  code=r"-----(#!/usr/bin/env Rscript
# DRC DHS 2023–24: adjusted province comparison for actionable discontinuation.
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

root <- Sys.getenv("DRC_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
support <- file.path(root,'output/Supporting_data')
derived <- file.path(root,'Data/Derived')
if(!requireNamespace('nnet',quietly=TRUE))stop('nnet package is required')
e <- readRDS(file.path(derived,'drc_2023_24_modern_episodes.rds'))
ir <- as.data.frame(haven::read_dta(Sys.getenv('DRC_IR_FILE', unset=file.path(root,'Data','CDIR81FL.dta'))))
times <- read.csv(file.path(support,'drc_modern_timepoints.csv'))
actionable <- c(1L,4L,5L,6L,7L,8L,10L,15L)
e$zone_name <- factor(e$province, levels=c('Kinshasa','Kongo Central','Kwango','Kwilu','Mai-Ndombe','Équateur','Nord-Ubangi','Sud-Ubangi','Mongala','Tshuapa','Tshopo','Bas-Uélé','Haut-Uélé','Ituri','Nord-Kivu','Sud-Kivu','Maniema','Haut-Katanga','Haut-Lomami','Lualaba','Tanganyika','Lomami','Sankuru','Kasaï Oriental','Kasaï','Kasaï Central'))
e$method_group <- factor(e$method_group,
  levels=c('Implants','Injectables','Pill','IUD','Other modern'))
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
# Pool recent starts to avoid sparse cohort terms.
year <- (e$start-1L)%/%12L+1900L
e$start_year <- factor(ifelse(year>=2023,'2023–24',as.character(year)))
complete <- complete.cases(e[,c('method_group','zone_name','age_group',
  'parity_group','marital_group','education','wealth','residence','start_year')])
cat('Complete-case episodes:',sum(complete),'of',nrow(e),'\n')
e <- e[complete,]
saveRDS(e,file.path(derived,'drc_2023_24_model_episode_covariates.rds'))

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
stopifnot(!anyNA(person),nrow(person)>10000)
saveRDS(person,file.path(derived,'drc_2023_24_person_month.rds'))

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
saveRDS(model1,file.path(derived,'drc_actionable_province_model_1.rds'))
saveRDS(model2,file.path(derived,'drc_actionable_province_model_2.rds'))

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
    unadjusted_pct=raw$actionable_pct,unadjusted_low=raw$actionable_ci_low,
    unadjusted_high=raw$actionable_ci_high,
    model_1_common_mix_pct=predict_cif(model1,z),
    model_2_common_mix_pct=predict_cif(model2,z))
}))
national <- times[times$scope=='National' & times$month==12,]
point <- rbind(data.frame(zone='National',
  eligible_episodes_n=national$eligible_episodes_n,
  actionable_endings_n=national$actionable_endings_n,
  unadjusted_pct=national$actionable_pct,
  unadjusted_low=national$actionable_ci_low,
  unadjusted_high=national$actionable_ci_high,
  model_1_common_mix_pct=predict_cif(model1,NULL),
  model_2_common_mix_pct=predict_cif(model2,NULL)),point)
write.csv(point,file.path(support,'drc_actionable_province_adjusted_rates.csv'),
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
write.csv(coef,file.path(support,'drc_actionable_province_model_odds_ratios.csv'),
  row.names=FALSE)

print(point,row.names=FALSE)
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 05_drc_current_user_planning.R
# LANGUAGE: R
MODULES[["05_drc_current_user_planning.R"]] <- list(
  language="R",
  original_sha256="12b21e8e44d796ecdb8825b6c4b60cc7871c98668557c62138ee5ff0b89e6deb",
  packaged_sha256="12b21e8e44d796ecdb8825b6c4b60cc7871c98668557c62138ee5ff0b89e6deb",
  args=character(),
  code=r"-----(#!/usr/bin/env Rscript
# Illustrative DRC 2024 current-user stock and next-year actionable original-method endings.
args<-grep('^--file=',commandArgs(FALSE),value=TRUE)
default_root<-if(length(args)) normalizePath(file.path(dirname(sub('^--file=','',args[1])),'..')) else normalizePath('..')
root<-Sys.getenv('DRC_PROJECT_ROOT',unset=default_root);sup<-file.path(root,'output','Supporting_data')
cur<-read.csv(file.path(sup,'drc_current_use_mcpr.csv'))
risk<-read.csv(file.path(sup,'drc_modern_timepoints.csv'))
causes<-read.csv(file.path(sup,'drc_actionable_reasons.csv'))
wra<-read.csv(file.path(sup,'drc_wpp2024_wra_2024_2026.csv'))
wra24<-wra$women_15_49[wra$year==2024];wra25<-wra$women_15_49[wra$year==2025]
mcpr<-cur$all_women_mcpr_pct[1]
methods<-c('Injectables','Implants','Pill','IUD','Other modern')
rows<-list();cc<-list()
for(m in methods){
 c<-cur[cur$method==m,];r<-risk[risk$scope==paste0('National: ',m)&risk$month==12,]
 stock<-wra24*c$all_women_method_prevalence_pct/100
 rows[[m]]<-data.frame(method=m,current_users_2024=stock,current_users_n=c$current_users_n,
  share_of_current_modern_users_pct=c$share_of_current_modern_users_pct,
  actionable_first_year_risk_pct=r$actionable_pct,
  illustrative_original_method_endings=stock*r$actionable_pct/100,
  sparse_method=as.logical(r$limited_precision))
 for(reason in unique(causes$reason)){
  q<-causes[causes$scope==paste0('National: ',m)&causes$reason==reason,]
  cc[[paste(m,reason)]]<-data.frame(method=m,reason=reason,current_users_2024=stock,
    cause_specific_12_month_pct=q$cause_specific_12_month_pct,
    illustrative_users=stock*q$cause_specific_12_month_pct/100)
 }
}
users<-do.call(rbind,rows);cause_users<-do.call(rbind,cc)
stopifnot(abs(sum(users$illustrative_original_method_endings)-sum(cause_users$illustrative_users))<1e-5)
write.csv(users,file.path(sup,'drc_current_users_by_method_and_actionable_projection.csv'),row.names=FALSE)
write.csv(cause_users,file.path(sup,'drc_current_users_actionable_by_cause.csv'),row.names=FALSE)
# The all-women DHS mCPR is the 2024 baseline. Three 2025 growth scenarios:
# no growth; observed 2013/14–2023/24 DHS annualized change; and FPET's
# modeled 2024–25 change (10.4 to 10.8 percentage points).
prior_mcp<-8.121123;dhs_growth<-(mcpr-prior_mcp)/10
scenario<-data.frame(scenario=c('No growth','DHS trend','Track20/FPET trend'),
  growth_pp=c(0,dhs_growth,0.4),baseline_mcpr_2024_pct=mcpr,
  baseline_wra_2024=wra24,current_users_2024=wra24*mcpr/100,
  wra_2025=wra25)
scenario$mcpr_2025_pct<-mcpr+scenario$growth_pp
scenario$usual_users_2025<-scenario$mcpr_2025_pct/100*wra25
scenario$illustrative_gross_endings<-sum(users$illustrative_original_method_endings)
scenario$gross_mcpr_equivalent_pp<-100*scenario$illustrative_gross_endings/wra25
scenario$mcpr_if_actionable_endings_avoided_pct<-scenario$mcpr_2025_pct+scenario$gross_mcpr_equivalent_pp
write.csv(scenario,file.path(sup,'drc_2025_mcpr_scenarios.csv'),row.names=FALSE)
cat('DHS all-women mCPR',mcpr,'current users',wra24*mcpr/100,'gross endings',sum(users$illustrative_original_method_endings),'pp',100*sum(users$illustrative_original_method_endings)/wra25,'\n')
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 06_drc_historical_landmarks.R
# LANGUAGE: R
MODULES[["06_drc_historical_landmarks.R"]] <- list(
  language="R",
  original_sha256="45ec8939a2a6e87c32fdfafb6bb37e362d2998a908cfc2421ccbe7159b937bc9",
  packaged_sha256="45ec8939a2a6e87c32fdfafb6bb37e362d2998a908cfc2421ccbe7159b937bc9",
  args=character(),
  code=r"-----(#!/usr/bin/env Rscript
# Historical 12-month lookahead from observed method-use landmarks, for duration-aware planning.
args<-grep('^--file=',commandArgs(FALSE),value=TRUE)
default_root<-if(length(args)) normalizePath(file.path(dirname(sub('^--file=','',args[1])),'..')) else normalizePath('..')
root<-Sys.getenv('DRC_PROJECT_ROOT',unset=default_root)
source_file<-Sys.getenv('DRC_IR_FILE',unset=file.path(root,'Data','CDIR81FL.dta'))
calendar<-readRDS(file.path(root,'Data','Derived','drc_2023_24_calendar_events.rds'))
ir<-as.data.frame(haven::read_dta(source_file,col_select=c(v005,v312,v313,v337)))
modern<-c(1L,2L,3L,5L,6L,7L,11L,13L,14L,15L,17L,18L,19L,20L)
method_group<-function(z)ifelse(z==3L,'Injectables',ifelse(z==11L,'Implants',ifelse(z==1L,'Pill',ifelse(z==2L,'IUD','Other modern'))))
cause_group<-function(z)ifelse(z==1L,'Method failure',ifelse(z==7L,'Wanted more effective method',ifelse(z==15L,'Changes in menstrual bleeding',ifelse(z%in%c(4L,5L),'Other side effects/health',ifelse(z%in%c(6L,8L,10L),'Access/cost/convenience',NA_character_)))))
actionable<-c(1L,4L,5L,6L,7L,8L,10L,15L)
by_woman<-split(seq_len(nrow(calendar)),calendar$woman_row)
spells<-calendar[calendar$method_code%in%modern & calendar$start>calendar$calendar_start,]
rows<-vector('list',nrow(spells))
for(i in seq_len(nrow(spells))){
 a<-spells[i,];last<-min(a$end,a$interview-15L)
 if(last<a$start)next
 landmark<-seq.int(a$start,last);future<-landmark+12L
 pe<-calendar[by_woman[[as.character(a$woman_row)]],]
 next_event<-findInterval(future,pe$start)
 if(any(next_event<=0L)||any(pe$end[next_event]<future))next
 code12<-pe$method_code[next_event]
 action<-a$end<future & a$reason_code%in%actionable
 direct<-action & !is.na(a$next_code) & a$next_code%in%modern
 modern12<-code12%in%modern
 rows[[i]]<-data.frame(woman_row=a$woman_row,method=method_group(a$method_code),
  duration_completed=landmark-a$start,wt=a$wt,actionable=action,
  direct_switch=direct,modern_at_month12=modern12,
  actionable_nonmodern_at_month12=action & !modern12,
  actionable_modern_at_month12=action & modern12,
  cause=ifelse(action,cause_group(a$reason_code),NA_character_))
}
land<-do.call(rbind,rows[!vapply(rows,is.null,logical(1))])
breaks<-c(-1,3,6,12,24,36,48,60,Inf);labels<-c('0–3','4–6','7–12','13–24','25–36','37–48','49–60','61+')
land$duration_bin<-cut(land$duration_completed,breaks,labels=labels)
stopifnot(!anyNA(land$duration_bin),all(land$actionable_nonmodern_at_month12+land$actionable_modern_at_month12==land$actionable))
saveRDS(land,file.path(root,'Data','Derived','drc_historical_duration_landmarks.rds'))
cat('landmarks',nrow(land),'unique women',length(unique(land$woman_row)),'\n')
print(with(land,table(method,duration_bin)),quote=FALSE)
current<-ir[as.numeric(ir$v313)==3 & as.numeric(ir$v312)%in%modern,]
current$method<-method_group(as.integer(current$v312));current$duration_bin<-cut(as.numeric(current$v337),breaks,labels=labels)
cat('current users',nrow(current),'duration 61+',sum(current$duration_bin=='61+'),'\n')
print(with(current,table(method,duration_bin)),quote=FALSE)
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 07_drc_duration_aware_planning.R
# LANGUAGE: R
MODULES[["07_drc_duration_aware_planning.R"]] <- list(
  language="R",
  original_sha256="aa9fe55e332001a97bbea42ff43ab87a5a1aae85f397919c9ac0c673d7061f82",
  packaged_sha256="aa9fe55e332001a97bbea42ff43ab87a5a1aae85f397919c9ac0c673d7061f82",
  args=character(),
  code=r"-----(#!/usr/bin/env Rscript
# Standardize observed historical month-12 pathways to 2024 current users' method-duration mix.
args<-grep('^--file=',commandArgs(FALSE),value=TRUE)
default_root<-if(length(args)) normalizePath(file.path(dirname(sub('^--file=','',args[1])),'..')) else normalizePath('..')
root<-Sys.getenv('DRC_PROJECT_ROOT',unset=default_root);sup<-file.path(root,'output','Supporting_data')
land<-readRDS(file.path(root,'Data','Derived','drc_historical_duration_landmarks.rds'))
ir<-as.data.frame(haven::read_dta(Sys.getenv('DRC_IR_FILE',unset=file.path(root,'Data','CDIR81FL.dta')),col_select=c(v005,v312,v313,v337)))
users<-read.csv(file.path(sup,'drc_current_users_by_method_and_actionable_projection.csv'))
scen<-read.csv(file.path(sup,'drc_2025_mcpr_scenarios.csv'))
methods<-c('Injectables','Implants','Pill','IUD','Other modern')
causes<-c('Method failure','Wanted more effective method','Changes in menstrual bleeding','Other side effects/health','Access/cost/convenience')
mg<-function(z)ifelse(z==3L,'Injectables',ifelse(z==11L,'Implants',ifelse(z==1L,'Pill',ifelse(z==2L,'IUD','Other modern'))))
modern<-c(1L,2L,3L,5L,6L,7L,11L,13L,14L,15L,17L,18L,19L,20L)
current<-ir[as.numeric(ir$v313)==3 & as.numeric(ir$v312)%in%modern,]
current$method<-mg(as.integer(current$v312));current$wt<-as.numeric(current$v005)/1e6
breaks<-c(-1,3,6,12,24,36,48,60,Inf);labels<-c('0–3','4–6','7–12','13–24','25–36','37–48','49–60','61+')
current$duration_bin<-cut(as.numeric(current$v337),breaks,labels=labels)
outcomes<-c('actionable','direct_switch','actionable_nonmodern_at_month12','actionable_modern_at_month12')
rate<-function(d,field){if(!nrow(d))return(NA_real_);sum(d$wt*as.numeric(d[[field]]))/sum(d$wt)}
rows<-list();cause_rows<-list();summary_rows<-list();kk<-0
for(m in methods){
 dcur<-current[current$method==m,];stock<-users$current_users_2024[users$method==m]
 if(length(stock)!=1L)stop('Missing current-user stock for ',m)
 for(b in labels){
  ck<-dcur[dcur$duration_bin==b,]
  historical_bins<-if(b=='61+')c('37–48','49–60') else b
  dl<-land[land$method==m & land$duration_bin%in%historical_bins,]
  if(!nrow(ck))next
  if(!nrow(dl))stop('No historical landmarks for current users in ',m,' ',b)
  kk<-kk+1L;rows[[kk]]<-data.frame(method=m,duration_bin=b,current_users_n=nrow(ck),current_weight=sum(ck$wt),
   historical_landmarks_n=nrow(dl),historical_women_n=length(unique(dl$woman_row)),
   actionable=rate(dl,'actionable'),direct_switch=rate(dl,'direct_switch'),
   actionable_nonmodern_at_month12=rate(dl,'actionable_nonmodern_at_month12'),
   actionable_modern_at_month12=rate(dl,'actionable_modern_at_month12'),proxy_for_61plus=b=='61+')
  for(cause in causes){
   flag<-!is.na(dl$cause)&dl$cause==cause
   cause_rows[[length(cause_rows)+1L]]<-data.frame(method=m,duration_bin=b,reason=cause,
    cause_risk=sum(dl$wt*flag)/sum(dl$wt),
    nonmodern_at_month12_risk=sum(dl$wt*flag*(!dl$modern_at_month12))/sum(dl$wt),
    direct_switch_risk=sum(dl$wt*flag*dl$direct_switch)/sum(dl$wt))
  }
 }
}
bin<-do.call(rbind,rows);cause_bin<-do.call(rbind,cause_rows)
write.csv(bin,file.path(sup,'drc_duration_landmark_support_and_risks.csv'),row.names=FALSE)
for(m in methods){
 b<-bin[bin$method==m,];stock<-users$current_users_2024[users$method==m]
 w<-b$current_weight/sum(b$current_weight)
 agg<-function(x)sum(w*b[[x]])
 summary_rows[[m]]<-data.frame(method=m,current_users_2024=stock,current_users_n=sum(b$current_users_n),
  current_users_61plus_share_pct=100*sum(w[b$duration_bin=='61+']),
  actionable_ending_risk_next12_pct=100*agg('actionable'),
  projected_actionable_original_method_endings=stock*agg('actionable'),
  projected_direct_modern_switchers=stock*agg('direct_switch'),
  projected_modern_at_month12_after_actionable=stock*agg('actionable_modern_at_month12'),
  projected_nonmodern_at_month12_after_actionable=stock*agg('actionable_nonmodern_at_month12'),
  descriptive_nonmodern_at_month12_pp=100*stock*agg('actionable_nonmodern_at_month12')/scen$wra_2025[1])
}
summary<-do.call(rbind,summary_rows);rownames(summary)<-NULL
stopifnot(max(abs(summary$projected_actionable_original_method_endings-summary$projected_modern_at_month12_after_actionable-summary$projected_nonmodern_at_month12_after_actionable))<1e-5)
write.csv(summary,file.path(sup,'drc_duration_aware_current_user_bridge.csv'),row.names=FALSE)
cr<-list()
for(m in methods)for(cause in causes){
 b<-bin[bin$method==m,];cb<-cause_bin[cause_bin$method==m&cause_bin$reason==cause,]
 cb<-cb[match(b$duration_bin,cb$duration_bin),]
 w<-b$current_weight/sum(b$current_weight);stock<-users$current_users_2024[users$method==m]
 cr[[paste(m,cause)]]<-data.frame(method=m,reason=cause,current_users_2024=stock,
  projected_actionable_original_method_endings=stock*sum(w*cb$cause_risk),
  projected_direct_modern_switchers=stock*sum(w*cb$direct_switch_risk),
  projected_nonmodern_at_month12=stock*sum(w*cb$nonmodern_at_month12_risk))
}
cr<-do.call(rbind,cr);rownames(cr)<-NULL
for(m in methods){a<-cr[cr$method==m,];s<-summary[summary$method==m,];stopifnot(abs(sum(a$projected_actionable_original_method_endings)-s$projected_actionable_original_method_endings)<1e-5)}
write.csv(cr,file.path(sup,'drc_duration_aware_current_user_by_cause.csv'),row.names=FALSE)
scen$historical_duration_actionable_endings<-sum(summary$projected_actionable_original_method_endings)
scen$historical_duration_nonmodern_year_end<-sum(summary$projected_nonmodern_at_month12_after_actionable)
scen$historical_duration_gross_pp<-100*scen$historical_duration_actionable_endings/scen$wra_2025
scen$historical_duration_year_end_pp<-100*scen$historical_duration_nonmodern_year_end/scen$wra_2025
write.csv(scen,file.path(sup,'drc_2025_mcpr_scenarios.csv'),row.names=FALSE)
cat('Historical duration gross endings',sum(summary$projected_actionable_original_method_endings),'year-end nonmodern',sum(summary$projected_nonmodern_at_month12_after_actionable),'pp',100*sum(summary$projected_nonmodern_at_month12_after_actionable)/scen$wra_2025[1],'\n')
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 08_drc_aft_duration_by_method_cause.R
# LANGUAGE: R
MODULES[["08_drc_aft_duration_by_method_cause.R"]] <- list(
  language="R",
  original_sha256="ca6110cc60f697136a1c27452f35f433f1566b19d53b614cf4485342dad24c5e",
  packaged_sha256="ca6110cc60f697136a1c27452f35f433f1566b19d53b614cf4485342dad24c5e",
  args=character(),
  code=r"-----(#!/usr/bin/env Rscript
# Cause-specific AFT duration sensitivity; competing hazards are integrated over next 12 months.
args<-grep('^--file=',commandArgs(FALSE),value=TRUE)
default_root<-if(length(args)) normalizePath(file.path(dirname(sub('^--file=','',args[1])),'..')) else normalizePath('..')
root<-Sys.getenv('DRC_PROJECT_ROOT',unset=default_root);sup<-file.path(root,'output','Supporting_data')
e<-readRDS(file.path(root,'Data','Derived','drc_2023_24_modern_episodes.rds'))
ir<-as.data.frame(haven::read_dta(Sys.getenv('DRC_IR_FILE',unset=file.path(root,'Data','CDIR81FL.dta')),col_select=c(v005,v312,v313,v337)))
stocks<-read.csv(file.path(sup,'drc_current_users_by_method_and_actionable_projection.csv'))
historical<-read.csv(file.path(sup,'drc_duration_aware_current_user_by_cause.csv'))
scenario<-read.csv(file.path(sup,'drc_2025_mcpr_scenarios.csv'))
modern<-c(1L,2L,3L,5L,6L,7L,11L,13L,14L,15L,17L,18L,19L,20L)
methods<-c('Injectables','Implants','Pill','IUD','Other modern')
model_methods<-c('Injectables','Implants','Pill','Other modern')
causes<-c('Method failure','Wanted more effective method','Changes in menstrual bleeding','Other side effects/health','Access/cost/convenience')
mg<-function(z)ifelse(z==3L,'Injectables',ifelse(z==11L,'Implants',ifelse(z==1L,'Pill','Other modern')))
cause_group<-function(z)ifelse(z==1L,causes[1],ifelse(z==7L,causes[2],ifelse(z==15L,causes[3],ifelse(z%in%c(4L,5L),causes[4],ifelse(z%in%c(6L,8L,10L),causes[5],NA_character_)))))
e<-e[e$entry==0L & e$exposure>0L,];e$method<-factor(mg(e$method_code),levels=model_methods)
e$cause<-cause_group(e$reason_code);e$cause[!e$discontinued]<-NA_character_
stopifnot(all(e$exposure>=1L),nrow(e)>3000L)
suppressPackageStartupMessages(library(survival))
dists<-c('weibull','loglogistic','lognormal','exponential')
fit_one<-function(cause){
 e$event<-as.integer(e$discontinued & if(cause=='Other endings')is.na(e$cause) else (!is.na(e$cause)&e$cause==cause))
 fits<-lapply(dists,function(dist)tryCatch(survreg(Surv(exposure,event)~method,data=e,weights=wt,dist=dist,control=survreg.control(maxiter=150)),error=function(err)NULL))
 aic<-vapply(fits,function(f)if(is.null(f)||!all(is.finite(coef(f)))||!is.finite(f$scale)||f$scale<0.05)Inf else AIC(f),0.0)
 if(all(!is.finite(aic)))stop('No AFT fit for ',cause)
 chosen<-which.min(aic)
 list(fit=fits[[chosen]],distribution=dists[chosen],aic=aic,events=sum(e$event))
}
models<-setNames(lapply(c(causes,'Other endings'),fit_one),c(causes,'Other endings'))
fit_report<-do.call(rbind,lapply(names(models),function(cause)data.frame(cause=cause,events=models[[cause]]$events,
 distribution=models[[cause]]$distribution,aic=models[[cause]]$aic[match(models[[cause]]$distribution,dists)])))
write.csv(fit_report,file.path(sup,'drc_aft_duration_fit.csv'),row.names=FALSE)
cumhaz<-function(t,mu,scale,dist){
 if(t<=0)return(0)
 if(dist=='weibull')return((t/exp(mu))^(1/scale))
 if(dist=='exponential')return(t/exp(mu))
 if(dist=='loglogistic')return(log1p(exp((log(t)-mu)/scale)))
 if(dist=='lognormal')return(-pnorm((log(t)-mu)/scale,lower.tail=FALSE,log.p=TRUE))
 stop('Unsupported distribution')
}
pars<-list()
for(m in model_methods){
 pars[[m]]<-lapply(models,function(obj){
  mu<-as.numeric(predict(obj$fit,newdata=data.frame(method=factor(m,levels=model_methods)),type='lp'))
  c(mu=mu,scale=obj$fit$scale)
 })
}
next12<-function(age,m){
 s<-1;risks<-setNames(numeric(length(models)),names(models))
 for(t in seq.int(age+1L,age+12L)){
  h<-vapply(names(models),function(cause){p<-pars[[m]][[cause]];max(0,cumhaz(t,p['mu'],p['scale'],models[[cause]]$distribution)-cumhaz(t-1L,p['mu'],p['scale'],models[[cause]]$distribution))},0.0)
  total<-sum(h);if(total>0)risks<-risks+s*(-expm1(-total))*h/total
  s<-s*exp(-total)
 }
 risks
}
current<-ir[as.numeric(ir$v313)==3 & as.numeric(ir$v312)%in%modern,]
current$method<-ifelse(as.integer(current$v312)==2L,'IUD',mg(as.integer(current$v312)))
current$elapsed<-as.integer(current$v337);current$wt<-as.numeric(current$v005)/1e6
stopifnot(!anyNA(current$elapsed),all(current$elapsed>=0))
rows<-list();cr<-list()
for(m in methods){
 d<-current[current$method==m,];model_m<-if(m=='IUD')'Other modern' else m
 ages<-sort(unique(d$elapsed));r<-vapply(ages,function(a)next12(a,model_m),setNames(numeric(length(models)),names(models)))
 # Weighted mean is computed cause by cause.
 prob<-vapply(seq_len(nrow(r)),function(j)weighted.mean(r[j,match(d$elapsed,ages)],d$wt),0.0)
 names(prob)<-rownames(r);stock<-stocks$current_users_2024[stocks$method==m]
 cause_sum<-sum(prob[causes]);rows[[m]]<-data.frame(method=m,current_users_n=nrow(d),current_users_2024=stock,
  survival_actionable_next12_pct=100*cause_sum,
  survival_original_method_endings=stock*cause_sum,
  gross_mcpr_equivalent_pp=100*stock*cause_sum/scenario$wra_2025[1],
  iud_uses_other_modern_aft_proxy=m=='IUD')
 for(cause in causes){
  base<-historical[historical$method==m & historical$reason==cause,]
  fraction<-if(base$projected_actionable_original_method_endings>0)
   base$projected_nonmodern_at_month12/base$projected_actionable_original_method_endings else 0
  cr[[paste(m,cause)]]<-data.frame(method=m,reason=cause,current_users_2024=stock,
   aft_cause_probability_pct=100*prob[cause],survival_original_method_endings=stock*prob[cause],
   historical_fraction_nonmodern_at_year_end=fraction,
   aft_pathway_nonmodern_at_year_end=stock*prob[cause]*fraction)
 }
}
out<-do.call(rbind,rows);cause_out<-do.call(rbind,cr);rownames(out)<-rownames(cause_out)<-NULL
out$survival_pathway_nonmodern_at_year_end<-vapply(out$method,function(m)sum(cause_out$aft_pathway_nonmodern_at_year_end[cause_out$method==m]),0.0)
write.csv(out,file.path(sup,'drc_survival_model_duration_by_method.csv'),row.names=FALSE)
write.csv(cause_out,file.path(sup,'drc_survival_model_duration_by_method_cause.csv'),row.names=FALSE)
scenario$aft_actionable_endings<-sum(out$survival_original_method_endings)
scenario$aft_pathway_nonmodern_year_end<-sum(out$survival_pathway_nonmodern_at_year_end)
scenario$aft_gross_pp<-100*scenario$aft_actionable_endings/scenario$wra_2025
scenario$aft_pathway_year_end_pp<-100*scenario$aft_pathway_nonmodern_year_end/scenario$wra_2025
write.csv(scenario,file.path(sup,'drc_2025_mcpr_scenarios.csv'),row.names=FALSE)
cat('AFT gross endings',sum(out$survival_original_method_endings),'year-end nonmodern',sum(out$survival_pathway_nonmodern_at_year_end),'pp',100*sum(out$survival_pathway_nonmodern_at_year_end)/scenario$wra_2025[1],'\n')
print(fit_report,row.names=FALSE)
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 09_drc_post_discontinuation_pathways.R
# LANGUAGE: R
MODULES[["09_drc_post_discontinuation_pathways.R"]] <- list(
  language="R",
  original_sha256="09ed4474cbb8ecedb2fc74dd4a7abbc79d5d4eed1ca146e8c43a8db3a5a8dfdc",
  packaged_sha256="09ed4474cbb8ecedb2fc74dd4a7abbc79d5d4eed1ca146e8c43a8db3a5a8dfdc",
  args=character(),
  code=r"-----(#!/usr/bin/env Rscript
# Descriptive status one and twelve months after an observed actionable
# original-method ending. This is a follow-up cohort, not a competing-risk
# life-table estimate. Only events with the respective follow-up month
# observable in the DHS calendar contribute at that checkpoint.
root <- Sys.getenv("DRC_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
out <- file.path(root,'output/Supporting_data')
e <- readRDS(file.path(root,'Data/Derived/drc_2023_24_modern_episodes.rds'))
all <- readRDS(file.path(root,'Data/Derived/drc_2023_24_calendar_events.rds'))
modern <- c(1L,2L,3L,5L,6L,7L,11L,13L,14L,15L,17L,18L,19L,20L)
eligible <- e[e$discontinued & e$exposure<=12 & e$reason_code %in% c(1L,4L,5L,6L,7L,8L,10L,15L),]
stopifnot(nrow(eligible)>100L)
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
write.csv(z,file.path(out,'drc_actionable_post_ending_pathways.csv'),row.names=FALSE)
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
write.csv(joint,file.path(out,'drc_actionable_post_ending_transitions.csv'),row.names=FALSE)
print(z)

# Ethiopia's earlier pathway slides follow endings for any reason other than
# wanted pregnancy and partner disapproval. Reproduce that broader intermediate
# cohort separately so it is not confused with the actionable-only follow-up.
eligible <- e[e$discontinued & e$exposure<=12 &
  !(e$reason_code %in% c(2L,3L)),]
stopifnot(nrow(eligible)>100L)
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
write.csv(selected,file.path(out,'drc_selected_reason_post_ending_pathways.csv'),row.names=FALSE)
d <- eligible[eligible$end+12L<=eligible$interview,]
code1 <- vapply(seq_len(nrow(d)),function(i)code_at(d,i,1L),integer(1))
code12 <- vapply(seq_len(nrow(d)),function(i)code_at(d,i,12L),integer(1))
d$status_month_1 <- mapply(status,code1,d$method_code)
d$status_month_12 <- mapply(status,code12,d$method_code)
joint <- aggregate(d$wt,list(month_1=d$status_month_1,month_12=d$status_month_12),sum)
names(joint)[3] <- 'weighted_events'
joint$share_of_common_cohort_pct <- 100*joint$weighted_events/sum(d$wt)
joint$observed_ending_events_n <- nrow(d)
write.csv(joint,file.path(out,'drc_selected_reason_post_ending_transitions.csv'),row.names=FALSE)
print(selected)
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 11_drc_raw_pairwise.R
# LANGUAGE: R
MODULES[["11_drc_raw_pairwise.R"]] <- list(
  language="R",
  original_sha256="414a64eef0080e3e8b6c13aa6b5498b97dcf0d64078af0888c30aa5f62319a83",
  packaged_sha256="414a64eef0080e3e8b6c13aa6b5498b97dcf0d64078af0888c30aa5f62319a83",
  args=character(),
  code=r"-----(#!/usr/bin/env Rscript
root <- Sys.getenv('DRC_PROJECT_ROOT', unset=normalizePath(file.path(getwd(),'..'),mustWork=FALSE))
b <- readRDS(file.path(root,'Data/Derived/drc_actionable_bootstrap.rds'))
r <- read.csv(file.path(root,'output/Supporting_data/drc_actionable_province_adjusted_rates.csv'))
for(t in c('3','12')){
  zones <- setdiff(r$zone,'National')
  pairs <- combn(zones,2,simplify=FALSE)
  out <- do.call(rbind,lapply(pairs,function(z){
    p1 <- r$unadjusted_pct[match(z[1],r$zone)];p2 <- r$unadjusted_pct[match(z[2],r$zone)]
    if(t=='3'){
      v <- read.csv(file.path(root,'output/Supporting_data/drc_modern_timepoints.csv'))
      p1 <- v$actionable_pct[v$scope==z[1]&v$month==3]
      p2 <- v$actionable_pct[v$scope==z[2]&v$month==3]
    }
    draws <- b[,z[1],t,'actionable']-b[,z[2],t,'actionable']
    se <- sd(draws,na.rm=TRUE);delta <- p1-p2
    data.frame(month=as.integer(t),province_1=z[1],province_2=z[2],difference_pp=delta,se_pp=se,
      ci_low=delta-1.96*se,ci_high=delta+1.96*se,p_raw=2*pnorm(-abs(delta/se)))
  }))
  out$p_holm <- p.adjust(out$p_raw,method='holm')
  out$significant_05 <- out$p_holm<.05
  write.csv(out,file.path(root,'output/Supporting_data',paste0('drc_actionable_raw_pairwise_',t,'month.csv')),row.names=FALSE)
  cat(t,'month:',sum(out$significant_05),'Holm-significant of',nrow(out),'pairs\n')
}
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 16_drc_province_adjusted_bootstrap.R
# LANGUAGE: R
MODULES[["16_drc_province_adjusted_bootstrap.R"]] <- list(
  language="R",
  original_sha256="7d54428a0492fbae6e72bb91646b18178a78fff1748ea4f01bc593fa2410e18f",
  packaged_sha256="7d54428a0492fbae6e72bb91646b18178a78fff1748ea4f01bc593fa2410e18f",
  args=character(),
  code=r"-----(#!/usr/bin/env Rscript
# Survey-stratified PSU bootstrap for DRC province-adjusted actionable risks.
# Input and output roots are supplied through DRC_PROJECT_ROOT.

root <- Sys.getenv('DRC_PROJECT_ROOT', unset=normalizePath('..',mustWork=FALSE))
support <- file.path(root,'output','Supporting_data')
derived <- file.path(root,'Data','Derived')
e <- readRDS(file.path(derived,'drc_2023_24_model_episode_covariates.rds'))
person <- readRDS(file.path(derived,'drc_2023_24_person_month.rds'))
point <- read.csv(file.path(support,'drc_actionable_province_adjusted_rates.csv'),check.names=FALSE)
zones <- as.character(point$zone[point$zone!='National'])
standard <- e[e$entry==0L,]

f1 <- outcome~month+method_group+zone_name
f2 <- outcome~month+method_group+zone_name+age_group+parity_group+
  marital_group+education+wealth+residence+start_year
fit <- function(formula,wts){
  person$fit_weight <- wts
  m <- nnet::multinom(formula,data=person,weights=fit_weight,trace=FALSE,
    maxit=350,MaxNWts=10000,Hess=FALSE)
  if(m$convergence!=0L)stop('Model did not converge')
  m
}
predict_cif <- function(model,zone,weights){
  d <- standard
  if(!is.na(zone))d$zone_name <- factor(zone,levels=levels(e$zone_name))
  survival <- rep(1,nrow(d)); cumulative <- numeric(nrow(d))
  for(t in 1:12){
    d$month <- factor(t,levels=1:12)
    p <- predict(model,newdata=d,type='probs')
    cumulative <- cumulative+survival*p[,'actionable']
    survival <- survival*p[,'continue']
  }
  100*weighted.mean(cumulative,weights)
}
frame <- full_survey_frame(); frame$id <- seq_len(nrow(frame))
groups <- split(frame$id,frame$stratum)
stopifnot(!anyDuplicated(frame$cluster))
# One analytic-sample stratum has only one contributing PSU. Hold that PSU
# fixed in the bootstrap; its between-PSU variance is not estimable here.
B <- as.integer(Sys.getenv('DRC_MODEL_BOOTSTRAP_REPS','120'))
one <- function(b){
  set.seed(20261030L+b)
  mult <- numeric(nrow(frame))
  for(ids in groups){
    n <- length(ids)
    mult[ids] <- if(n==1L) 1 else
      n/(n-1)*tabulate(sample.int(n,n-1,replace=TRUE),nbins=n)
  }
  lookup <- setNames(mult,frame$cluster)
  w <- person$wt*lookup[as.character(person$cluster)]
  sw <- standard$wt*lookup[as.character(standard$cluster)]
  m1 <- tryCatch(fit(f1,w),error=function(err)NULL)
  m2 <- tryCatch(fit(f2,w),error=function(err)NULL)
  if(is.null(m1)||is.null(m2))return(rep(NA_real_,2L*(length(zones)+1L)))
  c(vapply(c(NA_character_,zones),function(z)predict_cif(m1,z,sw),numeric(1)),
    vapply(c(NA_character_,zones),function(z)predict_cif(m2,z,sw),numeric(1)))
}
draws <- parallel::mclapply(seq_len(B),one,
  mc.cores=min(4L,parallel::detectCores()),mc.preschedule=FALSE)
draws <- do.call(rbind,draws)
colnames(draws) <- c(paste0('model1:',point$zone),paste0('model2:',point$zone))
valid <- complete.cases(draws)
message('Valid model refits: ',sum(valid),'/',B)
if(sum(valid)<max(30L,ceiling(.8*B)))stop('Insufficient successful bootstrap refits')
write.csv(draws,file.path(support,'drc_actionable_province_model_bootstrap.csv'),row.names=FALSE)
ci <- apply(draws[valid,,drop=FALSE],2,quantile,c(.025,.975),na.rm=TRUE)
n <- nrow(point)
point$model_1_low <- ci[1,seq_len(n)];point$model_1_high <- ci[2,seq_len(n)]
point$model_2_low <- ci[1,n+seq_len(n)];point$model_2_high <- ci[2,n+seq_len(n)]
point$small_actionable_cell <- point$actionable_endings_n<30L
write.csv(point,file.path(support,'drc_actionable_province_adjusted_rates.csv'),row.names=FALSE)

pairs <- combn(zones,2,simplify=FALSE)
out <- list()
for(stage in c('Method adjusted','Fully adjusted'))for(pair in pairs){
  stem <- if(stage=='Method adjusted')'model1:' else 'model2:'
  col <- if(stage=='Method adjusted')'model_1_common_mix_pct' else 'model_2_common_mix_pct'
  a<-pair[1];b<-pair[2]
  diff<-point[[col]][point$zone==a]-point[[col]][point$zone==b]
  v<-draws[valid,paste0(stem,a)]-draws[valid,paste0(stem,b)]
  se<-sd(v)
  out[[length(out)+1L]]<-data.frame(stage=stage,province_1=a,province_2=b,
    difference_pp=diff,ci_low=diff-1.96*se,ci_high=diff+1.96*se,
    p_value=2*pnorm(-abs(diff/se)),bootstrap_replicates=sum(valid),
    small_cell=point$small_actionable_cell[point$zone==a]|
      point$small_actionable_cell[point$zone==b])
}
tests<-do.call(rbind,out)
tests$p_holm<-ave(tests$p_value,tests$stage,FUN=function(p)p.adjust(p,'holm'))
tests$significant_05<-tests$p_holm<.05
tests$significant_10<-tests$p_holm<.10
write.csv(tests,file.path(support,'drc_actionable_adjusted_pairwise.csv'),row.names=FALSE)
print(aggregate(significant_05~stage,tests,sum),row.names=FALSE)
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 17_drc_selected_reason_subgroups.R
# LANGUAGE: R
MODULES[["17_drc_selected_reason_subgroups.R"]] <- list(
  language="R",
  original_sha256="d53d32491ff604ecc081fe41c61f56123ba5a5b2a4c0b9594839538a258ff34b",
  packaged_sha256="d53d32491ff604ecc081fe41c61f56123ba5a5b2a4c0b9594839538a258ff34b",
  args=character(),
  code=r"-----(#!/usr/bin/env Rscript
# Selected-reason discontinuation: all reasons except wanting pregnancy and
# partner disapproval. Other fertility-related and unresolved reasons remain.
# Uses the same delayed-entry, competing-risk, weighted life-table convention.

root <- Sys.getenv('DRC_PROJECT_ROOT', unset=normalizePath('..',mustWork=FALSE))
support <- file.path(root,'output','Supporting_data')
derived <- file.path(root,'Data','Derived')
e <- readRDS(file.path(derived,'drc_2023_24_model_episode_covariates.rds'))
selected <- function(z)!is.na(z) & !(z %in% c(2L,3L))
reason_codes <- list(method_failure=1L,want_more_effective=7L,
  bleeding=15L,other_health=c(4L,5L),access_cost_convenience=c(6L,8L,10L),
  other_fertility=c(9L,12L,13L))
life <- function(d,w=d$wt,month=12L){
  survival <- 1; result <- 0
  for(t in seq_len(month)){
    at <- d$entry<t & d$exposure>=t
    denom <- sum(w[at])
    if(denom<=0)return(NA_real_)
    ending <- at & d$exposure==t & d$discontinued
    result <- result+survival*sum(w[ending & selected(d$reason_code)])/denom
    survival <- survival*(1-sum(w[ending])/denom)
  }
  100*result
}
reason_life <- function(d){
  survival <- 1; cif <- numeric(length(reason_codes)+1L)
  names(cif) <- c(names(reason_codes),'other_recorded')
  for(t in 1:12){
    at <- d$entry<t & d$exposure>=t
    denom <- sum(d$wt[at])
    if(denom<=0){cif[]<-NA_real_;return(cif)}
    ending <- at & d$exposure==t & d$discontinued
    event <- d$reason_code
    for(j in seq_along(reason_codes))
      cif[j] <- cif[j]+survival*sum(d$wt[ending & event %in% reason_codes[[j]]])/denom
    other <- ending & selected(event) &
      !(event %in% unlist(reason_codes,use.names=FALSE))
    cif[length(cif)] <- cif[length(cif)]+survival*sum(d$wt[other])/denom
    survival <- survival*(1-sum(d$wt[ending])/denom)
  }
  100*cif
}
scopes <- list(National=seq_len(nrow(e)))
for(v in c('method_group','age_group','parity_group','marital_group',
           'education','wealth','residence','zone_name')){
  for(value in levels(e[[v]]))
    scopes[[paste(v,value,sep='::')]] <- which(e[[v]]==value)
}
for(pair in list(c('age_group','parity_group'),c('age_group','method_group'),
                 c('parity_group','method_group'))){
  a <- pair[1];b <- pair[2]
  for(av in levels(e[[a]]))for(bv in levels(e[[b]]))
    scopes[[paste(a,b,av,bv,sep='::')]] <- which(e[[a]]==av & e[[b]]==bv)
}
scopes <- scopes[lengths(scopes)>0L]
point <- do.call(rbind,lapply(names(scopes),function(key){
  d <- e[scopes[[key]],]
  n <- sum(d$discontinued & d$exposure<=12 & selected(d$reason_code))
  cause <- reason_life(d); total <- sum(cause)
  shares <- if(is.finite(total) && total>0)100*cause/total else
    rep(NA_real_,length(cause))
  names(cause) <- paste0('risk_',names(cause))
  names(shares) <- paste0('share_',sub('^risk_','',names(cause)))
  data.frame(group=key,eligible_episodes_n=nrow(d),
    weighted_episodes=sum(d$wt),selected_endings_n=n,
    selected_3_month_pct=life(d,month=3L),
    selected_6_month_pct=life(d,month=6L),
    selected_9_month_pct=life(d,month=9L),
    selected_12_month_pct=life(d,month=12L),
    as.list(cause),as.list(shares),
    limited_precision=n<30L)
}))
frame <- full_survey_frame();frame$id <- seq_len(nrow(frame))
stopifnot(!anyDuplicated(frame$cluster))
groups <- split(frame$id,frame$stratum)
B <- as.integer(Sys.getenv('DRC_SELECTED_BOOTSTRAP_REPS','120'))
draw <- matrix(NA_real_,B,nrow(point))
for(b in seq_len(B)){
  set.seed(20261030L+b)
  mult <- numeric(nrow(frame))
  for(ids in groups){
    n <- length(ids)
    mult[ids] <- if(n==1L)1 else n/(n-1)*
      tabulate(sample.int(n,n-1,replace=TRUE),nbins=n)
  }
  lookup <- setNames(mult,frame$cluster)
  for(j in seq_along(scopes)){
    d <- e[scopes[[j]],]
    draw[b,j] <- life(d,d$wt*lookup[as.character(d$cluster)])
  }
}
point$ci_low <- apply(draw,2,quantile,.025,na.rm=TRUE)
point$ci_high <- apply(draw,2,quantile,.975,na.rm=TRUE)
write.csv(point,file.path(support,'drc_selected_reason_subgroups.csv'),row.names=FALSE)
cat('Groups:',nrow(point),'national:',point$selected_12_month_pct[point$group=='National'],'\n')
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 18_drc_method_timing.R
# LANGUAGE: R
MODULES[["18_drc_method_timing.R"]] <- list(
  language="R",
  original_sha256="d49582282d4725d193e95029f339e1e0cb5e8c7b60198c62a1182c0647d431ae",
  packaged_sha256="d49582282d4725d193e95029f339e1e0cb5e8c7b60198c62a1182c0647d431ae",
  args=character(),
  code=r"-----(#!/usr/bin/env Rscript
# Recreate weighted monthly competing-risk life tables for the presentation.
args <- grep('^--file=', commandArgs(FALSE), value=TRUE)
default_root <- if(length(args)) normalizePath(file.path(dirname(sub('^--file=','',args[1])),'..')) else normalizePath('..')
root <- Sys.getenv('DRC_PROJECT_ROOT', unset=default_root)
e <- readRDS(file.path(root,'Data','Derived','drc_2023_24_modern_episodes.rds'))
out <- file.path(root,'output','Supporting_data')
dir.create(out,recursive=TRUE,showWarnings=FALSE)
actionable <- c(1L,4L,5L,6L,7L,8L,10L,15L)
life <- function(d){
  s <- 1; all <- 0; act <- 0; rows <- vector('list',12)
  for(t in seq_len(12)){
    at <- d$entry<t & d$exposure>=t
    risk <- sum(d$wt[at])
    if(risk<=0) stop('No risk set at month ',t)
    ending <- at & d$exposure==t & d$discontinued
    all <- all+s*sum(d$wt[ending])/risk
    act <- act+s*sum(d$wt[ending & d$reason_code%in%actionable])/risk
    s <- s*(1-sum(d$wt[ending])/risk)
    rows[[t]] <- data.frame(month=t,all_reason_pct=100*all,actionable_pct=100*act)
  }
  do.call(rbind,rows)
}
groups <- c('All modern','Injectables','Implants','Pill','IUD','Other modern')
rows <- lapply(groups,function(g){
  d <- if(g=='All modern') e else e[e$method_group==g,]
  z <- life(d);z$method <- g;z$eligible_episodes_n <- nrow(d)
  z
})
monthly <- do.call(rbind,rows)
rownames(monthly) <- NULL
check <- read.csv(file.path(out,'drc_modern_timepoints.csv'),check.names=FALSE)
for(g in groups){
  scope <- if(g=='All modern') 'National' else paste0('National: ',g)
  a <- monthly[monthly$method==g & monthly$month%in%c(3,6,9,12),]
  b <- check[check$scope==scope,]
  b <- b[match(a$month,b$month),]
  stopifnot(nrow(a)==4,nrow(b)==4,max(abs(a$all_reason_pct-b$all_reason_pct))<1e-8,
            max(abs(a$actionable_pct-b$actionable_pct))<1e-8)
}
write.csv(monthly,file.path(out,'drc_method_timing_monthly.csv'),row.names=FALSE)
cat('Validated all 3-, 6-, 9-, and 12-month values for 6 method groups.\n')
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 26_drc_reference_slide_data.R
# LANGUAGE: R
MODULES[["26_drc_reference_slide_data.R"]] <- list(
  language="R",
  original_sha256="8efdf2138c496d743d247076ddd5d715322f251be7d22c509a5d7b9b27f56e0f",
  packaged_sha256="8efdf2138c496d743d247076ddd5d715322f251be7d22c509a5d7b9b27f56e0f",
  args=character(),
  code=r"-----(#!/usr/bin/env Rscript
# Supporting national tables for the Ethiopia-sequence DRC presentation.
args<-grep('^--file=',commandArgs(FALSE),value=TRUE)
default_root<-if(length(args))normalizePath(file.path(dirname(sub('^--file=','',args[1])),'..')) else normalizePath('..')
root<-Sys.getenv('DRC_PROJECT_ROOT',unset=default_root)
support<-file.path(root,'output','Supporting_data')
e<-readRDS(file.path(root,'Data','Derived','drc_2023_24_modern_episodes.rds'))
all_e<-readRDS(file.path(root,'Data','Derived','drc_2023_24_table_7_13_episodes.rds'))
groups<-c('All modern','Injectables','Implants','Pill','IUD','Other modern')
reasons<-list('Method failure'=1L,'Wanted pregnancy'=2L,'Other fertility'=c(9L,12L,13L),
 'Bleeding changes'=15L,'Other health'=c(4L,5L),'More effective'=7L,
 'Access/cost/convenience'=c(6L,8L,10L),'Partner disapproval'=3L)
reason_name<-function(code){
 for(n in names(reasons))if(code%in%reasons[[n]])return(n)
 'Other recorded'
}
rows<-list();dist<-list();k<-0
for(g in groups){
 d<-if(g=='All modern')e else e[e$method_group==g,]
 s<-1;cv<-setNames(numeric(length(reasons)+1),c(names(reasons),'Other recorded'))
 for(t in 1:12){
  at<-d$entry<t & d$exposure>=t;risk<-sum(d$wt[at]);if(risk<=0)break
  ended<-at & d$exposure==t & d$discontinued
  for(n in names(cv)){
   match<-vapply(d$reason_code[ended],reason_name,character(1))==n
   cv[n]<-cv[n]+s*sum(d$wt[ended][match])/risk
  }
  s<-s*(1-sum(d$wt[ended])/risk)
 }
 for(n in names(cv)){
  k<-k+1;rows[[k]]<-data.frame(method=g,reason=n,risk_pct=100*cv[n],share_of_12mo_endings_pct=if(sum(cv)>0)100*cv[n]/sum(cv) else NA)
 }
 d12<-d[d$discontinued & d$exposure<=12,]
 tab<-tapply(d12$wt,vapply(d12$reason_code,reason_name,character(1)),sum)
 for(n in names(cv))dist[[length(dist)+1L]]<-data.frame(method=g,reason=n,weighted_endings=if(n%in%names(tab))unname(tab[n]) else 0,
  share_of_recorded_endings_pct=if(n%in%names(tab))100*unname(tab[n])/sum(tab) else 0)
}
write.csv(do.call(rbind,rows),file.path(support,'drc_all_cause_method_reason_cif.csv'),row.names=FALSE)
write.csv(do.call(rbind,dist),file.path(support,'drc_all_cause_recorded_reason_shares.csv'),row.names=FALSE)
starts<-all_e[all_e$entry==0,]
starts$year<-(starts$start-1L)%/%12L+1900L
starts<-starts[starts$year>=2020 & starts$year<=2024,]
modern_codes<-c(1L,2L,3L,5L,6L,7L,11L,13L,14L,15L,17L,18L,19L,20L)
starts$group<-'Other modern'
starts$group[starts$method_code==1]<-'Pill'
starts$group[starts$method_code==2]<-'IUD'
starts$group[starts$method_code==3]<-'Injectables'
starts$group[starts$method_code==11]<-'Implants'
starts$group[starts$method_code==16]<-'Emergency contraception'
starts$group[!starts$method_code%in%c(modern_codes,16)]<-'Non-modern methods'
tot<-aggregate(wt~year,starts,sum)
mix<-aggregate(wt~year+group,starts,sum)
mix$share_pct<-100*mix$wt/tot$wt[match(mix$year,tot$year)]
write.csv(mix,file.path(support,'drc_method_start_mix_by_year.csv'),row.names=FALSE)
cat('Wrote all-reason method-reason and year-mix tables.\n')
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 27_drc_all_reason_subgroup_model.R
# LANGUAGE: R
MODULES[["27_drc_all_reason_subgroup_model.R"]] <- list(
  language="R",
  original_sha256="23961e2943cf3dd14d57c53d1c61dddc58e4f670b3a73d97f96fc4f0e78a2ec5",
  packaged_sha256="23961e2943cf3dd14d57c53d1c61dddc58e4f670b3a73d97f96fc4f0e78a2ec5",
  args=character(),
  code=r"-----(#!/usr/bin/env Rscript
# Survey-design adjusted all-reason first-year discontinuation probabilities.
args<-grep('^--file=',commandArgs(FALSE),value=TRUE)
default_root<-if(length(args))normalizePath(file.path(dirname(sub('^--file=','',args[1])),'..')) else normalizePath('..')
root<-Sys.getenv('DRC_PROJECT_ROOT',unset=default_root)
derived<-file.path(root,'Data','Derived');support<-file.path(root,'output','Supporting_data')
person<-readRDS(file.path(derived,'drc_2023_24_person_month.rds'))
episodes<-readRDS(file.path(derived,'drc_2023_24_model_episode_covariates.rds'))
person$any_end<-as.integer(person$outcome!='continue')
options(survey.lonely.psu='adjust')
design<-survey::svydesign(ids=~cluster,strata=~stratum,weights=~wt,data=complete_survey_data(person),nest=TRUE)
form<-any_end~month+method_group+zone_name+age_group+parity_group+marital_group+education+wealth+residence+start_year
fit<-survey::svyglm(form,design=design,family=quasibinomial())
saveRDS(fit,file.path(derived,'drc_all_reason_full_model.rds'))
reference<-episodes[episodes$entry==0,]
vars<-c('method_group','age_group','parity_group','marital_group','education','wealth','residence')
predict_rate<-function(variable,value){
 d<-reference
 d[[variable]]<-factor(value,levels=levels(d[[variable]]))
 survival<-rep(1,nrow(d));score<-matrix(0,nrow(d),length(coef(fit)))
 for(t in 1:12){
  d$month<-factor(t,levels=1:12)
  x<-model.matrix(delete.response(terms(fit)),d)
  p<-as.numeric(predict(fit,newdata=d,type='response'))
  score<-score+x*p
  survival<-survival*(1-p)
 }
 point<-100*weighted.mean(1-survival,d$wt)
 gradient<-100*colSums(score*(survival*d$wt))/sum(d$wt)
 se<-sqrt(as.numeric(t(gradient)%*%vcov(fit)%*%gradient))
 c(adjusted_12mo_pct=point,ci_low=max(0,point-1.96*se),ci_high=min(100,point+1.96*se))
}
rows<-list()
for(v in vars)for(level in levels(reference[[v]])){
 rows[[length(rows)+1L]]<-data.frame(covariate=v,category=level,t(predict_rate(v,level)))
}
out<-do.call(rbind,rows)
write.csv(out,file.path(support,'drc_all_reason_adjusted_subgroups.csv'),row.names=FALSE)
cat('Fitted all-reason survey model; ',nrow(out),' adjusted subgroup estimates.\n',sep='')
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 28_drc_province_mcpr.R
# LANGUAGE: R
MODULES[["28_drc_province_mcpr.R"]] <- list(
  language="R",
  original_sha256="2028d0c8ad918202c60f141bb73fba923390e5c72c65817681229606e03b50c8",
  packaged_sha256="2028d0c8ad918202c60f141bb73fba923390e5c72c65817681229606e03b50c8",
  args=character(),
  code=r"-----(#!/usr/bin/env Rscript
args<-grep('^--file=',commandArgs(FALSE),value=TRUE)
default_root<-if(length(args))normalizePath(file.path(dirname(sub('^--file=','',args[1])),'..')) else normalizePath('..')
root<-Sys.getenv('DRC_PROJECT_ROOT',unset=default_root)
ir<-as.data.frame(haven::read_dta(Sys.getenv('DRC_IR_FILE',unset=file.path(root,'Data','CDIR81FL.dta')),
 col_select=c(v005,v024,v313)))
names26<-c('Kinshasa','Kongo Central','Kwango','Kwilu','Mai-Ndombe','Équateur','Nord-Ubangi','Sud-Ubangi','Mongala','Tshuapa','Tshopo','Bas-Uélé','Haut-Uélé','Ituri','Nord-Kivu','Sud-Kivu','Maniema','Haut-Katanga','Haut-Lomami','Lualaba','Tanganyika','Lomami','Sankuru','Kasaï Oriental','Kasaï','Kasaï Central')
ir$wt<-as.numeric(ir$v005)/1e6;ir$modern<-as.numeric(ir$v313)==3L
ir$province<-names26[as.integer(ir$v024)]
rows<-lapply(c('National',names26),function(z){d<-if(z=='National')ir else ir[ir$province==z,]
 data.frame(province=z,women_n=nrow(d),weighted_women=sum(d$wt),mcpr_all_women_pct=100*sum(d$wt[d$modern])/sum(d$wt))})
write.csv(do.call(rbind,rows),file.path(root,'output','Supporting_data','drc_province_mcpr.csv'),row.names=FALSE)
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 32_drc_actionable_subgroup_predictions.R
# LANGUAGE: R
MODULES[["32_drc_actionable_subgroup_predictions.R"]] <- list(
  language="R",
  original_sha256="8b480839eac8a27a8c06f8e440a3df9154f4080578851224be21187d08a67f90",
  packaged_sha256="8b480839eac8a27a8c06f8e440a3df9154f4080578851224be21187d08a67f90",
  args=character(),
  code=r"-----(#!/usr/bin/env Rscript
# Survey-stratified PSU-bootstrap marginal 12-month actionable CIFs by subgroup.
args <- grep('^--file=', commandArgs(FALSE), value=TRUE)
default_root <- normalizePath(file.path(dirname(sub('^--file=', '', args[1])), '..'))
root <- Sys.getenv('DRC_PROJECT_ROOT', unset=default_root)
library(nnet)
derived <- file.path(root, 'Data', 'Derived')
support <- file.path(root, 'output', 'Supporting_data')
e <- readRDS(file.path(derived, 'drc_2023_24_model_episode_covariates.rds'))
person <- readRDS(file.path(derived, 'drc_2023_24_person_month.rds'))
model <- readRDS(file.path(derived, 'drc_actionable_province_model_2.rds'))
reference <- e[e$entry == 0L, ]
vars <- c('age_group', 'parity_group', 'marital_group', 'education', 'wealth', 'residence')
spec <- do.call(rbind, lapply(vars, function(v)
  data.frame(covariate=v, category=levels(reference[[v]]))))
predict_one <- function(fit, d, w) {
  survival <- rep(1, nrow(d)); cumulative <- numeric(nrow(d))
  for (t in 1:12) {
    d$month <- factor(t, levels=1:12)
    p <- predict(fit, newdata=d, type='probs')
    cumulative <- cumulative + survival * p[, 'actionable']
    survival <- survival * p[, 'continue']
  }
  100 * weighted.mean(cumulative, w)
}
predict_all <- function(fit, w) {
  vapply(seq_len(nrow(spec)), function(i) {
    d <- reference
    v <- spec$covariate[i]
    d[[v]] <- factor(spec$category[i], levels=levels(reference[[v]]))
    predict_one(fit, d, w)
  }, numeric(1))
}
point <- predict_all(model, reference$wt)
frame <- full_survey_frame(); frame$id <- seq_len(nrow(frame))
groups <- split(frame$id, frame$stratum)
stopifnot(!anyDuplicated(frame$cluster))
B <- as.integer(Sys.getenv('DRC_SUBGROUP_BOOTSTRAP_REPS', '120'))
one <- function(b) {
  set.seed(20261030L + b)
  mult <- numeric(nrow(frame))
  for (ids in groups) {
    n <- length(ids)
    mult[ids] <- if (n == 1L) 1 else
      n / (n - 1) * tabulate(sample.int(n, n - 1, replace=TRUE), nbins=n)
  }
  lookup <- setNames(mult, frame$cluster)
  w <- person$wt * lookup[as.character(person$cluster)]
  sw <- reference$wt * lookup[as.character(reference$cluster)]
  person$fit_weight <- w
  fit <- tryCatch(nnet::multinom(
    outcome ~ month + method_group + zone_name + age_group + parity_group +
      marital_group + education + wealth + residence + start_year,
    data=person, weights=fit_weight, trace=FALSE, maxit=350,
    MaxNWts=10000, Hess=FALSE), error=function(err) NULL)
  if (is.null(fit) || fit$convergence != 0L)
    return(rep(NA_real_, nrow(spec)))
  tryCatch(predict_all(fit, sw), error=function(err) rep(NA_real_, nrow(spec)))
}
draws <- parallel::mclapply(seq_len(B), one,
  mc.cores=min(4L, parallel::detectCores()), mc.preschedule=FALSE)
draws <- do.call(rbind, draws)
valid <- complete.cases(draws)
cat('Valid bootstrap replicates:', sum(valid), '/', B, '\n')
if (sum(valid) < max(30L, ceiling(.8 * B)))
  stop('Insufficient successful survey-bootstrap model refits')
ci <- apply(draws[valid, , drop=FALSE], 2, quantile, c(.025, .975))
spec$adjusted_12mo_pct <- point
spec$ci_low <- ci[1, ]; spec$ci_high <- ci[2, ]
spec$bootstrap_replicates <- sum(valid)
write.csv(spec, file.path(support, 'drc_actionable_adjusted_subgroups.csv'), row.names=FALSE)
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 34_drc_html_extra_analyses.R
# LANGUAGE: R
MODULES[["34_drc_html_extra_analyses.R"]] <- list(
  language="R",
  original_sha256="a70af052f11ad01c4f6addd114122cf201b692c9b6154a51c5f7cc1368f2a289",
  packaged_sha256="4c4728e5d570340d50b32186df7848a892b244dbf9dc1a44db31fcae710a41e1",
  args=character(),
  code=r"-----(#!/usr/bin/env Rscript
# DRC descriptive analyses needed for the Ethiopia-sequence HTML.
args <- grep('^--file=', commandArgs(FALSE), value=TRUE)
root <- Sys.getenv('DRC_PROJECT_ROOT', unset=normalizePath(file.path(
  dirname(sub('^--file=', '', args[1])), '..')))
e <- readRDS(file.path(root, 'Data', 'Derived',
                       'drc_2023_24_modern_episodes.rds'))
support <- file.path(root, 'output', 'Supporting_data')
labels <- c('1'='Method failure', '2'='Wanted pregnancy',
            '3'='Partner disapproval', '4'='Other side effects/health', '5'='Other side effects/health',
            '6'='Access/cost/convenience', '7'='Want more effective method',
            '8'='Access/cost/convenience', '9'='Infrequent sex/husband away',
            '10'='Access/cost/convenience', '11'='Other recorded: fatalistic',
            '12'='Difficulty becoming pregnant/menopause',
            '13'='Marital dissolution/separation',
            '15'='Changes in menstrual bleeding',
            '96'='Other recorded: other', '98'='Other recorded: unknown',
            '99'='Other recorded: missing')
e$class <- ifelse(e$method_group %in% c('Injectables','Pill'),
                  'Short-acting reversible',
           ifelse(e$method_group %in% c('Implants','IUD'),
                  'Long-acting reversible','Other continuing modern'))
event <- e[e$discontinued & e$exposure<=12, ]
event$reason_label <- labels[as.character(event$reason_code)]
event$reason_label[is.na(event$reason_label)] <- 'Other recorded: unclassified'
counts <- aggregate(event$wt, list(reason=event$reason_label), sum)
names(counts)[2] <- 'weighted_endings'
counts$observed_endings_n <- as.integer(table(event$reason_label)[counts$reason])
counts$share_pct <- 100*counts$weighted_endings/sum(counts$weighted_endings)
counts <- counts[order(-counts$weighted_endings), ]
write.csv(counts,file.path(support,'drc_first_year_detailed_reason_counts.csv'),row.names=FALSE)

# Competing-risk 12-month cumulative incidence within method-duration classes.
actionable <- c(1L,4L,5L,6L,7L,8L,10L,15L)
calc <- function(d) {
  surv <- 1; all <- 0; selected <- 0; action <- 0
  for(t in 1:12) {
    risk <- sum(d$wt[d$entry<t & d$exposure>=t])
    if(risk<=0) next
    end <- d$discontinued & d$exposure==t
    ha <- sum(d$wt[end])/risk
    hs <- sum(d$wt[end & !(d$reason_code %in% c(2L,3L))])/risk
    hp <- sum(d$wt[end & d$reason_code %in% actionable])/risk
    all <- all+surv*ha; selected <- selected+surv*hs; action <- action+surv*hp
    surv <- surv*(1-ha)
  }
  data.frame(eligible_episodes_n=nrow(d),weighted_episodes=sum(d$wt),
    all_reason_12mo_pct=100*all,selected_reason_12mo_pct=100*selected,
    actionable_12mo_pct=100*action)
}
classes <- do.call(rbind,lapply(split(e,e$class),calc))
classes$class <- rownames(classes);rownames(classes) <- NULL
write.csv(classes,file.path(support,'drc_duration_class_12mo_rates.csv'),row.names=FALSE)

short <- event[event$class=='Short-acting reversible' &
                 !(event$reason_code %in% c(2L,3L)), ]
short_counts <- aggregate(short$wt,list(reason=short$reason_label),sum)
names(short_counts)[2] <- 'weighted_endings'
short_counts$share_pct <- 100*short_counts$weighted_endings/sum(short_counts$weighted_endings)
short_counts <- short_counts[order(-short_counts$weighted_endings), ]
write.csv(short_counts,file.path(support,'drc_short_acting_selected_reason_shares.csv'),row.names=FALSE)
province_events <- split(event,event$province)
province_reasons <- do.call(rbind,lapply(names(province_events),function(province) {
 x <- province_events[[province]]
 tab <- aggregate(x$wt,list(reason=x$reason_label),sum)
 names(tab)[2] <- 'weighted_endings'
 tab$province <- province
 tab$share_of_endings_pct <- 100*tab$weighted_endings/sum(x$wt)
 tab$observed_endings_n <- nrow(x)
 tab
}))
province_reasons <- province_reasons[,c('province','reason','weighted_endings',
                                        'share_of_endings_pct','observed_endings_n')]
write.csv(province_reasons,file.path(support,
  'drc_all_reason_province_reason_shares.csv'),row.names=FALSE)
# DHS Table 7.14 uses reported reason-months, not first-year episode runs.
ir <- if(file.exists(file.path(root,'Data/ir.rds')))readRDS(file.path(root,'Data/ir.rds'))else as.data.frame(haven::read_dta(Sys.getenv('DRC_IR_FILE',unset=file.path(root,'Data/CDIR81FL.dta'))))
modern_codes <- c(1L,2L,3L,4L,5L,6L,7L,11L,13L,14L,15L,17L,18L)
method_chars <- strsplit('123456789WNALCFEMS~','')[[1]]
reason_chars <- c('1'=1L,'2'=2L,'3'=3L,'4'=4L,'5'=5L,'6'=6L,'7'=7L,'8'=8L,'9'=9L,'C'=10L,'F'=11L,'A'=12L,'D'=13L,'M'=15L,'W'=96L,'K'=98L,'?'=99L)
five <- do.call(rbind,lapply(0:59,function(t){
 p<-as.integer(ir$v018)+t;r<-substring(ir$vcal_2,p,p);method<-match(substring(ir$vcal_1,p,p),method_chars)
 i<-which(nzchar(trimws(r))&method%in%modern_codes)
 data.frame(method_code=method[i],reason_code=unname(reason_chars[r[i]]),wt=as.numeric(ir$v005[i])/1e6)
}))
five$method <- ifelse(five$method_code==1L,'Pill',
               ifelse(five$method_code==2L,'IUD',
               ifelse(five$method_code==3L,'Injectables',
               ifelse(five$method_code==11L,'Implants','Other modern'))))
five$reason <- labels[as.character(five$reason_code)]
five$reason[is.na(five$reason)] <- 'Other recorded: unclassified'
five_counts <- aggregate(five$wt,list(method=five$method,reason=five$reason),sum)
names(five_counts)[3] <- 'weighted_endings'
denom <- tapply(five$wt,five$method,sum)
five_counts$share_within_method_pct <- 100*five_counts$weighted_endings/
  denom[five_counts$method]
five_counts$observed_endings_n <- as.integer(table(five$method,five$reason)[
  cbind(five_counts$method,five_counts$reason)])
write.csv(five_counts,file.path(support,
  'drc_five_year_reason_distribution_by_method.csv'),row.names=FALSE)
cat('Wrote detailed reasons, method-duration class risks, and short-acting reason shares.\n')
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 36_drc_other_reason_followup.R
# LANGUAGE: R
MODULES[["36_drc_other_reason_followup.R"]] <- list(
  language="R",
  original_sha256="f9f4e9997155e3a6cc6728b9a842e7068da5d545122bf6bbaf63ec4787ce612b",
  packaged_sha256="f9f4e9997155e3a6cc6728b9a842e7068da5d545122bf6bbaf63ec4787ce612b",
  args=character(),
  code=r"-----(#!/usr/bin/env Rscript
# Observed status at months 1 and 12 after each detailed Other reason.
args <- grep('^--file=', commandArgs(FALSE), value=TRUE)
root <- Sys.getenv('DRC_PROJECT_ROOT', unset=normalizePath(file.path(
  dirname(sub('^--file=', '', args[1])), '..')))
support <- file.path(root,'output','Supporting_data')
e <- readRDS(file.path(root,'Data','Derived','drc_2023_24_modern_episodes.rds'))
calendar <- readRDS(file.path(root,'Data','Derived','drc_2023_24_calendar_events.rds'))
modern <- c(1L,2L,3L,5L,6L,7L,11L,13L,14L,15L,17L,18L,19L,20L)
reason <- c('9'='Infrequent sex/husband away',
            '12'='Difficulty becoming pregnant/menopause',
            '13'='Marital dissolution/separation',
            '11'='Other recorded: fatalistic',
            '96'='Other recorded: other',
            '98'='Other recorded: unknown',
            '99'='Other recorded: missing')
d <- e[e$discontinued & e$exposure<=12 &
         e$reason_code %in% as.integer(names(reason)) &
         e$end+12L<=e$interview,]
indices <- split(seq_len(nrow(calendar)),calendar$woman_row)
get_code <- function(row,k) {
 x <- calendar[indices[[as.character(row$woman_row)]],]
 i <- which(x$start<=row$end+k & x$end>=row$end+k)
 if(length(i)!=1L)stop('Calendar timeline is not uniquely partitioned')
 x$method_code[i]
}
status <- function(code,original) {
 if(code %in% modern)
   return(if(code==original)'Same modern method' else 'Different modern method')
 if(code %in% c(8L,9L,10L,12L,99L))return('Traditional/other method')
 if(code %in% c(81L,82L,83L))return('Pregnant, birth or termination')
 if(code==0L)return('No method recorded')
 'Other/unknown'
}
d$reason <- reason[as.character(d$reason_code)]
out <- list()
for(code in names(reason)) {
 x <- d[d$reason_code==as.integer(code),]
 if(!nrow(x))next
 for(k in c(1L,12L)) {
   states <- vapply(seq_len(nrow(x)),function(i)
     status(get_code(x[i,],k),x$method_code[i]),character(1))
   tab <- aggregate(x$wt,list(status=states),sum)
   names(tab)[2] <- 'weighted_events'
   tab$reason <- reason[[code]];tab$month_after_ending <- k
   tab$observed_ending_events_n <- nrow(x)
   tab$weighted_ending_events <- sum(x$wt)
   tab$share_pct <- 100*tab$weighted_events/sum(x$wt)
   out[[length(out)+1L]] <- tab
 }
}
z <- do.call(rbind,out)
z <- z[,c('reason','month_after_ending','status','observed_ending_events_n',
         'weighted_ending_events','weighted_events','share_pct')]
write.csv(z,file.path(support,'drc_other_reason_followup.csv'),row.names=FALSE)
cat('Wrote',nrow(z),'code-specific follow-up cells.\n')
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 37_drc_selected_reason_province_models.R
# LANGUAGE: R
MODULES[["37_drc_selected_reason_province_models.R"]] <- list(
  language="R",
  original_sha256="3dbde19b019799410c50e218a55d6aaffea4b70040f7d69a2fec2482af55aba7",
  packaged_sha256="3dbde19b019799410c50e218a55d6aaffea4b70040f7d69a2fec2482af55aba7",
  args=character(),
  code=r"-----(#!/usr/bin/env Rscript
# DRC selected-reason province models, including survey-stratified PSU intervals.
args <- grep('^--file=', commandArgs(FALSE), value=TRUE)
root <- Sys.getenv('DRC_PROJECT_ROOT', unset=normalizePath(file.path(
  dirname(sub('^--file=', '', args[1])), '..')))
library(nnet)
derived <- file.path(root,'Data','Derived')
support <- file.path(root,'output','Supporting_data')
e <- readRDS(file.path(derived,'drc_2023_24_model_episode_covariates.rds'))
person <- readRDS(file.path(derived,'drc_2023_24_person_month.rds'))
raw <- read.csv(file.path(support,'drc_selected_reason_subgroups.csv'))
observed_months <- pmax(0L,pmin(12L,e$exposure)-e$entry)
idx <- rep(seq_len(nrow(e)),observed_months)
month <- unlist(Map(function(first,n)seq.int(first+1L,length.out=n),
  e$entry,observed_months),use.names=FALSE)
stopifnot(length(idx)==nrow(person))
ending <- e$discontinued[idx] & month==e$exposure[idx]
person$outcome <- factor(ifelse(!ending,'continue',
  ifelse(e$reason_code[idx] %in% c(2L,3L),'competing','selected')),
  levels=c('continue','selected','competing'))
reference <- e[e$entry==0L,]
zones <- levels(e$zone_name)
f1 <- outcome~month+method_group+zone_name
f2 <- outcome~month+method_group+zone_name+age_group+parity_group+
  marital_group+education+wealth+residence+start_year
fit <- function(formula,weights) {
  person$fit_weight <- weights
  m <- nnet::multinom(formula,data=person,weights=fit_weight,trace=FALSE,
    maxit=350,MaxNWts=10000,Hess=FALSE)
  if(m$convergence!=0L)stop('Model did not converge')
  m
}
predict_cif <- function(model,zone,weights) {
  d <- reference
  d$zone_name <- factor(zone,levels=levels(e$zone_name))
  survival <- rep(1,nrow(d));cum <- numeric(nrow(d))
  for(t in 1:12) {
    d$month <- factor(t,levels=1:12)
    p <- predict(model,newdata=d,type='probs')
    cum <- cum+survival*p[,'selected']
    survival <- survival*p[,'continue']
  }
  100*weighted.mean(cum,weights)
}
m1 <- fit(f1,person$wt);m2 <- fit(f2,person$wt)
saveRDS(m1,file.path(derived,'drc_selected_reason_province_model_1.rds'))
saveRDS(m2,file.path(derived,'drc_selected_reason_province_model_2.rds'))
point <- data.frame(province=zones,
  method_adjusted_pct=vapply(zones,function(z)predict_cif(m1,z,reference$wt),numeric(1)),
  fully_adjusted_pct=vapply(zones,function(z)predict_cif(m2,z,reference$wt),numeric(1)))
frame <- full_survey_frame();frame$id <- seq_len(nrow(frame))
groups <- split(frame$id,frame$stratum)
B <- as.integer(Sys.getenv('DRC_SELECTED_MODEL_BOOTSTRAP_REPS','100'))
one <- function(b) {
  set.seed(20261101L+b)
  mult <- numeric(nrow(frame))
  for(ids in groups) {
    n <- length(ids)
    mult[ids] <- if(n==1L)1 else n/(n-1)*
      tabulate(sample.int(n,n-1,replace=TRUE),nbins=n)
  }
  lookup <- setNames(mult,frame$cluster)
  pw <- person$wt*lookup[as.character(person$cluster)]
  sw <- reference$wt*lookup[as.character(reference$cluster)]
  a <- tryCatch(fit(f1,pw),error=function(err)NULL)
  b <- tryCatch(fit(f2,pw),error=function(err)NULL)
  if(is.null(a)||is.null(b))return(rep(NA_real_,2*length(zones)))
  c(vapply(zones,function(z)predict_cif(a,z,sw),numeric(1)),
    vapply(zones,function(z)predict_cif(b,z,sw),numeric(1)))
}
draws <- parallel::mclapply(seq_len(B),one,mc.cores=min(4L,parallel::detectCores()),
  mc.preschedule=FALSE)
draws <- do.call(rbind,draws)
valid <- complete.cases(draws)
cat('Valid selected-reason bootstrap replicates:',sum(valid),'/',B,'\n')
if(sum(valid)<max(30L,ceiling(.8*B)))stop('Too few successful model refits')
ci <- apply(draws[valid,,drop=FALSE],2,quantile,c(.025,.975))
n <- length(zones)
point$method_adjusted_low <- ci[1,seq_len(n)]
point$method_adjusted_high <- ci[2,seq_len(n)]
point$fully_adjusted_low <- ci[1,n+seq_len(n)]
point$fully_adjusted_high <- ci[2,n+seq_len(n)]
raw_zone <- raw[raw$group %in% paste0('zone_name::',zones),]
point$observed_pct <- raw_zone$selected_12_month_pct[
  match(paste0('zone_name::',zones),raw_zone$group)]
point$observed_low <- raw_zone$ci_low[
  match(paste0('zone_name::',zones),raw_zone$group)]
point$observed_high <- raw_zone$ci_high[
  match(paste0('zone_name::',zones),raw_zone$group)]
point$eligible_episodes_n <- raw_zone$eligible_episodes_n[
  match(paste0('zone_name::',zones),raw_zone$group)]
point$selected_endings_n <- raw_zone$selected_endings_n[
  match(paste0('zone_name::',zones),raw_zone$group)]
point$small_cell <- point$selected_endings_n<30L
write.csv(point,file.path(support,'drc_selected_reason_province_adjusted_rates.csv'),row.names=FALSE)
tests <- list()
for(stage in c('Method adjusted','Fully adjusted')) {
 stem <- if(stage=='Method adjusted')'method_adjusted_pct' else 'fully_adjusted_pct'
 offset <- if(stage=='Method adjusted')0L else n
 for(pair in combn(seq_len(n),2,simplify=FALSE)) {
  i<-pair[1];j<-pair[2]
  delta<-point[[stem]][i]-point[[stem]][j]
  replicate_delta<-draws[valid,offset+i]-draws[valid,offset+j]
  se<-sd(replicate_delta)
  tests[[length(tests)+1L]]<-data.frame(stage=stage,province_1=zones[i],
    province_2=zones[j],difference_pp=delta,ci_low=delta-1.96*se,
    ci_high=delta+1.96*se,p_value=2*pnorm(-abs(delta/se)),
    small_cell=point$small_cell[i]|point$small_cell[j])
 }
}
tests<-do.call(rbind,tests)
tests$p_holm<-ave(tests$p_value,tests$stage,FUN=function(x)p.adjust(x,'holm'))
tests$significant_05<-tests$p_holm<.05
write.csv(tests,file.path(support,'drc_selected_reason_adjusted_pairwise.csv'),row.names=FALSE)
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 38_drc_injectable_reason_destinations.R
# LANGUAGE: R
MODULES[["38_drc_injectable_reason_destinations.R"]] <- list(
  language="R",
  original_sha256="bcace57c0ff6b6098893c3556dda1d8c724da3d7f042a9ca3ff1b2273df03dcf",
  packaged_sha256="bcace57c0ff6b6098893c3556dda1d8c724da3d7f042a9ca3ff1b2273df03dcf",
  args=character(),
  code=r"-----(#!/usr/bin/env Rscript
# Immediate status after actionable first-year injectable endings.
args <- grep('^--file=', commandArgs(FALSE), value=TRUE)
root <- Sys.getenv('DRC_PROJECT_ROOT', unset=normalizePath(file.path(
  dirname(sub('^--file=', '', args[1])), '..')))
support <- file.path(root,'output','Supporting_data')
e <- readRDS(file.path(root,'Data','Derived','drc_2023_24_modern_episodes.rds'))
cal <- readRDS(file.path(root,'Data','Derived','drc_2023_24_calendar_events.rds'))
action <- c(1L,4L,5L,6L,7L,8L,10L,15L)
d <- e[e$method_group=='Injectables' & e$discontinued &
       e$exposure<=12 & e$reason_code %in% action &
       e$end+1L<=e$interview,]
reason <- function(x) {
 if(x==1L)return('Method failure')
 if(x==7L)return('Wanted more effective')
 if(x==15L)return('Bleeding changes')
 if(x %in% c(4L,5L))return('Other side effects/health')
 'Access/cost/convenience'
}
modern <- c(1L,2L,3L,5L,6L,7L,11L,13L,14L,15L,17L,18L,19L,20L)
status <- function(z,original) {
 if(z %in% modern)return(if(z==original)'Same modern method' else 'Different modern method')
 if(z %in% c(8L,9L,10L,12L,99L))return('Traditional/other method')
 if(z %in% c(81L,82L,83L))return('Pregnant, birth or termination')
 if(z==0L)return('No method recorded')
 'Other/unknown'
}
indices <- split(seq_len(nrow(cal)),cal$woman_row)
code <- function(row) {
 x <- cal[indices[[as.character(row$woman_row)]],]
 i <- which(x$start<=row$end+1L & x$end>=row$end+1L)
 if(length(i)!=1L)stop('Calendar timeline is not uniquely partitioned')
 x$method_code[i]
}
d$reason_group <- vapply(d$reason_code,reason,character(1))
d$destination <- vapply(seq_len(nrow(d)),function(i)
  status(code(d[i,]),d$method_code[i]),character(1))
d$ending_month_group <- cut(d$exposure,c(0,3,6,12),
                            labels=c('Months 1–3','Months 4–6','Months 7–12'))
tab <- aggregate(d$wt,list(reason=d$reason_group,destination=d$destination),sum)
names(tab)[3] <- 'weighted_endings'
denom <- tapply(d$wt,d$reason_group,sum)
tab$share_within_reason_pct <- 100*tab$weighted_endings/denom[tab$reason]
tab$observed_endings_n <- as.integer(table(d$reason_group,d$destination)[
  cbind(tab$reason,tab$destination)])
write.csv(tab,file.path(support,'drc_injectable_reason_month1_destinations.csv'),row.names=FALSE)
timing <- aggregate(d$wt,list(reason=d$reason_group,
  timing=d$ending_month_group,destination=d$destination),sum)
names(timing)[4] <- 'weighted_endings'
timing$share_within_reason_pct <- 100*timing$weighted_endings/denom[timing$reason]
write.csv(timing,file.path(support,'drc_injectable_reason_timing_destinations.csv'),row.names=FALSE)
cat('Injectable actionable ending events with month-one status:',nrow(d),'\n')
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 41_drc_selected_reason_risk_strata.R
# LANGUAGE: R
MODULES[["41_drc_selected_reason_risk_strata.R"]] <- list(
  language="R",
  original_sha256="a1d772e1c5c6ca7d454c32024e7df52c24853aa0a8eca5816d8e1ceedf013d1b",
  packaged_sha256="a1d772e1c5c6ca7d454c32024e7df52c24853aa0a8eca5816d8e1ceedf013d1b",
  args=character(),
  code=r"-----(#!/usr/bin/env Rscript
# Predictive lower/middle/higher selected-reason risk bands for observed starts.
args<-grep('^--file=',commandArgs(FALSE),value=TRUE)
root<-Sys.getenv('DRC_PROJECT_ROOT',unset=normalizePath(file.path(
  dirname(sub('^--file=','',args[1])),'..')))
library(nnet)
e<-readRDS(file.path(root,'Data','Derived',
                     'drc_2023_24_model_episode_covariates.rds'))
fit<-readRDS(file.path(root,'Data','Derived',
                       'drc_selected_reason_province_model_2.rds'))
support<-file.path(root,'output','Supporting_data')
d<-e[e$entry==0L,]
survival<-rep(1,nrow(d));cum<-numeric(nrow(d))
for(t in 1:12) {
 d$month<-factor(t,levels=1:12)
 p<-predict(fit,newdata=d,type='probs')
 cum<-cum+survival*p[,'selected']
 survival<-survival*p[,'continue']
}
d$predicted_risk_pct<-100*cum
weighted_quantile<-function(x,w,prob) {
 order<-order(x);x<-x[order];w<-w[order]
 x[which(cumsum(w)/sum(w)>=prob)[1]]
}
q<-vapply(c(1/3,2/3),function(x)weighted_quantile(d$predicted_risk_pct,d$wt,x),numeric(1))
d$risk_band<-cut(d$predicted_risk_pct,c(-Inf,q[1],q[2],Inf),
  labels=c('Lower','Middle','Higher'),include.lowest=TRUE)
summary<-aggregate(d$wt,list(risk_band=d$risk_band),sum)
names(summary)[2]<-'weighted_episodes'
summary$observed_episodes_n<-as.integer(table(d$risk_band)[summary$risk_band])
summary$mean_predicted_pct<-vapply(levels(d$risk_band),function(z)
 weighted.mean(d$predicted_risk_pct[d$risk_band==z],d$wt[d$risk_band==z]),numeric(1))
summary$min_predicted_pct<-vapply(levels(d$risk_band),function(z)
 min(d$predicted_risk_pct[d$risk_band==z]),numeric(1))
summary$max_predicted_pct<-vapply(levels(d$risk_band),function(z)
 max(d$predicted_risk_pct[d$risk_band==z]),numeric(1))
write.csv(summary,file.path(support,'drc_selected_reason_predicted_risk_bands.csv'),row.names=FALSE)
vars<-c('method_group','age_group','parity_group','marital_group',
        'education','wealth','residence')
rows<-list()
for(v in vars)for(level in levels(d[[v]]))for(band in levels(d$risk_band)) {
 x<-d[d$risk_band==band,]
 rows[[length(rows)+1L]]<-data.frame(risk_band=band,covariate=v,
   category=level,observed_episodes_n=sum(x[[v]]==level),
   weighted_share_within_band_pct=100*sum(x$wt[x[[v]]==level])/sum(x$wt))
}
write.csv(do.call(rbind,rows),file.path(support,
  'drc_selected_reason_risk_band_characteristics.csv'),row.names=FALSE)
cat('Risk cut points:',paste(round(q,2),collapse=', '),'\n')
)-----"
)

# =============================================================================
# ORIGINAL MODULE: 12_drc_2026_planning.py
# LANGUAGE: Python
MODULES[["12_drc_2026_planning.py"]] <- list(
  language="Python",
  original_sha256="abc4ad9ccfd52327e9fa799ed5b83c49928bd759a04bcf6c9404080b01fc29de",
  packaged_sha256="abc4ad9ccfd52327e9fa799ed5b83c49928bd759a04bcf6c9404080b01fc29de",
  args=c("--project-root"),
  code=r"-----(#!/usr/bin/env python3
"""Build DRC 2026 current-user planning tables from project-relative inputs.

Usage: python 12_drc_2026_planning.py --project-root PATH
The 2025 mCPR bridge applies the +0.4 percentage-point Track20/FPET
2024–25 change to the DHS 2023–24 all-women baseline. The 2026 cases use
no additional growth, the UN 2025–26 increment (+0.5 pp), and the
Track20/FPET recent increment (+0.4 pp). These are illustrations.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
import pandas as pd


METHODS = ["Injectables", "Implants", "Pill", "IUD", "Other modern"]
REASONS = [
    "Method failure", "Wanted more effective method",
    "Changes in menstrual bleeding", "Other side effects/health",
    "Access/cost/convenience",
]


def build(root: Path) -> None:
    support = root / "output" / "Supporting_data"
    support.mkdir(parents=True, exist_ok=True)
    read = lambda stem: pd.read_csv(support / f"drc_{stem}.csv")
    population = read("wpp2024_wra_2024_2026").set_index("year")["women_15_49"]
    use = read("current_use_mcpr").set_index("method")
    base_2024 = float(use["all_women_mcpr_pct"].iloc[0])
    assert np.allclose(use["all_women_mcpr_pct"], base_2024)
    base_2025 = base_2024 + 0.4
    users_2025 = float(population.loc[2025]) * base_2025 / 100
    wra_2026 = float(population.loc[2026])
    share = use.loc[METHODS, "share_of_current_modern_users_pct"] / 100
    stock = users_2025 * share

    first = read("current_users_by_method_and_actionable_projection").set_index("method")
    historical = read("duration_aware_current_user_bridge").set_index("method")
    aft = read("survival_model_duration_by_method").set_index("method")
    first_cause = read("current_users_actionable_by_cause")
    historical_cause = read("duration_aware_current_user_by_cause")
    aft_cause = read("survival_model_duration_by_method_cause")

    method_rows = []
    cause_rows = []
    definitions = [
        ("First-year life table", first, first_cause,
         "illustrative_original_method_endings", "illustrative_users",
         "illustrative_original_method_endings", "illustrative_users", False),
        ("Historical duration-aware", historical, historical_cause,
         "projected_nonmodern_at_month12_after_actionable",
         "projected_nonmodern_at_month12",
         "projected_actionable_original_method_endings",
         "projected_actionable_original_method_endings", True),
        ("AFT plus observed pathways", aft, aft_cause,
         "survival_pathway_nonmodern_at_year_end",
         "aft_pathway_nonmodern_at_year_end",
         "survival_original_method_endings",
         "survival_original_method_endings", True),
    ]
    for approach, table, causes, value_col, cause_col, original_col, original_cause_col, pathway_adjusted in definitions:
        for method in METHODS:
            old_users = float(table.loc[method, "current_users_2024"])
            multiplier = float(stock.loc[method]) / old_users
            count = float(table.loc[method, value_col]) * multiplier
            original_count = float(table.loc[method, original_col]) * multiplier
            method_rows.append({"approach": approach, "method": method,
                                "projected_2025_current_users": float(stock.loc[method]),
                                "projected_actionable_original_method_endings": original_count,
                                "retained_modern_users_2026_illustration": count,
                                "mcpr_equivalent_pp": 100 * count / wra_2026,
                                "pathway_adjusted": pathway_adjusted})
            subset = causes[causes["method"] == method].set_index("reason")
            for reason in REASONS:
                n = float(subset.loc[reason, cause_col]) * multiplier
                original_n = float(subset.loc[reason, original_cause_col]) * multiplier
                cause_rows.append({"approach": approach, "method": method,
                                   "reason": reason,
                                   "projected_actionable_original_method_endings": original_n,
                                   "retained_modern_users_2026_illustration": n,
                                   "mcpr_equivalent_pp": 100 * n / wra_2026})
    by_method = pd.DataFrame(method_rows)
    by_cause = pd.DataFrame(cause_rows)
    for (approach, method), row in by_method.set_index(["approach", "method"]).iterrows():
        subset = by_cause.loc[(by_cause.approach == approach) & (by_cause.method == method)]
        assert abs(row.retained_modern_users_2026_illustration - subset.retained_modern_users_2026_illustration.sum()) < 1.1, (approach, method)
        assert abs(row.projected_actionable_original_method_endings - subset.projected_actionable_original_method_endings.sum()) < 1.1, (approach, method)

    cases = [
        ("No further growth in 2026", 0.0),
        ("UN growth (+0.5 pp)", 0.5),
        ("Track20 growth (+0.4 pp)", 0.4),
    ]
    scenario_rows = []
    for approach in by_method.approach.unique():
        retained = by_method.loc[by_method.approach == approach,
                                 "retained_modern_users_2026_illustration"].sum()
        original_endings = by_method.loc[by_method.approach == approach,
                                         "projected_actionable_original_method_endings"].sum()
        for label, increment in cases:
            usual_mcpr = base_2025 + increment
            usual_users = wra_2026 * usual_mcpr / 100
            scenario_rows.append({
                "approach": approach, "scenario": label,
                "dhs_all_women_mcpr_2024_pct": base_2024,
                "projected_mcpr_2025_pct": base_2025,
                "projected_current_users_2025": users_2025,
                "wra_2026": wra_2026,
                "usual_mcpr_2026_pct": usual_mcpr,
                "usual_modern_users_2026": usual_users,
                "retained_modern_users_2026_illustration": retained,
                "projected_actionable_original_method_endings": original_endings,
                "mcpr_equivalent_pp": 100 * retained / wra_2026,
                "mcpr_if_retained_2026_pct": 100 * (usual_users + retained) / wra_2026,
            })
    scenarios = pd.DataFrame(scenario_rows)
    assert len(scenarios) == 9 and len(by_cause) == 75
    for name, frame in [
        ("2026_planning_scenarios", scenarios),
        ("2026_planning_by_method", by_method),
        ("2026_planning_by_method_cause", by_cause),
    ]:
        frame.to_csv(support / f"drc_{name}.csv", index=False)
    (support / "drc_2026_planning_bundle.json").write_text(
        json.dumps({
            "scenarios": scenarios.to_dict(orient="records"),
            "methods": by_method.to_dict(orient="records"),
            "causes": by_cause.to_dict(orient="records"),
            "current_mix": use["share_of_current_modern_users_pct"].to_dict(),
        }, ensure_ascii=False), encoding="utf-8")
    print(scenarios[["approach", "scenario", "usual_mcpr_2026_pct",
                     "retained_modern_users_2026_illustration",
                     "mcpr_equivalent_pp", "mcpr_if_retained_2026_pct"]].to_string(index=False))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root", type=Path, required=True)
    args = parser.parse_args()
    build(args.project_root.resolve())
)-----"
)

# Parameterized, local-file input validation. No API calls are made.
read_validated_ir <- function(ir_file, expected_sha256='') {
  for (pkg in c('haven','jsonlite','digest'))
    if (!requireNamespace(pkg, quietly=TRUE)) stop('Install required R package: ',pkg,call.=FALSE)
  if (!nzchar(ir_file) || !file.exists(ir_file))
    stop('Supply an existing authorized IR file with --ir-file or DHS_IR_FILE.',call.=FALSE)
  ext <- tolower(tools::file_ext(ir_file))
  allowed <- 'dta'
  if (!ext %in% allowed) stop('Unsupported input format for this country.',call.=FALSE)
  sha <- digest::digest(file=ir_file, algo='sha256')
  if (nzchar(expected_sha256) && (!grepl('^[a-fA-F0-9]{64}$',expected_sha256) ||
      !identical(tolower(expected_sha256),sha)))
    stop('Input SHA-256 does not match --expected-ir-sha256.',call.=FALSE)
  x <- tryCatch(if(ext=='dta') as.data.frame(haven::read_dta(ir_file)) else readRDS(ir_file),
    error=function(e)stop('Cannot read the supplied IR file; verify format and integrity.',call.=FALSE))
  if (!is.data.frame(x)) stop('IR input must be a woman-level data frame.',call.=FALSE)
  expected <- c(27583L,5942L,778L,51L)
  required <- c('caseid','v000','v005','v008','v011','v012','v017','v018','v019',
                'v021','v022','v024','v025','v106','v190','v312','v313','v337',
                'v501','vcal_1','vcal_2')
  
  missing <- setdiff(required,names(x))
  if(length(missing))stop('Required IR variables missing: ',paste(missing,collapse=', '),call.=FALSE)
  if(anyDuplicated(names(x)) || anyDuplicated(x$caseid) || anyNA(x$caseid))
    stop('IR variables and woman identifiers must be unique and nonmissing.',call.=FALSE)
  if(nrow(x)!=expected[1] || ncol(x)!=expected[2])
    stop('IR dimensions differ from the validated country release; review before analysis.',call.=FALSE)
  num <- function(k)as.numeric(x[[k]])
  if(!all(as.character(x$v000)=='CD8'))
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
  stopifnot(all(num('v024')%in%1:26))
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
  prefix<-'drc'
  derived<-file.path(root,'Data','Derived')
  load<-function(name)readRDS(file.path(derived,name))
  events<-load(paste0(prefix,'_2023_24_calendar_events.rds'))
  ep<-load('drc_2023_24_table_7_13_episodes.rds')
  months<-load(paste0(prefix,'_2023_24_calendar_months.rds'))
  cov<-load('drc_2023_24_model_episode_covariates.rds')
  person<-load(paste0(prefix,'_2023_24_person_month.rds'))
  frame<-load(paste0(prefix,'_2023_24_full_survey_frame.rds'))
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
  audit<-read.csv(file.path(root,'output/Supporting_data/drc_table_7_13_validation.csv'))
  stopifnot(sum(audit$rate_cells_matching)==104L,all(audit$episode_count_matching),
    max(audit$max_rate_abs_difference_pp)<=0.10000001,
    nrow(events)==132217L,nrow(ep)==8934L,nrow(cov)==4146L,nrow(person)==31415L)
  actual<-read.csv(file.path(root,'output/Supporting_data/drc_table_7_13_replicated.csv'))
  reference<-read.csv(file.path(root,'Data/validation_reference/drc_table_7_13_released_data.csv'))
  stopifnot(identical(actual$method,reference$method),identical(names(actual),names(reference)))
  for(k in setdiff(names(actual),'method'))stopifnot(all(abs(actual[[k]]-reference[[k]])<1e-9))
  validated_cells<-104L;validated_counts<-10L
  # Six known 0.1-pp differences are retained, not silently forced to match.
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
    dhs_rate_cells_differing=6L,maximum_report_difference_pp=0.1,
    released_data_reference_matches=TRUE,provinces=26L,
    input_preparation_complete=TRUE,full_html_regeneration=FALSE,
    html_and_pptx_modified=FALSE)
  jsonlite::write_json(result,file.path(dest,'preparation_validation.json'),
    auto_unbox=TRUE,pretty=TRUE,digits=15)
  cat('Preparation passed: ',nrow(events),' calendar runs; ',nrow(ep),
      ' published-table episodes; ',nrow(cov),' model episodes.\n',sep='')
}

MODULES[["210_prepare_analysis_inputs.R"]] <- list(language="R",packaged_sha256="47fba6488d7d3c48d604bba58d8eed22e7d951aa9e8e3a9d29a644057f0a23f9",args=character(),code=r"-----(#!/usr/bin/env Rscript
# Data preparation only, using the existing province/model definitions.
root<-Sys.getenv('DRC_PROJECT_ROOT');stopifnot(nzchar(root))
derived<-file.path(root,'Data','Derived');prefix<-'drc'

local({
#!/usr/bin/env Rscript
# DRC 2023-24 DHS contraceptive-calendar analysis. Input locations are configurable.
args<-grep('^--file=',commandArgs(FALSE),value=TRUE)
default_root<-if(length(args)) normalizePath(file.path(dirname(sub('^--file=','',args[1])),'..')) else normalizePath('..')
root<-Sys.getenv('DRC_PROJECT_ROOT',unset=default_root)
derived<-file.path(root,'Data','Derived');support<-file.path(root,'output','Supporting_data')
dir.create(support,recursive=TRUE,showWarnings=FALSE)
e<-readRDS(file.path(derived,'drc_2023_24_table_7_13_episodes.rds'))
ir<-haven::read_dta(Sys.getenv('DRC_IR_FILE',unset=file.path(root,'Data','CDIR81FL.dta')),
 col_select=c(caseid,v005,v021,v022,v024,v025,v312,v313,v106,v190,v201,v501,v008,v011))
ir<-as.data.frame(ir)
province_labels<-names(attr(ir$v024,'labels')); province_codes<-as.integer(attr(ir$v024,'labels'))
province_names<-c('Kinshasa','Kongo Central','Kwango','Kwilu','Mai-Ndombe','Équateur','Nord-Ubangi','Sud-Ubangi','Mongala','Tshuapa','Tshopo','Bas-Uélé','Haut-Uélé','Ituri','Nord-Kivu','Sud-Kivu','Maniema','Haut-Katanga','Haut-Lomami','Lualaba','Tanganyika','Lomami','Sankuru','Kasaï Oriental','Kasaï','Kasaï Central')
stopifnot(identical(province_codes,1:26))
modern_codes<-c(1L,2L,3L,5L,6L,7L,11L,13L,14L,15L,17L,18L,19L,20L)
causes<-list('Method failure'=1L,'Wanted more effective method'=7L,'Changes in menstrual bleeding'=15L,
 'Other side effects/health'=c(4L,5L),'Access/cost/convenience'=c(6L,8L,10L))
actionable<-unlist(causes,use.names=FALSE)
e<-e[e$method_code%in%modern_codes,]
e$province<-province_names[e$zone]
e$cluster<-as.numeric(ir$v021[e$woman_row]);e$stratum<-as.numeric(ir$v022[e$woman_row])
e$method_group<-'Other modern'
e$method_group[e$method_code==1L]<-'Pill'
e$method_group[e$method_code==2L]<-'IUD'
e$method_group[e$method_code==3L]<-'Injectables'
e$method_group[e$method_code==11L]<-'Implants'
e$action_event<-e$discontinued & e$exposure<=12L & e$reason_code%in%actionable
saveRDS(e,file.path(derived,'drc_2023_24_modern_episodes.rds'))

})
local({
#!/usr/bin/env Rscript
# DRC DHS 2023–24: adjusted province comparison for actionable discontinuation.
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

root <- Sys.getenv("DRC_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
support <- file.path(root,'output/Supporting_data')
derived <- file.path(root,'Data/Derived')
if(!requireNamespace('nnet',quietly=TRUE))stop('nnet package is required')
e <- readRDS(file.path(derived,'drc_2023_24_modern_episodes.rds'))
ir <- as.data.frame(haven::read_dta(Sys.getenv('DRC_IR_FILE', unset=file.path(root,'Data','CDIR81FL.dta'))))
actionable <- c(1L,4L,5L,6L,7L,8L,10L,15L)
e$zone_name <- factor(e$province, levels=c('Kinshasa','Kongo Central','Kwango','Kwilu','Mai-Ndombe','Équateur','Nord-Ubangi','Sud-Ubangi','Mongala','Tshuapa','Tshopo','Bas-Uélé','Haut-Uélé','Ituri','Nord-Kivu','Sud-Kivu','Maniema','Haut-Katanga','Haut-Lomami','Lualaba','Tanganyika','Lomami','Sankuru','Kasaï Oriental','Kasaï','Kasaï Central'))
e$method_group <- factor(e$method_group,
  levels=c('Implants','Injectables','Pill','IUD','Other modern'))
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
# Pool recent starts to avoid sparse cohort terms.
year <- (e$start-1L)%/%12L+1900L
e$start_year <- factor(ifelse(year>=2023,'2023–24',as.character(year)))
complete <- complete.cases(e[,c('method_group','zone_name','age_group',
  'parity_group','marital_group','education','wealth','residence','start_year')])
cat('Complete-case episodes:',sum(complete),'of',nrow(e),'\n')
e <- e[complete,]
saveRDS(e,file.path(derived,'drc_2023_24_model_episode_covariates.rds'))

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
stopifnot(!anyNA(person),nrow(person)>10000)
saveRDS(person,file.path(derived,'drc_2023_24_person_month.rds'))

})
ir<-as.data.frame(haven::read_dta(Sys.getenv('DRC_IR_FILE',unset=file.path(root,'Data','CDIR81FL.dta'))))
saveRDS(ir,file.path(root,'Data/ir.rds'))

# Save an explicit month-level calendar alongside the original run-level data.
# Nonuse, pregnancy, births and terminations remain in this broad calendar.
# Only method-use episodes enter discontinuation denominators.
cal <- readRDS(file.path(derived,paste0(prefix,'_2023_24_calendar_events.rds')))
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
saveRDS(month_data,file.path(derived,paste0(prefix,'_2023_24_calendar_months.rds')))
frame<-unique(data.frame(cluster=as.numeric(ir$v021),stratum=as.numeric(ir$v022)))
saveRDS(frame,file.path(derived,paste0(prefix,'_2023_24_full_survey_frame.rds')))
current<-which(as.integer(ir$v313)==3L)
current_users<-data.frame(woman_row=current,method_code=as.integer(ir$v312[current]),
 elapsed_months=as.numeric(ir$v337[current]),wt=as.numeric(ir$v005[current])/1e6,
 cluster=as.numeric(ir$v021[current]),stratum=as.numeric(ir$v022[current]),
 region=as.integer(ir$v024[current]))
saveRDS(current_users,file.path(derived,paste0(prefix,'_2023_24_current_modern_users.rds')))
cat('Created source-aligned calendar months, full survey frame and current-user inputs.\n')
)-----")

EXTERNAL_INPUTS[["Data/validation_reference/drc_table_7_13_released_data.csv"]] <- r"-----("method","reason_1_pct","reason_2_pct","reason_3_pct","reason_4_pct","reason_5_pct","reason_6_pct","reason_7_pct","reason_8_pct","reason_9_pct","any_reason_pct","switching_pct","weighted_episodes","unweighted_episodes","women","late_entries"
"Injectables",1.3565852206322,18.2350910680723,3.66822972353886,13.3560841180976,15.6797210265779,7.96780353419941,5.05590579241496,0.909603794545121,1.48266786372809,67.7116921418065,4.15183575066699,819.687662999999,624,541,51
"Implants",0.0697519653963223,7.3622100316531,3.5697897559457,4.570936640785,9.79675119371742,0.653075924935657,0.920284127667735,1.39671286684577,1.83825777998177,30.1777702869285,1.01359418975467,1122.204022,1040,942,90
"Pill",2.62699354497939,13.4680690983979,6.11041150168826,13.7386846160614,10.8661831794822,4.00239034501661,3.88326119092146,3.51481592860958,5.35042375584112,63.5612331609979,3.1952108030569,636.814654999999,433,368,45
"Male condom",0.683068655774842,10.9306308972988,16.5114725914668,1.37393214928162,1.45943245383782,6.13139516651979,4.57437193000003,9.07080923241801,2.8493537697536,53.5844668463514,4.48902843938114,1031.256763,836,709,67
"Emergency contraception",1.996339235399,9.58356789192611,12.346326930717,4.78694230226879,4.02268151862231,2.75897734526784,5.19802620597089,0.431895087948207,0.241353016642922,41.3661095347631,2.83549116406444,445.4756,205,188,11
"SDM/LAM/other",5.19829120530124,20.7166122362665,9.0126170274236,2.09033831205456,1.01947529212057,6.93293207143953,2.3247046262832,4.002920926766,3.56662101290815,54.8645127105634,3.99806526896737,497.689941,468,350,47
"Rhythm",5.45065159594016,18.9631708614136,11.3117306388001,1.16879841302471,0.200111895009473,2.45795516829433,1.79858662146323,3.55506316963598,2.55374478398458,47.4598131475661,1.14576172780685,2436.455761,2566,1927,261
"Withdrawal",5.06489328786093,19.2694079223476,11.0567180474114,1.07415122018291,0.628949210898754,6.41506788133342,2.23439709951597,8.52595965871056,4.49395158153219,58.7634959097937,3.87197750835584,1488.36124899999,1600,1250,135
"Other",1.54853376108423,13.7583782229048,9.45846383678151,2.58602000846468,1.56078958919494,9.12701581037906,0.647495089103222,4.60264481966723,4.56442982502437,47.853770962604,10.5588827654311,1157.99075,1162,917,94
"All methods",3.10486919541947,15.4679777565294,9.60977843282686,3.83539793214873,3.96632875518934,4.79634145417049,2.51464717482386,4.38222612437393,3.07816538759441,50.7557322130765,3.60181417317953,9635.93640399991,8934,6014,801
)-----"


MODULES[["211_full_frame_survey_inference.R"]] <- list(language="R",packaged_sha256="726800b74c3062a28dadf209b2ac05a425a75809c66245e382c25c8dce0595ae",args=character(),code=r"-----(#!/usr/bin/env Rscript
# Full-frame design linearization for DRC life tables and fitted predictions.
# Includes joint covariance and empirical standardization-reference uncertainty.
a<-commandArgs(TRUE);root<-normalizePath(if(length(a))a[1]else Sys.getenv('DRC_PROJECT_ROOT'));sup<-file.path(root,'output/Supporting_data');der<-file.path(root,'Data/Derived')
suppressPackageStartupMessages(library(haven));suppressPackageStartupMessages(library(nnet));suppressPackageStartupMessages(library(survey))
ir<-readRDS(file.path(root,'Data/ir.rds'));e<-readRDS(file.path(der,'drc_2023_24_modern_episodes.rds'));ep<-readRDS(file.path(der,'drc_2023_24_model_episode_covariates.rds'));person<-readRDS(file.path(der,'drc_2023_24_person_month.rds'))
frame<-unique(data.frame(cluster=as.numeric(ir$v021),stratum=as.numeric(ir$v022)));N<-nrow(frame);groups<-split(seq_len(N),frame$stratum);df<-N-length(groups);crit<-qt(.975,df)
stopifnot(N==778,length(groups)==51,df==727,all(lengths(groups)>1))
cluster_sum<-function(v,cluster){v<-as.matrix(v);z<-matrix(0,N,ncol(v));q<-rowsum(v,match(cluster,frame$cluster),reorder=FALSE);z[as.integer(rownames(q)),]<-q;z}
design_vcov<-function(z){v<-matrix(0,ncol(z),ncol(z));for(ids in groups){q<-z[ids,,drop=FALSE];q<-sweep(q,2,colMeans(q));v<-v+length(ids)/(length(ids)-1)*crossprod(q)};v}
bounds<-function(p,se,prob=TRUE){if(!prob)return(c(p-crit*se,p+crit*se));if(p<=0||p>=100)return(c(max(0,p-crit*se),min(100,p+crit*se)));100*plogis(qlogis(p/100)+c(-1,1)*crit*se/(p*(1-p/100)))}
action<-c(1L,4L,5L,6L,7L,8L,10L,15L)
cif<-function(d,targets=list(all=function(x)rep(TRUE,nrow(x)),actionable=function(x)x$reason_code%in%action,selected=function(x)!x$reason_code%in%c(2L,3L))){
 s<-1;ds<-rep(0,N);f<-numeric(length(targets));dif<-matrix(0,N,length(targets));out<-vector('list',12)
 marked<-do.call(cbind,lapply(targets,function(fun)fun(d)))
 for(t in 1:12){at<-d$entry<t&d$exposure>=t;den<-sum(d$wt[at]);if(den<=0)return(NULL)
  en<-at&d$discontinued&d$exposure==t;ha<-sum(d$wt[en])/den
  h<-colSums(marked*(d$wt*en))/den
  dha<-cluster_sum(d$wt*(as.numeric(en)-ha*as.numeric(at))/den,d$cluster)[,1]
  dh<-cluster_sum((marked*as.numeric(en)-outer(as.numeric(at),h))*d$wt/den,d$cluster)
  dif<-dif+outer(ds,h)+s*dh;f<-f+s*h;ds<-(1-ha)*ds-s*dha;s<-s*(1-ha)
  out[[t]]<-list(point=100*f,influence=100*dif)
 }
 out
}
# Raw timepoint estimates and joint province influences preserve all point estimates.
times<-read.csv(file.path(sup,'drc_modern_timepoints.csv'));raw_if<-list()
for(scope in unique(times$scope)){
 ix<-if(scope=='National')rep(TRUE,nrow(e))else if(startsWith(scope,'National: '))e$method_group==substring(scope,11) else if(grepl(': ',scope,fixed=TRUE)){v<-strsplit(scope,': ',fixed=TRUE)[[1]];e$province==v[1]&e$method_group==v[2]}else e$province==scope
 d<-e[ix,];z<-cif(d);if(is.null(z))next
 for(t in c(3L,6L,9L,12L)){
  row<-which(times$scope==scope&times$month==t);stopifnot(length(row)==1)
  stopifnot(abs(times$all_reason_pct[row]-z[[t]]$point[1])<1e-8,abs(times$actionable_pct[row]-z[[t]]$point[2])<1e-8)
  for(k in 1:2){se<-sqrt(design_vcov(z[[t]]$influence[,k,drop=FALSE])[1,1]);ci<-bounds(z[[t]]$point[k],se);stem<-c('all_reason','actionable')[k]
   times[row,paste0(stem,'_ci_low')]<-ci[1];times[row,paste0(stem,'_ci_high')]<-ci[2]}
 }
 raw_if[[scope]]<-z
}
write.csv(times,file.path(sup,'drc_modern_timepoints.csv'),row.names=FALSE)
# Life-table derivative check against a small perturbation to one PSU weight.
zz<-cif(e);cl<-frame$cluster[match(e$cluster[1],frame$cluster)];dd<-e;delta<-1e-5;dd$wt[dd$cluster==cl]<-dd$wt[dd$cluster==cl]*(1+delta);fd<-(cif(dd)[[12]]$point-zz[[12]]$point)/delta
stopifnot(max(abs(fd-zz[[12]]$influence[match(cl,frame$cluster),]))<1e-4)
selected<-read.csv(file.path(sup,'drc_selected_reason_subgroups.csv'))
for(i in seq_len(nrow(selected))){key<-selected$group[i];v<-strsplit(key,'::',fixed=TRUE)[[1]];ix<-if(key=='National')rep(TRUE,nrow(ep))else if(length(v)==2)as.character(ep[[v[1]]])==v[2]else as.character(ep[[v[1]]])==v[3]&as.character(ep[[v[2]]])==v[4]
 z<-cif(ep[ix,]);if(is.null(z))next;stopifnot(abs(selected$selected_12_month_pct[i]-z[[12]]$point[3])<1e-7)
 se<-sqrt(design_vcov(z[[12]]$influence[,3,drop=FALSE])[1,1]);ci<-bounds(z[[12]]$point[3],se);selected$ci_low[i]<-ci[1];selected$ci_high[i]<-ci[2]
}
write.csv(selected,file.path(sup,'drc_selected_reason_subgroups.csv'),row.names=FALSE)
cat('Updated raw full-frame life-table intervals; derivative check passed.\n');flush.console()
# Fit-score influence for weighted multinomial coefficients.
fit_system<-function(fit,dat,binary=FALSE){
 if(binary){X<-model.matrix(fit);be<-coef(fit);stopifnot(!anyNA(be));pr<-as.numeric(fitted(fit));h<-crossprod(X,X*(dat$wt*pr*(1-pr)));score<-X*(dat$wt*(dat$any_end-pr));bread<-MASS::ginv(h)}else{
  X<-model.matrix(delete.response(terms(fit)),dat,contrasts.arg=fit$contrasts);pr<-predict(fit,newdata=dat,type='probs');lev<-fit$lev[-1];score<-do.call(cbind,lapply(lev,function(y)X*(dat$wt*(as.numeric(dat$outcome==y)-pr[,y]))));bread<-MASS::ginv(fit$Hessian)
 }
 psi<-cluster_sum(score,dat$cluster)%*%t(bread);list(fit=fit,psi=psi,V=design_vcov(psi),binary=binary)
}
reference<-ep[ep$entry==0L,]
predict_influence<-function(system,variable=NULL,value=NULL,target='actionable'){
 fit<-system$fit;d<-reference;if(!is.null(variable))d[[variable]]<-factor(value,levels=levels(reference[[variable]]))
 p<-if(system$binary)length(coef(fit))else ncol(coef(fit));K<-if(system$binary)1L else nrow(coef(fit));Q<-matrix(0,nrow(d),p*K);DS<-Q;S<-rep(1,nrow(d));F<-rep(0,nrow(d))
 for(t in 1:12){d$month<-factor(t,levels=1:12);X<-model.matrix(delete.response(terms(fit)),d,contrasts.arg=fit$contrasts)
  if(system$binary){pa<-plogis(as.numeric(X%*%coef(fit)));pc<-1-pa;dA<-X*(pa*pc);dC<--dA}else{
   eta<-X%*%t(coef(fit));base<-pmax(0,eta[,1],eta[,2]);ex<-exp(eta-base);den<-exp(-base)+rowSums(ex);P<-ex/den;pc<-exp(-base)/den;j<-match(target,fit$lev[-1]);pa<-P[,j]
   dA<-do.call(cbind,lapply(1:K,function(k)X*(pa*(as.numeric(k==j)-P[,k]))));dC<-do.call(cbind,lapply(1:K,function(k)X*(-pc*P[,k])))
  }
  Q<-Q+DS*pa+dA*S;DS<-DS*pc+dC*S;F<-F+S*pa;S<-S*pc
 }
 den<-sum(d$wt);point<-100*sum(d$wt*F)/den;g<-100*colSums(Q*d$wt)/den
 psi<-as.numeric(system$psi%*%g)+cluster_sum(100*d$wt*(F-point/100)/den,d$cluster)[,1]
 se<-sqrt(design_vcov(matrix(psi,ncol=1))[1,1]);ci<-bounds(point,se)
 list(point=point,se=se,low=ci[1],high=ci[2],influence=psi,gradient=g)
}
# Explicit finite-difference check of the conditional model gradient.
check_gradient<-function(system,target){
 fit<-system$fit;ans<-predict_influence(system,target=target);k<-which.max(abs(ans$gradient));eps<-1e-5;f2<-fit
 
 # A separate direct trajectory implementation avoids reusing the derivative.
 beta<-if(system$binary)coef(fit)else as.vector(t(coef(fit)));direct<-function(b){s<-rep(1,nrow(reference));f<-rep(0,nrow(reference));d<-reference
  for(t in 1:12){d$month<-factor(t,levels=1:12);X<-model.matrix(delete.response(terms(fit)),d,contrasts.arg=fit$contrasts)
   if(system$binary){pa<-plogis(as.numeric(X%*%b));pc<-1-pa}else{B<-matrix(b,nrow=nrow(coef(fit)),byrow=TRUE);eta<-X%*%t(B);base<-pmax(0,eta[,1],eta[,2]);ex<-exp(eta-base);den<-exp(-base)+rowSums(ex);pa<-ex[,match(target,fit$lev[-1])]/den;pc<-exp(-base)/den}
   f<-f+s*pa;s<-s*pc}
 100*weighted.mean(f,reference$wt)}
 bb<-beta;bb[k]<-bb[k]+eps;fd<-(direct(bb)-direct(beta))/eps;stopifnot(abs(fd-ans$gradient[k])<max(.001,abs(fd)*.0001));TRUE
}
# Existing weighted point fits are retained; covariance uses all survey PSUs.
model1<-readRDS(file.path(der,'drc_actionable_province_model_1.rds'));model2<-readRDS(file.path(der,'drc_actionable_province_model_2.rds'))
systems<-list(fit_system(model1,person),fit_system(model2,person));check_gradient(systems[[2]],'actionable')
coef_rows<-list()
for(k in 1:2){fit<-systems[[k]]$fit;se<-sqrt(pmax(diag(systems[[k]]$V),0));beta<-as.vector(t(coef(fit)));coef_rows[[k]]<-data.frame(model=c('Method + duration','Full')[k],outcome=rep(fit$lev[-1],each=ncol(coef(fit))),covariate=rep(colnames(coef(fit)),length(fit$lev)-1),odds_ratio=exp(beta),ci_low=exp(beta-crit*se),ci_high=exp(beta+crit*se),p_value=2*pt(-abs(beta/se),df),survey_se=se,design_df=df);saveRDS(systems[[k]]$V,file.path(sup,paste0('model_',k,'_survey_vcov.rds')))}
write.csv(do.call(rbind,coef_rows),file.path(sup,'drc_actionable_province_model_odds_ratios.csv'),row.names=FALSE)
reg<-read.csv(file.path(sup,'drc_actionable_province_adjusted_rates.csv'));zones<-levels(ep$zone_name);joint<-list()
for(k in 1:2){out<-lapply(c(NA_character_,zones),function(z)predict_influence(systems[[k]],if(is.na(z))NULL else'zone_name',z));names(out)<-c('National',zones);joint[[k]]<-out
 for(name in names(out)){i<-match(name,reg$zone);z<-out[[name]];stem<-paste0('model_',k);stopifnot(abs(reg[[paste0(stem,'_common_mix_pct')]][i]-z$point)<1e-7);reg[[paste0(stem,'_low')]][i]<-z$low;reg[[paste0(stem,'_high')]][i]<-z$high}
}
for(i in seq_len(nrow(reg))){q<-times[times$scope==reg$zone[i]&times$month==12,];reg$unadjusted_low[i]<-q$actionable_ci_low;reg$unadjusted_high[i]<-q$actionable_ci_high}
reg$small_actionable_cell<-reg$actionable_endings_n<30;reg$inference_method<-'full-frame design linearization';write.csv(reg,file.path(sup,'drc_actionable_province_adjusted_rates.csv'),row.names=FALSE)
rows<-list()
for(k in 1:2)for(pair in combn(zones,2,simplify=FALSE)){aa<-joint[[k]][[pair[1]]];bb<-joint[[k]][[pair[2]]];delta<-aa$point-bb$point;se<-sqrt(design_vcov(matrix(aa$influence-bb$influence,ncol=1))[1,1]);ci<-bounds(delta,se,FALSE)
 rows[[length(rows)+1L]]<-data.frame(stage=c('Method adjusted','Fully adjusted')[k],province_1=pair[1],province_2=pair[2],difference_pp=delta,ci_low=ci[1],ci_high=ci[2],p_value=2*pt(-abs(delta/se),df),design_df=df,small_cell=any(reg$small_actionable_cell[match(pair,reg$zone)]))}
pairs<-do.call(rbind,rows);pairs$p_holm<-ave(pairs$p_value,pairs$stage,FUN=function(p)p.adjust(p,'holm'));pairs$significant_05<-pairs$p_holm<.05;pairs$significant_10<-pairs$p_holm<.10;write.csv(pairs,file.path(sup,'drc_actionable_adjusted_pairwise.csv'),row.names=FALSE)
for(t in c(3L,12L)){rows<-lapply(combn(zones,2,simplify=FALSE),function(pair){aa<-raw_if[[pair[1]]][[t]];bb<-raw_if[[pair[2]]][[t]];delta<-aa$point[2]-bb$point[2];se<-sqrt(design_vcov(matrix(aa$influence[,2]-bb$influence[,2],ncol=1))[1,1]);ci<-bounds(delta,se,FALSE);data.frame(month=t,province_1=pair[1],province_2=pair[2],difference_pp=delta,se_pp=se,ci_low=ci[1],ci_high=ci[2],p_raw=2*pt(-abs(delta/se),df))});q<-do.call(rbind,rows);q$p_holm<-p.adjust(q$p_raw,'holm');q$significant_05<-q$p_holm<.05;write.csv(q,file.path(sup,paste0('drc_actionable_raw_pairwise_',t,'month.csv')),row.names=FALSE)}
vars<-c('age_group','parity_group','marital_group','education','wealth','residence');rows<-list()
for(v in vars)for(level in levels(reference[[v]])){z<-predict_influence(systems[[2]],v,level);rows[[length(rows)+1L]]<-data.frame(covariate=v,category=level,adjusted_12mo_pct=z$point,ci_low=z$low,ci_high=z$high,design_df=df)}
write.csv(do.call(rbind,rows),file.path(sup,'drc_actionable_adjusted_subgroups.csv'),row.names=FALSE)
cat('Actionable model full-frame covariance, marginal intervals and pairwise tests updated.\n');flush.console()
# Broader selected-reason models are retained as explicitly labelled HTML diagnostics.
p2<-person;obs<-pmin(12L,ep$exposure)-ep$entry;index<-rep(seq_len(nrow(ep)),obs);mt<-as.integer(as.character(person$month));ended<-ep$discontinued[index]&mt==ep$exposure[index]
p2$outcome<-factor(ifelse(!ended,'continue',ifelse(ep$reason_code[index]%in%c(2L,3L),'competing','selected')),levels=c('continue','selected','competing'))
selected_systems<-lapply(1:2,function(k){fit<-readRDS(file.path(der,paste0('drc_selected_reason_province_model_',k,'.rds')));if(is.null(fit$Hessian))fit$Hessian<-nnet:::multinomHess(fit,model.matrix(delete.response(terms(fit)),p2,contrasts.arg=fit$contrasts));fit_system(fit,p2)})
selreg<-read.csv(file.path(sup,'drc_selected_reason_province_adjusted_rates.csv'));selif<-list()
for(k in 1:2){z<-lapply(zones,function(zone)predict_influence(selected_systems[[k]],'zone_name',zone,target='selected'));names(z)<-zones;selif[[k]]<-z;stem<-c('method_adjusted','fully_adjusted')[k]
 for(i in seq_len(nrow(selreg))){q<-z[[selreg$province[i]]];stopifnot(abs(selreg[[paste0(stem,'_pct')]][i]-q$point)<1e-7);selreg[[paste0(stem,'_low')]][i]<-q$low;selreg[[paste0(stem,'_high')]][i]<-q$high}}
for(i in seq_len(nrow(selreg))){j<-match(paste0('zone_name::',selreg$province[i]),selected$group);selreg$observed_low[i]<-selected$ci_low[j];selreg$observed_high[i]<-selected$ci_high[j]}
write.csv(selreg,file.path(sup,'drc_selected_reason_province_adjusted_rates.csv'),row.names=FALSE)
srows<-list();for(k in 1:2)for(pair in combn(zones,2,simplify=FALSE)){aa<-selif[[k]][[pair[1]]];bb<-selif[[k]][[pair[2]]];delta<-aa$point-bb$point;se<-sqrt(design_vcov(matrix(aa$influence-bb$influence,ncol=1))[1,1]);ci<-bounds(delta,se,FALSE);srows[[length(srows)+1L]]<-data.frame(stage=c('Method adjusted','Fully adjusted')[k],province_1=pair[1],province_2=pair[2],difference_pp=delta,ci_low=ci[1],ci_high=ci[2],p_value=2*pt(-abs(delta/se),df),small_cell=any(selreg$small_cell[match(pair,selreg$province)]))}
q<-do.call(rbind,srows);q$p_holm<-ave(q$p_value,q$stage,FUN=function(x)p.adjust(x,'holm'));q$significant_05<-q$p_holm<.05;write.csv(q,file.path(sup,'drc_selected_reason_adjusted_pairwise.csv'),row.names=FALSE)
# Full survey frame for the all-cause binary model, preserving its weighted fit.
pb<-person;pb$any_end<-as.integer(pb$outcome!='continue');form<-any_end~month+method_group+zone_name+age_group+parity_group+marital_group+education+wealth+residence+start_year
missing<-frame[!frame$cluster%in%pb$cluster,];extra<-pb[rep(1L,nrow(missing)),];extra$cluster<-missing$cluster;extra$stratum<-missing$stratum;extra$wt<-0
options(survey.lonely.psu='adjust');des<-svydesign(ids=~cluster,strata=~stratum,weights=~wt,data=rbind(pb,extra),nest=TRUE)
fitb<-svyglm(form,design=des,family=quasibinomial());saveRDS(fitb,file.path(der,'drc_all_reason_full_model.rds'))
# Fit-score matrix is computed on positive-weight observations only.
fit0<-glm(form,data=pb,weights=wt,family=quasibinomial());sysb<-fit_system(fit0,pb,TRUE);stopifnot(max(abs(coef(fitb)-coef(fit0)))<1e-6);check_gradient(sysb,'any')
rows<-list();for(v in c('method_group',vars))for(level in levels(reference[[v]])){z<-predict_influence(sysb,v,level);rows[[length(rows)+1L]]<-data.frame(covariate=v,category=level,adjusted_12mo_pct=z$point,ci_low=z$low,ci_high=z$high,design_df=df)}
write.csv(do.call(rbind,rows),file.path(sup,'drc_all_reason_adjusted_subgroups.csv'),row.names=FALSE)
saveRDS(list(frame=frame,raw_if=raw_if,joint=joint,selected_joint=selif),file.path(der,'drc_full_frame_inference.rds'))
# Broader first-year cause projections with joint risk/current-stock variance.
causes<-list('Method failure'=1L,'Other fertility'=c(9L,12L,13L),'Bleeding changes'=15L,'Other health'=c(4L,5L),'More effective'=7L,'Access/cost/convenience'=c(6L,8L,10L),'Other recorded'=c(11L,96L,98L,99L,0L))
W<-as.numeric(ir$v005)/1e6;modern<-as.numeric(ir$v313)==3L;method<-ifelse(as.integer(ir$v312)==3L,'Injectables',ifelse(as.integer(ir$v312)==11L,'Implants',ifelse(as.integer(ir$v312)==1L,'Pill',ifelse(as.integer(ir$v312)==2L,'IUD','Other modern'))))
method[as.integer(ir$v312)==16L]<-'EC'
T<-sum(W);M<-sum(W[modern]);w25<-25246885;rows<-list(c('Method','Reason','Projected 2025 current users','Cause-specific first-year probability','Illustrative original-method endings'))
for(m in c('Injectables','Implants','Pill','IUD','Other modern')){
 Mm<-sum(W[modern&method==m]);stock<-w25*(Mm/T+.004*Mm/M)
 stock_if<-cluster_sum(W*(-w25*Mm/T^2-w25*.004*Mm/M^2*as.numeric(modern)+w25*(1/T+.004/M)*as.numeric(modern&method==m)),as.numeric(ir$v021))[,1]
 ss<-sqrt(design_vcov(matrix(stock_if,ncol=1))[1,1]);sc<-bounds(stock,ss,FALSE)
 zz<-cif(e[e$method_group==m,],lapply(causes,function(c)function(x)x$reason_code%in%c))[[12]]
 for(j in seq_along(causes)){
  p<-zz$point[j]/100;ppsi<-zz$influence[,j]/100;v<-stock*p;vpsi<-stock_if*p+stock*ppsi;se<-sqrt(design_vcov(matrix(vpsi,ncol=1))[1,1]);ci<-bounds(v,se,FALSE);ps<-sqrt(design_vcov(matrix(zz$influence[,j],ncol=1))[1,1]);pc<-bounds(100*p,ps)
  fmt<-function(x,l,u,percent=FALSE){if(x==0&&l==0&&u==0)return('0 (CI unavailable†)');sprintf(if(percent)'%.1f%% (%.1f–%.1f)'else'%.0f (%.0f–%.0f)',x,max(0,l),u)}
  rows[[length(rows)+1L]]<-c(m,names(causes)[j],fmt(stock,sc[1],sc[2]),fmt(100*p,pc[1],pc[2],TRUE),fmt(v,ci[1],ci[2]))
 }
}
dir.create(file.path(root,'output/survey_planning'),recursive=TRUE,showWarnings=FALSE)
jsonlite::write_json(rows,file.path(root,'output/survey_planning/selected_projection.json'),auto_unbox=TRUE,pretty=TRUE)
cat('All displayed inference updated using',N,'PSUs;',length(groups),'strata;',df,'design degrees of freedom.\n')
)-----")

MODULES[["212_planning_survey_ci.R"]] <- list(language="R",packaged_sha256="052bbd849a2178d61a49493007fba0d5b7896596ff6942577890e81c3f91e871",args=character(),code=r"-----(#!/usr/bin/env Rscript
# DRC: gross actionable endings and switching sensitivities, with survey uncertainty.
# Input/output roots are command-line parameters. No personal locations are stored.
a<-commandArgs(TRUE);root<-normalizePath(if(length(a))a[1]else Sys.getenv('DRC_PROJECT_ROOT'));out<-if(length(a)>=2)a[2]else file.path(root,'output/survey_planning')
B<-if(length(a)>=3)as.integer(a[3])else as.integer(Sys.getenv('DRC_PLANNING_BOOTSTRAP_REPS','500'));cores<-if(length(a)>=4)as.integer(a[4])else 4L
dir.create(out,recursive=TRUE,showWarnings=FALSE)
suppressPackageStartupMessages(library(survival));stopifnot(requireNamespace('haven',quietly=TRUE))
ir<-readRDS(file.path(root,'Data/ir.rds'));e<-readRDS(file.path(root,'Data/Derived/drc_2023_24_modern_episodes.rds'))
cal<-readRDS(file.path(root,'Data/Derived/drc_2023_24_calendar_events.rds'));sup<-file.path(root,'output/Supporting_data')
pop<-read.csv(file.path(sup,'drc_wpp2024_wra_2024_2026.csv'))
w24<-pop$women_15_49[pop$year==2024];w25<-pop$women_15_49[pop$year==2025];w26<-pop$women_15_49[pop$year==2026]
methods<-c('Injectables','Implants','Pill','IUD','Other modern');model_methods<-methods[methods!='IUD']
causes<-c('Method failure','Wanted more effective method','Changes in menstrual bleeding','Other side effects/health','Access/cost/convenience')
codes<-list(1L,7L,15L,c(4L,5L),c(6L,8L,10L));action<-unlist(codes)
modern<-c(1L,2L,3L,5L,6L,7L,11L,13L,14L,15L,17L,18L,19L,20L);endpoint_modern<-c(modern,16L)
mg<-function(x)ifelse(x==3L,'Injectables',ifelse(x==11L,'Implants',ifelse(x==1L,'Pill',ifelse(x==2L,'IUD','Other modern'))))
cg<-function(x){v<-rep(NA_integer_,length(x));for(j in 1:5)v[x%in%codes[[j]]]<-j;v}
wt<-as.numeric(ir$v005)/1e6;psu<-as.numeric(ir$v021);stratum<-as.numeric(ir$v022)
frame<-unique(data.frame(psu,stratum));groups<-split(seq_len(nrow(frame)),frame$stratum);pi<-match(psu,frame$psu)
stopifnot(nrow(frame)==778L,length(groups)==51L,all(lengths(groups)>1),!anyDuplicated(frame$psu))
u<-as.numeric(ir$v313)==3;um<-mg(as.numeric(ir$v312));um[as.numeric(ir$v312)==16L]<-'EC'
ix<-which(u & as.numeric(ir$v312)%in%modern)
current<-data.frame(woman=ix,method=um[ix],elapsed=as.integer(ir$v337[ix]),wt=wt[ix])
stopifnot(!anyNA(current$elapsed),all(current$elapsed>=0))
bins<-c(-1,3,6,12,24,36,48,60,Inf);blabel<-c('0–3','4–6','7–12','13–24','25–36','37–48','49–60','61+')
current$bin<-as.integer(cut(current$elapsed,bins))
bywoman<-split(seq_len(nrow(cal)),cal$woman_row);spells<-cal[cal$method_code%in%modern & cal$start>cal$calendar_start,]
records<-vector('list',nrow(spells))
for(i in seq_len(nrow(spells))){q<-spells[i,];last<-min(q$end,q$interview-15L);if(last<q$start)next
 t<-seq.int(q$start,last);future<-t+12L;tl<-cal[bywoman[[as.character(q$woman_row)]],];j<-findInterval(future,tl$start)
 stopifnot(all(j>0),all(tl$end[j]>=future));end<-q$end<future&q$reason_code%in%action
 records[[i]]<-data.frame(woman=q$woman_row,episode=i,method=mg(q$method_code),elapsed=t-q$start,wt=q$wt,
 cause=ifelse(end,cg(q$reason_code),NA_integer_),net=end&!tl$method_code[j]%in%endpoint_modern,
 direct=end&!is.na(q$next_code)&q$next_code%in%endpoint_modern)
}
land<-do.call(rbind,records);land$bin<-as.integer(cut(land$elapsed,bins))
ci<-setNames(lapply(methods,function(m)which(current$method==m)),methods)
li<-setNames(lapply(methods,function(m)lapply(1:8,function(b)which(land$method==m&land$bin%in%if(b==8)c(6L,7L)else b))),methods)
support<-do.call(rbind,lapply(methods,function(m)do.call(rbind,lapply(1:5,function(j){z<-land$method==m&!is.na(land$cause)&land$cause==j;n<-length(unique(land$episode[z]));data.frame(method=m,cause=causes[j],unique_episodes=n,pool_across_methods=n<10)}))))
write.csv(support,file.path(out,'switching_support.csv'),row.names=FALSE)
# Preserve the existing six-cause AFT specification. IUD shares the pooled
# Other-modern curve because the IUD sample is too sparse for separate fits.
af<-e[e$entry==0L&e$exposure>0,];af$method<-factor(ifelse(af$method_group=='IUD','Other modern',as.character(af$method_group)),levels=model_methods)
for(j in 1:5)af[[paste0('cause',j)]]<-as.integer(af$discontinued&af$reason_code%in%codes[[j]])
af$other<-as.integer(af$discontinued&!af$reason_code%in%action)
events<-c(paste0('cause',1:5),'other');fam<-read.csv(file.path(sup,'drc_aft_duration_fit.csv'))
dists<-fam$distribution[match(c(causes,'Other endings'),fam$cause)];stopifnot(!anyNA(dists))
maxage<-max(current$elapsed)+12L;times<-0:maxage
H<-function(t,mu,sc,dist){if(dist=='weibull')return((t/exp(mu))^(1/sc));if(dist=='exponential')return(t/exp(mu));if(dist=='loglogistic')return(log1p(exp((log(t)-mu)/sc)));if(dist=='lognormal')return(-pnorm((log(t)-mu)/sc,lower.tail=FALSE,log.p=TRUE));stop('Unknown AFT family')}
measure<-function(mult){
 iw<-wt*mult[pi];ew<-e$wt*mult[pi[e$woman_row]];lw<-land$wt*mult[pi[land$woman]];cw<-current$wt*mult[pi[current$woman]]
 mcpr<-100*sum(iw[u])/sum(iw);mix<-vapply(c(methods,'EC'),function(m)sum(iw[u&um==m])/sum(iw[u]),0.0)
 stock<-w25*(mcpr+.4)/100*mix
 risk<-array(0,c(8L,5L,5L),dimnames=list(c('First-year gross','Historical gross','AFT gross','Historical switching','AFT switching','First-year direct switches','Historical direct switches','AFT direct switches'),methods,causes))
 for(m in methods){d<-which(e$method_group==m);s<-1;v<-numeric(5)
  for(t in 1:12){at<-d[e$entry[d]<t&e$exposure[d]>=t];den<-sum(ew[at]);stopifnot(den>0);en<-at[e$discontinued[at]&e$exposure[at]==t]
   v<-v+s*vapply(codes,function(z)sum(ew[en[e$reason_code[en]%in%z]])/den,0.0);s<-s*(1-sum(ew[en])/den)}
  risk[1,m,]<-v
  for(j in 1:5){en<-d[e$discontinued[d]&e$exposure[d]<=12&e$reason_code[d]%in%codes[[j]]];den<-sum(ew[en]);if(den>0)risk[6,m,j]<-v[j]*sum(ew[en[e$next_code[en]%in%endpoint_modern]])/den}
  ix<-ci[[m]];den<-sum(cw[ix]);for(b in 1:8){share<-sum(cw[ix[current$bin[ix]==b]])/den;if(share==0)next
   z<-li[[m]][[b]];dd<-sum(lw[z]);if(dd<=0)stop('Empty historical duration cell')
   for(j in 1:5){ok<-!is.na(land$cause[z])&land$cause[z]==j
    risk[2,m,j]<-risk[2,m,j]+share*sum(lw[z][ok])/dd
    risk[4,m,j]<-risk[4,m,j]+share*sum(lw[z][ok&land$net[z]])/dd
    risk[7,m,j]<-risk[7,m,j]+share*sum(lw[z][ok&land$direct[z]])/dd}}
 }
 aw<-af$wt*mult[pi[af$woman_row]]
 fits<-lapply(1:6,function(j){ad<-af;ad$fw<-aw;fit<-suppressWarnings(survreg(as.formula(paste0('Surv(exposure,',events[j],')~method')),data=ad,weights=fw,dist=dists[j],control=survreg.control(maxiter=500)));if(fit$iter>=500||any(!is.finite(coef(fit)))||!is.finite(fit$scale))stop('AFT fit failed');fit})
 for(m in methods){mm<-if(m=='IUD')'Other modern'else m;nd<-data.frame(method=factor(mm,levels=model_methods))
  hh<-sapply(1:6,function(j){f<-fits[[j]];mu<-as.numeric(predict(f,newdata=nd,type='lp'));pmax(0,diff(H(times,mu,f$scale,dists[j])))})
  ix<-ci[[m]];den<-sum(cw[ix]);for(age in unique(current$elapsed[ix])){share<-sum(cw[ix[current$elapsed[ix]==age]])/den;h<-hh[age+1:12,,drop=FALSE];total<-rowSums(h);s<-c(1,exp(-cumsum(total)))[1:12]
   v<-colSums(s*(-expm1(-total))*h/pmax(total,1e-300))[1:5];risk[3,m,]<-risk[3,m,]+share*v}
  for(j in 1:5){pooled<-support$pool_across_methods[support$method==m&support$cause==causes[j]]
   denh<-if(pooled)sum(stock[methods]*risk[2,,j])else risk[2,m,j]
   frac<-if(denh>0)(if(pooled)sum(stock[methods]*risk[4,,j])else risk[4,m,j])/denh else NA_real_
   direct<-if(denh>0)(if(pooled)sum(stock[methods]*risk[7,,j])else risk[7,m,j])/denh else NA_real_
   stopifnot(is.finite(frac),is.finite(direct),frac>=0,frac<=1+1e-8)
   risk[5,m,j]<-risk[3,m,j]*frac;risk[8,m,j]<-risk[3,m,j]*direct}
 }
 result<-risk;for(m in methods)result[,m,]<-risk[,m,]*stock[m]
 stopifnot(all(is.finite(result)),all(result>=0),all(apply(risk,c(1,2),sum)<=1+1e-8))
 list(counts=result,risk=risk,mcpr=mcpr,mix=mix,stock=stock,users2024=w24*mcpr/100*mix)
}
point<-measure(rep(1,nrow(frame)));saveRDS(point,file.path(out,'planning_point.rds'))
# Main gross outputs must reproduce the saved report to numerical tolerance.
references<-list(read.csv(file.path(sup,'drc_current_users_by_method_and_actionable_projection.csv')),read.csv(file.path(sup,'drc_duration_aware_current_user_bridge.csv')),read.csv(file.path(sup,'drc_survival_model_duration_by_method.csv')))
fields<-c('illustrative_original_method_endings','projected_actionable_original_method_endings','survival_original_method_endings')
for(i in 1:3){q<-references[[i]];j<-match(methods,q$method);target<-q[[fields[i]]][j]*point$stock[methods]/q$current_users_2024[j];stopifnot(max(abs(rowSums(point$counts[i,,])-target))<.2)}
cat('Point totals:',apply(point$counts,1,sum),'\n');flush.console()
checkpoint<-file.path(out,'replicates');dir.create(checkpoint,showWarnings=FALSE)
# Smoothed Rao-Wu resampling retains sparse support, including two-PSU strata.
# Epsilon=1e-4; deviations are rescaled by 1/(1-epsilon) in the summary.
epsilon<-1e-4
one<-function(b){f<-file.path(checkpoint,sprintf('rep_%04d.rds',b));if(file.exists(f))return(readRDS(f));set.seed(20261105L+b)
 mult<-numeric(nrow(frame));for(ids in groups){n<-length(ids);raw<-n/(n-1)*tabulate(sample.int(n,n-1,replace=TRUE),nbins=n);mult[ids]<-epsilon+(1-epsilon)*raw}
 z<-tryCatch(measure(mult),error=function(e)list(error=conditionMessage(e)));saveRDS(z,f);z}
if(B>0){draws<-parallel::mclapply(seq_len(B),one,mc.cores=cores,mc.preschedule=FALSE);valid<-!vapply(draws,function(x)!is.null(x$error),FALSE);cat('Valid',sum(valid),'of',B,'\n');stopifnot(mean(valid)>=.95);saveRDS(draws[valid],file.path(out,'planning_replicates.rds'))}
saveRDS(list(wra2024=w24,wra2025=w25,wra2026=w26,psus=nrow(frame),strata=length(groups),replicates=B,epsilon=epsilon,methods=methods,causes=causes,
 definitions=c('Gross: every actionable ending treated as user lost','Switching sensitivity includes EC at year end; AFT pathway fractions pool across methods for <10 distinct historical episodes','IUD AFT uses Other-modern proxy; selected AFT families fixed','2025 mCPR = survey +0.4 pp; 2026 baseline increments 0,0.5,0.4 pp; population fixed')),file.path(out,'planning_metadata.rds'))
)-----")

MODULES[["213_summarize_planning.R"]] <- list(language="R",packaged_sha256="9120b3b56610a0fbb2536e1570655f4fc19f787c5edc52f6dbc665ec37e04e60",args=character(),code=r"-----(a<-commandArgs(TRUE);o<-if(length(a))a[1]else file.path(Sys.getenv('DRC_PROJECT_ROOT'),'output/survey_planning')
p<-readRDS(file.path(o,'planning_point.rds'));d<-readRDS(file.path(o,'planning_replicates.rds'));meta<-readRDS(file.path(o,'planning_metadata.rds'))
metrics<-function(x){
 x$counts<-abind::abind(x$counts,x$counts[1,,,drop=FALSE]-x$counts[6,,,drop=FALSE],x$counts[2,,,drop=FALSE]-x$counts[4,,,drop=FALSE],x$counts[3,,,drop=FALSE]-x$counts[5,,,drop=FALSE],along=1)
 y<-c(stock_no_ec=sum(x$stock[meta$methods]),mcpr2024=x$mcpr,mcpr2025=x$mcpr+.4,users2025=sum(x$stock),users2024=sum(x$users2024))
 for(m in c(meta$methods,'EC'))y[paste('stock',m,sep='|')]<-x$stock[m]
 for(i in 1:11)for(m in c(meta$methods,'Total'))for(c in c(meta$causes,'Total')){
  mi<-if(m=='Total')1:5 else match(m,meta$methods);ci<-if(c=='Total')1:5 else match(c,meta$causes)
  v<-sum(x$counts[i,mi,ci]);s<-if(m=='Total')sum(x$stock[meta$methods])else x$stock[m];key<-paste(i,m,c,sep='|')
  y[paste0('count|',key)]<-v;y[paste0('pp|',key)]<-100*v/meta$wra2026;y[paste0('risk|',key)]<-100*v/s
 }
 base<-x$mcpr+.4+c(0,.5,.4)
 for(j in 1:3){y[paste0('base|',j)]<-base[j];y[paste0('baseusers|',j)]<-base[j]/100*meta$wra2026
  for(i in 1:11)for(m in c(meta$methods,'EC','Total')){
   mix<-if(m=='Total')1 else x$mix[m];add<-if(m=='Total')sum(x$counts[i,,])else if(m=='EC')0 else sum(x$counts[i,m,]);b<-base[j]*mix;key<-paste(j,i,m,sep='|')
   y[paste0('usualusers|',key)]<-b/100*meta$wra2026;y[paste0('retainedusers|',key)]<-b/100*meta$wra2026+add;y[paste0('usualmcpr|',key)]<-b;y[paste0('retainedmcpr|',key)]<-b+100*add/meta$wra2026
  }
 }
 # Earlier 2024-to-2025 diagnostics, with the same probability definitions.
 legacy_base<-x$mcpr+c(0,(x$mcpr-8.121123)/10,.4)
 for(i in 1:5)for(m in c(meta$methods,'Total'))for(c in c(meta$causes,'Total')){
  mi<-if(m=='Total')1:5 else match(m,meta$methods);ci<-if(c=='Total')1:5 else match(c,meta$causes)
  allcounts<-sweep(x$counts[i,,,drop=FALSE][1,,],1,x$users2024[meta$methods]/x$stock[meta$methods],'*')
  v<-sum(allcounts[mi,ci]);key<-paste(i,m,c,sep='|');y[paste0('legacy_count|',key)]<-v;y[paste0('legacy_pp|',key)]<-100*v/meta$wra2025
  den<-sum(x$counts[if(i==4)2 else if(i==5)3 else i,mi,ci]);y[paste0('fraction|',key)]<-if(den>0)100*sum(x$counts[i,mi,ci])/den else 0
 }
 for(m in c(meta$methods,'EC','Total'))y[paste0('legacy_stock|',m)]<-if(m=='Total')sum(x$users2024)else x$users2024[m]
 for(j in 1:3){y[paste0('legacy_base|',j)]<-legacy_base[j]
  for(i in 1:5)for(m in c(meta$methods,'EC','Total')){
   mix<-if(m=='Total')1 else x$mix[m];add<-if(m=='Total')sum(sweep(x$counts[i,,,drop=FALSE][1,,],1,x$users2024[meta$methods]/x$stock[meta$methods],'*'))else if(m=='EC')0 else sum(x$counts[i,m,])*x$users2024[m]/x$stock[m]
   v<-legacy_base[j]*mix;key<-paste(j,i,m,sep='|');y[paste0('legacy_usualusers|',key)]<-v/100*meta$wra2025;y[paste0('legacy_retainedusers|',key)]<-v/100*meta$wra2025+add;y[paste0('legacy_usualmcpr|',key)]<-v;y[paste0('legacy_retainedmcpr|',key)]<-v+100*add/meta$wra2025
  }
 }
 y
}
pt<-metrics(p);ds<-vapply(d,metrics,pt)
# Correct the first-order attenuation from the small positive multiplier floor.
ds<-pt+(ds-pt)/(1-meta$epsilon)
lo<-apply(ds,1,quantile,.025);hi<-apply(ds,1,quantile,.975)
# Rare outcomes can put the observed estimate outside percentile bounds.
# Expand only as needed to include the point; retain the empirical bounds.
lo<-pmax(0,pmin(lo,pt));hi<-pmax(hi,pt)
percent<-grepl("^(risk|fraction|usualmcpr|retainedmcpr|legacy_usualmcpr|legacy_retainedmcpr)\\|",names(pt));hi[percent]<-pmin(100,hi[percent])
write.csv(data.frame(key=names(pt),estimate=unname(pt),lower=unname(lo),upper=unname(hi)),file.path(o,'planning_intervals.csv'),row.names=FALSE)
meta$valid_replicates<-length(d);jsonlite::write_json(meta,file.path(o,'metadata.json'),auto_unbox=TRUE,pretty=TRUE)
cat('95% intervals for',length(pt),'metrics from',ncol(ds),'valid replicates\n')
)-----")

MODULES[["214_fit_point_models.R"]] <- list(language="R",packaged_sha256="d141c96d2656bc8322109161f38f4cef565ca2f6ac0cf3957ebae3e5ef2baffa",args=character(),code=r"-----(#!/usr/bin/env Rscript
# DRC DHS 2023–24: adjusted province comparison for actionable discontinuation.
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

root <- Sys.getenv("DRC_PROJECT_ROOT", unset=normalizePath(file.path(getwd(), ".."), mustWork=FALSE))
support <- file.path(root,'output/Supporting_data')
derived <- file.path(root,'Data/Derived')
if(!requireNamespace('nnet',quietly=TRUE))stop('nnet package is required')
e <- readRDS(file.path(derived,'drc_2023_24_modern_episodes.rds'))
ir <- as.data.frame(haven::read_dta(Sys.getenv('DRC_IR_FILE', unset=file.path(root,'Data','CDIR81FL.dta'))))
times <- read.csv(file.path(support,'drc_modern_timepoints.csv'))
actionable <- c(1L,4L,5L,6L,7L,8L,10L,15L)
e$zone_name <- factor(e$province, levels=c('Kinshasa','Kongo Central','Kwango','Kwilu','Mai-Ndombe','Équateur','Nord-Ubangi','Sud-Ubangi','Mongala','Tshuapa','Tshopo','Bas-Uélé','Haut-Uélé','Ituri','Nord-Kivu','Sud-Kivu','Maniema','Haut-Katanga','Haut-Lomami','Lualaba','Tanganyika','Lomami','Sankuru','Kasaï Oriental','Kasaï','Kasaï Central'))
e$method_group <- factor(e$method_group,
  levels=c('Implants','Injectables','Pill','IUD','Other modern'))
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
# Pool recent starts to avoid sparse cohort terms.
year <- (e$start-1L)%/%12L+1900L
e$start_year <- factor(ifelse(year>=2023,'2023–24',as.character(year)))
complete <- complete.cases(e[,c('method_group','zone_name','age_group',
  'parity_group','marital_group','education','wealth','residence','start_year')])
cat('Complete-case episodes:',sum(complete),'of',nrow(e),'\n')
e <- e[complete,]
saveRDS(e,file.path(derived,'drc_2023_24_model_episode_covariates.rds'))

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
stopifnot(!anyNA(person),nrow(person)>10000)
saveRDS(person,file.path(derived,'drc_2023_24_person_month.rds'))

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
saveRDS(model1,file.path(derived,'drc_actionable_province_model_1.rds'))
saveRDS(model2,file.path(derived,'drc_actionable_province_model_2.rds'))

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
    unadjusted_pct=raw$actionable_pct,unadjusted_low=raw$actionable_ci_low,
    unadjusted_high=raw$actionable_ci_high,
    model_1_common_mix_pct=predict_cif(model1,z),
    model_2_common_mix_pct=predict_cif(model2,z))
}))
national <- times[times$scope=='National' & times$month==12,]
point <- rbind(data.frame(zone='National',
  eligible_episodes_n=national$eligible_episodes_n,
  actionable_endings_n=national$actionable_endings_n,
  unadjusted_pct=national$actionable_pct,
  unadjusted_low=national$actionable_ci_low,
  unadjusted_high=national$actionable_ci_high,
  model_1_common_mix_pct=predict_cif(model1,NULL),
  model_2_common_mix_pct=predict_cif(model2,NULL)),point)
write.csv(point,file.path(support,'drc_actionable_province_adjusted_rates.csv'),
  row.names=FALSE)


# Broader selected-reason diagnostics retain their existing outcome definition.
p2<-person
obs<-pmin(12L,e$exposure)-e$entry;index<-rep(seq_len(nrow(e)),obs)
mt<-as.integer(as.character(person$month));ended<-e$discontinued[index]&mt==e$exposure[index]
p2$outcome<-factor(ifelse(!ended,'continue',ifelse(e$reason_code[index]%in%c(2L,3L),'competing','selected')),levels=c('continue','selected','competing'))
selected_models<-lapply(list(f1,f2),function(f)fit(f,p2,p2$wt,TRUE))
for(k in 1:2)saveRDS(selected_models[[k]],file.path(derived,paste0('drc_selected_reason_province_model_',k,'.rds')))
pred<-function(model,zone){d<-standard;d$zone_name<-factor(zone,levels=levels(e$zone_name));s<-rep(1,nrow(d));v<-rep(0,nrow(d));for(t in 1:12){d$month<-factor(t,levels=1:12);p<-predict(model,newdata=d,type='probs');v<-v+s*p[,'selected'];s<-s*p[,'continue']};100*weighted.mean(v,d$wt)}
raw<-read.csv(file.path(support,'drc_selected_reason_subgroups.csv'));z<-raw[raw$group%in%paste0('zone_name::',zones),];z<-z[match(paste0('zone_name::',zones),z$group),]
point<-data.frame(province=zones,method_adjusted_pct=vapply(zones,function(a)pred(selected_models[[1]],a),0.0),fully_adjusted_pct=vapply(zones,function(a)pred(selected_models[[2]],a),0.0),method_adjusted_low=NA_real_,method_adjusted_high=NA_real_,fully_adjusted_low=NA_real_,fully_adjusted_high=NA_real_,observed_pct=z$selected_12_month_pct,observed_low=z$ci_low,observed_high=z$ci_high,eligible_episodes_n=z$eligible_episodes_n,selected_endings_n=z$selected_endings_n,small_cell=z$selected_endings_n<30L)
write.csv(point,file.path(support,'drc_selected_reason_province_adjusted_rates.csv'),row.names=FALSE)
cat('Weighted actionable and broader selected-reason point fits completed.\n')
)-----")

MODULES[["216_reconcile_reason_distributions.R"]] <- list(language="R",packaged_sha256="cd41f25bddd298261217cf16a07c7e51cf9a193d7c615b9a99f87ad87740e6ce",args=character(),code=r"-----(#!/usr/bin/env Rscript
# DRC reason-distribution validation, using DHS calendar Example 5 / Table 7.14.
# Run on supplied IR input; output paths are project-relative.
a<-commandArgs(TRUE);root<-if(length(a))normalizePath(a[1])else Sys.getenv('DRC_PROJECT_ROOT');out<-if(length(a)>1)a[2]else file.path(root,'output/Supporting_data');dir.create(out,recursive=TRUE,showWarnings=FALSE)
suppressPackageStartupMessages(library(haven))
x<-if(file.exists(file.path(root,'Data/ir.rds')))readRDS(file.path(root,'Data/ir.rds'))else as.data.frame(read_dta(Sys.getenv('DRC_IR_FILE',unset=file.path(root,'Data/CDIR81FL.dta'))))
methodchars<-strsplit('123456789WNALCFEMS~','')[[1]]
reasonchars<-c('1'=1L,'2'=2L,'3'=3L,'4'=4L,'5'=5L,'6'=6L,'7'=7L,'8'=8L,'9'=9L,'C'=10L,'F'=11L,'A'=12L,'D'=13L,'M'=15L,'W'=96L,'K'=98L,'?'=99L)
labels<-c('1'='Method failure','2'='Wanted pregnancy','3'='Partner disapproval','7'='Want more effective method','15'='Changes in menstrual bleeding','4'='Other side effects/health','5'='Other side effects/health','6'='Lack of access/too far','10'='Cost too much','8'='Inconvenient to use','11'='Fatalistic','12'='Difficulty becoming pregnant/menopause','9'='Infrequent sex/husband away','13'='Marital dissolution/separation','96'='Other','98'="Don't know",'99'='Missing')
reason_order<-unname(labels[c('1','2','3','7','15','4','6','10','8','11','12','9','13','96','98','99')])
recs<-lapply(0:59,function(t){p<-as.integer(x$v018)+t;v<-substring(x$vcal_2,p,p);i<-which(nzchar(trimws(v)));data.frame(woman=i,months_before_interview=rep(t,length(i)),method_code=match(substring(x$vcal_1[i],p[i],p[i]),methodchars),reason_code=unname(reasonchars[v[i]]),wt=as.numeric(x$v005[i])/1e6)})
d<-do.call(rbind,recs);stopifnot(!anyNA(d),all(d$method_code>0));d$reason<-unname(labels[as.character(d$reason_code)]);stopifnot(!anyNA(d$reason))
# Published Table 7.14 "Other" combines traditional W with LAM and other modern.
d$published_method<-c('Pill','IUD','Injectables','Diaphragm','Male condom','Female sterilization','Male sterilization','Rhythm','Withdrawal','Other','Implants','Abstinence','Other','Female condom','Foam/jelly','EC','Other','SDM','Unknown')[d$method_code]
# All recognized ongoing modern methods, excluding EC and traditional/unknown codes.
modern_codes<-c(1L,2L,3L,4L,5L,6L,7L,11L,13L,14L,15L,17L,18L)
d$modern<-d$method_code%in%modern_codes
d$method<-ifelse(d$method_code==1L,'Pill',ifelse(d$method_code==2L,'IUD',ifelse(d$method_code==3L,'Injectables',ifelse(d$method_code==11L,'Implants','Other modern'))))
# Reference transcribed from DRC DHS 2023–24 Table 7.14. Suppressed columns
# are checked for counts only, never treated as published percentage values.
reference<-list(
 'Injectables'=c(3.2,30.6,1.8,9.6,17.8,22,2.1,3.4,1.1,1.2,.2,3.3,2.2,.8,.7,0),
 'Implants'=c(.4,32.8,3,2.5,15.2,29.2,.6,1.1,.4,2.1,3.8,2.7,1.4,4.2,.5,.1),
 'Pill'=c(6.4,24.4,5.5,5.9,20.1,15.7,.3,.8,4,2,0,10.2,0,2.2,.1,2.5),
 'Male condom'=c(3.3,21.3,16.7,8.5,1.9,2.9,2.5,2.2,5.2,.4,.2,23.8,6.7,3.9,.3,.3),
 'EC'=c(5.2,25.1,.8,4.9,9.7,7.4,1.1,4.8,1.6,.1,1.2,23.5,6.3,3.8,0,4.5),
 'SDM'=c(14.5,32.5,5.7,11.5,4.2,2.2,0,0,3.3,.3,2.4,15.9,2.2,2,1.1,2),
 'Rhythm'=c(13.5,41.2,5.1,5.5,3.8,.4,.7,0,2.5,2.5,.6,18.9,2.3,1.1,.6,1.3),
 'Withdrawal'=c(9.2,35.1,12.3,11.4,1.3,.9,.2,0,3.4,1,1.1,15.3,2.7,3.7,1.9,.6),
 'Other'=c(5.4,33.9,8.3,16.1,5.6,1.7,.1,0,1.1,4,.1,15.3,1.3,3.6,.8,2.8),
 'All methods'=c(7.9,33.4,7.2,8.4,7.1,7.2,.8,.9,2.7,1.8,1,14.6,2.6,2.5,.8,1.3))
counts<-c('Male sterilization'=0,'IUD'=24,'Injectables'=614,'Implants'=609,'Pill'=422,'Male condom'=580,'Female condom'=11,'EC'=221,'SDM'=370,'Rhythm'=1712,'Withdrawal'=1078,'Other'=660,'All methods'=6301)
validation<-do.call(rbind,lapply(names(reference),function(m){q<-if(m=='All methods')d else d[d$published_method==m,];v<-vapply(reason_order,function(r)100*sum(q$wt[q$reason==r])/sum(q$wt),0.0);data.frame(method=m,reason=reason_order,estimate_pct=v,published_pct=reference[[m]],difference_pp=round(v,1)-reference[[m]],matches=round(v,1)==reference[[m]])}))
check_counts<-do.call(rbind,lapply(names(counts),function(m){q<-if(m=='All methods')d else d[d$published_method==m,];data.frame(method=m,weighted_count=sum(q$wt),published_count=unname(counts[m]),matches=round(sum(q$wt))==counts[m])}))
stopifnot(all(validation$matches),all(check_counts$matches))
write.csv(validation,file.path(out,'drc_table_7_14_validation.csv'),row.names=FALSE);write.csv(check_counts,file.path(out,'drc_table_7_14_count_validation.csv'),row.names=FALSE)
# Full-frame ratio linearization for reason shares. Counts are weighted;
# observed sample sizes remain explicitly unweighted.
frame<-unique(data.frame(psu=as.numeric(x$v021),stratum=as.numeric(x$v022)));frame<-frame[order(frame$stratum,frame$psu),];fi<-match(as.numeric(x$v021),frame$psu);df<-nrow(frame)-length(unique(frame$stratum));crit<-qt(.975,df)
share_rows<-function(q,method,reason_var='reason',order=reason_order){den<-sum(q$wt);n<-nrow(q);lapply(order,function(r){v<-as.numeric(q[[reason_var]]==r);p<-sum(q$wt*v)/den;sc<-q$wt*(v-p)/den;ps<-rowsum(sc,fi[q$woman],reorder=FALSE);score<-numeric(nrow(frame));score[as.integer(rownames(ps))]<-ps[,1];variance<-sum(vapply(split(score,frame$stratum),function(v){length(v)/(length(v)-1)*sum((v-mean(v))^2)},0.0));se<-sqrt(variance);if(p>0&&p<1){ci<-plogis(qlogis(p)+c(-1,1)*crit*se/(p*(1-p)))}else ci<-c(NA,NA);data.frame(method=method,reason=r,share_pct=100*p,ci_low=100*ci[1],ci_high=100*ci[2],weighted_endings=sum(q$wt*v),observed_endings_n=sum(v),method_endings_n=n,weighted_method_endings=den,sparse_method=n<25,sparse_reason=sum(v)<5)})}
methods<-c('All modern','Injectables','Implants','Pill','IUD','Other modern');m<-d[d$modern,]
grouped<-do.call(rbind,lapply(methods,function(s)do.call(rbind,share_rows(if(s=='All modern')m else m[m$method==s,],s))))
write.csv(grouped,file.path(out,'drc_five_year_reason_shares_corrected.csv'),row.names=FALSE)
# Same nine reason groups used for first-year presentation comparisons.
group9<-function(v){ifelse(v%in%c('Lack of access/too far','Cost too much','Inconvenient to use'),'Access/cost/convenience',ifelse(v%in%c('Difficulty becoming pregnant/menopause','Infrequent sex/husband away','Marital dissolution/separation'),'Other fertility',ifelse(v%in%c('Fatalistic','Other',"Don't know",'Missing'),'Other recorded',v)))}
order9<-c('Method failure','Wanted pregnancy','Other fertility','Changes in menstrual bleeding','Other side effects/health','Want more effective method','Access/cost/convenience','Partner disapproval','Other recorded')
m$reason9<-group9(m$reason)
grouped9<-do.call(rbind,lapply(methods,function(s)do.call(rbind,share_rows(if(s=='All modern')m else m[m$method==s,],s,'reason9',order9))))
write.csv(grouped9,file.path(out,'drc_five_year_reason_groups_corrected.csv'),row.names=FALSE)
# Correct the old five-year CSV without changing its column contract.
oldfile<-file.path(root,'output/Supporting_data/drc_five_year_reason_distribution_by_method.csv');old<-if(file.exists(oldfile))read.csv(oldfile)else NULL
labels_detail<-c('1'='Method failure','2'='Wanted pregnancy','3'='Partner disapproval','7'='Want more effective method','15'='Changes in menstrual bleeding','4'='Other side effects/health','5'='Other side effects/health','6'='Access/cost/convenience','10'='Access/cost/convenience','8'='Access/cost/convenience','11'='Other recorded: fatalistic','12'='Difficulty becoming pregnant/menopause','9'='Infrequent sex/husband away','13'='Marital dissolution/separation','96'='Other recorded: other','98'='Other recorded: unknown','99'='Other recorded: missing')
m$detail<-unname(labels_detail[as.character(m$reason_code)]);r<-aggregate(wt~method+detail,m,sum);names(r)<-c('method','reason','weighted_endings');den<-tapply(m$wt,m$method,sum);r$share_within_method_pct<-100*r$weighted_endings/den[r$method];r$observed_endings_n<-vapply(seq_len(nrow(r)),function(i)sum(m$method==r$method[i]&m$detail==r$reason[i]),0L)
write.csv(r,file.path(out,'drc_five_year_reason_distribution_by_method.csv'),row.names=FALSE)
if(!is.null(old)){comp<-merge(old[,c('method','reason','share_within_method_pct')],r[,c('method','reason','share_within_method_pct')],by=c('method','reason'),all=TRUE,suffixes=c('_old','_corrected'));comp[is.na(comp)]<-0;comp$difference_pp<-comp$share_within_method_pct_corrected-comp$share_within_method_pct_old
write.csv(comp,file.path(out,'drc_reason_share_corrections.csv'),row.names=FALSE)}
write.csv(as.data.frame(table(m$method)),file.path(out,'drc_reason_method_sample_sizes.csv'),row.names=FALSE)
cat('Table 7.14:',sum(validation$matches),'of',nrow(validation),'published percentage cells and',sum(check_counts$matches),'of',nrow(check_counts),'weighted counts match.\n')
print(grouped9[,c('method','reason','share_pct')]);if(!is.null(old))print(comp[order(-abs(comp$difference_pp)),][1:10,])

# First-year recorded-ending shares retain the presentation's existing scope.
e<-readRDS(file.path(root,'Data/Derived/drc_2023_24_modern_episodes.rds'))
f<-e[e$discontinued&e$exposure<=12,];f$woman<-f$woman_row;f$method<-as.character(f$method_group);f$reason<-unname(labels[as.character(f$reason_code)]);f$reason[is.na(f$reason)]<-'Missing';f$reason9<-group9(f$reason)
first<-do.call(rbind,lapply(methods,function(s)do.call(rbind,share_rows(if(s=='All modern')f else f[f$method==s,],s,'reason9',order9))))
write.csv(first,file.path(out,'drc_first_year_reason_groups_checked.csv'),row.names=FALSE)
# Specific modern methods are available separately from the presentation groups.
names_individual<-c('Pill','IUD','Injectables','Diaphragm','Male condom','Female sterilization','Male sterilization','Rhythm','Withdrawal','Other traditional','Implants','Abstinence','LAM','Female condom','Foam/jelly','EC','Other modern specified','SDM','Unknown')
m$individual_method<-names_individual[m$method_code]
ind<-do.call(rbind,lapply(unique(m$individual_method),function(k)do.call(rbind,share_rows(m[m$individual_method==k,],k,'reason9',order9))))
write.csv(ind,file.path(out,'drc_five_year_reason_groups_individual_methods.csv'),row.names=FALSE)
# Both display horizons use weights, and CI denominators use the full survey frame.
stopifnot(max(abs(tapply(first$share_pct,first$method,sum)-100))<1e-8,max(abs(tapply(grouped9$share_pct,grouped9$method,sum)-100))<1e-8)
cat('Both reason-share tables sum to 100% within every method before rounding.\n')
# Individual-method first-year shares and timing, preserving sparse support flags.
f$individual_method<-names_individual[f$method_code]
individual_first<-do.call(rbind,lapply(unique(f$individual_method),function(k)do.call(rbind,share_rows(f[f$individual_method==k,],k,'reason9',order9))))
write.csv(individual_first,file.path(out,'drc_first_year_reason_groups_individual_methods.csv'),row.names=FALSE)
variance_psu<-function(v)sum(vapply(split(v,frame$stratum),function(z)length(z)/(length(z)-1)*sum((z-mean(z))^2),0.0))
psutotal<-function(w,id){z<-numeric(nrow(frame));if(length(w)){q<-rowsum(w,id,reorder=FALSE);z[as.integer(rownames(q))]<-q[,1]};z}
act<-c(1L,4L,5L,6L,7L,8L,10L,15L)
individual_times<-do.call(rbind,lapply(sort(unique(e$method_code)),function(code){
 q<-e[e$method_code==code,];id<-fi[q$woman_row];s<-1;ds<-numeric(nrow(frame));v<-c(all_reason=0,actionable=0);dv<-matrix(0,2,nrow(frame));rows<-list()
 for(t in 1:12){at<-q$entry<t&q$exposure>=t;en<-at&q$exposure==t&q$discontinued;rp<-psutotal(q$wt[at],id[at]);R<-sum(rp)
  if(R>0){dp<-psutotal(q$wt[en],id[en]);ap<-psutotal(q$wt[en&q$reason_code%in%act],id[en&q$reason_code%in%act]);h<-c(sum(dp)/R,sum(ap)/R);dh<-rbind((dp-h[1]*rp)/R,(ap-h[2]*rp)/R);dv<-dv+h%o%ds+s*dh;v<-v+s*h;ds<-ds*(1-h[1])-s*dh[1,];s<-s*(1-h[1])
  }else if(s>1e-10){v[]<-NA_real_;dv[]<-NA_real_}
  if(t%in%c(3L,6L,9L,12L)){z<-data.frame(method=names_individual[code],month=t,eligible_episodes_n=nrow(q),observed_first_year_endings=sum(q$discontinued&q$exposure<=12),limited_precision=nrow(q)<50L||sum(q$discontinued&q$exposure<=12)<25L)
   for(j in 1:2){ci<-c(NA_real_,NA_real_);if(is.finite(v[j])&&v[j]>0&&v[j]<1){se<-sqrt(variance_psu(dv[j,]));ci<-plogis(qlogis(v[j])+c(-1,1)*crit*se/(v[j]*(1-v[j])))};nm<-names(v)[j];z[[paste0(nm,'_pct')]]<-100*v[j];z[[paste0(nm,'_ci_low')]]<-100*ci[1];z[[paste0(nm,'_ci_high')]]<-100*ci[2]}
   rows[[length(rows)+1L]]<-z}
 };do.call(rbind,rows)
}))
write.csv(individual_times,file.path(out,'drc_individual_method_timepoints_checked.csv'),row.names=FALSE)
cat('Individual-method reason shares and survey-design timing intervals exported.\n')
)-----")

# Shared full sampling frame. Zero-weight records preserve factor levels while
# supplying PSUs omitted by an outcome domain; source observations are intact.
SURVEY_FRAME_HELPERS <- r"-----(
full_survey_frame <- function(){r<-Sys.getenv('DRC_PROJECT_ROOT');x<-if(file.exists(file.path(r,'Data/ir.rds')))readRDS(file.path(r,'Data/ir.rds'))else as.data.frame(haven::read_dta(Sys.getenv('DRC_IR_FILE',unset=file.path(r,'Data/CDIR81FL.dta')),col_select=c(v021,v022)));unique(data.frame(cluster=as.numeric(x$v021),stratum=as.numeric(x$v022)))}
complete_survey_data <- function(d){f<-full_survey_frame();miss<-f[!f$cluster%in%d$cluster,];if(nrow(miss)){z<-d[rep(1L,nrow(miss)),,drop=FALSE];z$cluster<-miss$cluster;z$stratum<-miss$stratum;z$wt<-0;d<-rbind(d,z)};d}
)-----"

# Register labelled-variable conversions in fresh module subprocesses.
for(module_name in names(MODULES))if(MODULES[[module_name]]$language=='R') {
  MODULES[[module_name]]$code<-paste0("if(!requireNamespace('haven',quietly=TRUE))stop('Install R package haven first.')\n",SURVEY_FRAME_HELPERS,"\n",MODULES[[module_name]]$code)
}

# Execute only when called as the command-line entry point.

# Latest revision calculations and incremental report rendering.
REVISED_GROWTH_ASSUMPTIONS <- r"--------({
  "scenarios": [
    {
      "scenario": "Recent DHS trend (2014\u20132024)",
      "annual_change_pp": 0.1772811744012914
    },
    {
      "scenario": "Longer-term DHS trend (2007\u20132024)",
      "annual_change_pp": 0.1905467681009662
    },
    {
      "scenario": "FPET-informed growth",
      "annual_change_pp": 0.4000000000000004
    }
  ],
  "rates_from": {
    "dhs2007": 6.654640011984162,
    "dhs2014": 8.121123325687673,
    "dhs2024": 9.893935069700587,
    "fpet2024": 10.4,
    "fpet2025": 10.8
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
    "title": "First-year: 10-year DHS trend by method",
    "kind": "method_scenario",
    "approach": 1,
    "scenario": 1
  },
  {
    "title": "First-year: 17-year DHS trend by method",
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
    "title": "Historical duration-aware: 10-year DHS trend by method",
    "kind": "method_scenario",
    "approach": 2,
    "scenario": 1
  },
  {
    "title": "Historical duration-aware: 17-year DHS trend by method",
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
    "title": "AFT survival: 10-year DHS trend by method",
    "kind": "method_scenario",
    "approach": 3,
    "scenario": 1
  },
  {
    "title": "AFT survival: 17-year DHS trend by method",
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
    "title": "Historical sensitivity: 10-year DHS trend by method",
    "kind": "method_scenario",
    "approach": 4,
    "scenario": 1
  },
  {
    "title": "Historical sensitivity: 17-year DHS trend by method",
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
    "title": "AFT sensitivity: 10-year DHS trend by method",
    "kind": "method_scenario",
    "approach": 5,
    "scenario": 1
  },
  {
    "title": "AFT sensitivity: 17-year DHS trend by method",
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
if(is.null(meta$epsilon))meta$epsilon<-0
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
labels=[f'10-year DHS trend\n({meta["scenarios"][0]["annual_change_pp"]:+.2f} pp/year)',f'17-year DHS trend\n({meta["scenarios"][1]["annual_change_pp"]:+.2f} pp/year)',f'FPET-informed growth\n({meta["scenarios"][2]["annual_change_pp"]:+.2f} pp/year)']
short=['10-year DHS trend','17-year DHS trend','FPET-informed growth']
def val(key,kind='num',deck=False):
 x=D[key];scale=1000 if deck and kind=='num' else 1;digits=(1 if deck else 0) if kind=='num' else 1 if kind=='risk' else 2
 def f(y):return '<0.01' if kind=='pp' and 0<y<.005 else '<0.1' if kind=='num' and deck and 0<y/scale<.05 else f'{y/scale:,.{digits}f}'
 suffix=' pp' if kind=='pp' else '%' if kind in ['risk','pct'] else ''
 v=f(x['estimate'])+suffix
 if x['estimate']==x['lower']==x['upper']==0:return v+'\n(CI unavailable†)'
 if abs(x['upper']-x['lower'])>1e-10:v+='\n('+f(x['lower'])+'–'+f(x['upper'])+')'
 return v
def make(sp,deck):
 s=copy.deepcopy(sp);a=s['approach'];kind=s['kind'];base=2 if a==4 else 3 if a==5 else a;label=s['title'].split(':')[0]
 s['subtitle']='Users in thousands; estimates (95% CI)' if deck else 'Numbers of women; estimates (95% survey intervals)'
 c=lambda m,ca:val(f'count|{a}|{m}|{ca}',deck=deck)
 pp=lambda m,ca:val(f'pp|{a}|{m}|{ca}','pp',deck)
 stock=lambda m:val('users2024' if m=='Total' else 'stock|'+m,deck=deck)
 name=lambda m:'IUD*' if m=='IUD' else m
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
 definitions={1:'First-year: weighted actionable cumulative incidence in months 1–12 after initiation, applied to observed 2024 current users. Elapsed use is not incorporated.',2:'Historical: observed next-12-month actionable ending probability at current elapsed duration. The 61+ month group uses 37–60-month experience.',3:'AFT: six weighted method-specific cause-specific survival models predict next-12-month outcomes conditional on elapsed use. Five actionable causes compete with other endings.'}
 s['note']=definitions[base]
 s['note']+=(' Sensitivity: year-end losses deduct modern-to-modern switches and later restarters; EC counts as modern at year end.' if a>3 else ' Every actionable original-method ending is treated as a lost user. Switching/restarting is not deducted.')
 s['note']+=' Partner/spousal disapproval is excluded. The observed 2024 cohort is fixed across scenarios. 95% intervals use 500 stratified PSU bootstrap draws; growth and population assumptions are fixed. CI bounds are not additive.'
 if base==3:s['note']+=' * IUD uses the Other-modern AFT curve. Sparse switching fractions pool across methods.' if a>3 else ' * IUD uses the Other-modern AFT curve.'
 else:s['note']+=' * IUD: 23 eligible episodes and 14 current users.'
 s['note']+=' † No reliable empirical CI when no events were observed.'
 if kind=='method':s['note']+=' Total ending probability averages method-specific risks using the 2024 current-user mix, excluding EC.'
 if kind=='baseline':s['note']=f'Recent annual change = (2024 DHS {meta["rates_from"]["dhs2024"]:.4f}% − 2014 DHS {meta["rates_from"]["dhs2014"]:.4f}%)/10. Longer-term change = (2024 DHS − 2007 DHS {meta["rates_from"]["dhs2007"]:.4f}%)/17. FPET-informed change = {meta["rates_from"]["fpet2025"]:.1f}% − {meta["rates_from"]["fpet2024"]:.1f}%. Each is added to the 2024 DHS baseline. Growth assumptions are fixed.'
 return s
for deck in [True,False]:(out/('planning_slides.json' if deck else 'planning_html.json')).write_text(json.dumps([make(s,deck) for s in old],indent=2))
print('Built 40 DRC tables for 2024-to-2025, including both switching sensitivity sets.')
)--------",
  "302_revised_html.py" = r"--------(from pathlib import Path
from lxml import html,etree
from html import escape
import json,csv,re,copy,sys
source,freshfile,stats,specfile,target=map(Path,sys.argv[1:]);doc=html.parse(str(freshfile));old=html.parse(str(source));oldids=set(old.xpath('//section/@id'))
specs=json.loads(specfile.read_text());meta=json.loads((stats/'metadata.json').read_text());D={r['key']:{k:float(r[k]) for k in ['estimate','lower','upper']} for r in csv.DictReader((stats/'planning_intervals.csv').open())}

for sid in ['switching-sensitivity','historical-switching-sensitivity','aft-observed-pathway-sensitivity']:
 for e in doc.xpath(f'//section[@id="{sid}"]'):e.getparent().remove(e)
methods=meta['methods'];causes=meta['causes'];short=['Method failure','Want more effective','Bleeding changes','Other side effects/health','Access/cost/convenience']
main=doc.find('.//main')
def sec(sid):return doc.xpath(f'//section[@id="{sid}"]')[0]
def content(sid,title,markup):
 s=sec(sid);s.clear();s.set('id',sid);h=html.Element('h2');h.text=title;s.append(h)
 for el in html.fragments_fromstring(markup):
  if isinstance(el,str):s.text=(s.text or'')+el
  else:s.append(el)
 return s
def table(rows):return '<div class="table-wrap"><table class="analysis-table"><thead><tr>'+''.join('<th>'+escape(str(c)).replace('\n','<br>')+'</th>' for c in rows[0])+'</tr></thead><tbody>'+''.join('<tr>'+''.join(('<th scope="row">' if j==0 else'<td>')+escape(str(c)).replace('\n','<br>')+('</th>' if j==0 else'</td>') for j,c in enumerate(row))+'</tr>' for row in rows[1:])+'</tbody></table></div>'
def article(s):return '<article class="planning-table"><h3>'+escape(s['title'])+'</h3><p>'+escape(s['subtitle'])+'</p>'+table(s['table'])+'<p class="note">'+escape(s['note'])+'</p></article>'
def val(key,kind='count'):
 x=D[key];digits=0 if kind=='count'else 1 if kind=='risk'else 2
 def f(v):return '<0.01' if kind=='pp'and 0<v<.005 else f'{v:,.{digits}f}'
 suffix=' pp'if kind=='pp'else'%'if kind in ['risk','pct']else''
 v=f(x['estimate'])+suffix
 if x['lower']==x['upper']==0:return v+'\n(CI unavailable†)'
 if abs(x['upper']-x['lower'])<1e-9:return v+'\n(fixed)'if kind=='pct'else v
 return v+'\n('+f(x['lower'])+'–'+f(x['upper'])+')'
def cirows(a,legacy=False):
 prefix='legacy_'if legacy else'';wra=meta['wra2025']if legacy else meta['wra2025'];rows=[['Method / measure',*short,'All actionable causes']]
 for m in methods:rows.append(['IUD*'if m=='IUD'else m]+[val(f'{prefix}count|{a}|{m}|{c}')for c in causes]+[val(f'{prefix}count|{a}|{m}|Total')])
 rows.append(['Users ending / year-end losses']+[val(f'{prefix}count|{a}|Total|{c}')for c in causes]+[val(f'{prefix}count|{a}|Total|Total')])
 rows.append([f'{2025} women aged 15–49 (fixed)']+[f'{wra:,.1f}']*6)
 rows.append(['mCPR equivalent (pp)']+[val(f'{prefix}pp|{a}|Total|{c}','pp')for c in causes]+[val(f'{prefix}pp|{a}|Total|Total','pp')]);return rows
base_note='<p class="note">Estimates show 95% survey confidence intervals. Population and growth assumptions are fixed. CI bounds do not add across methods/causes. † No reliable interval from zero observed events. * IUD estimates are sparse; its AFT curve is an Other-modern proxy.</p>'
# Canonical 2026 main sets contain gross actionable endings only.
content('mcpr-2026-retention-scenarios','2026 planning: first-year actionable method endings',
 '<p>The observed 2024 DHS current-user cohort is followed over the next 12 months to 2025. Current method mix remains at its survey distribution. The 2025 baseline mCPR equals the 2024 survey estimate plus the recent DHS, longer-term DHS, or FPET-informed annual change. Main tables assume every potentially actionable original-method ending is a lost modern user; switching/restarting is not deducted.</p>'+''.join(article(s)for s in specs[:8]))
content('historical-duration-aware-planning','Historical duration-aware planning: all actionable endings treated as user losses',
 '<p>These eight tables condition next-12-month actionable-ending probabilities on the current method and time already used. They use observed historical calendar landmarks and do not deduct switching or restarting. Duration 61+ months uses the observed 37–60-month proxy.</p>'+''.join(article(s)for s in specs[8:16]))
content('aft-duration-aware-planning','AFT survival planning: all actionable endings treated as user losses',
 '<p>These eight tables use six weighted cause-specific AFT models: five actionable causes and other competing endings. Current elapsed use conditions each next-12-month prediction. IUD shares the Other-modern curve. Switching/restarting is not deducted.</p>'+''.join(article(s)for s in specs[16:24]))
# All earlier switching tables move below the main three approaches.
div=html.Element('section',id='switching-sensitivity');div.append(html.Element('h2'));div[0].text='Appendix: Sensitivity analysis if some users who discontinue switch'
div.append(html.fragment_fromstring('<div><p>The following historical and AFT sets count women outside modern use at year end after a potentially actionable ending. Direct switching and later restarting can therefore reduce the gross count. EC is counted as modern at year end, consistently with the mCPR definition.</p><ul><li>Switching/restarting pathways are retrospective; future behavior and intervention effects are not identified.</li><li>IUD has 23 eligible episodes and 14 current users. AFT uses an Other-modern proxy. Implant method failure has only two first-year training events.</li><li>Eight of 25 AFT method–cause pathway fractions pool across methods because fewer than 10 distinct historical episodes support the narrower cell. Repeated monthly landmarks are not independent episodes.</li><li>Historical 61+ months uses a 37–60-month proxy. AFT intervals hold selected distribution families fixed.</li><li>500 stratified PSU bootstrap replicates propagate sampling uncertainty in prevalence, method/duration mix, risks, fitted curves and pathways. A small positive weight floor preserves sparse support; deviations are corrected for its first-order attenuation. Population and growth assumptions remain fixed.</li></ul></div>'))
main.append(div)
for sid,title,part in [('historical-switching-sensitivity','Historical sensitivity: switching and restarting',specs[24:32]),('aft-observed-pathway-sensitivity','AFT sensitivity: switching and restarting',specs[32:40])]:
 s=html.Element('section',id=sid);h=html.Element('h2');h.text=title;s.append(h)
 for sp in part:s.append(html.fragment_fromstring(article(sp)))
 main.append(s)
# Detailed 2026 matrices stay available with intervals for every mCPR cell.
content('mcpr-2026-method-detail','2026 method-specific user and mCPR detail',
 '<p>Method-specific results under all three growth scenarios appear in each main approach and sensitivity set above. The usual 2026 method mix is held at the observed current-user mix.</p>'+''.join(article(s)for s in specs if s['approach']in[1,2,3]and s['kind']=='method_scenario'))
content('actionable-cause-mcpr-ceiling','2026 percentage-point equivalents by actionable cause',
 '<p>Every cause uses the same 2026 WRA denominator. Gross tables assume all actionable endings are losses. Sensitivity tables deduct women using modern contraception at year end.</p>'+''.join(article(s)for s in specs if s['kind']=='cause_pp'))
# Preserve the earlier 2024-to-2025 illustration as separate diagnostics with CIs.
legacy_intro='<p>These complementary diagnostics use the same observed 2024 current-user cohort and projected 2025 women ages 15–49 as the main tables. The probabilities and survey bootstrap are unchanged; the current-user cohort, population denominator, and growth scenarios now agree throughout.</p>'
legacy_method=[['Method','2024 current users','First-year actionable discontinuation','Original-method endings','2025 mCPR equivalent']]
for m in methods:legacy_method.append(['IUD*'if m=='IUD'else m,val('legacy_stock|'+m),val(f'risk|1|{m}|Total','risk'),val(f'legacy_count|1|{m}|Total'),val(f'legacy_pp|1|{m}|Total','pp')])
legacy_sc=[['Different mCPR growth scenarios','2024 mCPR','2025 mCPR','2025 women 15–49 (fixed)','Gross equivalent (pp)','2025 mCPR if retained']]
for j,name in enumerate(['10-year DHS trend','17-year DHS trend','FPET-informed growth'],1):legacy_sc.append([name,val('mcpr2024','pct'),val(f'legacy_base|{j}','pct'),f'{meta["wra2025"]:,.0f}',val('legacy_pp|1|Total|Total','pp'),val(f'legacy_retainedmcpr|{j}|1|Total','pct')])
content('expected-user-calculations','Earlier 2024-to-2025 first-year illustration',legacy_intro+table(legacy_method)+table(cirows(1,True))+table(legacy_sc)+base_note)
content('current-user-actionable-projection','Current-user actionable projection definitions',
 '<p>The earlier 2024-to-2025 tables are in <a href="#expected-user-calculations">the earlier-horizon illustration</a>. The main 2025-to-2026 first-year set is <a href="#mcpr-2026-retention-scenarios">here</a>. Both assume every actionable original-method ending is a lost user.</p>')
content('duration-adjusted-reason-planning','Choosing the duration-aware planning approach',
 '<p>The main <a href="#historical-duration-aware-planning">historical</a> and <a href="#aft-duration-aware-planning">AFT</a> sets use gross actionable endings. Their <a href="#switching-sensitivity">switching sensitivities</a> are in the appendix. Earlier 2024-to-2025 diagnostics are retained below, using their own population denominator.</p>')
# Earlier duration diagnostics reproduce the previous analyses without bare pp cells.
legacy=['<h3>2024-to-2025 comparison of gross endings and year-end nonmodern use</h3>']
comparison=[['Approach','Gross original-method endings','Outside modern use at year end','Gross equivalent (pp)','Year-end equivalent (pp)']]
for a,name,net in [(1,'First-year',None),(2,'Historical',4),(3,'AFT',5)]:comparison.append([name,val(f'legacy_count|{a}|Total|Total'),'Not estimated'if net is None else val(f'legacy_count|{net}|Total|Total'),val(f'legacy_pp|{a}|Total|Total','pp'),'Not estimated'if net is None else val(f'legacy_pp|{net}|Total|Total','pp')])
legacy.append(table(comparison))
for a,name,net in [(2,'Historical',4),(3,'AFT',5)]:
 rows=[['Method','2024 current users','Next-12-month actionable discontinuation','Original-method endings','Outside modern use at year end']]
 for m in methods:rows.append(['IUD*'if m=='IUD'else m,val('legacy_stock|'+m),val(f'risk|{a}|{m}|Total','risk'),val(f'legacy_count|{a}|{m}|Total'),val(f'legacy_count|{net}|{m}|Total')])
 legacy.append('<h3>'+name+': original endings and year-end outcomes</h3>'+table(rows))
rows=[['Growth scenario','Usual 2025 mCPR','Historical year-end equivalent (pp)','AFT year-end equivalent (pp)']]
for j,name in enumerate(['10-year DHS trend','17-year DHS trend','FPET-informed growth'],1):rows.append([name,val(f'legacy_base|{j}','pct'),val('legacy_pp|4|Total|Total','pp'),val('legacy_pp|5|Total|Total','pp')])
legacy.append(table(rows))
for a,name in [(1,'First-year gross'),(4,'Historical switching sensitivity'),(5,'AFT switching sensitivity')]:
 legacy.append('<h3>'+name+': earlier method–cause matrix</h3>'+table(cirows(a,True)))
 for j,scenario in enumerate(['10-year DHS trend','17-year DHS trend','FPET-informed growth'],1):
  rows=[['Method','2024 current users','2025 usual users','Users counted if retained','Usual mCPR share','If retained mCPR share']]
  for m in methods+['EC','Total']:
   rows.append(['All modern'if m=='Total'else'IUD*'if m=='IUD'else m,val('legacy_stock|'+m),val(f'legacy_usualusers|{j}|{a}|{m}'),'Not estimated'if m=='EC'else val(f'legacy_count|{a}|{m}|Total'),val(f'legacy_usualmcpr|{j}|{a}|{m}','pct'),val(f'legacy_retainedmcpr|{j}|{a}|{m}','pct')])
  legacy.append('<h4>'+name+': '+scenario+'</h4>'+table(rows))
oldbin=copy.deepcopy(sec('duration-planning-appendix').xpath('.//table')[-1])
content('duration-planning-appendix','Appendix: earlier duration-aware diagnostics with uncertainty',legacy_intro+''.join(legacy)+base_note+'<h3>Historical duration support</h3><p>Landmark counts repeat episodes at different months and are not independent observations. These descriptive support counts retain their original definitions.</p>')
sec('duration-planning-appendix').append(oldbin)
content('duration-modern-use-2026-bridge','Appendix: original-method endings and modern use at year end',
 '<p>These two tables use observed 2024 users and the projected 2025 WRA denominator. The ending probability remains the gross actionable probability; year-end losses deduct switching and restarting.</p>'+article(specs[24])+article(specs[32]))
rows=[['Approach','Method','Actionable cause','Original-method endings','Users counted for mCPR','mCPR equivalent (pp)']]
for a,name in [(1,'First-year gross'),(2,'Historical gross'),(3,'AFT gross'),(4,'Historical sensitivity'),(5,'AFT sensitivity')]:
 for m in methods:
  for c in causes:rows.append([name,'IUD*'if m=='IUD'else m,c,val(f'count|{2 if a==4 else 3 if a==5 else a}|{m}|{c}'),val(f'count|{a}|{m}|{c}'),val(f'pp|{a}|{m}|{c}','pp')])
content('duration-aware-cause-pp-matrices','Appendix: complete method–cause planning estimates',table(rows)+base_note)
rows=[['Method','Cause','AFT actionable probability','AFT original-method endings','Fraction outside modern use at year end','AFT year-end losses']]
for m in methods:
 for c in causes:rows.append(['IUD*'if m=='IUD'else m,c,val(f'risk|3|{m}|{c}','risk'),val(f'count|3|{m}|{c}'),val(f'fraction|5|{m}|{c}','risk'),val(f'count|5|{m}|{c}')])
content('aft-switching-sensitivity','Appendix: AFT observed-pathway fractions',
 '<p>Eight sparse method–cause pathway fractions are pooled across methods. Fractions reflect modern-use status at year end and include later restarting. They are not causal switching probabilities.</p>'+table(rows)+base_note)
# Broader selected-reason projections remain labelled and receive joint survey CIs.
# Updated numerical cells are supplied by the survey-projection export.
projection=stats/'selected_projection.json'
if projection.exists():
 content('current-user-reason-planning','Broader selected-reason current-user illustration',
  '<p>This diagnostic includes endings other than wanted pregnancy or partner disapproval, including circumstances outside the actionable set. Main actionable planning tables are separate. First-year cause probabilities are applied to observed 2024 users without elapsed-duration adjustment.</p>'+table(json.loads(projection.read_text()))+base_note)
# Refresh the historical stock-to-outcome bridge with the same corrected estimates.
flow=sec('standardized-current-users')
flow_figure=copy.deepcopy(flow.xpath('.//figure')[0])
content('standardized-current-users','Current-user stock and year-end outcomes',
 '<p>Switching/restarting sensitivity: the observed 2024 cohort is followed to 2025 using historical duration-aware actionable-ending probabilities. The flow follows only women with an actionable original-method ending. It separates those using a modern method again at year end from those outside modern use. EC counts as modern at year end.</p>'+article(specs[24]))
flow=sec('standardized-current-users');flow.insert(2,flow_figure)
# Keep numerical tests legible rather than rounding p values to one decimal.
for csvpath in (stats.parent/'project/output/Supporting_data').glob('*.csv'):
 records=list(csv.reader(csvpath.open()))
 if not records or not any(c in records[0] for c in ['p_value','p_raw']):continue
 headers=records[0]
 for oldtable in list(doc.xpath('//table')):
  if [c.text_content().strip()for c in oldtable.xpath('./thead/tr/th')]!=headers:continue
  if len(oldtable.xpath('./tbody/tr'))!=len(records)-1:continue
  rows=[headers]
  for record in records[1:]:
   row=[]
   for key,value in zip(headers,record):
    if key in ['p_value','p_raw','p_holm']:
     value=('<0.001' if float(value)<.001 else f'{float(value):.3f}')
    elif key in ['odds_ratio','ci_low','ci_high','survey_se','difference_pp','se_pp']:
     value=f'{float(value):.2f}'
    row.append(value)
   rows.append(row)
  newtable=html.fragment_fromstring(table(rows));parent=oldtable.getparent()
  parent.replace(oldtable,newtable[0])

# Move appendix sections to the end after all three gross approaches.
append_ids=['switching-sensitivity','standardized-current-users','historical-switching-sensitivity','aft-observed-pathway-sensitivity','duration-planning-appendix','switching-2026-bridge','duration-modern-use-2026-bridge','duration-aware-cause-pp-matrices','aft-switching-sensitivity']
for sid in append_ids:s=sec(sid);s.getparent().remove(s);main.append(s)
# Add methods explaining full-frame inference and conditional planning uncertainty.
methods_note='<h3>Survey-design inference audit</h3><p>All point estimates use v005/1,000,000. Inference uses all 778 PSUs and 51 strata, including 141 PSUs with no eligible modern-method episodes. Repeated episodes/months stay within the woman\'s PSU. Life-table intervals use design linearization. Adjusted probability intervals combine full-frame clustered model-score covariance with uncertainty in the empirical common-reference distribution. Pairwise tests use joint covariance, 727 design degrees of freedom, and Holm correction over all 325 province pairs separately by stage/time.</p><p>Planning intervals use 500 Rao–Wu PSU bootstrap replicates within strata, with a 0.0001 positive-weight floor to retain sparse support. Replicate deviations are rescaled by 1/(1−0.0001). Current prevalence, mix, duration, risks, AFT fitting and pathways are propagated jointly; population, growth assumptions and selected AFT families are fixed. CI bounds are not additive. No-event cells have no reliable empirical interval and are flagged.</p><p>The historical gross count is unchanged from the saved calculation. Switching sensitivities now count EC as modern at year end. AFT sensitivities pool eight sparse pathway fractions rather than assuming that unsupported method–cause cells imply no year-end loss.</p>'
# Existing full-frame methods audit is retained without duplication.
# Correct stale descriptions without rewriting the underlying all-cause chapters.

for element in doc.iter():
 if element.text:element.text=element.text.replace('2026','2025').replace('main projected-2025-to-2025','main observed-2024-to-2025').replace('2025-to-2025','2024-to-2025').replace('The historical gross count is unchanged from the saved calculation.','Gross and switching-sensitive probabilities are unchanged; user counts now use the observed 2024 cohort and 2025 WRA denominator.')
 if element.tail:element.tail=element.tail.replace('2026','2025')
text=etree.tostring(doc,encoding='unicode',method='html')
text=text.replace('2025-to-2025','2024-to-2025').replace('using their own population denominator','using the same 2025 population denominator')
text=text.replace('Five-year recorded reasons by modern method','Recorded reasons across the observed calendar by modern method')
text=text.replace('two-sided normal approximations using bootstrap standard errors','two-sided t tests using survey-linearized standard errors and 727 design degrees of freedom')
for a,b in [('survey-bootstrap confidence intervals','survey-design confidence intervals'),('design-bootstrap 95% confidence intervals','survey-design 95% confidence intervals'),('stratified-PSU bootstrap','full-frame survey linearization'),('stratified PSU bootstrap','full-frame survey linearization'),('120 survey-stratified PSU-bootstrap model refits','full-frame survey linearization'),('Survey-stratified PSU-bootstrap intervals','Full-frame survey-design intervals')]:text=text.replace(a,b)
doc=html.document_fromstring(text)
# Remove obsolete Source-prefixed display notes while retaining method explanations.
for el in list(doc.xpath('//p|//figcaption|//div[@class="note"]')):
 if re.match(r'^\s*(DHS source|Source\s*:|National row is gold)',el.text_content(),re.I):el.getparent().remove(el)
# Make the country report standalone so moving/uploading it cannot break figures.
# Slide-gallery images are refreshed after the final PPTX render in a separate pass.
for im in doc.xpath('//img'):
 src=im.get('src','')
 if src.startswith(('http:','https:','data:')):continue
 src=src.split('?')[0];path=freshfile.parent/src
 if not path.exists():raise RuntimeError('Missing figure '+src)
 im.set('src',src)
# Comprehensive left navigation includes all section headings and table headings.
nav=doc.find('.//aside')
for a in list(nav.xpath('./a')):nav.remove(a)
seen=set(doc.xpath('//@id'))
for i,h in enumerate(doc.xpath('//main//h2|//main//h3'),1):
 parent=h.getparent();sid=parent.get('id')if h.tag=='h2'else None
 if not sid:
  sid=f'analysis-heading-{i}';h.set('id',sid)
 link=html.Element('a',href='#'+sid);link.text=h.text_content();
 if h.tag=='h3':link.set('style','padding-left:12px;font-size:11.5px')
 nav.append(link)
# Planning tables use navy headers and readable multiline estimates.
style=doc.find('.//style');style.text=(style.text or'')+'\n.planning-table table{font-size:13px}.planning-table td{white-space:normal;min-width:110px}.planning-table tbody th{background:#f1f6f8;color:#173f5b;position:static}.planning-table .note{font-size:12px}.planning-table{margin:26px 0 40px}tbody tr:last-child{font-weight:600}\n'
assert oldids<=set(doc.xpath('//section/@id'))
result=html.tostring(doc,encoding='unicode',doctype='<!DOCTYPE html>')
target.write_text(result)
print('Updated HTML with',len(doc.xpath('//section')),'sections and',len(doc.xpath('//table')),'tables.')
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
