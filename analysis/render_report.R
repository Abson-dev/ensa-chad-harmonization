# Render the analysis-by-domain report to Word.
# Run from the analysis/ folder:   Rscript render_report.R
# Requires the harmonised files in ../output (python run_harmonize.py).

pkgs <- c("rmarkdown", "knitr", "officedown", "officer", "flextable", "data.table", "ggplot2",
          "survey", "scales", "forcats", "ggrepel", "ragg", "jsonlite")
missing <- pkgs[!vapply(pkgs, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing)) {
  cat("Installing missing packages:", paste(missing, collapse = ", "), "\n")
  utils::install.packages(missing, repos = "https://cloud.r-project.org")
}

# R Markdown needs Pandoc to write Word files. Outside RStudio it is often installed but not on
# the PATH, so look in the usual places.
find_pandoc <- function() {
  if (rmarkdown::pandoc_available("2.0")) return(invisible(TRUE))
  candidates <- c(
    Sys.getenv("RSTUDIO_PANDOC"),
    file.path(Sys.getenv("LOCALAPPDATA"), "Pandoc"),
    file.path(Sys.getenv("ProgramFiles"), "Pandoc"),
    file.path(Sys.getenv("ProgramFiles"), "RStudio", "resources", "app", "bin", "quarto", "bin", "tools"),
    file.path(Sys.getenv("ProgramFiles"), "RStudio", "bin", "quarto", "bin", "tools"),
    file.path(Sys.getenv("ProgramFiles"), "Quarto", "bin", "tools"),
    file.path(Sys.getenv("LOCALAPPDATA"), "Programs", "Quarto", "bin", "tools"),
    file.path(Sys.getenv("ProgramFiles"), "Positron", "resources", "app", "quarto", "bin", "tools"),
    "/usr/local/bin", "/opt/homebrew/bin", "/Applications/RStudio.app/Contents/Resources/app/quarto/bin/tools"
  )
  exe <- if (.Platform$OS.type == "windows") "pandoc.exe" else "pandoc"
  for (dir in candidates[nzchar(candidates)]) {
    if (file.exists(file.path(dir, exe))) {
      Sys.setenv(RSTUDIO_PANDOC = dir)
      if (rmarkdown::pandoc_available("2.0")) return(invisible(TRUE))
    }
  }
  stop("Pandoc not found. Install it from https://pandoc.org/installing.html (or install RStudio), then retry.")
}
find_pandoc()
cat("Pandoc", as.character(rmarkdown::pandoc_version()), "\n")

out_dir <- file.path(getwd(), "output")
dir.create(out_dir, showWarnings = FALSE)
docx <- rmarkdown::render(
  "analysis_by_domain.Rmd",
  output_file = "ENSA_Chad_analysis_by_domain.docx",
  output_dir = out_dir,
  intermediates_dir = tempdir(),
  params = list(out_dir = out_dir),
  envir = new.env(),
  quiet = TRUE
)
# Captions, cross-references and the table of contents are Word fields: fill them in with Word
# when it is available (Windows), otherwise the reader updates them once (Ctrl+A, then F9).
updated <- FALSE
if (.Platform$OS.type == "windows") {
  status <- suppressWarnings(system2(
    "powershell", c("-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
                    shQuote(normalizePath("tools/update_word_fields.ps1")), "-Path", shQuote(normalizePath(docx))),
    stdout = TRUE, stderr = TRUE))
  updated <- is.null(attr(status, "status")) && any(grepl("Word fields updated", status))
}
if (!updated) {
  cat("Note: open the report in Word and press Ctrl+A then F9 to fill in the table of contents,",
      "table and figure numbers (close the file in Word first if it was open during rendering).\n")
}
cat("Report written to:", normalizePath(docx), "\n")
cat("Figures (PNG) and tables (CSV) in:", normalizePath(out_dir), "\n")
