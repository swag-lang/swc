#global private

/**
# The Leading Dot

A leading dot always names a member of an implicit subject. The subject is never
guessed from the name: it is decided by the position, on one of two planes.

- The **type plane**. Where the position already requires a type — a call
  argument, an assignment to a typed place, a 'case' of a 'switch', an operand
  compared against a typed value — the subject is that type.
- The **subject plane**. The subject is a value in scope: the innermost 'with'
  target, and 'me' when no 'with' is open.

The planes are ordered by how much the position really settles:

> An enum required by the position wins over every subject. Any other required
> type is a fallback, taken only when no subject has the name.

An enum member has no other reading in a typed slot, which is what makes
'case .Red' and 'paint(.Blue)' unambiguous. A non-enum required type is a much
weaker signal — an operand type travels to the other side of a comparison, so
'if size >= .count' would start reading '.count' on the left operand's type
rather than on the subject the method is written against.

The rules below are pinned by the tests on this page, so a change to how a dot
resolves shows up as a test failure rather than as a surprise in a caller.
*/

enum Channel
{
    Red
    Green
    Blue
}

func channelScore(c: Channel)->s32
{
    switch c
    {
    case .Red:   return 1
    case .Green: return 2
    default:     return 3
    }
}

/**
# The Type Plane

A position that already fixes a type lends it to the dot. This is the reading a
'case' label, a call argument, and a typed initializer all use.
*/
#test
{
    // A 'case' label is judged against the switch expression's type.
    Swag.assert(channelScore(Channel.Green) == 2)

    // A parameter declares the type, so '.Blue' names 'Channel.Blue'.
    Swag.assert(channelScore(.Blue) == 3)

    // So does a typed place.
    var picked: Channel = .Green
    Swag.assert(picked == .Green)
}

struct Slot
{
    value: s32
}

impl Slot
{
    mtd bump(by: s32)
    {
        // No 'with' is open, so the subject is the receiver: '.value' is 'me.value'.
        .value += by
    }

    mtd doubled() => .value * 2
}

/**
# The Subject Plane

Inside a method the subject is the receiver. Inside a 'with' block it is the
'with' target, which is nearer.
*/
#test
{
    var slot: Slot
    slot.bump(4)
    Swag.assert(slot.doubled() == 8)

    var other: Slot
    with other
    {
        .value = 21
    }

    Swag.assert(other.value == 21)
}

struct Reading
{
    tag: s32
}

struct Recorder
{
    total: s32
}

impl Recorder
{
    mtd record(reading: *Reading)
    {
        with reading
        {
            // The 'with' target is the subject here, so this writes the reading.
            .tag = 1

            // 'total' belongs to the receiver, not to the reading. Naming the
            // subject is what says so; a bare '.total' is reported instead of
            // reaching past the reading to find it.
            me.total += 1
        }

        // The 'with' is closed: the receiver is the subject again.
        .total += 1
    }
}

/**
# The Innermost Subject Answers

Where several subjects are live, the nearest one answers, and only that one: a
leading dot never reaches past it to an enclosing subject. A 'with' target is
nearer than the receiver it is written inside, and a nested 'with' is nearer than
the one that encloses it.

The rule exists to keep the reader out of the classic 'with' defect, where a
block silently captures a name the reader expected to come from the enclosing
method. When the innermost subject has no such member, the access is reported
and the source names the subject it meant.

When two live subjects both carry the name, the innermost one answers. That is
the whole rule: nesting decides, and nothing else is consulted.
*/
#test
{
    var reading:  Reading
    var recorder: Recorder
    recorder.record(&reading)

    Swag.assert(reading.tag == 1)
    Swag.assert(recorder.total == 2)
}

/**
# 'with' Takes a Value

The subject of a 'with' is always a value: a variable, a field, an element, or a
value the header declares. A namespace, an enum, or a struct type names a scope
rather than a value, and 'using' is what brings a scope into the current context.

Keeping the two apart is what makes "the subject is a value" a rule instead of a
tendency: 'using' publishes names, 'with' selects a value.
*/
#test
{
    using Channel

    // 'using' publishes the enum's values under their bare names.
    let direct = Blue
    Swag.assert(direct == Channel.Blue)
    Swag.assert(channelScore(direct) == 3)
}

/**
# The Right-Hand Side of a Dot

One rule belongs to the infix dot rather than to the leading one: an
'impl I for T' publishes its functions under a scope named 'I' inside 'T', so
'value.I.method()' reaches that implementation. That is the only place where the
name after a dot is a scope instead of a member, and it is how a call to a base
implementation is written.

# The Leading Dot Is Saturated

A construct that wants an implicit subject of its own takes a word, not the dot.
The language has already answered this once: a literal names its fields with
'name:' and never with a leading dot.
*/
#test
{
    let slot = Slot{value: 7}
    Swag.assert(slot.value == 7)
}
