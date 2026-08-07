# Toolchain discovery and environment injection.
#
# Design rule (DESIGN.md #3.1): every jekyll/bundler invocation goes through
# the package, which injects GEM_HOME/GEM_PATH/PATH pointing at an isolated
# gem directory under tools::R_user_dir(). Nothing is ever installed
# system-wide, and the user never has to configure their shell.

jd_data_dir <- function() tools::R_user_dir("jekylldown", "data")

# Provisioned Ruby (conda-forge layout), when install_jekyll()/the user has
# set one up under the data dir.
jd_ruby_dir <- function() {
  d <- file.path(jd_data_dir(), "ruby")
  if (dir.exists(file.path(d, "bin"))) d else NULL
}

# Isolated gem directory. A provisioned conda-forge Ruby keeps its gems in
# share/rubygems inside the env (its rubygems is configured to ignore an
# external GEM_HOME at install time); with a system Ruby we use gems/ under
# the data dir.
jd_gem_home <- function() {
  ruby <- jd_ruby_dir()
  if (!is.null(ruby)) {
    conda_gems <- file.path(ruby, "share", "rubygems")
    if (dir.exists(conda_gems)) return(conda_gems)
  }
  file.path(jd_data_dir(), "gems")
}

# Environment variables to inject into every external Ruby process. Returned
# as a named character vector; empty when nothing is provisioned (system
# Ruby/gems from the PATH are then used as-is).
jd_env <- function() {
  gem_home <- jd_gem_home()
  ruby <- jd_ruby_dir()
  bins <- c(file.path(gem_home, "bin"),
            if (!is.null(ruby)) file.path(ruby, "bin"))
  bins <- bins[dir.exists(bins)]
  if (!length(bins) && !dir.exists(gem_home)) return(character())

  path <- Sys.getenv("PATH")
  for (bin in rev(bins)) {
    if (!startsWith(path, paste0(bin, .Platform$path.sep))) {
      path <- paste(bin, path, sep = .Platform$path.sep)
    }
  }
  env <- c(PATH = path)
  if (dir.exists(gem_home)) {
    gem_path <- Sys.getenv("GEM_PATH")
    gem_path <- if (nzchar(gem_path) && gem_path != gem_home) {
      paste(gem_home, gem_path, sep = .Platform$path.sep)
    } else {
      gem_home
    }
    env <- c(GEM_HOME = gem_home, GEM_PATH = gem_path, env)
  }
  env
}

# Make jd_env() effective for child processes spawned outside our control
# (e.g. the `jekyll build` command that servr runs via system()).
jd_set_env <- function() {
  env <- jd_env()
  if (length(env)) do.call(Sys.setenv, as.list(env))
  invisible(env)
}

# Locate an executable: isolated gem bin dir first, then provisioned Ruby,
# then PATH. On Windows the Ruby commands are .bat/.cmd/.exe wrappers.
find_cmd <- function(cmd) {
  exts <- if (identical(.Platform$OS.type, "windows")) {
    c(".bat", ".cmd", ".exe", "")
  } else {
    ""
  }
  ruby <- jd_ruby_dir()
  bases <- c(file.path(jd_gem_home(), "bin", cmd),
             if (!is.null(ruby)) file.path(ruby, "bin", cmd))
  cand <- as.vector(t(outer(bases, exts, paste0)))
  cand <- cand[file.exists(cand)]
  if (length(cand)) return(cand[1])
  hit <- Sys.which(cmd)
  if (nzchar(hit)) unname(hit) else NULL
}

# processx cannot exec .bat/.cmd files directly (CreateProcess wants a
# real executable); route those through cmd.exe /c.
shell_cmd <- function(cmd, args,
                      windows = identical(.Platform$OS.type, "windows")) {
  if (windows && grepl("[.](bat|cmd)$", cmd, ignore.case = TRUE)) {
    list(cmd = Sys.getenv("COMSPEC", "cmd.exe"), args = c("/c", cmd, args))
  } else {
    list(cmd = cmd, args = args)
  }
}

jekyll_cmd <- function() {
  getOption("jekylldown.jekyll", find_cmd("jekyll"))
}

# Run jekyll with the injected environment, capturing stderr so failures
# surface as readable R errors. Sites with a Gemfile.lock (e.g. al-folio,
# after bundle_install()) get `bundle exec jekyll` so their plugins resolve;
# plain sites get the jekyll executable directly.
run_jekyll <- function(args, dir = ".", echo = TRUE) {
  jekyll <- jekyll_cmd()
  if (is.null(jekyll)) {
    cli::cli_abort(c(
      "The {.code jekyll} executable was not found.",
      "i" = "Install it with {.code gem install jekyll bundler}, or point the
             option {.code jekylldown.jekyll} at an executable.",
      "i" = "On Windows, {.fn jekylldown::install_ruby} sets up Ruby and
             Jekyll in an isolated toolchain.",
      "i" = "Run {.run jekylldown::check()} for a full diagnostic."
    ))
  }
  bundle <- find_cmd("bundle")
  env <- c("current", jd_env())
  if (file.exists(file.path(dir, "Gemfile.lock")) && !is.null(bundle)) {
    cmd <- bundle
    args <- c("exec", "jekyll", args)
  } else {
    cmd <- jekyll
    # a Gemfile without a lockfile (bundle_install() not run yet) makes
    # jekyll try to Bundler.setup anyway and die on any version skew;
    # this is jekyll's official escape hatch -- the globally installed
    # gems are used instead
    if (file.exists(file.path(dir, "Gemfile"))) {
      env <- c(env, JEKYLL_NO_BUNDLER_REQUIRE = "true")
    }
  }
  sc <- shell_cmd(cmd, args)
  res <- processx::run(
    sc$cmd, sc$args,
    wd = dir,
    env = env,
    echo = echo,
    error_on_status = FALSE
  )
  if (res$status != 0) {
    hint <- if (grepl("bundle install|not yet checked out",
                      paste(res$stderr, res$stdout))) {
      c("i" = "The site's gems are not installed yet: run
               {.code jekylldown::bundle_install(\"{dir}\")} first.")
    }
    cli::cli_abort(c(
      "{.code {basename(cmd)} {paste(args, collapse = ' ')}} failed
       (exit status {res$status}).",
      "x" = "{sub('\\n.*$', '', trimws(res$stderr))}",
      hint
    ))
  }
  invisible(res)
}

# Does the site's Gemfile pull any gem straight from a git repository
# (al-folio does)? Bundler shells out to git for those.
gemfile_needs_git <- function(root) {
  gemfile <- file.path(root, "Gemfile")
  if (!file.exists(gemfile)) return(FALSE)
  any(grepl("\\bgit(hub)?:", xfun::read_utf8(gemfile)))
}

#' Install a site's gem dependencies with Bundler
#'
#' Runs `bundle install` in the site root with the package's isolated gem
#' environment injected, so a theme's `Gemfile` (al-folio has one) resolves
#' without any manual `GEM_HOME`/`PATH` setup. Needed once per site (and
#' after editing the `Gemfile`); afterwards [build_site()] and
#' [serve_site()] automatically switch to `bundle exec jekyll`.
#'
#' One external requirement: a `Gemfile` that installs gems straight from
#' git repositories (al-folio's does) needs `git` on the `PATH`, because
#' Bundler shells out to it -- the only step in the jekylldown workflow
#' that requires git. On Windows, install it from
#' <https://git-scm.com/downloads>.
#'
#' @param dir Directory in (or under) the site.
#' @return Invisibly, the [processx::run()] result.
#' @examples
#' \dontrun{
#' bundle_install("my-site")
#' build_site("my-site")   # now builds with `bundle exec jekyll`
#' }
#' @export
bundle_install <- function(dir = ".") {
  root <- site_root(dir)
  bundle <- find_cmd("bundle")
  if (is.null(bundle)) {
    cli::cli_abort(c(
      "The {.code bundle} executable was not found.",
      "i" = "Install it with {.code gem install bundler}, then re-run.
             {.run jekylldown::check()} shows what is on the PATH."
    ))
  }
  if (gemfile_needs_git(root) && !nzchar(Sys.which("git"))) {
    cli::cli_abort(c(
      "This site's {.file Gemfile} installs gems from git repositories
       (al-folio's does), and {.code git} was not found.",
      "i" = "Install git from {.url https://git-scm.com/downloads} and
             re-run {.code bundle_install(\"{dir}\")}."))
  }
  sc <- shell_cmd(bundle, "install")
  res <- processx::run(
    sc$cmd, sc$args,
    wd = root,
    env = c("current", jd_env()),
    echo = TRUE,
    error_on_status = FALSE
  )
  if (res$status != 0) {
    cli::cli_abort(c(
      "{.code bundle install} failed (exit status {res$status}).",
      "x" = "{sub('\\n.*$', '', trimws(res$stderr))}"
    ))
  }
  invisible(res)
}

# Walk up from `dir` until a _config.yml is found.
site_root <- function(dir = ".") {
  if (!dir.exists(dir)) {
    cli::cli_abort(
      "Directory {.path {dir}} does not exist. Pass the path to your
       Jekyll site via the {.arg dir} argument."
    )
  }
  d <- normalizePath(dir, mustWork = TRUE)
  repeat {
    if (file.exists(file.path(d, "_config.yml"))) return(d)
    parent <- dirname(d)
    if (parent == d) {
      cli::cli_abort(c(
        "No {.file _config.yml} found in {.path {dir}} or any parent
         directory, so this does not look like a Jekyll site.",
        "i" = "If you are calling from outside the site folder, pass its
               path explicitly, e.g.
               {.code set_theme_color(\"#b509ac\", dir = \"path/to/site\")}.",
        "i" = "To create a new site, see {.fn jekylldown::new_site}."
      ))
    }
    d <- parent
  }
}

# Old signatures took the site path as the first argument; catch calls
# in that style and point at `dir` instead of failing confusingly.
abort_if_site_path <- function(x, fn) {
  if (is.character(x) && length(x) == 1 && !is.na(x) && dir.exists(x) &&
      file.exists(file.path(x, "_config.yml"))) {
    cli::cli_abort(c(
      "{.val {x}} looks like a site directory.",
      "i" = "The site path goes in the {.arg dir} argument now:
             {.code {fn}(..., dir = \"{x}\")}."),
      call = parent.frame())
  }
  invisible(x)
}

slugify <- function(x) {
  x <- tolower(trimws(x))
  x <- gsub("[^a-z0-9]+", "-", x)
  gsub("^-+|-+$", "", x)
}

# Version string of an external command, or NULL if unavailable/broken.
cmd_version <- function(cmd) {
  path <- find_cmd(cmd)
  if (is.null(path)) return(NULL)
  sc <- shell_cmd(path, "--version")
  res <- tryCatch(
    processx::run(sc$cmd, sc$args, env = c("current", jd_env()),
                  error_on_status = FALSE, timeout = 30),
    error = function(e) NULL
  )
  if (is.null(res) || res$status != 0) return(NULL)
  trimws(res$stdout)
}
