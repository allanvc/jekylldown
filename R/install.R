#' Install the Quarto CLI into jekylldown's isolated toolchain
#'
#' Downloads the latest Quarto release and unpacks it under
#' `tools::R_user_dir("jekylldown", "data")/quarto`, where [build_site()],
#' [serve_site()] and [check()] find it automatically. Nothing is installed
#' system-wide and no shell configuration is touched; uninstall by deleting
#' that directory. Only needed to write posts in Quarto (`.qmd`) --
#' see [new_post()].
#'
#' Linux x86_64 only for now (the platform jekylldown's isolated toolchain
#' targets); on other platforms install Quarto from
#' <https://quarto.org/docs/get-started/> and it is picked up from the
#' `PATH`.
#'
#' @param file Optional path to an already-downloaded
#'   `quarto-<version>-linux-amd64.tar.gz`, for offline installs. Default
#'   `NULL` downloads the latest release from GitHub.
#' @return The path to the installed `quarto` executable, invisibly.
#' @examples
#' \dontrun{
#' install_quarto()
#'
#' # offline: point at a tarball downloaded elsewhere
#' install_quarto(file = "~/Downloads/quarto-1.10.18-linux-amd64.tar.gz")
#' }
#' @export
install_quarto <- function(file = NULL) {
  sysinfo <- Sys.info()
  if (!identical(sysinfo[["sysname"]], "Linux") ||
      !identical(sysinfo[["machine"]], "x86_64")) {
    cli::cli_abort(c(
      "Automatic Quarto install currently supports Linux x86_64 only.",
      "i" = "Install it from {.url https://quarto.org/docs/get-started/};
             jekylldown finds it on the {.envvar PATH}."))
  }

  if (is.null(file)) {
    api <- "https://api.github.com/repos/quarto-dev/quarto-cli/releases/latest"
    release <- tryCatch(
      paste(readLines(api, warn = FALSE), collapse = "\n"),
      error = function(e) cli::cli_abort(
        "Could not reach GitHub to find the latest Quarto release
         ({conditionMessage(e)}). Download the Linux tarball yourself and
         pass it as {.arg file}."))
    url <- regmatches(release, regexpr(
      "https://[^\"]*linux-amd64[.]tar[.]gz", release))
    if (!length(url)) {
      cli::cli_abort("No Linux x86_64 tarball found in the latest release.")
    }
    file <- tempfile(fileext = ".tar.gz")
    on.exit(unlink(file), add = TRUE)
    cli::cli_alert_info("Downloading {.url {url}} ...")
    utils::download.file(url, file, mode = "wb", quiet = TRUE)
  }

  exdir <- tempfile("quarto-install-")
  on.exit(unlink(exdir, recursive = TRUE), add = TRUE)
  utils::untar(file, exdir = exdir)
  top <- list.dirs(exdir, recursive = FALSE)
  if (length(top) != 1) {
    cli::cli_abort("Unexpected tarball layout: expected one top-level
                    directory, found {length(top)}.")
  }

  dest <- file.path(jd_data_dir(), "quarto")
  if (dir.exists(dest)) unlink(dest, recursive = TRUE)
  fs::dir_create(dirname(dest))
  fs::dir_copy(top, dest)

  bin <- file.path(dest, "bin", "quarto")
  if (!file.exists(bin)) {
    cli::cli_abort("The tarball did not contain {.path bin/quarto}.")
  }
  version <- tryCatch(
    trimws(system2(bin, "--version", stdout = TRUE)[[1]]),
    error = function(e) "unknown")
  cli::cli_alert_success(
    "Quarto {version} installed at {.path {bin}} (delete
     {.path {dest}} to uninstall).")
  invisible(bin)
}
