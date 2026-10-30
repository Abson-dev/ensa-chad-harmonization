* =============================================================================
* check_demo.do  -  Demographics: sex, age, education, literacy and marital status
*                   of the head, household size, main income source, population group
* Compares output/ensa_demo.sav with the 14 original rounds, household by household.
* Report: output/stata_checks/check_demo.xlsx
* =============================================================================
version 16
if `"$ENSA"' == "" {
    * Run from the stata/ folder, or first: global ENSA "C:/.../harmonization"
    if fileexists(`"`c(pwd)'/config/crosswalk.csv"') global ENSA `"`c(pwd)'"'
    else global ENSA `"`c(pwd)'/.."'
}
run `"$ENSA/stata/ensa_check_programs.do"'
ensa_setup
capture log close chk_demo
log using `"$ENSA_CHK/check_demo.log"', replace text name(chk_demo)

* Code lists of each round (config/demo_codes.csv; an empty value means "not recorded")
capture frame drop democodes
frame create democodes
frame democodes: quietly import delimited using `"$ENSA/config/demo_codes.csv"', varnames(1) stringcols(_all) encoding("utf-8") clear

ensa_begin demo
foreach r of global ENSA_ROUNDS {
    ensa_load demo `r'

    * Categorical variables: source code -> harmonised code
    foreach var in HHHSex HHHEdu HHHMarital income_main pop_group {
        local k 0
        frame democodes {
            forvalues i = 1/`=_N' {
                if round_id[`i'] == "`r'" & variable[`i'] == "`var'" {
                    local ++k
                    local c`k' = code[`i']
                    local v`k' = value[`i']
                }
            }
        }
        gen double e_`var' = .
        forvalues i = 1/`k' {
            if "`v`i''" != "" quietly replace e_`var' = real("`v`i''") if o_`var' == real("`c`i''")
        }
    }

    * Education is asked only of literate heads: a non-literate head without a level = no formal education
    gen double e_edu_imputed = missing(e_HHHEdu) & o_edu_filter == 0
    quietly replace e_HHHEdu = 0 if e_edu_imputed

    * Literacy filter question, kept as HHHLiterate
    rename o_edu_filter o_HHHLiterate
    gen double e_HHHLiterate = o_HHHLiterate

    * Age of the head 12-100 years, household size 1-50; outside -> missing
    gen double e_HHHAge = o_HHHAge if inrange(o_HHHAge, 12, 100)
    gen double e_HHSize = o_HHSize if inrange(o_HHSize, 1, 50)

    ensa_compare demo `r'
}
ensa_end demo
frame drop democodes
log close chk_demo
