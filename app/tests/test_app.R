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
for (m in c("situation", "trends", "regions", "simulation", "approach", "process", "crosswalk", "rounds", "validation", "issues", "data", "about")) {
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

# Simulation: every output, including extreme inputs; then the R model against the Python model.
sim_defaults <- function(session, need = "cariB", rule = "B", budget = 7, floor = 25, price = 0, indexed = FALSE, fixed = 100) {
  session$setInputs(need = need, rule = rule, budget = budget, transfer = 52000, months = 4, delivery = 5, fixed = fixed,
                    floor = floor, price = price, indexed = indexed, frame = 100000, metric = "cariPB_fi", group_metric = "cariPB_fi")
}
if (!is.null(d$sim)) {
  testServer(simulation_server, args = list(d = d), {
    for (need in names(SIM_NEED)) for (rule in names(SIM_RULES)) {
      sim_defaults(session, need, rule)
      ok(sprintf("simulation[%s,%s]", need, rule), { output$kpis; output$rules; output$regions; output$region_table; output$region_title; output$tornado; output$shares })
    }
    sim_defaults(session)
    ok("simulation baseline", { output$national; output$forest; output$groups; output$popgroups })
    for (k in SIM_METRICS) { session$setInputs(metric = k); ok(sprintf("simulation forest[%s]", k), output$forest) }
    for (k in SIM_GROUP_METRICS) { session$setInputs(group_metric = k); ok(sprintf("simulation groups[%s]", k), output$groups) }
    ok("simulation trade-offs", { output$f_cov; output$f_tr; output$f_mo; output$funding; output$prices; output$delivery_tbl; output$delivery_note; output$modality; output$combined })
    ok("simulation robustness", { output$mc; output$top5; output$tornado; output$shares })
    ok("simulation targeting, read first", { output$targeting; output$logit; output$readiness; output$assumptions; output$provenance })
    ok("simulation csv says it is illustrative", {
      stopifnot(grepl("ILLUSTRATIVE", readLines(output$download, n = 1)))
      header <- readLines(output$download, n = 2)[2]
      stopifnot(!grepl("hh_id|uuid", header))
    })
    # A budget below the fixed cost funds nobody; a very large one covers everyone.
    for (rule in names(SIM_RULES)) {
      sim_defaults(session, rule = rule, budget = 1, fixed = 1000)
      ok(sprintf("simulation no money[%s]", rule), { output$kpis; output$rules; output$regions; output$funding; output$tornado; stopifnot(sum(alloc()$H[[rule]]) == 0) })
      sim_defaults(session, rule = rule, budget = 20)
      ok(sprintf("simulation everyone[%s]", rule), { output$kpis; if (rule != "C") stopifnot(abs(sum(alloc()$H[[rule]]) - sum(alloc()$E)) < 1e-6) })
      sim_defaults(session, rule = rule, floor = 100, price = 50, indexed = TRUE)
      ok(sprintf("simulation floor 100, indexed[%s]", rule), { output$kpis; stopifnot(all(alloc()$H[[rule]] <= alloc()$E + 1e-6)) })
    }
  })

  # Every rule respects 0 <= H <= E and the money available, whatever the inputs.
  p <- sim_params(d$sim)
  ok("simulation: rules stay within caseload and budget", {
    for (b in c(1e9, 3e9, 7e9, 15e9)) for (need in names(SIM_NEED)) for (r in names(SIM_RULES)) {
      q <- utils::modifyList(p, list(budget = b, need = need))
      a <- sim_allocation(d$sim$regional, q)
      stopifnot(all(a$H[[r]] >= -1e-9), all(a$H[[r]] <= a$E + 1e-6), sum(a$H[[r]]) <= a$capacity + 1e-6)
    }
  })
  ok("simulation: indexed price rise lowers coverage; a fixed transfer keeps it", {
    base <- sim_allocation(d$sim$regional, p)$summary$households[1]
    fixed <- sim_allocation(d$sim$regional, utils::modifyList(p, list(price = 0.2)))$summary$households[1]
    idx <- sim_allocation(d$sim$regional, utils::modifyList(p, list(price = 0.2, indexed = TRUE)))$summary$households[1]
    stopifnot(abs(fixed - base) < 1e-9, idx < base)
  })

  mdir <- file.path("..", "models", "Chad_Humanitarian_Operations_Reproducibility", "outputs")
  if (dir.exists(mdir)) {
    py <- function(x) utils::read.csv(file.path(mdir, "tables", x), stringsAsFactors = FALSE)
    same <- function(a, b, tol = 1e-6) stopifnot(length(a) == length(b), max(abs(a - b) / pmax(abs(b), 1)) < tol)
    reg <- d$sim$regional
    a <- sim_allocation(reg, p)
    al <- py("scen_allocation_default.csv")
    ok("python: same region order", stopifnot(identical(reg$admin1, al$admin1)))
    ok("python: eligible and severe by region", { same(a$E, al$eligible_hh); same(a$S, al$severe_hh) })
    for (r in names(SIM_RULES)) ok(sprintf("python: rule %s by region", r), same(a$H[[r]], al[[paste0("H_", r)]]))
    su <- py("scen_allocation_summary.csv")
    for (k in c("households", "coverage", "severe_reached", "min_regional_coverage", "regions_below_20pct")) ok(paste("python: rule summary", k), same(a$summary[[k]], su[[k]]))
    res <- jsonlite::fromJSON(file.path(mdir, "scenario_results.json"))
    ok("python: full requirement", same(a$full_requirement, res$full_requirement))
    fu <- py("scen_funding_tradeoffs.csv"); f2 <- sim_funding(reg, p, d$sim$inputs$budget_changes)
    for (k in c("budget_change", "budget", "households", "people", "coverage", "transfer", "adequacy_vs_ref", "pct_meb", "months", "gap_households")) ok(paste("python: funding", k), same(f2[[k]], fu[[k]]))
    ok("python: funding designs", stopifnot(identical(f2$design, fu$design)))
    pr <- py("scen_prices.csv"); p2 <- sim_prices(reg, p, d$sim$inputs$price_shocks)
    for (k in intersect(names(pr), names(p2))) ok(paste("python: prices", k), same(p2[[k]], pr[[k]]))
    mo <- py("scen_modality.csv"); m2 <- sim_modality(reg, p, d$sim$inputs)
    for (k in c("cost_hh_month", "value_to_hh", "cost_per_xaf_value", "households_fundable")) ok(paste("python: modality", k), same(m2[[k]][1:3], mo[[k]]))
    ok("workbook: mixed modality", same(m2$cost_per_xaf_value[4], 1.1310512985788792))
    de <- py("scen_delivery.csv"); d2 <- sim_delivery(reg, p, d$sim$inputs)
    ok("python: delivery", same(d2$table$households, de$households))
    ok("python: months lost, buffer", { same(d2$months_lost, res$assistance_months_lost); same(d2$buffer_cash, res$buffer_cash_xaf) })
    cb <- sim_combined(reg, p, d$sim$inputs)
    ok("python: combined", { same(cb$H_indexed, res$combined$H_indexed); same(cb$H_fixed, res$combined$H_fixed); same(cb$coverage_indexed, res$combined$coverage_indexed) })
    ns <- py("scen_need_share_by_indicator.csv"); n2 <- sim_need_shares(reg, p)
    ok("python: need shares and ranks", {
      same(n2$share_cariB, ns$share_cariPB_fi); same(n2$share_cariC, ns$share_cariPC_fi); same(n2$share_fcs, ns$share_fcs28_pb)
      same(n2$rank_cariB, ns$rank_cariPB_fi); same(n2$rank_cariC, ns$rank_cariPC_fi); same(n2$rank_fcs, ns$rank_fcs28_pb)
    })
    to <- py("tornado.csv"); t2 <- sim_tornado(reg, p)
    ok("python: tornado", { same(t2$low, to$low); same(t2$high, to$high) })
    # The model's national estimates against the dashboard's own, in every weighted round.
    ne <- py("national_estimates_all_rounds.csv"); ne <- ne[ne$weight_basis == "survey weights", ]
    pairs <- list(fcs_mean = c("fcs_mean_w", 1), fcs28_poor = c("fcs_poor_w", 100), rcsi_mean = c("rcsi_mean_w", 1), rcsi_ge19 = c("rcsi_p3_w", 100),
                  hhs_phase3p = c("hhs_p3_w", 100), hdds_mean = c("hdds_mean_w", 1), hdds_phase3p = c("hdds_p3_w", 100), fes_ge75 = c("fes_75_w", 100),
                  lcs_common_crisis_plus = c("lcs_ce_w", 100))
    for (k in names(pairs)) {
      ok(sprintf("model = dashboard: %s", k), {
        x <- ne[ne$indicator_key == k, ]
        v <- d$ind_round[[pairs[[k]][1]]][match(x$round_id, d$ind_round$round_id)]
        stopifnot(nrow(x) >= 9, max(abs(x$w_est * as.numeric(pairs[[k]][2]) - v)) < 1e-6)
      })
    }
    ok("model input is the current merged file", stopifnot(isTRUE(d$sim$meta$input_matches)))
  } else {
    cat("models folder absent: reconciliation with the Python model skipped\n")
  }

  # Data boundary of the model's tables.
  ok("sim: regional estimates rest on 30+ households", stopifnot(all(d$sim$regional$n >= 30)))
  ok("sim: small groups have no estimates", {
    small <- d$sim$profiles[d$sim$profiles$n < 100, ]
    stopifnot(nrow(small) > 0, all(is.na(small$cariPB_fi)), all(is.na(small$fcs28_pb)))
  })
  ok("sim: draws and working tables stay out", stopifnot(!any(grepl("mc_draws|availability|crosswalk_raw", list.files("data")))))
  if (dir.exists("demo_data")) {
    ok("sim: synthetic mode shows no real regional estimate", {
      dm <- utils::read.csv("demo_data/sim_regional.csv")
      r <- d$sim$regional; dm <- dm[match(r$admin1, dm$admin1), ]
      for (k in c("weight_share", "cariPB_fi", "cariPB_sev", "fcs28_pb", "rcsi_ge19", "hhs_modsev", "fcs_mean")) stopifnot(!any(abs(r[[k]] - dm[[k]]) < 1e-9))
      dn <- utils::read.csv("demo_data/sim_national.csv")
      stopifnot(!any(abs(d$sim$national$est - dn$est) < 1e-9))
      dmc <- utils::read.csv("demo_data/sim_mc_summary.csv")
      stopifnot(!any(abs(d$sim$mc_summary$p50 - dmc$p50) < 1e-9))
    })
  }
}
ok("simulation without model outputs", {
  d0 <- d; d0$sim <- NULL
  simulation_ui("x", d0)
  testServer(simulation_server, args = list(d = d0), invisible(TRUE))
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
