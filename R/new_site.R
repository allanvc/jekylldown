#' Create a new Jekyll site
#'
#' Scaffolds a Jekyll site ready for the jekylldown workflow: R Markdown
#' posts live in `_source/`, are knitted to `_posts/*.md`, and figures land
#' in `assets/img/posts/`. Four themes are supported first-class:
#'
#' * `"minima"` (default) -- a minimal self-contained blog, generated
#'   locally (no network needed);
#' * `"al-folio"` -- the academic theme
#'   (\url{https://github.com/alshedivat/al-folio}), fetched from GitHub
#'   (a shallow git clone when git is available, the template archive
#'   otherwise -- git is not required);
#' * `"chirpy"` -- the technical-blog theme
#'   (\url{https://github.com/cotes2020/jekyll-theme-chirpy}): its starter
#'   template is fetched the same way and stripped of the upstream repo
#'   tooling, keeping the GitHub Pages deploy workflow;
#' * `"minimal-mistakes"` -- the general-purpose theme
#'   (\url{https://github.com/mmistakes/minimal-mistakes}), generated
#'   locally as a gem-based site (see [set_theme_skin()] for its skins).
#'
#' @param dir Directory to create the site in. Must be empty or nonexistent.
#' @param theme `"minima"` (default), `"al-folio"`, `"chirpy"` or
#'   `"minimal-mistakes"`.
#' @param title Site title written to `_config.yml` (all themes except
#'   al-folio, which builds its identity from first/last name -- edit its
#'   config, or let [migrate_hugo()] fill it).
#' @param sample Create a sample `.Rmd` post in `_source/`? Default `TRUE`.
#' @param demo Keep the theme's demo content? Only al-folio ships demo
#'   content (sample posts, news, projects, books and an example
#'   biography); default `TRUE`, set to `FALSE` for a site that starts
#'   empty. [migrate_hugo()] always starts from a scrubbed site. The other
#'   themes start empty regardless.
#' @return The normalized site path, invisibly.
#' @examples
#' \dontrun{
#' # a minimal blog with the locally generated minima theme (no network)
#' new_site("my-blog")
#'
#' # the al-folio academic theme, fetched from GitHub, starting empty
#' new_site("my-site", theme = "al-folio", demo = FALSE)
#'
#' # the Chirpy starter, or a gem-based Minimal Mistakes site
#' new_site("my-blog", theme = "chirpy")
#' new_site("my-blog", theme = "minimal-mistakes", title = "My blog")
#' }
#' @export
new_site <- function(dir, theme = c("minima", "al-folio", "chirpy",
                                    "minimal-mistakes"),
                     title = "A jekylldown site", sample = TRUE,
                     demo = TRUE) {
  theme <- match.arg(theme)
  # Expand "~" before the path reaches external tools: git (via processx)
  # gets arguments verbatim, and an unexpanded "~/..." would become a
  # literal directory named "~" under the working directory.
  dir <- path.expand(dir)
  if (dir.exists(dir) && length(list.files(dir, all.files = TRUE, no.. = TRUE))) {
    cli::cli_abort("{.path {dir}} exists and is not empty.")
  }

  switch(theme,
    "minima"           = scaffold_minima(dir, title),
    "al-folio"         = scaffold_al_folio(dir),
    "chirpy"           = scaffold_chirpy(dir, title),
    "minimal-mistakes" = scaffold_minimal_mistakes(dir, title)
  )
  if (!demo && theme == "al-folio") scrub_al_folio_demo(dir)

  root <- normalizePath(dir)
  fs::dir_create(file.path(root, c("_source", "_posts", "assets/img/posts")))
  add_exclude(file.path(root, "_config.yml"), c("_source", "build.R"))
  ensure_serve_gitignore(root)
  write_build_script(root)
  if (sample) write_sample_post(root)

  cli::cli_alert_success("Created {theme} site in {.path {root}}.")
  cli::cli_bullets(c(
    "*" = "Write posts with {.code new_post(\"My title\", dir = \"{dir}\")}.",
    "*" = "Knit and build with {.code build_site(\"{dir}\")}.",
    "*" = "Preview with {.code serve_site(\"{dir}\")}."
  ))
  invisible(root)
}

scaffold_minima <- function(dir, title) {
  fs::dir_create(dir)
  xfun::write_utf8(c(
    sprintf("title: %s", title),
    "description: Built with R Markdown + Jekyll via the jekylldown package",
    "theme: minima",
    "exclude:",
    "  - Gemfile",
    "  - Gemfile.lock",
    "  - vendor"
  ), file.path(dir, "_config.yml"))
  xfun::write_utf8(c(
    'source "https://rubygems.org"',
    'gem "jekyll", "~> 4.3"',
    'gem "minima"',
    'gem "webrick"'
  ), file.path(dir, "Gemfile"))
  xfun::write_utf8(c(
    "---",
    "layout: home",
    "---"
  ), file.path(dir, "index.md"))
  xfun::write_utf8(c("_site/", ".jekyll-cache/", "_cache/"),
                   file.path(dir, ".gitignore"))
}

scaffold_al_folio <- function(dir) {
  clone_template("https://github.com/alshedivat/al-folio.git", dir,
                 "alshedivat/al-folio")
  # the template ships baseurl: /al-folio (its own project page); on a
  # fresh site that 404s every asset when served at the root, so the
  # first build looks completely unstyled
  config <- file.path(dir, "_config.yml")
  xfun::write_utf8(
    set_yaml_line(xfun::read_utf8(config), "baseurl", '""'), config)
}

# The Chirpy starter is the theme's official site template: Gemfile,
# config, structural tabs (about/archives/categories/tags) and the Pages
# deploy workflow -- no demo posts. Clone it and strip the upstream repo
# tooling.
scaffold_chirpy <- function(dir, title) {
  clone_template("https://github.com/cotes2020/chirpy-starter.git", dir,
                 "cotes2020/chirpy-starter")
  prune_repo_tooling(dir, workflow = "pages-deploy.yml")
  config <- file.path(dir, "_config.yml")
  xfun::write_utf8(
    set_yaml_line(xfun::read_utf8(config), "title", title, append = TRUE),
    config)
  # upstream pins the theme to releases that require Ruby ~> 3.1, which
  # fails outright on newer Rubies; let bundler pick the newest release
  # the local Ruby can actually run
  gemfile <- file.path(dir, "Gemfile")
  lines <- xfun::read_utf8(gemfile)
  i <- grep('^gem "jekyll-theme-chirpy"', lines)
  if (length(i)) lines[i[1]] <- 'gem "jekyll-theme-chirpy", ">= 7.0"'
  xfun::write_utf8(lines, gemfile)
}

# Minimal Mistakes works as a plain gem-based site, so it is generated
# locally like minima: config with the theme and its required
# jekyll-include-cache plugin, Gemfile, home page.
scaffold_minimal_mistakes <- function(dir, title) {
  fs::dir_create(dir)
  xfun::write_utf8(c(
    sprintf("title: %s", title),
    "description: Built with R Markdown + Jekyll via the jekylldown package",
    "theme: minimal-mistakes-jekyll",
    "minimal_mistakes_skin: default",
    "plugins:",
    "  - jekyll-include-cache",
    "# pages live in _pages/, which Jekyll only renders when included",
    "include:",
    "  - _pages",
    "exclude:",
    "  - Gemfile",
    "  - Gemfile.lock",
    "  - vendor"
  ), file.path(dir, "_config.yml"))
  xfun::write_utf8(c(
    'source "https://rubygems.org"',
    'gem "jekyll", "~> 4.3"',
    'gem "minimal-mistakes-jekyll"',
    'gem "jekyll-include-cache"',
    'gem "webrick"'
  ), file.path(dir, "Gemfile"))
  xfun::write_utf8(c("---", "layout: home", "---"),
                   file.path(dir, "index.md"))
  # Minimal Mistakes has no `post` layout (it uses `single`); jekylldown
  # posts carry `layout: post`, which Jekyll would otherwise render with
  # no layout at all -- a completely unstyled page. Alias it.
  fs::dir_create(file.path(dir, "_layouts"))
  xfun::write_utf8(c("---", "layout: single", "---", "", "{{ content }}"),
                   file.path(dir, "_layouts", "post.html"))
  xfun::write_utf8(c("_site/", ".jekyll-cache/", "_cache/"),
                   file.path(dir, ".gitignore"))
}

# Fetch a theme template from GitHub: shallow git clone when git is
# around (fast), otherwise the tarball of the default branch -- so a
# machine without git (common on Windows) can still scaffold every
# theme.
clone_template <- function(url, dir, label) {
  git <- Sys.which("git")
  if (nzchar(git)) {
    cli::cli_alert_info("Cloning {label} (shallow) ...")
    res <- processx::run(
      git, c("clone", "--depth", "1", url, dir),
      echo = FALSE, error_on_status = FALSE
    )
    if (res$status == 0) {
      # It is a template, not a fork: detach it from upstream history.
      unlink(file.path(dir, ".git"), recursive = TRUE, force = TRUE)
      return(invisible(dir))
    }
    cli::cli_warn("Cloning {label} failed
                   ({sub('\\n.*$', '', trimws(res$stderr))}); downloading
                   the template archive instead.")
  }

  tarball <- paste0(sub("[.]git$", "", url), "/tarball/HEAD")
  cli::cli_alert_info("Downloading {label} ...")
  tmp <- tempfile(fileext = ".tar.gz")
  on.exit(unlink(tmp), add = TRUE)
  status <- tryCatch(
    utils::download.file(tarball, tmp, mode = "wb", quiet = TRUE),
    error = function(e) conditionMessage(e))
  if (!identical(status, 0L)) {
    cli::cli_abort(
      "Could not download {label} from {.url {tarball}}
       ({if (is.character(status)) status else paste('status', status)}).")
  }
  exdir <- tempfile("template-")
  on.exit(unlink(exdir, recursive = TRUE), add = TRUE)
  utils::untar(tmp, exdir = exdir)
  top <- list.dirs(exdir, recursive = FALSE)
  if (length(top) != 1) {
    cli::cli_abort("Unexpected archive layout for the {label} template.")
  }
  fs::dir_copy(top, dir)
  invisible(dir)
}

# A cloned theme template is a template, not a fork of the theme's
# repository: drop the upstream repo tooling -- every hidden file or
# directory except .gitignore/.nojekyll/.github, the docs/ and tools/
# trees, top-level ALL-CAPS markdown dev docs (readme, install notes,
# tooling instructions) with their now-stale `exclude` entries, and
# everything in .github except the workflow that builds and deploys the
# site on GitHub Pages.
prune_repo_tooling <- function(dir, workflow) {
  dots <- fs::dir_ls(dir, all = TRUE, regexp = "/\\.[^/]+$")
  dots <- dots[!basename(dots) %in% c(".github", ".gitignore", ".nojekyll")]
  unlink(dots, recursive = TRUE, force = TRUE)
  unlink(file.path(dir, c("docs", "tools")), recursive = TRUE)

  dev_docs <- basename(fs::dir_ls(dir, type = "file",
                                  regexp = "/[A-Z][A-Z_-]*\\.md$"))
  unlink(file.path(dir, dev_docs))
  config <- file.path(dir, "_config.yml")
  if (file.exists(config)) {
    lines <- xfun::read_utf8(config)
    stale <- grepl("^\\s*-\\s*[A-Z][A-Z_-]*\\.md\\s*$", lines)
    xfun::write_utf8(lines[!stale], config)
  }

  gh_dir <- file.path(dir, ".github")
  if (dir.exists(gh_dir)) {
    gh <- fs::dir_ls(gh_dir, all = TRUE)
    unlink(gh[basename(gh) != "workflows"], recursive = TRUE, force = TRUE)
    wf_dir <- file.path(gh_dir, "workflows")
    if (dir.exists(wf_dir)) {
      wf <- fs::dir_ls(wf_dir, all = TRUE)
      unlink(wf[basename(wf) != workflow], recursive = TRUE, force = TRUE)
    }
  }
  invisible(dir)
}

# Remove al-folio's demo content so a migrated site does not look like the
# theme's own website: sample posts/news/projects/books, the Einstein pages,
# and the demo bibliography. Structural pages (about, blog, publications,
# 404) stay.
scrub_al_folio_demo <- function(dir) {
  collections <- file.path(dir, c("_posts", "_news", "_projects", "_books",
                                  "_teachings"))
  unlink(collections, recursive = TRUE)
  fs::dir_create(collections)

  demo_pages <- c("about_einstein", "dropdown", "profiles", "plugins",
                  "books", "projects", "news", "teaching", "repositories",
                  "cv")
  unlink(file.path(dir, "_pages", paste0(demo_pages, ".md")))

  bib <- file.path(dir, "_bibliography", "papers.bib")
  if (file.exists(bib)) {
    xfun::write_utf8("% Add your publications here in BibTeX format.", bib)
  }

  prune_repo_tooling(dir, workflow = "deploy.yml")
  unlink(file.path(dir, "_data",
                   c("cv.yml", "repositories.yml", "citations.yml")))
  config <- file.path(dir, "_config.yml")
  add_exclude(config, c("test/", "requirements.txt"))

  # the demo posts are the only notebook content; once they are gone the
  # jekyll-jupyter-notebook plugin only makes `jekyll build` abort on
  # machines without jupyter/nbconvert on the PATH
  gemfile <- file.path(dir, "Gemfile")
  if (file.exists(gemfile)) {
    lines <- xfun::read_utf8(gemfile)
    xfun::write_utf8(lines[!grepl("jekyll-jupyter-notebook", lines)], gemfile)
  }
  lines <- xfun::read_utf8(config)
  xfun::write_utf8(lines[!grepl("^\\s*-\\s*jekyll-jupyter-notebook\\s*$",
                                lines)], config)

  # the demo config pulls external posts (Medium/Google feeds) into the
  # blog index, which look like the user's own posts
  lines <- xfun::read_utf8(config)
  i <- grep("^external_sources:", lines)
  if (length(i)) {
    j <- i[1] + 1
    while (j <= length(lines) && grepl("^\\s+\\S", lines[j])) j <- j + 1
    xfun::write_utf8(lines[-(i[1]:(j - 1))], config)
  }

  # the sample about page announces demo news, selected demo papers, and
  # ships Einstein as the placeholder profile picture -- a scrubbed site
  # starts with no photo (migrate_hugo() re-enables the line when it
  # finds a real avatar)
  about <- file.path(dir, "_pages", "about.md")
  if (file.exists(about)) {
    lines <- xfun::read_utf8(about)
    lines <- set_block_value(lines, "announcements", "enabled", "false")
    lines <- set_yaml_line(lines, "selected_papers", "false")
    lines <- sub("^(\\s+)image:\\s*prof_pic.*$",
                 "\\1# image: your_photo.jpg", lines)
    xfun::write_utf8(lines, about)
  }
  invisible(dir)
}

# Replace `key:` inside an indented YAML block that starts at `block:`.
set_block_value <- function(lines, block, key, value) {
  b <- grep(sprintf("^%s:", block), lines)
  if (!length(b)) return(lines)
  j <- b[1] + 1
  while (j <= length(lines) && grepl("^\\s+", lines[j])) {
    if (grepl(sprintf("^\\s+%s:", key), lines[j])) {
      indent <- sub("^(\\s+).*$", "\\1", lines[j])
      lines[j] <- sprintf("%s%s: %s", indent, key, value)
      break
    }
    j <- j + 1
  }
  lines
}

# Add entries to the `exclude:` list of a _config.yml without a YAML
# round-trip (which would destroy comments and anchors in themes like
# al-folio). Inserts right after an existing `exclude:` line, or appends a
# new block.
add_exclude <- function(config, entries) {
  lines <- xfun::read_utf8(config)
  listed <- sub("^\\s*-\\s*", "", trimws(lines[grepl("^\\s*-\\s", lines)]))
  entries <- setdiff(entries, listed)
  if (!length(entries)) return(invisible(config))
  new <- paste0("  - ", entries)
  i <- grep("^exclude:\\s*$", lines)
  if (length(i)) {
    lines <- append(lines, new, after = i[1])
  } else {
    lines <- c(lines, "", "exclude:", new)
  }
  xfun::write_utf8(lines, config)
}

# Compatibility hook: users driving the site with servr::jekyll() directly
# get per-post re-knitting through `Rscript build.R <input> <output>`.
# jekylldown's own serve_site() does not need it (it calls knit_all()).
write_build_script <- function(root) {
  xfun::write_utf8(c(
    "# Generated by jekylldown; used by servr::jekyll(script = 'build.R').",
    "local({",
    "  a <- commandArgs(TRUE)",
    "  jekylldown::knit_post(a[1], a[2])",
    "})"
  ), file.path(root, "build.R"))
}

write_sample_post <- function(root) {
  slug <- sprintf("%s-hello-jekylldown", Sys.Date())
  xfun::write_utf8(c(
    "---",
    "layout: post",
    'title: "Hello, jekylldown"',
    sprintf("date: %s", Sys.Date()),
    "tags: [r, jekyll]",
    "---",
    "",
    "This post was written in R Markdown (`_source/`) and knitted to",
    "Markdown (`_posts/`) by **jekylldown**.",
    "",
    "```{r pressure-plot, fig.alt='Scatterplot of vapor pressure of mercury against temperature'}",
    "plot(pressure, main = 'Knitted by jekylldown')",
    "```",
    "",
    "Inline R also works: 2 + 2 = `r 2 + 2`."
  ), file.path(root, "_source", paste0(slug, ".Rmd")))
}
