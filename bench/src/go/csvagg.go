package main

import (
	"fmt"
	"time"
)

func main() {
	regions := []string{"EMEA", "APAC", "AMER", "LATAM", "NORDIC", "IBERIA", "BENELUX", "DACH"}
	text := make([]byte, 0, 400000*48)
	for j := 0; j < 400000; j++ {
		region := regions[rnd()%8]
		y, m, d, qty, cents := 2024+rnd()%3, 1+rnd()%12, 1+rnd()%28, 1+rnd()%50, 100+rnd()%99900
		if j > 0 {
			text = append(text, '\n')
		}
		text = fmt.Appendf(text, "%d,%s,%d-%02d-%02d,%d,%d.%02d", j, region, y, m, d, qty, cents/100, cents%100)
	}

	startTime := time.Now()
	agg := newByteMap(64, text)
	var count, quantity [64]int
	var revenue, maximum [64]float64
	pos, rows := 0, 0
	for pos < len(text) {
		eol := pos
		for eol < len(text) && text[eol] != '\n' {
			eol++
		}
		p := pos
		for text[p] != ',' {
			p++
		}
		p++
		rs := p
		for text[p] != ',' {
			p++
		}
		rlen := p - rs
		p++
		for text[p] != ',' {
			p++
		}
		p++
		qty := 0
		for text[p] != ',' {
			qty = qty*10 + int(text[p]-'0')
			p++
		}
		p++
		ip := 0
		for text[p] != '.' {
			ip = ip*10 + int(text[p]-'0')
			p++
		}
		p++
		fr := 0
		for p < eol {
			fr = fr*10 + int(text[p]-'0')
			p++
		}
		price := float64(ip) + float64(fr)/100
		idx := agg.probe(rs, rlen)
		if !agg.used[idx] {
			slot := agg.count
			agg.claim(idx, rs, rlen, slot)
			count[slot], quantity[slot], revenue[slot], maximum[slot] = 1, qty, float64(qty)*price, price
		} else {
			slot := agg.value[idx]
			count[slot]++
			quantity[slot] += qty
			revenue[slot] += float64(qty) * price
			if price > maximum[slot] {
				maximum[slot] = price
			}
		}
		rows++
		pos = eol + 1
	}
	order := make([]int, 0, agg.count)
	for i, used := range agg.used {
		if used {
			order = append(order, i)
		}
	}
	for i := range order {
		best := i
		for j := i + 1; j < len(order); j++ {
			a, b := order[best], order[j]
			if compareBytes(text[agg.off[b]:agg.off[b]+agg.length[b]], text[agg.off[a]:agg.off[a]+agg.length[a]]) < 0 {
				best = j
			}
		}
		order[i], order[best] = order[best], order[i]
	}
	check := rows
	for k, idx := range order {
		slot := agg.value[idx]
		check += (k+1)*(int(revenue[slot]*100+0.5)%1000003) + count[slot] + quantity[slot] + int(maximum[slot]*100+0.5)
	}
	report(check, startTime)
}
