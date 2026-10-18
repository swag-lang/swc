"""Readable competitive gaps and changes on a matched benchmark panel."""
import math
import statistics

import history


# A presentation band, not a confidence interval or a significance test.
DISPLAY_BAND_PCT = 1.0


def measurements(campaign, tasks, runtime, family, key):
    values = []
    for task in tasks:
        record = (campaign.get("tasks", {}).get(task, {}).get(runtime) or {}).get(family) or {}
        value = record.get(key)
        if record.get("error") or not isinstance(value, (int, float)) or not math.isfinite(value) or value <= 0:
            return None
        values.append(value)
    return values or None


def rivals(campaign, tasks, family, key, group=None):
    pool = history.RUN_GROUPS[group] if group else {
        runtime for task in tasks for runtime in campaign.get("tasks", {}).get(task, {})}
    return sorted(runtime for runtime in pool if runtime not in history.TRACKED
                  and measurements(campaign, tasks, runtime, family, key))


def comparison(campaign, tasks, lead, family, key, competitors):
    own = measurements(campaign, tasks, lead, family, key)
    if not own or not competitors:
        return None
    controls = [measurements(campaign, tasks, rt, family, key) for rt in competitors]
    if any(values is None for values in controls):
        return None
    best = [min(values) for values in zip(*controls)]
    ratios = [value / reference for value, reference in zip(own, best)]
    gaps = [(ratio - 1) * 100 for ratio in ratios]
    low, high = 1 - DISPLAY_BAND_PCT / 100, 1 + DISPLAY_BAND_PCT / 100
    return {"ratios": ratios, "gap_pct": statistics.median(gaps),
            "ahead": sum(ratio < low for ratio in ratios),
            "close": sum(low <= ratio <= high for ratio in ratios),
            "behind": sum(ratio > high for ratio in ratios),
            "min_gap_pct": min(gaps), "max_gap_pct": max(gaps),
            "median_ms": statistics.median(own), "total_ms": sum(own),
            "rival_total_ms": sum(best), "saved_ms": sum(best) - sum(own)}


def previous_change(current, campaigns, tasks, lead, family, key, group=None, peak=False):
    """Compare displayed time savings directly on the same task panel.

    Each time value uses that campaign's complete rivals, just like its headline.
    Peak memory compares the two measured Swag peaks directly.
    """
    current_rivals = set(rivals(current, tasks, family, key, group))
    for before in sorted(campaigns, key=lambda c: c["meta"]["date"], reverse=True):
        if before["meta"]["date"] >= current["meta"]["date"]:
            continue
        if before["meta"].get("protocol") != current["meta"].get("protocol"):
            continue
        if peak:
            now_peak = measurements(current, tasks, lead, family, key)
            old_peak = measurements(before, tasks, lead, family, key)
            if not now_peak or not old_peak:
                continue
            return {"reference": before["meta"], "tasks": len(tasks),
                    "previous_peak_bytes": max(old_peak), "current_peak_bytes": max(now_peak)}
        before_rivals = rivals(before, tasks, family, key, group)
        now = comparison(current, tasks, lead, family, key, sorted(current_rivals))
        old = comparison(before, tasks, lead, family, key, before_rivals)
        if not now or not old:
            continue
        result = {"reference": before["meta"], "tasks": len(tasks),
                  "rivals": len(current_rivals),
                  "saved_ms": now["saved_ms"] - old["saved_ms"],
                  "current_saved_ms": now["saved_ms"], "previous_saved_ms": old["saved_ms"]}
        return result
    return None
