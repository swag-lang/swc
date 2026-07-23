#global private
/**
# Introduction to Swag Mixins
A mixin in Swag is declared similarly to a function but with the attribute '#[Swag.Mixin]'.
Mixins inject code into the caller's scope, manipulate variables, or execute as if written in that scope.
This file provides a clear set of examples and tests.
*/

#test
{
    #[Swag.Mixin]
    func myMixin()
    {
    // Basic empty mixin
    }
}

/**
# Basic Example of a Mixin
A mixin can directly modify variables in the caller's scope.
This example increments 'a' by 1 each time it is called.
*/
#test
{
    #[Swag.Mixin]
    func myMixin()
    {
        a += 1
    }

    var a = 0
    myMixin() // Equivalent to writing 'a += 1' directly here
    myMixin()
    @assert(a == 2)
}

/**
# Mixins with Parameters
Mixins behave like functions: they can take parameters, default values, and return values.
Here, 'increment' defaults to 1.
*/
#test
{
    #[Swag.Mixin]
    func myMixin(increment: s32 = 1)
    {
        a += increment
    }

    var a = 0
    myMixin() // Uses default: 'a += 1'
    myMixin(2) // Uses provided value: 'a += 2'
    @assert(a == 3)
}

/**
# Mixins with Code Blocks
A mixin can accept a '#code' parameter, representing a Swag code block defined at the call site.
The mixin can execute this block multiple times using '#inject'.
*/
#test
{
    #[Swag.Mixin]
    func doItTwice(what: #code)
    {
        #inject(what)
        // first execution
        #inject(what)
    // second execution
    }

    var a = 0
    doItTwice(#code { a += 1; })
    @assert(a == 2)
}

/**
# Passing Code Blocks in Separate Statements
When the last parameter is a '#code' statement block, the code can be provided in a
separate block after the call.
*/

#test
{
    #[Swag.Mixin]
    func doItTwice(value: s32, what: #code)
    {
        #inject(what)
        #inject(what)
    }
    var a = 0
    // Inline code argument
    doItTwice(4, #code { a += value; })
    // Separate trailing block
    doItTwice(2)
    {
        a += value
    }
    @assert(a == 12)
}

/**
# Mixins with Block Parameters
Like macros, a mixin's '#code' parameter can declare named block parameters, bound
by '#inject'. Since a mixin already runs in the caller's scope, the bindings are
plain declarations there.
*/
#test
{
    #[Swag.Mixin]
    func inc10(stmt: #code(cell))
    {
        #inject(stmt, cell = 10)
    }

    var a, b = 0
    inc10()
    {
        a += cell
    }
    inc10() #code(amount) { b += amount }
    @assert(a == b and b == 10)
}

/**
# Unique Variable Names with '#uniq?'
Mixins can declare special variables named '#uniq?'.
Each invocation receives a unique symbol, avoiding naming conflicts and allowing multiple calls in the same scope.
*/
#test
{
    var total: s32

    #[Swag.Mixin]
    func toScope()
    {
        var #uniq0: s32 = 1
        total += #uniq0
    }

    toScope()
    toScope()
    toScope()

    @assert(total == 3)
}
