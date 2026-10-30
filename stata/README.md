# Stata consistency checks: harmonised files vs original rounds

These do-files check the merging step independently of the Python pipeline. For every domain, round and harmonised variable, they:

1. read the original variable(s) from the round's `.sav` file, as named in `config/crosswalk.csv`;
2. apply the crosswalk rule (`copy`, `copy_label`, `sum`, `sum_cap7`, `any`, `max_or_last`, `missing`) and the domain's documented recode, rewritten in Stata;
3. compare the result with the variable in `output/ensa_<domain>.sav`, household by household (matched on `hh_id` = round + KoBo uuid).

They also check that every household of each round is in the final file, and no other.

## Run

Needs Stata 16 or later and the pipeline outputs (`output/ensa_*.sav`).

```stata
cd "C:/.../ENSA Chad data 2018-2025/harmonization/stata"
do 00_run_all.do
```

Or set `global ENSA "C:/.../harmonization"` first and run from anywhere. A single domain can be run alone, e.g. `do check_lcs.do`.

**First run: about 1 hour.** Stata cannot select the KoBo key `@_uuid` by name (the `@` is not allowed in Stata names), so `01_extract_keys.do` reads each original file whole once and caches the key in `output/stata_checks/keys/`. Later runs reuse the cache and take a few minutes. After a change to the original files, rebuild the cache with `global ENSA_REBUILD_KEYS 1`.

## Files

| File | Domain | Documented rules checked |
|---|---|---|
| `check_core.do` | key, date, region, department, sub-prefecture, weight | region spelling (`admin1_names.csv`), spaces collapsed, date as day, weight as provided, round metadata |
| `check_fcs.do` | 9 FCS food groups | sub-groups summed and capped at 7, days outside 0-7 → missing |
| `check_rcsi.do` | 5 rCSI strategies | "adults for children" skipped with no child → 0, days outside 0-7 → missing |
| `check_lcs.do` | 14 LCS strategies, food reason | answer codes → WFP codes 10/20/30/9999 (`lcs_responses.csv`) |
| `check_hhs.do` | 3 HHS questions + frequency | yes codes (2019-10 exception), frequency 0 after a no, contradictions → missing |
| `check_hdds.do` | 12 HDDS food groups | skipped group with FCS 7-day answer 0 → not eaten, answers other than 0/1 → missing |
| `check_exp.do` | food, non-food, total expenditure | non-food derived as total − food where not stored, inconsistent aggregates → missing |
| `check_demo.do` | head sex, age, education, literacy, marital status, household size, income source, population group | code lists per round (`demo_codes.csv`), education of non-literate heads → none, age 12-100, size 1-50 |
| `ensa_check_programs.do` | shared programs | reading the sources, crosswalk methods, merge, comparison, report |
| `01_extract_keys.do` | household key cache | |
| `00_run_all.do` | runs everything and writes the summary | |

The analysts' pre-computed variables (`orig_*`) are checked as straight copies. Scores and categories computed by the pipeline (FCS, rCSI, HHS, …) are not merging variables and are not re-checked here; their agreement with the analysts' values is in `output/qc/`.

## Last run (30 Oct 2026, Stata 19)

- **Households:** all 197,947, in all 14 rounds, are in the final files with no extra household.
- **All 8 domains:** every merged variable is consistent with the original rounds, in every round.
- The first run found every interview date (`svy_date`) **one day late**: the pipeline's SPSS epoch constant (`ensa_harmonize/engine.py`) was one day short (12219292800 instead of 12219379200 seconds, 14 Oct 1582 to 1 Jan 1970). It is fixed, the unit test now derives the epoch from the calendar, and the rerun is consistent.

## Results (`output/stata_checks/`, not versioned)

| File | Content |
|---|---|
| `check_summary.xlsx` | all domains: `by_variable`, `by_round`, `merge` |
| `check_<domain>.xlsx` | `by_round`, `by_variable`, `merge`, and `mismatches` when there are any |
| `check_<domain>.log`, `check_summary.log` | Stata logs |

Columns of `by_round`, one row per variable and round:

| Column | Meaning |
|---|---|
| `method`, `sources` | crosswalk rule and original variable(s) |
| `households` | households matched between the original round and the final file |
| `orig_nonmiss`, `final_nonmiss` | non-missing values in the original and in the final file |
| `unchanged` | final value identical to the original value |
| `recoded` | final value different from the original, as the documented rule requires |
| `mismatch` | final value different from what the rule gives: **must be 0** |
| `status` | `OK`, `NOT COLLECTED` (question not asked in the round, final value missing as expected), `INPUT ONLY` (original variable used only to derive another one, e.g. `gate_*`, `n_children`; checked through that variable), `MISMATCH` |

The `merge` sheet gives, per round, the households in the original file and in the final file, the matched ones, those found on one side only, and malformed `hh_id`s; all but the first three columns must be 0. The `mismatches` sheet lists up to 1,000 households per variable and round, with the original, expected and final values. It contains household identifiers: keep it with the data, not on GitHub.
