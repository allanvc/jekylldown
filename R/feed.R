# Atom feeds rendered from a site-level copy of jekyll-feed's template.
#
# Why a copy: al-folio's `_config.yml` uses `title: blank` to mean "build
# the site title from first/middle/last name". The theme's layouts
# understand that convention; jekyll-feed does not, and prints the
# literal word "blank" as the feed title. Changing `title` instead would
# alter other theme output (al-folio adds `journal = {<title>}` to the
# BibTeX it generates for posts), so the fix lives in the feed template.
#
# Where the copy comes from, in order: the jekyll-feed gem installed for
# the site (the version pinned in Gemfile.lock -- what the local build
# and the deploy workflow render with); that same version's tag on
# GitHub when the gem is not installed yet; the copy shipped in
# inst/jekyll-feed/ as a last resort. The patch is a textual replacement
# of one anchor line, and aborts loudly if upstream ever moves it.
#
# jekyll-feed skips generating any feed whose file already exists in the
# site, so `feed.xml` and `feed/<category>.xml` become one-line pages
# that render the include. The template needs only core Liquid filters,
# so the pages work even on sites without the plugin.

feed_include <- "atom-feed.xml"
feed_anchor <- "{% assign title = site.title | default: site.name %}"
feed_content_anchor <- paste0(
  '<content type="html" xml:base="{{ post.url | absolute_url | xml_escape }}">',
  "<![CDATA[{{ post.content | strip }}]]></content>")
feed_marker <- "jekylldown: rendered from jekyll-feed"
feed_bundled_version <- "0.17.0"

rb_begin <- "<!-- >>> jekylldown r-bloggers -->"
rb_close <- "<!-- <<< jekylldown r-bloggers -->"

#' Atom feeds with a correct title, optionally per category
#'
#' Writes a site-level copy of jekyll-feed's template to
#' `_includes/atom-feed.xml` and the feed pages that render it:
#' `feed.xml` with every post, plus `feed/<category>.xml` for each
#' `category`. A category feed carries the full text of the posts whose
#' `categories` front-matter entry contains that value. The match is
#' verbatim, so `"R"` and `"r"` are different categories. Aggregators
#' such as R-Bloggers require exactly that kind of feed; see
#' [use_r_bloggers()] for the one-call setup.
#'
#' The copy differs from the plugin's template in one place. al-folio
#' sets `title: blank` in `_config.yml` to mean "build the site title
#' from the author's name". The theme's layouts follow that convention,
#' but jekyll-feed does not, and prints the literal word "blank" as the
#' feed title. The copy handles that case and leaves the title of every
#' other theme as it is.
#'
#' The template is taken from the jekyll-feed gem installed for the
#' site, at the version pinned in `Gemfile.lock`. That is the version
#' the local build and the deploy workflow render with, so the include
#' follows the plugin instead of freezing a copy inside jekylldown. When
#' the gem is not installed yet, the template of that version is fetched
#' from GitHub. Offline, the copy shipped with the package is used. It is
#' a complete template, and the feed pages need no plugin at all. The
#' include records where it came from. Running the function again after
#' a gem upgrade regenerates it from the new version, and `force = TRUE`
#' regenerates it unconditionally. An `atom-feed.xml` you wrote yourself,
#' without the jekylldown marker, is never touched.
#'
#' Chirpy ships a main feed of its own at the same address, and Jekyll
#' keeps the theme's version of `feed.xml` on that theme. The
#' per-category feeds are jekylldown's on every theme.
#'
#' In the feeds, root-relative image and link paths in the post body
#' (`/assets/img/...`, which is what [knit_post()] writes) are made
#' absolute from `url:` in `_config.yml`. Feed readers are supposed to
#' resolve such paths against the entry's `xml:base`, but aggregators
#' such as R-Bloggers ask for absolute URLs, so the feed does not depend
#' on the reader.
#'
#' [new_site()] and [migrate_hugo()] already call this on al-folio
#' sites. Call it yourself on an existing site, or on any theme where
#' you want per-category feeds.
#'
#' @param category Optional character vector of post categories, one
#'   feed each at `feed/<category>.xml`. `NULL` (the default) writes the
#'   main feed only.
#' @param dir Site root, or any directory inside it. Like
#'   [build_site()], the function climbs to the enclosing site.
#' @param force Regenerate `_includes/atom-feed.xml` even when it is
#'   current.
#' @return Invisibly, the paths of the feed pages written or confirmed
#'   (the main feed first), with the include's path as attribute
#'   `"include"`.
#' @examples
#' \dontrun{
#' add_feed()                  # fix the feed title on an al-folio site
#' add_feed(category = "R")    # plus /feed/R.xml with the R posts only
#' }
#' @seealso [use_r_bloggers()]
#' @export
add_feed <- function(category = NULL, dir = ".", force = FALSE) {
  abort_if_site_path(category, "add_feed")
  root <- site_root(dir)
  inc <- ensure_feed_include(root, force = force)
  pages <- c(feed_page(root, NULL),
             vapply(category, function(x) feed_page(root, x), ""))
  cli::cli_alert_success(
    "Feed{?s} in place: {.file {fs::path_rel(pages, root)}}.")
  invisible(structure(unname(pages), include = inc))
}

#' Set a site up for R-Bloggers
#'
#' R-Bloggers (\url{https://www.r-bloggers.com/}) aggregates R posts from
#' a full-text feed that contains R content only, and asks for a link
#' back to it on the blog. This function does the site side of that
#' setup in one call. It writes an R-only feed at `feed/<category>.xml`
#' through [add_feed()], which also fixes the feed title on al-folio
#' sites. On al-folio it adds a line under the blog header with links to
#' the category, to R-Bloggers and to the feed. That line is a
#' marker-delimited block in `_pages/blog.md`, replaced on re-runs; a
#' link to R-Bloggers you wrote there yourself is left alone. On other
#' themes the HTML snippet is printed for you to place. Finally it
#' prints the feed URL to submit at
#' \url{https://www.r-bloggers.com/add-your-blog/} once the site is
#' published.
#'
#' Only posts whose front matter carries the category enter the feed:
#' `new_post("...", categories = "R")`, or `categories: R` by hand.
#' Posts about anything else stay out, which is what R-Bloggers asks.
#'
#' @param category The category that marks R posts; `"R"` by default.
#' @inheritParams add_feed
#' @return Invisibly, a list with `feed` (the feed page's path), `url`
#'   (the public feed URL, from the site's `url` and `baseurl`) and
#'   `link` (the page the link was added to, or `NULL`).
#' @examples
#' \dontrun{
#' use_r_bloggers()
#' }
#' @export
use_r_bloggers <- function(category = "R", dir = ".") {
  abort_if_site_path(category, "use_r_bloggers")
  if (!is.character(category) || length(category) != 1 ||
      !nzchar(trimws(category))) {
    cli::cli_abort("{.arg category} must be a single category name.")
  }
  root <- site_root(dir)
  feed <- add_feed(category, dir = root)[2]
  rel <- sprintf("/feed/%s.xml", category)
  url <- site_page_url(root, rel)
  link <- rb_add_link(root, category, rel)

  cli::cli_bullets(c(
    "*" = "Only posts with {.code categories: {category}} enter the feed
           ({.code new_post(..., categories = \"{category}\")}).",
    "*" = "Build, commit and publish the site, then submit the feed at
           {.url https://www.r-bloggers.com/add-your-blog/}:",
    " " = "{.url {url}}"
  ))
  invisible(list(feed = feed, url = url, link = link))
}

# --- the include ---------------------------------------------------------

# Write (or refresh) _includes/atom-feed.xml. Returns its path.
ensure_feed_include <- function(root, force = FALSE) {
  inc <- file.path(root, "_includes", feed_include)
  if (file.exists(inc)) {
    have <- feed_include_version(xfun::read_utf8(inc))
    if (is.na(have)) {
      cli::cli_alert_info(
        "{.file _includes/{feed_include}} is not managed by jekylldown
         (no marker); left as is.")
      return(inc)
    }
    if (!force) {
      gem <- feed_gem_template(root)
      if (is.null(gem) || identical(gem$version, have)) return(inc)
      cli::cli_alert_info(
        "jekyll-feed {gem$version} is installed; regenerating the include
         written from {have}.")
    }
  }
  tpl <- feed_template(root)
  lines <- patch_feed_template(tpl$lines, tpl$version, tpl$source)
  fs::dir_create(dirname(inc))
  xfun::write_utf8(lines, inc)
  cli::cli_alert_success(
    "Wrote {.file _includes/{feed_include}} from jekyll-feed
     {tpl$version} ({tpl$source}).")
  inc
}

# Version recorded in an include we wrote; NA when the marker is absent.
feed_include_version <- function(lines) {
  m <- regmatches(lines, regexpr(
    sprintf("%s ([0-9]+(?:[.][0-9]+)*)", feed_marker), lines, perl = TRUE))
  if (!length(m)) return(NA_character_)
  sub(sprintf("^%s ", feed_marker), "", m[1])
}

# The template, from the best available source:
#   list(lines, version, source) with source one of "gem", "github",
#   "bundled".
feed_template <- function(root) {
  gem <- feed_gem_template(root)
  if (!is.null(gem)) return(gem)

  version <- lock_feed_version(root)
  if (!is.null(version)) {
    lines <- fetch_feed_template(version)
    if (!is.null(lines)) {
      return(list(lines = lines, version = version, source = "github"))
    }
  }
  bundled <- system.file("jekyll-feed",
                         sprintf("feed-%s.xml", feed_bundled_version),
                         package = "jekylldown", mustWork = TRUE)
  reason <- if (is.null(version)) {
    "The jekyll-feed gem is not installed"
  } else {
    "The jekyll-feed gem is not installed and GitHub could not be reached"
  }
  cli::cli_alert_info(
    "{reason}; using the copy of its template shipped with jekylldown
     ({feed_bundled_version}). Re-run {.fn add_feed} after
     {.fn bundle_install} to pick up the site's own version.")
  list(lines = xfun::read_utf8(bundled), version = feed_bundled_version,
       source = "bundled")
}

# Version pinned in the site's Gemfile.lock, or NULL.
lock_feed_version <- function(root) {
  lock <- file.path(root, "Gemfile.lock")
  if (!file.exists(lock)) return(NULL)
  lines <- xfun::read_utf8(lock)
  pat <- "^\\s*jekyll-feed \\(([0-9]+(?:[.][0-9]+)*)\\)\\s*$"
  hit <- grep(pat, lines, perl = TRUE, value = TRUE)
  if (!length(hit)) return(NULL)
  sub(pat, "\\1", hit[1], perl = TRUE)
}

# The template of the installed gem, or NULL. The gem directory under
# jekylldown's isolated GEM_HOME is tried first (the locked version when
# known, else the newest); then `bundle show`, which also covers gems
# installed elsewhere by the user's own bundler setup.
feed_gem_template <- function(root) {
  version <- lock_feed_version(root)
  dirs <- Sys.glob(file.path(jd_gem_home(), "gems", "jekyll-feed-*"))
  dirs <- dirs[grepl("jekyll-feed-[0-9]+(?:[.][0-9]+)*$", dirs, perl = TRUE)]
  if (length(dirs)) {
    vers <- sub("^.*jekyll-feed-", "", dirs)
    pick <- if (!is.null(version) && version %in% vers) {
      dirs[match(version, vers)]
    } else {
      dirs[order(numeric_version(vers), decreasing = TRUE)][1]
    }
    file <- file.path(pick, "lib", "jekyll-feed", "feed.xml")
    if (file.exists(file)) {
      return(list(lines = xfun::read_utf8(file),
                  version = sub("^.*jekyll-feed-", "", pick),
                  source = "gem"))
    }
  }
  dir <- bundle_show(root, "jekyll-feed")
  if (!is.null(dir)) {
    file <- file.path(dir, "lib", "jekyll-feed", "feed.xml")
    if (file.exists(file)) {
      return(list(lines = xfun::read_utf8(file),
                  version = sub("^.*jekyll-feed-", "", basename(dir)),
                  source = "gem"))
    }
  }
  NULL
}

# `bundle show <gem>` in the site: the gem's directory, or NULL when
# bundler is unavailable, the site has no lockfile, or the gem is missing.
bundle_show <- function(root, gem) {
  if (!file.exists(file.path(root, "Gemfile.lock"))) return(NULL)
  bundle <- find_cmd("bundle")
  if (is.null(bundle)) return(NULL)
  sc <- shell_cmd(bundle, c("show", gem))
  res <- tryCatch(
    processx::run(sc$cmd, sc$args, wd = root, env = c("current", jd_env()),
                  error_on_status = FALSE, timeout = 60),
    error = function(e) NULL)
  if (is.null(res) || res$status != 0) return(NULL)
  dir <- trimws(utils::tail(strsplit(res$stdout, "\n", fixed = TRUE)[[1]], 1))
  if (nzchar(dir) && dir.exists(dir)) dir else NULL
}

# The template at a jekyll-feed release tag on GitHub, or NULL (offline,
# unknown tag). Never the default branch: it may be ahead of the plugin
# the site actually runs.
fetch_feed_template <- function(version) {
  url <- sprintf(
    "https://raw.githubusercontent.com/jekyll/jekyll-feed/v%s/lib/jekyll-feed/feed.xml",
    version)
  tmp <- tempfile(fileext = ".xml")
  on.exit(unlink(tmp), add = TRUE)
  ok <- tryCatch(
    suppressWarnings(utils::download.file(url, tmp, quiet = TRUE,
                                          mode = "wb")) == 0,
    error = function(e) FALSE)
  if (!ok || !file.exists(tmp)) return(NULL)
  lines <- xfun::read_utf8(tmp)
  if (!any(grepl("^<\\?xml", lines))) return(NULL)
  lines
}

# Replacement for the plugin's <content> line: the post body with
# root-relative `src="/..."` and `href="/..."` rewritten to absolute
# URLs when the site has a `url:` (a trailing slash there is tolerated:
# split/join drops it). Core Liquid only.
feed_content_block <- c(
  "{% comment %}",
  "  jekylldown: root-relative src/href in the post body become absolute",
  "  (from `url:` in _config.yml), as aggregators such as R-Bloggers ask.",
  "{% endcomment %}",
  "{% assign jd_host = site.url | default: \"\" | split: \"/\" | join: \"/\" %}",
  "{% capture jd_src %}src=\"{{ jd_host }}/{% endcapture %}",
  "{% capture jd_href %}href=\"{{ jd_host }}/{% endcapture %}",
  "{% assign jd_content = post.content | strip %}",
  "{% if jd_host != empty %}",
  paste0("  {% assign jd_content = jd_content",
         " | replace: 'src=\"//', 'src=\"jd:proto//'",
         " | replace: 'href=\"//', 'href=\"jd:proto//'",
         " | replace: 'src=\"/', jd_src",
         " | replace: 'href=\"/', jd_href",
         " | replace: 'src=\"jd:proto//', 'src=\"//'",
         " | replace: 'href=\"jd:proto//', 'href=\"//' %}"),
  "{% endif %}",
  paste0("<content type=\"html\" xml:base=\"{{ post.url | absolute_url | xml_escape }}\">",
         "<![CDATA[{{ jd_content }}]]></content>"))

# Apply the title patch and stamp the provenance marker. The anchor is
# the plugin's own title assignment; if upstream moves it, this is where
# the package should fail, loudly, instead of writing a broken feed.
patch_feed_template <- function(lines, version, source) {
  i <- which(trimws(lines) == feed_anchor)
  if (length(i) != 1) {
    cli::cli_abort(c(
      "The jekyll-feed template ({version}, {source}) does not have the
       line jekylldown patches: {.code {feed_anchor}}.",
      "i" = "jekyll-feed changed its template; jekylldown needs an update.
             Please report this at
             {.url https://github.com/allanvc/jekylldown/issues}.",
      "i" = "Meanwhile, write {.file _includes/{feed_include}} by hand
             (any file there without the jekylldown marker is left alone)."
    ))
  }
  indent <- sub("^(\\s*).*$", "\\1", lines[i])
  block <- paste0(indent, c(
    "{% comment %}",
    "  jekylldown: al-folio sets `title: blank` to mean \"use the author's",
    "  name\"; jekyll-feed alone prints the literal \"blank\" as the title.",
    "{% endcomment %}",
    "{% if site.title == 'blank' %}",
    "  {% capture title %}{{ site.first_name }} {{ site.middle_name }} {{ site.last_name }}{% endcapture %}",
    "  {% assign title = title | normalize_whitespace %}",
    "{% else %}",
    paste0("  ", feed_anchor),
    "{% endif %}"))
  lines <- append(lines[-i], block, after = i - 1)

  # Root-relative src/href in the post body become absolute, from `url:`
  # in _config.yml. Readers should resolve them against xml:base;
  # aggregators such as R-Bloggers ask for absolute URLs instead, so the
  # feed does not depend on the reader. Protocol-relative `//host/...`
  # paths are protected from the rewrite.
  j <- which(trimws(lines) == feed_content_anchor)
  if (length(j) == 1) {
    indent <- sub("^(\\s*).*$", "\\1", lines[j])
    lines <- append(lines[-j], paste0(indent, feed_content_block), after = j - 1)
  } else {
    cli::cli_warn(c(
      "The jekyll-feed template ({version}, {source}) does not have the
       content line jekylldown patches; image and link paths in the feed
       stay relative.",
      "i" = "Please report this at
             {.url https://github.com/allanvc/jekylldown/issues}."))
  }

  # the marker goes right after the XML declaration, never before it:
  # anything ahead of <?xml ?> makes the document ill-formed
  marker <- sprintf(
    "{%% comment %%}%s %s (%s). Regenerate with jekylldown::add_feed(force = TRUE); edits here are lost then.{%% endcomment %%}",
    feed_marker, version, source)
  decl <- grep("^<\\?xml", lines)
  append(lines, marker, after = if (length(decl)) decl[1] else 0)
}

# --- the pages -----------------------------------------------------------

# feed.xml (category NULL) or feed/<category>.xml. An existing file that
# does not render our include is the user's own and is left alone.
feed_page <- function(root, category = NULL) {
  path <- if (is.null(category)) {
    file.path(root, "feed.xml")
  } else {
    file.path(root, "feed", paste0(category, ".xml"))
  }
  if (file.exists(path)) {
    if (!any(grepl(feed_include, xfun::read_utf8(path), fixed = TRUE))) {
      cli::cli_alert_info(
        "{.file {fs::path_rel(path, root)}} exists and is not rendered from
         {.file _includes/{feed_include}}; left as is.")
    }
    return(path)
  }
  head <- if (is.null(category)) {
    "# Main Atom feed (every post)."
  } else {
    sprintf("# Atom feed with only the posts whose `categories` include \"%s\".",
            category)
  }
  fm <- c(
    "---",
    head,
    "# Rendered from _includes/atom-feed.xml, written by jekylldown::add_feed().",
    "layout: null",
    "sitemap: false",
    "collection: posts",
    if (!is.null(category)) sprintf("category: \"%s\"", category),
    "---",
    sprintf("{%%- include %s -%%}", feed_include))
  fs::dir_create(dirname(path))
  xfun::write_utf8(fm, path)
  path
}

# Public URL of a site path, from `url:` and `baseurl:` in _config.yml;
# the bare path when the config has no url.
site_page_url <- function(root, path) {
  config <- file.path(root, "_config.yml")
  lines <- if (file.exists(config)) xfun::read_utf8(config) else character()
  value <- function(key) {
    v <- grep(sprintf("^%s:", key), lines, value = TRUE)
    if (!length(v)) return("")
    v <- sub(sprintf("^%s:\\s*", key), "", v[1])
    v <- sub("\\s+#.*$", "", v)
    gsub("^[\"']|[\"']$", "", trimws(v))
  }
  url <- sub("/+$", "", value("url"))
  base <- sub("/+$", "", value("baseurl"))
  if (!nzchar(url)) return(paste0(base, path))
  paste0(url, base, path)
}

# --- the R-Bloggers link -------------------------------------------------

# al-folio: a marker-delimited paragraph under the blog page's header
# bar (after the front matter when the header block is not found). Other
# themes: print the snippet and return NULL.
rb_add_link <- function(root, category, feed_rel) {
  theme <- site_theme(root)
  page <- file.path(root, "_pages", "blog.md")
  if (theme != "al-folio" || !file.exists(page)) {
    cli::cli_alert_info(c(
      "R-Bloggers asks for a link back on the blog; add this where your
       theme lists posts:"))
    cli::cli_code(rb_snippet(category, feed_rel, archive = NULL,
                             icons = FALSE))
    return(NULL)
  }
  archive <- sprintf("/blog/category/%s/", slugify(category))
  block <- c(rb_begin,
             rb_snippet(category, feed_rel, archive, icons = TRUE),
             rb_close)
  lines <- xfun::read_utf8(page)
  b <- which(lines == rb_begin)
  e <- which(lines == rb_close)
  # a link written by hand (outside our markers) is the user's own:
  # leave the page alone instead of adding a second one
  if (!(length(b) && length(e)) &&
      any(grepl("r-bloggers.com", lines, fixed = TRUE))) {
    cli::cli_alert_info(
      "{.file _pages/blog.md} already links to R-Bloggers; left as is.")
    return(page)
  }
  if (length(b) && length(e)) {
    lines <- append(lines[-(b[1]:e[1])], block, after = b[1] - 1)
  } else {
    lines <- append(lines, c("", block), after = rb_insert_after(lines))
  }
  xfun::write_utf8(lines, page)
  cli::cli_alert_success(
    "Link to R-Bloggers added to {.file _pages/blog.md}.")
  page
}

# Line after which the link goes: the `{% endif %}` that closes the
# header-bar block, else the end of the front matter.
rb_insert_after <- function(lines) {
  header <- grep('class="header-bar"', lines, fixed = TRUE)
  if (length(header)) {
    endif <- grep("^\\s*\\{%\\s*endif\\s*%\\}", lines)
    endif <- endif[endif > header[1]]
    if (length(endif)) return(endif[1])
  }
  fm <- which(lines == "---")
  if (length(fm) >= 2) fm[2] else 0
}

rb_snippet <- function(category, feed_rel, archive, icons) {
  cat_html <- if (is.null(archive)) {
    category
  } else {
    sprintf("<a href=\"{{ '%s' | relative_url }}\">%s</a>", archive, category)
  }
  rss <- if (icons) '<i class="fa-solid fa-rss fa-sm"></i> ' else ""
  c(
    '<p class="text-center jekylldown-r-bloggers">',
    if (icons) '  <i class="fa-brands fa-r-project fa-sm"></i>',
    sprintf("  Posts in the %s category are syndicated on", cat_html),
    '  <a href="https://www.r-bloggers.com/" target="_blank" rel="noopener">R-Bloggers</a>',
    sprintf("  &bull; <a href=\"{{ '%s' | relative_url }}\">%s%s feed</a>",
            feed_rel, rss, category),
    "</p>")
}
