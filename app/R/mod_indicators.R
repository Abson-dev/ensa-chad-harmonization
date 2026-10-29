# Harmonised indicators: national and regional, by round.

IND_CHOICES <- c("FCS groups (28/42)" = "fcs_cat", "rCSI phases (Cadre Harmonisé)" = "rcsi_ch",
                 "Mean FCS" = "fcs_mean", "Mean rCSI" = "rcsi_mean")
MAP_CHOICES <- c("% Poor FCS" = "fcs_poor", "% Poor + Borderline FCS" = "fcs_pb", "% rCSI phase 3+" = "rcsi_p3",
                 "% rCSI phase 2+" = "rcsi_p23", "Mean FCS" = "fcs_mean", "Mean rCSI" = "rcsi_mean")

indicators_ui <- function(id, d) {
  ns <- shiny::NS(id)
  regions <- sort(unique(d$ind_region$admin1))
  htmltools::tagList(
    page_intro("Harmonised indicators",
               "FCS and rCSI recomputed identically for all rounds. Compare February with February and October with October: the two seasons differ systematically."),
    bslib::layout_sidebar(
      fillable = FALSE,
      sidebar = bslib::sidebar(
        width = 290,
        shiny::radioButtons(ns("estimate"), "Estimate",
                            c("Weighted (survey weights)" = "w", "Unweighted" = "u"), selected = "w"),
        shiny::checkboxInput(ns("fallback"), "Use unweighted where a round has no weight", TRUE),
        shiny::checkboxGroupInput(ns("season"), "Season", c("February" = "2", "October" = "10"), selected = c("2", "10"),
                                  inline = TRUE),
        htmltools::hr(),
        shiny::selectInput(ns("region_metric"), "Regional heatmap", MAP_CHOICES, selected = "fcs_pb"),
        shinyWidgets::pickerInput(ns("regions"), "Regions to compare", choices = regions,
                                  selected = c("Lac", "Ouaddai", "Wadi Fira"), multiple = TRUE,
                                  options = shinyWidgets::pickerOptions(maxOptions = 6, liveSearch = TRUE)),
        htmltools::hr(),
        callout(type = "info", class = "small",
                "No usable weight in Oct 2021, Feb 2024 and Oct 2024; hatched bars use unweighted estimates. Regional cells under 30 households are suppressed.")
      ),
      bslib::layout_columns(
        col_widths = c(6, 6),
        bslib::card(full_screen = TRUE, bslib::card_header("Food Consumption Score groups (28/42)", class = "card-title-sm"),
                    plotly::plotlyOutput(ns("fcs"), height = "360px")),
        bslib::card(full_screen = TRUE, bslib::card_header("rCSI — Cadre Harmonisé phases", class = "card-title-sm"),
                    plotly::plotlyOutput(ns("rcsi"), height = "360px"))
      ),
      bslib::card(full_screen = TRUE, bslib::card_header(shiny::textOutput(ns("heat_title"), inline = TRUE), class = "card-title-sm"),
                  plotly::plotlyOutput(ns("heat"), height = "620px")),
      bslib::card(full_screen = TRUE, bslib::card_header("Selected regions vs national", class = "card-title-sm"),
                  plotly::plotlyOutput(ns("trend"), height = "360px")),
      htmltools::p(class = "small text-muted",
                   "Preliminary harmonised estimates for methodological review; not official ENSA results. Indicators recomputed from household answers with WFP formulas.")
    )
  )
}

indicators_server <- function(id, d) {
  shiny::moduleServer(id, function(input, output, session) {
    month_of <- function(round_id) as.integer(substr(round_id, 6, 7))

    # Pick weighted or unweighted columns; flag rounds where the weighted value fell back.
    pick <- function(x, base) {
      w <- x[[paste0(base, "_w")]]; u <- x[[paste0(base, "_u")]]
      if (input$estimate == "u") return(list(v = u, fb = rep(FALSE, length(u))))
      fb <- is.na(w) & !is.na(u) & isTRUE(input$fallback)
      list(v = ifelse(fb, u, w), fb = fb)
    }
    nat <- shiny::reactive({
      x <- d$ind_round[month_of(d$ind_round$round_id) %in% as.integer(input$season), ]
      x
    })
    reg <- shiny::reactive(d$ind_region[month_of(d$ind_region$round_id) %in% as.integer(input$season), ])

    stacked <- function(x, parts, cols) {
      p <- plotly::plot_ly()
      for (k in names(parts)) {
        s <- pick(x, parts[[k]])
        p <- plotly::add_bars(p, x = x$round, y = s$v, name = k, marker = list(
          color = cols[[k]], line = list(color = "#ffffff", width = 0.5),
          pattern = list(shape = ifelse(s$fb, "/", ""), fillmode = "overlay",
                         fgcolor = "rgba(255,255,255,0.55)", size = 7, solidity = 0.25)),
          text = ifelse(is.na(s$v), "", sprintf("%.0f", s$v)), textposition = "inside",
          insidetextfont = list(color = if (k %in% c("Phase 1", "Phase 2")) COL$ink else "#fff", size = 11),
          hovertemplate = paste0("%{x} · ", k, ": %{y:.1f}%", ifelse(s$fb, " (unweighted)", ""), "<extra></extra>"))
      }
      p |> plotly_style(barmode = "stack", xaxis = list(title = "", tickangle = -40),
                        yaxis = list(title = "% of households", range = c(0, 100), ticksuffix = "%"))
    }

    output$fcs <- plotly::renderPlotly({
      shiny::validate(shiny::need(length(input$season) > 0, "Select at least one season."))
      stacked(nat(), list(Poor = "fcs_poor", Borderline = "fcs_border", Acceptable = "fcs_accept"), as.list(FCS_COL))
    })
    output$rcsi <- plotly::renderPlotly({
      shiny::validate(shiny::need(length(input$season) > 0, "Select at least one season."))
      stacked(nat(), list(`Phase 1` = "rcsi_p1", `Phase 2` = "rcsi_p2", `Phase 3+` = "rcsi_p3"), as.list(CH_COL))
    })

    metric <- function(x) {
      m <- input$region_metric
      switch(m,
             fcs_poor = pick(x, "fcs_poor"),
             fcs_pb = { a <- pick(x, "fcs_poor"); b <- pick(x, "fcs_border"); list(v = a$v + b$v, fb = a$fb) },
             rcsi_p3 = pick(x, "rcsi_p3"),
             rcsi_p23 = { a <- pick(x, "rcsi_p2"); b <- pick(x, "rcsi_p3"); list(v = a$v + b$v, fb = a$fb) },
             fcs_mean = pick(x, "fcs_mean"),
             rcsi_mean = pick(x, "rcsi_mean"))
    }
    output$heat_title <- shiny::renderText(paste(names(MAP_CHOICES)[MAP_CHOICES == input$region_metric], "by region and round"))

    output$heat <- plotly::renderPlotly({
      x <- reg()
      shiny::validate(shiny::need(nrow(x) > 0, "Select at least one season."))
      s <- metric(x)
      x$v <- s$v; x$fb <- s$fb
      lv <- d$round_levels[d$round_levels %in% x$round]
      regions <- sort(unique(x$admin1), decreasing = TRUE)
      z <- tapply(x$v, list(factor(x$admin1, levels = regions), factor(as.character(x$round), levels = lv)), function(v) v[1])
      hh <- tapply(x$households, list(factor(x$admin1, levels = regions), factor(as.character(x$round), levels = lv)), function(v) v[1])
      fb <- tapply(x$fb, list(factor(x$admin1, levels = regions), factor(as.character(x$round), levels = lv)), function(v) v[1])
      is_pct <- !grepl("mean", input$region_metric)
      good_high <- input$region_metric == "fcs_mean"
      txt <- matrix(sprintf("<b>%s · %s</b><br>%s<br>%s households%s", rep(regions, length(lv)), rep(lv, each = length(regions)),
                            ifelse(is.na(z), "suppressed / not available", if (is_pct) fmt_pct(z) else formatC(z, format = "f", digits = 1)),
                            fmt_int(hh), ifelse(fb %in% TRUE, "<br><i>unweighted</i>", "")),
                    nrow = length(regions))
      scale <- if (good_high) list(c(0, "#B83227"), c(0.5, "#F2C14E"), c(1, "#2E8B57")) else
        list(c(0, "#F7F7F2"), c(0.35, "#F6D58E"), c(0.7, "#E8833A"), c(1, "#9E2A1E"))
      cell <- matrix(ifelse(is.na(z), "", formatC(z, format = "f", digits = if (is_pct) 0 else 1)), nrow = length(regions))
      plotly::plot_ly(x = lv, y = regions, z = z, type = "heatmap", colorscale = scale, xgap = 2, ygap = 2,
                      text = cell, customdata = txt, hovertemplate = "%{customdata}<extra></extra>",
                      texttemplate = "%{text}", textfont = list(size = 10),
                      colorbar = list(thickness = 12, ticksuffix = if (is_pct) "%" else "")) |>
        plotly_style(legend = FALSE, plot_bgcolor = "#F1F3F5",
                     xaxis = list(title = "", side = "top", tickangle = -40, showgrid = FALSE),
                     yaxis = list(title = "", showgrid = FALSE), margin = list(l = 10, r = 10, t = 60, b = 10))
    })

    output$trend <- plotly::renderPlotly({
      shiny::req(length(input$season) > 0)
      x <- reg()[reg()$admin1 %in% input$regions, ]
      n <- nat(); s_n <- metric(n)
      is_pct <- !grepl("mean", input$region_metric)
      p <- plotly::plot_ly() |>
        plotly::add_trace(x = n$round, y = s_n$v, type = "scatter", mode = "lines+markers", name = "National",
                          line = list(color = COL$navy, width = 3, dash = "dot"), marker = list(size = 7))
      pal <- c("#0F7C80", "#C17F3A", "#6C5CE7", "#B83227", "#2E8B57", "#2F7FB5")
      for (k in seq_along(input$regions)) {
        xr <- x[x$admin1 == input$regions[k], ]
        if (!nrow(xr)) next
        s <- metric(xr)
        p <- plotly::add_trace(p, x = xr$round, y = s$v, type = "scatter", mode = "lines+markers", name = input$regions[k],
                               line = list(color = pal[k], width = 2), marker = list(size = 7), connectgaps = FALSE)
      }
      p |> plotly_style(xaxis = list(title = "", tickangle = -40, categoryorder = "array", categoryarray = d$round_levels),
                        yaxis = list(title = names(MAP_CHOICES)[MAP_CHOICES == input$region_metric],
                                     ticksuffix = if (is_pct) "%" else ""))
    })
  })
}
