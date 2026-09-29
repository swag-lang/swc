package main

import common "common"

DATA_SIZE :: u64(1 << 20)
WORDS :: u64(512)
HASH_SIZE :: u64(65536)
WINDOW :: i64(32768)
MIN_MATCH :: i64(4)
MAX_MATCH :: i64(258)
MAX_CHAIN :: i64(32)

hash_at :: proc(d: [^]u8, p: i64) -> u64 {
    return (((u64(d[p]) * 33 + u64(d[p + 1])) * 33 + u64(d[p + 2])) * 33 + u64(d[p + 3])) % HASH_SIZE
}

main :: proc() {
    // Data generation is not timed.
    letters: [^]u8 = ([^]u8)(common.xalloc(WORDS * 10))
    word_start: [^]u64 = ([^]u64)(common.xalloc(WORDS * size_of(u64)))
    word_len: [^]u64 = ([^]u64)(common.xalloc(WORDS * size_of(u64)))
    used: u64 = 0
    for k: u64 = 0; k < WORDS; k += 1 {
        length: u64 = 2 + common.rnd() % 8
        word_start[k] = used
        word_len[k] = length
        for j: u64 = 0; j < length; j += 1 {
            letters[used + j] = u8(97 + common.rnd() % 26)
        }
        used += length
    }

    n: i64 = i64(DATA_SIZE)
    data: [^]u8 = ([^]u8)(common.xalloc(DATA_SIZE))
    pos: i64 = 0
    for pos < n {
        w := common.rnd() % WORDS
        for j: u64 = 0; j < word_len[w] && pos < n; j += 1 {
            data[pos] = letters[word_start[w] + j]
            pos += 1
        }
        if pos < n {
            data[pos] = ' '
            pos += 1
        }
    }

    // Timed work starts after data generation.
    t0: f64 = common.now()

    head: [^]i64 = ([^]i64)(common.xalloc(HASH_SIZE * size_of(i64)))
    prev: [^]i64 = ([^]i64)(common.xalloc(u64(WINDOW) * size_of(i64)))
    for k: u64 = 0; k < HASH_SIZE; k += 1 {
        head[k] = -1
    }
    for k: i64 = 0; k < WINDOW; k += 1 {
        prev[k] = -1
    }

    comp: [^]u8 = ([^]u8)(common.xalloc(DATA_SIZE * 2 + 16))
    csize: i64 = 0

    i: i64 = 0
    for i + MIN_MATCH <= n {
        best: i64 = 0
        dist: i64 = 0
        limit: i64 = n - i < MAX_MATCH ? n - i : MAX_MATCH
        h := hash_at(data, i)
        cand := head[h]
        chain: i64 = 0
        for cand >= 0 && i - cand < WINDOW && chain < MAX_CHAIN {
            l: i64 = 0
            for l < limit && data[cand + l] == data[i + l] {
                l += 1
            }
            if l > best {
                best = l
                dist = i - cand
                if l == limit {
                    break
                }
            }
            cand = prev[cand % WINDOW]
            chain += 1
        }

        prev[i % WINDOW] = head[h]
        head[h] = i

        if best >= MIN_MATCH {
            comp[csize] = 1
            comp[csize + 1] = u8(best - MIN_MATCH)
            comp[csize + 2] = u8((dist - 1) % 256)
            comp[csize + 3] = u8((dist - 1) / 256)
            csize += 4
            for p := i + 1; p < i + best; p += 1 {
                if p + MIN_MATCH <= n {
                    hp := hash_at(data, p)
                    prev[p % WINDOW] = head[hp]
                    head[hp] = p
                }
            }
            i += best
        } else {
            comp[csize] = 0
            comp[csize + 1] = data[i]
            csize += 2
            i += 1
        }
    }

    for i < n {
        comp[csize] = 0
        comp[csize + 1] = data[i]
        csize += 2
        i += 1
    }

    // Decompress and verify.
    out: [^]u8 = ([^]u8)(common.xalloc(DATA_SIZE))
    o: i64 = 0
    c: i64 = 0
    for c < csize {
        if comp[c] == 0 {
            out[o] = comp[c + 1]
            o += 1
            c += 2
        } else {
            length := i64(comp[c + 1]) + MIN_MATCH
            back := i64(comp[c + 2]) + i64(comp[c + 3]) * 256 + 1
            for k: i64 = 0; k < length; k += 1 {
                out[o] = out[o - back]
                o += 1
            }
            c += 4
        }
    }

    same := o == n
    for k: i64 = 0; same && k < n; k += 1 {
        if out[k] != data[k] {
            same = false
        }
    }

    hc: u64 = 0
    for k: i64 = 0; k < csize; k += 1 {
        hc = (hc * 31 + u64(comp[k])) % 1000003
    }

    check: u64 = same ? u64(csize) * 1000003 + hc : 0

    t1: f64 = common.now()
    common.report(check, t0, t1)

    common.free(out)
    common.free(comp)
    common.free(prev)
    common.free(head)
    common.free(data)
    common.free(word_len)
    common.free(word_start)
    common.free(letters)
}
