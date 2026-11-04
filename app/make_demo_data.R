# Build demo_data/: the app's metadata with INVENTED estimates, for screenshots and demonstrations.
# From the app/ folder, after prepare_app_data.R:   Rscript make_demo_data.R
# Then run the app with ENSA_DEMO=1: a banner says the data are synthetic.
#
# Indicator values are drawn at random from a fixed seed, independently of the real ones. Only the
# survey structure is kept: rounds, region names, households, which rounds have weights and which
# values are not collected. Agreement with the analysts and the crosswalk are methodological
# results, already public in the repository, and are kept.

if (!dir.exists("data")) stop("Run prepare_app_data.R first.", call. = FALSE)
set.seed(20261104)
dir.create("demo_data", showWarnings = FALSE)
invisible(file.copy(list.files("data", full.names = TRUE), "demo_data", overwrite = TRUE))

rw <- function(file, fun) {
  x <- utils::read.csv(file.path("demo_data", file), check.names = FALSE, stringsAsFactors = FALSE)
  utils::write.csv(fun(x), file.path("demo_data", file), row.names = FALSE, na = "")
}

# Three shares that sum to 100, with the first two growing with a level between 0 and 1.
shares <- function(level) {
  a <- pmin(45, pmax(1, 4 + 26 * level + stats::rnorm(length(level), 0, 1.5)))
  b <- pmin(45, pmax(2, 12 + 22 * level + stats::rnorm(length(level), 0, 2)))
  cbind(a, b, 100 - a - b)
}

synthetic <- function(x, region_effect = NULL) {
  year <- as.numeric(substr(x$round_id, 1, 4)) - 2018
  lean <- substr(x$round_id, 6, 7) == "02"
  level <- 0.25 + 0.03 * year + 0.08 * lean + 0.06 * sin(year) + stats::rnorm(nrow(x), 0, 0.02)
  if (!is.null(region_effect)) level <- level + region_effect[x$admin1] + stats::rnorm(nrow(x), 0, 0.05)
  level <- pmin(0.95, pmax(0.03, level))
  draws <- list(
    fcs = shares(level), rcsi = shares(level * 0.8),
    lcs_ce = 8 + 30 * level, hhs_p3 = 2 + 25 * level, hdds_p3 = 5 + 40 * level, hdds_mean = 7.5 - 4 * level,
    fes_75 = 15 + 45 * level, fes_mean = 55 + 20 * level, female_head = 18 + 8 * stats::runif(nrow(x)),
    hh_size = 5.2 + stats::runif(nrow(x)), fcs_mean = 72 - 45 * level, rcsi_mean = 3 + 20 * level
  )
  for (e in c("u", "w")) {
    noise <- function(sd = 0.6) stats::rnorm(nrow(x), 0, sd)
    keep <- function(name, v) {
      col <- paste0(name, "_", e)
      x[[col]] <<- ifelse(is.na(x[[col]]), NA_real_, pmax(0, v))
    }
    keep("fcs_poor", draws$fcs[, 1]); keep("fcs_border", draws$fcs[, 2]); keep("fcs_accept", draws$fcs[, 3])
    keep("rcsi_p3", draws$rcsi[, 1]); keep("rcsi_p2", draws$rcsi[, 2]); keep("rcsi_p1", draws$rcsi[, 3])
    for (n in c("lcs_ce", "hhs_p3", "hdds_p3", "fes_75", "fes_mean", "female_head", "fcs_mean", "rcsi_mean")) keep(n, draws[[n]] + noise())
    for (n in c("hdds_mean", "hh_size")) keep(n, draws[[n]] + noise(0.1))
  }
  x
}

rw("indicators_by_round.csv", synthetic)
regions <- unique(utils::read.csv("demo_data/indicators_by_round_region.csv")$admin1)
effect <- stats::setNames(stats::rnorm(length(regions), 0, 0.14), regions)
rw("indicators_by_round_region.csv", function(x) synthetic(x, effect))

# QC tables: estimates replaced; counts, completeness and agreement kept.
for (f in list.files("demo_data", pattern = "^qc_.*\\.csv$")) {
  rw(f, function(x) {
    est <- grep("_pct_w$|_pct_unw$|_mean|_median|^weight_sum$", names(x), value = TRUE)
    for (n in est) if (is.numeric(x[[n]])) x[[n]] <- ifelse(is.na(x[[n]]), NA_real_, round(stats::runif(nrow(x), 5, 45), 1))
    x
  })
}
cat("demo_data/ written: synthetic estimates. Run the app with ENSA_DEMO=1.\n")
