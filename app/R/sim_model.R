# Accounting scenarios of the Chad humanitarian operations simulation, in R, so that the page can
# recompute them live. Mirrors models/.../scripts/02_scenarios.py and the workbook's formulas;
# tests/test_app.R reconciles every function with the Python outputs at the reference inputs.
# Accounting only: no effect of assistance or prices on food security is modelled.

SIM_NEED <- list(
  cariB = list(fi = "cariPB_fi", sev = "cariPB_sev", label = "CARI-proxy B (default)", severe = "CARI-proxy B, severely food insecure"),
  cariC = list(fi = "cariPC_fi", sev = "cariPC_sev", label = "CARI-proxy C (no food share)", severe = "CARI-proxy C, severely food insecure"),
  fcs = list(fi = "fcs28_pb", sev = "fcs28_poor", label = "FCS poor + borderline (28/42)", severe = "FCS poor")
)
SIM_RULES <- c(A = "A · Proportional to caseload", B = "B · Severity-tiered", C = "C · Equity floor", D = "D · Severity ranking")

# The reference design: John's scenario_defaults.json.
sim_params <- function(sim) {
  i <- sim$inputs
  list(frame = i$frame_hh$value, transfer = i$transfer_T$value, months = i$months_M$value, delivery = i$delivery_rate_a$value,
       fixed = i$fixed_cost_F$value, budget = i$budget_ref$value, floor = i$min_cov_m$value, meb = i$meb$value,
       hhsize = sim$meta$mean_hhsize, need = "cariB", price = 0, indexed = FALSE)
}

sim_caseload <- function(reg, p) {
  n <- SIM_NEED[[p$need]]
  list(E = p$frame * reg$weight_share * reg[[n$fi]], S = p$frame * reg$weight_share * reg[[n$sev]], sev_rate = reg[[n$sev]])
}

sim_cost_hh <- function(transfer, months, delivery) months * transfer * (1 + delivery)

# An indexed transfer rises with prices and costs more; a fixed one costs the same and buys less.
sim_transfer <- function(p) if (isTRUE(p$indexed)) p$transfer * (1 + p$price) else p$transfer

sim_capacity <- function(p) max(p$budget - p$fixed, 0) / sim_cost_hh(sim_transfer(p), p$months, p$delivery)

sim_allocate <- function(E, S, cap, rule, floor, sev_rate) {
  Et <- sum(E); St <- sum(S)
  if (Et <= 0) return(0 * E)
  switch(rule,
    A = E * min(1, cap / Et),
    B = {
      if (cap <= St) S * cap / max(St, 1e-12)
      else S + (E - S) * min(1, (cap - St) / max(sum(E - S), 1e-12))
    },
    C = {
      low <- floor * E
      if (sum(low) >= cap) E * cap / Et
      else low + pmin(E - low, (cap - sum(low)) * S / max(St, 1e-12))
    },
    D = {
      H <- 0 * E; left <- cap
      for (i in order(-sev_rate)) {
        H[i] <- max(0, min(E[i], left))
        left <- left - H[i]
      }
      H
    },
    stop("unknown rule ", rule)
  )
}

sim_rule_summary <- function(E, S, H, rule) {
  reached <- if (rule == "B") pmin(H, S) else ifelse(E > 0, H * S / E, 0)
  cov <- ifelse(E > 0, H / E, 0)
  data.frame(rule = rule, households = sum(H), coverage = sum(H) / max(sum(E), 1e-12),
             severe_reached = sum(reached) / max(sum(S), 1e-12), min_regional_coverage = min(cov),
             regions_below_20pct = sum(cov < 0.2), stringsAsFactors = FALSE)
}

# All four rules at the design p. Regions stay in alphabetical order, as in the workbook.
sim_allocation <- function(reg, p) {
  cl <- sim_caseload(reg, p)
  cap <- sim_capacity(p)
  H <- lapply(stats::setNames(names(SIM_RULES), names(SIM_RULES)), function(r) sim_allocate(cl$E, cl$S, cap, r, p$floor, cl$sev_rate))
  summary <- do.call(rbind, lapply(names(H), function(r) sim_rule_summary(cl$E, cl$S, H[[r]], r)))
  cost <- sim_cost_hh(sim_transfer(p), p$months, p$delivery)
  list(E = cl$E, S = cl$S, H = H, summary = summary, capacity = cap, cost_hh = cost,
       full_requirement = sum(cl$E) * cost + p$fixed)
}

# One budget change, three ways of absorbing it.
sim_funding <- function(reg, p, changes) {
  Et <- sum(sim_caseload(reg, p)$E)
  c0 <- sim_cost_hh(p$transfer, p$months, p$delivery)
  Href <- min(Et, max(p$budget - p$fixed, 0) / c0)
  do.call(rbind, lapply(c(0, changes), function(d) {
    Bd <- p$budget * (1 + d); Bn <- max(Bd - p$fixed, 0)
    H1 <- min(Et, Bn / c0)
    T2 <- if (Href > 0) Bn / (Href * p$months * (1 + p$delivery)) else NA_real_
    M3 <- if (Href > 0) Bn / (Href * p$transfer * (1 + p$delivery)) else NA_real_
    data.frame(
      budget_change = d, design = c("Protect transfer & duration", "Protect coverage & duration", "Protect coverage & transfer"),
      budget = Bd, households = c(H1, Href, Href), people = c(H1, Href, Href) * p$hhsize, coverage = c(H1, Href, Href) / max(Et, 1e-12),
      transfer = c(p$transfer, T2, p$transfer), adequacy_vs_ref = c(1, T2 / p$transfer, 1), pct_meb = c(p$transfer, T2, p$transfer) / p$meb,
      months = c(p$months, p$months, M3), gap_households = Et - c(H1, Href, Href), stringsAsFactors = FALSE)
  }))
}

sim_prices <- function(reg, p, shocks) {
  Et <- sum(sim_caseload(reg, p)$E)
  Bn <- max(p$budget - p$fixed, 0)
  Href <- min(Et, Bn / sim_cost_hh(p$transfer, p$months, p$delivery))
  s <- c(0, shocks)
  data.frame(price_shock = s, real_transfer_fixed = p$transfer / (1 + s), purchasing_power_fixed = 1 / (1 + s),
             pct_meb_fixed = p$transfer / (p$meb * (1 + s)), transfer_indexed = p$transfer * (1 + s),
             extra_budget_indexed = Href * p$months * p$transfer * s * (1 + p$delivery),
             households_indexed_fixed_budget = pmin(Et, Bn / (p$months * p$transfer * (1 + s) * (1 + p$delivery))))
}

# Without a price shock. See the note on the Trade-offs tab.
sim_modality <- function(reg, p, inputs) {
  ik <- inputs$inkind
  Et <- sum(sim_caseload(reg, p)$E)
  Bn <- max(p$budget - p$fixed, 0)
  r <- unlist(ik$ration_kg_pp_day)
  days <- 30 * ik$ration_scale * p$hhsize
  kg <- sum(r) * days
  proc <- sum(r * unlist(ik$procurement_xaf_per_kg)[names(r)]) * days
  retail <- sum(r * unlist(ik$retail_xaf_per_kg)[names(r)]) * days
  cost_ik <- (proc + ik$ltsh_xaf_per_kg * kg) / (1 - ik$loss_rate)
  cost_cash <- p$transfer * (1 + p$delivery)
  share <- inputs$cash_share$value
  x <- data.frame(modality = c("Cash", "Voucher", "In-kind", sprintf("Mixed (%d%% cash)", round(100 * share))),
                  cost_hh_month = c(cost_cash, p$transfer * (1 + inputs$voucher$fee_rate), cost_ik, share * cost_cash + (1 - share) * cost_ik),
                  value_to_hh = c(p$transfer, p$transfer, retail, share * p$transfer + (1 - share) * retail),
                  stringsAsFactors = FALSE)
  x$cost_per_xaf_value <- x$cost_hh_month / x$value_to_hh
  x$households_fundable <- pmin(Et, Bn / (x$cost_hh_month * p$months))
  attr(x, "kg_hh_month") <- kg
  x
}

sim_delivery <- function(reg, p, inputs) {
  dl <- inputs$delivery
  Et <- sum(sim_caseload(reg, p)$E)
  Bn <- max(p$budget - p$fixed, 0)
  Href <- min(Et, Bn / sim_cost_hh(p$transfer, p$months, p$delivery))
  add <- c(0, dl$cost_increase_points)
  list(table = data.frame(cost_increase = add, households = pmin(Et, Bn / (p$months * p$transfer * (1 + p$delivery + add)))),
       months_lost = Href * min(dl$delay_months, p$months) * (1 - dl$recoverable_share),
       delay_months = dl$delay_months, lead_time = dl$lead_time_months,
       buffer_cash = Href * p$transfer * dl$lead_time_months)
}

sim_combined <- function(reg, p, inputs) {
  cb <- inputs$combined
  Et <- sum(sim_caseload(reg, p)$E)
  Bn <- max(p$budget * (1 + cb$funding) - p$fixed, 0)
  a <- p$delivery + cb$delivery_add
  idx <- min(Et, Bn / (p$months * p$transfer * (1 + cb$price) * (1 + a)))
  fix <- min(Et, Bn / (p$months * p$transfer * (1 + a)))
  list(price = cb$price, funding = cb$funding, delivery_add = cb$delivery_add, H_indexed = idx, H_fixed = fix,
       coverage_indexed = idx / max(Et, 1e-12), coverage_fixed = fix / max(Et, 1e-12), real_adequacy_fixed = 1 / (1 + cb$price))
}

# Caseload shares and ranks under each need indicator: does the top group depend on the indicator?
sim_need_shares <- function(reg, p) {
  out <- data.frame(admin1 = reg$admin1, stringsAsFactors = FALSE)
  for (k in names(SIM_NEED)) {
    p$need <- k
    e <- sim_caseload(reg, p)$E
    out[[paste0("share_", k)]] <- e / sum(e)
    out[[paste0("rank_", k)]] <- as.integer(rank(-e, ties.method = "average"))
  }
  out
}

# One-way sensitivity of households reached, around the design p.
sim_tornado <- function(reg, p) {
  Et <- sum(sim_caseload(reg, p)$E)
  h <- function(budget = p$budget, fixed = p$fixed, transfer = p$transfer, months = p$months, delivery = p$delivery) {
    min(Et, max(budget - fixed, 0) / sim_cost_hh(transfer, months, delivery))
  }
  x <- data.frame(
    param = c("Fixed cost 300m / 0 XAF", "Delivery rate 15% / 2%", "Indexed price rise 30% / 0%", "Transfer 60k / 45k XAF",
              "Budget -25% / +25%", "Duration 6 / 3 months"),
    low = c(h(fixed = 3e8), h(delivery = 0.15), h(transfer = p$transfer * 1.3), h(transfer = 60000), h(budget = p$budget * 0.75), h(months = 6)),
    high = c(h(fixed = 0), h(delivery = 0.02), h(), h(transfer = 45000), h(budget = p$budget * 1.25), h(months = 3)),
    stringsAsFactors = FALSE)
  x$range <- x$high - x$low
  x
}
