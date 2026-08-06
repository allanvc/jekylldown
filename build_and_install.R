#!/usr/bin/env Rscript

# build_and_install.R -- full development cycle for jekylldown.
#
# Run from the package root:
#   Rscript build_and_install.R              # everything
#   Rscript build_and_install.R --no-check   # skip R CMD check (faster)
#   Rscript build_and_install.R --no-tests   # skip testthat
#
# Steps: document (roxygen2) -> render README -> tests -> R CMD check ->
# build tarball (with vignettes) -> remove installed old versions + old
# tarballs -> install -> sanity check in a fresh R session.
#
# The build happens BEFORE the uninstall on purpose: building vignettes
# takes ~30s, and doing it after removing the package would leave a long
# window with no installed jekylldown (any other R session asking for the
# package or its vignettes during that window would fail).

args      <- commandArgs(trailingOnly = TRUE)
run_tests <- !"--no-tests" %in% args
run_check <- !"--no-check" %in% args

if (!file.exists("DESCRIPTION")) {
  stop("Run this script from the package root (DESCRIPTION not found in ",
       getwd(), ")", call. = FALSE)
}
desc    <- read.dcf("DESCRIPTION", fields = c("Package", "Version"))
pkg     <- unname(desc[1, "Package"])
version <- unname(desc[1, "Version"])
cli::cli_h1("{pkg} {version} -- build & install")

# 1. Documentation (NAMESPACE + man/) ------------------------------------
cli::cli_h2("Documenting (roxygen2)")
devtools::document(quiet = TRUE)

# 2. README --------------------------------------------------------------
if (file.exists("README.Rmd")) {
  cli::cli_h2("Rendering README.Rmd")
  rmarkdown::render("README.Rmd", quiet = TRUE)
  unlink("README.html")  # github_document leaves a preview file behind
}

# 3. Tests ----------------------------------------------------------------
if (run_tests) {
  cli::cli_h2("Running tests")
  res <- as.data.frame(devtools::test(stop_on_failure = TRUE))
  cli::cli_alert_success("{sum(res$passed)} test{?s} passed.")
} else {
  cli::cli_alert_warning("Tests skipped (--no-tests).")
}

# 4. R CMD check (includes building the vignettes) ------------------------
if (run_check) {
  cli::cli_h2("R CMD check")
  devtools::check(args = "--no-manual", error_on = "warning", quiet = TRUE)
} else {
  cli::cli_alert_warning("Check skipped (--no-check).")
}

# 5. Build the new tarball (vignettes included) ---------------------------
cli::cli_h2("Building source tarball")
tarball_dir <- dirname(normalizePath("."))
old_tars <- list.files(tarball_dir, sprintf("^%s_.*\\.tar\\.gz$", pkg),
                       full.names = TRUE)
if (length(old_tars)) {
  cli::cli_alert_info("Deleting old tarball{?s}: {.file {basename(old_tars)}}")
  unlink(old_tars)
}
tarball <- devtools::build(path = tarball_dir, quiet = TRUE)
cli::cli_alert_success("Built {.file {basename(tarball)}}")

# 6. Swap installations (uninstall -> install, back to back) --------------
cli::cli_h2("Installing")
old_libs <- dirname(find.package(pkg, lib.loc = .libPaths(), quiet = TRUE))
for (lib in unique(old_libs)) {
  cli::cli_alert_info("Uninstalling old copy from {.path {lib}}")
  remove.packages(pkg, lib = lib)
}
install.packages(tarball, repos = NULL, type = "source", quiet = TRUE)

# 7. Sanity check in a fresh R session ------------------------------------
cli::cli_h2("Sanity check (fresh R session)")
code <- sprintf(
  "cat(as.character(packageVersion('%s')), '|',
       nrow(vignette(package = '%s')$results), 'vignette(s)')", pkg, pkg)
out <- system2(file.path(R.home("bin"), "Rscript"), c("-e", shQuote(code)),
               stdout = TRUE, stderr = TRUE)
status <- attr(out, "status")
if (!is.null(status) && status != 0) {
  stop("Installed package failed to load:\n", paste(out, collapse = "\n"),
       call. = FALSE)
}
cli::cli_alert_success("Installed and loadable: {pkg} {out}")
cli::cli_alert_info(
  'Try: vignette("migrate-blogdown-to-al-folio", package = "{pkg}")')
