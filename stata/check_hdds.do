* =============================================================================
* check_hdds.do  -  Household Dietary Diversity: the 12 food groups eaten in the
*                   past 24 hours and the analysts' pre-computed HDDS / phase
* Compares output/ensa_hdds.sav with the 14 original rounds, household by household.
* Report: output/stata_checks/check_hdds.xlsx
* =============================================================================
version 16
if `"$ENSA"' == "" {
    * Run from the stata/ folder, or first: global ENSA "C:/.../harmonization"
    if fileexists(`"`c(pwd)'/config/crosswalk.csv"') global ENSA `"`c(pwd)'"'
    else global ENSA `"`c(pwd)'/.."'
}
run `"$ENSA/stata/ensa_check_programs.do"'
ensa_setup
capture log close chk_hdds
log using `"$ENSA_CHK/check_hdds.log"', replace text name(chk_hdds)

ensa_begin hdds
foreach r of global ENSA_ROUNDS {
    ensa_load hdds `r'

    * A skipped 24-hour question counts as "not eaten" when the matching FCS 7-day answer
    * (gate_<group>, input only) is 0; then answers other than 0/1 are set to missing
    gen double e_hdds_n_imputed = 0
    foreach v in HDDSStapCer HDDSStapRoot HDDSPulse HDDSVeg HDDSFruit HDDSPrMeat HDDSPrEgg ///
                 HDDSPrFish HDDSDairy HDDSSugar HDDSFat HDDSCond {
        tempvar imp
        gen byte `imp' = missing(o_`v') & o_gate_`v' == 0
        gen double e_`v' = cond(`imp', 0, o_`v')
        quietly replace e_`v' = . if !inrange(e_`v', 0, 1)
        quietly replace e_hdds_n_imputed = e_hdds_n_imputed + `imp'
        drop `imp'
    }

    * Analysts' variables: copied as they are (QC only)
    gen double e_orig_HDDS = o_orig_HDDS
    gen double e_orig_HDDS_phase = o_orig_HDDS_phase

    ensa_compare hdds `r'
}
ensa_end hdds
log close chk_hdds
