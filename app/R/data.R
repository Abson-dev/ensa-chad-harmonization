# Load everything the app shows. All inputs are metadata or aggregates (see prepare_app_data.R).

load_app_data <- function(dir = "data") {
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
    ind_round = read_qc("indicators_by_round.csv"),
    ind_region = read_qc("indicators_by_round_region.csv"),
    manifest = jsonlite::fromJSON(f("manifest.json")),
    settings = readLines(f("settings.toml"), encoding = "UTF-8"),
    xlsx_path = xl
  )
}
