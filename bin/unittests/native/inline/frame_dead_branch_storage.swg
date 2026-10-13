#global private

// A folded inline branch leaves the frame storage of its locals behind. The frame is laid
// out again from what the optimized body still reaches, and every value read back through
// the surviving addresses must be intact, whether the branch folded or not.

struct Request
{
    size:      u64
    alignment: u32
    tag:       u64
}

#[Swag.NoInline]
func fill(req: *Request, base: u64)
{
    req.size      = base + 1
    req.alignment = cast(u32, base) + 2
    req.tag       = base * 3
}

#[Swag.Inline, Swag.Safety(.Overflow, false)]
func acquire(size: u64, alignment: u32)->u64
{
    var classIndex = size >> 4
    if alignment > 8
    {
        var rounded: [4] u64
        rounded[0] = size + alignment - 1
        rounded[1] = rounded[0] & ~cast(u64, alignment - 1)
        rounded[2] = rounded[1] >> 4
        rounded[3] = rounded[2] + classIndex
        classIndex = rounded[3]
    }

    var req: Request
    fill(&req, classIndex)
    return req.size + req.alignment + req.tag
}

#[Swag.Optimize(true), Swag.NoInline]
func constantAlignment(size: u64)->u64 => acquire(size, 8)

#[Swag.Optimize(true), Swag.NoInline]
func dynamicAlignment(size: u64, alignment: u32)->u64 => acquire(size, alignment)

#test
{
    Swag.assert(constantAlignment(64) == 23)
    Swag.assert(constantAlignment(16) == 8)
    Swag.assert(dynamicAlignment(64, 8) == 23)
    Swag.assert(dynamicAlignment(64, 16) == 43)
}
