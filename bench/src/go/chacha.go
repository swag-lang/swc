package main

import "time"

func rol(x uint32, k uint) uint32 { return x<<k | x>>(32-k) }

func quarterRound(s *[16]uint32, a, b, c, d int) {
	s[a] += s[b]
	s[d] = rol(s[d]^s[a], 16)
	s[c] += s[d]
	s[b] = rol(s[b]^s[c], 12)
	s[a] += s[b]
	s[d] = rol(s[d]^s[a], 8)
	s[c] += s[d]
	s[b] = rol(s[b]^s[c], 7)
}

func main() {
	data := make([]uint32, 4194304)
	for i := range data {
		data[i] = uint32(rnd())
	}
	var key [8]uint32
	var nonce [3]uint32
	for i := range key {
		key[i] = uint32(rnd())
	}
	for i := range nonce {
		nonce[i] = uint32(rnd())
	}
	start := time.Now()
	initial := [16]uint32{0x61707865, 0x3320646e, 0x79622d32, 0x6b206574}
	for i := range key {
		initial[4+i] = key[i]
	}
	for i := range nonce {
		initial[13+i] = nonce[i]
	}
	counter := uint32(1)
	for offset := 0; offset < len(data); offset += 16 {
		initial[12] = counter
		state := initial
		for r := 0; r < 10; r++ {
			quarterRound(&state, 0, 4, 8, 12)
			quarterRound(&state, 1, 5, 9, 13)
			quarterRound(&state, 2, 6, 10, 14)
			quarterRound(&state, 3, 7, 11, 15)
			quarterRound(&state, 0, 5, 10, 15)
			quarterRound(&state, 1, 6, 11, 12)
			quarterRound(&state, 2, 7, 8, 13)
			quarterRound(&state, 3, 4, 9, 14)
		}
		for i := range state {
			data[offset+i] ^= state[i] + initial[i]
		}
		counter++
	}
	check := uint32(0)
	for i, v := range data {
		check ^= v + uint32(i)
	}
	report(int(check), start)
}
