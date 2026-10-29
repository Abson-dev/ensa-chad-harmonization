# Theme, palettes and small UI helpers shared by all pages.

COL <- list(
  navy = "#17324D", teal = "#0F7C80", sand = "#F4F1EA", ink = "#1F2933", muted = "#6B7785",
  grid = "#E6E9EE", na = "#E9ECEF"
)
GEN_COL <- c("1" = "#C17F3A", "2" = "#2F7FB5", "3" = "#2E8B57")
GEN_LABEL <- c("1" = "Gen 1 · French codebook", "2" = "Gen 2 · hybrid / WFP modules",
               "3" = "Gen 3 · WFP standard codebook")
FCS_COL <- c(Poor = "#B83227", Borderline = "#E58E26", Acceptable = "#3C9D5D")
# Cadre Harmonise / IPC phase colours.
CH_COL <- c("Phase 1" = "#CDFACD", "Phase 2" = "#FAE61E", "Phase 3+" = "#E67800")
METHOD_COL <- c(copy = "#2F7FB5", copy_label = "#6C5CE7", sum = "#0F7C80", sum_cap7 = "#C17F3A",
                any = "#2E8B57", max_or_last = "#B83227", missing = "#ADB5BD")
# Any method added to the pipeline later still gets a colour instead of breaking the Process page.
method_colour <- function(m) if (m %in% names(METHOD_COL)) METHOD_COL[[m]] else "#6B7785"
COVERAGE_SCALE <- list(c(0, "#C8553D"), c(0.5, "#F2C14E"), c(0.95, "#8CC084"), c(1, "#2E8B57"))

DOMAIN_NAMES <- c(core = "core", fcs = "FCS", rcsi = "rCSI", lcs = "LCS", hhs = "HHS", hdds = "HDDS",
                  exp = "expenditure", demo = "demographics")

# Facts from the metadata scan of the 14 source files (see the crosswalk README sheet).
FACTS <- list(distinct_vars = 3853, shared_vars = 14, tests = 11)

app_theme <- function() {
  bslib::bs_theme(
    version = 5,
    bg = "#FFFFFF", fg = COL$ink, primary = COL$teal, secondary = COL$navy,
    success = "#2E8B57", warning = "#E58E26", danger = "#B83227", info = "#2F7FB5",
    base_font = bslib::font_collection("Inter", "Segoe UI", "Roboto", "Helvetica Neue", "Arial", "sans-serif"),
    heading_font = bslib::font_collection("Inter", "Segoe UI", "Roboto", "Arial", "sans-serif"),
    "navbar-bg" = COL$navy, "border-radius" = "0.6rem", "card-border-color" = COL$grid
  )
}

fmt_int <- function(x) format(x, big.mark = ",", scientific = FALSE, trim = TRUE)
fmt_pct <- function(x, d = 1) ifelse(is.na(x), "–", paste0(formatC(x, format = "f", digits = d), "%"))

# Consistent plotly look; call last in each chart. Settings passed in ... override the defaults
# (axis, legend and margin lists are merged, not replaced).
plotly_style <- function(p, legend = TRUE, ...) {
  base <- list(
    font = list(family = "Inter, Segoe UI, Arial, sans-serif", size = 12, color = COL$ink),
    paper_bgcolor = "rgba(0,0,0,0)", plot_bgcolor = "rgba(0,0,0,0)",
    xaxis = list(gridcolor = COL$grid, zeroline = FALSE, title = list(text = ""), automargin = TRUE),
    yaxis = list(gridcolor = COL$grid, zeroline = FALSE, title = list(text = ""), automargin = TRUE),
    legend = list(orientation = "h", y = 1.14, x = 0, yanchor = "bottom"),
    showlegend = legend, hoverlabel = list(font = list(family = "Inter, Segoe UI, Arial")),
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

page_intro <- function(title, text) {
  htmltools::div(class = "page-intro", htmltools::h2(title), htmltools::p(class = "lead", text))
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
