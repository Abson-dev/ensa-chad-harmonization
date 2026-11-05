# Simulation: John's humanitarian operations model. The accounting scenarios recompute live from the
# inputs (sim_model.R); survey estimates and Monte Carlo results are fixed outputs of the model's run.

SIM_METRICS <- c(
  "CARI-proxy B: moderately + severely food insecure" = "cariPB_fi", "CARI-proxy B: severely food insecure" = "cariPB_sev",
  "CARI-proxy C (no food share)" = "cariPC_fi", "FCS poor + borderline (28/42)" = "fcs28_pb", "FCS poor (28)" = "fcs28_poor",
  "rCSI 19+" = "rcsi_ge19", "Hunger scale moderate or severe" = "hhs_modsev", "LCS crisis + emergency (round-specific)" = "lcs_crisis_plus",
  "Food share of spending 75%+" = "fes_ge75", "HDDS phase 3+" = "hdds_phase3p"
)
SIM_GROUP_METRICS <- c("CARI-proxy B: moderately + severely food insecure" = "cariPB_fi", "CARI-proxy B: severely food insecure" = "cariPB_sev",
                       "FCS poor + borderline (28/42)" = "fcs28_pb", "rCSI 19+" = "rcsi_ge19", "Hunger scale moderate or severe" = "hhs_modsev")
SIM_CHAR <- c(head_sex = "Sex of head", head_edu = "Education of head", head_age = "Age of head",
              hh_size_class = "Household size", income = "Main income")

sim_pct <- function(x, d = 1) fmt_pct(100 * x, d)
sim_hh <- function(x) ifelse(is.na(x), "–", fmt_int(round(x)))
sim_bn <- function(x) ifelse(is.na(x), "–", sprintf("XAF %s bn", formatC(x / 1e9, format = "f", digits = 2)))
sim_chg <- function(x) ifelse(x == 0, "Reference", sprintf("%+d%%", round(100 * x)))
sim_tbl <- function(x, columns = NULL, ...) {
  reactable::reactable(x, columns = columns, compact = TRUE, pagination = FALSE, striped = TRUE, sortable = FALSE,
                       highlight = TRUE, class = "dark-table", ...)
}
sim_right <- function(name, min = 90) reactable::colDef(name = name, align = "right", minWidth = min)

# Estimate with its approximate 95% interval, one row per category, on one percentage axis.
sim_dots <- function(labels, est, se, ref = NULL, ref_label = NULL) {
  v <- 100 * est; e <- 1.96 * 100 * se
  hover <- sprintf("%s<br><b>%s</b> (approx. 95%% CI %s to %s)", labels, fmt_pct(v), fmt_pct(pmax(v - e, 0)), fmt_pct(pmin(v + e, 100)))
  shapes <- annotations <- list()
  if (!is.null(ref)) {
    shapes <- list(list(type = "line", yref = "paper", y0 = 0, y1 = 1, x0 = 100 * ref, x1 = 100 * ref,
                        line = list(color = COL$muted, width = 1, dash = "dot")))
    annotations <- list(list(x = 100 * ref, y = 1, yref = "paper", yanchor = "bottom", showarrow = FALSE,
                             text = ref_label, font = list(size = 11, color = COL$muted)))
  }
  plotly::plot_ly(x = v, y = factor(labels, levels = labels), type = "scatter", mode = "markers",
                  marker = list(color = COL$blue, size = 9, line = list(color = "#fff", width = 2)),
                  error_x = list(type = "data", array = pmin(e, 100 - v), arrayminus = pmin(e, v), color = "#7FB9DA", thickness = 2, width = 0),
                  text = hover, hoverinfo = "text") |>
    plotly_style(legend = FALSE, margin = list(t = 24, r = 20, b = 30, l = 10), shapes = shapes, annotations = annotations,
                 xaxis = list(title = "", ticksuffix = "%", rangemode = "tozero"),
                 yaxis = list(title = "", tickfont = list(size = 11), showgrid = FALSE, dtick = 1))
}

simulation_ui <- function(id, d) {
  ns <- shiny::NS(id)
  if (is.null(d$sim)) {
    return(htmltools::tagList(
      page_intro("Simulation", "Humanitarian operations scenarios.", "sliders"),
      callout("The model's outputs are not in this copy of the app. Run prepare_app_data.R with the models folder in place.", type = "info")
    ))
  }
  sim <- d$sim
  p0 <- sim_params(sim)
  m <- sim$meta
  chip <- htmltools::div(class = "round-chip", bsicons::bs_icon("calendar3"), htmltools::strong("Baseline: Oct 2025"),
                         htmltools::span(sprintf("%s to %s", format(as.Date(m$baseline_dates[1]), "%d %b"), format(as.Date(m$baseline_dates[2]), "%d %b %Y"))))
  regions_note <- "* Unstable estimate: fewer than 400 households, or a 95% half-width above 10 points."

  planner <- bslib::layout_columns(
    col_widths = bslib::breakpoints(sm = 12, lg = c(3, 9)),
    bslib::card(
      bslib::card_header(bsicons::bs_icon("sliders"), " Your assumptions"),
      bslib::card_body(
        class = "sim-inputs", gap = "0.2rem",
        shiny::selectInput(ns("need"), "Who counts as in need", stats::setNames(names(SIM_NEED), vapply(SIM_NEED, `[[`, "", "label"))),
        shiny::selectInput(ns("rule"), "Allocation rule", stats::setNames(names(SIM_RULES), SIM_RULES), selected = "B"),
        shiny::sliderInput(ns("budget"), "Budget (XAF billion)", 1, 20, p0$budget / 1e9, step = 0.1),
        shiny::sliderInput(ns("transfer"), "Transfer (XAF per household per month)", 20000, 132000, p0$transfer, step = 1000, sep = ","),
        shiny::sliderInput(ns("months"), "Duration (months)", 1, 12, p0$months, step = 1),
        shiny::sliderInput(ns("delivery"), "Delivery cost (% of transfer)", 0, 30, 100 * p0$delivery, step = 1, post = "%"),
        shiny::sliderInput(ns("fixed"), "Fixed cost (XAF million)", 0, 1000, p0$fixed / 1e6, step = 25),
        shiny::sliderInput(ns("floor"), "Equity floor, rule C (% of each caseload)", 0, 100, 100 * p0$floor, step = 5, post = "%"),
        shiny::sliderInput(ns("price"), "Food price rise", 0, 50, 0, step = 5, post = "%"),
        shiny::checkboxInput(ns("indexed"), "Index the transfer to prices", FALSE),
        shiny::numericInput(ns("frame"), "Planning frame (households, not a population count)", p0$frame, min = 1000, step = 1000),
        shiny::actionButton(ns("reset"), "Back to reference values", icon = shiny::icon("rotate-left"), class = "btn-sm btn-outline-primary mt-2")
      )
    ),
    htmltools::tagList(
      shiny::uiOutput(ns("kpis")),
      bslib::card(
        bslib::card_header("The four allocation rules at these assumptions"),
        bslib::card_body(padding = 0, reactable::reactableOutput(ns("rules"))),
        bslib::card_footer(class = "table-note", "Severe tier reached: proportional within regions for A, C and D; severe households first for B, which assumes they can be identified one by one. The rules allocate by measured need, not by expected impact.")
      ),
      bslib::card(
        full_screen = TRUE, bslib::card_header(shiny::textOutput(ns("region_title"), inline = TRUE)),
        plotly::plotlyOutput(ns("regions"), height = "560px"),
        bslib::card_footer(class = "table-note", paste(regions_note, "Households within the planning frame: shares of the frame, not beneficiary numbers."))
      ),
      bslib::card(
        full_screen = TRUE,
        bslib::card_header(class = "d-flex justify-content-between align-items-center", "Region by rule",
                           shiny::downloadButton(ns("download"), "CSV", class = "btn-sm btn-outline-primary")),
        bslib::card_body(padding = 0, reactable::reactableOutput(ns("region_table")))
      )
    )
  )

  baseline <- htmltools::tagList(
    bslib::layout_columns(
      col_widths = bslib::breakpoints(sm = 12, lg = c(6, 6)),
      bslib::card(height = 620, full_screen = TRUE, bslib::card_header("National baseline, rural Chad"),
                  bslib::card_body(padding = 0, reactable::reactableOutput(ns("national"))),
                  bslib::card_footer(class = "table-note", "People: share of people living in such households. Approximate 95% intervals: strata = department, pseudo-PSU = sub-prefecture (true PSUs are not in the file). CARI-proxy indicators are analytical; they are not official CARI, IPC or Cadre Harmonisé results.")),
      bslib::card(height = 620, full_screen = TRUE,
                  bslib::card_header(shiny::selectInput(ns("metric"), "Indicator by region", SIM_METRICS, width = "100%")),
                  plotly::plotlyOutput(ns("forest"), height = "100%"),
                  bslib::card_footer(class = "table-note", paste(regions_note, "Good for broad priority groups, not for a fine ranking.")))
    ),
    bslib::layout_columns(
      col_widths = bslib::breakpoints(sm = 12, lg = c(6, 6)),
      bslib::card(height = 660, full_screen = TRUE,
                  bslib::card_header(shiny::selectInput(ns("group_metric"), "Indicator by household characteristic", SIM_GROUP_METRICS, width = "100%")),
                  plotly::plotlyOutput(ns("groups"), height = "100%"),
                  bslib::card_footer(class = "table-note", "Descriptive associations, not causes. Groups under 100 interviews are not shown.")),
      bslib::card(height = 660, full_screen = TRUE, bslib::card_header("Population groups, 2024 rounds (indicative only)"),
                  callout("Population group was not recorded in Oct 2025, so refugees, returnees and displaced households cannot be profiled at baseline. These 2024 rounds have no survey weights, and these samples may come from separate strata.", type = "warning"),
                  bslib::card_body(padding = 0, reactable::reactableOutput(ns("popgroups"))),
                  bslib::card_footer(class = "table-note", "FCS P+B: poor + borderline, 28/42. HHS 2+: moderate or severe hunger."))
    )
  )

  tradeoffs <- htmltools::tagList(
    callout("These panels follow the budget, transfer, duration, delivery and frame set in the planner, without its price rise.", type = "info"),
    htmltools::h5("When the budget changes, what absorbs it?"),
    bslib::layout_columns(
      col_widths = bslib::breakpoints(sm = 12, lg = c(4, 4, 4)),
      bslib::card(bslib::card_header("Protect transfer and duration: coverage moves"), plotly::plotlyOutput(ns("f_cov"), height = "230px")),
      bslib::card(bslib::card_header("Protect coverage and duration: transfer moves"), plotly::plotlyOutput(ns("f_tr"), height = "230px")),
      bslib::card(bslib::card_header("Protect coverage and transfer: months move"), plotly::plotlyOutput(ns("f_mo"), height = "230px"))
    ),
    bslib::card(bslib::card_header("Funding scenarios by design"), bslib::card_body(padding = 0, reactable::reactableOutput(ns("funding"))),
                bslib::card_footer(class = "table-note", "Which option better protects food security cannot be read from these data: the effect of transfer size on outcomes was not estimated.")),
    bslib::layout_columns(
      col_widths = bslib::breakpoints(sm = 12, lg = c(6, 6)),
      bslib::card(bslib::card_header("Food prices: fixed or indexed transfer"), bslib::card_body(padding = 0, reactable::reactableOutput(ns("prices"))),
                  bslib::card_footer(class = "table-note", "Hypothetical shocks, alternatives to each other. The MEB is assumed to move one-for-one with food prices. No effect on FCS, rCSI or HHS is simulated.")),
      bslib::card(bslib::card_header("Delivery costs and delay"), bslib::card_body(padding = 0, reactable::reactableOutput(ns("delivery_tbl"))),
                  bslib::card_footer(shiny::uiOutput(ns("delivery_note"), class = "table-note")))
    ),
    bslib::layout_columns(
      col_widths = bslib::breakpoints(sm = 12, lg = c(7, 5)),
      bslib::card(bslib::card_header("Modality, no price shock"), bslib::card_body(padding = 0, reactable::reactableOutput(ns("modality"))),
                  bslib::card_footer(class = "table-note", "Illustrative costs and ration. Markets, protection, preferences and nutritional adequacy are not assessed. Comparison under a price shock is not shown: its definition of value is being reviewed.")),
      bslib::card(bslib::card_header("Combined shock"), bslib::card_body(shiny::uiOutput(ns("combined"))))
    )
  )

  robustness <- htmltools::tagList(
    callout(sprintf("Monte Carlo: %s draws, seed %s, at the reference inputs. It does not follow the planner.", fmt_int(sim$inputs$monte_carlo$draws), sim$inputs$monte_carlo$seed), type = "info"),
    bslib::layout_columns(
      col_widths = bslib::breakpoints(sm = 12, lg = c(6, 6)),
      bslib::card(height = 430, full_screen = TRUE, bslib::card_header("Monte Carlo: median and 90% range"),
                  plotly::plotlyOutput(ns("mc"), height = "100%"),
                  bslib::card_footer(class = "table-note", "Rule B reaches 100% of the severe tier by construction, if that tier can be identified household by household. It is an assumption, not a finding. Price, funding and delivery ranges are analyst assumptions.")),
      bslib::card(height = 430, full_screen = TRUE, bslib::card_header("Chance of being among the five largest caseloads"),
                  plotly::plotlyOutput(ns("top5"), height = "100%"),
                  bslib::card_footer(class = "table-note", "Caseload share = prevalence × share of survey weight. Regions never in the top five are left out."))
    ),
    bslib::layout_columns(
      col_widths = bslib::breakpoints(sm = 12, lg = c(6, 6)),
      bslib::card(height = 430, full_screen = TRUE, bslib::card_header("Households reached: one input at a time"),
                  plotly::plotlyOutput(ns("tornado"), height = "100%"),
                  bslib::card_footer(class = "table-note", "Follows the planner's budget, transfer, duration, delivery and frame. The dotted line is the planner's design without a price rise.")),
      bslib::card(height = 430, full_screen = TRUE, bslib::card_header("Does the top group depend on the need indicator?"),
                  bslib::card_body(padding = 0, reactable::reactableOutput(ns("shares"))))
    )
  )

  targeting <- htmltools::tagList(
    bslib::card(bslib::card_header("Targeting rules against the analytical benchmark (CARI-proxy B)"),
                bslib::card_body(padding = 0, reactable::reactableOutput(ns("targeting"))),
                bslib::card_footer(class = "table-note", "Agreement with another survey classification, not verified inclusion or exclusion errors. Rules marked “by construction” use components of the benchmark, so their agreement says little about real performance. Validate out of sample and with communities before adopting a rule.")),
    bslib::card(bslib::card_header(sprintf("Who is more likely to be food insecure? Weighted logit, in-sample AUC %s", formatC(m$logit_auc, format = "f", digits = 2))),
                bslib::card_body(padding = 0, reactable::reactableOutput(ns("logit"))),
                bslib::card_footer(class = "table-note", "Outcome: CARI-proxy B moderate or severe. Region fixed effects not shown. Interval from robust standard errors that ignore clustering, so too narrow. Predictive associations, not causes."))
  )

  read_first <- htmltools::tagList(
    bslib::layout_columns(
      col_widths = bslib::breakpoints(sm = 12, lg = c(6, 6)),
      bslib::card(bslib::card_header("What each result can support"), bslib::card_body(padding = 0, reactable::reactableOutput(ns("readiness")))),
      bslib::card(bslib::card_header("Limits"), bslib::card_body(htmltools::tags$ul(
        class = "small mb-0",
        htmltools::tags$li("The baseline describes October-November 2025, after the harvest. It does not measure conditions today."),
        htmltools::tags$li("No validated denominators: every household count is a share of a standard frame, not a beneficiary number."),
        htmltools::tags$li("Accounting only: nothing here estimates what assistance achieves. No causal effects were estimated."),
        htmltools::tags$li("CARI-type indicators are proxies; ECMEN is unavailable and the food share series has a module break."),
        htmltools::tags$li("Regional estimates show implausibly large swings between rounds for some regions, which suggests measurement or fieldwork effects. Do not rank on one indicator or one round."),
        htmltools::tags$li("Standard errors are approximate: true strata and clusters are not in the file."),
        htmltools::tags$li("The frame is rural and excludes N'Djamena. Displacement status is absent at baseline."),
        htmltools::tags$li("Confirm against the Cadre Harmonisé and recent monitoring before any operational use.")
      )))
    ),
    bslib::card(bslib::card_header("Assumptions and their status"), bslib::card_body(padding = 0, reactable::reactableOutput(ns("assumptions")))),
    shiny::uiOutput(ns("provenance"))
  )

  htmltools::tagList(
    page_intro("Simulation", "What a budget can buy under explicit assumptions, built on the October 2025 round. Model and technical note by John.", "sliders", chip),
    callout(htmltools::strong("Illustrative inputs. Not for deployment decisions. "),
            "Budget, costs, prices and the 100,000-household frame are planning assumptions, not verified figures or beneficiary numbers. These results show relative sizes and trade-offs, and are not official ENSA, CARI, IPC or Cadre Harmonisé results.",
            type = "warning"),
    bslib::navset_underline(
      id = ns("tab"),
      bslib::nav_panel("Scenario planner", htmltools::div(class = "pt-3", planner)),
      bslib::nav_panel("Baseline", htmltools::div(class = "pt-3", baseline)),
      bslib::nav_panel("Trade-offs", htmltools::div(class = "pt-3", tradeoffs)),
      bslib::nav_panel("Robustness", htmltools::div(class = "pt-3", robustness)),
      bslib::nav_panel("Targeting", htmltools::div(class = "pt-3", targeting)),
      bslib::nav_panel("Read first", htmltools::div(class = "pt-3", read_first))
    )
  )
}

simulation_server <- function(id, d) {
  shiny::moduleServer(id, function(input, output, session) {
    if (is.null(d$sim)) return(invisible())
    sim <- d$sim
    reg <- sim$regional
    p0 <- sim_params(sim)
    labels <- paste0(reg$admin1, ifelse(reg$flag_unstable, " *", ""))

    params <- shiny::reactive({
      shiny::req(input$need, input$budget, input$transfer, input$months, !is.null(input$delivery), !is.null(input$fixed),
                 !is.null(input$floor), !is.null(input$price), input$frame > 0)
      utils::modifyList(p0, list(need = input$need, budget = input$budget * 1e9, transfer = input$transfer, months = input$months,
                                 delivery = input$delivery / 100, fixed = input$fixed * 1e6, floor = input$floor / 100,
                                 price = input$price / 100, indexed = isTRUE(input$indexed), frame = input$frame))
    })
    # The trade-off panels vary the price or the delivery cost themselves.
    design <- shiny::reactive(utils::modifyList(params(), list(price = 0, indexed = FALSE)))
    alloc <- shiny::reactive(sim_allocation(reg, params()))

    shiny::observeEvent(input$reset, {
      shiny::updateSelectInput(session, "need", selected = p0$need)
      shiny::updateSelectInput(session, "rule", selected = "B")
      shiny::updateSliderInput(session, "budget", value = p0$budget / 1e9)
      shiny::updateSliderInput(session, "transfer", value = p0$transfer)
      shiny::updateSliderInput(session, "months", value = p0$months)
      shiny::updateSliderInput(session, "delivery", value = 100 * p0$delivery)
      shiny::updateSliderInput(session, "fixed", value = p0$fixed / 1e6)
      shiny::updateSliderInput(session, "floor", value = 100 * p0$floor)
      shiny::updateSliderInput(session, "price", value = 0)
      shiny::updateCheckboxInput(session, "indexed", value = FALSE)
      shiny::updateNumericInput(session, "frame", value = p0$frame)
    })

    output$kpis <- shiny::renderUI({
      a <- alloc(); p <- params(); s <- a$summary[a$summary$rule == input$rule, ]
      tr <- sim_transfer(p)
      real <- tr / (1 + p$price)
      unspent <- max(p$budget - p$fixed, 0) - s$households * a$cost_hh
      bslib::layout_column_wrap(
        width = "190px", fill = FALSE, heights_equal = "row",
        kpi("Households funded", sim_hh(s$households), sprintf("in a frame of %s; about %s people", fmt_int(p$frame), sim_hh(s$households * p$hhsize)), "people", "blue"),
        kpi("Coverage of the caseload", sim_pct(s$coverage), sprintf("%s eligible households", sim_hh(sum(a$E))), "pie-chart", "navy"),
        kpi("Severe tier reached", sim_pct(s$severe_reached), sprintf("%s severe households", sim_hh(sum(a$S))), "shield-exclamation", "red"),
        kpi("Lowest regional coverage", sim_pct(s$min_regional_coverage), sprintf("%d region(s) below 20%%", s$regions_below_20pct), "geo-alt", "orange"),
        kpi("Real value of the transfer (XAF)", fmt_int(round(real)),
            sprintf("%s of the MEB%s", sim_pct(real / p$meb, 0), if (p$price > 0) sprintf("; pays XAF %s", fmt_int(round(tr))) else ""), "cash-coin", "brown"),
        kpi("Budget to cover everyone (XAF)", sprintf("%s bn", formatC(a$full_requirement / 1e9, format = "f", digits = 2)), if (unspent > 1e6) sprintf("%s left unallocated by this rule", sim_bn(unspent)) else "at this design", "wallet2", "slate")
      )
    })

    output$rules <- reactable::renderReactable({
      x <- alloc()$summary
      sel <- match(input$rule, x$rule)
      tb <- data.frame(Rule = unname(SIM_RULES[x$rule]), Households = sim_hh(x$households), Coverage = sim_pct(x$coverage),
                       Severe = sim_pct(x$severe_reached), Lowest = sim_pct(x$min_regional_coverage), Below = x$regions_below_20pct)
      sim_tbl(tb, columns = list(Rule = reactable::colDef(minWidth = 190, class = "cell-label"), Households = sim_right("Households funded"),
                                 Coverage = sim_right("Coverage"), Severe = sim_right("Severe tier reached"),
                                 Lowest = sim_right("Lowest regional coverage"), Below = sim_right("Regions below 20%")),
              rowStyle = function(i) if (i == sel) list(fontWeight = 700, background = "#E6F2F8"))
    })

    output$region_title <- shiny::renderText(sprintf("Caseload funded and unfunded by region, rule %s", SIM_RULES[[input$rule]]))
    output$regions <- plotly::renderPlotly({
      a <- alloc(); H <- a$H[[input$rule]]
      o <- order(a$E)
      lv <- labels[o]
      cov <- ifelse(a$E > 0, H / a$E, 0)
      hover <- sprintf("%s<br>%s of %s eligible households funded (%s)", labels, sim_hh(H), sim_hh(a$E), sim_pct(cov, 0))
      plotly::plot_ly(y = factor(labels, levels = lv)) |>
        plotly::add_bars(x = H, name = "Funded", marker = list(color = COL$blue, line = list(color = "#fff", width = 1)), text = hover, hoverinfo = "text", textposition = "none") |>
        plotly::add_bars(x = a$E - H, name = "Not funded", marker = list(color = "#B9E5FB", line = list(color = "#fff", width = 1)), text = hover, hoverinfo = "text", textposition = "none") |>
        plotly_style(barmode = "stack", bargap = 0.3, margin = list(r = 16, b = 30, l = 10),
                     xaxis = list(title = "Households in the frame", separatethousands = TRUE), yaxis = list(title = "", tickfont = list(size = 11), showgrid = FALSE, dtick = 1)) |>
        plotly::layout(legend = list(traceorder = "normal"))
    })

    scenario_table <- shiny::reactive({
      a <- alloc(); n <- SIM_NEED[[params()$need]]
      data.frame(Region = reg$admin1, Unstable = ifelse(reg$flag_unstable, "yes", ""), Households_surveyed = reg$n,
                 Need_rate = round(100 * reg[[n$fi]], 1), Severe_rate = round(100 * reg[[n$sev]], 1), Eligible = round(a$E), Severe = round(a$S),
                 Rule_A = round(a$H$A), Rule_B = round(a$H$B), Rule_C = round(a$H$C), Rule_D = round(a$H$D), check.names = FALSE)
    })
    output$region_table <- reactable::renderReactable({
      x <- scenario_table(); x <- x[order(-x$Eligible), ]
      x$Region <- paste0(x$Region, ifelse(x$Unstable == "yes", " *", "")); x$Unstable <- NULL
      num <- function(name) reactable::colDef(name = name, align = "right", minWidth = 68, format = reactable::colFormat(separators = TRUE))
      sim_tbl(x, columns = list(Region = reactable::colDef(minWidth = 145, class = "cell-label"),
                                Households_surveyed = num("Surveyed"),
                                Need_rate = reactable::colDef(name = "Need %", align = "right", minWidth = 62, format = reactable::colFormat(digits = 1)), Severe_rate = reactable::colDef(name = "Severe %", align = "right", minWidth = 66, format = reactable::colFormat(digits = 1)),
                                Eligible = num("Eligible"), Severe = num("Severe"), Rule_A = num("Rule A"), Rule_B = num("Rule B"), Rule_C = num("Rule C"), Rule_D = num("Rule D")))
    })
    output$download <- shiny::downloadHandler(
      filename = function() sprintf("ENSA_Chad_simulation_illustrative_%s.csv", Sys.Date()),
      content = function(file) {
        p <- params()
        note <- sprintf("# ILLUSTRATIVE accounting scenario, not for deployment. Households are shares of a %s-household planning frame, not beneficiary numbers. Budget XAF %s; transfer %s; %s months; delivery %s; fixed cost XAF %s; floor %s; need %s; price rise %s, %s.",
                        fmt_int(p$frame), fmt_int(p$budget), fmt_int(p$transfer), p$months, sim_pct(p$delivery, 0), fmt_int(p$fixed), sim_pct(p$floor, 0), p$need, sim_pct(p$price, 0), if (p$indexed) "indexed" else "fixed transfer")
        con <- file(file, open = "wt", encoding = "UTF-8"); on.exit(close(con))
        writeLines(note, con)
        utils::write.csv(scenario_table(), con, row.names = FALSE)
      }
    )

    # ---- Baseline ----
    output$national <- reactable::renderReactable({
      x <- sim$national
      prop <- x$type == "prop"
      f <- function(v) ifelse(is.na(v), "–", ifelse(prop, sim_pct(v), formatC(v, format = "f", digits = 1)))
      tb <- data.frame(Indicator = x$indicator, Estimate = f(x$est), CI = paste0(f(x$lo), " to ", f(x$hi)), People = ifelse(prop, f(x$person), "–"), Unweighted = f(x$unweighted))
      sim_tbl(tb, columns = list(Indicator = reactable::colDef(minWidth = 150, class = "cell-label"), Estimate = sim_right("Estimate", 76),
                                 CI = sim_right("Approx. 95% CI", 100), People = sim_right("People", 62), Unweighted = sim_right("Unweighted", 92)))
    })
    output$forest <- plotly::renderPlotly({
      k <- input$metric; shiny::req(k)
      o <- order(reg[[k]])
      nat <- sim$national$est[match(k, sim$national$key)]
      sim_dots(labels[o], reg[[k]][o], reg[[paste0(k, "_se")]][o], ref = nat, ref_label = sprintf("National %s", sim_pct(nat)))
    })
    output$groups <- plotly::renderPlotly({
      k <- input$group_metric; shiny::req(k)
      x <- sim$profiles[!is.na(sim$profiles[[k]]), ]
      x$char <- factor(x$characteristic, levels = rev(names(SIM_CHAR)))
      x <- x[order(x$char, -seq_len(nrow(x))), ]
      nat <- sim$national$est[match(k, sim$national$key)]
      sim_dots(sprintf("%s: %s", SIM_CHAR[as.character(x$characteristic)], x$group), x[[k]], x[[paste0(k, "_se")]], ref = nat, ref_label = sprintf("National %s", sim_pct(nat)))
    })
    output$popgroups <- reactable::renderReactable({
      x <- sim$popgroups
      lab <- d$rounds$round[match(x$round_id, d$rounds$round_id)]
      tb <- data.frame(Round = lab, Group = x$pop_group, n = fmt_int(x$n), PB = sim_pct(x$fcs28_pb, 0), Poor = sim_pct(x$fcs28_poor, 0), rCSI = sim_pct(x$rcsi_ge19, 0), HHS = sim_pct(x$hhs_modsev, 0))
      sim_tbl(tb, columns = list(Round = reactable::colDef(minWidth = 72), Group = reactable::colDef(minWidth = 140, class = "cell-label"), n = sim_right("Surveyed", 68),
                                 PB = sim_right("FCS P+B", 54), Poor = sim_right("FCS poor", 54), rCSI = sim_right("rCSI 19+", 54), HHS = sim_right("HHS 2+", 54)))
    })

    # ---- Trade-offs ----
    funding <- shiny::reactive(sim_funding(reg, design(), sim$inputs$budget_changes))
    f_bars <- function(design_name, y, fmt, colour) {
      x <- funding(); x <- x[x$design == design_name, ]; x <- x[order(x$budget_change), ]
      lab <- sim_chg(x$budget_change)
      v <- y(x)
      plotly::plot_ly(x = factor(lab, levels = lab), y = v, type = "bar", marker = list(color = ifelse(x$budget_change == 0, COL$navy, colour)),
                      text = fmt(v), textposition = "outside", cliponaxis = FALSE, hovertemplate = "Budget %{x}: %{text}<extra></extra>") |>
        plotly_style(legend = FALSE, bargap = 0.35, margin = list(t = 24, r = 8, b = 30, l = 8), xaxis = list(title = ""),
                     yaxis = list(title = "", showticklabels = FALSE, showgrid = FALSE, range = c(0, 1.2 * max(c(v, 1e-9), na.rm = TRUE))))
    }
    output$f_cov <- plotly::renderPlotly(f_bars("Protect transfer & duration", function(x) x$coverage, function(v) sim_pct(v, 0), COL$blue))
    output$f_tr <- plotly::renderPlotly(f_bars("Protect coverage & duration", function(x) x$transfer, function(v) fmt_int(round(v)), COL$blue))
    output$f_mo <- plotly::renderPlotly(f_bars("Protect coverage & transfer", function(x) x$months, function(v) formatC(v, format = "f", digits = 1), COL$blue))
    output$funding <- reactable::renderReactable({
      x <- funding(); x <- x[order(x$budget_change, x$design), ]
      tb <- data.frame(Change = sim_chg(x$budget_change), Budget = sim_bn(x$budget), Design = x$design, Households = sim_hh(x$households), Coverage = sim_pct(x$coverage, 0),
                       Transfer = sim_hh(x$transfer), MEB = sim_pct(x$pct_meb, 0), Months = formatC(x$months, format = "f", digits = 1), Gap = sim_hh(x$gap_households))
      sim_tbl(tb, columns = list(Change = reactable::colDef(name = "Budget change", minWidth = 80), Budget = reactable::colDef(minWidth = 100), Design = reactable::colDef(minWidth = 180, class = "cell-label"),
                                 Households = sim_right("Households", 80), Coverage = sim_right("Coverage", 70), Transfer = sim_right("Transfer (XAF)", 80), MEB = sim_right("% of MEB", 60), Months = sim_right("Months", 60), Gap = sim_right("Unfunded households", 86)))
    })
    output$prices <- reactable::renderReactable({
      x <- sim_prices(reg, design(), sim$inputs$price_shocks)
      tb <- data.frame(Rise = sim_pct(x$price_shock, 0), Real = sim_hh(x$real_transfer_fixed), Power = sim_pct(x$purchasing_power_fixed, 0), MEB = sim_pct(x$pct_meb_fixed, 0), Indexed = sim_hh(x$transfer_indexed), Extra = sim_bn(x$extra_budget_indexed), H = sim_hh(x$households_indexed_fixed_budget))
      sim_tbl(tb, columns = list(Rise = reactable::colDef(name = "Price rise", minWidth = 54), Real = sim_right("Real value, fixed (XAF)", 76), Power = sim_right("Buying power", 66), MEB = sim_right("% of MEB", 54), Indexed = sim_right("Indexed transfer (XAF)", 76), Extra = sim_right("Extra budget to index", 94), H = sim_right("Households if indexed, same budget", 96)))
    })
    delivery_calc <- shiny::reactive(sim_delivery(reg, design(), sim$inputs))
    output$delivery_tbl <- reactable::renderReactable({
      x <- delivery_calc()$table
      base <- x$households[1]
      tb <- data.frame(Add = ifelse(x$cost_increase == 0, "Reference", sprintf("+%d points", round(100 * x$cost_increase))), H = sim_hh(x$households), Lost = sim_hh(base - x$households))
      sim_tbl(tb, columns = list(Add = reactable::colDef(name = "Delivery cost rate"), H = sim_right("Households funded"), Lost = sim_right("Households lost")))
    })
    output$delivery_note <- shiny::renderUI({
      x <- delivery_calc()
      htmltools::span(sprintf("A %d-month delay with nothing recovered loses %s household-months. A %d-month pipeline buffer at this coverage is %s in cash. Delays, access limits and lead times are inputs for supply-chain and access teams.",
                              x$delay_months, sim_hh(x$months_lost), x$lead_time, sim_bn(x$buffer_cash)))
    })
    output$modality <- reactable::renderReactable({
      x <- sim_modality(reg, design(), sim$inputs)
      tb <- data.frame(Modality = x$modality, Cost = sim_hh(x$cost_hh_month), Value = sim_hh(x$value_to_hh), Ratio = formatC(x$cost_per_xaf_value, format = "f", digits = 2), H = sim_hh(x$households_fundable))
      sim_tbl(tb, columns = list(Modality = reactable::colDef(minWidth = 120, class = "cell-label"), Cost = sim_right("Cost per household-month (XAF)"), Value = sim_right("Value to household (XAF)"), Ratio = sim_right("Cost per XAF of value", 76), H = sim_right("Households fundable")))
    })
    output$combined <- shiny::renderUI({
      x <- sim_combined(reg, design(), sim$inputs)
      htmltools::tagList(
        htmltools::p(class = "small", sprintf("Prices %+d%%, funding %+d%%, delivery cost +%d points, each applied once.", round(100 * x$price), round(100 * x$funding), round(100 * x$delivery_add))),
        bslib::layout_column_wrap(
          width = "170px", fill = FALSE, heights_equal = "row",
          kpi("Fixed transfer", sim_pct(x$coverage_fixed, 0), sprintf("coverage; each transfer buys %s of its target", sim_pct(x$real_adequacy_fixed, 0)), "cash-stack", "orange"),
          kpi("Indexed transfer", sim_pct(x$coverage_indexed, 0), "coverage; real value kept", "graph-up-arrow", "blue")
        )
      )
    })

    # ---- Robustness ----
    output$mc <- plotly::renderPlotly({
      x <- sim$mc_summary
      show <- c(severe_reached_D = "Severe tier reached, rule D", severe_reached_C = "Severe tier reached, rule C", severe_reached_B = "Severe tier reached, rule B",
                severe_reached_A = "Severe tier reached, rule A", coverage_indexed = "Coverage, indexed transfer", coverage_fixed_nominal = "Coverage, fixed transfer")
      x <- x[match(names(show), x$parameter), ]
      lab <- unname(show)
      hover <- sprintf("%s<br>Median <b>%s</b>, 90%% range %s to %s", lab, sim_pct(x$p50, 0), sim_pct(x$p05, 0), sim_pct(x$p95, 0))
      plotly::plot_ly(x = 100 * x$p50, y = factor(lab, levels = lab), type = "scatter", mode = "markers",
                      marker = list(color = COL$blue, size = 10, line = list(color = "#fff", width = 2)),
                      error_x = list(type = "data", array = 100 * (x$p95 - x$p50), arrayminus = 100 * (x$p50 - x$p05), color = "#7FB9DA", thickness = 3, width = 0),
                      text = hover, hoverinfo = "text") |>
        plotly_style(legend = FALSE, margin = list(t = 16, r = 20, b = 30, l = 10), xaxis = list(title = "", ticksuffix = "%", range = c(0, 105)), yaxis = list(title = "", showgrid = FALSE))
    })
    output$top5 <- plotly::renderPlotly({
      x <- sim$mc_top5; x <- x[x$prob_top5_need_share > 0, ]; x <- x[order(x$prob_top5_need_share), ]
      plotly::plot_ly(x = 100 * x$prob_top5_need_share, y = factor(x$admin1, levels = x$admin1), type = "bar", orientation = "h", marker = list(color = COL$blue),
                      text = sim_pct(x$prob_top5_need_share, 0), textposition = "outside", cliponaxis = FALSE, hovertemplate = "%{y}: %{text} of draws<extra></extra>") |>
        plotly_style(legend = FALSE, bargap = 0.35, margin = list(t = 16, r = 40, b = 16, l = 10), xaxis = list(title = "", showticklabels = FALSE, showgrid = FALSE, range = c(0, 112)), yaxis = list(title = "", showgrid = FALSE, dtick = 1, tickfont = list(size = 11)))
    })
    output$tornado <- plotly::renderPlotly({
      p <- design()
      x <- sim_tornado(reg, p); x <- x[order(x$range), ]
      ref <- min(sum(sim_caseload(reg, p)$E), sim_capacity(p))
      hover <- sprintf("%s<br>%s to %s households", x$param, sim_hh(x$low), sim_hh(x$high))
      plotly::plot_ly(x = x$range, base = x$low, y = factor(x$param, levels = x$param), type = "bar", orientation = "h", marker = list(color = COL$blue), text = hover, hoverinfo = "text", textposition = "none") |>
        plotly_style(legend = FALSE, bargap = 0.4, margin = list(t = 26, r = 20, b = 30, l = 10), xaxis = list(title = "Households reached", separatethousands = TRUE), yaxis = list(title = "", showgrid = FALSE),
                     shapes = list(list(type = "line", yref = "paper", y0 = 0, y1 = 1, x0 = ref, x1 = ref, line = list(color = COL$ink, width = 1, dash = "dot"))),
                     annotations = list(list(x = ref, y = 1, yref = "paper", yanchor = "bottom", showarrow = FALSE, text = sprintf("Design: %s", sim_hh(ref)), font = list(size = 11, color = COL$ink))))
    })
    output$shares <- reactable::renderReactable({
      x <- sim_need_shares(reg, design()); x <- x[order(x$rank_cariB), ]
      f <- function(s, r) sprintf("%s (#%d)", sim_pct(s), r)
      tb <- data.frame(Region = x$admin1, B = f(x$share_cariB, x$rank_cariB), C = f(x$share_cariC, x$rank_cariC), FCS = f(x$share_fcs, x$rank_fcs))
      sim_tbl(tb, columns = list(Region = reactable::colDef(minWidth = 140, class = "cell-label"), B = sim_right("CARI-proxy B: share (rank)"), C = sim_right("CARI-proxy C: share (rank)"), FCS = sim_right("FCS 28/42: share (rank)")))
    })

    # ---- Targeting ----
    output$targeting <- reactable::renderReactable({
      x <- sim$targeting
      tb <- data.frame(Rule = x$rule, Share = sim_pct(x$share_targeted, 0), Coverage = sim_pct(x$benchmark_coverage, 0), Exclusion = sim_pct(x$benchmark_relative_exclusion, 0), Inclusion = sim_pct(x$benchmark_relative_inclusion, 0), Linked = ifelse(x$mechanically_linked_to_benchmark, "By construction", "Independent"))
      sim_tbl(tb, columns = list(Rule = reactable::colDef(minWidth = 280, class = "cell-label"), Share = sim_right("Households targeted"), Coverage = sim_right("Benchmark households reached"), Exclusion = sim_right("Relative exclusion"), Inclusion = sim_right("Relative inclusion"), Linked = reactable::colDef(name = "Link to benchmark", minWidth = 110)))
    })
    output$logit <- reactable::renderReactable({
      x <- sim$logit
      x <- x[x$term != "const", ]
      term <- sub("^head_sex_", "Male head (vs female)", x$term)
      term[term == "Male head (vs female)Male"] <- "Male head (vs female)"
      term <- sub("^head_edu_(.*)", "Head's education: \\1 (vs higher)", term)
      term <- sub("^hh_size_class_(.*)", "Household size \\1 (vs 1-4)", term)
      term <- sub("^income_(.*)", "Main income: \\1 (vs agriculture/livestock)", term)
      lo <- exp(x$coef - 1.96 * x$se_robust_no_cluster); hi <- exp(x$coef + 1.96 * x$se_robust_no_cluster)
      f <- function(v) formatC(v, format = "f", digits = 2)
      tb <- data.frame(Term = term, OR = f(x$odds_ratio), CI = paste0(f(lo), " to ", f(hi)))
      sim_tbl(tb, columns = list(Term = reactable::colDef(minWidth = 320, class = "cell-label"), OR = sim_right("Odds ratio"), CI = sim_right("Robust 95% interval, no clustering", 150)))
    })

    # ---- Read first ----
    output$readiness <- reactable::renderReactable({
      tb <- data.frame(
        Conclusion = c("Baseline prevalence, national and by region", "Direction of change, Oct 2023 to Oct 2025", "Long-run trend 2018-2025", "CARI-proxy prevalence and severe tier",
                       "Regions by caseload share", "Absolute beneficiary numbers", "Budget, coverage and adequacy trade-off logic", "Modality cost ranking", "Effects of transfers on food security"),
        Readiness = c("Ready for planning, with intervals and survey date", "Ready; indicative for single regions", "Indicative only: questionnaire, weight and module breaks", "Indicative: proxy, food share comparability problem",
                      "Top group robust across indicators; a prioritisation input", "Not available: no validated denominator", "Method ready; numbers illustrative until inputs are verified", "Illustrative; needs verified costs and a market assessment", "Not estimated"),
        Evidence = c("Descriptive", "Descriptive", "Descriptive", "Descriptive (analytical)", "Descriptive + accounting", "–", "Accounting", "Accounting", "Causal (absent)"))
      sim_tbl(tb, columns = list(Conclusion = reactable::colDef(minWidth = 190, class = "cell-label"), Readiness = reactable::colDef(minWidth = 230), Evidence = reactable::colDef(minWidth = 100)))
    })
    output$assumptions <- reactable::renderReactable({
      i <- sim$inputs
      row <- function(name, v, unit, status) data.frame(Assumption = name, Value = v, Unit = unit, Status = status, stringsAsFactors = FALSE)
      tb <- rbind(
        row("Planning frame", fmt_int(i$frame_hh$value), i$frame_hh$unit, i$frame_hh$status),
        row("Reference budget", fmt_int(i$budget_ref$value), i$budget_ref$unit, i$budget_ref$status),
        row("Transfer", fmt_int(i$transfer_T$value), i$transfer_T$unit, i$transfer_T$status),
        row("Minimum expenditure basket", fmt_int(i$meb$value), i$meb$unit, i$meb$status),
        row("Duration", i$months_M$value, i$months_M$unit, i$months_M$status),
        row("Delivery cost", sim_pct(i$delivery_rate_a$value, 0), i$delivery_rate_a$unit, i$delivery_rate_a$status),
        row("Fixed cost", fmt_int(i$fixed_cost_F$value), i$fixed_cost_F$unit, i$fixed_cost_F$status),
        row("Equity floor", sim_pct(i$min_cov_m$value, 0), i$min_cov_m$unit, i$min_cov_m$status),
        row("In-kind ration and prices", "see workbook", "kg and XAF per kg", i$inkind$status),
        row("Voucher fee", sim_pct(i$voucher$fee_rate, 0), "of transfer value", i$voucher$status))
      sim_tbl(tb, columns = list(Assumption = reactable::colDef(minWidth = 170, class = "cell-label"), Value = reactable::colDef(align = "right", minWidth = 110), Unit = reactable::colDef(minWidth = 210), Status = reactable::colDef(minWidth = 360)))
    })
    output$provenance <- shiny::renderUI({
      m <- sim$meta
      htmltools::p(class = "small text-muted",
                   sprintf("Model by John: Chad humanitarian operations simulation, technical draft for review. Input: ENSA_Chad_merged_2018-2025.dta, SHA-256 %s… (%s the current merged file).",
                           substr(m$sha256, 1, 12), if (isTRUE(m$input_matches)) "matches" else "DOES NOT MATCH"))
    })
  })
}
