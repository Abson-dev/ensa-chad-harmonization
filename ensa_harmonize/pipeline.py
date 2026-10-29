"""Run the harmonisation: read each round once, build every requested domain, write outputs + QC + manifest."""
import hashlib
import json
import logging
import platform
from datetime import datetime, timezone
from importlib.metadata import version
from pathlib import Path

import pandas as pd
import pyreadstat

from . import __version__
from .config import Config
from .domains import DOMAINS
from .engine import apply_rules, read_round, required_sources

log = logging.getLogger("ensa_harmonize")


def run(cfg: Config, domains: list[str], rounds: list[str] | None = None,
        formats=("csv", "sav"), hash_inputs: bool = True) -> dict:
    domains = ["core"] + [d for d in domains if d != "core"]
    rounds = rounds or list(cfg.rounds.index)
    out_dir = cfg.output_dir
    (out_dir / "qc").mkdir(parents=True, exist_ok=True)

    parts = {d: [] for d in domains}
    for rid in rounds:
        rnd = cfg.rounds.loc[rid]
        path = cfg.round_path(rid)
        rules = {d: cfg.rules(d, rid) for d in domains}
        cols = sorted(set().union(*(required_sources(r) for r in rules.values())))
        df, meta = read_round(path, cols)
        log.info("%s: read %d rows x %d columns from %s", rid, len(df), len(cols), path.name)
        keys = None
        for d in domains:
            targets = apply_rules(df, meta, rules[d])
            res = DOMAINS[d].derive(targets, rnd, cfg)
            if d == "core":
                keys = pd.DataFrame({"round_id": rid, "hh_id": rid + "_" + res["uuid"]}, index=res.index)
            parts[d].append(pd.concat([keys, res], axis=1))

    results, qcs, files = {}, {}, []
    core = pd.concat(parts["core"], ignore_index=True)
    if not core["hh_id"].is_unique:
        raise ValueError("hh_id is not unique across rounds")
    for d in domains:
        data = core if d == "core" else pd.concat(parts[d], ignore_index=True)
        data = data.sort_values(["round_id", "hh_id"], kind="stable").reset_index(drop=True)
        results[d] = data
        qcs[d] = DOMAINS[d].qc(data, core, cfg)
        files += write_domain(d, data, qcs[d], out_dir, formats)
        log.info("%s: %d rows, %d columns", d, *data.shape)

    manifest = build_manifest(cfg, domains, rounds, files, hash_inputs, results)
    (out_dir / "manifest.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False), encoding="utf-8")
    return {"data": results, "qc": qcs, "manifest": manifest}


def write_domain(d: str, data: pd.DataFrame, qc: pd.DataFrame, out_dir: Path, formats) -> list[Path]:
    mod = DOMAINS[d]
    files = []
    if "csv" in formats:
        p = out_dir / f"ensa_{d}.csv"
        data.to_csv(p, index=False, encoding="utf-8", date_format="%Y-%m-%d")
        files.append(p)
    if "sav" in formats:
        p = out_dir / f"ensa_{d}.sav"
        labels = {"round_id": "Survey round (YYYY-MM)", "hh_id": "Household ID, unique across rounds", **mod.LABELS}
        pyreadstat.write_sav(to_spss(data), str(p),
                             column_labels={c: labels.get(c, "") for c in data.columns},
                             variable_value_labels={k: v for k, v in mod.VALUE_LABELS.items() if k in data.columns})
        files.append(p)
    p = out_dir / "qc" / f"qc_{d}_by_round.csv"
    qc.to_csv(p, index=False, encoding="utf-8")
    files.append(p)
    return files


def to_spss(df: pd.DataFrame) -> pd.DataFrame:
    """pyreadstat needs plain object strings rather than pandas' nullable string dtype."""
    out = df.copy()
    for c in out.columns:
        if pd.api.types.is_string_dtype(out[c]) and not pd.api.types.is_object_dtype(out[c]):
            out[c] = out[c].astype(object).where(out[c].notna(), None)
    return out


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def build_manifest(cfg, domains, rounds, files, hash_inputs, results) -> dict:
    inputs = []
    for rid in rounds:
        p = cfg.round_path(rid)
        inputs.append({"round_id": rid, "file": p.relative_to(cfg.data_dir).as_posix(), "bytes": p.stat().st_size,
                       "sha256": sha256(p) if hash_inputs else None})
    cfg_files = sorted((cfg.root / "config").glob("*"))
    return {
        "run_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "pipeline_version": __version__,
        "domains": domains,
        "rounds": rounds,
        "environment": {"python": platform.python_version(), "platform": platform.platform(),
                        **{pkg: version(pkg) for pkg in ("pandas", "numpy", "pyreadstat")}},
        "config": [{"file": f.name, "sha256": sha256(f)} for f in cfg_files],
        "inputs": inputs,
        # .sav files embed their creation time, so only the .csv hashes are expected to be stable across runs.
        "outputs": [{"file": f.relative_to(cfg.output_dir).as_posix(), "sha256": sha256(f)} for f in files],
        "row_counts": {d: int(len(df)) for d, df in results.items()},
    }
