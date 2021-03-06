% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/glmmTMB.R
\name{getGrpVar}
\alias{getGrpVar}
\title{Get Grouping Variable}
\usage{
getGrpVar(x)
}
\arguments{
\item{x}{"flist" object; a data frame of factors including an \code{assign} attribute
matching columns to random effect terms}
}
\value{
character vector of grouping variables
}
\description{
Extract grouping variables for random effect terms from a factor list
}
\examples{
data(cbpp,package="lme4")
cbpp$obs <- factor(seq(nrow(cbpp)))
rt <- lme4::glFormula(cbind(size,incidence-size)~(1|herd)+(1|obs),
  data=cbpp,family=binomial)$reTrms
getGrpVar(rt$flist)
}
\keyword{internal}

