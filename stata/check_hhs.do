* =============================================================================
* check_hhs.do  -  Household Hunger Scale: 3 occurrence questions, their frequency,
*                  and the analysts' pre-computed HHS score / phase
* Compares output/ensa_hhs.sav with the 14 original rounds, household by household.
* Report: output/stata_checks/check_hhs.xlsx
* =============================================================================
version 16
if `"$ENSA"' == "" {
    * Run from the stata/ folder, or first: global ENSA "C:/.../harmonization"
    if fileexists(`"`c(pwd)'/config/crosswalk.csv"') global ENSA `"`c(pwd)'"'
    else global ENSA `"`c(pwd)'/.."'
}
run `"$ENSA/stata/ensa_check_programs.do"'
ensa_setup
capture log close chk_hhs
log using `"$ENSA_CHK/check_hhs.log"', replace text name(chk_hhs)

ensa_begin hhs
foreach r of global ENSA_ROUNDS {
    ensa_load hhs `r'

    * "Yes" codes (settings.toml [hhs]): 1; Oct 2019 also has code 2 on "no food in the house"
    local yes 1
    if "`r'" == "2019-10" local yes 1 2

    foreach q in HHSNoFood HHSBedHung HHSNotEat {
        * Occurrence: 0 no, 1 yes
        gen double e_`q' = 0 if o_`q' == 0
        foreach c of local yes {
            quietly replace e_`q' = 1 if o_`q' == `c'
        }
        * Frequency: as answered after a yes, 0 after a no; missing when it contradicts the
        * occurrence (yes without a 1-3 frequency, or no with a frequency above 0)
        gen double e_`q'_FR = cond(e_`q' == 1, o_`q'_FR, cond(e_`q' == 0, 0, .))
        quietly replace e_`q'_FR = . if (e_`q' == 1 & !inlist(o_`q'_FR, 1, 2, 3)) | ///
            (e_`q' == 0 & o_`q'_FR > 0 & !missing(o_`q'_FR))
    }

    * Analysts' variables: copied as they are (QC only)
    gen double e_orig_HHS = o_orig_HHS
    gen double e_orig_HHS_phase = o_orig_HHS_phase

    ensa_compare hhs `r'
}
ensa_end hhs
log close chk_hhs
