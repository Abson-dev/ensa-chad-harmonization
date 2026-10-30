* =============================================================================
* check_exp.do  -  Expenditure: monthly food, non-food and total expenditure
*                  (analysts' aggregates) and the analysts' food expenditure share
* Compares output/ensa_exp.sav with the 14 original rounds, household by household.
* Report: output/stata_checks/check_exp.xlsx
* =============================================================================
version 16
if `"$ENSA"' == "" {
    * Run from the stata/ folder, or first: global ENSA "C:/.../harmonization"
    if fileexists(`"`c(pwd)'/config/crosswalk.csv"') global ENSA `"`c(pwd)'"'
    else global ENSA `"`c(pwd)'/.."'
}
run `"$ENSA/stata/ensa_check_programs.do"'
ensa_setup
capture log close chk_exp
log using `"$ENSA_CHK/check_exp.log"', replace text name(chk_exp)

ensa_begin exp
foreach r of global ENSA_ROUNDS {
    ensa_load exp `r'

    * Non-food: as stored, or total - food when the round does not store it
    gen double e_exp_nonfood_derived = missing(o_exp_nonfood) & !missing(o_exp_food) & !missing(o_exp_total)
    tempvar nonfood
    gen double `nonfood' = cond(missing(o_exp_nonfood), o_exp_total - o_exp_food, o_exp_nonfood)

    * Inconsistent aggregates (total <= 0, negative food, food > total + 1 FCFA) are set to missing
    gen double e_exp_invalid = (o_exp_total <= 0) | (o_exp_food < 0) | ///
        (!missing(o_exp_food) & !missing(o_exp_total) & o_exp_food > o_exp_total + 1)
    gen double e_exp_food = o_exp_food if !e_exp_invalid
    gen double e_exp_nonfood = `nonfood' if !e_exp_invalid
    gen double e_exp_total = o_exp_total if !e_exp_invalid

    * Analysts' food share: copied as it is (QC only)
    gen double e_orig_FES = o_orig_FES

    ensa_compare exp `r'
}
ensa_end exp
log close chk_exp
