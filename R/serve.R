#' Serve the site locally with live reload
#'
#' Builds the site and serves `_site/` with live reload: keep the
#' preview tab open in the browser and every save of a watched file --
#' `_source/*.Rmd` and `*.qmd`, Markdown pages, `_config.yml`, data
#' files, styles -- re-knits what is stale, reruns `jekyll build` and
#' reloads the page. No manual [build_site()] calls while writing.
#'
#' By default the whole thing runs in a **separate background R
#' process**: your console stays free, nothing is printed there, and
#' rebuild output goes to a log file (`.jekylldown-serve.log` in the
#' site; the path is shown when the server starts). Stop it with
#' [stop_server()]. With `background = FALSE` the server runs in this
#' session instead (as a servr daemon), which keeps the console usable
#' but briefly busy during each rebuild.
#'
#' The rebuild is triggered by the open preview tab (it pings the server
#' about once a second); with no browser tab open, nothing rebuilds.
#'
#' @param dir Directory in (or under) the site.
#' @param background Run the watcher/server in a separate R process?
#'   Default `TRUE` in interactive sessions.
#' @param port Port to serve on; a random free port by default.
#' @param ... Passed on to [servr::httw()] (e.g. `daemon`, `interval`)
#'   when `background = FALSE`.
#' @return Invisibly, the preview URL.
#' @examples
#' \dontrun{
#' serve_site("my-site")               # console stays free; open the URL
#' stop_server("my-site")
#' }
#' @export
serve_site <- function(dir = ".", background = interactive(), port = NULL,
                       ...) {
  root <- site_root(dir)
  jekyll <- jekyll_cmd()
  if (is.null(jekyll)) {
    cli::cli_abort(c(
      "Serving needs a local {.code jekyll} to build the site.",
      "i" = "Install it with {.code gem install jekyll bundler}, then check
             with {.run jekylldown::check()}.",
      "i" = "Without Jekyll you can still knit with {.fn build_site} and let
             GitHub Pages build remotely."
    ))
  }
  if (is.null(port)) port <- servr::random_port()
  # any site being served gets the log/pid artifacts ignored -- also
  # sites created before this existed, or not created by jekylldown
  ensure_serve_gitignore(root)

  if (background) {
    pid_file <- file.path(root, ".jekylldown-serve.pid")
    # a server for this site may already be running (calling serve_site
    # twice is common): reuse it instead of piling up workers
    if (file.exists(pid_file)) {
      info <- suppressWarnings(strsplit(xfun::read_utf8(pid_file)[1],
                                        "\\s+")[[1]])
      old_pid <- as.integer(info[1])
      old_port <- if (length(info) > 1) as.integer(info[2]) else NA
      if (!is.na(old_pid) && !is.na(old_port) &&
          isTRUE(tools::pskill(old_pid, 0))) {
        url <- sprintf("http://127.0.0.1:%d", old_port)
        if (wait_for_server(old_port, timeout = 3)) {
          cli::cli_alert_info(
            "Already serving at {.url {url}} -- reopening the preview.
             Stop it with {.code stop_server(\"{dir}\")}.")
          open_preview(url)
          return(invisible(url))
        }
      }
    }

    log <- file.path(root, ".jekylldown-serve.log")
    code <- sprintf("jekylldown:::serve_worker(%s, %d)",
                    deparse(root), as.integer(port))
    px <- processx::process$new(
      file.path(R.home("bin"), "Rscript"), c("-e", code),
      stdout = log, stderr = "2>&1", cleanup = FALSE)
    xfun::write_utf8(paste(px$get_pid(), port), pid_file)
    url <- sprintf("http://127.0.0.1:%d", port)

    # the worker needs the initial jekyll build before it listens;
    # opening the preview earlier shows a blank page (the viewer does
    # not retry). Wait for the port -- and notice a worker that died.
    ready <- wait_for_server(port, px)
    if (!ready) {
      if (!px$is_alive()) {
        tail <- utils::tail(if (file.exists(log)) readLines(log) else
          character(), 10)
        unlink(file.path(root, ".jekylldown-serve.pid"))
        cli::cli_abort(c("The serve process died during the initial
                          build.",
                         stats::setNames(tail, rep("x", length(tail)))))
      }
      cli::cli_warn("Server still starting (slow first build?); open
                     {.url {url}} yourself once it responds.")
    }
    cli::cli_alert_success(
      "Serving {.path {root}} in a background process at {.url {url}}.")
    cli::cli_alert_info(
      "Console stays free; rebuild output goes to {.file {log}}.
       Keep the preview tab open -- it is what triggers rebuilds.
       Stop with {.code stop_server(\"{dir}\")}.")
    if (ready) open_preview(url)
    return(invisible(url))
  }

  serve_impl(root, port = port, ...)
  invisible(sprintf("http://127.0.0.1:%d", port))
}

# The in-process implementation (used directly with background = FALSE,
# and by the background worker).
serve_impl <- function(root, port, ...) {
  jd_set_env()
  command <- serve_build_command(root)

  serve_rebuild(root, command, first = TRUE)
  # `watch` MUST be an absolute path: servr evaluates its watcher lazily
  # from inside the served directory (_site), so a relative watch dir
  # would silently watch the wrong tree and no source edit would ever
  # trigger a rebuild.
  xfun::in_dir(root, servr::httw(
    dir = "_site",
    watch = root,
    pattern = "[.]([RrQq]?md|ya?ml|html|css|s[ac]ss|js|bib)$",
    filter = function(f) {
      f[!grepl("/(_site|_cache|[.]jekyll-cache|[.]sass-cache|[.]quarto|[.]git|vendor|node_modules)/",
               f)]
    },
    handler = function(files) serve_rebuild(root, command),
    baseurl = jekyll_baseurl(root),
    port = port,
    ...
  ))
}

# Entry point of the background process: block forever serving the site.
serve_worker <- function(root, port) {
  serve_impl(root, port = port, daemon = FALSE, browser = FALSE)
}

# How to run `jekyll build` for this site, as command + args + extra
# environment (env prefixes in a command string are POSIX-shell only,
# and .bat/.cmd wrappers need cmd.exe -- both handled at run time).
serve_build_command <- function(root) {
  jekyll <- jekyll_cmd()
  bundle <- find_cmd("bundle")
  if (file.exists(file.path(root, "Gemfile.lock")) && !is.null(bundle)) {
    list(cmd = bundle, args = c("exec", "jekyll", "build"),
         env = character())
  } else if (file.exists(file.path(root, "Gemfile"))) {
    # Gemfile without lockfile: stop jekyll from Bundler.setup-ing and
    # crashing on version skew (run bundle_install() for the real thing)
    list(cmd = jekyll, args = "build",
         env = c(JEKYLL_NO_BUNDLER_REQUIRE = "true"))
  } else {
    list(cmd = jekyll, args = "build", env = character())
  }
}

# One watcher round: re-knit whatever is outdated, then `jekyll build`
# -- quietly: one status line per rebuild instead of the full jekyll
# echo. A knitting or build error during serving is reported but must
# not kill the server (the user fixes the file and saves again).
serve_rebuild <- function(root, command, first = FALSE) {
  run <- function() {
    t0 <- Sys.time()
    knitted <- knit_all(root, quiet = TRUE)
    sc <- shell_cmd(command$cmd, command$args)
    env <- c("current", jd_env(), command$env)
    res <- processx::run(sc$cmd, sc$args, wd = root, env = env,
                         stdout = NULL, stderr = NULL,
                         error_on_status = FALSE)
    status <- res$status
    if (status != 0) {
      # rerun visibly so the error is in the log/console
      processx::run(sc$cmd, sc$args, wd = root, env = env,
                    echo = TRUE, error_on_status = FALSE)
      cli::cli_warn("{.code jekyll build} failed; fix and save again.")
    } else {
      secs <- round(as.numeric(Sys.time() - t0, units = "secs"), 1)
      what <- if (length(knitted)) {
        paste0(" (re-knitted ", paste(basename(knitted), collapse = ", "),
               ")")
      } else ""
      cli::cli_alert_success("Rebuilt{what} in {secs}s.")
    }
    # the background worker logs to a file; without flushing, lines sit
    # in the buffer and the log looks dead
    flush(stdout()); flush(stderr())
    invisible(status)
  }
  xfun::in_dir(root, {
    if (first) {
      if (run() != 0) cli::cli_abort("Initial build failed.")
    } else {
      tryCatch(run(), error = function(e) {
        cli::cli_warn(c("Rebuild failed: {conditionMessage(e)}",
                        "i" = "Fix the file and save again."))
      })
    }
  })
  invisible(TRUE)
}

# `baseurl` from _config.yml, so links work when the built site is served
# from a subpath (project pages).
jekyll_baseurl <- function(root) {
  config <- file.path(root, "_config.yml")
  if (!file.exists(config)) return("")
  line <- grep("^baseurl:", xfun::read_utf8(config), value = TRUE)
  if (!length(line)) return("")
  v <- trimws(sub("^baseurl:", "", line[[1]]))
  v <- sub("#.*$", "", v)
  gsub("[\"']", "", trimws(v))
}

#' Stop servers started by [serve_site()]
#'
#' Stops the background serve process of `dir` (found through the
#' `.jekylldown-serve.pid` file the server wrote), plus any in-session
#' servr daemons.
#'
#' @param dir Directory in (or under) a site served with
#'   `background = TRUE`; `NULL` only stops in-session daemons.
#' @return `NULL`, invisibly.
#' @examples
#' \dontrun{
#' stop_server("my-site")
#' }
#' @export
stop_server <- function(dir = ".") {
  root <- tryCatch(site_root(dir), error = function(e) NULL)
  if (!is.null(root)) {
    pid_file <- file.path(root, ".jekylldown-serve.pid")
    if (file.exists(pid_file)) {
      # the file holds "pid" (old format) or "pid port"
      first <- strsplit(trimws(xfun::read_utf8(pid_file)[1]), "\\s+")[[1]][1]
      pid <- suppressWarnings(as.integer(first))
      if (!is.na(pid)) {
        tools::pskill(pid)
        cli::cli_alert_success("Background server (pid {pid}) stopped.")
      }
      unlink(pid_file)
    }
  }
  try(servr::daemon_stop(), silent = TRUE)
  invisible(NULL)
}

# The background server writes .jekylldown-serve.log/.pid into the site;
# they belong to the machine, not the repo. Idempotently keep them out
# of git -- called by new_site() and by serve_site() itself, so sites
# from older versions (or not created by jekylldown) are covered too.
ensure_serve_gitignore <- function(root) {
  gitignore <- file.path(root, ".gitignore")
  gi <- if (file.exists(gitignore)) xfun::read_utf8(gitignore) else character()
  if (!any(grepl(".jekylldown-serve", gi, fixed = TRUE))) {
    xfun::write_utf8(c(gi, ".jekylldown-serve.*"), gitignore)
  }
  invisible(gitignore)
}

# Block until the server answers an actual HTTP request (or the worker
# dies, or the timeout passes). A bare TCP connect is not enough: the
# kernel accepts connections as soon as the listener exists, before the
# app responds -- the RStudio Viewer would land in that window, get
# nothing, and stay blank (it does not retry). Doing a real GET also
# warms the app up, so the Viewer's own request is fast.
wait_for_server <- function(port, px = NULL, timeout = 60) {
  t0 <- Sys.time()
  while (as.numeric(Sys.time() - t0, units = "secs") < timeout) {
    if (!is.null(px) && !px$is_alive()) return(FALSE)
    ok <- tryCatch({
      con <- suppressWarnings(socketConnection(
        "127.0.0.1", port, open = "r+b", blocking = TRUE, timeout = 3))
      on.exit(try(close(con), silent = TRUE), add = TRUE)
      writeLines(c("GET / HTTP/1.0", "Host: 127.0.0.1", "", ""), con,
                 sep = "\r\n")
      head <- suppressWarnings(readLines(con, n = 1))
      close(con)
      on.exit()
      length(head) && grepl("^HTTP/", head)
    }, error = function(e) FALSE)
    if (ok) return(TRUE)
    Sys.sleep(0.2)
  }
  FALSE
}

# Open the preview: RStudio's Viewer pane when available (live reload
# works there too), the default browser otherwise. The short settle
# gives the freshly-warmed server a beat before the pane fetches.
open_preview <- function(url) {
  if (!interactive()) return(invisible(url))
  Sys.sleep(0.3)
  viewer <- getOption("viewer")
  if (is.function(viewer)) {
    try(viewer(url), silent = TRUE)
  } else {
    try(utils::browseURL(url), silent = TRUE)
  }
  invisible(url)
}
