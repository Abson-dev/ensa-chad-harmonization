"""Merge the eight domain files into one household dataset, with a codebook.

Run after run_harmonize.py, in the 'ensa-chad' environment:
  python build_merged.py

Reads    output/ensa_<domain>.csv (the reference outputs)
Writes   output/merged/ENSA_Chad_merged_2018-2025.csv / .sav / .dta
         output/merged/ENSA_Chad_merged_2018-2025_codebook.xlsx

Every file has one row per household and joins on round_id + hh_id. The merge stops if any key is
missing, duplicated or unmatched, and each written file is read back and compared with the domain
files, cell by cell. output/ is not versioned: these files contain household-level data.
"""
import sys
from pathlib import Path

import pandas as pd
import pyreadstat

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))

from ensa_harmonize import config  # noqa: E402
from ensa_harmonize.domains import DOMAINS  # noqa: E402
from ensa_harmonize.pipeline import to_spss  # noqa: E402

KEYS = ["round_id", "hh_id"]
STEM = "ENSA_Chad_merged_2018-2025"
KEY_LABELS = {"round_id": "Survey round (YYYY-MM)", "hh_id": "Household ID, unique across rounds"}
STATA_LABEL_MAX = 80


def read_domain(out_dir: Path, domain: str) -> pd.DataFrame:
    # Only an empty cell is missing: text such as "NA" or "None" must stay text.
    # round_trip: the default float parser can change the last digit of a decimal.
    df = pd.read_csv(out_dir / f"ensa_{domain}.csv", low_memory=False, keep_default_na=False, na_values=[""],
                     float_precision="round_trip")
    if "svy_date" in df:
        df["svy_date"] = pd.to_datetime(df["svy_date"], format="%Y-%m-%d")
    for c in df.columns[df.dtypes == bool]:
        df[c] = df[c].astype(int)
    return df


def merge(frames: dict[str, pd.DataFrame]) -> pd.DataFrame:
    expected = None
    merged = None
    for d, df in frames.items():
        if df[KEYS].isna().any().any() or df.duplicated(KEYS).any():
            raise ValueError(f"{d}: missing or duplicated keys")
        keys = set(map(tuple, df[KEYS].to_numpy()))
        expected = keys if expected is None else expected
        if keys != expected:
            raise ValueError(f"{d}: households differ from core ({len(keys ^ expected)} unmatched)")
        merged = df if merged is None else merged.merge(df, on=KEYS, how="inner", validate="one_to_one")
    return merged.sort_values(KEYS, kind="stable").reset_index(drop=True)


def labels() -> tuple[dict, dict, dict]:
    var_labels, value_labels, source = dict(KEY_LABELS), {}, {k: "key" for k in KEYS}
    for d, mod in DOMAINS.items():
        var_labels.update(mod.LABELS)
        value_labels.update(mod.VALUE_LABELS)
        source.update({c: d for c in mod.LABELS})
    return var_labels, value_labels, source


def stata_value_labels(value_labels: dict, df: pd.DataFrame) -> tuple[dict, list[str]]:
    """Stata accepts value labels only on numeric variables with whole-number codes."""
    keep, dropped = {}, []
    for c, m in value_labels.items():
        if c not in df:
            continue
        if pd.api.types.is_numeric_dtype(df[c]) and all(float(k).is_integer() for k in m):
            keep[c] = {int(k): v for k, v in m.items()}
        else:
            dropped.append(c)
    return keep, dropped


def same(a: pd.Series, b: pd.Series) -> bool:
    """Equal cell by cell, with missing equal to missing. Stata and SPSS store missing text as ""."""
    a, b = a.reset_index(drop=True), b.reset_index(drop=True)
    if pd.api.types.is_datetime64_any_dtype(a):
        b = pd.to_datetime(b)
    elif pd.api.types.is_numeric_dtype(a):
        b = pd.to_numeric(b)
    else:
        a, b = a.astype(object).where(a.notna(), ""), b.astype(object).where(b.notna(), "")
    return bool(((a == b) | (a.isna() & b.isna())).all())


def check_file(path: Path, reader, reference: pd.DataFrame) -> None:
    back, _ = reader(str(path))
    if list(back.columns) != list(reference.columns) or len(back) != len(reference):
        raise ValueError(f"{path.name}: shape or column order differs")
    back = back.sort_values(KEYS, kind="stable")
    bad = [c for c in reference if not same(reference[c], back[c])]
    if bad:
        raise ValueError(f"{path.name}: values differ in {bad}")
    print(f"{path.name}: {back.shape[0]:,} rows x {back.shape[1]} columns, identical to the domain files")


def codebook(df: pd.DataFrame, var_labels: dict, value_labels: dict, source: dict) -> dict[str, pd.DataFrame]:
    rounds = sorted(df["round_id"].unique())
    filled = df.notna() & (df.astype(object) != "")
    exact_share = filled.groupby(df["round_id"]).mean() * 100
    share = exact_share.round(1)
    variables = pd.DataFrame({
        "variable": df.columns,
        "domain": [source.get(c, "") for c in df.columns],
        "label": [var_labels.get(c, "") for c in df.columns],
        "type": ["date" if pd.api.types.is_datetime64_any_dtype(df[c])
                 else "numeric" if pd.api.types.is_numeric_dtype(df[c]) else "text" for c in df.columns],
        "value_labels": ["; ".join(f"{k} = {v}" for k, v in value_labels[c].items()) if c in value_labels else ""
                         for c in df.columns],
        "non_missing_households": [int(filled[c].sum()) for c in df.columns],
        "rounds_with_data": [int((exact_share[c] > 0).sum()) for c in df.columns],
        "rounds_without_data": [", ".join(r for r in rounds if exact_share.loc[r, c] == 0) for c in df.columns],
    })
    coverage = share.T.rename_axis("variable").reset_index()
    # Interview dates outside the fieldwork window stay in the data with a flag, so they are left out of the range here.
    in_window = df[df["date_flag"] == "ok"]
    per_round = pd.DataFrame({
        "households": df.groupby("round_id").size(),
        "first_interview_in_window": in_window.groupby("round_id")["svy_date"].min().dt.strftime("%Y-%m-%d"),
        "last_interview_in_window": in_window.groupby("round_id")["svy_date"].max().dt.strftime("%Y-%m-%d"),
        "date_outside_window": df[df["date_flag"] == "outside_window"].groupby("round_id").size(),
        "date_missing": df[df["date_flag"] == "missing"].groupby("round_id").size(),
        "zero_weight": df[df["weight_flag"] == "zero"].groupby("round_id").size(),
        "no_weight_in_round": df[df["weight_flag"] == "no_weight_in_round"].groupby("round_id").size(),
    }).fillna(0).reset_index()
    counts = ["date_outside_window", "date_missing", "zero_weight", "no_weight_in_round"]
    per_round[counts] = per_round[counts].astype(int)
    return {"Variables": variables, "Share filled by round (%)": coverage, "Rounds": per_round}


def write_codebook(path: Path, sheets: dict[str, pd.DataFrame]) -> None:
    with pd.ExcelWriter(path, engine="openpyxl") as xl:
        for name, table in sheets.items():
            table.to_excel(xl, sheet_name=name, index=False, freeze_panes=(1, 1))
            ws = xl.sheets[name]
            ws.auto_filter.ref = ws.dimensions
            for i, c in enumerate(table.columns, start=1):
                width = min(60, max(len(str(c)), int(table[c].astype(str).str.len().quantile(0.9))) + 2)
                ws.column_dimensions[ws.cell(1, i).column_letter].width = width


def main() -> None:
    cfg = config.load(ROOT)
    out_dir = cfg.output_dir
    target = out_dir / "merged"
    target.mkdir(parents=True, exist_ok=True)

    frames = {d: read_domain(out_dir, d) for d in DOMAINS}
    df = merge(frames)
    var_labels, value_labels, source = labels()
    print(f"merged: {df.shape[0]:,} households, {df.shape[1]} columns, {df['round_id'].nunique()} rounds")

    undocumented = [c for c in df.columns if c not in var_labels]
    if undocumented:
        print("no variable label:", undocumented)
    too_long = [c for c in df.columns if len(c) > 32]
    if too_long:
        raise ValueError(f"names too long for Stata: {too_long}")

    csv_path = target / f"{STEM}.csv"
    df.to_csv(csv_path, index=False, encoding="utf-8", date_format="%Y-%m-%d")

    sav_path = target / f"{STEM}.sav"
    spss = to_spss(df)
    pyreadstat.write_sav(spss, str(sav_path), compress=True,
                         column_labels={c: var_labels.get(c, "") for c in df.columns},
                         variable_value_labels={k: v for k, v in value_labels.items() if k in df})

    dta_path = target / f"{STEM}.dta"
    dta_values, dropped = stata_value_labels(value_labels, df)
    if dropped:
        print("value labels not written to Stata (non-numeric or non-integer):", dropped)
    cut = [c for c in df.columns if len(var_labels.get(c, "")) > STATA_LABEL_MAX]
    if cut:
        print(f"variable labels cut to {STATA_LABEL_MAX} characters in Stata:", cut)
    # Date objects give a plain Stata date (%td); a pandas datetime would become a date-time (%tc).
    stata = spss.copy()
    stata["svy_date"] = stata["svy_date"].astype(object).where(stata["svy_date"].notna(), None)
    stata["svy_date"] = [d.date() if d is not None else None for d in stata["svy_date"]]
    pyreadstat.write_dta(stata, str(dta_path), file_label="ENSA Chad 2018-2025 merged household data (preliminary)",
                         column_labels={c: var_labels.get(c, "")[:STATA_LABEL_MAX] for c in df.columns},
                         variable_value_labels=dta_values)

    # The reference is rebuilt from the domain files, so a fault in the merge itself is caught too.
    reference = pd.concat([frames["core"].sort_values(KEYS, kind="stable").reset_index(drop=True)]
                          + [frames[d].sort_values(KEYS, kind="stable").reset_index(drop=True).drop(columns=KEYS)
                             for d in frames if d != "core"], axis=1)
    if not reference[KEYS].equals(df[KEYS]):
        raise ValueError("keys are out of order after the merge")
    reference = reference[df.columns]
    check_file(csv_path, lambda p: (pd.read_csv(p, low_memory=False, keep_default_na=False, na_values=[""],
                                                float_precision="round_trip", parse_dates=["svy_date"]), None),
               reference)
    check_file(sav_path, pyreadstat.read_sav, reference)
    check_file(dta_path, pyreadstat.read_dta, reference)

    write_codebook(target / f"{STEM}_codebook.xlsx", codebook(df, var_labels, value_labels, source))
    for f in sorted(target.iterdir()):
        print(f"{f.name}: {f.stat().st_size / 1e6:.1f} MB")


if __name__ == "__main__":
    main()
