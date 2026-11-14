"""Render a national reason-specific timing preview from aggregate estimates."""
import json
import sys
import math
from html import escape
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text())
rows = sorted(data['rows'], key=lambda r: r['probability'][-1], reverse=True)
parts = ['<svg xmlns="http://www.w3.org/2000/svg" width="1360" height="760" viewBox="0 0 1360 760">',
 '<rect width="1360" height="760" fill="white"/>',
 '<style>text{font-family:Arial,sans-serif;fill:#153F5B}.title{font-family:Georgia,serif;font-weight:bold}.label{font-size:22px}.small{font-size:18px}</style>',
 '<text x="48" y="57" class="title" font-size="32">When does actionable discontinuation accumulate?</text>',
 f'<text x="48" y="92" font-size="21">{escape(data["country"])} · national · modern methods excluding EC · DHS {escape(data["survey"])}</text>']
colors = ['#DA9A25','#B6DDDE','#69B7B8','#108B8D']
legends = ['By month 3','Added in months 4–6','Added in months 7–9','Added in months 10–12']
for i,(c,label) in enumerate(zip(colors,legends)):
 x=48+i*320
 parts += [f'<rect x="{x}" y="126" width="18" height="18" fill="{c}"/>',f'<text x="{x+27}" y="142" class="small">{label}</text>']
axis_max = float(sys.argv[3]) if len(sys.argv) > 3 else max(6, math.ceil(max(r['probability'][-1] for r in rows)))
assert axis_max >= max(r['probability'][-1] for r in rows)
x0=395; scale=660/axis_max
parts += ['<text x="1165" y="190" font-size="19" text-anchor="middle">Share of first-year</text>',
 '<text x="1165" y="215" font-size="19" text-anchor="middle">risk by month 3</text>']
step = 1 if axis_max <= 8 else 2
for t in range(0, int(axis_max)+1, step):
 x=x0+t*scale
 parts += [f'<line x1="{x}" y1="230" x2="{x}" y2="567" stroke="#E3E9EC"/>',f'<text x="{x}" y="599" text-anchor="middle" font-size="19">{t}</text>']
for i,r in enumerate(rows):
 y=258+i*67; vals=r['probability']; previous=0
 parts.append(f'<text x="373" y="{y+7}" text-anchor="end" class="label">{escape(r["reason"])}</text>')
 for val,c in zip(vals,colors):
  parts.append(f'<rect x="{x0+previous*scale:.3f}" y="{y-18}" width="{(val-previous)*scale:.3f}" height="35" fill="{c}"/>')
  previous=val
 parts += [f'<text x="{x0+previous*scale+10:.3f}" y="{y+7}" font-size="22">{previous:.2f}%</text>',
 f'<text x="1165" y="{y+7}" text-anchor="middle" font-size="24">{r["share_by_three"]:.1f}%</text>']
parts += ['<text x="725" y="637" font-size="21" text-anchor="middle">12-month cumulative discontinuation probability (%)</text>',
 '<text x="48" y="687" font-size="18">Full bar = first-year risk for that reason. Gold = the portion accumulated in the first 3 months.</text>',
 '<text x="48" y="717" font-size="18">Weighted competing-risk point estimates; bars are not reason shares. Partner/spousal disapproval is excluded.</text>',
 '</svg>']
Path(sys.argv[2]).write_text('\n'.join(parts))
