# Load and merge the harmonised domain files written by the Python pipeline (../output).

load_harmonised <- function(dir) {
  need <- file.path(dir, c("ensa_core.csv", "ensa_fcs.csv", "ensa_rcsi.csv"))
  if (!all(file.exists(need))) {
    stop("Harmonised files not found in ", normalizePath(dir, mustWork = FALSE),
         ". Run the pipeline first: python run_harmonize.py")
  }
  core <- data.table::fread(need[1], encoding = "UTF-8", na.strings = c("", "NA"))
  fcs <- data.table::fread(need[2], na.strings = c("", "NA"))
  rcsi <- data.table::fread(need[3], na.strings = c("", "NA"))
  fcs[, orig_FCS := NULL][, orig_FCSCat28 := NULL]
  rcsi[, orig_rCSI := NULL]

  # Domain files join one-to-one on round_id + hh_id.
  d <- merge(core, fcs, by = c("round_id", "hh_id"), all = FALSE)
  d <- merge(d, rcsi, by = c("round_id", "hh_id"), all = FALSE)
  stopifnot(nrow(d) == nrow(core), !anyDuplicated(d$hh_id))

  rounds <- unique(d[, .(round_id, year, season, generation)])
  rounds[, month := as.integer(substr(round_id, 6, 7))]
  data.table::setorder(rounds, year, month)
  rounds[, round := paste(season, year)]
  weighted <- d[, .(weighted = any(weight_flag == "ok")), by = round_id]
  rounds <- merge(rounds, weighted, by = "round_id", sort = FALSE)
  data.table::setorder(rounds, year, month)
  # Rounds without a usable weight are estimated unweighted and marked with a dagger.
  rounds[, round_lab := paste0(round, ifelse(weighted, "", "†"))]

  d[, round := factor(paste(season, year), levels = rounds$round)]
  d[, round_lab := factor(rounds$round_lab[match(round_id, rounds$round_id)], levels = rounds$round_lab)]
  d[, season := factor(season, levels = c("Feb", "Oct"), labels = c("February", "October"))]

  # Analysis weight: normalised survey weight (mean 1 within round); 1 where the round has none.
  d[, w := data.table::fifelse(round_id %in% rounds[weighted == TRUE, round_id], weight_norm, 1)]
  # Approximate primary sampling unit for variance estimation (see the Methods section).
  d[, psu := paste(round_id, admin1, admin2, admin3, sep = "|")]

  # Indicator flags (0/1, missing stays missing).
  fl <- function(x) as.numeric(x)
  d[, `:=`(
    fcs_poor = fl(FCSCat28 == 1), fcs_border = fl(FCSCat28 == 2), fcs_accept = fl(FCSCat28 == 3),
    fcs_pb = fl(FCSCat28 %in% 1:2) * ifelse(is.na(FCSCat28), NA, 1),
    fcs_pb21 = fl(FCSCat21 %in% 1:2) * ifelse(is.na(FCSCat21), NA, 1),
    rcsi_p1 = fl(rCSI_CH == 1), rcsi_p2 = fl(rCSI_CH == 2), rcsi_p3 = fl(rCSI_CH == 3),
    both_severe = fl(FCSCat28 %in% 1:2 & rCSI_CH == 3) * ifelse(is.na(FCSCat28) | is.na(rCSI_CH), NA, 1)
  )]
  for (s in c("rCSILessQlty", "rCSIBorrow", "rCSIMealSize", "rCSIMealAdult", "rCSIMealNb")) {
    d[, (paste0("use_", s)) := fl(get(s) > 0)]
  }
  list(d = d, rounds = rounds)
}

FCS_GROUPS <- c(FCSStap = "Cereals & tubers", FCSPulse = "Pulses & nuts", FCSVeg = "Vegetables",
                FCSFruit = "Fruits", FCSPr = "Meat, fish & eggs", FCSDairy = "Milk & dairy",
                FCSSugar = "Sugar", FCSFat = "Oil & fat", FCSCond = "Condiments")
RCSI_STRATEGIES <- c(rCSILessQlty = "Less preferred / cheaper food", rCSIBorrow = "Borrow food / rely on help",
                     rCSIMealSize = "Limit portion size", rCSIMealAdult = "Restrict adults for children",
                     rCSIMealNb = "Reduce number of meals")
