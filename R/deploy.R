#' Add a GitHub Pages deploy workflow to the site
#'
#' Writes the standard GitHub Actions workflow that builds the site with
#' Jekyll and publishes it to GitHub Pages on every push
#' (`.github/workflows/jekyll.yml`): checkout, Ruby with cached bundle,
#' `jekyll build`, upload, deploy. After pushing, enable it once in the
#' repository settings: *Settings > Pages > Source: GitHub Actions*.
#'
#' al-folio and Chirpy already ship their own deploy workflow -- for
#' those sites this function leaves it alone and tells you so. It is
#' meant for the themes that do not (minima, Minimal Mistakes, most
#' others).
#'
#' Note the division of labor: the workflow only runs `jekyll build`.
#' Knitting stays local -- run [build_site()] (with
#' `local_jekyll = FALSE` if you have no local Jekyll), then commit both
#' `_source/` and the generated `_posts/*.md` and push.
#'
#' The workflow caches gems, which requires a committed `Gemfile.lock`:
#' run [bundle_install()] once and commit the lockfile it produces.
#'
#' @param dir Site root.
#' @return Invisibly, the path of the workflow file (or of the theme's
#'   own workflow when one already exists).
#' @examples
#' \dontrun{
#' use_pages_workflow("my-site")
#' }
#' @export
use_pages_workflow <- function(dir = ".") {
  root <- normalizePath(dir, mustWork = TRUE)
  wf_dir <- file.path(root, ".github", "workflows")
  existing <- list.files(wf_dir, "[.]ya?ml$", full.names = TRUE)
  ships <- existing[grepl("deploy|pages", basename(existing))]
  if (length(ships)) {
    cli::cli_alert_info(
      "This site already has a Pages workflow
       ({.file {basename(ships[1])}}) -- nothing to add. Enable it under
       {.emph Settings > Pages > Source: GitHub Actions}.")
    return(invisible(ships[1]))
  }

  path <- file.path(wf_dir, "jekyll.yml")
  fs::dir_create(wf_dir)
  xfun::write_utf8(c(
    "# Build the Jekyll site and deploy it to GitHub Pages.",
    "# Written by jekylldown::use_pages_workflow(); knitting happens",
    "# locally (build_site()), this workflow only runs `jekyll build`.",
    "name: Deploy Jekyll site to Pages",
    "",
    "on:",
    "  push:",
    '    branches: ["main", "master"]',
    "  workflow_dispatch:",
    "",
    "permissions:",
    "  contents: read",
    "  pages: write",
    "  id-token: write",
    "",
    "concurrency:",
    '  group: "pages"',
    "  cancel-in-progress: false",
    "",
    "jobs:",
    "  build:",
    "    runs-on: ubuntu-latest",
    "    steps:",
    "      - name: Checkout",
    "        uses: actions/checkout@v4",
    "      - name: Setup Ruby",
    "        uses: ruby/setup-ruby@v1",
    "        with:",
    '          ruby-version: "3.3"',
    "          bundler-cache: true",
    "      - name: Setup Pages",
    "        id: pages",
    "        uses: actions/configure-pages@v5",
    "      - name: Build with Jekyll",
    "        run: >-",
    "          bundle exec jekyll build",
    '          --baseurl "${{ steps.pages.outputs.base_path }}"',
    "        env:",
    "          JEKYLL_ENV: production",
    "      - name: Upload artifact",
    "        uses: actions/upload-pages-artifact@v3",
    "",
    "  deploy:",
    "    environment:",
    "      name: github-pages",
    "      url: ${{ steps.deployment.outputs.page_url }}",
    "    runs-on: ubuntu-latest",
    "    needs: build",
    "    steps:",
    "      - name: Deploy to GitHub Pages",
    "        id: deployment",
    "        uses: actions/deploy-pages@v4"
  ), path)
  cli::cli_alert_success(
    "Workflow written to {.file .github/workflows/jekyll.yml}.")
  cli::cli_alert_info(
    "Push, then enable it once: {.emph Settings > Pages > Source:
     GitHub Actions}.")
  invisible(path)
}
