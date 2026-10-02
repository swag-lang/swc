package main

import "time"

const hashSize, window, minMatch, maxMatch, maxChain = 65536, 32768, 4, 258, 32

func hashAt(data []byte, p int) int {
	return (((int(data[p])*33+int(data[p+1]))*33+int(data[p+2]))*33 + int(data[p+3])) % hashSize
}

func main() {
	words := make([][]byte, 512)
	for k := range words {
		words[k] = make([]byte, 2+rnd()%8)
		for j := range words[k] {
			words[k][j] = byte(97 + rnd()%26)
		}
	}
	data := make([]byte, 1<<20)
	pos := 0
	for pos < len(data) {
		w := words[rnd()%len(words)]
		for _, b := range w {
			if pos >= len(data) {
				break
			}
			data[pos] = b
			pos++
		}
		if pos < len(data) {
			data[pos] = ' '
			pos++
		}
	}
	start := time.Now()
	head, prev := make([]int, hashSize), make([]int, window)
	for i := range head {
		head[i] = -1
	}
	for i := range prev {
		prev[i] = -1
	}
	comp := make([]byte, len(data)*2+16)
	csize, i := 0, 0
	for i+minMatch <= len(data) {
		best, dist := 0, 0
		limit := len(data) - i
		if limit > maxMatch {
			limit = maxMatch
		}
		h := hashAt(data, i)
		cand, chain := head[h], 0
		for cand >= 0 && i-cand < window && chain < maxChain {
			length := 0
			for length < limit && data[cand+length] == data[i+length] {
				length++
			}
			if length > best {
				best, dist = length, i-cand
				if length == limit {
					break
				}
			}
			cand = prev[cand%window]
			chain++
		}
		prev[i%window], head[h] = head[h], i
		if best >= minMatch {
			comp[csize], comp[csize+1], comp[csize+2], comp[csize+3] = 1, byte(best-minMatch), byte((dist-1)%256), byte((dist-1)/256)
			csize += 4
			for p := i + 1; p < i+best; p++ {
				if p+minMatch <= len(data) {
					hp := hashAt(data, p)
					prev[p%window], head[hp] = head[hp], p
				}
			}
			i += best
		} else {
			comp[csize], comp[csize+1] = 0, data[i]
			csize += 2
			i++
		}
	}
	for i < len(data) {
		comp[csize], comp[csize+1] = 0, data[i]
		csize += 2
		i++
	}
	output := make([]byte, len(data))
	o, c := 0, 0
	for c < csize {
		if comp[c] == 0 {
			output[o] = comp[c+1]
			o++
			c += 2
		} else {
			length, back := int(comp[c+1])+minMatch, int(comp[c+2])+int(comp[c+3])*256+1
			for k := 0; k < length; k++ {
				output[o] = output[o-back]
				o++
			}
			c += 4
		}
	}
	same := o == len(data)
	for k := 0; same && k < len(data); k++ {
		if output[k] != data[k] {
			same = false
		}
	}
	hc := 0
	for k := 0; k < csize; k++ {
		hc = (hc*31 + int(comp[k])) % 1000003
	}
	check := 0
	if same {
		check = csize*1000003 + hc
	}
	report(check, start)
}
