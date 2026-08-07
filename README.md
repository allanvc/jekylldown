
<!-- README.md is generated from README.Rmd. Please edit that file. -->

# jekylldown

<!-- badges: start -->

[![R-CMD-check](https://github.com/allanvc/jekylldown/actions/workflows/R-CMD-check.yml/badge.svg)](https://github.com/allanvc/jekylldown/actions/workflows/R-CMD-check.yml)
<!-- badges: end -->

**jekylldown** does for [Jekyll](https://jekyllrb.com) what
[blogdown](https://pkgs.rstudio.com/blogdown/) does for Hugo: create,
build, serve, and maintain Jekyll websites from R, writing posts in R
Markdown or [Quarto](https://quarto.org). It unlocks the Jekyll theme
ecosystem for R users, with first-class support for the most popular
themes — the academic
[al-folio](https://github.com/alshedivat/al-folio),
[Chirpy](https://github.com/cotes2020/jekyll-theme-chirpy), [Minimal
Mistakes](https://github.com/mmistakes/minimal-mistakes) and minima —
and GitHub Pages builds Jekyll natively, so simple sites deploy with a
plain `git push`.

Posts live as `.Rmd` or `.qmd` files in `_source/` and are knitted (or
rendered by the Quarto CLI, for `.qmd`) to Markdown in `_posts/` (front
matter preserved, figures in `assets/img/posts/`, tables styled by the
theme), which Jekyll consumes natively. Jekyll itself is only ever
called through its command line — there is no R–Ruby bridge to break.

## Installation

jekylldown is not on CRAN yet. Install the development version with:

``` r
# install.packages("remotes")
remotes::install_github("allanvc/jekylldown")
```

## Getting Jekyll running

jekylldown needs Ruby (\>= 3.0) with the **jekyll** and **bundler**
gems. Run `jekylldown::check()` at any time for a diagnostic of what is
(and is not) installed — it looks both on your `PATH` and in
jekylldown’s own isolated toolchain directory
(`tools::R_user_dir("jekylldown", "data")`).

> **No Ruby? You can still publish.** Knitting `.Rmd` posts only needs
> R. If you deploy on GitHub Pages/Actions (al-folio and Chirpy ship the
> workflow), the Jekyll build happens remotely and a local Jekyll is
> only needed for `serve_site()` previews and local `build_site()`
> builds.

To write posts in Quarto (`.qmd`) you also need the Quarto CLI —
`install_quarto()` puts it in the same isolated toolchain directory, or
it is picked up from the `PATH`.

### Windows

One function call — no admin rights, no graphical installer, nothing on
the system `PATH`:

``` r
install.packages("archive")   # unpacks the portable Ruby archive
jekylldown::install_ruby()
```

It downloads the portable [RubyInstaller](https://rubyinstaller.org)
archive into jekylldown’s isolated toolchain directory, adds the MSYS2
build tools (Jekyll’s own dependencies need a compiler on Windows — a
large but one-time download) and installs the jekyll and bundler gems
there; deleting that one directory uninstalls everything. On networks
where the GitHub API is blocked, a known-good pinned release is fetched
directly from `github.com`; fully offline, download the `.7z` from
[rubyinstaller.org](https://rubyinstaller.org/downloads/) and pass it as
`file =`. git is not required either: the GitHub-hosted theme templates
(al-folio, Chirpy) fall back to a plain archive download when git is
absent. The one step that needs git — al-folio’s `bundle_install()`,
whose `Gemfile` pulls a gem from a git repository — is covered by
`install_git()`, which drops a portable MinGit into the same isolated
toolchain (for publishing with `git push` you will still want a regular
[git installation](https://git-scm.com/downloads)). The whole workflow —
`install_ruby()`, `new_site()`, `build_site()`, `serve_site()` — runs on
a Windows GitHub Actions runner on every push.

### Linux

With admin rights (Debian/Ubuntu shown):

``` sh
sudo apt install ruby-full build-essential
gem install --user-install jekyll bundler minima
```

Without admin rights, use the fully isolated toolchain (conda-forge Ruby
via micromamba, installed under jekylldown’s data directory — deleting
that one directory uninstalls everything):

``` sh
DATA=$(Rscript -e 'cat(tools::R_user_dir("jekylldown", "data"))')
mkdir -p "$DATA"
curl -Ls https://micro.mamba.pm/api/micromamba/linux-64/latest \
  | tar -xj -C "$DATA" bin/micromamba
"$DATA/bin/micromamba" create -y -p "$DATA/ruby" \
  -c conda-forge ruby c-compiler cxx-compiler make
PATH="$DATA/ruby/bin:$PATH" gem install --no-document jekyll bundler minima
```

jekylldown auto-detects a toolchain in that directory and injects
`GEM_HOME`/`PATH` on every call — no shell configuration needed.

### macOS

The system Ruby that ships with macOS is outdated; install a current one
with [Homebrew](https://brew.sh) (you also need the Xcode Command Line
Tools for gems with native extensions):

``` sh
xcode-select --install   # if not already installed
brew install ruby
echo 'export PATH="$(brew --prefix ruby)/bin:$PATH"' >> ~/.zshrc && exec zsh
gem install --user-install jekyll bundler minima
```

### Windows

Install [RubyInstaller **with
Devkit**](https://rubyinstaller.org/downloads/) (the Devkit brings the
MSYS2 toolchain that compiles native gems). Tick *“Add Ruby executables
to your PATH”* during setup and run the final `ridk install` step it
offers. Then, in a new terminal:

``` sh
gem install jekyll bundler minima
```

### Verify

``` r
jekylldown::check()
```

## Minimal example

``` r
library(jekylldown)

new_site("mysite")                        # scaffold a Jekyll site
new_post("My first post", dir = "mysite") # creates _source/YYYY-MM-DD-my-first-post.Rmd
build_site("mysite")                      # knit .Rmd -> .md, then `jekyll build`
serve_site("mysite")                      # live preview with rebuild on save
stop_server()
```

`new_site()` also scaffolds `theme = "al-folio"`, `"chirpy"` or
`"minimal-mistakes"`. Posts come in three flavors: R Markdown via plain
knitr (default), R Markdown via pandoc (`knit_method: pandoc` in the
front matter — enables citations, footnotes, cross-references), and
Quarto (`new_post(format = "qmd")`).

For a theme with its own `Gemfile` (like al-folio), install its gems
once with `bundle_install("mysite")`; `build_site()`/`serve_site()` then
switch to `bundle exec jekyll` automatically.

## Customizing the theme

Declarative, idempotent, dark-mode aware — no hand-written CSS in theme
files. Four layers, most robust first:

``` r
# run from anywhere inside the site's project (they find the site root
# like build_site()); from outside, add dir = "mysite"

# 1. the theme's own CSS variables (al-folio and Chirpy)
set_theme_style(accent = "red",
                background = c(light = "#fffdf7", dark = "#1c1c1d"))

# Minimal Mistakes styles through compiled skins instead:
set_theme_skin("dark")

# 2. fonts (Google Fonts inlined) and base size
set_theme_font("Lora", size = "17px")

# 3. one semantic element at a time (the fragile layer -- see its docs)
set_element_style("navbar", background = "#222", color = "white")
set_element_style("socials", size = "2rem")   # social icon row

# 4. escape hatch: free-form CSS in a managed, removable block
add_css(".profile img { border-radius: 50%; }", id = "avatar")
```

To undo the accent, call `set_theme_color(NULL)`; deleting the
site-local stylesheet (`assets/css/main.scss`) drops every customization
at once.

## Migrating from blogdown/Hugo

``` r
migrate_hugo("path/to/hugo-site", "my-jekyll-site", theme = "al-folio")
```

`migrate_hugo()` converts posts (front matter, filenames, bundles,
static assets, common shortcodes), pages from the Hugo menu, the site
identity, social profiles and — with `publications = "bib"` (the default
on al-folio) — a publications page rebuilt from its DOIs, then reports
everything that needs manual attention. All four themes are migration
targets; each gets the pages, navigation, avatar and socials in its own
convention. See the vignette: `vignette("migrate-blogdown-to-al-folio",
package = "jekylldown")`.

## Publishing

`build_site()` leaves a plain static site in `_site/` — so ultimately
*any* static host works. The knitting always happens locally (commit
`_source/` **and** the generated `_posts/*.md`); what varies is who runs
`jekyll build`.

**GitHub Pages** (the natural home — free, and Jekyll-native):

1.  Push the site to a repository — `youruser.github.io` for a user
    site, any name for a project site.
2.  Get a build workflow. al-folio and Chirpy already ship one; for
    minima, Minimal Mistakes and other themes, add the standard one:

<!-- end list -->

``` r
use_pages_workflow("mysite")   # writes .github/workflows/jekyll.yml
```

3.  In the repository settings, set **Pages \> Source: GitHub Actions**
    (once). Every push then builds and publishes. Commit the
    `Gemfile.lock` from `bundle_install()` — the workflow caches gems
    from it.

Two alternatives on GitHub: the classic branch build (Settings \> Pages
\> Deploy from a branch) runs Jekyll for you but only with GitHub’s
whitelisted plugin set — fine for minima, not for al-folio/Chirpy; or
build locally and push the `_site/` contents to a `gh-pages` branch if
you want no remote build at all.

**Netlify / Cloudflare Pages**: connect the repository and set the build
command to `bundle exec jekyll build` with publish directory `_site`
(both detect Jekyll and suggest exactly this).

**GitLab Pages**: a minimal `.gitlab-ci.yml` that runs `bundle exec
jekyll build -d public` in a Ruby image and publishes the `public`
artifact.

**Your own server / anything else**: `build_site()` and copy `_site/`
over (`rsync -av _site/ server:/var/www/site/`). Static files, no
runtime.

## How it works

| Where                            | What                                                                                                               |
| -------------------------------- | ------------------------------------------------------------------------------------------------------------------ |
| `_source/*.Rmd`, `*.qmd`         | posts in R Markdown/Quarto (the source; excluded from Jekyll)                                                      |
| `_posts/*.md`                    | knitted output — an artifact, never edit by hand (unless the post has no `_source/` twin: then it *is* the source) |
| `_pages/`, `_tabs/`, or the root | pages, in the active theme’s convention — edit directly; front matter controls the menu                            |
| `assets/img/posts/<post>/`       | figures generated by your chunks                                                                                   |
| `assets/.../main.scss`           | site-local stylesheet holding the managed customization blocks                                                     |

Editing after creation or migration is covered in the getting-started
vignette (`vignette("jekylldown")`, section 5): where each theme keeps
pages, identity and data files, and why `_config.yml` edits apply live
under `serve_site()`.

Prior art: this package packages up the workflow of Yihui Xie’s
[`servr::jekyll()`](https://rdrr.io/cran/servr/man/jekyll.html) and
[knitr-jekyll](https://github.com/yihui/knitr-jekyll), with the API
mirroring blogdown on purpose. blogdown itself supports Jekyll only in a
limited way — essentially the serve-and-reknit loop, with everything
else (site scaffolding, themes, toolchain, migration) designed for Hugo;
jekylldown picks up where that support stops.
