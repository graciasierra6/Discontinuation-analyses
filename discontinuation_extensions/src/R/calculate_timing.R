#!/usr/bin/env Rscript
suppressPackageStartupMessages(library(jsonlite))
a <- commandArgs(TRUE)
stopifnot(length(a) == 4)
e <- readRDS(a[1])
e <- e[e$method_code %in% c(1,2,3,5,6,7,11,13,14,15,17,18,19,20) &
         e$entry < 12 & e$exposure > e$entry, ]
causes <- list('Method failure'=1, 'Wanted a more effective method'=7,
  'Bleeding changes'=15, 'Other side effects/health'=c(4,5),
  'Access/cost/convenience'=c(6,8,10))
S <- 1
F <- rep(0, length(causes))
P <- matrix(0, 13, length(causes))
for (t in 1:12) {
  r <- e$entry < t & e$exposure >= t
  event <- r & e$discontinued & e$exposure == t
  den <- sum(e$wt[r])
  F <- F + S * vapply(causes, function(codes)
    sum(e$wt[event & e$reason_code %in% codes])/den, 0)
  S <- S * (1 - sum(e$wt[event])/den)
  P[t+1, ] <- 100*F
}
out <- lapply(seq_along(causes), function(j) list(
  reason=names(causes)[j], months=c(3,6,9,12),
  probability=unname(P[c(4,7,10,13),j]),
  share_by_three=100*P[4,j]/P[13,j]))
write_json(list(country=a[3], survey=a[4],
  definition='National weighted competing-risk estimates, modern methods excluding EC. Nonactionable endings remain competing events.',
  eligible_episodes=nrow(e), rows=out),a[2],pretty=TRUE,auto_unbox=TRUE,digits=15)
