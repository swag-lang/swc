#global private
#global #[Swag.Safety(.Overflow, false)]

#[Swag.NoInline]
func sum(p: [*]u64, count: u64)->u64
{
    var result = 0_u64
    for i in 0 until count
    {
        result += p[i]
    }
    return result
}
#[Swag.NoInline]
func countNonzero(p: [*]u64, count: u64)->u64
{
    var result = 0_u64
    for i in 0 until count
    {
        if p[i] != 0
        {
            result += 1
        }
    }
    return result
}
#[Swag.NoInline]
func nested(p: [*]u64, count: u64, gate: bool)->u64
{
    var result = 0_u64
    if gate
    {
        for i in 0 until count
        {
            if p[i] == 0
            {
                break
            }
            result += p[i]
        }
    }
    return result
}
#[Swag.NoInline]
func selected(a, b: u64)->u64 => a < b ? a : 0

#test
{
    var values = [1_u64, 2, 0, 4, 0xFFFFFFFFFFFFFFFF]
    Swag.require(sum(&values[0], 0) == 0)
    Swag.require(sum(&values[0], 5) == 6)
    Swag.require(countNonzero(&values[0], 0) == 0)
    Swag.require(countNonzero(&values[0], 5) == 4)
    Swag.require(nested(&values[0], 5, false) == 0)
    Swag.require(nested(&values[0], 5, true) == 3)
    Swag.require(selected(3, 7) == 3)
    Swag.require(selected(7, 3) == 0)
    Swag.require(selected(0xFFFFFFFFFFFFFFFF, 3) == 0)
}

#[Swag.NoInline]
func(T) initializeElements(destination: [*] T, count: u64)
{
    Swag.init(destination, count)
}

struct ZeroElement
{
    first, second: u32
}

struct MixedElement
{
    first:  u32 = 19
    second: u32
}

#test
{
    var words: [66] u16
    for count in [0_u64, 1, 7, 8, 9, 15, 16, 17, 63, 64]
    {
        for &word in words
        {
            word[] = 0xBEEF
        }

        initializeElements(&words[1], count)
        Swag.require(words[0] == 0xBEEF)
        for index in 1 until words.count
        {
            Swag.require(words[index] == (index <= count ? 0 : 0xBEEF))
        }
    }

    var zeros = [ZeroElement{1, 2}, ZeroElement{3, 4}, ZeroElement{5, 6}, ZeroElement{7, 8}, ZeroElement{9, 10}]
    initializeElements(&zeros[1], 3)
    Swag.require(zeros[0].first == 1 and zeros[0].second == 2)
    for index in 1 until 4
    {
        Swag.require(zeros[index].first == 0 and zeros[index].second == 0)
    }
    Swag.require(zeros[4].first == 9 and zeros[4].second == 10)

    var mixed = [MixedElement{1, 2}, MixedElement{3, 4}, MixedElement{5, 6}, MixedElement{7, 8}, MixedElement{9, 10}]
    initializeElements(&mixed[1], 3)
    Swag.require(mixed[0].first == 1 and mixed[0].second == 2)
    for index in 1 until 4
    {
        Swag.require(mixed[index].first == 19 and mixed[index].second == 0)
    }
    Swag.require(mixed[4].first == 9 and mixed[4].second == 10)
}
