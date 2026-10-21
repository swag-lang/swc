"""What a campaign concludes: progress against the reference, comparisons, the page."""
import json
import math
import os
import random
import shutil
import sys
import tempfile
import unittest
from html.parser import HTMLParser
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import history
import mkpage
import toolchains as tc

TASKS = ["sort", "nbody", "csvagg"]
# Median times by runtime; the reference counterpart of each Swag runtime is 10 % slower,
# Rust 20 % faster than Swag release, clang-cl equal to it.
RUN = {"swag-release": 10.0, "ref-release": 11.0, "swag-devmode": 14.0, "ref-devmode": 14.0,
       "swc-jit-release": 10.5, "ref-jit-release": 11.55, "swc-jit-devmode": 15.0, "ref-jit-devmode": 15.0,
       "rust": 8.0, "cpp-clang-cl": 10.0, "node20": 30.0, "luajit2.1": 21.0}
BUILD = {"swag-release": 150.0, "ref-release": 150.0, "swag-devmode": 200.0, "ref-devmode": 220.0,
         "rust": 300.0, "cpp-clang-cl": 450.0}


def series(base, key, rng, rounds=12, noise=0.01, extra=None):
    samples = []
    for r in range(rounds):
        value = base * math.exp(rng.gauss(0, noise))
        sample = {key: value, "wall_ms": value, "foreign_cores": 1.0, "round": r, "attempts": 1}
        sample.update(extra or {})
        samples.append(sample)
    return {"samples": samples}


def make_campaign(stamp="20261022-100000", seed=1, shift=1.0):
    rng = random.Random(seed)
    tasks = {}
    for task in TASKS:
        entries = {}
        for rt, base in RUN.items():
            entry = {"kind": "aot" if rt in BUILD else "jit"}
            factor = shift if rt in tc.TRACKED else 1.0
            entry["run"] = series(base * factor, "ms", rng)
            entry["run"]["check"] = 42
            if rt in BUILD:
                entry["build"] = series(BUILD[rt], "wall_ms", rng, extra={"peak_bytes": 100 * 2 ** 20})
                entry["build"]["exe_bytes"] = 120000
            entries[rt] = entry
        tasks[task] = entries
    return {
        "meta": {"protocol": history.PROTOCOL, "stamp": stamp, "date": "2026-10-22T10:00:00+00:00",
                 "commit": "abc1234567", "subject": "test", "dirty": False, "label": "",
                 "settings": {"phases": ["build", "run"], "seed": 5, "pin_mask": "0x1", "pin_cores": 1},
                 "machine": {"cpu": "Test CPU", "power": {"ac": True, "mode": "best performance"}},
                 "installs": {"subject": {"swc_sha256": "0" * 64},
                              "reference": {"name": "r1", "commit": "dd211f6eeb", "frozen": "2026-10-21",
                                            "swc_sha256": "1" * 64}},
                 "toolchains": {"rust": "rustc 1.90.0"}},
        "quality": {"accepted": 100, "contended": 0, "set_aside": 3, "contended_share": 0.0,
                    "quiet_waits_s": 2.0, "foreign_median_cores": {"run": 1.0}},
        "calibration": {"probes": {"start": 40.0, "end": 41.0}},
        "tasks": tasks,
        "loop": {"core_rebuild": {"subject": series(3000.0, "wall_ms", rng),
                                  "reference": series(3300.0, "wall_ms", rng)}},
        "hello_build": {"swag-release": series(100.0, "wall_ms", rng), "ref-release": series(100.0, "wall_ms", rng)},
        "hello_run": {"swc-jit-release": series(90.0, "first_ms", rng), "ref-jit-release": series(90.0, "first_ms", rng)},
        "skipped": [],
    }


class ProgressTests(unittest.TestCase):
    def test_the_paired_ratio_against_the_reference(self):
        p = history.progress(make_campaign())
        self.assertAlmostEqual(p["run-release"]["geo"]["value"], 1 / 1.1, delta=0.01)
        self.assertLess(p["run-release"]["geo"]["high"], 1.0)
        self.assertAlmostEqual(p["run-devmode"]["geo"]["value"], 1.0, delta=0.01)
        self.assertLessEqual(p["run-devmode"]["geo"]["low"], 1.0)
        self.assertGreaterEqual(p["run-devmode"]["geo"]["high"], 1.0)
        self.assertAlmostEqual(p["build-devmode"]["geo"]["value"], 200 / 220, delta=0.01)
        self.assertAlmostEqual(p["singles"]["loop-core_rebuild"]["value"], 3000 / 3300, delta=0.02)
        self.assertIn("hello-build-release", p["singles"])
        self.assertIn("hello-run-release", p["singles"])

    def test_pairs_follow_rounds_not_positions(self):
        campaign = make_campaign()
        rec = campaign["tasks"]["sort"]["swag-release"]["run"]
        rec["samples"] = rec["samples"][1:]
        e = history.paired(rec, campaign["tasks"]["sort"]["ref-release"]["run"], "ms")
        self.assertEqual(e.n, 11)

    def test_a_missing_reference_produces_no_progress(self):
        campaign = make_campaign()
        for task in TASKS:
            for rt in tc.REFERENCES:
                del campaign["tasks"][task][rt]
        self.assertNotIn("run-release", history.progress(campaign))


class ComparisonTests(unittest.TestCase):
    def test_the_strongest_rival_and_its_verdicts(self):
        comps = history.comparisons(make_campaign())
        native = comps["swag-release"]["run"]
        self.assertEqual(native["strongest"], "rust")
        rust = native["rivals"]["rust"]
        self.assertAlmostEqual(rust["geo"].value, 10 / 8, delta=0.02)
        self.assertEqual(rust["tally"], {"faster": 0, "tie": 0, "slower": 3})
        self.assertEqual(native["rivals"]["cpp-clang-cl"]["geo"].verdict(), "tie")
        self.assertEqual(comps["swc-jit-release"]["run"]["strongest"], "luajit2.1")
        self.assertNotIn("rust", comps["swc-jit-release"]["run"]["rivals"])
        self.assertEqual(comps["swag-release"]["build"]["strongest"], "rust")

    def test_a_failed_competitor_leaves_the_panel(self):
        campaign = make_campaign()
        campaign["tasks"]["sort"]["rust"]["run"] = {"error": "exit=1"}
        self.assertNotIn("rust", history.comparisons(campaign)["swag-release"]["run"]["rivals"])

    def test_condense_round_trips_through_json(self):
        entry = history.condense(make_campaign())
        self.assertEqual(json.loads(json.dumps(entry))["headline"]["swag-release/run"]["rival"], "rust")


class _Parser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.ids = set()

    def handle_starttag(self, tag, attrs):
        for k, v in attrs:
            if k == "id":
                self.ids.add(v)


class PageTests(unittest.TestCase):
    def test_the_page_renders_every_section_from_raw_campaigns(self):
        scratch = tempfile.mkdtemp(prefix="bench page ")
        self.addCleanup(shutil.rmtree, scratch, True)
        results = os.path.join(scratch, "results")
        os.makedirs(results)
        for i, shift in enumerate((1.0, 0.95)):
            campaign = make_campaign("20261022-1%d0000" % i, seed=i, shift=shift)
            campaign["meta"]["date"] = "2026-10-22T1%d:00:00+00:00" % i
            with open(os.path.join(results, campaign["meta"]["stamp"] + ".json"), "w", encoding="utf-8") as f:
                json.dump(campaign, f)
        out = os.path.join(scratch, "bench.html")
        with mock.patch.object(history, "RESULTS", os.path.join(results, "*.json")), \
                mock.patch.object(history, "HISTORY", os.path.join(scratch, "history.json")), \
                mock.patch.object(mkpage, "BENCH", scratch), \
                mock.patch.object(mkpage, "OUTFILE", out), \
                mock.patch.object(mkpage, "REPO_README", os.path.join(scratch, "README.md")), \
                mock.patch("builtins.print"):
            mkpage.main()
        with open(out, encoding="utf-8") as f:
            page = f.read()
        self.assertNotIn("{{", page)
        parser = _Parser()
        parser.feed(page)
        for section in ("progress", "comparisons", "execution", "compilation", "ressources", "methode"):
            self.assertIn(section, parser.ids)
        self.assertIn("Rust", page)
        self.assertIn("95 % interval", page)
        with open(os.path.join(scratch, "history.json"), encoding="utf-8") as f:
            self.assertEqual(len(json.load(f)), 2)


if __name__ == "__main__":
    unittest.main()
