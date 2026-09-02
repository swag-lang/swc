#global private

// The three member access levels, the default they share with a top-level declaration, and the
// write restriction that rides on top of any of them.
struct Account
{
    public id:               s32  = 1
    public readonly balance: s32  = 100
    ledger:                  s32  = 7
    private secret:          s32  = 42
    opened:                  bool = true
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
    Swag.assert(a.total() == 1 + 150 + 8 + 43)
}

#test
{
    // 'public' and 'public readonly' read from anywhere; 'internal' and the default read inside
    // the module.
    var a: Account
    Swag.assert(a.id == 1)
    Swag.assert(a.balance == 100)
    Swag.assert(a.ledger == 7)
    Swag.assert(a.opened)
}

#test
{
    // Writing 'public', 'internal' and the default from outside the type stays legal.
    var a: Account
    a.id     = 3
    a.ledger = 9
    a.opened = false
    Swag.assert(a.id == 3)
    Swag.assert(a.ledger == 9)
    Swag.assert(!a.opened)
}

#test
{
    // A literal may name every field a caller can write.
    let a = Account{id: 5, ledger: 6}
    Swag.assert(a.id == 5)
    Swag.assert(a.ledger == 6)
    Swag.assert(a.balance == 100)
}

// An access modifier applies to a block and to a multi-name declaration. A single field keeps
// the modifier on its declaration, and 'readonly' rides on the level already in effect.
struct Grouped
{
    private
    {
        a, b: s32 = 3
        c:    s32 = 4
    }

    readonly d: s32 = 5

    public readonly e: s32 = 6
}

impl Grouped
{
    mtd sum()->s32 => .a + .b + .c + .d + .e
}

#test
{
    var g: Grouped
    Swag.assert(g.sum() == 21)
    Swag.assert(g.d == 5)
    Swag.assert(g.e == 6)
}

// A nested NAMED aggregate declares its own members: it starts from the default instead of
// inheriting the access of the field it sits in. An anonymous one has no declaration a modifier
// could be written on, so its members are public and the field that carries it decides who
// reaches them.
struct Nested
{
    private
    {
        pair: { key: s32, value: s32 }

        struct Inner
        {
            public slot: s32
        }

        inner: Inner
    }
}

// A nested named aggregate and a top-level declaration block introduce declaration scopes of
// their own. Their access modifiers do not restate the level of the enclosing block.

public
{
    struct PublicContainer
    {
        public
        {
            readonly value: s32 = 8

            struct PublicInner
            {
                public value: s32 = 9
            }
        }
    }
}

#test
{
    let outer: PublicContainer
    let inner: PublicContainer.PublicInner
    Swag.assert(outer.value == 8)
    Swag.assert(inner.value == 9)
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
    Swag.assert(n.sum() == 6)

    // The nested type declares its own members: only 'inner' is private, not 'slot'.
    var p: Nested.Inner
    p.slot = 7
    Swag.assert(p.slot == 7)
}

// A returned tuple is an anonymous aggregate too, so a caller reads what it names.
func split(value: s32)->{ half: s32, rest: s32 } => {value / 2, value % 2}

#test
{
    let r = split(7)
    Swag.assert(r.half == 3)
    Swag.assert(r.rest == 1)
}

// Reflection reports the level and the write restriction separately, so generic walkers can skip
// implementation state.
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
            Swag.assert(!(flags & Swag.TypeValueFlags.ReadOnly))
            Swag.assert(!(flags & Swag.TypeValueFlags.Internal))
            Swag.assert(!(flags & Swag.TypeValueFlags.Private))
            seen += 1
        case "balance":
            Swag.assert(flags & Swag.TypeValueFlags.ReadOnly)
            Swag.assert(!(flags & Swag.TypeValueFlags.Internal))
            seen += 1
        case "ledger":
            Swag.assert(flags & Swag.TypeValueFlags.Internal)
            seen += 1
        case "secret":
            Swag.assert(flags & Swag.TypeValueFlags.Private)
            seen += 1
        case "opened":
            Swag.assert(flags & Swag.TypeValueFlags.Internal)
            Swag.assert(!(flags & Swag.TypeValueFlags.ReadOnly))
            seen += 1
        }
    }

    Swag.assert(seen == 5)
}

#test
{
    // 'readonly' written alone rides on the default, so it reports both flags.
    let fields = #typeof(Grouped).fields
    var seen   = 0
    for f in fields
    {
        switch f.name
        {
        case "d":
            Swag.assert(f.flags & Swag.TypeValueFlags.ReadOnly)
            Swag.assert(f.flags & Swag.TypeValueFlags.Internal)
            seen += 1
        case "e":
            Swag.assert(f.flags & Swag.TypeValueFlags.ReadOnly)
            Swag.assert(!(f.flags & Swag.TypeValueFlags.Internal))
            seen += 1
        }
    }

    Swag.assert(seen == 2)
}
