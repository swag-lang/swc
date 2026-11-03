#global private

func assert(value: s32)->s32 => value + 1
func index()->s32  => 7
func count()->s32  => 11
func buffer()->s32 => 13

struct CountMemberWins
{
    count: u64
}

impl CountMemberWins
{
    mtd opCount()->u64 => 99
}

struct BufferMemberWins
{
    buffer: [*] u8
    data:   [2] u8
}

impl BufferMemberWins
{
    mtd opData()->[*] u8 => &.data[0]
}

#test
{
    Swag.require(assert(1) == 2)
    Swag.require(index() == 7)
    Swag.require(count() == 11)
    Swag.require(buffer() == 13)
}

#test
{
    let value = CountMemberWins{count: 5}
    Swag.require(value.count == 5)
}

#test
{
    var external: [1] u8 = [42]
    var value = BufferMemberWins{buffer: &external[0], data: [1, 2]}

    Swag.require(value.buffer == &external[0])
    Swag.require(value.buffer[] == 42)
}
