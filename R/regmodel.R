regmodel <- function(...) {
}

#' Cross-validation of a regression model
#'
#' @description
#' Does cross-validation of a regression model
#'
#' @param obj
#' a regression model (object of class \code{regmodel})
#' @param x
#' a matrix with x values (predictors from calibration set)
#' @param y
#' a matrix with y values (responses from calibration set)
#' @param cv
#' number of segments (if cv = 1, full cross-validation will be used)
#' @param cal.fun
#' reference to function for model calibration
#' @param pred.fun
#' reference to function for getting predicted y-values (see description)
#' @param cv.scope
#' scope for center/scale operations inside CV loop: 'global' — using globally computed mean and std
#' or 'local' — recompute new for each local calibration set.
#'
#' @return
#' object of class \code{plsres} with results of cross-validation
#'
#' Function `pred.fun` must take four agruments: autoscaled x-values, array with regression
#' coefficients, vectors for centring and scaling of y-values (if used). The function must
#' return predicted y-values in original units (unscaled and uncentered).
#'
#' @export
crossval.regmodel <- function(obj, x, y, cv, cal.fun, pred.fun, cv.scope = 'local') {

   # get attributes
   x.attrs <- attributes(x)
   y.attrs <- attributes(y)

   # remove excluded rows
   if (length(x.attrs$exclrows) > 0) {
      x <- x[-x.attrs$exclrows, , drop = FALSE]
      y <- y[-x.attrs$exclrows, , drop = FALSE]
      attr(x, "exclrows") <- NULL
      attr(y, "exclrows") <- NULL
   }

   # remove excluded columns
   if (length(x.attrs$exclcols) > 0) {
      x <- x[, -x.attrs$exclcols, drop = FALSE]
      attr(x, "exclcols") <- NULL
   }

   if (length(y.attrs$exclcols) > 0) {
      y <- y[, -y.attrs$exclcols, drop = FALSE]
      attr(y, "exclcols") <- NULL
   }

   y.ref <- y

   # get main data parameters
   nvar <- ncol(x)
   nobj <- nrow(x)
   nresp <- ncol(y)
   ncomp <- obj$ncomp

   # get matrix with indices for cv segments
   cv_ind <- crossval(cv, nobj = nobj, resp = y[, 1])
   nseg <- max(cv_ind)
   nrep <- ncol(cv_ind)

   # prepare arrays for results
   yp.cv <- array(0, dim = c(nobj, ncomp, nresp))
   jk.coeffs <- array(0, dim = c(nvar, ncomp, nresp, nseg))

   # define values for global scaling
   xcenter <- obj$xcenter
   ycenter <- obj$ycenter
   xscale  <- obj$xscale
   yscale  <- obj$yscale

   if (cv.scope == 'global') {
      x <- prep.autoscale(x, xcenter, xscale)
      y <- prep.autoscale(y, ycenter, yscale)
   }

   # loop over segments and repetitions
   for (ir in seq_len(nrep)) {
      for (is in seq_len(nseg)) {
         ind <- which(cv_ind[, ir] == is)
         if (length(ind) == 0) next

         xc <- x[-ind, , drop = FALSE]
         yc <- y[-ind, , drop = FALSE]
         xt <- x[ind, , drop = FALSE]

         # redefine values for local scaling if selected
         if (cv.scope != 'global') {
            xcenter <- if (obj$center) apply(xc, 2, mean) else rep(0, ncol(xc))
            ycenter <- if (obj$center) apply(yc, 2, mean) else rep(0, ncol(yc))
            xscale <- if (obj$scale)  apply(xc, 2, sd) else rep(1, ncol(xc))
            yscale <- if (obj$scale)  apply(yc, 2, sd) else rep(1, ncol(yc))

            xc <- prep.autoscale(xc, xcenter, xscale)
            yc <- prep.autoscale(yc, ycenter, yscale)
            xt <- prep.autoscale(xt, xcenter, xscale)
         }


         # create a model
         m.loc <- cal.fun(xc, yc, ncomp, method = obj$method, center = FALSE, scale = FALSE, cv = TRUE)

         if (m.loc$ncomp < ncomp) {
             stop(
                "Local model inside cross-validation can not be computed with the same number of\n",
                "components as used for calibration. Limit the number by using parameter 'ncomp'\n",
                "and run the code again.\n", call. = FALSE
             )
         }

         yp <- pred.fun(xt, m.loc$coeffs$values, ycenter = ycenter, yscale = yscale)


         # if any have NA values quit
         if (any(is.na(yp))) {
            stop("NA results produced during cross-validation.")
         }

         # save results
         yp.cv[ind, , ] <- yp.cv[ind, , , drop = FALSE] + yp
         jk.coeffs[, , , is] <- jk.coeffs[, , , is, drop = FALSE] +
            array(m.loc$coeffs$values, dim = c(dim(m.loc$coeffs$values), 1))
      }
   }

   # average results over repetitions
   yp.cv <- yp.cv / nrep
   jk.coeffs <- jk.coeffs / nrep

   # set up names
   dimnames(jk.coeffs) <- list(
      colnames(x),
      colnames(obj$coeffs$values),
      colnames(y),
      seq_len(nseg)
   )

   dimnames(yp.cv) <- list(
      rownames(x),
      colnames(obj$coeffs$values),
      colnames(y)
   )

   # make pls results and return
   return(list(y.pred = yp.cv, y.ref = y.ref, jk.coeffs = jk.coeffs))
}

#' Regression coefficients for PLS model'
#'
#' @description
#' Returns a matrix with regression coefficients for
#' the PLS model which can be applied to a data directly
#'
#' @param obj
#' a PLS model (object of class \code{pls})
#' @param ncomp
#' number of components to return the coefficients for
#' @param ny
#' if y is multivariate which variables you want to see the coefficients for
#' @param full
#' if TRUE the method also shows p-values and t-values as well as confidence intervals for the
#' coefficients (if available)
#' @param alpha
#' significance level for confidence intervals (a number between 0 and 1, e.g. 0.05)
#' @param ...
#' other parameters
#'
#' @details
#' The method recalculates the regression coefficients found by the PLS algorithm
#' taking into account centering and scaling of predictors and responses, so the
#' matrix with coefficients can be applied directly to original data (yp = Xb).
#'
#' If number of components is not specified, the optimal number, selected by user
#' or identified by a model will be used.
#'
#' If Jack-knifing method was used to get statistics for the coefficient the method
#' returns all statistics as well (p-value, t-value, confidence interval). In this case user
#' has to specified a number of y-variable (if there are many) to get the statistics and
#' the coefficients for. The confidence interval is computed for unstandardized coefficients.
#'
#' @return
#' A matrix  with regression coefficients and (optinally) statistics.
#'
#' @export
getRegcoeffs.regmodel <- function(obj, ncomp = obj$ncomp.selected, ny = 1, full = FALSE,
   alpha = 0.05, ...) {

   if (length(ncomp) != 1 || ncomp <= 0 || ncomp > obj$ncomp) {
      stop("Wrong value for number of components.")
   }

   attrs <- mda.getattr(obj$coeffs$values)
   out <- obj$coeffs$values[, ncomp, ny]

   # get center values and scale factors
   sx <- if (is.logical(obj$xscale)) rep(1, length(out)) else obj$xscale
   mx <- if (is.logical(obj$xcenter)) rep(0, length(out)) else obj$xcenter

   sy <- if (is.logical(obj$yscale)) rep(1, 1) else obj$yscale[ny]
   my <- if (is.logical(obj$ycenter)) rep(0, 1) else obj$ycenter[ny]


   # rescale coefficients and find intercept
   s <- sy / sx
   out <- matrix(c(my - sum(s * out * mx), s * out), ncol = 1)
   colnames(out) <- "Estimated"
   rownames(out) <- c("Intercept", dimnames(obj$coeffs$values)[[1]])


   if (full && !is.null(obj$coeffs$se)) {
      t  <- c(NA, obj$coeffs$t.values[, ncomp, ny])
      p  <- c(NA, obj$coeffs$p.values[, ncomp, ny])

      # standard error also needs to be rescaled and then new CI is computed
      se <- c(NA, obj$coeffs$se[, ncomp, ny] * s)
      ci <- cbind(out + qt(alpha/2, obj$coeffs$DoF) * se, out + qt(1 - alpha/2, obj$coeffs$DoF) * se)

      out <- cbind(out, se, t, p, ci)
      colnames(out)[2:6] <- c("Std. err.", "t-value", "p-value", paste0(round(c(alpha / 2, 1 - alpha / 2) * 100, 2), "%"))
   }

   attr(out, "exclrows") <- attrs$exclrows
   attr(out, "name") <- paste("Regression coefficients for ", obj$coeffs$respnames[ny])

   return(out)
}

#' Summary method for regression model object
#'
#' @description
#' Shows performance statistics for the model.
#'
#' @param object
#' a regression model (object of class \code{regmodel})
#' @param ncomp
#' number of components to show summary for
#' @param ny
#' which y variables to show the summary for (can be a vector)
#' @param res
#' list of results to show summary for
#' @param ...
#' other arguments
#'
#' @export
summary.regmodel <- function(object, ncomp = object$ncomp.selected,
   ny = seq_len(object$res$cal$nresp), res = object$res, ...) {

   if (length(ncomp) != 1 || ncomp < 1 || ncomp > dim(object$res[["cal"]]$y.pred)[2]) {
      stop("Wrong value for 'ncomp' parameter.")
   }

   cat("\nRegression model (class regmodel) summary\n")
   cat("\nPerformance and validation:\n")
   fprintf("Number of selected components: %d\n", ncomp)

   for (y in ny) {
      sum_data <- do.call(rbind, lapply(res, as.matrix, ny = y, ncomp = ncomp))
      rownames(sum_data) <- capitalize(names(res))

      sum_data[, "R2"] <- round(sum_data[, "R2"], 3)
      sum_data[, "RMSE"] <- mdaplot.formatValues(sum_data[, "RMSE"], round.only = TRUE)
      sum_data[, "Slope"] <- round(sum_data[, "Slope"], 3)
      sum_data[, "Bias"] <- round(sum_data[, "Bias"], 4)
      sum_data[, "RPD"] <- round(sum_data[, "RPD"], 1)

      attr(sum_data, "name") <- sprintf("\nResponse variable #%d (%s)", y, res[[1]]$respnames[y])
      mda.show(sum_data)
   }
   cat("\n")
}

#' Print method for PLS model object
#'
#' @description
#' Prints information about the object structure
#'
#' @param x
#' a regression model (object of class \code{regmodel})
#' @param ...
#' other arguments
#'
#' @export
print.regmodel <- function(x, ...) {
   cat("\nRegression model (class regmodel)\n")
   cat("\nCall:\n")
   print(x$call)
   cat("\nMajor fields:\n")
   cat("$ncomp - number of calculated components\n")
   cat("$ncomp.selected - number of selected components\n")
   cat("$coeffs - object (regcoeffs) with regression coefficients\n")
   cat("$res - list with result objects\n")
   cat("\nTry summary(model) and plot(model) to see the model performance.\n")
}


################################
#  Plotting methods            #
################################


#' RMSE plot for regression model
#'
#' @description
#' Shows plot with root mean squared error values vs. number of components for PLS model.
#'
#' @param obj
#' a regression model (object of class \code{regmodel})
#' @param ny
#' number of response variable to make the plot for (if y is multivariate)
#' @param type
#' type of the plot("b", "l" or "h")
#' @param labels
#' what to show as labels (vector or name, e.g. "names", "values", "indices")
#' @param xticks
#' vector with ticks for x-axis values
#' @param res
#' list with result objects
#' @param ylab
#' label for y-axis
#' @param ...
#' other plot parameters (see \code{mdaplotg} for details)
#'
#' @export
plotRMSE.regmodel <- function(obj, ny = 1, type = "b", labels = "values",
   xticks = seq_len(obj$ncomp), res = obj$res, ylab = paste0("RMSE (", obj$res$cal$respnames[ny], ")"), ...) {

   plot_data <- lapply(res, plotRMSE, ny = ny, show.plot = FALSE)
   mdaplotg(plot_data, type = type, xticks = xticks, labels = labels, ylab = ylab, ...)
}


#' RMSECV/RMSEC ratio plot for regression model
#'
#' @description
#' Shows plot with RMSECV/RMSEC values vs. RMSECV for each component.
#'
#' @param obj
#' a regression model (object of class \code{regmodel})
#' @param ny
#' number of response variable to make the plot for (if y is multivariate)
#' @param type
#' type of the plot (use only "b" or "l")
#' @param show.labels
#' logical, show or not labels for plot points
#' @param labels
#' vector with point labels (by default number of components)
#' @param main
#' main plot title
#' @param xlab
#' label for x-axis
#' @param ylab
#' label for y-axis
#' @param ...
#' other plot parameters (see \code{mdaplot} for details)
#'
#' @export
plotRMSERatio.regmodel <- function(obj, ny = 1, type = "b", show.labels = TRUE, labels = seq_len(obj$ncomp),
   main = paste0("RMSECV/RMSEC ratio (", obj$res$cal$respnames[ny], ")"),
   ylab = "RMSECV/RMSEC ratio",
   xlab = "RMSECV", ...) {

   stopifnot("Cross-validation results are not found." = !is.null(obj$res$cv))
   stopifnot("Parameter 'ny' has a wrong value." = (length(ny) == 1 && ny >= 1 && ny <= nrow(obj$res$cal$rmse)))

   plot_data <- matrix(obj$res$cv$rmse[ny, ] / obj$res$cal$rmse[ny, ], nrow = 1)
   attr(plot_data, "xaxis.values") <- obj$res$cv$rmse[ny, ]
   attr(plot_data, "xaxis.name") <- xlab

   mdaplot(plot_data, type = type, xlab = xlab, ylab = ylab, main = main, show.labels = show.labels,
   labels = labels, ...)
}


#' Predictions plot for regression model
#'
#' @description
#' Shows plot with predicted vs. reference (measured) y values for selected components.
#'
#' @param obj
#' a regression model (object of class \code{regmodel})
#' @param ncomp
#' how many components to use (if NULL - user selected optimal value will be used)
#' @param ny
#' number of response variable to make the plot for (if y is multivariate)
#' @param legend.position
#' position of legend on the plot (if shown)
#' @param show.line
#' logical, show or not line fit for the plot points
#' @param res
#' list with result objects
#' @param ...
#' other plot parameters (see \code{mdaplotg} for details)
#'
#' @export
plotPredictions.regmodel <- function(obj, ncomp = obj$ncomp.selected, ny = 1,
   legend.position = "topleft", show.line = TRUE, res = obj$res, ...) {

   if (length(ncomp) != 1 || ncomp < 1 || ncomp > dim(obj$res[["cal"]]$y.pred)[2]) {
      stop("Wrong value for 'ncomp' parameter.")
   }

   plot_data <- lapply(res, plotPredictions.regres, ny = ny, ncomp = ncomp, show.plot = FALSE)
   attr(plot_data[[1]], "name") <- sprintf("Predictions (ncomp = %d)", ncomp)
   plots <- mdaplotg(plot_data, type = "p", legend.position = legend.position, ...)

   if (show.line) {
      for (p in plots) {
         plotRegressionLine(p)
      }
   }
}

#' Y residuals plot for regression model
#'
#' @description
#' Shows plot with y residuals (predicted vs. reference values) for selected components.
#'
#' @param obj
#' a regression model (object of class \code{regmodel})
#' @param ncomp
#' how many components to use (if NULL - user selected optimal value will be used)
#' @param ny
#' number of response variable to make the plot for (if y is multivariate)
#' @param show.lines
#' allows to show the horizonta line at 0 level
#' @param res
#' list with result objects
#' @param ...
#' other plot parameters (see \code{mdaplotg} for details)
#'
#' @export
plotYResiduals.regmodel <- function(obj, ncomp = obj$ncomp.selected, ny = 1, show.lines = c(NA, 0),
   res = obj$res, ...) {

   if (length(ncomp) != 1 || ncomp < 1 || ncomp > dim(obj$res[["cal"]]$y.pred)[2]) {
      stop("Wrong value for 'ncomp' parameter.")
   }

   plot_data <- lapply(res, plotResiduals, ny = ny, ncomp = ncomp, show.plot = FALSE)
   attr(plot_data[[1]], "name") <- sprintf("Y-residuals (ncomp = %d)", ncomp)
   mdaplotg(plot_data, show.lines = show.lines, ...)
}

#' Regression coefficient plot for regression model
#'
#' @description
#' Shows plot with regression coefficient values. Is a proxy for \code{link{plot.regcoeffs}} method.
#'
#' @param obj
#' a regression model (object of class \code{regmodel})
#' @param ncomp
#' number of components to show the plot for
#' @param ...
#' other plot parameters (see \code{link{plot.regcoeffs}} for details)
#'
#' @export
plotRegcoeffs.regmodel <- function(obj, ncomp = obj$ncomp.selected, ...) {
   plot(obj$coeffs, ncomp = ncomp, ...)
}
