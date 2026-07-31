const N = 800;
const NN = N * N;

let seed = 12345;
function rnd() {
    seed = (seed * 16807) % 2147483647;
    return seed;
}

// ---- data generation (not timed) ----
const weight = new Array(NN);
for (let i = 0; i < NN; i++) weight[i] = 1 + (rnd() % 9);

// ---- timed work ----
const t0 = performance.now();

const INF = 1e18;
const dist = new Array(NN).fill(INF);

const hd = new Array(NN * 4).fill(0);
const hn = new Array(NN * 4).fill(0);
let hsize = 0;

function push(d, node) {
    let i = hsize;
    hsize++;
    hd[i] = d;
    hn[i] = node;
    while (i > 0) {
        const p = (i - 1) >> 1;
        if (hd[p] <= hd[i]) break;
        let t = hd[p]; hd[p] = hd[i]; hd[i] = t;
        t = hn[p]; hn[p] = hn[i]; hn[i] = t;
        i = p;
    }
}

let popD = 0, popN = 0;
function pop() {
    popD = hd[0];
    popN = hn[0];
    hsize--;
    hd[0] = hd[hsize];
    hn[0] = hn[hsize];
    let i = 0;
    for (;;) {
        const l = 2 * i + 1;
        if (l >= hsize) break;
        const r = l + 1;
        let m = l;
        if (r < hsize && hd[r] < hd[l]) m = r;
        if (hd[i] <= hd[m]) break;
        let t = hd[m]; hd[m] = hd[i]; hd[i] = t;
        t = hn[m]; hn[m] = hn[i]; hn[i] = t;
        i = m;
    }
}

dist[0] = 0;
push(0, 0);
let pops = 0;
const target = NN - 1;

while (hsize > 0) {
    pop();
    const d = popD, u = popN;
    pops++;
    if (d > dist[u]) continue;
    if (u === target) break;
    const x = u % N;
    const y = Math.floor(u / N);
    if (x > 0) {
        const v = u - 1, nd = d + weight[v];
        if (nd < dist[v]) { dist[v] = nd; push(nd, v); }
    }
    if (x < N - 1) {
        const v = u + 1, nd = d + weight[v];
        if (nd < dist[v]) { dist[v] = nd; push(nd, v); }
    }
    if (y > 0) {
        const v = u - N, nd = d + weight[v];
        if (nd < dist[v]) { dist[v] = nd; push(nd, v); }
    }
    if (y < N - 1) {
        const v = u + N, nd = d + weight[v];
        if (nd < dist[v]) { dist[v] = nd; push(nd, v); }
    }
}

const check = dist[target] * 1000 + (pops % 1000);

const t1 = performance.now();
console.log("CHECK=" + check + " MS=" + (t1 - t0).toFixed(3));
