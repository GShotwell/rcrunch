##' Crunch xtabs: Crosstab and otherwise aggregate variables in a Crunch Dataset
##'
##' Create a contingency table or other aggregation from cross-classifying
##' variables in a CrunchDataset.
##'
##' @param formula an object of class 'formula' object with the
##' cross-classifying variables, separated by '+', on the right hand side.
##' Compare to \code{\link[stats]{xtabs}}.
##' @param data an object of class \code{CrunchDataset}
##' @param weight a CrunchVariable that has been designated as a potential
##' weight variable for \code{data}, or \code{NULL} for unweighted results.
##' Default is the currently applied weight, \code{\link{weight}(data)}.
##' @param useNA whether to include missing values in tabular results. See
##' \code{\link[base]{table}}.
##' @return an object of class \code{CrunchCube}
##' @export
crtabs <- function (formula, data, weight=crunch::weight(data), 
                     useNA=c("no", "ifany", "always")) {
    ## Validate "formula"
    if (missing(formula)) {
        halt("Must provide a formula")
    }
    formula <- try(as.formula(formula), silent=TRUE)
    if (is.error(formula)) {
        halt(dQuote("formula"), " is not a valid formula")
    }
    
    ## Parse the formula
    f <- terms(as.formula(formula), allowDotAsName=TRUE) ## To catch "."
    f.vars <- attr(f, "variables")
    all.f.vars <- all.vars(f.vars)
    
    ## More input validation
    if ("." %in% all.f.vars) {
        halt("crtabs does not support ", dQuote("."), " in formula")
    }
    if (!length(all.f.vars)) {
        halt("Must supply one or more variables")
    }
    
    if (missing(data) || !is.dataset(data)) {
        halt(dQuote("data"), " must be a Dataset")
    }
    
    ## Find variables either in 'data' or in the calling environment
    where <- parent.frame()
    vars <- lapply(all.f.vars, 
        function (x) data[[x]] %||% safeGet(x, envir=where))
    names(vars) <- all.f.vars
    
    ## Validate what we got
    notfound <- vapply(vars, is.null, logical(1))
    if (any(notfound)) {
        badvars <- all.f.vars[notfound]
        halt(serialPaste(dQuote(badvars)), 
            ifelse(length(badvars) > 1, " are", " is"),
            " not found in ", dQuote("data"))
    }
    
    ## Evaluate the formula's terms in order to catch derived expressions
    vars <- registerCubeFunctions(vars)
    v.call <- do.call(substitute, list(expr=f.vars, env=vars))
    vars <- eval(v.call)
    
    ## Construct the "measures", either from the formula or default "count"
    resp <- attr(f, "response")
    if (resp) {
        measures <- lapply(vars[resp], absolute.zcl)
        vars <- vars[-resp]
    } else {
        measures <- list(count=zfunc("cube_count"))
    }
    
    ## Handle "weight"
    force(weight)
    if (is.variable(weight)) {
        weight <- self(weight)
        ## Should confirm that weight is in weight_variables. Server 400s
        ## if it isn't.
    } else {
        weight <- NULL
    }
    
    ## Construct the ZCL query
    query <- list(dimensions=varsToCubeDimensions(vars),
        measures=measures, weight=weight)
    
    ## Final validations
    badmeasures <- vapply(query$measures, Negate(isCubeAggregation), logical(1))
    if (any(badmeasures)) {
        halt("Left side of formula must be a valid aggregation")
    }
    baddimensions <- vapply(query$dimensions, isCubeAggregation, logical(1))
    if (any(baddimensions)) {
        halt("Right side of formula cannot contain aggregation functions")
    }
    
    ## One last munge
    names(query$measures) <- vapply(query$measures, function (m) {
        sub("^cube_", "", m[["function"]])
    }, character(1))
    
    ## Go GET it!
    cube_url <- shojiURL(data, "views", "cube")
    return(CrunchCube(crGET(cube_url, query=list(query=toJSON(query))),
        useNA=match.arg(useNA)))
}

safeGet <- function (x, ..., ifnot=NULL) {
    ## "get" with a default
    out <- try(get(x, ...), silent=TRUE)
    if (is.error(out)) out <- ifnot
    return(out)
}

registerCubeFunctions <- function (vars) {
    ## Given a list of variables, add to it "cube functions", to substitute()
    ## in. A better approach, which would avoid potential name collisions, would
    ## probably be to have vars be an environment inside of another environment
    ## that has the cube functions.
    
    funcs <- list(
        mean=function (x) zfunc("cube_mean", x),
        min=function (x) zfunc("cube_min", x),
        max=function (x) zfunc("cube_max", x),
        # median=function (x) zfunc("cube_quantile", x, .5),
        # quantile=function (x, q) zfunc("cube_quantile", x, q),
        sd=function (x) zfunc("cube_stddev", x),
        sum=function (x) zfunc("cube_sum", x)
    )
    
    overlap <- intersect(names(vars), names(funcs))
    if (length(overlap)) {
        halt("Cannot evaluate a cube with reserved name", 
            ifelse(length(overlap) > 1, "s", ""), ": ",
            serialPaste(dQuote(overlap)))
    }
    return(c(vars, funcs))
}

isCubeAggregation <- function (x) {
    "function" %in% names(x) && grepl("^cube_", x[["function"]])
}

varsToCubeDimensions <- function (vars) {
    ## Given variables, construct the appropriate ZCL to get a cube with them
    ## as dimensions
    dimensions <- unlist(lapply(vars, function (x) {
        v <- absolute.zcl(x)
        if (is.MR(x)) {
            ## Multiple response gets "selected_array" and "each"
            return(list(zfunc("selected_array", v),
                list(each=self(x))))
        } else if (is.CA(x)) {
            ## Categorical array gets the var reference and "each"
            ## Put "each" first so that the rows, not columns, are subvars
            return(list(list(each=self(x)),
                v))
        } else {
            ## Just the var ref, but nest in a list so we can unlist below to
            ## flatten
            return(list(v))
        }
    }), recursive=FALSE)
    names(dimensions) <- NULL
    return(dimensions)
}