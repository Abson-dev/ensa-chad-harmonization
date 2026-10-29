"""Helpers shared by the indicator domains."""
import numpy as np
import pandas as pd

from ..engine import to_number


def item_matrix(t: pd.DataFrame, items: list[str], lo: float, hi: float):
    """Numeric item matrix; values outside [lo, hi] become missing and are counted, never clipped."""
    raw = t[items].apply(to_number)
    invalid = raw.notna() & ((raw < lo) | (raw > hi))
    clean = raw.mask(invalid)
    return clean, clean.isna().sum(axis=1), invalid.sum(axis=1)


def categorise(score: pd.Series, bounds) -> pd.Series:
    """1 if score <= bounds[0], 2 if <= bounds[1], else 3; missing stays missing."""
    cat = np.select([score <= bounds[0], score <= bounds[1]], [1, 2], 3).astype(float)
    return pd.Series(np.where(score.isna(), np.nan, cat), index=score.index)


def weighted_share(cond: pd.Series, w: pd.Series, valid: pd.Series):
    """Weighted % of valid rows meeting cond; NaN when the round has no usable weight."""
    w = w.where(valid & (w > 0))
    if w.notna().sum() == 0:
        return np.nan
    return round(100 * w[cond].sum() / w.sum(), 2)


def compare_scores(new: pd.Series, orig: pd.Series, tol: float) -> dict:
    """Agreement between recomputed and pre-computed scores."""
    both = new.notna() & orig.notna()
    if both.sum() == 0:
        return {"n": 0, "agree_pct": np.nan, "corr": np.nan, "mean_diff": np.nan}
    diff = new[both] - orig[both]
    return {
        "n": int(both.sum()),
        "agree_pct": round(100 * (diff.abs() <= tol).mean(), 2),
        "corr": round(new[both].corr(orig[both]), 4),
        "mean_diff": round(diff.mean(), 3),
    }
