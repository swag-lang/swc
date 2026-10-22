"""Generate bench.html from the latest campaign plus the accumulated history.

Every number on the page comes from a raw campaign under results/, through history.py
and stats.py, never from an edit here, so the page cannot disagree with the measurement
that produced it. Every comparison is printed with its 95 % interval and its verdict.
"""
import html
import math
import os
import re

import allocbench
import history
import stats
import toolchains as tc

BENCH = tc.BENCH
OUTFILE = os.path.join(BENCH, "bench.html")
TEMPLATE = os.path.join(BENCH, "page_template.html")

# An optional repository README can quote the report's campaign between these markers.
REPO_README = os.path.join(tc.worktree(), "README.md")
README_BEGIN = "<!-- bench:begin -->"
README_END = "<!-- bench:end -->"

TASK_INFO = {
    "wordfreq": "custom hash table over 2 M words, then sorting",
    "csvagg": "400 k rows, byte-by-byte parsing, floating-point arithmetic",
    "sha256": "8 MiB, integer arithmetic and rotations",
    "dijkstra": "800 by 800 grid, binary heap",
    "raytrace": "480 by 360, f64, recursion",
    "leven": "40 queries against 6000 words",
    "chacha": "16 MiB keystream, 32-bit lanes and rotations",
    "nbody": "5 bodies, 500 k steps, f64, sqrt, array of structs",
    "fannkuch": "fannkuch-redux N = 9, permutations and reversals",
    "binarytrees": "depth 12, allocation and freeing node by node",
    "lz77": "1 MiB, hash-chain compression and decompression",
    "sort": "300 k integers, median-of-three quicksort",
}

RUNTIMES = [
    ("swag-release",       "Swag release",      "native"),
    ("swc-jit-release",    "Swag release",      "JIT"),
    ("swag-devmode",       "Swag devmode",      "native"),
    ("swc-jit-devmode",    "Swag devmode",      "JIT"),
    ("cpp-clang-cl",       "C++ / clang-cl",    "native"),
    ("cpp-msvc",           "C++ / MSVC",        "native"),
    ("rust",               "Rust",              "native"),
    ("zig",                "Zig",               "native"),
    ("d-ldc",              "D / LDC",           "native"),
    ("odin",               "Odin",              "native"),
    ("go",                 "Go",                "native"),
    ("swift",              "Swift",             "native"),
    ("csharp-aot",         "C# NativeAOT",      "AOT"),
    ("csharp-jit",         "C# CoreCLR",        "JIT"),
    ("java-hotspot",       "Java HotSpot",      "JIT"),
    ("node20",             "JavaScript / V8",   "JIT"),
    ("luajit2.1",          "LuaJIT",            "JIT"),
    ("lua5.4",             "Lua",               "interpreted"),
    ("python3.12",         "CPython",           "interpreted"),
    ("php",                "PHP",               "interpreted"),
    ("php-jit",            "PHP",               "JIT"),
    ("ruby",               "Ruby",              "interpreted"),
]
META = {r[0]: r for r in RUNTIMES}

CODES = {
    "swag-release": "SW", "swc-jit-release": "SJ", "swag-devmode": "SD", "swc-jit-devmode": "JD",
    "cpp-clang-cl": "CL", "cpp-msvc": "VC", "rust": "RS", "zig": "ZG", "d-ldc": "LD", "odin": "OD",
    "swift": "SF", "go": "GO", "csharp-aot": "CA", "csharp-jit": "CJ", "java-hotspot": "JV",
    "node20": "V8", "luajit2.1": "LJ", "lua5.4": "LU", "python3.12": "PY", "php": "PH",
    "php-jit": "PJ", "ruby": "RB",
}

LANG = {
    "swag-release": "swag", "swc-jit-release": "swagjit", "swag-devmode": "swagdev",
    "swc-jit-devmode": "swagdevjit", "cpp-clang-cl": "clang", "cpp-msvc": "msvc", "rust": "rust",
    "zig": "zig", "d-ldc": "d", "odin": "odin", "swift": "swift", "csharp-aot": "csaot",
    "csharp-jit": "csjit", "node20": "js", "luajit2.1": "luajit", "lua5.4": "lua", "python3.12": "py",
    "go": "go", "java-hotspot": "java", "php": "php", "php-jit": "phpjit", "ruby": "ruby",
}

# The comparison columns, in reading order.
LEAD_COLUMNS = [
    ("swag-release", "run", "execution release"),
    ("swag-devmode", "run", "execution devmode"),
    ("swc-jit-release", "run", "JIT release"),
    ("swc-jit-devmode", "run", "JIT devmode"),
    ("swag-release", "build", "build release"),
    ("swag-devmode", "build", "build devmode"),
]

LOOP = [
    ("core_rebuild", "std/core full rebuild"),
    ("core_noop", "std/core, nothing changed"),
    ("core_touch", "std/core, one file saved"),
    ("doc_std", "standard library documentation"),
    ("format_tree", "formatting the library sources"),
]

HISTORY_SERIES = [
    ("run-release", "SW", "h-a"), ("jit-release", "SJ", "h-b"),
    ("run-devmode", "SD", "h-c"), ("jit-devmode", "JD", "h-d"),
]


def esc(text):
    return html.escape(str(text), quote=True)


def lang_class(rt):
    return "l-" + LANG.get(rt, "other")


def runtime_label(rt):
    return "%s (%s)" % (META[rt][1], META[rt][2])


def runtime_badge(rt):
    label = esc(runtime_label(rt))
    return ('<span class="runtime-badge %s" role="img" title="%s" aria-label="%s">%s</span>'
            % (lang_class(rt), label, label, CODES[rt]))


def runtime_legend(runtimes):
    return '<ul class="runtime-legend" aria-label="Language legend">%s</ul>' % "".join(
        '<li>%s<span>%s</span></li>' % (runtime_badge(rt), esc(runtime_label(rt))) for rt in runtimes)


# ------------------------------------------------------------------ formatting
def fmt(v, nd=2):
    return "&mdash;" if v is None else ("%." + str(nd) + "f") % v


def duration(ms):
    if ms is None:
        return "&mdash;"
    return "%.2f s" % (ms / 1000) if ms >= 1000 else ("%.1f ms" % ms if ms >= 1 else "%.2f ms" % ms)


def pct(e):
    """A ratio as a signed time difference: 0.92 reads -8.0 %."""
    return "&mdash;" if e is None else "%+.1f&nbsp;%%" % ((e.value - 1.0) * 100.0)


def timed(e):
    return duration(e.value) if e else "&mdash;"


def ci_text(e):
    if e is None:
        return ""
    return "%+.1f to %+.1f %%" % ((e.low - 1.0) * 100.0, (e.high - 1.0) * 100.0)


VERDICT_CLASS = {"faster": "won", "slower": "lost", "tie": "tied"}

# How a value moved since the previous campaign: an arrow and its words.
MOVES = {
    "improved": ("&uarr;", "measurably better than in the previous campaign"),
    "regressed": ("&darr;", "measurably worse than in the previous campaign"),
    "unchanged": ("=", "no measurable change since the previous campaign"),
}


def move_mark(move, title):
    return '<span class="trend %s" role="img" aria-label="%s" title="%s">%s</span>' % (
        move, esc(MOVES[move][1]), esc(title), MOVES[move][0])


def since(now, before):
    """How a time or size ratio moved between two campaigns. Only a change whose 95 % interval
    lies on one side of parity is a move; anything else is "unchanged", noise."""
    return {"faster": "improved", "slower": "regressed", "tie": "unchanged"}[stats.ratio(now, before).verdict()]


def since_mark(now, before, previous_campaign):
    """(move, arrow) of a value since the previous campaign, both values and the change on hover."""
    move, change = since(now, before), stats.ratio(now, before)
    title = "%s (%s): %s before, %s now; change %s, 95 %% interval %s" % (
        MOVES[move][1], campaign_name(previous_campaign), html.unescape(pct(before)), html.unescape(pct(now)),
        html.unescape(pct(change)), ci_text(change))
    return move, move_mark(move, title)


def ordinal(n):
    return "%d%s" % (n, "th" if 10 <= n % 100 <= 20 else {1: "st", 2: "nd", 3: "rd"}.get(n % 10, "th"))


def change_cell(e, lower_word="less time", higher_word="more time"):
    """A ratio with its interval on hover and its verdict as a colour."""
    if e is None:
        return '<span class="ci-cell">&mdash;</span>'
    verdict = e.verdict()
    word = {"faster": lower_word, "slower": higher_word, "tie": "no measurable difference"}[verdict]
    title = "%s; 95 %% interval %s; %d samples%s" % (word, ci_text(e), e.n,
                                                       ", few samples: interval widened" if e.n < 6 else "")
    return '<span class="ci-cell %s" title="%s">%s</span>' % (VERDICT_CLASS[verdict], esc(title), pct(e))


def estimate_title(e, unit_fn=duration):
    if e is None:
        return "no measurement"
    return "median %s, 95 %% interval %s to %s, %d samples" % (
        html.unescape(unit_fn(e.value)), html.unescape(unit_fn(e.low)), html.unescape(unit_fn(e.high)), e.n)


def simple_table(headers, rows, cls=""):
    out = ['<div class="table-wrap"><table%s><thead><tr>' % (' class="%s"' % cls if cls else "")]
    out += ["<th>%s</th>" % h for h in headers]
    out.append("</tr></thead><tbody>")
    for r in rows:
        out.append("<tr><th>%s</th>%s</tr>" % (r[0], "".join("<td>%s</td>" % c for c in r[1:])))
    out.append("</tbody></table></div>")
    return "\n".join(out)


def geo(values):
    values = [v for v in values if v]
    return math.exp(sum(math.log(v) for v in values) / len(values)) if values else None


# --------------------------------------------------------------------- charts
def linw(v, hi):
    return max(0.0, min(100.0, v / hi * 100.0))


def lin_axis(values, steps=4):
    top = max([v for v in values if v] or [1])
    magnitude = 10 ** math.floor(math.log10(top))
    for factor in (1, 1.25, 1.5, 2, 2.5, 3, 4, 5, 7.5, 10):
        hi = factor * magnitude
        if hi >= top:
            break
    hi = math.ceil(hi / steps) * steps
    return hi, [hi * i / steps for i in range(steps + 1)]


def chart(rows, unit):
    """rows: (runtime, value, printed, title); a sorted horizontal bar chart on a zero axis."""
    if not rows:
        return '<p class="cap">No measurement.</p>'
    hi, ticks = lin_axis([v for _, v, _, _ in rows])
    out = ['<figure class="chart">', '<div class="axis" aria-hidden="true">']
    for t in ticks:
        out.append('<span class="tick" style="left:%.3f%%"><i></i><b>%g</b></span>' % (linw(t, hi), t))
    out.append("</div>")
    for rt, v, printed, title in sorted(rows, key=lambda r: r[1]):
        out.append('<div class="row %s" title="%s"><div class="rl"><span class="runtime-name">%s '
                   '<span class="mode">%s</span></span>%s</div>'
                   '<div class="track"><span class="bar" style="width:%.3f%%"></span></div>'
                   '<div class="rv">%s<em>%s</em></div></div>'
                   % (lang_class(rt), esc(title), META[rt][1], META[rt][2], runtime_badge(rt), linw(v, hi),
                      printed, unit))
    out.append("</figure>")
    return "\n".join(out)


def svg_history(labels, series, band=None, width=520, height=200):
    """Lines over campaigns, a shaded 95 % band for the first series, and a parity rule.

    series: (css class, end label, [value or None per campaign]); band: [(lo, hi) or None].
    Values are percentages of time difference against the reference."""
    flat = [v for _, _, vs in series for v in vs if v is not None]
    flat += [v for pair in (band or []) if pair for v in pair]
    if not flat:
        return '<p class="cap">No campaign yet.</p>'
    lo, hi = min(flat + [0.0]), max(flat + [0.0])
    span = max(hi - lo, 2.0)
    lo, hi = lo - span * 0.15, hi + span * 0.15
    pad_l, pad_r, pad_t, pad_b = 48, 40, 12, 26
    n = len(labels)
    px = lambda i: pad_l + ((width - pad_l - pad_r) / 2 if n == 1 else i * (width - pad_l - pad_r) / (n - 1))
    py = lambda v: pad_t + (1 - (v - lo) / (hi - lo)) * (height - pad_t - pad_b)
    o = ['<svg class="hchart" viewBox="0 0 %d %d" role="img" aria-label="Progress against the reference" '
         'preserveAspectRatio="xMidYMid meet">' % (width, height)]
    for k in range(5):
        v = lo + (hi - lo) * k / 4
        o.append('<line class="hgrid" x1="%d" y1="%.1f" x2="%d" y2="%.1f"/>' % (pad_l, py(v), width - pad_r, py(v)))
        o.append('<text class="hlab" x="%d" y="%.1f" text-anchor="end">%+.1f%%</text>' % (pad_l - 6, py(v) + 3.5, v))
    o.append('<line class="hreference" x1="%d" y1="%.1f" x2="%d" y2="%.1f"/>' % (pad_l, py(0), width - pad_r, py(0)))
    if band:
        top = [(px(i), py(p[1])) for i, p in enumerate(band) if p]
        bottom = [(px(i), py(p[0])) for i, p in enumerate(band) if p]
        if len(top) > 1:
            o.append('<polygon class="hband" points="%s"/>' % " ".join("%.1f,%.1f" % p for p in top + bottom[::-1]))
        elif len(top) == 1:
            o.append('<line class="hwhisker" x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f"/>'
                     % (top[0][0], top[0][1], bottom[0][0], bottom[0][1]))
    step = max(1, -(-(n - 1) // 4))
    for i, label in enumerate(labels):
        if i in (0, n - 1) or (i % step == 0 and n - 1 - i >= step):
            anchor = "start" if i == 0 and n > 1 else ("end" if i == n - 1 and n > 1 else "middle")
            o.append('<text class="hlab" x="%.1f" y="%d" text-anchor="%s">%s</text>' % (px(i), height - 8, anchor, esc(label)))
    ends = []
    for cls, name, vs in series:
        pts = [(px(i), py(v)) for i, v in enumerate(vs) if v is not None]
        if not pts:
            continue
        if len(pts) > 1:
            o.append('<polyline class="hline %s" points="%s"/>' % (cls, " ".join("%.1f,%.1f" % p for p in pts)))
        for x, y in pts[-12:]:
            o.append('<circle class="hdot %s" cx="%.1f" cy="%.1f" r="2.6"/>' % (cls, x, y))
        if name:
            ends.append([pts[-1][1], pts[-1][0], cls, name])
    ends.sort()
    for i in range(1, len(ends)):
        if ends[i][0] - ends[i - 1][0] < 12:
            ends[i][0] = ends[i - 1][0] + 12
    for y, x, cls, name in ends:
        o.append('<text class="hend %s" x="%.1f" y="%.1f">%s</text>' % (cls, x + 8, y + 3.5, name))
    o.append("</svg>")
    return "\n".join(o)


def spark(values):
    """Percentages over campaigns, around the zero rule."""
    pts = [(i, v) for i, v in enumerate(values) if v is not None]
    if not pts:
        return ""
    lo = min([v for _, v in pts] + [0.0])
    hi = max([v for _, v in pts] + [0.0])
    if hi - lo < 1.0:
        lo, hi = lo - 0.5, hi + 0.5
    n = max(1, len(values) - 1)
    x = lambda i: 2 + i * 136.0 / n
    y = lambda v: 20 - (v - lo) / (hi - lo) * 18
    if len(pts) == 1:
        pts = [(0, pts[0][1]), (n, pts[0][1])]
    return ('<svg class="spark" viewBox="0 0 140 22" aria-hidden="true"><line x1="0" x2="140" y1="%.1f" y2="%.1f"/>'
            '<polyline points="%s"/></svg>' % (y(0), y(0), " ".join("%.1f,%.1f" % (x(i), y(v)) for i, v in pts)))


# ------------------------------------------------------------------- campaigns
def campaigns_of(results, phase):
    """The recorded campaigns that measured `phase`, oldest first."""
    return [c for c in results if phase in ((c["meta"].get("settings") or {}).get("phases") or ())]


def campaign_name(campaign):
    meta = campaign["meta"]
    return "%s, %s" % (meta["date"][:10], meta.get("commit") or meta["stamp"])


def reference_name_of(campaign):
    return (((campaign or {}).get("meta", {}).get("installs") or {}).get("reference") or {}).get("name")


def series_estimate(campaign, task, rt, family):
    key = "ms" if family == "run" else "wall_ms"
    return history.estimate(history.record(campaign, task, rt, family), key)


def merged_comparisons(run_campaign, build_campaign):
    """Every Swag lead's comparisons, execution from one campaign and compilation from another."""
    comps = {}
    for campaign in (run_campaign, build_campaign):
        if campaign:
            for lead, families in history.comparisons(campaign).items():
                comps.setdefault(lead, {}).update(families)
    return comps


def progress_of(campaign, family):
    """The progress series a campaign measured for one family, run or build; the hello program
    on the JIT belongs to execution, the edit-build loop and the hello builds to compilation."""
    if not campaign:
        return {}
    progress = history.progress(campaign)
    out = {pid: rec for pid, rec in progress.items()
           if pid != "singles" and next(p for p in history.PROGRESS if p[0] == pid)[2] == family}
    singles = {sid: e for sid, e in (progress.get("singles") or {}).items()
               if sid.startswith("hello-run") == (family == "run")}
    if singles:
        out["singles"] = singles
    return out


def progress_pairs(run_campaigns, build_campaigns):
    """The progress series of the latest campaign of each family, the same series of the previous
    campaign measured against the same reference, and that campaign per series."""
    latest, previous, previous_of = {}, {}, {}
    for family, campaigns in (("build", build_campaigns), ("run", run_campaigns)):
        if not campaigns:
            continue
        campaign = campaigns[-1]
        # A different reference starts a different series: its ratios are not comparable.
        before = next((c for c in reversed(campaigns[:-1])
                       if reference_name_of(c) == reference_name_of(campaign)), None)
        for pid, rec in progress_of(campaign, family).items():
            if pid == "singles":
                latest.setdefault("singles", {}).update(rec)
            else:
                latest[pid] = rec
        for pid, rec in progress_of(before, family).items():
            if pid == "singles":
                previous.setdefault("singles", {}).update(rec)
                previous_of.update({sid: before for sid in rec})
            else:
                previous[pid] = rec
                previous_of[pid] = before
    return latest, previous, previous_of


# The progress series that says whether each headline's Swag runtime itself moved.
CARD_PROGRESS = {("swag-release", "run"): "run-release", ("swag-devmode", "run"): "run-devmode",
                 ("swc-jit-release", "run"): "jit-release", ("swag-release", "build"): "build-release",
                 ("swag-devmode", "build"): "build-devmode"}


def headline_card(name, lead, family, comps, previous_comps, pairs):
    c = (comps.get(lead) or {}).get(family)
    cls = lang_class(lead)
    if not c:
        return ('<div class="stat %s"><div class="sl">%s</div><div class="sv">&mdash;</div>'
                '<div class="sn">No complete comparison</div></div>' % (cls, name))
    rival = c["strongest"]
    best = c["rivals"][rival]
    e, tally = best["geo"], best["tally"]
    value = "%+.1f<em>%%</em>" % ((e.value - 1.0) * 100.0)
    previous = (previous_comps.get(lead) or {}).get(family)
    if previous:
        rival_before = previous["strongest"]
        b = previous["rivals"][rival_before]["geo"]
        against = "" if rival_before == rival else " vs %s" % (runtime_label(rival_before) if family == "run"
                                                             else META[rival_before][1])
        # The value against a rival also moves when the rival does; the arrow says whether Swag
        # itself moved, measured against its frozen reference in the same rounds.
        latest, earlier, previous_of = pairs
        pid = CARD_PROGRESS[(lead, family)]
        now_ref = stats.Estimate.from_dict((latest.get(pid) or {}).get("geo"))
        before_ref = stats.Estimate.from_dict((earlier.get(pid) or {}).get("geo"))
        mark = ""
        if now_ref and before_ref:
            move, change = since(now_ref, before_ref), stats.ratio(now_ref, before_ref)
            mark = move_mark(move, "Swag itself, against the frozen reference: %s (%s): %s before, %s now; "
                                   "change %s, 95 %% interval %s" % (
                                       MOVES[move][1], campaign_name(previous_of[pid]), html.unescape(pct(before_ref)),
                                       html.unescape(pct(now_ref)), html.unescape(pct(change)), ci_text(change)))
        movement = '<span class="trend-pair">%s<span class="previous-value">previous %s%s</span></span>' % (
            mark, pct(b), esc(against))
    else:
        movement = '<span class="trend-pair"><span class="previous-value">no previous campaign</span></span>'
    rival_name = runtime_label(rival) if family == "run" else META[rival][1]
    return ('<div class="stat %s"><div class="sl">%s</div><div class="sv">%s%s</div>'
            '<div class="sn">time against the strongest rival, %s<br>95 %% interval %s</div>'
            '<div class="sn"><b>%d faster &middot; %d no difference &middot; %d slower</b> of %d tasks</div></div>'
            % (cls, name, value, movement, esc(rival_name), ci_text(e), tally["faster"], tally["tie"],
               tally["slower"], sum(tally.values())))


SHORT_SERIES = {
    "run-release": "native release", "run-devmode": "native devmode", "jit-release": "JIT release",
    "jit-devmode": "JIT devmode", "build-release": "build release", "build-devmode": "build devmode",
    "memory-release": "compiler memory", "size-release": "executable size",
}


def changes_by_task(latest, previous, previous_of, tasks):
    """Per task and series, the ratio to the reference, with an arrow and the previous value where
    it measurably moved since the previous campaign: the effect of the work done on the compiler."""
    pids = [p[0] for p in history.PROGRESS if p[0] in latest]
    better, worse, rows = [], [], []
    for task in tasks:
        cells = []
        for pid in pids:
            now = stats.Estimate.from_dict(latest[pid]["tasks"].get(task))
            before = stats.Estimate.from_dict(((previous.get(pid) or {}).get("tasks") or {}).get(task))
            if now is None:
                cells.append("&mdash;")
                continue
            cell = change_cell(now)
            if before is not None:
                move, mark = since_mark(now, before, previous_of[pid])
                if move != "unchanged":
                    cell += '%s<small class="was">was %s</small>' % (mark, pct(before))
                    (better if move == "improved" else worse).append(
                        "<code>%s</code> %s %s &rarr; %s" % (task, SHORT_SERIES[pid], pct(before), pct(now)))
            cells.append(cell)
        rows.append(["<code>%s</code>" % task] + cells)
    summary = ""
    if previous:
        summary = ('<p class="cap moves"><b class="improved">&uarr; better:</b> %s<br>'
                   '<b class="regressed">&darr; worse:</b> %s<br>'
                   'Everything else: no measurable change.</p>'
                   % (", ".join(better) or "nothing", ", ".join(worse) or "nothing"))
    summary += ('<p class="cap">A value is green or red when it is measurably better or worse than the reference; '
                'an arrow and the previous value mark a measurable move since the previous campaign.</p>')
    return summary + simple_table(["task"] + [SHORT_SERIES[p] for p in pids], rows, "by-task")


def progress_section(entries, pairs, reference_label, tasks):
    """The compiler under test against the frozen reference: latest campaign, the previous one, history."""
    if not entries:
        return '<p class="cap">No recorded campaign yet.</p>'
    latest, previous, previous_of = pairs

    def row(label, e, before, previous_campaign, trend, lower="less time", higher="more time"):
        cell = change_cell(e, lower, higher)
        if before is not None:
            cell += since_mark(e, before, previous_campaign)[1]
        rows.append([label, cell, pct(before) if before is not None else "&mdash;", ci_text(e), trend])

    rows = []
    for pid, label, *_ in history.PROGRESS:
        rec = latest.get(pid)
        if not rec:
            continue
        e = stats.Estimate.from_dict(rec.get("geo"))
        if e is None:
            continue
        series = [((x.get("progress") or {}).get(pid) or {}).get("geo") for x in entries]
        size = pid.startswith(("memory", "size"))
        per_task = " ".join("%s %s" % (t, html.unescape(pct(stats.Estimate.from_dict(v))))
                            for t, v in rec["tasks"].items() if v)
        row('<span title="%s">%s</span>' % (esc(per_task), label), e,
            stats.Estimate.from_dict((previous.get(pid) or {}).get("geo")), previous_of.get(pid),
            spark([((s["value"] - 1.0) * 100.0) if s else None for s in series]),
            "smaller" if size else "less time", "larger" if size else "more time")
    singles = latest.get("singles") or {}
    singles_before = previous.get("singles") or {}
    for sid, label in [("loop-" + wid, label) for wid, label in LOOP] + [
            ("hello-build-release", "hello world build, release"),
            ("hello-build-devmode", "hello world build, devmode"),
            ("hello-run-release", "hello world on the JIT, time to output")]:
        e = stats.Estimate.from_dict(singles.get(sid))
        if e:
            series = [(((x.get("progress") or {}).get("singles") or {}).get(sid)) for x in entries]
            row(label, e, stats.Estimate.from_dict(singles_before.get(sid)), previous_of.get(sid),
                spark([((s["value"] - 1.0) * 100.0) if s else None for s in series]))
    parts = [simple_table(["series", "against the reference", "previous campaign", "95 % interval", "history"],
                          rows, "progress")]
    parts.append('<h3>Task by task</h3>')
    parts.append(changes_by_task(latest, previous, previous_of, tasks))
    labels_x = [e["meta"].get("commit") or e["meta"]["stamp"] for e in entries]
    parts.append('<div class="grid2">')
    for title, ids in (("Execution", ("run-release", "jit-release", "run-devmode", "jit-devmode")),
                       ("Compilation", ("build-release", "build-devmode"))):
        series, band = [], None
        for pid in ids:
            values = [((x.get("progress") or {}).get(pid) or {}).get("geo") for x in entries]
            if not any(values):
                continue
            code = {"run-release": "SW", "jit-release": "SJ", "run-devmode": "SD", "jit-devmode": "JD",
                    "build-release": "SW", "build-devmode": "SD"}[pid]
            cls = {"run-release": "h-a", "jit-release": "h-b", "run-devmode": "h-c", "jit-devmode": "h-d",
                   "build-release": "h-a", "build-devmode": "h-c"}[pid]
            series.append((cls, code, [((v["value"] - 1.0) * 100.0) if v else None for v in values]))
            if band is None:
                band = [(((v["low"] - 1.0) * 100.0), ((v["high"] - 1.0) * 100.0)) if v else None for v in values]
        parts.append('<div><h3>%s, time against reference %s</h3>%s</div>'
                     % (title, esc(reference_label), svg_history(labels_x, series, band)))
    parts.append('</div>')
    return "\n".join(parts)


def comparison_matrix(comps):
    """Every competitor against every Swag mode: geometric mean of the per-task ratios."""
    headers = ["language / mode"] + ['%s %s' % (runtime_badge(lead), label) for lead, _, label in LEAD_COLUMNS]
    rows = []
    for rt, *_ in RUNTIMES:
        if rt in history.TRACKED:
            continue
        cells, present = [], False
        for lead, family, _ in LEAD_COLUMNS:
            c = ((comps.get(lead) or {}).get(family) or {}).get("rivals", {}).get(rt)
            if c:
                present = True
                t = c["tally"]
                cell = change_cell(c["geo"])
                cells.append('%s <small class="tally" title="tasks where Swag is faster / not different / slower">'
                             '%d&middot;%d&middot;%d</small>' % (cell, t["faster"], t["tie"], t["slower"]))
            else:
                cells.append("&mdash;")
        if present:
            rows.append(['%s %s' % (runtime_badge(rt), esc(runtime_label(rt)))] + cells)
    return simple_table(headers, rows, "matrix")


def ranking_values(campaign, tasks, runtimes, family):
    """Per task, the median of every runtime; for compilation, the hello program too."""
    rows = [(t, {rt: series_estimate(campaign, t, rt, family) for rt in runtimes}) for t in tasks]
    if family == "build":
        hello = campaign.get("hello_build") or {}
        rows.append(("hello", {rt: history.estimate(hello.get(rt) if hello.get(rt) and not hello[rt].get("error")
                                                    else None, "wall_ms") for rt in runtimes}))
    return rows


def places_of(values, order):
    """The place printed for each runtime of a line ordered by median: its position, except that a
    Swag runtime and the runtimes next to it in that order that are not measurably different from
    it share the place where their run starts, printed "2=". Returns rt -> (place, shared, swag)."""
    places = {}
    for i, s in enumerate(order):
        if s not in history.TRACKED or s in places:
            continue
        tie = lambda rt: rt not in places and stats.ratio(values[rt], values[s]).verdict() == "tie"
        start, end = i, i
        while start > 0 and tie(order[start - 1]):
            start -= 1
        while end + 1 < len(order) and tie(order[end + 1]):
            end += 1
        for rt in order[start:end + 1]:
            places[rt] = (start + 1, end > start, s)
    for i, rt in enumerate(order):
        places.setdefault(rt, (i + 1, False, None))
    return places


def ranking_table(rows, previous_rows=None, previous_campaign=None):
    """One line per task, fastest to slowest median. The runtimes next to a Swag runtime that are
    not measurably different from it share one shaded band, so their order is plainly noise;
    neighbouring bands alternate shades. Swag's place carries its move since the previous
    campaign, counted among the runtimes measured in both."""
    out = ['<div class="table-wrap"><table class="performance"><thead><tr><th scope="col">task</th>'
           '<th scope="col">fastest &rarr; slowest &middot; median</th></tr></thead><tbody>']
    previous_rows = dict(previous_rows or [])
    for task, values in rows:
        median = lambda rt: values[rt].value
        measured = sorted((rt for rt in values if values[rt]), key=median)
        before = previous_rows.get(task) or {}
        both = [rt for rt in measured if before.get(rt)]
        places = places_of(values, measured)
        places_now = places_of(values, both)
        places_before = places_of(before, sorted(both, key=lambda rt: before[rt].value))
        # One band per run of runtimes sharing a place, alternating shades so touching bands part.
        bands, band_of = [], {}
        for rt in measured:
            place, shared, _ = places[rt]
            if shared:
                if not bands or bands[-1][0] != place:
                    bands.append((place, []))
                bands[-1][1].append(rt)
        for n, (_, members) in enumerate(bands):
            for k, rt in enumerate(members):
                band_of[rt] = " band band-%s%s" % ("ab"[n % 2], "" if k == len(members) - 1 else " band-more")
        info = TASK_INFO.get(task, task)
        out.append('<tr><th scope="row" title="%s"><code>%s</code></th><td><ol>' % (esc(info), task))
        for rt in measured + [rt for rt in values if not values[rt]]:
            if rt not in META:
                continue
            e = values[rt]
            place, shared, swag = places.get(rt, (None, False, None))
            title = "%s: %s" % (runtime_label(rt), estimate_title(e))
            if before.get(rt):
                title += "; previous campaign %s" % html.unescape(duration(before[rt].value))
            if shared and rt != swag:
                title += "; not measurably different from %s, so it shares its place" % runtime_label(swag)
            mark = ""
            if rt in history.TRACKED and rt in places_now:
                now_place, before_place = places_now[rt][0], places_before[rt][0]
                move = "improved" if now_place < before_place else (
                    "regressed" if now_place > before_place else "unchanged")
                mark = move_mark(move, "%s of %d now, %s in the previous campaign (%s), among the runtimes measured "
                                       "in both" % (ordinal(now_place), len(both), ordinal(before_place),
                                                    campaign_name(previous_campaign)))
            out.append('<li class="%s%s" title="%s"><span class="speed-label">%s%s</span>'
                       '<span class="speed-value">%s</span></li>'
                       % (lang_class(rt), band_of.get(rt, ""), esc(title), runtime_badge(rt), mark, timed(e)))
        out.append("</ol></td></tr>")
    out.append("</tbody></table></div>")
    return "\n".join(out)


def execution_tables(campaign, previous, tasks):
    parts = []
    for group, title in (("native", "Native / AOT"), ("jit", "JIT / interpreted")):
        runtimes = [rt for rt, *_ in RUNTIMES if rt in tc.RUN_GROUPS[group] and
                    any(history.record(campaign, t, rt, "run") for t in tasks)]
        if runtimes:
            before = ranking_values(previous, tasks, runtimes, "run") if previous else None
            parts.append('<h3>%s</h3>%s' % (title, ranking_table(ranking_values(campaign, tasks, runtimes, "run"),
                                                                 before, previous)))
    return "\n".join(parts)


def build_table(campaign, previous, tasks):
    runtimes = [rt for rt, *_ in RUNTIMES if any(history.record(campaign, t, rt, "build") for t in tasks)]
    before = ranking_values(previous, tasks, runtimes, "build") if previous else None
    return ranking_table(ranking_values(campaign, tasks, runtimes, "build"), before, previous)


def resources(run_campaign, build_campaign, tasks):
    parts = ['<div class="grid2">']
    if build_campaign:
        rows = []
        for rt, *_ in RUNTIMES:
            peaks = [history.estimate(history.record(build_campaign, t, rt, "build"), "peak_bytes") for t in tasks]
            if all(peaks) and peaks:
                worst = max(peaks, key=lambda e: e.value)
                rows.append((rt, worst.value / 2 ** 20, fmt(worst.value / 2 ** 20, 0),
                             "largest per-task median, %s" % estimate_title(worst, lambda b: "%.0f MiB" % (b / 2 ** 20))))
        parts.append('<div><h3>Peak compiler memory</h3><p class="cap">Committed memory of the whole build '
                     'process tree; the largest per-task median.</p>%s</div>' % chart(rows, "MiB"))
        rows = []
        for rt, *_ in RUNTIMES:
            sizes = [(history.record(build_campaign, t, rt, "build") or {}).get("exe_bytes") for t in tasks]
            if sizes and all(sizes):
                g = geo(sizes) / 1024.0
                rows.append((rt, g, fmt(g, 0), "geometric mean over the tasks"))
        parts.append('<div><h3>Artifact size</h3><p class="cap">Geometric mean. C# CoreCLR: IL assembly; '
                     'Java: class files; both need their installed runtime.</p>%s</div>' % chart(rows, "KiB"))
    if run_campaign:
        rows = []
        for rt, *_ in RUNTIMES:
            peaks = [history.estimate(history.record(run_campaign, t, rt, "run"), "peak_bytes") for t in tasks]
            if peaks and all(peaks):
                worst = max(peaks, key=lambda e: e.value)
                rows.append((rt, worst.value / 2 ** 20, fmt(worst.value / 2 ** 20, 1), "largest per-task median"))
        parts.append('<div><h3>Peak program memory</h3><p class="cap">Largest per-task median.</p>%s</div>'
                     % chart(rows, "MiB"))
        rows = []
        for rt, rec in (run_campaign.get("hello_run") or {}).items():
            if rt in META and rec.get("samples") and not rec.get("error"):
                e = history.estimate(rec, "first_ms")
                if e:
                    rows.append((rt, e.value, "%.1f" % e.value, estimate_title(e)))
        parts.append('<div><h3>Hello-world startup</h3><p class="cap">Time to first output, median. '
                     'Swag JIT compiles the program first.</p>%s</div>' % chart(rows, "ms"))
    parts.append("</div>")
    return "\n".join(parts)


ALLOC_WORKLOADS = [
    ("pair", "one 32-byte block allocated and freed"),
    ("trees", "binary trees of 16-byte nodes"),
    ("churn", "50,000 live blocks of mixed sizes, replaced at random"),
    ("medium", "256 live blocks from 4 to 64 KiB"),
    ("large", "32 live blocks from 64 KiB to 1 MiB, one page touched per 4 KiB"),
    ("realloc", "buffers doubled from 16 bytes to 4 MiB"),
    ("spread", "a few live blocks of twelve sizes, like an application"),
    ("grow", "4 million 32-byte blocks allocated before any are freed"),
    ("spread:8", "spread on 8 threads"),
    ("churn:4", "churn on 4 threads"),
    ("medium:4", "medium on 4 threads"),
    ("large:4", "large on 4 threads"),
    ("xfer:2", "2 producer/consumer pairs, cross-thread freeing"),
    ("xfer:4", "4 producer/consumer pairs"),
]


ALLOC_NAMES = {"swag": "Swag", "mimalloc": "mimalloc", "crt": "CRT"}
ALLOC_RIVALS = ("mimalloc", "crt")


def allocator_measures(campaign):
    """Per workload, every implementation's median and Swag's ratio to each competitor; then those
    ratios' geometric means over the workloads where all three completed."""
    workloads, panel = {}, {r: [] for r in ALLOC_RIVALS}
    for workload, accs in (campaign.get("allocator") or {}).items():
        est = {name: stats.estimate((accs.get(name) or {}).get("samples") or [])
               for name in allocbench.IMPLEMENTATIONS if not (accs.get(name) or {}).get("error")}
        vs = {r: stats.ratio(est.get("swag"), est.get(r)) for r in ALLOC_RIVALS}
        if all(vs.values()):
            for r in ALLOC_RIVALS:
                panel[r].append(vs[r])
        workloads[workload] = {"est": est, "vs": vs, "accs": accs}
    return {"workloads": workloads, "geo": {r: stats.geomean(v) if v else None for r, v in panel.items()}}


def allocator_move(now, before):
    """Whether Swag's allocator measurably moved, from its ratios to both fixed competitors.

    mimalloc and the C runtime heap do not change between campaigns and are measured in the
    same rounds as Swag. Swag moved only when its ratios to both moved measurably the same way;
    a machine state that shifts one of them alone is not Swag (measured 2026-10-22 on `spread`:
    mimalloc -31 % and CRT +46 % with no allocator change)."""
    if not now or not before or not all(now.get(r) for r in ALLOC_RIVALS) or \
            not all(before.get(r) for r in ALLOC_RIVALS):
        return None
    moves = {since(now[r], before[r]) for r in ALLOC_RIVALS}
    return moves.pop() if len(moves) == 1 else "unchanged"


def allocator_mark(move, now, before, previous_campaign):
    title = "%s (%s): %s" % (MOVES[move][1], campaign_name(previous_campaign), "; ".join(
        "against %s %s before, %s now" % (ALLOC_NAMES[r], html.unescape(pct(before[r])), html.unescape(pct(now[r])))
        for r in ALLOC_RIVALS))
    return move_mark(move, title)


def ns_per_op(e):
    if e is None:
        return "&mdash;"
    return "%s ns/op" % (fmt(e.value, 0) if e.value >= 100 else fmt(e.value, 1))


def allocator_section(campaigns):
    measured = [c for c in campaigns if c.get("allocator")]
    if not measured:
        return '<p class="cap">No allocator measurement in this campaign.</p>'
    now = allocator_measures(measured[-1])
    previous_campaign = measured[-2] if len(measured) > 1 else None
    before = allocator_measures(previous_campaign) if previous_campaign else None
    known = dict(ALLOC_WORKLOADS)
    names = [w for w, _ in ALLOC_WORKLOADS if w in now["workloads"]] + \
            [w for w in now["workloads"] if w not in known]
    better, worse = [], []
    overview = ['<div class="alloc-grid">']
    rows = []
    for workload in names:
        rec = now["workloads"][workload]
        vs_before = ((before or {}).get("workloads", {}).get(workload) or {}).get("vs")
        move = allocator_move(rec["vs"], vs_before)
        mark = allocator_mark(move, rec["vs"], vs_before, previous_campaign) if move and move != "unchanged" else ""
        if mark:
            (better if move == "improved" else worse).append("<code>%s</code> against mimalloc %s &rarr; %s" % (
                workload, pct(vs_before["mimalloc"]), pct(rec["vs"]["mimalloc"])))
        overview.append('<div class="alloc-workload"><h3 title="%s">%s</h3>' % (esc(known.get(workload, "")), workload))
        timings = [(name, e) for name, e in rec["est"].items() if e]
        longest = max((e.value for _, e in timings), default=1)
        for name, e in sorted(timings, key=lambda x: x[1].value):
            title = "%s: %s" % (ALLOC_NAMES[name], estimate_title(e, lambda v: "%.1f ns/op" % v))
            overview.append('<div class="alloc-row alloc-%s" title="%s"><span>%s%s</span><span class="alloc-track">'
                            '<i style="width:%.4f%%"></i></span><span class="num">%s</span></div>'
                            % (name, esc(title), ALLOC_NAMES[name], mark if name == "swag" else "",
                               100 * e.value / longest, ns_per_op(e)))
        overview.append("</div>")
        ws = [((rec["accs"].get(name) or {}).get("peak_working_set_bytes") or 0) / 1048576.0 or None
              for name in allocbench.IMPLEMENTATIONS]
        rows.append(['%s <span class="mode">%s</span>' % (workload, known.get(workload, ""))] +
                    [ns_per_op(rec["est"].get(name)) for name in allocbench.IMPLEMENTATIONS] +
                    [change_cell(rec["vs"].get(r)) for r in ALLOC_RIVALS] + [fmt(v, 1) for v in ws])
    overview.append("</div>")
    move = allocator_move(now["geo"], (before or {}).get("geo"))
    panel = " &middot; ".join("against %s %s%s" % (
        ALLOC_NAMES[r], change_cell(now["geo"][r]),
        ' <small class="was">previous %s</small>' % pct(before["geo"][r]) if before and before["geo"].get(r) else "")
        for r in ALLOC_RIVALS if now["geo"].get(r))
    if move:
        panel += allocator_mark(move, now["geo"], before["geo"], previous_campaign)
    summary = '<p class="cap moves"><b>Swag over the workloads:</b> %s' % panel
    if before:
        summary += ('<br><b class="improved">&uarr; better:</b> %s<br><b class="regressed">&darr; worse:</b> %s<br>'
                    'Everything else: no measurable change against both mimalloc and CRT.'
                    % (", ".join(better) or "nothing", ", ".join(worse) or "nothing"))
    summary += "</p>"
    return "\n".join([summary] + overview + [
        '<details><summary>Allocator times and peak memory</summary>',
        simple_table(["workload", "Swag", "mimalloc", "CRT", "Swag / mimalloc", "Swag / CRT",
                      "Swag (MiB)", "mimalloc (MiB)", "CRT (MiB)"], rows), "</details>"])


def quality_section(campaign):
    """The machine, its state, the toolchains, and how quiet the campaign was."""
    if not campaign:
        return ""
    meta = campaign["meta"]
    m = meta.get("machine") or {}
    power = m.get("power") or {}
    q = campaign.get("quality") or {}
    ref = (meta.get("installs") or {}).get("reference") or {}
    subject = (meta.get("installs") or {}).get("subject") or {}
    foreign = q.get("foreign_median_cores") or {}
    items = [
        ("Machine", "%s, %s logical processors (%s performance cores), %s GiB, %s"
         % (esc(m.get("cpu")), m.get("logical_processors"), m.get("performance_cores"), m.get("memory_gib"),
            esc(m.get("os")))),
        ("Power", "%s, power mode <code>%s</code>" % ("mains" if power.get("ac") else "battery", esc(power.get("mode")))),
        ("Compiler", "<code>%s</code>%s, sha256 <code>%s</code>" % (esc(meta.get("commit")), "*" if meta.get("dirty") else "",
                                                                   esc((subject.get("swc_sha256") or "")[:16]))),
        ("Reference", "<code>%s</code>, commit <code>%s</code>, frozen %s, sha256 <code>%s</code>"
         % (esc(ref.get("name")), esc(ref.get("commit")), esc((ref.get("frozen") or "")[:10]),
            esc((ref.get("swc_sha256") or "")[:16]))),
        ("Samples", "%d accepted; %d taken again after interference; %d still contended (%.1f %%); %.0f s waited for quiet"
         % (q.get("accepted", 0), q.get("set_aside", 0), q.get("contended", 0), 100 * q.get("contended_share", 0.0),
            q.get("quiet_waits_s", 0.0))),
        ("Background", "median foreign load while sampling: %s cores" % ", ".join(
            "%s %.1f" % (k, v) for k, v in foreign.items() if v is not None)),
        ("Sampling", "seed %s, execution pinned to %s (%s performance cores), compiler workers %s"
         % ((meta.get("settings") or {}).get("seed"), esc((meta.get("settings") or {}).get("pin_mask")),
            (meta.get("settings") or {}).get("pin_cores"), (meta.get("settings") or {}).get("swc_cores") or "compiler default")),
    ]
    versions = meta.get("toolchains") or {}
    tool_rows = [[esc(runtime_label(rt)) if rt in META else esc(rt), '<span class="l">%s</span>' % esc(v or "?")]
                 for rt, v in sorted(versions.items())]
    return ('<ul class="method">%s</ul><details><summary>Toolchain versions</summary>%s</details>'
            % ("".join("<li><b>%s</b>%s</li>" % item for item in items),
               simple_table(["toolchain", "version"], tool_rows)))


# ---------------------------------------------------------------- repo README
def write_repo_readme(block):
    if not os.path.exists(REPO_README):
        return False
    with open(REPO_README, "rb") as f:
        raw = f.read()
    eol = b"\r\n" if raw.count(b"\r\n") > raw.count(b"\n") // 2 else b"\n"
    text = raw.decode("utf-8").replace("\r\n", "\n")
    start, end = text.find(README_BEGIN), text.find(README_END)
    if start < 0 or end < 0 or end < start:
        return False
    merged = text[:start + len(README_BEGIN)] + "\n" + block.strip("\n") + "\n" + text[end:]
    with open(REPO_README, "wb") as f:
        f.write(merged.encode("utf-8").replace(b"\n", eol))
    return True


def md_table(header, rows):
    out = ["| %s |" % " | ".join(header), "|%s|" % "|".join(["---"] * len(header))]
    return "\n".join(out + ["| %s |" % " | ".join(r) for r in rows])


def median_cell(campaign, task, rt, family, nd):
    e = series_estimate(campaign, task, rt, family)
    return fmt(e.value, nd) if e else "-"


def readme_block(run_campaign, build_campaign, comps, tasks):
    def md_pct(e):
        return "%s (%s)" % (html.unescape(pct(e)), ci_text(e)) if e else "-"

    lines = ["", "Medians of a campaign on a Windows laptop, protocol %d "
             "([`%s`](bench/results/%s.json)); every ratio has its 95 %% interval. "
             "Negative means less time than the rival." % (history.PROTOCOL, run_campaign["meta"]["stamp"],
                                                            run_campaign["meta"]["stamp"]), ""]
    rows = []
    for lead, family, label in LEAD_COLUMNS:
        c = (comps.get(lead) or {}).get(family)
        if c:
            best = c["rivals"][c["strongest"]]
            t = best["tally"]
            rows.append([label, "%s %s" % (META[c["strongest"]][1], META[c["strongest"]][2]), md_pct(best["geo"]),
                         "%d / %d / %d" % (t["faster"], t["tie"], t["slower"])])
    lines.append(md_table(["Swag", "strongest rival", "time difference", "faster / same / slower"], rows))
    cols = [("swag-release", "Swag"), ("cpp-clang-cl", "clang-cl"), ("rust", "Rust"), ("zig", "Zig"),
            ("go", "Go"), ("swc-jit-release", "Swag JIT"), ("luajit2.1", "LuaJIT"), ("node20", "V8")]
    lines += ["", "**Execution, median ms:**", "",
              md_table(["task"] + [n for _, n in cols],
                       [["`%s`" % t] + [median_cell(run_campaign, t, rt, "run", 1) for rt, _ in cols]
                        for t in tasks])]
    if build_campaign:
        bcols = [("swag-release", "Swag"), ("cpp-clang-cl", "clang-cl"), ("rust", "Rust"), ("zig", "Zig"),
                 ("go", "Go"), ("d-ldc", "D"), ("odin", "Odin")]
        lines += ["", "**Compilation, source to executable, median ms** (warm toolchain, clean project):", "",
                  md_table(["task"] + [n for _, n in bcols],
                           [["`%s`" % t] + [median_cell(build_campaign, t, rt, "build", 0) for rt, _ in bcols]
                            for t in tasks])]
    lines += ["", "See [bench/](bench) for the protocol: medians with confidence intervals, a frozen reference "
              "compiler measured in every campaign, interference checks on every sample.", ""]
    return "\n".join(lines)


# ----------------------------------------------------------------------- main
def main():
    results = history.load_results()
    run_campaigns, build_campaigns = campaigns_of(results, "run"), campaigns_of(results, "build")
    run_campaign = run_campaigns[-1] if run_campaigns else None
    build_campaign = build_campaigns[-1] if build_campaigns else None
    previous_run = run_campaigns[-2] if len(run_campaigns) > 1 else None
    previous_build = build_campaigns[-2] if len(build_campaigns) > 1 else None
    if not run_campaign and not build_campaign:
        raise SystemExit("no campaign of protocol %d under bench/results; run a campaign first" % history.PROTOCOL)
    entries = history.rebuild()
    main_campaign = run_campaign or build_campaign
    tasks = [t for t in tc.TASKS if t in main_campaign["tasks"] and
             (build_campaign is None or t in build_campaign["tasks"])]

    comps = merged_comparisons(run_campaign, build_campaign)
    previous_comps = merged_comparisons(previous_run, previous_build)
    matrix = comparison_matrix(comps)
    pairs = progress_pairs(run_campaigns, build_campaigns)
    execution_stats = "".join(headline_card(name, lead, "run", comps, previous_comps, pairs)
                              for lead, name in (("swag-release", "Native execution &middot; release"),
                                                 ("swag-devmode", "Native execution &middot; devmode"),
                                                 ("swc-jit-release", "JIT / interpreted &middot; release")))
    build_stats = "".join(headline_card(name, lead, "build", comps, previous_comps, pairs)
                          for lead, name in (("swag-release", "Compilation &middot; release"),
                                             ("swag-devmode", "Compilation &middot; devmode")))
    reference = ((main_campaign["meta"].get("installs") or {}).get("reference") or {})
    reference_name = "%s (%s)" % (reference.get("name", "?"), reference.get("commit", "?"))
    present = [rt for rt, *_ in RUNTIMES if any(history.record(c, t, rt, f) for c, f in
                                                ((run_campaign, "run"), (build_campaign, "build")) if c
                                                for t in tasks)]
    subs = {
        "{{execution_stats}}": execution_stats,
        "{{build_stats}}": build_stats,
        "{{progress}}": progress_section(entries, pairs, reference_name, tasks),
        "{{comparison_matrix}}": matrix,
        "{{ex_performance}}": execution_tables(run_campaign, previous_run, tasks) if run_campaign else "",
        "{{bu_performance}}": build_table(build_campaign, previous_build, tasks) if build_campaign else "",
        "{{previous_run}}": campaign_name(previous_run) if previous_run else "none",
        "{{previous_build}}": campaign_name(previous_build) if previous_build else "none",
        "{{allocator}}": allocator_section(run_campaigns),
        "{{resources}}": resources(run_campaign, build_campaign, tasks),
        "{{quality}}": quality_section(main_campaign),
        "{{runtime_legend}}": runtime_legend(present),
        "{{reference}}": esc(reference_name),
        "{{campaigns}}": str(len(entries)),
        "{{protocol}}": str(history.PROTOCOL),
        "{{ntasks}}": str(len(tasks)),
        "{{nruntimes}}": str(len(present)),
        "{{run_date}}": run_campaign["meta"]["date"][:10] if run_campaign else "&mdash;",
        "{{build_date}}": build_campaign["meta"]["date"][:10] if build_campaign else "&mdash;",
        "{{run_commit}}": esc(run_campaign["meta"].get("commit")) if run_campaign else "&mdash;",
        "{{build_commit}}": esc(build_campaign["meta"].get("commit")) if build_campaign else "&mdash;",
        "{{commit}}": esc(main_campaign["meta"].get("commit")),
        "{{subject}}": esc((main_campaign["meta"].get("subject") or "")[:90]),
        "{{skipped}}": esc(", ".join(main_campaign.get("skipped") or []) or "none"),
    }
    with open(TEMPLATE, encoding="utf-8") as f:
        page = f.read()
    for k, v in subs.items():
        page = page.replace(k, v)
    left = set(re.findall(r"\{\{\w+\}\}", page))
    if left:
        print("WARNING unresolved placeholders:", left)
    with open(OUTFILE, "w", encoding="utf-8", newline="\r\n") as f:
        f.write(page)
    print("written bench.html (%d bytes, %d campaign(s) in history)" % (len(page), len(entries)))
    if run_campaign and build_campaign and run_campaign["meta"]["stamp"] == build_campaign["meta"]["stamp"]:
        if write_repo_readme(readme_block(run_campaign, build_campaign, comps, tasks)):
            print("repository README refreshed from campaign %s" % run_campaign["meta"]["stamp"])


if __name__ == "__main__":
    main()
