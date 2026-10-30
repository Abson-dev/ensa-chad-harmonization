* =============================================================================
* 01_extract_keys.do  -  Household key (@_uuid) of each original round
* Stata cannot select "@_uuid" by name, so each original file is read whole once
* (about 30-45 minutes for the 14 rounds) and the key is cached in
* output/stata_checks/keys/. Later runs reuse it; to rebuild (e.g. after the
* original files change): global ENSA_REBUILD_KEYS 1
* =============================================================================
version 16
if `"$ENSA"' == "" {
    * Run from the stata/ folder, or first: global ENSA "C:/.../harmonization"
    if fileexists(`"`c(pwd)'/config/crosswalk.csv"') global ENSA `"`c(pwd)'"'
    else global ENSA `"`c(pwd)'/.."'
}
run `"$ENSA/stata/ensa_check_programs.do"'
ensa_setup
foreach r of global ENSA_ROUNDS {
    ensa_keys `r'
}
clear
