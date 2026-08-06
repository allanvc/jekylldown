make_hugo_site <- function(dir) {
  fs::dir_create(file.path(dir, c("content/post/my-bundle", "static/images",
                                  "content/talks", "layouts")))
  xfun::write_utf8(c(
    'baseURL = "https://example.com/"',
    'title = "My Hugo blog"',
    "[params]",
    '  author = "Ada L. Lovelace"',
    '  description = "A site about numbers"  # trailing comment',
    "[menu]",
    "  [[menu.main]]",
    '    name = "Home"',
    '    url = "/"',
    "    weight = 1",
    "  [[menu.main]]",
    '    name = "Publications"',
    '    url = "/publications"',
    "    weight = 2",
    "  [[menu.main]]",
    '    name = "Posts"',
    '    url = "/post"',
    "    weight = 3",
    "  [[menu.main]]",
    '    name = "Talks"',
    '    url = "/talks"',
    "    weight = 4"
  ), file.path(dir, "config.toml"))

  # home page with an avatar shortcode
  xfun::write_utf8(c(
    "---",
    'title: "Ada L. Lovelace"',
    "---",
    "",
    '{{< figure class="avatar" src="/images/me.jpg" >}}',
    "",
    "I compute, therefore I am."
  ), file.path(dir, "content/_index.md"))

  # menu-referenced pages (one plain file, one section _index; note the
  # leading blank line before the front matter, as seen in the wild)
  xfun::write_utf8(c(
    "",
    "---",
    'title: "Main Publications"',
    "---",
    "",
    "1. A paper. ![](/images/logo.png)"
  ), file.path(dir, "content/publications.md"))
  xfun::write_utf8(c(
    "---",
    'title: "Talks"',
    "---",
    "",
    "My talks."
  ), file.path(dir, "content/talks/_index.md"))

  # content NOT referenced by the menu stays behind
  xfun::write_utf8(c("---", 'title: "Secret"', "---", "shh"),
                   file.path(dir, "content/secret.md"))

  # contact page with social profiles (the repository link must be ignored;
  # the second e-mail must not win over the first)
  xfun::write_utf8(c(
    "---",
    'title: "Contact"',
    "---",
    "",
    "* Email: [me](mailto:ada@example.com) |",
    "  [work](mailto:ada@work.example.com)",
    "* [Resume](/files/resume.pdf)",
    "",
    "## Social",
    "",
    "1. [LinkedIn](https://www.linkedin.com/in/ada-lovelace/)",
    "2. [GitHub](https://github.com/ada)",
    "3. [My engine](https://github.com/ada/analytical-engine)",
    "4. [StackOverflow](https://stackoverflow.com/users/12345/ada)"
  ), file.path(dir, "content/contact.md"))

  # TOML front matter, shortcodes, draft
  xfun::write_utf8(c(
    "+++",
    'title = "A TOML post"',
    'date = "2020-05-04T10:00:00Z"',
    'tags = ["r", "stats"]',
    "draft = true",
    "+++",
    "",
    '{{< figure src="/images/logo.png" caption="The logo" >}}',
    '{{< figure class="pkg" src="/images/logo.png" >}}',
    "{{< youtube dQw4w9WgXcQ >}}",
    '{{< tweet 123 >}}'
  ), file.path(dir, "content/post/toml-post.md"))

  # theme CSS that gives figure classes their display size
  fs::dir_create(file.path(dir, "themes/researcher/assets/sass"))
  xfun::write_utf8(c(
    "$pkg-size: 90px;",
    ".content {",
    "    .avatar > img {",
    "        border-radius: 50%;",
    "        width: 130px;",
    "    }",
    "    .pkg > img {",
    "        float: right;",
    "        width: $pkg-size;",
    "    }",
    "}"
  ), file.path(dir, "themes/researcher/assets/sass/researcher.scss"))

  # blogdown .Rmd with YAML front matter + generated .html artifact
  xfun::write_utf8(c(
    "---",
    'title: "An Rmd post"',
    "date: 2021-01-15",
    "slug: my-rmd-post",
    "---",
    "",
    "The answer is `r 40 + 2`."
  ), file.path(dir, "content/post/rmd-post.Rmd"))
  xfun::write_utf8("<html>artifact</html>",
                   file.path(dir, "content/post/rmd-post.html"))

  # leaf bundle with a resource and relative image link
  xfun::write_utf8(c(
    "---",
    'title: "Bundle post"',
    "date: 2022-03-01",
    "---",
    "",
    "![a plot](plot.png)"
  ), file.path(dir, "content/post/my-bundle/index.md"))
  writeBin(as.raw(c(0x89, 0x50, 0x4e, 0x47)),
           file.path(dir, "content/post/my-bundle/plot.png"))

  # section page must not become a post
  xfun::write_utf8(c("---", 'title: "Posts"', "---"),
                   file.path(dir, "content/post/_index.md"))

  writeBin(as.raw(c(0x89, 0x50, 0x4e, 0x47)),
           file.path(dir, "static/images/logo.png"))
  writeBin(as.raw(c(0x89, 0x50, 0x4e, 0x47)),
           file.path(dir, "static/images/me.jpg"))
  writeBin(as.raw(0x00), file.path(dir, "static/unused.bin"))
  writeBin(as.raw(0x00), file.path(dir, "favicon-source.txt"))  # not static/
  xfun::write_utf8("icon", file.path(dir, "static/favicon.ico"))
  dir
}

test_that("migrate_hugo converts posts, assets and front matter", {
  tmp <- withr::local_tempdir()
  hugo <- make_hugo_site(file.path(tmp, "hugo"))
  site <- file.path(tmp, "jekyll")

  report <- migrate_hugo(hugo, site)

  expect_length(report$posts, 3)
  expect_length(report$skipped, 0)

  # TOML post: date from front matter, filename kept as slug (preserves the
  # Hugo URL), draft unpublished, shortcodes
  toml <- file.path(site, "_posts", "2020-05-04-toml-post.md")
  expect_true(file.exists(toml))
  md <- readLines(toml)
  expect_true(any(grepl("^published: no$", md)))
  expect_true(any(grepl("^- stats$", md)))
  expect_true(any(grepl("!\\[The logo\\]\\(/images/logo.png\\)", md)))
  expect_true(any(grepl("![](/images/logo.png){: .pkg}", md, fixed = TRUE)))
  expect_true(any(grepl("youtube.com/embed/dQw4w9WgXcQ", md)))
  # the unconverted shortcode stays visible (liquid-escaped so the literal
  # braces cannot abort Jekyll's build) and is flagged in the report
  expect_true(any(grepl("tweet 123", md, fixed = TRUE)))
  expect_true(any(grepl("{% raw %}", md, fixed = TRUE)))
  expect_equal(report$drafts, toml)
  expect_true("tweet" %in% report$shortcodes[[toml]])

  # Rmd post goes to _source with the slug from front matter; artifact skipped
  expect_true(file.exists(file.path(site, "_source",
                                    "2021-01-15-my-rmd-post.Rmd")))
  expect_false(any(grepl("artifact", list.files(site, recursive = TRUE))))

  # bundle: slug from the bundle dir, resource copied, relative link rewritten
  bundle <- file.path(site, "_posts", "2022-03-01-my-bundle.md")
  expect_true(file.exists(bundle))
  expect_true(file.exists(file.path(
    site, "assets/img/posts/2022-03-01-my-bundle/plot.png")))
  expect_true(any(grepl(
    "\\{\\{ site.baseurl \\}\\}/assets/img/posts/2022-03-01-my-bundle/plot.png",
    readLines(bundle))))

  # _index.md did not become a post; static copied to site root
  expect_length(list.files(file.path(site, "_posts"), "index"), 0)
  expect_true(file.exists(file.path(site, "images", "logo.png")))

  # the Hugo source was not modified
  expect_true(file.exists(file.path(hugo, "content/post/toml-post.md")))

  # menu-referenced pages migrated (minima: site root), Hugo URL preserved,
  # nav_order from the menu weights
  pubs <- file.path(site, "publications.md")
  expect_true(file.exists(pubs))
  md <- readLines(pubs)
  expect_true(any(grepl("^title: Main Publications$", md)))
  expect_true(any(grepl("^permalink: /publications/$", md)))
  expect_true(any(grepl("^nav_order: 2$", md)))
  talks <- file.path(site, "talks.md")
  expect_true(file.exists(talks))
  expect_true(any(grepl("^nav_order: 4$", readLines(talks))))

  # home: _index.md body lands in index.md; on minima (no profile slot)
  # the avatar figure is converted to a plain image
  idx <- readLines(file.path(site, "index.md"))
  expect_true(any(grepl("I compute, therefore I am.", idx, fixed = TRUE)))
  expect_true(any(grepl("![](/images/me.jpg)", idx, fixed = TRUE)))

  # identity from the Hugo config
  cfg <- readLines(file.path(site, "_config.yml"))
  expect_true(any(grepl("^title: My Hugo blog$", cfg)))
  expect_true(any(grepl("^url: https://example.com$", cfg)))
  expect_true(any(grepl('^baseurl: ""$', cfg)))
  expect_true(any(grepl("^description: A site about numbers$", cfg)))

  # content not referenced by the menu is reported, not migrated
  expect_true("secret" %in% report$manual)
  expect_false(file.exists(file.path(site, "secret.md")))

  # figure classes keep their Hugo display size: rule ported from the
  # theme sass with variables resolved and selector rewritten for kramdown
  expect_setequal(report$styles, c("pkg", "avatar"))
  css <- readLines(file.path(site, "assets", "main.scss"))
  expect_true(any(grepl("img.pkg, .pkg img {", css, fixed = TRUE)))
  expect_true(any(grepl("width: 90px;", css, fixed = TRUE)))
  expect_true(any(grepl("img.avatar, .avatar img {", css, fixed = TRUE)))
  expect_true(any(grepl('@import "minima";', css, fixed = TRUE)))
})

test_that("only_referenced copies just the static files the site uses", {
  tmp <- withr::local_tempdir()
  hugo <- make_hugo_site(file.path(tmp, "hugo"))
  site <- file.path(tmp, "jekyll")

  report <- migrate_hugo(hugo, site, only_referenced = TRUE)

  # /images/logo.png is referenced by a post and a page; me.jpg by the home
  # page; favicons always kept
  expect_true(file.exists(file.path(site, "images", "logo.png")))
  expect_true(file.exists(file.path(site, "images", "me.jpg")))
  expect_true(file.exists(file.path(site, "favicon.ico")))
  # nothing references unused.bin
  expect_false(file.exists(file.path(site, "unused.bin")))
  expect_true("unused.bin" %in% report$static_skipped)
})

test_that("extract_dois and pair_previews work on a hand-written list", {
  lines <- c(
    '<div style="display:flex;">',
    '<img src="/img/JORS1.png" style="width:53px;">',
    '<span>Quadros A. (2024) <em>mRpostman</em>,',
    '<a href="https://doi.org/10.5334/jors.480">[link]</a></span>',
    "</div>",
    '<div style="display:flex;">',
    '<img src="/img/BJB.png">',
    '<span>... <a href="https://doi.org/10.28951/bjb.v40i2.566">[link]</a>',
    "</div>",
    "No doi here."
  )
  expect_equal(jekylldown:::extract_dois(lines),
               c("10.5334/jors.480", "10.28951/bjb.v40i2.566"))
  pv <- jekylldown:::pair_previews(lines)
  expect_equal(pv[["10.5334/jors.480"]], "/img/JORS1.png")
  expect_equal(pv[["10.28951/bjb.v40i2.566"]], "/img/BJB.png")
})

test_that("migrate_publications_bib writes papers.bib with previews", {
  tmp <- withr::local_tempdir()
  root <- file.path(tmp, "site")
  fs::dir_create(file.path(root, c("_bibliography", "_pages")))
  xfun::write_utf8(c("---", "layout: page", "nav_order: 99", "---"),
                   file.path(root, "_pages", "publications.md"))
  from <- file.path(tmp, "hugo")
  fs::dir_create(file.path(from, "static", "img"))
  writeBin(as.raw(1), file.path(from, "static", "img", "JORS1.png"))
  src <- file.path(from, "pubs.md")
  xfun::write_utf8(c(
    "---", 'title: "Pubs"', "---",
    '<img src="/img/JORS1.png">',
    '<span><a href="https://doi.org/10.5334/jors.480">[link]</a></span>',
    '<a href="https://doi.org/10.1234/gone">[dead]</a>'
  ), src)

  withr::local_options(jekylldown.bibtex_fetcher = function(doi) {
    if (doi == "10.1234/gone") return(NULL)
    sprintf("@article{key_1, doi={%s}, year={2024}}", doi)
  })
  res <- jekylldown:::migrate_publications_bib(src, root, nav_order = 2,
                                               from = from)

  expect_false(res$fallback)
  expect_equal(res$entries, 1L)
  expect_equal(res$failed, "10.1234/gone")
  bib <- readLines(file.path(root, "_bibliography", "papers.bib"))
  expect_match(bib[1], "^@article\\{key_1, preview=\\{JORS1.png\\}, bibtex_show=\\{true\\},")
  expect_true(file.exists(
    file.path(root, "assets", "img", "publication_preview", "JORS1.png")))
  expect_true(any(grepl("^nav_order: 2$",
                        readLines(file.path(root, "_pages", "publications.md")))))
})

test_that("publications = 'bib' falls back to html without _bibliography", {
  tmp <- withr::local_tempdir()
  hugo <- make_hugo_site(file.path(tmp, "hugo"))
  site <- file.path(tmp, "jekyll")
  report <- migrate_hugo(hugo, site, publications = "bib")
  expect_equal(report$bib, 0L)
  expect_true(file.exists(file.path(site, "publications.md")))
})

test_that("parse_toml_config reads sections, menus and comments", {
  cfg <- jekylldown:::parse_toml_config(c(
    'title = "T"  # comment',
    "[params]",
    '  author = "A B"',
    "[menu]",
    "  [[menu.main]]",
    '    name = "One"',
    '    url = "/one"',
    "    weight = 2",
    "  [[menu.main]]",
    '    name = "Two"',
    '    url = "/two"',
    "    weight = 1"
  ))
  expect_equal(cfg$title, "T")
  expect_equal(cfg$params$author, "A B")
  expect_length(cfg$menu$main, 2)
  expect_equal(cfg$menu$main[[1]]$name, "One")
  expect_equal(cfg$menu$main[[2]]$weight, "1")
})

test_that("convert_pandoc_attrs rewrites image attributes as kramdown IALs", {
  out <- jekylldown:::convert_pandoc_attrs(
    c("![](img/a.png){width=100%}",
      '![alt](b.png){width=50% height="10"}',
      "no attrs here ![](c.png)"))
  expect_equal(out[1], '![](img/a.png){: width="100%"}')
  expect_equal(out[2], '![alt](b.png){: width="50%" height="10"}')
  expect_equal(out[3], "no attrs here ![](c.png)")
})

test_that("parse_toml_simple handles common front matter", {
  meta <- jekylldown:::parse_toml_simple(c(
    'title = "Quoted # title"',
    "weight = 3",
    'tags = ["a", "b c"]',
    "draft = false",
    "[params]",
    'nested = "skip me"'
  ))
  expect_equal(meta$title, "Quoted # title")
  expect_equal(meta$tags, c("a", "b c"))
  expect_false(meta$draft)
  expect_null(meta$nested)
})

test_that("extract_socials finds profiles, e-mail and CV, ignores repos", {
  s <- jekylldown:::extract_socials(c(
    "[me](mailto:ada@example.com) [work](mailto:ada@work.example.com)",
    "[Resume](/files/resume.pdf) [slides](/files/talk.pdf)",
    "[GitHub](https://github.com/ada)",
    "[repo](https://github.com/ada/analytical-engine)",
    "[LinkedIn](https://www.linkedin.com/in/ada-lovelace/)",
    "[SO](https://stackoverflow.com/users/12345/ada)",
    "[RG](https://www.researchgate.net/profile/Ada_Lovelace)",
    "[Scholar](https://scholar.google.com/citations?user=aBc-12_3&hl=en)",
    "[ORCID](https://orcid.org/0000-0002-1825-0097)"
  ))
  expect_equal(s[["email"]], "ada@example.com")
  expect_equal(s[["cv_pdf"]], "/files/resume.pdf")
  expect_equal(s[["github_username"]], "ada")
  expect_equal(s[["linkedin_username"]], "ada-lovelace")
  expect_equal(s[["stackoverflow_id"]], "12345")
  expect_equal(s[["research_gate_profile"]], "Ada_Lovelace")
  expect_equal(s[["scholar_userid"]], "aBc-12_3")
  expect_equal(s[["orcid_id"]], "0000-0002-1825-0097")
})

test_that("migrate_socials replaces the theme's demo socials.yml", {
  tmp <- withr::local_tempdir()
  hugo <- make_hugo_site(file.path(tmp, "hugo"))
  root <- file.path(tmp, "site")
  fs::dir_create(file.path(root, "_data"))
  xfun::write_utf8(c("github_username: demouser", "scholar_userid: demoid"),
                   file.path(root, "_data", "socials.yml"))

  keys <- jekylldown:::migrate_socials(hugo, root)
  expect_true(all(c("email", "cv_pdf", "github_username",
                    "linkedin_username", "stackoverflow_id") %in% keys))

  lines <- xfun::read_utf8(file.path(root, "_data", "socials.yml"))
  expect_true('github_username: "ada"' %in% lines)
  expect_true('linkedin_username: "ada-lovelace"' %in% lines)
  expect_true('stackoverflow_id: "12345"' %in% lines)
  expect_true('email: "ada@example.com"' %in% lines)
  expect_true('cv_pdf: "/files/resume.pdf"' %in% lines)
  expect_false(any(grepl("demouser|demoid|analytical-engine", lines)))

  # a site without _data/socials.yml (minima) is left alone
  expect_identical(jekylldown:::migrate_socials(hugo, tmp), character())
})

test_that("migrate_hugo targets Minimal Mistakes (pages, nav, author)", {
  tmp <- withr::local_tempdir()
  hugo <- make_hugo_site(file.path(tmp, "hugo"))
  site <- file.path(tmp, "mm")
  expect_warning(
    migrate_hugo(hugo, site, theme = "minimal-mistakes",
                 theme_color = "red"),
    "set_theme_skin")

  # pages in _pages/, navigation.yml in menu order
  expect_true(file.exists(file.path(site, "_pages", "publications.md")))
  expect_true(file.exists(file.path(site, "_pages", "talks.md")))
  nav <- readLines(file.path(site, "_data", "navigation.yml"))
  expect_equal(nav[1], "main:")
  expect_true(any(grepl("url: /publications/", nav)))
  expect_true(grep("Main Publications", nav) < grep('"Talks"', nav))

  page <- readLines(file.path(site, "_pages", "publications.md"))
  expect_true("layout: single" %in% page)
  expect_true("permalink: /publications/" %in% page)

  # home -> index.md; avatar + socials -> the author block
  idx <- readLines(file.path(site, "index.md"))
  expect_true("layout: home" %in% idx)
  expect_true(any(grepl("I compute, therefore I am.", idx)))
  cfg <- readLines(file.path(site, "_config.yml"))
  expect_true("author:" %in% cfg)
  expect_true(any(grepl("avatar: /assets/img/me.jpg", cfg)))
  expect_true(any(grepl('name: "Ada L. Lovelace"', cfg)))
  expect_true(any(grepl("url: https://github.com/ada$", cfg)))
  expect_true(any(grepl("fa-github", cfg)))
  expect_true(any(grepl("url: mailto:ada@example.com", cfg)))
  # identity
  expect_true(any(grepl("^title: My Hugo blog", cfg)))
  expect_true(any(grepl("^url: https://example.com", cfg)))
})

test_that("chirpy migration pieces: tabs, home tab, config socials", {
  tmp <- withr::local_tempdir()
  hugo <- make_hugo_site(file.path(tmp, "hugo"))
  site <- file.path(tmp, "chirpy")
  fs::dir_create(file.path(site, "_tabs"))
  xfun::write_utf8(c(
    "theme: jekyll-theme-chirpy",
    "title: Chirpy",
    "github:",
    "  username: demouser",
    "twitter:",
    "  username: demouser",
    "social:",
    "  name: Demo Name",
    "  email: demo@example.org",
    "  links:",
    "    - https://x.com/demouser"
  ), file.path(site, "_config.yml"))
  xfun::write_utf8(c("---", "icon: fas fa-info-circle", "order: 4", "---"),
                   file.path(site, "_tabs", "about.md"))

  jekylldown:::migrate_page(
    file.path(hugo, "content", "publications.md"), site, "publications",
    "Pubs", "/publications/", 2)
  tab <- readLines(file.path(site, "_tabs", "publications.md"))
  expect_true("title: Main Publications" %in% tab)
  expect_true("order: 2" %in% tab)
  expect_true("permalink: /publications/" %in% tab)
  expect_true(any(grepl("^icon:", tab)))

  h <- jekylldown:::hugo_structure(hugo)
  jekylldown:::migrate_home(hugo, site, h)
  about <- readLines(file.path(site, "_tabs", "about.md"))
  expect_equal(about[1], "---")
  expect_true(any(grepl("icon: fas fa-info-circle", about)))
  expect_true(any(grepl("I compute, therefore I am.", about)))
  cfg <- readLines(file.path(site, "_config.yml"))
  expect_true(any(grepl("^avatar: /assets/img/me.jpg", cfg)))
  expect_true(file.exists(file.path(site, "assets", "img", "me.jpg")))

  keys <- jekylldown:::migrate_socials(hugo, site, hugo = h)
  expect_true("github_username" %in% keys)
  cfg <- readLines(file.path(site, "_config.yml"))
  expect_true(any(grepl("^  username: ada$", cfg)))       # github button
  expect_true(any(grepl("^  email: ada@example.com", cfg)))
  expect_true(any(grepl("- https://github.com/ada$", cfg)))
  expect_true(any(grepl("name: Ada L. Lovelace", cfg)))
  expect_false(any(grepl("demo@example.org", cfg)))       # social replaced
})

test_that("hugo_structure finds menus beyond menu.main", {
  tmp <- withr::local_tempdir()
  fs::dir_create(file.path(tmp, "content"))

  # Academic-style [[menu.header]]
  xfun::write_utf8(c(
    'title = "T"',
    "[[menu.header]]",
    '  name = "About"', '  url = "/about/"', "  weight = 1"
  ), file.path(tmp, "config.toml"))
  h <- jekylldown:::hugo_structure(tmp)
  expect_equal(h$menu[[1]]$url, "/about/")

  # sam-style [[params.mainMenu]] with link/text keys
  xfun::write_utf8(c(
    'title = "T"',
    "[[params.mainMenu]]",
    '  link = "/code"', '  text = "code"'
  ), file.path(tmp, "config.toml"))
  h <- jekylldown:::hugo_structure(tmp)
  expect_equal(h$menu[[1]]$url, "/code")
  expect_equal(h$menu[[1]]$name, "code")
})

test_that("date-named content directories are detected as posts", {
  tmp <- withr::local_tempdir()
  fs::dir_create(file.path(tmp, "content", "en"))
  xfun::write_utf8("baseURL = \"https://x.org/\"", file.path(tmp, "config.toml"))
  for (i in 1:6) {
    xfun::write_utf8(
      c("---", sprintf('title: "P%d"', i), "---", "hi"),
      file.path(tmp, "content", "en", sprintf("2020-01-0%d-p%d.md", i, i)))
  }
  site <- file.path(withr::local_tempdir(), "site")
  migrate_hugo(tmp, site, theme = "minima")
  expect_length(list.files(file.path(site, "_posts")), 6)
})

test_that("percent shortcodes, quoted args and blogdown/postref convert", {
  sc <- jekylldown:::convert_shortcodes(c(
    '{{% youtube "aBc123" %}}',
    '{{< youtube xYz789 >}}',
    '<img src="{{< blogdown/postref >}}index_files/figure-html/p.png" />'
  ))
  expect_true(all(grepl("youtube.com/embed", sc$body[1:2])))
  expect_equal(sc$body[3], '<img src="index_files/figure-html/p.png" />')
  expect_length(sc$remaining, 0)
})

test_that("escape_liquid protects Liquid from literal braces", {
  out <- jekylldown:::escape_liquid(c(
    "$$X = {{\\sqrt Y}}$$",
    "use {% if %} in Liquid",
    "![]({{ site.baseurl }}/assets/img/posts/p/f.png)"
  ))
  expect_equal(out[1],
    "$$X = {% raw %}{{{% endraw %}\\sqrt Y}}$$")
  expect_equal(out[2], "use {% raw %}{%{% endraw %} if %} in Liquid")
  expect_equal(out[3], "![]({{ site.baseurl }}/assets/img/posts/p/f.png)")
})

test_that("rerender = FALSE migrates committed rendered output", {
  tmp <- withr::local_tempdir()
  fs::dir_create(file.path(tmp, "content", "post"))
  xfun::write_utf8("baseURL = \"https://x.org/\"", file.path(tmp, "config.toml"))
  src <- c("---", 'title: "R post"', "date: 2021-01-15", "---", "",
           "The answer is `r 40 + 2`.")
  out <- c("---", 'title: "R post"', "date: 2021-01-15", "---", "",
           "The answer is 42.")
  xfun::write_utf8(src, file.path(tmp, "content/post/2021-01-15-x.Rmarkdown"))
  xfun::write_utf8(out, file.path(tmp, "content/post/2021-01-15-x.markdown"))

  site <- file.path(withr::local_tempdir(), "site")
  migrate_hugo(tmp, site, theme = "minima", rerender = FALSE)
  expect_length(list.files(file.path(site, "_source")), 0)
  post <- list.files(file.path(site, "_posts"), full.names = TRUE)
  expect_length(post, 1)
  expect_true(any(grepl("The answer is 42.", readLines(post), fixed = TRUE)))
})

test_that("Minimal Mistakes scaffold includes _pages in the build", {
  dir <- file.path(withr::local_tempdir(), "mm")
  new_site(dir, theme = "minimal-mistakes", sample = FALSE)
  cfg <- readLines(file.path(dir, "_config.yml"))
  expect_true("include:" %in% cfg)
  expect_true("  - _pages" %in% cfg)
})

test_that("publications become formatted citations on non-scholar themes", {
  withr::local_options(jekylldown.citation_fetcher = function(doi) {
    if (doi == "10.9999/broken") return(NULL)
    sprintf("Author, A. (2020). A fine paper about %s. Journal, 1(2).", doi)
  })
  tmp <- withr::local_tempdir()
  fs::dir_create(file.path(tmp, "content"))
  xfun::write_utf8(c(
    'baseURL = "https://x.org/"',
    "[[menu.main]]",
    '  name = "Publications"', '  url = "/publications"', "  weight = 1"
  ), file.path(tmp, "config.toml"))
  xfun::write_utf8(c(
    "---", 'title: "Pubs"', "---", "",
    '<div style="display:flex;"><span>One. doi.org/10.1234/abc</span></div>',
    "Two. https://doi.org/10.9999/broken"
  ), file.path(tmp, "content", "publications.md"))

  site <- file.path(withr::local_tempdir(), "site")
  report <- migrate_hugo(tmp, site, theme = "minima")

  expect_equal(report$bib, 1L)
  expect_identical(report$bib_kind, "citations")
  page <- readLines(file.path(site, "publications.md"))
  expect_true(any(grepl("A fine paper about 10.1234/abc", page)))
  expect_true(any(grepl("[doi.org/10.1234/abc](https://doi.org/10.1234/abc)",
                        page, fixed = TRUE)))
  expect_false(any(grepl("display:flex", page)))     # raw HTML gone
  expect_true(any(grepl("^title: Pubs", page)))      # front matter carried
  expect_true(any(grepl("unfetchable DOI.*10.9999/broken", report$manual)))
})

test_that("dot-relative paths in plain posts are rooted", {
  tmp <- withr::local_tempdir()
  fs::dir_create(file.path(tmp, "content", "post"))
  xfun::write_utf8("baseURL = \"https://x.org/\"", file.path(tmp, "config.toml"))
  xfun::write_utf8(c(
    "---", 'title: "P"', "date: 2020-01-01", "---", "",
    "<img alt='x' src='./img/logo.png' />",
    "![y](./img/other.png)"
  ), file.path(tmp, "content", "post", "2020-01-01-p.md"))
  site <- file.path(withr::local_tempdir(), "site")
  migrate_hugo(tmp, site, theme = "minima")
  md <- readLines(file.path(site, "_posts", "2020-01-01-p.md"))
  expect_true(any(grepl("src='/img/logo.png'", md, fixed = TRUE)))
  expect_true(any(grepl("![y](/img/other.png)", md, fixed = TRUE)))
})
