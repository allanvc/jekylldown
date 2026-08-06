#' Diagnose the Jekyll toolchain
#'
#' Prints a situation report on everything `jekylldown` needs: Ruby, gem,
#' bundler and jekyll executables (looking first in the package's isolated
#' `GEM_HOME`, then on the `PATH`), plus the current site, if any.
#'
#' @param dir Directory in (or under) a Jekyll site. Defaults to the working
#'   directory; not finding a site is reported, not an error.
#' @return Invisibly, a named list with the collected information.
#' @examples
#' \dontrun{
#' jekylldown::check()
#' }
#' @export
check <- function(dir = ".") {
  cli::cli_h1("jekylldown sitrep")

  info <- list(
    ruby    = cmd_version("ruby"),
    gem     = cmd_version("gem"),
    bundler = cmd_version("bundle"),
    jekyll  = cmd_version("jekyll")
  )

  cli::cli_h2("Toolchain")
  report <- function(name, value, required, hint) {
    if (!is.null(value)) {
      cli::cli_alert_success("{name}: {.val {value}} at {.path {find_cmd(name)}}")
    } else if (required) {
      cli::cli_alert_danger("{name}: not found. {hint}")
    } else {
      cli::cli_alert_warning("{name}: not found. {hint}")
    }
  }
  report("ruby", info$ruby, TRUE,
         "Install Ruby >= 3.0 (e.g. {.code apt install ruby-full}).")
  report("gem", info$gem, TRUE, "Usually ships with Ruby.")
  report("bundle", info$bundler, FALSE,
         "Optional for simple sites; themes like al-folio want it.
          {.code gem install bundler}.")
  report("jekyll", info$jekyll, FALSE,
         "Needed for local builds/previews only; knitting and GitHub Pages
          builds work without it. {.code gem install jekyll}.")

  quarto <- jd_quarto()
  if (!is.null(quarto)) {
    qv <- tryCatch(trimws(system2(quarto, "--version", stdout = TRUE)[[1]]),
                   error = function(e) "unknown")
    info$quarto <- qv
    cli::cli_alert_success("quarto: {.val {qv}} at {.path {quarto}}")
  } else {
    info$quarto <- NULL
    cli::cli_alert_warning(
      "quarto: not found. Only needed for {.file .qmd} posts; install into
       the isolated toolchain with {.run jekylldown::install_quarto()}.")
  }

  gem_home <- jd_gem_home()
  if (dir.exists(gem_home)) {
    cli::cli_alert_info("Isolated GEM_HOME in use: {.path {gem_home}}")
  } else {
    cli::cli_alert_info(
      "No isolated GEM_HOME yet (would live at {.path {gem_home}});
       using system gems from the PATH."
    )
  }
  info$gem_home <- if (dir.exists(gem_home)) gem_home else NULL

  cli::cli_h2("Site")
  root <- tryCatch(site_root(dir), error = function(e) NULL)
  info$site <- root
  if (is.null(root)) {
    cli::cli_alert_warning(
      "No Jekyll site found here. Create one with {.fn jekylldown::new_site}."
    )
  } else {
    n_src <- length(list.files(file.path(root, "_source"),
                               "[.]([Rr]|[qQ])md$"))
    n_posts <- length(list.files(file.path(root, "_posts"), "[.](md|markdown)$"))
    cli::cli_alert_success("Site root: {.path {root}}")
    cli::cli_alert_info("{n_src} source post{?s} (Rmd/qmd) in {.file _source/},
                         {n_posts} Markdown post{?s} in {.file _posts/}.")
  }

  invisible(info)
}
