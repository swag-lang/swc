#global private

/**
# Return Value Usage
Swag enforces that all function return values must be used.
If a function’s result is ignored, the compiler raises an error.
This prevents accidental omission of important results and ensures deliberate handling of all return values.
*/
#test
{
    func sum(x, y: s32) => x + y

    // Uncommenting the following line would cause a compile-time error:
    // sum(2, 3)

    // Use 'discard' to explicitly ignore the return value
    discard sum(2, 3)
}

/**
# `Swag.Discardable` Attribute
Marking a function with '#[Swag.Discardable]' allows its return value to be safely ignored.
Use this for utility functions whose results are optional.
*/
#test
{
    #[Swag.Discardable]
    func mul(x, y: s32)->s32 => x * y

    // Return value can be ignored without using 'discard'
    mul(2, 4)
}

/**
# Unused Names
A name is declared to be used. A local variable, a parameter, or a closure capture that nothing
in its body refers to is an error, and so is the name of a loop that never reads it.

```swag
func scale(value: s32, factor: s32)->s32 => value     // error: unused parameter 'factor'
```

A local whose type has an 'opDrop' is the exception: it is a guard, and the drop at the end of
its scope is its use. The parameters of an interface method are another one: they belong to the
interface, whatever a default implementation does with them.
*/

/**
# Unnamed Parameters
A parameter the body has no use for is spelled '_'. It keeps its position and its type, and has
no name: nothing can refer to it, and reflection reports it with an empty name. This is how a
callback, an interface implementation or an operator states that it ignores an argument.
*/
#test
{
    func second(_: s32, b: s32)->s32 => b
    Swag.assert(second(1, 2) == 2)

    // Several parameters can be unnamed at once: '_' is not a name, so it never clashes.
    func neither(_: s32, _: s32)->s32 => 0
    Swag.assert(neither(1, 2) == 0)

    // A lambda leaves an inferred parameter unnamed the same way.
    func apply(cb: func(s32, s32)->s32)->s32 => cb(10, 20)
    Swag.assert(apply(func(_, b) => b) == 20)

    #assert(#typeof(second).name == "func(s32, b: s32)->s32")
}

/**
'_' is the same placeholder wherever a binding is declared: a loop position, a destructuring
position, or a '#code' binder. It is not a name, so it can appear several times in one
declaration, and reading it is an error.
*/
#test
{
    var total = 0'u64
    for _, index in [10, 20, 30] do
        total += index
    Swag.assert(total == 3)

    let {_, second} = {1, 2}
    Swag.assert(second == 2)

    // A counting loop that does not read its index simply has no name.
    for 3 do
        total += 1
    Swag.assert(total == 6)
}

/**
# Keeping a Name
'discard' also takes variable names. It is the way to keep a name the body does not use when the
name itself must stay: a public parameter that callers pass by name or that the documentation
refers to, or a value used only in a '#static if' branch this configuration does not compile.
One 'discard' lists them all; a list holds variable names only, and any other expression keeps
its own 'discard'.
*/
#test
{
    func onPressed(sender: string, index: s32)
    {
        discard sender, index
    }

    onPressed("ok", 0)
}

/**
There is no naming convention for an unused value: a leading underscore is an ordinary name.
*/
