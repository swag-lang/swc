#global private

// A value built by an implicit 'opSet' lives in a compiler temporary that nobody else names, so
// whoever stores it adopts it with 'opPostMove' and the temporary is never dropped. A literal
// field used to bit-copy it without 'opPostMove': a value that points into itself, such as a
// 'Core.String' holding its bytes inline, kept pointing into the dead temporary, and its
// 'opDrop' freed that address. A variable or an assignment deep-copied it instead and leaked
// the temporary, and a by-value argument never dropped it.
var SetCount, DropCount, PostMoveCount, PostCopyCount, StaleDropCount: u32

// Points at itself, like a small 'Core.String' pointing at its inline buffer.
struct Owned
{
    addr:  *Owned? = null
    value: string  = ""
}

impl Owned
{
    #[Swag.Implicit]
    mtd opSet(value: string)
    {
        SetCount += 1
        .addr    = me
        .value   = value
    }

    mtd opPostMove()
    {
        PostMoveCount += 1
        .addr         = me
    }

    mtd opPostCopy()
    {
        PostCopyCount += 1
        .addr         = me
    }

    mtd opDrop()
    {
        DropCount += 1
        if .addr and .addr != me do
            StaleDropCount += 1
    }
}

struct Holder
{
    owned: Owned
}

impl Holder
{
    const Default = "default"
}

struct Request
{
    stage:  Owned
    holder: Holder
}

const Bytes: [3] u8 = [65, 66, 67]
const FromBytes     = cast(string, Bytes)

func name()->string     => "dyn"
func ownsItself(owned: Owned)->bool => owned.addr == &owned
func makeOwned()->Owned => name()

func makeOwnedHolder(value: string)->Holder
{
    return Holder{owned: value}
}

// A conditional whose branch converts through 'opSet' owns its value: it adopts the selected
// branch, and a branch that did not run leaves nothing to drop.
func assignConditional(flag: bool)
{
    var holder: Holder
    holder.owned = flag ? "lit" : makeOwned()
    Swag.assert(holder.owned.value == (flag ? "lit" : "dyn"))
    Swag.assert(holder.owned.addr == &holder.owned)
}

func resetCounts()
{
    SetCount, DropCount, PostMoveCount, PostCopyCount, StaleDropCount = 0
}

// Every value 'opSet' built was dropped exactly once, from where it was finally stored.
func assertBalanced(sets: u32)
{
    Swag.assert(SetCount == sets)
    Swag.assert(DropCount == sets)
    Swag.assert(PostCopyCount == 0)
    Swag.assert(StaleDropCount == 0)
}

#test
{
    resetCounts()
    scope
    {
        let holder: Holder = Holder{owned: "abc"}
        Swag.assert(holder.owned.value == "abc")
        Swag.assert(holder.owned.addr == &holder.owned)
    }
    assertBalanced(1)
}

#test
{
    resetCounts()
    scope
    {
        let holder = makeOwnedHolder("returned")
        Swag.assert(holder.owned.value == "returned")
        Swag.assert(holder.owned.addr == &holder.owned)
    }
    assertBalanced(1)
}

#test
{
    resetCounts()
    scope
    {
        let holder = Holder{owned: Holder.Default}
        Swag.assert(holder.owned.value == "default")
        Swag.assert(holder.owned.addr == &holder.owned)
    }
    assertBalanced(1)
}

#test
{
    resetCounts()
    scope
    {
        let request: Request = Request{stage: "pre-emit", holder: Holder{owned: Holder.Default}}
        Swag.assert(request.stage.value == "pre-emit")
        Swag.assert(request.stage.addr == &request.stage)
        Swag.assert(request.holder.owned.value == "default")
        Swag.assert(request.holder.owned.addr == &request.holder.owned)
    }
    assertBalanced(2)
}

#test
{
    resetCounts()
    scope
    {
        let holder: Holder = Holder{owned: name()}
        Swag.assert(holder.owned.value == "dyn")
        Swag.assert(holder.owned.addr == &holder.owned)
    }
    assertBalanced(1)
}

#test
{
    resetCounts()
    scope
    {
        let holder: Holder = Holder{owned: FromBytes}
        Swag.assert(holder.owned.value == "ABC")
        Swag.assert(holder.owned.addr == &holder.owned)
    }
    assertBalanced(1)
}

#test
{
    resetCounts()
    scope
    {
        var holder: Holder
        holder = {owned: name()}
        Swag.assert(holder.owned.value == "dyn")
        Swag.assert(holder.owned.addr == &holder.owned)
    }

    // The default value the assignment replaces is dropped too.
    Swag.assert(SetCount == 1)
    Swag.assert(DropCount == 2)
    Swag.assert(PostCopyCount == 0)
    Swag.assert(StaleDropCount == 0)
}

#test
{
    resetCounts()
    scope
    {
        let owned: [2] Owned = ["a", name()]
        Swag.assert(owned[0].addr == &owned[0])
        Swag.assert(owned[1].value == "dyn")
        Swag.assert(owned[1].addr == &owned[1])
    }
    assertBalanced(2)
}

#test
{
    resetCounts()
    scope
    {
        let tuple = {owned: cast(Owned, name())}
        Swag.assert(tuple.owned.addr == &tuple.owned)
    }

    Swag.assert(SetCount == 1)
    Swag.assert(DropCount == 1)
    Swag.assert(PostCopyCount == 0)
    Swag.assert(StaleDropCount == 0)
}

#test
{
    resetCounts()
    scope
    {
        let tuple = {owned: makeOwned()}
        Swag.assert(tuple.owned.addr == &tuple.owned)
    }

    Swag.assert(SetCount == 1)
    Swag.assert(DropCount == 1)
    Swag.assert(PostCopyCount == 0)
    Swag.assert(StaleDropCount == 0)
}

#test
{
    resetCounts()
    assignConditional(true)
    Swag.assert(SetCount == 1)
    Swag.assert(DropCount == 2)
    Swag.assert(PostCopyCount == 0)
    Swag.assert(StaleDropCount == 0)
}

#test
{
    resetCounts()
    assignConditional(false)
    Swag.assert(SetCount == 1)
    Swag.assert(DropCount == 2)
    Swag.assert(PostCopyCount == 0)
    Swag.assert(StaleDropCount == 0)
}

#test
{
    // The argument is only built when its branch runs, so it is only dropped then.
    resetCounts()
    var flag     = false
    let selected = flag ? ownsItself("abc") : false
    Swag.assert(not selected)
    Swag.assert(SetCount == 0)
    Swag.assert(DropCount == 0)
}

#test
{
    resetCounts()
    Swag.assert(ownsItself("abc"))
    assertBalanced(1)
}

#test
{
    resetCounts()
    scope
    {
        let owned = cast(Owned, name())
        Swag.assert(owned.addr == &owned)
    }
    assertBalanced(1)
}

#test
{
    resetCounts()
    scope
    {
        var owned: Owned
        owned = cast(Owned, name())
        Swag.assert(owned.addr == &owned)
    }

    // The default value the assignment replaces is dropped too.
    Swag.assert(SetCount == 1)
    Swag.assert(DropCount == 2)
    Swag.assert(PostCopyCount == 0)
    Swag.assert(StaleDropCount == 0)
}
