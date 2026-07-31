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

TASKS = [
    ("wordfreq", "comptage de mots", "table de hachage maison sur 2 M mots, puis tri"),
    ("csvagg", "agr&eacute;gation CSV", "400 k lignes, parsing octet &agrave; octet, flottants"),
    ("sha256", "SHA-256", "512 Ko, ALU enti&egrave;re pure, rotations"),
    ("dijkstra", "Dijkstra", "grille 800&times;800, tas binaire"),
    ("raytrace", "lancer de rayons", "480&times;360, f64, r&eacute;cursion"),
    ("leven", "Levenshtein", "40 requ&ecirc;tes contre 6000 mots"),
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

HIST_SERIES = [
    ("swag-release",       "release natif",    "h-a"),
    ("swc-jit-release",    "release JIT",      "h-b"),
    ("swag-fast-debug",    "fast-debug natif", "h-c"),
    ("swc-jit-fast-debug", "fast-debug JIT",   "h-d"),
]


def latest_campaign():
    files = sorted(glob.glob(os.path.join(BENCH, "results", "*.json")))
    if not files:
        raise SystemExit("no campaign in bench/results — run campaign.py first")
    with open(files[-1], encoding="utf-8") as f:
        return json.load(f)


def fmt(v, nd=2):
    return "&mdash;" if v is None else ("%." + str(nd) + "f") % v


def geo(values):
    values = [v for v in values if v]
    return math.exp(sum(math.log(v) for v in values) / len(values)) if values else None


def logw(v, lo, hi):
    return max(0.7, min(100.0, (math.log10(v) - math.log10(lo)) /
                        (math.log10(hi) - math.log10(lo)) * 100.0))


def linw(v, hi):
    return max(0.7, min(100.0, v / hi * 100.0))


# --------------------------------------------------------------------- charts
def chart(rows, lo, hi, ticks, unit, scale="log"):
    out = ['<figure class="chart">', '<div class="axis" aria-hidden="true">']
    for t in ticks:
        pos = logw(t, lo, hi) if scale == "log" else linw(t, hi)
        out.append('<span class="tick" style="left:%.3f%%"><i></i><b>%s</b></span>' % (pos, t))
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


def svg_lines(labels, series, unit, nd=2, zero=False, compact=False):
    """series: list of (css class, legend text, [values, one per campaign]).

    `compact` draws at the size it will actually occupy, so the text is not shrunk
    to nothing by the browser scaling a wide viewBox into a narrow column."""
    flat = [v for _, _, vs in series for v in vs if v is not None]
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

    parts.append("<h3>Ex&eacute;cution &mdash; rapport au C++ de la m&ecirc;me campagne</h3>")
    parts.append('<p class="cap">Normalis&eacute; contre <code>%s</code> mesur&eacute; le m&ecirc;me '
                 "jour : une baisse ici veut dire que swc a progress&eacute;, pas que la machine "
                 "&eacute;tait plus fra&icirc;che.</p>" % tc.REFERENCE)
    parts.append(svg_lines(labels, series("run_geo_ratio"), "&times;"))

    parts.append("<h3>Compilation &mdash; rapport au C++ de la m&ecirc;me campagne</h3>")
    parts.append(svg_lines(labels, series("build_geo_ratio"), "&times;"))

    parts.append("<h3>Pic m&eacute;moire du compilateur</h3>")
    parts.append('<p class="cap">En m&eacute;gaoctets bruts : contrairement au temps, '
                 "la m&eacute;moire ne d&eacute;rive pas avec l'&eacute;tat de la machine.</p>")
    parts.append(svg_lines(labels, [(c, n, [e["runtimes"].get(rt, {}).get("build_peak_mb")
                                            for e in entries])
                                    for rt, n, c in HIST_SERIES
                                    if any(e["runtimes"].get(rt, {}).get("build_peak_mb")
                                           for e in entries)],
                           "Mo", nd=0))

    parts.append("<h3>Par t&acirc;che &mdash; swag release natif, rapport au C++</h3>")
    parts.append('<div class="small-mult">')
    for tid, name, _ in TASKS:
        vals = [e["runtimes"].get("swag-release", {}).get("run_ratio", {}).get(tid)
                for e in entries]
        parts.append('<div class="sm"><b>%s</b>%s</div>'
                     % (tid, svg_lines(labels, [("h-a", "", vals)], "&times;", compact=True)))
    parts.append("</div>")

    rows = []
    dirty_seen = False
    for e in reversed(entries):
        m = e["meta"]
        rel = e["runtimes"].get("swag-release", {})
        jit = e["runtimes"].get("swc-jit-release", {})
        dirty_seen = dirty_seen or m.get("dirty")
        rows.append([
            "swag",
            "<code>%s%s</code>" % (m.get("commit") or "?", "*" if m.get("dirty") else ""),
            m["date"][:10],
            (m.get("label") or "&mdash;"),
            fmt(rel.get("run_geo_ratio")),
            fmt(jit.get("run_geo_ratio")),
            fmt(rel.get("build_geo_ms"), 0),
            fmt(rel.get("build_peak_mb"), 0),
            fmt(e.get("drift_pct"), 1),
        ])
    parts.append("<h3>Journal des campagnes</h3>")
    parts.append(table(["commit", "date", "note", "exec natif", "exec JIT",
                        "compil (ms)", "m&eacute;moire (Mo)", "d&eacute;rive (%)"],
                       rows, "wide"))
    if dirty_seen:
        parts.append('<p class="cap">Un ast&eacute;risque marque une campagne mesur&eacute;e '
                     "sur un arbre modifi&eacute; : son commit seul ne la reproduit pas.</p>")
    return "\n".join(parts)


# ----------------------------------------------------------------------- main
def main():
    R = latest_campaign()
    T = R["tasks"]
    entries = history.load()

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
             "Moyenne g&eacute;om&eacute;trique sur les 6 t&acirc;ches. Le meilleur est %s."
             % META[best_rt][1]),
        stat("%+.0f" % jit_gap, "%", "JIT swc vs natif swc",
             "Le m&ecirc;me code, compil&eacute; en m&eacute;moire au lieu d'un exe."),
        stat(fmt(build_edge, 1), "&times;", "compilation plus rapide",
             "swc face &agrave; MSVC, m&ecirc;me protocole, ex&eacute;cutable produit."),
        stat("%d" % round(bmem["swag-release"]), "Mo", "pic m&eacute;moire du compilateur",
             "Plancher fixe : m&ecirc;me valeur sur un hello world."),
    ])

    order = sorted(present, key=lambda r: gm[r])
    ex_chart = chart([(r, gm[r], fmt(gm[r])) for r in order], 1, 128,
                     [1, 2, 4, 8, 16, 32, 64, 128], "&times;")
    ex_table = table(["runtime"] + TASK_IDS + ["moy. g&eacute;o"],
                     [[META[r][3], "%s <span class=\"mode\">%s</span>" % (META[r][1], META[r][2])]
                      + [fmt(ms(r, t)) for t in TASK_IDS] + ["<b>%s</b>" % fmt(gm[r])]
                      for r in order], "wide")
    ra_table = table(["runtime"] + TASK_IDS + ["moy. g&eacute;o"],
                     [[META[r][3], "%s <span class=\"mode\">%s</span>" % (META[r][1], META[r][2])]
                      + [fmt(ratio[r][t]) for t in TASK_IDS] + ["<b>%s</b>" % fmt(gm[r])]
                      for r in order], "wide")

    border = sorted(aot, key=lambda r: bgeo[r])
    bu_chart = chart([(r, bgeo[r], fmt(bgeo[r], 0)) for r in border], 64, 8192,
                     [64, 128, 256, 512, 1024, 2048, 4096, 8192], "ms")
    bu_table = table(["toolchain"] + TASK_IDS + ["moy. g&eacute;o", "hello"],
                     [[META[r][3], "%s <span class=\"mode\">%s</span>" % (META[r][1], META[r][2])]
                      + [fmt(build(r, t, "wall_ms"), 0) for t in TASK_IDS]
                      + ["<b>%s</b>" % fmt(bgeo[r], 0),
                         fmt((R["hello_build"].get(r) or {}).get("wall_ms"), 0)]
                      for r in border], "wide")

    me_chart = chart(sorted(((r, bmem[r], fmt(bmem[r], 0)) for r in aot), key=lambda x: -x[1]),
                     0, 400, [0, 100, 200, 300, 400], "Mo", "lin")
    rm_chart = chart(sorted(((r, rmem[r] / 1048576.0, fmt(rmem[r] / 1048576.0, 0))
                             for r in present), key=lambda x: -x[1]),
                     0, 260, [0, 65, 130, 195, 260], "Mo", "lin")

    hr = R["hello_run"]
    st_chart = chart(sorted(((r, hr[r]["wall_ms"], fmt(hr[r]["wall_ms"], 0))
                             for r in hr if r in META), key=lambda x: x[1]),
                     15, 128, [15, 30, 60, 120], "ms")
    sz_chart = chart(sorted(((r, exekb[r], fmt(exekb[r], 0)) for r in aot), key=lambda x: x[1]),
                     4, 2048, [4, 16, 64, 256, 1024], "Ko")

    tt = ['<div class="scroll"><table class="tasks">',
          "<thead><tr><th>t&acirc;che</th><th>ce qu'elle exerce</th>"
          '<th class="num">checksum commun</th></tr></thead><tbody>']
    for tid, name, desc in TASKS:
        tt.append('<tr><th scope="row"><code>%s</code> &nbsp;%s</th><td>%s</td>'
                  '<td class="num">%d</td></tr>'
                  % (tid, name, desc, T[tid]["swag-release"]["run"]["check"]))
    tt.append("</tbody></table></div>")

    m = R["meta"]
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
