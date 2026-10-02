package main

import "time"

func sortWords(order, counts, off, length []int, text []byte, low, high int) {
	less := func(a, b int) bool {
		if counts[a] != counts[b] {
			return counts[a] > counts[b]
		}
		return compareBytes(text[off[a]:off[a]+length[a]], text[off[b]:off[b]+length[b]]) < 0
	}
	for low < high {
		pivot := order[(low+high)/2]
		i, j := low, high
		for i <= j {
			for less(order[i], pivot) {
				i++
			}
			for less(pivot, order[j]) {
				j--
			}
			if i <= j {
				order[i], order[j] = order[j], order[i]
				i++
				j--
			}
		}
		sortWords(order, counts, off, length, text, low, j)
		low = i
	}
}

func main() {
	const vocabSize, words = 5000, 2000000
	vocab := make([][]byte, vocabSize)
	for i := range vocab {
		vocab[i] = makeWord(i, 3, 6)
	}
	text := make([]byte, 0, words*12)
	for j := 0; j < words; j++ {
		text = append(text, vocab[rnd()%vocabSize]...)
		if (j+1)%12 == 0 {
			text = append(text, '\n')
		} else {
			text = append(text, ' ')
		}
	}

	startTime := time.Now()
	m := newByteMap(16384, text)
	start := -1
	for i, b := range text {
		if b >= 'a' && b <= 'z' {
			if start < 0 {
				start = i
			}
		} else if start >= 0 {
			slot := m.probe(start, i-start)
			if m.used[slot] {
				m.value[slot]++
			} else {
				m.claim(slot, start, i-start, 1)
			}
			start = -1
		}
	}
	if start >= 0 {
		slot := m.probe(start, len(text)-start)
		if m.used[slot] {
			m.value[slot]++
		} else {
			m.claim(slot, start, len(text)-start, 1)
		}
	}
	counts, off, length, order := make([]int, m.count), make([]int, m.count), make([]int, m.count), make([]int, m.count)
	n := 0
	for i, used := range m.used {
		if used {
			counts[n], off[n], length[n], order[n] = m.value[i], m.off[i], m.length[i], n
			n++
		}
	}
	sortWords(order, counts, off, length, text, 0, n-1)
	check := n * 7
	for k := 0; k < 20; k++ {
		check += (k + 1) * counts[order[k]]
	}
	report(check, startTime)
}
