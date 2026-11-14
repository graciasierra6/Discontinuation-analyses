"""Draw within-reason endpoint and continuity shares from aggregate estimates."""
import argparse
import base64
import json
from html import escape
from pathlib import Path

p=argparse.ArgumentParser()
p.add_argument('--input',required=True,type=Path)
p.add_argument('--output-dir',required=True,type=Path)
a=p.parse_args();d=json.loads(a.input.read_text());a.output_dir.mkdir(parents=True,exist_ok=True)
assert all(d['validation'].values())
colors=['#108B8D','#DA9A25','#85909D','#D45A49','#8D73A8']
left=445;bar_width=1000
yrows=[250,350,450,550,650,760]
legend=[['Modern method recorded','in all 12 months'],['Modern use at month 12','after an interruption'],
 ['No method recorded','at month 12'],['Pregnancy-related record','at month 12'],['Traditional method','at month 12']]
svg=['<svg xmlns="http://www.w3.org/2000/svg" width="1800" height="1100" viewBox="0 0 1800 1100" role="img">',
 f'<title>{d["country"]}: modern-use continuity and month-twelve states by actionable discontinuation reason</title>',
 '<rect width="1800" height="1100" fill="white"/>',
 '<style>text{font-family:Arial,sans-serif;fill:#153F5B}.title{font-family:Georgia,serif;font-weight:bold}</style>',
 '<text x="48" y="54" class="title" font-size="35">Modern use a year after stopping, by reported reason</text>',
 f'<text x="48" y="94" font-size="23">{escape(d["country"])} · DHS {escape(d["survey"])} · Same {d["endings"]:,} actionable endings as the alluvial · Each row sums to 100%</text>']
for i,(lines,c) in enumerate(zip(legend,colors)):
 x=48+345*i
 svg.append(f'<rect x="{x}" y="124" width="18" height="18" fill="{c}"/>')
 for j,line in enumerate(lines):svg.append(f'<text x="{x+27}" y="{141+j*25}" font-size="20">{escape(line)}</text>')
svg.extend(['<text x="1485" y="193" font-size="20" text-anchor="middle">Traditional</text>',
 '<text x="1485" y="218" font-size="20" text-anchor="middle">use</text>',
 '<text x="1650" y="193" font-size="21" text-anchor="middle">Modern use</text>',
 '<text x="1650" y="218" font-size="21" text-anchor="middle">at month 12</text>',
 '<rect x="35" y="219" width="1730" height="67" fill="#FFF5DC"/>'])
for tick in range(0,101,20):
 x=left+bar_width*tick/100
 svg.append(f'<line x1="{x}" y1="225" x2="{x}" y2="792" stroke="#E3E9EC"/>')
 svg.append(f'<text x="{x}" y="835" font-size="20" text-anchor="middle">{tick}%</text>')
for i,(r,y) in enumerate(zip(d['rows'],yrows)):
 assert abs(sum(c['share'] for c in r['cells'])-100)<1e-8
 reason=r['reason'];label_lines=['Wanted a more','effective method'] if reason=='Wanted a more effective method' else [reason]
 start=y-(len(label_lines)-1)*13-2
 for k,line in enumerate(label_lines):svg.append(f'<text x="48" y="{start+26*k}" font-size="23"'+(' font-weight="bold"' if i==0 else '')+f'>{escape(line)}</text>')
 count_y=start+26*len(label_lines)
 svg.append(f'<text x="48" y="{count_y}" font-size="18" style="fill:#526777">N = {r["endings"]:,} observed endings</text>')
 cursor=left
 for j,(cell,c) in enumerate(zip(r['cells'],colors)):
  v=cell['share'];w=bar_width*v/100;flag='†' if cell['endings']<5 else ''
  svg.append(f'<rect x="{cursor:.5f}" y="{y-21}" width="{w:.5f}" height="42" fill="{c}"/>')
  if j==4:
   svg.append(f'<text x="1485" y="{y+8}" text-anchor="middle" font-size="22" style="fill:{c}">{v:.1f}%{flag}</text>')
  elif w>=60:
   col='#153F5B' if j==1 else 'white'
   svg.append(f'<text x="{cursor+w/2:.5f}" y="{y+8}" text-anchor="middle" font-size="22" style="fill:{col}">{v:.1f}%{flag}</text>')
  else:
   center=cursor+w/2
   svg.append(f'<path d="M{center:.5f},{y-21} V{y-33}" fill="none" stroke="{c}" stroke-width="1.5"/>')
   svg.append(f'<text x="{center:.5f}" y="{y-42}" text-anchor="middle" font-size="20" style="fill:{c}">{v:.1f}%{flag}</text>')
  cursor+=w
 assert abs(cursor-left-bar_width)<1e-6
 svg.append(f'<text x="1650" y="{y+8}" text-anchor="middle" font-size="25"'+(' font-weight="bold"' if i==0 else '')+f'>{r["modern12"]:.1f}%</text>')
svg.extend(['<line x1="48" y1="704" x2="1750" y2="704" stroke="#DCE5EB"/>',
 '<text x="945" y="879" text-anchor="middle" font-size="22">Weighted percentage of eligible endings for the reason named in that row</text>',
 '<text x="48" y="944" font-size="19">Denominators differ by row: for example, the bleeding row includes only bleeding-related endings with complete follow-up.</text>',
 '<text x="48" y="977" font-size="19">Teal plus gold gives modern use at month 12. Earlier months outside modern use can include pregnancy-related records or traditional use.</text>',
 '<text x="48" y="1010" font-size="19">Method failure involves pregnancy at the original ending and describes a distinct pathway. † Fewer than 5 observed endings in that segment.</text>',
 '<text x="48" y="1043" font-size="19">Original EC excluded; subsequent EC counts as modern. N is unweighted. Values are rounded; no tests of differences are shown.</text>',
 '</svg>'])
result='\n'.join(svg)
base=f'{d["country"]}_continuity_by_actionable_reason'
(a.output_dir/f'{base}.svg').write_text(result)
encoded=base64.b64encode(result.encode()).decode()
rows=[]
for r in d['rows']:
 for c in r['cells']:
  interval='Not estimated: no observed endings' if c['ci_low'] is None else f'{c["ci_low"]:.1f}–{c["ci_high"]:.1f}%'
  rows.append('<tr><th>'+escape(r['reason'])+'</th><td>'+escape(c['outcome'])+'</td>'+f'<td>{c["share"]:.1f}%</td><td>{interval}</td><td>{c["endings"]}</td></tr>')
page='''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Continuity by actionable reason</title><style>body{font:18px/1.5 Arial,sans-serif;color:#153F5B;margin:24px}main{max-width:1800px;margin:auto}img{width:100%;height:auto;display:block}details{overflow:auto}table{border-collapse:collapse;width:100%;font-size:16px}th,td{padding:12px;border-bottom:1px solid #DCE5EB;text-align:right}th:first-child,td:nth-child(2){text-align:left}</style></head><body><main>'''+f'<img src="data:image/svg+xml;base64,{encoded}" alt="{escape(d["country"])}: outcome composition within each actionable ending reason. Detailed numerical estimates follow."/><p>Each reason-specific row uses all eligible endings for that reason. Outcomes are not discontinuation rates. Weights determine the shares; full-frame cluster resampling within survey strata keeps all episodes from each woman together for confidence intervals. These descriptive associations do not establish which intervention would change subsequent use.</p><details><summary>Numerical estimates and confidence intervals</summary><table><thead><tr><th>Reported reason</th><th>Outcome</th><th>Weighted share</th><th>95% CI</th><th>Observed endings</th></tr></thead><tbody>'+''.join(rows)+'</tbody></table></details></main></body></html>'
(a.output_dir/f'{base}.html').write_text(page)
print('Rendered reason-specific continuity bars; all row percentages and the overall reference reconcile.')
