"""Coping domain: the 5 rCSI strategies, the recomputed rCSI and its Cadre Harmonise phase."""
import numpy as np
import pandas as pd

from ..engine import to_number
from .common import categorise, item_matrix, weighted_share, compare_scores

NAME = "rcsi"
ITEMS = ["rCSILessQlty", "rCSIBorrow", "rCSIMealSize", "rCSIMealAdult", "rCSIMealNb"]
PHASE_LABELS = {1: "Phase 1 (0-3)", 2: "Phase 2 (4-18)", 3: "Phase 3+ (19+)"}

LABELS = {
    "rCSILessQlty": "Days (0-7) relied on less preferred / less expensive food",
    "rCSIBorrow": "Days (0-7) borrowed food or relied on help from relatives / friends",
    "rCSIMealSize": "Days (0-7) limited portion size at mealtimes",
    "rCSIMealAdult": "Days (0-7) restricted adult consumption so children could eat",
    "rCSIMealNb": "Days (0-7) reduced number of meals eaten per day",
    "rcsi_mealadult_imputed": "rCSIMealAdult set to 0 because skipped and no children 0-17 in household",
    "rcsi_n_missing": "Number of rCSI items missing (after imputation)",
    "rcsi_n_invalid": "Number of rCSI items set to missing because outside 0-7",
    "rCSI": "Reduced Coping Strategies Index (recomputed, 0-56)",
    "rCSI_CH": "rCSI Cadre Harmonise phase",
    "orig_rCSI": "rCSI as pre-computed in the source file (QC only)",
}
VALUE_LABELS = {"rCSI_CH": PHASE_LABELS, "rcsi_mealadult_imputed": {0: "No", 1: "Yes"}}


def derive(t: pd.DataFrame, rnd: pd.Series, cfg) -> pd.DataFrame:
    s = cfg.settings["rcsi"]
    t = t.copy()
    # Skip pattern (Oct 2024): the "restrict adults for children" question is not asked when the
    # household has no children, which is equivalent to 0 days.
    n_children = to_number(t["n_children"])
    adult = to_number(t["rCSIMealAdult"])
    impute = adult.isna() & n_children.eq(0)
    t.loc[impute, "rCSIMealAdult"] = 0
    items, n_missing, n_invalid = item_matrix(t, ITEMS, lo=0, hi=7)
    out = items.copy()
    out["rcsi_mealadult_imputed"] = impute.astype(int)
    out["rcsi_n_missing"] = n_missing
    out["rcsi_n_invalid"] = n_invalid
    out["rCSI"] = rcsi_score(items, s["weights"])
    out["rCSI_CH"] = categorise(out["rCSI"], s["ch_thresholds"])
    out["orig_rCSI"] = to_number(t["orig_rCSI"])
    return out


def rcsi_score(items: pd.DataFrame, weights: dict) -> pd.Series:
    """Weighted sum of strategy days; missing if any of the 5 strategies is missing."""
    w = pd.Series(weights)[ITEMS]
    score = items[ITEMS].mul(w, axis=1).sum(axis=1, min_count=len(ITEMS))
    return score.where(items[ITEMS].notna().all(axis=1))


def qc(df: pd.DataFrame, core: pd.DataFrame, cfg) -> pd.DataFrame:
    d = df.merge(core[["hh_id", "weight"]], on="hh_id", how="left")
    rows = []
    for rid, g in d.groupby("round_id", sort=False):
        ok = g["rCSI"].notna()
        rows.append({
            "round_id": rid,
            "households": len(g),
            "rcsi_complete_pct": round(100 * ok.mean(), 2),
            "items_invalid": int(g["rcsi_n_invalid"].sum()),
            "mealadult_imputed": int(g["rcsi_mealadult_imputed"].sum()),
            "rcsi_mean": round(g["rCSI"].mean(), 2),
            "rcsi_mean_weighted": round(np.average(g.loc[ok, "rCSI"], weights=g.loc[ok, "weight"])
                                        if g.loc[ok, "weight"].gt(0).any() else np.nan, 2),
            "phase1_pct_w": weighted_share(g["rCSI_CH"] == 1, g["weight"], g["rCSI_CH"].notna()),
            "phase2_pct_w": weighted_share(g["rCSI_CH"] == 2, g["weight"], g["rCSI_CH"].notna()),
            "phase3plus_pct_w": weighted_share(g["rCSI_CH"] == 3, g["weight"], g["rCSI_CH"].notna()),
            **{f"vs_orig_{k}": v for k, v in compare_scores(g["rCSI"], g["orig_rCSI"], tol=0.5).items()},
        })
    return pd.DataFrame(rows)
