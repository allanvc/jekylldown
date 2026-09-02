bundled_template <- function() {
  xfun::read_utf8(system.file("jekyll-feed", "feed-0.17.0.xml",
                              package = "jekylldown", mustWork = TRUE))
}

# A site whose isolated GEM_HOME holds a fake jekyll-feed gem carrying
# the bundled template, so the "gem" path runs without Ruby and without
# the network. R_USER_DATA_DIR redirects tools::R_user_dir().
local_site <- function(gem_version = "0.17.0", lock = gem_version,
                       config = c("title: blank", "first_name: Ada",
                                  "middle_name: ", "last_name: Lovelace",
                                  "url: https://ada.example.org",
                                  "baseurl: \"\"", "theme: al-folio"),
                       env = parent.frame()) {
  data <- withr::local_tempdir(.local_envir = env)
  withr::local_envvar(c(R_USER_DATA_DIR = data), .local_envir = env)
  if (!is.null(gem_version)) {
    # GEM_HOME layout: <gem home>/gems/<name>-<version>/
    gem <- file.path(jekylldown:::jd_gem_home(), "gems",
                     paste0("jekyll-feed-", gem_version), "lib", "jekyll-feed")
    fs::dir_create(gem)
    xfun::write_utf8(bundled_template(), file.path(gem, "feed.xml"))
  }
  site <- withr::local_tempdir(.local_envir = env)
  xfun::write_utf8(config, file.path(site, "_config.yml"))
  if (!is.null(lock)) {
    xfun::write_utf8(c("GEM", "  specs:", sprintf("    jekyll-feed (%s)", lock),
                       "      jekyll (>= 3.7, < 5.0)"),
                     file.path(site, "Gemfile.lock"))
  }
  site
}

test_that("the title patch applies to jekyll-feed's template", {
  out <- jekylldown:::patch_feed_template(bundled_template(), "0.17.0", "gem")
  # nothing may precede the XML declaration; the marker follows it
  expect_match(out[1], "^<\\?xml")
  expect_match(out[2], "jekylldown: rendered from jekyll-feed 0.17.0 \\(gem\\)")
  expect_equal(jekylldown:::feed_include_version(out), "0.17.0")
  # the anchor survives only inside the else branch of the blank check
  anchor <- which(trimws(out) == jekylldown:::feed_anchor)
  expect_length(anchor, 1)
  expect_match(out[anchor - 1], "\\{% else %\\}")
  expect_true(any(grepl("site.title == 'blank'", out, fixed = TRUE)))
  expect_true(any(grepl("site.first_name", out, fixed = TRUE)))
  # the rest of the template is intact
  expect_true(any(grepl("<entry", out, fixed = TRUE)))
  expect_equal(sum(grepl("<feed ", out, fixed = TRUE)), 1)
})

test_that("a template without the anchor line is refused, loudly", {
  tpl <- bundled_template()
  tpl <- tpl[trimws(tpl) != jekylldown:::feed_anchor]
  expect_error(
    jekylldown:::patch_feed_template(tpl, "9.9.9", "gem"),
    "does not have the line jekylldown patches")
})

test_that("add_feed writes the include from the installed gem and the pages", {
  site <- local_site()
  paths <- suppressMessages(add_feed("R", dir = site))

  inc <- file.path(site, "_includes", "atom-feed.xml")
  # site_root() normalises the site path; on Windows the tempdir may come
  # back in 8.3 short form, so compare normalised paths on both sides
  expect_equal(normalizePath(attr(paths, "include")), normalizePath(inc))
  expect_equal(normalizePath(paths),
               normalizePath(file.path(site, c("feed.xml", "feed/R.xml"))))
  lines <- readLines(inc)
  expect_match(lines[2], "jekyll-feed 0.17.0 \\(gem\\)")

  main <- readLines(file.path(site, "feed.xml"))
  expect_equal(main[1], "---")
  expect_true("collection: posts" %in% main)
  expect_false(any(grepl("^category:", main)))
  expect_true("{%- include atom-feed.xml -%}" %in% main)

  r <- readLines(file.path(site, "feed", "R.xml"))
  expect_true('category: "R"' %in% r)
  expect_true("sitemap: false" %in% r)
  expect_true("{%- include atom-feed.xml -%}" %in% r)
})

test_that("add_feed is idempotent, follows gem upgrades and honours force", {
  site <- local_site()
  suppressMessages(add_feed(dir = site))
  inc <- file.path(site, "_includes", "atom-feed.xml")
  before <- readLines(inc)

  # same gem: untouched
  suppressMessages(add_feed(dir = site))
  expect_identical(readLines(inc), before)

  # a newer gem appears (and the lock moves to it): regenerated
  gem <- file.path(jekylldown:::jd_gem_home(), "gems",
                   "jekyll-feed-0.18.0", "lib", "jekyll-feed")
  fs::dir_create(gem)
  xfun::write_utf8(bundled_template(), file.path(gem, "feed.xml"))
  xfun::write_utf8(c("GEM", "  specs:", "    jekyll-feed (0.18.0)"),
                   file.path(site, "Gemfile.lock"))
  suppressMessages(add_feed(dir = site))
  expect_match(readLines(inc)[2], "jekyll-feed 0.18.0 \\(gem\\)")

  # the locked version wins over a newer one lying around
  xfun::write_utf8(c("GEM", "  specs:", "    jekyll-feed (0.17.0)"),
                   file.path(site, "Gemfile.lock"))
  suppressMessages(add_feed(dir = site))
  expect_match(readLines(inc)[2], "jekyll-feed 0.17.0 \\(gem\\)")

  # force rewrites even when current
  xfun::write_utf8(c(readLines(inc), "<!-- stray -->"), inc)
  suppressMessages(add_feed(dir = site, force = TRUE))
  expect_false(any(grepl("stray", readLines(inc), fixed = TRUE)))
})

test_that("hand-written include and feed pages are left alone", {
  site <- local_site()
  fs::dir_create(file.path(site, "_includes"))
  xfun::write_utf8("<feed>mine</feed>",
                   file.path(site, "_includes", "atom-feed.xml"))
  xfun::write_utf8(c("---", "---", "<feed>custom</feed>"),
                   file.path(site, "feed.xml"))
  expect_message(add_feed("R", dir = site), "not managed by jekylldown")
  expect_equal(readLines(file.path(site, "_includes", "atom-feed.xml")),
               "<feed>mine</feed>")
  expect_equal(readLines(file.path(site, "feed.xml"))[3], "<feed>custom</feed>")
  # the category page is still written, rendering the (user's) include
  expect_true(file.exists(file.path(site, "feed", "R.xml")))
})

test_that("without a gem or a lockfile the bundled copy is used (offline)", {
  site <- local_site(gem_version = NULL, lock = NULL)
  expect_message(add_feed(dir = site), "shipped with jekylldown")
  lines <- readLines(file.path(site, "_includes", "atom-feed.xml"))
  expect_match(lines[2], "jekyll-feed 0.17.0 \\(bundled\\)")
})

test_that("the lockfile version is read from the specs, not the dependencies", {
  site <- local_site(gem_version = NULL, lock = NULL)
  xfun::write_utf8(c("GEM", "  specs:",
                     "    jekyll-feed (0.17.0)",
                     "      jekyll (>= 3.7, < 5.0)",
                     "    minima (2.5.1)",
                     "      jekyll-feed (~> 0.9)"),
                   file.path(site, "Gemfile.lock"))
  expect_equal(jekylldown:::lock_feed_version(site), "0.17.0")
})

test_that("the installed jekyll-feed gem still has the anchor line", {
  # the drift detector: fails as soon as the real gem changes its template
  gem <- Sys.glob(file.path(jekylldown:::jd_gem_home(), "gems",
                            "jekyll-feed-*", "lib", "jekyll-feed", "feed.xml"))
  skip_if(!length(gem), "jekyll-feed gem not installed")
  for (f in gem) {
    version <- sub("^.*jekyll-feed-([0-9.]+)/.*$", "\\1", f)
    out <- jekylldown:::patch_feed_template(xfun::read_utf8(f), version, "gem")
    expect_equal(jekylldown:::feed_include_version(out), version)
  }
})

test_that("use_r_bloggers adds the feed and the link on al-folio", {
  site <- local_site()
  fs::dir_create(file.path(site, "_pages"))
  blog <- file.path(site, "_pages", "blog.md")
  xfun::write_utf8(c(
    "---", "layout: default", "permalink: /blog/", "---",
    "",
    '<div class="post">',
    "",
    "{% if blog_name_size > 0 %}",
    '  <div class="header-bar">',
    "    <h1>{{ site.blog_name }}</h1>",
    "  </div>",
    "  {% endif %}",
    "",
    "{% assign featured_posts = site.posts | where: \"featured\", \"true\" %}"
  ), blog)

  res <- suppressMessages(use_r_bloggers(dir = site))
  expect_equal(res$url, "https://ada.example.org/feed/R.xml")
  expect_true(file.exists(file.path(site, "feed", "R.xml")))
  expect_equal(normalizePath(res$link), normalizePath(blog))

  lines <- readLines(blog)
  b <- which(lines == jekylldown:::rb_begin)
  expect_length(b, 1)
  # right after the endif that closes the header bar
  expect_match(lines[b - 2], "endif")
  expect_true(any(grepl("r-bloggers.com", lines, fixed = TRUE)))
  expect_true(any(grepl("/feed/R.xml", lines, fixed = TRUE)))
  expect_true(any(grepl("/blog/category/r/", lines, fixed = TRUE)))

  # idempotent
  suppressMessages(use_r_bloggers(dir = site))
  expect_length(which(readLines(blog) == jekylldown:::rb_begin), 1)
})

test_that("use_r_bloggers prints the snippet on other themes", {
  site <- local_site(config = c("title: My blog", "theme: minima",
                                "url: https://b.example.org",
                                "baseurl: /blog"))
  res <- NULL
  expect_message(res <- use_r_bloggers(dir = site), "link back")
  expect_null(res$link)
  expect_equal(res$url, "https://b.example.org/blog/feed/R.xml")
  expect_true(file.exists(file.path(site, "feed", "R.xml")))
})

test_that("bad category arguments are rejected", {
  site <- local_site()
  expect_error(use_r_bloggers(c("R", "S"), dir = site), "single category")
  expect_error(use_r_bloggers(site), "looks like a site directory")
})
