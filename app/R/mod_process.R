# Harmonisation process: pipeline diagram, domain status and the rule set behind each domain.

DOMAIN_DETAIL <- c(
  core = "Keys (round_id, hh_id), interview date with fieldwork-window check, standardised regions, sampling weight and per-round normalised weight.",
  fcs = "9 food groups → Food Consumption Score (WFP weights) → groups at 21/35 and 28/42 thresholds.",
  rcsi = "5 strategies → reduced Coping Strategies Index → Cadre Harmonisé phase; Oct 2024 skip pattern resolved by rule.",
  lcs = "14 livelihood strategies on three answer scales → maximum category, round-specific and comparable (7 common strategies, coping for food).",
  hhs = "3 hunger experiences × frequency (from Oct 2019) → Household Hunger Scale, WFP category and IPC phase.",
  hdds = "12 food groups eaten in the last 24 h → dietary diversity score and Cadre Harmonisé phase; Oct 2024 skips resolved from the FCS module.",
  exp = "Analysts' monthly food and non-food aggregates → total expenditure and food share (CARI); Oct 2024 not reproducible, left missing.",
  demo = "Household head (sex, age, education, marital status), household size, income source, population group; per-round code lists recoded.")

PIPELINE_NODES <- function(d) {
  n_rules <- nrow(d$rules)
  dom <- names(DOMAIN_DETAIL)
  nd <- length(dom)
  data.frame(
    id = seq_len(nd + 9),
    label = c("14 SPSS files\n(raw .sav)", "Metadata scan", "Crosswalk workbook",
              "Configuration", "Harmonisation engine", dom,
              "Domain files\n(CSV + SAV)", "QC tables", "Provenance\nmanifest", "Unit tests"),
    group = c("input", "step", "doc", "config", "step", rep("domain", nd),
              "output", "output", "output", "check"),
    level = c(1, 2, 3, 3, 4, rep(5, nd), 6, 6, 6, 4),
    detail = c(
      sprintf("%s households in 14 rounds, Oct 2018 – Oct 2025. Raw files are read in place and never modified.",
              fmt_int(sum(d$rounds$households, na.rm = TRUE))),
      sprintf("Variable names, labels, value labels and coverage read from every file: %s distinct variable names, only %d present in all rounds (KoBo system fields).",
              fmt_int(FACTS$distinct_vars), FACTS$shared_vars),
      sprintf("%d concepts × 14 rounds mapped by question content, with coverage, storage type, value labels and data issues. This is the reference for all domains.",
              nrow(d$concepts)),
      sprintf("crosswalk.csv (%d rules: one per domain × target × round), rounds.csv, admin1_names.csv (32 spellings → 23 regions) and settings.toml (weights, thresholds). All decisions live here, not in code.", n_rules),
      "Reads only the columns needed, applies one method per rule (copy, copy_label, sum, sum_cap7, any, max_or_last, missing) and stops on any gap, unknown region spelling or duplicate ID.",
      unname(DOMAIN_DETAIL),
      "One file per domain, joinable on round_id + hh_id, with variable and value labels in SPSS format.",
      "Per round: completeness, invalid values, weighted indicators and agreement with the original analysts' scores.",
      "SHA-256 of every input, configuration file and output, plus software versions. Reruns give byte-identical CSV outputs.",
      sprintf("%d tests: configuration completeness, scoring formulas, thresholds, date and text conversions, region lookup.", FACTS$tests)
    ),
    stringsAsFactors = FALSE
  )
}

process_ui <- function(id, d) {
  ns <- shiny::NS(id)
  htmltools::tagList(
    page_intro("Harmonisation process",
               "From raw survey files to validated, documented domain datasets. Click a step in the diagram for details."),
    bslib::layout_columns(
      col_widths = c(8, 4),
      bslib::card(
        full_screen = TRUE,
        bslib::card_header("Pipeline", class = "card-title-sm"),
        visNetwork::visNetworkOutput(ns("flow"), height = "540px")
      ),
      bslib::card(
        bslib::card_header("Step details", class = "card-title-sm"),
        shiny::uiOutput(ns("node_detail"))
      )
    ),
    bslib::card(
      bslib::card_header("Domains", class = "card-title-sm"),
      shiny::uiOutput(ns("domains"))
    ),
    bslib::layout_columns(
      col_widths = c(5, 7),
      bslib::card(
        full_screen = TRUE,
        bslib::card_header("How each rule builds its target", class = "card-title-sm"),
        plotly::plotlyOutput(ns("methods"), height = "380px"),
        bslib::card_footer(class = "small text-muted",
                           "copy = take source as is · copy_label = take value label · sum / sum_cap7 = combine items (cap at 7 days) · any = eaten in any sub-group · max_or_last = sub-groups, else main group · missing = documented as not available")
      ),
      bslib::card(
        full_screen = TRUE,
        bslib::card_header(
          class = "d-flex justify-content-between align-items-center card-title-sm",
          "Configuration rules (config/crosswalk.csv)",
          shiny::selectInput(ns("rule_domain"), NULL, choices = c("All domains" = "", sort(unique(d$rules$domain))),
                             width = "180px")
        ),
        reactable::reactableOutput(ns("rules"))
      )
    )
  )
}

process_server <- function(id, d) {
  shiny::moduleServer(id, function(input, output, session) {
    nodes <- PIPELINE_NODES(d)

    output$flow <- visNetwork::renderVisNetwork({
      vn <- nodes |>
        dplyr::mutate(title = detail, shape = "box",
                      font.color = ifelse(group %in% c("input", "step"), "#ffffff", COL$ink),
                      font.size = 16, margin = 12)
      dom_id <- nodes$id[nodes$group == "domain"]
      out_id <- nodes$id[nodes$group == "output"]
      test_id <- nodes$id[nodes$group == "check"]
      edges <- data.frame(from = c(1, 2, 3, 4, rep(5, length(dom_id)), dom_id, dom_id, 5, test_id),
                          to = c(2, 3, 4, 5, dom_id, rep(out_id[1], length(dom_id)),
                                 rep(out_id[2], length(dom_id)), out_id[3], 5))
      edges$dashes <- edges$from == test_id
      visNetwork::visNetwork(vn, edges) |>
        visNetwork::visGroups(groupname = "input", color = list(background = COL$navy, border = COL$navy)) |>
        visNetwork::visGroups(groupname = "step", color = list(background = COL$teal, border = COL$teal)) |>
        visNetwork::visGroups(groupname = "doc", color = list(background = "#FDF3E7", border = GEN_COL[["1"]])) |>
        visNetwork::visGroups(groupname = "config", color = list(background = "#EEF2FF", border = "#6C5CE7")) |>
        visNetwork::visGroups(groupname = "domain", color = list(background = "#EAF5EE", border = "#2E8B57")) |>
        visNetwork::visGroups(groupname = "output", color = list(background = "#F1F3F5", border = "#6B7785")) |>
        visNetwork::visGroups(groupname = "check", color = list(background = "#FFF8E1", border = "#E58E26")) |>
        visNetwork::visEdges(arrows = "to", color = list(color = "#9AA5B1", highlight = COL$teal),
                             smooth = list(type = "cubicBezier", forceDirection = "horizontal")) |>
        visNetwork::visHierarchicalLayout(direction = "LR", levelSeparation = 175, nodeSpacing = 50) |>
        visNetwork::visOptions(highlightNearest = list(enabled = TRUE, degree = 1)) |>
        visNetwork::visInteraction(dragNodes = FALSE, zoomView = FALSE, navigationButtons = FALSE) |>
        visNetwork::visEvents(select = sprintf(
          "function(p){ Shiny.setInputValue('%s', p.nodes.length ? p.nodes[0] : null, {priority: 'event'}); }",
          session$ns("node")))
    })

    output$node_detail <- shiny::renderUI({
      i <- input$node
      if (is.null(i)) {
        return(htmltools::div(class = "text-muted",
                              bsicons::bs_icon("hand-index"), " Select a step in the diagram.",
                              htmltools::hr(), htmltools::p(class = "small", nodes$detail[5])))
      }
      n <- nodes[nodes$id == i, ]
      htmltools::div(htmltools::h4(gsub("\n", " ", n$label)), htmltools::p(n$detail))
    })

    output$domains <- shiny::renderUI({
      done <- c(core = "Keys, interview date, regions, sampling weight",
                fcs = "Food Consumption Score and groups",
                rcsi = "Reduced Coping Strategies Index and CH phase",
                lcs = "Livelihood coping: 14 strategies, max category (round-specific and comparable)",
                hhs = "Household Hunger Scale (from Oct 2019): score, WFP category, IPC phase",
                hdds = "Household Dietary Diversity Score (12 groups, 24 h) and CH phase",
                exp = "Monthly food / non-food / total expenditure, food share (CARI)",
                demo = "Household head (sex, age, education, marital status), household size, income, population group")
      planned <- character(0) # add planned domains here as c(name = "description")
      card <- function(k, txt, ok) {
        htmltools::div(class = paste("domain-card", if (ok) "done" else "planned"),
                       htmltools::div(class = "d-flex justify-content-between",
                                      htmltools::strong(k),
                                      if (ok) pill("done", "#2E8B57") else pill("planned", "#ADB5BD")),
                       htmltools::div(class = "small", txt))
      }
      htmltools::div(class = "domain-grid",
                     lapply(names(done), function(k) card(k, done[[k]], TRUE)),
                     lapply(names(planned), function(k) card(k, planned[[k]], FALSE)))
    })

    output$methods <- plotly::renderPlotly({
      m <- d$rules |> dplyr::count(domain, method) |>
        dplyr::mutate(method = factor(method, levels = names(METHOD_COL)))
      plotly::plot_ly(m, y = ~domain, x = ~n, color = ~method, colors = METHOD_COL, type = "bar",
                      orientation = "h",
                      hovertemplate = "%{y} · %{fullData.name}: %{x} rules<extra></extra>") |>
        plotly_style(barmode = "stack", xaxis = list(title = "Rules (target × round)"),
                     yaxis = list(title = "", categoryorder = "array",
                                  categoryarray = rev(intersect(names(DOMAIN_NAMES), unique(m$domain)))))
    })

    output$rules <- reactable::renderReactable({
      r <- d$rules
      if (nzchar(input$rule_domain %||% "")) r <- r[r$domain == input$rule_domain, ]
      r <- r |> dplyr::arrange(domain, target, round) |>
        dplyr::transmute(domain, target, round = as.character(round), method, sources, note)
      reactable::reactable(
        r, searchable = TRUE, filterable = TRUE, compact = TRUE, striped = TRUE, highlight = TRUE,
        defaultPageSize = 10, groupBy = c("target"),
        columns = list(
          domain = reactable::colDef(width = 70),
          target = reactable::colDef(width = 140),
          round = reactable::colDef(width = 85),
          method = reactable::colDef(width = 100, cell = function(v) pill(v, method_colour(v))),
          sources = reactable::colDef(minWidth = 170, style = list(fontFamily = "Consolas, monospace", fontSize = "0.82em")),
          note = reactable::colDef(minWidth = 220, style = list(fontSize = "0.82em"))
        )
      )
    })
  })
}
