"""Unit tests for the harmonisation rules. Run from harmonization/:  python -m pytest -q"""
import sys
from pathlib import Path

import numpy as np
import pandas as pd
import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from ensa_harmonize import config  # noqa: E402
from ensa_harmonize.domains import fcs, rcsi  # noqa: E402
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
