package main

import (
	"fmt"
	"syscall"
	"unsafe"
)

var seed int64 = 12345

func rnd() int {
	seed = seed * 16807 % 2147483647
	return int(seed)
}

// The Windows performance counter, as in every other port. time.Now reads the interrupt
// clock, which only advances once per timer tick: a run of a few milliseconds can read
// a tick short, and a 10 ms raytrace once read 0.5 ms.
var kernel32 = syscall.NewLazyDLL("kernel32.dll")
var queryPerformanceCounter = kernel32.NewProc("QueryPerformanceCounter")
var queryPerformanceFrequency = kernel32.NewProc("QueryPerformanceFrequency")

func now() float64 {
	var counter, frequency int64
	queryPerformanceCounter.Call(uintptr(unsafe.Pointer(&counter)))
	queryPerformanceFrequency.Call(uintptr(unsafe.Pointer(&frequency)))
	return float64(counter) / float64(frequency)
}

func report(check int, start float64) {
	fmt.Printf("CHECK=%d MS=%.6f\n", check, (now()-start)*1000.0)
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
