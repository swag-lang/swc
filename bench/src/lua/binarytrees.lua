local MIN_DEPTH = 4
local MAX_DEPTH = 12

local function bottomUp(depth)
    if depth > 0 then
        return { left = bottomUp(depth - 1), right = bottomUp(depth - 1) }
    end
    return {}
end

local function check(node)
    local left = node.left
    if not left then return 1 end
    return 1 + check(left) + check(node.right)
end

-- ---- timed work (no input data) ----
local t0 = os.clock()

local total = 0

local stretch = bottomUp(MAX_DEPTH + 1)
total = total + check(stretch)
stretch = nil

local longLived = bottomUp(MAX_DEPTH)

for d = MIN_DEPTH, MAX_DEPTH, 2 do
    local iterations = 2 ^ (MAX_DEPTH - d + MIN_DEPTH)
    for i = 1, iterations do
        local tree = bottomUp(d)
        total = total + check(tree)
    end
end

total = total + check(longLived)
longLived = nil

local t1 = os.clock()
print(string.format("CHECK=%d MS=%.3f", total, (t1 - t0) * 1000.0))
