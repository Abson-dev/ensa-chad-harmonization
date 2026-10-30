* =============================================================================
* check_lcs.do  -  Livelihood coping strategies: the 14 strategies (WFP answer
*                  scale), the "to buy food" reason and the analysts' max category
* Compares output/ensa_lcs.sav with the 14 original rounds, household by household.
* Report: output/stata_checks/check_lcs.xlsx
* =============================================================================
version 16
if `"$ENSA"' == "" {
    * Run from the stata/ folder, or first: global ENSA "C:/.../harmonization"
    if fileexists(`"`c(pwd)'/config/crosswalk.csv"') global ENSA `"`c(pwd)'"'
    else global ENSA `"`c(pwd)'/.."'
}
run `"$ENSA/stata/ensa_check_programs.do"'
ensa_setup
capture log close chk_lcs
log using `"$ENSA_CHK/check_lcs.log"', replace text name(chk_lcs)

* Answer codes of each round (config/lcs_responses.csv)
capture frame drop lcsresp
frame create lcsresp
frame lcsresp: quietly import delimited using `"$ENSA/config/lcs_responses.csv"', varnames(1) stringcols(_all) encoding("utf-8") clear

local items LCS_DomAsset LCS_Animals LCS_Saving LCS_BorrowCash LCS_CrdtFood LCS_EduHealth LCS_ProdAssets ///
    LCS_EatCrops LCS_ChildWork LCS_OutSchool LCS_Marriage LCS_ResAsset LCS_FemAnimal LCS_Begged

ensa_begin lcs
foreach r of global ENSA_ROUNDS {
    ensa_load lcs `r'

    * Source answer code -> WFP code: 10 no need, 20 already exhausted, 30 yes, 9999 not applicable
    local k 0
    frame lcsresp {
        forvalues i = 1/`=_N' {
            if round_id[`i'] == "`r'" {
                local ++k
                local c`k' = code[`i']
                local resp = response[`i']
                local w`k' = cond("`resp'" == "no_need", 10, cond("`resp'" == "exhausted", 20, ///
                    cond("`resp'" == "yes", 30, cond("`resp'" == "not_applicable", 9999, .))))
                if `w`k'' == . {
                    di as err "`r': unknown LCS response `resp' in config/lcs_responses.csv"
                    exit 198
                }
            }
        }
    }
    foreach v of local items {
        gen double e_`v' = .
        forvalues i = 1/`k' {
            quietly replace e_`v' = `w`i'' if o_`v' == real("`c`i''")
        }
    }

    * Reason "to buy food" (Oct 2024 onward) and the analysts' max category: copied as they are
    gen double e_lcs_food_reason = o_lcs_food_reason
    gen double e_orig_LCS = o_orig_LCS

    ensa_compare lcs `r'
}
ensa_end lcs
frame drop lcsresp
log close chk_lcs
