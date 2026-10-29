# Server-side checks of every page of the app: builds each UI and renders every output
# (including all indicator / filter combinations) with shiny::testServer.
# Run from the app/ folder, after prepare_app_data.R:   Rscript tests/test_app.R
# Exits with status 1 if any check fails.

args <- commandArgs(trailingOnly = TRUE)
setwd(if (length(args)) args[1] else ".")
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
for (m in c("overview", "process", "crosswalk", "rounds", "validation", "indicators", "issues", "about")) {
  ok(paste("ui:", m), get(paste0(m, "_ui"))(m, d))
}

testServer(overview_server, args = list(d = d), { ok("overview$hh_plot", output$hh_plot) })

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
testServer(indicators_server, args = list(d = d), {
  for (est in c("w", "u")) for (fb in c(TRUE, FALSE)) for (m in MAP_CHOICES) {
    session$setInputs(estimate = est, fallback = fb, season = c("2", "10"), region_metric = m,
                      regions = c("Lac", "Ouaddai", "Wadi Fira"))
    lab <- sprintf("ind[%s,%s,%s]", est, fb, m)
    ok(paste(lab, "fcs/rcsi"), { output$fcs; output$rcsi })
    ok(paste(lab, "heat/trend"), { output$heat; output$trend; output$heat_title })
  }
  session$setInputs(season = "10"); ok("ind season=Oct", { output$fcs; output$heat; output$trend })
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
