# Server-side checks of every page of the app: builds each UI and renders every output
# (including all indicator / filter combinations) with shiny::testServer.
# Run from the app/ folder, after prepare_app_data.R:   Rscript tests/test_app.R
# Exits with status 1 if any check fails.

args <- commandArgs(trailingOnly = TRUE)
setwd(if (length(args)) args[1] else ".")
Sys.setenv(ENSA_LOCAL = "1")
suppressPackageStartupMessages({ library(shiny); library(bslib) })
for (f in list.files("R", full.names = TRUE)) source(f)
d <- load_app_data("data")
cat("data ok:", nrow(d$details), "detail rows,", nrow(d$concepts), "concepts,", nrow(d$rules), "rules\n")

failures <- 0
ok <- function(label, expr) {
  r <- tryCatch({ force(expr); "OK" }, error = function(e) paste("ERROR:", conditionMessage(e)))
  if (r != "OK") failures <<- failures + 1
  cat(sprintf("%-45s %s\n", label, r))
}

# UI builders
for (m in c("situation", "trends", "regions", "approach", "process", "crosswalk", "rounds", "validation", "issues", "data", "about")) {
  ok(paste("ui:", m), get(paste0(m, "_ui"))(m, d))
}

testServer(approach_server, args = list(d = d), { ok("approach$hh_plot", output$hh_plot) })

# The pages that follow the reference round, for every round (first round, unweighted rounds,
# rounds where a module was not collected).
for (rid in d$rounds$round_id) {
  ref <- shiny::reactive(rid)
  testServer(situation_server, args = list(d = d, ref = ref), {
    ok(sprintf("situation[%s]", rid), { output$chip; output$kpis; output$attention; output$table; output$g_fcs; output$g_rcsi; output$g_lcs })
  })
  testServer(trends_server, args = list(d = d, ref = ref), {
    session$setInputs(indicator = "fcs_pb", geo = "", estimate = "w")
    ok(sprintf("trends[%s]", rid), { output$kpis; output$season; output$table; output$fcs; output$rcsi; output$title })
  })
  testServer(regions_server, args = list(d = d, ref = ref), {
    session$setInputs(region = "Lac", metric = "fcs_pb", compare = c("Lac", "Ouaddai", "Wadi Fira"))
    ok(sprintf("regions[%s]", rid), { output$kpis; output$rank; output$heat; output$trend; output$table_title; output$rank_title; output$heat_title })
    tb <- tryCatch(output$table, error = function(e) if (inherits(e, "shiny.silent.error")) NULL else stop(e))
  })
}
ref <- shiny::reactive("2025-10")
testServer(trends_server, args = list(d = d, ref = ref), {
  for (id in IND$id) for (est in c("w", "u")) for (geo in c("", "Lac")) {
    session$setInputs(indicator = id, geo = geo, estimate = est)
    ok(sprintf("trends[%s,%s,%s]", id, est, geo), { output$kpis; output$season; output$table })
  }
})
testServer(regions_server, args = list(d = d, ref = ref), {
  for (id in setdiff(IND$id, c("female_head", "hh_size"))) {
    session$setInputs(region = "Lac", metric = id, compare = c("Lac", "Ouaddai"))
    ok(sprintf("regions[%s]", id), { output$rank; output$heat; output$trend })
  }
})
testServer(data_server, args = list(d = d), {
  session$setInputs(indicators = NULL, geo = NULL, rounds = NULL, season = "")
  ok("data all", { output$count; output$table })
  session$setInputs(indicators = IND$label[1], geo = "Lac", rounds = "Oct 2025", season = "October")
  ok("data filtered", { output$count; output$table })
  ok("data one row", stopifnot(nrow(shown()) == 1))
  ok("data csv", stopifnot(file.exists(output$csv), file.size(output$csv) > 0))
  ok("data excel", stopifnot(file.exists(output$excel), file.size(output$excel) > 0))
})

# Figures: the comparison rule.
nat <- d$ind_round
ok("compare: same season", {
  c1 <- ind_compare(nat, "fcs_pb", "2024-02")
  stopifnot(c1$base_id == "2023-02", c1$compared_unweighted)  # Feb 2024 has no weight
  stopifnot(abs(c1$diff - (nat$fcs_pb_u[nat$round_id == "2024-02"] - nat$fcs_pb_u[nat$round_id == "2023-02"])) < 1e-9)
})
ok("compare: weighted when both have weights", {
  c2 <- ind_compare(nat, "fcs_pb", "2019-10")
  stopifnot(c2$base_id == "2018-10", !c2$compared_unweighted)
  stopifnot(abs(c2$diff - (nat$fcs_pb_w[nat$round_id == "2019-10"] - nat$fcs_pb_w[nat$round_id == "2018-10"])) < 1e-9)
})
ok("compare: first round has no base", stopifnot(is.na(ind_compare(nat, "fcs_pb", "2018-10")$diff)))
ok("compare: Oct 2024 food share not available", stopifnot(is.na(ind_compare(nat, "fes_75", "2024-10")$value)))
ok("compare: Oct 2025 food share skips to an available round", stopifnot(ind_compare(nat, "fes_75", "2025-10")$base_id == "2023-10"))

# Figures: the app's indicators against the pipeline's own QC tables (weights, category rules).
close_to <- function(a, b, label, tol = 0.011) {
  a <- a[order(nat$round_id)]; keep <- !is.na(a) & !is.na(b)
  ok(label, stopifnot(sum(keep) >= 5, max(abs(a[keep] - b[keep])) < tol))
}
nat <- nat[order(nat$round_id), ]
close_to(nat$lcs_ce_w, d$qc_lcs$common_crisis_emergency_pct_w[order(d$qc_lcs$round_id)], "lcs_ce_w = pipeline QC")
close_to(nat$lcs_ce_u, d$qc_lcs$common_crisis_emergency_pct_unw[order(d$qc_lcs$round_id)], "lcs_ce_u = pipeline QC")
close_to(nat$hhs_p3_w, d$qc_hhs$phase3plus_pct_w[order(d$qc_hhs$round_id)], "hhs_p3_w = pipeline QC")
close_to(nat$hdds_p3_w, d$qc_hdds$phase3plus_pct_w[order(d$qc_hdds$round_id)], "hdds_p3_w = pipeline QC")
close_to(nat$fes_75_w, d$qc_exp$fes_75plus_pct_w[order(d$qc_exp$round_id)], "fes_75_w = pipeline QC")
close_to(nat$female_head_w, d$qc_demo$female_head_pct_w[order(d$qc_demo$round_id)], "female_head_w = pipeline QC")

# Data boundary: no household identifiers, and small regional cells stay suppressed.
ok("no household columns in data/", {
  for (f in list.files("data", pattern = "\\.csv$", full.names = TRUE)) {
    stopifnot(!any(c("hh_id", "uuid") %in% strsplit(readLines(f, n = 1, warn = FALSE), ",")[[1]]))
  }
})
ok("cells under 30 households suppressed", {
  small <- as.data.frame(d$ind_region)[d$ind_region$households < 30, ]
  cols <- grep("_[uw]$", names(small), value = TRUE)
  stopifnot(all(is.na(small[, cols])))  # no region is below the threshold in the current data
})

# Login: a server without accounts refuses to start; with them, only the right password passes.
Sys.setenv(ENSA_LOCAL = "", ENSA_ACCOUNTS_DB = file.path(tempdir(), "none.sqlite"), ENSA_ACCOUNTS_SECRET = "")
ok("auth: required on a server", stopifnot(auth_required() || interactive()))
if (!interactive()) {
  r <- tryCatch({ check_auth(); "started" }, error = function(e) conditionMessage(e))
  ok("auth: refuses to start without accounts", stopifnot(grepl("refusing", r)))
  db <- file.path(tempdir(), "accounts_test.sqlite")
  shinymanager::create_db(data.frame(user = "tester", password = "correct-horse", admin = FALSE, stringsAsFactors = FALSE),
                          sqlite_path = db, passphrase = "test-secret")
  Sys.setenv(ENSA_ACCOUNTS_DB = db, ENSA_ACCOUNTS_SECRET = "test-secret")
  ok("auth: starts with accounts", check_auth())
  ok("auth: login page built", stopifnot(is.function(protect_ui(shiny::fluidPage()))))
  chk <- shinymanager::check_credentials(db, passphrase = "test-secret")
  ok("auth: right password", stopifnot(isTRUE(chk("tester", "correct-horse")$result)))
  ok("auth: wrong password", stopifnot(isFALSE(chk("tester", "wrong")$result)))
}
Sys.setenv(ENSA_LOCAL = "1", ENSA_ACCOUNTS_DB = "", ENSA_ACCOUNTS_SECRET = "")

testServer(process_server, args = list(d = d), {
  session$setInputs(rule_domain = "")
  ok("process$flow", output$flow); ok("process$node_detail (none)", output$node_detail)
  session$setInputs(node = 4); ok("process$node_detail (4)", output$node_detail)
  ok("process$domains", output$domains); ok("process$methods", output$methods)
  ok("process$rules (all)", output$rules)
  session$setInputs(rule_domain = "fcs"); ok("process$rules (fcs)", output$rules)
})

testServer(crosswalk_server, args = list(d = d), {
  session$setInputs(domains = levels(d$concepts$domain), gaps_only = FALSE, jump = "")
  ok("crosswalk$matrix_ui", output$matrix_ui); ok("crosswalk$matrix", output$matrix)
  ok("crosswalk$table", output$table); ok("crosswalk$details", output$details)
  ok("crosswalk$concept_card (default)", output$concept_card); ok("crosswalk$concept_rounds", output$concept_rounds)
  session$setInputs(jump = "LCS_FemAnimal"); ok("crosswalk$concept_card (LCS_FemAnimal)", output$concept_card)
  ok("crosswalk$concept_rounds (LCS)", output$concept_rounds)
  session$setInputs(domains = c("LCS items (30 days)", "ID & design"), gaps_only = TRUE)
  ok("crosswalk$matrix (filtered)", output$matrix); ok("crosswalk$table (filtered)", output$table)
  session$setInputs(domains = character(0))
  r <- tryCatch(output$matrix, error = function(e) conditionMessage(e)); cat(sprintf("%-45s %s\n", "crosswalk$matrix (empty) ->", substr(r, 1, 40)))
})

testServer(rounds_server, args = list(d = d), {
  ok("rounds$calendar", output$calendar); ok("rounds$concepts", output$concepts); ok("rounds$inventory", output$inventory)
})
testServer(validation_server, args = list(d = d), {
  ok("validation$agree", output$agree); ok("validation$reversal", output$reversal); ok("validation$qc_table", output$qc_table)
})
testServer(issues_server, args = list(d = d), {
  session$setInputs(impact = "All"); ok("issues all", { output$count; output$cards })
  session$setInputs(impact = "High"); ok("issues high", output$count); cat("   ", output$count, "\n")
})
testServer(about_server, args = list(d = d), { ok("about$inputs", output$inputs) })

# Full app object (ui + server wiring)
ok("shinyAppDir", app <- shiny::shinyAppDir("."))

cat(if (failures) sprintf("\n%d check(s) FAILED\n", failures) else "\nAll checks passed\n")
if (failures) quit(status = 1)
