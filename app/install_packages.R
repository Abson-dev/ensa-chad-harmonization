# Installs the R packages the application needs (only the missing ones).
# Versions the application was tested with (R 4.5.2):
#   shiny 1.14.0, bslib 0.11.0, bsicons 0.1.2, plotly 4.12.0, reactable 0.4.5, visNetwork 2.1.4,
#   shinyWidgets 0.9.1, readxl 1.4.5, readr 2.1.6, dplyr 1.2.1, tidyr 1.3.2, jsonlite 2.0.0

pkgs <- c("shiny", "bslib", "bsicons", "plotly", "reactable", "visNetwork", "shinyWidgets",
          "readxl", "readr", "dplyr", "tidyr", "jsonlite", "htmltools", "rlang")
repo <- "https://cloud.r-project.org"

missing <- pkgs[!vapply(pkgs, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing)) {
  # if R's library is not writable (R installed for all users), use the user's personal library
  lib <- .libPaths()[1]
  if (file.access(lib, 2) != 0) {
    lib <- Sys.getenv("R_LIBS_USER")
    dir.create(lib, recursive = TRUE, showWarnings = FALSE)
    .libPaths(c(lib, .libPaths()))
  }
  # behind a corporate proxy, the "wininet" method (Windows network settings) often works
  # where the default method fails
  if (.Platform$OS.type == "windows") {
    reachable <- suppressWarnings(tryCatch(nrow(utils::available.packages(repos = repo)) > 0,
                                           error = function(e) FALSE))
    if (!reachable) options(download.file.method = "wininet")
  }
  cat("Installing missing packages:", paste(missing, collapse = ", "), "\n")
  suppressWarnings(utils::install.packages(missing, lib = lib, repos = repo))
  still <- missing[!vapply(missing, requireNamespace, logical(1), quietly = TRUE)]
  if (length(still)) stop("Could not install: ", paste(still, collapse = ", "))
}
cat("R packages: OK\n")
