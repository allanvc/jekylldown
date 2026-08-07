test_that("slugify produces clean slugs", {
  expect_equal(jekylldown:::slugify("Hello, jekylldown!"), "hello-jekylldown")
  expect_equal(jekylldown:::slugify("  A/B testing & R  "), "a-b-testing-r")
})

test_that("new_site expands ~ so external tools never see it", {
  fake_home <- withr::local_tempdir()
  withr::local_envvar(c(HOME = fake_home))
  old_wd <- withr::local_tempdir()
  withr::local_dir(old_wd)

  new_site("~/tilde-site", theme = "minima", sample = FALSE)
  expect_true(file.exists(file.path(fake_home, "tilde-site", "_config.yml")))
  # the bug: a literal "~" directory appearing under the working directory
  expect_false(dir.exists(file.path(old_wd, "~")))
})

test_that("new_site + new_post + knit pipeline work end to end (no Ruby)", {
  site <- file.path(withr::local_tempdir(), "site")
  expect_invisible(new_site(site, theme = "minima", sample = FALSE))
  expect_true(file.exists(file.path(site, "_config.yml")))
  expect_true(dir.exists(file.path(site, "_source")))
  cfg <- readLines(file.path(site, "_config.yml"))
  expect_true(any(grepl("- _source", cfg)))

  post <- new_post("My first post", date = "2026-08-03", tags = "r",
                   dir = site, open = FALSE)
  expect_true(file.exists(post))
  expect_match(basename(post), "^2026-08-03-my-first-post[.]Rmd$")

  writeLines(c(
    readLines(post),
    "```{r test-fig}", "plot(1:3)", "```",
    "", "Two plus two is `r 2 + 2`."
  ), post)

  knitted <- build_site(site, local_jekyll = FALSE)
  out <- file.path(site, "_posts", "2026-08-03-my-first-post.md")
  expect_equal(knitted, out)
  md <- readLines(out)
  expect_equal(md[1], "---")           # front matter preserved
  expect_true(any(grepl("Two plus two is 4", md)))
  expect_true(any(grepl("\\{\\{ site.baseurl \\}\\}/assets/img/posts/", md)))
  figs <- list.files(file.path(site, "assets", "img", "posts",
                               "2026-08-03-my-first-post"), "[.]png$")
  expect_gt(length(figs), 0)

  # up to date on second run
  expect_length(build_site(site, local_jekyll = FALSE), 0)
})

test_that("scrub_al_folio_demo drops dev files and the jupyter plugin", {
  dir <- withr::local_tempdir()
  fs::dir_create(file.path(dir, "_pages"))

  # upstream repo tooling: dot-directories, theme docs, .github beyond the
  # Pages deploy workflow
  fs::dir_create(file.path(dir, c(".toolcfg", "docs",
                                  ".github/workflows", ".github/other")))
  xfun::write_utf8("x", file.path(dir, ".toolcfg", "settings.json"))
  xfun::write_utf8("x", file.path(dir, ".linkcheckignore"))
  xfun::write_utf8("_site", file.path(dir, ".gitignore"))
  xfun::write_utf8("x", file.path(dir, "docs", "guide.md"))
  xfun::write_utf8("x", file.path(dir, ".github", "workflows", "deploy.yml"))
  xfun::write_utf8("x", file.path(dir, ".github", "workflows", "ci.yml"))
  xfun::write_utf8("x", file.path(dir, ".github", "template.md"))

  xfun::write_utf8(c("readme"), file.path(dir, "README.md"))
  xfun::write_utf8(c("install"), file.path(dir, "INSTALL.md"))
  xfun::write_utf8(c("faq"), file.path(dir, "FAQ.md"))
  xfun::write_utf8(c(
    "source 'https://rubygems.org'",
    "group :jekyll_plugins do",
    "  gem 'jekyll-scholar'",
    "  gem 'jekyll-jupyter-notebook'",
    "end"
  ), file.path(dir, "Gemfile"))
  xfun::write_utf8(c(
    "title: demo",
    "plugins:",
    "  - jekyll-scholar",
    "  - jekyll-jupyter-notebook",
    "exclude:",
    "  - README.md"
  ), file.path(dir, "_config.yml"))

  jekylldown:::scrub_al_folio_demo(dir)

  # dev docs deleted, their stale exclude entries dropped
  expect_false(any(file.exists(file.path(dir, c("README.md", "INSTALL.md",
                                                "FAQ.md")))))
  config <- xfun::read_utf8(file.path(dir, "_config.yml"))
  expect_false(any(grepl("README|INSTALL|FAQ", config)))
  expect_true(all(c("  - test/", "  - requirements.txt") %in% config))
  expect_false(any(grepl("jekyll-jupyter-notebook", config)))
  expect_true("  - jekyll-scholar" %in% config)

  gemfile <- xfun::read_utf8(file.path(dir, "Gemfile"))
  expect_false(any(grepl("jekyll-jupyter-notebook", gemfile)))
  expect_true(any(grepl("jekyll-scholar", gemfile)))

  # repo tooling pruned; only the Pages deploy workflow survives
  expect_false(dir.exists(file.path(dir, ".toolcfg")))
  expect_false(file.exists(file.path(dir, ".linkcheckignore")))
  expect_true(file.exists(file.path(dir, ".gitignore")))
  expect_false(dir.exists(file.path(dir, "docs")))
  expect_true(file.exists(file.path(dir, ".github/workflows/deploy.yml")))
  expect_false(file.exists(file.path(dir, ".github/workflows/ci.yml")))
  expect_false(file.exists(file.path(dir, ".github/template.md")))
  expect_false(dir.exists(file.path(dir, ".github/other")))
})

test_that("tag_tables tags pipe tables but not code or existing IALs", {
  out <- jekylldown:::tag_tables(c(
    "| a | b |",
    "|---|---|",
    "| 1 | 2 |",
    "",
    "{% highlight text %}",
    "| not | a | table |",
    "|-----|---|-------|",
    "{% endhighlight %}",
    "",
    "```",
    "| also | not |",
    "|------|-----|",
    "```",
    "",
    "| c | d |",
    "|---|---|",
    "{: .table .table-sm}",
    "",
    "| just one pipe line, no separator"
  ))
  expect_equal(sum(out == "{: .table}"), 1)
  expect_equal(out[4], "{: .table}")             # after the first table only
  expect_equal(sum(grepl("^\\{:", out)), 2)      # existing IAL untouched
})

test_that("qmd posts are rendered via the quarto CLI and adapted", {
  skip_on_os("windows")
  site <- withr::local_tempdir()
  fs::dir_create(file.path(site, c("_source", "_posts")))
  xfun::write_utf8("name: test", file.path(site, "_config.yml"))

  # a fake quarto CLI: writes <stem>.md (with pandoc-style front matter,
  # a figure link and a table) plus the <stem>_files figure directory
  mock <- file.path(withr::local_tempdir(), "quarto")
  xfun::write_utf8(c(
    "#!/bin/sh",
    'stem=$(basename "$2" .qmd)',
    'cat > "${stem}.md" <<HERE',
    "---",
    "title: Rendered Title",
    "---",
    "",
    "# A Quarto post",
    "",
    "2026-08-05",
    "",
    "Body with a figure:",
    "",
    '![p](${stem}_files/figure-commonmark/plot-1.png)',
    "",
    "| a | b |",
    "|---|---|",
    "| 1 | 2 |",
    "HERE",
    'mkdir -p "${stem}_files/figure-commonmark"',
    'printf PNG > "${stem}_files/figure-commonmark/plot-1.png"'
  ), mock)
  Sys.chmod(mock, "0755")
  withr::local_options(jekylldown.quarto = mock)

  src <- file.path(site, "_source", "2026-08-05-quarto-post.qmd")
  xfun::write_utf8(c(
    "---",
    'title: "A Quarto post"',
    "date: 2026-08-05",
    "format: gfm",
    "execute:",
    "  echo: true",
    "---",
    "",
    "Hello."
  ), src)

  out <- file.path(site, "_posts", "2026-08-05-quarto-post.md")
  knit_post(src, out, root = site)

  md <- xfun::read_utf8(out)
  fm_end <- grep("^---$", md)[2]
  fm <- md[2:(fm_end - 1)]
  expect_true("layout: post" %in% fm)
  expect_true(any(grepl("A Quarto post", fm)))    # source front matter wins
  expect_false(any(grepl("format|execute|echo", fm)))
  expect_false(any(grepl("Rendered Title", md)))
  # pandoc's repeated title heading and date line are stripped from the body
  expect_false(any(grepl("^# A Quarto post", md)))
  expect_false(any(md == "2026-08-05"))
  expect_true(any(grepl("Body with a figure", md)))

  expect_true(any(grepl(
    "\\{\\{ site.baseurl \\}\\}/assets/img/posts/2026-08-05-quarto-post/figure-commonmark/plot-1.png",
    md)))
  expect_true(file.exists(file.path(
    site, "assets", "img", "posts", "2026-08-05-quarto-post",
    "figure-commonmark", "plot-1.png")))
  expect_true("{: .table}" %in% md)

  # no leftovers next to the source
  expect_equal(list.files(file.path(site, "_source")),
               "2026-08-05-quarto-post.qmd")
})

test_that("new_post writes qmd sources and knit_all picks them up", {
  site <- withr::local_tempdir()
  fs::dir_create(file.path(site, "_source"))
  xfun::write_utf8("name: test", file.path(site, "_config.yml"))
  post <- new_post("Quarto here", date = "2026-08-05", format = "qmd",
                   dir = site, open = FALSE)
  expect_match(basename(post), "^2026-08-05-quarto-here[.]qmd$")
  expect_true(startsWith(basename(dirname(post)), "_source"))
  # missing quarto CLI fails with guidance, not silently
  withr::local_options(jekylldown.quarto = "/nonexistent/quarto")
  expect_error(knit_post(post, file.path(site, "_posts", "x.md"),
                         root = site), "Quarto CLI")
})

test_that("knit_method: pandoc renders via rmarkdown with pandoc features", {
  skip_if_not_installed("rmarkdown")
  skip_if_not(rmarkdown::pandoc_available("2.0"))
  site <- withr::local_tempdir()
  fs::dir_create(file.path(site, c("_source", "_posts")))
  xfun::write_utf8("name: test", file.path(site, "_config.yml"))

  src <- file.path(site, "_source", "2026-08-05-pandoc-post.Rmd")
  xfun::write_utf8(c(
    "---",
    'title: "A pandoc post"',
    "date: 2026-08-05",
    "knit_method: pandoc",
    "---",
    "",
    "A footnote.^[Only pandoc renders these.]",
    "",
    "```{r pfig}",
    "plot(1:3)",
    "```",
    "",
    "```{r}",
    "knitr::kable(head(mtcars[, 1:2], 2))",
    "```"
  ), src)

  out <- file.path(site, "_posts", "2026-08-05-pandoc-post.md")
  knit_post(src, out, root = site)

  md <- xfun::read_utf8(out)
  expect_true("layout: post" %in% md)
  expect_false(any(grepl("knit_method", md)))
  # the inline footnote was processed by pandoc (its `^[...]` syntax is
  # gone, the note text survives; the exact output differs by pandoc
  # version)
  expect_false(any(grepl("\\^\\[", md)))
  expect_true(any(grepl("Only pandoc renders these", md)))
  expect_true(any(grepl(
    "\\{\\{ site.baseurl \\}\\}/assets/img/posts/2026-08-05-pandoc-post/", md)))
  figs <- list.files(file.path(site, "assets", "img", "posts",
                               "2026-08-05-pandoc-post"), recursive = TRUE)
  expect_true(any(grepl("pfig", figs)))
  expect_true("{: .table}" %in% md)
  # no leftovers next to the source
  expect_equal(list.files(file.path(site, "_source")),
               "2026-08-05-pandoc-post.Rmd")
})

test_that("serve_rebuild knits Rmd and qmd and runs the build command", {
  skip_on_os("windows")
  site <- withr::local_tempdir()
  fs::dir_create(file.path(site, c("_source", "_posts")))
  xfun::write_utf8("name: test", file.path(site, "_config.yml"))
  xfun::write_utf8(c("---", "title: R post", "---", "", "Hi `r 1 + 1`."),
                   file.path(site, "_source", "2026-08-05-r-post.Rmd"))

  jekylldown:::serve_rebuild(site, "touch built.marker")
  expect_true(file.exists(file.path(site, "_posts", "2026-08-05-r-post.md")))
  expect_true(file.exists(file.path(site, "built.marker")))

  # a failing command warns but does not error (the server must survive)
  expect_warning(jekylldown:::serve_rebuild(site, "false"), "failed")
})

test_that("jekyll_baseurl reads baseurl from _config.yml", {
  site <- withr::local_tempdir()
  expect_equal(jekylldown:::jekyll_baseurl(site), "")
  xfun::write_utf8(c("title: x", 'baseurl: "/proj"  # comment'),
                   file.path(site, "_config.yml"))
  expect_equal(jekylldown:::jekyll_baseurl(site), "/proj")
  xfun::write_utf8(c("baseurl: \"\""), file.path(site, "_config.yml"))
  expect_equal(jekylldown:::jekyll_baseurl(site), "")
})

test_that("use_pages_workflow writes the standard workflow once", {
  site <- file.path(withr::local_tempdir(), "site")
  new_site(site, theme = "minima", sample = FALSE)
  wf <- use_pages_workflow(site)
  expect_true(file.exists(file.path(site, ".github/workflows/jekyll.yml")))
  lines <- readLines(wf)
  expect_true(any(grepl("actions/deploy-pages", lines)))
  expect_true(any(grepl("bundler-cache: true", lines)))
  expect_true(any(grepl("jekyll build", lines)))

  # a theme that ships its own deploy workflow is left alone
  ship <- file.path(withr::local_tempdir(), "chirpy-like")
  fs::dir_create(file.path(ship, ".github", "workflows"))
  xfun::write_utf8("name: x", file.path(ship, "_config.yml"))
  xfun::write_utf8("name: deploy", file.path(ship, ".github", "workflows",
                                             "pages-deploy.yml"))
  out <- use_pages_workflow(ship)
  expect_equal(basename(out), "pages-deploy.yml")
  expect_false(file.exists(file.path(ship, ".github/workflows/jekyll.yml")))
})

test_that("Minimal Mistakes scaffold aliases the post layout to single", {
  dir <- file.path(withr::local_tempdir(), "mm")
  new_site(dir, theme = "minimal-mistakes", sample = FALSE)
  alias <- readLines(file.path(dir, "_layouts", "post.html"))
  expect_true("layout: single" %in% alias)
  expect_true("{{ content }}" %in% alias)
})

test_that("tag_tables normalizes tables without leading pipes", {
  out <- jekylldown:::tag_tables(c(
    "Topic|Length|",
    "-----|------|",
    "[Loops](https://x.org/a)|15",
    "[Apply](https://x.org/b)|34",
    "",
    "prose with a | pipe that is not a table",
    "",
    "```",
    "code|with|pipes",
    "----|----|----",
    "```"
  ))
  expect_equal(out[1], "|Topic|Length|")
  expect_equal(out[2], "|-----|------|")
  expect_equal(out[3], "|[Loops](https://x.org/a)|15")
  expect_true("{: .table}" %in% out)
  expect_equal(out[grep("prose", out)], "prose with a | pipe that is not a table")
  expect_equal(sum(grepl("^\\|", out[grep("code", out)])), 0)  # fenced untouched
})

test_that("tag_tables separates a table glued to the previous paragraph", {
  out <- jekylldown:::tag_tables(c(
    "Year: jan. 2018",
    "Topic|Length|",
    "-----|------|",
    "[Intro](https://x.org/1)|34"
  ))
  expect_equal(out[1], "Year: jan. 2018")
  expect_equal(out[2], "")                 # blank line inserted
  expect_equal(out[3], "|Topic|Length|")
  expect_true("{: .table}" %in% out)
})

test_that("scaffolds gitignore the serve artifacts", {
  dir <- file.path(withr::local_tempdir(), "site")
  new_site(dir, theme = "minima", sample = FALSE)
  expect_true(".jekylldown-serve.*" %in%
                readLines(file.path(dir, ".gitignore")))
})

test_that("ensure_serve_gitignore covers pre-existing sites, once", {
  site <- withr::local_tempdir()
  xfun::write_utf8("_site/", file.path(site, ".gitignore"))
  jekylldown:::ensure_serve_gitignore(site)
  jekylldown:::ensure_serve_gitignore(site)   # idempotent
  gi <- readLines(file.path(site, ".gitignore"))
  expect_equal(sum(gi == ".jekylldown-serve.*"), 1)
  expect_true("_site/" %in% gi)

  # and creates the file when the site has none
  bare <- withr::local_tempdir()
  jekylldown:::ensure_serve_gitignore(bare)
  expect_true(file.exists(file.path(bare, ".gitignore")))
})

test_that("wait_for_server detects a live port and a dead worker", {
  port <- servr::random_port()
  # nothing listening + no process -> times out quickly
  expect_false(jekylldown:::wait_for_server(port, timeout = 1))

  # a real listener flips it to TRUE
  px <- processx::process$new(
    file.path(R.home("bin"), "Rscript"),
    c("-e", sprintf("servr::httd(port = %d, daemon = FALSE, browser = FALSE)",
                    port)))
  on.exit(px$kill(), add = TRUE)
  expect_true(jekylldown:::wait_for_server(port, px, timeout = 30))

  # a dead worker returns FALSE immediately
  px$kill()
  Sys.sleep(0.3)
  expect_false(jekylldown:::wait_for_server(port, px, timeout = 5))
})

test_that("site_root() guides the user when called outside a site", {
  not_a_site <- withr::local_tempdir()
  expect_error(site_root(not_a_site), "pass its\\s+path explicitly")
  expect_error(site_root(file.path(not_a_site, "nope")),
               "does not exist")
})
