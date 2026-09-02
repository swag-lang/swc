#global private

/**
# The 'with' Statement
The 'with' statement reduces repetition by letting you access the fields and
methods of one value within a scoped block. Inside a 'with' block, the leading
dot names a member of that value.

The subject is always a value — a variable, a field, an element, or a value the
header declares. A namespace, an enum, or a struct type names a scope rather than
a value, and 'using' is what brings a scope into the current context.
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

    Swag.assert(pt.x == 1)
    Swag.assert(pt.y == 2)
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
        Swag.assert(.x == 1)
        Swag.assert(.y == 2)
    }

    Swag.assert(pt.x == 1)
    Swag.assert(pt.y == 2)
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

    Swag.assert(pt.x == 10 and pt.y == 20)
}

#test
{
    with var pt: Point     // Declaration without initializer
    {
        .x = 10
        .y = 20
    }

    Swag.assert(pt.x == 10 and pt.y == 20)
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

    Swag.assert(pt.x == 10 and pt.y == 20)
}
