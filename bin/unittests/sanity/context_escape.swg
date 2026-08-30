#global private
// 'Swag.setContext' stores a POINTER to its argument in storage the runtime owns, and that
// storage outlives the statement. A frame-local context is therefore only sound while the
// frame lives, which the scoped idiom below guarantees and a bare install does not.
using Swag

var contextEscapeGlobal: Context

// Installing a frame local and leaving without putting the previous context back: every
// later 'Swag.getContext' reads recycled stack, and the first thing to use the context - the
// error machinery, the allocator - dies far from here.
func contextEscapeLeaksLocal()
{
    var cxt = Swag.getContext()[]     // swc-expected-note {{sema_note_borrow_source_declared_here}}
    cxt.user0 = 1
    Swag.setContext(cxt)     // swc-expected-error {{sanity_err_context_escape}}
}

// A nested scope does not change the answer: nothing puts the previous context back.
func contextEscapeLeaksFromInnerScope(patch: bool)
{
    if patch
    {
        var cxt = Swag.getContext()[]
        cxt.user1 = 2
        Swag.setContext(cxt)     // swc-expected-error {{sanity_err_context_escape}}
    }
}

// A pointer parameter is opaque while the macro is declared. At the expansion site it is
// bound to a caller local, and the compiler must use that newly visible provenance.
#[Swag.Macro]
func contextEscapeMacroInstalls(context: const *Context)
{
    Swag.setContext(context)     // swc-expected-error {{sanity_err_context_escape}}
}

func contextEscapeCallsLeakingMacro()
{
    var cxt = Swag.getContext()[]
    cxt.user0 = 3
    contextEscapeMacroInstalls(&cxt)     // swc-expected-note {{sema_note_expansion_invoked_here}}
}

// ---------------------------------------------------------------------------
// Shapes that must stay silent.
// ---------------------------------------------------------------------------

// The scoped idiom 'Core.withAllocator' is built on: the previous context goes back when
// the scope ends, so the local is installed only while it is alive.
func contextEscapeScoped()
{
    let prev = Swag.getContext()
    defer Swag.setContext(prev)

    var cxt = prev[]
    cxt.user0 = 1
    Swag.setContext(cxt)
}

// The matching expansion is safe when it restores the previous context itself.
#[Swag.Macro]
func contextEscapeMacroScoped(context: const *Context, prev: const *Context)
{
    defer Swag.setContext(prev)
    Swag.setContext(context)
}

func contextEscapeCallsScopedMacro()
{
    let prev = Swag.getContext()
    var cxt  = prev[]
    cxt.user1 = 4
    contextEscapeMacroScoped(&cxt, prev)
}

// A restore in the surrounding macro cannot repair a context leaked by a nested
// function: that function has a distinct frame and lifetime boundary.
#[Swag.Macro]
func(var T) contextEscapeMacroWithNestedLeak(_: T)
{
    let prev = Swag.getContext()
    defer Swag.setContext(prev)

    func leak()
    {
        var cxt = Swag.getContext()[]
        Swag.setContext(cxt)     // swc-expected-error {{sanity_err_context_escape}}
    }
}

// A context the runtime owns roots nowhere in this frame.
func contextEscapeRestoreOnly(prev: const *Context)
{
    Swag.setContext(prev)
}

// A global outlives every frame, which is how a thread installs its own context.
func contextEscapeGlobalContext()
{
    Swag.setContext(&contextEscapeGlobal)
}

struct ContextEscapeHolder
{
    context: #null *Context
}

// A pointer read out of a value is not this frame's storage either.
func contextEscapeFromHolder(holder: *ContextEscapeHolder)
{
    Swag.setContext(holder.context!)
}

#test
{
    if false
    {
        contextEscapeCallsLeakingMacro()
        contextEscapeMacroWithNestedLeak(0)     // swc-expected-note {{sema_note_expansion_invoked_here}}
    }
    contextEscapeCallsScopedMacro()
}
