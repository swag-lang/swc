package main

import "time"

func main() {
	words := make([][]byte, 6000)
	for i := range words {
		words[i] = makeWord(i, 4, 7)
	}
	queries := make([][]byte, 40)
	for q := range queries {
		w := append([]byte(nil), words[rnd()%len(words)]...)
		for m := 0; m < 2; m++ {
			p, op, c := rnd()%len(w), rnd()%3, byte(97+rnd()%26)
			switch op {
			case 0:
				w[p] = c
			case 1:
				if len(w) > 2 {
					w = append(w[:p], w[p+1:]...)
				}
			case 2:
				w = append(w, 0)
				copy(w[p+1:], w[p:])
				w[p] = c
			}
		}
		queries[q] = w
	}
	start := time.Now()
	var row0, row1 [64]int
	check := 0
	for _, a := range queries {
		best, bestIdx := 1<<30, -1
		for i, b := range words {
			d := len(a) - len(b)
			if d < 0 {
				d = -d
			}
			if d > 3 {
				continue
			}
			for j := 0; j <= len(b); j++ {
				row0[j] = j
			}
			for x, ca := range a {
				row1[0] = x + 1
				for y, cb := range b {
					cost := 1
					if ca == cb {
						cost = 0
					}
					v := row0[y] + cost
					if v2 := row0[y+1] + 1; v2 < v {
						v = v2
					}
					if v2 := row1[y] + 1; v2 < v {
						v = v2
					}
					row1[y+1] = v
				}
				for j := 0; j <= len(b); j++ {
					row0[j] = row1[j]
				}
			}
			if row0[len(b)] < best {
				best, bestIdx = row0[len(b)], i
			}
		}
		check += best*31 + bestIdx
	}
	report(check, start)
}
