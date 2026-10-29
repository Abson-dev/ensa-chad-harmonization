"""Domain registry. To add a domain: write a module with NAME, LABELS, VALUE_LABELS,
derive() and qc(), add its rules to config/crosswalk.csv, and register it here."""
from . import core, fcs, rcsi

DOMAINS = {m.NAME: m for m in (core, fcs, rcsi)}
