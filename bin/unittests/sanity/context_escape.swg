#global private
// '@setcontext' stores a POINTER to its argument in storage the runtime owns, and that
// storage outlives the statement. A frame-local context is therefore only sound while the
// frame lives, which the scoped idiom below guarantees and a bare install does not.
using Swag

var contextEscapeGlobal: Context

// Installing a frame local and leaving without putting the previous context back: every
// later '@getcontext' reads recycled stack, and the first thing to use the context - the
// error machinery, the allocator - dies far from here.
func contextEscapeLeaksLocal()
{
    var cxt = @getcontext()[]
    cxt.user0 = 1
    @setcontext(cxt)     // swc-expected-error {{sanity_err_context_escape}}
}

// A nested scope does not change the answer: nothing puts the previous context back.
func contextEscapeLeaksFromInnerScope(patch: bool)
{
    if patch
    {
        var cxt = @getcontext()[]
        cxt.user1 = 2
        @setcontext(cxt)     // swc-expected-error {{sanity_err_context_escape}}
    }
}

// ---------------------------------------------------------------------------
// Shapes that must stay silent.
// ---------------------------------------------------------------------------

// The scoped idiom 'Core.withAllocator' is built on: the previous context goes back when
// the scope ends, so the local is installed only while it is alive.
func contextEscapeScoped()
{
    let prev = @getcontext()
    defer @setcontext(prev)

    var cxt = prev[]
    cxt.user0 = 1
    @setcontext(cxt)
}

// A context the runtime owns roots nowhere in this frame.
func contextEscapeRestoreOnly(prev: const *Context)
{
    @setcontext(prev)
}

// A global outlives every frame, which is how a thread installs its own context.
func contextEscapeGlobalContext()
{
    @setcontext(&contextEscapeGlobal)
}

struct ContextEscapeHolder
{
    context: #null *Context
}

// A pointer read out of a value is not this frame's storage either.
func contextEscapeFromHolder(holder: *ContextEscapeHolder)
{
    @setcontext(holder.context!)
}
