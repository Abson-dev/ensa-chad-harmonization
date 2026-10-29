"""Household Dietary Diversity domain: 12 food groups eaten in the past 24 hours, the HDDS (0-12)
and its Cadre Harmonise phase."""
import numpy as np
import pandas as pd

from ..engine import to_number
from .common import compare_scores, item_matrix, weighted_share

NAME = "hdds"
ITEMS = ["HDDSStapCer", "HDDSStapRoot", "HDDSPulse", "HDDSVeg", "HDDSFruit", "HDDSPrMeat", "HDDSPrEgg",
         "HDDSPrFish", "HDDSDairy", "HDDSSugar", "HDDSFat", "HDDSCond"]
GROUP_LABELS = {
    "HDDSStapCer": "Cereals", "HDDSStapRoot": "Roots and tubers", "HDDSPulse": "Pulses, nuts and seeds",
    "HDDSVeg": "Vegetables", "HDDSFruit": "Fruits", "HDDSPrMeat": "Meat and offal", "HDDSPrEgg": "Eggs",
    "HDDSPrFish": "Fish and seafood", "HDDSDairy": "Milk and dairy", "HDDSSugar": "Sugar and sweets",
    "HDDSFat": "Oils and fats", "HDDSCond": "Condiments, spices, beverages",
}
PHASE_LABELS = {1: "Phase 1", 2: "Phase 2", 3: "Phase 3", 4: "Phase 4", 5: "Phase 5"}

LABELS = {
    **{k: f"{v} eaten in the past 24 hours" for k, v in GROUP_LABELS.items()},
    "hdds_n_imputed": "Food groups skipped and set to 'not eaten' because the FCS 7-day answer was 0",
    "hdds_n_missing": "Food groups still missing",
    "hdds_n_invalid": "Food groups set to missing because the answer was not 0/1",
    "HDDS": "Household Dietary Diversity Score (number of 12 groups eaten in the past 24 hours, recomputed)",
    "HDDS_phase": "HDDS phase (Cadre Harmonise)",
    "orig_HDDS": "HDDS as pre-computed in the source file (QC only)",
    "orig_HDDS_phase": "HDDS phase as pre-computed in the source file (QC only)",
}
VALUE_LABELS = {**{k: {0: "No", 1: "Yes"} for k in ITEMS},
                "HDDS_phase": PHASE_LABELS, "orig_HDDS_phase": PHASE_LABELS}


def derive(t: pd.DataFrame, rnd: pd.Series, cfg) -> pd.DataFrame:
    s = cfg.settings["hdds"]
    t = t.copy()
    imputed = pd.Series(0, index=t.index)
    if s.get("impute_skip_when_gate_zero", True):
        for item in ITEMS:
            gate = to_number(t[f"gate_{item}"])
            fill = to_number(t[item]).isna() & gate.eq(0)
            t.loc[fill, item] = 0
            imputed += fill.astype(int)
    items, n_missing, n_invalid = item_matrix(t, ITEMS, lo=0, hi=1)
    out = items.copy()
    out["hdds_n_imputed"] = imputed
    out["hdds_n_missing"] = n_missing
    out["hdds_n_invalid"] = n_invalid
    out["HDDS"] = items.sum(axis=1, min_count=len(ITEMS)).where(items.notna().all(axis=1))
    out["HDDS_phase"] = out["HDDS"].map(dict(enumerate(s["phase_by_score"])))
    out["orig_HDDS"] = to_number(t["orig_HDDS"])
    out["orig_HDDS_phase"] = to_number(t["orig_HDDS_phase"])
    return out


def qc(df: pd.DataFrame, core: pd.DataFrame, cfg) -> pd.DataFrame:
    d = df.merge(core[["hh_id", "weight"]], on="hh_id", how="left")
    rows = []
    for rid, g in d.groupby("round_id", sort=False):
        ok = g["HDDS"].notna()
        ph = g[["HDDS_phase", "orig_HDDS_phase"]].dropna()
        rows.append({
            "round_id": rid,
            "households": len(g),
            "hdds_complete_pct": round(100 * ok.mean(), 2),
            "groups_imputed": int(g["hdds_n_imputed"].sum()),
            "groups_invalid": int(g["hdds_n_invalid"].sum()),
            "hdds_mean": round(g["HDDS"].mean(), 2),
            "phase3plus_pct_w": weighted_share(g["HDDS_phase"] >= 3, g["weight"], ok),
            "phase3plus_pct_unw": round(100 * (g["HDDS_phase"] >= 3)[ok].mean(), 2) if ok.any() else np.nan,
            **{f"vs_orig_{k}": v for k, v in compare_scores(g["HDDS"], g["orig_HDDS"], tol=0).items()},
            "vs_orig_phase_n": len(ph),
            "vs_orig_phase_agree_pct": round(100 * (ph["HDDS_phase"] == ph["orig_HDDS_phase"]).mean(), 2) if len(ph) else np.nan,
        })
    return pd.DataFrame(rows)
