# Survey rounds: inventory, fieldwork calendar, weights and core QC.

rounds_ui <- function(id, d) {
  ns <- shiny::NS(id)
  htmltools::tagList(
    page_intro("Survey rounds",
               "Fourteen cross-sectional rounds: February (lean-season onset) and October (harvest). Households differ between rounds, so rounds are stacked, never linked."),
    bslib::layout_columns(
      col_widths = c(7, 5),
      bslib::card(
        full_screen = TRUE,
        bslib::card_header("Fieldwork calendar", class = "card-title-sm"),
        plotly::plotlyOutput(ns("calendar"), height = "380px"),
        bslib::card_footer(class = "small text-muted", "Bars span the 1st–99th percentile of interview dates, shown on a common within-season axis; colour = questionnaire generation.")
      ),
      bslib::card(
        full_screen = TRUE,
        bslib::card_header("Concepts available per round", class = "card-title-sm"),
        plotly::plotlyOutput(ns("concepts"), height = "380px"),
        bslib::card_footer(class = "small text-muted", "Out of the concepts in the crosswalk workbook.")
      )
    ),
    bslib::card(
      full_screen = TRUE,
      bslib::card_header("Round inventory and core checks", class = "card-title-sm"),
      reactable::reactableOutput(ns("inventory"))
    )
  )
}

rounds_server <- function(id, d) {
  shiny::moduleServer(id, function(input, output, session) {
    # Fieldwork windows on a within-season axis (all dates moved to the year 2000) so timing is comparable.
    output$calendar <- plotly::renderPlotly({
      to_ref <- function(x) as.Date(paste0("2000-", format(x, "%m-%d")))
      r <- d$rounds |> dplyr::mutate(
        start = to_ref(fieldwork_start), end = to_ref(fieldwork_end),
        days = as.numeric(fieldwork_end - fieldwork_start) + 1,
        hover = sprintf("<b>%s</b> · %s<br>%s → %s (%d days)<br>%s households", round, GEN_LABEL[as.character(generation)],
                        format(fieldwork_start, "%d %b %Y"), format(fieldwork_end, "%d %b %Y"), days, fmt_int(households)))
      panel <- function(rs, range, title, show_legend) {
        rs$lab <- factor(rs$round, levels = rev(rs$round))
        p <- plotly::plot_ly()
        for (g in sort(unique(rs$generation))) {
          rg <- rs[rs$generation == g, ]
          p <- plotly::add_segments(p, data = rg, x = ~start, xend = ~end, y = ~lab, yend = ~lab,
                                    name = GEN_LABEL[[as.character(g)]], legendgroup = as.character(g),
                                    showlegend = show_legend, line = list(width = 14, color = GEN_COL[[as.character(g)]]),
                                    text = ~hover, hoverinfo = "text")
        }
        plotly::layout(p, xaxis = list(type = "date", range = range, tickformat = "%d %b", title = title),
                       yaxis = list(title = ""))
      }
      feb <- panel(r[r$month == 2, ], as.Date(c("2000-01-12", "2000-04-02")), "February rounds", TRUE)
      oct <- panel(r[r$month == 10, ], as.Date(c("2000-09-28", "2000-11-18")), "October rounds", FALSE)
      plotly::subplot(feb, oct, nrows = 1, margin = 0.08, titleX = TRUE, titleY = FALSE) |>
        plotly_style(xaxis = list(tickformat = "%d %b", title = "February rounds"),
                     xaxis2 = list(tickformat = "%d %b", gridcolor = COL$grid),
                     yaxis2 = list(gridcolor = COL$grid), margin = list(b = 50))
    })

    output$concepts <- plotly::renderPlotly({
      x <- d$details |> dplyr::group_by(round) |>
        dplyr::summarise(n = sum(available), .groups = "drop") |>
        dplyr::left_join(dplyr::distinct(d$rounds, round, generation) |>
                           dplyr::mutate(round = factor(round, levels = d$round_levels)), by = "round")
      plotly::plot_ly(x, x = ~round, y = ~n, type = "bar",
                      marker = list(color = unname(GEN_COL[as.character(x$generation)])),
                      text = ~n, textposition = "outside", cliponaxis = FALSE,
                      hovertemplate = "%{x}: %{y} concepts<extra></extra>") |>
        plotly_style(legend = FALSE, xaxis = list(title = "", tickangle = -40),
                     yaxis = list(title = "", range = c(0, nrow(d$concepts) + 8)))
    })

    output$inventory <- reactable::renderReactable({
      q <- d$qc_core |> dplyr::select(round_id, regions, date_outside_window, date_missing, admin1_missing, weight_sum)
      x <- d$rounds |>
        dplyr::left_join(q, by = "round_id") |>
        dplyr::transmute(round, generation, households, variables, file = file_label,
                         fieldwork = paste(format(fieldwork_start, "%d %b"), "–", format(fieldwork_end, "%d %b %Y")),
                         regions, date_outside_window, weight_status, weight_sum)
      reactable::reactable(
        x, compact = TRUE, striped = TRUE, highlight = TRUE, pagination = FALSE,
        columns = list(
          round = reactable::colDef(minWidth = 85, style = list(fontWeight = 600)),
          generation = reactable::colDef(name = "gen", minWidth = 55, align = "center",
                                         cell = function(v) pill(v, GEN_COL[[as.character(v)]])),
          households = reactable::colDef(format = reactable::colFormat(separators = TRUE), minWidth = 95),
          variables = reactable::colDef(name = "variables in file", format = reactable::colFormat(separators = TRUE), minWidth = 95),
          file = reactable::colDef(minWidth = 270, style = list(fontFamily = "Consolas, monospace", fontSize = "0.8em")),
          fieldwork = reactable::colDef(minWidth = 160),
          regions = reactable::colDef(minWidth = 70, align = "center"),
          date_outside_window = reactable::colDef(name = "dates outside window", minWidth = 95, align = "center"),
          weight_status = reactable::colDef(name = "weight", minWidth = 260, html = TRUE, cell = function(v) {
            ok <- v == "Ponderation OK"
            icon <- if (ok) bsicons::bs_icon("check-circle-fill", class = "text-success")
                    else bsicons::bs_icon("exclamation-triangle-fill", class = "text-warning")
            paste(as.character(icon), htmltools::htmlEscape(v))
          }),
          weight_sum = reactable::colDef(name = "sum of weights", minWidth = 110,
                                         format = reactable::colFormat(separators = TRUE, digits = 0))
        )
      )
    })
  })
}
