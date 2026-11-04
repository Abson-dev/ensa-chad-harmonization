# Data: the aggregate tables behind the app, to filter and export. Never household records.

data_ui <- function(id, d) {
  ns <- shiny::NS(id)
  x <- d$ind_long
  htmltools::tagList(
    page_intro("Data", "Aggregate indicators, to filter and download. The app holds no household records.", "table"),
    bslib::layout_columns(
      col_widths = c(3, 2, 2, 2, 3), class = "filters",
      shiny::selectizeInput(ns("indicators"), "Indicators", stats::setNames(IND$label, IND$label), multiple = TRUE, options = list(placeholder = "All")),
      shiny::selectizeInput(ns("geo"), "Areas", c("Chad", sort(unique(x$geography[x$level == "Region"]))), multiple = TRUE, options = list(placeholder = "All")),
      shiny::selectizeInput(ns("rounds"), "Rounds", rev(d$round_levels), multiple = TRUE, options = list(placeholder = "All")),
      shiny::selectInput(ns("season"), "Season", c("All" = "", "February", "October")),
      htmltools::div(class = "buttons",
                     shiny::downloadButton(ns("csv"), "CSV", class = "btn-outline-primary"),
                     shiny::downloadButton(ns("excel"), "Excel", class = "btn-outline-primary"))
    ),
    callout(type = "info", "Preliminary harmonised estimates for methodological review, not official ENSA results. Agree any use outside the team with the data owners (SISAAP / WFP). Regional values under 30 households are suppressed; weighted is empty where the round has no usable weight."),
    bslib::card(bslib::card_header(shiny::textOutput(ns("count"), inline = TRUE)),
                bslib::card_body(fillable = FALSE, fill = FALSE, class = "free-body", DT::DTOutput(ns("table"), height = "auto", fill = FALSE)))
  )
}

data_server <- function(id, d) {
  shiny::moduleServer(id, function(input, output, session) {
    shown <- shiny::reactive({
      x <- d$ind_long
      if (length(input$indicators)) x <- x[x$indicator %in% input$indicators, ]
      if (length(input$geo)) x <- x[x$geography %in% input$geo, ]
      if (length(input$rounds)) x <- x[x$round %in% input$rounds, ]
      if (nzchar(input$season)) x <- x[x$season == input$season, ]
      x[order(x$round_id, x$level != "National", x$geography, decreasing = FALSE), ]
    })
    output$count <- shiny::renderText(sprintf("%s rows", fmt_int(nrow(shown()))))
    output$table <- DT::renderDT(
      DT::datatable(
        shown()[, c("geography", "round", "domain", "indicator", "unit", "weighted", "unweighted", "households")],
        rownames = FALSE, class = "compact hover stripe", selection = "none",
        colnames = c("Area", "Round", "Domain", "Indicator", "Unit", "Weighted", "Unweighted", "Households"),
        options = list(pageLength = 25, lengthMenu = c(25, 50, 100), autoWidth = FALSE, order = list(),
                       language = list(search = "Search:", lengthMenu = "_MENU_ rows", info = "_START_–_END_ of _TOTAL_"))
      ) |>
        DT::formatRound(c("weighted", "unweighted"), digits = 1) |>
        DT::formatRound("households", digits = 0) |>
        DT::formatStyle("geography", fontWeight = "650"),
      server = TRUE
    )
    name <- function(ext) sprintf("%sENSA_Chad_indicators.%s", if (demo_mode()) "SYNTHETIC_" else "", ext)
    output$csv <- shiny::downloadHandler(filename = function() name("csv"), content = function(f) readr::write_excel_csv(shown(), f))
    output$excel <- shiny::downloadHandler(filename = function() name("xlsx"), content = function(f) writexl::write_xlsx(shown(), f))
  })
}
