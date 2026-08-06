#' Set the al-folio accent color
#'
#' al-folio derives its accent (links, buttons, badges) from the
#' `--global-theme-color` CSS variable defined in the theme's
#' `_sass/_themes.scss` -- purple in light mode, cyan in dark mode. This
#' function overrides it without touching the theme: the theme's
#' `assets/css/main.scss` is copied into the site (a local file shadows the
#' theme's) and a plain-CSS override block is appended, one rule per
#' selector in which the theme sets `--global-theme-color`, so the override
#' tracks the theme's own light/dark structure. Named colors are resolved
#' from the theme's palette (`$red-color`, `$blue-color`, ... in
#' `_sass/_variables.scss`); hex values are used as-is.
#'
#' The theme files live in the `al_folio_core` gem, so run
#' [bundle_install()] once before calling this. Calling it again replaces
#' the previous override, so the color can be changed at any time.
#'
#' On a Chirpy site this delegates to `set_theme_style(accent = color)`
#' (the link color); on Minimal Mistakes it points you at
#' [set_theme_skin()] instead.
#'
#' @param dir Site root.
#' @param color A named theme color (e.g. `"red"`, `"blue"`, `"green"`,
#'   `"cyan"`, `"purple"`, `"pink"`, `"orange"`, `"yellow"`) or a CSS hex
#'   value like `"#b71c1c"`.
#' @return The hex color applied, invisibly.
#' @examples
#' \dontrun{
#' set_theme_color("my-site", "red")
#' set_theme_color("my-site", "#0057b7")
#' }
#' @export
set_theme_color <- function(dir = ".", color) {
  root <- normalizePath(dir, mustWork = TRUE)
  theme <- site_theme(root)
  if (theme == "chirpy") {
    set_theme_style(root, accent = color)
    return(invisible(color))
  }
  if (theme == "minimal-mistakes") {
    cli::cli_abort("Minimal Mistakes has no accent variable; pick a skin
                    with {.fn set_theme_skin} instead.")
  }
  sass <- find_theme_sass(root)
  hex <- resolve_theme_color(color, sass)

  main <- site_css_file(root)
  if (is.null(main)) {
    cli::cli_abort("Cannot find the theme's {.file assets/css/main.scss}
                    to copy into the site -- run
                    {.code bundle_install(\"{root}\")} first.")
  }

  block <- unlist(lapply(theme_color_selectors(sass), function(s) c(
    sprintf("%s {", s),
    sprintf("  --global-theme-color: %s;", hex),
    sprintf("  --global-hover-color: %s;", hex),
    "}"
  )))
  append_marked_block(
    main,
    "/* >>> jekylldown theme color (generated; change via set_theme_color) */",
    "/* <<< jekylldown theme color */",
    block)
  cli::cli_alert_success(
    "Theme color set to {.val {hex}} in {.file {basename(main)}}.")
  invisible(hex)
}

# The site-local stylesheet that shadows the theme's, creating it when
# needed: gem themes (al-folio, Chirpy, Minimal Mistakes) get a copy of
# the gem's main stylesheet (NULL if the gems are not installed yet);
# minima gets an assets/main.scss that imports the theme. An existing
# local file is used as-is.
site_css_file <- function(root) {
  theme <- site_theme(root)

  if (theme == "minima") {
    m <- file.path(root, "assets", "main.scss")
    if (!file.exists(m)) {
      fs::dir_create(dirname(m))
      xfun::write_utf8(c("---", "---", "", '@import "minima";'), m)
    }
    return(m)
  }

  spec <- switch(theme,
    "chirpy" = c(glob = "jekyll-theme-chirpy-*",
                 rel = "assets/css/jekyll-theme-chirpy.scss"),
    "minimal-mistakes" = c(glob = "minimal-mistakes-jekyll-*",
                           rel = "assets/css/main.scss"),
    c(glob = "al_folio_core-*", rel = "assets/css/main.scss"))

  main <- file.path(root, spec[["rel"]])
  if (file.exists(main)) return(main)
  # a pre-existing local stylesheet (vendored/unknown themes) is used as-is
  for (alt in file.path(root, c("assets/css/main.scss", "assets/main.scss"))) {
    if (file.exists(alt)) return(alt)
  }

  src <- Sys.glob(file.path(jd_gem_home(), "gems", spec[["glob"]],
                            spec[["rel"]]))
  if (!length(src)) return(NULL)
  fs::dir_create(dirname(main))
  fs::file_copy(sort(src, decreasing = TRUE)[1], main)
  main
}

# Append a marker-delimited block to a file, replacing any previous block
# with the same markers (so repeated calls do not stack).
append_marked_block <- function(path, begin, close, block) {
  lines <- xfun::read_utf8(path)
  b <- which(lines == begin)
  e <- which(lines == close)
  if (length(b) && length(e)) lines <- lines[-(b[1]:e[1])]
  xfun::write_utf8(c(lines, begin, block, close), path)
}

# Locate _sass/_themes.scss: site-local override first, then the newest
# al_folio_core gem in the isolated gem home.
find_theme_sass <- function(root) {
  local <- file.path(root, "_sass", "_themes.scss")
  if (file.exists(local)) return(local)
  gems <- Sys.glob(file.path(jd_gem_home(), "gems", "al_folio_core-*",
                             "_sass", "_themes.scss"))
  if (length(gems)) return(sort(gems, decreasing = TRUE)[1])
  cli::cli_abort("Theme sass not found -- run
                  {.code bundle_install(\"{root}\")} first so the al-folio
                  gems are available.")
}

# "red" -> the theme's $red-color hex; "#b71c1c" -> itself.
resolve_theme_color <- function(color, sass) {
  if (grepl("^#[0-9a-fA-F]{3,8}$", color)) return(color)
  vars <- file.path(dirname(sass), "_variables.scss")
  lines <- if (file.exists(vars)) xfun::read_utf8(vars) else character()
  pat <- sprintf("^\\$%s-color:\\s*(#[0-9a-fA-F]{3,8})", color)
  hit <- Filter(function(x) length(x) == 2,
                regmatches(lines, regexec(pat, lines)))
  if (length(hit)) return(hit[[1]][2])
  avail <- Filter(function(x) length(x) == 2,
                  regmatches(lines,
                             regexec("^\\$([a-z]+)-color:\\s*#", lines)))
  avail <- unique(vapply(avail, `[`, "", 2))
  cli::cli_abort(c("Unknown theme color {.val {color}}.",
                   "i" = "Available: {.val {avail}}, or any #hex value."))
}

# The selectors in _themes.scss that set --global-theme-color (the light
# and dark blocks), so overrides match whatever the theme version uses.
theme_color_selectors <- function(sass) {
  lines <- xfun::read_utf8(sass)
  idx <- grep("--global-theme-color:", lines, fixed = TRUE)
  sels <- vapply(idx, function(i) {
    j <- i
    while (j > 1 && !grepl("\\{\\s*$", lines[j])) j <- j - 1
    trimws(sub("\\{\\s*$", "", lines[j]))
  }, "")
  unique(sels[nzchar(sels)])
}
