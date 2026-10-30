"""Read-only tools for the ENSA agent.

Every tool reads the aggregate tables in agent/data/ (built by
build_agent_data.py). None of them can open a household file, so nothing the
model sees is a household record. Each call is logged in TRACE so the answer
can show where its numbers came from.
"""
from __future__ import annotations

import json
import os
from functools import lru_cache
from pathlib import Path

import pandas as pd
from anthropic import beta_tool

DATA = Path(os.environ.get("ENSA_AGENT_DATA", Path(__file__).resolve().parents[1] / "data"))
TRACE: list[dict] = []
MAX_ROWS = 400


@lru_cache(maxsize=None)
def _table(name: str) -> pd.DataFrame:
    path = DATA / name
    if not path.exists():
        raise FileNotFoundError(f"{path} not found. Build it first: python agent/build_agent_data.py")
    return pd.read_csv(path, dtype={"round_id": str})


def _log(tool: str, **args) -> None:
    TRACE.append({"tool": tool, "args": {k: v for k, v in args.items() if v not in ("", None)}})


def _csv(df: pd.DataFrame) -> str:
    if len(df) > MAX_ROWS:
        return f"{len(df)} rows: too many, narrow the request (rounds, groups or breakdown)."
    return df.to_csv(index=False, float_format="%.1f")


def _split(s: str) -> list[str]:
    return [x.strip() for x in s.split(",") if x.strip()]


def _round_ids(rounds: str) -> list[str]:
    """Accept '2025-10' or 'Oct 2025' (comma-separated); empty means all rounds."""
    if not rounds.strip():
        return []
    r = _table("rounds.csv")
    lookup = {**dict(zip(r["round"].str.lower(), r["round_id"])), **{x: x for x in r["round_id"]}}
    return [lookup.get(x.lower(), x) for x in _split(rounds)]


@beta_tool
def list_indicators(domain: str = "") -> str:
    """List the indicators available, with id, label, unit and definition.

    Call this first when you are unsure of an indicator id.

    Args:
        domain: Optional filter: fcs, rcsi, lcs, hhs, hdds, exp, demo or cross.
    """
    _log("list_indicators", domain=domain)
    cat = _table("indicator_catalog.csv")
    if domain:
        cat = cat[cat["domain"] == domain.strip().lower()]
    return _csv(cat)


@beta_tool
def list_rounds() -> str:
    """List the 14 survey rounds: round id and label, season, questionnaire generation, households,
    whether a sampling weight is available, and the fieldwork window."""
    _log("list_rounds")
    return _csv(_table("rounds.csv"))


@beta_tool
def get_indicator(indicator: str, breakdown: str = "national", rounds: str = "", groups: str = "") -> str:
    """Get an indicator by round as a table: value, households with data (n), weighted or not.

    Values are point estimates (weighted where the round has a sampling weight). Empty value with
    n = 0 means not collected in that round; suppressed = true means fewer than 30 households.

    Args:
        indicator: Indicator id from list_indicators, e.g. fcs_poor_borderline.
        breakdown: national, region or head_sex.
        rounds: Optional comma-separated rounds, e.g. "2024-10,2025-10" or "Oct 2024, Oct 2025". Empty = all.
        groups: Optional comma-separated region names or Male-headed / Female-headed. Empty = all.
    """
    _log("get_indicator", indicator=indicator, breakdown=breakdown, rounds=rounds, groups=groups)
    cat = _table("indicator_catalog.csv").set_index("indicator")
    if indicator not in cat.index:
        return f"Unknown indicator '{indicator}'. Call list_indicators to see the valid ids."
    if breakdown not in ("national", "region", "head_sex"):
        return "breakdown must be national, region or head_sex."
    t = _table("indicators.csv")
    t = t[(t["indicator"] == indicator) & (t["breakdown"] == breakdown)]
    if rid := _round_ids(rounds):
        t = t[t["round_id"].isin(rid)]
    if grp := _split(groups):
        t = t[t["group"].str.lower().isin([g.lower() for g in grp])]
        if t.empty:
            all_t = _table("indicators.csv")
            names = sorted(all_t.loc[all_t["breakdown"] == breakdown, "group"].unique())
            return f"No rows for groups {grp}. Valid names for {breakdown}: {names}"
    info = cat.loc[indicator]
    head = f"# {info['label']} ({info['unit']}). {info['definition']}\n"
    return head + _csv(t[["round_id", "round", "group", "value", "n", "weighted", "suppressed"]])


@beta_tool
def compare_rounds(indicator: str, round_a: str, round_b: str, breakdown: str = "national") -> str:
    """Compare an indicator between two rounds: value in each, change (b - a) in points, and whether each
    round is weighted. Point estimates only: no significance test (confidence intervals are in the Word report).

    Args:
        indicator: Indicator id from list_indicators.
        round_a: Earlier round, e.g. "2024-10" or "Oct 2024".
        round_b: Later round, e.g. "2025-10" or "Oct 2025".
        breakdown: national, region or head_sex.
    """
    _log("compare_rounds", indicator=indicator, round_a=round_a, round_b=round_b, breakdown=breakdown)
    if indicator not in set(_table("indicator_catalog.csv")["indicator"]):
        return f"Unknown indicator '{indicator}'. Call list_indicators to see the valid ids."
    ra, rb = _round_ids(round_a), _round_ids(round_b)
    if len(ra) != 1 or len(rb) != 1:
        return "Give exactly one round for round_a and one for round_b, e.g. 2024-10 and 2025-10."
    a, b = ra[0], rb[0]
    if breakdown not in ("national", "region", "head_sex"):
        return "breakdown must be national, region or head_sex."
    t = _table("indicators.csv")
    t = t[(t["indicator"] == indicator) & (t["breakdown"] == breakdown)]
    x = t[t["round_id"] == a].set_index("group")
    y = t[t["round_id"] == b].set_index("group")
    if x.empty or y.empty:
        return f"No data for {indicator} in {a if x.empty else b}."
    out = pd.DataFrame({"value_a": x["value"], "value_b": y["value"], "change": y["value"] - x["value"],
                        "n_a": x["n"], "n_b": y["n"], "weighted_a": x["weighted"], "weighted_b": y["weighted"]})
    out = out.reset_index().sort_values("change", ascending=False)
    season_note = "" if a[-2:] == b[-2:] else " Note: different seasons (February lean-season vs October harvest)."
    return f"# {indicator}: {a} -> {b}.{season_note}\n" + _csv(out)


@beta_tool
def get_quality_checks(domain: str) -> str:
    """Per-round quality checks for one domain: completeness, invalid or imputed values, and agreement
    of the recomputed indicator with the original analysts' variable (vs_orig_* columns).

    Args:
        domain: core, fcs, rcsi, lcs, hhs, hdds, exp or demo.
    """
    _log("get_quality_checks", domain=domain)
    name = f"qc/qc_{domain.strip().lower()}_by_round.csv"
    if not (DATA / name).exists():
        return "Unknown domain. Use core, fcs, rcsi, lcs, hhs, hdds, exp or demo."
    return _csv(_table(name))


@beta_tool
def get_crosswalk(domain: str, target: str = "", round_id: str = "") -> str:
    """Harmonisation rules: for each target variable and round, the method, the source variable(s) in the
    original SPSS file, and a note (e.g. why a variable is missing in a round).

    Args:
        domain: core, fcs, rcsi, lcs, hhs, hdds, exp or demo.
        target: Optional harmonised variable name, e.g. HHHSex or LCS_FemAnimal.
        round_id: Optional round, e.g. "2024-10" or "Oct 2024".
    """
    _log("get_crosswalk", domain=domain, target=target, round_id=round_id)
    cw = _table("crosswalk.csv")
    cw = cw[cw["domain"] == domain.strip().lower()]
    if target:
        cw = cw[cw["target"].str.lower() == target.strip().lower()]
    if rid := _round_ids(round_id):
        cw = cw[cw["round_id"].isin(rid)]
    if cw.empty:
        return "No rules match. Check the domain, target and round."
    return _csv(cw)


@beta_tool
def search_data_issues(keyword: str = "") -> str:
    """Data issues found during harmonisation (reversed codes, missing weights, skip patterns, ...), with
    the rounds affected, what was found and how it is handled.

    Args:
        keyword: Optional word to filter on, e.g. "weight", "LCS", "sex", "Oct 2024". Empty = all issues.
    """
    _log("search_data_issues", keyword=keyword)
    t = _table("data_issues.csv")
    if keyword:
        hit = t.apply(lambda r: r.astype(str).str.contains(keyword, case=False, regex=False).any(), axis=1)
        t = t[hit]
    return _csv(t) if len(t) else f"No documented issue mentions '{keyword}'."


def build_info() -> dict:
    return json.loads((DATA / "build_info.json").read_text(encoding="utf-8"))


TOOLS = [list_indicators, list_rounds, get_indicator, compare_rounds, get_quality_checks,
         get_crosswalk, search_data_issues]
