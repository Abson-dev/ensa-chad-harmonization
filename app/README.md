# ENSA Chad food security dashboard (R Shiny)

The dashboard of the ENSA Chad 2018–2025 harmonisation. It shows the food security situation of any round against the same season, and documents **how** the 14 survey rounds were made comparable.

> **No household-level data.** The app ships only variable metadata, pipeline configuration, QC tables and aggregate indicators by round and region (regional cells under 30 households suppressed). The estimates are preliminary, not official ENSA results.

## Pages

The **reference round** in the left panel drives Overview, Trends and Regions.

| Page | Question it answers |
|---|---|
| **Overview** | What is the situation in this round, and what should I check first? Key figures, points of attention generated from the data and QC tables, indicators of the latest rounds of the same season |
| **Trends** | How has an indicator moved, February with February and October with October, nationally or in one region? |
| **Regions** | How does a region compare with the national value and the other regions? Profile, ranking, region × round map |
| **Validation** | Do the results match the sources? Agreement with the analysts, the reversed FCS coding, the Stata check against the original files |
| **Data issues** | What was found, and how is it handled? |
| **Method** | *Approach*, *Process* (pipeline, rules), *Crosswalk* (83 concepts × 14 rounds, downloads), *Rounds* (fieldwork, weights) |
| **Data** | Filter the aggregate indicators and download them as CSV or Excel |
| **About** | Method, how to reproduce, run provenance, data statement |

Changes are shown against the latest earlier round of the **same season** with a value. If either round has no weight, both are compared unweighted. Rises are not coloured as good or bad, and there is no significance test: confidence intervals are in the Word report (`analysis/`).

## Run locally

Requires R ≥ 4.3 and these packages (versions tested):

```r
install.packages(c("shiny", "bslib", "bsicons", "plotly", "reactable", "visNetwork",
                   "shinyWidgets", "readxl", "readr", "dplyr", "tidyr", "jsonlite",
                   "data.table", "htmltools", "rlang", "DT", "writexl"))
# tested with R 4.5.2, shiny 1.14.0, bslib 0.11.0, plotly 4.12.0, reactable 0.4.5,
# visNetwork 2.1.4, shinyWidgets 0.9.1, readxl 1.4.5
```

On Windows, double-click `run_app.bat`. In RStudio / Positron: open `app.R` → **Run App**. No login is asked in these cases. In any non-interactive run (`Rscript`, a server), the app **requires a login and refuses to start without accounts**; for a local `Rscript` run, set `ENSA_LOCAL=1`.

### Synthetic mode

For screenshots and demonstrations, with invented estimates and a banner saying so:

```bash
Rscript make_demo_data.R      # builds demo_data/ (not versioned)
```

Then run the app with the environment variable `ENSA_DEMO=1`. The screenshots in the repository are taken this way, so that no real estimate goes on GitHub.

## Refresh the data

`app/data/` is generated. After each pipeline run (`python run_harmonize.py` in the parent folder):

```bash
cd app
Rscript prepare_app_data.R
```

This aggregates `../output/ensa_*.csv` (household files, never copied into the app) into `data/indicators_by_round*.csv`, for all 8 domains. It also copies the QC tables, the configuration, a cleaned manifest (file names only, no local paths), the latest crosswalk workbook and, if it was run, the result of the Stata check. It needs `data.table` and `jsonlite` in addition to the app packages. Run the pipeline with hashes (without `--no-hash`) first: the About page shows them.

## Test

```bash
Rscript tests/test_app.R     # every page and output, for every round; figures against the pipeline's QC;
                             # data boundary; login (173 checks); exit status 1 on failure
```

## Share with the IFPRI team

1. **Publish with a login** on shinyapps.io (one link, named accounts). From the `app/` folder:
   ```bash
   # Once: link the account, with the token from the Tokens page of shinyapps.io
   #   rsconnect::setAccountInfo(name = "...", token = "...", secret = "...")
   Rscript manage_accounts.R first.name other.name   # creates the accounts; list ALL accounts to keep
   Rscript publish.R                                 # lists what would be sent; sends nothing
   Rscript publish.R --publish                       # sends it
   ```
   For Posit Connect Cloud: link it once with `rsconnect::connectCloudUser()`, then `Rscript publish.R --publish --target=connect`.
   - Passwords are written to `accounts_passwords.csv`. Send each one individually through a safe channel, then delete that file.
   - `publish.R` sends only the files on its allow-list, and refuses to run without accounts, if `.Renviron` would disable the login, or if a file looks like household data.
   - The app starts only with its accounts database and secret. Its URL can be public: the login is what protects the data.
   - **Before sending the link,** open it in a private browser window: you should see the login page, with no data.
   - After a data refresh, or to change the accounts, run the same commands again.
2. **Zip the `app/` folder** (with `data/`) and share it; recipients double-click `run_app.bat` (see `README_FIRST.txt`). Leave out `accounts.sqlite`, `accounts_passwords.csv` and `.Renviron`.

Check with the data owners (SISAAP / WFP) before publishing the regional indicators outside the team.

## Structure

```
app/
├── app.R                 page layout, reference round and server wiring
├── R/                    loaded automatically by Shiny
│   ├── data.R            loads the workbook, config, QC and indicators
│   ├── utils.R           theme, indicator catalogue, same-season comparison, chart style, helpers
│   ├── auth.R            login: required on a server, refuses to start without accounts
│   └── mod_*.R           one module per page
├── www/styles.css        visual design: WFP Visual Brand Guide v6.0 colours
├── www/fonts/            Open Sans, WFP's corporate font, with its licence (OFL.txt)
├── tests/test_app.R      checks of every page, the figures, the data boundary and the login
├── data/                 generated by prepare_app_data.R (aggregates and metadata only; not versioned)
├── prepare_app_data.R
├── make_demo_data.R      synthetic estimates for screenshots and demonstrations
├── manage_accounts.R     creates the login accounts (database, secret and passwords are not versioned)
└── publish.R             publishes to Posit Connect Cloud from an allow-list; a dry run by default
```
