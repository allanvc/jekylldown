#' Create a new post
#'
#' Creates `_source/YYYY-MM-DD-slug.Rmd` (default) or `.qmd` (Quarto), or,
#' with `format = "md"`, a plain `_posts/YYYY-MM-DD-slug.md`, all with
#' Jekyll front matter.
#'
#' @param title Post title.
#' @param date Post date; defaults to today.
#' @param format `"Rmd"` (R Markdown source, default), `"qmd"` (Quarto
#'   source; rendered by [build_site()] via the Quarto CLI), or `"md"`
#'   (plain Markdown, written directly to `_posts/`).
#' @param rmd Deprecated alias kept for compatibility: `rmd = FALSE` is
#'   `format = "md"`.
#' @param tags,categories Optional character vectors for the front matter.
#' @param dir Directory in (or under) the site. Defaults to the working
#'   directory.
#' @param open Open the file (via [utils::file.edit()]) in interactive
#'   sessions?
#' @return The path to the created file, invisibly.
#' @examples
#' \dontrun{
#' new_post("Hello world", dir = "my-site")
#' new_post("A Quarto post", format = "qmd", dir = "my-site")
#' new_post("Plain Markdown, no R code", format = "md", dir = "my-site",
#'          tags = c("news", "r"))
#' }
#' @export
new_post <- function(title, date = Sys.Date(),
                     format = c("Rmd", "qmd", "md"),
                     tags = NULL, categories = NULL,
                     dir = ".", open = interactive(), rmd = NULL) {
  format <- match.arg(format)
  if (!is.null(rmd)) format <- if (isTRUE(rmd)) "Rmd" else "md"
  root <- site_root(dir)
  slug <- slugify(title)
  if (!nzchar(slug)) cli::cli_abort("{.arg title} produced an empty slug.")

  name <- sprintf("%s-%s.%s", format(as.Date(date), "%Y-%m-%d"), slug,
                  format)
  subdir <- if (format == "md") "_posts" else "_source"
  path <- file.path(root, subdir, name)
  if (file.exists(path)) cli::cli_abort("{.path {path}} already exists.")
  fs::dir_create(dirname(path))

  fm <- list(layout = "post", title = title,
             date = format(as.Date(date), "%Y-%m-%d"))
  if (length(tags)) fm$tags <- as.list(tags)
  if (length(categories)) fm$categories <- as.list(categories)

  xfun::write_utf8(c(
    "---",
    strsplit(yaml::as.yaml(fm), "\n")[[1]],
    "---",
    "",
    ""
  ), path)

  cli::cli_alert_success("Created {.path {path}}.")
  if (open && interactive()) utils::file.edit(path)
  invisible(path)
}
