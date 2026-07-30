#global private

// The four member access levels, and what each one still allows.
struct Account
{
    public   id:      s32 = 1
    readonly balance: s32 = 100
    internal ledger:  s32 = 7
    private  secret:  s32 = 42
}

impl Account
{
    // The declaring type reaches and writes every level.
    mtd deposit(amount: s32)
    {
        .balance += amount
        .ledger  += 1
        .secret  += 1
    }

    mtd total()->s32 => .id + .balance + .ledger + .secret
}

#test
{
    var a: Account
    a.deposit(50)
    @assert(a.total() == 1 + 150 + 8 + 43)
}

#test
{
    // 'public' and 'readonly' read from anywhere; 'internal' reads inside the module.
    var a: Account
    @assert(a.id == 1)
    @assert(a.balance == 100)
    @assert(a.ledger == 7)
}

#test
{
    // Writing 'public' and 'internal' from outside the type stays legal.
    var a: Account
    a.id     = 3
    a.ledger = 9
    @assert(a.id == 3)
    @assert(a.ledger == 9)
}

#test
{
    // A literal may name every field a caller can write.
    let a = Account{id: 5, ledger: 6}
    @assert(a.id == 5)
    @assert(a.ledger == 6)
    @assert(a.balance == 100)
}

// An access modifier also applies as a block, and to a multi-name declaration.
struct Grouped
{
    private
    {
        a, b: s32 = 3
        c:    s32 = 4
    }

    readonly d: s32 = 5
}

impl Grouped
{
    mtd sum()->s32 => .a + .b + .c + .d
}

#test
{
    var g: Grouped
    @assert(g.sum() == 15)
    @assert(g.d == 5)
}

// A nested or anonymous aggregate declares its own members: it starts from the default
// instead of inheriting the access of the field it sits in.
struct Nested
{
    private
    {
        pair: { key: s32, value: s32 }

        struct Inner
        {
            slot: s32
        }

        inner: Inner
    }
}

impl Nested
{
    mtd fill()
    {
        .pair       = {1, 2}
        .inner.slot = 3
    }

    mtd sum()->s32 => .pair.key + .pair.value + .inner.slot
}

#test
{
    var n: Nested
    n.fill()
    @assert(n.sum() == 6)

    // The nested type declares its own members: only 'inner' is private, not 'slot'.
    var p: Nested.Inner
    p.slot = 7
    @assert(p.slot == 7)
}

// Reflection reports the declared access, so generic walkers can skip implementation state.
#test
{
    let fields = #typeof(Account).fields
    var seen   = 0
    for f in fields
    {
        let flags = f.flags
        switch f.name
        {
        case "id":
            @assert(!(flags & Swag.TypeValueFlags.ReadOnly))
            @assert(!(flags & Swag.TypeValueFlags.Internal))
            @assert(!(flags & Swag.TypeValueFlags.Private))
            seen += 1
        case "balance":
            @assert(flags & Swag.TypeValueFlags.ReadOnly)
            seen += 1
        case "ledger":
            @assert(flags & Swag.TypeValueFlags.Internal)
            seen += 1
        case "secret":
            @assert(flags & Swag.TypeValueFlags.Private)
            seen += 1
        }
    }

    @assert(seen == 4)
}
