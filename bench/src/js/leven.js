const DICT = 6000;
const QUERIES = 40;
const MAXLEN = 3;

let seed = 12345;
function rnd() {
    seed = (seed * 16807) % 2147483647;
    return seed;
}

function makeWord(i) {
    let n = i + 1;
    const L = 4 + (i % 7);
    let out = "";
    for (let k = 0; k < L; k++) {
        out += String.fromCharCode(97 + (n % 26));
        n = Math.floor(n / 26) + 7 * k;
    }
    return out;
}

// ---- data generation (not timed) ----
const words = [];
for (let i = 0; i < DICT; i++) words.push(makeWord(i));

const queries = [];
for (let q = 0; q < QUERIES; q++) {
    const src = words[rnd() % DICT];
    const w = src.split("");
    for (let m = 0; m < 2; m++) {
        const p = rnd() % w.length;
        const op = rnd() % 3;
        const c = String.fromCharCode(97 + (rnd() % 26));
        if (op === 0) {
            w[p] = c;
        } else if (op === 1) {
            if (w.length > 2) w.splice(p, 1);
        } else {
            w.splice(p, 0, c);
        }
    }
    queries.push(w.join(""));
}

// ---- timed work ----
const t0 = performance.now();

const row0 = new Array(64).fill(0);
const row1 = new Array(64).fill(0);

let check = 0;
for (let q = 0; q < QUERIES; q++) {
    const a = queries[q];
    const la = a.length;
    let best = 1073741824;
    let bestIdx = -1;
    for (let i = 0; i < DICT; i++) {
        const b = words[i];
        const lb = b.length;
        let d = la - lb;
        if (d < 0) d = -d;
        if (d > MAXLEN) continue;
        for (let j = 0; j <= lb; j++) row0[j] = j;
        for (let x = 0; x < la; x++) {
            row1[0] = x + 1;
            const ca = a.charCodeAt(x);
            for (let y = 0; y < lb; y++) {
                const cost = ca === b.charCodeAt(y) ? 0 : 1;
                let v = row0[y] + cost;
                let v2 = row0[y + 1] + 1;
                if (v2 < v) v = v2;
                v2 = row1[y] + 1;
                if (v2 < v) v = v2;
                row1[y + 1] = v;
            }
            for (let j = 0; j <= lb; j++) row0[j] = row1[j];
        }
        const dd = row0[lb];
        if (dd < best) {
            best = dd;
            bestIdx = i;
        }
    }
    check += best * 31 + bestIdx;
}

const t1 = performance.now();
console.log("CHECK=" + check + " MS=" + (t1 - t0).toFixed(3));
