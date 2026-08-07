test_that("RubyInstaller URLs are resolved correctly", {
  base <- "https://github.com/oneclick/rubyinstaller2/releases/download"
  json <- sprintf(
    '"browser_download_url": "%s/RubyInstaller-3.3.7-1/%s",',
    base,
    c("rubyinstaller-devkit-3.3.7-1-x64.exe",
      "rubyinstaller-3.3.7-1-x64.7z",
      "rubyinstaller-3.3.7-1-x64.exe"))
  json <- paste(json, collapse = "\n")

  # the plain .7z, never the .exe installers
  expect_match(ri_pick_asset(json), "/rubyinstaller-3\\.3\\.7-1-x64\\.7z$")
  expect_error(ri_pick_asset('{"assets": []}'), "rubyinstaller.org")

  # the pinned fallback for when api.github.com is unreachable
  expect_equal(
    ri_pinned_url("3.3.7-1"),
    paste0(base, "/RubyInstaller-3.3.7-1/rubyinstaller-3.3.7-1-x64.7z"))

  # the version parsed out of the releases/latest page on github.com
  html <- '<a href="/oneclick/rubyinstaller2/releases/tag/RubyInstaller-4.0.6-1">'
  expect_equal(ri_tag_version(html), "4.0.6-1")
  expect_length(ri_tag_version("<html>nothing here</html>"), 0)
})

test_that("shell_cmd routes .bat/.cmd through cmd.exe on Windows", {
  sc <- shell_cmd("C:/ruby/bin/jekyll.bat", "build", windows = TRUE)
  expect_match(tolower(basename(sc$cmd)), "cmd")
  expect_equal(sc$args[1:2], c("/c", "C:/ruby/bin/jekyll.bat"))

  # real executables and non-Windows platforms pass through untouched
  sc <- shell_cmd("C:/ruby/bin/ruby.exe", "-v", windows = TRUE)
  expect_equal(sc$cmd, "C:/ruby/bin/ruby.exe")
  sc <- shell_cmd("/usr/bin/jekyll", "build", windows = FALSE)
  expect_equal(sc, list(cmd = "/usr/bin/jekyll", args = "build"))
})

test_that("install_ruby explains itself off Windows", {
  skip_on_os("windows")
  expect_error(install_ruby(), "Windows")
})

test_that("MinGit URLs are resolved correctly", {
  base <- "https://github.com/git-for-windows/git/releases/download"
  json <- sprintf(
    '"browser_download_url": "%s/v2.55.0.windows.3/%s",',
    base,
    c("Git-2.55.0.3-64-bit.exe",
      "MinGit-2.55.0.3-busybox-64-bit.zip",
      "MinGit-2.55.0.3-64-bit.zip",
      "MinGit-2.55.0.3-arm64.zip"))
  json <- paste(json, collapse = "\n")

  # the plain 64-bit zip -- never the installer or the busybox variant
  expect_match(mg_pick_asset(json), "/MinGit-2\\.55\\.0\\.3-64-bit\\.zip$")
  expect_error(mg_pick_asset('{"assets": []}'), "git-for-windows")

  # tag notation <-> asset notation, both windows.1 and windows.N
  expect_equal(
    mg_pinned_url("2.55.0.3"),
    paste0(base, "/v2.55.0.windows.3/MinGit-2.55.0.3-64-bit.zip"))
  expect_equal(
    mg_pinned_url("2.47.1"),
    paste0(base, "/v2.47.1.windows.1/MinGit-2.47.1-64-bit.zip"))
  expect_equal(mg_tag_version('tag/v2.55.0.windows.3"'), "2.55.0.3")
  expect_equal(mg_tag_version('tag/v2.47.1.windows.1"'), "2.47.1")
  expect_length(mg_tag_version("<html>nothing</html>"), 0)
})

test_that("install_git explains itself off Windows", {
  skip_on_os("windows")
  expect_error(install_git(), "Windows")
})
