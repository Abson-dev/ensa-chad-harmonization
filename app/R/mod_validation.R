# Validation: recomputed indicators vs the scores pre-computed by the original analysts.

validation_ui <- function(id, d) {
  ns <- shiny::NS(id)
  f <- d$qc_fcs; r <- d$qc_rcsi
  n_r100 <- sum(r$vs_orig_agree_pct == 100, na.rm = TRUE)
  n_rcmp <- sum(!is.na(r$vs_orig_agree_pct))
  fcs_min <- min(f$vs_orig_agree_pct, na.rm = TRUE)
  n_rev <- sum(f$vs_orig_cat28_agree_if_reversed_pct > 99, na.rm = TRUE)
  htmltools::tagList(
    page_intro("Validation",
               "Every indicator is recomputed from the item answers, then compared with the score the original analysts computed in each round (agreement = within ±0.5 points)."),
    bslib::layout_column_wrap(
      width = "220px", fill = FALSE,
      bslib::value_box("rCSI: identical", sprintf("%d / %d rounds", n_r100, n_rcmp), "100% of households agree",
                       showcase = bsicons::bs_icon("bullseye"), theme = bslib::value_box_theme(bg = "#EAF5EE", fg = "#1E6B41")),
      bslib::value_box("FCS: agreement", paste0("≥ ", formatC(fcs_min, format = "f", digits = 1), "%"),
                       sprintf("in all %d comparable rounds", sum(!is.na(f$vs_orig_agree_pct))),
                       showcase = bsicons::bs_icon("check2-all"), theme = bslib::value_box_theme(bg = "#E8F4F4", fg = COL$teal)),
      bslib::value_box("Reversed FCS groups", sprintf("%d rounds", n_rev), "original codes 1 = Acceptable … 3 = Poor",
                       showcase = bsicons::bs_icon("arrow-down-up"), theme = bslib::value_box_theme(bg = "#FDECEA", fg = "#8A2318")),
      bslib::value_box("Unit tests", FACTS$tests, "formulas, thresholds, config, conversions",
                       showcase = bsicons::bs_icon("clipboard-check"), theme = bslib::value_box_theme(bg = "#F1F3F5", fg = COL$navy))
    ),
    bslib::layout_columns(
      col_widths = c(6, 6),
      bslib::card(
        full_screen = TRUE,
        bslib::card_header("Score agreement with original analysts", class = "card-title-sm"),
        plotly::plotlyOutput(ns("agree"), height = "360px"),
        bslib::card_footer(class = "small text-muted",
                           "Missing points: no pre-computed score in that round (FCS: Oct 2023 – Oct 2025; rCSI: Oct 2024).")
      ),
      bslib::card(
        full_screen = TRUE,
        bslib::card_header("FCS groups (28/42): a reversed coding found", class = "card-title-sm"),
        plotly::plotlyOutput(ns("reversal"), height = "360px"),
        bslib::card_footer(class = "small text-muted",
                           "Agreement of recomputed groups with the original group variable, as coded and with codes reversed (4 − code).")
      )
    ),
    callout(type = "warning",
            htmltools::strong("Why this matters. "),
            "From Feb 2020 to Feb 2023 the original FCS group variable codes 'Poor' as 3 and 'Acceptable' as 1, the opposite of other rounds. ",
            sprintf("Pooling the original group variables would invert the trend for %d rounds. The harmonised files only use groups recomputed from the items.", n_rev)),
    bslib::card(
      full_screen = TRUE,
      bslib::card_header("Quality checks by round", class = "card-title-sm"),
      reactable::reactableOutput(ns("qc_table"))
    )
  )
}

validation_server <- function(id, d) {
  shiny::moduleServer(id, function(input, output, session) {
    output$agree <- plotly::renderPlotly({
      x <- dplyr::bind_rows(
        d$qc_fcs |> dplyr::transmute(round, indicator = "FCS", agree = vs_orig_agree_pct, corr = vs_orig_corr, n = vs_orig_n),
        d$qc_rcsi |> dplyr::transmute(round, indicator = "rCSI", agree = vs_orig_agree_pct, corr = vs_orig_corr, n = vs_orig_n)
      )
      plotly::plot_ly(x, x = ~round, y = ~agree, color = ~indicator, colors = c(FCS = COL$teal, rCSI = GEN_COL[["1"]]),
                      type = "scatter", mode = "lines+markers", marker = list(size = 9), line = list(width = 2),
                      text = ~sprintf("%s · %s<br>Agreement: %s<br>Correlation: %s<br>Households compared: %s",
                                      indicator, round, fmt_pct(agree, 2), ifelse(is.na(corr), "–", formatC(corr, digits = 4, format = "f")),
                                      fmt_int(n)),
                      hoverinfo = "text") |>
        plotly_style(xaxis = list(title = "", tickangle = -40),
                     yaxis = list(title = "% households within ±0.5", range = c(97, 100.4), ticksuffix = "%"))
    })

    output$reversal <- plotly::renderPlotly({
      x <- d$qc_fcs
      rev_rounds <- as.character(x$round[!is.na(x$vs_orig_cat28_agree_if_reversed_pct) & x$vs_orig_cat28_agree_if_reversed_pct > 99])
      plotly::plot_ly(x, x = ~round) |>
        plotly::add_bars(y = ~vs_orig_cat28_agree_pct, name = "as coded", marker = list(color = "#9AA5B1"),
                         hovertemplate = "%{x}: %{y:.1f}% as coded<extra></extra>") |>
        plotly::add_bars(y = ~vs_orig_cat28_agree_if_reversed_pct, name = "codes reversed", marker = list(color = "#B83227"),
                         hovertemplate = "%{x}: %{y:.1f}% if reversed<extra></extra>") |>
        plotly_style(barmode = "group", xaxis = list(title = "", tickangle = -40),
                     yaxis = list(title = "% agreement", range = c(0, 105), ticksuffix = "%"),
                     shapes = list(list(type = "rect", xref = "x", yref = "paper",
                                        x0 = match(rev_rounds[1], d$round_levels) - 1.5,
                                        x1 = match(rev_rounds[length(rev_rounds)], d$round_levels) - 0.5,
                                        y0 = 0, y1 = 1, fillcolor = "rgba(184,50,39,0.07)", line = list(width = 0))))
    })

    output$qc_table <- reactable::renderReactable({
      x <- d$qc_fcs |>
        dplyr::select(round, households, fcs_complete_pct, fcs_items_invalid = items_invalid, fcs_agree = vs_orig_agree_pct) |>
        dplyr::left_join(d$qc_rcsi |> dplyr::select(round, rcsi_complete_pct, rcsi_items_invalid = items_invalid,
                                                    mealadult_imputed, rcsi_agree = vs_orig_agree_pct), by = "round") |>
        dplyr::mutate(round = as.character(round))
      pct <- function(name) reactable::colDef(name = name, minWidth = 95, align = "right", cell = function(v) fmt_pct(v, 2))
      reactable::reactable(
        x, compact = TRUE, striped = TRUE, pagination = FALSE,
        columnGroups = list(
          reactable::colGroup("Food Consumption Score", c("fcs_complete_pct", "fcs_items_invalid", "fcs_agree")),
          reactable::colGroup("Reduced Coping Strategies Index", c("rcsi_complete_pct", "rcsi_items_invalid", "mealadult_imputed", "rcsi_agree"))
        ),
        columns = list(
          round = reactable::colDef(minWidth = 85, style = list(fontWeight = 600)),
          households = reactable::colDef(format = reactable::colFormat(separators = TRUE)),
          fcs_complete_pct = pct("complete"), fcs_items_invalid = reactable::colDef(name = "invalid items", align = "right"),
          fcs_agree = pct("agree w/ original"),
          rcsi_complete_pct = pct("complete"), rcsi_items_invalid = reactable::colDef(name = "invalid items", align = "right"),
          mealadult_imputed = reactable::colDef(name = "skip → 0 (no children)", minWidth = 120, align = "right"),
          rcsi_agree = pct("agree w/ original")
        )
      )
    })
  })
}
