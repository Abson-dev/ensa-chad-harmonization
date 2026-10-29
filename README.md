# ENSA Chad 2018–2025 — Reproducible harmonisation of household food security surveys

![Python](https://img.shields.io/badge/python-3.11-blue)
![Environment](https://img.shields.io/badge/env-conda--forge-green)
![Tests](https://img.shields.io/badge/tests-11%20passing-brightgreen)
![Status](https://img.shields.io/badge/status-pilot%20(3%20domains)-orange)

A config-driven, tested and documented pipeline that harmonises **14 rounds** of Chad's national food security assessment (*Enquête Nationale de Sécurité Alimentaire*, ENSA), October 2018 to October 2025, **197,947 households**, into one comparable dataset per **thematic domain**.

Across these rounds the questionnaire went through three codebook generations: French variable names (2018–2020), a hybrid with WFP modules (2021–2023) and the WFP standard codebook (2023–2025). Only 14 of 3,853 variable names, all KoBo system fields, are shared by every round. This repository turns that heterogeneity into explicit, auditable mapping rules and recomputes the indicators the same way for every round.

> **Data are not included.** The repository contains code and harmonisation rules only. See [Data](#data).

---

## Contents

- [Highlights](#highlights)
- [Domains](#domains)
- [Data](#data)
- [Quick start](#quick-start)
- [Interactive explorer (R Shiny)](#interactive-explorer-r-shiny)
- [Repository structure](#repository-structure)
- [How harmonisation works](#how-harmonisation-works)
- [Validation](#validation)
- [Domain decisions](#domain-decisions)
- [Data issues found during harmonisation](#data-issues-found-during-harmonisation)
- [Reproducibility](#reproducibility)
- [Extending the pipeline](#extending-the-pipeline)
- [Outputs](#outputs)
- [Author, citation and license](#author-citation-and-license)

---

## Highlights

- **All decisions are in configuration, not code.** Every source variable for every domain × target × round is one row of [`config/crosswalk.csv`](config/crosswalk.csv), including the variables that are explicitly unavailable, each with a reason.
- **Indicators are recomputed from the item answers** with the WFP formulas, never copied from the heterogeneous pre-computed scores.
- **Validated against the original analysts' scores:** rCSI is identical in 100% of households in all 13 comparable rounds; FCS is identical in 9 rounds and agrees for 98.7–99.2% of households in the other 3.
- **It fails loudly:** the run stops on incomplete rules, unknown region spellings or duplicate household IDs. Out-of-range answers are set to missing and counted, never clipped silently.
- **Provenance:** each run writes a manifest with SHA-256 hashes of the inputs, config and outputs, plus the software versions. Two consecutive runs give byte-identical CSV outputs.
- **Outputs in CSV and SPSS** (`.sav` with variable and value labels).

## Domains

| Domain | Status | Content |
|---|---|---|
| `core` | ✅ done | Household keys, interview date, regions (23 standardised names), department, sub-prefecture, sampling weight |
| `fcs` | ✅ done | 9 food groups, Food Consumption Score, groups 21/35 and 28/42 |
| `rcsi` | ✅ done | 5 coping strategies, reduced Coping Strategies Index, Cadre Harmonisé phase |
| `lcs` | 🔜 planned | Livelihood coping strategies (needs a common item set: the module changes between rounds) |
| `hhs` | 🔜 planned | Household Hunger Scale (from Oct 2019) |
| `hdds` | 🔜 planned | Household Dietary Diversity Score (12 groups) |
| `exp` | 🔜 planned | Food / non-food expenditure, food expenditure share |
| `demo` | 🔜 planned | Head of household characteristics, household size, income source |

The variable mapping for the planned domains has already been worked out (crosswalk workbook, 83 concepts × 14 rounds); they need their rules and a domain module.

## Data

The ENSA household surveys are conducted by the Government of Chad (SISAAP) with WFP and partners. The microdata are **not redistributed here**. Request access from the data owners.

The pipeline expects the original SPSS files laid out like this (folder names are configurable in [`config/rounds.csv`](config/rounds.csv) and [`config/settings.toml`](config/settings.toml)):

```
<data folder>/
├── Round  de fevrier/      022019 … 022024_CHD_ENSA_HH_Base_analyse.sav   (6 rounds)
├── Round d'octobre/        102018 … 102025_CHD_ENSA_HH_Base_analyse.sav   (8 rounds)
└── harmonization/          <- this repository
```

| Round | Households | Generation | | Round | Households | Generation |
|---|---:|:---:|---|---|---:|:---:|
| Oct 2018 | 9,443 | 1 | | Oct 2021 | 14,761 | 2 |
| Feb 2019 | 10,155 | 1 | | Feb 2022 | 15,187 | 2 |
| Oct 2019 | 9,483 | 1 | | Oct 2022 | 14,874 | 2 |
| Feb 2020 | 15,456 | 1 | | Feb 2023 | 16,564 | 2 |
| Oct 2020 | 13,208 | 1 | | Oct 2023 | 14,777 | 3 |
| Feb 2021 | 11,517 | 2 | | Feb 2024 | 19,918 | 3 |
| | | | | Oct 2024 | 19,672 | 3 |
| | | | | Oct 2025 | 12,932 | 3 |

## Quick start

Full step-by-step guide for Windows, Miniforge and VS Code: **[SETUP.md](SETUP.md)**.

```bash
git clone https://github.com/Abson-dev/ensa-chad-harmonization.git harmonization
cd harmonization
conda env create -f environment.yml      # Python 3.11 + pinned packages from conda-forge
conda activate ensa-chad
python -m pytest -q                      # 11 rule tests
python run_harmonize.py                  # all domains, all rounds (about 2-3 min)
```

Useful options:

```bash
python run_harmonize.py --domains fcs                      # core + FCS only
python run_harmonize.py --rounds 2024-10 2025-10 --no-hash # quick partial run
python run_harmonize.py --formats csv                      # skip .sav output
```

## Interactive explorer (R Shiny)

[`app/`](app/) contains a Shiny app that presents the whole process for reviewers: an overview, a clickable pipeline diagram, the crosswalk workbook made interactive (coverage of 83 concepts × 14 rounds, a profile per concept), the fieldwork calendar and weights, validation against the original scores, FCS / rCSI indicators by round and region, and the data issues found.

The app ships **aggregates and metadata only**. Its `data/` folder is not versioned; build it after a pipeline run:

```bash
cd app
Rscript prepare_app_data.R       # aggregates ../output into app/data (cells < 30 households suppressed)
Rscript -e "shiny::runApp()"     # or double-click run_app.bat on Windows
```

Details, sharing options and package versions: [app/README.md](app/README.md). For a non-technical user who receives the app folder with its `data/`, see [app/README_FIRST.txt](app/README_FIRST.txt).

## Repository structure

```
harmonization/
├── config/                  <- ALL harmonisation decisions
│   ├── settings.toml        paths, FCS / rCSI weights and thresholds, date tolerance
│   ├── rounds.csv           one row per round: file, season, codebook generation, fieldwork window
│   ├── crosswalk.csv        one row per domain x target x round: method + source variable(s) + note
│   └── admin1_names.csv     every region spelling found -> standard name (32 -> 23)
├── ensa_harmonize/
│   ├── config.py            loads and validates the config
│   ├── engine.py            reads only the needed columns; applies crosswalk methods
│   ├── pipeline.py          orchestration, writers, provenance manifest
│   └── domains/             one module per domain: derive() + qc()
├── tests/test_rules.py      scoring rules, thresholds, conversions, config completeness
├── app/                     R Shiny explorer (app.R, R/ modules, www/, run_app.bat, prepare_app_data.R)
├── .vscode/                 interpreter, test and run/debug configuration
├── environment.yml          conda environment (conda-forge, pinned)
├── requirements.txt         pip alternative
├── run_harmonize.py         command-line entry point
├── SETUP.md                 installation and usage guide
└── output/                  generated, not versioned
```

## How harmonisation works

```
raw .sav (14 rounds) ──► crosswalk rules ──► domain derive() ──► ensa_<domain>.csv/.sav
        │                (config/*.csv)       (scores, flags)            │
        └────────────── SHA-256 ──────────► manifest.json ◄──── QC tables (qc/)
```

1. For each round, the engine reads **only** the columns that the selected domains need.
2. Each target is built by one crosswalk rule:

| Method | Meaning |
|---|---|
| `copy` | Take the source variable (text-stored numbers are converted) |
| `copy_label` | Take the SPSS value label instead of the code (admin names) |
| `sum` | Row sum of the `\|`-separated sources (missing only if all are missing) |
| `sum_cap7` | Row sum capped at 7 days |
| `missing` | Explicitly not available in this round; `note` says why |

3. The domain module computes the indicators and flags, and writes a QC table that compares them with the original scores.
4. All domain files share `round_id` + `hh_id` and join one-to-one to `ensa_core`.

## Validation

Recomputed scores against the scores pre-computed by the original analysts (± 0.5 points):

| Round | FCS agreement | rCSI agreement |
|---|---:|---:|
| Oct 2018 | 98.7% | 100% |
| Feb 2019 – Oct 2019 | 100% | 100% |
| Feb 2020 | 98.9% | 100% |
| Oct 2020 – Feb 2023 | 100% | 100% |
| Oct 2023 | no original score | 100% |
| Feb 2024 | 99.2% | 100% |
| Oct 2024 | no original score | no original score |
| Oct 2025 | no original score | 100% |

Per-round QC tables (completeness, invalid values, weighted means and prevalences, agreement) are written to `output/qc/` on every run.

## Domain decisions

### core
- `hh_id` = `round_id` + KoBo uuid. Rounds are independent cross-sections with no panel ID, so they are **stacked**, never joined on household.
- `svy_date` is converted from SPSS seconds; dates more than 7 days outside the fieldwork window are **flagged**, not removed.
- `admin1`: 32 raw spellings map to 23 standard names. `admin2` / `admin3` keep the source labels (P-code matching is a later step).
- `weight` is kept as provided. `weight_norm` rescales it to mean 1 within each round for pooled analyses.

### fcs
- WFP weights (2, 3, 1, 1, 4, 4, 0.5, 0.5, 0). The score is missing if any group is missing. Thresholds 28/42 (Chad standard) and 21/35.
- **Generation 1 staples:** cereals and tubers were asked separately. `FCSStap = min(7, cereals + tubers)` reproduces the analysts' own staples variable in 100% of households and is applied to every Gen-1 round.
- Raw answers are used, not the analysts' `*_cor` corrected items.

### rcsi
- rCSI = LessQlty + 2×Borrow + MealSize + 3×MealAdult + MealNb (0–56). Cadre Harmonisé phase: ≤3 / 4–18 / ≥19.
- **Oct 2024 skip pattern:** "restrict adults so children can eat" was not asked in households without children. It is set to 0 for those households (1,078, flagged per household); the 185 skipped answers in households with children stay missing.

## Data issues found during harmonisation

| Issue | Rounds | Handling |
|---|---|---|
| Pre-computed FCS groups coded in **reverse** (1 = Acceptable, 3 = Poor) | Feb 2020 – Feb 2023 | Groups recomputed; reversal detected automatically in QC |
| No usable sampling weight | Oct 2021, Feb 2024 (only group weights), Oct 2024 | Weighted QC left blank; weights to confirm with the data owners |
| Weights on a different scale (sum about 21k vs 130–240k) | Feb 2020 | `weight_norm` per round |
| LCS strategy slots renumbered and severities changed | 2021 onward | Content-based mapping (planned `lcs` domain) |
| Region name variants (Hajer/Hadjer Lamis, Wardi Fira, …) | Several | Explicit lookup table |
| Many pre-computed indicators stored as text | Gen 2 | Converted, then recomputed |

## Reproducibility

- **Deterministic:** the same inputs and config give byte-identical CSV and QC outputs (verified with SHA-256). The `.sav` outputs embed their creation time, so the CSVs are the reference outputs.
- **Provenance:** `output/manifest.json` records the run time, pipeline version, Python and package versions, and SHA-256 of every input, config file and output.
- **Pinned environment:** `environment.yml` (conda-forge) and `requirements.txt`.
- **Tests:** `python -m pytest -q` checks the config completeness, formulas, thresholds, conversions and lookups.

## Extending the pipeline

**New round** (e.g. Feb 2026): add a row to `config/rounds.csv` and one rule per target to `config/crosswalk.csv`, then run. Validation lists any target you forgot.

**New domain**: add its rules to `config/crosswalk.csv`, write `ensa_harmonize/domains/<name>.py` (with `rcsi.py` as a template: `NAME`, `LABELS`, `VALUE_LABELS`, `derive()`, `qc()`), register it in `domains/__init__.py` and add tests.

Details: [SETUP.md §10](SETUP.md#10-change-a-harmonisation-decision).

## Outputs

| File | Rows | Columns |
|---|---|---|
| `ensa_core.csv/.sav` | 197,947 | round_id, hh_id, year, season, generation, uuid, svy_date, date_flag, admin1, admin1_raw, admin2, admin3, weight, weight_norm, weight_flag |
| `ensa_fcs.csv/.sav` | 197,947 | round_id, hh_id, 9 food groups, fcs_n_missing, fcs_n_invalid, FCS, FCSCat21, FCSCat28, orig_FCS, orig_FCSCat28 |
| `ensa_rcsi.csv/.sav` | 197,947 | round_id, hh_id, 5 strategies, rcsi_mealadult_imputed, rcsi_n_missing, rcsi_n_invalid, rCSI, rCSI_CH, orig_rCSI |
| `qc/qc_<domain>_by_round.csv` | 14 | completeness, invalid values, unweighted and weighted indicators, agreement with original scores |

`orig_*` columns are kept for QC only; analyse the recomputed columns. Outputs contain household-level data and are **not versioned** (`.gitignore`).

## Author, citation and license

**Author:** [Abson-dev](https://github.com/Abson-dev)

If you use this pipeline, please cite the repository:

```
Abson-dev (2026). ENSA Chad 2018–2025 — Reproducible harmonisation of household food
security surveys. GitHub repository. https://github.com/Abson-dev/ensa-chad-harmonization
```

**License:** not yet specified. Add a `LICENSE` file before reusing the code. The license covers the code only; the ENSA data remain subject to the data owners' terms.

**Acknowledgements:** the ENSA surveys are produced by the Government of Chad (SISAAP) with WFP and partners; all credit for data collection goes to them.
