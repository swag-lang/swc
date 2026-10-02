package main

import (
	"math"
	"time"
)

var scx = [4]float64{0, 2, -2, 0}
var scy = [4]float64{-0.5, 0, 0, -5001}
var scz = [4]float64{3, 4.5, 4, 0}
var radius = [4]float64{1, 1, 1, 5000}
var red = [4]float64{1, 0.2, 0.2, 0.9}
var green = [4]float64{0.25, 1, 0.3, 0.85}
var blue = [4]float64{0.25, 0.3, 1, 0.3}
var reflectivity = [4]float64{0.35, 0.45, 0.55, 0.15}

func intersect(ox, oy, oz, dx, dy, dz, tmin float64) (float64, int) {
	best, hit := 1e30, -1
	for i := range scx {
		ex, ey, ez := ox-scx[i], oy-scy[i], oz-scz[i]
		b := 2 * (ex*dx + ey*dy + ez*dz)
		c := ex*ex + ey*ey + ez*ez - radius[i]*radius[i]
		disc := b*b - 4*c
		if disc < 0 {
			continue
		}
		sq := math.Sqrt(disc)
		t := (-b - sq) * 0.5
		if t < tmin {
			t = (-b + sq) * 0.5
		}
		if t >= tmin && t < best {
			best, hit = t, i
		}
	}
	return best, hit
}

func trace(ox, oy, oz, dx, dy, dz float64, depth int) (float64, float64, float64) {
	t, hit := intersect(ox, oy, oz, dx, dy, dz, 0.0001)
	if hit < 0 {
		return 0.05, 0.07, 0.12
	}
	px, py, pz := ox+dx*t, oy+dy*t, oz+dz*t
	nl := 1 / radius[hit]
	nx, ny, nz := (px-scx[hit])*nl, (py-scy[hit])*nl, (pz-scz[hit])*nl
	lx, ly, lz := 5-px, 5-py, -3-pz
	ll := 1 / math.Sqrt(lx*lx+ly*ly+lz*lz)
	lx *= ll
	ly *= ll
	lz *= ll
	lam := nx*lx + ny*ly + nz*lz
	if lam < 0 {
		lam = 0
	} else {
		_, shadow := intersect(px, py, pz, lx, ly, lz, 0.001)
		if shadow >= 0 {
			lam = 0
		}
	}
	k := 0.12 + 0.88*lam
	cr, cg, cb := red[hit]*k, green[hit]*k, blue[hit]*k
	refl := reflectivity[hit]
	if refl > 0 && depth < 2 {
		d := 2 * (dx*nx + dy*ny + dz*nz)
		rr, rg, rb := trace(px, py, pz, dx-d*nx, dy-d*ny, dz-d*nz, depth+1)
		cr, cg, cb = cr*(1-refl)+rr*refl, cg*(1-refl)+rg*refl, cb*(1-refl)+rb*refl
	}
	return cr, cg, cb
}

func main() {
	const width, height = 480, 360
	start := time.Now()
	aspect := float64(width) / float64(height)
	check := 0
	for py := 0; py < height; py++ {
		for px := 0; px < width; px++ {
			dx := ((float64(px)+0.5)/width*2 - 1) * aspect
			dy, dz := 1-(float64(py)+0.5)/height*2, 1.0
			il := 1 / math.Sqrt(dx*dx+dy*dy+dz*dz)
			cr, cg, cb := trace(0, 0, 0, dx*il, dy*il, dz*il, 0)
			ir, ig, ib := int(cr*255), int(cg*255), int(cb*255)
			if ir > 255 {
				ir = 255
			}
			if ig > 255 {
				ig = 255
			}
			if ib > 255 {
				ib = 255
			}
			check += ir + 2*ig + 3*ib
		}
	}
	report(check, start)
}
