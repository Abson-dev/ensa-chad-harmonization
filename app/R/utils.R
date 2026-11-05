# Theme, palettes and small UI helpers shared by all pages.

# Colours: WFP Visual Brand Guide v6.0 (October 2025), pages 26-29. Keep in step with www/styles.css.
COL <- list(
  navy = "#002F5A", blue = "#007DBC", sand = "#F9F4DF", ink = "#231F20", muted = "#636466",
  grid = "#E6E9EE", na = "#E9ECEF"
)
GEN_COL <- c("1" = "#AA5628", "2" = "#007DBC", "3" = "#035537")
GEN_LABEL <- c("1" = "Gen 1 · French codebook", "2" = "Gen 2 · hybrid / WFP modules",
               "3" = "Gen 3 · WFP standard codebook")
FCS_COL <- c(Poor = "#E3002B", Borderline = "#F8A07E", Acceptable = "#03924A")
# Cadre Harmonise / IPC phase colours: the IPC standard, also in WFP's wfpthemes package. Not to be rebranded.
CH_COL <- c("Phase 1" = "#CDFACD", "Phase 2" = "#FAE61E", "Phase 3+" = "#E67800")
METHOD_COL <- c(copy = "#007DBC", copy_label = "#950158", sum = "#002F5A", sum_cap7 = "#AA5628",
                any = "#035537", max_or_last = "#E3002B", missing = "#636466")
# Any method added to the pipeline later still gets a colour instead of breaking the Process page.
method_colour <- function(m) if (m %in% names(METHOD_COL)) METHOD_COL[[m]] else "#636466"
COVERAGE_SCALE <- list(c(0, "#E3002B"), c(0.5, "#ECE1B1"), c(0.95, "#74C48A"), c(1, "#03924A"))

DOMAIN_NAMES <- c(core = "core", fcs = "FCS", rcsi = "rCSI", lcs = "LCS", hhs = "HHS", hdds = "HDDS",
                  exp = "expenditure", demo = "demographics")

# Facts from the metadata scan of the 14 source files (see the crosswalk README sheet).
FACTS <- list(distinct_vars = 3853, shared_vars = 14, tests = 29)

app_theme <- function() {
  bslib::bs_theme(
    version = 5,
    bg = "#FFFFFF", fg = COL$ink, primary = COL$blue, secondary = COL$navy,
    success = "#03924A", warning = "#F0512D", danger = "#E3002B", info = "#008EB2",
    base_font = bslib::font_collection("Open Sans", "Segoe UI", "Roboto", "Helvetica Neue", "Arial", "sans-serif"),
    heading_font = bslib::font_collection("Open Sans", "Segoe UI", "Roboto", "Arial", "sans-serif"),
    "navbar-bg" = COL$navy, "border-radius" = "0.6rem", "card-border-color" = COL$grid
  )
}

fmt_int <- function(x) format(x, big.mark = ",", scientific = FALSE, trim = TRUE)
fmt_pct <- function(x, d = 1) ifelse(is.na(x), "–", paste0(formatC(x, format = "f", digits = d), "%"))

# Consistent plotly look; call last in each chart. Settings passed in ... override the defaults
# (axis, legend and margin lists are merged, not replaced).
plotly_style <- function(p, legend = TRUE, ...) {
  base <- list(
    font = list(family = "Open Sans, Segoe UI, Arial, sans-serif", size = 12, color = COL$ink),
    paper_bgcolor = "rgba(0,0,0,0)", plot_bgcolor = "rgba(0,0,0,0)",
    xaxis = list(gridcolor = COL$grid, zeroline = FALSE, title = list(text = ""), automargin = TRUE),
    yaxis = list(gridcolor = COL$grid, zeroline = FALSE, title = list(text = ""), automargin = TRUE),
    legend = list(orientation = "h", y = 1.14, x = 0, yanchor = "bottom"),
    showlegend = legend, hoverlabel = list(font = list(family = "Open Sans, Segoe UI, Arial")),
    margin = list(t = if (legend) 75 else 30, r = 20, b = 30, l = 50)
  )
  extra <- list(...)
  for (k in names(extra)) {
    base[[k]] <- if (is.list(base[[k]]) && is.list(extra[[k]])) utils::modifyList(base[[k]], extra[[k]]) else extra[[k]]
  }
  for (ax in c("xaxis", "yaxis")) {
    if (is.character(base[[ax]]$title)) base[[ax]]$title <- list(text = base[[ax]]$title)
  }
  do.call(plotly::layout, c(list(p), base)) |>
    plotly::config(displaylogo = FALSE, modeBarButtonsToRemove = c("lasso2d", "select2d", "autoScale2d"),
                   toImageButtonOptions = list(format = "png", scale = 2))
}

PAGE_ICONS <- c("Harmonisation process" = "diagram-3", "Crosswalk explorer" = "table", "Survey rounds" = "calendar3",
                "Validation" = "patch-check", "Data issues" = "exclamation-triangle",
                "About & reproducibility" = "info-circle")

# Page header: icon, title, one-line purpose and, on the pages that follow it, the reference round.
page_intro <- function(title, text, icon = PAGE_ICONS[title], right = NULL) {
  htmltools::div(
    class = "page-head",
    htmltools::div(class = "page-icon", bsicons::bs_icon(if (is.na(icon)) "info-circle" else unname(icon))),
    htmltools::div(class = "page-text", htmltools::h2(title), htmltools::p(text)),
    right
  )
}

brand <- function() {
  htmltools::div(class = "brand",
                 htmltools::span(class = "brand-title", "ENSA Chad · Food security"),
                 htmltools::span(class = "brand-sub", "Harmonised surveys, 2018–2025"))
}

# tone: navy, blue, orange, red, brown, slate.
kpi <- function(title, value, detail, icon, tone = "slate") {
  bslib::value_box(title, value, htmltools::div(class = "kpi-detail", detail), class = paste0("kpi tone-", tone),
                   showcase = bsicons::bs_icon(icon), showcase_layout = bslib::showcase_left_center(width = 0.22))
}

# ---- Indicator catalogue ------------------------------------------------------------------------
# Columns <id>_w (weighted) and <id>_u (unweighted) come from prepare_app_data.R.

IND <- data.frame(
  id = c("fcs_pb", "fcs_poor", "fcs_mean", "rcsi_p3", "rcsi_p23", "rcsi_mean", "lcs_ce", "hhs_p3", "hdds_p3",
         "hdds_mean", "fes_75", "fes_mean", "female_head", "hh_size"),
  label = c("Poor + borderline food consumption", "Poor food consumption", "Mean FCS", "rCSI phase 3+", "rCSI phase 2+",
            "Mean rCSI", "Crisis + emergency coping (comparable)", "Hunger scale phase 3+", "Dietary diversity phase 3+",
            "Mean HDDS", "Food share of spending 75%+", "Mean food share of spending", "Female-headed households",
            "Mean household size"),
  short = c("Poor + borderline FCS", "Poor FCS", "Mean FCS", "rCSI phase 3+", "rCSI phase 2+", "Mean rCSI",
            "Crisis + emergency LCS", "HHS phase 3+", "HDDS phase 3+", "Mean HDDS", "Food share 75%+", "Mean food share",
            "Female-headed", "Household size"),
  domain = c("FCS", "FCS", "FCS", "rCSI", "rCSI", "rCSI", "LCS", "HHS", "HDDS", "HDDS", "Expenditure", "Expenditure",
             "Demographics", "Demographics"),
  unit = c("%", "%", "score", "%", "%", "score", "%", "%", "%", "score", "%", "%", "%", "members"),
  # Which end of the scale is the worse one, for the colour scale of the regional maps.
  worse = c("high", "high", "low", "high", "high", "high", "high", "high", "high", "low", "high", "high", "none", "none"),
  stringsAsFactors = FALSE
)
IND_CHOICES <- lapply(split(IND, factor(IND$domain, levels = unique(IND$domain))), function(g) stats::setNames(g$id, g$label))
# In the tables of the Overview and Regions pages.
IND_MAIN <- c("fcs_pb", "fcs_poor", "fcs_mean", "rcsi_p3", "rcsi_mean", "lcs_ce", "hhs_p3", "hdds_p3", "hdds_mean", "fes_75")

ind_info <- function(id) IND[match(id, IND$id), ]
is_pct <- function(id) ind_info(id)$unit == "%"

# Value of an indicator: weighted where the round has weights, otherwise unweighted (flagged).
ind_value <- function(x, id, est = "w") {
  w <- x[[paste0(id, "_w")]]; u <- x[[paste0(id, "_u")]]
  if (identical(est, "u")) return(list(v = u, fb = rep(FALSE, length(u))))
  fb <- is.na(w) & !is.na(u)
  list(v = ifelse(fb, u, w), fb = fb)
}

fmt_ind <- function(v, id) {
  ifelse(is.na(v), "–", if (is_pct(id)) fmt_pct(v) else formatC(v, format = "f", digits = 1))
}

same_season <- function(a, b) substr(a, 6, 7) == substr(b, 6, 7)

# Change since the latest earlier round of the same season with a value. If either round has no
# weight, both are compared unweighted, so that the change does not come from the weighting.
ind_compare <- function(x, id, rid, est = "w") {
  cur <- x[x$round_id == rid, , drop = FALSE]
  a <- ind_value(cur, id, est)
  out <- list(value = if (nrow(cur)) a$v else NA_real_, unweighted = if (nrow(cur)) a$fb else FALSE,
              base_round = NA_character_, base_id = NA_character_, diff = NA_real_, compared_unweighted = FALSE)
  if (!nrow(cur) || is.na(out$value)) return(out)
  ear <- x[same_season(x$round_id, rid) & x$round_id < rid, , drop = FALSE]
  ear <- ear[order(ear$round_id, decreasing = TRUE), , drop = FALSE]
  b <- ind_value(ear, id, est)
  ear <- ear[!is.na(b$v), , drop = FALSE]
  fb_b <- b$fb[!is.na(b$v)]
  if (!nrow(ear)) return(out)
  base <- ear[1, , drop = FALSE]
  unw <- identical(est, "u") || a$fb || fb_b[1]
  col <- paste0(id, if (unw) "_u" else "_w")
  out$base_round <- as.character(base$round)
  out$base_id <- base$round_id
  out$diff <- cur[[col]] - base[[col]]
  out$compared_unweighted <- unw && !identical(est, "u")
  out
}

# Rises are not painted as good or bad: the comparison has no significance test.
change_tag <- function(cmp, id, html = FALSE) {
  if (is.na(cmp$diff)) return(if (html) "<span class='muted'>–</span>" else "No earlier round of this season")
  up <- cmp$diff >= 0
  unit <- if (is_pct(id)) "pts" else ""
  arrow <- sprintf("%s%s%s", if (up) "▲ +" else "▼ −", formatC(abs(cmp$diff), format = "f", digits = 1),
                   if (nzchar(unit)) paste0(" ", unit) else "")
  if (html) return(sprintf("<span class='%s'>%s</span>", if (up) "rise" else "fall", arrow))
  htmltools::tagList(htmltools::span(class = if (up) "rise" else "fall", arrow),
                     sprintf(" vs %s%s", cmp$base_round, if (cmp$compared_unweighted) ", unweighted" else ""))
}

# Table of indicators by round, with the reference round highlighted and the same-season change.
ind_table <- function(x, ids, round_ids, rid) {
  x <- x[x$round_id %in% round_ids, , drop = FALSE]
  x <- x[order(x$round_id), , drop = FALSE]
  labels <- paste0(as.character(x$round), ifelse(!x$weighted_available, " *", ""))
  body <- lapply(seq_along(ids), function(k) {
    r <- ind_value(x, ids[k])
    stats::setNames(as.list(fmt_ind(r$v, ids[k])), labels)
  })
  tab <- data.frame(Indicator = ind_info(ids)$short, check.names = FALSE, stringsAsFactors = FALSE)
  for (l in labels) tab[[l]] <- vapply(body, function(b) b[[l]], "")
  list(table = tab, current = labels[match(rid, x$round_id)])
}

ind_reactable <- function(tab, x_full, ids, rid) {
  chg <- vapply(ids, function(id) change_tag(ind_compare(x_full, id, rid), id, html = TRUE), "")
  t2 <- tab$table
  t2$Change <- chg
  cols <- list(
    Indicator = reactable::colDef(minWidth = 165, class = "cell-label"),
    Change = reactable::colDef(name = "Same-season change", html = TRUE, align = "right", minWidth = 92)
  )
  for (l in setdiff(names(tab$table), "Indicator")) {
    cur <- identical(l, tab$current)
    cols[[l]] <- reactable::colDef(align = "right", minWidth = 60, class = if (cur) "cell-current",
                                   headerClass = if (cur) "head-current")
  }
  reactable::reactable(t2, columns = cols, compact = TRUE, pagination = FALSE, striped = TRUE, sortable = FALSE,
                       highlight = TRUE, class = "dark-table")
}

# Same-season bars up to the reference round, darker for the reference; hatched without weights.
season_bars <- function(x, id, rid, colour, dark) {
  x <- x[same_season(x$round_id, rid) & x$round_id <= rid, , drop = FALSE]
  x <- x[order(x$round_id), , drop = FALSE]
  r <- ind_value(x, id)
  lab <- as.character(x$round)
  plotly::plot_ly(x = factor(lab, levels = lab), y = r$v, type = "bar",
                  marker = list(color = ifelse(x$round_id == rid, dark, colour),
                                pattern = list(shape = ifelse(r$fb, "/", ""), fillmode = "overlay",
                                               fgcolor = "rgba(255,255,255,0.6)", size = 6, solidity = 0.25)),
                  text = fmt_ind(r$v, id), textposition = "outside", cliponaxis = FALSE,
                  hovertemplate = paste0("%{x}: %{text}", ifelse(r$fb, " (unweighted)", ""), "<extra></extra>")) |>
    plotly_style(legend = FALSE, bargap = 0.3, margin = list(t = 24, r = 8, b = 30, l = 8),
                 xaxis = list(title = "", tickangle = -35),
                 yaxis = list(title = "", showticklabels = FALSE, showgrid = FALSE,
                              range = c(0, 1.2 * max(c(r$v, 1), na.rm = TRUE))))
}

round_chip <- function(d, ref) {
  shiny::renderUI({
    r <- d$rounds[d$rounds$round_id == ref(), ]
    htmltools::div(class = "round-chip", bsicons::bs_icon("calendar3"), htmltools::strong(r$round),
                   htmltools::span(sprintf("%s to %s", format(r$fieldwork_start, "%d %b"), format(r$fieldwork_end, "%d %b %Y"))))
  })
}

metric_label <- function(id) ind_info(id)$label

# Regional heatmap colour scale, by which end of the indicator is the worse one.
heat_scale <- function(id) {
  switch(ind_info(id)$worse,
         low = list(c(0, "#E3002B"), c(0.5, "#F9F4DF"), c(1, "#007DBC")),
         high = list(c(0, "#F9F4DF"), c(1/3, "#F8A07E"), c(2/3, "#F0512D"), c(1, "#9A331B")),
         list(c(0, "#B9E5FB"), c(0.5, "#007DBC"), c(1, "#004670")))
}

pill <- function(text, colour, text_colour = "#fff") {
  htmltools::span(class = "pill", style = sprintf("background:%s;color:%s", colour, text_colour), text)
}

callout <- function(..., type = c("info", "warning", "success")) {
  type <- match.arg(type)
  icon <- c(info = "info-circle", warning = "exclamation-triangle", success = "check-circle")[[type]]
  htmltools::div(class = paste("callout", paste0("callout-", type)),
                 bsicons::bs_icon(icon, size = "1.2em"), htmltools::div(...))
}
