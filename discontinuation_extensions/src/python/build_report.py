"""Build a portable aggregate report from parameterized analysis results."""
import argparse
import base64
import html
import json
import math
from pathlib import Path

p = argparse.ArgumentParser()
p.add_argument('--results-dir', type=Path, required=True)
p.add_argument('--output', type=Path, required=True)
p.add_argument('--reason-timing-dir', type=Path, required=True)
p.add_argument('--alluvial-dir', type=Path, required=True)
p.add_argument('--alluvial-aggregate-dir', type=Path, required=True)
a = p.parse_args()
COUNTRIES = ['Ethiopia', 'Nigeria', 'DRC']
GROUPS = ['Injectables', 'Implants', 'Pill', 'IUD', 'Other modern']
COLORS = {'Injectables':'#0E8C8F','Implants':'#153F5B','Pill':'#DA9A25','IUD':'#E45A4B','Other modern':'#7C8797'}
E = html.escape
def num(x, digits=2):
    return '—' if x is None else f'{x:,.{digits}f}'
def integer(x): return f'{x:,}'
def ci(s):
    return 'Not estimated' if s['ci_low_12'] is None else f"{num(s['ci_low_12'])}–{num(s['ci_high_12'])}"
def star(s):
    return '*' if s['partner_endings'] < 30 or s['month1_episodes'] < 250 else ''
def table(headers, rows, caption='', classes=''):
    return f'<div class="table-wrap"><table class="{classes}"><caption>{caption}</caption><thead><tr>'+''.join(f'<th scope="col">{h}</th>' for h in headers)+'</tr></thead><tbody>'+''.join('<tr>'+''.join(f'<th scope="row">{v}</th>' if i==0 else f'<td>{v}</td>' for i,v in enumerate(row))+'</tr>' for row in rows)+'</tbody></table></div>'
def svg_start(label, height, width=900):
    return f'<svg class="chart" viewBox="0 0 {width} {height}" role="img" aria-label="{E(label)}"><title>{E(label)}</title>'
def curve(data, country):
    mm=data['monthly']; maximum=max(v['ci_high'] or v['probability'] or 0 for v in mm)
    top=math.ceil(maximum*1.15*2)/2
    left,right,up,down=75,780,28,290
    x=lambda m:left+(right-left)*m/12
    y=lambda v:down-(down-up)*v/top
    s=svg_start(f'{country}: cumulative probability of partner-disapproval discontinuation, 0 to 12 months',360)
    for i in range(5):
        v=top*i/4; yy=y(v)
        s+=f'<line x1="{left}" x2="{right}" y1="{yy}" y2="{yy}" class="grid"/><text x="{left-14}" y="{yy+5}" text-anchor="end">{num(v, 1)}%</text>'
    for m in [0,3,6,9,12]:
        xx=x(m); s+=f'<text x="{xx}" y="{down+25}" text-anchor="middle">{m}</text>'
    path=f'M {x(0)} {y(0)}'
    for v in mm[1:]: path+=f' H {x(v["month"])} V {y(v["probability"])}'
    s+=f'<path d="{path}" fill="none" stroke="#0E8C8F" stroke-width="3"/>'
    for v in mm:
        if v['month'] not in [3,6,9,12]:continue
        xx=x(v['month'])
        if v['ci_low'] is not None:
            lo,hi=y(v['ci_low']),y(v['ci_high'])
            s+=f'<path d="M {xx} {lo} V {hi} M {xx-5} {lo} H {xx+5} M {xx-5} {hi} H {xx+5}" fill="none" stroke="#153F5B" stroke-width="1.5"/>'
        s+=f'<circle cx="{xx}" cy="{y(v["probability"])}" r="4.5" fill="#0E8C8F"/>'
    s+=f'<text x="{right+12}" y="{y(mm[-1]["probability"])+5}" class="endpoint">{num(mm[-1]["probability"])}%</text>'
    s+=f'<text x="{(left+right)/2}" y="345" text-anchor="middle">Months since method initiation</text></svg>'
    return s
def forest(methods, country):
    summaries=[methods[k]['summary'][0] for k in GROUPS]
    top=max(1,math.ceil(max((s['ci_high_12'] or s['probability_12'] or 0) for s in summaries)*1.13))
    left,right,up,step=170,675,40,57
    x=lambda v:left+(right-left)*v/top
    s=svg_start(f'{country}: 12-month partner-disapproval discontinuation by method, with 95% intervals',390)
    for i in range(5):
        v=top*i/4;xx=x(v)
        s+=f'<line x1="{xx}" x2="{xx}" y1="22" y2="310" class="grid"/><text x="{xx}" y="337" text-anchor="middle">{num(v,1)}%</text>'
    for i,(k,v) in enumerate(zip(GROUPS,summaries)):
        yy=up+step*i
        s+=f'<text x="{left-14}" y="{yy+5}" text-anchor="end">{E(k)}{star(v)}</text>'
        if v['ci_low_12'] is not None:
            lo,hi=x(v['ci_low_12']),x(v['ci_high_12'])
            s+=f'<path d="M {lo} {yy} H {hi} M {lo} {yy-5} V {yy+5} M {hi} {yy-5} V {yy+5}" stroke="{COLORS[k]}" stroke-width="2" fill="none"/>'
        s+=f'<circle cx="{x(v["probability_12"])}" cy="{yy}" r="5" fill="{COLORS[k]}"/>'
        label=f'{num(v["probability_12"])}%'
        if v['partner_endings']==0:label+=' · no observed endings'
        s+=f'<text x="700" y="{yy+5}">{label}</text>'
    s+='<text x="422" y="378" text-anchor="middle">12-month probability (%)</text></svg>'
    return s

def subgroup_symbol(row):
    return '†' if row['target_endings']<5 else '*' if row['target_endings']<30 else ''

def subgroup_forest(data, country):
    rows=[r for r in data['summary'] if r['domain']!='National']
    national=data['summary'][0]['probability_12']
    maximum=max(r['ci_high_12'] for r in rows)
    top=math.ceil(maximum*1.08*2)/2 if maximum<2 else math.ceil(maximum*1.08)
    left,right=190,625
    x=lambda v:left+(right-left)*v/top
    s=svg_start(f'{country}: actual national subgroup estimates of 12-month modern-method discontinuation due to partner/spousal disapproval; EC excluded',710)
    s+=f'<text x="0" y="23" style="font-weight:700;font-size:21px">{country}: partner/spousal-disapproval discontinuation</text><text x="0" y="49">First-year probabilities · Modern methods excluding EC</text><g transform="translate(0,75)">'
    for i in range(5):
        v=top*i/4;xx=x(v)
        s+=f'<line x1="{xx}" x2="{xx}" y1="48" y2="497" class="grid"/><text x="{xx}" y="526" text-anchor="middle">{num(v,1)}%</text>'
    s+=f'<line x1="{x(national)}" x2="{x(national)}" y1="48" y2="497" stroke="#153F5B" stroke-width="1.5" stroke-dasharray="4 4"/>'
    s+='<text x="704" y="24" text-anchor="middle">Estimate (95% CI)</text><text x="870" y="24" text-anchor="end">Endings</text>'
    layout=[('Age at method initiation',54,92),('Parity at method initiation',218,256),('Residence at interview',382,420)]
    for domain,title_y,first_y in layout:
        s+=f'<text x="0" y="{title_y}" style="font-weight:700">{E(domain)}</text>'
        for i,r in enumerate(z for z in rows if z['domain']==domain):
            yy=first_y+44*i
            s+=f'<text x="8" y="{yy+5}">{E(r["subgroup"])}{subgroup_symbol(r)}</text>'
            lo,hi=x(r['ci_low_12']),x(r['ci_high_12'])
            col='#DA9A25' if r['target_endings']<5 else '#0E8C8F'
            s+=f'<path d="M {lo} {yy} H {hi} M {lo} {yy-5} V {yy+5} M {hi} {yy-5} V {yy+5}" stroke="{col}" stroke-width="2" fill="none"/>'
            s+=f'<circle cx="{x(r["probability_12"])}" cy="{yy}" r="5" fill="{col}"/>'
            s+=f'<text x="704" y="{yy+5}" text-anchor="middle">{num(r["probability_12"])} ({num(r["ci_low_12"])}–{num(r["ci_high_12"])})</text><text x="870" y="{yy+5}" text-anchor="end">{r["target_endings"]}</text>'
    s+=f'<text x="{(left+right)/2}" y="557" text-anchor="middle">12-month probability (%)</text></g><text x="0" y="665" style="font-size:13px">Dotted line: national probability ({num(national)}%). Estimates are unadjusted; intervals account for survey design.</text><text x="0" y="688" style="font-size:13px">Sample flags: * 5–29 endings; † fewer than 5. Endings are unweighted counts. No formal subgroup tests.</text></svg>'
    return s

css='''
:root{--navy:#153F5B;--teal:#0E8C8F;--gold:#DA9A25;--gray:#66778A;--line:#DCE5EB}*{box-sizing:border-box}body{margin:0;font:17px/1.55 Arial,sans-serif;color:#233746;background:#F5F7F9}aside{width:255px;position:fixed;inset:0 auto 0 0;padding:30px 20px;background:white;border-right:1px solid var(--line);overflow:auto}aside h2{font:700 21px Georgia,serif;color:var(--navy);margin-top:0}.eyebrow{letter-spacing:.1em;text-transform:uppercase;font-size:12px;font-weight:700;color:var(--teal)}[role=tablist]{display:flex;flex-direction:column;gap:8px;margin:18px 0}[role=tab]{text-align:left;padding:12px 14px;border:1px solid var(--line);background:white;border-radius:5px;font:inherit;color:var(--navy);cursor:pointer}[role=tab][aria-selected=true]{background:var(--navy);color:white;border-color:var(--navy)}.toc a{display:block;color:#40566B;padding:7px 8px;font-size:14px;text-decoration:none}.toc a:hover{text-decoration:underline}.toc .common{border-top:1px solid var(--line);margin-top:18px;padding-top:14px}main{margin-left:255px;padding:42px 5vw 60px;max-width:1560px}header{margin-bottom:28px}h1{font:700 clamp(29px,3vw,42px)/1.17 Georgia,serif;color:var(--navy);margin:10px 0 20px}h2{font:700 29px Georgia,serif;color:var(--navy);margin:0 0 14px}h3{font-size:21px;line-height:1.3;color:var(--navy);margin:0 0 18px}h4{font-size:18px;color:var(--navy)}p{margin:12px 0}.lead{max-width:920px;font-size:19px}.definition{border-left:4px solid var(--teal);padding:13px 20px;background:#EAF4F4;margin:22px 0}.country-head{display:flex;align-items:baseline;justify-content:space-between;gap:15px;border-bottom:2px solid var(--navy);margin-top:30px;padding-bottom:10px}.country-head h2{margin:0}.survey{color:var(--gray);font-size:16px}.cards{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:14px;margin:22px 0}.card{padding:20px;background:white;border:1px solid var(--line);border-radius:7px}.card .value{font-size:32px;color:var(--navy);display:block}.card .label{font-size:15px;color:#526777}.card .ci{font-size:15px;display:block;margin-top:5px}.section{background:white;border:1px solid var(--line);padding:28px;margin:23px 0;border-radius:7px;scroll-margin-top:18px}.note{font-size:14px;color:#526777;line-height:1.5}.warning{padding:14px 18px;background:#FFF8E9;border-left:4px solid var(--gold);font-size:15px;margin:18px 0}.table-wrap{overflow-x:auto;margin:16px 0}table{border-collapse:collapse;width:100%;font-size:15px;font-variant-numeric:tabular-nums}caption{text-align:left;font-size:14px;color:#526777;padding:0 0 12px}th,td{padding:12px 13px;border-bottom:1px solid var(--line);vertical-align:top;text-align:right}th:first-child,td:first-child{text-align:left}thead th{background:var(--navy);color:white;font-weight:400;line-height:1.35;white-space:normal;min-width:95px}tbody th{font-weight:400;color:var(--navy)}tbody tr:nth-child(even){background:#F5F8FA}.status{font-size:13px;max-width:185px;display:inline-block;text-align:left}.chart{width:100%;height:auto;display:block;min-width:520px}.chart text{font:15px Arial,sans-serif;fill:#233746}.chart .endpoint{font-size:17px}.grid{stroke:#E1E8EE;stroke-width:1}.plot-wrap{overflow-x:auto}details{border-top:1px solid var(--line);padding:16px 0}summary{color:var(--navy);font-weight:700;cursor:pointer}.timingbar{display:flex;height:40px;width:100%;border-radius:3px;overflow:hidden;margin:18px 0}.timingbar span{display:flex;align-items:center;justify-content:center;font-size:14px;white-space:nowrap}.legend{display:flex;gap:16px;flex-wrap:wrap;font-size:14px}.swatch{display:inline-block;width:13px;height:13px;margin-right:7px;vertical-align:middle}.compact-list li{margin-bottom:10px}.methodology{margin-top:35px}a{color:#086C80}button:focus-visible,a:focus-visible,summary:focus-visible{outline:3px solid var(--gold);outline-offset:3px}.js [hidden]{display:none!important}footer{font-size:13px;color:#66778A;margin-top:25px}
@media(max-width:850px){aside{position:static;width:auto;padding:20px;border-right:0;border-bottom:1px solid var(--line)}aside h2{margin-bottom:8px}[role=tablist]{flex-direction:row;margin:12px 0}[role=tab]{flex:1;text-align:center;padding:10px 7px}.toc nav{display:flex;flex-wrap:wrap}.toc a{display:inline-block}.toc .common{border:0;margin:0;padding:0}main{margin:0;padding:25px 18px}.cards{grid-template-columns:1fr}.card{padding:14px 18px}.card .value{font-size:28px}.section{padding:20px 16px}.country-head{display:block}h2{font-size:27px}th,td{padding:10px}h1{font-size:31px}}
@media print{aside{display:none}main{margin:0;padding:0;max-width:none}body{background:white;font-size:11pt}.js [role=tabpanel][hidden]{display:block!important}.section{border:0;padding:12px 0;break-inside:avoid}.country-head{break-before:page}.cards{grid-template-columns:repeat(2,1fr)}.chart{min-width:0}details{display:block}details>*{display:block}details summary{display:none}.table-wrap{overflow:visible}a{color:inherit;text-decoration:none}footer{display:none}}
'''
sections=[]
navigation=[]
reason_sections=[]
alluvial_sections=[]
endpoint_reason_sections=[]
destination_sections=[]
for index,country in enumerate(COUNTRIES):
    slug=country.lower(); data=json.loads((a.results_dir/slug/'results.json').read_text())
    methods=data['methods'];meta=data['metadata']; pooled=methods['All modern'];s=pooled['summary'][0]
    timing_name='timing.json' if country=='Ethiopia' else f'{slug}_timing.json'
    timing=json.loads((a.reason_timing_dir/timing_name).read_text())
    assert timing['country']==country and timing['eligible_episodes']==s['eligible_episodes']
    assert len(timing['rows'])==5
    figure_name=f'{country}_actionable_reason_timing'+('_comparable' if country=='Ethiopia' else '')+'.svg'
    figure=(a.reason_timing_dir/figure_name).read_text()
    assert f'{country} · national' in figure
    assert all(f'{r["probability"][-1]:.2f}%' in figure for r in timing['rows'])
    embedded='data:image/svg+xml;base64,'+base64.b64encode(figure.encode()).decode()
    ranked=sorted(timing['rows'],key=lambda r:r['probability'][-1],reverse=True)
    total=sum(r['probability'][-1] for r in ranked)
    reason_content=f'<section class="section" id="{slug}-actionable-timing"><h3>{country}: reasons and timing of potentially actionable discontinuation</h3><p>The combined 12-month probability for these five categories is <strong>{total:.2f}%</strong>. Each bar shows one reason’s contribution to that probability.</p><figure style="margin:20px 0"><img class="reason-timing-figure" src="{embedded}" alt="{country}: national reason-specific cumulative discontinuation probabilities, divided into months 1–3, 4–6, 7–9 and 10–12. Numerical values follow in the expandable table." style="display:block;width:100%;height:auto"/></figure>'
    reason_content+='<details><summary>View cumulative probabilities at 3, 6, 9 and 12 months</summary>'
    reason_content+=table(['Potentially actionable reason','3 months','6 months','9 months','12 months','Share of first-year risk by month 3'],[[E(r['reason'])]+[f'{v:.2f}%' for v in r['probability']]+[f'{r["share_by_three"]:.1f}%'] for r in ranked], 'National weighted competing-risk point estimates. The final column is the 3-month probability divided by the 12-month probability × 100.')
    reason_content+='</details></section>'
    reason_sections.append(reason_content)
    pathways=json.loads((a.alluvial_aggregate_dir/f'{slug}.json').read_text())
    assert pathways['country']==country and pathways['validation']['all_margins_reconcile']
    assert pathways['validation']['original_EC_excluded'] and pathways['validation']['actionable_only']
    assert pathways['validation']['partner_disapproval_excluded']
    assert pathways['times']==[1,3,6,12]
    alluvial=(a.alluvial_dir/f'{country}_actionable_post_discontinuation_alluvial.svg').read_text()
    assert 'Method discontinued' in alluvial and f'{country} · DHS' in alluvial
    alluvial_uri='data:image/svg+xml;base64,'+base64.b64encode(alluvial.encode()).decode()
    ending_n=pathways['endings'];women_n=pathways['women']
    modern_12=next(r['share'] for r in pathways['shares'] if r['month']==12 and r['state']=='Modern method')
    alt=f'{country}: original method discontinued and status at months 1, 3, 6 and 12 after an actionable ending.'
    img=f'<img class="alluvial-figure" src="{alluvial_uri}" alt="{alt}" style="display:block;width:100%;height:auto"/>'
    block=f'<section class="section" id="{slug}-actionable-alluvial"><h3>{country}: what follows an actionable modern-method ending?</h3><p><strong>{ending_n:,} observed endings from {women_n:,} women</strong>, each with twelve subsequent calendar months available. Original-method EC episodes are excluded. Only potentially actionable endings are included.</p><figure style="margin:20px 0">{img}</figure>'
    block+=f'<p><strong>Reading the month-12 column:</strong> {modern_12:.1f}% of the weighted eligible endings across <em>all original methods combined</em> are followed by modern use twelve months later. Modern use can reflect a different method or restarting the original method.</p>'
    block+='<details><summary>View a larger figure</summary><div class="plot-wrap">'+img.replace('class="alluvial-figure"','class="alluvial-enlarged"').replace('width:100%;height:auto','width:1800px;max-width:none;height:auto')+'</div></details>'
    assert abs(sum(r['share'] for r in pathways['origins'])-100)<1e-8
    for t in pathways['times']:assert abs(sum(r['share'] for r in pathways['shares'] if r['month']==t)-100)<1e-8
    block+='</section>'
    alluvial_sections.append(block)
    reason_endpoints=json.loads((a.alluvial_aggregate_dir/f'{slug}_reason_endpoint.json').read_text())
    assert reason_endpoints['country']==country and all(reason_endpoints['validation'].values())
    assert reason_endpoints['endings']==ending_n and reason_endpoints['women']==women_n
    assert sum(r['endings'] for r in reason_endpoints['rows'][1:])==ending_n
    assert abs(reason_endpoints['rows'][0]['modern12']-modern_12)<1e-8
    for row in reason_endpoints['rows']:
        assert abs(sum(cell['share'] for cell in row['cells'])-100)<1e-8
        assert sum(cell['endings'] for cell in row['cells'])==row['endings']
    reason_outcome_svg=(a.alluvial_dir/f'{country}_continuity_by_actionable_reason.svg').read_text()
    assert f'{country} · DHS' in reason_outcome_svg
    assert all(f'{r["modern12"]:.1f}%' in reason_outcome_svg for r in reason_endpoints['rows'])
    reason_outcome_uri='data:image/svg+xml;base64,'+base64.b64encode(reason_outcome_svg.encode()).decode()
    reason_outcome_img=f'<img class="reason-outcome-figure" src="{reason_outcome_uri}" alt="{country}: month-12 outcomes and modern-use continuity within each actionable ending reason. Every row sums to 100 percent." style="display:block;width:100%;height:auto"/>'
    reason_block=f'<section class="section" id="{slug}-continuity-by-reason"><h3>{country}: subsequent use by reason for stopping</h3><p>The overall row uses the same <strong>{ending_n:,} endings</strong> as the alluvial. Each subsequent row includes only endings attributed to the reason shown. All original modern methods are combined.</p><figure style="margin:20px 0">{reason_outcome_img}</figure>'
    reason_block+='<p><strong>How to read a row:</strong> the five colors divide that reason’s eligible endings into their subsequent histories and month-12 states. Teal means a modern method was recorded in every following month. Gold means modern use at month 12 after earlier months outside modern use. The remaining colors show no method, a pregnancy-related record, or traditional use at month 12. Teal plus gold gives the percentage in the right-hand column.</p>'
    reason_block+='<details><summary>View a larger figure</summary><div class="plot-wrap">'+reason_outcome_img.replace('class="reason-outcome-figure"','class="reason-outcome-enlarged"').replace('width:100%;height:auto','width:1800px;max-width:none;height:auto')+'</div></details>'
    reason_block+='<p class="note">Percentages use DHS sampling weights. N counts observed endings, not distinct women. † marks a colored segment supported by fewer than five observed endings. These are descriptive results; no tests of differences between reasons are shown.</p>'
    detailed=json.loads((a.alluvial_aggregate_dir/f'{slug}_endpoint_duration_table.json').read_text())
    assert detailed['country']==country and detailed['endings']==ending_n and detailed['women']==women_n
    assert all(detailed['validation'].values())
    split=detailed['endpoint_interruption_distribution']
    assert all(split['validation'].values())
    groups=split['groups']
    assert len(groups)==7 and abs(sum(g['share'] for g in groups)-100)<1e-8
    assert sum(g['observed_endings'] for g in groups)==ending_n
    assert abs(sum(g['share'] for g in groups[:4])-modern_12)<1e-8
    assert abs(groups[0]['share']-reason_endpoints['rows'][0]['cells'][0]['share'])<1e-8
    assert abs(sum(g['share'] for g in groups[1:4])-reason_endpoints['rows'][0]['cells'][1]['share'])<1e-8
    assert all(abs(groups[i+4]['share']-reason_endpoints['rows'][0]['cells'][i+2]['share'])<1e-8 for i in range(3))
    detailed_svg=(a.alluvial_dir/f'{country}_single_endpoint_interruption_bar.svg').read_text()
    assert f'{country} ' in detailed_svg
    assert all(f'{g["share"]:.1f}%' in detailed_svg for g in groups)
    detailed_uri='data:image/svg+xml;base64,'+base64.b64encode(detailed_svg.encode()).decode()
    detailed_img=f'<img class="detailed-interruption-figure" src="{detailed_uri}" alt="{country}: a single 100-percent bar dividing the same actionable ending cohort into modern use at month 12 after zero, one, two to five, or six to eleven months outside modern use, and the three other month-12 states." style="display:block;width:100%;height:auto"/>'
    reason_block+=f'<div id="{slug}-detailed-interruption" class="detailed-interruption"><h4>{country}: modern use and interruptions over the following year</h4><p>This bar takes the overall row above and splits the modern-use group in more detail. It follows the same <strong>{ending_n:,} endings from {women_n:,} women</strong>, with all actionable reasons combined. Every ending appears once, and the unrounded shares total 100%.</p><figure style="margin:20px 0">{detailed_img}</figure>'
    reason_block+='<p><strong>How the figures connect:</strong> the first four segments in the overall bar reproduce the combined teal-and-gold share in the overall row above. They distinguish modern use in every following month from modern use at month 12 after one, two to five, or six to eleven months outside modern use. The no-method, pregnancy-related and traditional-use endpoint shares are unchanged.</p>'
    reason_block+='<details><summary>View a larger interruption figure</summary><div class="plot-wrap">'+detailed_img.replace('class="detailed-interruption-figure"','class="detailed-interruption-enlarged"').replace('width:100%;height:auto','width:1800px;max-width:none;height:auto')+'</div></details>'
    detailed_rows=[]
    for g in groups:
        interval='Not estimated: no observed endings' if g['ci_low'] is None else f'{g["ci_low"]:.1f}–{g["ci_high"]:.1f}%'
        detailed_rows.append([E(g['group']),f'{g["share"]:.1f}%',interval,integer(g['observed_endings'])])
    reason_block+='<details><summary>View interruption percentages, confidence intervals and counts</summary>'
    reason_block+=table(['Follow-up outcome','Weighted share of all endings','95% CI','Observed endings'],detailed_rows,'The full country cohort is the denominator for every percentage. Intervals use 1,999 full-frame stratified PSU bootstrap draws, keeping women and their repeated histories together.')+'</details></div></section>'
    endpoint_reason_sections.append(reason_block)
    destinations=json.loads((a.alluvial_aggregate_dir/f'{slug}_destinations.json').read_text())
    assert destinations['country']==country and all(destinations['validation'].values())
    assert destinations['endings']==ending_n and destinations['women']==women_n
    assert abs(destinations['modern12_share']-modern_12)<1e-8
    assert sum(r['endings'] for r in destinations['rows'][1:])==ending_n
    assert destinations['rows'][0]['origin']=='All actionable endings'
    for row in destinations['rows']:
        assert abs(sum(cell['share'] for cell in row['cells'])-100)<1e-8
        assert sum(cell['endings'] for cell in row['cells'])==row['endings']
    assert abs(sum(c['share'] for c in destinations['rows'][0]['cells'][:-1])-destinations['first_modern_share'])<1e-8
    destination_svg=(a.alluvial_dir/f'{country}_origin_to_first_modern_destination.svg').read_text()
    assert f'{country} · DHS' in destination_svg
    assert all(f'{cell["share"]:.1f}%' in destination_svg for row in destinations['rows'] for cell in row['cells'])
    destination_uri='data:image/svg+xml;base64,'+base64.b64encode(destination_svg.encode()).decode()
    destination_alt=f'{country}: first modern method recorded in the twelve months after a potentially actionable ending, grouped by the original method. Each original-method row sums to 100 percent, including endings without a modern return.'
    destination_img=f'<img class="destination-matrix" src="{destination_uri}" alt="{destination_alt}" style="display:block;width:100%;height:auto"/>'
    destination_block=f'<section class="section" id="{slug}-first-modern-destination"><h3>{country}: first modern method used within 12 months after discontinuation</h3><p>The same <strong>{ending_n:,} potentially actionable endings from {women_n:,} women</strong> are followed here as in the alluvial and preceding bar graph.</p><figure style="margin:20px 0">{destination_img}</figure>'
    very_sparse=[r for r in destinations['rows'][1:] if r['endings']<30]
    if very_sparse:
        caution='; '.join(f'{E(r["origin"])}: {r["endings"]} observed endings' for r in very_sparse)
        destination_block+=f'<div class="warning"><strong>Very sparse original-method row:</strong> {caution}. These percentages are shown for completeness and are too unstable for firm conclusions about destinations.</div>'
    destination_block+='<p><strong>Read across one row:</strong> start with the method that ended. The columns show the first modern method recorded in any of the next twelve months, whether immediately or after a gap or pregnancy. Every ending appears in just one column. An ending stays assigned to that first modern method even if it is later discontinued.</p>'
    destination_block+='<p><strong>What is the denominator?</strong> Each method row includes all eligible actionable endings of that original method, including endings with no modern return. The gold overall row combines all original methods. Percentages sum to 100% within each row before rounding.</p>'
    no_return=destinations['rows'][0]['cells'][-1]['share']
    destination_block+=f'<div class="definition"><strong>How this differs from the alluvial:</strong> {destinations["first_modern_share"]:.1f}% of these endings are followed by modern use at least once during the year, while {modern_12:.1f}% are followed by modern use at month 12. The matrix describes the first destination; the alluvial describes states at specific follow-up months. The {no_return:.1f}% in “No modern return” have no modern method recorded in any of the twelve following months. This is broader than “No method” and differs from being outside modern use only at month 12.</div>'
    destination_block+='<details><summary>View a larger matrix</summary><div class="plot-wrap">'+destination_img.replace('class="destination-matrix"','class="destination-enlarged"').replace('width:100%;height:auto','width:1800px;max-width:none;height:auto')+'</div></details>'
    destination_block+='<details><summary>View percentages, confidence intervals and counts</summary>'
    destination_rows=[]
    for row in destinations['rows']:
        for cell in row['cells']:
            interval=E(cell.get('ci_status','Not estimated: no observed endings')) if cell['ci_low'] is None else f'{cell["ci_low"]:.1f}–{cell["ci_high"]:.1f}%'
            destination_rows.append([E(row['origin']),E(cell['destination']),f'{cell["share"]:.1f}%',interval,integer(cell['endings'])])
    destination_block+=table(['Method discontinued','First modern destination','Weighted share','95% CI','Observed endings'],destination_rows,'Confidence intervals use 1,999 stratified cluster-bootstrap draws from the full survey frame. Women and all their episodes stay together.')+'</details>'
    destination_block+='<p class="note">† marks a cell with fewer than five observed endings. * marks an original-method row with fewer than 100 endings, a descriptive caution rather than a statistical-power threshold. Zero observed cells do not establish zero population probability. Intervals are withheld for rows with empty bootstrap draws. Original EC is excluded; subsequent EC is included in Other modern. A return to the same method group may be a restart. These are observed destinations, not preferences or evidence that a method is best for a particular woman. No formal tests of differences are shown.</p></section>'
    destination_sections.append(destination_block)
    # Structural reconciliation before rendering any values.
    assert meta['validation']['status']=='pass' and meta['validation']['EC_episodes']==0
    assert sum(methods[k]['summary'][0]['eligible_episodes'] for k in GROUPS)==s['eligible_episodes']
    assert sum(methods[k]['summary'][0]['partner_endings'] for k in GROUPS)==s['partner_endings']
    detail=[v for k,v in methods.items() if k.startswith('Detail: ')]
    assert sum(v['summary'][0]['eligible_episodes'] for v in detail)==methods['Other modern']['summary'][0]['eligible_episodes']
    assert sum(v['summary'][0]['partner_endings'] for v in detail)==methods['Other modern']['summary'][0]['partner_endings']
    for v in methods.values():
        mm=[x['probability'] for x in v['monthly'] if x['probability'] is not None]
        assert all(y>=x-1e-9 for x,y in zip(mm,mm[1:]))
        if v['timing'] and v['summary'][0]['probability_12']:
            assert abs(sum(t['share_first_year_probability'] for t in v['timing'])-100)<1e-7
    navigation.append(f'<nav data-country="{slug}" aria-label="{country} analyses">'+''.join(f'<a href="#{slug}-{key}">{label}</a>' for key,label in [('overview','Overview'),('share','Share among discontinuations'),('timing','Timing of discontinuation'),('subgroups','Age, parity & residence'),('methods','By modern method'),('composition','When endings occur'),('interpretation','Samples & interpretation')])+'</nav>')
    content=f'<article id="panel-{slug}" role="tabpanel" aria-labelledby="tab-{slug}" data-country="{slug}"><div class="country-head" id="{slug}-overview"><h2>{country}</h2><span class="survey">DHS {meta["survey"]}</span></div>'
    content+=f'<div class="cards"><div class="card"><span class="label">12-month probability</span><span class="value">{num(s["probability_12"])}%</span><span class="ci">95% CI: {ci(s)}% · life-table estimate</span></div><div class="card"><span class="label">Share of observed first-year discontinuations</span><span class="value">{num(s["partner_share_of_first_year_endings"])}%</span><span class="ci">95% CI: {num(s["share_ci_low"])}–{num(s["share_ci_high"])}% · reason distribution</span></div><div class="card"><span class="label">Eligible modern-method episodes</span><span class="value">{integer(s["eligible_episodes"])}</span><span class="ci">EC excluded · unweighted count</span></div><div class="card"><span class="label">Observed partner-disapproval endings in year 1</span><span class="value">{integer(s["partner_endings"])}</span><span class="ci">Contributed by {integer(s["partner_women"])} women</span></div></div>'
    content+=f'<p>Among eligible modern-method episodes, the estimated probability of ending the original method because of reported partner/spousal disapproval within its first year is <strong>{num(s["probability_12"])}%</strong>. Other reasons for ending the method are competing events.</p>'
    assert abs(100*s['weighted_first_year_partner_endings']/s['weighted_first_year_all_endings']-s['partner_share_of_first_year_endings'])<1e-10
    content+=f'<section class="section" id="{slug}-share"><h3>What share of discontinuations is attributed to partner/spousal disapproval?</h3><p><strong>{num(s["partner_share_of_first_year_endings"])}%</strong> of observed modern-method discontinuations occurring within the first year were attributed to partner/spousal disapproval. The denominator includes endings for all reasons, including other, unknown and missing reasons. EC is excluded.</p>'
    comparison=[['12-month discontinuation probability',f'{num(s["probability_12"])}%', 'What is the probability that an eligible modern-method episode ends due to partner disapproval within its first year? Calculated from monthly risk sets, retaining competing endings.'],['Share among observed first-year discontinuations',f'{num(s["partner_share_of_first_year_endings"])}%', 'Among observed first-year modern-method endings, what percentage reported partner disapproval? Calculated as a weighted reason distribution.']]
    content+=table(['Measure','Estimate','Question and denominator'],comparison)
    content+=f'<p class="note">Reason-share calculation: {num(s["weighted_first_year_partner_endings"])} weighted partner-disapproval endings ÷ {num(s["weighted_first_year_all_endings"])} weighted all-reason first-year endings × 100 = {num(s["partner_share_of_first_year_endings"])}%. Weighted counts are survey-scaled episode counts, not national population totals. All reason shares would sum to 100%, apart from rounding.</p>'
    content+='<details><summary>View partner-disapproval shares among discontinuations by method</summary>'
    rows=[]
    for k in GROUPS:
        v=methods[k]['summary'][0]
        interval='Not estimated' if v['share_ci_low'] is None else f'{num(v["share_ci_low"])}–{num(v["share_ci_high"])}%'
        share='Not estimable' if v['partner_share_of_first_year_endings'] is None else f'{num(v["partner_share_of_first_year_endings"])}%'
        rows.append([E(k)+star(v),share,interval,integer(v['partner_endings']),integer(v['first_year_all_endings'])])
    content+=table(['Modern method','Share attributed to partner disapproval','95% CI','Observed partner endings','Observed all-reason endings'],rows,'Shares use weighted counts. The two count columns show unweighted observed endings within the first year.')
    content+='<p class="note">* Sample-support flags use the same criteria as the method-specific probability table. A method with no observed first-year endings has no estimable reason distribution. Zero observed target endings do not establish zero population risk.</p></details></section>'
    content+=f'<section class="section" id="{slug}-timing"><h3>Discontinuation due to partner/spousal disapproval accumulates over the first year</h3><div class="plot-wrap">{curve(pooled,country)}</div><p class="note">Weighted cumulative probability; whiskers show survey-design 95% confidence intervals. The vertical scale varies by country so low probabilities remain visible.</p>'
    rows=[]
    for t in [3,6,9,12]:
        v=pooled['monthly'][t]
        rows.append([f'{t} months',f'{num(v["probability"])}%',f'{num(v["ci_low"])}–{num(v["ci_high"])}%',integer(v['at_risk_n']),integer(v['observed_partner_endings_to_month'])])
    content+=table(['Time since initiation','Cumulative probability','95% CI','Episodes at risk in this month','Observed target endings through this month'],rows,'Probabilities use changing monthly risk sets. Episode and event counts are unweighted.')+'</section>'
    subgroups=json.loads((a.results_dir/slug/'subgroups.json').read_text())
    assert subgroups['metadata']['validation']['status']=='pass'
    assert abs(subgroups['summary'][0]['probability_12']-s['probability_12'])<1e-10
    plot=subgroup_forest(subgroups,country)
    (a.output.parent/f'{slug}_partner_disapproval_subgroups.svg').write_text(plot,encoding='utf-8')
    content+=f'<section class="section" id="{slug}-subgroups"><h3>Partner/spousal-disapproval discontinuation by age, parity and residence</h3><p>National estimates among all modern-method episodes, excluding EC. Each characteristic is examined separately; these are unadjusted comparisons.</p><div class="plot-wrap">{plot}</div><p class="note">Dots show weighted probabilities; lines show survey-design 95% confidence intervals. The dotted vertical line marks the national probability ({num(s["probability_12"])}%). Horizontal scales vary by country. Endings are unweighted observed partner-disapproval events.</p>'
    content+='<p class="note">Sample flags: * 5–29 target endings; † fewer than 5. These are screening rules for caution, not statistical-power thresholds or significance indicators. No formal tests of subgroup differences were performed.</p>'
    subgroup_rows=[]
    for r in subgroups['summary'][1:]:
        subgroup_rows.append([E(r['domain']),E(r['subgroup'])+subgroup_symbol(r),f'{num(r["probability_12"])}%',f'{num(r["ci_low_12"])}–{num(r["ci_high_12"])}%',integer(r['eligible_episodes']),integer(r['target_endings']),f'<span class="status">{E(r["flag"])}</span>'])
    content+=table(['Characteristic','Subgroup','12-month probability','95% CI','Eligible episodes','Partner-disapproval endings','Sample support'],subgroup_rows,'Eligible episode counts and reported endings are unweighted. All other original-method endings are competing events.')
    if country=='Ethiopia':
        content+='<div class="warning">Only 30 first-year partner-disapproval endings were observed nationally. All subgroup estimates have limited event counts; the age-35+ estimate rests on three endings and is particularly unstable. Use these results descriptively rather than as evidence of established subgroup differences.</div>'
    else:
        content+='<div class="warning">Broad subgroup estimates are suitable for exploratory description with their confidence intervals. This does not establish adequate power to detect a particular difference. Sparse groups and differences in method mix can affect interpretation.</div>'
    content+='<p class="note">Age is calculated at method initiation; “Under 25” includes initiation before age 15 among women aged 15–49 at interview. Parity is reconstructed from live births by the month of initiation, including births in that same month. Residence is measured at interview and may differ from residence during method use. These temporal distinctions limit causal interpretation.</p></section>'
    content+=f'<section class="section" id="{slug}-methods"><h3>12-month discontinuation due to partner/spousal disapproval, by modern method</h3><div class="plot-wrap">{forest(methods,country)}</div>'
    rows=[]
    for k in GROUPS:
        v=methods[k]['summary'][0]
        rows.append([E(k)+star(v),f'{num(v["probability_12"])}%',ci(v)+('%' if v['ci_low_12'] is not None else ''),integer(v['eligible_episodes']),integer(v['partner_endings']),f'<span class="status">{E(v["flag"])}</span>'])
    content+=table(['Modern method','12-month probability','95% CI','Eligible episodes','Observed target endings','Sample support'],rows)
    content+='<p class="note">* Fewer than 30 observed target endings or fewer than 250 episodes at risk in month 1. These screening rules flag estimates for caution; they are not minimum-sample standards. “Very sparse” means fewer than 5 target endings or fewer than 25 month-1 episodes. Zero observed endings do not establish zero population risk; a zero-to-zero interval is not reported.</p>'
    content+='<details><summary>View estimates at 3, 6, 9 and 12 months for each method</summary>'
    rows=[]
    for k in GROUPS:
        v=methods[k];cells=[]
        for t in [3,6,9,12]:
            m=v['monthly'][t]; cells.append(f'{num(m["probability"])}%<br><span class="note">'+(f'{num(m["ci_low"])}–{num(m["ci_high"])}%' if m['ci_low'] is not None else 'CI not estimated')+'</span>')
        rows.append([E(k)+star(v['summary'][0])]+cells)
    content+=table(['Modern method','3 months','6 months','9 months','12 months'],rows,'Cumulative probabilities with 95% confidence intervals below each estimate.')+'</details>'
    content+='<details><summary>What is included in Other modern methods?</summary>'
    rows=[]
    for k,v in methods.items():
        if not k.startswith('Detail: '):continue
        ss=v['summary'][0]
        rows.append([E(k.removeprefix('Detail: '))+star(ss),integer(ss['eligible_episodes']),integer(ss['partner_endings']),f'{num(ss["probability_12"])}%' if ss['probability_12'] is not None else 'Not estimable',ci(ss)+('%' if ss['ci_low_12'] is not None else ''),f'<span class="status">{E(ss["flag"])}</span>'])
    content+=table(['Method within Other modern','Eligible episodes','Observed target endings','12-month probability','95% CI','Sample support'],rows)
    content+='<p class="note">Only methods represented in the eligible episodes are shown. An uninterrupted 12-month risk set is required for a full-year estimate. Sparse components are displayed for transparency and should not be ranked.</p></details></section>'
    content+=f'<section class="section" id="{slug}-composition"><h3>When does the first-year partner-disapproval probability accumulate?</h3><p>This view divides the first-year partner-disapproval probability into four time periods. It answers a different question from the cumulative probabilities above.</p>'
    shades=['#E8C36C','#B8DADB','#59AFB0','#0E8C8F']
    content+='<div class="timingbar" role="img" aria-label="Shares of first-year partner-disapproval probability by quarter">'
    for t,col in zip(pooled['timing'],shades):
        v=t['share_first_year_probability'];content+=f'<span style="width:{v:.8f}%;background:{col};color:{"white" if col==shades[-1] else "#173F55"}" title="{t["period"]}: {num(v,1)}%">{num(v,1)+"%" if v>=9 else ""}</span>'
    content+='</div><div class="legend">'+''.join(f'<span><i class="swatch" style="background:{col}"></i>{t["period"]}</span>' for t,col in zip(pooled['timing'],shades))+'</div>'
    rows=[[t['period'],f'{num(t["probability_increment_pp"])} pp',f'{num(t["share_first_year_probability"],1)}%'] for t in pooled['timing']]
    content+=table(['Period since method initiation','Increment in cumulative probability','Share of first-year probability'],rows)
    content+='<p class="note">Shares are increments in the competing-risk cumulative probability divided by its 12-month value. They add to 100% before rounding. They are not raw percentages of observed discontinuations.</p></section>'
    content+=f'<section class="section" id="{slug}-interpretation"><h3>How much can these data support?</h3><ul class="compact-list"><li>The analysis includes <strong>{integer(s["eligible_episodes"])} episodes</strong>, with {integer(s["month1_episodes"])} at risk in month 1. It retains {integer(s["late_entries"])} episodes entering observation after method initiation; they contribute only at observed durations.</li><li>There are <strong>{integer(s["partner_endings"])} first-year partner-disapproval endings</strong>, contributed by {integer(s["partner_women"])} women across {integer(s["partner_psus"])} survey clusters. Event counts, rather than total episodes alone, limit method-specific precision.</li><li>Survey weights determine the estimates. Uncertainty resamples the full survey frame of {integer(meta["full_frame_psus"])} clusters in {integer(meta["full_frame_strata"])} strata, preserving repeated episodes from the same woman.</li><li>These are unadjusted descriptive estimates. No formal tests of country or method differences were performed.</li></ul><div class="warning">A low reported probability does not imply an absence of partner influence. The calendar records one main reason for a method ending and cannot capture all pressure, secrecy, control, or barriers to starting contraception.</div></section></article>'
    sections.append(content)

methodology='''<section class="section methodology" id="methods"><h2>Definitions and methods</h2><h4>Population and outcome</h4><p>The analysis uses women’s individual recode data and prepared contraceptive-calendar episodes for Ethiopia 2024–25, Nigeria 2024, and DRC 2023–24. The observation window is 3–62 months before each woman’s interview. Episodes have an identifiable start; eligible delayed entry is retained. Modern-method episodes are included and emergency contraception (EC) is excluded throughout.</p><p>The outcome is an original-method ending within 12 months of initiation whose reported main reason is husband/partner disapproval (calendar reason code 3). Partner/spousal disapproval is a separate outcome and is <strong>not included among potentially actionable causes</strong>. These estimates do not describe broader partner influence or spousal support.</p><h4>Competing-risk life tables</h4><p>At each month, the weighted number of target endings is divided by the weighted original-method risk set. That monthly probability is multiplied by the probability of still using the original method at the beginning of the month and accumulated over time. Every other method-ending reason reduces original-method survival as a competing event. Episodes ending for other reasons are retained in the analysis.</p><p>Risk sets change as episodes end, become censored, or enter observation after initiation. Therefore, a 12-month probability is not calculated by dividing observed endings by the total episode count. Repeated episodes are allowed. The point estimates were independently checked against a weighted Aalen–Johansen estimator and a separate life-table implementation.</p><h4>Subgroup estimates and sample support</h4><p>Age and parity are reconstructed at method initiation. Parity counts live births occurring by that month; the order of events within a month is unknown. Full birth-history counts were checked against total births reported at interview. Residence is measured at interview. Every characteristic partitions the full eligible cohort, and subgroup episode and event counts reconcile with the national totals. These are unadjusted subgroup probabilities; they retain actual differences in method mix. No formal subgroup tests or minimum-detectable-difference calculations were performed.</p><h4>Share among discontinuations</h4><p>The reason share divides weighted partner-disapproval endings by all weighted observed modern-method endings within their first 12 months, in the same eligible episode cohort. This is a conditional distribution among observed endings, rather than a life-table probability. Other, unknown and missing reasons stay in the denominator. Reason-share intervals use the same full-frame survey bootstrap as the life-table estimates. The cumulative-risk timing shares shown elsewhere divide life-table probability increments by their 12-month probability and have a different denominator.</p><h4>Weights and survey uncertainty</h4><p>Point estimates use the women’s DHS sampling weights. Percentile 95% confidence intervals use 1,999 stratified Rao–Wu n−1 cluster-bootstrap replicates drawn from the full interviewed-women survey frame, including clusters without eligible episodes. Women and all their episodes stay together within each sampled cluster. A small positive multiplier (0.0001) preserves sparse risk-set support; its effect is removed from replicate deviations before calculating intervals.</p><p>No interval is reported when no target event was observed by the specified month; an all-zero empirical bootstrap would give misleading certainty. The sample flags are transparent descriptive screening rules, not proof of sufficient power. No model-based smoothing, adjusted regression, or pairwise significance tests were used.</p><h4>Interpretation and limitations</h4><ul class="compact-list"><li>The life-table probabilities and the reason shares are explicitly labeled and have different denominators. Neither measures the percentage of women who experience partner opposition or the probability that a current user will leave modern use next year.</li><li>Switching or restarting after an ending does not erase that ending. This module does not estimate net loss of modern users or an effect on mCPR.</li><li>Rare events, retrospective recall, monthly date resolution, a single reported main reason, and differences in method mix affect interpretation. Broad Other-modern estimates combine heterogeneous methods.</li><li>Country and method estimates should be read with their intervals and counts. No causal explanation or statistical ranking follows from their point estimates alone.</li></ul><h4>Methodological references</h4><p><a href="https://www.dhsprogram.com/pubs/pdf/DHSG1/Guide_to_DHS_Statistics_DHS-8.pdf">DHS Guide to Statistics</a> · <a href="https://www.dhsprogram.com/data/calendar-tutorial/upload/DHS-Contraceptive-Calendar-Tutorial.pdf">DHS Contraceptive Calendar Tutorial</a> · <a href="https://github.com/DHSProgram/DHS-Indicators-Stata/blob/master/Chap07_FP/FP_DISCONT.do">DHS discontinuation indicator code</a>.</p><p class="note">This separate analysis preserves the existing national reports and presentations. All numerical displays are built from the same checked aggregate results.</p></section>'''
js='''document.documentElement.classList.add('js');const tabs=[...document.querySelectorAll('[role=tab]')];function activate(country,focus=false){tabs.forEach(t=>{let on=t.dataset.country===country;t.setAttribute('aria-selected',on);t.tabIndex=on?0:-1;if(on&&focus)t.focus()});document.querySelectorAll('[role=tabpanel],nav[data-country]').forEach(el=>el.hidden=el.dataset.country!==country)}function fromHash(){const c=location.hash.slice(1).split('-')[0];if(['ethiopia','nigeria','drc'].includes(c))activate(c);else if(!tabs.some(t=>t.getAttribute('aria-selected')==='true'))activate('ethiopia')}tabs.forEach((t,i)=>{t.addEventListener('click',()=>{activate(t.dataset.country);location.hash=t.dataset.country+'-overview'});t.addEventListener('keydown',e=>{let j;if(e.key==='ArrowDown'||e.key==='ArrowRight')j=(i+1)%tabs.length;if(e.key==='ArrowUp'||e.key==='ArrowLeft')j=(i+tabs.length-1)%tabs.length;if(e.key==='Home')j=0;if(e.key==='End')j=tabs.length-1;if(j!==undefined){e.preventDefault();activate(tabs[j].dataset.country,true);location.hash=tabs[j].dataset.country+'-overview'}})});window.addEventListener('hashchange',fromHash);fromHash();'''
reason_intro='<header><div class="eyebrow">Ethiopia · Nigeria · DRC</div><h1>Discontinuation and switching extensions</h1><p class="lead">National reasons and timing are followed by post-discontinuation pathways and the separate analysis of partner/spousal disapproval.</p></header><section class="section" id="national-reasons-timing"><h2>Which actionable reasons contribute most, and when?</h2><p>These figures describe the first 12 months after method initiation. All estimates use modern-method episodes excluding EC. Potentially actionable causes are method failure, wanting a more effective method, bleeding changes, other side effects/health, and access/cost/convenience. Partner/spousal disapproval is separate and is excluded from these five categories.</p><div class="definition"><strong>How to read the figures:</strong> The horizontal axis is a percentage, not months. A full bar gives the 12-month probability of ending for that reason. Gold shows the portion accumulated by month 3; the other colors show the added probability during months 4–6, 7–9 and 10–12. The right-hand percentage divides the month-3 probability by its month-12 value. It is a timing summary, not a discontinuation rate.</div><p>For example, Ethiopia’s bleeding-related probability is 1.08% by month 3 and 2.81% by month 12. Thus, 38.5% of its first-year bleeding-related risk has accumulated by month 3, calculated using unrounded estimates.</p><p class="note">All three figures use the same 0–8% horizontal scale and display weighted point estimates. Nonactionable endings remain competing events. The charts describe when method endings occur, not when symptoms begin. These estimates do not show intervention effects or net losses of modern users after switching/restarting.</p></section>'+''.join(reason_sections)
alluvial_intro='<section class="section" id="actionable-post-ending-pathways"><h2>What happens after an actionable modern-method ending?</h2><h3>What these figures tell us</h3><p>Stopping a method does not always mean stopping modern contraception. A woman may move straight to another method, spend some time without one, or return to use later. These figures follow what happened after women stopped a modern method for one of the potentially actionable reasons.</p><p>They help us answer the following questions:</p><ul class="compact-list"><li><strong>Which methods were women using when they stopped?</strong> The first column shows the methods that ended. Its percentages describe these discontinuations, not the method mix among all current users.</li><li><strong>What happened soon afterward?</strong> The month-1 column shows how often an ending was followed by modern use, no method, traditional use, or a pregnancy-related record.</li><li><strong>What changed over the following year?</strong> The ribbons connect each ending to the same woman’s later records. They show, for example, whether women recorded with no method at an earlier snapshot were using a modern method later.</li><li><strong>Where did things stand twelve months after stopping?</strong> The final column shows the share in each recorded state at that point. Modern use includes a different modern method or a return to the original one.</li></ul><p>Two women can reach the same month-12 outcome through very different experiences. One might switch straight from injectables to pills and keep using them. Another might spend several months without a method before starting an implant. Both count as modern users at month 12. The earlier columns help show that difference.</p><p>We should read the ribbons as links between the displayed months. A woman recorded in modern use at months 3 and 6 could still have had a gap between those snapshots. The figures also do not tell us which subsequent method lasts longest, or why a woman did or did not return to use. Answering those questions requires looking at the intervening monthly records and subsequent method episodes.</p><h3>Who is included, and when does follow-up start?</h3><p>The preceding charts measure the probability of an ending during the first twelve months after method initiation. The following alluvials start with episodes that have already ended for a potentially actionable cause and describe what follows. They include endings at any duration of method use, rather than only first-year endings.</p><div class="definition"><strong>First column:</strong> the method recorded in the episode’s last month of use. <strong>Later columns:</strong> the same endings linked to recorded states 1, 3, 6 and 12 months afterward. All percentages use the country’s entire eligible follow-up cohort as the denominator. A month-12 modern-use percentage therefore combines all original methods.</div><p>These figures describe twelve months <em>after discontinuation</em>. The mCPR planning sensitivity tables instead assess modern use twelve months <em>from the prediction baseline</em>, allowing less post-ending time for women who discontinue later in that window. The two quantities are not interchangeable.</p></section>'+''.join(alluvial_sections)
endpoint_reason_intro='<section class="section" id="outcomes-by-actionable-reason"><h2>Does subsequent use differ by the reason for stopping?</h2><p>The alluvials combine all actionable reasons. These charts take the next step: they link the reported reason for stopping to the following year of contraceptive records.</p><p>For example, the bleeding row asks: among eligible endings attributed to bleeding changes, how many are followed by modern use throughout the year, a return after an interruption, or another recorded state at month 12? The access row asks the same question among access-, cost- or convenience-related endings.</p><p><strong>Each row has its own denominator and sums to 100%.</strong> These are outcome distributions among endings, not discontinuation probabilities. The gold segment can include pregnancy-related or traditional-use months before modern use is recorded at month 12. Method failure remains separate because pregnancy caused the original ending.</p><p>These comparisons help show where later modern use is less common and where return follows an interruption. They do not establish why those differences occur or which service response would change them.</p></section>'+''.join(endpoint_reason_sections)
destination_intro='<section class="section" id="first-modern-destinations"><h2>Which modern methods do women take up after stopping?</h2><p>The preceding bar graphs show continuity and status at month 12. These matrices describe a different part of the experience: the first modern method recorded at any point during the twelve months after a potentially actionable ending.</p><p>For example, an injectable ending followed by pills, then an implant, then no method at month 12 is assigned to the Pill column here. In the alluvial, the same ending appears in the No method category at month 12. Both descriptions can be true.</p><p>These tables show which alternatives women actually adopt and how often there is no modern return during the year. They do not show how long the new method lasts. Partner/spousal disapproval is excluded from the actionable ending cohort. The unit is a method ending; one woman can contribute more than one ending.</p></section>'+''.join(destination_sections)
reason_nav='<div class="toc"><a href="#national-reasons-timing"><strong>National reasons &amp; timing</strong></a>'+''.join(f'<a href="#{c.lower()}-actionable-timing">{c}</a>' for c in COUNTRIES)+'</div><div class="toc" style="margin-top:16px"><a href="#actionable-post-ending-pathways"><strong>After actionable endings</strong></a>'+''.join(f'<a href="#{c.lower()}-actionable-alluvial">{c}</a>' for c in COUNTRIES)+'</div><div class="toc" style="margin-top:16px"><a href="#outcomes-by-actionable-reason"><strong>Outcomes by reason</strong></a>'+''.join(f'<a href="#{c.lower()}-continuity-by-reason">{c}</a>' for c in COUNTRIES)+'</div><h3 style="font-size:17px;margin:24px 0 8px">Partner/spousal disapproval</h3>'
reason_nav=reason_nav.replace('<h3 style="font-size:17px;margin:24px 0 8px">Partner/spousal disapproval</h3>', '<div class="toc" style="margin-top:16px"><a href="#first-modern-destinations"><strong>First modern destinations</strong></a>'+''.join(f'<a href="#{c.lower()}-first-modern-destination">{c}</a>' for c in COUNTRIES)+'</div><h3 style="font-size:17px;margin:24px 0 8px">Partner/spousal disapproval</h3>')
page='<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Discontinuation and switching extensions</title><style>'+css+'</style></head><body><aside><div class="eyebrow">Separate analysis</div><h2>Discontinuation and switching extensions</h2>'+reason_nav+'<div role="tablist" aria-label="Country" aria-orientation="vertical">'+''.join(f'<button id="tab-{c.lower()}" role="tab" aria-controls="panel-{c.lower()}" aria-selected="false" data-country="{c.lower()}">{c}</button>' for c in COUNTRIES)+'</div><div class="toc">'+''.join(navigation)+'<div class="common"><a href="#methods">Definitions & methods</a></div></div></aside><main>'+reason_intro+alluvial_intro+endpoint_reason_intro+destination_intro+'<header id="partner-analysis"><div class="eyebrow">Separate partner/spousal analysis</div></header><header><div class="eyebrow">Ethiopia · Nigeria · DRC</div><h1>Modern-method discontinuation due to partner/spousal disapproval</h1><p class="lead">First-year probabilities and timing, pooled across modern methods and shown by method.</p><div class="definition"><strong>EC is excluded from all episode denominators.</strong> Partner/spousal disapproval is analyzed separately from potentially actionable causes. All other method-ending reasons remain competing events.</div></header>'+''.join(sections)+methodology+'<footer>Values are weighted estimates. Counts are unweighted unless explicitly stated. Percentages and intervals may differ slightly due to rounding.</footer></main><script>'+js+'</script></body></html>'
a.output.parent.mkdir(parents=True,exist_ok=True)
a.output.write_text(page,encoding='utf-8')
print(f'Built report: {len(page):,} characters; 3 country panels; all reconciliations passed.')
