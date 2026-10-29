# ENSA Chad 2018-2025 — harmonisation explorer.
# Run from this folder:  shiny::runApp()   (after Rscript prepare_app_data.R)
# Files in R/ are loaded automatically by Shiny.

library(shiny)
library(bslib)

d <- load_app_data("data")

ui <- page_navbar(
  title = tags$span(class = "brand", bsicons::bs_icon("grid-3x3-gap-fill"), " ENSA Chad · Harmonisation"),
  window_title = "ENSA Chad harmonisation explorer",
  theme = app_theme(),
  fillable = FALSE,
  header = tagList(
    tags$link(rel = "stylesheet", href = "styles.css"),
    useBusyIndicators()
  ),
  nav_panel("Overview", icon = bsicons::bs_icon("house"), overview_ui("overview", d)),
  nav_panel("Process", icon = bsicons::bs_icon("diagram-3"), process_ui("process", d)),
  nav_panel("Crosswalk", icon = bsicons::bs_icon("table"), crosswalk_ui("crosswalk", d)),
  nav_panel("Rounds", icon = bsicons::bs_icon("calendar3"), rounds_ui("rounds", d)),
  nav_panel("Validation", icon = bsicons::bs_icon("patch-check"), validation_ui("validation", d)),
  nav_panel("Indicators", icon = bsicons::bs_icon("bar-chart-line"), indicators_ui("indicators", d)),
  nav_panel("Data issues", icon = bsicons::bs_icon("exclamation-triangle"), issues_ui("issues", d)),
  nav_spacer(),
  nav_panel("About", icon = bsicons::bs_icon("info-circle"), about_ui("about", d)),
  footer = tags$footer(
    class = "app-footer",
    "ENSA Chad 2018–2025 harmonisation · aggregate data only · ",
    tags$a(href = "https://github.com/Abson-dev/ensa-chad-harmonization", target = "_blank", "Abson-dev on GitHub")
  )
)

server <- function(input, output, session) {
  overview_server("overview", d)
  process_server("process", d)
  crosswalk_server("crosswalk", d)
  rounds_server("rounds", d)
  validation_server("validation", d)
  indicators_server("indicators", d)
  issues_server("issues", d)
  about_server("about", d)
}

shinyApp(ui, server)
