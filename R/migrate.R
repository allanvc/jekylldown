#' Migrate a Hugo/blogdown site to Jekyll (best effort)
#'
#' Creates a fresh Jekyll site with [new_site()] and converts the mechanical
#' parts of a Hugo site into it. The Hugo config (`config.toml`/`.yaml`) is
#' read first and drives the migration:
#'
#' * posts under `content/post/`, `content/posts/` or `content/blog/` are
#'   renamed to Jekyll's `YYYY-MM-DD-slug` convention; `.Rmd`/`.Rmarkdown`
#'   sources go to `_source/` (to be knitted by jekylldown), plain
#'   `.md`/`.markdown` to `_posts/`;
#' * every page referenced by the Hugo menu (`[[menu.main]]`) is migrated
#'   to the theme's own convention, with `permalink` preserving the Hugo
#'   URL and the menu order kept: al-folio gets `_pages/<slug>.md` with
#'   `nav_order`, Chirpy gets `_tabs/<slug>.md` with `order`, Minimal
#'   Mistakes gets `_pages/<slug>.md` plus an entry in
#'   `_data/navigation.yml`, minima gets `<slug>.md` at the root; a menu
#'   entry pointing at the posts section maps to the theme's blog page;
#' * the home page (`content/_index.md`) becomes the body of the theme's
#'   landing page (al-folio: `_pages/about.md`; Chirpy: `_tabs/about.md`;
#'   Minimal Mistakes and minima: `index.md`); an avatar
#'   `{{< figure class="avatar" >}}` becomes the theme's profile picture
#'   (al-folio profile, Chirpy `avatar:`, Minimal Mistakes
#'   `author.avatar`);
#' * site identity from the config (title/author, `baseURL`, description)
#'   is written into the new `_config.yml` (al-folio: `first_name`/
#'   `last_name`, jekyll-scholar author names; minima: `title`);
#' * social profile links found in the Hugo pages (GitHub, LinkedIn, ORCID,
#'   Google Scholar, ResearchGate, StackOverflow, ...), the first e-mail
#'   address and a link to a CV/resume PDF are written where the theme
#'   shows them: al-folio's `_data/socials.yml`, Chirpy's `social:` config
#'   block (plus its github/twitter buttons), or Minimal Mistakes'
#'   `author:` sidebar links. Posts are not scanned (they may link to
#'   other people's profiles), and only profile-shaped URLs count (a
#'   GitHub repository link is ignored);
#' * front matter (YAML `---` or TOML `+++`) is converted to Jekyll YAML:
#'   `layout: post` added, `draft: true` becomes `published: false`,
#'   `aliases` becomes `redirect_from` (needs the jekyll-redirect-from
#'   plugin), Hugo-only keys are dropped;
#' * `static/` is copied to the site root, so absolute asset URLs like
#'   `/images/foo.png` keep working; with `only_referenced = TRUE` only the
#'   files actually referenced by the migrated content are copied;
#' * page-bundle resources (`content/post/my-post/plot.png`) are copied to
#'   `assets/img/posts/<post>/` and relative image links are rewritten;
#' * `{{< figure >}}` and `{{< youtube >}}` shortcodes are converted;
#'   any other shortcode is left in place and reported for manual porting.
#'
#' The Hugo site is only read, never modified. Content not referenced by the
#' menu, layouts and whatever else cannot be converted is listed in the
#' final report.
#'
#' @param from Root of the existing Hugo site (must contain `content/`).
#' @param to Directory to create the Jekyll site in (must not exist or be
#'   empty).
#' @param theme Passed to [new_site()].
#' @param drafts Migrate draft posts (as `published: false`)? Default `TRUE`.
#' @param only_referenced Copy from `static/` only the files referenced by
#'   the migrated content (posts, pages, config)? Default `FALSE` (copy
#'   everything, as Hugo serves it).
#' @param publications How to migrate a publications page found in the menu
#'   (slug `publications`, `papers` or `pubs`). `"bib"` (default) extracts
#'   the DOIs from the page, fetches each reference as BibTeX from
#'   \url{https://doi.org} (Crossref/DataCite content negotiation; needs
#'   network), pairs preview images found next to each DOI, and writes
#'   `_bibliography/papers.bib` so al-folio's jekyll-scholar renders the
#'   publications page with the theme's badges and buttons. Entries
#'   without a DOI are reported for manual addition. On themes without
#'   jekyll-scholar (minima, Chirpy, Minimal Mistakes) the page is
#'   rebuilt instead as a clean Markdown list of formatted citations
#'   (APA, also from doi.org) -- raw-HTML publication pages rarely
#'   survive kramdown. `"html"` keeps your page as-is; `"bib"` falls
#'   back to it automatically when the page has no DOI or there is no
#'   network.
#' @param rerender Should `.Rmd`/`.Rmarkdown` sources be migrated to
#'   `_source/` for re-knitting (`TRUE`, default)? With `FALSE`, when a
#'   post's committed rendered output (`.markdown`/`.md`) sits next to
#'   its R source, the rendered file is migrated as a plain post instead
#'   -- the right choice for archival migrations, where years of old
#'   posts should not have their code executed again.
#' @param theme_color Accent color for al-folio, passed to
#'   [set_theme_color()] (a palette name like `"red"` or a `#hex` value).
#'   Applied right away when the theme gems are already installed;
#'   otherwise remembered in the report as a step to run after
#'   [bundle_install()]. Default `NULL` keeps the theme default.
#' @return Invisibly, a list report: converted posts, drafts, pages, files
#'   with remaining shortcodes, config keys set, social links written,
#'   static files skipped, and content left for manual migration.
#' @examples
#' \dontrun{
#' migrate_hugo(
#'   from  = "~/blog-hugo",     # existing blogdown/Hugo site (never written to)
#'   to    = "~/blog-jekyll",   # created here; must not exist yet
#'   theme = "al-folio",
#'   only_referenced = TRUE,    # copy only the static files actually used
#'   theme_color = "red"
#' )
#'
#' # then preview locally:
#' bundle_install("~/blog-jekyll")
#' build_site("~/blog-jekyll")
#' serve_site("~/blog-jekyll")
#' }
#' @export
migrate_hugo <- function(from, to, theme = c("minima", "al-folio",
                                             "chirpy", "minimal-mistakes"),
                         drafts = TRUE, only_referenced = FALSE,
                         publications = c("bib", "html"),
                         theme_color = NULL, rerender = TRUE) {
  publications <- match.arg(publications)
  from <- normalizePath(from, mustWork = TRUE)
  if (!dir.exists(file.path(from, "content"))) {
    cli::cli_abort("{.path {from}} has no {.file content/} directory --
                    is it really a Hugo site?")
  }

  hugo <- hugo_structure(from)
  new_site(to, theme = match.arg(theme), sample = FALSE, demo = FALSE)
  root <- normalizePath(to)

  report <- list(posts = character(), drafts = character(),
                 pages = character(), replaced = character(),
                 skipped = character(), shortcodes = list(),
                 config = character(), static_skipped = character(),
                 bib = 0L, styles = character(), socials = character(),
                 manual = character())

  fig_classes <- character()

  # --- posts ---------------------------------------------------------------
  post_dirs <- file.path(from, "content", c("post", "posts", "blog"))
  post_dirs <- post_dirs[dir.exists(post_dirs)]
  # sites organize posts differently (multilingual content/en, custom
  # section names): any content subdirectory dominated by date-named
  # files is treated as a posts section
  cand <- setdiff(list.dirs(file.path(from, "content"), recursive = FALSE),
                  post_dirs)
  dated <- vapply(cand, function(d) {
    f <- list.files(d)
    n <- sum(grepl("^\\d{4}-\\d{2}-\\d{2}-", f))
    n >= 5 && n >= length(f) / 2
  }, logical(1))
  post_dirs <- c(post_dirs, cand[dated])
  files <- list.files(post_dirs, "[.](md|markdown|Rmd|Rmarkdown)$",
                      recursive = TRUE, full.names = TRUE)
  # _index.* are Hugo section list pages, not posts (index.* in a leaf
  # bundle is a post and stays)
  files <- files[!grepl("^_index[.]", basename(files))]
  # blogdown builds .Rmarkdown -> .markdown (and .Rmd -> .html). With
  # rerender = TRUE (default) a rendered file next to its R source is an
  # artifact and the source wins (it will be re-knitted). With
  # rerender = FALSE the committed rendered output wins -- the right choice
  # for archival migrations where old posts should not run again.
  if (rerender) {
    is_artifact <- vapply(files, function(f) {
      !grepl("[.]R(md|markdown)$", f) &&
        any(file.exists(paste0(xfun::sans_ext(f), c(".Rmd", ".Rmarkdown"))))
    }, logical(1))
    files <- files[!is_artifact]
  } else {
    has_rendered <- vapply(files, function(f) {
      grepl("[.]R(md|markdown)$", f) &&
        any(file.exists(paste0(xfun::sans_ext(f), c(".md", ".markdown"))))
    }, logical(1))
    files <- files[!has_rendered]
  }

  for (f in files) {
    res <- migrate_post(f, root, drafts = drafts)
    if (is.null(res)) next
    if (isTRUE(res$skipped)) {
      report$skipped <- c(report$skipped, f)
    } else {
      report$posts <- c(report$posts, res$target)
      if (isTRUE(res$draft)) report$drafts <- c(report$drafts, res$target)
      if (length(res$shortcodes)) {
        report$shortcodes[[res$target]] <- res$shortcodes
      }
      fig_classes <- c(fig_classes, res$classes)
    }
  }

  # --- menu-referenced pages ----------------------------------------------
  consumed <- character()
  nav_order <- 0
  for (entry in hugo$menu) {
    url <- sub("/+$", "", entry$url)
    nav_order <- nav_order + 1
    if (url %in% c("", "/")) next  # home: handled below via content/_index.md
    slug <- sub("^/+", "", url)
    if (slug %in% c("post", "posts", "blog", basename(post_dirs))) {
      # the theme already has a blog page; put it where the Hugo menu had it
      blog <- file.path(root, "_pages", "blog.md")
      if (file.exists(blog)) {
        lines <- set_yaml_line(xfun::read_utf8(blog), "nav_order", nav_order)
        xfun::write_utf8(lines, blog)
      }
      consumed <- c(consumed, slug)
      next
    }
    src <- page_source(from, slug)
    if (is.null(src)) {
      report$manual <- c(report$manual, sprintf("menu entry %s (no content file)", url))
      next
    }
    if (publications == "bib" && slug %in% c("publications", "papers", "pubs")) {
      pb <- migrate_publications_bib(src, root, nav_order, from = from)
      if (!isTRUE(pb$fallback)) {
        report$bib <- pb$entries
        if (!is.null(pb$markdown)) {
          # non-scholar theme: place the rebuilt citation list as a
          # normal page, in the theme's own convention
          report$bib_kind <- "citations"
          fm <- split_front_matter(xfun::read_utf8(src))
          hdr <- if (!is.null(fm)) {
            c("---", strsplit(yaml::as.yaml(fm$meta), "\n")[[1]], "---")
          } else c("---", "---")
          tmp_src <- tempfile(fileext = ".md")
          xfun::write_utf8(c(hdr, "", pb$markdown), tmp_src)
          res <- migrate_page(tmp_src, root, slug,
                              title_fallback = entry$name,
                              permalink = paste0("/", slug, "/"),
                              nav_order = nav_order)
          report$pages <- c(report$pages, res$target)
          unlink(tmp_src)
        } else {
          report$bib_kind <- "scholar"
        }
        if (length(pb$failed)) {
          report$manual <- c(report$manual, sprintf(
            "publications with unfetchable DOI (add by hand): %s",
            paste(pb$failed, collapse = ", ")))
        }
        consumed <- c(consumed, slug)
        next
      }
      cli::cli_alert_warning(
        "BibTeX conversion not possible (no {.file _bibliography/}, no DOI
         found, or network unavailable) -- migrating the publications page
         as HTML instead.")
    }
    res <- migrate_page(src, root, slug, title_fallback = entry$name,
                        permalink = paste0("/", slug, "/"),
                        nav_order = nav_order)
    report$pages <- c(report$pages, res$target)
    if (res$replaced) report$replaced <- c(report$replaced, res$target)
    if (length(res$shortcodes)) report$shortcodes[[res$target]] <- res$shortcodes
    fig_classes <- c(fig_classes, res$classes)
    consumed <- c(consumed, slug)
  }

  # --- home page and site identity -----------------------------------------
  home <- migrate_home(from, root, hugo)
  if (!is.null(home)) {
    report$pages <- c(report$pages, home$target)
    fig_classes <- c(fig_classes, home$classes)
  }
  report$config <- apply_identity(root, hugo)

  # --- social links ---------------------------------------------------------
  report$socials <- migrate_socials(from, root, hugo = hugo,
                                    avatar = home$avatar)

  # --- figure styles from the Hugo theme -----------------------------------
  styles <- port_figure_classes(from, root, fig_classes)
  report$styles <- styles$ported
  if (length(styles$missing)) {
    report$manual <- c(report$manual, sprintf(
      "figure style .%s (not in the Hugo theme CSS, or the site CSS is
       not available yet)", styles$missing))
  }

  # --- static assets -------------------------------------------------------
  static <- copy_static(from, root, only_referenced)
  report$static_skipped <- static$skipped

  # --- what stays manual ---------------------------------------------------
  sections <- basename(setdiff(
    list.dirs(file.path(from, "content"), recursive = FALSE), post_dirs))
  top_pages <- xfun::sans_ext(list.files(file.path(from, "content"),
                                         "[.](md|markdown)$"))
  top_pages <- setdiff(top_pages, "_index")
  report$manual <- c(report$manual,
                     setdiff(c(sections, top_pages), consumed),
                     if (dir.exists(file.path(from, "layouts"))) "layouts/")

  # --- theme color ---------------------------------------------------------
  color_pending <- FALSE
  if (!is.null(theme_color)) {
    if (theme == "minimal-mistakes") {
      cli::cli_warn("Minimal Mistakes has no accent color variable --
                     ignoring {.arg theme_color}; pick a skin with
                     {.code set_theme_skin(..., dir = \"{to}\")} instead.")
    } else {
      color_pending <- !tryCatch({
        set_theme_color(theme_color, dir = root)
        TRUE
      }, error = function(e) FALSE)
    }
  }

  # --- report --------------------------------------------------------------
  cli::cli_h2("Migration report")
  cli::cli_alert_success("{length(report$posts)} post{?s} migrated
                          ({length(report$drafts)} draft{?s} kept unpublished).")
  if (length(report$pages)) {
    cli::cli_alert_success("{length(report$pages)} page{?s} migrated from the
                            Hugo menu: {.file {basename(report$pages)}}")
  }
  if (length(report$replaced)) {
    cli::cli_alert_info("Theme page{?s} replaced by your content:
                         {.file {basename(report$replaced)}}")
  }
  if (length(report$config)) {
    cli::cli_alert_success(
      "Site identity set in {.file _config.yml}: {report$config}")
  }
  if (length(report$styles)) {
    cli::cli_alert_success(
      "Figure style{?s} ported from the Hugo theme CSS:
       {.val {paste0('.', report$styles)}}")
  }
  if (length(report$socials)) {
    cli::cli_alert_success(
      "Social profiles found in the Hugo pages and migrated to the
       theme's convention: {report$socials}")
  }
  if (report$bib > 0) {
    if (identical(report$bib_kind, "citations")) {
      cli::cli_alert_success(
        "{report$bib} publication{?s} rebuilt as formatted citations
         (APA, from doi.org) -- this theme has no jekyll-scholar, so the
         page is a clean Markdown list instead of the original HTML.")
    } else {
      cli::cli_alert_success(
        "{report$bib} publication{?s} written to
         {.file _bibliography/papers.bib} from DOI metadata; entries
         without a DOI must be added by hand.")
    }
  }
  if (color_pending) {
    cli::cli_alert_info(
      "Theme color: run
       {.code set_theme_color(\"{theme_color}\", dir = \"{to}\")}
       after {.code bundle_install(\"{to}\")} (theme gems not installed yet).")
  }
  if (length(report$skipped)) {
    cli::cli_alert_warning("{length(report$skipped)} post{?s} skipped
                            (no usable date/title): {.file {report$skipped}}")
  }
  if (length(report$static_skipped)) {
    cli::cli_alert_info("{length(report$static_skipped)} unreferenced static
                         file{?s} not copied (only_referenced = TRUE).")
  }
  if (length(report$shortcodes)) {
    cli::cli_alert_warning(
      "Hugo shortcodes left in {length(report$shortcodes)} file{?s} -- port
       these by hand:")
    for (p in names(report$shortcodes)) {
      cli::cli_bullets(c(" " = "{.file {basename(p)}}:
                          {.code {report$shortcodes[[p]]}}"))
    }
  }
  if (length(report$manual)) {
    cli::cli_alert_info(
      "Not referenced by the menu, left for manual migration:
       {.file {report$manual}}")
  }
  cli::cli_alert_info("Now run {.code build_site(\"{to}\")} to knit and build.")

  invisible(report)
}

# Read the parts of the Hugo site that drive the migration: config (title,
# baseURL, params), the main menu sorted by weight, and the home page title.
hugo_structure <- function(from) {
  cfg_toml <- file.path(from, c("config.toml", "hugo.toml",
                                "config/_default/config.toml"))
  cfg_yaml <- file.path(from, c("config.yaml", "hugo.yaml",
                                "config/_default/config.yaml"))
  cfg <- if (any(file.exists(cfg_toml))) {
    parse_toml_config(xfun::read_utf8(cfg_toml[file.exists(cfg_toml)][1]))
  } else if (any(file.exists(cfg_yaml))) {
    tryCatch(yaml::yaml.load(paste(
      xfun::read_utf8(cfg_yaml[file.exists(cfg_yaml)][1]), collapse = "\n")),
      error = function(e) list())
  } else list()

  # menu.main is the Hugo convention, but themes vary: some use
  # menu.header/menu.nav, others keep a theme-specific list in params
  # (e.g. [[params.mainMenu]] with link/text instead of url/name)
  menu <- cfg$menu$main %||% cfg$menu$header %||% cfg$menu$nav %||% list()
  if (!length(menu)) {
    pm <- cfg$params$mainMenu %||% cfg$params$menu %||% list()
    menu <- lapply(pm, function(m) {
      list(name = m$text %||% m$name, url = m$link %||% m$url,
           weight = m$weight)
    })
  }
  menu <- menu[vapply(menu, function(m) !is.null(m$url), logical(1))]
  if (length(menu)) {
    w <- vapply(menu, function(m)
      suppressWarnings(as.numeric(m$weight %||% Inf)), numeric(1))
    menu <- menu[order(w)]
  }

  home_title <- NULL
  home <- file.path(from, "content", "_index.md")
  if (file.exists(home)) {
    fm <- split_front_matter(xfun::read_utf8(home))
    home_title <- fm$meta$title
  }

  list(config = cfg, menu = menu,
       title = cfg$title,
       baseURL = cfg$baseURL %||% cfg$baseurl,
       description = cfg$params$description %||% cfg$description,
       author = cfg$params$author %||% cfg$author,
       home_title = home_title)
}

# Locate the content file behind a menu URL like /publications.
page_source <- function(from, slug) {
  cands <- file.path(from, "content",
                     c(paste0(slug, ".md"), paste0(slug, ".markdown"),
                       file.path(slug, "index.md"),
                       file.path(slug, "_index.md")))
  cands <- cands[file.exists(cands)]
  if (length(cands)) cands[1] else NULL
}

# Convert one Hugo page into a Jekyll page, placed by the theme's own
# convention: al-folio keeps pages in _pages/ (nav from front matter);
# Chirpy puts navigation pages in _tabs/ (icon + order); Minimal Mistakes
# uses _pages/ plus an entry in _data/navigation.yml; minima takes them at
# the site root.
migrate_page <- function(file, root, slug, title_fallback, permalink,
                         nav_order) {
  lines <- xfun::read_utf8(file)
  fm <- split_front_matter(lines)
  meta <- if (is.null(fm)) list() else fm$meta
  body <- if (is.null(fm)) lines else fm$body

  sc <- convert_shortcodes(body)
  body <- escape_liquid(tag_tables(convert_pandoc_attrs(sc$body)))

  theme <- site_theme(root)
  title <- meta$title %||% title_fallback %||% slug
  name <- paste0(gsub("/", "-", slug), ".md")

  if (theme == "chirpy") {
    target <- file.path(root, "_tabs", name)
    out <- list(title = title, icon = "fas fa-file-lines",
                order = as.integer(nav_order), permalink = permalink)
  } else if (theme == "minimal-mistakes") {
    target <- file.path(root, "_pages", name)
    out <- list(layout = "single", title = title, permalink = permalink)
    mm_add_nav(root, title, permalink)
  } else {
    pages_dir <- file.path(root, "_pages")
    target <- file.path(if (dir.exists(pages_dir)) pages_dir else root,
                        name)
    out <- list(layout = "page", title = title, permalink = permalink,
                nav = TRUE, nav_order = as.integer(nav_order))
  }
  if (!is.null(meta$description)) out$description <- meta$description

  replaced <- file.exists(target)
  fs::dir_create(dirname(target))
  xfun::write_utf8(c(
    "---",
    strsplit(yaml::as.yaml(out), "\n")[[1]],
    "---",
    body
  ), target)

  list(target = target, shortcodes = sc$remaining, classes = sc$classes,
       replaced = replaced)
}

# Append an entry to Minimal Mistakes' _data/navigation.yml `main` menu
# (created when missing), in menu order.
mm_add_nav <- function(root, title, url) {
  nav <- file.path(root, "_data", "navigation.yml")
  fs::dir_create(dirname(nav))
  lines <- if (file.exists(nav)) xfun::read_utf8(nav) else "main:"
  if (!any(grepl(sprintf("url: %s$", url), lines))) {
    lines <- c(lines,
               sprintf('  - title: "%s"', title),
               sprintf("    url: %s", url))
  }
  xfun::write_utf8(lines, nav)
}

# content/_index.md -> the theme's landing page. On al-folio the body goes
# into _pages/about.md (keeping the theme's front matter, minus its
# placeholders); on Chirpy into _tabs/about.md; on Minimal Mistakes and
# minima into index.md above the post list. An avatar
# {{< figure class="avatar" >}} becomes the theme's profile picture where
# the theme has a slot (al-folio profile, Chirpy `avatar:`, Minimal
# Mistakes `author.avatar` -- the latter returned for the socials step,
# which owns the author block).
migrate_home <- function(from, root, hugo) {
  src <- file.path(from, "content", "_index.md")
  if (!file.exists(src)) return(NULL)
  fm <- split_front_matter(xfun::read_utf8(src))
  body <- if (is.null(fm)) xfun::read_utf8(src) else fm$body

  theme <- site_theme(root)
  about <- file.path(root, "_pages", "about.md")

  av_re <- '\\{\\{<\\s*figure[^>]*class="avatar"[^>]*>\\}\\}'
  avatar <- NULL
  hit <- grep(av_re, body, value = TRUE)
  has_slot <- file.exists(about) ||
    theme %in% c("chirpy", "minimal-mistakes")
  if (length(hit) && has_slot) {
    m <- regmatches(hit[1], regexec('src="([^"]+)"', hit[1]))[[1]]
    if (length(m) == 2) avatar <- m[2]
    body <- body[!grepl(av_re, body)]
  }
  # copy the avatar into the site and keep its site-relative path
  avatar_path <- NULL
  if (!is.null(avatar)) {
    img <- file.path(from, "static", sub("^/+", "", avatar))
    if (file.exists(img)) {
      fs::dir_create(file.path(root, "assets", "img"))
      fs::file_copy(img, file.path(root, "assets", "img", basename(img)),
                    overwrite = TRUE)
      avatar_path <- paste0("/assets/img/", basename(img))
    }
  }

  sc <- convert_shortcodes(body)
  body <- escape_liquid(tag_tables(convert_pandoc_attrs(sc$body)))

  if (theme == "chirpy") {
    tab <- file.path(root, "_tabs", "about.md")
    if (file.exists(tab)) {
      al <- xfun::read_utf8(tab)
      end <- grep("^---\\s*$", al)
      head <- if (length(end) >= 2) al[1:end[2]] else
        c("---", "icon: fas fa-info-circle", "order: 99", "---")
      xfun::write_utf8(c(head, "", body), tab)
    } else {
      tab <- file.path(root, "_tabs", "about.md")
      fs::dir_create(dirname(tab))
      xfun::write_utf8(c("---", "icon: fas fa-info-circle", "order: 99",
                         "---", "", body), tab)
    }
    if (!is.null(avatar_path)) {
      config <- file.path(root, "_config.yml")
      xfun::write_utf8(
        set_yaml_line(xfun::read_utf8(config), "avatar", avatar_path,
                      append = TRUE),
        config)
    }
    return(list(target = tab, classes = sc$classes))
  }

  if (theme == "minimal-mistakes") {
    idx <- file.path(root, "index.md")
    xfun::write_utf8(c("---", "layout: home", "author_profile: true",
                       "---", "", body), idx)
    return(list(target = idx, classes = sc$classes, avatar = avatar_path))
  }

  if (file.exists(about)) {
    al <- xfun::read_utf8(about)
    end <- grep("^---\\s*$", al)
    if (length(end) >= 2) {
      head <- al[1:end[2]]
      if (!is.null(avatar_path)) {
        # the scrub may have commented the placeholder image line out
        head <- sub("^(\\s+)#?\\s*image:.*$",
                    paste0("\\1image: ", basename(avatar_path)), head)
      }
      head <- sub("^subtitle:.*",
                  paste0("subtitle: ", hugo$description %||% ""), head)
      # theme placeholder address under `more_info:` makes no sense here
      i <- grep("^\\s+more_info:", head)
      if (length(i)) {
        j <- i[1] + 1
        while (j <= length(head) && grepl("^\\s+<p>", head[j])) j <- j + 1
        if (j > i[1] + 1) head <- head[-((i[1] + 1):(j - 1))]
      }
      xfun::write_utf8(c(head, "", body), about)
      return(list(target = about, classes = sc$classes))
    }
  }

  idx <- file.path(root, "index.md")
  xfun::write_utf8(c("---", "layout: home", "---", "", body), idx)
  list(target = idx, classes = sc$classes)
}

# Write the site identity from the Hugo config into the new _config.yml.
# Returns the names of the keys that were set.
apply_identity <- function(root, hugo) {
  config <- file.path(root, "_config.yml")
  lines <- xfun::read_utf8(config)
  set <- character()

  full <- hugo$home_title %||% hugo$author %||% hugo$title
  al_folio <- any(grepl("^first_name:", lines))

  if (al_folio) {
    if (!is.null(full)) {
      parts <- strsplit(trimws(full), "\\s+")[[1]]
      if (length(parts) >= 2) {
        first <- parts[1]
        last <- parts[length(parts)]
        middle <- paste(parts[-c(1, length(parts))], collapse = " ")
        lines <- set_yaml_line(lines, "first_name", first)
        lines <- set_yaml_line(lines, "middle_name", middle)
        lines <- set_yaml_line(lines, "last_name", last)
        # jekyll-scholar highlights these author names in publication lists
        lines <- set_yaml_line(lines, "last_name",
                               sprintf("[%s]", last), indent = 2)
        lines <- set_yaml_line(lines, "first_name",
                               sprintf("[%s, %s.]", first,
                                       substr(first, 1, 1)), indent = 2)
        set <- c(set, "first_name", "middle_name", "last_name")
      }
    }
    # front-page tag/category filters point at the theme's demo posts
    lines <- set_yaml_line(lines, "display_tags", "[]")
    lines <- set_yaml_line(lines, "display_categories", "[]")
  } else if (!is.null(hugo$title)) {
    lines <- set_yaml_line(lines, "title", hugo$title)
    set <- c(set, "title")
  }
  if (site_theme(root) == "chirpy" && !is.null(hugo$description)) {
    lines <- set_yaml_line(lines, "tagline", hugo$description, append = TRUE)
    set <- c(set, "tagline")
  }

  if (!is.null(hugo$baseURL)) {
    u <- sub("/+$", "", hugo$baseURL)
    host <- sub("^([A-Za-z][A-Za-z0-9+.-]*://[^/]+).*$", "\\1", u)
    lines <- set_yaml_line(lines, "url", host, append = TRUE)
    # project pages live under a path (https://user.github.io/repo);
    # user pages need an empty baseurl or every link 404s
    lines <- set_yaml_line(lines, "baseurl",
                           sprintf('"%s"', substr(u, nchar(host) + 1,
                                                  nchar(u))),
                           append = TRUE)
    set <- c(set, "url", "baseurl")
  }
  if (!is.null(hugo$description)) {
    lines <- set_description(lines, hugo$description)
    set <- c(set, "description")
  }

  xfun::write_utf8(lines, config)
  set
}

# Replace the value of a top-level (or indented) `key:` line, preserving the
# rest of the file (comments, anchors) untouched.
set_yaml_line <- function(lines, key, value, indent = 0, append = FALSE) {
  pad <- strrep(" ", indent)
  i <- grep(sprintf("^%s%s:", pad, key), lines)
  new <- sprintf("%s%s: %s", pad, key, value)
  if (length(i)) lines[i[1]] <- new
  else if (append) lines <- c(lines, new)
  lines
}

# Replace an inline or block-scalar `description:` with a one-line value.
set_description <- function(lines, value) {
  i <- grep("^description:", lines)
  if (!length(i)) return(c(lines, paste0("description: ", value)))
  i <- i[1]
  if (grepl("^description:\\s*[>|]", lines[i])) {
    j <- i + 1
    while (j <= length(lines) && grepl("^\\s+\\S", lines[j])) j <- j + 1
    lines <- append(lines[-((i + 1):(j - 1))], paste0("  ", value), after = i)
  } else {
    lines[i] <- paste0("description: ", value)
  }
  lines
}

# Copy static/ into the site root. With only_referenced, keep only files
# whose absolute URL (/path/file.ext) appears in the migrated content or
# config; favicons are always kept.
copy_static <- function(from, root, only_referenced) {
  static <- file.path(from, "static")
  if (!dir.exists(static)) return(list(copied = 0L, skipped = character()))
  files <- list.files(static, recursive = TRUE, all.files = TRUE, no.. = TRUE)
  keep <- files

  if (only_referenced) {
    content <- c(
      list.files(file.path(root, c("_posts", "_source", "_pages", "_tabs",
                                   "_data")),
                 full.names = TRUE),
      list.files(root, "[.](md|yml)$", full.names = TRUE)
    )
    text <- paste(unlist(lapply(content[file.exists(content)],
                                xfun::read_utf8)),
                  collapse = "\n")
    hit <- vapply(files, function(f) grepl(paste0("/", f), text, fixed = TRUE),
                  logical(1))
    keep <- union(files[hit], files[grepl("^favicon[.](ico|png|svg)$", files)])
  }

  for (f in keep) {
    target <- file.path(root, f)
    fs::dir_create(dirname(target))
    fs::file_copy(file.path(static, f), target, overwrite = TRUE)
  }
  list(copied = length(keep), skipped = setdiff(files, keep))
}

# Convert one Hugo post file. Returns NULL for unreadable files, otherwise a
# list(target, draft, shortcodes, skipped).
migrate_post <- function(file, root, drafts = TRUE) {
  lines <- xfun::read_utf8(file)
  fm <- split_front_matter(lines)
  if (is.null(fm)) return(list(skipped = TRUE))

  rmd <- grepl("[.]R(md|markdown)$", file)
  bundle <- grepl("^_?index$", xfun::sans_ext(basename(file)))
  fallback_slug <- slugify(if (bundle) basename(dirname(file)) else
                             xfun::sans_ext(basename(file)))

  date <- fm_date(fm$meta$date %||% fm$meta$publishDate)
  if (is.na(date)) date <- format(as.Date(file.mtime(file)), "%Y-%m-%d")
  slug <- fm$meta$slug %||% fallback_slug
  # Hugo filenames may already carry a date prefix; don't double it.
  slug <- sub("^\\d{4}-\\d{2}-\\d{2}-", "", slug)
  if (!nzchar(slug)) return(list(skipped = TRUE))

  draft <- isTRUE(fm$meta$draft) || identical(fm$meta$draft, "true")
  if (draft && !drafts) return(list(skipped = TRUE))

  base <- sprintf("%s-%s", date, slug)
  target <- file.path(root, if (rmd) "_source" else "_posts",
                      sprintf("%s.%s", base, if (rmd) "Rmd" else "md"))
  if (file.exists(target)) return(list(skipped = TRUE))

  # bundle resources -> assets/img/posts/<base>/, and rewrite relative
  # image links to match
  body <- fm$body
  if (!bundle) {
    # in a plain post, `./x` can only sensibly mean the site root (Hugo
    # sites with relativeURLs=true got away with it); left alone it
    # resolves against the post's pretty URL and 404s
    body <- gsub("(src\\s*=\\s*[\"'])\\./", "\\1/", body)
    body <- gsub("(!\\[[^]]*\\]\\()\\./", "\\1/", body)
  }
  if (bundle) {
    res <- setdiff(list.files(dirname(file), full.names = TRUE),
                   list.files(dirname(file), "[.](md|markdown|Rmd|Rmarkdown|html)$",
                              full.names = TRUE))
    if (length(res)) {
      dest <- file.path(root, "assets", "img", "posts", base)
      fs::dir_create(dest)
      for (r in res) {
        if (fs::is_dir(r)) fs::dir_copy(r, file.path(dest, basename(r)),
                                        overwrite = TRUE)
        else fs::file_copy(r, file.path(dest, basename(r)), overwrite = TRUE)
      }
      body <- gsub("(!\\[[^]]*\\]\\()(?!(?:[a-z+]+:)?//|/|\\{\\{)([^)]+\\))",
                   sprintf("\\1{{ site.baseurl }}/assets/img/posts/%s/\\2",
                           base),
                   body, perl = TRUE)
    }
  }

  sc <- convert_shortcodes(body)
  sc$body <- escape_liquid(tag_tables(convert_pandoc_attrs(sc$body)))

  out <- list(layout = "post",
              title = fm$meta$title %||% gsub("-", " ", slug),
              date = date)
  for (k in c("author", "authors", "description", "subtitle", "tags",
              "categories")) {
    if (!is.null(fm$meta[[k]])) out[[k]] <- fm$meta[[k]]
  }
  if (draft) out$published <- FALSE
  if (!is.null(fm$meta$aliases)) {
    out$redirect_from <- as.list(fm$meta$aliases)
  }

  xfun::write_utf8(c(
    "---",
    strsplit(yaml::as.yaml(out), "\n")[[1]],
    "---",
    sc$body
  ), target)

  list(target = target, draft = draft, shortcodes = sc$remaining,
       classes = sc$classes, skipped = FALSE)
}

# Split a post into front matter (YAML --- or TOML +++) and body. Leading
# blank lines are tolerated (Hugo does the same).
split_front_matter <- function(lines) {
  while (length(lines) && !nzchar(trimws(lines[1]))) lines <- lines[-1]
  if (!length(lines)) return(NULL)
  delim <- if (grepl("^---\\s*$", lines[1])) "^---\\s*$" else
           if (grepl("^\\+\\+\\+\\s*$", lines[1])) "^\\+\\+\\+\\s*$" else
           return(NULL)
  end <- grep(delim, lines[-1])
  if (!length(end)) return(NULL)
  end <- end[1] + 1
  header <- if (end > 2) lines[2:(end - 1)] else character()
  meta <- if (delim == "^---\\s*$") {
    tryCatch(yaml::yaml.load(paste(header, collapse = "\n")),
             error = function(e) NULL)
  } else {
    parse_toml_simple(header)
  }
  if (is.null(meta)) return(NULL)
  list(meta = meta, body = if (end < length(lines)) lines[(end + 1):length(lines)]
                           else character())
}

# Minimal TOML front matter parser: flat `key = value` lines with string,
# boolean, number, date or one-line array values -- which covers Hugo front
# matter in practice. Section tables ([params]) are ignored.
parse_toml_simple <- function(lines) {
  meta <- list()
  in_section <- FALSE
  for (l in lines) {
    if (grepl("^\\s*(#|$)", l)) next
    if (grepl("^\\s*\\[", l)) { in_section <- TRUE; next }
    if (in_section) next
    m <- regmatches(l, regexec("^\\s*([A-Za-z0-9_-]+)\\s*=\\s*(.+?)\\s*$", l))[[1]]
    if (length(m) != 3) next
    meta[[m[2]]] <- toml_value(strip_toml_comment(m[3]))
  }
  meta
}

# Full-file TOML parser for Hugo configs: handles top-level keys, nested
# [section.sub] tables and [[array.of.tables]] (menus). Values as in
# toml_value. Good enough for real-world Hugo configs; not a general TOML
# implementation.
parse_toml_config <- function(lines) {
  root <- list()
  path <- character()
  in_array <- FALSE
  for (l in lines) {
    if (grepl("^\\s*(#|$)", l)) next
    m <- regmatches(l, regexec(
      "^\\s*\\[\\[\\s*([A-Za-z0-9_.-]+)\\s*\\]\\]\\s*$", l))[[1]]
    if (length(m) == 2) {
      path <- strsplit(m[2], ".", fixed = TRUE)[[1]]
      cur <- nested_get(root, path) %||% list()
      cur[[length(cur) + 1]] <- list()
      root <- nested_set(root, path, cur)
      in_array <- TRUE
      next
    }
    m <- regmatches(l, regexec(
      "^\\s*\\[\\s*([A-Za-z0-9_.-]+)\\s*\\]\\s*$", l))[[1]]
    if (length(m) == 2) {
      path <- strsplit(m[2], ".", fixed = TRUE)[[1]]
      if (is.null(nested_get(root, path))) {
        root <- nested_set(root, path, list())
      }
      in_array <- FALSE
      next
    }
    m <- regmatches(l, regexec("^\\s*([A-Za-z0-9_-]+)\\s*=\\s*(.+?)\\s*$",
                               l))[[1]]
    if (length(m) != 3) next
    value <- toml_value(strip_toml_comment(m[3]))
    if (!length(path)) {
      root[[m[2]]] <- value
    } else if (in_array) {
      cur <- nested_get(root, path)
      cur[[length(cur)]][[m[2]]] <- value
      root <- nested_set(root, path, cur)
    } else {
      cur <- nested_get(root, path) %||% list()
      cur[[m[2]]] <- value
      root <- nested_set(root, path, cur)
    }
  }
  root
}

nested_get <- function(x, path) {
  for (p in path) {
    x <- x[[p]]
    if (is.null(x)) return(NULL)
  }
  x
}

nested_set <- function(x, path, value) {
  if (!length(path)) return(value)
  x[[path[1]]] <- nested_set(x[[path[1]]] %||% list(), path[-1], value)
  x
}

# Drop a trailing `# comment` from a raw TOML value (respecting quotes).
strip_toml_comment <- function(v) {
  if (grepl('^"', v)) sub('^("(?:[^"\\\\]|\\\\.)*").*$', "\\1", v)
  else if (grepl("^'", v)) sub("^('[^']*').*$", "\\1", v)
  else sub("\\s+#.*$", "", v)
}

toml_value <- function(v) {
  if (grepl("^\\[", v)) {
    items <- regmatches(v, gregexpr('"[^"]*"|\'[^\']*\'|[^,\\[\\]\\s]+', v))[[1]]
    return(unname(vapply(items, toml_value, "")))
  }
  if (grepl('^".*"$', v) || grepl("^'.*'$", v)) return(substr(v, 2, nchar(v) - 1))
  if (v %in% c("true", "false")) return(v == "true")
  v
}

# Normalize a front matter date of any common type/format to YYYY-MM-DD.
fm_date <- function(x) {
  if (is.null(x) || !length(x)) return(NA_character_)
  s <- substr(as.character(x[1]), 1, 10)
  if (grepl("^\\d{4}-\\d{2}-\\d{2}$", s)) s else NA_character_
}

# Convert the shortcodes with clean Markdown/HTML equivalents; report the
# rest. Returns list(body, remaining = character vector of shortcode
# names, classes = figure classes seen -- their display size lives in the
# Hugo theme CSS, which port_figure_classes() carries over).
convert_shortcodes <- function(body) {
  # blogdown wraps bundle resources as {{< blogdown/postref >}}index_files/…
  # in its rendered .markdown; the prefix resolves to the page's own URL,
  # which is exactly where the migrated relative link already points, so it
  # just goes away
  body <- gsub("\\{\\{[<%]\\s*blogdown/postref\\s*[>%]\\}\\}", "", body)

  # {{< figure src="..." caption="..." class="..." >}} -> Markdown image,
  # with class/width/height kept as a kramdown inline attribute list
  # (both the {{< >}} and {{% %}} delimiters appear in the wild)
  fig <- "\\{\\{[<%]\\s*figure\\s+([^>}]*?)\\s*[>%]\\}\\}"
  classes <- character()
  body <- vapply(body, function(l) {
    m <- regmatches(l, regexec(fig, l))[[1]]
    if (length(m) < 2) return(l)
    attr_of <- function(a) {
      x <- regmatches(m[2], regexec(sprintf('%s\\s*=\\s*"([^"]*)"', a), m[2]))[[1]]
      if (length(x) == 2) x[2] else ""
    }
    src <- attr_of("src")
    cap <- attr_of("caption")
    if (!nzchar(cap)) cap <- attr_of("title")
    if (!nzchar(cap)) cap <- attr_of("alt")
    if (!nzchar(src)) return(l)
    cls <- attr_of("class")
    if (nzchar(cls)) classes <<- c(classes, strsplit(cls, "\\s+")[[1]])
    ial <- c(if (nzchar(cls)) paste0(".", strsplit(cls, "\\s+")[[1]]),
             if (nzchar(attr_of("width")))
               sprintf('width="%s"', attr_of("width")),
             if (nzchar(attr_of("height")))
               sprintf('height="%s"', attr_of("height")))
    img <- sprintf("![%s](%s)", cap, src)
    if (length(ial)) img <- paste0(img, "{: ", paste(ial, collapse = " "), "}")
    sub(fig, img, l)
  }, "", USE.NAMES = FALSE)

  # {{< youtube ID >}} (or the {{% %}} form, quoted or not) -> iframe
  yt <- '\\{\\{[<%]\\s*youtube\\s+"?([A-Za-z0-9_-]+)"?\\s*[>%]\\}\\}'
  body <- gsub(yt, paste0(
    '<iframe src="https://www.youtube.com/embed/\\1" width="560" ',
    'height="315" frameborder="0" allowfullscreen></iframe>'), body)

  left <- regmatches(body, gregexpr("\\{\\{[<%]\\s*/?([A-Za-z0-9_-]+)", body))
  left <- unique(gsub("\\{\\{[<%]\\s*/?", "", unlist(left)))
  list(body = body, remaining = left, classes = unique(classes))
}

# Jekyll runs Liquid over every post body before Markdown, so a literal
# {{ or {% in migrated content (LaTeX math, Go/Hugo template snippets,
# mustache examples...) aborts the whole build with a Liquid syntax
# error. Escape both -- except the {{ site.baseurl }} links this package
# generates itself, and the {% raw %} markers the escaping introduces.
escape_liquid <- function(body) {
  body <- gsub("\\{\\{(?!\\s*site\\.)", "{% raw %}{{{% endraw %}", body,
               perl = TRUE)
  gsub("\\{%(?!\\s*(raw|endraw)\\b)", "{% raw %}{%{% endraw %}", body,
       perl = TRUE)
}

# Pandoc attaches image attributes as ![](x){width=100%}; kramdown needs an
# inline attribute list with quoted values: ![](x){: width="100%"}. Without
# the conversion the braces show up as literal text in the rendered post.
convert_pandoc_attrs <- function(body) {
  # (?!:) skips braces that are already a kramdown IAL, e.g. from a
  # converted figure shortcode
  body <- gsub("(!\\[[^]]*\\]\\([^)]*\\))\\{\\s*(?!:)([^}]+?)\\s*\\}",
               "\\1{: \\2}", body, perl = TRUE)
  vapply(body, function(l) {
    r <- gregexpr("\\{:[^}]*\\}", l)
    regmatches(l, r) <- lapply(regmatches(l, r), function(x)
      gsub("([A-Za-z-]+)=([^\"'[:space:]}]+)", '\\1="\\2"', x))
    l
  }, "", USE.NAMES = FALSE)
}

# Publications page -> _bibliography/papers.bib, deterministically: extract
# the DOIs (a DOI is unambiguous), fetch each reference as authoritative
# BibTeX from doi.org (Crossref/DataCite content negotiation), and let
# jekyll-scholar render the page. No parsing of the hand-written HTML
# beyond pairing a preview image with the nearest DOI in the same block.
migrate_publications_bib <- function(src, root, nav_order, from = NULL) {
  res <- list(entries = 0L, failed = character(), fallback = FALSE,
              markdown = NULL)
  lines <- xfun::read_utf8(src)
  fm <- split_front_matter(lines)
  body <- if (is.null(fm)) lines else fm$body
  dois <- extract_dois(body)
  if (!length(dois)) {
    res$fallback <- TRUE
    return(res)
  }

  # Themes without jekyll-scholar (no _bibliography/) still deserve better
  # than the page's raw HTML, which kramdown mangles: rebuild it as a
  # clean Markdown list of formatted citations, fetched from doi.org --
  # the same authoritative source the BibTeX route uses.
  bib_dir <- file.path(root, "_bibliography")
  if (!dir.exists(bib_dir)) {
    fetchc <- getOption("jekylldown.citation_fetcher", fetch_citation)
    items <- character()
    for (doi in dois) {
      cite <- fetchc(doi)
      if (is.null(cite)) {
        res$failed <- c(res$failed, doi)
        next
      }
      # APA already ends with the DOI URL; swap it for a Markdown link
      # instead of printing it twice
      url <- paste0("https://doi.org/", doi)
      cite <- trimws(sub(paste0("\\Q", url, "\\E[.]?\\s*$"), "", cite,
                         perl = TRUE))
      items <- c(items, sprintf(
        "%d. %s [doi.org/%s](%s)", length(items) + 1L, cite, doi, url))
    }
    if (!length(items)) {
      res$fallback <- TRUE
      return(res)
    }
    res$entries <- length(items)
    res$markdown <- items
    return(res)
  }

  fetch <- getOption("jekylldown.bibtex_fetcher", fetch_bibtex)
  previews <- pair_previews(body)
  out <- character()
  for (doi in dois) {
    bib <- fetch(doi)
    if (is.null(bib)) {
      res$failed <- c(res$failed, doi)
      next
    }
    extras <- "bibtex_show={true},"
    img <- previews[[doi]]
    if (!is.null(img) && !is.null(from)) {
      img_src <- file.path(from, "static", sub("^/+", "", img))
      if (file.exists(img_src)) {
        pv_dir <- file.path(root, "assets", "img", "publication_preview")
        fs::dir_create(pv_dir)
        fs::file_copy(img_src, file.path(pv_dir, basename(img_src)),
                      overwrite = TRUE)
        extras <- paste0(sprintf("preview={%s},", basename(img_src)),
                         " ", extras)
      }
    }
    # inject al-folio's extra fields right after `@type{key,`
    bib[1] <- sub("^(\\s*@[A-Za-z]+\\{[^,]+,)", paste0("\\1 ", extras),
                  bib[1])
    out <- c(out, bib, "")
  }
  if (!length(out)) {
    res$fallback <- TRUE
    return(res)
  }

  xfun::write_utf8(out, file.path(bib_dir, "papers.bib"))
  # al-folio's own bib-driven publications page takes the menu position
  pubs <- file.path(root, "_pages", "publications.md")
  if (file.exists(pubs)) {
    xfun::write_utf8(
      set_yaml_line(xfun::read_utf8(pubs), "nav_order", nav_order), pubs)
  }
  res$entries <- length(dois) - length(res$failed)
  res
}

doi_re <- "10\\.\\d{4,9}/[-._;()/:A-Za-z0-9]+"

# Unique DOIs in order of appearance, trailing punctuation stripped.
extract_dois <- function(lines) {
  dois <- unlist(regmatches(lines, gregexpr(doi_re, lines)))
  unique(sub("[.,;)\"']+$", "", dois))
}

# Map each DOI to the nearest preceding <img src="..."> in the same HTML
# block (publication lists typically show a journal cover per entry).
pair_previews <- function(lines) {
  out <- list()
  img_re <- '<img[^>]*src="([^"]+)"'
  for (i in seq_along(lines)) {
    dois <- regmatches(lines[i], gregexpr(doi_re, lines[i]))[[1]]
    if (!length(dois)) next
    doi <- sub("[.,;)\"']+$", "", dois[1])
    if (!is.null(out[[doi]])) next
    for (j in i:max(1L, i - 6L)) {
      if (j < i && grepl("</div>", lines[j], fixed = TRUE)) break
      m <- regmatches(lines[j], regexec(img_re, lines[j]))[[1]]
      if (length(m) == 2) {
        out[[doi]] <- m[2]
        break
      }
    }
  }
  out
}

# Figure classes carry their display size in the Hugo theme's CSS. Port
# each class rule into the Jekyll site's CSS: find the rule in the Hugo
# theme's css/scss/sass, resolve `$var` values, and rewrite the selector
# for kramdown output (the class lands on the <img> itself, so
# `.pkg > img` becomes `img.pkg`).
port_figure_classes <- function(from, root, classes) {
  res <- list(ported = character(), missing = character())
  classes <- unique(classes)
  if (!length(classes)) return(res)

  files <- unlist(lapply(file.path(from, c("assets", "themes", "static")),
                         function(d) list.files(d, "[.](css|scss|sass)$",
                                                recursive = TRUE,
                                                full.names = TRUE)))
  lines <- unlist(lapply(files, xfun::read_utf8))
  vars <- sass_vars(lines)

  blocks <- character()
  for (cl in classes) {
    b <- extract_class_css(lines, cl, vars)
    if (is.null(b)) {
      res$missing <- c(res$missing, cl)
    } else {
      blocks <- c(blocks, b, "")
      res$ported <- c(res$ported, cl)
    }
  }
  if (!length(res$ported)) return(res)

  target <- site_css_file(root)
  if (is.null(target)) {
    res$missing <- union(res$missing, res$ported)
    res$ported <- character()
    return(res)
  }
  append_marked_block(
    target,
    "/* >>> jekylldown figure styles (ported from the Hugo theme) */",
    "/* <<< jekylldown figure styles */",
    blocks)
  res
}

# Flat `$name: value;` declarations across the theme's sass files.
sass_vars <- function(lines) {
  m <- regmatches(lines,
                  regexec("^\\s*\\$([A-Za-z0-9_-]+)\\s*:\\s*([^;!]+?)\\s*(!default)?\\s*;",
                          lines))
  m <- Filter(function(x) length(x) >= 3, m)
  stats::setNames(vapply(m, `[`, "", 3), vapply(m, `[`, "", 2))
}

subst_sass_vars <- function(lines, vars) {
  for (. in 1:3) {
    for (nm in names(vars)) {
      lines <- gsub(paste0("\\$", nm, "\\b"), vars[[nm]], lines)
    }
    if (!any(grepl("\\$", lines))) break
  }
  lines
}

# The first rule block whose selector targets `.cl` (possibly nested sass;
# nesting context is dropped, which is what we want -- the rule must apply
# directly in the new site).
extract_class_css <- function(lines, cl, vars) {
  sel_re <- sprintf("\\.%s\\b[^{;]*\\{\\s*$", cl)
  start <- grep(sel_re, lines)
  if (!length(start)) return(NULL)
  start <- start[1]
  body <- character()
  depth <- 1
  j <- start
  while (depth > 0 && j < length(lines)) {
    j <- j + 1
    depth <- depth +
      lengths(regmatches(lines[j], gregexpr("\\{", lines[j]))) -
      lengths(regmatches(lines[j], gregexpr("\\}", lines[j])))
    if (depth > 0) body <- c(body, lines[j])
  }
  sel <- transform_selector(trimws(sub("\\{\\s*$", "", lines[start])), cl)
  c(paste0(sel, " {"), subst_sass_vars(body, vars), "}")
}

# In Hugo, figure classes sit on the <figure> wrapper; kramdown IALs put
# them on the <img> itself -- except on themes that post-process content
# images (Chirpy wraps them in an <a> and moves the class there), so the
# ported rule targets both shapes.
transform_selector <- function(sel, cl) {
  if (grepl(sprintf("^(figure)?\\.%s\\s*>?\\s*img$", cl), sel)) {
    return(sprintf("img.%s, .%s img", cl, cl))
  }
  if (grepl(sprintf("^figure\\.%s$", cl), sel)) return(sprintf(".%s", cl))
  sel
}

# One reference as BibTeX from doi.org content negotiation; NULL on any
# failure (offline, unknown DOI, unexpected payload).
# A formatted citation (APA) for a DOI, from doi.org content negotiation
# -- the same authoritative source as the BibTeX route, as plain text.
fetch_citation <- function(doi) {
  tmp <- tempfile(fileext = ".txt")
  on.exit(unlink(tmp))
  ok <- tryCatch(
    utils::download.file(
      paste0("https://doi.org/", doi), tmp, quiet = TRUE,
      headers = c(Accept = "text/x-bibliography; style=apa; locale=en-US")
    ) == 0,
    error = function(e) FALSE, warning = function(w) FALSE)
  if (!ok || !file.exists(tmp)) return(NULL)
  txt <- trimws(paste(xfun::read_utf8(tmp), collapse = " "))
  if (nzchar(txt)) txt else NULL
}

fetch_bibtex <- function(doi) {
  tmp <- tempfile(fileext = ".bib")
  on.exit(unlink(tmp))
  ok <- tryCatch(
    utils::download.file(paste0("https://doi.org/", doi), tmp, quiet = TRUE,
                         headers = c(Accept = "application/x-bibtex")) == 0,
    error = function(e) FALSE, warning = function(w) FALSE)
  if (!ok || !file.exists(tmp)) return(NULL)
  bib <- xfun::read_utf8(tmp)
  bib <- bib[nzchar(trimws(bib))]
  if (!length(bib) || !grepl("^\\s*@", bib[1])) return(NULL)
  bib
}

# --- social links ----------------------------------------------------------
# al-folio renders an icon row from `_data/socials.yml`, which the theme
# ships filled with demo profiles. Recognize the user's own profiles in the
# Hugo *pages* (contact/about/sections -- posts are excluded, they may link
# to other people's profiles) and rewrite the file with what was found.
#
# Only profile-shaped URLs count: a GitHub link with a repository path is a
# project link, not the site owner's profile, so every pattern is anchored
# at the end of the URL.
social_url_patterns <- c(
  github_username       = "github\\.com/([A-Za-z0-9-]+)/?",
  gitlab_username       = "gitlab\\.com/([A-Za-z0-9._-]+)/?",
  linkedin_username     = "linkedin\\.com/in/([A-Za-z0-9._-]+)/?",
  x_username            = "(?:twitter|x)\\.com/([A-Za-z0-9_]+)/?",
  scholar_userid        = "scholar\\.google\\.[a-z.]+/citations\\?user=([A-Za-z0-9_-]+).*",
  orcid_id              = "orcid\\.org/([0-9X-]+)/?",
  research_gate_profile = "researchgate\\.net/profile/([A-Za-z0-9_-]+)/?",
  stackoverflow_id      = "stackoverflow\\.com/users/([0-9]+)(?:/[A-Za-z0-9._-]+)?/?",
  medium_username       = "medium\\.com/@([A-Za-z0-9._-]+)/?",
  telegram_username     = "t\\.me/([A-Za-z0-9_]+)/?",
  instagram_id          = "instagram\\.com/([A-Za-z0-9._]+)/?",
  facebook_id           = "facebook\\.com/([A-Za-z0-9.]+)/?",
  youtube_id            = "youtube\\.com/@([A-Za-z0-9._-]+)/?",
  kaggle_id             = "kaggle\\.com/([A-Za-z0-9]+)/?"
)

# The Hugo files worth scanning for the owner's profiles: top-level pages
# (contact.md, about.md, ...) and section _index pages, but never posts.
social_sources <- function(from) {
  content <- file.path(from, "content")
  files <- list.files(content, "[.](md|markdown|Rmd|Rmarkdown)$",
                      full.names = TRUE)
  sections <- setdiff(list.dirs(content, recursive = FALSE),
                      file.path(content, c("post", "posts", "blog")))
  idx <- file.path(rep(sections, each = 2),
                   c("_index.md", "_index.markdown"))
  c(files, idx[file.exists(idx)])
}

# Pull recognizable profile URLs, the first mailto: address and a CV/resume
# PDF link out of a blob of page text. Returns a named character vector in
# a stable display order.
extract_socials <- function(text) {
  text <- paste(text, collapse = "\n")
  out <- c(character(0))

  emails <- unlist(regmatches(text, gregexpr("mailto:[^\\s)\"'>\\]]+", text,
                                             perl = TRUE)))
  if (length(emails)) {
    out[["email"]] <- sub("[?].*$", "", sub("^mailto:", "", emails[[1]]))
  }

  # markdown/href targets ending in .pdf whose file name says CV/resume
  pdfs <- unlist(regmatches(
    text, gregexpr("[(\"']((?:https?://[^\\s\"')]+)?/[^\\s\"')]+[.]pdf)[)\"']",
                   text, perl = TRUE)))
  pdfs <- sub("^[(\"']", "", sub("[)\"']$", "", pdfs))
  is_cv <- grepl("resume|curriculum|(^|[^a-z])cv([^a-z]|$)",
                 basename(pdfs), ignore.case = TRUE)
  if (any(is_cv)) out[["cv_pdf"]] <- pdfs[is_cv][[1]]

  urls <- unlist(regmatches(text, gregexpr("https?://[^\\s)\"'>\\]]+", text,
                                           perl = TRUE)))
  urls <- sub("[.,;]+$", "", urls)
  for (key in names(social_url_patterns)) {
    re <- paste0("^https?://(?:www\\.)?", social_url_patterns[[key]], "$")
    m <- regmatches(urls, regexec(re, urls, perl = TRUE))
    hits <- unique(unlist(lapply(m, function(x) if (length(x) >= 2) x[[2]])))
    if (length(hits)) out[[key]] <- hits[[1]]
  }
  out
}

# Write the profiles found in the Hugo pages where the theme shows them:
# al-folio's _data/socials.yml, Chirpy's config (`social:` block plus
# github/twitter usernames), or Minimal Mistakes' `author:` block
# (with the avatar found by migrate_home()). Returns the keys written.
migrate_socials <- function(from, root, hugo = NULL, avatar = NULL) {
  files <- social_sources(from)
  if (!length(files)) return(character())
  socials <- as.list(extract_socials(unlist(lapply(files, xfun::read_utf8))))
  if (!length(socials)) return(character())

  theme <- site_theme(root)
  if (theme == "chirpy") {
    return(migrate_socials_chirpy(root, socials, hugo))
  }
  if (theme == "minimal-mistakes") {
    return(migrate_socials_mm(root, socials, hugo, avatar))
  }

  data_file <- file.path(root, "_data", "socials.yml")
  if (!file.exists(data_file)) return(character())
  xfun::write_utf8(c(
    "# Social links migrated from the Hugo site.",
    sprintf('%s: "%s"', names(socials), socials),
    "rss_icon: true"
  ), data_file)
  names(socials)
}

# Rebuild a profile URL from an extracted username/id, for themes that
# want full links rather than per-network keys.
social_url_templates <- c(
  github_username       = "https://github.com/%s",
  gitlab_username       = "https://gitlab.com/%s",
  linkedin_username     = "https://www.linkedin.com/in/%s/",
  x_username            = "https://x.com/%s",
  scholar_userid        = "https://scholar.google.com/citations?user=%s",
  orcid_id              = "https://orcid.org/%s",
  research_gate_profile = "https://www.researchgate.net/profile/%s",
  stackoverflow_id      = "https://stackoverflow.com/users/%s",
  medium_username       = "https://medium.com/@%s",
  telegram_username     = "https://t.me/%s",
  instagram_id          = "https://www.instagram.com/%s",
  facebook_id           = "https://www.facebook.com/%s",
  youtube_id            = "https://www.youtube.com/@%s",
  kaggle_id             = "https://www.kaggle.com/%s"
)

social_urls <- function(socials) {
  keys <- intersect(names(socials), names(social_url_templates))
  stats::setNames(
    vapply(keys, function(k) sprintf(social_url_templates[[k]],
                                     socials[[k]]), ""),
    keys)
}

# Chirpy: social.name/email/links drive the sidebar contact area; the
# github/twitter usernames feed their dedicated buttons.
migrate_socials_chirpy <- function(root, socials, hugo) {
  config <- file.path(root, "_config.yml")
  lines <- xfun::read_utf8(config)
  urls <- social_urls(socials)

  if (!is.null(socials[["github_username"]])) {
    lines <- set_block_value(lines, "github", "username",
                             socials[["github_username"]])
  }
  if (!is.null(socials[["x_username"]])) {
    lines <- set_block_value(lines, "twitter", "username",
                             socials[["x_username"]])
  }
  name <- hugo$home_title %||% hugo$author %||% hugo$title
  block <- c(
    if (!is.null(name)) sprintf("  name: %s", name),
    if (!is.null(socials[["email"]]))
      sprintf("  email: %s", socials[["email"]]),
    if (length(urls)) c("  links:", sprintf("    - %s", urls))
  )
  lines <- replace_top_block(lines, "social", block)
  xfun::write_utf8(lines, config)
  names(socials)
}

# Minimal Mistakes: the author block renders the sidebar profile --
# name, avatar and one link entry (label/icon/url) per network.
mm_link_icons <- c(
  email                 = "fas fa-fw fa-envelope",
  cv_pdf                = "fas fa-fw fa-file-pdf",
  github_username       = "fab fa-fw fa-github",
  gitlab_username       = "fab fa-fw fa-gitlab",
  linkedin_username     = "fab fa-fw fa-linkedin",
  x_username            = "fab fa-fw fa-square-x-twitter",
  scholar_userid        = "fas fa-fw fa-graduation-cap",
  orcid_id              = "fab fa-fw fa-orcid",
  research_gate_profile = "fab fa-fw fa-researchgate",
  stackoverflow_id      = "fab fa-fw fa-stack-overflow",
  medium_username       = "fab fa-fw fa-medium",
  telegram_username     = "fab fa-fw fa-telegram",
  instagram_id          = "fab fa-fw fa-instagram",
  facebook_id           = "fab fa-fw fa-facebook",
  youtube_id            = "fab fa-fw fa-youtube",
  kaggle_id             = "fab fa-fw fa-kaggle"
)

mm_link_labels <- c(
  email = "Email", cv_pdf = "CV", github_username = "GitHub",
  gitlab_username = "GitLab", linkedin_username = "LinkedIn",
  x_username = "X", scholar_userid = "Google Scholar",
  orcid_id = "ORCID", research_gate_profile = "ResearchGate",
  stackoverflow_id = "StackOverflow", medium_username = "Medium",
  telegram_username = "Telegram", instagram_id = "Instagram",
  facebook_id = "Facebook", youtube_id = "YouTube", kaggle_id = "Kaggle"
)

migrate_socials_mm <- function(root, socials, hugo, avatar) {
  config <- file.path(root, "_config.yml")
  lines <- xfun::read_utf8(config)

  urls <- social_urls(socials)
  if (!is.null(socials[["email"]])) {
    urls <- c(c(email = paste0("mailto:", socials[["email"]])), urls)
  }
  if (!is.null(socials[["cv_pdf"]])) {
    urls <- c(urls, c(cv_pdf = socials[["cv_pdf"]]))
  }
  entries <- unlist(lapply(names(urls), function(k) c(
    sprintf('    - label: "%s"', mm_link_labels[[k]]),
    sprintf('      icon: "%s"', mm_link_icons[[k]]),
    sprintf("      url: %s", urls[[k]])
  )))

  name <- hugo$home_title %||% hugo$author %||% hugo$title
  block <- c(
    if (!is.null(name)) sprintf('  name: "%s"', name),
    if (!is.null(avatar)) sprintf("  avatar: %s", avatar),
    if (length(entries)) c("  links:", entries)
  )
  lines <- replace_top_block(lines, "author", block)
  xfun::write_utf8(lines, config)
  names(socials)
}

# Replace (or append) a top-level YAML block `key:` and its indented body.
replace_top_block <- function(lines, key, block) {
  i <- grep(sprintf("^%s:", key), lines)
  if (length(i)) {
    j <- i[1] + 1
    while (j <= length(lines) && grepl("^\\s+\\S", lines[j])) j <- j + 1
    lines <- lines[-(i[1]:(j - 1))]
  }
  c(lines, sprintf("%s:", key), block)
}

`%||%` <- function(a, b) if (is.null(a)) b else a
