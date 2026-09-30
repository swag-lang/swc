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

# The repository README quotes one campaign in full. It used to be hand-copied, which
# meant it was stale between the moment a campaign moved and the moment somebody
# remembered; the block between these markers is now rewritten from the same campaign
# that produced the page, so the two can never disagree.
REPO_README = os.path.join(tc.worktree(), "README.md")
README_BEGIN = "<!-- bench:begin -->"
README_END = "<!-- bench:end -->"

# What each task exercises, shown when hovering its name. The order and the list itself
# come from toolchains.TASKS; a task missing here is still shown, only without a description.
TASK_INFO = {
    "wordfreq": "table de hachage maison sur 2 M mots, puis tri",
    "csvagg": "400 k lignes, parsing octet &agrave; octet, flottants",
    "sha256": "8 Mio, ALU enti&egrave;re pure, rotations",
    "dijkstra": "grille 800&times;800, tas binaire",
    "raytrace": "480&times;360, f64, r&eacute;cursion",
    "leven": "40 requ&ecirc;tes contre 6000 mots",
    "chacha": "16 Mio de flot de cl&eacute;, lanes 32 bits, rotations",
    "nbody": "5 corps, 500 k pas, f64, sqrt, tableau de structures",
    "fannkuch": "fannkuch-redux N = 9, permutations et retournements",
    "binarytrees": "profondeur 12, allocation et lib&eacute;ration n&oelig;ud par n&oelig;ud",
    "lz77": "1 Mio, compression par cha&icirc;nes de hachage puis d&eacute;compression",
    "sort": "300 k entiers, quicksort m&eacute;diane de trois",
}

RUNTIMES = [
    ("swag-release",       "swag release",      "natif",     "swag"),
    ("swc-jit-release",    "swag release",      "JIT",       "swag"),
    ("swag-fast-debug",    "swag devmode",      "natif",     "swag"),
    ("swc-jit-fast-debug", "swag devmode",      "JIT",       "swag"),
    ("cpp-clang-cl",       "clang",             "natif",     "native"),
    ("cpp-msvc",           "MSVC",              "natif",     "native"),
    ("rust",               "Rust",              "natif",     "native"),
    ("zig",                "Zig",               "native",    "native"),
    ("d-ldc",              "D",                 "native",    "native"),
    ("odin",               "Odin",              "native",    "native"),
    ("swift",              "Swift",             "natif",     "native"),
    ("csharp-aot",         "C# NativeAOT",      "AOT",       "managed"),
    ("csharp-jit",         "C# CoreCLR",        "JIT",       "managed"),
    ("node20",             "Node / V8",         "JIT",       "dynamic"),
    ("luajit2.1",          "LuaJIT",            "JIT",       "dynamic"),
    ("lua5.4",             "Lua",               "interpr&eacute;t&eacute;", "dynamic"),
    ("python3.12",         "CPython",           "interpr&eacute;t&eacute;", "dynamic"),
]
META = {r[0]: r for r in RUNTIMES}

# Column headers of the per-task matrices: two short lines, name then mode.
SHORT = {
    "swag-release": ("swag", "natif"), "swc-jit-release": ("swag", "JIT"),
    "swag-fast-debug": ("swag dev", "natif"), "swc-jit-fast-debug": ("swag dev", "JIT"),
    "cpp-clang-cl": ("clang", ""), "cpp-msvc": ("MSVC", ""), "rust": ("Rust", ""),
    "zig": ("Zig", ""), "d-ldc": ("D", ""), "odin": ("Odin", ""), "swift": ("Swift", ""),
    "csharp-aot": ("C#", "AOT"), "csharp-jit": ("C#", "JIT"), "node20": ("Node", "V8"),
    "luajit2.1": ("LuaJIT", ""), "lua5.4": ("Lua", "5.4"), "python3.12": ("Python", "3.12"),
}

# One colour per runtime, shared by every chart bar and ranking entry; no two runtimes share
# one, swag's four variants included.
LANG = {
    "swag-release": "swag", "swc-jit-release": "swagjit",
    "swag-fast-debug": "swagdev", "swc-jit-fast-debug": "swagdevjit",
    "cpp-clang-cl": "clang", "cpp-msvc": "msvc", "rust": "rust", "zig": "zig", "d-ldc": "d",
    "odin": "odin", "swift": "swift", "csharp-aot": "csaot", "csharp-jit": "csjit",
    "node20": "js", "luajit2.1": "luajit", "lua5.4": "lua", "python3.12": "py",
}


def lang_class(rt):
    return "l-" + LANG.get(rt, "other")


# The journal shows only the most recent campaigns; the curves carry every one.
JOURNAL_ROWS = 10

DRIFT_LIMIT = history.DRIFT_LIMIT_PCT

HIST_SERIES = [
    ("swag-release",       "release natif",    "h-a"),
    ("swc-jit-release",    "release JIT",      "h-b"),
    ("swag-fast-debug",    "devmode natif",    "h-c"),
    ("swc-jit-fast-debug", "devmode JIT",      "h-d"),
]

# The edit-build loop, in the order a person meets it: the first build, the build where
# nothing changed, the build after one save, and the two commands that are not builds.
LOOP = [
    ("core_rebuild", "std/core &agrave; froid", "tous les fichiers, sorties supprim&eacute;es"),
    ("core_noop", "std/core sans changement", "rien n'a boug&eacute; depuis la derni&egrave;re construction"),
    ("core_touch", "std/core, un fichier sauv&eacute;", "une seule date de modification a avanc&eacute;"),
    ("hello_build", "hello world &rarr; exe", "small program, source to executable"),
    ("doc_std", "documentation de std", "tout le site de la biblioth&egrave;que standard"),
    ("format_tree", "formatage du d&eacute;p&ocirc;t", "toutes les sources Swag, sur une copie"),
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
            return campaign
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


def logw(v, lo, hi):
    return max(0.7, min(100.0, (math.log10(v) - math.log10(lo)) /
                        (math.log10(hi) - math.log10(lo)) * 100.0))


def linw(v, hi):
    return max(0.7, min(100.0, v / hi * 100.0))


def log_axis(values, max_ticks=8):
    """Powers of two that bracket the data.

    Hardcoded bounds were fine until a task was rescaled and the longest bar ran off
    the end of its own axis, silently clamped to the full width. An axis derived from
    the values it draws cannot go stale behind a measurement.
    """
    values = [v for v in values if v and v > 0]
    if not values:
        return 1, 2, [1, 2]
    lo = 2 ** math.floor(math.log2(min(values)))
    hi = 2 ** math.ceil(math.log2(max(values)))
    if hi <= lo:
        hi = lo * 2
    ticks = []
    tick = lo
    while tick <= hi:
        ticks.append(tick)
        tick *= 2
    step = max(1, (len(ticks) + max_ticks - 1) // max_ticks)
    ticks = ticks[::step]
    if ticks[-1] != hi:
        ticks.append(hi)
    return lo, hi, ticks


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
def chart(rows, lo, hi, ticks, unit, scale="log"):
    out = ['<figure class="chart">', '<div class="axis" aria-hidden="true">']
    for t in ticks:
        pos = logw(t, lo, hi) if scale == "log" else linw(t, hi)
        out.append('<span class="tick" style="left:%.3f%%"><i></i><b>%g</b></span>' % (pos, t))
    out.append("</div>")
    for rt, v, printed in rows:
        w = logw(v, lo, hi) if scale == "log" else linw(v, hi)
        m = META[rt]
        out.append(
            '<div class="row %s"><div class="rl">%s <span class="mode">%s</span></div>'
            '<div class="track"><span class="bar" style="width:%.3f%%"></span></div>'
            '<div class="rv">%s<em>%s</em></div></div>'
            % (lang_class(rt), m[1], m[2], w, printed, unit))
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
    out = ['<div class="table-wrap"><table class="matrix"><thead><tr><th>t&acirc;che</th>']
    for i, rt in enumerate(runtimes):
        name, mode = SHORT.get(rt, (META[rt][1], ""))
        out.append('<th%s>%s<br><span class="mode">%s</span></th>'
                   % (_cell_class(rt, runtimes[i - 1] if i else None), name, mode))
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


def ranked_table(tasks, runtimes, value, display):
    """One line per task: every runtime from the lowest value to the highest, swag marked.

    The second column gives swag release's place in that line, which is the question the
    table exists to answer."""
    lead = next((rt for rt in ("swag-release", "swc-jit-release") if rt in runtimes), None)
    out = ['<div class="table-wrap"><table class="ranked"><thead><tr><th>t&acirc;che</th>'
           '<th>swag</th><th>classement</th></tr></thead><tbody>']
    for task in tasks:
        measured = [(rt, value(rt, task)) for rt in runtimes]
        measured.sort(key=lambda item: (item[1] is None,
                                        item[1] if item[1] is not None else math.inf))
        ranks = {rt: rank for rank, (rt, _) in enumerate(measured, 1)}
        info = TASK_INFO.get(task)
        title = ' title="%s"' % html.escape(html.unescape(info), quote=True) if info else ""
        place = ("%d<span class=\"mode\">/%d</span>" % (ranks[lead], len(measured))
                 if lead in ranks else "&mdash;")
        out.append("<tr><th%s><code>%s</code></th><td>%s</td><td><ol>" % (title, task, place))
        for rank, (rt, result) in enumerate(measured, 1):
            name, mode = SHORT.get(rt, (META[rt][1], ""))
            if META[rt][3] == "swag":
                mode = ""  # the table already says native or JIT; the colour says swag
            out.append('<li class="%s"><b>%d</b>%s%s<i>%s</i></li>'
                       % (lang_class(rt), rank, name,
                          ' <span class="mode">%s</span>' % mode if mode else "",
                          display(result)))
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


def svg_lines(labels, series, unit, nd=2, zero=False, compact=False, band=None, width=None):
    """series: list of (css class, legend text, [values, one per campaign]).

    `compact` draws at the size it will actually occupy, so the text is not shrunk
    to nothing by the browser scaling a wide viewBox into a narrow column.
    `band` is an optional [lo, hi] per campaign, drawn behind the curves: it is where
    code that did not change between two campaigns lands."""
    flat = [v for _, _, vs in series for v in vs if v is not None]
    flat += [v for pair in (band or []) if pair for v in pair]
    if not flat:
        return '<p class="cap">Aucune donn&eacute;e.</p>'

    if compact:
        W, H, PAD_L, PAD_R, PAD_T, PAD_B, rows = 300, 104, 40, 12, 12, 20, 2
    else:
        W, H, PAD_L, PAD_R, PAD_T, PAD_B, rows = globals()["W"], globals()["H"], 52, 96, 16, 34, 4
        if width:
            W, H = width, 200

    lo, hi = nice_bounds(flat)
    if zero:
        lo = 0.0
    n = len(labels)
    span = W - PAD_L - PAD_R
    # A lone campaign sits in the middle rather than pinned to the left edge, where
    # it would read as the start of a line that does not exist yet.
    px = lambda i: PAD_L + (span / 2 if n == 1 else i * span / (n - 1))
    py = lambda v: PAD_T + (1 - (v - lo) / (hi - lo)) * (H - PAD_T - PAD_B)

    o = ['<svg class="hchart%s" viewBox="0 0 %d %d" role="img" '
         'preserveAspectRatio="xMidYMid meet">' % (" compact" if compact else "", W, H)]

    for k in range(rows + 1):
        v = lo + (hi - lo) * k / rows
        y = py(v)
        o.append('<line class="hgrid" x1="%d" y1="%.1f" x2="%d" y2="%.1f"/>'
                 % (PAD_L, y, W - PAD_R, y))
        o.append('<text class="hlab" x="%d" y="%.1f" text-anchor="end">%s</text>'
                 % (PAD_L - 6, y + 3.5, fmt(v, nd)))

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


def history_section(entries):
    if not entries:
        return '<p class="cap">Aucune campagne enregistr&eacute;e.</p>'

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

    parts = ['<div class="small-mult">']
    for field, name, nd, unit in (
            ("exec_vs_best", "ex&eacute;cution vs le meilleur (&times;)", 2, "&times;"),
            ("jit_gap_pct", "JIT swc vs natif swc (%)", 0, "%"),
            ("build_edge", "build MSVC / swc (&times;)", 1, "&times;")):
        vals = [e.get("headline", {}).get(field) for e in entries]
        parts.append('<div class="sm"><b>%s</b>%s</div>'
                     % (name, svg_lines(labels, [("h-a", "", vals)], unit, nd=nd, compact=True)))
    parts.append("</div>")

    parts.append('<div class="grid2"><div>')
    parts.append("<h3>Indice d'ex&eacute;cution</h3>")
    parts.append(svg_lines(labels, series("run_geo_index"), "&times;", band=null_band("run"),
                             width=520))
    parts.append("</div><div>")
    parts.append("<h3>Indice de compilation</h3>")
    parts.append(svg_lines(labels, series("build_geo_index"), "&times;", band=null_band("build"),
                             width=520))
    parts.append("</div><div>")
    parts.append("<h3>Pic m&eacute;moire du compilateur (Mo)</h3>")
    parts.append(svg_lines(labels, [(c, n, [e["runtimes"].get(rt, {}).get("build_peak_mb")
                                            for e in entries])
                                    for rt, n, c in HIST_SERIES
                                    if any(e["runtimes"].get(rt, {}).get("build_peak_mb")
                                           for e in entries)],
                           "Mo", nd=0, width=520))
    parts.append("</div></div>")

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
    parts.append("<h3>swag release par t&acirc;che et boucle d'&eacute;dition</h3>")
    parts.append('<p class="cap">Indice corrig&eacute;, 1,00 &agrave; la campagne de r&eacute;f&eacute;rence '
                 "(ou &agrave; la premi&egrave;re qui a mesur&eacute; la ligne). Plus bas est mieux.</p>")
    parts.append(simple_table(["", "indice", "r&eacute;solution", "depuis", "tendance"], rows))

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
    parts.append("<h3>Journal</h3>")
    parts.append('<p class="cap">%d derni&egrave;res campagnes. * arbre modifi&eacute;.</p>'
                 % len(journal))
    parts.append(simple_table(["commit", "date", "exec (ms)", "build (ms)", "Mo",
                               "ctx exec", "ctx build", "sondes %", "note"], journal))
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
    first = TASK_IDS[0]
    present = [r[0] for r in RUNTIMES if r[0] in T[first]
               and (T[first][r[0]].get("run") or {}).get("ms")]
    aot = [r[0] for r in RUNTIMES if r[0] in BT[first]
           and (BT[first][r[0]].get("build") or {}).get("wall_ms")]

    def ms(rt, task):
        return ((T[task].get(rt) or {}).get("run") or {}).get("ms")

    def build(rt, task, key):
        return ((BT[task].get(rt) or {}).get("build") or {}).get(key)

    best = {t: min(v for v in (ms(r, t) for r in present) if v) for t in TASK_IDS}
    ratio = {r: {t: ms(r, t) / best[t] for t in TASK_IDS if ms(r, t)} for r in present}
    gm = {r: geo(list(ratio[r].values())) for r in present}
    bgeo = {r: geo([build(r, t, "wall_ms") for t in TASK_IDS]) for r in aot}
    bmem = {r: max(build(r, t, "peak_bytes") or 0 for t in TASK_IDS) / 1048576.0 for r in aot}
    exekb = {r: geo([build(r, t, "exe_bytes") for t in TASK_IDS]) / 1024.0 for r in aot}
    rmem = {r: max(((T[t].get(r) or {}).get("run") or {}).get("peak_bytes") or 0
                   for t in TASK_IDS) for r in present}

    swag = gm["swag-release"]
    jit_gap = (gm["swc-jit-release"] / swag - 1.0) * 100.0
    build_entry = next(entry for entry in entries
                       if entry["meta"]["stamp"] == B["meta"]["stamp"])
    build_edge = build_entry["headline"]["build_edge"]

    def stat(value, unit, name):
        return ('<div class="stat"><div class="sv">%s<em>%s</em></div>'
                '<div class="sl">%s</div></div>' % (value, unit, name))

    stats = "".join([
        stat(fmt(swag), "&times;", "ex&eacute;cution vs le meilleur"),
        stat("%+.0f" % jit_gap, "%", "JIT swc vs natif swc"),
        stat(fmt(build_edge, 1), "&times;", "build MSVC / swc"),
        stat("%d" % round(bmem["swag-release"]), "Mo", "pic m&eacute;moire du compilateur"),
    ])

    order = sorted(present, key=lambda r: gm[r])
    ex_lo, ex_hi, ex_ticks = log_axis([gm[r] for r in order])
    ex_chart = chart([(r, gm[r], fmt(gm[r])) for r in order], ex_lo, ex_hi, ex_ticks, "&times;")
    ex_matrix = matrix(TASK_IDS, present, ms, ms_text,
                       ("g&eacute;o &times;", gm, lambda v: fmt(v)))
    native_run = [r for r in present if META[r][2] not in ("JIT", "interpr&eacute;t&eacute;")]
    jit_run = [r for r in present if r not in native_run]
    ex_native_rank = ranked_table(TASK_IDS, native_run, ms, ms_text)
    ex_jit_rank = ranked_table(TASK_IDS, jit_run, ms, ms_text)

    border = sorted(aot, key=lambda r: bgeo[r])
    bu_lo, bu_hi, bu_ticks = log_axis([bgeo[r] for r in border])
    bu_chart = chart([(r, bgeo[r], fmt(bgeo[r], 0)) for r in border],
                     bu_lo, bu_hi, bu_ticks, "ms")
    def build_ms(r, t):
        return ((B["hello_build"].get(r) or {}).get("wall_ms") if t == "hello"
                else build(r, t, "wall_ms"))

    bu_matrix = matrix(TASK_IDS + ["hello"], aot, build_ms,
                       lambda v: fmt(v, 0) if v is not None else "&mdash;",
                       ("g&eacute;o ms", bgeo, lambda v: fmt(v, 0)))
    bu_rank = ranked_table(TASK_IDS + ["hello"], aot, build_ms,
                           lambda v: fmt(v, 0) if v is not None else "&mdash;")

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
    loop_table = (simple_table(["charge", "brut (ms)", "corrig&eacute; (ms)", "Mo", "indice"],
                               loop_rows)
                  if loop_rows else '<p class="cap">Aucune charge mesur&eacute;e.</p>')

    me_hi, me_ticks = lin_axis([bmem[r] for r in aot])
    me_chart = chart(sorted(((r, bmem[r], fmt(bmem[r], 0)) for r in aot), key=lambda x: x[1]),
                     0, me_hi, me_ticks, "Mo", "lin")
    rm_lo, rm_hi, rm_ticks = log_axis([rmem[r] / 1048576.0 for r in present])
    rm_chart = chart(sorted(((r, rmem[r] / 1048576.0, fmt(rmem[r] / 1048576.0, 0))
                             for r in present), key=lambda x: x[1]),
                     rm_lo, rm_hi, rm_ticks, "Mo")

    hr = R["hello_run"]
    startup = [(r, hr[r].get("first_stdout_ms") or hr[r].get("wall_ms"))
               for r in hr if r in META]
    startup = [(runtime, elapsed) for runtime, elapsed in startup if elapsed is not None]
    st_lo, st_hi, st_ticks = log_axis([elapsed for _, elapsed in startup])
    st_chart = chart(sorted(((runtime, elapsed, fmt(elapsed, 0)) for runtime, elapsed in startup),
                            key=lambda x: x[1]),
                     st_lo, st_hi, st_ticks, "ms")
    sz_lo, sz_hi, sz_ticks = log_axis([exekb[r] for r in aot])
    sz_chart = chart(sorted(((r, exekb[r], fmt(exekb[r], 0)) for r in aot), key=lambda x: x[1]),
                     sz_lo, sz_hi, sz_ticks, "Ko")

    m = R["meta"]
    settings = m.get("settings") or {}

    # ---------------------------------------------------- repository README block
    ex_cols = [("swag-release", "swc"), ("swc-jit-release", "swc JIT"),
               ("cpp-clang-cl", "clang-cl"), ("rust", "rustc"),
               ("zig", "Zig"), ("d-ldc", "D (LDC)"), ("odin", "Odin"),
               ("luajit2.1", "LuaJIT"), ("node20", "Node 20"),
               ("python3.12", "CPython 3.12")]
    bu_cols = [("swag-release", "swc"), ("cpp-clang-cl", "clang-cl"), ("rust", "rustc"),
               ("zig", "Zig"), ("d-ldc", "D (LDC)"), ("odin", "Odin")]
    ex_cols = [c for c in ex_cols if c[0] in present]
    bu_cols = [c for c in bu_cols if c[0] in aot]
    readme = [
        "",
        "%s programs, written by hand and identically in every language, none of them using a "
        "standard library" % spelled(len(TASK_IDS)),
        "container: each one reimplements its own hash map, heap, or matrix. All ports "
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
        "**Compilation**, from source to a linked executable, including each port's required "
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
        "the control-adjusted MSVC baseline / swc build ratio is **%sx**. The raw table "
        "above includes each compiler's imports and linker." % fmt(build_edge, 1),
        "A hello world compiles and links in %s ms."
        % fmt((B["hello_build"].get("swag-release") or {}).get("wall_ms"), 0),
        "",
        "The JIT lands **within %s percent of the native backend** here, which is what makes "
        "compile-time" % fmt(abs(jit_gap), 0),
        "execution, `#test`, and script mode usable rather than a slow mode you avoid: on the "
        "same programs it",
        "is about **%sx faster than LuaJIT**, **%sx faster than Node**, and **%sx faster than "
        "CPython**." % (fmt(gm["luajit2.1"] / gm["swc-jit-release"], 1),
                        fmt(gm["node20"] / gm["swc-jit-release"], 1),
                        fmt(gm["python3.12"] / gm["swc-jit-release"], 0)),
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
        "{{ex_chart}}": ex_chart, "{{ex_matrix}}": ex_matrix,
        "{{ex_native_rank}}": ex_native_rank, "{{ex_jit_rank}}": ex_jit_rank,
        "{{bu_chart}}": bu_chart, "{{bu_matrix}}": bu_matrix, "{{bu_rank}}": bu_rank,
        "{{loop_table}}": loop_table,
        "{{me_chart}}": me_chart, "{{rm_chart}}": rm_chart,
        "{{st_chart}}": st_chart, "{{sz_chart}}": sz_chart,
        "{{history}}": history_section(entries),
        "{{machine_spread}}": fmt(R["calibration"].get("spread_pct"), 1),
        "{{calib_start}}": fmt(R["calibration"]["start"], 1),
        "{{calib_end}}": fmt(R["calibration"]["end"], 1),
        "{{provenance}}": ("arbre modifi&eacute; au moment de la mesure" if m.get("dirty")
                           else "Release x64 reconstruit depuis ce commit"),
        "{{commit}}": m.get("commit") or "?",
        "{{subject}}": (m.get("subject") or "").replace("&", "&amp;").replace("<", "&lt;")[:90],
        "{{date}}": m["date"][:10],
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
        "{{skipped}}": (", ".join(R.get("skipped") or []) or "aucune"),
    }

    with open(TEMPLATE, encoding="utf-8") as template:
        html = template.read()
    for k, v in subs.items():
        html = html.replace(k, v)
    import re
    left = set(re.findall(r"\{\{\w+\}\}", html))
    if left:
        print("WARNING unresolved placeholders:", left)
    with open(OUTFILE, "w", encoding="utf-8", newline="\n") as f:
        f.write(html)
    print("written bench.html (%d bytes, %d campaign(s) in history)" % (len(html), len(entries)))


if __name__ == "__main__":
    main()
