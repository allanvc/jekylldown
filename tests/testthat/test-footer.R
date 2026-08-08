ver <- as.character(utils::packageVersion("jekylldown"))

test_that("footer credit goes into footer_text after the Jekyll sentence", {
  site <- withr::local_tempdir()
  xfun::write_utf8(c(
    "title: x",
    "footer_text: >",
    '  Powered by <a href="https://jekyllrb.com/">Jekyll</a> with al-folio theme.',
    '  Hosted by <a href="https://pages.github.com/">GitHub Pages</a>.',
    "keywords: a"
  ), file.path(site, "_config.yml"))

  add_footer_credit(site)
  lines <- readLines(file.path(site, "_config.yml"))
  at <- grep("jekylldown</a>", lines, fixed = TRUE)
  expect_length(at, 1)
  expect_match(lines[at], sprintf("jekylldown</a> %s\\.", ver))
  # right after the Jekyll sentence, before the hosting one
  expect_true(grepl("Jekyll", lines[at - 1], fixed = TRUE))
  expect_true(grepl("Hosted", lines[at + 1], fixed = TRUE))

  # idempotent: re-running replaces instead of stacking
  add_footer_credit(site)
  lines <- readLines(file.path(site, "_config.yml"))
  expect_length(grep("jekylldown</a>", lines, fixed = TRUE), 1)

  # a stale version is refreshed by the build hook
  xfun::write_utf8(sub(ver, "0.0.1", lines, fixed = TRUE),
                   file.path(site, "_config.yml"))
  refresh_footer_credit(site)
  lines <- readLines(file.path(site, "_config.yml"))
  expect_match(lines[grep("jekylldown</a>", lines)],
               sprintf("jekylldown</a> %s\\.", ver))

  remove_footer_credit(site)
  expect_false(any(grepl("jekylldown</a>",
                         readLines(file.path(site, "_config.yml")),
                         fixed = TRUE)))
})

test_that("footer credit lands in a local footer include for gem themes", {
  site <- withr::local_tempdir()
  xfun::write_utf8(c("title: x", "theme: minima"),
                   file.path(site, "_config.yml"))
  fs::dir_create(file.path(site, "_includes"))
  xfun::write_utf8(c("<footer>", "<p>footer</p>", "</footer>"),
                   file.path(site, "_includes", "footer.html"))

  add_footer_credit(site)
  lines <- readLines(file.path(site, "_includes", "footer.html"))
  at <- grep("jekylldown-credit", lines, fixed = TRUE)
  expect_length(at, 1)
  # inside the footer element, before </footer>
  expect_true(at < grep("</footer>", lines, fixed = TRUE))

  add_footer_credit(site)   # idempotent
  lines <- readLines(file.path(site, "_includes", "footer.html"))
  expect_length(grep("jekylldown-credit", lines, fixed = TRUE), 1)

  remove_footer_credit(site)
  lines <- readLines(file.path(site, "_includes", "footer.html"))
  expect_false(any(grepl("jekylldown", lines, fixed = TRUE)))
  expect_true("<p>footer</p>" %in% lines)
})

test_that("new_site adds the credit to a minima scaffold when possible", {
  skip_if(is.null(jekylldown:::find_cmd("gem")), "no toolchain")
  site <- file.path(withr::local_tempdir(), "s")
  suppressMessages(new_site(site, sample = FALSE))
  inc <- file.path(site, "_includes", "footer.html")
  skip_if_not(file.exists(inc), "minima gem not installed")
  expect_true(any(grepl("jekylldown-credit", readLines(inc), fixed = TRUE)))
})
