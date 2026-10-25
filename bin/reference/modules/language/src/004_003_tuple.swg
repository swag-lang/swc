#global private

/**
# Tuples and Records

A tuple groups values by position. A record groups values by field name. Their construction,
types and destructuring patterns use different delimiters: parentheses for tuples and braces
for records. Neither family implicitly converts to the other.

Braces whose destination is a struct initialize that struct instead, and can then list values
by position: 'let p: Point = {1, 2}'. Without such a destination, braces need field names.
*/
#test
{
    let pair = (10, 20)
    Swag.assert(pair.item0 == 10 and pair.item1 == 20)

    let point = {x: 10, y: 20}
    Swag.assert(point.x == 10 and point.y == 20)
}

/**
# Positional Tuples

Tuple elements have zero-based 'itemN' accessors. A tuple type lists the element types in
position order. An initializer, argument or return value matches those positions.
*/
#test
{
    func makePair()->(string, s32) => ("name", 42)

    let (name, count) = makePair()
    Swag.assert(name == "name" and count == 42)

    var pair: (s32, s32) = (10, 20)
    (pair.item1, pair.item0) = pair
    Swag.assert(pair.item0 == 20 and pair.item1 == 10)
}

/**
# One-Element Tuples and Grouping

A comma distinguishes a one-element tuple from a parenthesized expression. Write '(value,)'
and '(T,)' for its value and type, and '(binding,)' for its destructuring pattern. '(value)'
remains ordinary grouping. An empty '()' is not a tuple value.
*/
#test
{
    var single: (s32,) = (42,)
    let (value,)       = single
    Swag.assert(value == 42 and (value) == 42)
    single.item0 = 43
    Swag.assert(single.item0 == 43)
}

/**
# Named Records

Each record field has a name. A bare identifier abbreviates 'name: name'. When the braces
initialize a struct, an identifier that names none of its fields is a positional value
instead. Anonymous record types list the names and their types in braces.
*/
#test
{
    let x     = 10
    let y     = 20
    let point = {x, y}
    Swag.assert(point.x == 10 and point.y == 20)

    var destination: {x: s32, y: s32}
    destination = {y: 40, x: 30}
    Swag.assert(destination.x == 30 and destination.y == 40)
}

/**
# Record Compatibility

Record assignment, arguments and returns associate fields by name, even when declaration
orders differ. Anonymous records need exactly the same field names and compatible field types.
A record with 'width' and 'height' does not implicitly become one with 'x' and 'y'. Reconstruct
the destination explicitly when changing names or selecting a smaller record.

Equality compares corresponding fields. Tuples correspond by position; records correspond by
name. Field declaration order remains meaningful for storage and reflection.
*/
#test
{
    let point     = {x: 10, y: 20}
    let reordered = {y: 20, x: 10}
    Swag.assert(point == reordered)

    let dimensions = {width: point.x, height: point.y}
    Swag.assert(dimensions.width == 10 and dimensions.height == 20)
}

/**
# Tuple Destructuring

A positional pattern has one binding or '_' placeholder for every element. Binding names do
not select elements. Tuple patterns cannot destructure a record or a named struct.
*/
#test
{
    let pair   = (10, 20)
    let (y, x) = pair
    Swag.assert(y == 10 and x == 20)

    let (_, second) = pair
    Swag.assert(second == 20)
}

/**
# Record and Struct Destructuring

A named pattern selects fields by name. Bare 'field' abbreviates 'field: field'; write
'field: binding' to rename it. Both forms can appear in one pattern. Named patterns can select
a subset in any order. A missing field or a field selected twice is an error.
*/
#test
{
    let point  = {x: 10, y: 20}
    let {y, x} = point
    Swag.assert(y == 20 and x == 10)

    let {x: horizontal, z} = {x: 30, z: 40}
    Swag.assert(horizontal == 30 and z == 40)

    let {y: vertical} = point
    Swag.assert(vertical == 20)
}

#test
{
    struct RGB
    {
        red, green, blue: f32
    }

    let color = RGB{0.5, 0.25, 1.0}
    let {blue: b, red: r} = color
    Swag.assert(b == 1.0 and r == 0.5)
}

/**
# Destructuring Assignment

The same patterns assign to existing storage. The source is evaluated once and its values
are preserved before the targets are overwritten. This also permits exchanging fields.
*/
#test
{
    var first, second: s32
    (first, second) = (10, 20)
    Swag.assert(first == 10 and second == 20)

    var point = {x: 30, y: 40}
    {y: point.x, x: point.y} = point
    Swag.assert(point.x == 40 and point.y == 30)
}

/**
# Ignoring Named Fields

An omitted field is not bound. 'field: _' selects a field without introducing a binding.
Ignoring a value preserves the ordinary ownership and cleanup rules.
*/
#test
{
    let {x: value, y: _} = {x: 10, y: 20}
    Swag.assert(value == 10)
}

/**
# Nested Patterns

A selected field can itself contain a tuple or record pattern. Each nested pattern follows
its own delimiter's rules. Patterns have no rest form.
*/
#test
{
    let source = (2, {point: (10, 20), label: "position"})
    let (count, {point: (x, y)}) = source
    Swag.assert(count == 2 and x == 10 and y == 20)
}
