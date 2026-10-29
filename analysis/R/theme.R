# Palettes, ggplot theme and flextable style shared by the analysis report.

PAL <- list(
  navy = "#17324D", teal = "#0F7C80", ink = "#1F2933", muted = "#6B7785", grid = "#E6E9EE",
  gen = c("1" = "#C17F3A", "2" = "#2F7FB5", "3" = "#2E8B57"),
  fcs = c(Poor = "#B83227", Borderline = "#E58E26", Acceptable = "#3C9D5D"),
  # Cadre Harmonise / IPC phase colours
  ch = c("Phase 1" = "#CDFACD", "Phase 2" = "#FAE61E", "Phase 3+" = "#E67800"),
  lcs = c("No strategy" = "#CDFACD", Stress = "#FAE61E", Crisis = "#E67800", Emergency = "#C80000"),
  # IPC / Cadre Harmonise 5-phase colours
  ipc = c("Phase 1" = "#CDFACD", "Phase 2" = "#FAE61E", "Phase 3" = "#E67800", "Phase 4" = "#C80000", "Phase 5" = "#640000"),
  season = c(Feb = "#C17F3A", Oct = "#0F7C80")
)
GEN_LABEL <- c("1" = "Gen 1 · French codebook", "2" = "Gen 2 · hybrid / WFP modules",
               "3" = "Gen 3 · WFP standard codebook")

theme_report <- function(base_size = 10) {
  ggplot2::theme_minimal(base_size = base_size) +
    ggplot2::theme(
      plot.title = ggplot2::element_text(face = "bold", colour = PAL$navy, size = base_size + 2),
      plot.subtitle = ggplot2::element_text(colour = PAL$muted),
      plot.caption = ggplot2::element_text(colour = PAL$muted, size = base_size - 2, hjust = 0),
      plot.title.position = "plot", plot.caption.position = "plot",
      panel.grid.minor = ggplot2::element_blank(),
      panel.grid.major = ggplot2::element_line(colour = PAL$grid),
      strip.text = ggplot2::element_text(face = "bold", colour = PAL$navy, hjust = 0),
      legend.position = "top", legend.justification = "left",
      axis.title = ggplot2::element_text(colour = PAL$muted)
    )
}

pct <- function(x, d = 1) ifelse(is.na(x), "–", formatC(100 * x, format = "f", digits = d))
num <- function(x, d = 1) ifelse(is.na(x), "–", formatC(x, format = "f", digits = d, big.mark = ","))
int <- function(x) ifelse(is.na(x), "–", formatC(x, format = "d", big.mark = ","))
ci <- function(lo, hi, d = 1, scale = 100) {
  ifelse(is.na(lo), "–", sprintf("%s–%s", formatC(scale * lo, format = "f", digits = d),
                                formatC(scale * hi, format = "f", digits = d)))
}

flextable_style <- function() {
  flextable::set_flextable_defaults(
    font.family = "Calibri", font.size = 9, padding = 3, border.color = "#BFC7D1",
    theme_fun = flextable::theme_booktabs, big.mark = ",", na_str = "–"
  )
}

# Colour the "Change (pp)" column: red for increases > 5 pp, green for decreases > 5 pp.
# Use in a flextable pipe: ft(...) |> colour_change(tab$change)
colour_change <- function(x, change, j = "Change (pp)", threshold = 5) {
  up <- which(!is.na(change) & change > threshold)
  down <- which(!is.na(change) & change < -threshold)
  if (length(up)) x <- flextable::color(x, i = up, j = j, color = PAL$fcs[["Poor"]])
  if (length(down)) x <- flextable::color(x, i = down, j = j, color = PAL$fcs[["Acceptable"]])
  x
}

# Numbered table caption with a bookmark, so that \@ref(tab:<id>) in the text points to it.
# (Set here rather than with the tab.cap chunk option, which would add a second caption.)
cap <- function(x, text, id) {
  flextable::set_caption(x, caption = text, style = "Table Caption",
                         autonum = officer::run_autonum(seq_id = "tab", pre_label = "Table ", post_label = ". ", bkm = id))
}

# Final look for every table in the report.
ft <- function(df, header = NULL, widths = NULL) {
  x <- flextable::flextable(df)
  if (!is.null(header)) x <- flextable::set_header_labels(x, values = header)
  x <- x |>
    flextable::bold(part = "header") |>
    flextable::color(part = "header", color = "white") |>
    flextable::bg(part = "header", bg = PAL$navy) |>
    flextable::align(part = "header", align = "center") |>
    flextable::align(j = seq_len(ncol(df))[-1], align = "right", part = "body") |>
    flextable::valign(valign = "center", part = "all") |>
    flextable::bg(i = seq(2, max(2, nrow(df)), by = 2), bg = "#F4F6F8", part = "body")
  if (is.null(widths)) flextable::autofit(x) else flextable::width(x, width = widths)
}
