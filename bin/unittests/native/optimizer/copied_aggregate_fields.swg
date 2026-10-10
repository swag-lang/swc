#global private

// A sixteen-byte value copied into a local and then read field by field: an interface's
// receiver and method table, a slice's data and count, a string's bytes and length. Each
// field may be read from the source instead of the copy, but only while nothing has written
// the source since the copy was taken.

interface ICounter
{
    mtd add(value: u64)->u64
}

struct Counter { total: u64 }
impl ICounter for Counter
{
    mtd impl add(value: u64)->u64
    {
        .total += value
        return .total
    }
}

struct Holder
{
    counter: ICounter
    words:   const [..] u64
    name:    string
}

#[Swag.Optimize(true), Swag.NoInline]
func callThrough(holder: *Holder, value: u64)->u64
{
    let counter = holder.counter
    return counter.add(value)
}

#[Swag.Optimize(true), Swag.NoInline]
func sumWords(holder: const *Holder)->u64
{
    let words = holder.words
    var sum   = 0'u64
    for w in words do
        sum += w
    return sum
}

#[Swag.Optimize(true), Swag.NoInline]
func nameWeight(holder: const *Holder)->u64
{
    let name = holder.name
    return name.count * 1000 + name[0]
}

// The copy is taken before the holder's fields are replaced: it keeps the old values, so
// its fields cannot come from the holder after those stores.
#[Swag.Optimize(true), Swag.NoInline]
func sumBeforeReplace(holder: *Holder, other: const [..] u64, otherName: string)->u64
{
    let words = holder.words
    let name  = holder.name
    holder.words = other
    holder.name  = otherName
    var sum = name.count
    for w in words do
        sum += w
    return sum
}

#test
{
    var counter = Counter{5}
    let first   = [1'u64, 2, 3]
    let second  = [10'u64, 20]
    var holder  = Holder{counter: &counter, words: first, name: "abc"}

    Swag.assert(callThrough(&holder, 7) == 12)
    Swag.assert(callThrough(&holder, 1) == 13)
    Swag.assert(sumWords(&holder) == 6)
    Swag.assert(nameWeight(&holder) == 3000 + 'a')

    Swag.assert(sumBeforeReplace(&holder, second, "hello") == 9)
    Swag.assert(sumWords(&holder) == 30)
    Swag.assert(nameWeight(&holder) == 5000 + 'h')
}
