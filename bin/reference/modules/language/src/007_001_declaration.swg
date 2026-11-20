#global private

/**
# Function Declarations

A function declaration starts with the 'func' keyword, followed by the function name
and parentheses. If no parameters are needed, the parentheses remain empty.
*/
func toto() {}

/**
# Returning Values from Functions

If a function returns a value, use '->' followed by the return type.
The body must contain a 'return' statement.
*/
func toto1()->s32
{
    return 0
}

/**
# Every Path Must Produce the Value

A function that declares a return type is rejected when its body can reach the end without
returning: the promise is part of the signature, and a value the caller reads has to exist.

What counts as leaving the function is 'return', 'fail', 'unreachable', 'Swag.panic', a call to
a function marked '#[Swag.NoReturn]', an 'if' whose branches all leave, a loop with no way out,
or an exhaustive 'switch' whose branches all leave. For a closed enum, a switch can prove
every value covered when its cases include the default-initialized value as well as every
declared value, or when it has an unconditional 'default' arm.

'unreachable' is the escape hatch when a path cannot happen for a reason the compiler cannot
see. It costs nothing once its guard is off.
*/
enum Season { Summer, Winter }

func seasonLength(season: Season)->s32
{
    switch season
    {
    case .Summer: return 92
    case .Winter: return 90
    }
}

#test
{
    Swag.require(seasonLength(Season.Winter) == 90)
}

/**
'#[Swag.NoReturn]' adds a function of your own to that list: a call to it ends the path the
same way 'Swag.panic' does, so nothing has to follow it. The function keeps the promise
itself: it has no return type, contains no 'return', and ends every path with a call that
does not come back.
*/
#[Swag.NoReturn]
func invalidSeason()
{
    Swag.panic("this index names no season", #curlocation)
}

func seasonAt(index: s32)->Season
{
    if index == 0 do
        return .Summer
    if index == 1 do
        return .Winter
    invalidSeason()
}

#test
{
    Swag.require(seasonAt(1) == Season.Winter)
}

/**
# Inferring Return Types

Use '=>' for simple expressions when the return type can be inferred automatically.
*/
func sum(x, y: s32) => x + y

/**
# Defining Parameters in Functions

Parameters are declared within parentheses after the function name. Required parameters
with the same type can share a type annotation.
*/
func sum1(x, y: s32, scale: f32)->f32
{
    return cast(f32, x + y) * scale
}

/**
# Using Default Parameter Values

Each optional parameter declares its own default value with '='. The caller can omit
that argument.
*/
func sum2(x, y: s32, scale: f32 = 1)->f32
{
    return cast(f32, x + y) * scale
}

/**
# Inferred Parameter Types

If a parameter has a default value, its type can be inferred from it.
*/
func sum3(x = 0.0, y = 0.0)
{
    #assert(#typeof(x) == f32)
    #assert(#typeof(y) == f32)
}

/**
# Overloading Functions

Multiple functions can share the same name if they differ in parameter count or types.
*/
enum Values { A, B }

func toto(x: s32, y = Values.A)
{
    #assert(#typeof(x) == s32)
    #assert(#typeof(y) == Values)
}

/**
# Nested Functions

Functions can be nested within other functions for local logic organization.
Nested functions are scoped, not closures.
*/
#test
{
    func sub(x, y: s32) => x - y

    let x = sub(5, 2)
    Swag.require(x == 3)
}

/**
# Named Parameters and Parameter Order

Named parameters allow calling functions with arguments in any order.
*/
#test
{
    func sub(x, y: s32) => x - y
    scope
    {
        let x1 = sub(x: 5, y: 2)
        Swag.require(x1 == 3)

        let x2 = sub(y: 5, x: 2)
        Swag.require(x2 == -3)
    }

    scope
    {
        func returnMe(x: s32 = 0, y: s32 = 0) => x + y * 2
        Swag.require(returnMe(x: 10) == 10)
        Swag.require(returnMe(y: 10) == 20)
    }
}

/**
# Returning Multiple Values with Anonymous Structs

Functions can return anonymous structs to conveniently hold multiple values.
These can be accessed directly or destructured.
*/

#test
{
    func myFunction()->{ x, y: f32 }
    {
        return {1.0, 2.0}
    }

    let result = myFunction()
    Swag.require(result.x == 1.0)
    Swag.require(result.y == 2.0)
    let {x, y} = myFunction()
    Swag.require(x == 1.0)
    Swag.require(y == 2.0)
    let {x: z, y: w} = myFunction()
    Swag.require(z == 1.0)
    Swag.require(w == 2.0)
}
