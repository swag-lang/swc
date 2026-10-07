#global private
using Swag

// A counted loop over adjacent 32-bit lanes, written as scalar source. Full
// unrolling turns each induction-derived address into a constant offset, which
// is what lets the superword pass see four adjacent stores and pack them. The
// asserted results are the scalar semantics, packed or not.

struct WordLanes
{
    left:   [8] u32
    right:  [8] u32
    result: [8] u32
}

struct FloatLanes
{
    left:   [8] f32
    right:  [8] f32
    result: [8] f32
}

#[Swag.Optimize(true)]
func xorWords(lanes: *WordLanes)
{
    for i in 8 do
        lanes.result[i] = lanes.left[i] ^ lanes.right[i]
}

// The repeated addend is one sixteen-byte constant read, shared by both groups.
#[Swag.Optimize(true)]
func scaleAndBias(lanes: *FloatLanes)
{
    for i in 8 do
        lanes.result[i] = lanes.left[i] * lanes.right[i] + 1.5'f32
}

// The sign mask of an absolute value is a repeated constant too.
#[Swag.Optimize(true)]
func magnitudes(lanes: *FloatLanes)
{
    for i in 8 do
        lanes.result[i] = Swag.abs(lanes.left[i])
}

// A trip count that leaves a group incomplete packs the full group only.
#[Swag.Optimize(true)]
func addSixWords(lanes: *WordLanes)
{
    for i in 6 do
        lanes.result[i] = lanes.left[i] + lanes.right[i] + 0x8000_0001
}

// Each store feeds the next read: the lanes depend on one another and stay scalar.
#[Swag.Optimize(true)]
func prefixSums(lanes: *WordLanes)
{
    lanes.result[0] = lanes.left[0]
    for i in 1 until 8 do
        lanes.result[i] = lanes.result[i - 1] + lanes.left[i]
}

#test
{
    var lanes: WordLanes
    for i in 8
    {
        lanes.left[i]  = cast(u32, i) * 0x0101_0101
        lanes.right[i] = 0xFFFF_0000 + cast(u32, i)
    }

    xorWords(&lanes)
    for i in 8 do
        Swag.assert(lanes.result[i] == ((cast(u32, i) * 0x0101_0101) ^ (0xFFFF_0000 + cast(u32, i))))
}

#test
{
    var lanes: FloatLanes
    for i in 8
    {
        lanes.left[i]  = cast(f32, i) - 3.0'f32
        lanes.right[i] = 2.0'f32
    }

    scaleAndBias(&lanes)
    for i in 8 do
        Swag.assert(lanes.result[i] == (cast(f32, i) - 3.0'f32) * 2.0'f32 + 1.5'f32)

    magnitudes(&lanes)
    Swag.assert(lanes.result[0] == 3.0'f32 and lanes.result[1] == 2.0'f32 and lanes.result[2] == 1.0'f32 and lanes.result[3] == 0.0'f32)
    Swag.assert(lanes.result[4] == 1.0'f32 and lanes.result[7] == 4.0'f32)
}

#test
{
    var lanes: WordLanes
    for i in 8
    {
        lanes.left[i]   = cast(u32, i) * 3
        lanes.right[i]  = cast(u32, i)
        lanes.result[i] = 99
    }

    addSixWords(&lanes)
    for i in 6 do
        Swag.assert(lanes.result[i] == cast(u32, i) * 4 + 0x8000_0001)
    Swag.assert(lanes.result[6] == 99 and lanes.result[7] == 99)
}

#test
{
    var lanes: WordLanes
    for i in 8 do
        lanes.left[i] = cast(u32, i) + 1

    prefixSums(&lanes)
    var expected = 0'u32
    for i in 8
    {
        expected += cast(u32, i) + 1
        Swag.assert(lanes.result[i] == expected)
    }
}
