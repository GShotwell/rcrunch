context("API calling")

if (run.integration.tests) {
    test_that("crunchConfig has right structure", {
        expect_identical(getOption("httr_config")$encoding, "gzip")
        expect_identical(getOption("httr_config")$sslversion, "SSLVERSION_TLSv1_2")
    })

    test_that("crunchUserAgent", {
        expect_true(grepl("rcrunch", crunchUserAgent()))
        expect_true(grepl("rcrunch",
            getOption("httr_config")$httpheader["user-agent"]))
        expect_false(is.error(try(crunchUserAgent("anotherpackage/3.1.4"))))
        expect_true(grepl("anotherpackage", crunchUserAgent("anotherpackage")))
    })
    
    with(test.authentication, 
        test_that("API root can be fetched", {
            expect_false(is.error(try(getAPIroot())))
            urls <- getAPIroot()
            expect_true(is.shojiObject(urls))
        }))

    if (crunchAPIcanBeReached()) {
        test_that("API calls throw an error if user is not authenticated", {
            logout()
            expect_error(getAPIroot(), "401")
        })
    }
    
    test_that("Deprecated endpoints tell user to upgrade", {
        expect_error(crGET("http://httpbin.org/status/410"), 
            "The API resource at http://httpbin.org/status/410 has moved permanently. Please upgrade crunch to the latest version.")
    })
}