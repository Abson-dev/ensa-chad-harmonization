* =============================================================================
* 00_run_all.do  -  Consistency of the merged (harmonised) files with the original
*                   ENSA Chad rounds, domain by domain
*
* For every domain, round and harmonised variable, the check rebuilds from the
* original .sav file the value the variable should have (crosswalk rule +
* documented recode) and compares it with output/ensa_<domain>.sav, household
* by household. It also checks that every household of each round is found in
* the final file, and only those.
*
* Run: set the path below (or cd to the stata/ folder) and do this file.
* Needs Stata 16 or later. First run about 1 hour (household keys, cached), then
* a few minutes.
* Results in output/stata_checks/:
*   check_summary.xlsx        all domains: by variable, by round, merge
*   check_<domain>.xlsx       by_round, by_variable, merge, mismatches (if any)
*   check_<domain>.log
* =============================================================================
version 16
clear all
set more off
capture set maxvar 10000

* Path to the harmonization folder (the one with config/ and output/)
* global ENSA "C:/Users/AHema/OneDrive - CGIAR/Desktop/2026/SPACERISE/Apply/ENSA Chad data 2018-2025/harmonization"
if `"$ENSA"' == "" {
    if fileexists(`"`c(pwd)'/config/crosswalk.csv"') global ENSA `"`c(pwd)'"'
    else global ENSA `"`c(pwd)'/.."'
}
run `"$ENSA/stata/ensa_check_programs.do"'
ensa_setup
capture log close chk_all
log using `"$ENSA_CHK/check_summary.log"', replace text name(chk_all)

local domains core fcs rcsi lcs hhs hdds exp demo

do `"$ENSA/stata/01_extract_keys.do"'
foreach d of local domains {
    do `"$ENSA/stata/check_`d'.do"'
}

* Summary of all domains
clear
foreach d of local domains {
    append using `"$ENSA_CHK/check_`d'_results.dta"'
}
local xl `"$ENSA_CHK/check_summary.xlsx"'
quietly export excel using `"`xl'"', sheet("by_round") firstrow(variables) replace
preserve
gen byte rounds_ok = status == "OK"
gen byte rounds_mismatch = status == "MISMATCH"
gen byte rounds_not_collected = status == "NOT COLLECTED"
gen byte rounds_input_only = status == "INPUT ONLY"
gen long order = _n
collapse (min) order (sum) rounds_ok rounds_mismatch rounds_not_collected rounds_input_only households recoded mismatch, by(domain variable)
sort order
drop order
gen str13 status = cond(mismatch > 0, "MISMATCH", cond(rounds_input_only > 0, "INPUT ONLY", "OK"))
quietly export excel using `"`xl'"', sheet("by_variable", replace) firstrow(variables)
restore
preserve
clear
foreach d of local domains {
    append using `"$ENSA_CHK/check_`d'_merge.dta"'
}
quietly export excel using `"`xl'"', sheet("merge", replace) firstrow(variables)
quietly count if only_in_source + only_in_final + bad_hh_id > 0 | source_rows != final_rows
local n_mrg = r(N)
restore

di as txt _n "{hline 78}" _n "SUMMARY: variable x round cells by status" _n "{hline 78}"
tabulate domain status, missing
quietly count if status == "MISMATCH"
if r(N) + `n_mrg' == 0 di as res _n "All domains CONSISTENT with the original rounds."
else di as err _n "`r(N)' variable x round cell(s) with mismatches, `n_mrg' domain x round merge problem(s): see check_summary.xlsx"
di as txt `"Report: `xl'"'
log close chk_all
