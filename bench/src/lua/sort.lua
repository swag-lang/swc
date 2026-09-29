local N = 300000

local floor = math.floor

local seed = 12345
local function rnd()
    seed = (seed * 16807) % 2147483647
    return seed
end

local function qsort(a, lo, hi)
    while hi - lo > 16 do
        local mid = lo + floor((hi - lo) / 2)
        if a[mid] < a[lo] then a[lo], a[mid] = a[mid], a[lo] end
        if a[hi] < a[lo] then a[lo], a[hi] = a[hi], a[lo] end
        if a[hi] < a[mid] then a[mid], a[hi] = a[hi], a[mid] end

        local pivot = a[mid]
        local i = lo
        local j = hi
        repeat
            while a[i] < pivot do i = i + 1 end
            while a[j] > pivot do j = j - 1 end
            if i <= j then
                a[i], a[j] = a[j], a[i]
                i = i + 1
                j = j - 1
            end
        until i > j

        -- recurse into the smaller side, loop on the larger one
        if j - lo < hi - i then
            qsort(a, lo, j)
            lo = i
        else
            qsort(a, i, hi)
            hi = j
        end
    end

    for i = lo + 1, hi do
        local v = a[i]
        local j = i - 1
        while j >= lo and a[j] > v do
            a[j + 1] = a[j]
            j = j - 1
        end
        a[j + 1] = v
    end
end

-- ---- data generation (not timed) ----
local a = {}
for i = 0, N - 1 do
    a[i] = rnd()
end

-- ---- timed work ----
local t0 = os.clock()

qsort(a, 0, N - 1)

local sorted = true
for i = 1, N - 1 do
    if a[i - 1] > a[i] then sorted = false end
end

local check = 0
if sorted then
    for i = 0, N - 1 do
        check = check + (a[i] % 1000) * (i % 7 + 1)
    end
end

local t1 = os.clock()
print(string.format("CHECK=%d MS=%.3f", check, (t1 - t0) * 1000.0))
