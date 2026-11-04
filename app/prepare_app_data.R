# Build the aggregate-only data used by the Shiny app.
#
# Reads the harmonised household files in ../output (never shipped with the app)
# and writes small summary tables to app/data/. Run from the app/ folder:
#   Rscript prepare_app_data.R
#
# Re-run after every pipeline run (python run_harmonize.py).

suppressPackageStartupMessages({
  library(data.table)
  library(jsonlite)
})

MIN_CELL <- 30 # suppress region x round estimates based on fewer households

app_dir <- normalizePath(".", winslash = "/")
root <- normalizePath("..", winslash = "/")
out <- file.path(root, "output")
dat <- file.path(app_dir, "data")
dir.create(dat, showWarnings = FALSE)

stopifnot(file.exists(file.path(out, "ensa_core.csv")))

core <- fread(file.path(out, "ensa_core.csv"), encoding = "UTF-8",
              select = c("round_id", "hh_id", "admin1", "weight", "weight_flag", "date_flag"))
fcs <- fread(file.path(out, "ensa_fcs.csv"), select = c("hh_id", "FCS", "FCSCat28"))
rcsi <- fread(file.path(out, "ensa_rcsi.csv"), select = c("hh_id", "rCSI", "rCSI_CH"))
lcs <- fread(file.path(out, "ensa_lcs.csv"), select = c("hh_id", "LCS_max_common"))
hhs <- fread(file.path(out, "ensa_hhs.csv"), select = c("hh_id", "HHS_phase"))
hdds <- fread(file.path(out, "ensa_hdds.csv"), select = c("hh_id", "HDDS", "HDDS_phase"))
exp <- fread(file.path(out, "ensa_exp.csv"), select = c("hh_id", "FES", "FES_cat"))
demo <- fread(file.path(out, "ensa_demo.csv"), select = c("hh_id", "HHHSex", "HHSize"))
d <- Reduce(function(a, b) merge(a, b, by = "hh_id"), list(core, fcs, rcsi, lcs, hhs, hdds, exp, demo))
d[, w := fifelse(weight_flag == "ok", weight, NA_real_)]

wmean <- function(x, w) {
  ok <- !is.na(x) & !is.na(w)
  if (!any(ok)) NA_real_ else sum(x[ok] * w[ok]) / sum(w[ok])
}
share <- function(cond, w) 100 * wmean(as.numeric(cond), w)

# Unweighted and weighted value of a 0/1 flag or a score; missing below min_n valid households,
# so that a region is not reported on a handful of answers to a partly collected module.
both <- function(name, value, w, min_n) {
  ok <- !is.na(value)
  v <- if (sum(ok) < min_n) c(NA_real_, NA_real_) else c(mean(value[ok]), wmean(value, w))
  stats::setNames(as.list(v), paste0(name, c("_u", "_w")))
}

summarise <- function(x, min_n = 1) {
  one <- rep(1, nrow(x))
  c(list(
    households = nrow(x),
    weighted_available = any(!is.na(x$w)),
    fcs_mean_u = mean(x$FCS, na.rm = TRUE),
    fcs_mean_w = wmean(x$FCS, x$w),
    fcs_poor_u = share(x$FCSCat28 == 1, one * !is.na(x$FCSCat28)),
    fcs_border_u = share(x$FCSCat28 == 2, one * !is.na(x$FCSCat28)),
    fcs_accept_u = share(x$FCSCat28 == 3, one * !is.na(x$FCSCat28)),
    fcs_poor_w = share(x$FCSCat28 == 1, x$w * !is.na(x$FCSCat28)),
    fcs_border_w = share(x$FCSCat28 == 2, x$w * !is.na(x$FCSCat28)),
    fcs_accept_w = share(x$FCSCat28 == 3, x$w * !is.na(x$FCSCat28)),
    rcsi_mean_u = mean(x$rCSI, na.rm = TRUE),
    rcsi_mean_w = wmean(x$rCSI, x$w),
    rcsi_p1_u = share(x$rCSI_CH == 1, one * !is.na(x$rCSI_CH)),
    rcsi_p2_u = share(x$rCSI_CH == 2, one * !is.na(x$rCSI_CH)),
    rcsi_p3_u = share(x$rCSI_CH == 3, one * !is.na(x$rCSI_CH)),
    rcsi_p1_w = share(x$rCSI_CH == 1, x$w * !is.na(x$rCSI_CH)),
    rcsi_p2_w = share(x$rCSI_CH == 2, x$w * !is.na(x$rCSI_CH)),
    rcsi_p3_w = share(x$rCSI_CH == 3, x$w * !is.na(x$rCSI_CH))
  ),
  both("lcs_ce", 100 * (x$LCS_max_common >= 3), x$w, min_n),
  both("hhs_p3", 100 * (x$HHS_phase >= 3), x$w, min_n),
  both("hdds_p3", 100 * (x$HDDS_phase >= 3), x$w, min_n),
  both("hdds_mean", x$HDDS, x$w, min_n),
  both("fes_75", 100 * (x$FES_cat == 4), x$w, min_n),
  both("fes_mean", x$FES, x$w, min_n),
  both("female_head", 100 * (x$HHHSex == 2), x$w, min_n),
  both("hh_size", x$HHSize, x$w, min_n))
}

by_round <- d[, summarise(.SD), by = round_id]
# Households with no region recorded count nationally, not as a region of their own (fread reads them as "").
by_region <- d[!is.na(admin1) & admin1 != "", summarise(.SD, min_n = MIN_CELL), by = .(round_id, admin1)]
num <- setdiff(names(by_region), c("round_id", "admin1", "households", "weighted_available"))
by_region[households < MIN_CELL, (num) := NA_real_]

fwrite(by_round[order(round_id)], file.path(dat, "indicators_by_round.csv"))
fwrite(by_region[order(round_id, admin1)], file.path(dat, "indicators_by_round_region.csv"))

# Pipeline configuration, QC tables and provenance (all aggregate / metadata only).
for (f in c("crosswalk.csv", "rounds.csv", "admin1_names.csv", "settings.toml")) {
  file.copy(file.path(root, "config", f), file.path(dat, f), overwrite = TRUE)
}
for (f in list.files(file.path(out, "qc"), pattern = "\\.csv$", full.names = TRUE)) {
  file.copy(f, file.path(dat, basename(f)), overwrite = TRUE)
}
m <- fromJSON(file.path(out, "manifest.json"))
m$inputs$file <- basename(m$inputs$file) # no local paths in the shared app
write_json(m, file.path(dat, "manifest.json"), auto_unbox = TRUE, pretty = TRUE)

# The crosswalk workbook is built by the crosswalk step; use the data-folder copy if it is newer.
wb_src <- file.path(dirname(root), "ENSA_Chad_crosswalk_2018-2025.xlsx")
wb_app <- file.path(dat, basename(wb_src))
if (file.exists(wb_src) && (!file.exists(wb_app) || file.mtime(wb_src) > file.mtime(wb_app))) {
  file.copy(wb_src, wb_app, overwrite = TRUE)
}
stopifnot("Crosswalk workbook missing from app/data" = file.exists(wb_app))

# Result of the independent Stata check (stata/00_run_all.do), by domain; no household identifiers.
stata_src <- file.path(out, "stata_checks", "check_summary.xlsx")
stata_app <- file.path(dat, "stata_check.csv")
if (file.exists(stata_src)) {
  s <- as.data.table(readxl::read_excel(stata_src, sheet = "by_variable"))
  fwrite(s[, .(variables = .N, cells_ok = sum(rounds_ok), cells_not_collected = sum(rounds_not_collected),
               cells_mismatch = sum(rounds_mismatch), values_mismatch = sum(mismatch)), by = domain], stata_app)
} else if (file.exists(stata_app)) {
  file.remove(stata_app)
}

cat(sprintf("App data written to %s\n  rounds: %d, region x round cells: %d (suppressed < %d HH: %d)\n",
            dat, nrow(by_round), nrow(by_region), MIN_CELL, sum(by_region$households < MIN_CELL)))
