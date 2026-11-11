#!/usr/bin/env python3
"""Check shared repository files and optional incremental report rebuilds.

Checks structure, privacy patterns and aggregate numerical identities. It does
not establish that a statistical model is correct or that forecasts will hold.
"""
import argparse
import base64
import hashlib
from datetime import date
import io
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET
import zipfile
from lxml import html

COUNTRIES = {
    'Ethiopia': ('Ethiopia_discontinuation_analysis.html', 'ethiopia_presentation.pptx', 'Ethiopia_final_html_analysis.R', 107, 162, 2025, 2026),
    'Nigeria': ('Nigeria_discontinuation_analysis.html', 'Nigeria_discontinuation.pptx', 'Nigeria_final_html_analysis.R', 98, 141, 2024, 2025),
    'DRC': ('DRC_discontinuation_analysis.html', 'DRC_discontinuation.pptx', 'DRC_final_html_analysis.R', 79, 199, 2024, 2025),
}
IGNORED = {'.git', 'work', 'analysis_output', '__pycache__', '.Rproj.user'}
TEXT_SUFFIXES = {'.R', '.py', '.md', '.txt', '.json', '.csv', '.html'}
PATTERNS = [
    re.compile(rb'/(?:Users|Volumes|home|private|tmp)/', re.I),
    re.compile(rb'file:[/\\]{2}', re.I),
    re.compile(rb'[A-Z]:[\\/](?:Users|Documents and Settings)[\\/]', re.I),
    re.compile(rb'https?://(?:localhost|127\.0\.0\.1)(?::\d+)?', re.I),
    re.compile(rb'\bAKIA[0-9A-Z]{16}\b|\bghp_[A-Za-z0-9]{30,}|\bgithub_pat_[A-Za-z0-9_]{30,}'),
]
P = 'http://schemas.openxmlformats.org/presentationml/2006/main'
A = 'http://schemas.openxmlformats.org/drawingml/2006/main'


def require(condition, message):
    if not condition:
        raise ValueError(message)


def shared_files(root):
    return sorted(p for p in root.rglob('*') if p.is_file()
                  and not any(part in IGNORED for part in p.relative_to(root).parts)
                  and p.name not in {'.DS_Store', '.Rhistory', '.RData'}
                  and '__MACOSX' not in p.parts)


def scan(data, label, patterns):
    # Scan decoded data assets separately; random base64 characters are not text.
    encoded = re.compile(rb'data:[A-Za-z0-9.+/-]+;base64,[A-Za-z0-9+/=]+')
    for item in encoded.finditer(data):
        try:
            payload = base64.b64decode(item.group().split(b',', 1)[1], validate=True)
        except ValueError as exc:
            raise ValueError(f'Invalid embedded data asset: {label}') from exc
        scan(payload, label + ':decoded asset', patterns)
    text = encoded.sub(b'[embedded data asset]', data)
    require(not any(p.search(text) for p in patterns), f'Private path, credential or forbidden text: {label}')


def check_package(data, label, patterns, presentation=False):
    with zipfile.ZipFile(io.BytesIO(data)) as z:
        names = z.namelist()
        require(not any('notesSlides/' in n or 'notesMasters/' in n for n in names), f'Presenter notes: {label}')
        for n in names:
            payload = z.read(n)
            scan(payload, label + ':' + n, patterns)
            if n.endswith(('.xlsx', '.pptx', '.docx')):
                check_package(payload, label + ':' + n, patterns)
            if n.endswith('.rels'):
                rels = ET.fromstring(payload)
                require(not any('notesSlide' in x.get('Type', '') or 'notesMaster' in x.get('Type', '') for x in rels), f'Notes relationship: {label}')
            if n == 'docProps/core.xml':
                props = ET.fromstring(payload)
                require(not any(x.tag.rsplit('}', 1)[-1] in {'creator', 'lastModifiedBy'} and (x.text or '').strip() for x in props), f'Identifying document properties: {label}')
        if not presentation:
            return None
        pres = ET.fromstring(z.read('ppt/presentation.xml'))
        ids = pres.find(f'{{{P}}}sldIdLst')
        return len(ids)


def table_text(doc):
    return [[[' '.join(c.text_content().split()) for c in r.xpath('./th|./td')]
             for r in t.xpath('.//tr')] for t in doc.xpath('//table')]


def report_checks(path, patterns):
    raw = path.read_bytes()
    scan(raw, path.name, patterns)
    doc = html.fromstring(raw)
    ids = doc.xpath('//@id')
    require(len(ids) == len(set(ids)), f'Duplicate HTML anchors: {path.name}')
    for src in doc.xpath('//img/@src'):
        if src.startswith('data:') and ';base64,' in src:
            scan(base64.b64decode(src.split(',', 1)[1]), path.name + ':embedded image', patterns)
    return doc


R_CHECK = r'''
root<-commandArgs(TRUE)[1]
for(country in c('Ethiopia','Nigeria','DRC')) {
 folder<-file.path(root,paste0(country,'_analysis'),'revision_inputs')
 p<-readRDS(file.path(folder,'planning_point.rds'))
 d<-readRDS(file.path(folder,'planning_replicates.rds'))
 m<-readRDS(file.path(folder,'planning_metadata.rds'))
 stopifnot(length(d)==500L,identical(dim(p$risk),c(9L,5L,5L)))
 inspect<-function(x){
  if(is.environment(x)||is.function(x)||is.data.frame(x))stop('Non-aggregate object in shared inputs.')
  if(is.character(x))stopifnot(!any(grepl('/(Users|Volumes|home|private|tmp)/|file:/',x,ignore.case=TRUE)))
  if(is.list(x))invisible(lapply(x,inspect))
  at<-attributes(x);if(length(at))for(y in at)if(is.character(y))inspect(y)
 }
 for(x in c(list(p,m),d))inspect(x)
 for(x in c(list(p),d)){
  stopifnot(is.null(x$error),identical(dim(x$counts),c(9L,5L,5L)),identical(dim(x$risk),c(9L,5L,5L)),all(is.finite(x$counts)),all(is.finite(x$risk)),all(x$counts>=0),all(x$risk>=0))
  stopifnot(max(abs(x$counts-sweep(x$risk,2,x$stock[m$methods],'*')))<1e-6)
  stopifnot(all(apply(x$risk,c(1,2),sum)<=1+1e-8))
  for(pair in list(c(4,2),c(5,3),c(9,3)))stopifnot(all(x$counts[pair[1],,]<=x$counts[pair[2],,]+1e-7))
 }
 cat(country,': aggregate schema, 500 joint replicates, probability bounds and count identities pass.\n',sep='')
}
for(f in list.files(file.path(root,'Nigeria_analysis','Kano_Kaduna_Lagos'),pattern='[.]R$',full.names=TRUE))invisible(parse(f))
invisible(parse(file.path(root,'build_reports.R')))
'''


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--root', default='.', help='Repository root; no input locations are recorded.')
    ap.add_argument('--build-dir', help='Compare national outputs below this relative or supplied directory.')
    ap.add_argument('--rscript', default='Rscript')
    ap.add_argument('--skip-r', action='store_true', help='Structural checks only; aggregate RDS and syntax checks are skipped.')
    ap.add_argument('--forbidden-token', action='append', default=[], help='Additional text to reject; token values are not written to results.')
    ap.add_argument('--output', help='Optional relative JSON results file; no machine locations are recorded.')
    ap.add_argument('--skip-hashes', action='store_true', help='Skip the saved release checksum manifest while intentionally editing files.')
    ap.add_argument('--refresh-manifest', action='store_true', help='After a passing rebuild comparison, refresh release checksums and the root validation summary.')
    args = ap.parse_args()
    require(not args.refresh_manifest or (args.build_dir and not args.skip_r), 'Refreshing the release manifest requires --build-dir and R checks.')
    root = Path(args.root).resolve()
    patterns = PATTERNS + [re.compile(re.escape(t.encode()), re.I) for t in args.forbidden_token]
    files = shared_files(root)
    for path in files:
        rel = path.relative_to(root)
        require(not path.is_symlink(), f'Symbolic link in shared files: {rel}')
        require(path.suffix.lower() not in {'.dta', '.sav', '.rda', '.rdata', '.log'}, f'Restricted or working file: {rel}')
        if path.suffix.lower() == '.rds':
            require(path.parent.name == 'revision_inputs' and path.name in {'planning_point.rds', 'planning_replicates.rds', 'planning_metadata.rds'}, f'Unexpected R object: {rel}')
        if path.suffix in TEXT_SUFFIXES or path.name == '.gitignore':
            scan(path.read_bytes(), str(rel), patterns)
        if path.suffix == '.pptx':
            check_package(path.read_bytes(), str(rel), patterns, True)
        require(path.stat().st_size < 100_000_000, f'File exceeds normal repository upload limit: {rel}')
    if not args.skip_hashes and not args.refresh_manifest:
        manifest = json.loads((root / 'validation_summary.json').read_text())
        fingerprints = manifest.get('file_sha256', {})
        names = {p.relative_to(root).as_posix() for p in files if p.name != 'validation_summary.json' or p.parent != root}
        require(set(fingerprints) == names, 'Release file list differs from its checksum manifest.')
        for name, expected in fingerprints.items():
            require(hashlib.sha256((root / name).read_bytes()).hexdigest() == expected, f'Release checksum differs: {name}')
    results = {}
    for country, (report, pptx, script, slides, tables, baseline, outcome) in COUNTRIES.items():
        folder = root / (country + '_analysis')
        for name in [report, pptx, script, 'README.md', 'validation_summary.json']:
            require((folder / name).is_file(), f'Missing {country} file: {name}')
        doc = report_checks(folder / report, patterns)
        count = check_package((folder / pptx).read_bytes(), country + ':' + pptx, patterns, True)
        require(count == slides, f'Unexpected slide count: {country}')
        require(len(doc.xpath('//table')) == tables, f'Unexpected HTML table count: {country}')
        require(bool(doc.xpath('//*[@id="aft-modeled-transition-sensitivity"]')), f'Missing new sensitivity: {country}')
        data = dict(slides=count, html_tables=tables, reference_year=baseline, outcome_year=outcome, presenter_notes=0)
        if args.build_dir:
            build = Path(args.build_dir)
            if not build.is_absolute():
                build = root / build
            rebuilt = build / folder.name / 'output' / report
            require(rebuilt.is_file(), f'Missing rebuild: {country}')
            fresh = report_checks(rebuilt, patterns)
            require(table_text(doc) == table_text(fresh), f'Rebuilt table mismatch: {country}')
            require(doc.xpath('//img/@src') == fresh.xpath('//img/@src'), f'Rebuilt figure mismatch: {country}')
            require(doc.xpath('//section/@id') == fresh.xpath('//section/@id'), f'Rebuilt section mismatch: {country}')
            # Titles, subtitles and probability notes are part of the planning output.
            descriptions = lambda x: [' '.join(a.text_content().split()) for a in x.xpath('//article[contains(@class,"duration-slide") or contains(@class,"planning-table")]')]
            require(descriptions(doc) == descriptions(fresh), f'Rebuilt planning explanation mismatch: {country}')
            data['incremental_html_rebuild'] = 'tables, figures, sections and planning explanations match'
        results[country] = data
    state = root / 'Nigeria_analysis' / 'Kano_Kaduna_Lagos'
    state_doc = report_checks(state / 'Kano_Kaduna_Lagos_discontinuation_analysis.html', patterns)
    state_slides = check_package((state / 'Kano_Kaduna_Lagos_discontinuation.pptx').read_bytes(), 'three-state presentation', patterns, True)
    require(len(state_doc.xpath('//table')) == 61, 'Unexpected combined state report table count')
    state_tables = state_doc.xpath('//section[starts-with(@id,"kano-") or starts-with(@id,"kaduna-") or starts-with(@id,"lagos-")]//table')
    require(len(state_tables) == 60, 'Unexpected state display-table count')
    if not args.skip_r:
        require(shutil.which(args.rscript) is not None, 'Rscript is required; use --rscript or explicitly select --skip-r.')
        for country, info in COUNTRIES.items():
            p = root / (country + '_analysis') / info[2]
            child = subprocess.run([args.rscript, str(p), '--validate'], capture_output=True, text=True)
            require(child.returncode == 0, f'R module syntax failed: {country}')
        child = subprocess.run([args.rscript, '-e', R_CHECK, str(root)], capture_output=True, text=True)
        require(child.returncode == 0, 'Aggregate RDS validation failed; check the numerical inputs.')
        print(child.stdout.strip())
    result = dict(status='pass', countries=results, three_state_display_tables=60, three_state_html_tables=61, three_state_slides=state_slides,
                  aggregate_and_r_module_checks='skipped' if args.skip_r else 'pass',
                  shared_file_checks='pass', extra_forbidden_text_check=bool(args.forbidden_token),
                  file_count=len(files), full_raw_ir_to_entire_report_verified=False,
                  scope='Shared-file structure and content checks, aggregate planning identities, and optionally incremental HTML equality. No fresh statistical validation of unchanged chapters or forecast transportability.')
    if args.refresh_manifest:
        manifest_path = root / 'validation_summary.json'
        manifest = json.loads(manifest_path.read_text()) if manifest_path.exists() else {}
        manifest['updated'] = date.today().isoformat()
        manifest['latest_repository_checks'] = result
        manifest['file_sha256'] = {p.relative_to(root).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
                                   for p in files if p != manifest_path}
        manifest_path.write_text(json.dumps(manifest, indent=2) + '\n')
    if args.output:
        output = Path(args.output)
        if not output.is_absolute():
            output = root / output
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, zipfile.BadZipFile, ET.ParseError) as exc:
        print('Validation failed: ' + str(exc), file=sys.stderr)
        sys.exit(1)
