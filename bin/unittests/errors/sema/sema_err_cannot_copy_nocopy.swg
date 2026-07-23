#global private

// A struct marked with '#[Swag.NoCopy]' cannot be copied: assignments and
// initializations from an lvalue must transfer ownership with '#move'.
#[Swag.NoCopy]
struct Handle { x: s32 }
impl Handle
{
    mtd opDrop() {}
    mtd opPostMove() {}
}

struct Wrap { h: Handle }

#test
{
    var a = Handle{1}
    var b = a     // swc-expected-error {{sema_err_cannot_copy_nocopy}}
}

#test
{
    var a = Handle{1}
    var b: Handle
    b = a     // swc-expected-error {{sema_err_cannot_copy_nocopy}}
}

var g_target: Handle

#test
{
    // Reading through a '#move' parameter without forwarding it is a copy.
    func sink(v: #move Handle)
    {
        g_target = v     // swc-expected-error {{sema_err_cannot_copy_nocopy}}
    }
    var h = Handle{1}
    sink(#move h)
}

#test
{
    // Copying an lvalue into a struct literal field is a copy.
    var h = Handle{1}
    var w = Wrap{h}     // swc-expected-error {{sema_err_cannot_copy_nocopy}}
}

#test
{
    // Copying an lvalue into an array literal element is a copy.
    var h = Handle{1}
    var arr = [h, h]     // swc-expected-error {{sema_err_cannot_copy_nocopy}}
}

// A struct containing a non-copyable field is non-copyable too.
#test
{
    var a: Wrap
    var b = a     // swc-expected-error {{sema_err_cannot_copy_nocopy}}
}
