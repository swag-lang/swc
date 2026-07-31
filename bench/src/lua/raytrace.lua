local W = 480
local H = 360
local NS = 4

local sqrt = math.sqrt
local floor = math.floor

local scx = { 0.0, 2.0, -2.0, 0.0 }
local scy = { -0.5, 0.0, 0.0, -5001.0 }
local scz = { 3.0, 4.5, 4.0, 0.0 }
local srad = { 1.0, 1.0, 1.0, 5000.0 }
local sr = { 1.0, 0.2, 0.2, 0.9 }
local sg = { 0.25, 1.0, 0.3, 0.85 }
local sb = { 0.25, 0.3, 1.0, 0.3 }
local sre = { 0.35, 0.45, 0.55, 0.15 }

local LX, LY, LZ = 5.0, 5.0, -3.0
local AMB = 0.12

local function intersect(ox, oy, oz, dx, dy, dz, tmin)
    local best = 1e30
    local hit = -1
    for i = 1, NS do
        local ex = ox - scx[i]
        local ey = oy - scy[i]
        local ez = oz - scz[i]
        local b = 2.0 * (ex * dx + ey * dy + ez * dz)
        local c = ex * ex + ey * ey + ez * ez - srad[i] * srad[i]
        local disc = b * b - 4.0 * c
        if disc >= 0.0 then
            local sq = sqrt(disc)
            local t = (-b - sq) * 0.5
            if t < tmin then t = (-b + sq) * 0.5 end
            if t >= tmin and t < best then
                best = t
                hit = i
            end
        end
    end
    return best, hit
end

local function trace(ox, oy, oz, dx, dy, dz, depth)
    local t, hit = intersect(ox, oy, oz, dx, dy, dz, 0.0001)
    if hit < 0 then
        return 0.05, 0.07, 0.12
    end

    local px = ox + dx * t
    local py = oy + dy * t
    local pz = oz + dz * t
    local nl = 1.0 / srad[hit]
    local nx = (px - scx[hit]) * nl
    local ny = (py - scy[hit]) * nl
    local nz = (pz - scz[hit]) * nl

    local lx = LX - px
    local ly = LY - py
    local lz = LZ - pz
    local ll = 1.0 / sqrt(lx * lx + ly * ly + lz * lz)
    lx = lx * ll
    ly = ly * ll
    lz = lz * ll

    local lam = nx * lx + ny * ly + nz * lz
    if lam < 0.0 then
        lam = 0.0
    else
        local st, sh = intersect(px, py, pz, lx, ly, lz, 0.001)
        if sh >= 0 then lam = 0.0 end
    end

    local k = AMB + 0.88 * lam
    local cr = sr[hit] * k
    local cg = sg[hit] * k
    local cb = sb[hit] * k

    local refl = sre[hit]
    if refl > 0.0 and depth < 2 then
        local d = 2.0 * (dx * nx + dy * ny + dz * nz)
        local rr, rg, rb = trace(px, py, pz, dx - d * nx, dy - d * ny, dz - d * nz, depth + 1)
        cr = cr * (1.0 - refl) + rr * refl
        cg = cg * (1.0 - refl) + rg * refl
        cb = cb * (1.0 - refl) + rb * refl
    end

    return cr, cg, cb
end

-- ---- timed work ----
local t0 = os.clock()

local aspect = W / H
local check = 0
for py = 0, H - 1 do
    for px = 0, W - 1 do
        local dx = ((px + 0.5) / W * 2.0 - 1.0) * aspect
        local dy = 1.0 - (py + 0.5) / H * 2.0
        local dz = 1.0
        local il = 1.0 / sqrt(dx * dx + dy * dy + dz * dz)
        local cr, cg, cb = trace(0.0, 0.0, 0.0, dx * il, dy * il, dz * il, 0)
        local ir = floor(cr * 255.0)
        local ig = floor(cg * 255.0)
        local ib = floor(cb * 255.0)
        if ir > 255 then ir = 255 end
        if ig > 255 then ig = 255 end
        if ib > 255 then ib = 255 end
        check = check + ir + 2 * ig + 3 * ib
    end
end

local t1 = os.clock()
print(string.format("CHECK=%d MS=%.3f", check, (t1 - t0) * 1000.0))
