#global private

/**
# The 'with' Statement
The 'with' statement reduces repetition by letting you access fields and methods
of a variable, struct, or namespace within a scoped block. Inside a 'with' block,
the '.' prefix refers to the selected object, yielding concise, readable code.
*/

struct Point
{
    x, y: s32
}

impl Point
{
    mtd setOne()
    {
        me.x, me.y = 1

    // Set both coordinates to 1 on this Point.
    }
}

/**
# 'with' and a Namespace
You can apply 'with' to a namespace to call functions or access constants
without fully qualifying names.
*/
namespace NameSpace
{
    func inside0()
    {
    // Example namespaced function.
    }

    func inside1()
    {
    // Another namespaced function.
    }
}

/**
# 'with' on a Variable
Use 'with' with a variable to streamline field access without repeating
the variable name.
*/
#test
{
    var pt: Point
    with pt
    {
        .x = 1     // Equivalent to 'pt.x = 1'
        .y = 2     // Equivalent to 'pt.y = 2'
    }

    @assert(pt.x == 1)
    @assert(pt.y == 2)
}

/**
# Calling Functions inside 'with'
Inside a 'with' block, you can invoke methods and access fields directly.
*/
#test
{
    var pt: Point
    with pt
    {
        .setOne()     // Equivalent to 'pt.setOne()'
        .y = 2        // Adjust a single field afterward
        @assert(.x == 1)
        @assert(.y == 2)
    }

    @assert(pt.x == 1)
    @assert(pt.y == 2)
}

/**
# Using Names from a 'with' Namespace
Demonstrates calling namespaced functions via 'with'.
*/
#test
{
    with NameSpace
    {
        .inside0()
        .inside1()
    }
}

/**
# Declaring a Variable with 'with'
You can declare a variable directly in the 'with' header and work with it
immediately inside the block.
*/
#test
{
    with var pt = Point{1, 2}
    {
        .x = 10
        .y = 20
    }

    @assert(pt.x == 10 and pt.y == 20)
}

#test
{
    with var pt: Point     // Declaration without initializer
    {
        .x = 10
        .y = 20
    }

    @assert(pt.x == 10 and pt.y == 20)
}

/**
# Assignment inside 'with'
You can also use 'with' on an assignment to modify the freshly assigned value
immediately.
*/
#test
{
    var pt: Point
    with pt = Point{1, 2}
    {
        .x = 10
        .y = 20
    }

    @assert(pt.x == 10 and pt.y == 20)
}
