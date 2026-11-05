# Load everything the app shows. All inputs are metadata or aggregates (see prepare_app_data.R).

# Synthetic mode (ENSA_DEMO=1): invented estimates from make_demo_data.R, for screenshots and demonstrations.
demo_mode <- function() identical(Sys.getenv("ENSA_DEMO"), "1")
app_data_dir <- function() {
  if (!demo_mode()) return("data")
  if (!dir.exists("demo_data")) stop("demo_data is missing: run Rscript make_demo_data.R", call. = FALSE)
  "demo_data"
}

# One row per geography x round x indicator, for the Data page and its exports.
indicators_long <- function(ind_round, ind_region, rounds) {
  one <- function(x, geo) {
    do.call(rbind, lapply(seq_len(nrow(IND)), function(i) {
      id <- IND$id[i]
      data.frame(geography = geo, level = if ("admin1" %in% names(x)) "Region" else "National",
                 round_id = x$round_id, domain = IND$domain[i], indicator = IND$label[i], unit = IND$unit[i],
                 weighted = round(x[[paste0(id, "_w")]], 2), unweighted = round(x[[paste0(id, "_u")]], 2),
                 households = x$households)
    }))
  }
  out <- rbind(one(ind_round, "Chad"), one(as.data.frame(ind_region), ind_region$admin1))
  out <- out[!(is.na(out$weighted) & is.na(out$unweighted)), ]
  i <- match(out$round_id, rounds$round_id)
  out$round <- rounds$round[i]
  out$season <- month.name[rounds$month[i]]
  out$generation <- rounds$generation[i]
  out[, c("level", "geography", "round_id", "round", "season", "generation", "domain", "indicator", "unit",
          "weighted", "unweighted", "households")]
}

# Outputs of the humanitarian operations model, written by prepare_app_data.R. NULL if not there.
load_sim <- function(dir) {
  f <- function(x) file.path(dir, paste0("sim_", x))
  if (!file.exists(f("regional.csv"))) return(NULL)
  csv <- function(x) utils::read.csv(f(x), stringsAsFactors = FALSE, encoding = "UTF-8", check.names = FALSE)
  regional <- csv("regional.csv")
  # Alphabetical order in the byte sense, as in the Python model: rule D keeps ties in this order.
  regional <- regional[order(regional$admin1, method = "radix"), ]
  rownames(regional) <- NULL
  list(regional = regional, national = csv("national.csv"), profiles = csv("profiles.csv"), popgroups = csv("popgroups.csv"),
       targeting = csv("targeting.csv"), logit = csv("logit.csv"), mc_summary = csv("mc_summary.csv"), mc_top5 = csv("mc_top5.csv"),
       inputs = jsonlite::fromJSON(f("inputs.json")), meta = jsonlite::fromJSON(f("meta.json")))
}

load_app_data <- function(dir = app_data_dir()) {
  f <- function(x) file.path(dir, x)
  xl <- f("ENSA_Chad_crosswalk_2018-2025.xlsx")

  rounds <- readr::read_csv(f("rounds.csv"), col_types = readr::cols(.default = "c")) |>
    dplyr::mutate(
      year = as.integer(year), month = as.integer(month), generation = as.integer(generation),
      fieldwork_start = as.Date(fieldwork_start), fieldwork_end = as.Date(fieldwork_end),
      round = paste(month.abb[month], year)
    ) |>
    dplyr::arrange(year, month)
  lv <- rounds$round

  details <- readxl::read_excel(xl, "Details") |>
    rlang::set_names(c("domain", "concept", "harm", "round_code", "round", "source", "type",
                       "coverage", "range", "label", "value_labels", "alternates")) |>
    dplyr::mutate(
      round_id = paste0(substr(round_code, 3, 6), "-", substr(round_code, 1, 2)),
      round = factor(round, levels = lv),
      available = source != "(not available)",
      coverage = coverage * 100,
      # KoBo labels in some rounds carry HTML styling (e.g. <span style="color:blue">)
      label = trimws(gsub("\\s+", " ", gsub("<[^>]+>", " ", label)))
    )

  cw <- readxl::read_excel(xl, "Crosswalk")
  concepts <- cw |>
    dplyr::filter(!is.na(Concept)) |>
    dplyr::transmute(domain = Domain, concept = Concept, harm = `Harmonised name`,
                     rounds_available = as.integer(sub("/14", "", `Rounds available`)), notes = Notes) |>
    dplyr::mutate(domain = factor(domain, levels = unique(domain)), order = dplyr::row_number())
  details$domain <- factor(details$domain, levels = levels(concepts$domain))

  rounds_sheet <- readxl::read_excel(xl, "Rounds")
  rounds_sheet <- rounds_sheet[!is.na(rounds_sheet[[1]]), ] |>
    rlang::set_names(c("round_code", "round", "season", "folder", "file", "households", "variables",
                       "generation_label", "fieldwork", "weight_status", "concepts_available"))
  rounds <- dplyr::left_join(rounds, dplyr::select(rounds_sheet, round, file_label = file, households,
                                                   variables, weight_status, concepts_available), by = "round")

  flags <- readxl::read_excel(xl, "Data flags") |>
    rlang::set_names(c("issue", "rounds", "found", "handling"))

  rules <- readr::read_csv(f("crosswalk.csv"), col_types = readr::cols(.default = "c")) |>
    dplyr::mutate(round = factor(lv[match(round_id, rounds$round_id)], levels = lv))

  add_round <- function(x) dplyr::mutate(x, round = factor(lv[match(round_id, rounds$round_id)], levels = lv))
  read_qc <- function(x) add_round(readr::read_csv(f(x), show_col_types = FALSE))
  # Sums of categories shown as one indicator.
  add_sums <- function(x) {
    for (e in c("u", "w")) {
      x[[paste0("fcs_pb_", e)]] <- x[[paste0("fcs_poor_", e)]] + x[[paste0("fcs_border_", e)]]
      x[[paste0("rcsi_p23_", e)]] <- x[[paste0("rcsi_p2_", e)]] + x[[paste0("rcsi_p3_", e)]]
    }
    x
  }
  ind_round <- add_sums(read_qc("indicators_by_round.csv"))
  ind_region <- add_sums(read_qc("indicators_by_round_region.csv"))
  stata_file <- f("stata_check.csv")

  list(
    rounds = rounds,
    round_levels = lv,
    details = details,
    concepts = concepts,
    flags = flags,
    rules = rules,
    qc_core = read_qc("qc_core_by_round.csv"),
    qc_fcs = read_qc("qc_fcs_by_round.csv"),
    qc_rcsi = read_qc("qc_rcsi_by_round.csv"),
    qc_lcs = read_qc("qc_lcs_by_round.csv"),
    qc_hhs = read_qc("qc_hhs_by_round.csv"),
    qc_hdds = read_qc("qc_hdds_by_round.csv"),
    qc_exp = read_qc("qc_exp_by_round.csv"),
    qc_demo = read_qc("qc_demo_by_round.csv"),
    ind_round = ind_round,
    ind_region = ind_region,
    ind_long = indicators_long(ind_round, ind_region, rounds),
    stata_check = if (file.exists(stata_file)) readr::read_csv(stata_file, show_col_types = FALSE),
    manifest = jsonlite::fromJSON(f("manifest.json")),
    settings = readLines(f("settings.toml"), encoding = "UTF-8"),
    sim = load_sim(dir),
    xlsx_path = xl
  )
}
