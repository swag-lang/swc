const N = 9;

// ---- data generation (not timed) ----
const perm = new Array(N).fill(0);
const perm1 = new Array(N).fill(0);
const count = new Array(N).fill(0);

// ---- timed work ----
const t0 = performance.now();

for (let i = 0; i < N; i++) perm1[i] = i;

let checksum = 0;
let maxFlips = 0;
let permCount = 0;
let r = N;

for (;;) {
    while (r !== 1) {
        count[r - 1] = r;
        r--;
    }

    for (let i = 0; i < N; i++) perm[i] = perm1[i];

    let flips = 0;
    let k = perm[0];
    while (k !== 0) {
        let i = 0;
        let j = k;
        while (i < j) {
            const t = perm[i]; perm[i] = perm[j]; perm[j] = t;
            i++;
            j--;
        }
        flips++;
        k = perm[0];
    }

    if (flips > maxFlips) maxFlips = flips;
    if (permCount % 2 === 0) checksum += flips;
    else checksum -= flips;

    // rotate the prefix to reach the next permutation
    let done = false;
    for (;;) {
        if (r === N) {
            done = true;
            break;
        }
        const perm0 = perm1[0];
        for (let i = 0; i < r; i++) perm1[i] = perm1[i + 1];
        perm1[r] = perm0;
        count[r]--;
        if (count[r] > 0) break;
        r++;
    }
    if (done) break;
    permCount++;
}

const check = checksum * 1000 + maxFlips;

const t1 = performance.now();
console.log("CHECK=" + check + " MS=" + (t1 - t0).toFixed(3));
