#global private
/**
# Introduction to Swag Macros
Macros in Swag are declared like functions, but with the '#[Swag.Macro]' attribute.
They are expanded at compile time and can be reused to generate code.
*/

#test
{
    #[Swag.Macro]
    func myMacro() {}
}

/**
# Macro Scope
Macros run in their own scope, isolated from the caller. Unlike mixins, they do not
share the caller's scope. Variables defined inside a macro cannot interfere with
the caller unless explicitly elevated.
*/
#test
{
    #[Swag.Macro]
    func myMacro()
    {
        // 'a' here is local to the macro
        var a = 666
    }

    let a = 0
    myMacro() // no conflict with outer 'a'
    @assert(a == 0)
}

/**
# Resolving Identifiers Outside the Macro Scope
Use '#up' to explicitly reference and modify variables from the caller's scope.
*/

#test
{
    #[Swag.Macro]
    func myMacro()
    {
        #up a += 1 // increments the caller's 'a'
    }
    var a = 0
    myMacro()
    myMacro()
    @assert(a == 2)
}

/**
# Macros with '#code' Parameters
A '#code' parameter declares like a function, with 'func' replaced by '#code':
- '#code' alone is a statement block.
- '#code->T' is an expression block of type T.
- '#code(a, b: T)' declares named block parameters (types are optional).

'#inject' inserts the caller-provided code at the injection point.
*/
#test
{
    #[Swag.Macro]
    func myMacro(what: #code)
    {
        #inject(what) // insert provided code
    }

    var a = 0

    // Use '#code' to pass a block as code (not evaluated at call site)
    myMacro(#code { #up a += 1; })

    // If the last parameter is a '#code' statement block, the following statement
    // becomes the last argument
    myMacro()
    {
        #up a += 1
    }

    @assert(a == 2)
}

/**
# Expression '#code' Parameters
Use '#code->T' for a code expression that returns a specific type. The expression
is evaluated at each '#inject', not at the call site. '#code => expr' is the
explicit expression literal, mirroring the short function form 'func() => expr'.
*/
#test
{
    #[Swag.Macro]
    func myMacro(what: #code->bool)
    {
        @assert(#inject(what))
    }

    // A plain expression argument converts to code implicitly
    myMacro(1 == 1)
    myMacro(3 > 2 and 2 < 4)
    myMacro(true)

    // The explicit literal form
    myMacro(#code => true)
}

/**
# Forcing Code into the Caller's Scope with '#macro'
Use '#macro' to run macro code as if it were in the caller's scope,
avoiding the need for '#up' inside the injected block.
*/
#test
{
    #[Swag.Macro]
    func myMacro(what: #code)
    {
        var a = 666 // macro-local 'a'

        #macro
        {
            // references the caller's scope
            #inject(#up what)
        }
    }

    var a = 1
    myMacro()
    {
        a += 2 // operates on caller's 'a' due to '#macro'
    }

    @assert(a == 3)
}

/**
# Declared Block Parameters
The '#code(...)' parameter names are the macro's contract: '#inject' binds them
by name, and the injected code sees the resulting values under those names.
Binding initializers evaluate in the macro's own scope, so no '#up' or '#macro'
wrapping is needed.
*/
#test
{
    #[Swag.Macro]
    func call(v: s32, stmt: #code(value: s32, double: s32))
    {
        #inject(stmt, value = v, double = v * 2)
    }

    // The declared names are visible at the call site by default.
    call(20)
    {
        @assert(value == 20)
        @assert(double == 40)
    }
}

/**
# Renaming Block Parameters at the Call Site
The caller can rename the block parameters positionally with a '#code(...)'
literal placed before the block. The same literal works inline, as a regular
argument.
*/
#test
{
    #[Swag.Macro]
    func call(v: s32, stmt: #code(value: s32, double: s32))
    {
        #inject(stmt, value = v, double = v * 2)
    }

    var total = 0

    // Trailing form: the binder renames 'value' to 'x' and 'double' to 'y'.
    call(20) #code(x, y) { total = x + y }
    @assert(total == 60)

    // Inline form: the code literal is a normal argument.
    call(10, #code(a, b) { total = a + b })
    @assert(total == 30)

    // Partial binder: only the first parameter is renamed, like 'foreach'.
    call(5) #code(first) { total = first + double }
    @assert(total == 15)
}

/**
# Mutable Block Parameters
A 'var' parameter gives the injected code a mutable binding. A typed parameter
also types (and checks) the binding, which is required for references.
*/
#test
{
    #[Swag.Macro]
    func withCounter(start: s32, stmt: #code(var counter: s32))
    {
        #inject(stmt, counter = start)
    }

    var got = 0
    withCounter(10)
    {
        counter += 5
        got = counter
    }

    @assert(got == 15)
}

/**
# Performance Considerations with Macros
Macros extend the language without function-pointer/lambda overhead.
They can be used to generate tight loops with caller-visible indices, etc.
*/
#test
{
    #[Swag.Macro]
    func repeat(count: s32, what: #code(index: s32))
    {
        var a = 0
        while a < count
        {
            #inject(what, index = a)
            a += 1
        }
    }

    var a = 0
    repeat(5)
    {
        a += index // sum 0..4
    }
    @assert(a == 0 + 1 + 2 + 3 + 4)

    repeat(3)
    {
        a += index // add 0..2
    }
    @assert(a == 10 + 3)
}

/**
# Handling 'break' and 'continue' in User Code with Macros
You can remap 'break'/'continue' in injected user code to control which loop they target.
Bindings and control-flow replacements live in the same '#inject'.
*/
#test
{
    #[Swag.Macro]
    func repeatSquare(count: u32, what: #code)
    {
        // Define a scope label used as the break target
        #scope(ScopeTarget)

        for count
        {
            for count
            {
                // Remap 'break' in user code to 'break to ScopeTarget' (outer loop exit)
                #inject(what, break = break to ScopeTarget)
            }
        }
    }

    var a = 0

    repeatSquare(5)
    {
        a += 1
        if a == 10 do
            break // remapped to 'break to ScopeTarget'
    }

    @assert(a == 10)
}

/**
## Another example:
Remap both 'break' and 'continue' to influence outer/inner loop flow.
*/
#test
{
    #[Swag.Macro]
    func repeatSquare(count: u32, what: #code)
    {
        // Label for controlling the outer loop
        #scope(Outer)

        for count
        {
            for count
            {
                // 'break' -> exit outer loop; 'continue' -> skip inner iteration
                #inject(what, break = break to Outer, continue = break)
            }
        }
    }

    var a = 0
    var b = 0

    repeatSquare(5)
    {
        a += 1

        // If 'a' divisible by 3, skip to next inner iteration (acts like 'continue')
        if a % 3 == 0 do
            continue

        b += 1

        // Exit both loops when 'a' reaches 8
        if a == 8 do
            break
    }

    @assert(a == 8)
    @assert(b == 6)
}
