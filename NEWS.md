# jekylldown 0.2.1

* `new_site()` no longer requires git for the GitHub-hosted themes
  (al-folio and the Chirpy starter): when git is missing -- common on
  Windows -- the template is downloaded as a plain archive of the
  default branch instead, and a failed clone falls back to the same
  download.
* Documentation refreshed for Windows: a CI badge in the README, the
  Windows setup section notes that neither git nor admin rights are
  needed to scaffold and build, and the "cloned with git" wording is
  gone from `?new_site` and the vignettes.

# jekylldown 0.2.0

* `serve_site()` works on Windows: the build command was assembled as a
  shell string with a POSIX-only `VAR=value` environment prefix and a
  `/dev/null`-style redirect, which Windows cannot run ("
  'JEKYLL_NO_BUNDLER_REQUIRE=true' not found"). Rebuilds now go through
  processx with the environment passed properly, the output silenced
  without a shell redirect, and `.bat`/`.cmd` wrappers routed through
  `cmd.exe` -- on every platform.
* The Windows CI smoke test now also starts (and stops) a background
  `serve_site()`, so the serving path is exercised on a real Windows
  from here on.

# jekylldown 0.1.19

* Re-running `install_ruby()` is now cheap: a working provisioned Ruby
  is reused (no re-download; `force = TRUE` starts over) and
  already-installed gems are skipped (`gem install --conservative`), so
  the function doubles as "complete whatever is missing".
* `install_ruby()` also installs the minima gem: the second Windows CI
  run got all the way through Ruby, MSYS2 and Jekyll, then failed
  building the scaffolded default site because the theme gem was
  missing. The README's Linux/macOS `gem install` one-liners gained
  minima too -- a fresh toolchain set up from those instructions had
  the same gap on every platform.

# jekylldown 0.1.18

* When `api.github.com` is unreachable, the latest release is now
  discovered from the `releases/latest` page on `github.com` itself
  (the same host the archive downloads from) before resorting to the
  pinned fallback, and the DNS warning noise is suppressed.
* First real-Windows CI run, three fixes fed back from it:
  `install_ruby()` now sets up the MSYS2 build tools by default
  (`devkit = TRUE`) -- Jekyll depends on the eventmachine gem, which
  has no precompiled binary for current Rubies and failed to compile
  without a proper toolchain; two test expectations compare normalized
  paths (Windows mixes separators and 8.3 short names); the tilde
  expansion test is skipped on Windows, where `R_USER` is fixed at
  startup and the fixture's `HOME` override cannot take effect.

# jekylldown 0.1.17

* `install_ruby()` no longer depends on `api.github.com` being
  reachable: when the release lookup fails (that host is blocked on
  some networks even where `github.com` works), a known-good pinned
  RubyInstaller release is downloaded directly from `github.com`, with
  a new `version` argument to pick a specific release; download
  failures now explain the proxy/offline escape hatches.
* `devkit = TRUE` fixed before it ever worked: upstream publishes no
  portable `.7z` of the devkit variant, so the MSYS2 toolchain is now
  added by running RubyInstaller's own `ridk install` after unpacking.
* New GitHub Actions workflow: R CMD check on Linux and Windows, plus a
  Windows end-to-end smoke test that runs `install_ruby()`, scaffolds a
  site and builds it.

# jekylldown 0.1.16

* Windows support for the isolated toolchain: new `install_ruby()`
  downloads the portable RubyInstaller archive (a `.7z`; needs the
  `archive` package to unpack) into
  `tools::R_user_dir("jekylldown", "data")` and installs the jekyll and
  bundler gems there -- no admin rights, no graphical installer,
  nothing system-wide. `install_ruby(devkit = TRUE)` adds the MSYS2
  build tools for gems that compile C extensions.
* Windows plumbing to match: executable discovery now finds the
  `.bat`/`.cmd`/`.exe` wrappers Ruby uses there, those wrappers are run
  through `cmd.exe /c` (processx cannot exec batch files directly), the
  quiet serve rebuild redirects to `NUL` instead of `/dev/null`, and
  `check()`'s advice for a missing Ruby points at `install_ruby()` on
  Windows.

# jekylldown 0.1.15

* `set_element_style("socials", size = ...)` now actually resizes the
  icons. The mapped selectors were losing to the themes' own,
  more specific rules (al-folio nests `.contact-icons` under `.social`;
  Chirpy nests `.sidebar-bottom` under `#sidebar`) -- the maps now
  match the themes' specificity. On top of the `font-size`, the sizing
  writes companion rules for what a font size cannot reach: al-folio's
  image icons, minima's fixed 16px SVG icons, and Chirpy's fixed-size
  circular buttons all track the requested size now.

# jekylldown 0.1.14

* Breaking change (ergonomics): the customization functions now take
  what you are setting as the *first* argument and the site as the
  *last* -- so calls like `set_element_style("socials", size = "3rem")`
  and `set_theme_color("red")` work directly from inside the site's
  project. New signatures:
  `set_theme_color(color, dir = ".")`,
  `set_theme_style(..., dir = ".")`,
  `set_theme_skin(skin, dir = ".")`,
  `set_theme_font(family, size, headings, code, google, dir = ".")`,
  `set_element_style(element, ..., dir = ".")`,
  `add_css(css, id, dir = ".")`.
  From outside a site, pass the location by name:
  `set_theme_color("red", dir = "my-site")`.
* Calls in the old style (site path first) do not fail obscurely: when
  the first argument is an existing site directory, the functions abort
  with a message pointing at the `dir` argument.

# jekylldown 0.1.13

* Undo for the accent color: `set_theme_color(dir, NULL)` removes the
  override and returns to the theme default. Deleting the site-local
  stylesheet (`assets/css/main.scss`) remains the documented way to
  drop every customization at once.
* New `"socials"` element in `set_element_style()`'s per-theme maps
  (al-folio's about-page icon row, Chirpy's sidebar icons, Minimal
  Mistakes' author links, minima's footer icons) -- e.g.
  `set_element_style(site, "socials", size = "2rem")`.
* Calling any of these (or `build_site()`) from outside a site now
  aborts with a message that tells you to pass the site's path via
  `dir`, instead of a bare "no _config.yml" error.
* All customization functions (`set_theme_color()`, `set_theme_style()`,
  `set_theme_skin()`, `set_theme_font()`, `set_element_style()`,
  `add_css()`, `add_mathjax()`) now find the site root from any
  subdirectory, exactly like `build_site()` -- running them from inside
  the site's RStudio project just works with the default `dir = "."`.

# jekylldown 0.1.12

* The blank-Viewer race, actually fixed: waiting for a TCP connection
  was not enough (the kernel accepts connections before the app answers
  anything). `serve_site()` now waits for a real HTTP response -- which
  also warms the server up before the Viewer's own request -- plus a
  short settle before opening the preview.
* Calling `serve_site()` again for a site that is already being served
  now reuses the running server and just reopens the preview, instead
  of silently piling up background workers (the pid file records the
  port too).

# jekylldown 0.1.11

* Fixed the blank RStudio Viewer on `serve_site()`: the preview was
  opened while the background worker was still doing the initial build,
  before anything listened on the port (the Viewer does not retry).
  `serve_site()` now waits for the server to answer before opening the
  preview -- and if the worker dies during the initial build, the last
  log lines are surfaced as the error instead of a silent blank page.
* `serve_site()` itself now keeps `.jekylldown-serve.*` (its log and
  pid files) in the site's `.gitignore` -- covering sites created by
  older versions or not created by jekylldown at all; users never need
  to know the line exists.

# jekylldown 0.1.10

* `serve_site()` opens the preview in RStudio's Viewer pane again when
  running inside RStudio (background mode was sending it to the system
  browser); elsewhere the default browser keeps being used.
* `new_site()` adds `.jekylldown-serve.*` (the background server's log
  and pid files) to the site's `.gitignore` on every theme.

# jekylldown 0.1.9

* Fixed a critical `serve_site()` bug: since the `servr::httw()`
  rewrite, source edits never triggered a rebuild -- servr evaluates
  its file watcher lazily from inside the served `_site/` directory, so
  the watcher was silently watching the wrong tree. The watch path is
  now absolute, and the live loop truly works: save a watched file with
  the preview tab open and the site re-knits, rebuilds and reloads.
* `serve_site()` now runs in a separate background R process by default
  (`background = TRUE` in interactive sessions): the console stays
  free, nothing spams it, and rebuild output goes to
  `.jekylldown-serve.log` in the site (one status line per rebuild
  instead of the full jekyll echo). `stop_server("site")` stops it via
  the recorded PID. `background = FALSE` keeps the old in-session
  daemon.
* `knit_all()` gained `quiet =`, used by the serve loop to silence the
  per-poll "all posts up to date" chatter.

# jekylldown 0.1.8

* The migration gallery's before/after comparisons are side-by-side
  again, composed at a fixed 680px so the two halves split the
  vignette's text width exactly and can never overflow it (plus a CSS
  guard in the vignette itself).
* Visual audit of the migrated software, talks and contact pages across
  Chirpy, Minimal Mistakes and minima: all render correctly (package
  logos at their ported size, floated where the theme allows).

# jekylldown 0.1.7

* Fixed, for real this time: Markdown tables written GitHub-style --
  without the leading pipe (`Topic|Length` over `----|----`) and/or
  glued to the previous paragraph with no blank line -- were not
  recognized by kramdown on any theme, and rendered as prose full of
  pipe characters. `tag_tables()` (applied both when knitting and when
  migrating) now normalizes them: leading pipes added, a blank line
  inserted before the table, and the `{: .table}` styling tag applied.
  Fenced code and `{% highlight %}` blocks remain untouched.

# jekylldown 0.1.6

Theme-parity pass: everything that worked on al-folio now works on the
other three themes.

* Fixed: posts on Minimal Mistakes rendered with no layout at all (the
  theme has no `post` layout -- it uses `single`), which looked like
  "nothing renders", tables included. The scaffold now ships a
  `_layouts/post.html` alias, so every jekylldown post works unchanged.
* Fixed: figure classes ported from the Hugo theme had no effect on
  Chirpy -- its content pipeline moves the image's class onto a
  wrapping `<a>`, so `img.pkg` matched nothing and logos rendered
  full-size. Ported rules now target both shapes
  (`img.pkg, .pkg img`).
* Fixed: `./`-relative paths in plain posts (e.g.
  `<img src='./img/logo.png'>`, which Hugo's `relativeURLs` used to
  paper over) resolved against the post URL and 404'd; they are now
  rooted to the site during migration.
* Audited the rest: tables, socials, avatar, identity, publications,
  MathJax, styling layers and deploy workflows behave equivalently on
  all four themes; the intentional differences that remain are minima's
  lack of a CSS-variable layer (documented) and jekyll-scholar being
  al-folio-only (other themes get the formatted-citation page).

# jekylldown 0.1.5

* Fixed: on a site with a `Gemfile` but no `Gemfile.lock` (that is,
  before `bundle_install()`), `build_site()` and `serve_site()` crashed
  -- Jekyll insisted on `Bundler.setup` and died on any version skew
  (`You have already activated bigdecimal ...`). Plain-jekyll runs now
  set `JEKYLL_NO_BUNDLER_REQUIRE`, Jekyll's own escape hatch; once a
  lockfile exists, `bundle exec` takes over as before.
* `publications = "bib"` now produces a decent page on every theme: on
  al-folio it keeps feeding jekyll-scholar, and on themes without it
  (minima, Chirpy, Minimal Mistakes) the page is rebuilt as a clean
  Markdown list of formatted citations (APA, fetched from doi.org --
  the same authoritative source), each ending in a single DOI link.
  Raw-HTML publication pages, which kramdown mangles, are no longer
  the fallback when the DOIs are fetchable.

# jekylldown 0.1.4

* The getting-started vignette shows what the first build of each
  scaffold looks like (minima, al-folio, Chirpy), screenshots taken
  from freshly generated sites.
* `new_site(theme = "al-folio")` now sets `baseurl: ""` (the template
  ships its own `/al-folio`, which 404'd every asset on a fresh site
  served at the root — the first build looked completely unstyled),
  and the scrub comments out the placeholder profile picture (Einstein)
  so an empty site starts with no photo; `migrate_hugo()` re-enables
  the line when it finds a real avatar.

# jekylldown 0.1.3

* The getting-started vignette maps the home page per theme: where the
  welcome text lives, where your name and photo come from, and which
  file controls the social icons shown (al-folio `_data/socials.yml`,
  Chirpy `_data/contact.yml` + config usernames, Minimal Mistakes
  `author.links`, minima footer keys).

# jekylldown 0.1.2

* New "Edit the site afterwards" section in the getting-started
  vignette: the source-vs-artifact rule for posts, a per-theme map of
  where pages and their menu positions live, where identity/socials/
  publications data go, the live-edit loop (including why
  `_config.yml` changes apply without a server restart under
  `serve_site()`), and the pages-are-not-Rmd limitation. The README's
  file map gained the pages row and points there.

# jekylldown 0.1.1

* New `use_pages_workflow()`: writes the standard GitHub Actions
  workflow that builds and deploys the site to GitHub Pages (checkout,
  cached Ruby/bundle, `jekyll build`, deploy) for themes that do not
  ship one (minima, Minimal Mistakes, ...); sites whose theme already
  includes a deploy workflow (al-folio, Chirpy) are left alone.
* New "Publishing" section in the README: the three GitHub Pages routes
  (Actions, classic branch build and its plugin limits, local build +
  `gh-pages`), plus Netlify/Cloudflare Pages, GitLab Pages and plain
  static hosting — `_site/` is static files, any host works.

# jekylldown 0.1.0

First minor release: four themes with scaffolding, styling, migration
and a real-world gallery — the package is feature-complete for its
anchor use cases.

* New `add_mathjax()`: enables LaTeX math the way each theme expects
  (al-folio's native flag, Chirpy's per-page `math` default, Minimal
  Mistakes' `head_scripts`, or a configured MathJax script inserted
  into a site-local head include on minima), with inline `$...$` and
  display `$$...$$` both rendering. Demonstrated in the gallery on a
  2007 post.
* The migration gallery closes the loop with a "make it yours"
  section: the customization layers applied to the gallery sites, with
  results shown — Chirpy CSS variables plus the author portrait
  recovered from the Hugo source, a Minimal Mistakes skin with an
  inlined Google Font, and al-folio fonts/background/managed CSS.
* All before/after comparisons are now stacked and labeled (original
  on top, migrated below), sized to the vignette page.

# jekylldown 0.0.9

* New vignette, "Migration gallery": four real published blogdown sites
  — yihui.org (Yihui Xie, 1884 posts), juliasilge.com (Julia Silge),
  jennybryan.org (Jenny Bryan) and allanvc.github.io — migrated from
  their public sources to the four supported themes, with before/after
  screenshots of more than one page per site.
* The gallery hardened `migrate_hugo()` against the real world:
  * menus are also found in `[[menu.header]]`, `[[menu.nav]]` and
    theme-specific `[[params.mainMenu]]` lists (`link`/`text` keys);
  * content directories dominated by date-named files (multilingual
    `content/en/`, custom section names) are detected as post sections;
  * shortcodes in the `{{% %}}` form and with quoted arguments convert
    like their `{{< >}}` cousins, and blogdown's
    `{{< blogdown/postref >}}` wrappers are resolved away;
  * literal `{{`/`{%` in migrated content (LaTeX math, template
    snippets) are Liquid-escaped — previously a single such post
    aborted the entire Jekyll build;
  * new `rerender` argument: `rerender = FALSE` migrates the rendered
    Markdown blogdown committed next to each R source instead of
    queueing years of old posts for re-knitting — the right mode for
    archival migrations.
* Fixed: gem-based Minimal Mistakes sites now include `_pages` in the
  Jekyll build — without it every migrated page 404'd.

# jekylldown 0.0.8

* The package `Title` now says what has been true since 0.0.3: sites are
  written from 'R Markdown' *and* 'Quarto'.
* Documentation synchronized with everything shipped since the first
  prototype: the README gained a "Customizing the theme" section (the
  four styling layers plus Minimal Mistakes skins), the Quarto CLI
  install, the three post flavors and the multi-theme migration scope;
  the getting-started vignette now covers deployment for all four
  themes; the migration vignette points out that every supported theme
  is a `migrate_hugo()` target (with al-folio as its worked example);
  and the package `Description` mentions the four themes and the
  declarative customization.
* Removed a stale claim: `build.R` is no longer described as the hook
  behind `serve_site()` (it has not been since the `servr::httw()`
  rewrite); the generated file documents itself as a compatibility hook
  for users driving `servr::jekyll()` directly.

# jekylldown 0.0.7

* First-class support for the most popular Jekyll themes, joining
  al-folio and minima:
  `new_site(theme = "chirpy")` clones the Chirpy starter (stripped of
  the upstream repo tooling, Pages deploy workflow kept, and the theme
  gem un-pinned so bundler can pick a release the local Ruby runs);
  `new_site(theme = "minimal-mistakes")` generates a gem-based Minimal
  Mistakes site locally. The knit/serve pipeline, the styled tables and
  the customization layers know all four themes: `set_theme_style()`
  speaks Chirpy's CSS variables, the new `set_theme_skin()` switches
  Minimal Mistakes' compiled skins, `set_element_style()` carries
  per-theme selector maps, and `set_theme_color()` delegates sensibly.
* `migrate_hugo()` targets the new themes too: menu pages become
  Chirpy `_tabs/` entries (icon + `order`) or Minimal Mistakes
  `_pages/` plus `_data/navigation.yml`; the Hugo home lands in
  Chirpy's about tab or above the Minimal Mistakes post list; the
  avatar becomes Chirpy's `avatar:` or Minimal Mistakes'
  `author.avatar`; social profiles are written to Chirpy's `social:`
  config block (plus its github/twitter buttons) or Minimal Mistakes'
  `author:` sidebar links, with URLs rebuilt deterministically from the
  extracted usernames. `publications = "bib"` falls back to `"html"`
  on themes without `_bibliography/`.

# jekylldown 0.0.6

* Declarative theme customization, in four layers of decreasing
  robustness, all written as managed idempotent blocks in the site-local
  stylesheet: `set_theme_style()` overrides al-folio's own CSS variables
  (background, text, dividers, code/card/footer colors, ...) with
  light/dark-aware values; `set_theme_font()` sets font families (Google
  Fonts faces are fetched and inlined as `@font-face`, valid anywhere in
  a stylesheet, unlike `@import`) and the base size; `set_element_style()`
  styles one semantic element (`"navbar"`, `"footer"`, `"headings"`, ...)
  through a curated selector map — documented as the fragile layer, with
  a warning when the installed theme no longer contains a mapped
  selector; `add_css()` is the escape hatch: free-form CSS in a managed,
  removable block.

# jekylldown 0.0.5

* Every exported function now has runnable examples and a documented
  return value.
* New "Getting started with jekylldown" vignette covering the full
  workflow: toolchain check, site creation, the three post flavors,
  build/preview, customization and GitHub Pages deployment.

# jekylldown 0.0.4

* `.Rmd` posts can opt into a pandoc pipeline with `knit_method: pandoc`
  in the front matter (or site-wide with
  `options(jekylldown.knit_method = "pandoc")`): the post is rendered
  through rmarkdown's `md_document(variant = "gfm")`, which enables the
  pandoc-only features — citations (`bibliography:`), footnotes,
  cross-references — while figures and front matter get the same
  treatment as every other post. The default remains plain knitr (fast,
  no pandoc needed).
* `serve_site()` was rebuilt on `servr::httw()`: it now watches the whole
  source tree (`.Rmd`, `.qmd`, Markdown pages, `_config.yml`, data
  files, styles) and re-knits/re-renders whatever is outdated before
  rebuilding — Quarto posts included. Previously only `.Rmd` changes
  triggered a rebuild.
* `install_quarto()` downloads the Quarto CLI into jekylldown's isolated
  toolchain directory (`tools::R_user_dir("jekylldown", "data")/quarto`),
  where the package finds it automatically — nothing system-wide, no
  shell configuration, delete the directory to uninstall. `check()`
  reports the Quarto found (toolchain, `PATH`, or the `quarto` package's
  discovery).

# jekylldown 0.0.3

* Quarto support: `_source/*.qmd` posts are rendered by `build_site()`
  through the Quarto CLI (`quarto render --to gfm`) and adapted to the
  same conventions as `.Rmd` posts: source front matter carried over
  (minus Quarto-only keys), pandoc's repeated title/date heading
  stripped, figures moved to `assets/img/posts/<post>/` behind
  `{{ site.baseurl }}`. `new_post()` gained
  `format = c("Rmd", "qmd", "md")`.
* Markdown pipe tables (hand-written or from `knitr::kable()`) are
  tagged with a `{: .table}` kramdown IAL when knitting and when
  migrating, so al-folio styles them (a bare `<table>` gets almost no
  styling from the theme); code blocks are left untouched.

# jekylldown 0.0.2

* `migrate_hugo()` fills al-folio's `_data/socials.yml` from the
  Hugo pages: profile URLs (GitHub, LinkedIn, ORCID, Google Scholar,
  ResearchGate, StackOverflow, X, and friends), the first `mailto:`
  address, and a CV/resume PDF link. Only profile-shaped URLs on
  non-post pages count, so repository links and profiles mentioned in
  posts are not mistaken for the site owner's.
* `publications = "bib"` is now the default in `migrate_hugo()` (it
  falls back to `"html"` automatically without `_bibliography/`, DOIs
  or network), after a real-world migration with the old `"html"`
  default produced a broken publications page.
* The al-folio scrub goes deeper: the theme's own top-level dev docs
  are deleted together with their `exclude` entries, the upstream repo
  tooling is dropped (hidden files and directories except `.gitignore`,
  the `docs/` tree, demo data files, and all of `.github` except the
  Pages deploy workflow), and the `jekyll-jupyter-notebook` plugin is
  removed (the demo posts were its only content, and without
  `jupyter`/`nbconvert` on the PATH it aborts every local build).

# jekylldown 0.0.1

First prototype. Do for Jekyll what blogdown does for Hugo:

* `new_site()` scaffolds a Jekyll site with the jekylldown conventions
  (`_source/*.Rmd` knitted to `_posts/*.md`), with the `minima` theme
  generated locally or `al-folio` cloned from GitHub.
* `new_post()` creates dated posts with Jekyll front matter.
* `build_site()` / `knit_post()` knit outdated posts (front matter
  preserved, kramdown/rouge fences, figures in `assets/img/posts/` via
  `{{ site.baseurl }}`) and run `jekyll build` when available.
* `serve_site()` / `stop_server()` wrap `servr::jekyll()` for live
  preview with automatic re-knitting.
* `bundle_install()` installs a theme's `Gemfile` dependencies into the
  isolated gem environment; sites with a `Gemfile.lock` are then built
  with `bundle exec jekyll` automatically.
* `migrate_hugo()` converts a Hugo/blogdown site guided by its config:
  post filenames, YAML and TOML front matter, page bundles, `figure`/
  `youtube` shortcodes, and Pandoc image attributes. The Hugo menu
  (`[[menu.main]]`) drives page migration (`content/<slug>.md` becomes a
  Jekyll page with the same URL and `nav_order`), `content/_index.md`
  becomes the landing page (with avatar-to-profile-picture conversion on
  al-folio), and the site identity (name, `url`, description,
  jekyll-scholar author names) is written into `_config.yml`.
  `only_referenced = TRUE` copies from `static/` only the files the
  migrated content actually references. `publications = "bib"` converts
  a hand-written publications page deterministically: the DOIs are
  extracted, each reference is fetched as authoritative BibTeX from
  doi.org (Crossref/DataCite content negotiation), preview images are
  paired with their DOIs, and `_bibliography/papers.bib` drives
  al-folio's jekyll-scholar page (badges and buttons included).
  `theme_color =` picks the al-folio accent color. `url`/`baseurl` are
  derived from the Hugo `baseURL` (empty `baseurl` for user pages). A
  report lists everything that needs manual porting.
* `{{< figure >}}` conversion keeps `class`/`width`/`height` as a
  kramdown inline attribute list, and the CSS rules behind those classes
  (which is where Hugo themes define figure display sizes) are ported
  from the Hugo theme's sass into the new site's stylesheet, with sass
  variables resolved and selectors rewritten for kramdown output — so
  images keep the size they had on the old site.
* `set_theme_color()` changes al-folio's accent color at any time: named
  palette colors (`"red"`, `"blue"`, ...) resolved from the theme's own
  variables, or any hex value; implemented as a CSS-variable override
  appended to a site-local copy of the theme's `main.scss`.
* `new_site(demo = FALSE)` (implied by `migrate_hugo()`) scrubs
  al-folio's demo content: sample posts, news, projects, books,
  teachings, the Einstein pages, the demo bibliography and the external
  demo blog feeds (`external_sources`).
* `check()` prints a situation report on the Ruby/Jekyll toolchain, with
  support for a fully isolated toolchain under
  `tools::R_user_dir("jekylldown", "data")`.
