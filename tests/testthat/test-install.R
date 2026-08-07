test_that("ri_pick_asset picks the right RubyInstaller archive", {
  base <- "https://github.com/oneclick/rubyinstaller2/releases/download"
  json <- sprintf(paste0(
    '"browser_download_url": "%s/RubyInstaller-3.3.7-1/%s",'),
    base,
    c("rubyinstaller-devkit-3.3.7-1-x64.7z",
      "rubyinstaller-devkit-3.3.7-1-x64.exe",
      "rubyinstaller-3.3.7-1-x64.7z",
      "rubyinstaller-3.3.7-1-x64.exe"))
  json <- paste(json, collapse = "\n")

  expect_match(ri_pick_asset(json),
               "/rubyinstaller-3\\.3\\.7-1-x64\\.7z$")
  expect_match(ri_pick_asset(json, devkit = TRUE),
               "/rubyinstaller-devkit-3\\.3\\.7-1-x64\\.7z$")
  expect_error(ri_pick_asset('{"assets": []}'), "rubyinstaller.org")
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
