#global private
#global #[Swag.Safety(.Lifecycle, false), Swag.Sanity(.Lifecycle, false)]

var drops:  s32
var copies: s32
var moves:  s32

struct Owner
{
    value:   s64
    padding: s64
}

impl Owner
{
    mtd opDrop() { drops += cast(s32) .value }
    mtd opPostCopy() { copies += 1 }
    mtd opPostMove() { moves += 1 }
}

struct Pair
{
    kind: s32
    item: Owner
}

func choose(flag: bool)
{
    var left     = Owner{3}
    var right    = Owner{7}
    let selected = flag ? #move left : #move right
    Swag.assert(selected.value == (flag ? 3 : 7))
    Swag.assert(left.value == (flag ? 0 : 3))
    Swag.assert(right.value == (flag ? 7 : 0))
    Swag.assert(copies == 0)
}

#test
{
    drops  = 0
    copies = 0
    moves  = 0
    {
        var source = Owner{5}
        let pair   = Pair{item: #move source, kind: 2}
        Swag.assert(pair.item.value == 5)
        Swag.assert(pair.kind == 2)
        Swag.assert(source.value == 0)
        Swag.assert(copies == 0)
    }
    Swag.assert(drops == 5)
}

#test
{
    drops  = 0
    copies = 0
    moves  = 0
    {
        var first  = Owner{2}
        var second = Owner{4}
        let values: [2] Owner = [#move first, #move second]
        Swag.assert(values[0].value == 2 and values[1].value == 4)
        Swag.assert(first.value == 0 and second.value == 0)
        Swag.assert(copies == 0)
    }
    Swag.assert(drops == 6)
}

#test
{
    drops  = 0
    copies = 0
    moves  = 0
    choose(true)
    choose(false)
    Swag.assert(drops == 20)
}

func chooseCopy(flag: bool)
{
    var source   = Owner{11}
    let selected = flag ? source : #move source
    Swag.assert(selected.value == 11)
    Swag.assert(source.value == (flag ? 11 : 0))
}

#test
{
    drops  = 0
    copies = 0
    chooseCopy(true)
    Swag.assert(copies == 1)
    chooseCopy(false)
    Swag.assert(copies == 1)
    Swag.assert(drops == 33)
}

struct Unique
{
    value: s64
}

impl Unique
{
    mtd opDrop() { drops += cast(s32) .value }
}

struct UniquePair
{
    first, second: Unique
}

func takePair(pair: UniquePair) { Swag.assert(pair.first.value == 8) }
func makePair()->UniquePair
{
    var first  = Unique{8}
    var second = Unique{9}
    return UniquePair{#move first, #move second}
}

func chooseUnique(flag: bool)
{
    var first  = Unique{8}
    var second = Unique{9}
    var selected: Unique
    selected = flag ? #move first : #move second
    Swag.assert(selected.value == (flag ? 8 : 9))
}

#test
{
    drops = 0
    chooseUnique(true)
    chooseUnique(false)
    Swag.assert(drops == 34)
    {
        let pair = makePair()
        takePair(pair)
    }
    Swag.assert(drops == 51)
    var first  = Unique{8}
    var second = Unique{9}
    takePair(UniquePair{#move first, #move second})
    Swag.assert(drops == 68)
}

func readValue(owner: *Owner)->s32 => cast(s32) owner.value

var dropTrace: u64
struct TraceOwner { value: u64 }
impl TraceOwner
{
    mtd opDrop() { if .value != 0 do dropTrace = dropTrace * 10 + .value }
}
struct TracePair { first, second: TraceOwner; code: s32 }

func interruptedPair() fail
{
    var first  = TraceOwner{1}
    var second = TraceOwner{2}
    discard TracePair{#move first, #move second, try failField()}
}

#test
{
    dropTrace = 0
    catch interruptedPair()
    Swag.assert(dropTrace == 21)
}

#test
{
    drops = 0
    {
        var first  = Unique{2}
        var second = Unique{3}
        let values: [2] Unique = [(#move first), #move second]
        Swag.assert(values[0].value == 2 and values[1].value == 3)
        Swag.assert(first.value == 0 and second.value == 0)
    }
    Swag.assert(drops == 5)
}

struct ConstructionError { using base: Swag.BaseError }

func failField()->s32 fail { fail ConstructionError{} }

func interruptedLiteral() fail
{
    var source = Owner{17}
    discard Pair{item: #move source, kind: try failField()}
}

#test
{
    drops = 0
    catch interruptedLiteral()
    Swag.assert(drops == 17)
}

#test
{
    drops  = 0
    copies = 0
    {
        var source = Owner{13}
        let pair   = Pair{item: #move source, kind: readValue(&source)}
        Swag.assert(pair.item.value == 13)
        Swag.assert(pair.kind == 0)
    }
    Swag.assert(drops == 13)
    Swag.assert(copies == 0)
}

func nestedSelection(flag: bool, inner: bool)
{
    var first    = Owner{2}
    var second   = Owner{3}
    var third    = Owner{5}
    let selected = flag ? (inner ? first : second) : #move third
    Swag.assert(selected.value == (flag ? (inner ? 2 : 3) : 5))
}

#test
{
    drops  = 0
    copies = 0
    nestedSelection(true, false)
    Swag.assert(copies == 1)
    Swag.assert(drops == 13)
}

func makeOwner()->Owner
{
    var result = Owner{19}
    return result
}

func chooseTemporary(flag: bool)
{
    var source   = Owner{23}
    let selected = flag ? makeOwner() : #move source
    Swag.assert(selected.value == (flag ? 19 : 23))
}

#test
{
    drops  = 0
    copies = 0
    chooseTemporary(true)
    chooseTemporary(false)
    Swag.assert(drops == 65)
    Swag.assert(copies == 0)
}

func interruptedBranch(flag: bool) fail
{
    var source = Owner{29}
    discard flag ? Pair{item: #move source, kind: try failField()} : Pair{}
}

#test
{
    drops = 0
    catch interruptedBranch(false)
    Swag.assert(drops == 29)
}

#test
{
    drops = 0
    catch interruptedBranch(true)
    Swag.assert(drops == 29)
}

struct AddressOwner
{
    value:   s64
    address: *s64?
}

impl AddressOwner
{
    mtd opPostMove() { .address = &.value }
    mtd opDrop()
    {
        if .address do Swag.assert(.address == &.value)
        drops += cast(s32) .value
    }
}

func addressResult(flag: bool)->AddressOwner
{
    var first  = AddressOwner{31}
    var second = AddressOwner{37}
    return flag ? #move first : #move second
}

#test
{
    drops = 0
    {
        let selected = addressResult(true)
        Swag.assert(selected.value == 31)
        Swag.assert(selected.address == &selected.value)
    }
    Swag.assert(drops == 68)
}

#test
{
    drops = 0
    {
        var source   = Unique{41}
        let selected = true ? #move source : Unique{43}
        Swag.assert(selected.value == 41)
    }
    Swag.assert(drops == 41)
}
