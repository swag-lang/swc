package main

import "time"

func main() {
	const n = 9
	var perm, perm1, count [n]int
	start := time.Now()
	for i := range perm1 {
		perm1[i] = i
	}
	checksum, maxFlips, permCount, r := 0, 0, 0, n
	for {
		for r != 1 {
			count[r-1] = r
			r--
		}
		for i := range perm {
			perm[i] = perm1[i]
		}
		flips := 0
		for k := perm[0]; k != 0; k = perm[0] {
			for i, j := 0, k; i < j; i, j = i+1, j-1 {
				perm[i], perm[j] = perm[j], perm[i]
			}
			flips++
		}
		if flips > maxFlips {
			maxFlips = flips
		}
		if permCount%2 == 0 {
			checksum += flips
		} else {
			checksum -= flips
		}
		done := false
		for {
			if r == n {
				done = true
				break
			}
			p := perm1[0]
			for i := 0; i < r; i++ {
				perm1[i] = perm1[i+1]
			}
			perm1[r] = p
			count[r]--
			if count[r] > 0 {
				break
			}
			r++
		}
		if done {
			break
		}
		permCount++
	}
	report(checksum*1000+maxFlips, start)
}
