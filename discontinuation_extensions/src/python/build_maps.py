"""Build a self-contained map report from parameterized aggregate inputs."""
import argparse
import json
import re
import unicodedata
from pathlib import Path

p=argparse.ArgumentParser()
p.add_argument('--build-dir',type=Path,required=True)
p.add_argument('--aggregation-dir',type=Path,required=True)
p.add_argument('--output',type=Path,required=True)
a=p.parse_args()
source_dir=Path(__file__).resolve().parent
def canonical(s):
    key=re.sub('[^a-z]','',unicodedata.normalize('NFKD',s).encode('ascii','ignore').decode().lower())
    return {'gambela':'gambella','federalcapitalterritory':'fct'}.get(key,key)
def wrap_name(s):
    if len(s)<=15:return [s]
    lines=['']
    for word in s.replace('-','- ').split():
        if len(lines[-1])+len(word)>15 and lines[-1]:lines.append(word)
        else:lines[-1]+=(' ' if lines[-1] else '')+word
    return [v.replace('- ','-') for v in lines]
def build_view(result_path,geometry_path,label,detail=False,grouping_note=''):
    d=json.loads(result_path.read_text())
    assert d['metadata']['validation']['status']=='pass'
    g=json.loads(geometry_path.read_text())
    rows={canonical(r['area']):r for r in d['summary'] if r['area_code'] and r['outcome']=='All reasons'}
    assert len(g['features'])==len(rows)
    features=[];all_points=[];display={}
    for f in g['features']:
        prop=f['properties'];name=prop['adm1_name'];key=canonical(name)
        if 'group_code' in prop:code=prop['group_code']
        else:assert key in rows;code=rows[key]['area_code']
        display[code]='FCT' if key=='fct' else 'Gambella' if key=='gambella' else name
        geom=f['geometry'];polys=[geom['coordinates']] if geom['type']=='Polygon' else geom['coordinates']
        for poly in polys:
            for ring in poly:all_points.extend(ring)
        features.append({'code':code,'polygons':polys,'center':[prop['label_x'],prop['label_y']],
                         'members':prop.get('member_names','')})
    assert len({f['code'] for f in features})==len(rows)
    for code in [0]+[f['code'] for f in features]:
        reasons=[r for r in d['reasons'] if r['area_code']==code]
        assert len(reasons)==9
        assert abs(sum(r['share_all'] for r in reasons)-100)<1e-8
        assert abs(sum(r['share_actionable'] for r in reasons if r['actionable'])-100)<1e-8
        for outcome in ['All reasons','Potentially actionable']:
            subset=[r for r in reasons if outcome=='All reasons' or r['actionable']]
            total=next(r for r in d['summary'] if r['area_code']==code and r['outcome']==outcome)
            assert abs(sum(r['probability_12'] for r in subset)-total['probability_12'])<1e-8
            assert sum(r['observed_endings'] for r in subset)==total['observed_target_endings']
    xmin=min(v[0] for v in all_points);xmax=max(v[0] for v in all_points)
    ymin=min(v[1] for v in all_points);ymax=max(v[1] for v in all_points)
    scale=min(680/(xmax-xmin),575/(ymax-ymin))
    ox=(800-(xmax-xmin)*scale)/2;oy=(660-(ymax-ymin)*scale)/2
    def xy(v):return [round(ox+(v[0]-xmin)*scale,2),round(oy+(ymax-v[1])*scale,2)]
    for f in features:
        rings=[]
        for poly in f.pop('polygons'):
            for ring in poly:rings.append('M'+'L'.join(f'{v[0]},{v[1]}' for v in map(xy,ring))+'Z')
        f['path']=''.join(rings);f['center']=xy(f['center']);f['name']=display[f['code']]
        f['label']=f['center'].copy();f['lines']=wrap_name(f['name'])
    for _ in range(130):
        moved=False
        for i,f in enumerate(features):
            w=max(map(len,f['lines']))*5.6+10;h=len(f['lines'])*13+6
            for q in features[:i]:
                qw=max(map(len,q['lines']))*5.6+10;qh=len(q['lines'])*13+6
                dx=f['label'][0]-q['label'][0];dy=f['label'][1]-q['label'][1]
                overx=(w+qw)/2-abs(dx);overy=(h+qh)/2-abs(dy)
                if overx>0 and overy>0:
                    sign=1 if dy>=0 else -1;shift=(overy+.3)*.51
                    f['label'][1]+=sign*shift;q['label'][1]-=sign*shift;moved=True
            f['label'][0]=min(795-w/2,max(5+w/2,f['label'][0]))
            f['label'][1]=min(647-h/2,max(13+h/2,f['label'][1]))
        if not moved:break
    for row in d['summary']:
        if row['area_code']:row['area']=display[row['area_code']]
    d.update(features=features,label=label,detail=detail,grouping_note=grouping_note)
    return d

data={
 'Ethiopia':{'views':{'overview':build_view(a.build_dir/'ethiopia/geography.json',a.build_dir/'boundaries/ETH_projected.geojson','14 regions/administrations',grouping_note='Regional view. Somali has fewer than 125 first-month exposures; Afar has 125–249.')}},
 'Nigeria':{'views':{
  'overview':build_view(a.aggregation_dir/'nigeria_zones6/geography.json',a.build_dir/'boundaries/NGA_zones_projected.geojson','Six geopolitical zones',grouping_note='Main overview: six geopolitical zones. Each zone pools its underlying modern-method episodes; state rates are not averaged.'),
  'detail':build_view(a.build_dir/'nigeria/geography.json',a.build_dir/'boundaries/NGA_projected.geojson','States + FCT · exploratory detail',True)}},
 'DRC':{'views':{
  'overview':build_view(a.aggregation_dir/'drc_geographic6/geography.json',a.build_dir/'boundaries/COD_groups_projected.geojson','Six broad geographic groups',grouping_note='Main overview: Kinshasa, Grand Ouest, Grand Kasaï, Grand Est, Grand Équateur and Grand Katanga. These are broad geographic groupings listed by the Interior Ministry, not current administrative provinces.'),
  'detail':build_view(a.build_dir/'drc/geography.json',a.build_dir/'boundaries/COD_projected.geojson','26 provinces · exploratory detail',True)}}
}
for country,c in data.items():
    if len(c['views'])<2:continue
    for outcome in ['All reasons','Potentially actionable']:
        national=[next(r for r in v['summary'] if r['area_code']==0 and r['outcome']==outcome) for v in c['views'].values()]
        assert abs(national[0]['probability_12']-national[1]['probability_12'])<1e-9
        assert national[0]['eligible_episodes']==national[1]['eligible_episodes']
css=(source_dir/'map_style.css').read_text()
js=(source_dir/'map_interactions.js').read_text().replace('__DATA__',json.dumps(data,separators=(',',':'),ensure_ascii=False).replace('</','<\\/'))
page=(source_dir/'map_template.html').read_text().replace('__STYLE__',css).replace('__SCRIPT__',js)
a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(page,encoding='utf-8')
print('Built five map views; geographic joins, national totals, reason probabilities and reason shares reconciled.')
