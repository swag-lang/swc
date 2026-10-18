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

# One colour per runtime, shared by every chart bar and ranking entry; no two runtimes share
# one, swag's four variants included.
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
def chart(rows, hi, ticks, unit):
    out = ['<figure class="chart">', '<div class="axis" aria-hidden="true">']
    for t in ticks:
        pos = linw(t, hi)
        out.append('<span class="tick" style="left:%.3f%%"><i></i><b>%g</b></span>' % (pos, t))
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


def speed_text(speed):
    """Keep rounding from presenting a slower measurement as an exact best."""
    if speed == 100:
        return "100"
    if speed >= 99.95:
        return "&lt;100"
    return "&lt;0.1" if speed < 0.1 else fmt(speed, 1)


def simple_table(headers, rows):
    """rows: [label, cell, ...]; the first column is text, the others numbers."""
    out = ['<div class="table-wrap"><table><thead><tr>']
    out += ["<th>%s</th>" % h for h in headers]
    out.append("</tr></thead><tbody>")
    for r in rows:
        out.append("<tr><th>%s</th>%s</tr>" % (r[0], "".join("<td>%s</td>" % c for c in r[1:])))
    out.append("</tbody></table></div>")
    return "\n".join(out)


def _cell_class(rt, previous, *extra):
    cls = [c for c in extra if c]
    if rt == "swag-release":
        cls.append("sw")
    if previous and META[rt][3] != META[previous][3]:
        cls.append("gap")
    return ' class="%s"' % " ".join(cls) if cls else ""


def matrix(tasks, runtimes, value, show, footer=None):
    """One task per row, one runtime per column; the best of each row in bold.

    Tasks grow downwards, so adding one adds a row and moves nothing else."""
    out = ['<div class="table-wrap"><table class="matrix"><thead><tr><th>task</th>']
    for i, rt in enumerate(runtimes):
        out.append('<th scope="col"%s>%s</th>'
                   % (_cell_class(rt, runtimes[i - 1] if i else None), runtime_badge(rt)))
    out.append("</tr></thead><tbody>")
    for task in tasks:
        values = [value(rt, task) for rt in runtimes]
        best = min((v for v in values if v is not None), default=None)
        info = TASK_INFO.get(task)
        title = ' title="%s"' % html.escape(html.unescape(info), quote=True) if info else ""
        out.append("<tr><th%s><code>%s</code></th>" % (title, task))
        for i, (rt, v) in enumerate(zip(runtimes, values)):
            best_cls = "best" if v is not None and v == best else ""
            out.append("<td%s>%s</td>"
                       % (_cell_class(rt, runtimes[i - 1] if i else None, best_cls), show(v)))
        out.append("</tr>")
    out.append("</tbody>")
    if footer:
        label, values, show_footer = footer
        out.append("<tfoot><tr><th>%s</th>" % label)
        for i, rt in enumerate(runtimes):
            out.append("<td%s>%s</td>" % (_cell_class(rt, runtimes[i - 1] if i else None),
                                          show_footer(values.get(rt))))
        out.append("</tr></tfoot>")
    out.append("</table></div>")
    return "\n".join(out)


def performance_table(tasks, runtimes, value, display):
    """Sort runtimes per task, with linear speed bars: best time / time, best = 100%.

    Equal bar lengths mean equal speeds, regardless of how many competitors fall between
    two measurements. Missing and non-positive times cannot define the reference.
    """
    lead = next((rt for rt in ("swag-release", "swc-jit-release") if rt in runtimes), None)
    out = ['<div class="table-wrap"><table class="performance"><thead><tr><th scope="col">task</th>']
    if lead:
        out.append('<th scope="col">Swag time<br>vs group best</th>')
    out.append('<th scope="col">Faster &rarr; slower &middot; best speed = 100%</th></tr></thead><tbody>')
    for task in tasks:
        values = [value(rt, task) for rt in runtimes]
        values = [v if v is not None and math.isfinite(v) and v > 0 else None for v in values]
        best = min((v for v in values if v is not None), default=None)
        measured = sorted(zip(runtimes, values), key=lambda item: item[1] if item[1] is not None else math.inf)
        info = TASK_INFO.get(task)
        title = ' title="%s"' % html.escape(html.unescape(info), quote=True) if info else ""
        out.append('<tr><th scope="row"%s><code>%s</code></th>' % (title, task))
        lead_time = dict(measured).get(lead)
        gap = "&mdash;"
        if lead_time and best:
            extra_time = 100 * (lead_time / best - 1)
            gap = "best" if lead_time == best else ("+%.2g%%" if extra_time < 0.1 else "+%.1f%%") % extra_time
        if lead:
            out.append('<td class="swag-gap">%s</td>' % gap)
        out.append('<td><ol>')
        for rt, result in measured:
            if result is None or best is None:
                out.append('<li class="%s" title="No measurement"><span class="speed-label">'
                           '%s<span>&mdash;</span></span></li>' % (lang_class(rt), runtime_badge(rt)))
                continue
            speed = 100 * best / result
            shown = speed_text(speed)
            detail = html.escape(html.unescape(
                "%s: %s ms; %s times the best time; +%.3g%% time vs best"
                % (runtime_label(rt), display(result), "%.4g" % (result / best), 100 * (result / best - 1))), quote=True)
            out.append('<li class="%s" title="%s"><span class="speed-label">%s'
                       '<span class="speed-value">%s%%</span></span>'
                       '<span class="speed-track" aria-hidden="true">'
                       '<span style="width:%.4f%%"></span></span></li>'
                       % (lang_class(rt), detail, runtime_badge(rt), shown, speed))
        out.append("</ol></td></tr>")
    out.append("</tbody></table></div>")
    return "\n".join(out)


def comparison_table(tasks, groups, value, reference):
    """Compare complete runtimes with Swag release over the same tasks.

    Ratios are geometric means of competitor time / Swag release time. Values above
    one mean the competitor is slower; values below one mean it is faster. Each group
    is ordered from the fastest competitor to the slowest, without ordinal ranks.
    """
    out = ['<div class="table-wrap"><table class="ranked"><tbody>']
    for title, runtimes in groups:
        ratios = []
        for rt in runtimes:
            if rt == reference:
                continue
            pairs = [(value(rt, task), value(reference, task)) for task in tasks]
            if any(not competitor or competitor <= 0 or not swag or swag <= 0
                   for competitor, swag in pairs):
                continue
            ratios.append((rt, geo([competitor / swag for competitor, swag in pairs])))
        ratios.sort(key=lambda item: item[1])
        out.append('<tr><th>%s</th><td><ol>' % title)
        for rt, ratio in ratios:
            out.append('<li class="%s">%s<i>%s&nbsp;&times;</i></li>'
                       % (lang_class(rt), runtime_badge(rt), fmt(ratio)))
        out.append("</ol></td></tr>")
    out.append("</tbody></table></div>")
    return "\n".join(out)


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
    """The latest allocator measurement, then how Swag's ratios to its competitors moved."""
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
        best = min((elapsed for _, elapsed in timings), default=None)
        for name, elapsed in sorted(timings, key=lambda item: item[1]):
            speed = 100 * best / elapsed
            overview.append('<div class="alloc-row alloc-%s" title="%s ns/op">'
                            '<span>%s</span><span class="alloc-track"><i style="width:%.4f%%"></i></span>'
                            '<span class="num">%s%%</span></div>'
                            % (name.lower(), ns(elapsed), name, speed, speed_text(speed)))
        overview.append('</div>')
        rows.append(['%s <span class="mode">%s</span>' % (workload, known.get(workload, "")),
                     ns(rec.get("swag_ns")), ns(rec.get("mimalloc_ns")), ns(rec.get("crt_ns")),
                     fmt(rec.get("vs_mimalloc")), fmt(rec.get("vs_crt")),
                     "%s / %s / %s" % (fmt(rec.get("swag_ws_mb"), 1), fmt(rec.get("mimalloc_ws_mb"), 1),
                                       fmt(rec.get("crt_ws_mb"), 1))])
    rows.append(["geometric mean", "", "", "",
                 fmt(alloc.get("geo_vs_mimalloc")), fmt(alloc.get("geo_vs_crt")),
                 "&times;%s / &times;%s" % (fmt(alloc.get("geo_ws_vs_mimalloc")), fmt(alloc.get("geo_ws_vs_crt")))])
    overview.append('</div>')
    parts = ["\n".join(overview), '<details><summary>Allocator times, ratios and working set</summary>',
             '<p class="cap">Time and working-set ratios are Swag / competitor; lower is better. '
             'Working set is listed as Swag / mimalloc / CRT in MiB.</p>',
             simple_table(["workload", "Swag (ns)", "mimalloc (ns)", "CRT (ns)", "swag / mimalloc",
                           "swag / CRT", "peak WS (MiB)"], rows), '</details>']

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
            ("exec_jit_vs_best", "SJ JIT time / JIT per-task best (lower is better)", 2, "&times;", "h-b"),
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

    bgeo = {r: geo([build(r, t, "wall_ms") for t in TASK_IDS]) for r in aot}
    bmem = {r: max(build(r, t, "peak_bytes") or 0 for t in TASK_IDS) / 1048576.0 for r in aot}
    exekb = {r: geo([build(r, t, "exe_bytes") for t in TASK_IDS]) / 1024.0 for r in aot}
    rmem = {r: max(((T[t].get(r) or {}).get("run") or {}).get("peak_bytes") or 0
                   for t in TASK_IDS) for r in present}

    build_speedup = history.build_speedup(BT, TASK_IDS)

    def stat(value, unit, name, runtime="swag-release", note=""):
        return ('<div class="stat %s"><div class="sv">%s<em>%s</em></div>'
                '<div class="sl">%s</div><div class="sn">%s</div></div>'
                % (lang_class(runtime), value, unit, name, note))

    def progress_stat(runtime, family, campaign, name):
        progress = history.progress_series(entries, runtime, family)
        value = progress["scores"].get(campaign["meta"]["stamp"])
        baseline = progress["baseline"]
        note = ("100 at %s &middot; %s" % (baseline["date"][:10], baseline.get("commit") or "?")
                if baseline else "Waiting for a complete, reproducible reference")
        return stat(fmt(value, 1), "pts", name, runtime, note)

    stats = "".join([
        progress_stat("swag-release", "run", R, "SW native progress"),
        progress_stat("swc-jit-release", "run", R, "SJ JIT progress"),
        progress_stat("swag-release", "build", B, "Build progress"),
        stat("%d" % round(bmem["swag-release"]), "MiB", "peak compiler memory"),
    ])

    native_run = [rt for rt in present if rt in execution["native"]]
    jit_run = [rt for rt in present if rt in execution["jit"]]
    interpreted_run = [rt for rt in present if rt in execution["interpreted"]]
    ex_matrix = "\n".join('<h3>%s</h3>%s' % (name, matrix(
        TASK_IDS, runtimes, ms, ms_text, ("geo time / group best", gm, lambda v: fmt(v))))
        for name, runtimes in (("Native / AOT", native_run), ("JIT", jit_run),
                               ("Interpreted", interpreted_run)) if runtimes)
    def speed_chart(runtimes, ratios):
        return chart([(rt, 100 / ratios[rt], speed_text(100 / ratios[rt]))
                      for rt in sorted(runtimes, key=ratios.get)],
                     100, [0, 25, 50, 75, 100], "%")

    ex_native_chart = speed_chart(native_run, gm)
    ex_jit_chart = speed_chart(jit_run, gm)
    ex_interpreted_chart = speed_chart(interpreted_run, gm)
    ex_native_performance = performance_table(TASK_IDS, native_run, ms, ms_text)
    ex_jit_performance = performance_table(TASK_IDS, jit_run, ms, ms_text)
    ex_interpreted_performance = performance_table(TASK_IDS, interpreted_run, ms, ms_text)
    ex_native_comparison = comparison_table(TASK_IDS, [("native / AOT", native_run)], ms, "swag-release")
    ex_jit_comparison = comparison_table(TASK_IDS, [("JIT", jit_run)], ms, "swc-jit-release")

    def competitive_summary(runtimes, lead):
        ratios = [ms(lead, t) / min(ms(rt, t) for rt in runtimes) for t in TASK_IDS]
        return ('Geometric time gap: <b>+%s%%</b>. Lowest recorded time on <b>%d / %d</b> tasks. '
                'Largest gap: <b>+%s%%</b>.' % (fmt((geo(ratios) - 1) * 100, 1),
                sum(r == 1 for r in ratios), len(ratios), fmt((max(ratios) - 1) * 100, 1)))

    ex_native_summary = competitive_summary(native_run, "swag-release")
    ex_jit_summary = (competitive_summary(jit_run, "swc-jit-release")
                      if "swc-jit-release" in gm else "No complete Swag JIT measurement.")

    bu_chart = speed_chart(aot, bgm)
    def build_ms(r, t):
        if t != "hello":
            return build(r, t, "wall_ms")
        rec = B["hello_build"].get(r) or {}
        return rec.get("wall_ms") if not rec.get("error") else None

    bu_matrix = matrix(TASK_IDS + ["hello"], aot, build_ms,
                       lambda v: fmt(v, 0) if v is not None else "&mdash;",
                       ("geo ms", bgeo, lambda v: fmt(v, 0)))
    bu_performance = performance_table(TASK_IDS + ["hello"], aot, build_ms,
                                       lambda v: fmt(v, 0) if v is not None else "&mdash;")
    bu_comparison = comparison_table(
        TASK_IDS, [("compiler", aot)], lambda rt, task: build(rt, task, "wall_ms"),
        "swag-release")

    # The edit-build loop of this campaign, from its condensed entry: that is where the
    # correction and the index live, and the raw file only holds what was measured.
    current = next((e for e in entries if e["meta"].get("stamp") == B["meta"].get("stamp")),
                   entries[-1] if entries else {})
    loop = current.get("loop") or {}
    loop_rows = []
    for wid, name, what in LOOP:
        rec = loop.get(wid)
        if not rec:
            continue
        loop_rows.append(['%s <span class="mode">%s</span>' % (name, what),
                          fmt(rec.get("wall_ms"), 0), fmt(rec.get("adjusted_ms"), 0),
                          fmt(rec.get("peak_mb"), 0), fmt(rec.get("index"))])
    run_entry = next((e for e in entries if e["meta"].get("stamp") == R["meta"].get("stamp")), None)
    allocator = allocator_section(entries, run_entry)

    loop_table = (simple_table(["workload", "raw (ms)", "adjusted (ms)", "MiB", "index"],
                               loop_rows)
                  if loop_rows else '<p class="cap">No measured edit-build workload.</p>')

    me_hi, me_ticks = lin_axis([bmem[r] for r in aot])
    me_chart = chart(sorted(((r, bmem[r], fmt(bmem[r], 0)) for r in aot), key=lambda x: x[1]),
                     me_hi, me_ticks, "MiB")
    rm_hi, rm_ticks = lin_axis([rmem[r] / 1048576.0 for r in present])
    rm_chart = chart(sorted(((r, rmem[r] / 1048576.0, fmt(rmem[r] / 1048576.0, 0))
                             for r in present), key=lambda x: x[1]),
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
        "Native code runs within about **%sx of clang-cl** on those %s programs (geometric "
        "mean), while" % (fmt(gm["swag-release"] / gm["cpp-clang-cl"], 1),
                              spelled(len(TASK_IDS)).lower()),
        "the geometric mean of fastest non-Swag build time / swc build time per task is "
        "**%sx** (higher is better; 2x means swc builds twice as fast on average). The raw table "
        "above includes each recipe's imports and linking or bytecode generation." % fmt(build_speedup),
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
        "{{stats}}": stats,
        "{{progress_version}}": str(history.PROGRESS_VERSION),
        "{{progress_tasks}}": str(len(history.PROGRESS_TASKS)),
        "{{ex_native_summary}}": ex_native_summary, "{{ex_jit_summary}}": ex_jit_summary,
        "{{build_speedup}}": fmt(build_speedup),
        "{{runtime_legend}}": runtime_legend([r[0] for r in RUNTIMES if r[0] in set(present + aot)]),
        "{{ex_native_chart}}": ex_native_chart, "{{ex_jit_chart}}": ex_jit_chart,
        "{{ex_interpreted_chart}}": ex_interpreted_chart,
        "{{ex_matrix}}": ex_matrix,
        "{{ex_native_performance}}": ex_native_performance, "{{ex_jit_performance}}": ex_jit_performance,
        "{{ex_interpreted_performance}}": ex_interpreted_performance,
        "{{ex_native_comparison}}": ex_native_comparison, "{{ex_jit_comparison}}": ex_jit_comparison,
        "{{bu_chart}}": bu_chart, "{{bu_matrix}}": bu_matrix, "{{bu_performance}}": bu_performance,
        "{{bu_comparison}}": bu_comparison,
        "{{loop_table}}": loop_table,
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
        html = template.read()
    for k, v in subs.items():
        html = html.replace(k, v)
    import re
    left = set(re.findall(r"\{\{\w+\}\}", html))
    if left:
        print("WARNING unresolved placeholders:", left)
    with open(OUTFILE, "w", encoding="utf-8", newline="\r\n") as f:
        f.write(html)
    print("written bench.html (%d bytes, %d campaign(s) in history)" % (len(html), len(entries)))


if __name__ == "__main__":
    main()
