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
    @assert(tuple.item0 == "string")
    @assert(tuple.item1 == 2)
    @assert(tuple.item2 == true)
}

/**
# Named Fields in Tuples

Tuple fields can have explicit names.
*/

#test
{
    let tuple = {x: 1.0, y: 2.0}
    @assert(tuple.x == 1.0)
    @assert(tuple.y == 2.0)
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
    @assert(t.x == 555)
    @assert(t.y == 666)
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

    @assert(x.a == 1)
    @assert(x.b == 2)
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
    @assert(value0 == 1.0)
    @assert(value1 == 2.0)

    let tuple2        = {"name", true}
    let {name, value} = tuple2
    @assert(name == "name")
    @assert(value == true)
}

/**
# Ignoring Fields During Positional Destructuring

Use '?' as a placeholder to ignore a field.
*/

#test
{
    let tuple1 = {x: 1.0, y: 2.0}
    let {x, ?} = tuple1
    @assert(x == 1.0)

    let {?, y} = tuple1
    @assert(y == 2.0)
}

/**
# Named Tuple Destructuring

Write 'field: binding' to select fields by name. Named patterns can select a subset of the
fields and can list them in any order. Every entry in one pattern uses the same mode:
positional and named entries cannot be mixed.
*/

#test
{
    let point                        = {x: 10.0, y: 20.0}
    let {y: vertical, x: horizontal} = point
    @assert(horizontal == 10.0)
    @assert(vertical == 20.0)

    let {x: onlyX} = point
    @assert(onlyX == 10.0)
}

/**
Unnamed tuple fields retain their implicit 'itemN' names. This also applies when explicit
and unnamed fields appear in either order.
*/

#test
{
    let namedThenUnnamed          = {x: 11, 22}
    let {x: first, item1: second} = namedThenUnnamed
    @assert(first == 11)
    @assert(second == 22)

    let unnamedThenNamed          = {33, y: 44}
    let {item0: third, y: fourth} = unnamedThenNamed
    @assert(third == 33)
    @assert(fourth == 44)
}

/**
# Destructuring Assignment

The same positional and named patterns can assign to existing storage.
*/

#test
{
    var first, second: s32
    {first, second} = {1, 2}
    @assert(first == 1)
    @assert(second == 2)

    var point = {x: 3, y: 4}
    {y: second, x: first} = point
    @assert(first == 3)
    @assert(second == 4)
}
