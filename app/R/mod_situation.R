# Overview: the food security situation of the reference round, and what to check first.

situation_ui <- function(id, d) {
  ns <- shiny::NS(id)
  htmltools::tagList(
    page_intro("Overview", "National situation in the reference round, compared with the latest round of the same season.",
               "speedometer2", shiny::uiOutput(ns("chip"))),
    shiny::uiOutput(ns("kpis")),
    bslib::layout_columns(
      col_widths = c(4, 8),
      bslib::card(height = 470, bslib::card_header(bsicons::bs_icon("bell"), " Points of attention"),
                  bslib::card_body(shiny::uiOutput(ns("attention")))),
      bslib::card(height = 470, full_screen = TRUE, bslib::card_header("Indicators, latest rounds of the same season"),
                  bslib::card_body(padding = 0, reactable::reactableOutput(ns("table"))),
                  bslib::card_footer(class = "table-note",
                                     "* No usable weight in that round: unweighted. Change in percentage points (pts) or score points, without a significance test; unweighted when either round has no weight. Preliminary figures, not official ENSA results."))
    ),
    bslib::layout_columns(
      col_widths = c(4, 4, 4),
      bslib::card(bslib::card_header("Poor + borderline food consumption"), plotly::plotlyOutput(ns("g_fcs"), height = "230px")),
      bslib::card(bslib::card_header("rCSI phase 3+"), plotly::plotlyOutput(ns("g_rcsi"), height = "230px")),
      bslib::card(bslib::card_header("Crisis + emergency coping (comparable)"), plotly::plotlyOutput(ns("g_lcs"), height = "230px"))
    )
  )
}

# What a reader should know before using the figures of a round. Levels: serious, watch, info, ok.
attention_points <- function(d, rid) {
  out <- list()
  add <- function(level, title, detail) out[[length(out) + 1]] <<- list(level = level, title = title, detail = detail)
  nat <- d$ind_round
  r <- nat[nat$round_id == rid, ]

  if (!isTRUE(r$weighted_available)) {
    add("serious", "No sampling weight in this round",
        "All figures are unweighted, so they may not represent the population. Changes are computed on unweighted values for both rounds.")
  }
  cmp <- ind_compare(nat, "fcs_pb", rid)
  if (is.na(cmp$base_id)) {
    add("watch", "No earlier round of this season", "No same-season comparison is possible for this round.")
  } else {
    gen <- d$rounds$generation[match(c(rid, cmp$base_id), d$rounds$round_id)]
    if (gen[1] != gen[2]) {
      add("watch", sprintf("Questionnaire changed since %s", cmp$base_round),
          sprintf("Generation %d here, generation %d in the comparison round: harmonised, but read the change with care.", gen[1], gen[2]))
    }
  }
  missing_ind <- IND$short[IND$id %in% IND_MAIN & is.na(vapply(IND$id, function(id) ind_value(r, id)$v, 0))]
  if (length(missing_ind)) {
    add("watch", "Not available in this round", paste(missing_ind, collapse = ", "))
  }
  a <- agreement_long(d)
  a <- a[as.character(a$round) == as.character(r$round) & !is.na(a$agree) & a$agree < 95, ]
  if (nrow(a)) {
    add("watch", "Differs from the original analysts' variable",
        paste0(paste(sprintf("%s: %s agreement", a$indicator, fmt_pct(a$agree, 0)), collapse = "; "), ". See Validation and Data issues."))
  }
  core <- d$qc_core[d$qc_core$round_id == rid, ]
  if (nrow(core) && core$date_outside_window > 0.01 * core$households) {
    add("watch", "Interview dates outside the fieldwork window",
        sprintf("%s households (flagged, not removed).", fmt_int(core$date_outside_window)))
  }

  reg <- as.data.frame(d$ind_region)
  reg_r <- reg[reg$round_id == rid, ]
  v <- ind_value(reg_r, "fcs_pb")$v
  if (any(!is.na(v))) {
    o <- order(v, decreasing = TRUE, na.last = NA)[seq_len(min(3, sum(!is.na(v))))]
    add("info", "Highest poor + borderline food consumption",
        paste(sprintf("%s %s", reg_r$admin1[o], fmt_pct(v[o], 0)), collapse = " · "))
    changes <- vapply(reg_r$admin1, function(g) ind_compare(reg[reg$admin1 == g, ], "fcs_pb", rid)$diff, 0)
    if (any(!is.na(changes))) {
      k <- which.max(abs(changes))
      c_k <- ind_compare(reg[reg$admin1 == reg_r$admin1[k], ], "fcs_pb", rid)
      add("info", "Largest regional change in poor + borderline",
          sprintf("%s: %s%.1f pts vs %s (no significance test).", reg_r$admin1[k], if (c_k$diff >= 0) "+" else "−", abs(c_k$diff), c_k$base_round))
    }
  }
  n_supp <- sum(is.na(v))
  if (n_supp) add("info", "Regions without an estimate", sprintf("%d region(s): fewer than 30 households, or not surveyed.", n_supp))
  if (!any(vapply(out, function(p) p$level %in% c("serious", "watch"), TRUE))) {
    add("ok", "No specific caution for this round", "Weighted, comparable with the same season, and consistent with the analysts' variables.")
  }
  rank <- c(serious = 1, watch = 2, ok = 3, info = 4)
  out[order(rank[vapply(out, `[[`, "", "level")])]
}

attention_ui <- function(points) {
  icons <- c(serious = "exclamation-triangle-fill", watch = "exclamation-circle-fill", info = "info-circle-fill", ok = "check-circle-fill")
  htmltools::div(class = "alert-stack", lapply(points, function(p) {
    htmltools::div(class = paste("attention", p$level), bsicons::bs_icon(icons[[p$level]]),
                   htmltools::div(htmltools::strong(p$title), htmltools::div(class = "detail", p$detail)))
  }))
}

situation_server <- function(id, d, ref) {
  shiny::moduleServer(id, function(input, output, session) {
    nat <- d$ind_round
    output$chip <- round_chip(d, ref)

    output$kpis <- shiny::renderUI({
      rid <- ref()
      r <- d$rounds[d$rounds$round_id == rid, ]
      card <- function(id, title, icon, tone) {
        cmp <- ind_compare(nat, id, rid)
        kpi(title, fmt_ind(cmp$value, id),
            if (is.na(cmp$value)) "Not available in this round" else change_tag(cmp, id), icon, tone)
      }
      bslib::layout_column_wrap(
        width = "160px", fill = FALSE, heights_equal = "row",
        kpi("Households", fmt_int(r$households), if (isTRUE(nat$weighted_available[nat$round_id == rid])) "Weighted estimates" else "No weight: unweighted estimates",
            "people", "slate"),
        card("fcs_pb", "Poor + borderline FCS", "basket", "orange"),
        card("rcsi_p3", "rCSI phase 3+", "shield-exclamation", "red"),
        card("lcs_ce", "Crisis + emergency coping", "life-preserver", "amber"),
        card("hhs_p3", "Hunger scale phase 3+", "exclamation-diamond", "blue"),
        card("fes_75", "Food share of spending 75%+", "cash-coin", "teal")
      )
    })

    output$attention <- shiny::renderUI(attention_ui(attention_points(d, ref())))

    output$table <- reactable::renderReactable({
      rid <- ref()
      same <- sort(nat$round_id[same_season(nat$round_id, rid) & nat$round_id <= rid])
      keep <- utils::tail(same, 4)
      ind_reactable(ind_table(nat, IND_MAIN, keep, rid), nat, IND_MAIN, rid)
    })

    output$g_fcs <- plotly::renderPlotly(season_bars(nat, "fcs_pb", ref(), "#F0B37E", "#C96A1B"))
    output$g_rcsi <- plotly::renderPlotly(season_bars(nat, "rcsi_p3", ref(), "#DD9A92", "#B83227"))
    output$g_lcs <- plotly::renderPlotly(season_bars(nat, "lcs_ce", ref(), "#E8CF8C", "#B58A10"))
  })
}
