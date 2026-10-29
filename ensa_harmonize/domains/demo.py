"""Demographics domain: household head (sex, age, education, literacy, marital status), household size,
main income source and population group. Categorical codes are harmonised per round with
config/demo_codes.csv, because code lists differ (and the sex coding flips) between questionnaires."""
import numpy as np
import pandas as pd

from ..engine import to_number
from .common import weighted_share

NAME = "demo"
CATEGORICAL = ["HHHSex", "HHHEdu", "HHHMarital", "income_main", "pop_group"]
SEX_LABELS = {1: "Male", 2: "Female"}
EDU_LABELS = {0: "No formal education", 1: "Primary", 2: "Secondary", 3: "Higher", 4: "Non-formal education"}
MARITAL_LABELS = {1: "Married, monogamous", 2: "Married, polygamous", 3: "Married (type not asked)", 4: "Widowed",
                  5: "Divorced / separated", 6: "Single", 7: "Cohabiting / engaged", 9: "Other"}
INCOME_LABELS = {0: "No other source", 1: "Crops / market gardening", 2: "Livestock",
                 3: "Fishing, hunting, gathering", 4: "Trade", 5: "Crafts / skilled work", 6: "Daily / casual labour",
                 7: "Salary / pension", 8: "Transfers, aid, remittances", 9: "Other",
                 10: "Crops and livestock (not separable)"}
# Broad income categories comparable in every round (Oct 2025 does not separate crops from livestock).
INCOME_BROAD = {0: 0, 1: 1, 2: 1, 10: 1, 3: 2, 4: 3, 5: 4, 6: 4, 7: 5, 8: 6, 9: 7}
INCOME_BROAD_LABELS = {0: "No other source", 1: "Agriculture and livestock", 2: "Fishing, hunting, gathering",
                       3: "Trade", 4: "Labour (skilled, daily, casual)", 5: "Salary / pension",
                       6: "Transfers, aid, remittances", 7: "Other"}
POP_LABELS = {1: "Local population", 2: "Host population", 3: "Refugees (earlier arrivals)",
              4: "Refugees (new arrivals)", 5: "Refugees (arrival not recorded)", 6: "Returnees",
              7: "Internally displaced"}

LABELS = {
    "HHHSex": "Sex of household head", "HHHAge": "Age of household head (years)",
    "HHHEdu": "Education of household head", "HHHLiterate": "Household head can read and write (where asked)",
    "edu_imputed": "Education set to 'no formal education' because the head is not literate (level not asked)",
    "HHHMarital": "Marital status of household head", "HHSize": "Household size (members)",
    "income_main": "Main income source (detailed)", "income_main_broad": "Main income source (broad, comparable)",
    "pop_group": "Population group (where recorded)",
    "demo_out_of_range": "Number of values set to missing because out of range (age, household size)",
}
VALUE_LABELS = {"HHHSex": SEX_LABELS, "HHHEdu": EDU_LABELS, "HHHMarital": MARITAL_LABELS,
                "income_main": INCOME_LABELS, "income_main_broad": INCOME_BROAD_LABELS, "pop_group": POP_LABELS,
                "HHHLiterate": {0: "No", 1: "Yes"}, "edu_imputed": {0: "No", 1: "Yes"}}


def derive(t: pd.DataFrame, rnd: pd.Series, cfg) -> pd.DataFrame:
    rid = rnd.name
    s = cfg.settings["demo"]
    codes = cfg.table("demo_codes")
    codes = codes[codes["round_id"] == rid]
    out = pd.DataFrame(index=t.index)
    for var in CATEGORICAL:
        raw = to_number(t[var])
        # An empty value declares a known code as "not recorded" (missing).
        mapping = {float(c): (float(v) if v != "" else np.nan)
                   for c, v in codes.loc[codes["variable"] == var, ["code", "value"]].itertuples(index=False)}
        if raw.notna().any() and not mapping:
            raise ValueError(f"Round {rid}: no codes for {var} in config/demo_codes.csv")
        unknown = sorted(set(raw.dropna().unique()) - set(mapping))
        if unknown:
            raise ValueError(f"Round {rid}: {var} has codes {unknown} missing from config/demo_codes.csv")
        out[var] = raw.map(mapping)

    literate = to_number(t["edu_filter"])
    out["HHHLiterate"] = literate
    imputed = out["HHHEdu"].isna() & literate.eq(0) & bool(s.get("edu_impute_from_literacy", True))
    out.loc[imputed, "HHHEdu"] = 0
    out["edu_imputed"] = imputed.astype(int)

    age, size = to_number(t["HHHAge"]), to_number(t["HHSize"])
    a_lo, a_hi = s["age_range"]
    n_lo, n_hi = s["size_range"]
    bad_age = age.notna() & ((age < a_lo) | (age > a_hi))
    bad_size = size.notna() & ((size < n_lo) | (size > n_hi))
    out["HHHAge"] = age.mask(bad_age)
    out["HHSize"] = size.mask(bad_size)
    out["demo_out_of_range"] = bad_age.astype(int) + bad_size.astype(int)
    out["income_main_broad"] = out["income_main"].map(INCOME_BROAD)
    order = ["HHHSex", "HHHAge", "HHHEdu", "HHHLiterate", "edu_imputed", "HHHMarital", "HHSize",
             "income_main", "income_main_broad", "pop_group", "demo_out_of_range"]
    return out[order]


def qc(df: pd.DataFrame, core: pd.DataFrame, cfg) -> pd.DataFrame:
    d = df.merge(core[["hh_id", "weight"]], on="hh_id", how="left")
    rows = []
    for rid, g in d.groupby("round_id", sort=False):
        rows.append({
            "round_id": rid,
            "households": len(g),
            **{f"{v}_complete_pct": round(100 * g[v].notna().mean(), 1) for v in
               ("HHHSex", "HHHAge", "HHHEdu", "HHHMarital", "HHSize", "income_main", "pop_group")},
            "female_head_pct_w": weighted_share(g["HHHSex"] == 2, g["weight"], g["HHHSex"].notna()),
            "female_head_pct_unw": round(100 * (g["HHHSex"] == 2)[g["HHHSex"].notna()].mean(), 2),
            "age_median": g["HHHAge"].median(),
            "size_mean": round(g["HHSize"].mean(), 2),
            "edu_imputed": int(g["edu_imputed"].sum()),
            "out_of_range": int(g["demo_out_of_range"].sum()),
        })
    return pd.DataFrame(rows)
