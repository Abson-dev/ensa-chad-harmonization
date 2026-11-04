# Regions: profile of one region, ranking of all regions, region x round map.

regions_ui <- function(id, d) {
  ns <- shiny::NS(id)
  regions <- sort(unique(d$ind_region$admin1))
  htmltools::tagList(
    page_intro("Regions", "Profile of one region against the national value, and all regions side by side.",
               "geo-alt", shiny::uiOutput(ns("chip"))),
    bslib::layout_columns(
      col_widths = c(4, 8), class = "filters",
      shiny::selectInput(ns("region"), "Region", regions, selected = if ("Lac" %in% regions) "Lac" else regions[1]),
      shiny::selectInput(ns("metric"), "Indicator for the ranking and the map", IND_CHOICES[names(IND_CHOICES) != "Demographics"], selected = "fcs_pb")
    ),
    shiny::uiOutput(ns("kpis")),
    bslib::layout_columns(
      col_widths = c(8, 4),
      bslib::card(height = 500, full_screen = TRUE, bslib::card_header(shiny::textOutput(ns("table_title"), inline = TRUE)),
                  bslib::card_body(padding = 0, reactable::reactableOutput(ns("table"))),
                  bslib::card_footer(class = "table-note", "* No usable weight: unweighted. –: not collected, or fewer than 30 households. Change against the latest round of the same season.")),
      bslib::card(height = 500, full_screen = TRUE, bslib::card_header(shiny::textOutput(ns("rank_title"), inline = TRUE)),
                  plotly::plotlyOutput(ns("rank"), height = "100%"))
    ),
    bslib::card(full_screen = TRUE, bslib::card_header(shiny::textOutput(ns("heat_title"), inline = TRUE)),
                plotly::plotlyOutput(ns("heat"), height = "620px")),
    bslib::card(full_screen = TRUE, bslib::card_header("Selected regions against the national value"),
                shinyWidgets::pickerInput(ns("compare"), NULL, choices = regions, selected = c("Lac", "Ouaddai", "Wadi Fira"), multiple = TRUE,
                                          options = shinyWidgets::pickerOptions(maxOptions = 6, liveSearch = TRUE, noneSelectedText = "Select up to 6 regions")),
                plotly::plotlyOutput(ns("trend"), height = "340px")),
    htmltools::p(class = "small text-muted", "Preliminary harmonised estimates for methodological review; not official ENSA results. Regional cells under 30 households are suppressed.")
  )
}

regions_server <- function(id, d, ref) {
  shiny::moduleServer(id, function(input, output, session) {
    reg <- as.data.frame(d$ind_region)
    nat <- d$ind_round
    output$chip <- round_chip(d, ref)
    area <- shiny::reactive(reg[reg$admin1 == input$region, ])

    output$kpis <- shiny::renderUI({
      x <- area(); rid <- ref()
      card <- function(id, title, icon, tone) {
        cmp <- ind_compare(x, id, rid)
        n <- ind_value(nat[nat$round_id == rid, ], id)$v
        kpi(title, fmt_ind(cmp$value, id),
            if (is.na(cmp$value)) "Not available in this round" else
              htmltools::tagList(change_tag(cmp, id), htmltools::br(), sprintf("National: %s", fmt_ind(n, id))),
            icon, tone)
      }
      hh <- x$households[x$round_id == rid]
      bslib::layout_column_wrap(
        width = "190px", fill = FALSE, heights_equal = "row",
        kpi("Households surveyed", if (length(hh)) fmt_int(hh) else "–",
            if (length(hh)) sprintf("%s in %s", input$region, d$rounds$round[d$rounds$round_id == rid]) else "Not surveyed in this round", "people", "slate"),
        card("fcs_pb", "Poor + borderline FCS", "basket", "orange"),
        card("rcsi_p3", "rCSI phase 3+", "shield-exclamation", "red"),
        card("lcs_ce", "Crisis + emergency coping", "life-preserver", "amber"),
        card("hdds_p3", "Dietary diversity phase 3+", "egg-fried", "blue")
      )
    })

    output$table_title <- shiny::renderText(sprintf("%s, latest six rounds", input$region))
    output$table <- reactable::renderReactable({
      x <- area(); rid <- ref()
      keep <- utils::tail(sort(x$round_id[x$round_id <= rid]), 6)
      shiny::validate(shiny::need(rid %in% x$round_id, "This region was not surveyed in the reference round."))
      ind_reactable(ind_table(x, IND_MAIN, keep, rid), x, IND_MAIN, rid)
    })

    output$rank_title <- shiny::renderText(sprintf("%s, %s", metric_label(input$metric), d$rounds$round[d$rounds$round_id == ref()]))
    output$rank <- plotly::renderPlotly({
      id <- input$metric; rid <- ref()
      x <- reg[reg$round_id == rid, ]
      x$v <- ind_value(x, id)$v
      x <- x[!is.na(x$v), ]
      shiny::validate(shiny::need(nrow(x) > 0, "Not available in this round."))
      x <- x[order(x$v), ]
      n <- ind_value(nat[nat$round_id == rid, ], id)$v
      plotly::plot_ly(x, y = factor(x$admin1, levels = x$admin1), x = ~v, type = "bar", orientation = "h",
                      marker = list(color = ifelse(x$admin1 == input$region, COL$navy, "#9FCFCF")),
                      text = fmt_ind(x$v, id), textposition = "outside", cliponaxis = FALSE,
                      hovertemplate = "%{y}: %{text}<extra></extra>") |>
        plotly_style(legend = FALSE, margin = list(t = 26, r = 44, b = 10, l = 10),
                     xaxis = list(title = "", showticklabels = FALSE, showgrid = FALSE),
                     yaxis = list(title = "", tickfont = list(size = 11)),
                     shapes = list(list(type = "line", yref = "paper", y0 = 0, y1 = 1, x0 = n, x1 = n,
                                        line = list(color = COL$ink, width = 1, dash = "dot"))),
                     annotations = list(list(x = n, y = 1, yref = "paper", yanchor = "bottom", showarrow = FALSE,
                                             text = sprintf("National %s", fmt_ind(n, id)), font = list(size = 11, color = COL$ink))))
    })

    output$heat_title <- shiny::renderText(sprintf("%s by region and round", metric_label(input$metric)))
    output$heat <- plotly::renderPlotly({
      id <- input$metric
      x <- reg
      s <- ind_value(x, id)
      x$v <- s$v; x$fb <- s$fb
      lv <- d$round_levels[d$round_levels %in% x$round]
      regions <- sort(unique(x$admin1), decreasing = TRUE)
      grid <- function(col) tapply(x[[col]], list(factor(x$admin1, levels = regions), factor(as.character(x$round), levels = lv)), function(v) v[1])
      z <- grid("v"); hh <- grid("households"); fb <- grid("fb")
      txt <- matrix(sprintf("<b>%s · %s</b><br>%s<br>%s households%s", rep(regions, length(lv)), rep(lv, each = length(regions)),
                            ifelse(is.na(z), "suppressed / not available", fmt_ind(z, id)),
                            fmt_int(hh), ifelse(fb %in% TRUE, "<br><i>unweighted</i>", "")),
                    nrow = length(regions))
      cell <- matrix(ifelse(is.na(z), "", formatC(z, format = "f", digits = if (is_pct(id)) 0 else 1)), nrow = length(regions))
      k <- match(as.character(d$rounds$round[d$rounds$round_id == ref()]), lv)
      plotly::plot_ly(x = lv, y = regions, z = z, type = "heatmap", colorscale = heat_scale(id), xgap = 2, ygap = 2,
                      text = cell, customdata = txt, hovertemplate = "%{customdata}<extra></extra>",
                      texttemplate = "%{text}", textfont = list(size = 10),
                      colorbar = list(thickness = 12, ticksuffix = if (is_pct(id)) "%" else "")) |>
        plotly_style(legend = FALSE, plot_bgcolor = "#F1F3F5",
                     xaxis = list(title = "", side = "top", tickangle = -40, showgrid = FALSE),
                     yaxis = list(title = "", showgrid = FALSE), margin = list(l = 10, r = 10, t = 60, b = 10),
                     shapes = list(list(type = "rect", yref = "paper", xref = "x", y0 = 0, y1 = 1, x0 = k - 1.5, x1 = k - 0.5,
                                        line = list(color = COL$navy, width = 2))))
    })

    output$trend <- plotly::renderPlotly({
      id <- input$metric
      n <- nat[order(nat$round_id), ]
      p <- plotly::plot_ly() |>
        plotly::add_trace(x = n$round, y = ind_value(n, id)$v, type = "scatter", mode = "lines+markers", name = "National",
                          line = list(color = COL$navy, width = 3, dash = "dot"), marker = list(size = 7))
      pal <- c("#0F7C80", "#C17F3A", "#6C5CE7", "#B83227", "#2E8B57", "#2F7FB5")
      for (k in seq_along(input$compare)) {
        xr <- reg[reg$admin1 == input$compare[k], ]
        xr <- xr[order(xr$round_id), ]
        if (!nrow(xr)) next
        p <- plotly::add_trace(p, x = xr$round, y = ind_value(xr, id)$v, type = "scatter", mode = "lines+markers", name = input$compare[k],
                               line = list(color = pal[k], width = 2), marker = list(size = 7), connectgaps = FALSE)
      }
      p |> plotly_style(xaxis = list(title = "", tickangle = -40, categoryorder = "array", categoryarray = d$round_levels),
                        yaxis = list(title = "", ticksuffix = if (is_pct(id)) "%" else ""))
    })
  })
}
