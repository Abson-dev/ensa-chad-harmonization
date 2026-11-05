# ENSA Chad 2018-2025: food security dashboard and harmonisation explorer.
# Run from this folder:  shiny::runApp()   (after Rscript prepare_app_data.R)
# Files in R/ are loaded automatically by Shiny.

library(shiny)
library(bslib)

check_auth()
d <- load_app_data()
round_choices <- rev(setNames(d$rounds$round_id, d$rounds$round))

ui <- protect_ui(page_navbar(
  id = "page",
  title = brand(),
  window_title = "ENSA Chad · Food security",
  theme = app_theme(),
  navbar_options = navbar_options(theme = "light"),
  fillable = FALSE,
  header = tagList(
    tags$link(rel = "stylesheet", href = "styles.css"),
    useBusyIndicators()
  ),
  sidebar = sidebar(
    class = "global-sidebar", width = 250, gap = "0.5rem",
    # On narrow screens the round selector stays reachable above the content.
    open = list(desktop = "open", mobile = "always-above"),
    if (demo_mode()) div(class = "demo-banner", "SYNTHETIC DATA: no estimate on this page is real"),
    selectInput("ref_round", "Reference round", round_choices, selected = round_choices[1]),
    uiOutput("round_info"),
    hr(),
    div(class = "note", "The reference round drives Overview, Trends and Regions."),
    hr(),
    uiOutput("provenance")
  ),
  nav_panel("Overview", icon = bsicons::bs_icon("speedometer2"), situation_ui("situation", d)),
  nav_panel("Trends", icon = bsicons::bs_icon("graph-up"), trends_ui("trends", d)),
  nav_panel("Regions", icon = bsicons::bs_icon("geo-alt"), regions_ui("regions", d)),
  nav_panel("Simulation", icon = bsicons::bs_icon("sliders"), simulation_ui("simulation", d)),
  nav_panel("Validation", icon = bsicons::bs_icon("patch-check"), validation_ui("validation", d)),
  nav_panel("Data issues", icon = bsicons::bs_icon("exclamation-triangle"), issues_ui("issues", d)),
  nav_menu(
    "Method", icon = bsicons::bs_icon("diagram-3"),
    nav_panel("Approach", icon = bsicons::bs_icon("signpost-split"), approach_ui("approach", d)),
    nav_panel("Process", icon = bsicons::bs_icon("diagram-3"), process_ui("process", d)),
    nav_panel("Crosswalk", icon = bsicons::bs_icon("table"), crosswalk_ui("crosswalk", d)),
    nav_panel("Rounds", icon = bsicons::bs_icon("calendar3"), rounds_ui("rounds", d))
  ),
  nav_panel("Data", icon = bsicons::bs_icon("download"), data_ui("data", d)),
  nav_panel("About", icon = bsicons::bs_icon("info-circle"), about_ui("about", d)),
  footer = tags$footer(
    class = "app-footer",
    "ENSA Chad 2018–2025 harmonisation · aggregate data only · preliminary, not official ENSA results · ",
    tags$a(href = "https://github.com/Abson-dev/ensa-chad-harmonization", target = "_blank", "Code on GitHub")
  )
))

server <- function(input, output, session) {
  protect_server()
  ref <- reactive(if (is.null(input$ref_round)) unname(round_choices[1]) else input$ref_round)

  output$round_info <- renderUI({
    r <- d$rounds[d$rounds$round_id == ref(), ]
    div(class = "note",
        strong("Fieldwork: "), sprintf("%s to %s", format(r$fieldwork_start, "%d %b"), format(r$fieldwork_end, "%d %b %Y")), br(),
        strong("Questionnaire: "), GEN_LABEL[[as.character(r$generation)]], br(),
        strong("Households: "), fmt_int(r$households), br(),
        strong("Weights: "), if (isTRUE(d$ind_round$weighted_available[d$ind_round$round_id == ref()])) "available" else "none, unweighted")
  })
  output$provenance <- renderUI({
    i <- d$manifest$inputs
    k <- match(ref(), i$round_id)
    div(class = "note",
        strong("Source: "), i$file[k], br(),
        strong("SHA-256: "), paste0(substr(i$sha256[k], 1, 12), "…"), br(),
        strong("Pipeline run: "), substr(d$manifest$run_utc, 1, 10))
  })

  situation_server("situation", d, ref)
  trends_server("trends", d, ref)
  regions_server("regions", d, ref)
  simulation_server("simulation", d)
  validation_server("validation", d)
  issues_server("issues", d)
  approach_server("approach", d)
  process_server("process", d)
  crosswalk_server("crosswalk", d)
  rounds_server("rounds", d)
  data_server("data", d)
  about_server("about", d)
}

shinyApp(ui, server)
