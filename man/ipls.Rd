% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/ipls.R
\name{ipls}
\alias{ipls}
\title{Variable selection with interval PLS}
\usage{
ipls(
  x,
  y,
  glob.ncomp = 10,
  center = TRUE,
  scale = FALSE,
  cv = list("ven", 10),
  exclcols = NULL,
  exclrows = NULL,
  int.ncomp = glob.ncomp,
  int.num = NULL,
  int.width = NULL,
  int.limits = NULL,
  int.niter = NULL,
  ncomp.selcrit = "min",
  method = "forward",
  x.test = NULL,
  y.test = NULL,
  silent = FALSE,
  full = FALSE,
  cv.scope = "local"
)
}
\arguments{
\item{x}{a matrix with predictor values.}

\item{y}{a vector with response values.}

\item{glob.ncomp}{maximum number of components for a global PLS model.}

\item{center}{logical, center or not the data values.}

\item{scale}{logical, standardize or not the data values.}

\item{cv}{cross-validation settings (see details).}

\item{exclcols}{columns of x to be excluded from calculations (numbers, names or vector with logical values).}

\item{exclrows}{rows to be excluded from calculations (numbers, names or vector with logical values).}

\item{int.ncomp}{maximum number of components for interval PLS models.}

\item{int.num}{number of intervals.}

\item{int.width}{width of intervals.}

\item{int.limits}{a two column matrix with manual intervals specification.}

\item{int.niter}{maximum number of iterations (if NULL it will be the smallest of two values: number of intervals and 30).}

\item{ncomp.selcrit}{criterion for selecting optimal number of components ('min' for minimum of RMSECV).}

\item{method}{iPLS method (\code{'forward'} or \code{'backward'}).}

\item{x.test}{matrix with predictors for test set (by default is NULL, if specified, is used instead of cv).}

\item{y.test}{matrix with responses for test set.}

\item{silent}{logical, show or not information about selection process.}

\item{full}{logical, if TRUE the procedure will continue even if no improvements is observed.}

\item{cv.scope}{scope for center/scale operations inside CV loop: 'global' — using globally computed mean and std
or 'local' — recompute new for each local calibration set.}
}
\value{
object of 'ipls' class with several fields, including:
   \item{var.selected}{a vector with indices of selected variables}
   \item{int.selected}{a vector with indices of selected intervals }
   \item{int.num}{total number of intervals}
   \item{int.width}{width of the intervals}
   \item{int.limits}{a matrix with limits for each interval}
   \item{int.stat}{a data frame with statistics for the selection algorithm}
   \item{glob.stat}{a data frame with statistics for the first step (individual intervals)}
   \item{gm}{global PLS model with all variables included}
   \item{om}{optimized PLS model with selected variables}
}
\description{
Applies iPLS algorithm to find variable intervals most important for
prediction.
}
\details{
The algorithm splits the predictors into several intervals and tries to find a combination
of the intervals, which gives best prediction performance. There are two selection methods:
"forward" when the intervals are successively included, and "backward" when the intervals
are successively excluded from a model. On the first step the algorithm finds the best
(forward) or the worst (backward) individual interval. Then it tests the others to find the
one which gives the best model in a combination with the already selected/excluded one. The
procedure continues until no improvements is observed or the maximum number of iteration
is reached.

There are several ways to specify the intervals. First of all either number of intervals
(\code{int.num}) or width of the intervals (\code{int.width}) can be provided. Alternatively
one can specify the limits (first and last variable number) of the intervals manually
with \code{int.limits}.

Cross-validation settings, \code{cv}, can be a number or a list. If \code{cv} is a number, it
will be used as a number of segments for random cross-validation (if \code{cv = 1}, full
cross-validation will be preformed). If it is a list, the following syntax can be used:
\code{cv = list('rand', nseg, nrep)} for random repeated cross-validation with \code{nseg}
segments and \code{nrep} repetitions or \code{cv = list('ven', nseg)} for systematic splits
to \code{nseg} segments ('venetian blinds').
}
\examples{
library(mdatools)

## forward selection for simdata

data(simdata)
Xc = simdata$spectra.c
yc = simdata$conc.c[, 3, drop = FALSE]

# run iPLS and show results
im = ipls(Xc, yc, int.ncomp = 5, int.num = 10, cv = 4, method = "forward")
summary(im)
plot(im)

# show "developing" of RMSECV during the algorithm execution
plotRMSE(im)

# plot predictions before and after selection
par(mfrow = c(1, 2))
plotPredictions(im$gm)
plotPredictions(im$om)

# show selected intervals on spectral plot
ind = im$var.selected
mspectrum = apply(Xc, 2, mean)
plot(simdata$wavelength, mspectrum, type = 'l', col = 'lightblue')
points(simdata$wavelength[ind], mspectrum[ind], pch = 16, col = 'blue')

}
\references{
[1] Lars Noergaard at al.  Interval partial least-squares regression (iPLS): a
comparative chemometric study with an example from near-infrared spectroscopy.
Appl.Spec. 2000; 54: 413-419
}
