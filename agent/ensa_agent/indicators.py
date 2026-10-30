"""Catalogue of the indicators the agent can report.

Each indicator is computed from the merged harmonised household files by
build_agent_data.py; the agent itself only ever sees the aggregated results.

stat:
  share   percentage of households (the function returns 0/1, missing stays missing)
  mean    mean of the values
  median  median of the values
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Callable

import numpy as np
import pandas as pd


@dataclass(frozen=True)
class Indicator:
    id: str
    domain: str
    label: str
    stat: str
    unit: str
    definition: str
    func: Callable[[pd.DataFrame], pd.Series]


def _flag(cond: pd.Series, source: pd.Series) -> pd.Series:
    """0/1 flag that stays missing where the source value is missing."""
    return cond.astype(float).where(source.notna())


def _used(col: str) -> Callable[[pd.DataFrame], pd.Series]:
    # Used = "yes" (30) or "already exhausted" (20); missing where the strategy was not asked in the round.
    def f(d: pd.DataFrame) -> pd.Series:
        used = d[col].isin([20, 30]).astype(float)
        asked = d.groupby("round_id")[col].transform(lambda s: s.notna().any())
        return used.where(asked)
    return f


FCS_GROUPS = {"FCSStap": "cereals & tubers", "FCSPulse": "pulses & nuts", "FCSVeg": "vegetables",
              "FCSFruit": "fruits", "FCSPr": "meat, fish & eggs", "FCSDairy": "milk & dairy",
              "FCSSugar": "sugar", "FCSFat": "oil & fat", "FCSCond": "condiments"}
LCS_STRATEGIES = {
    "LCS_DomAsset": "sold household assets", "LCS_Animals": "sold more animals than usual",
    "LCS_Saving": "spent savings", "LCS_BorrowCash": "borrowed money / food",
    "LCS_CrdtFood": "bought food on credit", "LCS_EduHealth": "reduced health / education spending",
    "LCS_ProdAssets": "sold productive assets", "LCS_EatCrops": "consumed immature crops",
    "LCS_ChildWork": "child labour (<15)", "LCS_OutSchool": "withdrew children from school",
    "LCS_Marriage": "child marriage (<18)", "LCS_ResAsset": "sold house or land",
    "LCS_FemAnimal": "sold last female animals", "LCS_Begged": "begged"}
INCOME_BROAD = {1: "agriculture & livestock", 2: "fishing, hunting, gathering", 3: "trade",
                4: "labour (skilled, daily)", 5: "salary / pension", 6: "transfers, aid, remittances",
                7: "other", 0: "no other source"}

INDICATORS: list[Indicator] = [
    # Food consumption
    Indicator("fcs_mean", "fcs", "Food Consumption Score, mean", "mean", "score 0-112",
              "WFP FCS from 9 food groups (7-day recall), weights 2,3,1,1,4,4,0.5,0.5,0.",
              lambda d: d["FCS"]),
    Indicator("fcs_poor", "fcs", "Poor food consumption (FCS <= 28)", "share", "% of households",
              "FCS group 28/42 (Chad standard): poor = 0-28.",
              lambda d: _flag(d["FCSCat28"] == 1, d["FCSCat28"])),
    Indicator("fcs_borderline", "fcs", "Borderline food consumption (FCS 28.5-42)", "share", "% of households",
              "FCS group 28/42: borderline = 28.5-42.",
              lambda d: _flag(d["FCSCat28"] == 2, d["FCSCat28"])),
    Indicator("fcs_poor_borderline", "fcs", "Poor or borderline food consumption (28/42)", "share", "% of households",
              "Poor + borderline, thresholds 28/42.",
              lambda d: _flag(d["FCSCat28"].isin([1, 2]), d["FCSCat28"])),
    Indicator("fcs_poor_borderline_21", "fcs", "Poor or borderline food consumption (21/35)", "share", "% of households",
              "Poor + borderline, standard WFP thresholds 21/35.",
              lambda d: _flag(d["FCSCat21"].isin([1, 2]), d["FCSCat21"])),
    *[Indicator(f"fcs_days_{k}", "fcs", f"Days eating {v} (past 7 days), mean", "mean", "days 0-7",
                f"Mean number of days in the past 7 days the household ate {v}.",
                (lambda c: (lambda d: d[c]))(k)) for k, v in FCS_GROUPS.items()],
    # Coping
    Indicator("rcsi_mean", "rcsi", "Reduced Coping Strategies Index, mean", "mean", "score 0-56",
              "rCSI = LessQlty + 2xBorrow + MealSize + 3xMealAdult + MealNb (7-day recall).",
              lambda d: d["rCSI"]),
    Indicator("rcsi_phase3", "rcsi", "rCSI Cadre Harmonise phase 3+ (rCSI >= 19)", "share", "% of households",
              "Cadre Harmonise rCSI phases: <=3 phase 1, 4-18 phase 2, >=19 phase 3+.",
              lambda d: _flag(d["rCSI_CH"] == 3, d["rCSI_CH"])),
    Indicator("lcs_stress", "lcs", "Livelihood coping: stress as maximum (comparable)", "share", "% of households",
              "LCS_max_common = 2: 7 strategies asked in every round, fixed severity, coping for food only.",
              lambda d: _flag(d["LCS_max_common"] == 2, d["LCS_max_common"])),
    Indicator("lcs_crisis", "lcs", "Livelihood coping: crisis as maximum (comparable)", "share", "% of households",
              "LCS_max_common = 3 (comparable set, see lcs_stress).",
              lambda d: _flag(d["LCS_max_common"] == 3, d["LCS_max_common"])),
    Indicator("lcs_emergency", "lcs", "Livelihood coping: emergency (comparable)", "share", "% of households",
              "LCS_max_common = 4 (comparable set, see lcs_stress).",
              lambda d: _flag(d["LCS_max_common"] == 4, d["LCS_max_common"])),
    Indicator("lcs_crisis_emergency", "lcs", "Livelihood coping: crisis or emergency (comparable)", "share",
              "% of households", "LCS_max_common >= 3. Use this one for trends across rounds.",
              lambda d: _flag(d["LCS_max_common"] >= 3, d["LCS_max_common"])),
    Indicator("lcs_crisis_emergency_round", "lcs", "Livelihood coping: crisis or emergency (round-specific)", "share",
              "% of households", "LCS_max >= 3: all strategies asked in the round, at that round's severity. "
              "Not comparable across rounds (item set and severities change).",
              lambda d: _flag(d["LCS_max"] >= 3, d["LCS_max"])),
    *[Indicator(f"lcs_used_{k.removeprefix('LCS_')}", "lcs", f"Used strategy: {v}", "share", "% of households",
                f"Household {v} (answer 'yes' or 'already exhausted'); missing in rounds where it was not asked.",
                _used(k)) for k, v in LCS_STRATEGIES.items()],
    # Hunger
    Indicator("hhs_mean", "hhs", "Household Hunger Scale, mean", "mean", "score 0-6",
              "HHS = sum of 3 items (never 0, rarely/sometimes 1, often 2). Collected from Oct 2019.",
              lambda d: d["HHS"]),
    Indicator("hhs_moderate", "hhs", "Moderate hunger (HHS 2-3)", "share", "% of households",
              "WFP HHS category moderate.", lambda d: _flag(d["HHSCat"] == 2, d["HHSCat"])),
    Indicator("hhs_severe", "hhs", "Severe hunger (HHS 4-6)", "share", "% of households",
              "WFP HHS category severe.", lambda d: _flag(d["HHSCat"] == 3, d["HHSCat"])),
    Indicator("hhs_phase3", "hhs", "HHS IPC/CH phase 3+ (HHS >= 2)", "share", "% of households",
              "IPC/CH phase from HHS: 0 -> 1, 1 -> 2, 2-3 -> 3, 4 -> 4, 5-6 -> 5.",
              lambda d: _flag(d["HHS_phase"] >= 3, d["HHS_phase"])),
    # Dietary diversity
    Indicator("hdds_mean", "hdds", "Household Dietary Diversity Score, mean", "mean", "groups 0-12",
              "Number of 12 food groups eaten in the past 24 hours.", lambda d: d["HDDS"]),
    Indicator("hdds_phase3", "hdds", "HDDS Cadre Harmonise phase 3+ (HDDS <= 3)", "share", "% of households",
              "CH phase from HDDS: >=5 -> 1, 4 -> 2, 3 -> 3, 2 -> 4, 0-1 -> 5.",
              lambda d: _flag(d["HDDS_phase"] >= 3, d["HDDS_phase"])),
    # Expenditure
    Indicator("exp_food_median", "exp", "Monthly food expenditure, median", "median", "FCFA per household per month",
              "Analysts' monthly food aggregate (all sources), nominal FCFA. Not available Oct 2024.",
              lambda d: d["exp_food"]),
    Indicator("exp_total_median", "exp", "Monthly total expenditure, median", "median", "FCFA per household per month",
              "Analysts' monthly total (food + non-food), nominal FCFA. Not available Oct 2024.",
              lambda d: d["exp_total"]),
    Indicator("fes_median", "exp", "Food expenditure share, median", "median", "% of total expenditure",
              "FES = 100 x food / total. Level shift from Oct 2023 (new module): compare generation-3 rounds "
              "with each other.", lambda d: d["FES"]),
    Indicator("fes_75plus", "exp", "Food expenditure share >= 75%", "share", "% of households",
              "CARI food expenditure share category 4 (>= 75%).",
              lambda d: _flag(d["FES_cat"] == 4, d["FES_cat"])),
    # Demographics
    Indicator("female_head", "demo", "Female-headed households", "share", "% of households",
              "Sex of the household head = female (codes harmonised per round).",
              lambda d: _flag(d["HHHSex"] == 2, d["HHHSex"])),
    Indicator("head_age_median", "demo", "Age of the household head, median", "median", "years",
              "Head's age; values outside 12-100 set to missing.", lambda d: d["HHHAge"]),
    Indicator("hh_size_mean", "demo", "Household size, mean", "mean", "persons",
              "Household members; values outside 1-50 set to missing.", lambda d: d["HHSize"]),
    Indicator("head_no_school", "demo", "Head with no formal education", "share", "% of households",
              "Head's education = none. Not collected Oct 2018 - Feb 2020.",
              lambda d: _flag(d["HHHEdu"] == 0, d["HHHEdu"])),
    *[Indicator(f"income_{k}", "demo", f"Main income source: {v}", "share", "% of households",
                f"Broad main income source = {v} (comparable in every round).",
                (lambda c: (lambda d: _flag(d["income_main_broad"] == c, d["income_main_broad"])))(k))
      for k, v in INCOME_BROAD.items()],
    # Cross-domain
    Indicator("fcs_pb_and_rcsi3", "cross", "Poor/borderline FCS and rCSI phase 3+", "share", "% of households",
              "FCS 28/42 poor or borderline AND rCSI >= 19.",
              lambda d: _flag(d["FCSCat28"].isin([1, 2]) & (d["rCSI_CH"] == 3),
                              d["FCSCat28"].where(d["rCSI_CH"].notna()))),
]

BY_ID = {i.id: i for i in INDICATORS}
assert len(BY_ID) == len(INDICATORS), "duplicate indicator id"


def weighted_median(x: np.ndarray, w: np.ndarray) -> float:
    ok = ~np.isnan(x) & ~np.isnan(w) & (w > 0)
    if not ok.any():
        return np.nan
    x, w = x[ok], w[ok]
    order = np.argsort(x, kind="mergesort")
    x, cw = x[order], np.cumsum(w[order])
    return float(x[np.searchsorted(cw, cw[-1] / 2)])
