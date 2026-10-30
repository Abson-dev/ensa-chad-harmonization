* =============================================================================
* ensa_check_programs.do
* Shared programs for the merging consistency checks (one check_<domain>.do per
* domain). Each check rebuilds, from the ORIGINAL round files, the value every
* harmonised variable should have, and compares it with output/ensa_<domain>.sav.
*
*   ensa_setup              paths, rounds list (config/rounds.csv)
*   ensa_keys    round      household key (@_uuid) of a round, read once and cached
*   ensa_begin   domain     crosswalk rules, final file, result tables
*   ensa_load    domain rnd original sources -> o_<target> (crosswalk rule applied),
*                           merged 1:1 on the household with the final file (f_<var>)
*   ensa_compare domain rnd every e_<var> (expected, written in the domain do-file)
*                           against f_<var>; o_<var> gives the "unchanged" count
*   ensa_end     domain     Excel report + results .dta
*
* Variable prefixes after ensa_load:  o_ original value (rule applied, no recode)
*                                      e_ expected final value (domain do-file)
*                                      f_ value in the harmonised file
* =============================================================================

capture program drop ensa_setup
program define ensa_setup
    version 16
    if !fileexists(`"$ENSA/config/crosswalk.csv"') {
        di as err `"Global ENSA must point to the harmonization folder (with config/ and output/); now: "$ENSA""'
        exit 601
    }
    * Absolute paths. Note: import spss accepts the file name only in plain double quotes
    * ("..."), not in compound quotes (`"..."').
    local here `"`c(pwd)'"'
    quietly cd `"$ENSA"'
    global ENSA `"`c(pwd)'"'
    quietly cd ..
    global ENSA_DATA `"`c(pwd)'"'
    quietly cd `"`here'"'
    global ENSA_OUT  `"$ENSA/output"'
    global ENSA_CHK  `"$ENSA/output/stata_checks"'
    capture mkdir `"$ENSA_CHK"'
    capture mkdir `"$ENSA_CHK/keys"'
    capture mkdir `"$ENSA_CHK/tmp"'
    capture frame drop rounds
    frame create rounds
    frame rounds {
        quietly import delimited using `"$ENSA/config/rounds.csv"', varnames(1) stringcols(_all) encoding("utf-8") clear
        global ENSA_ROUNDS ""
        forvalues i = 1/`=_N' {
            global ENSA_ROUNDS $ENSA_ROUNDS `=round_id[`i']'
        }
    }
end

* Path and metadata of a round (config/rounds.csv).
capture program drop ensa_roundinfo
program define ensa_roundinfo, rclass
    version 16
    args round
    local found 0
    frame rounds {
        forvalues i = 1/`=_N' {
            if round_id[`i'] == "`round'" {
                local found 1
                return local file `"$ENSA_DATA/`=folder[`i']'/`=file[`i']'"'
                return local year = year[`i']
                return local season = season[`i']
                return local generation = generation[`i']
            }
        }
    }
    if !`found' {
        di as err "Round `round' is not in config/rounds.csv"
        exit 198
    }
end

* Household key of a round. Stata cannot select "@_uuid" by name (invalid name), so the
* whole file is read once and the key is cached with its row number. instanceID is kept
* to check, at every later (selective) import, that rows are still aligned.
capture program drop ensa_keys
program define ensa_keys
    version 16
    args round
    local kf `"$ENSA_CHK/keys/keys_`round'.dta"'
    if fileexists(`"`kf'"') & "$ENSA_REBUILD_KEYS" != "1" exit
    ensa_roundinfo `round'
    local file `"`r(file)'"'
    di as txt "`round': reading the whole original file once to get the household key (@_uuid)..."
    timer clear 99
    timer on 99
    quietly import spss using "`file'", clear
    timer off 99
    quietly timer list 99
    local secs = r(t99)
    local uvar ""
    foreach v of varlist _all {
        if `"`: variable label `v''"' == "_uuid" local uvar `uvar' `v'
    }
    if `: word count `uvar'' != 1 {
        di as err "`round': expected one variable labelled _uuid, found: `uvar'"
        exit 459
    }
    keep `uvar' instanceID
    rename `uvar' k_uuid
    rename instanceID k_instanceID
    confirm string variable k_uuid
    quietly count if k_uuid == ""
    if r(N) {
        di as err "`round': `r(N)' households without @_uuid"
        exit 459
    }
    isid k_uuid
    gen long _row = _n
    quietly compress
    quietly save `"`kf'"', replace
    di as txt "`round': " %9.0fc _N " households, key saved (" %4.0f `secs' " s)"
end

* Numeric value as the pipeline reads it: text-stored numbers become numbers, blanks missing.
capture program drop ensa_num
program define ensa_num
    version 16
    syntax varname, GENerate(name)
    capture confirm string variable `varlist'
    if !_rc quietly gen double `generate' = real(ustrtrim(`varlist'))
    else quietly gen double `generate' = `varlist'
end

* Any variable as text (for the mismatch listing).
capture program drop ensa_str
program define ensa_str
    version 16
    syntax varname, GENerate(name)
    capture confirm string variable `varlist'
    if !_rc quietly gen strL `generate' = `varlist'
    else quietly gen strL `generate' = string(`varlist', "%20.10g")
end

capture program drop ensa_begin
program define ensa_begin
    version 16
    args domain
    capture frame drop rules
    frame create rules
    frame rules {
        quietly import delimited using `"$ENSA/config/crosswalk.csv"', varnames(1) stringcols(_all) encoding("utf-8") clear
        quietly keep if domain == "`domain'"
        if _N == 0 {
            di as err "No rule for domain `domain' in config/crosswalk.csv"
            exit 198
        }
    }
    quietly import spss using "$ENSA_OUT/ensa_`domain'.sav", clear
    quietly save `"$ENSA_CHK/tmp/final_`domain'.dta"', replace
    capture frame drop res
    frame create res str10 domain str7 round_id str32 variable str12 method str2045 sources ///
        double(households orig_nonmiss final_nonmiss unchanged recoded mismatch pct_consistent) str13 status
    capture frame drop mrg
    frame create mrg str10 domain str7 round_id double(source_rows final_rows matched only_in_source only_in_final bad_hh_id)
    clear
    foreach v in round_id hh_id variable original expected final {
        quietly gen str1 `v' = ""
    }
    quietly save `"$ENSA_CHK/tmp/mismatch_`domain'.dta"', replace emptyok
    di as txt _n "{hline 78}" _n "Domain `domain': harmonised file vs original rounds" _n "{hline 78}"
end

capture program drop ensa_load
program define ensa_load
    version 16
    args domain round
    ensa_keys `round'
    ensa_roundinfo `round'
    local file `"`r(file)'"'

    * Crosswalk rules of this domain and round
    local n 0
    frame rules {
        forvalues i = 1/`=_N' {
            if round_id[`i'] == "`round'" {
                local ++n
                local T`n' = target[`i']
                local M`n' = method[`i']
                local S`n' = sources[`i']
            }
        }
    }
    if `n' == 0 {
        di as err "No crosswalk rule for `domain' in round `round'"
        exit 198
    }

    * Source variables: valid Stata names in one selective import; the others (longer than
    * 32 characters, or with a dot) one at a time, since Stata renames them _v1, _v2...
    local srcs ""
    forvalues j = 1/`n' {
        if "`M`j''" == "missing" continue
        local s : subinstr local S`j' "|" " ", all
        local srcs : list srcs | s
    }
    local uu "@_uuid"
    local srcs : list srcs - uu
    local valid ""
    local odd ""
    foreach s of local srcs {
        if ustrregexm("`s'", "^[A-Za-z_][A-Za-z0-9_]*$") & ustrlen("`s'") <= 32 local valid `valid' `s'
        else local odd `odd' `s'
    }
    quietly import spss instanceID `valid' using "`file'", clear
    local missing_src ""
    foreach s of local valid {
        capture confirm variable `s', exact
        if _rc local missing_src `missing_src' `s'
    }
    local valid : list valid - missing_src
    local odd `odd' `missing_src'
    gen long _row = _n
    local allsrc `valid'
    local allvar `valid'
    local k 0
    foreach s of local odd {
        if substr("`s'", 1, 1) == "@" {
            di as err "`round': source `s' cannot be read by name in Stata"
            exit 198
        }
        local ++k
        preserve
        quietly import spss `s' using "`file'", clear
        if c(k) != 1 {
            di as err "`round': source `s' not found in `file'"
            exit 111
        }
        unab v : _all
        rename `v' _odd`k'
        gen long _row = _n
        tempfile odd`k'
        quietly save `"`odd`k''"'
        restore
        quietly merge 1:1 _row using `"`odd`k''"', assert(match) nogenerate
        local allsrc `allsrc' `s'
        local allvar `allvar' _odd`k'
    }
    quietly merge 1:1 _row using `"$ENSA_CHK/keys/keys_`round'.dta"', assert(match) nogenerate
    capture assert instanceID == k_instanceID
    if _rc {
        di as err "`round': rows of the selective import are not aligned with the cached key; rerun with global ENSA_REBUILD_KEYS 1"
        exit 459
    }
    drop instanceID k_instanceID

    * o_<target>: the crosswalk rule applied to the original values (engine.apply_rules)
    forvalues j = 1/`n' {
        local T `T`j''
        local M `M`j''
        local V ""
        if "`M'" != "missing" {
            local S : subinstr local S`j' "|" " ", all
            foreach s of local S {
                if "`s'" == "@_uuid" local V `V' k_uuid
                else {
                    local p : list posof "`s'" in allsrc
                    local V `V' `: word `p' of `allvar''
                }
            }
        }
        if "`M'" == "missing" {
            quietly gen double o_`T' = .
        }
        else if "`M'" == "copy" & "`T'" == "uuid" {
            quietly gen strL o_`T' = `V'
        }
        else if "`M'" == "copy" {
            ensa_num `V', generate(o_`T')
        }
        else if "`M'" == "copy_label" {
            capture confirm string variable `V'
            if !_rc quietly gen strL o_`T' = `V'
            else if "`: value label `V''" != "" {
                quietly decode `V', generate(o_`T')
                * Codes without a label keep their code (engine.decode_label)
                quietly replace o_`T' = string(`V', "%20.0g") if o_`T' == "" & !missing(`V')
            }
            else quietly gen strL o_`T' = string(`V', "%20.0g") if !missing(`V')
            quietly replace o_`T' = ustrtrim(o_`T')
        }
        else {
            local nv ""
            foreach v of local V {
                tempvar t
                ensa_num `v', generate(`t')
                local nv `nv' `t'
            }
            if inlist("`M'", "sum", "sum_cap7") {
                quietly egen double o_`T' = rowtotal(`nv'), missing
                if "`M'" == "sum_cap7" quietly replace o_`T' = 7 if o_`T' > 7 & !missing(o_`T')
            }
            else if "`M'" == "any" {
                tempvar nnm
                quietly egen `nnm' = rownonmiss(`nv')
                quietly gen double o_`T' = 0 if `nnm' > 0
                foreach t of local nv {
                    quietly replace o_`T' = 1 if `t' == 1
                }
            }
            else if "`M'" == "max_or_last" {
                local last : word `: word count `nv'' of `nv'
                local head : list nv - last
                if "`head'" != "" quietly egen double o_`T' = rowmax(`head')
                else quietly gen double o_`T' = .
                quietly replace o_`T' = `last' if missing(o_`T')
            }
            else {
                di as err "Unknown method `M' (`domain'/`T'/`round')"
                exit 198
            }
        }
        char o_`T'[method] `M'
        char o_`T'[sources] `S`j''
    }
    rename k_uuid _uuid
    keep _row _uuid o_*
    quietly compress
    local n_source = _N

    * Final (harmonised) file, same round; its variables get the prefix f_
    preserve
    quietly use `"$ENSA_CHK/tmp/final_`domain'.dta"' if round_id == "`round'", clear
    local n_final = _N
    quietly count if substr(hh_id, 1, 8) != "`round'_"
    local bad_id = r(N)
    quietly gen _uuid = substr(hh_id, 9, .)
    foreach v of varlist _all {
        if !inlist("`v'", "round_id", "hh_id", "_uuid") rename `v' f_`v'
    }
    tempfile fin
    quietly save `"`fin'"'
    restore
    quietly merge 1:1 _uuid using `"`fin'"'
    quietly count if _merge == 3
    local matched = r(N)
    quietly count if _merge == 1
    local only_src = r(N)
    quietly count if _merge == 2
    local only_fin = r(N)
    frame post mrg ("`domain'") ("`round'") (`n_source') (`n_final') (`matched') (`only_src') (`only_fin') (`bad_id')
    quietly keep if _merge == 3
    drop _merge
    di as txt "`round': " %7.0fc `n_source' " households in the source, " %7.0fc `n_final' " in the final file, " ///
        %7.0fc `matched' " matched" cond(`only_src' + `only_fin' + `bad_id' > 0, "  <-- CHECK", "")
end

capture program drop ensa_compare
program define ensa_compare
    version 16
    args domain round
    local N = _N
    capture unab evars : e_*
    foreach e of local evars {
        local v = substr("`e'", 3, .)
        capture confirm variable f_`v', exact
        if _rc {
            di as err "`e': no variable `v' in output/ensa_`domain'.sav"
            exit 111
        }
        capture confirm variable o_`v', exact
        local has_o = !_rc
        if `has_o' {
            local M : char o_`v'[method]
            local S : char o_`v'[sources]
        }
        else {
            local M : char `e'[method]
            local S : char `e'[sources]
            if "`M'" == "" local M "derived"
        }
        capture confirm string variable `e'
        local is_str = !_rc
        capture confirm string variable f_`v'
        if `is_str' != !_rc {
            di as err "`v': expected and final values are not of the same type (string / numeric)"
            exit 109
        }
        tempvar eq same
        if `is_str' {
            quietly gen byte `eq' = (`e' == f_`v')
            quietly count if f_`v' != ""
        }
        else {
            quietly gen byte `eq' = (`e' == f_`v') | (missing(`e') & missing(f_`v')) | (abs(`e' - f_`v') <= 1e-7 * max(1, abs(f_`v')))
            quietly count if !missing(f_`v')
        }
        local fin_nm = r(N)
        local orig_nm = .
        local unchanged = .
        local recoded = .
        if `has_o' {
            capture confirm string variable o_`v'
            local o_str = !_rc
            if `o_str' quietly count if o_`v' != ""
            else quietly count if !missing(o_`v')
            local orig_nm = r(N)
            if `o_str' == `is_str' {
                if `is_str' quietly gen byte `same' = (o_`v' == f_`v')
                else quietly gen byte `same' = (o_`v' == f_`v') | (missing(o_`v') & missing(f_`v')) | (abs(o_`v' - f_`v') <= 1e-7 * max(1, abs(f_`v')))
                quietly count if `same'
                local unchanged = r(N)
                quietly count if !`same' & `eq'
                local recoded = r(N)
            }
        }
        quietly count if !`eq'
        local mis = r(N)
        if `mis' > 0 local st "MISMATCH"
        else if "`M'" == "missing" local st "NOT COLLECTED"
        else local st "OK"
        local pct = cond(`N' > 0, 100 * (`N' - `mis') / `N', .)
        frame post res ("`domain'") ("`round'") ("`v'") ("`M'") (`"`S'"') (`N') (`orig_nm') (`fin_nm') ///
            (`unchanged') (`recoded') (`mis') (`pct') ("`st'")
        if `mis' > 0 {
            di as err "  `round' `v': `mis' household(s) differ from the expected value"
            preserve
            quietly keep if !`eq'
            if _N > 1000 quietly keep in 1/1000
            if `has_o' ensa_str o_`v', generate(original)
            else quietly gen strL original = ""
            ensa_str `e', generate(expected)
            ensa_str f_`v', generate(final)
            quietly gen strL variable = "`v'"
            keep round_id hh_id variable original expected final
            quietly append using `"$ENSA_CHK/tmp/mismatch_`domain'.dta"'
            quietly save `"$ENSA_CHK/tmp/mismatch_`domain'.dta"', replace
            restore
        }
        drop `eq'
        capture drop `same'
    }
    * Crosswalk inputs not kept in the final file (used only to derive other variables)
    capture unab ovars : o_*
    foreach o of local ovars {
        local v = substr("`o'", 3, .)
        capture confirm variable e_`v', exact
        if !_rc continue
        capture confirm string variable `o'
        if !_rc quietly count if `o' != ""
        else quietly count if !missing(`o')
        frame post res ("`domain'") ("`round'") ("`v'") ("`: char `o'[method]'") (`"`: char `o'[sources]'"') ///
            (`N') (r(N)) (.) (.) (.) (.) (.) ("INPUT ONLY")
    }
end

capture program drop ensa_end
program define ensa_end
    version 16
    args domain
    local xl `"$ENSA_CHK/check_`domain'.xlsx"'
    frame res {
        quietly save `"$ENSA_CHK/check_`domain'_results.dta"', replace
        quietly export excel using `"`xl'"', sheet("by_round") firstrow(variables) replace
        preserve
        quietly gen byte rounds_ok = status == "OK"
        quietly gen byte rounds_mismatch = status == "MISMATCH"
        quietly gen byte rounds_not_collected = status == "NOT COLLECTED"
        quietly gen byte rounds_input_only = status == "INPUT ONLY"
        collapse (sum) rounds_ok rounds_mismatch rounds_not_collected rounds_input_only households recoded mismatch, by(domain variable)
        quietly gen str13 status = cond(mismatch > 0, "MISMATCH", cond(rounds_input_only > 0, "INPUT ONLY", "OK"))
        quietly export excel using `"`xl'"', sheet("by_variable", replace) firstrow(variables)
        di as txt _n "Domain `domain', by variable (all rounds):"
        list variable rounds_ok rounds_not_collected rounds_mismatch recoded mismatch status, noobs sep(0) abbreviate(20)
        restore
        quietly count if status == "MISMATCH"
        local n_mis = r(N)
    }
    frame mrg {
        quietly save `"$ENSA_CHK/check_`domain'_merge.dta"', replace
        quietly export excel using `"`xl'"', sheet("merge", replace) firstrow(variables)
        quietly count if only_in_source + only_in_final + bad_hh_id > 0 | source_rows != final_rows
        local n_mrg = r(N)
    }
    preserve
    quietly use `"$ENSA_CHK/tmp/mismatch_`domain'.dta"', clear
    if _N > 0 {
        sort variable round_id hh_id
        quietly export excel using `"`xl'"', sheet("mismatches", replace) firstrow(variables)
    }
    restore
    if `n_mis' + `n_mrg' == 0 di as res _n "Domain `domain': CONSISTENT. Every variable matches the original rounds after the documented rules."
    else di as err _n "Domain `domain': `n_mis' variable x round cell(s) with mismatches, `n_mrg' round(s) with household-matching problems. See the mismatches sheet."
    di as txt `"Report: `xl'"'
end
