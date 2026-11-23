#!/usr/bin/env python3
"""Test rendering contracts with synthetic aggregate tables; no survey data needed."""
import ast
import csv
import runpy
import tempfile
from pathlib import Path
from lxml import html, etree

repo = Path(__file__).resolve().parents[1]
source = runpy.run_path(str(repo / 'report_tools.py'))['SOURCES']['tools/finalize_national_html.py']
function = next(node for node in ast.parse(source).body
                if isinstance(node, ast.FunctionDef) and node.name == 'preserve_drc_table_precision')
namespace = {'csv': csv}
exec(compile(ast.Module(body=[function], type_ignores=[]), '<display function>', 'exec'), namespace)

with tempfile.TemporaryDirectory(prefix='report-test-') as directory:
    supporting = Path(directory)
    specifications = [
        ('selected-reason-regional-analysis', 'drc_selected_reason_adjusted_pairwise.csv',
         ['stage', 'province_1', 'province_2', 'difference_pp', 'ci_low', 'ci_high',
          'p_value', 'small_cell', 'p_holm', 'significant_05']),
        ('updated-subnational-heterogeneity-analyses', 'drc_actionable_province_model_odds_ratios.csv',
         ['model', 'outcome', 'covariate', 'odds_ratio', 'ci_low', 'ci_high',
          'p_value', 'survey_se', 'design_df']),
        ('updated-subnational-heterogeneity-analyses', 'drc_actionable_adjusted_pairwise.csv',
         ['stage', 'province_1', 'province_2', 'difference_pp', 'ci_low', 'ci_high',
          'p_value', 'design_df', 'small_cell', 'p_holm', 'significant_05', 'significant_10']),
    ]
    document = html.fromstring('<html><body><section id="selected-reason-regional-analysis"></section>'
                              '<section id="updated-subnational-heterogeneity-analyses"></section></body></html>')
    for section, filename, headers in specifications:
        record = {key: 'example' for key in headers}
        record.update({key: '-11.149' for key in headers
                       if key in {'difference_pp', 'odds_ratio', 'ci_low', 'ci_high', 'survey_se'}})
        record.update({key: '0.0004' for key in headers if key in {'p_value', 'p_holm'}})
        record.update({key: 'TRUE' for key in headers if key in {'small_cell', 'significant_05', 'significant_10'}})
        if 'design_df' in record:
            record['design_df'] = '727'
        with (supporting / filename).open('w', newline='') as stream:
            writer = csv.DictWriter(stream, fieldnames=headers)
            writer.writeheader()
            writer.writerow(record)
        section_node = document.xpath('//section[@id=$id]', id=section)[0]
        table = etree.SubElement(section_node, 'table')
        head = html.fragment_fromstring('<tr>' + ''.join(f'<th>{key}</th>' for key in headers) + '</tr>')
        table.append(head)
        row = html.fragment_fromstring('<tr>' + ''.join(f'<td>{record[key]}</td>' for key in headers) + '</tr>')
        table.append(row)
    namespace['preserve_drc_table_precision'](document, supporting)
    text = document.text_content()
    assert '-11.1' in text and '-11.2' not in text, 'Must round raw CSV values, not rounded HTML.'
    assert 'True' in text and 'TRUE' not in text
    assert '727' in text
    document.xpath('//table')[0].xpath('.//tr')[1][0].text = 'different row'
    try:
        namespace['preserve_drc_table_precision'](document, supporting)
    except ValueError:
        pass
    else:
        raise AssertionError('A table with mismatched row identifiers must be rejected.')
print('Reporting checks passed: full-precision rounding, boolean labels and row identity.')
