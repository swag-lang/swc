local N = 9

-- ---- data generation (not timed) ----
local perm = {}
local perm1 = {}
local count = {}
for i = 0, N - 1 do
    perm[i] = 0
    perm1[i] = 0
    count[i] = 0
end

-- ---- timed work ----
local t0 = os.clock()

for i = 0, N - 1 do perm1[i] = i end

local checksum = 0
local maxFlips = 0
local permCount = 0
local r = N

while true do
    while r ~= 1 do
        count[r - 1] = r
        r = r - 1
    end

    for i = 0, N - 1 do perm[i] = perm1[i] end

    local flips = 0
    local k = perm[0]
    while k ~= 0 do
        local i = 0
        local j = k
        while i < j do
            perm[i], perm[j] = perm[j], perm[i]
            i = i + 1
            j = j - 1
        end
        flips = flips + 1
        k = perm[0]
    end

    if flips > maxFlips then maxFlips = flips end
    if permCount % 2 == 0 then
        checksum = checksum + flips
    else
        checksum = checksum - flips
    end

    -- rotate the prefix to reach the next permutation
    local done = false
    while true do
        if r == N then
            done = true
            break
        end
        local perm0 = perm1[0]
        for i = 0, r - 1 do perm1[i] = perm1[i + 1] end
        perm1[r] = perm0
        count[r] = count[r] - 1
        if count[r] > 0 then break end
        r = r + 1
    end
    if done then break end
    permCount = permCount + 1
end

local check = checksum * 1000 + maxFlips

local t1 = os.clock()
print(string.format("CHECK=%d MS=%.3f", check, (t1 - t0) * 1000.0))
