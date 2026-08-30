#global private

// A '#move' or '#fwd' parameter that lands past the argument registers is passed in a stack
// slot. Such a parameter needs addressable storage (the move reference is the address of its
// storage), and the incoming argument must be read before that storage is handed out --
// otherwise the callee moves out of an uninitialized slot.

var g_out:    u64
var g_moves:  s32
var g_copies: s32

struct Tracked
{
    x: s32
    y: s32
}

impl Tracked
{
    mtd opPostCopy() { g_copies += 1 }
    mtd opPostMove() { g_moves += 1 }
    mtd opDrop() {}
}

var g_slot: Tracked

func moveScalarOnStack(a, b, c, d: u64, value: #move u64)
{
    g_out = #move value
}

func moveScalarInRegister(value: #move u64, a, b, c, d: u64)
{
    g_out = #move value
}

// The move reference must denote the caller's variable, whichever ABI slot carried it.
#test
{
    var v = 77'u64
    moveScalarOnStack(1, 2, 3, 4, #move v)
    Swag.assert(g_out == 77)

    var w = 88'u64
    moveScalarInRegister(#move w, 1, 2, 3, 4)
    Swag.assert(g_out == 88)
}

func fwdScalarOnStack(a, b, c, d: u64, value: #fwd u64)
{
    g_out = #fwd value
}

// '#fwd' selects the move variant here, and the copy variant on a plain argument.
#test
{
    var v = 11'u64
    fwdScalarOnStack(1, 2, 3, 4, #move v)
    Swag.assert(g_out == 11)

    let plain = 22'u64
    fwdScalarOnStack(1, 2, 3, 4, plain)
    Swag.assert(g_out == 22)
}

func moveStructOnStack(a, b, c, d: u64, value: #move Tracked)
{
    g_slot = #nodrop #move value
}

// Same for a struct with lifecycle hooks: the moved-from source is reset, not left untouched.
#test
{
    g_copies, g_moves = 0
    var t = Tracked{5, 6}
    moveStructOnStack(1, 2, 3, 4, #move t)
    Swag.assert(g_slot.x == 5 and g_slot.y == 6)
    Swag.assert(g_moves == 1)
    Swag.assert(g_copies == 0)
    Swag.assert(t.x == 0 and t.y == 0)
}

struct Table
{
    slots: [4] u64
}

impl Table
{
    // 'me' takes an argument slot, so 'value' is the fifth and lands on the stack
    mtd store(index: u64, tag: u32, other: u64, value: #fwd u64)
    {
        .slots[index] = #fwd value + other + cast(u64) tag
    }

    mtd storeDefault(index: u64)
    {
        var value: u64
        .store(index, 9, 100, #move value)
    }
}

// The shape that first exposed this: a method forwarding a default-initialized local into a
// '#fwd' parameter sitting in a stack slot.
#test
{
    var table: Table
    table.store(0, 1, 10, 30'u64)
    Swag.assert(table.slots[0] == 41)

    table.storeDefault(1)
    Swag.assert(table.slots[1] == 109)
}
