"""Read a round and apply the crosswalk rules to produce harmonised target columns."""
import numpy as np
import pandas as pd
import pyreadstat

# Seconds between the SPSS epoch (1582-10-14) and the Unix epoch (1970-01-01): 141,428 days.
SPSS_EPOCH_OFFSET = 12219379200


def required_sources(rules: pd.DataFrame) -> list[str]:
    srcs = set()
    for s in rules.loc[rules["method"] != "missing", "sources"]:
        srcs.update(s.split("|"))
    return sorted(srcs)


def read_round(path, columns):
    """Read only the needed columns, keeping SPSS codes (labels are decoded per rule)."""
    df, meta = pyreadstat.read_sav(str(path), usecols=columns, apply_value_formats=False)
    return df, meta


def to_number(s: pd.Series) -> pd.Series:
    """Numeric conversion; text-stored numbers (KoBo calculate fields) become floats, blanks NaN."""
    if s.dtype == object:
        s = s.astype(str).str.strip().replace({"": None, "nan": None})
    return pd.to_numeric(s, errors="coerce")


def spss_to_datetime(s: pd.Series) -> pd.Series:
    if pd.api.types.is_datetime64_any_dtype(s):
        return s.dt.normalize()
    secs = to_number(s) - SPSS_EPOCH_OFFSET
    return pd.to_datetime(secs, unit="s", errors="coerce").dt.normalize()


def decode_label(s: pd.Series, meta, var: str) -> pd.Series:
    labelset = meta.variable_to_label.get(var)
    if not labelset:
        return s.astype("string").str.strip()
    labels = meta.value_labels[labelset]
    out = s.map(labels)
    # Codes without a label keep their raw value so nothing is silently lost.
    out = out.where(out.notna() | s.isna(), s.astype("string"))
    return out.astype("string").str.strip()


def apply_rules(df: pd.DataFrame, meta, rules: pd.DataFrame) -> pd.DataFrame:
    """Return one column per target, built from the source columns as the rule says."""
    out = pd.DataFrame(index=df.index)
    for rule in rules.itertuples():
        srcs = rule.sources.split("|") if rule.sources else []
        if rule.method == "missing":
            out[rule.target] = np.nan
        elif rule.method == "copy":
            out[rule.target] = df[srcs[0]]
        elif rule.method == "copy_label":
            out[rule.target] = decode_label(df[srcs[0]], meta, srcs[0])
        elif rule.method == "sum":
            out[rule.target] = sum_sources(df, srcs, cap=None)
        elif rule.method == "sum_cap7":
            out[rule.target] = sum_sources(df, srcs, cap=7)
        elif rule.method == "any":
            out[rule.target] = any_source(df, srcs)
        elif rule.method == "max_or_last":
            out[rule.target] = max_or_last(df, srcs)
    return out


def any_source(df: pd.DataFrame, srcs: list[str]) -> pd.Series:
    """1 if any source is 1, 0 if none is 1 but at least one is 0, missing if all are missing."""
    x = df[srcs].apply(to_number)
    return (x == 1).any(axis=1).astype(float).where(x.notna().any(axis=1))


def max_or_last(df: pd.DataFrame, srcs: list[str]) -> pd.Series:
    """Row maximum of all sources but the last; the last source when they are all missing
    (e.g. sub-group days, falling back to the main group)."""
    x = df[srcs].apply(to_number)
    head = x.iloc[:, :-1].max(axis=1) if len(srcs) > 1 else pd.Series(np.nan, index=df.index)
    return head.fillna(x.iloc[:, -1])


def sum_sources(df: pd.DataFrame, srcs: list[str], cap=None) -> pd.Series:
    """Row sum of the sources; NaN only if all sources are missing."""
    s = df[srcs].apply(to_number).sum(axis=1, min_count=1)
    return s.clip(upper=cap) if cap is not None else s
