# Data issues: the 'Data flags' sheet of the crosswalk workbook, organised by impact.

ISSUE_IMPACT <- c(
  "Weights" = "High", "FCS group coding reversed" = "High", "LCS item set" = "High", "LCS slot swap" = "High",
  "No panel ID" = "High", "Household size" = "Medium", "Expenditure" = "Medium", "HDDS score" = "Medium",
  "FCS staples" = "Medium", "Region names" = "Medium", "Population groups" = "Medium",
  "Education of head" = "Medium", "Text-stored indicators" = "Low", "Dates" = "Low", "Accented labels" = "Low",
  "Corrected FCS items" = "Low", "HDDS skip patterns" = "Low", "HHS" = "Low", "HHS frequency items" = "Low",
  "Cadre Harmonise variables" = "Low"
)
IMPACT_COL <- c(High = "#B83227", Medium = "#E58E26", Low = "#2F7FB5")

issues_ui <- function(id, d) {
  ns <- shiny::NS(id)
  htmltools::tagList(
    page_intro("Data issues",
               "Problems found while building the crosswalk and the pipeline, with how each is handled. 'High' issues change results if ignored."),
    htmltools::div(class = "d-flex gap-3 align-items-center mb-3",
                   shiny::radioButtons(ns("impact"), NULL, c("All", "High", "Medium", "Low"), inline = TRUE),
                   htmltools::span(class = "text-muted small", shiny::textOutput(ns("count"), inline = TRUE))),
    shiny::uiOutput(ns("cards"))
  )
}

issues_server <- function(id, d) {
  shiny::moduleServer(id, function(input, output, session) {
    flags <- d$flags |>
      dplyr::mutate(impact = factor(dplyr::coalesce(unname(ISSUE_IMPACT[issue]), "Medium"), levels = names(IMPACT_COL))) |>
      dplyr::arrange(impact)
    shown <- shiny::reactive(if (input$impact == "All") flags else flags[flags$impact == input$impact, ])
    output$count <- shiny::renderText(sprintf("%d of %d issues", nrow(shown()), nrow(flags)))
    output$cards <- shiny::renderUI({
      x <- shown()
      htmltools::div(class = "issue-grid", lapply(seq_len(nrow(x)), function(i) {
        imp <- as.character(x$impact[i])
        htmltools::div(
          class = "issue-card", style = sprintf("border-top-color:%s", IMPACT_COL[[imp]]),
          htmltools::div(class = "d-flex justify-content-between align-items-start gap-2",
                         htmltools::h5(x$issue[i]), pill(imp, IMPACT_COL[[imp]])),
          htmltools::div(class = "issue-rounds", bsicons::bs_icon("calendar3"), " ", x$rounds[i]),
          htmltools::p(class = "small", x$found[i]),
          htmltools::div(class = "issue-fix", bsicons::bs_icon("wrench-adjustable"), " ", x$handling[i])
        )
      }))
    })
  })
}
