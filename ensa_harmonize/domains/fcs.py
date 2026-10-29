"""Food consumption domain: the 9 FCS food groups, the recomputed FCS and its categories."""
import numpy as np
import pandas as pd

from ..engine import to_number
from .common import categorise, item_matrix, weighted_share, compare_scores

NAME = "fcs"
ITEMS = ["FCSStap", "FCSPulse", "FCSVeg", "FCSFruit", "FCSPr", "FCSDairy", "FCSSugar", "FCSFat", "FCSCond"]
CAT_LABELS = {1: "Poor", 2: "Borderline", 3: "Acceptable"}

LABELS = {
    "FCSStap": "Days (0-7) eating cereals, grains, roots and tubers",
    "FCSPulse": "Days (0-7) eating pulses / nuts",
    "FCSVeg": "Days (0-7) eating vegetables / leaves",
    "FCSFruit": "Days (0-7) eating fruits",
    "FCSPr": "Days (0-7) eating meat, fish, eggs",
    "FCSDairy": "Days (0-7) eating milk / dairy",
    "FCSSugar": "Days (0-7) eating sugar / sweets",
    "FCSFat": "Days (0-7) eating oil / fat / butter",
    "FCSCond": "Days (0-7) eating condiments / spices",
    "fcs_n_missing": "Number of FCS items missing",
    "fcs_n_invalid": "Number of FCS items set to missing because outside 0-7",
    "FCS": "Food Consumption Score (recomputed, 0-112)",
    "FCSCat21": "FCS group, thresholds 21/35",
    "FCSCat28": "FCS group, thresholds 28/42 (Chad standard)",
    "orig_FCS": "FCS as pre-computed in the source file (QC only)",
    "orig_FCSCat28": "FCS group 28/42 as pre-computed in the source file (QC only)",
}
VALUE_LABELS = {"FCSCat21": CAT_LABELS, "FCSCat28": CAT_LABELS, "orig_FCSCat28": CAT_LABELS}


def derive(t: pd.DataFrame, rnd: pd.Series, cfg) -> pd.DataFrame:
    s = cfg.settings["fcs"]
    items, n_missing, n_invalid = item_matrix(t, ITEMS, lo=0, hi=7)
    out = items.copy()
    out["fcs_n_missing"] = n_missing
    out["fcs_n_invalid"] = n_invalid
    out["FCS"] = fcs_score(items, s["weights"])
    out["FCSCat21"] = categorise(out["FCS"], s["thresholds_21"])
    out["FCSCat28"] = categorise(out["FCS"], s["thresholds_28"])
    out["orig_FCS"] = to_number(t["orig_FCS"])
    out["orig_FCSCat28"] = to_number(t["orig_FCSCat28"])
    return out


def fcs_score(items: pd.DataFrame, weights: dict) -> pd.Series:
    """Weighted sum of food-group days; missing if any of the 9 groups is missing."""
    w = pd.Series(weights)[ITEMS]
    score = items[ITEMS].mul(w, axis=1).sum(axis=1, min_count=len(ITEMS))
    return score.where(items[ITEMS].notna().all(axis=1))


def qc(df: pd.DataFrame, core: pd.DataFrame, cfg) -> pd.DataFrame:
    d = df.merge(core[["hh_id", "weight"]], on="hh_id", how="left")
    rows = []
    for rid, g in d.groupby("round_id", sort=False):
        cmp = compare_scores(g["FCS"], g["orig_FCS"], tol=0.5)
        cat = g[["FCSCat28", "orig_FCSCat28"]].dropna()
        rows.append({
            "round_id": rid,
            "households": len(g),
            "fcs_complete_pct": round(100 * g["FCS"].notna().mean(), 2),
            "items_invalid": int(g["fcs_n_invalid"].sum()),
            "fcs_mean": round(g["FCS"].mean(), 2),
            "fcs_mean_weighted": round(np.average(g["FCS"].dropna(), weights=g.loc[g["FCS"].notna(), "weight"])
                                       if g.loc[g["FCS"].notna(), "weight"].gt(0).any() else np.nan, 2),
            "poor_28_pct_w": weighted_share(g["FCSCat28"] == 1, g["weight"], g["FCSCat28"].notna()),
            "borderline_28_pct_w": weighted_share(g["FCSCat28"] == 2, g["weight"], g["FCSCat28"].notna()),
            "acceptable_28_pct_w": weighted_share(g["FCSCat28"] == 3, g["weight"], g["FCSCat28"].notna()),
            **{f"vs_orig_{k}": v for k, v in cmp.items()},
            "vs_orig_cat28_agree_pct": round(100 * (cat["FCSCat28"] == cat["orig_FCSCat28"]).mean(), 2) if len(cat) else np.nan,
            # Some rounds code the original groups in reverse (1 = Acceptable ... 3 = Poor).
            "vs_orig_cat28_agree_if_reversed_pct": round(100 * (cat["FCSCat28"] == 4 - cat["orig_FCSCat28"]).mean(), 2) if len(cat) else np.nan,
        })
    return pd.DataFrame(rows)
