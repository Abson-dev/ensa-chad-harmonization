* =============================================================================
* check_fcs.do  -  Food Consumption Score: the 9 food groups (days in the past 7)
*                  and the analysts' pre-computed FCS / FCS group
* Compares output/ensa_fcs.sav with the 14 original rounds, household by household.
* Report: output/stata_checks/check_fcs.xlsx
* =============================================================================
version 16
if `"$ENSA"' == "" {
    * Run from the stata/ folder, or first: global ENSA "C:/.../harmonization"
    if fileexists(`"`c(pwd)'/config/crosswalk.csv"') global ENSA `"`c(pwd)'"'
    else global ENSA `"`c(pwd)'/.."'
}
run `"$ENSA/stata/ensa_check_programs.do"'
ensa_setup
capture log close chk_fcs
log using `"$ENSA_CHK/check_fcs.log"', replace text name(chk_fcs)

ensa_begin fcs
foreach r of global ENSA_ROUNDS {
    ensa_load fcs `r'

    * Days per food group: 0-7 (groups summed from sub-groups are capped at 7 by the rule);
    * values outside 0-7 are set to missing
    foreach v in FCSStap FCSPulse FCSVeg FCSFruit FCSPr FCSDairy FCSSugar FCSFat FCSCond {
        gen double e_`v' = o_`v' if inrange(o_`v', 0, 7)
    }

    * Analysts' variables: copied as they are (QC only)
    gen double e_orig_FCS = o_orig_FCS
    gen double e_orig_FCSCat28 = o_orig_FCSCat28

    ensa_compare fcs `r'
}
ensa_end fcs
log close chk_fcs
