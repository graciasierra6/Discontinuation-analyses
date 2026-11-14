"""Render an origin-to-first-modern-destination matrix from aggregate results."""
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
left=330;cw=225;rowh=66;yrows=[310,395,480,565,650,735]
def blend(start,end,weight):
 x=[int(start[i:i+2],16) for i in (1,3,5)];y=[int(end[i:i+2],16) for i in (1,3,5)]
 return '#'+''.join(f'{round(a+(b-a)*weight):02X}' for a,b in zip(x,y))
header_colors=['#108B8D','#153F5B','#DA9A25','#E45A4B','#7C8797','#526777']
heads=[['Injectables'],['Implants'],['Pill'],['IUD'],['Other modern','including EC'],['No modern return','within 12 months']]
s=['<svg xmlns="http://www.w3.org/2000/svg" width="1800" height="1040" viewBox="0 0 1800 1040" role="img">',
 f'<title>{d["country"]}: original method and first modern method recorded after actionable discontinuation</title>',
 '<rect width="1800" height="1040" fill="white"/>',
 '<style>text{font-family:Arial,sans-serif;fill:#153F5B}.title{font-family:Georgia,serif;font-weight:bold}</style>',
 '<text x="48" y="54" class="title" font-size="34">First modern method used within 12 months after discontinuation</text>',
 f'<text x="48" y="96" font-size="23">{escape(d["country"])} · DHS {escape(d["survey"])} · {d["endings"]:,} endings from {d["women"]:,} women · Each row sums to 100%</text>',
 '<text x="48" y="137" font-size="21">Potentially actionable endings only · First recorded destination, even if that method is later discontinued.</text>',
 '<text x="48" y="221" font-size="23">Method discontinued</text>',
 '<text x="892" y="184" font-size="22" text-anchor="middle">FIRST MODERN METHOD RECORDED</text>']
for j,(lines,col) in enumerate(zip(heads,header_colors)):
 center=left+(j+.5)*cw
 s.append(f'<line x1="{left+j*cw+8}" x2="{left+(j+1)*cw-8}" y1="205" y2="205" stroke="{col}" stroke-width="5"/>')
 start=235 if len(lines)==1 else 226
 for k,line in enumerate(lines):s.append(f'<text x="{center}" y="{start+25*k}" text-anchor="middle" font-size="22">{escape(line)}</text>')
for i,(row,y) in enumerate(zip(d['rows'],yrows)):
 assert abs(sum(c['share'] for c in row['cells'])-100)<1e-8
 label=row['origin'];flag='*' if i>0 and row['endings']<100 else ''
 lines=['All actionable','endings'] if i==0 else [label]
 start=y-(len(lines)-1)*12-5
 for k,line in enumerate(lines):s.append(f'<text x="48" y="{start+24*k}" font-size="23"'+(' font-weight="bold"' if i==0 else '')+f'>{escape(line)}{flag if k==len(lines)-1 else ""}</text>')
 s.append(f'<text x="48" y="{start+24*len(lines)}" font-size="18" style="fill:#526777">N = {row["endings"]:,} endings</text>')
 for j,cell in enumerate(row['cells']):
  x=left+j*cw;value=cell['share'];w=min(value/60,1)
  fill=blend('#FFF8E8','#E8BA55',w) if i==0 else blend('#F2F7F7','#A9DCDD',w)
  if j==5 and i>0:fill=blend('#F3F5F7','#BCC7D0',w)
  outline=i>0 and row['origin']==cell['destination']
  border='#DA9A25' if outline else 'white'
  stroke=3 if outline else 2
  s.append(f'<rect x="{x+3}" y="{y-rowh/2}" width="{cw-6}" height="{rowh}" fill="{fill}" stroke="{border}" stroke-width="{stroke}"/>')
  sparse='†' if 0<cell['endings']<5 else ''
  s.append(f'<text x="{x+cw/2}" y="{y+9}" font-size="25" text-anchor="middle">{value:.1f}%{sparse}</text>')
s.extend(['<text x="48" y="839" font-size="19">Each row includes all eligible actionable endings of that original method, including those without a modern return.</text>',
 '<text x="48" y="872" font-size="19">Outlined cells indicate the same method group again. Other-to-other can involve different specific methods within that group.</text>',
 '<text x="48" y="905" font-size="19">The first modern record may follow a gap or pregnancy. It does not establish continuous use or modern use at month 12.</text>',
 '<text x="48" y="938" font-size="19">† Fewer than 5 observed endings in the cell. * Fewer than 100 endings in the original-method row; interpret descriptively with caution.</text>',
 '<text x="48" y="971" font-size="19">Percentages use DHS weights; N is unweighted. Original EC excluded; subsequent EC is in Other modern. Darker cells show larger shares.</text>',
 '</svg>'])
svg='\n'.join(s)
base=f'{d["country"]}_origin_to_first_modern_destination'
(a.output_dir/f'{base}.svg').write_text(svg)
encoded=base64.b64encode(svg.encode()).decode()
rows=[]
for row in d['rows']:
 for cell in row['cells']:
  ci=cell.get('ci_status','Not estimated: no observed endings') if cell['ci_low'] is None else f'{cell["ci_low"]:.1f}–{cell["ci_high"]:.1f}%'
  rows.append('<tr><th>'+escape(row['origin'])+'</th><td>'+escape(cell['destination'])+'</td>'+f'<td>{cell["share"]:.1f}%</td><td>{ci}</td><td>{cell["endings"]}</td></tr>')
html='''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Original method and first modern destination</title><style>body{font:18px/1.5 Arial,sans-serif;color:#153F5B;margin:24px}main{max-width:1800px;margin:auto}img{width:100%;height:auto;display:block}details{overflow:auto}table{border-collapse:collapse;width:100%;font-size:16px}th,td{padding:12px;border-bottom:1px solid #DCE5EB;text-align:right}th:first-child,td:nth-child(2){text-align:left}</style></head><body><main>'''+f'<img src="data:image/svg+xml;base64,{encoded}" alt="Original discontinued method and first modern method recorded within twelve months; every row sums to 100 percent."/><p>All eligible actionable endings are retained, including those followed by no modern return. The first recorded modern destination can occur after a pregnancy-related period. This table describes observed adoption, not preference, the method used at month twelve, or an effect of services.</p><p>Confidence intervals resample the full survey cluster frame within strata and keep each woman and all her episodes together. Sparse cells require caution; zero observed cells do not establish a zero population probability.</p><details><summary>Numerical estimates, confidence intervals and counts</summary><table><thead><tr><th>Original method</th><th>First modern destination</th><th>Weighted share</th><th>95% CI</th><th>Observed endings</th></tr></thead><tbody>'+''.join(rows)+'</tbody></table></details></main></body></html>'
(a.output_dir/f'{base}.html').write_text(html)
print('Built a first-destination matrix with row denominators and sparse-cell flags.')
