"""Load and validate the configuration files in harmonization/config/."""
from dataclasses import dataclass
from pathlib import Path
import tomllib

import pandas as pd

METHODS = {"copy", "copy_label", "sum", "sum_cap7", "any", "max_or_last", "missing"}


@dataclass
class Config:
    root: Path
    settings: dict
    rounds: pd.DataFrame
    crosswalk: pd.DataFrame
    admin1: dict

    @property
    def data_dir(self) -> Path:
        return (self.root / self.settings["paths"]["data_dir"]).resolve()

    @property
    def output_dir(self) -> Path:
        return (self.root / self.settings["paths"]["output_dir"]).resolve()

    def round_path(self, round_id: str) -> Path:
        r = self.rounds.loc[round_id]
        return self.data_dir / r["folder"] / r["file"]

    def rules(self, domain: str, round_id: str) -> pd.DataFrame:
        cw = self.crosswalk
        return cw[(cw["domain"] == domain) & (cw["round_id"] == round_id)]

    def table(self, name: str) -> pd.DataFrame:
        """A domain-specific configuration table, config/<name>.csv, read as text."""
        return pd.read_csv(self.root / "config" / f"{name}.csv", dtype=str, keep_default_na=False)


def load(root: Path) -> Config:
    root = Path(root)
    cfg_dir = root / "config"
    with open(cfg_dir / "settings.toml", "rb") as fh:
        settings = tomllib.load(fh)
    rounds = pd.read_csv(cfg_dir / "rounds.csv", dtype=str, keep_default_na=False).set_index("round_id")
    crosswalk = pd.read_csv(cfg_dir / "crosswalk.csv", dtype=str, keep_default_na=False)
    admin1 = pd.read_csv(cfg_dir / "admin1_names.csv", dtype=str, keep_default_na=False)
    cfg = Config(root, settings, rounds, crosswalk, dict(zip(admin1["raw_name"], admin1["admin1"])))
    validate(cfg)
    return cfg


def validate(cfg: Config) -> None:
    """Fail early if the crosswalk is incomplete or malformed."""
    cw = cfg.crosswalk
    errors = []
    bad = cw.loc[~cw["method"].isin(METHODS), ["domain", "target", "round_id", "method"]]
    errors += [f"unknown method: {tuple(r)}" for r in bad.itertuples(index=False)]
    unknown = sorted(set(cw["round_id"]) - set(cfg.rounds.index))
    errors += [f"round_id not in rounds.csv: {r}" for r in unknown]
    no_src = cw[(cw["method"] != "missing") & (cw["sources"] == "")]
    errors += [f"no sources: {r.domain}/{r.target}/{r.round_id}" for r in no_src.itertuples()]
    dup = cw[cw.duplicated(["domain", "target", "round_id"], keep=False)]
    errors += [f"duplicate rule: {r.domain}/{r.target}/{r.round_id}" for r in dup.itertuples()]
    # Every target of a domain must have an explicit rule (possibly "missing") for every round.
    for (domain, target), g in cw.groupby(["domain", "target"]):
        for r in sorted(set(cfg.rounds.index) - set(g["round_id"])):
            errors.append(f"no rule for {domain}/{target} in round {r}")
    if errors:
        raise ValueError("Invalid crosswalk:\n  " + "\n  ".join(errors))
