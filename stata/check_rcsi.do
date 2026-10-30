* =============================================================================
* check_rcsi.do  -  Reduced Coping Strategies Index: the 5 strategies (days in
*                   the past 7) and the analysts' pre-computed rCSI
* Compares output/ensa_rcsi.sav with the 14 original rounds, household by household.
* Report: output/stata_checks/check_rcsi.xlsx
* =============================================================================
version 16
if `"$ENSA"' == "" {
    * Run from the stata/ folder, or first: global ENSA "C:/.../harmonization"
    if fileexists(`"`c(pwd)'/config/crosswalk.csv"') global ENSA `"`c(pwd)'"'
    else global ENSA `"`c(pwd)'/.."'
}
run `"$ENSA/stata/ensa_check_programs.do"'
ensa_setup
capture log close chk_rcsi
log using `"$ENSA_CHK/check_rcsi.log"', replace text name(chk_rcsi)

ensa_begin rcsi
foreach r of global ENSA_ROUNDS {
    ensa_load rcsi `r'

    * Skip pattern (Oct 2024): "restrict adults for children" is not asked when the household
    * has no child 0-17 (n_children, input only) -> 0 days
    gen double e_rcsi_mealadult_imputed = missing(o_rCSIMealAdult) & o_n_children == 0

    * Days per strategy: 0-7; values outside 0-7 are set to missing
    foreach v in rCSILessQlty rCSIBorrow rCSIMealSize rCSIMealAdult rCSIMealNb {
        gen double e_`v' = o_`v'
        if "`v'" == "rCSIMealAdult" quietly replace e_`v' = 0 if e_rcsi_mealadult_imputed
        quietly replace e_`v' = . if !inrange(e_`v', 0, 7)
    }

    * Analysts' variable: copied as it is (QC only)
    gen double e_orig_rCSI = o_orig_rCSI

    ensa_compare rcsi `r'
}
ensa_end rcsi
log close chk_rcsi
