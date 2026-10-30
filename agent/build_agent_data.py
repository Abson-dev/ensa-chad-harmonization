"""Build the aggregate-only tables the ENSA agent is allowed to read.

This is the ONLY step that touches household data. It reads the harmonised
files in ../output, computes every indicator of ensa_agent/indicators.py by
round, region and sex of the household head, suppresses cells under
MIN_CELL households, and writes small tables to agent/data/. The agent's
tools read agent/data/ only, so no household record is ever sent to the API.

Run from the repository root after the pipeline:
    python agent/build_agent_data.py
"""
from __future__ import annotations

import json
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
import pandas as pd

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(HERE))
from ensa_agent.indicators import INDICATORS, weighted_median  # noqa: E402

OUT = ROOT / "output"
DATA = HERE / "data"
MIN_CELL = 30  # same rule as the Shiny app and the Word report
DOMAINS = ["core", "fcs", "rcsi", "lcs", "hhs", "hdds", "exp", "demo"]


def load() -> pd.DataFrame:
    missing = [d for d in DOMAINS if not (OUT / f"ensa_{d}.csv").exists()]
    if missing:
        sys.exit(f"Harmonised files missing in {OUT}: {missing}. Run: python run_harmonize.py")
    d = pd.read_csv(OUT / "ensa_core.csv", encoding="utf-8",
                    usecols=["round_id", "hh_id", "year", "season", "generation", "admin1",
                             "weight_norm", "weight_flag"])
    for dom in DOMAINS[1:]:
        x = pd.read_csv(OUT / f"ensa_{dom}.csv")
        x = x.drop(columns=[c for c in x.columns if c.startswith("orig_")])
        d = d.merge(x, on=["round_id", "hh_id"], how="inner", validate="one_to_one")
    # Analysis weight as in the report: normalised weight in rounds that have one, else 1.
    weighted = d.groupby("round_id")["weight_flag"].transform(lambda s: (s == "ok").any())
    d["w"] = np.where(weighted, d["weight_norm"], 1.0)
    d["weighted"] = weighted
    d["head_sex"] = d["HHHSex"].map({1: "Male-headed", 2: "Female-headed"})
    d["national"] = "Chad"
    return d


def aggregate(d: pd.DataFrame) -> pd.DataFrame:
    rows = []
    breakdowns = {"national": "national", "region": "admin1", "head_sex": "head_sex"}
    for ind in INDICATORS:
        v = ind.func(d).astype(float)
        frame = pd.DataFrame({"round_id": d["round_id"], "v": v, "w": d["w"], "weighted": d["weighted"],
                              **{b: d[c] for b, c in breakdowns.items()}})
        for b in breakdowns:
            for (rid, grp), g in frame.dropna(subset=[b]).groupby(["round_id", b], sort=True):
                ok = g["v"].notna() & g["w"].notna()
                n = int(ok.sum())
                if n == 0:
                    value = np.nan
                elif ind.stat == "median":
                    value = weighted_median(g["v"].to_numpy(), g["w"].to_numpy())
                else:
                    value = float(np.average(g.loc[ok, "v"], weights=g.loc[ok, "w"])) if g.loc[ok, "w"].sum() > 0 \
                        else np.nan
                    if ind.stat == "share" and not np.isnan(value):
                        value *= 100
                suppressed = b != "national" and 0 < n < MIN_CELL
                rows.append({"round_id": rid, "breakdown": b, "group": grp, "indicator": ind.id,
                             "value": np.nan if suppressed else value, "n": n,
                             "weighted": bool(g["weighted"].iloc[0]), "suppressed": suppressed})
    return pd.DataFrame(rows)


def rounds_table(d: pd.DataFrame) -> pd.DataFrame:
    cfg = pd.read_csv(ROOT / "config" / "rounds.csv", dtype=str)
    r = d.groupby("round_id").agg(households=("hh_id", "size"), weighted=("weighted", "first")).reset_index()
    r = cfg[["round_id", "year", "season", "generation", "fieldwork_start", "fieldwork_end"]].merge(r, on="round_id")
    r["round"] = r["season"] + " " + r["year"]
    return r[["round_id", "round", "season", "year", "generation", "households", "weighted",
              "fieldwork_start", "fieldwork_end"]]


def main() -> None:
    d = load()
    DATA.mkdir(exist_ok=True)
    (DATA / "qc").mkdir(exist_ok=True)

    rounds = rounds_table(d)
    agg = aggregate(d)
    agg = agg.merge(rounds[["round_id", "round"]], on="round_id", how="left")
    agg = agg[["round_id", "round", "breakdown", "group", "indicator", "value", "n", "weighted", "suppressed"]]
    agg.to_csv(DATA / "indicators.csv", index=False, float_format="%.4f")
    rounds.to_csv(DATA / "rounds.csv", index=False)
    pd.DataFrame([{"indicator": i.id, "domain": i.domain, "label": i.label, "stat": i.stat, "unit": i.unit,
                   "definition": i.definition} for i in INDICATORS]).to_csv(DATA / "indicator_catalog.csv", index=False)

    # Metadata and QC (no household data): crosswalk rules, QC by round, documented data issues.
    shutil.copy(ROOT / "config" / "crosswalk.csv", DATA / "crosswalk.csv")
    for f in (OUT / "qc").glob("qc_*_by_round.csv"):
        shutil.copy(f, DATA / "qc" / f.name)
    wb = ROOT.parent / "ENSA_Chad_crosswalk_2018-2025.xlsx"
    if wb.exists():
        flags = pd.read_excel(wb, sheet_name="Data flags")
        flags.columns = ["issue", "rounds", "found", "handling"]
        flags.to_csv(DATA / "data_issues.csv", index=False)
    else:
        print(f"warning: {wb.name} not found; data_issues.csv not written")

    src = json.loads((OUT / "manifest.json").read_text(encoding="utf-8"))
    meta = {"built_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
            "min_cell": MIN_CELL,
            "pipeline_run": src.get("run_at") or src.get("created") or src.get("timestamp"),
            "households": int(len(d)), "rounds": int(rounds.shape[0]), "indicators": len(INDICATORS)}
    (DATA / "build_info.json").write_text(json.dumps(meta, indent=2), encoding="utf-8")

    sup = int(agg["suppressed"].sum())
    print(f"Agent data written to {DATA}\n  {len(INDICATORS)} indicators, {len(agg):,} cells "
          f"({sup:,} suppressed: under {MIN_CELL} households)")


if __name__ == "__main__":
    main()
