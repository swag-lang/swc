local N = 800
local NN = N * N

local floor = math.floor

local seed = 12345
local function rnd()
    seed = (seed * 16807) % 2147483647
    return seed
end

-- ---- data generation (not timed) ----
local weight = {}
for i = 0, NN - 1 do
    weight[i] = 1 + (rnd() % 9)
end

-- ---- timed work ----
local t0 = os.clock()

local INF = 1e18
local dist = {}
for i = 0, NN - 1 do dist[i] = INF end

local hd = {}
local hn = {}
local hsize = 0

local function push(d, node)
    local i = hsize
    hsize = hsize + 1
    hd[i] = d
    hn[i] = node
    while i > 0 do
        local p = floor((i - 1) / 2)
        if hd[p] <= hd[i] then break end
        hd[p], hd[i] = hd[i], hd[p]
        hn[p], hn[i] = hn[i], hn[p]
        i = p
    end
end

local function pop()
    local rd = hd[0]
    local rn = hn[0]
    hsize = hsize - 1
    hd[0] = hd[hsize]
    hn[0] = hn[hsize]
    local i = 0
    while true do
        local l = 2 * i + 1
        if l >= hsize then break end
        local r = l + 1
        local m = l
        if r < hsize and hd[r] < hd[l] then m = r end
        if hd[i] <= hd[m] then break end
        hd[m], hd[i] = hd[i], hd[m]
        hn[m], hn[i] = hn[i], hn[m]
        i = m
    end
    return rd, rn
end

dist[0] = 0
push(0, 0)
local pops = 0
local target = NN - 1

while hsize > 0 do
    local d, u = pop()
    pops = pops + 1
    if d <= dist[u] then
        if u == target then break end
        local x = u % N
        local y = floor(u / N)
        if x > 0 then
            local v = u - 1
            local nd = d + weight[v]
            if nd < dist[v] then dist[v] = nd; push(nd, v) end
        end
        if x < N - 1 then
            local v = u + 1
            local nd = d + weight[v]
            if nd < dist[v] then dist[v] = nd; push(nd, v) end
        end
        if y > 0 then
            local v = u - N
            local nd = d + weight[v]
            if nd < dist[v] then dist[v] = nd; push(nd, v) end
        end
        if y < N - 1 then
            local v = u + N
            local nd = d + weight[v]
            if nd < dist[v] then dist[v] = nd; push(nd, v) end
        end
    end
end

local check = dist[target] * 1000 + (pops % 1000)

local t1 = os.clock()
print(string.format("CHECK=%d MS=%.3f", check, (t1 - t0) * 1000.0))
