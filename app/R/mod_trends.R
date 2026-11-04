# Trends: one indicator across years, February with February and October with October.

trends_ui <- function(id, d) {
  ns <- shiny::NS(id)
  htmltools::tagList(
    page_intro("Trends", "One indicator over time. The two seasons differ systematically: compare February with February and October with October.",
               "graph-up", shiny::uiOutput(ns("chip"))),
    bslib::layout_columns(
      col_widths = c(5, 4, 3), class = "filters",
      shiny::selectInput(ns("indicator"), "Indicator", IND_CHOICES, selected = "fcs_pb"),
      shiny::selectInput(ns("geo"), "Area", c("Chad (national)" = "", sort(unique(d$ind_region$admin1)))),
      shiny::radioButtons(ns("estimate"), "Estimate", c("Weighted" = "w", "Unweighted" = "u"), inline = TRUE)
    ),
    shiny::uiOutput(ns("kpis")),
    bslib::layout_columns(
      col_widths = c(7, 5),
      bslib::card(full_screen = TRUE, bslib::card_header(shiny::textOutput(ns("title"), inline = TRUE)),
                  plotly::plotlyOutput(ns("season"), height = "360px"),
                  bslib::card_footer(class = "table-note", "Hollow marker: no usable weight, unweighted value. Gaps: not collected, or fewer than 30 households. Ring: reference round.")),
      bslib::card(full_screen = TRUE, bslib::card_header("Same indicator, round by round"),
                  bslib::card_body(padding = 0, reactable::reactableOutput(ns("table"))))
    ),
    bslib::layout_columns(
      col_widths = c(6, 6),
      bslib::card(full_screen = TRUE, bslib::card_header("Food Consumption Score groups (28/42)"), plotly::plotlyOutput(ns("fcs"), height = "340px")),
      bslib::card(full_screen = TRUE, bslib::card_header("rCSI, Cadre Harmonisé phases"), plotly::plotlyOutput(ns("rcsi"), height = "340px"))
    ),
    htmltools::p(class = "small text-muted", "Preliminary harmonised estimates for methodological review; not official ENSA results. Hatched bars: no usable weight, unweighted.")
  )
}

trends_server <- function(id, d, ref) {
  shiny::moduleServer(id, function(input, output, session) {
    output$chip <- round_chip(d, ref)
    area <- shiny::reactive({
      if (!nzchar(input$geo)) d$ind_round else as.data.frame(d$ind_region[d$ind_region$admin1 == input$geo, ])
    })
    area_name <- shiny::reactive(if (nzchar(input$geo)) input$geo else "Chad")

    output$title <- shiny::renderText(sprintf("%s, %s, by season", metric_label(input$indicator), area_name()))

    output$kpis <- shiny::renderUI({
      x <- area(); rid <- ref(); id <- input$indicator
      seasons <- x[same_season(x$round_id, rid) & x$round_id <= rid, ]
      seasons <- seasons[order(seasons$round_id, decreasing = TRUE), ]
      seasons <- utils::head(seasons, 4)
      seasons <- seasons[order(seasons$round_id), ]
      bslib::layout_column_wrap(
        width = "200px", fill = FALSE, heights_equal = "row",
        !!!lapply(seq_len(nrow(seasons)), function(i) {
          s <- seasons[i, ]
          cmp <- ind_compare(x, id, s$round_id, input$estimate)
          current <- s$round_id == rid
          kpi(as.character(s$round), fmt_ind(cmp$value, id),
              if (is.na(cmp$value)) "Not available" else change_tag(cmp, id),
              "calendar3", if (current) "teal" else "slate")
        })
      )
    })

    output$season <- plotly::renderPlotly({
      x <- area(); id <- input$indicator; rid <- ref()
      x$year <- as.integer(substr(x$round_id, 1, 4))
      x$r <- ind_value(x, id, input$estimate)$v
      x$fb <- ind_value(x, id, input$estimate)$fb
      series <- list(October = list(m = "10", col = COL$teal), February = list(m = "02", col = "#C17F3A"))
      p <- plotly::plot_ly()
      for (nm in names(series)) {
        s <- x[substr(x$round_id, 6, 7) == series[[nm]]$m, ]
        s <- s[order(s$year), ]
        ref_row <- s$round_id == rid
        p <- plotly::add_trace(
          p, x = s$year, y = s$r, type = "scatter", mode = "lines+markers", name = nm, connectgaps = FALSE,
          line = list(color = series[[nm]]$col, width = 2.5),
          marker = list(size = ifelse(ref_row, 14, 9), color = ifelse(s$fb, "#FFFFFF", series[[nm]]$col),
                        line = list(color = ifelse(ref_row, COL$navy, series[[nm]]$col), width = ifelse(ref_row, 3, 2))),
          text = sprintf("%s: %s%s", s$round, fmt_ind(s$r, id), ifelse(s$fb, " (unweighted)", "")),
          hoverinfo = "text"
        )
      }
      p |> plotly_style(xaxis = list(title = "", dtick = 1, tickformat = "d"),
                        yaxis = list(title = "", ticksuffix = if (is_pct(id)) "%" else "", rangemode = "tozero"))
    })

    output$table <- reactable::renderReactable({
      x <- area(); id <- input$indicator
      x <- x[order(x$round_id, decreasing = TRUE), ]
      r <- ind_value(x, id, input$estimate)
      t <- data.frame(
        Round = as.character(x$round),
        Value = paste0(fmt_ind(r$v, id), ifelse(r$fb, " *", "")),
        Change = vapply(x$round_id, function(k) change_tag(ind_compare(x, id, k, input$estimate), id, html = TRUE), "", USE.NAMES = FALSE),
        Households = fmt_int(x$households), id = x$round_id, stringsAsFactors = FALSE
      )
      rid <- ref()
      reactable::reactable(
        t, compact = TRUE, striped = TRUE, pagination = FALSE, sortable = FALSE, height = 400, class = "dark-table",
        rowClass = function(i) if (t$id[i] == rid) "row-current",
        columns = list(
          id = reactable::colDef(show = FALSE),
          Round = reactable::colDef(class = "cell-label", minWidth = 85),
          Value = reactable::colDef(align = "right"),
          Change = reactable::colDef(name = "Same-season change", html = TRUE, align = "right", minWidth = 115),
          Households = reactable::colDef(align = "right")
        )
      )
    })

    stacked <- function(x, parts, cols) {
      x <- x[order(x$round_id), ]
      lab <- factor(as.character(x$round), levels = as.character(x$round))
      p <- plotly::plot_ly()
      for (k in names(parts)) {
        s <- ind_value(x, parts[[k]], input$estimate)
        p <- plotly::add_bars(p, x = lab, y = s$v, name = k, marker = list(
          color = cols[[k]], line = list(color = "#ffffff", width = 0.5),
          pattern = list(shape = ifelse(s$fb, "/", ""), fillmode = "overlay", fgcolor = "rgba(255,255,255,0.55)", size = 7, solidity = 0.25)),
          text = ifelse(is.na(s$v), "", sprintf("%.0f", s$v)), textposition = "inside",
          insidetextfont = list(color = if (k %in% c("Phase 1", "Phase 2")) COL$ink else "#fff", size = 11),
          hovertemplate = paste0("%{x} · ", k, ": %{y:.1f}%", ifelse(s$fb, " (unweighted)", ""), "<extra></extra>"))
      }
      p |> plotly_style(barmode = "stack", xaxis = list(title = "", tickangle = -40),
                        yaxis = list(title = "", range = c(0, 100), ticksuffix = "%"))
    }
    output$fcs <- plotly::renderPlotly(stacked(area(), list(Poor = "fcs_poor", Borderline = "fcs_border", Acceptable = "fcs_accept"), as.list(FCS_COL)))
    output$rcsi <- plotly::renderPlotly(stacked(area(), list(`Phase 1` = "rcsi_p1", `Phase 2` = "rcsi_p2", `Phase 3+` = "rcsi_p3"), as.list(CH_COL)))
  })
}
