#' Knit sources and build the site
#'
#' Knits every outdated `_source/*.Rmd` and renders every outdated
#' `_source/*.qmd` (Quarto) to `_posts/*.md` (see [knit_post()]), then runs
#' `jekyll build` if a usable Jekyll is available.
#'
#' @param dir Directory in (or under) the site.
#' @param local_jekyll Run `jekyll build` after knitting? `NULL` (default)
#'   auto-detects: builds when a `jekyll` executable is found, otherwise
#'   skips with a note (knitting alone is enough when GitHub Pages/Actions
#'   does the Jekyll build remotely).
#' @param force Re-knit sources even when the output is up to date?
#' @return Invisibly, the paths of the posts (re)knitted.
#' @examples
#' \dontrun{
#' # knit/render outdated posts, then build with the local Jekyll (if any)
#' build_site("my-site")
#'
#' # knit only -- e.g. when GitHub Actions does the Jekyll build remotely
#' build_site("my-site", local_jekyll = FALSE)
#'
#' # re-knit everything from scratch
#' build_site("my-site", force = TRUE)
#' }
#' @export
build_site <- function(dir = ".", local_jekyll = NULL, force = FALSE) {
  root <- site_root(dir)
  knitted <- knit_all(root, force = force)

  if (is.null(local_jekyll)) local_jekyll <- !is.null(jekyll_cmd())
  if (local_jekyll) {
    run_jekyll("build", dir = root)
    cli::cli_alert_success("Site built into {.path {file.path(root, '_site')}}.")
  } else {
    cli::cli_alert_info(
      "No local {.code jekyll} found; skipped the Jekyll build.
       Knitted Markdown is ready for a remote build (GitHub Pages/Actions)."
    )
  }
  invisible(knitted)
}

# Knit every _source/*.Rmd whose _posts/*.md output is missing or older.
# quiet = TRUE suppresses the "all up to date" chatter (the serve loop
# calls this once per rebuild).
knit_all <- function(root, force = FALSE, quiet = FALSE) {
  sources <- list.files(file.path(root, "_source"), "[.]([Rr]|[qQ])md$",
                        full.names = TRUE)
  knitted <- character()
  for (input in sources) {
    output <- file.path(root, "_posts",
                        paste0(xfun::sans_ext(basename(input)), ".md"))
    outdated <- force || !file.exists(output) ||
      file.mtime(input) > file.mtime(output)
    if (!outdated) next
    cli::cli_alert_info("Knitting {.file {basename(input)}} ...")
    knit_post(input, output, root)
    knitted <- c(knitted, output)
  }
  if (!length(knitted) && !quiet) cli::cli_alert_success("All posts up to date.")
  invisible(knitted)
}

#' Knit one source post to Jekyll-ready Markdown
#'
#' Knits a single `.Rmd` with the conventions inherited from Yihui Xie's
#' knitr-jekyll: front matter preserved, output fenced for kramdown/rouge
#' via [knitr::render_jekyll()], figures written to
#' `assets/img/posts/<post-name>/` and referenced through
#' `{{ site.baseurl }}` so they resolve wherever the site is mounted.
#'
#' A `.qmd` input is rendered with the Quarto CLI (`quarto render --to
#' gfm`) instead, and the result is adapted to the same conventions: the
#' front matter of the `.qmd` is carried over (minus Quarto-only keys,
#' with `layout: post` added), and figures are moved to
#' `assets/img/posts/<post-name>/`. Quarto is looked up in jekylldown's
#' isolated toolchain (see [install_quarto()]), then on the `PATH`;
#' `options(jekylldown.quarto = "/path/to/quarto")` overrides both.
#'
#' In both cases Markdown pipe tables get a `{: .table}` kramdown IAL so
#' the theme styles them (al-folio only styles Bootstrap's `.table`
#' class; a bare `<table>` looks unstyled).
#'
#' Mostly called for you by [build_site()] and [serve_site()] (the latter via
#' the generated `build.R`), but exported so those entry points and users can
#' share one implementation.
#'
#' @param input Path to the `.Rmd` (or `.qmd`) source.
#' @param output Path of the `.md` to write.
#' @param root Site root; found from `input` when `NULL`.
#' @param method For `.Rmd` sources: `"knitr"` (default) knits with plain
#'   knitr -- fast, no pandoc needed; `"pandoc"` renders through
#'   rmarkdown/pandoc, enabling citations (`bibliography:`), footnotes
#'   and cross-references. `NULL` (the default) takes the post's
#'   `knit_method:` front matter key if present, then
#'   `options(jekylldown.knit_method =)`, then `"knitr"`. Ignored for
#'   `.qmd` (always the Quarto CLI).
#' @return `output`, invisibly.
#' @examples
#' \dontrun{
#' # normally called for you by build_site()/serve_site()
#' knit_post("my-site/_source/2026-01-01-hello.Rmd",
#'           "my-site/_posts/2026-01-01-hello.md")
#'
#' # force the pandoc pipeline for one post (citations, footnotes, ...)
#' knit_post("my-site/_source/2026-01-01-paper.Rmd",
#'           "my-site/_posts/2026-01-01-paper.md", method = "pandoc")
#' }
#' @export
knit_post <- function(input, output, root = NULL, method = NULL) {
  if (is.null(root)) root <- site_root(dirname(normalizePath(input)))
  base <- xfun::sans_ext(basename(input))
  if (grepl("[.][qQ]md$", input)) {
    return(render_quarto_post(input, output, root, base))
  }
  if (is.null(method)) {
    fm <- split_front_matter(xfun::read_utf8(input))
    method <- fm$meta$knit_method %||%
      getOption("jekylldown.knit_method", "knitr")
  }
  method <- match.arg(method, c("knitr", "pandoc"))
  if (method == "pandoc") {
    return(render_pandoc_post(input, output, root, base))
  }

  # knitr's state is global: snapshot everything we touch and restore on exit
  # so knitting a post never leaks into the user's session.
  old_knit  <- knitr::opts_knit$get(c("base.dir", "base.url"))
  old_chunk <- knitr::opts_chunk$get(c("fig.path", "cache.path"))
  old_hooks <- knitr::knit_hooks$get()
  on.exit({
    knitr::opts_knit$set(old_knit)
    knitr::opts_chunk$set(old_chunk)
    knitr::knit_hooks$restore(old_hooks)
  }, add = TRUE)

  knitr::render_jekyll()
  knitr::opts_knit$set(
    base.dir = paste0(root, "/"),
    base.url = "{{ site.baseurl }}/"
  )
  knitr::opts_chunk$set(
    fig.path   = sprintf("assets/img/posts/%s/", base),
    cache.path = file.path(root, "_cache", base, "")
  )
  knitr::knit(input, output, envir = new.env(parent = globalenv()),
              quiet = TRUE, encoding = "UTF-8")
  xfun::write_utf8(tag_tables(xfun::read_utf8(output)), output)
  invisible(output)
}

# Render a Quarto post with the quarto CLI (`--to gfm`), then adapt the
# result to the site's conventions: front matter taken from the .qmd source
# (minus Quarto-only keys, plus `layout: post`), figures moved to
# `assets/img/posts/<post>/` and linked through `{{ site.baseurl }}`, and
# tables tagged for the theme. Rendering happens next to the source so
# chunks reading files through relative paths keep working; every
# intermediate output is cleaned up afterwards.
render_quarto_post <- function(input, output, root, base) {
  quarto <- jd_quarto()
  if (is.null(quarto)) {
    cli::cli_abort(c(
      "Rendering {.file {basename(input)}} needs the Quarto CLI, which was
       not found.",
      "i" = "Install it from {.url https://quarto.org/docs/get-started/}, or
             point {.code options(jekylldown.quarto = ...)} at the
             executable."))
  }
  input <- normalizePath(input)
  src_dir <- dirname(input)
  stem <- xfun::sans_ext(basename(input))
  out_md <- file.path(src_dir, paste0(stem, ".md"))
  files_dir <- file.path(src_dir, paste0(stem, "_files"))
  on.exit(unlink(c(out_md, files_dir, file.path(src_dir, ".quarto")),
                 recursive = TRUE), add = TRUE)

  log <- xfun::in_dir(src_dir, suppressWarnings(
    system2(quarto, c("render", basename(input), "--to", "gfm"),
            stdout = TRUE, stderr = TRUE)))
  if (!is.null(attr(log, "status")) || !file.exists(out_md)) {
    writeLines(utils::tail(log, 15))
    cli::cli_abort("Quarto failed to render {.file {basename(input)}}
                    (output above).")
  }

  adapt_rendered_post(input, output, root, base, out_md, files_dir,
                      drop_keys = c("format", "execute", "engine", "jupyter",
                                    "editor", "knitr", "embed-resources"))
}

# Render an .Rmd through rmarkdown/pandoc (GitHub-flavored Markdown
# output) instead of plain knitr: this enables the pandoc-only features
# -- citations (`bibliography:`), footnotes, cross-references -- at the
# cost of requiring pandoc. Selected per post with `knit_method: pandoc`
# in the front matter, or globally with
# `options(jekylldown.knit_method = "pandoc")`.
render_pandoc_post <- function(input, output, root, base) {
  if (!requireNamespace("rmarkdown", quietly = TRUE) ||
      !rmarkdown::pandoc_available("2.0")) {
    cli::cli_abort(c(
      "The pandoc method needs the {.pkg rmarkdown} package and
       pandoc >= 2.0.",
      "i" = "Install them, or remove {.code knit_method: pandoc} from the
             front matter to use the plain knitr method."))
  }
  input <- normalizePath(input)
  src_dir <- dirname(input)
  stem <- xfun::sans_ext(basename(input))
  out_name <- paste0(stem, ".pandoc.md")
  out_md <- file.path(src_dir, out_name)
  # rmarkdown names the figure directory after the *output* file
  files_dir <- file.path(src_dir, paste0(stem, ".pandoc_files"))
  on.exit(unlink(c(out_md, files_dir), recursive = TRUE), add = TRUE)

  fmt <- rmarkdown::md_document(variant = "gfm", preserve_yaml = FALSE)
  rmarkdown::render(input, fmt, output_file = out_name, quiet = TRUE,
                    envir = new.env(parent = globalenv()))

  adapt_rendered_post(input, output, root, base, out_md, files_dir,
                      drop_keys = c("output", "bibliography", "csl",
                                    "link-citations", "nocite",
                                    "knit_method"))
}

# Adapt a pandoc-flavored Markdown rendering (from Quarto or rmarkdown) to
# the site's conventions: body taken from the rendered file (its front
# matter, if any, is discarded), figures moved from the renderer's
# `*_files/` directory to `assets/img/posts/<post>/` behind
# `{{ site.baseurl }}`, front matter carried over from the source minus
# renderer-only keys (plus `layout: post`), the repeated title block
# stripped, and tables tagged for the theme.
adapt_rendered_post <- function(input, output, root, base, out_md,
                                files_dir, drop_keys) {
  rendered <- xfun::read_utf8(out_md)
  rfm <- split_front_matter(rendered)
  body <- if (is.null(rfm)) rendered else rfm$body

  if (dir.exists(files_dir)) {
    target <- file.path(root, "assets", "img", "posts", base)
    if (dir.exists(target)) unlink(target, recursive = TRUE)
    fs::dir_create(dirname(target))
    fs::dir_copy(files_dir, target)
    body <- gsub(paste0(basename(files_dir), "/"),
                 sprintf("{{ site.baseurl }}/assets/img/posts/%s/", base),
                 body, fixed = TRUE)
  }

  sfm <- split_front_matter(xfun::read_utf8(input))
  meta <- if (is.null(sfm)) list() else sfm$meta
  meta <- meta[setdiff(names(meta), drop_keys)]
  if (is.null(meta$layout)) meta <- c(list(layout = "post"), meta)
  fm <- strsplit(yaml::as.yaml(meta), "\n")[[1]]
  body <- strip_title_block(body, meta)

  fs::dir_create(dirname(output))
  xfun::write_utf8(c("---", fm, "---", "", tag_tables(body)), output)
  invisible(output)
}

# pandoc's standalone gfm repeats the front matter as body text -- the
# title as a leading `#` heading, then date/author lines. The Jekyll post
# layout already renders those, so drop the repetition (and only it: a
# post starting with an unrelated heading is left alone).
strip_title_block <- function(body, meta) {
  drop_blank <- function(b) {
    while (length(b) && !nzchar(trimws(b[[1]]))) b <- b[-1]
    b
  }
  b <- drop_blank(body)
  title <- meta$title
  if (is.null(title) || !length(b) || !grepl("^#\\s", b[[1]]) ||
      !identical(trimws(sub("^#\\s+", "", b[[1]])), trimws(title))) {
    return(body)
  }
  b <- drop_blank(b[-1])
  for (key in c("date", "author")) {
    v <- meta[[key]]
    if (!is.null(v) && length(b) &&
        identical(trimws(b[[1]]), trimws(as.character(v)))) {
      b <- drop_blank(b[-1])
    }
  }
  b
}

# Locate the Quarto CLI: an explicit option first (also the test seam),
# then jekylldown's isolated toolchain (see install_quarto()), then the
# quarto package's discovery, then the PATH.
jd_quarto <- function() {
  opt <- getOption("jekylldown.quarto")
  if (!is.null(opt)) return(if (file.exists(opt)) opt else NULL)
  tc <- file.path(jd_data_dir(), "quarto", "bin", "quarto")
  if (file.exists(tc)) return(tc)
  if (requireNamespace("quarto", quietly = TRUE)) {
    p <- tryCatch(quarto::quarto_path(), error = function(e) NULL)
    if (!is.null(p) && nzchar(p)) return(p)
  }
  p <- Sys.which("quarto")
  if (nzchar(p)) unname(p) else NULL
}

# Markdown pipe tables render as bare <table> elements, which al-folio
# leaves almost unstyled (the theme styles Bootstrap's `.table` class).
# kramdown applies a block IAL written on the line right after a table, so
# tag every pipe table with `{: .table}`. Lines inside fenced code or
# {% highlight %} blocks are left alone, as are tables that already carry
# an IAL. Harmless on minima (no `.table` class, and its own CSS already
# styles bare tables).
tag_tables <- function(lines) {
  n <- length(lines)
  if (!n) return(lines)
  protected <- logical(n)
  in_code <- FALSE
  for (i in seq_len(n)) {
    l <- lines[[i]]
    if (grepl("^\\s*(```|~~~)", l)) {
      protected[i] <- TRUE
      in_code <- !in_code
      next
    }
    if (grepl("^\\s*\\{%\\s*highlight", l)) in_code <- TRUE
    protected[i] <- in_code
    if (grepl("^\\s*\\{%\\s*endhighlight", l)) in_code <- FALSE
  }
  # GitHub renders pipe tables without the leading pipe
  # (`Topic|Length` over `----|----`), but kramdown only recognizes rows
  # that START with `|` -- normalize such loose tables first
  has_pipe <- grepl("\\|", lines) & !protected
  is_delim <- has_pipe & grepl("^\\s*[|: -]+$", lines) & grepl("-", lines)
  i <- 1
  while (i < n) {
    if (has_pipe[[i]] && !is_delim[[i]] && is_delim[[i + 1]]) {
      j <- i
      while (j <= n && has_pipe[[j]]) {
        if (!grepl("^\\s*\\|", lines[[j]])) lines[[j]] <- paste0("|", lines[[j]])
        j <- j + 1
      }
      i <- j
    } else {
      i <- i + 1
    }
  }

  is_row <- grepl("^\\s*\\|", lines) & !protected
  is_sep <- grepl("^\\s*\\|[-:| ]+\\|?\\s*$", lines) & is_row

  out <- character()
  for (i in seq_len(n)) {
    # kramdown needs the table to start its own block: when a real table
    # run begins right after prose (no blank line), insert one
    run_starts <- is_row[i] && (i == 1 || !is_row[i - 1])
    if (run_starts) {
      e <- i
      while (e < n && is_row[e + 1]) e <- e + 1
      real <- (e - i + 1) >= 2 && any(is_sep[i:e])
      if (real && length(out) && nzchar(trimws(out[[length(out)]]))) {
        out <- c(out, "")
      }
    }
    out <- c(out, lines[[i]])
    run_ends <- is_row[i] && (i == n || !is_row[i + 1])
    if (!run_ends) next
    s <- i
    while (s > 1 && is_row[s - 1]) s <- s - 1
    real_table <- (i - s + 1) >= 2 && any(is_sep[s:i])
    has_ial <- i < n && grepl("^\\s*\\{:", lines[[i + 1]])
    if (real_table && !has_ial) out <- c(out, "{: .table}")
  }
  out
}
