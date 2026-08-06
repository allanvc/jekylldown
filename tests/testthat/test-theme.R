make_themed_site <- function(dir) {
  fs::dir_create(file.path(dir, c("_sass", "assets/css")))
  xfun::write_utf8(c(
    "$red-color: #ff3636 !default;",
    "$purple-color: #b509ac !default;"
  ), file.path(dir, "_sass", "_variables.scss"))
  xfun::write_utf8(c(
    ":root {",
    "  --global-theme-color: #{v.$purple-color};",
    "  --global-bg-color: #ffffff;",
    "  --global-footer-bg-color: #1c1c1d;",
    "}",
    'html[data-theme="dark"] {',
    "  --global-theme-color: #{v.$cyan-color};",
    "  --global-bg-color: #1c1c1d;",
    "  --global-footer-bg-color: #1c1c1d;",
    "}"
  ), file.path(dir, "_sass", "_themes.scss"))
  xfun::write_utf8(c(
    ".navbar {",
    "  background-color: var(--global-bg-color);",
    "}"
  ), file.path(dir, "_sass", "_navbar.scss"))
  xfun::write_utf8('@use "themes";', file.path(dir, "assets/css/main.scss"))
  dir
}

test_that("set_theme_color appends overrides for every theme selector", {
  site <- make_themed_site(withr::local_tempdir())

  hex <- set_theme_color(site, "red")
  expect_equal(hex, "#ff3636")

  css <- readLines(file.path(site, "assets/css/main.scss"))
  expect_true(any(grepl("--global-theme-color: #ff3636;", css, fixed = TRUE)))
  expect_true(any(grepl('html[data-theme="dark"] {', css, fixed = TRUE)))
  # both light and dark blocks overridden
  expect_equal(sum(grepl("--global-theme-color: #ff3636;", css, fixed = TRUE)), 2)

  # changing the color replaces the previous override instead of stacking
  set_theme_color(site, "#123456")
  css <- readLines(file.path(site, "assets/css/main.scss"))
  expect_false(any(grepl("#ff3636", css, fixed = TRUE)))
  expect_equal(sum(grepl("--global-theme-color: #123456;", css, fixed = TRUE)), 2)
  expect_equal(sum(css == '@use "themes";'), 1)
})

test_that("set_theme_color rejects unknown color names with the palette", {
  site <- make_themed_site(withr::local_tempdir())
  expect_error(set_theme_color(site, "mauve"), "red")
})

test_that("set_theme_style overrides CSS variables per mode", {
  site <- make_themed_site(withr::local_tempdir())

  set_theme_style(site,
    accent = "red",
    background = c(light = "#fffdf7", dark = "#101010"),
    footer_background = "black")

  css <- readLines(file.path(site, "assets/css/main.scss"))
  # palette name resolved; single value lands in both modes
  expect_equal(sum(grepl("--global-theme-color: #ff3636;", css, fixed = TRUE)), 2)
  expect_equal(sum(grepl("--global-footer-bg-color: black;", css, fixed = TRUE)), 2)
  # per-mode values land once each, in the right block
  light_at <- grep("--global-bg-color: #fffdf7;", css, fixed = TRUE)
  dark_at <- grep("--global-bg-color: #101010;", css, fixed = TRUE)
  expect_length(light_at, 1)
  expect_length(dark_at, 1)
  root_at <- grep(":root {", css, fixed = TRUE)
  dark_block_at <- grep('html[data-theme="dark"] {', css, fixed = TRUE)
  expect_true(any(root_at < light_at & light_at < dark_block_at[length(dark_block_at)]))

  # re-running replaces, not stacks
  set_theme_style(site, accent = "#123456")
  css <- readLines(file.path(site, "assets/css/main.scss"))
  expect_false(any(grepl("#fffdf7", css, fixed = TRUE)))
  expect_equal(sum(grepl("--global-theme-color: #123456;", css, fixed = TRUE)), 2)

  expect_error(set_theme_style(site, banana = "red"), "banana")
  expect_error(set_theme_style(site), "named")

  # a variable the theme does not define draws a warning
  expect_warning(set_theme_style(site, card_background = "#fff"),
                 "not found")
})

test_that("set_theme_font writes font-face and overrides", {
  site <- make_themed_site(withr::local_tempdir())
  withr::local_options(jekylldown.font_fetcher = function(family) {
    sprintf('@font-face { font-family: "%s"; src: url(fake.woff2); }', family)
  })

  set_theme_font(site, family = "Lora", size = "17px",
                 code = "JetBrains Mono")
  css <- readLines(file.path(site, "assets/css/main.scss"))
  expect_true(any(grepl('@font-face { font-family: "Lora"', css, fixed = TRUE)))
  expect_true(any(grepl('@font-face { font-family: "JetBrains Mono"', css,
                        fixed = TRUE)))
  expect_true(any(grepl('body { font-family: "Lora", sans-serif; }', css,
                        fixed = TRUE)))
  expect_true(any(grepl(
    'code, pre, kbd, samp { font-family: "JetBrains Mono", monospace; }',
    css, fixed = TRUE)))
  expect_true(any(grepl("html { font-size: 17px; }", css, fixed = TRUE)))

  # replaces on re-run; validates size
  set_theme_font(site, size = "110%")
  css <- readLines(file.path(site, "assets/css/main.scss"))
  expect_false(any(grepl("Lora", css, fixed = TRUE)))
  expect_error(set_theme_font(site, size = "seventeen"), "CSS length")
  expect_error(set_theme_font(site), "Nothing to set")

  # a failing fetch warns but still writes the override
  withr::local_options(jekylldown.font_fetcher = function(family) NULL)
  expect_warning(set_theme_font(site, family = "Ghost"), "Google Fonts")
  css <- readLines(file.path(site, "assets/css/main.scss"))
  expect_true(any(grepl('body { font-family: "Ghost", sans-serif; }', css,
                        fixed = TRUE)))
})

test_that("set_element_style maps semantic elements to theme selectors", {
  site <- make_themed_site(withr::local_tempdir())

  set_element_style(site, "navbar", background = "red", color = "white",
                    font_weight = "600")
  css <- readLines(file.path(site, "assets/css/main.scss"))
  expect_true(any(grepl(".navbar {", css, fixed = TRUE)))
  expect_true(any(grepl("background-color: #ff3636;", css, fixed = TRUE)))
  expect_true(any(grepl("color: white;", css, fixed = TRUE)))
  expect_true(any(grepl("font-weight: 600;", css, fixed = TRUE)))

  # two elements coexist in separate blocks; re-running one replaces it
  set_element_style(site, "headings", color = "#222222")
  set_element_style(site, "navbar", background = "blue")
  css <- readLines(file.path(site, "assets/css/main.scss"))
  expect_true(any(grepl("color: #222222;", css, fixed = TRUE)))
  expect_false(any(grepl("#ff3636", css, fixed = TRUE)))
  expect_true(any(grepl("background-color: blue;", css, fixed = TRUE)))

  expect_error(set_element_style(site, "sidebar", color = "red"))
  expect_error(set_element_style(site, "navbar"), "Nothing to set")

  # selector missing from the theme sass -> the fragile-layer warning
  expect_warning(set_element_style(site, "buttons", color = "red"),
                 "not found")
})

test_that("add_css writes and removes managed blocks", {
  site <- make_themed_site(withr::local_tempdir())

  add_css(site, ".profile img { border-radius: 50%; }", id = "round-avatar")
  css <- readLines(file.path(site, "assets/css/main.scss"))
  expect_true(any(grepl("border-radius: 50%;", css, fixed = TRUE)))
  expect_true(any(grepl("custom css: round-avatar", css, fixed = TRUE)))

  add_css(site, character(0), id = "round-avatar")
  css <- readLines(file.path(site, "assets/css/main.scss"))
  expect_false(any(grepl("round-avatar", css, fixed = TRUE)))

  expect_error(add_css(site, "a {}", id = "Bad Id!"), "id")
})

test_that("site_theme detects the theme from _config.yml", {
  site <- withr::local_tempdir()
  expect_equal(jekylldown:::site_theme(site), "unknown")
  xfun::write_utf8("theme: minima", file.path(site, "_config.yml"))
  expect_equal(jekylldown:::site_theme(site), "minima")
  xfun::write_utf8("theme: al_folio_core", file.path(site, "_config.yml"))
  expect_equal(jekylldown:::site_theme(site), "al-folio")
})

make_chirpy_site <- function(dir) {
  fs::dir_create(file.path(dir, c("_sass/colors", "assets/css")))
  xfun::write_utf8("theme: jekyll-theme-chirpy", file.path(dir, "_config.yml"))
  xfun::write_utf8(c(
    "@mixin light-scheme {",
    "  --main-bg: white;",
    "  --text-color: #34343c;",
    "  --link-color: #0056b2;",
    "}"
  ), file.path(dir, "_sass", "colors", "typography-light.scss"))
  xfun::write_utf8(c("---", "---", "", "@import 'main';"),
                   file.path(dir, "assets/css/jekyll-theme-chirpy.scss"))
  dir
}

make_mm_site <- function(dir) {
  fs::dir_create(file.path(dir, c("_sass/minimal-mistakes/skins", "assets/css")))
  xfun::write_utf8(c("title: x", "theme: minimal-mistakes-jekyll"),
                   file.path(dir, "_config.yml"))
  for (s in c("default", "dark", "air")) {
    xfun::write_utf8("/* skin */",
      file.path(dir, "_sass/minimal-mistakes/skins", paste0("_", s, ".scss")))
  }
  xfun::write_utf8(".masthead { position: relative; }",
                   file.path(dir, "_sass/minimal-mistakes/_masthead.scss"))
  xfun::write_utf8(c("---", "---", "", '@import "minimal-mistakes";'),
                   file.path(dir, "assets/css/main.scss"))
  dir
}

test_that("set_theme_style on Chirpy mirrors its mode selectors", {
  site <- make_chirpy_site(withr::local_tempdir())

  set_theme_style(site, accent = "#d2603a",
                  background = c(light = "white", dark = "#0d0d0d"))
  css <- readLines(file.path(site, "assets/css/jekyll-theme-chirpy.scss"))
  expect_true("html:not([data-mode]), html[data-mode='light'] {" %in% css)
  expect_true("html[data-mode='dark'] {" %in% css)
  expect_true("@media (prefers-color-scheme: dark) {" %in% css)
  # accent (single value) present in light and dark + media block
  expect_equal(sum(grepl("--link-color: #d2603a;", css, fixed = TRUE)), 3)
  expect_equal(sum(grepl("--main-bg: white;", css, fixed = TRUE)), 1)
  expect_equal(sum(grepl("--main-bg: #0d0d0d;", css, fixed = TRUE)), 2)

  # chirpy-only option validated against the chirpy map
  expect_error(set_theme_style(site, footer_background = "x"),
               "sidebar_background")
  # var missing from the fixture sass -> warning
  expect_warning(set_theme_style(site, heading = "#000"), "not found")

  # set_theme_color delegates to the accent variable
  set_theme_color(site, "#00ff00")
  css <- readLines(file.path(site, "assets/css/jekyll-theme-chirpy.scss"))
  expect_true(any(grepl("--link-color: #00ff00;", css, fixed = TRUE)))
})

test_that("Minimal Mistakes styles via skins, not variables", {
  site <- make_mm_site(withr::local_tempdir())

  expect_error(set_theme_style(site, background = "#fff"), "set_theme_skin")
  expect_error(set_theme_color(site, "red"), "set_theme_skin")

  set_theme_skin(site, "dark")
  cfg <- readLines(file.path(site, "_config.yml"))
  expect_true('minimal_mistakes_skin: "dark"' %in% cfg)
  set_theme_skin(site, "air")
  cfg <- readLines(file.path(site, "_config.yml"))
  expect_true('minimal_mistakes_skin: "air"' %in% cfg)
  expect_equal(sum(grepl("minimal_mistakes_skin", cfg)), 1)

  expect_error(set_theme_skin(site, "vaporwave"), "Available")
  # skins are MM-only
  chirpy <- make_chirpy_site(withr::local_tempdir())
  expect_error(set_theme_skin(chirpy, "dark"), "Minimal Mistakes")

  # element map uses MM selectors, validated against its sass
  set_element_style(site, "navbar", background = "#000")
  css <- readLines(file.path(site, "assets/css/main.scss"))
  expect_true(any(grepl(".masthead {", css, fixed = TRUE)))
})

test_that("new_site scaffolds a gem-based Minimal Mistakes site", {
  dir <- file.path(withr::local_tempdir(), "mm-site")
  new_site(dir, theme = "minimal-mistakes", title = "MM blog",
           sample = FALSE)
  cfg <- readLines(file.path(dir, "_config.yml"))
  expect_true("theme: minimal-mistakes-jekyll" %in% cfg)
  expect_true("title: MM blog" %in% cfg)
  expect_true("  - jekyll-include-cache" %in% cfg)
  expect_true(any(grepl("- _source", cfg)))
  gemfile <- readLines(file.path(dir, "Gemfile"))
  expect_true(any(grepl("minimal-mistakes-jekyll", gemfile)))
  expect_true(dir.exists(file.path(dir, "_source")))
  expect_true(file.exists(file.path(dir, "build.R")))
  expect_equal(jekylldown:::site_theme(dir), "minimal-mistakes")
})

test_that("site_theme tells minimal-mistakes and chirpy apart from minima", {
  site <- withr::local_tempdir()
  xfun::write_utf8("theme: minimal-mistakes-jekyll",
                   file.path(site, "_config.yml"))
  expect_equal(jekylldown:::site_theme(site), "minimal-mistakes")
  xfun::write_utf8("theme: jekyll-theme-chirpy", file.path(site, "_config.yml"))
  expect_equal(jekylldown:::site_theme(site), "chirpy")
  xfun::write_utf8("remote_theme: mmistakes/minimal-mistakes",
                   file.path(site, "_config.yml"))
  expect_equal(jekylldown:::site_theme(site), "minimal-mistakes")
})

test_that("add_mathjax enables math per theme convention", {
  # minima/unknown: script into a site-local head include, before </head>
  site <- withr::local_tempdir()
  fs::dir_create(file.path(site, "_includes"))
  xfun::write_utf8("theme: minima", file.path(site, "_config.yml"))
  xfun::write_utf8(c("<head>", "  <title>x</title>", "</head>"),
                   file.path(site, "_includes", "head.html"))
  add_mathjax(site)
  head <- readLines(file.path(site, "_includes", "head.html"))
  expect_true(any(grepl("MathJax.js", head, fixed = TRUE)))
  expect_true(grep("MathJax.js", head)[1] < grep("</head>", head, fixed = TRUE))
  expect_true(any(grepl("inlineMath", head)))
  add_mathjax(site)  # idempotent
  expect_equal(sum(grepl("MathJax.js", readLines(
    file.path(site, "_includes", "head.html")), fixed = TRUE)), 1)

  # al-folio: flips the native flag
  alf <- withr::local_tempdir()
  xfun::write_utf8(c("theme: al_folio_core", "enable_math: false"),
                   file.path(alf, "_config.yml"))
  add_mathjax(alf)
  expect_true("enable_math: true" %in% readLines(file.path(alf, "_config.yml")))

  # chirpy: front matter default
  ch <- withr::local_tempdir()
  xfun::write_utf8(c("theme: jekyll-theme-chirpy", "defaults:",
                     "  - scope:", '      path: ""', "    values:",
                     "      layout: post"),
                   file.path(ch, "_config.yml"))
  add_mathjax(ch)
  cfg <- readLines(file.path(ch, "_config.yml"))
  expect_true("      math: true" %in% cfg)
  expect_equal(sum(grepl("^defaults:", cfg)), 1)   # no duplicate key

  # minimal-mistakes: head_scripts hook
  mm <- withr::local_tempdir()
  xfun::write_utf8("theme: minimal-mistakes-jekyll",
                   file.path(mm, "_config.yml"))
  add_mathjax(mm)
  cfg <- readLines(file.path(mm, "_config.yml"))
  expect_true("head_scripts:" %in% cfg)
  expect_true(any(grepl("MathJax.js", cfg, fixed = TRUE)))
})
