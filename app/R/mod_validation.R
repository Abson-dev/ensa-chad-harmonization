# Validation: recomputed indicators vs the scores pre-computed by the original analysts.

# One row per indicator × round: agreement of the recomputed value with the analysts' own variable.
agreement_long <- function(d) {
  one <- function(x, ind) dplyr::transmute(x, round, indicator = ind, agree = vs_orig_agree_pct, n = vs_orig_n)
  x <- dplyr::bind_rows(one(d$qc_fcs, "FCS"), one(d$qc_rcsi, "rCSI"), one(d$qc_lcs, "LCS max category"),
                        one(d$qc_hhs, "HHS"), one(d$qc_hdds, "HDDS"), one(d$qc_exp, "Food share"))
  dplyr::mutate(x, indicator = factor(indicator, levels = unique(indicator)))
}

validation_ui <- function(id, d) {
  ns <- shiny::NS(id)
  f <- d$qc_fcs
  a <- agreement_long(d) |> dplyr::filter(!is.na(agree))
  n_rev <- sum(f$vs_orig_cat28_agree_if_reversed_pct > 99, na.rm = TRUE)
  htmltools::tagList(
    page_intro("Validation",
               "Every indicator is recomputed from the item answers, then compared with the value the original analysts computed in each round (scores: within ±0.5 points; categories: same category; food share: within 0.5 points)."),
    bslib::layout_column_wrap(
      width = "220px", fill = FALSE,
      bslib::value_box("Identical to the analysts", sprintf("%d / %d", sum(a$agree >= 99.5), nrow(a)),
                       "indicator × round comparisons with ≥ 99.5% agreement",
                       showcase = bsicons::bs_icon("bullseye"), theme = bslib::value_box_theme(bg = "#EAF5EE", fg = "#1E6B41")),
      bslib::value_box("Indicators checked", nlevels(a$indicator), paste(levels(a$indicator), collapse = " · "),
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
        bslib::card_header("Agreement with the original analysts' variables", class = "card-title-sm"),
        plotly::plotlyOutput(ns("agree"), height = "360px"),
        bslib::card_footer(class = "small text-muted",
                           "Blank: no pre-computed variable in that round. Below 100%: the original variable used another item set or definition (LCS in several rounds, HDDS sub-groups in 2020–2022); see Data issues.")
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
      x <- agreement_long(d) |>
        dplyr::mutate(label = ifelse(is.na(agree), "", ifelse(agree >= 99.95, "100", formatC(agree, format = "f", digits = 0))),
                      hover = ifelse(is.na(agree), sprintf("%s · %s<br>no original variable", indicator, round),
                                     sprintf("%s · %s<br>Agreement: %s<br>Households compared: %s",
                                             indicator, round, fmt_pct(agree, 2), fmt_int(n))))
      plotly::plot_ly(x, x = ~round, y = ~indicator, z = ~agree, type = "heatmap", zmin = 50, zmax = 100,
                      colorscale = list(c(0, "#B83227"), c(0.6, "#F2C14E"), c(0.9, "#9BD0A9"), c(1, "#1E6B41")),
                      xgap = 2, ygap = 2, text = ~hover, hoverinfo = "text",
                      colorbar = list(title = "", ticksuffix = "%", len = 0.8, thickness = 10)) |>
        plotly::add_annotations(x = ~round, y = ~indicator, text = ~label, showarrow = FALSE,
                                font = list(size = 11, color = ifelse(!is.na(x$agree) & x$agree > 90, "#ffffff", COL$ink))) |>
        plotly_style(xaxis = list(title = "", tickangle = -40),
                     yaxis = list(title = "", autorange = "reversed"))
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
        dplyr::left_join(d$qc_lcs |> dplyr::select(round, lcs_agree = vs_orig_agree_pct), by = "round") |>
        dplyr::left_join(d$qc_hhs |> dplyr::select(round, hhs_agree = vs_orig_agree_pct), by = "round") |>
        dplyr::left_join(d$qc_hdds |> dplyr::select(round, hdds_agree = vs_orig_agree_pct), by = "round") |>
        dplyr::left_join(d$qc_exp |> dplyr::select(round, exp_agree = vs_orig_agree_pct), by = "round") |>
        dplyr::mutate(round = as.character(round))
      pct <- function(name) reactable::colDef(name = name, minWidth = 95, align = "right", cell = function(v) fmt_pct(v, 2))
      reactable::reactable(
        x, compact = TRUE, striped = TRUE, pagination = FALSE,
        columnGroups = list(
          reactable::colGroup("Food Consumption Score", c("fcs_complete_pct", "fcs_items_invalid", "fcs_agree")),
          reactable::colGroup("Reduced Coping Strategies Index", c("rcsi_complete_pct", "rcsi_items_invalid", "mealadult_imputed", "rcsi_agree")),
          reactable::colGroup("Agreement with original", c("lcs_agree", "hhs_agree", "hdds_agree", "exp_agree"))
        ),
        columns = list(
          round = reactable::colDef(minWidth = 85, style = list(fontWeight = 600)),
          households = reactable::colDef(format = reactable::colFormat(separators = TRUE)),
          fcs_complete_pct = pct("complete"), fcs_items_invalid = reactable::colDef(name = "invalid items", align = "right"),
          fcs_agree = pct("agree w/ original"),
          rcsi_complete_pct = pct("complete"), rcsi_items_invalid = reactable::colDef(name = "invalid items", align = "right"),
          mealadult_imputed = reactable::colDef(name = "skip → 0 (no children)", minWidth = 120, align = "right"),
          rcsi_agree = pct("agree w/ original"),
          lcs_agree = pct("LCS"), hhs_agree = pct("HHS"), hdds_agree = pct("HDDS"), exp_agree = pct("food share")
        )
      )
    })
  })
}
