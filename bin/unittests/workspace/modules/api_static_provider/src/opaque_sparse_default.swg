#global public

// Large zero ranges should occupy storage without becoming thousands of API literals.
#[Swag.Opaque, Swag.Align(16)]
struct OpaqueSparseDefault
{
    private
    {
        leading:    [4096] u8
        first:      u64    = 0x0102030405060708
        middle:     [8192] u8
        second:     u8     = 0xA5
        shortZeros: [7] u8
        third:      u64    = 0x1122334455667788
        trailing:   [4096] u8
        text:       string = "sparse-default"
        tail:       [1024] u8
        last:       u16    = 0x1234
    }
}

impl OpaqueSparseDefault
{
    #[Swag.NoInline]
    mtd const isDefault()->bool
    {
        #assert(#offsetof(OpaqueSparseDefault.first) == 4096)
        #assert(#offsetof(OpaqueSparseDefault.second) == 12296)
        #assert(#offsetof(OpaqueSparseDefault.third) == 12304)
        #assert(#offsetof(OpaqueSparseDefault.text) == 16408)
        #assert(#offsetof(OpaqueSparseDefault.last) == 17448)
        if .first != 0x0102030405060708 or .second != 0xA5 or
           .third != 0x1122334455667788 or .last != 0x1234 or
           .text != "sparse-default"
        {
            return false
        }
        for value in .leading where value != 0 do
            return false
        for value in .middle where value != 0 do
            return false
        for value in .shortZeros where value != 0 do
            return false
        for value in .trailing where value != 0 do
            return false
        for value in .tail where value != 0 do
            return false
        return true
    }

    #[Swag.NoInline]
    mtd change()
    {
        .leading[0]     = 1
        .first          = 0
        .middle[8191]   = 2
        .second         = 0
        .shortZeros[3]  = 3
        .third          = 0
        .trailing[4095] = 4
        .text           = "changed"
        .tail[512]      = 5
        .last           = 0
    }
}
