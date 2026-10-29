# Setup guide — Miniforge + VS Code

How to install, run, test and maintain the ENSA Chad harmonisation pipeline on Windows with **Miniforge** (conda from conda-forge) and **Visual Studio Code**.

For what the pipeline does and why, see [README.md](README.md).

---

## Contents

1. [Prerequisites](#1-prerequisites)
2. [Get the project and data](#2-get-the-project-and-data)
3. [Create the conda environment](#3-create-the-conda-environment)
4. [Check the installation](#4-check-the-installation)
5. [Open the project in VS Code](#5-open-the-project-in-vs-code)
6. [Run the pipeline](#6-run-the-pipeline)
7. [Run the tests](#7-run-the-tests)
8. [Debug a rule](#8-debug-a-rule)
9. [Explore the outputs in a notebook](#9-explore-the-outputs-in-a-notebook)
10. [Change a harmonisation decision](#10-change-a-harmonisation-decision)
11. [Keep the environment reproducible](#11-keep-the-environment-reproducible)
12. [Verify that a run reproduces the reference outputs](#12-verify-that-a-run-reproduces-the-reference-outputs)
13. [Version control with Git (recommended)](#13-version-control-with-git-recommended)
14. [Troubleshooting](#14-troubleshooting)
15. [Command cheat sheet](#15-command-cheat-sheet)

---

## 1. Prerequisites

| Tool | Version used | Where to get it |
|---|---|---|
| Miniforge | conda 26.x | <https://github.com/conda-forge/miniforge> → *Miniforge3-Windows-x86_64.exe* |
| Visual Studio Code | any recent | <https://code.visualstudio.com> |
| VS Code extensions | — | **Python** (`ms-python.python`), **Python Debugger** (`ms-python.debugpy`), **Jupyter** (`ms-toolsai.jupyter`) |
| Git *(optional)* | any | <https://git-scm.com> |

### Install Miniforge (skip if already installed)

1. Run the installer and choose **Just Me** (no administrator rights needed).
2. Keep the default location: `%LOCALAPPDATA%\miniforge3`.
3. Leave **"Add Miniforge3 to my PATH"** unticked (recommended by the installer).

Afterwards you will have a **Miniforge Prompt** entry in the Start menu. Use it for all `conda` commands in this guide.

> **If Anaconda is also installed on the machine** (common on CGIAR laptops), the two can shadow each other. Always use **Miniforge Prompt**, not "Anaconda Prompt", and check which conda is active:
> ```bat
> where conda
> ```
> The first line should point to `...\miniforge3\...`.

### Install the VS Code extensions

In VS Code: **Extensions** (`Ctrl+Shift+X`) → search and install **Python** and **Jupyter** (Python Debugger installs with Python).

---

## 2. Get the project and data

The pipeline expects this layout. Only the `harmonization` folder is code; the `.sav` files are the raw data and are **never modified**.

```
ENSA Chad data 2018-2025/
├── Round  de fevrier/          <- 6 February .sav files (note: two spaces after "Round")
├── Round d'octobre/            <- 8 October .sav files
└── harmonization/              <- this project
    ├── config/
    ├── ensa_harmonize/
    ├── tests/
    ├── environment.yml
    ├── run_harmonize.py
    ├── README.md
    └── SETUP.md                <- this file
```

If the data lives elsewhere, change one line in `config/settings.toml`:

```toml
[paths]
data_dir = ".."     # relative to harmonization/, or an absolute path such as "D:/data/ENSA"
```

---

## 3. Create the conda environment

The environment is defined in `environment.yml` (name **`ensa-chad`**, pinned versions of Python 3.11, pandas, numpy, pyreadstat, pytest, openpyxl, ipykernel).

### On a corporate / CGIAR network: let conda trust the network certificate (once)

Many institutional networks inspect HTTPS traffic with their own certificate. conda then fails with:

```
CondaSSLError: ... CERTIFICATE_VERIFY_FAILED ... self-signed certificate in certificate chain
```

Tell conda to use the Windows certificate store, which already trusts the network certificate. In **Miniforge Prompt**:

```bat
conda config --set ssl_verify truststore
```

This is a one-time user setting (stored in `%USERPROFILE%\.condarc`). To undo it: `conda config --remove-key ssl_verify`. Do **not** use `ssl_verify false`, which turns off certificate checking entirely.

### Create the environment

Open **Miniforge Prompt** and run:

```bat
cd "%USERPROFILE%\OneDrive - CGIAR\Desktop\2026\SPACERISE\Apply\ENSA Chad data 2018-2025\harmonization"
conda env create -f environment.yml
```

This downloads the packages from conda-forge (a few minutes the first time). Then activate it:

```bat
conda activate ensa-chad
```

The prompt now starts with `(ensa-chad)`. You need to activate it in every new Miniforge Prompt window. VS Code does it automatically (section 5).

---

## 4. Check the installation

Still in the activated prompt:

```bat
python --version
python -c "import pandas, numpy, pyreadstat; print(pandas.__version__, numpy.__version__, pyreadstat.__version__)"
python -m pytest -q
```

Expected:

```
Python 3.11.x
2.2.2 2.2.6 1.2.7
...........                                                              [100%]
20 passed
```

If the tests pass, the environment and the data paths are correct.

---

## 5. Open the project in VS Code

From the activated Miniforge Prompt (still inside `harmonization`):

```bat
code .
```

or in VS Code: **File → Open Folder…** → select the **`harmonization`** folder.

> Open `harmonization` itself, **not** the parent data folder. The project settings in `harmonization/.vscode/` are only read when it is the opened folder.

### Select the interpreter

`.vscode/settings.json` already points VS Code to `%LOCALAPPDATA%\miniforge3\envs\ensa-chad\python.exe`. Check the **status bar** (bottom right): it should show `3.11.x ('ensa-chad')`.

If it shows another environment:

1. `Ctrl+Shift+P` → **Python: Select Interpreter**
2. Choose **`ensa-chad`** (path containing `miniforge3\envs\ensa-chad`)

If `ensa-chad` is not listed, choose **Enter interpreter path…** and paste:

```
%LOCALAPPDATA%\miniforge3\envs\ensa-chad\python.exe
```

### Integrated terminal

Open it with `` Ctrl+` ``. With the Python extension it activates `ensa-chad` automatically; the prompt shows `(ensa-chad)`.

If you see `conda : The term 'conda' is not recognized` in the PowerShell terminal, run this **once** in Miniforge Prompt, then restart VS Code:

```bat
conda init powershell
```

---

## 6. Run the pipeline

### Option A — Run and Debug panel (no typing)

1. `Ctrl+Shift+D` opens **Run and Debug**.
2. Pick a configuration from the drop-down (defined in `.vscode/launch.json`):
   - **Harmonise: all domains**: full run, all 14 rounds, about 2–3 minutes
   - **Harmonise: quick test (2 rounds, no hash)**: Oct 2024 + Oct 2025 only, about 20 seconds; use it while developing
3. Press **F5** (or the green ▶).

### Option B — Terminal

```bat
python run_harmonize.py                                    # all domains, all rounds
python run_harmonize.py --domains fcs                      # core + FCS only
python run_harmonize.py --rounds 2024-10 2025-10           # selected rounds
python run_harmonize.py --no-hash                          # skip input SHA-256 (faster)
python run_harmonize.py --formats csv                      # CSV only, no .sav
python run_harmonize.py --help                             # all options
```

`core` is always built, because every domain joins to it.

### What is produced

```
output/
├── ensa_core.csv / .sav      keys, date, regions, weight
├── ensa_fcs.csv  / .sav      FCS items, score, groups
├── ensa_rcsi.csv / .sav      rCSI items, score, CH phase
├── qc/qc_<domain>_by_round.csv
├── manifest.json             inputs, config, versions, output hashes
└── harmonize.log             log of the last run
```

All domain files share `round_id` + `hh_id`. Example merge in Python:

```python
import pandas as pd
core = pd.read_csv("output/ensa_core.csv", parse_dates=["svy_date"])
fcs  = pd.read_csv("output/ensa_fcs.csv")
df   = core.merge(fcs, on=["round_id", "hh_id"], validate="one_to_one")
```

In SPSS, open the `.sav` files directly. They carry variable and value labels.

---

## 7. Run the tests

Run the tests after **any** change to code or `config/`.

### In VS Code

1. Click the **Testing** icon (flask) in the left bar.
2. The first time, if prompted, choose **pytest** and the folder **tests** (already set in `.vscode/settings.json`).
3. Click ▶ **Run Tests**. All 20 should turn green.

### In the terminal

```bat
python -m pytest -q
```

The tests check the configuration (every rule present for every round, input files found), the FCS and rCSI formulas, category thresholds, out-of-range handling, the Gen-1 staples rule, text-to-number conversion, SPSS date conversion and the region lookup.

---

## 8. Debug a rule

Use this to see exactly what happens to the data at any step.

1. Open a domain module, e.g. `ensa_harmonize/domains/rcsi.py`.
2. Click in the margin left of a line number (e.g. the line `out["rCSI"] = rcsi_score(...)`) to set a red **breakpoint**.
3. `Ctrl+Shift+D` → select **Harmonise: quick test** → **F5**.
4. Execution pauses at the breakpoint:
   - the **Variables** pane shows the objects (`t`, `items`, `out`, …)
   - the **Debug Console** accepts Python, e.g. `items.describe()` or `t["rCSIMealAdult"].isna().sum()`
5. **F10** steps over a line, **F5** continues, **Shift+F5** stops.

---

## 9. Explore the outputs in a notebook

1. `Ctrl+Shift+P` → **Create: New Jupyter Notebook**.
2. Top right, **Select Kernel** → **Python Environments** → **`ensa-chad`**.
3. Save it in a separate folder, e.g. `harmonization/notebooks/explore.ipynb`, so analysis stays separate from the pipeline code.

Example cells:

```python
import pandas as pd
qc = pd.read_csv("../output/qc/qc_fcs_by_round.csv")
qc[["round_id", "fcs_mean_weighted", "poor_28_pct_w", "borderline_28_pct_w"]]
```

```python
core = pd.read_csv("../output/ensa_core.csv")
fcs  = pd.read_csv("../output/ensa_fcs.csv")
d = core.merge(fcs, on=["round_id", "hh_id"])
d.groupby(["round_id", "admin1"])["FCS"].mean().unstack(0).round(1)
```

> Notebooks are for exploring. Any rule that changes the harmonised data belongs in `config/` or `ensa_harmonize/`, never only in a notebook. Otherwise it is not reproduced on the next run.

---

## 10. Change a harmonisation decision

All decisions live in `config/`. Edit them in VS Code; CSV files open as text.

| To change… | Edit | Example |
|---|---|---|
| Which source variable feeds a target in a round | `config/crosswalk.csv` | change `sources` of `rcsi,rCSIBorrow,2021-02,...` |
| Declare a variable unavailable | `config/crosswalk.csv` | `method = missing`, explain in `note` |
| A new region spelling | `config/admin1_names.csv` | add `raw_name,admin1` |
| FCS / rCSI weights or thresholds | `config/settings.toml` | `thresholds_28 = [28.0, 42.0]` |
| Fieldwork window used for date checks | `config/rounds.csv` | `fieldwork_start`, `fieldwork_end` |
| Data location | `config/settings.toml` | `data_dir` |

Crosswalk methods: `copy`, `copy_label`, `sum`, `sum_cap7`, `missing` (see README).

Then always:

```bat
python -m pytest -q
python run_harmonize.py
```

and check the QC tables in `output/qc/`. If the configuration is invalid, the run stops and lists every problem (missing rule, unknown method, unknown region spelling, …).

### Add a new round (e.g. February 2026)

1. Put the `.sav` file in `Round  de fevrier/`.
2. Add a row to `config/rounds.csv`.
3. Add one row per target to `config/crosswalk.csv` with `round_id = 2026-02`. Use `ENSA_Chad_crosswalk_2018-2025.xlsx` (in the data folder) to find the variable names.
4. Run the tests: any target you forgot is listed by name.
5. Run the pipeline and review `output/qc/`.

### Add a new domain (e.g. HDDS)

1. Add its rules to `config/crosswalk.csv` (`domain = hdds`), one per target and round.
2. Copy `ensa_harmonize/domains/rcsi.py` to `hdds.py` and adapt `NAME`, `ITEMS`, `LABELS`, `VALUE_LABELS`, `derive()`, `qc()`. If answer codes differ between rounds, put them in a `config/<name>.csv` table read with `cfg.table("<name>")`, as `lcs.py` does with `lcs_responses.csv` and `lcs_severity.csv`.
3. Register it in `ensa_harmonize/domains/__init__.py`.
4. Add tests in `tests/test_rules.py`.
5. Run `python run_harmonize.py --domains hdds`.

---

## 11. Keep the environment reproducible

**Rule: the environment is defined by `environment.yml`, not by what happens to be installed.**

| Situation | Do this |
|---|---|
| You need a new package | Add it to `environment.yml`, then `conda env update -f environment.yml --prune` |
| You want to upgrade a package | Change its pinned version in `environment.yml`, update, rerun the tests and compare outputs (section 12) |
| The environment is broken | `conda env remove -n ensa-chad` then `conda env create -f environment.yml` |
| A colleague sets up the project | They follow sections 1–4 and get the same versions |

Avoid one-off `pip install` or `conda install` commands in the environment. They are not recorded, and the next person cannot rebuild the same setup.

To record the **exact** build of every package (including dependencies) for an archive or publication:

```bat
conda env export -n ensa-chad --no-builds > environment.lock.yml
conda list -n ensa-chad --explicit > conda-explicit-win64.txt
```

`conda-explicit-win64.txt` recreates the identical environment on Windows:

```bat
conda create -n ensa-chad --file conda-explicit-win64.txt
```

---

## 12. Verify that a run reproduces the reference outputs

Each run writes `output/manifest.json` with:

- SHA-256 of every input `.sav` file and every config file
- Python and package versions
- SHA-256 of every output file and the row counts

To check that a colleague (or a future you) gets the same result:

1. Keep a copy of a reference manifest, e.g. `manifest_reference.json`.
2. Run the pipeline.
3. Compare:

```bat
python -c "import json; a=json.load(open('manifest_reference.json')); b=json.load(open('output/manifest.json')); [print('OK  ' if x['sha256']==y['sha256'] else 'DIFF', x['file']) for x,y in zip(a['outputs'], b['outputs'])]"
```

The **CSV and QC files must be `OK`**. The `.sav` files always show `DIFF`, because SPSS stores the creation time in the file header; their content is the same.

If a CSV differs, compare the `inputs`, `config` and `environment` sections of the two manifests. One of them has changed.

---

## 13. Version control with Git (recommended)

Git keeps a dated history of every code and configuration decision, which you can cite and roll back.

### One-time setup

In the activated Miniforge Prompt, inside `harmonization`:

```bat
git init
git config user.name "Your Name"
git config user.email "you@example.org"
```

Create a file `.gitignore` in `harmonization` with:

```gitignore
# generated outputs (rebuild with run_harmonize.py)
output/
# raw data is never committed
*.sav
# Python / tooling
__pycache__/
.pytest_cache/
.ipynb_checkpoints/
```

Then:

```bat
git add .
git commit -m "ENSA harmonisation: core, FCS, rCSI"
```

### Daily use in VS Code

**Source Control** panel (`Ctrl+Shift+G`):
1. Review changed files (click one to see the diff).
2. Type a message that explains the decision, e.g. *"rCSI: set MealAdult to 0 when no children (Oct 2024 skip)"*.
3. **Commit**.

The raw data and outputs stay out of Git. Anyone with the repository and the `.sav` files can regenerate the outputs.

---

## 14. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `CondaSSLError … CERTIFICATE_VERIFY_FAILED` | Network inspects HTTPS with its own certificate | `conda config --set ssl_verify truststore` (section 3) |
| `'conda' is not recognized` (cmd) | Not using Miniforge Prompt | Open **Miniforge Prompt** from the Start menu |
| `conda` not recognized in the VS Code PowerShell terminal | Shell not initialised | In Miniforge Prompt: `conda init powershell`, then restart VS Code |
| `where conda` shows `anaconda3` | Anaconda shadows Miniforge | Use Miniforge Prompt, or call `%LOCALAPPDATA%\miniforge3\Scripts\conda.exe` directly |
| `ensa-chad` missing from **Select Interpreter** | Environment not created, or VS Code not reloaded | Check `conda env list`; then `Ctrl+Shift+P` → **Developer: Reload Window** |
| `ModuleNotFoundError: pyreadstat` | Wrong interpreter selected | Status bar must show `ensa-chad`; reselect it (section 5) |
| `PowerShell: running scripts is disabled` | Execution policy | `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` in PowerShell, or switch the terminal to cmd (`Ctrl+Shift+P` → **Terminal: Select Default Profile** → Command Prompt) |
| `FileNotFoundError` for a `.sav` | Data moved, or folder name differs (`Round  de fevrier` has **two** spaces) | Fix `data_dir` in `config/settings.toml` or the folder name in `config/rounds.csv` |
| `Invalid crosswalk: no rule for …` | A target lacks a rule for some round | Add the row (use `method = missing` if unavailable) |
| `admin1 spellings missing from config/admin1_names.csv` | New region spelling in the data | Add it to `config/admin1_names.csv` |
| `PermissionError` when writing outputs | Output file open in Excel or SPSS | Close the file and rerun |
| Slow first run | Packages loading, OneDrive syncing large files | Make the data folder *Always keep on this device* in OneDrive; use `--no-hash` while developing |
| Accented names look like `Ouadda�` in the terminal | Console display only; the files are correct | Ignore, or run `chcp 65001` in the terminal |

---

## 15. Command cheat sheet

```bat
:: --- once ---
conda config --set ssl_verify truststore     :: only on networks that inspect HTTPS
cd "%USERPROFILE%\OneDrive - CGIAR\Desktop\2026\SPACERISE\Apply\ENSA Chad data 2018-2025\harmonization"
conda env create -f environment.yml

:: --- every session ---
conda activate ensa-chad
code .

:: --- work ---
python -m pytest -q                          :: tests
python run_harmonize.py                      :: full run
python run_harmonize.py --rounds 2025-10 --no-hash   :: quick run
python run_harmonize.py --domains fcs        :: one domain (+ core)

:: --- environment maintenance ---
conda env update -f environment.yml --prune  :: after editing environment.yml
conda env remove -n ensa-chad                :: rebuild from scratch (then create again)
conda env list                               :: list environments
```

| VS Code shortcut | Action |
|---|---|
| `Ctrl+Shift+P` | Command palette (Select Interpreter, New Notebook, Reload Window) |
| `` Ctrl+` `` | Integrated terminal |
| `Ctrl+Shift+D` then `F5` | Run the selected launch configuration |
| `F9` / `F10` / `Shift+F5` | Toggle breakpoint / step over / stop debugging |
| `Ctrl+Shift+G` | Source Control (Git) |
| `Ctrl+Shift+X` | Extensions |
