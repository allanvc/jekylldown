# Declarative theme customization, in four layers of decreasing robustness:
#
#   1. set_theme_style()   -- overrides the theme's own CSS variables
#   2. set_theme_font()    -- font family/size overrides (+ Google Fonts)
#   3. set_element_style() -- curated semantic element -> selector map
#   4. add_css()           -- managed free-form CSS blocks
#
# All of them write marker-delimited blocks into the site-local stylesheet
# (site_css_file()), so they are idempotent per concern, survive theme
# updates (a local main.scss shadows the gem's), and can be re-run to
# change or undo a customization.

# Semantic style option -> al-folio CSS variable. The variables are
# defined per light/dark mode in the theme's _sass/_themes.scss, so
# overriding them keeps dark mode working.
al_folio_style_vars <- c(
  accent            = "--global-theme-color",
  hover             = "--global-hover-color",
  background        = "--global-bg-color",
  text              = "--global-text-color",
  text_light        = "--global-text-color-light",
  divider           = "--global-divider-color",
  highlight         = "--global-highlight-color",
  code_background   = "--global-code-bg-color",
  card_background   = "--global-card-bg-color",
  footer_background = "--global-footer-bg-color",
  footer_text       = "--global-footer-text-color",
  footer_link       = "--global-footer-link-color"
)

# Semantic style option -> Chirpy CSS variable. Chirpy sets them through
# light-scheme/dark-scheme mixins on html[data-mode] selectors (plus a
# prefers-color-scheme media query when the visitor has no explicit mode).
chirpy_style_vars <- c(
  accent             = "--link-color",
  background         = "--main-bg",
  text               = "--text-color",
  text_light         = "--text-muted-color",
  heading            = "--heading-color",
  divider            = "--main-border-color",
  code_background    = "--highlight-bg-color",
  card_background    = "--card-bg",
  sidebar_background = "--sidebar-bg",
  sidebar_active     = "--sidebar-active-color"
)

#' Customize theme colors through the theme's own CSS variables
#'
#' al-folio and Chirpy define their palettes as CSS variables, with one
#' block per color scheme (light and dark). This function overrides those
#' variables from R -- the most robust customization layer, because the
#' theme's components all read from the variables, and light/dark mode
#' keeps working.
#'
#' Every option takes either a single color (applied to both modes) or a
#' vector like `c(light = "#ffffff", dark = "#1c1c1d")`. Colors can be a
#' `#hex` value or any CSS color (on al-folio, also a theme palette name
#' like `"red"` or `"blue"`). Re-running replaces the previous override.
#'
#' Options on **al-folio**: `accent` and `hover` (the accent color --
#' [set_theme_color()] is shorthand for both), `background`, `text`,
#' `text_light`, `divider`, `highlight`, `code_background`,
#' `card_background`, `footer_background`, `footer_text`, `footer_link`.
#'
#' Options on **Chirpy**: `accent` (the link color), `background`, `text`,
#' `text_light`, `heading`, `divider`, `code_background`,
#' `card_background`, `sidebar_background`, `sidebar_active`.
#'
#' **Minimal Mistakes** has no CSS variables (its palette is compiled from
#' Sass skins): use [set_theme_skin()] to switch skins, and
#' [set_element_style()]/[add_css()] for finer control. The same applies
#' to minima.
#'
#' This needs the theme gems: run [bundle_install()] once first.
#'
#' @param dir Site root.
#' @param ... Named style options from the list above.
#' @return Invisibly, the named list of CSS variables written.
#' @examples
#' \dontrun{
#' set_theme_style("my-site",
#'   accent = "red",
#'   footer_background = "#222222",
#'   background = c(light = "#fffdf7", dark = "#1c1c1d")
#' )
#' }
#' @export
set_theme_style <- function(dir = ".", ...) {
  root <- normalizePath(dir, mustWork = TRUE)
  theme <- site_theme(root)
  if (theme %in% c("minimal-mistakes", "minima")) {
    cli::cli_abort(c(
      "{.val {theme}} has no CSS variables for {.fn set_theme_style} to
       override.",
      "i" = if (theme == "minimal-mistakes") {
        "Pick a skin with {.fn set_theme_skin}, style parts with
         {.fn set_element_style}, or use {.fn add_css}."
      } else {
        "Use {.fn set_element_style} or {.fn add_css}."
      }))
  }
  vars_map <- if (theme == "chirpy") chirpy_style_vars else al_folio_style_vars

  opts <- list(...)
  if (!length(opts) || is.null(names(opts)) || any(!nzchar(names(opts)))) {
    cli::cli_abort(c("Pass named style options.",
                     "i" = "Available: {.val {names(vars_map)}}."))
  }
  unknown <- setdiff(names(opts), names(vars_map))
  if (length(unknown)) {
    cli::cli_abort(c("Unknown style option{?s}: {.val {unknown}}.",
                     "i" = "Available: {.val {names(vars_map)}}."))
  }

  main <- require_site_css(root)

  if (theme == "chirpy") {
    sass_text <- theme_sass_text(root, "jekyll-theme-chirpy-*")
    block <- chirpy_style_block(opts, vars_map)
  } else {
    sass <- find_theme_sass(root)
    sass_text <- paste(xfun::read_utf8(sass), collapse = "\n")
    modes <- theme_mode_selectors(sass)
    decls <- function(mode) {
      out <- character()
      for (nm in names(opts)) {
        v <- style_mode_value(opts[[nm]], mode)
        if (is.null(v)) next
        out <- c(out, sprintf("  %s: %s;", vars_map[[nm]],
                              resolve_css_color(v, sass)))
      }
      out
    }
    block <- character()
    for (mode in names(modes)) {
      d <- decls(mode)
      if (length(d)) block <- c(block, sprintf("%s {", modes[[mode]]), d, "}")
    }
  }

  if (nzchar(sass_text)) {
    missing <- setdiff(unname(vars_map[names(opts)]),
                       unlist(regmatches(sass_text,
                                         gregexpr("--[a-z-]+", sass_text))))
    if (length(missing)) {
      cli::cli_warn("Variable{?s} {.val {missing}} not found in the installed
                     theme's sass; the override may have no effect.")
    }
  }

  append_marked_block(
    main,
    "/* >>> jekylldown theme style (generated; change via set_theme_style) */",
    "/* <<< jekylldown theme style */",
    block)
  cli::cli_alert_success(
    "Theme style ({.val {names(opts)}}) written to {.file {basename(main)}}.")
  invisible(stats::setNames(as.list(vars_map[names(opts)]), names(opts)))
}

# Chirpy applies its schemes on html[data-mode] selectors, with a
# prefers-color-scheme media query when the visitor has not chosen a mode;
# the override mirrors that structure exactly.
chirpy_style_block <- function(opts, vars_map) {
  decls <- function(mode, indent = "  ") {
    out <- character()
    for (nm in names(opts)) {
      v <- style_mode_value(opts[[nm]], mode)
      if (!is.null(v)) {
        out <- c(out, sprintf("%s%s: %s;", indent, vars_map[[nm]], v))
      }
    }
    out
  }
  light <- decls("light")
  dark <- decls("dark")
  c(
    if (length(light)) {
      c("html:not([data-mode]), html[data-mode='light'] {", light, "}")
    },
    if (length(dark)) {
      c("html[data-mode='dark'] {", dark, "}",
        "@media (prefers-color-scheme: dark) {",
        "  html:not([data-mode]) {",
        decls("dark", indent = "    "),
        "  }",
        "}")
    }
  )
}

#' Pick a Minimal Mistakes skin
#'
#' Minimal Mistakes styles the whole site through Sass "skins" compiled
#' into the CSS (there are no CSS variables to override). This sets
#' `minimal_mistakes_skin` in `_config.yml`; the skin list is read from
#' the installed theme gem when available (`"default"`, `"air"`,
#' `"aqua"`, `"contrast"`, `"dark"`, `"dirt"`, `"mint"`, `"neon"`,
#' `"plum"`, `"sunrise"`, ...).
#'
#' @param dir Site root.
#' @param skin Skin name.
#' @return Invisibly, the skin set.
#' @examples
#' \dontrun{
#' set_theme_skin("my-site", "dark")
#' }
#' @export
set_theme_skin <- function(dir = ".", skin) {
  root <- normalizePath(dir, mustWork = TRUE)
  theme <- site_theme(root)
  if (theme != "minimal-mistakes") {
    cli::cli_abort("Skins are a Minimal Mistakes feature; this site uses
                    {.val {theme}}.")
  }
  known <- mm_skins(root)
  if (!skin %in% known) {
    cli::cli_abort(c("Unknown skin {.val {skin}}.",
                     "i" = "Available: {.val {known}}."))
  }
  config <- file.path(root, "_config.yml")
  xfun::write_utf8(
    set_yaml_line(xfun::read_utf8(config), "minimal_mistakes_skin",
                  sprintf('"%s"', skin), append = TRUE),
    config)
  cli::cli_alert_success("Skin set to {.val {skin}} in {.file _config.yml}.")
  invisible(skin)
}

# Skin names from the installed Minimal Mistakes gem (or the site's own
# _sass, for a vendored copy); the documented list as a fallback.
mm_skins <- function(root) {
  dirs <- c(file.path(root, "_sass", "minimal-mistakes", "skins"),
            Sys.glob(file.path(jd_gem_home(), "gems",
                               "minimal-mistakes-jekyll-*",
                               "_sass", "minimal-mistakes", "skins")))
  f <- unlist(lapply(dirs[dir.exists(dirs)], list.files,
                     pattern = "^_.*[.]scss$"))
  if (!length(f)) {
    return(c("default", "air", "aqua", "contrast", "dark", "dirt", "mint",
             "neon", "plum", "sunrise"))
  }
  sort(unique(sub("^_", "", sub("[.]scss$", "", f))))
}

#' Customize the site fonts
#'
#' Overrides the theme's font family and base size without touching the
#' theme: `@font-face` rules for Google Fonts are inlined into the
#' site-local stylesheet (they are valid anywhere in a stylesheet, unlike
#' `@import`), followed by `font-family`/`font-size` overrides. Re-running
#' replaces the previous override.
#'
#' @param dir Site root.
#' @param family Body font family (e.g. `"Lora"`). With `google = TRUE`
#'   the face is fetched from Google Fonts at call time (needs network);
#'   otherwise it must be available on the visitor's system.
#' @param size Base font size as a CSS length (`"17px"`, `"110%"`, ...).
#'   Themes sized in `rem` (al-folio, minima) scale the whole site.
#' @param headings Font family for `h1`-`h6` (defaults to `family`'s
#'   behavior -- i.e. unchanged unless given).
#' @param code Font family for code (`code`, `pre`, `kbd`, `samp`).
#' @param google Fetch the given families from Google Fonts and inline
#'   their `@font-face` rules? Default `TRUE`.
#' @return Invisibly, the path of the stylesheet written.
#' @examples
#' \dontrun{
#' set_theme_font("my-site", family = "Lora", size = "17px")
#' set_theme_font("my-site", code = "JetBrains Mono")
#' }
#' @export
set_theme_font <- function(dir = ".", family = NULL, size = NULL,
                           headings = NULL, code = NULL, google = TRUE) {
  root <- normalizePath(dir, mustWork = TRUE)
  if (is.null(family) && is.null(size) && is.null(headings) &&
      is.null(code)) {
    cli::cli_abort("Nothing to set: pass {.arg family}, {.arg size},
                    {.arg headings} and/or {.arg code}.")
  }
  if (!is.null(size) &&
      !grepl("^[0-9.]+(px|%|em|rem|pt)$", size)) {
    cli::cli_abort("{.arg size} must be a CSS length like {.val 17px} or
                    {.val 110%}.")
  }
  main <- require_site_css(root)

  block <- character()
  if (google) {
    fetch <- getOption("jekylldown.font_fetcher", fetch_google_font_css)
    for (f in unique(c(family, headings, code))) {
      css <- fetch(f)
      if (is.null(css)) {
        cli::cli_warn("Could not fetch {.val {f}} from Google Fonts
                       (offline?); assuming the font is available locally.")
      } else {
        block <- c(block, css)
      }
    }
  }
  quote_family <- function(f, generic) sprintf('"%s", %s', f, generic)
  if (!is.null(family)) {
    block <- c(block, sprintf("body { font-family: %s; }",
                              quote_family(family, "sans-serif")))
  }
  if (!is.null(headings)) {
    block <- c(block, sprintf("h1, h2, h3, h4, h5, h6 { font-family: %s; }",
                              quote_family(headings, "sans-serif")))
  }
  if (!is.null(code)) {
    block <- c(block, sprintf("code, pre, kbd, samp { font-family: %s; }",
                              quote_family(code, "monospace")))
  }
  if (!is.null(size)) {
    block <- c(block, sprintf("html { font-size: %s; }", size))
  }

  append_marked_block(
    main,
    "/* >>> jekylldown fonts (generated; change via set_theme_font) */",
    "/* <<< jekylldown fonts */",
    block)
  cli::cli_alert_success("Fonts written to {.file {basename(main)}}.")
  invisible(main)
}

#' Style one semantic element of the theme
#'
#' Styles a single part of the site -- the navbar, the footer, headings --
#' without writing CSS: the element name is translated to the theme's own
#' selectors and the properties are appended to the site-local stylesheet
#' in a managed block (one per element; re-running replaces it).
#'
#' Elements: `"navbar"`, `"brand"` (the site name in the navbar),
#' `"footer"`, `"headings"`, `"post_title"`, `"links"`, `"code"`,
#' `"buttons"`.
#'
#' @section A word of caution -- this is the fragile layer:
#' Unlike [set_theme_style()], which goes through the CSS variables the
#' theme itself promises, this layer depends on a curated map of theme
#' selectors (`.navbar`, `footer`, ...) that upstream can rename at any
#' release. jekylldown checks the installed theme's sass and warns when a
#' mapped selector is no longer found, but the check needs the theme gems
#' installed and cannot catch everything. Prefer [set_theme_style()]
#' whenever a CSS variable covers your case; treat this function as the
#' middle ground before dropping to [add_css()].
#'
#' @param dir Site root.
#' @param element One of the element names above.
#' @param color,background,size Text color, background color and
#'   `font-size` for the element. Colors accept theme palette names,
#'   `#hex`, or any CSS color.
#' @param ... Further CSS properties as named arguments, with `_` for
#'   `-`: e.g. `font_weight = "600"`, `border_bottom = "none"`.
#' @return Invisibly, the CSS selector styled.
#' @examples
#' \dontrun{
#' set_element_style("my-site", "navbar",
#'                   background = "#222222", color = "white")
#' set_element_style("my-site", "headings", color = "red",
#'                   font_weight = "600")
#' }
#' @export
set_element_style <- function(dir = ".", element, color = NULL,
                              background = NULL, size = NULL, ...) {
  root <- normalizePath(dir, mustWork = TRUE)
  map <- jd_element_map(site_theme(root))
  element <- match.arg(element, names(map))
  selector <- map[[element]]

  extra <- list(...)
  if (length(extra) && (is.null(names(extra)) || any(!nzchar(names(extra))))) {
    cli::cli_abort("Extra CSS properties must be named,
                    e.g. {.code font_weight = \"600\"}.")
  }
  sass <- tryCatch(find_theme_sass(root), error = function(e) NULL)
  col <- function(x) if (is.null(sass)) x else resolve_css_color(x, sass)
  props <- c(
    if (!is.null(color))      sprintf("  color: %s;", col(color)),
    if (!is.null(background)) sprintf("  background-color: %s;",
                                      col(background)),
    if (!is.null(size))       sprintf("  font-size: %s;", size),
    vapply(names(extra), function(nm) {
      sprintf("  %s: %s;", gsub("_", "-", nm), extra[[nm]])
    }, "")
  )
  if (!length(props)) {
    cli::cli_abort("Nothing to set for {.val {element}}.")
  }

  found <- selector_in_theme(root, selector)
  if (isFALSE(found)) {
    cli::cli_warn("Selector {.val {selector}} was not found in the installed
                   theme's sass -- the theme may have changed and this rule
                   may have no effect (see {.help set_element_style}).")
  }

  main <- require_site_css(root)
  append_marked_block(
    main,
    sprintf("/* >>> jekylldown element style: %s (generated) */", element),
    sprintf("/* <<< jekylldown element style: %s */", element),
    c(sprintf("%s {", selector), props, "}"))
  cli::cli_alert_success(
    "{.val {element}} ({.code {selector}}) styled in
     {.file {basename(main)}}.")
  invisible(selector)
}

#' Add (or remove) a managed block of custom CSS
#'
#' The escape hatch under [set_theme_style()], [set_theme_font()] and
#' [set_element_style()]: free-form CSS, but written into a
#' marker-delimited block in the site-local stylesheet, so it is
#' idempotent per `id`, easy to find, and removable -- instead of hand
#' edits scattered through theme files. Works with any theme whose site
#' has (or can get) a local `main.scss`.
#'
#' @param dir Site root.
#' @param css Character vector of CSS lines. `character(0)` (or `""`)
#'   removes the block with this `id`.
#' @param id Identifier of the block (lowercase letters, digits, `-`,
#'   `_`), so independent customizations do not overwrite each other.
#' @return Invisibly, the path of the stylesheet written.
#' @examples
#' \dontrun{
#' add_css("my-site", c(
#'   ".profile img { border-radius: 50%; }"
#' ), id = "round-avatar")
#'
#' # remove it later
#' add_css("my-site", character(0), id = "round-avatar")
#' }
#' @export
add_css <- function(dir = ".", css, id = "custom") {
  root <- normalizePath(dir, mustWork = TRUE)
  if (!grepl("^[a-z0-9_-]+$", id)) {
    cli::cli_abort("{.arg id} must match {.code [a-z0-9_-]+}.")
  }
  main <- require_site_css(root)
  begin <- sprintf("/* >>> jekylldown custom css: %s */", id)
  close <- sprintf("/* <<< jekylldown custom css: %s */", id)

  css <- css[nzchar(css)]
  if (!length(css)) {
    remove_marked_block(main, begin, close)
    cli::cli_alert_success("Custom CSS block {.val {id}} removed.")
  } else {
    append_marked_block(main, begin, close, css)
    cli::cli_alert_success(
      "Custom CSS block {.val {id}} written to {.file {basename(main)}}.")
  }
  invisible(main)
}

# ---------------------------------------------------------------------------
# helpers

# site_css_file() or a clear error telling the user what to do.
require_site_css <- function(root) {
  main <- site_css_file(root)
  if (is.null(main)) {
    cli::cli_abort("Cannot find or create the site's stylesheet -- for
                    al-folio run {.code bundle_install(\"{root}\")} first;
                    for other themes create {.file assets/css/main.scss}
                    in the site.")
  }
  main
}

# Light/dark selector of the theme's variable blocks, classified by name
# ("dark" in the selector = the dark block).
theme_mode_selectors <- function(sass) {
  sels <- theme_color_selectors(sass)
  dark <- grepl("dark", sels, ignore.case = TRUE)
  out <- list()
  if (any(!dark)) out$light <- sels[!dark][[1]]
  if (any(dark))  out$dark  <- sels[dark][[1]]
  if (!length(out)) {
    cli::cli_abort("Could not find the theme's variable blocks in
                    {.file {basename(sass)}}.")
  }
  out
}

# A style value is a single color (both modes) or c(light = , dark = ).
style_mode_value <- function(value, mode) {
  if (is.null(names(value))) return(value[[1]])
  if (mode %in% names(value)) return(value[[mode]])
  NULL
}

# Palette name -> theme hex; anything else (hex, rgb(), CSS keyword) as-is.
resolve_css_color <- function(color, sass) {
  if (grepl("^[a-z]+$", color)) {
    hex <- tryCatch(resolve_theme_color(color, sass), error = function(e) NULL)
    if (!is.null(hex)) return(hex)
  }
  color
}

# Which theme is this site built on? Drives the element map, the style
# variable map, and where the site stylesheet comes from.
site_theme <- function(root) {
  cfg <- file.path(root, "_config.yml")
  lines <- if (file.exists(cfg)) xfun::read_utf8(cfg) else character()
  t <- grep("^(remote_)?theme:", lines, value = TRUE)
  t <- if (length(t)) t[[1]] else ""
  if (grepl("minimal-mistakes", t)) return("minimal-mistakes")
  if (grepl("minima", t)) return("minima")
  if (grepl("al[-_]folio", t)) return("al-folio")
  if (grepl("chirpy", t)) return("chirpy")
  "unknown"
}

# Semantic element -> selector, per theme. Curated by hand, which is what
# makes set_element_style() the fragile layer; unknown themes get the
# al-folio map (the flagship) plus the warning from selector_in_theme().
jd_element_map <- function(theme) {
  switch(theme,
    "minima" = list(
      navbar     = ".site-header",
      brand      = ".site-title",
      footer     = ".site-footer",
      headings   = "h1, h2, h3, h4, h5, h6",
      post_title = ".post-title",
      links      = "a",
      code       = "code, pre",
      buttons    = "button"
    ),
    "chirpy" = list(
      navbar     = "#topbar",
      sidebar    = "#sidebar",
      brand      = ".site-title",
      footer     = "footer",
      headings   = "h1, h2, h3, h4, h5, h6",
      post_title = "h1",
      links      = "a",
      code       = "code, pre",
      buttons    = ".btn"
    ),
    "minimal-mistakes" = list(
      navbar     = ".masthead",
      brand      = ".site-title",
      footer     = ".page__footer",
      headings   = "h1, h2, h3, h4, h5, h6",
      post_title = ".page__title",
      links      = "a",
      code       = "code, pre",
      buttons    = ".btn"
    ),
    list(
      navbar     = ".navbar",
      brand      = ".navbar-brand",
      footer     = "footer",
      headings   = "h1, h2, h3, h4, h5, h6",
      post_title = ".post-title",
      links      = "a",
      code       = "code, pre",
      buttons    = ".btn"
    )
  )
}

# All of a theme's sass as one string. The site-local _sass (when
# present) is authoritative; otherwise the installed gem is read. ""
# when neither exists (checks are then skipped).
theme_sass_text <- function(root, gem_glob) {
  local <- file.path(root, "_sass")
  dirs <- if (dir.exists(local)) local else
    Sys.glob(file.path(jd_gem_home(), "gems", gem_glob, "_sass"))
  files <- unlist(lapply(dirs[dir.exists(dirs)], list.files,
                         pattern = "[.]scss$", full.names = TRUE,
                         recursive = TRUE))
  if (!length(files)) return("")
  paste(unlist(lapply(files, xfun::read_utf8)), collapse = "\n")
}

# Is (the first simple piece of) a selector mentioned in the theme's sass?
# The site-local _sass (when present) is authoritative; otherwise the
# installed theme gems are checked. NA when there is nothing to check
# (validation skipped).
selector_in_theme <- function(root, selector) {
  local <- file.path(root, "_sass")
  dirs <- if (dir.exists(local)) local else
    Sys.glob(file.path(jd_gem_home(), "gems", "*", "_sass"))
  files <- unlist(lapply(dirs[dir.exists(dirs)], list.files,
                         pattern = "[.]scss$", full.names = TRUE))
  if (!length(files)) return(NA)
  text <- paste(unlist(lapply(files, xfun::read_utf8)), collapse = "\n")
  pieces <- trimws(strsplit(selector, ",")[[1]])
  # bare element selectors (h1, a, code, footer) always exist in the HTML;
  # only theme-specific class/id selectors can drift with theme versions
  pieces <- pieces[grepl("^[.#]", pieces)]
  if (!length(pieces)) return(TRUE)
  any(vapply(pieces, function(p) {
    tok <- strsplit(p, "[ >]")[[1]][[1]]
    grepl(tok, text, fixed = TRUE)
  }, logical(1)))
}

# Remove a marker-delimited block (inverse of append_marked_block).
remove_marked_block <- function(path, begin, close) {
  lines <- xfun::read_utf8(path)
  b <- which(lines == begin)
  e <- which(lines == close)
  if (length(b) && length(e)) xfun::write_utf8(lines[-(b[1]:e[1])], path)
  invisible(path)
}

# @font-face rules for a Google Fonts family (regular/bold/italic), ready
# to inline anywhere in a stylesheet. NULL when the fetch fails.
fetch_google_font_css <- function(family) {
  url <- sprintf(
    "https://fonts.googleapis.com/css2?family=%s:ital,wght@0,400;0,700;1,400&display=swap",
    utils::URLencode(family, reserved = TRUE))
  tmp <- tempfile(fileext = ".css")
  on.exit(unlink(tmp), add = TRUE)
  ok <- tryCatch(
    utils::download.file(url, tmp, quiet = TRUE, mode = "wb") == 0,
    error = function(e) FALSE, warning = function(w) FALSE)
  if (!ok) return(NULL)
  xfun::read_utf8(tmp)
}

#' Enable LaTeX math rendering (MathJax)
#'
#' R Markdown writers use LaTeX math, but not every Jekyll theme renders
#' it out of the box (on minima, `$$...$$` shows up as literal text).
#' This turns math on the way each theme expects:
#'
#' * **al-folio**: sets its native `enable_math: true`;
#' * **Chirpy**: enables its per-page `math` flag site-wide through a
#'   front matter default;
#' * **Minimal Mistakes**: loads MathJax through the theme's
#'   `head_scripts` hook;
#' * **minima** (and unknown themes): copies the theme's
#'   `_includes/head.html` into the site and inserts the MathJax
#'   `<script>` before `</head>`, in a managed, idempotent block.
#'
#' kramdown (Jekyll's Markdown engine) emits MathJax-v2-flavored output
#' for math, so the v2 bundle is loaded where jekylldown injects the
#' script itself; al-folio and Chirpy ship their own MathJax setups.
#'
#' @param dir Site root.
#' @return Invisibly, a short description of what was changed.
#' @examples
#' \dontrun{
#' add_mathjax("my-site")
#' }
#' @export
add_mathjax <- function(dir = ".") {
  root <- normalizePath(dir, mustWork = TRUE)
  theme <- site_theme(root)
  config <- file.path(root, "_config.yml")
  mathjax2 <- paste0("https://cdn.jsdelivr.net/npm/mathjax@2.7.9/",
                     "MathJax.js?config=TeX-AMS-MML_HTMLorMML")

  if (theme == "al-folio") {
    xfun::write_utf8(
      set_yaml_line(xfun::read_utf8(config), "enable_math", "true",
                    append = TRUE), config)
    cli::cli_alert_success("Math enabled: {.code enable_math: true} in
                            {.file _config.yml}.")
    return(invisible("enable_math: true"))
  }

  if (theme == "chirpy") {
    lines <- xfun::read_utf8(config)
    if (!any(grepl("^\\s+math: true", lines))) {
      entry <- c("  - scope:", '      path: ""', "    values:",
                 "      math: true")
      d <- grep("^defaults:", lines)
      lines <- if (length(d)) append(lines, entry, after = d[1]) else
        c(lines, "defaults:", entry)
      xfun::write_utf8(lines, config)
    }
    cli::cli_alert_success("Math enabled for all pages ({.code math: true}
                            front matter default).")
    return(invisible("defaults: math: true"))
  }

  if (theme == "minimal-mistakes") {
    lines <- xfun::read_utf8(config)
    if (!any(grepl("MathJax.js", lines, fixed = TRUE))) {
      h <- grep("^head_scripts:", lines)
      entry <- paste0("  - ", mathjax2)
      lines <- if (length(h)) append(lines, entry, after = h[1]) else
        c(lines, "head_scripts:", entry)
      xfun::write_utf8(lines, config)
    }
    cli::cli_alert_success("MathJax added to {.code head_scripts} in
                            {.file _config.yml}.")
    return(invisible("head_scripts"))
  }

  head <- site_head_file(root)
  if (is.null(head)) {
    cli::cli_abort("No {.file _includes/head.html} found (site or theme
                    gem) -- add the MathJax script to your theme's head
                    include by hand.")
  }
  insert_marked_before(
    head,
    "<!-- >>> jekylldown mathjax (generated by add_mathjax) -->",
    "<!-- <<< jekylldown mathjax -->",
    c('<script type="text/x-mathjax-config">',
      "MathJax.Hub.Config({ tex2jax: { inlineMath: [['$','$'],['\\\\(','\\\\)']],",
      "                                processEscapes: true } });",
      "</script>",
      sprintf('<script src="%s" async></script>', mathjax2)),
    anchor = "</head>")
  cli::cli_alert_success("MathJax script inserted in
                          {.file _includes/head.html}.")
  invisible(head)
}

# The site's head include, copying the theme gem's (minima) when the site
# has none -- a local _includes/head.html shadows the theme's.
site_head_file <- function(root) {
  local <- file.path(root, "_includes", "head.html")
  if (file.exists(local)) return(local)
  src <- Sys.glob(file.path(jd_gem_home(), "gems", "minima-*",
                            "_includes", "head.html"))
  if (!length(src)) return(NULL)
  fs::dir_create(dirname(local))
  fs::file_copy(sort(src, decreasing = TRUE)[1], local)
  local
}

# Insert a marker-delimited block before an anchor line (replacing any
# previous block with the same markers), e.g. a <script> before </head>.
insert_marked_before <- function(path, begin, close, block, anchor) {
  lines <- xfun::read_utf8(path)
  b <- which(lines == begin)
  e <- which(lines == close)
  if (length(b) && length(e)) lines <- lines[-(b[1]:e[1])]
  ins <- c(begin, block, close)
  i <- grep(anchor, lines, fixed = TRUE)
  lines <- if (length(i)) append(lines, ins, after = i[1] - 1) else
    c(lines, ins)
  xfun::write_utf8(lines, path)
  invisible(path)
}
