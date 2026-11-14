#!/usr/bin/env Rscript
suppressPackageStartupMessages({library(jsonlite);library(grid)})
args<-commandArgs(TRUE)
if(length(args)!=2L)stop('Supply checked endpoint-duration aggregates and output directory.')
d<-read_json(args[1],simplifyVector=FALSE)
stopifnot(all(unlist(d$validation)),all(unlist(d$endpoint_interruption_distribution$validation)))
g<-d$endpoint_interruption_distribution$groups
v<-vapply(g,function(x)x$share,0)
stopifnot(length(v)==7L,abs(sum(v)-100)<1e-8)
dir.create(args[2],recursive=TRUE,showWarnings=FALSE)
out<-file.path(args[2],paste0(d$country,'_single_endpoint_interruption_bar.svg'))
svglite::svglite(out,width=13.8,height=7.0)
grid.newpage()
pushViewport(viewport(x=unit(0,'in'),y=unit(7.0-8.7,'in'),
 width=unit(13.8,'in'),height=unit(8.7,'in'),just=c('left','bottom')))
navy<-'#153F5B';muted<-'#526777'
txt<-function(label,x,y,size=14,just='left',bold=FALSE,col=navy,family='Arial')
 grid.text(label,x=x,y=y,just=just,gp=gpar(fontfamily=family,fontsize=size,
 fontface=if(bold)'bold'else 'plain',col=col))
txt('Modern use a year after an actionable ending',.045,.95,24,bold=TRUE,family='Georgia')
txt(sprintf('%s · %s endings from %s women · Every history appears once · Total = 100%%',
 d$country,format(d$endings,big.mark=','),format(d$women,big.mark=',')),
 .045,.895,13,col=muted)
x0<-.055;w<-.89;y<-.66;h<-.10
modern_end<-x0+w*sum(v[1:4])/100
grid.lines(x=unit(c(x0,x0,modern_end,modern_end),'npc'),y=unit(c(.78,.794,.794,.78),'npc'),gp=gpar(col=navy,lwd=1.1))
txt(sprintf('%.1f%% in modern use at month 12',sum(v[1:4])),x0,.827,15)
colors<-c('#108B8D','#B7DBDC','#60AFB1','#DA9A25','#85909D','#D45A49','#8D73A8')
cursor<-x0;small_turn<-0L
for(i in seq_along(v)){
 width<-w*v[i]/100;center<-cursor+width/2
 grid.rect(x=center,y=y,width=width,height=h,gp=gpar(fill=colors[i],col=NA))
 if(i<=4){
  if(v[i]>=7)txt(sprintf('%.1f%%',v[i]),center,y,17.5,just='center',col='#111111')
  else{
   small_turn<-small_turn+1L;above<-small_turn%%2L==1L
   grid.lines(x=unit(c(center,center),'npc'),
    y=unit(if(above)c(y+h/2,.739)else c(y-h/2,.575),'npc'),gp=gpar(col=navy,lwd=.8))
   txt(sprintf('%.1f%%',v[i]),center,if(above).755 else .551,14,just='center',col='#111111')
  }
 }
 if(i%in%c(5,6))txt(sprintf('%.1f%%',v[i]),center,y,17.5,just='center',col='#111111')
 if(i==7){
  grid.lines(x=unit(c(center,center,.85),'npc'),y=unit(c(y-h/2,.575,.575),'npc'),gp=gpar(col=colors[i],lwd=.8))
  txt(sprintf('Traditional use %.1f%%',v[i]),.84,.575,12.5,just='right',col=colors[i])
 }
 cursor<-cursor+width
}
txt('Modern use at month 12, grouped by total months outside modern use',.045,.482,14.5)
modern_labels<-c('0 months\nModern in every recorded month',
 '1 month\nOutside modern use',
 '2–5 months\nOutside modern use',
 '6–11 months\nOutside modern use')
for(i in 1:4){
 x<-.055+(i-1)*.229
 grid.rect(x=x+.006,y=.429,width=.012,height=.018,gp=gpar(fill=colors[i],col=NA))
 txt(modern_labels[i],x+.023,.42,12)
}
txt('Other recorded states at month 12',.045,.315,14.5)
other_labels<-c('No method','Pregnancy/birth/termination','Traditional method')
for(i in 1:3){
 x<-.055+(i-1)*.31
 grid.rect(x=x+.006,y=.269,width=.012,height=.018,gp=gpar(fill=colors[i+4],col=NA))
 txt(other_labels[i],x+.023,.269,12.5)
}
popViewport()
dev.off()
s<-readLines(out,warn=FALSE);s<-gsub('svglite','endpoint-summary',s,fixed=TRUE)
writeLines(s,out)
cat('Rendered one mutually exclusive seven-category bar totaling 100 percent before rounding.\n')
