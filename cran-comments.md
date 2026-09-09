## New submission

jekylldown 0.3.4 is a first submission.

## Test environments

* local: Ubuntu 22.04.5 LTS, R version 4.4.1 (2024-06-14)
* GitHub Actions: ubuntu-latest (R release) and windows-latest (R release),
  R CMD check, plus a Windows end-to-end run that installs Ruby and
  builds two sites
* win-builder: R-devel (R Under development 2026-09-08 r90509, Windows
  Server 2022): 1 note, the new-submission one

## R CMD check results

0 errors | 0 warnings | 1 note

* This is a new submission.
* win-builder (R-devel, 2026-09-08 r90509) also lists "possibly
  misspelled words" in DESCRIPTION: declaratively, natively and
  toolchain. All three are ordinary English words used as intended.

## Notes for the reviewer

* The package drives Jekyll, a Ruby program, through its command line.
  Ruby, bundler and jekyll are listed in SystemRequirements and are
  not needed to install the package, run the tests or run the
  examples. Everything that needs them (build_site() with a local
  Jekyll, serve_site(), bundle_install(), install_ruby(), the
  theme-gem based styling helpers) is wrapped in \dontrun{} and skips
  in the tests when the toolchain is absent.
* The other examples run, in a site scaffolded under tempfile() with
  the locally generated minima theme, without network access, and
  remove the site afterwards.
* install_ruby(), install_git() and install_quarto() download tools
  into tools::R_user_dir("jekylldown", "data") only when the user
  calls them. Nothing is written outside tempdir() at install, test or
  example time.
