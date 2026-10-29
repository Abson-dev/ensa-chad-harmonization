"""Expenditure domain: monthly food, non-food and total household expenditure (nominal FCFA, the
analysts' aggregates), the food expenditure share and its CARI category."""
import numpy as np
import pandas as pd

from ..engine import to_number
from .common import weighted_share

NAME = "exp"
FES_LABELS = {1: "< 50%", 2: "50-65%", 3: "65-75%", 4: ">= 75%"}

LABELS = {
    "exp_food": "Monthly food expenditure, all sources (FCFA, nominal)",
    "exp_nonfood": "Monthly non-food expenditure (FCFA, nominal)",
    "exp_total": "Monthly total expenditure (FCFA, nominal)",
    "exp_nonfood_derived": "Non-food expenditure derived as total - food (not stored in the source)",
    "exp_invalid": "Aggregates set to missing (total <= 0, negative food, or food > total)",
    "exp_outlier": "Total expenditure above the outlier threshold (flag only)",
    "FES": "Food expenditure share (%, recomputed = food / total)",
    "FES_cat": "Food expenditure share category (CARI)",
    "orig_FES": "Food expenditure share as stored in the source file (QC only)",
}
VALUE_LABELS = {"FES_cat": FES_LABELS, "exp_nonfood_derived": {0: "No", 1: "Yes"},
                "exp_invalid": {0: "No", 1: "Yes"}, "exp_outlier": {0: "No", 1: "Yes"}}


def derive(t: pd.DataFrame, rnd: pd.Series, cfg) -> pd.DataFrame:
    s = cfg.settings["exp"]
    food = to_number(t["exp_food"])
    total = to_number(t["exp_total"])
    nonfood_src = to_number(t["exp_nonfood"])
    derived = nonfood_src.isna() & food.notna() & total.notna()
    nonfood = nonfood_src.fillna(total - food)
    invalid = (total <= 0) | (food < 0) | (food > total + 1)
    out = pd.DataFrame(index=t.index)
    out["exp_food"] = food.mask(invalid)
    out["exp_nonfood"] = nonfood.mask(invalid)
    out["exp_total"] = total.mask(invalid)
    out["exp_nonfood_derived"] = derived.astype(int)
    out["exp_invalid"] = invalid.astype(int)
    med = out["exp_total"].median()
    out["exp_outlier"] = (out["exp_total"] > s["outlier_multiple"] * med).astype(int) if pd.notna(med) else 0
    out["FES"] = 100 * out["exp_food"] / out["exp_total"]
    b = s["fes_bounds"]
    fes = out["FES"]
    out["FES_cat"] = pd.Series(np.select([fes < b[0], fes < b[1], fes < b[2]], [1, 2, 3], 4), index=t.index).where(fes.notna())
    out["orig_FES"] = to_number(t["orig_FES"])
    return out


def qc(df: pd.DataFrame, core: pd.DataFrame, cfg) -> pd.DataFrame:
    d = df.merge(core[["hh_id", "weight"]], on="hh_id", how="left")
    rows = []
    for rid, g in d.groupby("round_id", sort=False):
        ok = g["FES"].notna()
        cmp = g[["FES", "orig_FES"]].dropna()
        rows.append({
            "round_id": rid,
            "households": len(g),
            "exp_complete_pct": round(100 * ok.mean(), 2),
            "invalid": int(g["exp_invalid"].sum()),
            "outliers_flagged": int(g["exp_outlier"].sum()),
            "nonfood_derived": bool(g["exp_nonfood_derived"].any()),
            "food_median": g["exp_food"].median(),
            "total_median": g["exp_total"].median(),
            "fes_median": round(g["FES"].median(), 1) if ok.any() else np.nan,
            "fes_75plus_pct_w": weighted_share(g["FES_cat"] == 4, g["weight"], ok),
            "fes_75plus_pct_unw": round(100 * (g["FES_cat"] == 4)[ok].mean(), 2) if ok.any() else np.nan,
            "vs_orig_n": len(cmp),
            "vs_orig_agree_pct": round(100 * ((cmp["FES"] - cmp["orig_FES"]).abs() <= 0.5).mean(), 2) if len(cmp) else np.nan,
        })
    return pd.DataFrame(rows)
