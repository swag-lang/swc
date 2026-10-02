package main

// Open addressing over byte-slice keys, with the same FNV-1a probe as Swag.
type byteMap struct {
	base               []byte
	off, length, value []int
	used               []bool
	mask, count        int
}

func newByteMap(capacity int, base []byte) *byteMap {
	return &byteMap{base: base, off: make([]int, capacity), length: make([]int, capacity),
		value: make([]int, capacity), used: make([]bool, capacity), mask: capacity - 1}
}

func compareBytes(a, b []byte) int {
	n := len(a)
	if len(b) < n {
		n = len(b)
	}
	for i := 0; i < n; i++ {
		if a[i] < b[i] {
			return -1
		}
		if a[i] > b[i] {
			return 1
		}
	}
	return len(a) - len(b)
}

func (m *byteMap) probe(off, length int) int {
	h := uint32(2166136261)
	for _, b := range m.base[off : off+length] {
		h = (h ^ uint32(b)) * 16777619
	}
	i := int(h) & m.mask
	for m.used[i] {
		if m.length[i] == length && compareBytes(m.base[m.off[i]:m.off[i]+length], m.base[off:off+length]) == 0 {
			return i
		}
		i = (i + 1) & m.mask
	}
	return i
}

func (m *byteMap) claim(i, off, length, value int) {
	m.used[i], m.off[i], m.length[i], m.value[i] = true, off, length, value
	m.count++
}
