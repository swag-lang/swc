package main

import (
	"fmt"
	"time"
)

var seed int64 = 12345

func rnd() int {
	seed = seed * 16807 % 2147483647
	return int(seed)
}

func report(check int, start time.Time) {
	elapsed := time.Since(start)
	fmt.Printf("CHECK=%d MS=%.6f\n", check, float64(elapsed.Nanoseconds())/1e6)
}

func makeWord(i, minLength, span int) []byte {
	n := i + 1
	w := make([]byte, minLength+i%span)
	for k := range w {
		w[k] = byte(97 + n%26)
		n = n/26 + 7*k
	}
	return w
}
