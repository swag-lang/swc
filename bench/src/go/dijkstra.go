package main

import "time"

type heap struct {
	distance, node []int
	size           int
}

func (h *heap) swap(a, b int) {
	h.distance[a], h.distance[b] = h.distance[b], h.distance[a]
	h.node[a], h.node[b] = h.node[b], h.node[a]
}

func (h *heap) push(d, node int) {
	i := h.size
	h.size++
	h.distance[i], h.node[i] = d, node
	for i > 0 {
		p := (i - 1) >> 1
		if h.distance[p] <= h.distance[i] {
			break
		}
		h.swap(p, i)
		i = p
	}
}

func (h *heap) pop() (int, int) {
	d, n := h.distance[0], h.node[0]
	h.size--
	h.distance[0], h.node[0] = h.distance[h.size], h.node[h.size]
	i := 0
	for {
		l := 2*i + 1
		if l >= h.size {
			break
		}
		r, m := l+1, l
		if r < h.size && h.distance[r] < h.distance[l] {
			m = r
		}
		if h.distance[i] <= h.distance[m] {
			break
		}
		h.swap(m, i)
		i = m
	}
	return d, n
}

func main() {
	const n, nn = 800, 800 * 800
	weight := make([]int, nn)
	for i := range weight {
		weight[i] = 1 + rnd()%9
	}
	start := time.Now()
	dist := make([]int, nn)
	for i := range dist {
		dist[i] = 1 << 60
	}
	h := heap{distance: make([]int, nn*4), node: make([]int, nn*4)}
	dist[0] = 0
	h.push(0, 0)
	pops := 0
	for h.size > 0 {
		d, u := h.pop()
		pops++
		if d > dist[u] {
			continue
		}
		if u == nn-1 {
			break
		}
		x, y := u%n, u/n
		if x > 0 {
			v := u - 1
			if nd := d + weight[v]; nd < dist[v] {
				dist[v] = nd
				h.push(nd, v)
			}
		}
		if x < n-1 {
			v := u + 1
			if nd := d + weight[v]; nd < dist[v] {
				dist[v] = nd
				h.push(nd, v)
			}
		}
		if y > 0 {
			v := u - n
			if nd := d + weight[v]; nd < dist[v] {
				dist[v] = nd
				h.push(nd, v)
			}
		}
		if y < n-1 {
			v := u + n
			if nd := d + weight[v]; nd < dist[v] {
				dist[v] = nd
				h.push(nd, v)
			}
		}
	}
	report(dist[nn-1]*1000+pops%1000, start)
}
