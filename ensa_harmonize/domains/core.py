"""Core domain: household keys, interview date, geography and sampling weight.

Every other domain file carries round_id + hh_id and joins to this one.
"""
import numpy as np
import pandas as pd

from ..engine import spss_to_datetime, to_number

NAME = "core"
KEYS_FIRST = ["round_id", "hh_id"]

LABELS = {
    "round_id": "Survey round (YYYY-MM)",
    "hh_id": "Household ID, unique across rounds (round_id + KoBo uuid)",
    "year": "Survey year",
    "season": "Survey season (Feb / Oct)",
    "generation": "Questionnaire generation (1 French codebook, 2 hybrid, 3 WFP codebook)",
    "uuid": "KoBo submission uuid (unique within round only)",
    "svy_date": "Interview date",
    "date_flag": "Interview date check",
    "admin1": "Region (standardised name)",
    "admin1_raw": "Region as recorded in the source file",
    "admin2": "Department (source label, whitespace-cleaned)",
    "admin3": "Sub-prefecture (source label, whitespace-cleaned)",
    "weight": "Sampling weight as provided in the source file",
    "weight_norm": "Weight rescaled to mean 1 within the round",
    "weight_flag": "Weight status",
}
VALUE_LABELS = {}


def derive(t: pd.DataFrame, rnd: pd.Series, cfg) -> pd.DataFrame:
    out = pd.DataFrame(index=t.index)
    out["year"] = int(rnd["year"])
    out["season"] = rnd["season"]
    out["generation"] = int(rnd["generation"])
    out["uuid"] = t["uuid"].astype("string")

    # Date: convert from SPSS seconds; flag (never drop) values outside the fieldwork window.
    tol = pd.Timedelta(days=cfg.settings["core"]["date_tolerance_days"])
    d = spss_to_datetime(t["svy_date"])
    lo, hi = pd.Timestamp(rnd["fieldwork_start"]) - tol, pd.Timestamp(rnd["fieldwork_end"]) + tol
    out["svy_date"] = d
    out["date_flag"] = np.select([d.isna(), (d < lo) | (d > hi)], ["missing", "outside_window"], "ok")

    # Region: explicit lookup; an unknown spelling stops the run so it gets added to admin1_names.csv.
    raw = t["admin1"]
    unknown = sorted(set(raw.dropna()) - set(cfg.admin1))
    if unknown:
        raise ValueError(f"Round {rnd.name}: admin1 spellings missing from config/admin1_names.csv: {unknown}")
    out["admin1"] = raw.map(cfg.admin1).astype("string")
    out["admin1_raw"] = raw
    for a in ("admin2", "admin3"):
        out[a] = t[a].str.replace(r"\s+", " ", regex=True).str.strip()

    # Weight: kept as provided; normalised copy for pooling across rounds.
    w = to_number(t["weight"])
    out["weight"] = w
    valid = w > 0
    out["weight_norm"] = np.where(valid, w / w[valid].mean(), np.nan) if valid.any() else np.nan
    rule_missing = t["weight"].isna().all()
    out["weight_flag"] = np.select([w.isna() & rule_missing, w.isna(), w == 0],
                                   ["no_weight_in_round", "missing", "zero"], "ok")
    return out


def qc(df: pd.DataFrame, core: pd.DataFrame, cfg) -> pd.DataFrame:
    g = df.groupby("round_id", sort=False)
    return pd.DataFrame({
        "households": g.size(),
        "hh_id_unique": g["hh_id"].agg(lambda s: s.is_unique),
        "regions": g["admin1"].nunique(),
        "admin1_missing": g["admin1"].agg(lambda s: int(s.isna().sum())),
        "date_outside_window": g["date_flag"].agg(lambda s: int((s == "outside_window").sum())),
        "date_missing": g["date_flag"].agg(lambda s: int((s == "missing").sum())),
        "weight_status": g["weight_flag"].agg(lambda s: "no weight" if (s == "no_weight_in_round").all()
                                              else f"ok={int((s == 'ok').sum())}, zero={int((s == 'zero').sum())}, missing={int((s == 'missing').sum())}"),
        "weight_sum": g["weight"].sum(min_count=1).round(1),
    }).reset_index()
