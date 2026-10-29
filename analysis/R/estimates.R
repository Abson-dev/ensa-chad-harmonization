# Survey-weighted estimates with 95% confidence intervals.

options(survey.lonely.psu = "adjust")

# One design for all rounds; estimates are always computed within round (svyby), so
# weights only need to be comparable within a round.
make_design <- function(d, cluster = c("admin3", "none")) {
  cluster <- match.arg(cluster)
  dd <- d[!is.na(w) & w > 0 & !is.na(admin1)]
  survey::svydesign(ids = if (cluster == "none") ~1 else ~psu, weights = ~w, data = dd)
}

# Mean (or proportion for 0/1 variables) of each variable by group, with 95% CI.
estimate_by <- function(design, vars, by = ~round_id) {
  out <- lapply(vars, function(v) {
    r <- survey::svyby(stats::as.formula(paste0("~", v)), by, design, survey::svymean,
                       na.rm = TRUE, keep.var = TRUE)
    g <- all.vars(by)
    data.frame(r[g], var = v, est = r[[v]], se = r[["se"]], row.names = NULL)
  })
  x <- do.call(rbind, out)
  x$lo <- x$est - 1.96 * x$se
  x$hi <- x$est + 1.96 * x$se
  x
}

# Fast weighted shares / means without CI (used for large region x round grids).
weighted_grid <- function(d, vars, by, min_n = 30) {
  dt <- d[!is.na(w) & w > 0]
  res <- dt[, c(list(n = .N), lapply(.SD, function(x) {
    ok <- !is.na(x)
    if (!any(ok)) NA_real_ else sum(x[ok] * w[ok]) / sum(w[ok])
  })), by = by, .SDcols = vars]
  res[n < min_n, (vars) := NA_real_]
  res[]
}

# Spearman correlation within each round.
corr_by_round <- function(d, x, y) {
  d[, .(rho = suppressWarnings(stats::cor(get(x), get(y), method = "spearman", use = "complete.obs"))),
    by = round_id]
}
