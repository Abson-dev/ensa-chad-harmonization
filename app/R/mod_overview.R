overview_ui <- function(id, d) {
  ns <- shiny::NS(id)
  n_hh <- sum(d$rounds$households, na.rm = TRUE)
  n_dom_done <- length(unique(d$rules$domain))
  first <- d$rounds$round[1]; last <- d$rounds$round[nrow(d$rounds)]

  htmltools::tagList(
    htmltools::div(
      class = "hero",
      htmltools::div(class = "hero-kicker", "ENSA Chad · Enquête Nationale de Sécurité Alimentaire"),
      htmltools::h1("Harmonising 14 survey rounds into one comparable dataset"),
      htmltools::p(sprintf(
        "From %s to %s, three questionnaire generations used different variable names, codes and modules. This app documents how every concept was mapped, recomputed and validated so that results can be compared across rounds.",
        first, last))
    ),
    bslib::layout_column_wrap(
      width = "200px", fill = FALSE, class = "kpis",
      bslib::value_box("Survey rounds", nrow(d$rounds), paste(first, "–", last),
                       showcase = bsicons::bs_icon("calendar3"), theme = "primary"),
      bslib::value_box("Households", fmt_int(n_hh), "household interviews",
                       showcase = bsicons::bs_icon("people-fill"), theme = "secondary"),
      bslib::value_box("Source variables", fmt_int(FACTS$distinct_vars),
                       sprintf("distinct names; only %d shared by all rounds", FACTS$shared_vars),
                       showcase = bsicons::bs_icon("table"), theme = bslib::value_box_theme(bg = "#FDF3E7", fg = "#7A4A12")),
      bslib::value_box("Concepts mapped", nrow(d$concepts), "in the crosswalk workbook",
                       showcase = bsicons::bs_icon("diagram-3"), theme = bslib::value_box_theme(bg = "#E8F4F4", fg = COL$teal)),
      bslib::value_box("Domains harmonised", paste0(n_dom_done, " / 8"), "core, FCS, rCSI · more planned",
                       showcase = bsicons::bs_icon("check2-circle"), theme = bslib::value_box_theme(bg = "#EAF5EE", fg = "#1E6B41"))
    ),
    bslib::layout_columns(
      col_widths = c(7, 5),
      bslib::card(
        full_screen = TRUE,
        bslib::card_header("Households interviewed per round", class = "card-title-sm"),
        plotly::plotlyOutput(ns("hh_plot"), height = "330px"),
        bslib::card_footer(class = "small text-muted",
                           "Colour = questionnaire generation. Larger 2024 samples include refugee and returnee strata.")
      ),
      bslib::card(
        bslib::card_header("Three questionnaire generations", class = "card-title-sm"),
        generations_list(d)
      )
    ),
    bslib::card(
      bslib::card_header("The approach in four steps", class = "card-title-sm"),
      htmltools::div(
        class = "steps",
        step_box(1, "search", "Inventory & crosswalk",
                 sprintf("Scanned the metadata of all 14 SPSS files and mapped %d concepts across rounds, by question content rather than variable name.", nrow(d$concepts))),
        step_box(2, "sliders", "Rules as configuration",
                 sprintf("Encoded every mapping as one explicit rule (%d rules for the domains done), including documented 'not available' cases.", nrow(d$rules))),
        step_box(3, "calculator", "Recompute indicators",
                 "Rebuilt FCS and rCSI from the item answers with the WFP formulas, identically for every round."),
        step_box(4, "patch-check", "Validate & document",
                 "Compared with the original analysts' scores, ran unit tests, and recorded hashes of every input and output.")
      )
    )
  )
}

generations_list <- function(d) {
  g <- d$rounds |>
    dplyr::group_by(generation) |>
    dplyr::summarise(first = dplyr::first(round), last = dplyr::last(round), n = dplyr::n(),
                     hh = sum(households, na.rm = TRUE), .groups = "drop")
  desc <- c("1" = "French variable names (jour_conso_*, Ponderation, sexe…). Few raw module items; many pre-computed scores.",
            "2" = "Hybrid: WFP module items (FCSStap, rCSI*, LhCSI*) next to French names; CH classifications; GPS.",
            "3" = "WFP standard codebook (HHHSex, HHSize*, Lcs*, HHExp*). Refugee and returnee strata from 2024.")
  htmltools::div(
    class = "gen-list",
    lapply(seq_len(nrow(g)), function(i) {
      k <- as.character(g$generation[i])
      htmltools::div(
        class = "gen-item", style = sprintf("border-left-color:%s", GEN_COL[[k]]),
        htmltools::div(class = "gen-head", htmltools::strong(GEN_LABEL[[k]]),
                       htmltools::span(class = "text-muted small", sprintf("%s – %s · %d rounds · %s HH",
                                                                         g$first[i], g$last[i], g$n[i], fmt_int(g$hh[i])))),
        htmltools::div(class = "small", desc[[k]])
      )
    })
  )
}

step_box <- function(n, icon, title, text) {
  htmltools::div(
    class = "step",
    htmltools::div(class = "step-num", n),
    htmltools::div(class = "step-icon", bsicons::bs_icon(icon, size = "1.4em")),
    htmltools::h5(title), htmltools::p(class = "small", text)
  )
}

overview_server <- function(id, d) {
  shiny::moduleServer(id, function(input, output, session) {
    output$hh_plot <- plotly::renderPlotly({
      r <- d$rounds |> dplyr::mutate(gen = factor(GEN_LABEL[as.character(generation)], levels = GEN_LABEL),
                                     round = factor(round, levels = d$round_levels))
      plotly::plot_ly(r, x = ~round, y = ~households, color = ~gen, colors = unname(GEN_COL),
                      type = "bar", marker = list(line = list(width = 0)),
                      text = ~fmt_int(households), textposition = "outside", cliponaxis = FALSE,
                      hovertemplate = paste0("<b>%{x}</b><br>%{y:,} households<br>", r$weight_status, "<extra></extra>")) |>
        plotly_style(xaxis = list(title = "", tickangle = -40),
                     yaxis = list(title = "", tickformat = ",", range = c(0, max(r$households, na.rm = TRUE) * 1.15)),
                     bargap = 0.25)
    })
  })
}
