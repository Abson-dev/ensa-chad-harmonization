"""Command-line entry point.

Examples
  python run_harmonize.py                         # all domains, all rounds
  python run_harmonize.py --domains fcs           # core + FCS only
  python run_harmonize.py --rounds 2024-10 2025-10 --no-hash
"""
import argparse
import logging
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))

try:
    import pyreadstat  # noqa: F401
except ModuleNotFoundError:
    sys.exit("pyreadstat is missing: the pipeline runs in the 'ensa-chad' environment.\n"
             "  conda activate ensa-chad\n  python run_harmonize.py\n"
             "(The 'ensa-agent' environment is only for the agent/ folder.)")

from ensa_harmonize import config, pipeline  # noqa: E402
from ensa_harmonize.domains import DOMAINS  # noqa: E402


def main(argv=None):
    ap = argparse.ArgumentParser(description="Harmonise ENSA Chad household data by domain.")
    ap.add_argument("--domains", nargs="+", default=list(DOMAINS), choices=list(DOMAINS))
    ap.add_argument("--rounds", nargs="+", help="round_ids from config/rounds.csv (default: all)")
    ap.add_argument("--formats", nargs="+", default=["csv", "sav"], choices=["csv", "sav"])
    ap.add_argument("--no-hash", action="store_true", help="skip SHA-256 of the input .sav files (faster)")
    args = ap.parse_args(argv)

    cfg = config.load(ROOT)
    cfg.output_dir.mkdir(parents=True, exist_ok=True)
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s",
                        handlers=[logging.StreamHandler(),
                                  logging.FileHandler(cfg.output_dir / "harmonize.log", mode="w", encoding="utf-8")])
    res = pipeline.run(cfg, args.domains, args.rounds, tuple(args.formats), hash_inputs=not args.no_hash)
    logging.info("Done. Outputs in %s", cfg.output_dir)
    return res


if __name__ == "__main__":
    main()
