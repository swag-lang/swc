package main

import "time"

func quicksort(a []int, lo, hi int) {
	for hi-lo > 16 {
		mid := lo + (hi-lo)/2
		if a[mid] < a[lo] {
			a[lo], a[mid] = a[mid], a[lo]
		}
		if a[hi] < a[lo] {
			a[lo], a[hi] = a[hi], a[lo]
		}
		if a[hi] < a[mid] {
			a[mid], a[hi] = a[hi], a[mid]
		}
		pivot, i, j := a[mid], lo, hi
		for {
			for a[i] < pivot {
				i++
			}
			for a[j] > pivot {
				j--
			}
			if i <= j {
				a[i], a[j] = a[j], a[i]
				i++
				j--
			}
			if i > j {
				break
			}
		}
		if j-lo < hi-i {
			quicksort(a, lo, j)
			lo = i
		} else {
			quicksort(a, i, hi)
			hi = j
		}
	}
	for i := lo + 1; i <= hi; i++ {
		v, j := a[i], i-1
		for j >= lo && a[j] > v {
			a[j+1] = a[j]
			j--
		}
		a[j+1] = v
	}
}

func main() {
	a := make([]int, 300000)
	for i := range a {
		a[i] = rnd()
	}
	start := time.Now()
	quicksort(a, 0, len(a)-1)
	sorted := true
	for i := 1; i < len(a); i++ {
		if a[i-1] > a[i] {
			sorted = false
		}
	}
	check := 0
	if sorted {
		for i, v := range a {
			check += (v % 1000) * (i%7 + 1)
		}
	}
	report(check, start)
}
