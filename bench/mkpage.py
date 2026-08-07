"""Generate bench.html from the latest campaign plus the accumulated history.

Every number on the page comes from a JSON file, never from an edit here, so the
page can never disagree with the measurement that produced it.
"""
import glob
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

TASKS = [
    ("wordfreq", "comptage de mots", "table de hachage maison sur 2 M mots, puis tri"),
    ("csvagg", "agr&eacute;gation CSV", "400 k lignes, parsing octet &agrave; octet, flottants"),
    ("sha256", "SHA-256", "8 Mio, ALU enti&egrave;re pure, rotations"),
    ("dijkstra", "Dijkstra", "grille 800&times;800, tas binaire"),
    ("raytrace", "lancer de rayons", "480&times;360, f64, r&eacute;cursion"),
    ("leven", "Levenshtein", "40 requ&ecirc;tes contre 6000 mots"),
    ("chacha", "ChaCha20", "16 Mio de flot de cl&eacute;, lanes 32 bits, rotations"),
]
TASK_IDS = [t[0] for t in TASKS]

RUNTIMES = [
    ("swag-release",       "swag release",      "natif",     "swag"),
    ("swc-jit-release",    "swag release",      "JIT",       "swag"),
    ("swag-fast-debug",    "swag fast-debug",   "natif",     "swag"),
    ("swc-jit-fast-debug", "swag fast-debug",   "JIT",       "swag"),
    ("cpp-clang-cl",       "C++ clang-cl",      "natif",     "native"),
    ("cpp-msvc",           "C++ MSVC",          "natif",     "native"),
    ("rust",               "Rust",              "natif",     "native"),
    ("swift",              "Swift",             "natif",     "native"),
    ("csharp-aot",         "C# NativeAOT",      "AOT",       "managed"),
    ("csharp-jit",         "C# CoreCLR",        "JIT",       "managed"),
    ("node20",             "Node / V8",         "JIT",       "dynamic"),
    ("luajit2.1",          "LuaJIT",            "JIT",       "dynamic"),
    ("lua5.4",             "Lua",               "interpr&eacute;t&eacute;", "dynamic"),
    ("python3.12",         "CPython",           "interpr&eacute;t&eacute;", "dynamic"),
]
META = {r[0]: r for r in RUNTIMES}

DRIFT_LIMIT = history.DRIFT_LIMIT_PCT

HIST_SERIES = [
    ("swag-release",       "release natif",    "h-a"),
    ("swc-jit-release",    "release JIT",      "h-b"),
    ("swag-fast-debug",    "fast-debug natif", "h-c"),
    ("swc-jit-fast-debug", "fast-debug JIT",   "h-d"),
]


def latest_campaign():
    """The most recent campaign of the current protocol.

    A campaign measured under an older protocol is not merely older, it measured
    something else; publishing one as if it were current is the failure this whole
    file exists to prevent.
    """
    for path in sorted(glob.glob(os.path.join(BENCH, "results", "*.json")), reverse=True):
        with open(path, encoding="utf-8") as f:
            campaign = json.load(f)
        if campaign.get("meta", {}).get("protocol") == history.PROTOCOL:
            return campaign
    raise SystemExit("no campaign of protocol %d in bench/results — run a campaign first"
                     % history.PROTOCOL)


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
            '<div class="row f-%s"><div class="rl">%s <span class="mode">%s</span></div>'
            '<div class="track"><span class="bar" style="width:%.3f%%"></span></div>'
            '<div class="rv">%s<em>%s</em></div></div>' % (m[3], m[1], m[2], w, printed, unit))
    out.append("</figure>")
    return "\n".join(out)


def table(headers, rows, cls=""):
    out = ['<div class="scroll"><table class="%s">' % cls, "<thead><tr>"]
    for i, h in enumerate(headers):
        out.append("<th%s>%s</th>" % (' class="num"' if i else "", h))
    out.append("</tr></thead><tbody>")
    for r in rows:
        out.append('<tr class="f-%s"><th scope="row">%s</th>' % (r[0], r[1]))
        for c in r[2:]:
            out.append('<td class="num">%s</td>' % c)
        out.append("</tr>")
    out.append("</tbody></table></div>")
    return "\n".join(out)


# -------------------------------------------------------------- history plots
W, H = 760, 250
PAD_L, PAD_R, PAD_T, PAD_B = 52, 96, 16, 34


def nice_bounds(values):
    lo, hi = min(values), max(values)
    if hi == lo:
        return max(0.0, lo * 0.9), hi * 1.1 + (0.1 if hi == 0 else 0)
    span = hi - lo
    return lo - span * 0.25, hi + span * 0.25


def svg_lines(labels, series, unit, nd=2, zero=False, compact=False, band=None):
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

    shown = [0, n - 1] if compact else list(range(n))
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
            for x, y in pts:
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
        return '<p class="lede">Aucune campagne enregistr&eacute;e.</p>'

    labels = []
    for e in entries:
        m = e["meta"]
        labels.append(m.get("commit") or m["date"][:10])

    def series(field, sub=None):
        out = []
        for rt, name, cls in HIST_SERIES:
            vals = []
            for e in entries:
                rec = e["runtimes"].get(rt)
                if not rec:
                    vals.append(None)
                    continue
                v = rec.get(field)
                vals.append(v.get(sub) if (sub and isinstance(v, dict)) else v)
            if any(v is not None for v in vals):
                out.append((cls, name, vals))
        return out

    parts = []

    if len(entries) == 1:
        parts.append(
            '<div class="note"><p><b>Une seule campagne enregistr&eacute;e.</b> Les courbes '
            "apparaissent d&egrave;s la deuxi&egrave;me : chaque point ci-dessous est le "
            "rep&egrave;re de d&eacute;part.</p></div>")

    latest_context = entries[-1].get("context", {})
    run_tasks = latest_context.get("run_task_factors", {})
    build_tasks = latest_context.get("build_task_factors", {})
    run_per_task = (latest_context.get("run_controls", 0) // len(run_tasks)) if run_tasks else 0
    build_per_task = ((latest_context.get("build_controls", 0) // len(build_tasks))
                      if build_tasks else 0)
    baseline = latest_context.get("baseline_commit") or latest_context.get("baseline") or "?"

    def null_band(family, task=None):
        out = []
        for e in entries:
            null = (e.get("null") or {}).get(family) or {}
            out.append(null.get("tasks", {}).get(task) if task else null.get("geo"))
        return out

    def half_width(bands):
        """Typical distance from 1.00 an unchanged runtime reaches, in percent. The
        reference campaign is exactly 1.00 by construction and is not evidence."""
        widths = [max(abs(pair[1] - 1.0), abs(1.0 - pair[0])) for pair in bands if pair]
        widths = sorted(w for w in widths if w > 0)
        return 100.0 * (widths[len(widths) // 2] if widths else 0.0)

    run_band = null_band("run")
    build_band = null_band("build")
    controls_run = ((entries[-1].get("null") or {}).get("run") or {}).get("controls", 0)

    parts.append("<h3>Les quatre chiffres de t&ecirc;te, campagne apr&egrave;s campagne</h3>")
    parts.append('<p class="cap">Les trois rapports affich&eacute;s en haut de page compar&eacute;s '
                 "aux m&ecirc;mes runtimes mesur&eacute;s dans la m&ecirc;me campagne : ce sont des "
                 "rapports, ils ne portent donc aucune d&eacute;rive machine et ne re&ccedil;oivent "
                 "aucune correction. Le quatri&egrave;me, le pic m&eacute;moire, a son propre graphe "
                 "plus bas.</p>")
    parts.append('<div class="small-mult">')
    for field, name, nd, unit in (
            ("exec_vs_best", "ex&eacute;cution vs le meilleur (&times;)", 2, "&times;"),
            ("jit_gap_pct", "JIT swc vs natif swc (%)", 0, "%"),
            ("build_edge", "compilation vs MSVC (&times;)", 1, "&times;")):
        vals = [e.get("headline", {}).get(field) for e in entries]
        parts.append('<div class="sm"><b>%s</b>%s</div>'
                     % (name, svg_lines(labels, [("h-a", "", vals)], unit,
                                        nd=nd, compact=True)))
    parts.append("</div>")

    parts.append("<h3>Ex&eacute;cution &mdash; indice corrig&eacute; du contexte machine</h3>")
    parts.append('<p class="cap">Pour chaque t&acirc;che, le temps Swag brut est divis&eacute; par '
                 "le mouvement m&eacute;dian de %d runtimes t&eacute;moins inchang&eacute;s. "
                 "La campagne <code>%s</code> vaut 1,00 ; une baisse mesure donc un progr&egrave;s "
                 "du compilateur, apr&egrave;s retrait du contexte machine.</p>" % (run_per_task, baseline))
    parts.append('<p class="cap">La bande grise est la <b>r&eacute;solution du banc</b> : la m&ecirc;me '
                 "correction appliqu&eacute;e &agrave; chacun des %d t&eacute;moins, dont le code ne "
                 "change jamais, corrig&eacute; par la m&eacute;diane des autres. Un t&eacute;moin devrait "
                 "valoir exactement 1,00 ; l'&eacute;cart qu'il affiche est ce que le banc ne sait pas "
                 "distinguer de z&eacute;ro. Une variation de la courbe Swag inf&eacute;rieure &agrave; "
                 "&plusmn;%.0f&nbsp;%% d'une campagne &agrave; la suivante n'a pas &eacute;t&eacute; "
                 "mesur&eacute;e.</p>" % (controls_run, half_width(run_band)))
    parts.append(svg_lines(labels, series("run_geo_index"), "&times;", band=run_band))

    parts.append("<h3>Compilation &mdash; indice corrig&eacute; du contexte machine</h3>")
    parts.append('<p class="cap">M&ecirc;me correction et m&ecirc;me bande de r&eacute;solution, '
                 "calcul&eacute;es s&eacute;par&eacute;ment avec %d toolchains de compilation par "
                 "t&acirc;che.</p>" % build_per_task)
    parts.append(svg_lines(labels, series("build_geo_index"), "&times;", band=build_band))

    parts.append("<h3>Pic m&eacute;moire du compilateur</h3>")
    parts.append('<p class="cap">En m&eacute;gaoctets bruts : contrairement au temps, '
                 "la m&eacute;moire ne d&eacute;rive pas avec l'&eacute;tat de la machine.</p>")
    parts.append(svg_lines(labels, [(c, n, [e["runtimes"].get(rt, {}).get("build_peak_mb")
                                            for e in entries])
                                    for rt, n, c in HIST_SERIES
                                    if any(e["runtimes"].get(rt, {}).get("build_peak_mb")
                                           for e in entries)],
                           "Mo", nd=0))

    late = latest_context.get("task_baselines", {})
    parts.append("<h3>Par t&acirc;che &mdash; swag release natif, indice corrig&eacute;</h3>")
    parts.append('<p class="cap">Chaque t&acirc;che porte sa propre bande de r&eacute;solution, et '
                 "elles ne se valent pas : une t&acirc;che de quelques millisecondes est bien plus "
                 "sensible &agrave; l'&eacute;tat de la machine qu'une t&acirc;che de cent. Une "
                 "t&acirc;che ajout&eacute;e apr&egrave;s la campagne de r&eacute;f&eacute;rence est "
                 "index&eacute;e sur sa premi&egrave;re campagne, indiqu&eacute;e sous son nom.</p>")
    parts.append('<div class="small-mult">')
    for tid, name, _ in TASKS:
        vals = [e["runtimes"].get("swag-release", {}).get("run_index", {}).get(tid)
                for e in entries]
        band = null_band("run", tid)
        width = half_width(band)
        note = " depuis %s" % late[tid] if tid in late else ""
        if width:
            note += " &middot; r&eacute;solution &plusmn;%.0f&nbsp;%%" % width
        parts.append('<div class="sm"><b>%s<span class="mode">%s</span></b>%s</div>'
                     % (tid, note, svg_lines(labels, [("h-a", "", vals)], "&times;",
                                             compact=True, band=band)))
    parts.append("</div>")

    rows = []
    dirty_seen = False
    busy_seen = False
    for e in reversed(entries):
        m = e["meta"]
        rel = e["runtimes"].get("swag-release", {})
        jit = e["runtimes"].get("swc-jit-release", {})
        context = e.get("context", {})
        dirty_seen = dirty_seen or m.get("dirty")
        drift = e.get("machine_spread_pct")
        if drift is None:
            drift = abs(e.get("drift_pct") or 0.0)
        busy = drift > DRIFT_LIMIT
        busy_seen = busy_seen or busy
        rows.append([
            "swag",
            "<code>%s%s</code>" % (m.get("commit") or "?", "*" if m.get("dirty") else ""),
            m["date"][:10],
            (m.get("label") or "&mdash;"),
            fmt(rel.get("run_geo_adjusted_ms")),
            fmt(jit.get("run_geo_adjusted_ms")),
            fmt(rel.get("build_geo_adjusted_ms"), 0),
            signed_pct(context.get("run_factor")),
            signed_pct(context.get("build_factor")),
            fmt(rel.get("build_peak_mb"), 0),
            fmt(e.get("sample_spread_pct"), 0),
            "<b>%s !</b>" % fmt(drift, 1) if busy else fmt(drift, 1),
        ])
    parts.append("<h3>Journal des campagnes</h3>")
    parts.append(table(["commit", "date", "note", "exec natif corrig&eacute;e (ms)",
                        "exec JIT corrig&eacute;e (ms)", "compil corrig&eacute;e (ms)",
                        "contexte exec (%)", "contexte compil (%)", "m&eacute;moire (Mo)",
                        "&eacute;cart des &eacute;chantillons (%)", "sondes machine (%)"],
                       rows, "wide"))
    parts.append('<p class="cap">Un contexte n&eacute;gatif signifie que les t&eacute;moins ont '
                 "tourn&eacute; plus vite que pendant la campagne de r&eacute;f&eacute;rence ; les temps "
                 "Swag bruts sont alors relev&eacute;s d'autant. La dispersion m&eacute;diane des "
                 "t&eacute;moins de la derni&egrave;re campagne est de %.1f&nbsp;%% en ex&eacute;cution et "
                 "%.1f&nbsp;%% en compilation. L'&eacute;cart des &eacute;chantillons est celui d'un "
                 "runtime avec lui-m&ecirc;me &agrave; l'int&eacute;rieur d'une campagne : il dit si la "
                 "machine &eacute;tait calme ce jour-l&agrave;, l&agrave; o&ugrave; la bande de "
                 "r&eacute;solution dit ce que le banc distingue d'une campagne &agrave; l'autre.</p>" %
                 (latest_context.get("run_dispersion_pct") or 0.0,
                  latest_context.get("build_dispersion_pct") or 0.0))
    if dirty_seen:
        parts.append('<p class="cap">Un ast&eacute;risque marque une campagne mesur&eacute;e '
                     "sur un arbre modifi&eacute; : son commit seul ne la reproduit pas.</p>")
    parts.append('<p class="cap">Les sondes machine sont l\'&eacute;cart maximal de la charge de '
                 "r&eacute;f&eacute;rence, mesur&eacute;e avant chaque t&acirc;che puis aux deux bouts "
                 "du balayage. Au-del&agrave; de %.0f&nbsp;%%, quelque chose d'ext&eacute;rieur "
                 "occupait la machine pendant la mesure et la campagne est archiv&eacute;e sans "
                 "&ecirc;tre publi&eacute;e.</p>" % DRIFT_LIMIT)
    if busy_seen:
        parts.append('<p class="cap">Un point d\'exclamation marque une campagne '
                     "ant&eacute;rieure &agrave; cette r&egrave;gle et qui la violerait : son point "
                     "ne constitue pas une preuve.</p>")
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
    R = latest_campaign()
    T = R["tasks"]
    entries = history.rebuild()

    present = [r[0] for r in RUNTIMES if r[0] in T[TASK_IDS[0]]
               and (T[TASK_IDS[0]][r[0]].get("run") or {}).get("ms")]
    aot = [r for r in present if (T[TASK_IDS[0]][r].get("build") or {}).get("wall_ms")]

    def ms(rt, task):
        return T[task][rt]["run"]["ms"]

    def build(rt, task, key):
        return (T[task][rt].get("build") or {}).get(key)

    best = {t: min(ms(r, t) for r in present) for t in TASK_IDS}
    ratio = {r: {t: ms(r, t) / best[t] for t in TASK_IDS} for r in present}
    gm = {r: geo([ratio[r][t] for t in TASK_IDS]) for r in present}
    bgeo = {r: geo([build(r, t, "wall_ms") for t in TASK_IDS]) for r in aot}
    bmem = {r: max(build(r, t, "peak_bytes") for t in TASK_IDS) / 1048576.0 for r in aot}
    exekb = {r: geo([build(r, t, "exe_bytes") for t in TASK_IDS]) / 1024.0 for r in aot}
    rmem = {r: max(T[t][r]["run"]["peak_bytes"] for t in TASK_IDS) for r in present}

    swag = gm["swag-release"]
    best_rt = min(present, key=lambda r: gm[r])
    jit_gap = (gm["swc-jit-release"] / swag - 1.0) * 100.0
    build_edge = bgeo["cpp-msvc"] / bgeo["swag-release"]

    def stat(value, unit, name, note):
        return ('<div class="stat"><div class="sv">%s<em>%s</em></div>'
                '<div class="sl">%s</div><p>%s</p></div>' % (value, unit, name, note))

    stats = "".join([
        stat(fmt(swag), "&times;", "ex&eacute;cution vs le meilleur",
             "Moyenne g&eacute;om&eacute;trique sur les %d t&acirc;ches. Le meilleur est %s."
             % (len(TASK_IDS), META[best_rt][1])),
        stat("%+.0f" % jit_gap, "%", "JIT swc vs natif swc",
             "Le m&ecirc;me code, compil&eacute; en m&eacute;moire au lieu d'un exe."),
        stat(fmt(build_edge, 1), "&times;", "compilation plus rapide",
             "swc face &agrave; MSVC, m&ecirc;me protocole, ex&eacute;cutable produit."),
        stat("%d" % round(bmem["swag-release"]), "Mo", "pic m&eacute;moire du compilateur",
             "Plancher fixe : m&ecirc;me valeur sur un hello world."),
    ])

    order = sorted(present, key=lambda r: gm[r])
    ex_lo, ex_hi, ex_ticks = log_axis([gm[r] for r in order])
    ex_chart = chart([(r, gm[r], fmt(gm[r])) for r in order],
                     ex_lo, ex_hi, ex_ticks, "&times;")
    ex_table = table(["runtime"] + TASK_IDS + ["moy. g&eacute;o"],
                     [[META[r][3], "%s <span class=\"mode\">%s</span>" % (META[r][1], META[r][2])]
                      + [fmt(ms(r, t)) for t in TASK_IDS] + ["<b>%s</b>" % fmt(gm[r])]
                      for r in order], "wide")
    ra_table = table(["runtime"] + TASK_IDS + ["moy. g&eacute;o"],
                     [[META[r][3], "%s <span class=\"mode\">%s</span>" % (META[r][1], META[r][2])]
                      + [fmt(ratio[r][t]) for t in TASK_IDS] + ["<b>%s</b>" % fmt(gm[r])]
                      for r in order], "wide")

    border = sorted(aot, key=lambda r: bgeo[r])
    bu_lo, bu_hi, bu_ticks = log_axis([bgeo[r] for r in border])
    bu_chart = chart([(r, bgeo[r], fmt(bgeo[r], 0)) for r in border],
                     bu_lo, bu_hi, bu_ticks, "ms")
    bu_table = table(["toolchain"] + TASK_IDS + ["moy. g&eacute;o", "hello"],
                     [[META[r][3], "%s <span class=\"mode\">%s</span>" % (META[r][1], META[r][2])]
                      + [fmt(build(r, t, "wall_ms"), 0) for t in TASK_IDS]
                      + ["<b>%s</b>" % fmt(bgeo[r], 0),
                         fmt((R["hello_build"].get(r) or {}).get("wall_ms"), 0)]
                      for r in border], "wide")

    me_hi, me_ticks = lin_axis([bmem[r] for r in aot])
    me_chart = chart(sorted(((r, bmem[r], fmt(bmem[r], 0)) for r in aot), key=lambda x: -x[1]),
                     0, me_hi, me_ticks, "Mo", "lin")
    rm_hi, rm_ticks = lin_axis([rmem[r] / 1048576.0 for r in present])
    rm_chart = chart(sorted(((r, rmem[r] / 1048576.0, fmt(rmem[r] / 1048576.0, 0))
                             for r in present), key=lambda x: -x[1]),
                     0, rm_hi, rm_ticks, "Mo", "lin")

    hr = R["hello_run"]
    st_lo, st_hi, st_ticks = log_axis([hr[r]["wall_ms"] for r in hr if r in META])
    st_chart = chart(sorted(((r, hr[r]["wall_ms"], fmt(hr[r]["wall_ms"], 0))
                             for r in hr if r in META), key=lambda x: x[1]),
                     st_lo, st_hi, st_ticks, "ms")
    sz_lo, sz_hi, sz_ticks = log_axis([exekb[r] for r in aot])
    sz_chart = chart(sorted(((r, exekb[r], fmt(exekb[r], 0)) for r in aot), key=lambda x: x[1]),
                     sz_lo, sz_hi, sz_ticks, "Ko")

    tt = ['<div class="scroll"><table class="tasks">',
          "<thead><tr><th>t&acirc;che</th><th>ce qu'elle exerce</th>"
          '<th class="num">checksum commun</th></tr></thead><tbody>']
    for tid, name, desc in TASKS:
        tt.append('<tr><th scope="row"><code>%s</code> &nbsp;%s</th><td>%s</td>'
                  '<td class="num">%d</td></tr>'
                  % (tid, name, desc, T[tid]["swag-release"]["run"]["check"]))
    tt.append("</tbody></table></div>")

    m = R["meta"]
    settings = m.get("settings") or {}

    # ---------------------------------------------------- repository README block
    ex_cols = [("swag-release", "swc"), ("swc-jit-release", "swc JIT"),
               ("cpp-clang-cl", "clang-cl"), ("rust", "rustc"),
               ("luajit2.1", "LuaJIT"), ("node20", "Node 20"),
               ("python3.12", "CPython 3.12")]
    bu_cols = [("swag-release", "swc"), ("cpp-clang-cl", "clang-cl"), ("rust", "rustc")]
    ex_cols = [c for c in ex_cols if c[0] in present]
    bu_cols = [c for c in bu_cols if c[0] in aot]
    readme = [
        "",
        "%s programs, written by hand and identically in every language, none of them using a "
        "standard library" % spelled(len(TASK_IDS)),
        "container: each one reimplements its own hash map, heap, or matrix, so the benchmark "
        "measures the",
        "compiler rather than somebody's hash table. All ports print the same checksum.",
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
        "**Compilation**, from source to a linked executable:",
        "",
        md_table(["program"] + [name for _, name in bu_cols],
                 [["`%s`" % t] + [fmt(build(r, t, "wall_ms"), 1) for r, _ in bu_cols]
                  for t in TASK_IDS]),
        "",
        "Native code runs within about **%sx of clang-cl** on those %s programs (geometric "
        "mean), while the" % (fmt(gm["swag-release"] / gm["cpp-clang-cl"], 1),
                              spelled(len(TASK_IDS)).lower()),
        "compiler produces them roughly **%sx faster** than `clang-cl` and **%sx faster** than "
        "`rustc`, linker" % (fmt(bgeo["cpp-clang-cl"] / bgeo["swag-release"], 1),
                             fmt(bgeo["rust"] / bgeo["swag-release"], 1)),
        "included. A hello world compiles and links in %s ms."
        % fmt((R["hello_build"].get("swag-release") or {}).get("wall_ms"), 0),
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
        "against ten control",
        "> runtimes, and states the resolution below which it can see nothing at all. See "
        "[bench/](bench) for",
        "> the method, the fourteen runtimes, and the rules that keep the numbers honest.",
        "",
    ]
    if write_repo_readme("\n".join(readme)):
        print("repository README refreshed from campaign %s" % m["stamp"])

    subs = {
        "{{stats}}": stats,
        "{{ex_chart}}": ex_chart, "{{ex_table}}": ex_table, "{{ra_table}}": ra_table,
        "{{bu_chart}}": bu_chart, "{{bu_table}}": bu_table,
        "{{me_chart}}": me_chart, "{{rm_chart}}": rm_chart,
        "{{st_chart}}": st_chart, "{{sz_chart}}": sz_chart,
        "{{task_table}}": "\n".join(tt),
        "{{history}}": history_section(entries),
        "{{swag_geo}}": fmt(swag),
        "{{best_name}}": META[best_rt][1],
        "{{jit_gap}}": "%+.1f" % jit_gap,
        "{{jit_gap_abs}}": "%.0f" % abs(jit_gap),
        "{{build_edge}}": fmt(build_edge, 1),
        "{{drift}}": "%+.1f" % R["calibration"]["drift_pct"],
        "{{machine_spread}}": fmt(R["calibration"].get("spread_pct"), 1),
        "{{calib_start}}": fmt(R["calibration"]["start"], 3),
        "{{calib_end}}": fmt(R["calibration"]["end"], 3),
        "{{swag_build}}": fmt(bgeo["swag-release"], 0),
        "{{swiftc_edge}}": fmt(bgeo["swift"] / bgeo["swag-release"], 0),
        "{{aot_edge}}": fmt(bgeo["csharp-aot"] / bgeo["swag-release"], 0),
        "{{rustc_edge}}": fmt(bgeo["rust"] / bgeo["swag-release"], 1),
        "{{luajit_geo}}": fmt(gm["luajit2.1"]),
        "{{jitswag_geo}}": fmt(gm["swc-jit-release"]),
        "{{sha_swag}}": fmt(ms("swag-release", "sha256")),
        "{{sha_best}}": fmt(best["sha256"]),
        "{{sha_fd}}": fmt(ms("swag-fast-debug", "sha256")),
        "{{sha_fd_ratio}}": fmt(ms("swag-fast-debug", "sha256") / ms("swag-release", "sha256"), 1),
        "{{worst_task}}": max(TASK_IDS, key=lambda t: ratio["swag-release"][t]),
        "{{worst_ratio}}": fmt(max(ratio["swag-release"][t] for t in TASK_IDS)),
        "{{best_task}}": min(TASK_IDS, key=lambda t: ratio["swag-release"][t]),
        "{{best_ratio}}": fmt(min(ratio["swag-release"][t] for t in TASK_IDS)),
        "{{provenance}}": ("arbre modifi&eacute; au moment de la mesure : ce commit seul ne la "
                           "reproduit pas" if m.get("dirty")
                           else "Release x64 reconstruit depuis ce commit avant la mesure"),
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
        "{{ntasks}}": str(len(TASK_IDS)),
        "{{nruntimes}}": str(len(present)),
        "{{nbinaries}}": str(len(TASK_IDS) * len(present)),
        "{{skipped}}": (", ".join(R.get("skipped") or []) or "aucune"),
    }

    html = open(TEMPLATE, encoding="utf-8").read()
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
