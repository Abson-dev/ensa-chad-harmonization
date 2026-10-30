* =============================================================================
* check_core.do  -  Core: household key, interview date, region, department,
*                   sub-prefecture, sampling weight, round metadata
* Compares output/ensa_core.sav with the 14 original rounds, household by household.
* Report: output/stata_checks/check_core.xlsx
* =============================================================================
version 16
if `"$ENSA"' == "" {
    * Run from the stata/ folder, or first: global ENSA "C:/.../harmonization"
    if fileexists(`"`c(pwd)'/config/crosswalk.csv"') global ENSA `"`c(pwd)'"'
    else global ENSA `"`c(pwd)'/.."'
}
run `"$ENSA/stata/ensa_check_programs.do"'
ensa_setup
capture log close chk_core
log using `"$ENSA_CHK/check_core.log"', replace text name(chk_core)

* Standard region names (config/admin1_names.csv)
quietly import delimited using `"$ENSA/config/admin1_names.csv"', varnames(1) stringcols(_all) encoding("utf-8") clear
rename (raw_name admin1) (o_admin1 e_admin1)
tempfile admin1
quietly save `admin1'

ensa_begin core
foreach r of global ENSA_ROUNDS {
    ensa_load core `r'
    ensa_roundinfo `r'
    local year `r(year)'
    local season `r(season)'
    local generation `r(generation)'

    * Round metadata (config/rounds.csv)
    gen double e_year = `year'
    gen e_season = "`season'"
    gen double e_generation = `generation'
    foreach v in year season generation {
        char e_`v'[method] rounds.csv
    }

    * Household key: KoBo uuid, unchanged (hh_id = round_id + "_" + uuid was used for the merge)
    gen e_uuid = o_uuid

    * Interview date: Stata reads SPSS date-times in milliseconds since 1960; the pipeline keeps the day
    gen double e_svy_date = dofc(o_svy_date)
    quietly replace f_svy_date = dofc(f_svy_date)
    format e_svy_date f_svy_date %td

    * Region: label of the source code, then the standard spelling
    quietly merge m:1 o_admin1 using `admin1', keep(master match) nogenerate
    gen o_admin1_raw = o_admin1
    char o_admin1_raw[method] `: char o_admin1[method]'
    char o_admin1_raw[sources] `: char o_admin1[sources]'
    gen e_admin1_raw = o_admin1

    * Department and sub-prefecture: label, repeated spaces collapsed, trimmed
    foreach a in admin2 admin3 {
        gen e_`a' = ustrtrim(ustrregexra(o_`a', "\s+", " "))
    }

    * Sampling weight: as provided (missing where the round has none)
    gen double e_weight = o_weight

    ensa_compare core `r'
}
ensa_end core
log close chk_core
