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
