##' Extract info from formulas, reTrms, etc., format for TMB
##' @param formula conditional formula
##' @param ziformula zero-inflation formula
##' @param dispformula dispersion formula
##' @param mf call to model frame
##' @param fr frame
##' @param yobs observed y
##' @param offset offset
##' @param weights weights
##' @param family character
##' @param link character
##' @param ziPredictCode zero-inflation code
##' @param doPredict flag to enable sds of predictions
##' @keywords internal
##' @importFrom stats model.offset
mkTMBStruc <- function(formula, ziformula, dispformula,
                       mf, fr,
                       yobs, offset, weights,
                       family, link,
                       ziPredictCode="corrected",
                       doPredict=0) {

  condList  <- getXReTrms(formula, mf, fr)
  ziList    <- getXReTrms(ziformula, mf, fr)
  dispList  <- getXReTrms(dispformula, mf, fr, ranOK=FALSE, "dispersion")

  condReStruc <- with(condList, getReStruc(reTrms, ss))
  ziReStruc <- with(ziList, getReStruc(reTrms, ss))

  grpVar <- with(condList, getGrpVar(reTrms$flist))

  nobs <- nrow(fr)
  ## FIXME: deal with offset in formula
  ##if (grepl("offset", safeDeparse(formula)))
  ##  stop("Offsets within formulas not implemented. Use argument.")

  if (is.null(offset <- model.offset(fr)))
      offset <- rep(0,nobs)

  if (is.null(weights <- fr[["(weights)"]]))
    weights <- rep(1,nobs)

  data.tmb <- namedList(
    X = condList$X,
    Z = condList$Z,
    Xzi = ziList$X,
    Zzi = ziList$Z,
    Xd = dispList$X,
    ## Zdisp=dispList$Z,
    yobs,
    offset,
    weights,
    ## information about random effects structure
    terms = condReStruc,
    termszi = ziReStruc,
    family = .valid_family[family],
    link = .valid_link[link],
    ziPredictCode = .valid_zipredictcode[ziPredictCode],
    doPredict = doPredict
  )
  getVal <- function(obj, component)
    vapply(obj, function(x) x[[component]], numeric(1))

  beta_init <- as.numeric(link == "inverse") # 1 or 0

  parameters <- with(data.tmb,
                     list(
                       beta    = rep(beta_init, ncol(X)),
                       b       = rep(beta_init, ncol(Z)),
                       betazi  = rep(0, ncol(Xzi)),
                       bzi     = rep(0, ncol(Zzi)),
                       theta   = rep(0, sum(getVal(condReStruc,"blockNumTheta"))),
                       thetazi = rep(0, sum(getVal(ziReStruc,  "blockNumTheta"))),
                       betad   = rep(0, ncol(Xd))
                     ))
  randomArg <- c(if(ncol(data.tmb$Z)   > 0) "b",
                 if(ncol(data.tmb$Zzi) > 0) "bzi")
  namedList(data.tmb, parameters, randomArg, grpVar,
            condList, ziList, dispList, condReStruc, ziReStruc)
}

##' Create X and random effect terms from formula
##' @param formula current formula, containing both fixed & random effects
##' @param mf matched call
##' @param fr full model frame
##' @param ranOK random effects allowed here?
##' @param type label for model type
##' @return a list composed of
##' \item{X}{design matrix for fixed effects}
##' \item{Z}{design matrix for random effects}
##' \item{reTrms}{output from \code{\link{mkReTrms}} from \pkg{lme4}}
##'
##' @importFrom stats model.matrix contrasts
##' @importFrom methods new
##' @importFrom lme4 findbars nobars
getXReTrms <- function(formula, mf, fr, ranOK=TRUE, type="") {
    ## fixed-effects model matrix X -
    ## remove random effect parts from formula:
    fixedform <- formula
    RHSForm(fixedform) <- nobars(RHSForm(fixedform))

    nobs <- nrow(fr)
    ## check for empty fixed form

    if (identical(RHSForm(fixedform), ~  0) ||
        identical(RHSForm(fixedform), ~ -1)) {
        X <- NULL
    } else {
        mf$formula <- fixedform

        ## FIXME: make sure that predvars are captured appropriately

        ## attr(attr(fr,"terms"), "predvars.fixed") <-
        ##    attr(attr(fixedfr,"terms"), "predvars")

        ## FIXME: make model matrix sparse?? i.e. Matrix:::sparse.model.matrix()
        X <- model.matrix(fixedform, fr, contrasts)
        ## will be 0-column matrix if fixed formula is empty
        
        terms <- list(fixed=terms(fixedform))
    }
    ## ran-effects model frame (for predvars)
    ## important to COPY formula (and its environment)?
    ranform <- formula
    if (is.null(findbars(ranform))) {
        reTrms <- NULL
        Z <- new("dgCMatrix",Dim=c(as.integer(nobs),0L)) ## matrix(0, ncol=0, nrow=nobs)
        ss <- integer(0)
    } else {
        if (!ranOK) stop("no random effects allowed in ", type, " term")
        RHSForm(ranform) <- subbars(RHSForm(reOnly(formula)))

        mf$formula <- ranform
        reTrms <- mkReTrms(findbars(RHSForm(formula)), fr)

        ss <- splitForm(formula)
        ss <- unlist(ss$reTrmClasses)

        Z <- t(reTrms$Zt)   ## still sparse ...
    }

    ## if(is.null(rankX.chk <- control[["check.rankX"]]))
    ## rankX.chk <- eval(formals(lmerControl)[["check.rankX"]])[[1]]
    ## X <- chkRank.drop.cols(X, kind=rankX.chk, tol = 1e-7)
    ## if(is.null(scaleX.chk <- control[["check.scaleX"]]))
    ##     scaleX.chk <- eval(formals(lmerControl)[["check.scaleX"]])[[1]]
    ## X <- checkScaleX(X, kind=scaleX.chk)

    ## list(fr = fr, X = X, reTrms = reTrms, family = family, formula = formula,
    ##      wmsgs = c(Nlev = wmsgNlev, Zdims = wmsgZdims, Zrank = wmsgZrank))

    namedList(X, Z, reTrms, ss, terms)
}

##' Extract grouping variables for random effect terms from a factor list
##' @title Get Grouping Variable
##' @param x "flist" object; a data frame of factors including an \code{assign} attribute
##' matching columns to random effect terms
##' @return character vector of grouping variables
##' @keywords internal
##' @examples
##' data(cbpp,package="lme4")
##' cbpp$obs <- factor(seq(nrow(cbpp)))
##' rt <- lme4::glFormula(cbind(size,incidence-size)~(1|herd)+(1|obs),
##'   data=cbpp,family=binomial)$reTrms
##' getGrpVar(rt$flist)
##' @export
getGrpVar <- function(x)
{
  assign <- attr(x,"assign")
  names(x)[assign]
}

##' Calculate random effect structure
##' Calculates number of random effects, number of parameters,
##' blocksize and number of blocks.  Mostly for internal use.
##' @param reTrms random-effects terms list
##' @param ss a character string indicating a valid covariance structure. 
##' Must be one of \code{names(glmmTMB:::.valid_covstruct)};
##' default is to use an unstructured  variance-covariance
##' matrix (\code{"us"}) for all blocks).
##' @return a list
##' \item{blockNumTheta}{number of variance covariance parameters per term}
##' \item{blockSize}{size (dimension) of one block}
##' \item{blockReps}{number of times the blocks are repeated (levels)}
##' \item{covCode}{structure code}
##' @examples
##' data(sleepstudy, package="lme4")
##' rt <- lme4::lFormula(Reaction~Days+(1|Subject)+(0+Days|Subject),
##'                     sleepstudy)$reTrms
##' rt2 <- lme4::lFormula(Reaction~Days+(Days|Subject),
##'                     sleepstudy)$reTrms
##' getReStruc(rt)
##' @importFrom stats setNames
##' @export
getReStruc <- function(reTrms, ss=NULL) {

  ## information from ReTrms is contained in cnms, flist
  ## cnms: list of column-name vectors per term
  ## flist: data frame of grouping variables (factors)
  ##   'assign' attribute gives match between RE terms and factors
    if (is.null(reTrms)) {
        list()
    } else {
        ## Get info on sizes of RE components

        assign <- attr(reTrms$flist,"assign")
        nreps <- vapply(assign,
                          function(i) length(levels(reTrms$flist[[i]])),
                          0)
        blksize <- diff(reTrms$Gp) / nreps
        ## figure out number of parameters from block size + structure type

        if (is.null(ss)) {
            ss <- rep("us",length(blksize))
        }

        covCode <- .valid_covstruct[ss]

        parFun <- function(struc, blksize) {
            switch(as.character(struc),
                   "0" = blksize, # diag
                   "1" = blksize * (blksize+1) / 2, # us
                   "2" = blksize + 1, # cs
                   "3" = 2 ) # ar1
        }
        blockNumTheta <- mapply(parFun, covCode, blksize, SIMPLIFY=FALSE)

        ans <-
            lapply( seq_along(ss), function(i) {
                tmp <-
                    list(blockReps = nreps[i],
                         blockSize = blksize[i],
                         blockNumTheta = blockNumTheta[[i]],
                         blockCode = covCode[i]
                         )
                if(ss[i] == "ar1"){
                    ## FIXME: Find proper way to pass data associated
                    ## with factor levels (such as numeric 'times') to
                    ## struct. For now, assume levels correspond to
                    ## equally spaced time points.
                    if (any(reTrms$cnms[[i]][1] == "(Intercept)") )
                        warning("AR1 not meaningful with intercept")
                    tmp$times <- seq_along( reTrms$cnms[[i]] )
                }
                tmp
            })
        setNames(ans, names(reTrms$Ztlist))
    }
}

.noDispersionFamilies <- c("binomial", "poisson", "truncated_poisson")

usesDispersion <- function(x) {
    is.na(match(x, .noDispersionFamilies))
    ## !x %in% .noDispersionFamilies
}

## select only desired pieces from results of getXReTrms
stripReTrms <- function(xrt, whichReTrms = c("cnms","flist"), which="terms") {
  c(xrt$reTrms[whichReTrms],setNames(xrt[which],which))
}

##' Fit models with TMB
##' @param formula combined fixed and random effects formula, following lme4
##'     syntax
##' @param data data frame
##' @param family family (variance/link function) information; see \code{\link{family}} for
##' details.  As in \code{\link{glm}}, \code{family} can be specified as (1) a character string
##' referencing an existing family-construction function (e.g. \sQuote{"binomial"}); (2) a symbol referencing
##' such a function (\sQuote{binomial}); or (3) the output of such a function (\sQuote{binomial()}).
##' In addition, for families such as \code{betabinomial} that are special to \code{glmmTMB}, family
##' can be specified as (4) a list comprising the name of the distribution and the link function
##' (\sQuote{list(family="binomial",link="logit")}).
##' @param ziformula combined fixed and random effects formula for
##'     zero-inflation: the default \code{~0} specifies no zero-inflation.
##' The zero-inflation model uses a logit link.
##' @param dispformula combined fixed and random effects formula for dispersion:
##'     the default \code{NULL} specifies no extra dispersion.  The dispersion model
##' uses a log link.
##' @param weights weights, as in \code{glm}.
##' @param offset offset
##' @param se whether to return standard errors
##' @param verbose logical indicating if some progress indication should be printed to the console.
##' @param debug whether to return the preprocessed data and parameter objects,
##'     without fitting the model
##' @importFrom stats gaussian binomial poisson nlminb as.formula terms
##' @importFrom lme4 subbars findbars mkReTrms nobars
##' @importFrom Matrix t
##' @importFrom TMB MakeADFun sdreport
##' @details
##' \itemize{
##' \item binomial models with more than one trial (i.e., not binary/Bernoulli)
##' must be specified in the form \code{prob ~ ..., weights = N} rather than in
##' the more typical two-column matrix (\code{cbind(successes,failures)~...}) form.
##' \item in all cases \code{glmmTMB} returns maximum likelihood estimates - random effects variance-covariance matrices are not REML (so use \code{REML=FALSE} when comparing with \code{lme4::lmer}), and residual standard deviations (\code{\link{sigma}}) are not bias-corrected. Because the \code{\link{df.residual}} method for \code{glmmTMB} currently counts the dispersion parameter, one would need to multiply by \code{sqrt(nobs(fit)/(1+df.residual(fit)))} when comparing with \code{lm} ...
##' }
##' @useDynLib glmmTMB
##' @export
##' @examples
##' data(sleepstudy, package="lme4")
##' fm1 <- glmmTMB(Reaction ~ Days +     (1|Subject), sleepstudy)
##' fm2 <- glmmTMB(Reaction ~ Days + us  (1|Subject), sleepstudy)
##' fm3 <- glmmTMB(Reaction ~ Days + diag(1|Subject), sleepstudy)
glmmTMB <- function (
    formula,
    data = NULL,
    family = gaussian(),
    ziformula = ~0,
    dispformula= NULL,
    weights=NULL,
    offset=NULL,
    se=TRUE,
    verbose=FALSE,
    debug=FALSE
    )
{

    ## edited copy-paste from glFormula
    ## glFormula <- function(formula, data=NULL, family = gaussian,
    ##                       subset, weights, na.action, offset,
    ##                       contrasts = NULL, mustart, etastart,
    ##                       control = glmerControl(), ...) {

    ## FIXME: check for offsets in ziformula/dispformula, throw an error

    call <- mf <- mc <- match.call()

    if (is.character(family))
      family <- get(family, mode = "function", envir = parent.frame())
    if (is.function(family))
      family <- family()
    if (is.null(family$family)) {
      print(family)
      stop("'family' not recognized")
    }
    if (!all(c("family","link") %in% names(family)))
        stop("'family' must contain at least 'family' and 'link' components")
    ## FIXME: warning/message if 'family' doesn't contain 'variance' ?

    if (grepl("^quasi", family$family))
        stop('"quasi" families cannot be used in glmmTMB')

    ## extract family and link information from family object
    link <- family$link
    familyStr <- family$family

    if (is.null(dispformula)) {
      dispformula <- if (usesDispersion(familyStr)) ~1 else ~0
    }

    ## lme4 function for warning about unused arguments in ...
    ## ignoreArgs <- c("start","verbose","devFunOnly",
    ##   "optimizer", "control", "nAGQ")
    ## l... <- list(...)
    ## l... <- l...[!names(l...) %in% ignoreArgs]
    ## do.call(checkArgs, c(list("glmer"), l...))

    # substitute evaluated version
    ## FIXME: denv leftover from lme4, not defined yet

    call$formula <- mc$formula <- formula <-
        as.formula(formula, env = parent.frame())

    ## now work on evaluating model frame
    m <- match(c("data", "subset", "weights", "na.action", "offset"),
               names(mf), 0L)
    mf <- mf[c(1L, m)]
    mf$drop.unused.levels <- TRUE
    mf[[1]] <- as.name("model.frame")

    ## want the model frame to contain the union of all variables
    ## used in any of the terms
    ## combine all formulas

    formList <- list(formula, ziformula, dispformula)
    formList <- lapply(formList,
                   function(x) noSpecials(subbars(x), delete=FALSE))
                       ## substitute "|" by "+"; drop special
    combForm <- do.call(addForm,formList)
    environment(combForm) <- environment(formula)
    ## model.frame.default looks for these objects in the environment
    ## of the *formula* (see 'extras', which is anything passed in ...),
    ## so they have to be put there ...
    for (i in c("weights", "offset")) {
        if (!eval(bquote(missing(x=.(i)))))
            assign(i, get(i, parent.frame()), environment(combForm))
    }

    mf$formula <- combForm
    fr <- eval(mf, parent.frame())
    ## FIXME: throw an error *or* convert character to factor
    ## convert character vectors to factor (defensive)
    ## fr <- factorize(fr.form, fr, char.only = TRUE)
    ## store full, original formula & offset
    ## attr(fr,"formula") <- combForm  ## unnecessary?
    nobs <- nrow(fr)

    ## sanity checks (skipped!)
    ## wmsgNlev <- checkNlevels(reTrms$ flist, n=n, control, allow.n=TRUE)
    ## wmsgZdims <- checkZdims(reTrms$Ztlist, n=n, control, allow.n=TRUE)
    ## wmsgZrank <- checkZrank(reTrms$Zt, n=n, control, nonSmall=1e6, allow.n=TRUE)

    ## store info on location of response variable
    respCol <- attr(terms(fr), "response")
    names(respCol) <- names(fr)[respCol]

    ## extract response variable
    yobs <- fr[,respCol]

    err0 <- "response variable must be a numeric vector"
    if (!is.numeric(yobs) || is.matrix(yobs)) {
        if (family$family!="binomial") {
            stop(err0)
        } else {
            ## allow factor/logical values as in glm() (?)
            if (is.matrix(yobs)) {
                err <- c(err0,
                         " (use probability as response vector, ",
                         "and use 'weights' for sample size)")
                stop(err)
            }
            if (is.factor(yobs)) {
                ## ‘success’ is interpreted as the factor not
                ## having the first level (and hence usually of having the
                ## second level).
                yobs <- pmin(as.numeric(yobs)-1,1)
            } else {
                yobs <- as.numeric(yobs)
            }
        }
    }
    
    TMBStruc <- eval.parent(
        mkTMBStruc(formula, ziformula, dispformula,
                   mf, fr,
                   yobs, offset, weights,
                   familyStr, link))

    ## short-circuit
    if(debug) return(TMBStruc)

    obj <- with(TMBStruc,
                MakeADFun(data.tmb,
                     parameters,
                     random = randomArg,
                     profile = NULL, # TODO: Optionally "beta"
                     silent = !verbose,
                     DLL = "glmmTMB"))

    optTime <- system.time(fit <- with(obj, nlminb(start=par, objective=fn,
                                                   gradient=gr)))

    fitted <- NULL

    if (se) {
        sdr <- sdreport(obj)
        ## FIXME: assign original rownames to fitted?
    } else {
        sdr <- NULL
    }

    modelInfo <- with(TMBStruc,
                      namedList(nobs, respCol, grpVar, familyStr, family, link,
                                ## FIXME:apply condList -> cond earlier?
                                reTrms = lapply(list(cond=condList, zi=ziList),
                                                stripReTrms),
                                reStruc = namedList(condReStruc, ziReStruc),
                                allForm = namedList(combForm, formula,
                                                    ziformula, dispformula)))
    ## FIXME: are we including obj and frame or not?
    ##  may want model= argument as in lm() to exclude big stuff from the fit
    ## If we don't include obj we need to get the basic info out
    ##    and provide a way to regenerate it as necessary
    ## If we don't include frame, then we may have difficulty
    ##    with predict() in its current form
    structure(namedList(obj, fit, sdr, call, frame=fr, modelInfo,
                        fitted),
              class = "glmmTMB")
}

##' @importFrom stats AIC BIC
llikAIC <- function(object) {
    llik <- logLik(object)
    AICstats <- 
        c(AIC = AIC(llik), BIC = BIC(llik), logLik = c(llik),
          deviance = -2*llik, ## FIXME:
          df.resid = df.residual(object))
    list(logLik = llik, AICtab = AICstats)
}

## FIXME: export/import from lme4?
ngrps <- function(object, ...) UseMethod("ngrps")

ngrps.default <- function(object, ...) stop("Cannot extract the number of groups from this object")

ngrps.glmmTMB <- function(object, ...) {
    res <- lapply(object$modelInfo$reTrms,
           function(x) vapply(x$flist, nlevels, 1))
    ## FIXME: adjust reTrms names for consistency rather than hacking here
    names(res) <- gsub("List$","",names(res))
    return(res)
    
}

ngrps.factor <- function(object, ...) nlevels(object)


##' @importFrom stats pnorm
##' @method summary glmmTMB
##' @export
summary.glmmTMB <- function(object,...)
{
    if (length(list(...)) > 0) {
        ## FIXME: need testing code
        warning("additional arguments ignored")
    }
    ## figure out useSc
    sig <- sigma(object)

    famL <- family(object)

    mkCoeftab <- function(coefs,vcov) {
        p <- length(coefs)
        coefs <- cbind("Estimate" = coefs,
                       "Std. Error" = sqrt(diag(vcov)))
        if (p > 0) {
            coefs <- cbind(coefs, (cf3 <- coefs[,1]/coefs[,2]),
                           deparse.level = 0)
            ## statType <- if (useSc) "t" else "z"
            statType <- "z"
            ## ??? should we provide Wald p-values???
            coefs <- cbind(coefs, 2*pnorm(abs(cf3), lower.tail = FALSE))
            colnames(coefs)[3:4] <- c(paste(statType, "value"),
                                      paste0("Pr(>|",statType,"|)"))
        }
        coefs
    }

    ff <- fixef(object)
    vv <- vcov(object)
    coefs <- setNames(lapply(names(ff),
            function(nm) if (trivialFixef(names(ff[[nm]]),nm)) NULL else
                             mkCoeftab(ff[[nm]],vv[[nm]])),
                      names(ff))

    llAIC <- llikAIC(object)
                   
    ## FIXME: You can't count on object@re@flist,
    ##	      nor compute VarCorr() unless is(re, "reTrms"):
    varcor <- VarCorr(object)
					# use S3 class for now
    structure(list(logLik = llAIC[["logLik"]],
                   family = famL$fami, link = famL$link,
		   ngrps = ngrps(object),
                   nobs = nobs(object),
		   coefficients = coefs, sigma = sig,
		   vcov = vcov(object),
		   varcor = varcor, # and use formatVC(.) for printing.
		   AICtab = llAIC[["AICtab"]], call = object$call
                   ## residuals = residuals(object,"pearson",scaled = TRUE),
		   ## fitMsgs = .merMod.msgs(object),
                   ## optinfo = object@optinfo
		   ), class = "summary.glmmTMB")
               
}

## copied from lme4:::print.summary.merMod (makes use of
##' @importFrom lme4 .prt.family .prt.call .prt.resids .prt.VC .prt.grps
##' @importFrom stats printCoefmat
##' @method print summary.glmmTMB
##' @export
print.summary.glmmTMB <- function(x, digits = max(3, getOption("digits") - 3),
                                 signif.stars = getOption("show.signif.stars"),
                                 ranef.comp = c("Variance", "Std.Dev."),
                                 show.resids = FALSE, ...)
{
    .prt.family(x)
    .prt.call(x$call); cat("\n")
    .prt.aictab(x$AICtab); cat("\n")
    if (show.resids)
        .prt.resids(x$residuals, digits = digits)

    if (any(whichRE <- !sapply(x$varcor,is.null))) {
        cat("Random effects:\n")
        for (nn in names(x$varcor[whichRE])) {
            cat("\n",cNames[[nn]],":\n",sep="")
            ## lme4:::.prt.VC is not quite what we want here
            print(formatVC(x$varcor[[nn]],
                           digits = digits,
                           comp = ranef.comp),
                  quote=FALSE, digits=digits)
            ## FIXME: redundant nobs output
            .prt.grps(x$ngrps[[nn]],nobs=x$nobs)
        }
    }

    for (nn in names(x$coefficients)) {
        cc <- x$coefficients[[nn]]
        p <- length(cc)
        if (p > 0) {
            cat("\n",cNames[[nn]],":\n",sep="")
            printCoefmat(cc, zap.ind = 3, #, tst.ind = 4
                         digits = digits, signif.stars = signif.stars)
        } ## if (p>0)
    }

    invisible(x)
}## print.summary.glmmTMB


