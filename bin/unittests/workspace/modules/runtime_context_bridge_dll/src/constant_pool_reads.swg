// Constants a library image holds, read from inside that image. A table of
// names carries pointers into the pool beside it, and a table of numbers is
// read at an offset the reading instruction can carry itself. Folding the
// address of such a constant into the read is what a library image has to
// survive: the read becomes instruction-pointer-relative and no register ever
// holds the pool's address.

const ColorNames: [4] string = ["black", "white", "red", "green"]
const ColorValues: [4] u32   = [0x00000000, 0x00FFFFFF, 0x00FF0000, 0x0000FF00]

// Read through an index the caller chooses: the address stays in a register.
public func ctxPoolNameAt(index: u64)->string => ColorNames[index]
public func ctxPoolValueAt(index: u64)->u32 => ColorValues[index]

// Read at a fixed offset: this is the shape the fold rewrites, at offset zero
// and past it.
public func ctxPoolFirstName()->string => ColorNames[0]
public func ctxPoolThirdName()->string => ColorNames[2]
public func ctxPoolFirstValue()->u32 => ColorValues[0]
public func ctxPoolFourthValue()->u32 => ColorValues[3]

// A vector constant, whose sixteen bytes are one pool entry read in one
// instruction.
public func ctxPoolVectorSum(seed: s32)->s32
{
    let base  = cast(#simd [4] s32) Swag.vecsplat(seed)
    let steps = cast(#simd [4] s32) [1, 2, 3, 4]
    let sum   = cast([4] s32) (base + steps)
    return sum[0] + sum[1] + sum[2] + sum[3]
}
