# Load and merge the harmonised domain files written by the Python pipeline (../output).

load_harmonised <- function(dir) {
  need <- file.path(dir, c("ensa_core.csv", "ensa_fcs.csv", "ensa_rcsi.csv", "ensa_lcs.csv", "ensa_hhs.csv",
                           "ensa_hdds.csv", "ensa_exp.csv"))
  if (!all(file.exists(need))) {
    stop("Harmonised files not found in ", normalizePath(dir, mustWork = FALSE),
         ". Run the pipeline first: python run_harmonize.py")
  }
  core <- data.table::fread(need[1], encoding = "UTF-8", na.strings = c("", "NA"))
  fcs <- data.table::fread(need[2], na.strings = c("", "NA"))
  rcsi <- data.table::fread(need[3], na.strings = c("", "NA"))
  lcs <- data.table::fread(need[4], na.strings = c("", "NA"))
  fcs[, orig_FCS := NULL][, orig_FCSCat28 := NULL]
  rcsi[, orig_rCSI := NULL]
  lcs[, orig_LCS := NULL]
  hhs <- data.table::fread(need[5], na.strings = c("", "NA"))
  hhs[, orig_HHS := NULL][, orig_HHS_phase := NULL]
  hdds <- data.table::fread(need[6], na.strings = c("", "NA"))
  hdds[, orig_HDDS := NULL][, orig_HDDS_phase := NULL]
  expd <- data.table::fread(need[7], na.strings = c("", "NA"))
  expd[, orig_FES := NULL]

  # Domain files join one-to-one on round_id + hh_id.
  d <- merge(core, fcs, by = c("round_id", "hh_id"), all = FALSE)
  d <- merge(d, rcsi, by = c("round_id", "hh_id"), all = FALSE)
  d <- merge(d, lcs, by = c("round_id", "hh_id"), all = FALSE)
  d <- merge(d, hhs, by = c("round_id", "hh_id"), all = FALSE)
  d <- merge(d, hdds, by = c("round_id", "hh_id"), all = FALSE)
  d <- merge(d, expd, by = c("round_id", "hh_id"), all = FALSE)
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
  # Livelihood coping: comparable max category (common strategies, coping for food) and the
  # round-specific one; a strategy is used if "yes" (30) or "already exhausted" (20).
  na_if <- function(x, cond) ifelse(cond, NA_real_, x)
  d[, `:=`(
    lcs_none = na_if(fl(LCS_max_common == 1), is.na(LCS_max_common)),
    lcs_stress = na_if(fl(LCS_max_common == 2), is.na(LCS_max_common)),
    lcs_crisis = na_if(fl(LCS_max_common == 3), is.na(LCS_max_common)),
    lcs_emergency = na_if(fl(LCS_max_common == 4), is.na(LCS_max_common)),
    lcs_ce = na_if(fl(LCS_max_common >= 3), is.na(LCS_max_common)),
    lcs_ce_round = na_if(fl(LCS_max >= 3), is.na(LCS_max))
  )]
  # Household Hunger Scale (collected from Oct 2019): phases and WFP categories as 0/1 flags.
  for (k in 1:5) d[, (paste0("hhs_ph", k)) := na_if(fl(HHS_phase == k), is.na(HHS_phase))]
  d[, `:=`(
    hhs_p3 = na_if(fl(HHS_phase >= 3), is.na(HHS_phase)),
    hhs_moderate = na_if(fl(HHSCat == 2), is.na(HHSCat)),
    hhs_severe = na_if(fl(HHSCat == 3), is.na(HHSCat))
  )]
  # Household Dietary Diversity: Cadre Harmonise phases as 0/1 flags.
  for (k in 1:5) d[, (paste0("hdds_ph", k)) := na_if(fl(HDDS_phase == k), is.na(HDDS_phase))]
  d[, hdds_p3 := na_if(fl(HDDS_phase >= 3), is.na(HDDS_phase))]
  # Food expenditure share: CARI categories as 0/1 flags.
  for (k in 1:4) d[, (paste0("fes_c", k)) := na_if(fl(FES_cat == k), is.na(FES_cat))]
  for (s in names(LCS_STRATEGIES)) {
    # Only where the strategy was asked in the round (otherwise NA); skipped answers count as not used.
    d[, (paste0("use_", s)) := fl(get(s) %in% c(20, 30))]
    d[, (paste0("use_", s)) := ifelse(rep(all(is.na(get(s))), .N), NA_real_, get(paste0("use_", s))), by = round_id]
  }
  list(d = d, rounds = rounds)
}

FCS_GROUPS <- c(FCSStap = "Cereals & tubers", FCSPulse = "Pulses & nuts", FCSVeg = "Vegetables",
                FCSFruit = "Fruits", FCSPr = "Meat, fish & eggs", FCSDairy = "Milk & dairy",
                FCSSugar = "Sugar", FCSFat = "Oil & fat", FCSCond = "Condiments")
LCS_STRATEGIES <- c(
  LCS_DomAsset = "Sold household assets", LCS_Animals = "Sold more animals than usual", LCS_Saving = "Spent savings",
  LCS_BorrowCash = "Borrowed money / food", LCS_CrdtFood = "Bought food on credit",
  LCS_EduHealth = "Reduced health / education spending", LCS_ProdAssets = "Sold productive assets",
  LCS_EatCrops = "Consumed immature crops", LCS_ChildWork = "Child labour (<15)",
  LCS_OutSchool = "Withdrew children from school", LCS_Marriage = "Child marriage (<18)",
  LCS_ResAsset = "Sold house or land", LCS_FemAnimal = "Sold last female animals", LCS_Begged = "Begged"
)
HDDS_GROUPS <- c(HDDSStapCer = "Cereals", HDDSStapRoot = "Roots & tubers", HDDSPulse = "Pulses & nuts",
                 HDDSVeg = "Vegetables", HDDSFruit = "Fruits", HDDSPrMeat = "Meat & offal", HDDSPrEgg = "Eggs",
                 HDDSPrFish = "Fish", HDDSDairy = "Milk & dairy", HDDSSugar = "Sugar", HDDSFat = "Oil & fat",
                 HDDSCond = "Condiments")
HHS_QUESTIONS <- c(HHSNoFood = "No food of any kind in the house", HHSBedHung = "Went to sleep hungry",
                   HHSNotEat = "Whole day and night without eating")
LCS_COMMON <- c("LCS_DomAsset", "LCS_Animals", "LCS_Saving", "LCS_ProdAssets", "LCS_ResAsset",
                "LCS_FemAnimal", "LCS_Begged")
RCSI_STRATEGIES <- c(rCSILessQlty = "Less preferred / cheaper food", rCSIBorrow = "Borrow food / rely on help",
                     rCSIMealSize = "Limit portion size", rCSIMealAdult = "Restrict adults for children",
                     rCSIMealNb = "Reduce number of meals")
