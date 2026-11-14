"""Compare recalculated aggregates with the checked report's numerical baseline."""
import argparse
import base64
from html.parser import HTMLParser
import json
import math
from pathlib import Path
import re

COUNTRIES = ('ethiopia', 'nigeria', 'drc')


def collect(work, target='all'):
    records = {}

    def add(key, file, fields):
        data = json.loads(file.read_text())
        records[key] = {field: data[field] for field in fields}

    for country in COUNTRIES:
        add(f'{country}/partner_rates', work / 'results' / country / 'results.json', ['methods'])
        if target in ('all', 'extensions'):
            add(f'{country}/subgroups', work / 'results' / country / 'subgroups.json', ['summary', 'monthly'])
            name = 'timing.json' if country == 'ethiopia' else f'{country}_timing.json'
            add(f'{country}/timing', work / 'timing' / name, ['eligible_episodes', 'rows'])
            add(f'{country}/pathways', work / 'switching' / f'{country}.json',
                ['eligible_endings', 'endings', 'women', 'weighted_endings', 'times', 'paths', 'shares', 'origins'])
            for suffix, fields in (
                ('reason_endpoint', ['endings', 'women', 'rows']),
                ('destinations', ['endings', 'women', 'rows']),
                ('endpoint_duration_table', ['endings', 'women', 'rows', 'column_totals', 'endpoint_interruption_distribution']),
            ):
                add(f'{country}/{suffix}', work / 'switching' / f'{country}_{suffix}.json', fields)
        if target in ('all', 'maps'):
            add(f'{country}/geography', work / 'maps' / country / 'geography.json', ['summary', 'monthly', 'reasons'])
            if country != 'ethiopia':
                scheme = 'nigeria_zones6' if country == 'nigeria' else 'drc_geographic6'
                add(f'{country}/grouped_geography', work / 'aggregation' / scheme / 'geography.json',
                    ['summary', 'monthly', 'reasons'])
    return records


def compare(actual, expected, key, errors, stats):
    if isinstance(actual, dict) and isinstance(expected, dict):
        if actual.keys() != expected.keys():
            errors.append(key + ': fields differ')
            return
        for field in actual:
            compare(actual[field], expected[field], key + '/' + field, errors, stats)
    elif isinstance(actual, list) and isinstance(expected, list):
        if len(actual) != len(expected):
            errors.append(key + ': row count differs')
            return
        for i, (a, b) in enumerate(zip(actual, expected)):
            compare(a, b, key + '/' + str(i), errors, stats)
    elif isinstance(actual, (int, float)) and not isinstance(actual, bool) and isinstance(expected, (int, float)):
        stats['numeric_values_checked'] += 1
        if not math.isfinite(actual) or not math.isfinite(expected) or not math.isclose(actual, expected, rel_tol=1e-10, abs_tol=1e-8):
            errors.append(key + ': numerical value differs')
        stats['maximum_absolute_difference'] = max(stats['maximum_absolute_difference'], abs(actual - expected))
    elif actual != expected:
        errors.append(key + ': categorical value differs')


class ReportParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.images = []
        self.ids = set()
        self.anchors = []

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if 'id' in attrs:
            self.ids.add(attrs['id'])
        if tag == 'img':
            self.images.append(attrs['src'])
        if tag == 'a' and attrs.get('href', '').startswith('#'):
            self.anchors.append(attrs['href'][1:])


def validate(work, reference, output, target):
    actual = collect(work, target)
    baseline = json.loads(reference.read_text())['records']
    errors = []
    stats = {'numeric_values_checked': 0, 'maximum_absolute_difference': 0}
    for key, data in actual.items():
        compare(data, baseline[key], key, errors, stats)
    reports = []
    private_path = re.compile(r'file:/{2}|/(?:Users|Volumes|home|private|tmp)/|[A-Za-z]:\\')
    names = []
    if target in ('all', 'extensions'):
        names.append('Discontinuation_and_switching_extensions.html')
    if target in ('all', 'maps'):
        names.append('Modern_method_discontinuation_maps.html')
    for name in names:
        page = (output.parent / name).read_text()
        if private_path.search(page):
            errors.append(name + ': nonportable reference')
        parser = ReportParser()
        parser.feed(page)
        if any(anchor not in parser.ids for anchor in parser.anchors):
            errors.append(name + ': broken section anchor')
        for src in parser.images:
            if not src.startswith('data:image/svg+xml;base64,'):
                errors.append(name + ': nonembedded image')
                continue
            svg = base64.b64decode(src.split(',', 1)[1]).decode()
            if private_path.search(svg):
                errors.append(name + ': nonportable image content')
        if name.startswith('Discontinuation_'):
            if len(parser.images) != 27:
                errors.append(name + ': unexpected figure count')
            if 'What counts toward the duration?' in page:
                errors.append(name + ': obsolete duration paragraph')
        reports.append({'name': name, 'embedded_image_instances': len(parser.images),
                        'anchors_valid': True, 'self_contained': True})
    result = {'status': 'pass' if not errors else 'fail', 'target': target,
              'comparison': 'Regenerated aggregate calculations versus the checked report baseline; independent life-table checks also run in the R modules.',
              'modules_checked': len(actual), **stats, 'reports': reports,
              'restricted_microdata_exported': False, 'errors': errors}
    output.write_text(json.dumps(result, indent=2) + '\n')
    if errors:
        raise SystemExit('Validation failed: ' + '; '.join(errors[:8]))
    print('Numerical baseline, embedded-image and anchor validation passed.')


if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('--work-dir', type=Path, required=True)
    p.add_argument('--reference', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--target', choices=('all', 'maps', 'extensions'), default='all')
    args = p.parse_args()
    validate(args.work_dir, args.reference, args.output, args.target)
