# Analysis by domain (R Markdown → Word)

Merges the harmonised domain files (`../output/ensa_core`, `ensa_fcs`, `ensa_rcsi`, `ensa_lcs`, `ensa_hhs`, `ensa_hdds`, `ensa_exp`, `ensa_demo`) and produces a Word report with survey-weighted tables and figures, plus every table as CSV and every figure as PNG for reuse in other documents.

```
analysis/
├── analysis_by_domain.Rmd        the report (officedown → Word)
├── render_report.R               renders it: installs missing packages, finds Pandoc, updates Word fields
├── render_report.bat             double-click launcher (Windows); opens the report when done
├── R/
│   ├── load_data.R               reads and merges the domain files; indicator flags; analysis weight
│   ├── estimates.R               survey design, weighted estimates with 95% CI, region × round grids
│   └── theme.R                   palettes (FCS, Cadre Harmonisé), ggplot theme, flextable style, captions
├── tools/update_word_fields.ps1  fills in the table of contents and table/figure numbers with Word
└── output/                       generated, not versioned (contains regional estimates)
    ├── ENSA_Chad_analysis_by_domain.docx
    ├── figures/                  F01–F19 (PNG, 300 dpi)
    └── tables/                   T01–T20, A01 (CSV)
```

## Run

Prerequisite: the harmonised files exist (`python run_harmonize.py` in the parent folder).

```bash
cd analysis
Rscript render_report.R          # or double-click render_report.bat on Windows
```

About 1–2 minutes. Missing R packages are installed on first run. **Pandoc** is needed to write Word files: the script finds the copy bundled with RStudio, Quarto or Positron, or a standalone install (<https://pandoc.org/installing.html>). On Windows with Microsoft Word installed, the table of contents and the table / figure numbers are filled in automatically; otherwise open the report and press **Ctrl+A, then F9**.

Parameters (top of `analysis_by_domain.Rmd`, or `params = list(...)` in `render_report.R`):

| Parameter | Default | Meaning |
|---|---|---|
| `data_dir` | `../output` | harmonised domain files |
| `cluster` | `admin3` | variance clusters: sub-prefecture as approximate PSU, or `none` (simple random sampling) |
| `min_cell` | `30` | regional estimates on fewer households are suppressed |
| `author` | — | shown on the title page |

## Report contents

| Section | Tables | Figures |
|---|---|---|
| Key messages | computed from the data (no hand-typed numbers) | |
| Data and methods | rounds, households, fieldwork, weighting | |
| Sample (core) | | households per round and questionnaire generation |
| Food consumption (FCS) | national FCS and groups with 95% CI (28/42 and 21/35); regions, latest vs previous October | groups by round and season; days per food group; **decomposition of the FCS change by food group**; region × round heatmap |
| Coping (rCSI) | national rCSI and Cadre Harmonisé phases with 95% CI; regions, latest vs previous October | phases by round and season; use of each strategy; region × round heatmap |
| Livelihood coping (LCS) | maximum category by round with 95% CI: comparable (7 strategies asked in every round, coping for food) and round-specific | categories by round and season; use of each of the 14 strategies; region × round heatmap of crisis + emergency |
| Household Hunger Scale (HHS) | score, moderate / severe hunger and phase 3+ by round with 95% CI (from Oct 2019) | IPC phases by round and season; each hunger experience by round; region × round heatmap of phase 3+ |
| Household profile (demographics) | female-headed share, head's age, household size, no formal education, by round | main income source (broad categories) by round |
| Dietary diversity (HDDS) | mean HDDS and CH phases with 95% CI | phases by round and season; share eating each food group |
| Expenditure | median food and total expenditure, food share and share ≥ 75% with 95% CI (not available Oct 2024) | food-share categories by round and season, with the generation-3 caveat |
| Cross-domain | indicators by sex of the household head (latest October, with significance) |  |
| Food consumption × coping | overlap (poor/borderline FCS and rCSI phase 3+), Spearman correlation by round | joint distribution in the latest round; regional scatter |
| Limitations, annex | households by region × round; provenance (data run, package versions) | |

## Methods in brief

- **Weights:** normalised survey weights (mean 1 within round). Oct 2021, Feb 2024 and Oct 2024 have no usable weight and are estimated unweighted (marked † everywhere).
- **Confidence intervals:** `survey` package; the harmonised files do not carry the official strata / PSUs, so sub-prefectures are used as approximate clusters (conservative intervals). Replace with the official design variables when available.
- **Comparisons:** regional changes compare the two most recent *weighted* October rounds; February and October are compared within season.
- **Text:** every number and direction word in the text ("rose", "weak", …) is computed, so the narrative stays correct when the data are updated.

The report contains regional estimates: `output/` is not versioned. Share the Word file only with the data owners' agreement (SISAAP / WFP).
