#' Install Ruby and Jekyll into jekylldown's isolated toolchain (Windows)
#'
#' Windows has no system package manager to get Ruby from, so this
#' function does the whole setup: it downloads the portable RubyInstaller
#' archive (a `.7z`, no graphical installer, no registry entries), unpacks
#' it under `tools::R_user_dir("jekylldown", "data")/ruby`, and installs
#' the **jekyll** and **bundler** gems into the package's isolated gem
#' directory. Nothing is installed system-wide and no shell configuration
#' is touched; uninstall by deleting the data directory. [build_site()],
#' [serve_site()] and [check()] find this toolchain automatically.
#'
#' Unpacking the `.7z` archive needs the \pkg{archive} package
#' (`install.packages("archive")`).
#'
#' The MSYS2 build tools are set up by default (`devkit = TRUE`, via
#' RubyInstaller's `ridk install`): Jekyll depends on the
#' \samp{eventmachine} gem, which has no precompiled binary for current
#' Rubies and must be compiled at install time. `devkit = FALSE` skips
#' that large download for the rare setups that already have a working
#' MSYS2 toolchain.
#'
#' On Linux and macOS install Ruby with your package manager instead (see
#' the README's prerequisites); jekylldown picks it up from the `PATH`.
#'
#' @param file Optional path to an already-downloaded
#'   `rubyinstaller-<version>-x64.7z`, for offline installs. Default
#'   `NULL` downloads the latest release from GitHub. (The release
#'   lookup uses the GitHub API; on networks where `api.github.com` is
#'   unreachable, a known-good pinned release is downloaded directly
#'   from `github.com` instead.)
#' @param devkit Set up the MSYS2 toolchain (via `ridk install`), which
#'   gems with C extensions -- including Jekyll's own dependency
#'   \samp{eventmachine} -- need at install time? Default `TRUE`.
#' @param version Optional RubyInstaller release to install instead of
#'   the latest, as tagged upstream (e.g. `"3.3.7-1"`).
#' @return The path to the installed `jekyll` command, invisibly.
#' @examples
#' \dontrun{
#' install_ruby()
#'
#' # offline: point at an archive downloaded elsewhere
#' install_ruby(file = "C:/Users/me/Downloads/rubyinstaller-3.3.7-1-x64.7z")
#' }
#' @export
install_ruby <- function(file = NULL, devkit = TRUE, version = NULL) {
  if (!identical(.Platform$OS.type, "windows")) {
    cli::cli_abort(c(
      "Automatic Ruby install is for Windows, which has no package
       manager to get Ruby from.",
      "i" = "On Linux/macOS install Ruby (>= 3.0) with your package
             manager -- see the README's prerequisites section;
             jekylldown finds it on the {.envvar PATH}."))
  }
  if (!requireNamespace("archive", quietly = TRUE)) {
    cli::cli_abort(c(
      "The {.pkg archive} package is needed to unpack the RubyInstaller
       {.file .7z} archive.",
      "i" = "Run {.code install.packages(\"archive\")} and call
             {.fn install_ruby} again."))
  }

  if (is.null(file)) {
    url <- if (!is.null(version)) {
      ri_pinned_url(version)
    } else {
      ri_latest_url()
    }
    file <- tempfile(fileext = ".7z")
    on.exit(unlink(file), add = TRUE)
    cli::cli_alert_info("Downloading {.url {url}} ...")
    status <- tryCatch(
      utils::download.file(url, file, mode = "wb", quiet = TRUE),
      error = function(e) conditionMessage(e))
    if (!identical(status, 0L)) {
      cli::cli_abort(c(
        "Could not download {.url {url}}
         ({if (is.character(status)) status else paste('status', status)}).",
        "i" = "Behind a proxy or firewall? Download the {.file .7z}
               archive from {.url https://rubyinstaller.org/downloads/}
               in your browser and pass its path as {.arg file}."))
    }
  }

  exdir <- tempfile("ruby-install-")
  on.exit(unlink(exdir, recursive = TRUE), add = TRUE)
  cli::cli_alert_info("Unpacking (this can take a few minutes) ...")
  archive::archive_extract(file, dir = exdir)
  top <- list.dirs(exdir, recursive = FALSE)
  if (length(top) != 1) {
    cli::cli_abort("Unexpected archive layout: expected one top-level
                    directory, found {length(top)}.")
  }

  dest <- file.path(jd_data_dir(), "ruby")
  if (dir.exists(dest)) unlink(dest, recursive = TRUE)
  fs::dir_create(dirname(dest))
  fs::dir_copy(top, dest)

  if (devkit) {
    ridk <- find_cmd("ridk")
    if (is.null(ridk)) {
      cli::cli_abort("The archive did not contain the {.code ridk} command
                      needed to set up the MSYS2 toolchain.")
    }
    cli::cli_alert_info("Installing the MSYS2 build toolchain (a large
                         extra download) ...")
    sc <- shell_cmd(ridk, c("install", "1", "2", "3"))
    res <- processx::run(sc$cmd, sc$args, env = c("current", jd_env()),
                         echo = TRUE, error_on_status = FALSE)
    if (res$status != 0) {
      cli::cli_abort("{.code ridk install} failed (exit status
                      {res$status}).")
    }
  }

  gem <- find_cmd("gem")
  if (is.null(gem)) {
    cli::cli_abort("The archive did not contain a {.code gem} command
                    under {.path bin/}.")
  }
  cli::cli_alert_info("Installing the {.pkg jekyll} and {.pkg bundler}
                       gems ...")
  sc <- shell_cmd(gem, c("install", "--no-document", "jekyll", "bundler"))
  res <- processx::run(sc$cmd, sc$args, env = c("current", jd_env()),
                       echo = TRUE, error_on_status = FALSE)
  if (res$status != 0) {
    cli::cli_abort(c(
      "{.code gem install jekyll bundler} failed (exit status
       {res$status}).",
      if (!devkit) c("i" = "If the error mentions development tools or a
                            compiler, re-run with
                            {.code install_ruby(devkit = TRUE)}.")))
  }

  version <- cmd_version("jekyll")
  if (is.null(version)) version <- ""
  cli::cli_alert_success(
    "Ruby and Jekyll {version} installed under {.path {dest}}
     (delete {.path {jd_data_dir()}} to uninstall).")
  invisible(find_cmd("jekyll"))
}

# A recent RubyInstaller release known to work with jekylldown's themes,
# used when the GitHub API is unreachable (some networks resolve
# github.com, where the archives live, but block api.github.com).
ri_fallback_version <- "3.3.7-1"

ri_pinned_url <- function(version) {
  sprintf(paste0("https://github.com/oneclick/rubyinstaller2/releases",
                 "/download/RubyInstaller-%s/rubyinstaller-%s-x64.7z"),
          version, version)
}

# The newest release's archive URL. Tried in order: the GitHub API;
# the releases/latest page on github.com itself (some networks resolve
# github.com, where the archives also live, but not api.github.com);
# the pinned known-good release.
ri_latest_url <- function() {
  fetch <- function(url) tryCatch(
    suppressWarnings(paste(readLines(url, warn = FALSE), collapse = "\n")),
    error = function(e) NULL)

  api <- fetch(
    "https://api.github.com/repos/oneclick/rubyinstaller2/releases/latest")
  if (!is.null(api)) return(ri_pick_asset(api))

  html <- fetch(
    "https://github.com/oneclick/rubyinstaller2/releases/latest")
  version <- if (!is.null(html)) ri_tag_version(html)
  if (length(version)) return(ri_pinned_url(version))

  cli::cli_warn(
    "Could not reach GitHub to find the latest RubyInstaller release;
     using the known-good RubyInstaller {ri_fallback_version} instead
     (pass {.arg version} to choose another one).")
  ri_pinned_url(ri_fallback_version)
}

# "RubyInstaller-4.0.6-1" somewhere in the releases/latest page ->
# "4.0.6-1"; character(0) when no tag is found.
ri_tag_version <- function(html) {
  tag <- regmatches(html, regexpr("RubyInstaller-[0-9][0-9.]*-[0-9]+", html))
  sub("^RubyInstaller-", "", tag)
}

# Pick the portable .7z asset out of a rubyinstaller2 release JSON.
# Only the plain archive exists as .7z upstream (the devkit variant
# ships as an .exe installer only) -- the MSYS2 toolchain is added
# afterwards with `ridk install`, see install_ruby(devkit = TRUE).
ri_pick_asset <- function(release_json) {
  pat <- "https://[^\"]*/rubyinstaller-[0-9][^\"]*-x64[.]7z"
  url <- regmatches(release_json, regexpr(pat, release_json))
  if (!length(url)) {
    cli::cli_abort(
      "No matching {.file .7z} archive in the latest RubyInstaller
       release. Download one from
       {.url https://rubyinstaller.org/downloads/} and pass it as
       {.arg file}.")
  }
  url
}

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
