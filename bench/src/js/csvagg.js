const ROWS = 400000;
const REGIONS = ["EMEA", "APAC", "AMER", "LATAM", "NORDIC", "IBERIA", "BENELUX", "DACH"];

let seed = 12345;
function rnd() {
    seed = (seed * 16807) % 2147483647;
    return seed;
}

function pad2(v) {
    return v < 10 ? "0" + v : "" + v;
}

// ---- data generation (not timed) ----
const lines = [];
for (let j = 0; j < ROWS; j++) {
    const region = REGIONS[rnd() % 8];
    const y = 2024 + (rnd() % 3);
    const m = 1 + (rnd() % 12);
    const d = 1 + (rnd() % 28);
    const qty = 1 + (rnd() % 50);
    const cents = 100 + (rnd() % 99900);
    lines.push(j + "," + region + "," + y + "-" + pad2(m) + "-" + pad2(d) + "," + qty + "," +
        Math.floor(cents / 100) + "." + pad2(cents % 100));
}
const text = lines.join("\n");

// ---- timed work ----
const t0 = performance.now();

const n = text.length;
const agg = new Map();
let pos = 0;
let rows = 0;
while (pos < n) {
    let eol = pos;
    while (eol < n && text.charCodeAt(eol) !== 10) eol++;

    // field 0: id
    let p = pos;
    while (p < eol && text.charCodeAt(p) !== 44) p++;
    p++;

    // field 1: region
    const rs = p;
    while (p < eol && text.charCodeAt(p) !== 44) p++;
    const region = text.slice(rs, p);
    p++;

    // field 2: date (skipped)
    while (p < eol && text.charCodeAt(p) !== 44) p++;
    p++;

    // field 3: qty
    let qty = 0;
    while (p < eol && text.charCodeAt(p) !== 44) {
        qty = qty * 10 + (text.charCodeAt(p) - 48);
        p++;
    }
    p++;

    // field 4: price
    let ip = 0;
    while (p < eol && text.charCodeAt(p) !== 46) {
        ip = ip * 10 + (text.charCodeAt(p) - 48);
        p++;
    }
    p++;
    let fr = 0;
    while (p < eol) {
        fr = fr * 10 + (text.charCodeAt(p) - 48);
        p++;
    }
    const price = ip + fr / 100.0;

    const e = agg.get(region);
    if (e === undefined) {
        agg.set(region, [1, qty, qty * price, price]);
    } else {
        e[0] += 1;
        e[1] += qty;
        e[2] += qty * price;
        if (price > e[3]) e[3] = price;
    }

    rows++;
    pos = eol + 1;
}

const keys = Array.from(agg.keys()).sort();
let check = rows;
for (let k = 0; k < keys.length; k++) {
    const e = agg.get(keys[k]);
    check += (k + 1) * (Math.floor(e[2] * 100.0 + 0.5) % 1000003);
    check += e[0] + e[1] + Math.floor(e[3] * 100.0 + 0.5);
}

const t1 = performance.now();
console.log("CHECK=" + check + " MS=" + (t1 - t0).toFixed(3));
