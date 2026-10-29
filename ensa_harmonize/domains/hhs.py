"""Household Hunger Scale domain: 3 occurrence questions and their frequency (past 30 days),
the HHS score (0-6), the WFP category and the IPC / Cadre Harmonise phase."""
import numpy as np
import pandas as pd

from ..engine import to_number
from .common import categorise, compare_scores, weighted_share

NAME = "hhs"
QUESTIONS = ["HHSNoFood", "HHSBedHung", "HHSNotEat"]
CAT_LABELS = {1: "Little or no hunger", 2: "Moderate hunger", 3: "Severe hunger"}
PHASE_LABELS = {1: "Phase 1", 2: "Phase 2", 3: "Phase 3", 4: "Phase 4", 5: "Phase 5"}
FREQ_LABELS = {0: "Did not occur", 1: "Rarely (1-2 times)", 2: "Sometimes (3-10 times)", 3: "Often (> 10 times)"}

LABELS = {
    "HHSNoFood": "No food of any kind in the household because of lack of resources (past 30 days)",
    "HHSNoFood_FR": "How often: no food in the household",
    "HHSBedHung": "Any member went to sleep hungry because there was not enough food (past 30 days)",
    "HHSBedHung_FR": "How often: went to sleep hungry",
    "HHSNotEat": "Any member went a whole day and night without eating (past 30 days)",
    "HHSNotEat_FR": "How often: whole day and night without eating",
    "hhs_n_missing": "Number of the 3 questions that cannot be scored (missing occurrence or frequency)",
    "hhs_inconsistent": "Number of questions with occurrence and frequency in contradiction",
    "hhs_code_exception": "Occurrence code accepted as 'yes' by a round-specific exception (settings.toml)",
    "HHS": "Household Hunger Scale score (0-6, recomputed)",
    "HHSCat": "HHS category (WFP)",
    "HHS_phase": "HHS phase (IPC / Cadre Harmonise)",
    "orig_HHS": "HHS score as pre-computed in the source file (QC only)",
    "orig_HHS_phase": "HHS phase as pre-computed in the source file (QC only)",
}
VALUE_LABELS = {**{q: {0: "No", 1: "Yes"} for q in QUESTIONS},
                **{f"{q}_FR": FREQ_LABELS for q in QUESTIONS},
                "HHSCat": CAT_LABELS, "HHS_phase": PHASE_LABELS, "orig_HHS_phase": PHASE_LABELS}


def derive(t: pd.DataFrame, rnd: pd.Series, cfg) -> pd.DataFrame:
    rid = rnd.name
    s = cfg.settings["hhs"]
    yes_codes = set(s["yes_codes"]) | set(s.get("extra_yes_codes", {}).get(rid, []))
    freq_score = {float(k): v for k, v in s["frequency_score"].items()}
    out = pd.DataFrame(index=t.index)
    item_scores, missing, inconsistent = [], 0, 0
    exception = pd.Series(False, index=t.index)
    for q in QUESTIONS:
        occ_raw = to_number(t[q])
        freq_raw = to_number(t[f"{q}_FR"])
        known = {0.0} | {float(c) for c in yes_codes}
        unknown = sorted(set(occ_raw.dropna().unique()) - known)
        if unknown:
            raise ValueError(f"Round {rid}: {q} has codes {unknown}; declare them in settings.toml [hhs]")
        occ = occ_raw.map(lambda v: np.nan if pd.isna(v) else (1.0 if v in yes_codes else 0.0))
        exception |= occ_raw.isin([c for c in yes_codes if c not in s["yes_codes"]])
        # Frequency is asked only after a "yes"; "no" means it did not occur (0).
        freq = freq_raw.where(occ == 1, np.where(occ == 0, 0.0, np.nan))
        bad = ((occ == 1) & ~freq_raw.isin(list(freq_score))) | ((occ == 0) & freq_raw.gt(0))
        score = np.where(occ == 0, 0.0, freq.map(freq_score))
        score = pd.Series(score, index=t.index).where(occ.notna() & ~bad)
        out[q] = occ
        out[f"{q}_FR"] = freq.where(~bad)
        item_scores.append(score)
        missing = missing + score.isna().astype(int)
        inconsistent = inconsistent + bad.astype(int)
    scores = pd.concat(item_scores, axis=1)
    out["hhs_n_missing"] = missing
    out["hhs_inconsistent"] = inconsistent
    out["hhs_code_exception"] = exception.astype(int)
    out["HHS"] = scores.sum(axis=1, min_count=3).where(scores.notna().all(axis=1))
    out["HHSCat"] = categorise(out["HHS"], s["category_bounds"])
    phase = dict(enumerate(s["phase_by_score"]))
    out["HHS_phase"] = out["HHS"].map(phase)
    out["orig_HHS"] = to_number(t["orig_HHS"])
    out["orig_HHS_phase"] = to_number(t["orig_HHS_phase"])
    return out


def qc(df: pd.DataFrame, core: pd.DataFrame, cfg) -> pd.DataFrame:
    d = df.merge(core[["hh_id", "weight"]], on="hh_id", how="left")
    rows = []
    for rid, g in d.groupby("round_id", sort=False):
        ok = g["HHS"].notna()
        ph = g[["HHS_phase", "orig_HHS_phase"]].dropna()
        rows.append({
            "round_id": rid,
            "households": len(g),
            "collected": bool(g[QUESTIONS].notna().any().any()),
            "hhs_complete_pct": round(100 * ok.mean(), 2),
            "items_inconsistent": int(g["hhs_inconsistent"].sum()),
            "code_exceptions": int(g["hhs_code_exception"].sum()),
            "hhs_mean": round(g["HHS"].mean(), 3),
            "moderate_pct_w": weighted_share(g["HHSCat"] == 2, g["weight"], ok),
            "severe_pct_w": weighted_share(g["HHSCat"] == 3, g["weight"], ok),
            "phase3plus_pct_w": weighted_share(g["HHS_phase"] >= 3, g["weight"], ok),
            "phase3plus_pct_unw": round(100 * (g["HHS_phase"] >= 3)[ok].mean(), 2) if ok.any() else np.nan,
            **{f"vs_orig_{k}": v for k, v in compare_scores(g["HHS"], g["orig_HHS"], tol=0).items()},
            "vs_orig_phase_n": len(ph),
            "vs_orig_phase_agree_pct": round(100 * (ph["HHS_phase"] == ph["orig_HHS_phase"]).mean(), 2) if len(ph) else np.nan,
        })
    return pd.DataFrame(rows)
