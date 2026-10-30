# ENSA data assistant (AI agent)

Ask questions about the harmonised ENSA Chad surveys in plain English or French, for example:

> *Which regions had the highest share of poor or borderline food consumption in October 2025, and how does that compare with October 2024?*
>
> *Pourquoi l'accord du LCS avec les analystes est-il faible en février 2019 ?*

The assistant is Claude (Anthropic API) with seven **read-only tools** over aggregate tables. It looks up the numbers, checks the documented data issues and the harmonisation rules, and answers with the round, the unit and whether the round is weighted. With `--sources` it lists the tool calls behind each answer.

## Data boundary: no household data leaves the machine

```
output/ensa_*.csv  ──►  build_agent_data.py  ──►  agent/data/       ──►  tools  ──►  Claude API
(197,947 households)    (runs locally)            aggregates only         (read-only)
                                                  cells < 30 HH suppressed
```

- `build_agent_data.py` is the **only** step that reads household files. It writes indicators by round × {national, region, sex of head}, the per-round QC tables, the crosswalk rules and the documented data issues to `agent/data/`.
- The tools read `agent/data/` only. No tool can return a household record, and the tests check that no file in `agent/data/` has household-level columns.
- Regional cells with fewer than 30 households are suppressed (same rule as the Shiny app and the Word report).
- `agent/data/` is **not versioned** (`.gitignore`). Regional aggregates are still sent to the API when a question needs them: **agree this use with the data owners (SISAAP / WFP) before sharing the assistant.**

## Setup

1. The agent has **its own conda environment**, `ensa-agent`, separate from the pipeline's `ensa-chad`, so the API client never enters the pipeline environment. From the repository root:
   ```bash
   conda env create -f agent/environment.yml
   conda activate ensa-agent
   ```
   (Without conda: a virtual environment with `pip install pandas==2.2.2 numpy==2.2.6 pytest==8.2.2 -r agent/requirements-agent.txt`.) In VS Code, select the `ensa-agent` interpreter for the `agent/` files (*Python: Select Interpreter*).
2. An Anthropic API key, from <https://console.anthropic.com>:
   ```powershell
   setx ANTHROPIC_API_KEY "sk-ant-..."     # Windows, then open a new terminal
   ```
3. Build the aggregate tables, after each pipeline run (about 1.5 minutes):
   ```bash
   conda activate ensa-chad && python run_harmonize.py      # only if output/ is not up to date
   conda activate ensa-agent && python agent/build_agent_data.py
   ```

All the commands below run in `ensa-agent`.

## Use

```bash
python agent/ask.py "What share of households were female-headed in October 2023?"
python agent/ask.py --sources        # interactive; 'reset' clears the conversation, 'quit' exits
```

From Python (e.g. a notebook, or later a Shiny tab via `reticulate`):

```python
import sys; sys.path.insert(0, "agent")
from ensa_agent.agent import EnsaAgent
agent = EnsaAgent()
a = agent.ask("Compare rCSI phase 3+ between Oct 2024 and Oct 2025 by region")
print(a.text, a.tool_calls)
a = agent.ask("And for female-headed households?")    # follow-ups keep the conversation
```

Settings (environment variables): `ENSA_AGENT_MODEL` (default `claude-opus-5-5`), `ENSA_AGENT_EFFORT` (`low` … `max`, default `high`; `medium` is cheaper and often enough for simple look-ups), `ENSA_AGENT_DATA` (folder of the aggregate tables).

## What it can answer

| Tool | Gives |
|---|---|
| `list_indicators` | the 58 indicators: FCS (and days per food group), rCSI, LCS (comparable and round-specific, each strategy), HHS, HDDS, expenditure and food share, household profile, main income source, FCS × rCSI |
| `get_indicator` | an indicator by round, nationally, by region or by sex of the head (value, households, weighted) |
| `compare_rounds` | change between two rounds, with a note when the seasons differ |
| `list_rounds` | rounds, generation, households, weight availability, fieldwork window |
| `get_quality_checks` | per-round completeness and agreement with the original analysts' variables |
| `get_crosswalk` | the source variable and method for any target × round |
| `search_data_issues` | the documented data issues and how they are handled |

It does **not** have confidence intervals or significance tests (use the Word report from `analysis/`), breakdowns below region, or anything not in these tables. Its instructions tell it to say so rather than guess.

## Check it

```bash
python -m pytest agent/tests -q                 # offline: data boundary, suppression, tools (no API calls)
python agent/evals/run_evals.py --dry-run       # the 12 eval questions and their expected values
python agent/evals/run_evals.py                 # asks the agent each question and grades the answers
```

The evals (`evals/questions.csv`) check that answers contain the right number (read from the tables at run time, ± 0.15) and the expected caveats: unweighted rounds, Oct 2024 expenditure not available, refusing household-level requests, the reversed FCS groups. A full run calls the API 12 times. Re-run it after any change to the instructions (`ensa_agent/system_prompt.md`) or the tools. Results go to `evals/results/` (not versioned).

## Files

```
agent/
├── build_agent_data.py        household files -> aggregate tables (the only step that reads household data)
├── ask.py                     command line: one question or interactive
├── environment.yml            conda environment ensa-agent (Python 3.11, pandas, anthropic, pytest)
├── requirements-agent.txt     pip alternative (anthropic SDK, pinned)
├── ensa_agent/
│   ├── indicators.py          the 58 indicator definitions (one place, used by the build and the tools)
│   ├── tools.py               the 7 read-only tools
│   ├── system_prompt.md       the assistant's instructions: methods, caveats, answer style
│   └── agent.py               EnsaAgent: tool loop, conversation history, token counts
├── tests/test_agent_tools.py  offline tests
├── evals/                     questions.csv, run_evals.py
└── data/                      generated, not versioned
```

## Cost

Each question takes a few tool calls. The instructions and tool definitions are cached between questions, so follow-up questions in the same session cost less. `ask.py` prints the tokens used for each answer; check the current prices at <https://www.anthropic.com/pricing>.
