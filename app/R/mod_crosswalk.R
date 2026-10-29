# Crosswalk explorer: the ENSA_Chad_crosswalk_2018-2025.xlsx workbook, made interactive.

cov_fill <- function(v) {
  dplyr::case_when(is.na(v) ~ "#F1F3F5", v == 0 ~ "#F8D7D3", v < 95 ~ "#FFF1CC", TRUE ~ "#E3F1E6")
}

crosswalk_ui <- function(id, d) {
  ns <- shiny::NS(id)
  doms <- levels(d$concepts$domain)
  htmltools::tagList(
    page_intro("Crosswalk explorer",
               sprintf("Where each of the %d harmonised concepts lives in each of the 14 rounds: source variable, coverage, storage type and value labels. Click any concept to see its full profile.",
                       nrow(d$concepts))),
    bslib::layout_sidebar(
      fillable = FALSE,
      sidebar = bslib::sidebar(
        width = 290, open = "desktop",
        shinyWidgets::pickerInput(ns("domains"), "Domains", choices = doms, selected = doms, multiple = TRUE,
                                  options = shinyWidgets::pickerOptions(actionsBox = TRUE, selectedTextFormat = "count > 3",
                                                                        countSelectedText = "{0} domains")),
        shiny::selectizeInput(ns("jump"), "Find a concept",
                              choices = c("Type to search…" = "", stats::setNames(d$concepts$harm,
                                                                                    paste0(d$concepts$concept, " (", d$concepts$harm, ")")))),
        shiny::checkboxInput(ns("gaps_only"), "Only concepts missing in some rounds", FALSE),
        htmltools::hr(),
        htmltools::div(class = "legend-block",
                       htmltools::strong("Coverage"),
                       legend_row("#E3F1E6", "found, ≥ 95% non-missing"),
                       legend_row("#FFF1CC", "found, 1–95% (often skip pattern)"),
                       legend_row("#F8D7D3", "variable exists but empty"),
                       legend_row("#F1F3F5", "no equivalent in that round")),
        htmltools::hr(),
        shiny::downloadButton(ns("dl_xlsx"), "Crosswalk workbook (.xlsx)", class = "btn-sm btn-outline-primary w-100 mb-2"),
        shiny::downloadButton(ns("dl_csv"), "Filtered details (.csv)", class = "btn-sm btn-outline-secondary w-100")
      ),
      bslib::navset_card_underline(
        full_screen = TRUE,
        bslib::nav_panel("Coverage matrix", shiny::uiOutput(ns("matrix_ui"), style = "width:100%")),
        bslib::nav_panel("Crosswalk table", reactable::reactableOutput(ns("table"))),
        bslib::nav_panel("All variable details", reactable::reactableOutput(ns("details")))
      ),
      shiny::uiOutput(ns("concept_card"))
    )
  )
}

legend_row <- function(col, txt) {
  htmltools::div(class = "legend-row", htmltools::span(class = "swatch", style = sprintf("background:%s", col)), txt)
}

crosswalk_server <- function(id, d) {
  shiny::moduleServer(id, function(input, output, session) {
    ns <- session$ns
    selected <- shiny::reactiveVal("FCSStap")

    concepts_f <- shiny::reactive({
      x <- d$concepts[d$concepts$domain %in% input$domains, ]
      if (isTRUE(input$gaps_only)) x <- x[x$rounds_available < 14, ]
      x[order(x$order), ]
    })
    details_f <- shiny::reactive(d$details[d$details$harm %in% concepts_f()$harm, ])

    shiny::observeEvent(input$jump, if (nzchar(input$jump)) selected(input$jump), ignoreInit = TRUE)

    # ---- coverage matrix ----
    output$matrix_ui <- shiny::renderUI({
      plotly::plotlyOutput(ns("matrix"), width = "100%", height = paste0(190 + 19 * max(nrow(concepts_f()), 1), "px"))
    })
    output$matrix <- plotly::renderPlotly({
      cf <- concepts_f()
      shiny::validate(shiny::need(nrow(cf) > 0, "No concept matches the filters."))
      lab <- paste0(cf$concept, "  ·  ", cf$harm)
      det <- details_f()
      z <- matrix(NA_real_, nrow(cf), length(d$round_levels), dimnames = list(cf$harm, d$round_levels))
      txt <- z
      for (i in seq_len(nrow(det))) {
        r <- det[i, ]
        if (r$available) z[r$harm, as.character(r$round)] <- r$coverage
        txt[r$harm, as.character(r$round)] <- sprintf(
          "<b>%s</b><br>%s<br>Source: <b>%s</b><br>Coverage: %s<br>Type: %s",
          r$concept, r$round, r$source, if (r$available) fmt_pct(r$coverage) else "–",
          if (is.na(r$type) || r$type == "") "–" else r$type)
      }
      txt[is.na(txt)] <- ""
      # unname(): named numbers would serialise to JSON objects, which plotly rejects.
      counts <- table(droplevels(cf$domain))
      bounds <- unname(cumsum(as.integer(counts)))
      mids <- stats::setNames(bounds - as.integer(counts) / 2, names(counts))
      shapes <- lapply(head(bounds, -1), function(b) list(
        type = "line", xref = "paper", x0 = -0.01, x1 = 1, y0 = b - 0.5, y1 = b - 0.5,
        line = list(color = COL$navy, width = 1.5)))
      ann <- lapply(seq_along(mids), function(k) list(
        xref = "paper", x = 1.01, y = mids[[k]] - 0.5, xanchor = "left", showarrow = FALSE,
        text = sprintf("<b>%s</b>", names(mids)[k]), font = list(size = 11, color = COL$navy)))
      plotly::plot_ly(
        x = d$round_levels, y = lab, z = z, type = "heatmap", source = ns("cov"),
        text = txt, hovertemplate = "%{text}<extra></extra>", xgap = 2, ygap = 2,
        colorscale = COVERAGE_SCALE, zmin = 0, zmax = 100,
        colorbar = list(title = list(text = "% non-missing", side = "top"), orientation = "h", thickness = 10,
                        len = 0.35, x = 0.5, xanchor = "center", y = 0, yanchor = "top", ypad = 8,
                        ticksuffix = "%")
      ) |>
        plotly_style(legend = FALSE, plot_bgcolor = "#F1F3F5",
                     xaxis = list(side = "top", tickangle = -40, showgrid = FALSE),
                     yaxis = list(autorange = "reversed", showgrid = FALSE, tickfont = list(size = 11)),
                     shapes = shapes, annotations = ann, margin = list(l = 10, r = 175, t = 70, b = 70)) |>
        plotly::event_register("plotly_click")
    })

    shiny::observe({
      ev <- plotly::event_data("plotly_click", source = ns("cov"))
      shiny::req(ev)
      harm <- sub(".*  ·  ", "", ev$y)
      if (harm %in% d$concepts$harm) selected(harm)
    })

    # ---- crosswalk table (workbook layout) ----
    output$table <- reactable::renderReactable({
      cf <- concepts_f()
      det <- details_f()
      src <- tidyr::pivot_wider(det[, c("harm", "round", "source")], names_from = round, values_from = source)
      cov <- tidyr::pivot_wider(det[, c("harm", "round", "coverage", "available")] |>
                                  dplyr::mutate(coverage = ifelse(available, coverage, NA)) |>
                                  dplyr::select(-available), names_from = round, values_from = coverage)
      tbl <- cf[, c("domain", "concept", "harm", "rounds_available")] |>
        dplyr::mutate(domain = as.character(domain)) |>
        dplyr::left_join(src, by = "harm")
      covm <- as.data.frame(cov)[match(tbl$harm, cov$harm), ]
      round_cols <- stats::setNames(lapply(d$round_levels, function(rl) reactable::colDef(
        name = rl, minWidth = 135,
        cell = function(v) if (is.na(v) || v == "(not available)") "—" else v,
        style = function(v, i) {
          cv <- covm[[rl]][i]
          list(background = cov_fill(cv), fontFamily = "Consolas, monospace", fontSize = "0.78em",
               color = if (is.na(cv)) "#9AA5B1" else COL$ink)
        })), d$round_levels)
      reactable::reactable(
        tbl, groupBy = "domain", defaultExpanded = TRUE, compact = TRUE, bordered = TRUE,
        highlight = TRUE, pagination = FALSE, height = 640, searchable = TRUE,
        selection = "single", onClick = "select",
        rowStyle = list(cursor = "pointer"),
        theme = reactable::reactableTheme(headerStyle = list(background = COL$navy, color = "#fff"),
                                          groupHeaderStyle = list(background = COL$navy, color = "#fff")),
        columns = c(list(
          domain = reactable::colDef(name = "Domain", minWidth = 150, sticky = "left"),
          concept = reactable::colDef(name = "Concept", minWidth = 210, sticky = "left",
                                      style = list(fontWeight = 600)),
          harm = reactable::colDef(name = "Harmonised", minWidth = 130,
                                   style = list(fontFamily = "Consolas, monospace", fontSize = "0.82em")),
          rounds_available = reactable::colDef(name = "Rounds", minWidth = 70, align = "center",
                                               cell = function(v) paste0(v, "/14"))
        ), round_cols)
      )
    })

    shiny::observe({
      i <- reactable::getReactableState("table", "selected")
      shiny::req(i)
      selected(concepts_f()$harm[i])
    })

    # ---- long details ----
    output$details <- reactable::renderReactable({
      x <- details_f() |>
        dplyr::transmute(domain = as.character(domain), concept, harm, round = as.character(round), source, type,
                         coverage = ifelse(available, coverage, NA), range, label, value_labels, alternates)
      reactable::reactable(
        x, filterable = TRUE, searchable = TRUE, compact = TRUE, striped = TRUE, defaultPageSize = 15,
        columns = list(
          domain = reactable::colDef(minWidth = 120), concept = reactable::colDef(minWidth = 170),
          harm = reactable::colDef(name = "harmonised", minWidth = 110),
          round = reactable::colDef(minWidth = 85),
          source = reactable::colDef(minWidth = 170, style = list(fontFamily = "Consolas, monospace", fontSize = "0.82em")),
          coverage = reactable::colDef(name = "% non-missing", minWidth = 110, cell = coverage_bar),
          label = reactable::colDef(name = "SPSS label", minWidth = 240),
          value_labels = reactable::colDef(name = "value labels", minWidth = 220),
          alternates = reactable::colDef(name = "other candidates", minWidth = 200)
        )
      )
    })

    # ---- concept profile ----
    output$concept_card <- shiny::renderUI({
      h <- selected()
      shiny::req(h)
      cc <- d$concepts[d$concepts$harm == h, ]
      bslib::card(
        class = "concept-card",
        bslib::card_header(
          class = "d-flex flex-wrap gap-2 align-items-center",
          htmltools::span(class = "h5 m-0", cc$concept),
          htmltools::code(cc$harm), pill(as.character(cc$domain), COL$navy),
          pill(sprintf("%d / 14 rounds", cc$rounds_available),
               if (cc$rounds_available == 14) "#2E8B57" else "#E58E26")
        ),
        if (!is.na(cc$notes)) callout(cc$notes, type = if (grepl("SLOT SWAP|SEVERITY|EMPTY|NO weight|different scale", cc$notes)) "warning" else "info"),
        reactable::reactableOutput(ns("concept_rounds"))
      )
    })

    output$concept_rounds <- reactable::renderReactable({
      x <- d$details[d$details$harm == selected(), ] |>
        dplyr::arrange(round) |>
        dplyr::mutate(gen = d$rounds$generation[match(round_id, d$rounds$round_id)]) |>
        dplyr::transmute(round = as.character(round), gen, source, coverage = ifelse(available, coverage, NA),
                         type, range, label, value_labels, alternates)
      reactable::reactable(
        x, compact = TRUE, pagination = FALSE, striped = TRUE,
        rowStyle = function(i) if (x$source[i] == "(not available)") list(color = "#9AA5B1"),
        columns = list(
          round = reactable::colDef(minWidth = 85, style = list(fontWeight = 600)),
          gen = reactable::colDef(name = "gen", minWidth = 55, align = "center",
                                  cell = function(v) pill(v, GEN_COL[[as.character(v)]])),
          source = reactable::colDef(minWidth = 200, style = list(fontFamily = "Consolas, monospace", fontSize = "0.82em")),
          coverage = reactable::colDef(name = "% non-missing", minWidth = 120, cell = coverage_bar),
          type = reactable::colDef(minWidth = 100), range = reactable::colDef(minWidth = 90),
          label = reactable::colDef(name = "SPSS label", minWidth = 260, style = list(fontSize = "0.85em")),
          value_labels = reactable::colDef(name = "value labels", minWidth = 220, style = list(fontSize = "0.82em")),
          alternates = reactable::colDef(name = "other candidates", minWidth = 180, style = list(fontSize = "0.82em"))
        )
      )
    })

    # ---- downloads ----
    output$dl_xlsx <- shiny::downloadHandler(
      filename = function() "ENSA_Chad_crosswalk_2018-2025.xlsx",
      content = function(file) file.copy(d$xlsx_path, file)
    )
    output$dl_csv <- shiny::downloadHandler(
      filename = function() "ENSA_Chad_crosswalk_details.csv",
      content = function(file) readr::write_csv(dplyr::select(details_f(), -round_code), file, na = "")
    )
  })
}

coverage_bar <- function(v) {
  if (is.na(v)) return("—")
  htmltools::div(class = "cov-bar",
                 htmltools::div(class = "cov-fill", style = sprintf("width:%s%%;background:%s", v,
                                                                     if (v >= 95) "#2E8B57" else if (v > 0) "#E5A823" else "#C8553D")),
                 htmltools::span(fmt_pct(v, 0)))
}
