# Footer credit ("Built from R with jekylldown X.Y.Z."), per theme:
# al-folio renders `site.footer_text` from _config.yml, so the sentence
# is inserted there; minima, Chirpy and Minimal Mistakes get a local
# _includes/footer.html (copied from the theme gem when the site has
# none) with a marker-delimited block. build_site() keeps the version
# number current on every build.

fc_begin <- "<!-- >>> jekylldown credit -->"
fc_close <- "<!-- <<< jekylldown credit -->"

credit_sentence <- function() {
  sprintf(paste0('Built from R with <a href=',
                 '"https://github.com/allanvc/jekylldown" ',
                 'target="_blank">jekylldown</a> %s.'),
          as.character(utils::packageVersion("jekylldown")))
}

#' Add a jekylldown credit to the site footer
#'
#' Inserts "Built from R with jekylldown X.Y.Z." (with a link) into the
#' footer line the theme already has -- right after its "Powered by
#' Jekyll ..." sentence on al-folio, and at the natural end of the
#' footer on minima, Chirpy and Minimal Mistakes. [new_site()] adds the
#' credit to fresh sites; call this yourself on migrated or existing
#' ones. [build_site()] refreshes the version number automatically, so
#' the footer follows package upgrades with no manual edits.
#'
#' Per theme: on al-folio the sentence goes into the `footer_text:`
#' entry of `_config.yml` (plain text you can reorder or edit). On the
#' other themes the theme's `_includes/footer.html` is copied into the
#' site (a local include shadows the gem's; for Chirpy and Minimal
#' Mistakes the gem must be installed -- run [bundle_install()] first)
#' and the credit is added as a marker-delimited block.
#'
#' Undo with [remove_footer_credit()].
#'
#' @param dir Site root, or any directory inside it -- like
#'   [build_site()], the function climbs to the enclosing site, so the
#'   default `"."` works from anywhere in the site's project.
#' @return Invisibly, the file the credit was written to.
#' @examples
#' \dontrun{
#' add_footer_credit()
#' remove_footer_credit()
#' }
#' @export
add_footer_credit <- function(dir = ".") {
  root <- site_root(dir)
  theme <- site_theme(root)
  path <- if (theme == "al-folio" || fc_has_footer_text(root)) {
    fc_config_add(root)
  } else {
    fc_include_add(root, theme)
  }
  cli::cli_alert_success(
    "Footer credit added to {.file {basename(path)}} (remove with
     {.fn remove_footer_credit}).")
  invisible(path)
}

#' @rdname add_footer_credit
#' @export
remove_footer_credit <- function(dir = ".") {
  root <- site_root(dir)
  removed <- FALSE

  config <- file.path(root, "_config.yml")
  if (file.exists(config)) {
    lines <- xfun::read_utf8(config)
    keep <- !grepl("jekylldown</a>", lines, fixed = TRUE)
    if (any(!keep)) {
      xfun::write_utf8(lines[keep], config)
      removed <- TRUE
    }
  }

  inc <- file.path(root, "_includes", "footer.html")
  if (file.exists(inc) &&
      any(xfun::read_utf8(inc) == fc_begin)) {
    remove_marked_block(inc, fc_begin, fc_close)
    removed <- TRUE
  }

  if (removed) {
    cli::cli_alert_success("Footer credit removed.")
  } else {
    cli::cli_alert_info("No footer credit found -- nothing to remove.")
  }
  invisible(removed)
}

# Does _config.yml have a footer_text entry to slot the sentence into?
fc_has_footer_text <- function(root) {
  config <- file.path(root, "_config.yml")
  file.exists(config) &&
    any(grepl("^footer_text:", xfun::read_utf8(config)))
}

# al-folio path: the credit becomes one more sentence of footer_text.
fc_config_add <- function(root) {
  config <- file.path(root, "_config.yml")
  lines <- if (file.exists(config)) xfun::read_utf8(config) else character()
  credit <- paste0("  ", credit_sentence())

  hit <- grep("jekylldown</a>", lines, fixed = TRUE)
  if (length(hit)) {
    lines[hit[1]] <- credit
    xfun::write_utf8(lines, config)
    return(config)
  }

  key <- grep("^footer_text:", lines)
  if (!length(key)) {
    xfun::write_utf8(c(lines, "footer_text: >", credit), config)
    return(config)
  }
  # the block runs until the next top-level key; insert after the
  # sentence naming Jekyll when there is one, else at the block's end
  end <- key[1]
  while (end < length(lines) &&
         (grepl("^\\s", lines[end + 1]) || !nzchar(trimws(lines[end + 1])))) {
    end <- end + 1
  }
  block <- seq(key[1] + 1, length.out = max(0, end - key[1]))
  jek <- block[grepl("Jekyll", lines[block], fixed = TRUE)]
  at <- if (length(jek)) jek[length(jek)] else end
  xfun::write_utf8(append(lines, credit, after = at), config)
  config
}

# Include path (minima, Chirpy, Minimal Mistakes): shadow the gem's
# footer include and append a marked block.
fc_include_add <- function(root, theme) {
  inc <- file.path(root, "_includes", "footer.html")
  if (!file.exists(inc)) {
    glob <- switch(theme,
      "chirpy"           = "jekyll-theme-chirpy-*",
      "minimal-mistakes" = "minimal-mistakes-jekyll-*",
      "minima"           = "minima-*",
      cli::cli_abort(c(
        "No {.file _includes/footer.html} in the site and no known gem
         to copy one from for theme {.val {theme}}.",
        "i" = "Add a {.file footer.html} include (or a
               {.code footer_text:} entry in {.file _config.yml}) and
               re-run.")))
    src <- Sys.glob(file.path(jd_gem_home(), "gems", glob,
                              "_includes", "footer.html"))
    if (!length(src)) {
      cli::cli_abort("The {.val {theme}} gem is not installed, so there
                      is no footer include to copy -- run
                      {.code bundle_install(\"{root}\")} first.")
    }
    fs::dir_create(dirname(inc))
    fs::file_copy(sort(src, decreasing = TRUE)[1], inc)
  }

  block <- c(fc_begin,
             sprintf('<p class="jekylldown-credit">%s</p>',
                     credit_sentence()),
             fc_close)
  lines <- xfun::read_utf8(inc)
  b <- which(lines == fc_begin)
  e <- which(lines == fc_close)
  if (length(b) && length(e)) {
    lines <- append(lines[-(b[1]:e[1])], block, after = b[1] - 1)
  } else {
    foot <- grep("</footer>", lines, fixed = TRUE)
    at <- if (length(foot)) foot[length(foot)] - 1 else length(lines)
    lines <- append(lines, block, after = at)
  }
  xfun::write_utf8(lines, inc)
  inc
}

# Keep the version in an existing credit current; called by
# build_site() on every build, silent and safe by design.
refresh_footer_credit <- function(root) {
  pat <- "(jekylldown</a>\\s*)[0-9]+([.][0-9]+)*"
  rep <- paste0("\\1", as.character(utils::packageVersion("jekylldown")))
  for (f in file.path(root, c("_config.yml", "_includes/footer.html"))) {
    if (!file.exists(f)) next
    lines <- xfun::read_utf8(f)
    fixed <- sub(pat, rep, lines)
    if (!identical(fixed, lines)) xfun::write_utf8(fixed, f)
  }
  invisible(NULL)
}
