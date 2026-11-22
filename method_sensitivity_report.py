#!/usr/bin/env python3
"""Append reproducible permanent-method definitions and overall grouping checks."""
import argparse,csv
from pathlib import Path
from lxml import html,etree

def load(path):
    with path.open() as stream:return list(csv.DictReader(stream))

def table(parent,rows):
    wrap=etree.SubElement(parent,'div',{'class':'table-wrap analysis-table'})
    t=etree.SubElement(wrap,'table',{'class':'survey-table'})
    for i,row in enumerate(rows):
        tr=etree.SubElement(t,'tr')
        for j,v in enumerate(row):etree.SubElement(tr,'th'if i==0 or j==0 else'td').text=str(v)

def append(country,root,page):
    doc=html.parse(str(page));main=doc.xpath('//main')[0]
    for e in doc.xpath('//*[@id="permanent-method-planning"]|//*[@id="separate-condom-lam-sensitivity"]'):e.getparent().remove(e)
    s=etree.SubElement(main,'section',id='permanent-method-planning')
    etree.SubElement(s,'h2').text='Permanent methods in current-user planning'
    etree.SubElement(s,'p').text=('Female and male sterilization remain modern methods in baseline prevalence and observed subsequent use. Current permanent-method users receive no modeled stopping probability or additional retained-user gain. Historical landmarks and AFT stopping models use reversible original methods. Other modern in the planning tables therefore contains reversible methods only. These decisions do not change the observed DHS life-table definitions.')
    for node in doc.xpath('//*[@id="planning-validation"]//p'):
        if node.text and 'First-year planning uses all 8,682' in node.text:
            support=load(root/'output/survey_planning/planning_sample_support.csv')[0]
            node.text=node.text.replace('all 8,682 eligible non-EC modern-method episodes',f'{int(support["firstyear_reversible_episodes"]):,} eligible reversible non-EC episodes')
    etree.SubElement(s,'p').text=('In the modeled switching sensitivity, subsequent permanent-method use is a separate absorbing destination: it remains modern use through the endpoint. Because uptake is rare, its immediate and monthly entry probabilities are pooled across methods and causes. Observed calendar histories used for calibration are retained unchanged.')
    stock=load(root/'output/survey_planning/permanent_method_stock.csv')[0]
    table(s,[['Current method','Estimated baseline users','Stopping probability'],['Permanent methods',f'{float(stock["current_users"]):,.0f}','Not modeled']])
    if country=='Ethiopia':
        etree.SubElement(s,'p').text='Condoms and LAM remain grouped with the other reversible modern methods. Ethiopia has insufficient method-specific sample support for the additional separation check used in Nigeria and DRC.'
    else:
        d=root/'output/method_group_sensitivity';rows=load(d/'overall_comparison.csv')
        a=etree.SubElement(main,'section',id='separate-condom-lam-sensitivity')
        etree.SubElement(a,'h2').text='Appendix: condoms and LAM modeled separately'
        etree.SubElement(a,'p').text=('This overall sensitivity separates male condoms and reported LAM from the remaining reversible methods. Permanent users receive no modeled gain in either column. It uses potentially actionable endings only; partner/spousal disapproval is excluded. Both columns use the same observed baseline cohort and projected outcome-year women aged 15–49. The pp contribution is the same under each existing growth scenario.')
        names={'firstyear':'First-year exploratory','historical_gross':'Historical: all endings','aft_gross':'AFT: all endings','historical_net':'Historical: net of switching','aft_net':'AFT: net of observed switching'}
        values={(x['grouping'],x['approach']):x for x in rows}
        tab=[['Approach','Pooled reversible group: users','Condoms/LAM separate: users','Pooled: pp','Separate: pp']]
        for k,label in names.items():
            b=values['Other reversible pooled',k];n=values['Condoms and LAM separate',k]
            tab.append([label,f'{float(b["users"]):,.0f}',f'{float(n["users"]):,.0f}',f'{float(b["pp"]):.2f}',f'{float(n["pp"]):.2f}'])
        table(a,tab)
        etree.SubElement(a,'h3').text='Method-specific probabilities in the separated check'
        data=load(d/'separated_methods.csv');by={(x['method'],x['approach']):x for x in data}
        tab=[['Method','Current users','First-year actionable probability','Historical next-12-month probability','AFT next-12-month probability']]
        for m in ['Male condoms','LAM','Other modern']:
            x=by[m,'firstyear'];tab.append([('Other reversible methods†'if country=='Nigeria'else'Other reversible methods')if m=='Other modern'else m,f'{float(x["current_users"]):,.0f}',*[f'{100*float(by[m,k]["probability"]):.1f}%'for k in ['firstyear','historical_gross','aft_gross']]])
        table(a,tab)
        etree.SubElement(a,'p',{'class':'note'}).text=('The probability table shows the three groups replacing pooled Other modern. † Nigeria’s residual group is sparse. Historical duration cells combine adjacent duration groups until they contain at least 25 distinct episodes, where available. This is a pooling rule, not a guarantee of precision. The 61+ month group borrows experience at shorter observed durations. Switching fractions use at least 10 distinct actionable endings, otherwise they pool durations or methods. AFT models here combine the actionable causes into one event competing with all other endings; this matched pooled-versus-separated comparison is distinct from the main cause-specific allocation. DRC retains the pooled reversible AFT proxy for IUD in both columns. These are point-estimate checks; no new confidence intervals are shown.')
        etree.SubElement(a,'p',{'class':'note'}).text=('LAM is the reported calendar method. Recorded durations do not verify its postpartum, amenorrhea or breastfeeding eligibility criteria. Averted endings are interpreted as maintaining appropriate modern use, not extending LAM beyond eligibility. Sparse remaining-method and long-duration estimates require caution. Ethiopia has insufficient sample support for this separation check.')
    for link in doc.xpath('//aside//a[@href="#permanent-method-planning" or @href="#separate-condom-lam-sensitivity"]'):link.getparent().remove(link)
    aside=doc.xpath('//aside')[0]
    for sid,title in [('permanent-method-planning','Permanent methods in planning'),('separate-condom-lam-sensitivity','Condom and LAM sensitivity')]:
        if doc.xpath('//*[@id=$s]',s=sid):etree.SubElement(aside,'a',href='#'+sid).text=title
    page.write_bytes(html.tostring(doc,encoding='utf-8',doctype='<!doctype html>'))

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--country',required=True,choices=['Ethiopia','Nigeria','DRC']);p.add_argument('--project-root',type=Path,required=True);p.add_argument('--html',type=Path,required=True);a=p.parse_args();append(a.country,a.project_root,a.html)
