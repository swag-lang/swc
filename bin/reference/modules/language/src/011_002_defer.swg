#global private

/**
# The 'defer' Statement
The 'defer' statement registers an expression that executes automatically
when the current scope is exited. The registration is resolved at compile time,
so there is no runtime bookkeeping: the compiler emits the deferred code on every
exit path. This keeps cleanup and finalization close to the acquisition that needs
them.
*/
#test
{
    var v = 0
    defer Swag.assert(v == 1)     // Ensures v equals 1 on scope exit.
    v += 1                    // Increment v.

// When the scope ends, the deferred expression executes here.
}

/**
# Deferring a Block
A 'defer' can also enclose multiple expressions within a block. This allows
you to group operations that should all run when leaving the scope.
*/
#test
{
    var v = 0
    defer
    {
        v += 10
        Swag.assert(v == 15)
    }

    v += 5

// Upon scope exit, the defer block executes, ensuring v == 15.
}

/**
# 'defer' and Control Flow
The deferred expression executes every time a scope exits, even when leaving
via 'return', 'break', or 'continue'. This guarantees proper cleanup in all
control flow paths.
*/
#test
{
    var G = 0
    for 10
    {
        defer G += 1     // Increment G at end of each iteration, even if broken.

        if G == 2 do
            break     // Exiting early still triggers the defer expression.
    }

    Swag.assert(G == 3)
}

/**
# Deferred Execution Order
When multiple 'defer' statements exist, they execute in reverse declaration
order. The most recent defer runs first when the scope ends.
*/
#test
{
    var x = 1
    defer Swag.assert(x == 2)     // Executes second
    defer x *= 2              // Executes first

// Execution order is reversed for predictable cleanup flow.
}

/**
# Example: Resource Management
'defer' is ideal for resource handling — ensuring that allocation and
release logic stay close together and cleanup always happens.
*/
#test
{
    func createResource() => true

    func releaseResource(resource: *bool)
    {
        resource[] = false
    }

    func isResourceCreated(b: bool) => b

    var resource = false
    for 10
    {
        resource = createResource()
        defer
        {
            Swag.assert(resource.isResourceCreated())
            releaseResource(&resource)
        }

        if Swag.index == 2 do
            break     // Defer ensures cleanup even on early exit.
    }

    Swag.assert(!resource.isResourceCreated())
}

/**
# Example: Error Handling
'defer' ensures reliable cleanup even in functions that may return early due
to errors. This pattern creates robust, error-resilient code.
*/
#test
{
    func createResource() => true

    func releaseResource(resource: *bool)
    {
        resource[] = false
    }

    func isResourceCreated(b: bool) => b

    func performTask()->bool
    {
        var resource = createResource()
        defer releaseResource(&resource)     // Always release resource.

        if !resource.isResourceCreated()
        {
            // Early return still triggers defer.
            return false
        }

        // Perform work...
        return true
    }

    let success = performTask()
    Swag.assert(success)
}
