#global fileprivate
struct MyStruct
{
    x: s32 = 10
    y: s32 = 20
    z: s32 = 30
}

/**
# Introduction to 'opVisit'

'opVisit' is a flexible macro for iterating over elements of a struct or any
data it owns (dynamic arrays, buffers, object graphs). The '#[Swag.Macro]'
attribute is mandatory.

'opVisit' is generic over two compile-time booleans:
- 'ptr': if true, elements are visited by pointer (address).
- 'back': if true, elements are visited in reverse order.
*/
impl MyStruct
{
    #[Swag.Macro]
    func(ptr: bool, back: bool) opVisit(me, stmt: #code void)
    {
        #if ptr do
            #error("Visiting by pointer is not supported in this example.")

        #if back do
            #error("Reverse visiting is not supported in this example.")

        // Visit fields x, y, z in declaration order
        for idx in 3
        {
            #macro
            {
                var #alias0: s32 = undefined

                switch #up idx
                {
                case 0: #alias0 = #up me.x
                case 1: #alias0 = #up me.y
                case 2: #alias0 = #up me.z
                }

                var #alias1 = @index
                #inject(#up stmt)
            }
        }
    }
}

/**
# Iterating Over Struct Fields

Example usage of 'opVisit' to traverse fields of a struct.
*/
#test
{
    var myStruct = MyStruct{}
    var cpt = 0

    foreach v, i in myStruct
    {
        switch i
        {
        case 0: @assert(v == 10)
        case 1: @assert(v == 20)
        case 2: @assert(v == 30)
        }
        cpt += 1
    }

    @assert(cpt == 3)
}

/**
# Extending 'opVisit': Reverse Order Iteration

An alternative macro that visits fields in reverse order.
*/
impl MyStruct
{
    #[Swag.Macro]
    mtd(ptr: bool, back: bool) opVisitReverse(stmt: #code void)
    {
        for idx in 3
        {
            #macro
            {
                var #alias0: s32 = undefined
                switch #up idx
                {
                case 0: #alias0 = #up me.z
                case 1: #alias0 = #up me.y
                case 2: #alias0 = #up me.x
                }

                var #alias1 = @index
                #inject(#up stmt)
            }
        }
    }
}

/**
# Reverse Order Iteration

Using 'opVisitReverse' to iterate fields from last to first.
*/
#test
{
    var myStruct = MyStruct{}
    var cpt = 0

    foreach #Reverse v, i in myStruct
    {
        switch i
        {
        case 0: @assert(v == 30)
        case 1: @assert(v == 20)
        case 2: @assert(v == 10)
        }
        cpt += 1
    }

    @assert(cpt == 3)
}

/**
# Visiting Elements in Dynamic Arrays

Beyond fields, 'opVisit' can target owned collections such as dynamic arrays.
*/
struct SliceStruct
{
    buffer: [?] s32 = [1, 2, 3, 4, 5]
}

/**
# Custom 'opVisit' for Dynamic Arrays

Iterate over 'buffer' elements instead of struct fields.
*/
impl SliceStruct
{
    #[Swag.Macro]
    func(ptr: bool, back: bool) opVisit(me, stmt: #code void)
    {
        #if back do
            #error("Reverse visiting is not supported for this slice example.")

        #if ptr
        {
            for idx in @countof(me.buffer)
            {
                #macro
                {
                    var #alias0: *s32 = cast(*s32) &(#up me.buffer[#up idx])
                    var #alias1 = @index
                    #inject(#up stmt)
                }
            }
        }
        #else
        {
            for idx in @countof(me.buffer)
            {
                #macro
                {
                    var #alias0 = #up me.buffer[#up idx]
                    var #alias1 = @index
                    #inject(#up stmt)
                }
            }
        }
    }
}

/**
# Iterating Over a Dynamic Array

Sum elements of a slice via 'opVisit'.
*/
#test
{
    var arrStruct = SliceStruct{}
    var sum = 0

    foreach v, i in arrStruct do
        sum += v

    @assert(sum == 1 + 2 + 3 + 4 + 5)
}

/**
# Visiting by Pointer

'ptr == true' lets custom iteration expose elements by address so the loop body
can update the underlying storage.
*/
#test
{
    var arrStruct = SliceStruct{}

    foreach &v, i in arrStruct do
        dref v += cast(s32) i

    @assert(arrStruct.buffer[0] == 1)
    @assert(arrStruct.buffer[1] == 3)
    @assert(arrStruct.buffer[2] == 5)
    @assert(arrStruct.buffer[3] == 7)
    @assert(arrStruct.buffer[4] == 9)
}

/**
# Named Variants of 'opVisit'

A specialization such as 'foreach #Pairs ...' resolves to 'opVisitPairs'.
This is useful when a type wants to expose multiple traversal strategies.
*/
struct WindowStruct
{
    values: [4] s32 = [2, 4, 6, 8]
}

impl WindowStruct
{
    #[Swag.Macro]
    mtd(ptr: bool, back: bool) const opVisitPairs(stmt: #code void)
    {
        #if ptr do
            #error("WindowStruct does not expose pointer iteration for pair visits.")

        for idx in 3
        {
            #macro
            {
                let #alias0 = #up me.values[#up idx]
                let #alias1 = #up me.values[#up idx + 1]
                #inject(#up stmt)
            }
        }
    }
}

/**
# Iterating Over Adjacent Pairs

Named variants can return aliases that are completely custom; '@index' still
tracks the foreach ordinal.
*/
#test
{
    let windows = WindowStruct{}
    var code = 0
    var ordinals: u64

    foreach #Pairs left, right in windows
    {
        code = code * 100 + left * 10 + right
        ordinals += @index
    }

    @assert(code == 244668)
    @assert(ordinals == 3)
}
