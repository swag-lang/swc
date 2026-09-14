// Same data, arithmetic and timed region as the other benchmark ports.
const common = @import("common.zig");
const rnd = common.rnd;
const now = common.now;
const report = common.report;
const xalloc = common.xalloc;
const free = common.free;

const N: u64 = 800;
const NN: u64 = (N * N);
const INF: u64 = 0x0FFFFFFFFFFFFFFF;
var g_HeapD: [*]u64 = undefined;
var g_HeapN: [*]u64 = undefined;
var g_HeapSize: u64 = 0;
var g_PopD: u64 = 0;
var g_PopN: u64 = 0;
fn push(d: u64, node: u64) void {
    var i: u64 = g_HeapSize;
    g_HeapSize += 1;
    g_HeapD[i] = d;
    g_HeapN[i] = node;
    while ((i > 0)) {
        const p: u64 = ((i - 1) >> @intCast(1));
        if ((g_HeapD[p] <= g_HeapD[i])) {
            break;
        }
        const td: u64 = g_HeapD[p];
        g_HeapD[p] = g_HeapD[i];
        g_HeapD[i] = td;
        const tn: u64 = g_HeapN[p];
        g_HeapN[p] = g_HeapN[i];
        g_HeapN[i] = tn;
        i = p;
    }
}

fn pop() void {
    g_PopD = g_HeapD[0];
    g_PopN = g_HeapN[0];
    g_HeapSize -= 1;
    g_HeapD[0] = g_HeapD[g_HeapSize];
    g_HeapN[0] = g_HeapN[g_HeapSize];
    var i: u64 = 0;
    while (true) {
        const l: u64 = ((2 * i) + 1);
        if ((l >= g_HeapSize)) {
            break;
        }
        const r: u64 = (l + 1);
        var m: u64 = l;
        if (((r < g_HeapSize) and (g_HeapD[r] < g_HeapD[l]))) {
            m = r;
        }
        if ((g_HeapD[i] <= g_HeapD[m])) {
            break;
        }
        const td: u64 = g_HeapD[m];
        g_HeapD[m] = g_HeapD[i];
        g_HeapD[i] = td;
        const tn: u64 = g_HeapN[m];
        g_HeapN[m] = g_HeapN[i];
        g_HeapN[i] = tn;
        i = m;
    }
}

pub fn main() void {
    const weight: [*]u64 = @ptrCast(@alignCast(xalloc((NN * @sizeOf(u64)))));
    {
        var i: u64 = 0;
        while ((i < NN)) : (i += 1) {
            weight[i] = (1 + (rnd() % 9));
        }
    }
    const t0: f64 = now();
    const dist: [*]u64 = @ptrCast(@alignCast(xalloc((NN * @sizeOf(u64)))));
    {
        var i: u64 = 0;
        while ((i < NN)) : (i += 1) {
            dist[i] = INF;
        }
    }
    g_HeapD = @ptrCast(@alignCast(xalloc(((NN * 4) * @sizeOf(u64)))));
    g_HeapN = @ptrCast(@alignCast(xalloc(((NN * 4) * @sizeOf(u64)))));
    g_HeapSize = 0;
    dist[0] = 0;
    push(0, 0);
    var pops: u64 = 0;
    const Target: u64 = (NN - 1);
    while ((g_HeapSize > 0)) {
        pop();
        const d: u64 = g_PopD;
        const u: u64 = g_PopN;
        pops += 1;
        if ((d > dist[u])) {
            continue;
        }
        if ((u == Target)) {
            break;
        }
        const x: u64 = (u % N);
        const y: u64 = (u / N);
        if ((x > 0)) {
            const v: u64 = (u - 1);
            const nd: u64 = (d + weight[v]);
            if ((nd < dist[v])) {
                dist[v] = nd;
                push(nd, v);
            }
        }
        if ((x < (N - 1))) {
            const v: u64 = (u + 1);
            const nd: u64 = (d + weight[v]);
            if ((nd < dist[v])) {
                dist[v] = nd;
                push(nd, v);
            }
        }
        if ((y > 0)) {
            const v: u64 = (u - N);
            const nd: u64 = (d + weight[v]);
            if ((nd < dist[v])) {
                dist[v] = nd;
                push(nd, v);
            }
        }
        if ((y < (N - 1))) {
            const v: u64 = (u + N);
            const nd: u64 = (d + weight[v]);
            if ((nd < dist[v])) {
                dist[v] = nd;
                push(nd, v);
            }
        }
    }
    const check: u64 = ((dist[Target] * 1000) + (pops % 1000));
    const t1: f64 = now();
    report(check, t0, t1);
    free(g_HeapN);
    free(g_HeapD);
    free(dist);
    free(weight);
    return;
}

