Sys.setlocale("LC_COLLATE", "C") ## What CRAN does
set.seed(666)

## Our "test package" common harness code
## `try` added because of some devtools::document weirdness
try(source(system.file("crunch-test.R", package="crunch")))

skip_on_jenkins <- function (...) {
    if (nchar(Sys.getenv("JENKINS_HOME"))) {
        skip(...)
    }
}

fromJSON <- jsonlite::fromJSON
loadLogfile <- httpcache::loadLogfile
cacheLogSummary <- httpcache::cacheLogSummary
requestLogSummary <- httpcache::requestLogSummary
uncached <- httpcache::uncached
newDataset <- function (...) suppressMessages(crunch::newDataset(...))

## .onAttach stuff, for testthat to work right
## See other options in inst/crunch-test.R
options(
    warn=1,
    crunch.debug=FALSE,
    digits.secs=3,
    crunch.timeout=15, ## In case an import fails to start, don't wait forever
    # httpcache.log="",
    crunch.require.confirmation=TRUE,
    crunch.namekey.dataset="alias",
    crunch.namekey.array="alias"
)
httr::set_config(crunchConfig())

## Test serialize and deserialize
cereal <- function (x) fromJSON(toJSON(x), simplifyVector=FALSE)

newDatasetFromFixture <- function (filename) {
    ## Grab csv and json from "dataset-fixtures" and make a dataset
    m <- fromJSON(file.path("dataset-fixtures", paste0(filename, ".json")),
        simplifyVector=FALSE)
    return(suppressMessages(createWithMetadataAndFile(m,
        file.path("dataset-fixtures", paste0(filename, ".csv")))))
}

releaseAndReload <- function (dataset) {
    .releaseDataset(dataset)
    return(refresh(dataset))
}

## Data frames to make datasets with
df <- data.frame(v1=c(rep(NA_real_, 5), rnorm(15)),
                 v2=c(letters[1:15], rep(NA_character_, 5)),
                 v3=8:27,
                 v4=as.factor(LETTERS[2:3]),
                 v5=as.Date(0:19, origin="1955-11-05"),
                 v6=TRUE,
                 stringsAsFactors=FALSE)

mrdf <- data.frame(mr_1=c(1,0,1,NA_real_),
                   mr_2=c(0,0,1,NA_real_),
                   mr_3=c(0,0,1,NA_real_),
                   v4=as.factor(LETTERS[2:3]),
                   stringsAsFactors=FALSE)

testfile.csv <- "fake.csv"
testfile.df <- read.csv(testfile.csv)

mrdf.setup <- function (dataset, pattern="mr_", name=ifelse(is.null(selections),
                        "CA", "MR"), selections=NULL) {
    cast.these <- grep(pattern, names(dataset))
    dataset[cast.these] <- lapply(dataset[cast.these],
        castVariable, "categorical")
    if (is.null(selections)) {
        dataset[[name]] <- makeArray(dataset[cast.these], name=name)
    } else {
        dataset[[name]] <- makeMR(dataset[cast.these], name=name,
            selections=selections)
    }
    return(dataset)
}
