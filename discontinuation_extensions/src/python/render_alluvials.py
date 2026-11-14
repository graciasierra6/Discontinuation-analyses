"""Draw linked national snapshots from aggregate, checked episode pathways."""
import argparse
import base64
import json
from html import escape
from pathlib import Path

p=argparse.ArgumentParser()
p.add_argument('--aggregate-dir',required=True,type=Path)
p.add_argument('--output-dir',required=True,type=Path)
a=p.parse_args()
a.output_dir.mkdir(parents=True,exist_ok=True)
states=['Modern method','No method','Pregnancy/birth/termination','Traditional method','Other/unknown']
methods=['Injectables','Implants','Pill','IUD','Other modern']
colors={'Modern method':'#108B8D','No method':'#85909D','Pregnancy/birth/termination':'#D45A49','Traditional method':'#8D73A8','Other/unknown':'#BBC2CA',
 'Injectables':'#108B8D','Implants':'#153F5B','Pill':'#DA9A25','IUD':'#E45A4B','Other modern':'#7C8797'}
rank={s:i for i,s in enumerate(states)}
method_rank={s:i for i,s in enumerate(methods)}
html_figures=[]
for country in ['Ethiopia','DRC','Nigeria']:
    data=json.loads((a.aggregate_dir/(country.lower()+'.json')).read_text())
    paths=sorted(data['paths'],key=lambda r:(method_rank[r['origin']],)+tuple(rank[r[f'month{t}']] for t in data['times']))
    active=[s for s in states if any(r['state']==s for r in data['shares'])]
    stages=['origin']+[f'month{t}' for t in data['times']]
    labels=['Method discontinued']+[f'{t} month{"s" if t>1 else ""} after ending' for t in data['times']]
    origin_active=[s for s in methods if any(r['method']==s for r in data['origins'])]
    node_x=[80,500,920,1340,1760]
    node_width=240
    top=220
    gap=22
    scale=5.2
    positions=[]
    node_positions=[]
    for stage in stages:
        groups=origin_active if stage=='origin' else active
        shares={r['method']:r['share'] for r in data['origins']} if stage=='origin' else {r['state']:r['share'] for r in data['shares'] if r['month']==int(stage[5:])}
        pos={};cursor=top
        for s in groups:
            value=shares.get(s,0)
            pos[s]=(cursor,cursor+value*scale,value)
            cursor+=value*scale+gap
        node_positions.append(pos)
        slots={};cursor={s:pos[s][0] for s in groups}
        for i,r in enumerate(paths):
            s=r[stage];slots[i]=(cursor[s],cursor[s]+r['share']*scale)
            cursor[s]+=r['share']*scale
        assert all(abs(cursor[s]-pos[s][1])<1e-7 for s in groups)
        positions.append(slots)
    svg=['<svg xmlns="http://www.w3.org/2000/svg" width="2100" height="1120" viewBox="0 0 2100 1120" role="img">',
      f'<title>{country}: monthly states after actionable modern-method endings</title>',
      '<rect width="2100" height="1120" fill="white"/>',
      '<style>text{font-family:Arial,sans-serif;fill:#153F5B}.title{font-family:Georgia,serif;font-weight:bold}.node{fill:white;font-size:23px}.small{font-size:19px}</style>',
      '<text x="48" y="56" class="title" font-size="36">The year after an actionable modern-method ending</text>',
      f'<text x="48" y="98" font-size="25">{country} · DHS {data["survey"]} · National · {data["endings"]:,} endings from {data["women"]:,} women</text>',
      '<text x="48" y="135" font-size="21">Same endings followed at months 1, 3, 6 and 12 · Percentages within each snapshot sum to 100%</text>']
    for stage in range(4):
        x0=node_x[stage]+node_width;x1=node_x[stage+1];mid=(x0+x1)/2
        for i,r in enumerate(paths):
            y0,y1=positions[stage][i];z0,z1=positions[stage+1][i]
            origin=r[stages[stage]]
            desc='Original method: '+r['origin']+'; '+'; '.join(f'month {t}: {r[f"month{t}"]}' for t in data['times'])
            curve=f'M{x0},{y0:.5f} C{mid},{y0:.5f} {mid},{z0:.5f} {x1},{z0:.5f} L{x1},{z1:.5f} C{mid},{z1:.5f} {mid},{y1:.5f} {x0},{y1:.5f} Z'
            svg.append(f'<path d="{curve}" fill="{colors[origin]}" fill-opacity="0.36"><title>{escape(desc)}; {r["share"]:.2f}% of endings</title></path>')
    for j,stage in enumerate(stages):
        x=node_x[j];center=x+node_width/2
        svg.append(f'<text x="{center}" y="192" text-anchor="middle" font-size="23">{labels[j]}</text>')
        for s in node_positions[j]:
            lo,hi,v=node_positions[j][s]
            if v==0:continue
            svg.append(f'<rect x="{x}" y="{lo:.5f}" width="{node_width}" height="{hi-lo:.5f}" fill="{colors[s]}"/>')
            if hi-lo>=65 or (stage=='origin' and hi-lo>=55):
                lines=['Pregnancy/birth/','termination',f'{v:.1f}%'] if s=='Pregnancy/birth/termination' else [s,f'{v:.1f}%']
                step=22 if s=='Pregnancy/birth/termination' else 26
                start=(lo+hi)/2-(len(lines)-1)*step/2+7
                style=' style="font-size:20px"' if s=='Pregnancy/birth/termination' else ''
                for k,label in enumerate(lines):svg.append(f'<text x="{center}" y="{start+step*k:.4f}" class="node" text-anchor="middle"{style}>{escape(label)}</text>')
            elif s=='Modern method' and hi-lo>=25:
                svg.append(f'<text x="{center}" y="{(lo+hi)/2+7:.4f}" text-anchor="middle" font-size="19" style="fill:white">Modern method {v:.1f}%</text>')
            elif stage=='origin':
                if s=='IUD':
                    middle=(lo+hi)/2
                    svg.append(f'<path d="M{x},{middle:.4f} H{x-14}" stroke="{colors[s]}" fill="none" stroke-width="1.5"/>')
                    svg.append(f'<text x="{x-40}" y="{middle-4:.4f}" text-anchor="middle" font-size="20" style="fill:{colors[s]}">IUD</text>')
                    svg.append(f'<text x="{x-40}" y="{middle+20:.4f}" text-anchor="middle" font-size="20" style="fill:{colors[s]}">{v:.1f}%</text>')
                else:
                    label_y=920
                    svg.append(f'<path d="M{center},{hi:.4f} V{label_y-23}" stroke="{colors[s]}" fill="none" stroke-width="1.5"/>')
                    svg.append(f'<text x="{center}" y="{label_y}" text-anchor="middle" font-size="21" style="fill:{colors[s]}">{escape(s)} {v:.1f}%</text>')
            else:
                assert s in ['Traditional method','Other/unknown'], 'Use a larger label area for a small main state.'
                label_y=850 if s=='Traditional method' else 892
                svg.append(f'<path d="M{center},{hi:.4f} V{label_y-24}" stroke="{colors[s]}" fill="none" stroke-width="1.5"/>')
                svg.append(f'<text x="{center}" y="{label_y}" text-anchor="middle" font-size="21" style="fill:{colors[s]}">{escape(s)} {v:.1f}%</text>')
    svg.extend([
      '<text x="48" y="1000" class="small">First column: method recorded in the last month of use. Actionable endings only; original EC excluded.</text>',
      '<text x="48" y="1030" class="small">Other modern includes condoms, sterilization, LAM, SDM and other modern methods.</text>',
      '</svg>'])
    result='\n'.join(svg)
    (a.output_dir/f'{country}_actionable_post_discontinuation_alluvial.svg').write_text(result)
    encoded=base64.b64encode(result.encode()).decode()
    rows=[]
    for s in active:
        vals=[node_positions[j][s][2] for j in range(1,5)]
        rows.append('<tr><th scope="row">'+escape(s)+'</th>'+''.join(f'<td>{v:.1f}%</td>' for v in vals)+'</tr>')
    origin_table='<table><thead><tr><th>Method discontinued</th><th>Share of actionable endings</th></tr></thead><tbody>'+''.join(f'<tr><th scope="row">{escape(s)}</th><td>{node_positions[0][s][2]:.1f}%</td></tr>' for s in origin_active)+'</tbody></table>'
    html_figures.append(f'<section id="{country.lower()}"><h2>{country}</h2><img src="data:image/svg+xml;base64,{encoded}" alt="{country}: original discontinued method linked to subsequent weighted states; tables below give all percentages."/><details><summary>View numerical shares</summary>'+origin_table+'<table><thead><tr><th>State</th>'+''.join(f'<th>{t} month{"s" if t>1 else ""}</th>' for t in data['times'])+'</tr></thead><tbody>'+''.join(rows)+'</tbody></table></details></section>')
page='''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>National actionable discontinuation pathways</title><style>body{font:18px/1.5 Arial,sans-serif;color:#153F5B;margin:0;background:#F5F7F9}nav{padding:16px 5vw;background:white;position:sticky;top:0;border-bottom:1px solid #DCE5EB}nav a{margin-right:25px;color:#153F5B}main{max-width:1700px;margin:auto;padding:22px 3vw}h1,h2{font-family:Georgia,serif}section{background:white;padding:20px;margin:25px 0;scroll-margin-top:70px}img{display:block;width:100%;height:auto}table{border-collapse:collapse;width:100%;font-variant-numeric:tabular-nums}td,th{padding:12px;border-bottom:1px solid #DCE5EB;text-align:right}th:first-child{text-align:left}summary{cursor:pointer}details{overflow:auto}</style></head><body><nav><a href="#ethiopia">Ethiopia</a><a href="#drc">DRC</a><a href="#nigeria">Nigeria</a></nav><main><h1>What follows an actionable modern-method ending?</h1><p>National descriptive previews use the same definitions and complete-follow-up rule in all three countries. Each ending remains linked to the same woman’s subsequent calendar records.</p>'''+''.join(html_figures)+'</main></body></html>'
(a.output_dir/'Actionable_modern_method_discontinuation_alluvials.html').write_text(page)
print('Built three reconciled SVG figures and a self-contained preview.')
