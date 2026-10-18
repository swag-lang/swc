"""Generate bench.html from the latest campaign plus the accumulated history.

Every number on the page comes from a JSON file, never from an edit here, so the
page can never disagree with the measurement that produced it.
"""
import glob
import html
import json
import math
import os

import history
import report_metrics
import toolchains as tc

BENCH = tc.BENCH
OUTFILE = os.path.join(BENCH, "bench.html")
TEMPLATE = os.path.join(BENCH, "page_template.html")

# An optional repository README can quote the report's campaign between these markers.
# Refresh that block from the same data so it cannot drift from the generated page.
REPO_README = os.path.join(tc.worktree(), "README.md")
README_BEGIN = "<!-- bench:begin -->"
README_END = "<!-- bench:end -->"

# What each task exercises, shown when hovering its name. The order and the list itself
# come from toolchains.TASKS; a task missing here is still shown, only without a description.
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
    ("swag-release",       "swag release",      "native",    "swag"),
    ("swc-jit-release",    "swag release",      "JIT",       "swag"),
    ("swag-fast-debug",    "swag devmode",      "native",    "swag"),
    ("swc-jit-fast-debug", "swag devmode",      "JIT",       "swag"),
    ("cpp-clang-cl",       "clang",             "native",    "native"),
    ("cpp-msvc",           "MSVC",              "native",    "native"),
    ("rust",               "Rust",              "native",    "native"),
    ("zig",                "Zig",               "native",    "native"),
    ("d-ldc",              "D",                 "native",    "native"),
    ("odin",               "Odin",              "native",    "native"),
    ("go",                 "Go",                "native",    "native"),
    ("swift",              "Swift",             "native",    "native"),
    ("csharp-aot",         "C# NativeAOT",      "AOT",       "managed"),
    ("csharp-jit",         "C# CoreCLR",        "JIT",       "managed"),
    ("java-hotspot",       "Java HotSpot",      "JIT",       "managed"),
    ("node20",             "Node / V8",         "JIT",       "dynamic"),
    ("luajit2.1",          "LuaJIT",            "JIT",       "dynamic"),
    ("lua5.4",             "Lua",               "interpreted", "dynamic"),
    ("python3.12",         "CPython",           "interpreted", "dynamic"),
    ("php",                "PHP",               "interpreted", "dynamic"),
    ("php-jit",            "PHP",               "JIT",       "dynamic"),
    ("ruby",               "Ruby",              "interpreted", "dynamic"),
]
META = {r[0]: r for r in RUNTIMES}

# Stable two-character codes identify compilers and runtime modes on every surface.
CODES = {
    "swag-release": "SW", "swc-jit-release": "SJ",
    "swag-fast-debug": "SD", "swc-jit-fast-debug": "JD",
    "cpp-clang-cl": "CL", "cpp-msvc": "VC", "rust": "RS",
    "zig": "ZG", "d-ldc": "LD", "odin": "OD", "swift": "SF", "go": "GO",
    "csharp-aot": "CA", "csharp-jit": "CJ", "java-hotspot": "JV", "node20": "V8",
    "luajit2.1": "LJ", "lua5.4": "LU", "python3.12": "PY",
    "php": "PH", "php-jit": "PJ", "ruby": "RB",
}

# Runtime classes identify configurations; the stylesheet shares colours across execution modes.
LANG = {
    "swag-release": "swag", "swc-jit-release": "swagjit",
    "swag-fast-debug": "swagdev", "swc-jit-fast-debug": "swagdevjit",
    "cpp-clang-cl": "clang", "cpp-msvc": "msvc", "rust": "rust", "zig": "zig", "d-ldc": "d",
    "odin": "odin", "swift": "swift", "csharp-aot": "csaot", "csharp-jit": "csjit",
    "node20": "js", "luajit2.1": "luajit", "lua5.4": "lua", "python3.12": "py",
    "go": "go", "java-hotspot": "java", "php": "php", "php-jit": "phpjit", "ruby": "ruby",
}


def lang_class(rt):
    return "l-" + LANG.get(rt, "other")


def runtime_label(rt):
    name = {"cpp-clang-cl": "C++ / clang-cl", "cpp-msvc": "C++ / MSVC",
            "node20": "JavaScript / Node V8", "d-ldc": "D / LDC"}.get(rt, META[rt][1])
    return "%s (%s)" % (name, META[rt][2])


def runtime_badge(rt):
    label = html.escape(runtime_label(rt), quote=True)
    return ('<span class="runtime-badge %s" role="img" title="%s" aria-label="%s">%s</span>'
            % (lang_class(rt), label, label, CODES[rt]))


def runtime_legend(runtimes):
    return '<ul class="runtime-legend" aria-label="Language legend">%s</ul>' % "".join(
        '<li>%s<span>%s</span></li>' % (runtime_badge(rt), html.escape(runtime_label(rt)))
        for rt in runtimes)


# The journal shows only the most recent campaigns; the curves carry every one.
JOURNAL_ROWS = 10

DRIFT_LIMIT = history.DRIFT_LIMIT_PCT

HIST_SERIES = [
    ("swag-release",       "SW", "h-a"),
    ("swc-jit-release",    "SJ", "h-b"),
    ("swag-fast-debug",    "SD", "h-c"),
    ("swc-jit-fast-debug", "JD", "h-d"),
]

# The edit-build loop, in the order a person meets it: the first build, the build where
# nothing changed, the build after one save, and the two commands that are not builds.
LOOP = [
    ("core_rebuild", "std/core cold rebuild", "all sources, outputs removed"),
    ("core_noop", "std/core unchanged", "nothing changed since the previous build"),
    ("core_touch", "std/core one saved file", "one source timestamp advanced"),
    ("hello_build", "hello world &rarr; exe", "small program, source to executable"),
    ("doc_std", "standard library documentation", "complete standard library site"),
    ("format_tree", "repository formatting", "baseline source trees, on a private copy"),
]


def latest_campaign(phase=None):
    """The most recent campaign that contains ``phase`` of the current protocol.

    A campaign measured under an older protocol is not merely older, it measured
    something else; publishing one as if it were current is the failure this whole
    file exists to prevent. A complete campaign contains both phases, including the
    historical campaigns that predate explicit phase metadata.
    """
    for path in sorted(glob.glob(os.path.join(BENCH, "results", "*.json")), reverse=True):
        with open(path, encoding="utf-8") as f:
            campaign = json.load(f)
        phases = (campaign.get("meta", {}).get("settings") or {}).get("phases")
        if campaign.get("meta", {}).get("protocol") != history.PROTOCOL:
            continue
        measured = set(phases or ("build", "run"))
        if (phase is None and {"build", "run"}.issubset(measured)) or phase in measured:
            return history.settle_campaign(campaign)
    what = "complete" if phase is None else phase
    raise SystemExit("no %s campaign of protocol %d in bench/results — run a campaign first"
                     % (what, history.PROTOCOL))


def fmt(v, nd=2):
    return "&mdash;" if v is None else ("%." + str(nd) + "f") % v


def signed_pct(v):
    return "&mdash;" if v is None else "%+.1f" % ((v - 1.0) * 100.0)


def duration(ms):
    if ms is None:
        return "&mdash;"
    return "%s s" % fmt(ms / 1000, 2) if ms >= 1000 else "%s ms" % fmt(ms, 1 if ms >= 1 else 2)


def signed_duration(ms):
    if math.isclose(ms, 0, abs_tol=1e-9):
        return "0.0 ms"
    return ("+" if ms > 0 else "-") + duration(abs(ms))


def time_saved(saved_ms):
    if math.isclose(saved_ms, 0, abs_tol=1e-9):
        return "0.0 ms difference"
    return "%s %s" % (duration(abs(saved_ms)), "saved" if saved_ms > 0 else "lost")


def total_time_gap(summary):
    return time_saved(summary["saved_ms"]) if summary else "No complete comparison"


def trend(change, show_previous=True):
    if change is None:
        return ('<span class="trend unavailable" aria-label="No comparable earlier campaign">'
                '&mdash;</span>', 'No comparable earlier campaign')
    evidence = ""
    if "saved_ms" in change:
        previous = signed_duration(-change["previous_saved_ms"])
        current = signed_duration(-change["current_saved_ms"])
        sensitivity = change.get("sensitivity_ms")
        unresolved = ("sensitivity_ms" in change and
                      (sensitivity is None or sensitivity[0] <= 0 <= sensitivity[1]))
        if current == previous:
            state, arrow, label = "unchanged", "&rarr;", "Unchanged"
        elif unresolved:
            state, arrow, label = "unchanged", "&rarr;", "Change unresolved by repeated samples"
        elif change["saved_ms"] > 0:
            state, arrow, label = "improved", "&uarr;", "Time gap decreased"
        else:
            state, arrow, label = "regressed", "&darr;", "Time gap increased"
        detail = "%s: %s before, %s now" % (label, previous, current)
        if sensitivity is not None:
            evidence = "; removing each selected minimum gives a change from %s to %s" % (
                signed_duration(sensitivity[0]), signed_duration(sensitivity[1]))
        elif "sensitivity_ms" in change:
            evidence = "; repeated samples are missing for the sensitivity check"
    else:
        previous = "%d MiB" % round(change["previous_peak_bytes"] / 1048576)
        current = "%d MiB" % round(change["current_peak_bytes"] / 1048576)
        if current == previous:
            state, arrow, label = "unchanged", "&rarr;", "Unchanged"
        elif change["current_peak_bytes"] < change["previous_peak_bytes"]:
            state, arrow, label = "improved", "&uarr;", "Improved"
        else:
            state, arrow, label = "regressed", "&darr;", "Regressed"
        detail = "%s: %s before, %s now" % (label, previous, current)
    if not show_previous:
        detail = label
    detail += evidence
    reference = change["reference"]
    note = '%s vs %s' % (detail, reference["date"][:10])
    title = "%s; reference %s (%s); %d tasks" % (
        detail, reference["date"], reference["stamp"], change["tasks"])
    markup = ('<span class="trend %s" role="img" aria-label="%s" title="%s">%s</span>'
              % (state, html.escape(detail, quote=True), html.escape(title, quote=True), arrow))
    if show_previous:
        previous_title = "Previous measured value, %s (%s): %s" % (
            reference["date"], reference["stamp"], previous)
        markup = ('<span class="trend-pair">%s<small class="previous-value" title="%s">%s</small></span>'
                  % (markup, html.escape(previous_title, quote=True), previous))
    return markup, note


def competitive_stat(campaign, campaigns, tasks, lead, family, group, name):
    key = "ms" if family == "run" else "wall_ms"
    competitors = report_metrics.rivals(campaign, tasks, family, key, group)
    summary = report_metrics.comparison(campaign, tasks, lead, family, key, competitors)
    change = report_metrics.previous_change(campaign, campaigns, tasks, lead, family, key, group)
    arrow, _ = trend(change)
    if summary is None:
        value, description, note = "&mdash;", "No complete comparison", ""
    else:
        amount, unit = signed_duration(-summary["saved_ms"]).split(" ", 1)
        value = "%s<em>%s</em>" % (amount, unit)
        description = "Total time difference across %d workloads" % len(tasks)
        note = ('<b>%d ahead &middot; %d close &middot; %d behind</b><br>'
                'Swag total: %s<br>Non-Swag rival total: %s<br>Reference: %s' % (
                    summary["ahead"], summary["close"], summary["behind"],
                    duration(summary["total_ms"]),
                    duration(summary["rival_total_ms"]),
                    html.escape(runtime_label(summary["reference_runtime"]))))
    return ('<div class="stat %s"><div class="sl">%s</div><div class="sv">%s%s</div>'
            '<div class="sn">%s</div><div class="sn">%s</div></div>' % (
                lang_class(lead), name, value, arrow, description, note))


def geo(values):
    values = [v for v in values if v]
    return math.exp(sum(math.log(v) for v in values) / len(values)) if values else None


def linw(v, hi):
    return max(0.0, min(100.0, v / hi * 100.0))


def lin_axis(values, steps=4):
    """A round upper bound above the data, with evenly spaced ticks."""
    top = max([v for v in values if v] or [1])
    magnitude = 10 ** math.floor(math.log10(top))
    for factor in (1, 1.25, 1.5, 2, 2.5, 3, 4, 5, 7.5, 10):
        hi = factor * magnitude
        if hi >= top:
            break
    hi = math.ceil(hi / steps) * steps
    return hi, [hi * i / steps for i in range(steps + 1)]


# --------------------------------------------------------------------- charts
def chart(rows, hi, ticks, unit, tick_label=None):
    out = ['<figure class="chart">', '<div class="axis" aria-hidden="true">']
    for t in ticks:
        pos = linw(t, hi)
        out.append('<span class="tick" style="left:%.3f%%"><i></i><b>%s</b></span>'
                   % (pos, tick_label(t) if tick_label else "%g" % t))
    out.append("</div>")
    for rt, v, printed in rows:
        w = linw(v, hi)
        m = META[rt]
        out.append(
            '<div class="row %s"><div class="rl"><span class="runtime-name">%s <span class="mode">%s</span></span>%s</div>'
            '<div class="track"><span class="bar" style="width:%.3f%%"></span></div>'
            '<div class="rv">%s<em>%s</em></div></div>'
            % (lang_class(rt), m[1], m[2], runtime_badge(rt), w, printed, unit))
    out.append("</figure>")
    return "\n".join(out)


def ms_text(v):
    """Three significant digits: 21593, 1980, 45.0, 9.23."""
    if v is None:
        return "&mdash;"
    return "%.0f" % v if v >= 100 else ("%.1f" % v if v >= 10 else "%.2f" % v)


def simple_table(headers, rows):
    """rows: [label, cell, ...]; the first column is text, the others numbers."""
    out = ['<div class="table-wrap"><table><thead><tr>']
    out += ["<th>%s</th>" % h for h in headers]
    out.append("</tr></thead><tbody>")
    for r in rows:
        out.append("<tr><th>%s</th>%s</tr>" % (r[0], "".join("<td>%s</td>" % c for c in r[1:])))
    out.append("</tbody></table></div>")
    return "\n".join(out)


def performance_table(tasks, runtimes, value):
    """Keep each example's sorted times on one compact horizontal line."""
    out = ['<div class="table-wrap"><table class="performance"><thead><tr><th scope="col">task</th>']
    out.append('<th scope="col">Fastest &rarr; slowest &middot; measured time</th></tr></thead><tbody>')
    for task in tasks:
        values = [value(rt, task) for rt in runtimes]
        values = [v if v is not None and math.isfinite(v) and v > 0 else None for v in values]
        measured = sorted(zip(runtimes, values), key=lambda item: item[1] if item[1] is not None else math.inf)
        info = TASK_INFO.get(task)
        description = html.unescape(info) if info else task
        title = ' title="%s"' % html.escape(description, quote=True)
        out.append('<tr><th scope="row"%s><code>%s</code></th>' % (title, task))
        out.append('<td><ol>')
        for rt, result in measured:
            label = '<span class="speed-label">%s</span>' % runtime_badge(rt)
            name = html.escape(runtime_label(rt), quote=True)
            if result is None:
                out.append('<li class="%s" title="No measurement: %s">%s<span class="speed-value">&mdash;</span></li>'
                           % (lang_class(rt), name, label))
                continue
            out.append('<li class="%s" title="%s">%s<span class="speed-value">%s</span></li>'
                       % (lang_class(rt), name, label, duration(result)))
        out.append("</ol></td></tr>")
    out.append("</tbody></table></div>")
    return "\n".join(out)


def swag_comparison_table(campaign, tasks, family, campaigns=()):
    """Compare every competitor directly with Swag on the complete displayed panel."""
    key = "ms" if family == "run" else "wall_ms"
    leads = ["swag-release", "swag-fast-debug"]
    if family == "run":
        leads += ["swc-jit-release", "swc-jit-fast-debug"]
    headers = ["language / mode", "competitor total"]
    for lead in leads:
        values = report_metrics.measurements(campaign, tasks, lead, family, key)
        headers.append('%s %s<br><span class="comparison-total">total %s</span>' % (
            runtime_badge(lead), html.escape(runtime_label(lead)), duration(sum(values)) if values else "&mdash;"))

    rows = []
    for runtime, *_ in RUNTIMES:
        if runtime in history.TRACKED or not any(
                family in (campaign.get("tasks", {}).get(task, {}).get(runtime) or {}) for task in tasks):
            continue
        values = report_metrics.measurements(campaign, tasks, runtime, family, key)
        row = ['%s %s' % (runtime_badge(runtime), html.escape(runtime_label(runtime))),
               duration(sum(values)) if values else "&mdash;"]
        for lead in leads:
            summary = report_metrics.comparison(campaign, tasks, lead, family, key, [runtime])
            if summary is None:
                row.append("&mdash;")
                continue
            saved = summary["saved_ms"]
            state = "won" if saved > 0 else "lost" if saved < 0 else "tied"
            change = report_metrics.previous_change(campaign, campaigns, tasks, lead, family, key,
                                                     competitor=runtime)
            arrow, _ = trend(change, show_previous=False)
            row.append('<span class="comparison-gap %s">%s</span> %s' % (state, signed_duration(-saved), arrow))
        rows.append(row)
    return simple_table(headers, rows)


def execution_tables(tasks, runtimes, value):
    """Keep native and JIT/interpreted rankings separate."""
    parts = []
    for group, title in (("native", "Native / AOT"), ("jit", "JIT / interpreted")):
        selected = [rt for rt in runtimes if rt in history.RUN_GROUPS[group]]
        if selected:
            parts.append('<h3>%s</h3>%s' % (title, performance_table(tasks, selected, value)))
    return "\n".join(parts)


def spark(values):
    """A 140x22 trend line, one point per campaign, over a rule at 1.00."""
    pts = [(i, v) for i, v in enumerate(values) if v is not None]
    if not pts:
        return ""
    lo = min([v for _, v in pts] + [1.0])
    hi = max([v for _, v in pts] + [1.0])
    if hi - lo < 1e-9:
        lo, hi = lo - 0.05, hi + 0.05
    n = max(1, len(values) - 1)
    x = lambda i: 2 + i * 136.0 / n
    y = lambda v: 20 - (v - lo) / (hi - lo) * 18
    if len(pts) == 1:
        pts = [(0, pts[0][1]), (n, pts[0][1])]
    return ('<svg class="spark" viewBox="0 0 140 22" aria-hidden="true">'
            '<line x1="0" x2="140" y1="%.1f" y2="%.1f"/><polyline points="%s"/></svg>'
            % (y(1.0), y(1.0), " ".join("%.1f,%.1f" % (x(i), y(v)) for i, v in pts)))


# -------------------------------------------------------------- history plots
W, H = 760, 250
PAD_L, PAD_R, PAD_T, PAD_B = 52, 96, 16, 34


def nice_bounds(values):
    lo, hi = min(values), max(values)
    if hi == lo:
        return max(0.0, lo * 0.9), hi * 1.1 + (0.1 if hi == 0 else 0)
    span = hi - lo
    return lo - span * 0.25, hi + span * 0.25


def svg_lines(labels, series, unit, nd=2, zero=False, compact=False, band=None, width=None,
              bounds=None, reference=None):
    """series: list of (css class, legend text, [values, one per campaign]).

    `compact` draws at the size it will actually occupy, so the text is not shrunk
    to nothing by the browser scaling a wide viewBox into a narrow column.
    `band` is an optional [lo, hi] per campaign, drawn behind the curves: it is where
    code that did not change between two campaigns lands."""
    flat = [v for _, _, vs in series for v in vs if v is not None]
    flat += [v for pair in (band or []) if pair for v in pair]
    if not flat:
        return '<p class="cap">No data.</p>'

    if compact:
        W, H, PAD_L, PAD_R, PAD_T, PAD_B, rows = 520, 160, 44, 16, 12, 24, 3
    else:
        W, H, PAD_L, PAD_R, PAD_T, PAD_B, rows = globals()["W"], globals()["H"], 52, 96, 16, 34, 4
        if width:
            W, H = width, 200

    lo, hi = bounds if bounds is not None else nice_bounds(flat)
    if zero:
        lo = 0.0
    n = len(labels)
    span = W - PAD_L - PAD_R
    # A lone campaign sits in the middle rather than pinned to the left edge, where
    # it would read as the start of a line that does not exist yet.
    px = lambda i: PAD_L + (span / 2 if n == 1 else i * span / (n - 1))
    py = lambda v: PAD_T + (1 - (v - lo) / (hi - lo)) * (H - PAD_T - PAD_B)

    description = html.escape("Campaign history (%s): %s" % (html.unescape(unit), ", ".join(name for _, name, _ in series)), quote=True)
    o = ['<svg class="hchart%s" viewBox="0 0 %d %d" role="img" aria-label="%s" '
         'preserveAspectRatio="xMidYMid meet">' % (" compact" if compact else "", W, H, description)]

    for k in range(rows + 1):
        v = lo + (hi - lo) * k / rows
        y = py(v)
        o.append('<line class="hgrid" x1="%d" y1="%.1f" x2="%d" y2="%.1f"/>'
                 % (PAD_L, y, W - PAD_R, y))
        o.append('<text class="hlab" x="%d" y="%.1f" text-anchor="end">%s</text>'
                 % (PAD_L - 6, y + 3.5, fmt(v, nd)))

    if reference is not None:
        y = py(reference)
        o.append('<line class="hreference" x1="%d" y1="%.1f" x2="%d" y2="%.1f"/>'
                 % (PAD_L, y, W - PAD_R, y))
        o.append('<text class="hlab" x="%d" y="%.1f">%g ref</text>'
                 % (W - PAD_R + 8, y + 3.5, reference))

    if band:
        top = [(px(i), py(pair[1])) for i, pair in enumerate(band) if pair]
        bottom = [(px(i), py(pair[0])) for i, pair in enumerate(band) if pair]
        if len(top) > 1:
            pts = " ".join("%.1f,%.1f" % p for p in top + bottom[::-1])
            o.append('<polygon class="hband" points="%s"/>' % pts)

    # A few labels, always the first and the last, so commits never overlap.
    step = max(1, -(-(n - 1) // (4 if width else 7)))
    shown = [0, n - 1] if compact else sorted({i for i in range(0, n, step)
                                               if n - 1 - i >= step} | {n - 1})
    for i, lab in enumerate(labels):
        if i not in shown:
            continue
        anchor = "middle"
        if compact:
            anchor = "start" if i == 0 else "end"
        o.append('<text class="hlab" x="%.1f" y="%d" text-anchor="%s">%s</text>'
                 % (px(i), H - 8, anchor, lab))

    ends = []
    for cls, name, vs in series:
        pts = [(px(i), py(v)) for i, v in enumerate(vs) if v is not None]
        if not pts:
            continue
        if len(pts) == 1:
            o.append('<circle class="hdot %s" cx="%.1f" cy="%.1f" r="4"/>' % (cls, pts[0][0], pts[0][1]))
        else:
            d = " ".join("%.1f,%.1f" % p for p in pts)
            o.append('<polyline class="hline %s" points="%s"/>' % (cls, d))
            # Past a dozen campaigns the dots add weight and no reading.
            for x, y in (pts if len(pts) <= 12 else []):
                o.append('<circle class="hdot %s" cx="%.1f" cy="%.1f" r="2.6"/>' % (cls, x, y))
        if name:
            ends.append([pts[-1][1], pts[-1][0], cls, name])

    # Direct labels replace a legend box, so they must not sit on top of each other
    # when two series land on almost the same value.
    ends.sort()
    for i in range(1, len(ends)):
        if ends[i][0] - ends[i - 1][0] < 12:
            ends[i][0] = ends[i - 1][0] + 12
    for y, x, cls, name in ends:
        o.append('<text class="hend %s" x="%.1f" y="%.1f">%s</text>' % (cls, x + 8, y + 3.5, name))

    if not compact:
        o.append('<text class="hunit" x="%d" y="%d">%s</text>' % (PAD_L - 8, PAD_T - 4, unit))
    o.append("</svg>")
    return "\n".join(o)


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


def allocator_section(entries, current):
    """Show current times and peaks, then the historical competitor ratios."""
    alloc = (current or {}).get("allocator")
    if not alloc:
        return '<p class="cap">No allocator measurement in this campaign.</p>'

    def ns(v):
        return fmt(v, 0) if v is not None and v >= 100 else fmt(v, 1)

    rows = []
    overview = ['<div class="alloc-grid">']
    known = dict(ALLOC_WORKLOADS)
    names = [w for w, _ in ALLOC_WORKLOADS if w in alloc["workloads"]]
    names += [w for w in alloc["workloads"] if w not in known]
    for workload in names:
        rec = alloc["workloads"][workload]
        description = html.escape(html.unescape(known.get(workload, "")), quote=True)
        overview.append('<div class="alloc-workload"><h3 title="%s">%s</h3>' % (description, workload))
        timings = [(name, rec.get(key)) for name, key in
                   (("Swag", "swag_ns"), ("mimalloc", "mimalloc_ns"), ("CRT", "crt_ns"))]
        timings = [(name, elapsed) for name, elapsed in timings
                   if elapsed is not None and math.isfinite(elapsed) and elapsed > 0]
        longest = max((elapsed for _, elapsed in timings), default=1)
        for name, elapsed in sorted(timings, key=lambda item: item[1]):
            overview.append('<div class="alloc-row alloc-%s" title="%s ns/op">'
                            '<span>%s</span><span class="alloc-track"><i style="width:%.4f%%"></i></span>'
                            '<span class="num">%s ns/op</span></div>'
                            % (name.lower(), ns(elapsed), name, 100 * elapsed / longest, ns(elapsed)))
        overview.append('</div>')
        rows.append(['%s <span class="mode">%s</span>' % (workload, known.get(workload, "")),
                     ns(rec.get("swag_ns")), ns(rec.get("mimalloc_ns")), ns(rec.get("crt_ns")),
                     fmt(rec.get("swag_ws_mb"), 1), fmt(rec.get("mimalloc_ws_mb"), 1),
                     fmt(rec.get("crt_ws_mb"), 1)])
    overview.append('</div>')
    parts = ["\n".join(overview), '<details><summary>Allocator times and peak memory</summary>',
             '<p class="cap">Measured time per operation and peak working set for each allocator.</p>',
             simple_table(["workload", "Swag (ns/op)", "mimalloc (ns/op)", "CRT (ns/op)",
                           "Swag (MiB)", "mimalloc (MiB)", "CRT (MiB)"], rows), '</details>']

    measured = [e for e in entries if e.get("allocator")]
    if measured:
        labels = [e["meta"].get("commit") or e["meta"]["date"][:10] for e in measured]
        parts.append('<details class="alloc-history"><summary>Allocator history vs competitors</summary>')
        parts.append('<p class="cap">Geometric mean of Swag / competitor measured in the same rounds. '
                     '1 = parity; below 1 favours Swag. Solid lines: time; dashed lines: peak working set.</p>')
        parts.append(svg_lines(labels, [
            ("h-a", "time / mimalloc", [e["allocator"].get("geo_vs_mimalloc") for e in measured]),
            ("h-b", "WS / mimalloc", [e["allocator"].get("geo_ws_vs_mimalloc") for e in measured]),
            ("h-c", "time / CRT", [e["allocator"].get("geo_vs_crt") for e in measured]),
            ("h-d", "WS / CRT", [e["allocator"].get("geo_ws_vs_crt") for e in measured]),
        ], "&times;"))
        parts.append('</details>')
    return "\n".join(parts)


def history_section(entries):
    if not entries:
        return '<p class="cap">No recorded campaign.</p>'

    labels = [e["meta"].get("commit") or e["meta"]["date"][:10] for e in entries]

    def series(field):
        out = []
        for rt, name, cls in HIST_SERIES:
            vals = [(e["runtimes"].get(rt) or {}).get(field) for e in entries]
            if any(v is not None for v in vals):
                out.append((cls, name, vals))
        return out

    def null_band(family, task=None):
        out = []
        for e in entries:
            null = (e.get("null") or {}).get(family) or {}
            out.append(null.get("tasks", {}).get(task) if task else null.get("geo"))
        return out

    def half_width(bands):
        """Typical distance from 1.00 an unchanged runtime reaches, in percent. The
        reference campaign is exactly 1.00 by construction and is not evidence."""
        widths = sorted(w for w in (max(abs(pair[1] - 1.0), abs(1.0 - pair[0]))
                                    for pair in bands if pair) if w > 0)
        return 100.0 * (widths[len(widths) // 2] if widths else 0.0)

    progress_groups = [(name, cls, history.progress_series(entries, rt, family))
                       for rt, family, name, cls in
                       (("swag-release", "run", "SW native progress", "h-a"),
                        ("swc-jit-release", "run", "SJ JIT progress", "h-b"),
                        ("swag-release", "build", "Build progress", "h-a"))]
    scores = [score for _, _, progress in progress_groups for score in progress["scores"].values()
              if score is not None]
    lo, hi = nice_bounds(scores + [100])
    score_bounds = max(0, lo), hi
    parts = ['<div class="grid2">']
    for name, cls, progress in progress_groups:
        baseline = progress["baseline"]
        parts.append('<div><h3>%s</h3>' % name)
        if baseline:
            points = [(e, progress["scores"].get(e["meta"]["stamp"])) for e in entries]
            first = next(i for i, (_, score) in enumerate(points) if score is not None)
            points = points[first:]
            parts.append('<p class="cap">100 = %s &middot; <code>%s</code>. Higher is faster.</p>'
                         % (baseline["date"][:10], baseline.get("commit") or "?"))
            parts.append(svg_lines([e["meta"].get("commit") or e["meta"]["date"][:10] for e, _ in points],
                                   [(cls, "", [score for _, score in points])], "score", nd=0, width=520,
                                   bounds=score_bounds, reference=100))
        else:
            parts.append('<p class="cap">No clean campaign covers the complete progress panel yet.</p>')
        parts.append('</div>')
    parts.append('</div><details><summary>Competitor ratios and original-panel indices</summary>')
    parts.append('<div class="small-mult">')
    for field, name, nd, unit, cls in (
            ("exec_native_vs_best", "SW native time / native per-task best (lower is better)", 2, "&times;", "h-a"),
            ("exec_jit_vs_best", "SJ JIT time / JIT + interpreted per-task best (lower is better)", 2, "&times;", "h-b"),
            ("build_speedup", "build speedup vs fastest rival (higher is better)", 2, "&times;", "h-a")):
        vals = [e.get("headline", {}).get(field) for e in entries]
        parts.append('<div class="sm"><b>%s</b>%s</div>'
                     % (name, svg_lines(labels, [(cls, "", vals)], unit, nd=nd, compact=True)))
    parts.append("</div>")

    parts.append('<div class="grid2"><div>')
    parts.append('<h3>Execution time index</h3><p class="cap">Baseline = 1. Lower is better.</p>')
    parts.append(svg_lines(labels, series("run_geo_index"), "&times;", band=null_band("run"),
                             width=520))
    parts.append("</div><div>")
    parts.append('<h3>Build time index</h3><p class="cap">Baseline = 1. Lower is better.</p>')
    parts.append(svg_lines(labels, series("build_geo_index"), "&times;", band=null_band("build"),
                             width=520))
    parts.append("</div><div>")
    parts.append('<h3>Peak compiler memory (MiB)</h3>')
    parts.append(svg_lines(labels, [(c, n, [e["runtimes"].get(rt, {}).get("build_peak_mb")
                                            for e in entries])
                                    for rt, n, c in HIST_SERIES
                                    if any(e["runtimes"].get(rt, {}).get("build_peak_mb")
                                           for e in entries)],
                           "MiB", nd=0, width=520))
    parts.append("</div></div></details>")

    # One row per task and per edit-loop workload: the latest index, its resolution, and
    # the trend. Rows, not charts, so the section grows by one line per task.
    late = entries[-1].get("context", {}).get("task_baselines", {})
    rows = []
    for tid in tc.TASKS:
        vals = [e["runtimes"].get("swag-release", {}).get("run_index", {}).get(tid)
                for e in entries]
        if not any(v is not None for v in vals):
            continue
        last = next((v for v in reversed(vals) if v is not None), None)
        width = half_width(null_band("run", tid))
        rows.append(["<code>%s</code>" % tid, fmt(last),
                     "&plusmn;%.0f&nbsp;%%" % width if width else "&mdash;",
                     late.get(tid, "&mdash;"), spark(vals)])
    for wid, name, _ in LOOP:
        vals = [((e.get("loop") or {}).get(wid) or {}).get("index") for e in entries]
        if not any(v is not None for v in vals):
            continue
        since = next((((e.get("loop") or {}).get(wid) or {}).get("since")
                      for e in reversed(entries)
                      if ((e.get("loop") or {}).get(wid) or {}).get("since")), None)
        last = next((v for v in reversed(vals) if v is not None), None)
        rows.append([name, fmt(last), "&mdash;", since or "&mdash;", spark(vals)])
    parts.append("<details><summary>Swag release per task and edit-build workload</summary>")
    parts.append('<p class="cap">Adjusted index: 1 at the reference campaign, '
                 'or the first campaign measuring that workload. Lower is better.</p>')
    parts.append(simple_table(["workload", "index", "resolution", "since", "trend"], rows))
    parts.append('</details>')

    journal = []
    for e in list(reversed(entries))[:JOURNAL_ROWS]:
        m = e["meta"]
        rel = e["runtimes"].get("swag-release", {})
        context = e.get("context", {})
        drift = e.get("machine_spread_pct")
        if drift is None:
            drift = abs(e.get("drift_pct") or 0.0)
        journal.append([
            "<code>%s%s</code>" % (m.get("commit") or "?", "*" if m.get("dirty") else ""),
            m["date"][:10],
            fmt(rel.get("run_geo_adjusted_ms")),
            fmt(rel.get("build_geo_adjusted_ms"), 0),
            fmt(rel.get("build_peak_mb"), 0),
            signed_pct(context.get("run_factor")),
            signed_pct(context.get("build_factor")),
            "<b>%s</b>" % fmt(drift, 1) if drift > DRIFT_LIMIT else fmt(drift, 1),
            '<span class="l">%s</span>' % (m.get("label") or ""),
        ])
    parts.append('<details><summary>Recent campaigns</summary>')
    parts.append('<p class="cap">%d latest campaigns. * modified source tree.</p>'
                 % len(journal))
    parts.append(simple_table(["commit", "date", "exec (ms)", "build (ms)", "MiB",
                               "exec context", "build context", "probe spread %", "note"], journal))
    parts.append('</details>')
    return "\n".join(parts)


# --------------------------------------------------------------- repo README
WORDS = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight",
         "nine", "ten", "eleven", "twelve"]


def spelled(n):
    """Prose counts a handful of programs in words, not digits."""
    return WORDS[n].capitalize() if n < len(WORDS) else str(n)


def md_table(header, rows):
    out = ["| %s |" % " | ".join(header), "|%s|" % "|".join(["---"] * len(header))]
    for row in rows:
        out.append("| %s |" % " | ".join(row))
    return "\n".join(out)


def write_repo_readme(block):
    """Replace the generated block in the repository README, in place."""
    if not os.path.exists(REPO_README):
        return False
    with open(REPO_README, "rb") as f:
        raw = f.read()
    eol = b"\r\n" if raw.count(b"\r\n") > raw.count(b"\n") // 2 else b"\n"
    text = raw.decode("utf-8").replace("\r\n", "\n")
    start, end = text.find(README_BEGIN), text.find(README_END)
    if start < 0 or end < 0 or end < start:
        print("WARNING repository README has no %s/%s markers, left untouched"
              % (README_BEGIN, README_END))
        return False
    merged = (text[:start + len(README_BEGIN)] + "\n" + block.strip("\n") + "\n"
              + text[end:])
    with open(REPO_README, "wb") as f:
        f.write(merged.encode("utf-8").replace(b"\n", eol))
    return True


# ----------------------------------------------------------------------- main
def main():
    R = latest_campaign("run")
    B = latest_campaign("build")
    T = R["tasks"]
    BT = B["tasks"]
    entries = history.rebuild()

    # The tasks of the published campaigns, in toolchains order: a task added since the
    # last campaign appears once a campaign has measured it.
    TASK_IDS = [t for t in tc.TASKS if t in T and t in BT]
    execution = {group: history.execution_ratios(T, TASK_IDS, group) for group in history.RUN_GROUPS}
    gm = {rt: ratio for group in execution.values() for rt, ratio in group.items()}
    bgm = history.ratios_to_best(BT, TASK_IDS, "build", "wall_ms")
    present = [r[0] for r in RUNTIMES if r[0] in gm]
    aot = [r[0] for r in RUNTIMES if r[0] in bgm]

    def ms(rt, task):
        rec = (T[task].get(rt) or {}).get("run") or {}
        return rec.get("ms") if not rec.get("error") else None

    def build(rt, task, key):
        rec = (BT[task].get(rt) or {}).get("build") or {}
        return rec.get(key) if not rec.get("error") else None

    bmem = {r: max(values) / 1048576 for r in aot
            if (values := report_metrics.measurements(B, TASK_IDS, r, "build", "peak_bytes"))}
    exekb = {r: geo([build(r, t, "exe_bytes") for t in TASK_IDS]) / 1024.0 for r in aot}
    rmem = {r: max(values) / 1048576 for r in present
            if (values := report_metrics.measurements(R, TASK_IDS, r, "run", "peak_bytes"))}

    campaigns = history.load_results()
    build_summary = report_metrics.comparison(
        B, TASK_IDS, "swag-release", "build", "wall_ms",
        report_metrics.rivals(B, TASK_IDS, "build", "wall_ms"))
    build_gap = total_time_gap(build_summary)
    memory_change = report_metrics.previous_change(
        B, campaigns, TASK_IDS, "swag-release", "build", "peak_bytes", peak=True)
    memory_arrow, _ = trend(memory_change)
    memory_value = "%d<em>MiB</em>" % round(bmem["swag-release"]) if "swag-release" in bmem else "&mdash;"
    execution_stats = "".join([
        competitive_stat(R, campaigns, TASK_IDS, "swag-release", "run", "native", "Native execution &middot; release"),
        competitive_stat(R, campaigns, TASK_IDS, "swag-fast-debug", "run", "native", "Native execution &middot; devmode"),
        competitive_stat(R, campaigns, TASK_IDS, "swc-jit-release", "run", "jit", "JIT / interpreted execution"),
    ])
    build_stats = "".join([
        competitive_stat(B, campaigns, TASK_IDS, "swag-release", "build", None, "Compilation"),
        ('<div class="stat l-swag"><div class="sl">Peak compiler memory</div>'
         '<div class="sv">%s%s</div>'
         '<div class="sn">Largest Swag release build working set</div></div>'
         % (memory_value, memory_arrow)),
    ])

    run_totals = {rt: sum(values) for rt in present
                  if (values := report_metrics.measurements(R, TASK_IDS, rt, "run", "ms"))}
    # Include partial runtimes in per-example rankings; only their missing cells are blank.
    run_runtimes = [rt for rt, *_ in RUNTIMES if any("run" in (T[t].get(rt) or {}) for t in TASK_IDS)]
    build_runtimes = [rt for rt, *_ in RUNTIMES if any("build" in (BT[t].get(rt) or {}) for t in TASK_IDS)]
    ex_performance = execution_tables(TASK_IDS, run_runtimes, ms)

    def build_ms(r, t):
        if t != "hello":
            return build(r, t, "wall_ms")
        rec = B["hello_build"].get(r) or {}
        return rec.get("wall_ms") if not rec.get("error") else None

    bu_performance = performance_table(TASK_IDS + ["hello"], build_runtimes, build_ms)

    run_entry = next((e for e in entries if e["meta"].get("stamp") == R["meta"].get("stamp")), None)
    allocator = allocator_section(entries, run_entry)

    me_hi, me_ticks = lin_axis(list(bmem.values()))
    me_chart = chart(sorted(((r, v, fmt(v, 1)) for r, v in bmem.items()), key=lambda x: x[1]),
                     me_hi, me_ticks, "MiB")
    rm_hi, rm_ticks = lin_axis(list(rmem.values()))
    rm_chart = chart(sorted(((r, v, fmt(v, 1)) for r, v in rmem.items()), key=lambda x: x[1]),
                     rm_hi, rm_ticks, "MiB")

    hr = R["hello_run"]
    startup = [(r, hr[r].get("first_stdout_ms") or hr[r].get("wall_ms"))
               for r in hr if r in META]
    startup = [(runtime, elapsed) for runtime, elapsed in startup if elapsed is not None]
    st_hi, st_ticks = lin_axis([elapsed for _, elapsed in startup])
    st_chart = chart(sorted(((runtime, elapsed, ms_text(elapsed)) for runtime, elapsed in startup),
                            key=lambda x: x[1]),
                     st_hi, st_ticks, "ms")
    sz_hi, sz_ticks = lin_axis([exekb[r] for r in aot])
    sz_chart = chart(sorted(((r, exekb[r], fmt(exekb[r], 0)) for r in aot), key=lambda x: x[1]),
                     sz_hi, sz_ticks, "KiB")

    m = R["meta"]
    settings = m.get("settings") or {}

    # ---------------------------------------------------- repository README block
    ex_cols = [("swag-release", "swc"), ("swc-jit-release", "swc JIT"),
               ("cpp-clang-cl", "clang-cl"), ("rust", "rustc"),
               ("zig", "Zig"), ("d-ldc", "D (LDC)"), ("odin", "Odin"),
               ("go", "Go"), ("java-hotspot", "Java HotSpot"),
               ("luajit2.1", "LuaJIT"), ("node20", "Node 20"),
               ("python3.12", "CPython 3.12"), ("php", "PHP"), ("php-jit", "PHP JIT"), ("ruby", "Ruby")]
    bu_cols = [("swag-release", "swc"), ("cpp-clang-cl", "clang-cl"), ("rust", "rustc"),
               ("zig", "Zig"), ("d-ldc", "D (LDC)"), ("odin", "Odin"), ("go", "Go"),
               ("java-hotspot", "javac (bytecode)")]
    ex_cols = [c for c in ex_cols if c[0] in present]
    bu_cols = [c for c in bu_cols if c[0] in aot]
    readme = [
        "",
        "%s programs implementing the same workloads in every language. Systems-language ports "
        "use explicit byte maps and sorting; dynamic ports also use their runtime's containers. " % spelled(len(TASK_IDS)),
        "The numeric kernels, input sizes and checksums match across ports. All ports "
        "print the same checksum, while their required imports and runtime interfaces differ.",
        "",
        "Milliseconds, lower is better. `swc` in `release`, `clang-cl /O2`,",
        "`rustc -C opt-level=3 -C codegen-units=1`, one campaign on a Windows laptop",
        "([`%s`](bench/results/%s.json))." % (m["stamp"], m["stamp"]),
        "",
        "**Execution.** The same program compiled natively, then run again through the "
        "compiler's JIT, then",
        "against the other runtimes:",
        "",
        md_table(["program"] + [name for _, name in ex_cols],
                 [["`%s`" % t] + [fmt(ms(r, t), 1) for r, _ in ex_cols] for t in TASK_IDS]),
        "",
        "**Compilation**, from source to a runnable artifact (Java: bytecode), including each port's required "
        "imports and runtime interfaces:",
        "The programs have matching behavior, but these numbers do not isolate compiler speed "
        "because library work and build pipelines differ between languages. The `hello` program "
        "is a separate small workload, not a common overhead to subtract.",
        "",
        md_table(["program"] + [name for _, name in bu_cols],
                 [["`%s`" % t] + [fmt(build(r, t, "wall_ms"), 1) for r, _ in bu_cols]
                  for t in TASK_IDS]),
        "",
        "Total native execution time across those %s programs: **%s** for Swag release, "
        "**%s** for Swag devmode, and **%s** for clang-cl."
        % (spelled(len(TASK_IDS)).lower(), duration(run_totals.get("swag-release")),
           duration(run_totals.get("swag-fast-debug")), duration(run_totals.get("cpp-clang-cl"))),
        "The total build-time difference vs the non-Swag compiler with the smallest total is "
        "**%s**. The raw table above includes each recipe's imports and linking or bytecode generation."
        % build_gap,
        "A hello world compiles and links in %s ms."
        % fmt((B["hello_build"].get("swag-release") or {}).get("wall_ms"), 0),
        "",
        "> [!NOTE]",
        "> Raw milliseconds are not comparable between campaigns — the same machine drifts by "
        "more than ten",
        "> percent between sessions — so the recorded history normalizes every measurement "
        "against the measured control",
        "> runtimes, and states the resolution below which it can see nothing at all. See "
        "[bench/](bench) for",
        "> the method, the supported runtimes, and the rules that keep the numbers honest.",
        "",
    ]
    if R["meta"].get("stamp") == B["meta"].get("stamp") and write_repo_readme("\n".join(readme)):
        print("repository README refreshed from campaign %s" % m["stamp"])

    subs = {
        "{{execution_stats}}": execution_stats, "{{build_stats}}": build_stats,
        "{{swag_execution_comparison}}": swag_comparison_table(R, TASK_IDS, "run", campaigns),
        "{{swag_build_comparison}}": swag_comparison_table(B, TASK_IDS, "build", campaigns),
        "{{progress_version}}": str(history.PROGRESS_VERSION),
        "{{progress_tasks}}": str(len(history.PROGRESS_TASKS)),
        "{{runtime_legend}}": runtime_legend([r[0] for r in RUNTIMES if r[0] in set(run_runtimes + build_runtimes)]),
        "{{ex_performance}}": ex_performance, "{{bu_performance}}": bu_performance,
        "{{allocator}}": allocator,
        "{{me_chart}}": me_chart, "{{rm_chart}}": rm_chart,
        "{{st_chart}}": st_chart, "{{sz_chart}}": sz_chart,
        "{{history}}": history_section(entries),
        "{{machine_spread}}": fmt(R["calibration"].get("spread_pct"), 1),
        "{{calib_start}}": fmt(R["calibration"]["start"], 1),
        "{{calib_end}}": fmt(R["calibration"]["end"], 1),
        "{{provenance}}": ("modified source tree at measurement time" if m.get("dirty")
                           else "Release x64 binary from this checkout"),
        "{{commit}}": m.get("commit") or "?",
        "{{subject}}": (m.get("subject") or "").replace("&", "&amp;").replace("<", "&lt;")[:90],
        "{{date}}": m["date"][:10],
        "{{run_date}}": R["meta"]["date"][:10],
        "{{build_date}}": B["meta"]["date"][:10],
        "{{run_commit}}": R["meta"].get("commit") or "?",
        "{{build_commit}}": B["meta"].get("commit") or "?",
        "{{campaigns}}": str(len(entries)),
        "{{protocol}}": str(m.get("protocol", "?")),
        "{{pin_mask}}": "<code>%s</code>" % settings.get("pin_mask", "?"),
        "{{pin_cores}}": str(settings.get("pin_cores", "?")),
        "{{budget_ms}}": str(settings.get("budget_ms", "?")),
        "{{min_reps}}": str(settings.get("min_reps", "?")),
        "{{max_reps}}": str(settings.get("max_reps", "?")),
        "{{drift_limit}}": "%.0f" % DRIFT_LIMIT,
        "{{build_control_limit}}": "%.0f" % history.BUILD_CONTROL_SPREAD_LIMIT_PCT,
        "{{ntasks}}": str(len(TASK_IDS)),
        "{{nruntimes}}": str(len(present)),
        "{{skipped}}": (", ".join(R.get("skipped") or []) or "none"),
    }

    with open(TEMPLATE, encoding="utf-8") as template:
        page = template.read()
    for k, v in subs.items():
        page = page.replace(k, v)
    import re
    left = set(re.findall(r"\{\{\w+\}\}", page))
    if left:
        print("WARNING unresolved placeholders:", left)
    with open(OUTFILE, "w", encoding="utf-8", newline="\r\n") as f:
        f.write(page)
    print("written bench.html (%d bytes, %d campaign(s) in history)" % (len(page), len(entries)))


if __name__ == "__main__":
    main()
