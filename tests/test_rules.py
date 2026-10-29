"""Unit tests for the harmonisation rules. Run from harmonization/:  python -m pytest -q"""
import sys
from pathlib import Path

import numpy as np
import pandas as pd
import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from ensa_harmonize import config  # noqa: E402
from ensa_harmonize.domains import fcs, hdds, hhs, lcs, rcsi  # noqa: E402
from ensa_harmonize.engine import any_source, max_or_last  # noqa: E402
from ensa_harmonize.domains.common import categorise, item_matrix  # noqa: E402
from ensa_harmonize.engine import spss_to_datetime, sum_sources, to_number  # noqa: E402


@pytest.fixture(scope="module")
def cfg():
    return config.load(ROOT)


def test_config_is_complete(cfg):
    # validate() runs inside load(); also check every round has a rule for every target.
    cw = cfg.crosswalk
    assert cw.groupby(["domain", "target"]).size().eq(len(cfg.rounds)).all()


def test_input_files_exist(cfg):
    missing = [r for r in cfg.rounds.index if not cfg.round_path(r).exists()]
    assert not missing, missing


def test_fcs_score_max_and_known_value(cfg):
    w = cfg.settings["fcs"]["weights"]
    full = pd.DataFrame([[7] * 9], columns=fcs.ITEMS)
    assert fcs.fcs_score(full, w).iloc[0] == 112
    row = pd.DataFrame([[7, 2, 3, 0, 1, 0, 4, 7, 7]], columns=fcs.ITEMS)
    # 2*7 + 3*2 + 3 + 0 + 4*1 + 0 + 0.5*4 + 0.5*7 + 0 = 32.5
    assert fcs.fcs_score(row, w).iloc[0] == 32.5


def test_fcs_missing_item_gives_missing_score(cfg):
    row = pd.DataFrame([[7, np.nan, 3, 0, 1, 0, 4, 7, 7]], columns=fcs.ITEMS)
    assert np.isnan(fcs.fcs_score(row, cfg.settings["fcs"]["weights"]).iloc[0])


def test_rcsi_score(cfg):
    row = pd.DataFrame([[1, 2, 3, 4, 5]], columns=rcsi.ITEMS)
    # 1 + 2*2 + 3 + 3*4 + 5 = 25
    assert rcsi.rcsi_score(row, cfg.settings["rcsi"]["weights"]).iloc[0] == 25
    assert rcsi.rcsi_score(pd.DataFrame([[7] * 5], columns=rcsi.ITEMS), cfg.settings["rcsi"]["weights"]).iloc[0] == 56


def test_categories_are_inclusive_upper_bounds():
    s = pd.Series([0, 28, 28.5, 42, 42.5, np.nan])
    assert categorise(s, [28, 42]).tolist()[:5] == [1, 1, 2, 2, 3]
    assert np.isnan(categorise(s, [28, 42]).iloc[5])
    assert categorise(pd.Series([3, 4, 18, 19]), [3, 18]).tolist() == [1, 2, 2, 3]


def test_out_of_range_items_become_missing_not_clipped():
    t = pd.DataFrame({"a": [3, 9, -1, None], "b": [1, 1, 1, 1]})
    clean, n_missing, n_invalid = item_matrix(t, ["a", "b"], 0, 7)
    assert clean["a"].tolist()[:1] == [3] and clean["a"].iloc[1:].isna().all()
    assert n_invalid.tolist() == [0, 1, 1, 0]
    assert n_missing.tolist() == [0, 1, 1, 1]


def test_sum_cap7_reproduces_gen1_staples():
    df = pd.DataFrame({"cer": [7, 3, 0, None], "tub": [2, 2, 0, None]})
    assert sum_sources(df, ["cer", "tub"], cap=7).tolist()[:3] == [7, 5, 0]
    assert np.isnan(sum_sources(df, ["cer", "tub"], cap=7).iloc[3])


def test_text_stored_numbers_are_converted():
    s = to_number(pd.Series(["12.5", "", " 3 "], dtype=object))
    assert s.iloc[0] == 12.5 and np.isnan(s.iloc[1]) and s.iloc[2] == 3


def test_spss_date_conversion():
    # 2024-11-01 00:00 UTC in SPSS seconds since 1582-10-14
    secs = pd.Timestamp("2024-11-01").value // 10**9 + 12219292800
    assert spss_to_datetime(pd.Series([secs])).iloc[0] == pd.Timestamp("2024-11-01")


def test_admin1_lookup_covers_23_regions(cfg):
    assert len(set(cfg.admin1.values())) == 23


# ---- Livelihood coping strategies ----------------------------------------------------------

def test_lcs_severity_matches_strategies_asked(cfg):
    cw = cfg.crosswalk
    asked = {(r.target, r.round_id) for r in cw[(cw["domain"] == "lcs") & (cw["method"] != "missing")].itertuples()
             if r.target in lcs.ITEMS}
    sev = cfg.table("lcs_severity")
    assert asked == set(zip(sev["target"], sev["round_id"]))
    assert set(sev["severity"]) <= set(lcs.SEVERITIES)


def test_lcs_answer_codes_cover_every_round(cfg):
    resp = cfg.table("lcs_responses")
    for rid in cfg.rounds.index:
        r = resp[resp["round_id"] == rid]
        assert sorted(r["response"]) == sorted(lcs.RESPONSE_CODES), rid


def test_lcs_reversed_scale_oct2021_to_feb2023(cfg):
    resp = cfg.table("lcs_responses")
    code = lambda rid, c: resp[(resp["round_id"] == rid) & (resp["code"] == c)]["response"].item()
    assert code("2021-02", "1") == "yes" and code("2021-10", "1") == "no_need"
    assert code("2021-10", "3") == "yes" and code("2023-02", "3") == "yes"
    assert code("2023-10", "30") == "yes" and code("2023-10", "20") == "exhausted"


def test_lcs_common_items_asked_in_every_round(cfg):
    cw = cfg.crosswalk
    for item in cfg.settings["lcs"]["common_items"]:
        rules = cw[(cw["domain"] == "lcs") & (cw["target"] == item)]
        assert (rules["method"] != "missing").all(), item


# ---- Household Dietary Diversity -------------------------------------------------------------

def test_any_and_max_or_last():
    df = pd.DataFrame({"a": [1, 0, None, None, 0], "b": [0, 0, 1, None, None], "g": [5, 0, 2, 0, None]})
    assert any_source(df, ["a", "b"]).tolist()[:3] == [1, 0, 1] and np.isnan(any_source(df, ["a", "b"]).iloc[3])
    # sub-group maximum first, main group only when all sub-groups are missing
    assert max_or_last(df, ["a", "b", "g"]).tolist()[:4] == [1, 0, 1, 0]


def test_hdds_skip_set_to_not_eaten_only_when_gate_is_zero(cfg):
    t = pd.DataFrame({i: [1.0, 1.0] for i in hdds.ITEMS})
    for i in hdds.ITEMS:
        t[f"gate_{i}"] = np.nan
    t.loc[:, "HDDSPrEgg"] = np.nan          # both skipped
    t.loc[:, "gate_HDDSPrEgg"] = [0.0, 3.0]  # gate 0 -> not eaten; gate > 0 -> stays missing
    t["orig_HDDS"] = np.nan
    t["orig_HDDS_phase"] = np.nan
    out = hdds.derive(t, cfg.rounds.loc["2024-10"], cfg)
    assert out["HDDS"].iloc[0] == 11 and np.isnan(out["HDDS"].iloc[1])
    assert out["hdds_n_imputed"].tolist() == [1, 0]


def test_hdds_phase_thresholds(cfg):
    phase = cfg.settings["hdds"]["phase_by_score"]
    assert len(phase) == 13 and [phase[k] for k in (0, 1, 2, 3, 4, 5, 12)] == [5, 5, 4, 3, 2, 1, 1]


# ---- Household Hunger Scale ------------------------------------------------------------------

def hhs_frame(rows):
    cols = ["HHSNoFood", "HHSNoFood_FR", "HHSBedHung", "HHSBedHung_FR", "HHSNotEat", "HHSNotEat_FR"]
    t = pd.DataFrame(rows, columns=cols, dtype=float)
    t["orig_HHS"] = np.nan
    t["orig_HHS_phase"] = np.nan
    return t


def test_hhs_scoring_category_and_phase(cfg):
    t = hhs_frame([
        [0, None, 0, None, 0, None],   # no hunger -> 0
        [1, 1, 0, None, 0, None],      # rarely -> 1
        [1, 2, 1, 2, 0, None],         # sometimes x2 -> 2
        [1, 3, 1, 3, 0, None],         # often x2 -> 4
        [1, 3, 1, 3, 1, 3],            # often x3 -> 6
    ])
    out = hhs.derive(t, cfg.rounds.loc["2025-10"], cfg)
    assert out["HHS"].tolist() == [0, 1, 2, 4, 6]
    assert out["HHSCat"].tolist() == [1, 1, 2, 3, 3]
    assert out["HHS_phase"].tolist() == [1, 2, 3, 4, 5]
    assert out["HHSNoFood_FR"].tolist()[0] == 0  # "no" -> frequency 0


def test_hhs_inconsistent_answers_are_not_scored(cfg):
    t = hhs_frame([[1, None, 0, None, 0, None],   # yes but no frequency
                   [0, 2, 0, None, 0, None]])     # no but a frequency
    out = hhs.derive(t, cfg.rounds.loc["2025-10"], cfg)
    assert out["HHS"].isna().all() and out["hhs_inconsistent"].tolist() == [1, 1]


def test_hhs_oct2019_code2_exception_only_in_that_round(cfg):
    t = hhs_frame([[2, 3, 0, None, 0, None]])
    out = hhs.derive(t, cfg.rounds.loc["2019-10"], cfg)
    assert out["HHS"].item() == 2 and out["hhs_code_exception"].item() == 1
    with pytest.raises(ValueError):
        hhs.derive(t, cfg.rounds.loc["2022-10"], cfg)


def test_hhs_phase_table_covers_scores_0_to_6(cfg):
    assert cfg.settings["hhs"]["phase_by_score"] == [1, 2, 3, 3, 4, 5, 5]


def test_lcs_max_category():
    used = pd.DataFrame({"a": [False, True, True, False], "b": [False, False, True, False],
                         "c": [False, False, False, True]})
    severity = {"a": "stress", "b": "crisis", "c": "emergency"}
    assert lcs.max_category(used, severity).tolist() == [1, 2, 3, 4]
