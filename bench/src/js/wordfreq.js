const VOCAB = 5000;
const WORDS = 2000000;

let seed = 12345;
function rnd() {
    seed = (seed * 16807) % 2147483647;
    return seed;
}

function makeWord(i) {
    let n = i + 1;
    const L = 3 + (i % 6);
    let out = "";
    for (let k = 0; k < L; k++) {
        out += String.fromCharCode(97 + (n % 26));
        n = Math.floor(n / 26) + 7 * k;
    }
    return out;
}

// ---- data generation (not timed) ----
const vocab = [];
for (let i = 0; i < VOCAB; i++) vocab.push(makeWord(i));

const pieces = [];
for (let j = 0; j < WORDS; j++) {
    pieces.push(vocab[rnd() % VOCAB]);
    pieces.push((j + 1) % 12 === 0 ? "\n" : " ");
}
const text = pieces.join("");

// ---- timed work ----
const t0 = performance.now();

const counts = new Map();
const n = text.length;
let start = -1;
for (let i = 0; i < n; i++) {
    const c = text.charCodeAt(i);
    if (c >= 97 && c <= 122) {
        if (start < 0) start = i;
    } else if (start >= 0) {
        const tok = text.slice(start, i);
        const v = counts.get(tok);
        counts.set(tok, v === undefined ? 1 : v + 1);
        start = -1;
    }
}
if (start >= 0) {
    const tok = text.slice(start, n);
    const v = counts.get(tok);
    counts.set(tok, v === undefined ? 1 : v + 1);
}

const items = [];
for (const [w, c] of counts) items.push([c, w]);
items.sort((x, y) => (x[0] !== y[0] ? y[0] - x[0] : (x[1] < y[1] ? -1 : x[1] > y[1] ? 1 : 0)));

let check = counts.size * 7;
for (let k = 0; k < 20; k++) check += (k + 1) * items[k][0];

const t1 = performance.now();
console.log("CHECK=" + check + " MS=" + (t1 - t0).toFixed(3));
