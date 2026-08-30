#global private

/**
# Tuples in Swag

A tuple represents an anonymous structure (a *struct literal*) that can group multiple values
of different types together without defining a named structure. Tuples are enclosed in curly braces '{}'
and can mix any combination of data types.
*/
#test
{
    let tuple1 = {2, 2}
    let tuple2 = {"string", 2, true}
}

/**
# Accessing Tuple Values

Tuple fields are automatically named 'itemX', where 'X' is the zero-based index of the field.
*/
#test
{
    let tuple = {"string", 2, true}
    Swag.assert(tuple.item0 == "string")
    Swag.assert(tuple.item1 == 2)
    Swag.assert(tuple.item2 == true)
}

/**
# Named Fields in Tuples

Tuple fields can have explicit names.
*/

#test
{
    let tuple = {x: 1.0, y: 2.0}
    Swag.assert(tuple.x == 1.0)
    Swag.assert(tuple.y == 2.0)
}

/**
# Automatic Field Naming

When creating a tuple from variables, Swag automatically uses the variable names as field names
unless overridden.
*/

#test
{
    let x = 555
    let y = 666
    let t = {x, y}
    Swag.assert(t.x == 555)
    Swag.assert(t.y == 666)
}

/**
# Tuple Assignment and Compatibility

Tuples can be assigned to each other if their field types match, even if field names differ.
*/
#test
{
    var x:
    {
        a: s32
        b: s32
    }
    var y:
    {
        c: s32
        d: s32
    }

    y = {1, 2}
    x = y

    Swag.assert(x.a == 1)
    Swag.assert(x.b == 2)
    #assert(#typeof(x) != #typeof(y))
}

/**
# Positional Tuple Destructuring

Curly-braced patterns destructure tuple fields by position. A positional pattern provides
one binding or placeholder for every field.
*/

#test
{
    let tuple1           = {x: 1.0, y: 2.0}
    let {value0, value1} = tuple1
    Swag.assert(value0 == 1.0)
    Swag.assert(value1 == 2.0)

    let tuple2        = {"name", true}
    let {name, value} = tuple2
    Swag.assert(name == "name")
    Swag.assert(value == true)
}

/**
# Ignoring Fields During Positional Destructuring

Use '?' as a placeholder to ignore a field.
*/

#test
{
    let tuple1 = {x: 1.0, y: 2.0}
    let {x, ?} = tuple1
    Swag.assert(x == 1.0)

    let {?, y} = tuple1
    Swag.assert(y == 2.0)
}

/**
# Named Tuple Destructuring

Write 'field: binding' to select fields by name. Named patterns can select a subset of the
fields and can list them in any order. Every entry in one pattern uses the same mode:
positional and named entries cannot be mixed.
*/

#test
{
    let point = {x: 10.0, y: 20.0}
    let {y: vertical, x: horizontal} = point
    Swag.assert(horizontal == 10.0)
    Swag.assert(vertical == 20.0)

    let {x: onlyX} = point
    Swag.assert(onlyX == 10.0)
}

/**
Unnamed tuple fields retain their implicit 'itemN' names. This also applies when explicit
and unnamed fields appear in either order.
*/

#test
{
    let namedThenUnnamed          = {x: 11, 22}
    let {x: first, item1: second} = namedThenUnnamed
    Swag.assert(first == 11)
    Swag.assert(second == 22)

    let unnamedThenNamed          = {33, y: 44}
    let {item0: third, y: fourth} = unnamedThenNamed
    Swag.assert(third == 33)
    Swag.assert(fourth == 44)
}

/**
# Destructuring Assignment

The same positional and named patterns can assign to existing storage.
*/

#test
{
    var first, second: s32
    {first, second} = {1, 2}
    Swag.assert(first == 1)
    Swag.assert(second == 2)

    var point = {x: 3, y: 4}
    {y: second, x: first} = point
    Swag.assert(first == 3)
    Swag.assert(second == 4)
}
