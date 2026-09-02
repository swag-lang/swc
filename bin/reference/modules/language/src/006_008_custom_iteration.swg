#global private

struct MyStruct
{
    x: s32 = 10
    y: s32 = 20
    z: s32 = 30
}

/**
# The 'opVisit' Iteration Hook

'opVisit' is the single custom iteration hook. It is a macro generic over the
compile-time boolean 'ptr': 'ptr' is true for a loop binding introduced by '&',
and the hook then injects the element's address ('*T') instead of its value.
There is no traversal selector or direction argument. Alternative traversals
are ordinary borrowed views returned by functions or methods.

The '#code' parameters are the values made available to loop destructuring.
A loop may bind any prefix of them, or discard a position with '?'. Struct
values are handed out by read-only address; scalar values are copied.
*/
impl MyStruct
{
    #[Swag.Macro]
    mtd(ptr: bool) const opVisit(stmt: #code(item: s32, doubled: s32, index: u64))
        where !ptr
    {
        for index in 3
        {
            var item: s32 = undefined
            switch index
            {
            case 0:  item = me.x
            case 1:  item = me.y
            default: item = me.z
            }

            #inject(stmt, item = item, doubled = item * 2, index = index)
        }
    }
}

/**
# Destructuring Visit Values

The bindings after 'for' are positional. '?' discards one position, consistently
with other destructuring forms, and it can stand in any of them: a loop that wants
only the last value discards the ones before it rather than naming them.
*/
#test
{
    let values = MyStruct{}
    var total: s32

    for value, doubled, index in values do
        total += value + doubled + cast(s32) index

    for ?, doubled in values do
        total += doubled

    for ?, ?, index in values do
        total += cast(s32) index

    Swag.assert(total == 306)
}

#[Swag.Opaque]
struct ReversedMyStruct
{
    source: const *MyStruct
}

impl ReversedMyStruct
{
    #[Swag.Macro]
    mtd(ptr: bool) const opVisit(stmt: #code(item: s32, index: u64))
        where !ptr
    {
        #inject(stmt, item = me.source.z, index = 2'u64)
        #inject(stmt, item = me.source.y, index = 1'u64)
        #inject(stmt, item = me.source.x, index = 0'u64)
    }
}

impl MyStruct
{
    // Returns a zero-allocation borrowed view with reverse traversal.
    mtd const reversed()->ReversedMyStruct
    {
        return {source: me}
    }
}

/**
# Composable Traversal Views

A view is an ordinary small value, usually a pointer or slice. Constructing it
does not copy the source or allocate memory. Since the view itself implements
'opVisit', views compose with regular calls and require no compiler-specific
'#Name' convention.
*/
#test
{
    let values = MyStruct{}
    var code: s32

    for value in values.reversed() do
        code = code * 100 + value

    Swag.assert(code == 302010)
}

struct SliceStruct
{
    buffer: [?] s32 = [1, 2, 3, 4, 5]
}

impl SliceStruct
{
    #[Swag.Macro]
    mtd(ptr: bool) opVisit(stmt: #code(item, index: u64))
    {
        for index in me.buffer.count
        {
            #static if ptr do
                #inject(stmt, item = cast(*s32) &me.buffer[index], index = index)
            else do
                #inject(stmt, item = me.buffer[index], index = index)
        }
    }
}

/**
# Visiting by Address

The '&' binding selects 'ptr == true', and the hook answers with the element's
mutable address: the loop binding is a non-null pointer, and the loop body
writes the element through '[]'. Without '&', scalar elements are copied
into the loop binding.
*/
#test
{
    var values = SliceStruct{}

    for &value, index in values do
        value[] += cast(s32) index

    Swag.assert(values.buffer[0] == 1)
    Swag.assert(values.buffer[4] == 9)
}

/**
# Standard Views

Collections expose traversal policies as regular methods. For example,
'.pairs()' visits adjacent elements and '.reversed()' visits in reverse order.
Both return constant-size, zero-allocation views, and each names the positions it
hands out: '.pairs()' adds the position of the left element after the two values.
*/
#test
{
    let values: [4] s32 = [2, 4, 6, 8]
    var code:   s32
    var steps:  u64

    for left, right, index in values.pairs()
    {
        code  = code * 100 + left * 10 + right
        steps += index
    }

    Swag.assert(code == 244668)
    Swag.assert(steps == 0 + 1 + 2)
}
