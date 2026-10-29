"""Livelihood coping domain: 14 strategies on the WFP answer scale, and the maximum coping category,
both round-specific (all strategies asked, at that round's severity) and on a common set of
strategies asked in every round (fixed severity), which is the one to use for trends."""
import numpy as np
import pandas as pd

from ..engine import to_number
from .common import weighted_share

NAME = "lcs"
ITEMS = ["LCS_DomAsset", "LCS_Animals", "LCS_Saving", "LCS_BorrowCash", "LCS_CrdtFood", "LCS_EduHealth",
         "LCS_ProdAssets", "LCS_EatCrops", "LCS_ChildWork", "LCS_OutSchool", "LCS_Marriage",
         "LCS_ResAsset", "LCS_FemAnimal", "LCS_Begged"]
SEVERITIES = ["stress", "crisis", "emergency"]
# Max coping category, coded as in the WFP codebook (and the source files' own max variables).
SEVERITY_RANK = {"stress": 2, "crisis": 3, "emergency": 4}
MAX_LABELS = {1: "No strategy", 2: "Stress", 3: "Crisis", 4: "Emergency"}
# Harmonised answers: WFP standard codes.
RESPONSE_CODES = {"no_need": 10, "exhausted": 20, "yes": 30, "not_applicable": 9999}
RESPONSE_LABELS = {10: "No, no need", 20: "No, already exhausted", 30: "Yes", 9999: "Not applicable"}

ITEM_LABELS = {
    "LCS_DomAsset": "Sold household assets (radio, furniture, jewellery...)",
    "LCS_Animals": "Sold more (non-productive) animals than usual",
    "LCS_Saving": "Spent savings",
    "LCS_BorrowCash": "Borrowed money or food",
    "LCS_CrdtFood": "Bought food on credit / borrowed food",
    "LCS_EduHealth": "Reduced essential non-food spending (education, health)",
    "LCS_ProdAssets": "Sold productive assets or means of transport",
    "LCS_EatCrops": "Consumed immature crops",
    "LCS_ChildWork": "Child under 15 worked to bring in income",
    "LCS_OutSchool": "Withdrew children from school",
    "LCS_Marriage": "Girl under 18 married",
    "LCS_ResAsset": "Sold house or land",
    "LCS_FemAnimal": "Sold last female animals",
    "LCS_Begged": "Begged",
}
LABELS = {
    **{k: f"{v} (past 30 days, WFP answer scale)" for k, v in ITEM_LABELS.items()},
    "lcs_n_asked": "Number of strategies asked in this round",
    "lcs_n_answered": "Number of strategies answered by the household",
    "lcs_n_used": "Number of strategies used (yes or already exhausted)",
    "LCS_stress": "Used at least one stress strategy (round-specific severity)",
    "LCS_crisis": "Used at least one crisis strategy (round-specific severity)",
    "LCS_emergency": "Used at least one emergency strategy (round-specific severity)",
    "LCS_max": "Maximum coping category, all strategies asked in the round (round-specific)",
    "LCS_max_common": "Maximum coping category, strategies asked in all rounds, coping for food only (comparable over time)",
    "lcs_food_reason": "Strategies used to buy food (essential-needs module, Oct 2024 onward): 1 yes, 0 no",
    "lcs_not_for_food": "Used strategies, but not to buy food (excluded from LCS_max_common)",
    "orig_LCS": "Maximum coping category as pre-computed in the source file (QC only)",
}
VALUE_LABELS = {**{k: RESPONSE_LABELS for k in ITEMS},
                "LCS_max": MAX_LABELS, "LCS_max_common": MAX_LABELS, "orig_LCS": MAX_LABELS,
                **{f"LCS_{s}": {0: "No", 1: "Yes"} for s in SEVERITIES}}


def derive(t: pd.DataFrame, rnd: pd.Series, cfg) -> pd.DataFrame:
    rid = rnd.name
    s = cfg.settings["lcs"]
    resp = cfg.table("lcs_responses")
    resp = resp[resp["round_id"] == rid]
    code_map = {float(c): r for c, r in zip(resp["code"], resp["response"])}
    sev = cfg.table("lcs_severity")
    sev = sev[sev["round_id"] == rid]
    sev_map = dict(zip(sev["target"], sev["severity"]))
    rules = cfg.rules(NAME, rid)
    asked = [i for i in ITEMS if i in set(rules.loc[rules["method"] != "missing", "target"])]

    # Configuration must cover every strategy asked in the round, and every answer code found.
    if not code_map:
        raise ValueError(f"Round {rid}: no answer codes in config/lcs_responses.csv")
    no_sev = [i for i in asked if i not in sev_map]
    if no_sev:
        raise ValueError(f"Round {rid}: no severity in config/lcs_severity.csv for {no_sev}")

    out = pd.DataFrame(index=t.index)
    used = pd.DataFrame(False, index=t.index, columns=asked)
    for item in ITEMS:
        if item not in asked:
            out[item] = np.nan
            continue
        raw = to_number(t[item])
        unknown = sorted(set(raw.dropna().unique()) - set(code_map))
        if unknown:
            raise ValueError(f"Round {rid}: {item} has answer codes {unknown} missing from config/lcs_responses.csv")
        r = raw.map(code_map)
        out[item] = r.map(RESPONSE_CODES)
        # Skipped questions (missing) count as not used, as in the WFP method.
        used[item] = r.isin(s["used_responses"])

    answered = out[asked].notna()
    out["lcs_n_asked"] = len(asked)
    out["lcs_n_answered"] = answered.sum(axis=1)
    out["lcs_n_used"] = used.sum(axis=1)
    any_answer = answered.any(axis=1)
    for level in SEVERITIES:
        cols = [i for i in asked if sev_map[i] == level]
        flag = used[cols].any(axis=1).astype(float) if cols else pd.Series(np.nan, index=t.index)
        out[f"LCS_{level}"] = flag.where(any_answer)
    out["LCS_max"] = max_category(used, {i: sev_map[i] for i in asked}).where(any_answer)

    common = s["common_items"]
    not_asked = [i for i in common if i not in asked]
    if not_asked:
        raise ValueError(f"Round {rid}: common LCS strategies {not_asked} are not available")
    # Essential-needs module (Oct 2024 onward): keep only coping used to buy food, as in earlier rounds.
    # A missing reason is kept (counted), the conservative choice.
    reason = to_number(t["lcs_food_reason"])
    not_food = reason.eq(0) if s.get("food_reason_filter", True) else pd.Series(False, index=t.index)
    out["lcs_food_reason"] = reason
    out["lcs_not_for_food"] = (not_food & used.any(axis=1)).astype(int)
    used_food = used[list(common)].mul(~not_food, axis=0).astype(bool)
    out["LCS_max_common"] = max_category(used_food, common).where(answered[list(common)].any(axis=1))
    out["orig_LCS"] = to_number(t["orig_LCS"])
    return out


def max_category(used: pd.DataFrame, severity: dict) -> pd.Series:
    """1 = no strategy used, 2 = stress, 3 = crisis, 4 = emergency (highest severity used)."""
    if used.shape[1] == 0:
        return pd.Series(np.nan, index=used.index)
    ranks = np.array([SEVERITY_RANK[severity[c]] for c in used.columns])
    return pd.Series(np.where(used.to_numpy(), ranks, 1).max(axis=1).astype(float), index=used.index)


def qc(df: pd.DataFrame, core: pd.DataFrame, cfg) -> pd.DataFrame:
    d = df.merge(core[["hh_id", "weight"]], on="hh_id", how="left")
    rows = []
    for rid, g in d.groupby("round_id", sort=False):
        ok = g["LCS_max"].notna()
        cmp = g[["LCS_max", "orig_LCS"]].dropna()
        # Diagnostic: the original may count only "yes" (not "already exhausted") as used.
        yes_only = _max_yes_only(g, cfg, rid).loc[cmp.index]
        rows.append({
            "round_id": rid,
            "households": len(g),
            "strategies_asked": int(g["lcs_n_asked"].iloc[0]),
            "lcs_complete_pct": round(100 * ok.mean(), 2),
            **{f"max_{lab.lower().replace(' ', '_')}_pct_w": weighted_share(g["LCS_max"] == k, g["weight"], ok)
               for k, lab in MAX_LABELS.items()},
            "common_crisis_emergency_pct_w": weighted_share(g["LCS_max_common"] >= 3, g["weight"], g["LCS_max_common"].notna()),
            "common_crisis_emergency_pct_unw": round(100 * (g["LCS_max_common"] >= 3)[g["LCS_max_common"].notna()].mean(), 2),
            "not_for_food_excluded": int(g["lcs_not_for_food"].sum()),
            "vs_orig_n": len(cmp),
            "vs_orig_agree_pct": round(100 * (cmp["LCS_max"] == cmp["orig_LCS"]).mean(), 2) if len(cmp) else np.nan,
            "vs_orig_agree_if_yes_only_pct": round(100 * (yes_only == cmp["orig_LCS"]).mean(), 2) if len(cmp) else np.nan,
        })
    return pd.DataFrame(rows)


def _max_yes_only(g: pd.DataFrame, cfg, rid: str) -> pd.Series:
    sev = cfg.table("lcs_severity")
    sev = sev[sev["round_id"] == rid]
    sev_map = dict(zip(sev["target"], sev["severity"]))
    asked = [i for i in ITEMS if i in sev_map]
    return max_category(g[asked] == RESPONSE_CODES["yes"], sev_map)
