# About: methods, reproducibility, provenance and data statement.

about_ui <- function(id, d) {
  ns <- shiny::NS(id)
  m <- d$manifest
  env <- m$environment
  htmltools::tagList(
    page_intro("About & reproducibility", "How the harmonised data are produced, and how to reproduce them."),
    bslib::layout_columns(
      col_widths = c(6, 6),
      bslib::card(
        bslib::card_header("Method", class = "card-title-sm"),
        htmltools::tags$ol(
          htmltools::tags$li(htmltools::strong("Crosswalk. "), sprintf("Metadata of the 14 SPSS files scanned (%s distinct variables); %d concepts mapped by question content.", fmt_int(FACTS$distinct_vars), nrow(d$concepts))),
          htmltools::tags$li(htmltools::strong("Configuration. "), sprintf("%d explicit rules (domain × target × round), region lookup and scoring parameters in plain CSV/TOML files.", nrow(d$rules))),
          htmltools::tags$li(htmltools::strong("Recomputation. "), "FCS = 2·staples + 3·pulses + vegetables + fruit + 4·meat/fish + 4·dairy + 0.5·sugar + 0.5·oil; rCSI = less preferred + 2·borrow + portion + 3·adults + meals. Missing if any item is missing; out-of-range answers set to missing, never clipped."),
          htmltools::tags$li(htmltools::strong("Validation. "), "Agreement with the original scores, completeness checks, unit tests, SHA-256 provenance.")
        ),
        htmltools::h6("Thresholds"),
        htmltools::tags$ul(class = "small",
                           htmltools::tags$li("FCS groups: Poor ≤ 28, Borderline 28.5–42, Acceptable > 42 (Chad standard); 21/35 also provided."),
                           htmltools::tags$li("rCSI Cadre Harmonisé: Phase 1 ≤ 3, Phase 2 = 4–18, Phase 3+ ≥ 19."))
      ),
      bslib::card(
        bslib::card_header("Reproduce", class = "card-title-sm"),
        htmltools::p("Python pipeline (conda-forge environment) and this Shiny app:"),
        htmltools::pre(class = "code-block", paste(
          "conda env create -f environment.yml", "conda activate ensa-chad", "python -m pytest -q",
          "python run_harmonize.py", "", "# app (R)", "cd app", "Rscript prepare_app_data.R",
          "Rscript -e \"shiny::runApp()\"", sep = "\n")),
        htmltools::p(class = "small", "Code: ", htmltools::a(href = "https://github.com/Abson-dev/ensa-chad-harmonization",
                                                        target = "_blank", "github.com/Abson-dev/ensa-chad-harmonization"))
      )
    ),
    bslib::layout_columns(
      col_widths = c(5, 7),
      bslib::card(
        bslib::card_header("Run provenance", class = "card-title-sm"),
        htmltools::tags$dl(class = "row small mb-0",
                           htmltools::tags$dt(class = "col-5", "Pipeline run (UTC)"), htmltools::tags$dd(class = "col-7", m$run_utc),
                           htmltools::tags$dt(class = "col-5", "Pipeline version"), htmltools::tags$dd(class = "col-7", m$pipeline_version),
                           htmltools::tags$dt(class = "col-5", "Python"), htmltools::tags$dd(class = "col-7", env$python),
                           htmltools::tags$dt(class = "col-5", "pandas · numpy · pyreadstat"),
                           htmltools::tags$dd(class = "col-7", paste(env$pandas, env$numpy, env$pyreadstat, sep = " · ")),
                           htmltools::tags$dt(class = "col-5", "Households per domain"),
                           htmltools::tags$dd(class = "col-7", paste(names(m$row_counts), fmt_int(unlist(m$row_counts)), collapse = " · ")),
                           htmltools::tags$dt(class = "col-5", "App built with"),
                           htmltools::tags$dd(class = "col-7", sprintf("R %s · shiny %s · bslib %s", getRversion(),
                                                                       utils::packageVersion("shiny"), utils::packageVersion("bslib"))))
      ),
      bslib::card(
        bslib::card_header("Input files (SHA-256)", class = "card-title-sm"),
        reactable::reactableOutput(ns("inputs"))
      )
    ),
    bslib::card(
      bslib::card_header("Data statement", class = "card-title-sm"),
      htmltools::p("The ENSA surveys are conducted by the Government of Chad (SISAAP) with WFP and partners. This app contains ",
                   htmltools::strong("no household-level data"),
                   ": only variable metadata (crosswalk), pipeline configuration, quality-control tables and aggregate indicators by round and region (cells under 30 households suppressed). The estimates are preliminary harmonised figures for methodological review, not official ENSA results.")
    )
  )
}

about_server <- function(id, d) {
  shiny::moduleServer(id, function(input, output, session) {
    output$inputs <- reactable::renderReactable({
      x <- d$manifest$inputs
      x <- data.frame(round = x$round_id, file = x$file, MB = round(x$bytes / 1e6, 1),
                      sha256 = ifelse(is.na(x$sha256), "–", paste0(substr(x$sha256, 1, 16), "…")))
      reactable::reactable(x, compact = TRUE, pagination = FALSE, striped = TRUE,
                           columns = list(file = reactable::colDef(minWidth = 260, style = list(fontSize = "0.8em")),
                                          sha256 = reactable::colDef(style = list(fontFamily = "Consolas, monospace", fontSize = "0.8em"))))
    })
  })
}
