const N = 300000;

let seed = 12345;
function rnd() {
    seed = (seed * 16807) % 2147483647;
    return seed;
}

function qsort(a, lo, hi) {
    while (hi - lo > 16) {
        const mid = lo + Math.floor((hi - lo) / 2);
        let t;
        if (a[mid] < a[lo]) { t = a[lo]; a[lo] = a[mid]; a[mid] = t; }
        if (a[hi] < a[lo]) { t = a[lo]; a[lo] = a[hi]; a[hi] = t; }
        if (a[hi] < a[mid]) { t = a[mid]; a[mid] = a[hi]; a[hi] = t; }

        const pivot = a[mid];
        let i = lo;
        let j = hi;
        do {
            while (a[i] < pivot) i++;
            while (a[j] > pivot) j--;
            if (i <= j) {
                t = a[i]; a[i] = a[j]; a[j] = t;
                i++;
                j--;
            }
        } while (i <= j);

        // recurse into the smaller side, loop on the larger one
        if (j - lo < hi - i) {
            qsort(a, lo, j);
            lo = i;
        } else {
            qsort(a, i, hi);
            hi = j;
        }
    }

    for (let i = lo + 1; i <= hi; i++) {
        const v = a[i];
        let j = i - 1;
        while (j >= lo && a[j] > v) {
            a[j + 1] = a[j];
            j--;
        }
        a[j + 1] = v;
    }
}

// ---- data generation (not timed) ----
const a = new Array(N);
for (let i = 0; i < N; i++) a[i] = rnd();

// ---- timed work ----
const t0 = performance.now();

qsort(a, 0, N - 1);

let sorted = true;
for (let i = 1; i < N; i++) {
    if (a[i - 1] > a[i]) sorted = false;
}

let check = 0;
if (sorted) {
    for (let i = 0; i < N; i++) check += (a[i] % 1000) * (i % 7 + 1);
}

const t1 = performance.now();
console.log("CHECK=" + check + " MS=" + (t1 - t0).toFixed(3));
