#global private

struct Registers
{
    values: [3] u64
    marker: u32
}

impl Registers
{
    // Two 'return' statements in different branches: the result slot of the expansion must
    // have an address on every path, not only on the one that materialized it first.
    #[Swag.Inline]
    mtd pick(operand: u8)->u64
    {
        if operand <= 3 do return cast(u64) operand
        return me.values[operand - 4]
    }
}

#[Swag.NoInline]
func pickThroughInline(operand: u8)->u64
{
    var regs: Registers
    regs.values[0] = 100
    regs.values[1] = 200
    return regs.pick(operand)
}

// A literal operand skips the early return, so the branch holding the first
// materialization of the result slot is dead code
#test
{
    var regs: Registers
    regs.values[2] = 300
    Swag.assert(regs.pick(6) == 300)
    Swag.assert(regs.pick(2) == 2)
    Swag.assert(pickThroughInline(4) == 100)
    Swag.assert(pickThroughInline(5) == 200)
    Swag.assert(pickThroughInline(1) == 1)
}
