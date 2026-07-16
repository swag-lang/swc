#global public
// Iterator invalidation: structurally mutating a collection while an enclosing loop
// iterates it. Force the lifecycle sanity so the checks fire in every build config.
#global #[Swag.Sanity(.Lifecycle, true)]
using Swag

// A minimal dynamic container exercised the way the standard collections are: a
// '#[Macro] opVisit' drives 'foreach', and 'add'/'remove' are non-const methods that
// grow or move the backing storage (here a fixed buffer stands in for a heap block).
struct CollMutVec
{
    buffer: [16] s32
    count:  u64
}

// Two independent collections behind a shared owner, to check field-granular tracking.
struct CollMutHolder
{
    items: CollMutVec
    other: CollMutVec
}

impl CollMutVec
{
    mtd add(value: s32)
    {
        me.buffer[me.count] = value
        me.count += 1
    }

    mtd remove()
    {
        if me.count > 0 do
            me.count -= 1
    }

    #[Swag.Inline]
    mtd const opCount()->u64
    {
        return me.count
    }

    #[Swag.Inline]
    mtd const opIndex(index: u64)->s32
    {
        return me.buffer[index]
    }

    #[Macro]
    func(ptr: bool, back: bool) opVisit(me, stmt: #code(item, index: u64))
    {
        for idx in me.count
        {
            #if ptr do
                #inject(stmt, item = cast(&s32) &me.buffer[idx], index = idx)
            #else do
                #inject(stmt, item = me.buffer[idx], index = idx)
        }
    }
}

// Adding to the very collection being iterated invalidates the loop.
func collMutAddDuringIter()
{
    var v: CollMutVec
    v.add(1)
    v.add(2)
    for x in v
    {
        v.add(x) // swc-expected-error {{sanity_err_collection_mutated}}
    }
}

// Removing during a by-address iteration dangles the alias.
func collMutRemoveDuringIter()
{
    var v: CollMutVec
    v.add(1)
    v.add(2)
    for &x in v
    {
        x += 1
        v.remove() // swc-expected-error {{sanity_err_collection_mutated}}
    }
}

// Mutating through an alias of the iterated variable is caught too.
func collMutThroughAlias()
{
    var v: CollMutVec
    v.add(1)
    let p = &v
    for x in v
    {
        p.add(x) // swc-expected-error {{sanity_err_collection_mutated}}
    }
}

// Mutating a DIFFERENT collection is fine.
func collMutOtherCollection()
{
    var v: CollMutVec
    var w: CollMutVec
    v.add(1)
    for x in v
    {
        w.add(x)
    }
}

// Reading (const methods, element access) during iteration is fine.
func collMutReadDuringIter()->u64
{
    var v: CollMutVec
    v.add(1)
    var total: u64
    for x in v
    {
        total += v.opCount()
        total += cast(u64) v[0]
    }
    return total
}

// Mutating after the loop has finished is fine.
func collMutAfterIter()
{
    var v: CollMutVec
    v.add(1)
    for x in v
    {
        var _ = x
    }
    v.add(2)
}

// Iteration is tracked at the projected storage level: mutating a sibling field of the
// same owner is fine, mutating the iterated field itself is not.
func collMutProjectionSibling()
{
    var holder: CollMutHolder
    holder.items.add(1)
    for x in holder.items
    {
        holder.other.add(x)
    }
}

func collMutProjectionSameField()
{
    var holder: CollMutHolder
    holder.items.add(1)
    for x in holder.items
    {
        holder.items.add(x) // swc-expected-error {{sanity_err_collection_mutated}}
    }
}

// Mutating then leaving the loop right away is safe: the snapshot is never read again.
// 'return' after the mutation.
func collMutRemoveThenReturn(target: s32)->bool
{
    var v: CollMutVec
    v.add(1)
    v.add(2)
    for x, i in v
    {
        if x == target
        {
            v.remove()
            return true
        }
    }
    return false
}

// 'break' after the mutation.
func collMutRemoveThenBreak()
{
    var v: CollMutVec
    v.add(1)
    for x, i in v
    {
        if x == 1
        {
            v.remove()
            break
        }
    }
}
