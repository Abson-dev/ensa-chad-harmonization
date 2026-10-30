"""Offline checks for the ENSA agent: data boundary, suppression and tools. No API calls."""
import sys
from pathlib import Path

import pandas as pd
import pytest

pytest.importorskip("anthropic")
AGENT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(AGENT))
from ensa_agent import tools  # noqa: E402
from ensa_agent.indicators import INDICATORS, weighted_median  # noqa: E402

pytestmark = pytest.mark.skipif(not (tools.DATA / "indicators.csv").exists(),
                                reason="agent data not built (python agent/build_agent_data.py)")
HOUSEHOLD_COLUMNS = {"hh_id", "uuid", "svy_date", "weight", "weight_norm", "admin2", "admin3"}


def call(tool, **kw):
    return tool.call(kw) if hasattr(tool, "call") else tool(**kw)


def test_no_household_level_data_in_agent_folder():
    for f in tools.DATA.rglob("*.csv"):
        cols = set(pd.read_csv(f, nrows=0).columns)
        assert not cols & HOUSEHOLD_COLUMNS, f"{f.name} has household-level columns {cols & HOUSEHOLD_COLUMNS}"
    ind = pd.read_csv(tools.DATA / "indicators.csv")
    assert len(ind) < 50_000  # aggregates only


def test_small_cells_suppressed():
    ind = pd.read_csv(tools.DATA / "indicators.csv")
    small = ind[(ind.breakdown != "national") & (ind.n > 0) & (ind.n < 30)]
    assert small.value.isna().all() and small.suppressed.all()


def test_matches_app_aggregates():
    """National poor FCS must match the Shiny app's R computation."""
    app = AGENT.parent / "app" / "data" / "indicators_by_round.csv"
    if not app.exists():
        pytest.skip("app data not built")
    a = pd.read_csv(app, dtype={"round_id": str}).set_index("round_id")
    ref = a.fcs_poor_w.where(a.weighted_available, a.fcs_poor_u)
    ind = pd.read_csv(tools.DATA / "indicators.csv", dtype={"round_id": str})
    got = ind.query("indicator == 'fcs_poor' and breakdown == 'national'").set_index("round_id").value
    assert (got.reindex(ref.index) - ref).abs().max() < 1e-3


def test_catalog_complete():
    cat = pd.read_csv(tools.DATA / "indicator_catalog.csv")
    assert set(cat.indicator) == {i.id for i in INDICATORS}


def test_get_indicator_and_round_labels():
    out = call(tools.get_indicator, indicator="fcs_poor_borderline", rounds="Oct 2025, 2024-10")
    assert "2025-10" in out and "2024-10" in out and "2023-10" not in out
    assert "Unknown indicator" in call(tools.get_indicator, indicator="nope")
    reg = call(tools.get_indicator, indicator="fcs_poor", breakdown="region", rounds="2025-10", groups="batha")
    assert "Batha" in reg


def test_not_collected_rounds_are_empty():
    out = call(tools.get_indicator, indicator="fes_median", rounds="2024-10")
    row = [l for l in out.splitlines() if l.startswith("2024-10")][0]
    assert ",,0," in row  # no value, n = 0


def test_compare_rounds():
    out = call(tools.compare_rounds, indicator="rcsi_phase3", round_a="2024-10", round_b="Oct 2025")
    assert "change" in out and "Chad" in out
    assert "exactly one round" in call(tools.compare_rounds, indicator="rcsi_phase3", round_a="", round_b="2025-10")


def test_metadata_tools():
    assert "LCS_FemAnimal" in call(tools.get_crosswalk, domain="lcs", target="LCS_FemAnimal")
    assert "vs_orig_agree_pct" in call(tools.get_quality_checks, domain="hhs")
    assert "Unknown domain" in call(tools.get_quality_checks, domain="xyz")
    if (tools.DATA / "data_issues.csv").exists():
        assert "No documented issue" in call(tools.search_data_issues, keyword="zzzz-no-match")


def test_weighted_median():
    import numpy as np
    assert weighted_median(np.array([1.0, 2.0, 3.0]), np.array([1.0, 1.0, 1.0])) == 2.0
    assert weighted_median(np.array([1.0, 2.0, 3.0]), np.array([0.0, 0.0, 5.0])) == 3.0
    assert np.isnan(weighted_median(np.array([np.nan]), np.array([1.0])))
