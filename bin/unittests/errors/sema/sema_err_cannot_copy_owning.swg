#global private

// A struct that declares 'opDrop' owns what that method releases, so it states no copy:
// two values would release the same resource. No attribute is needed for that, and
// declaring 'opPostCopy' beside it opts the copy back in.

struct Owner
{
    handle: s32
}

impl Owner
{
    mtd opDrop() {}
}

struct Holder
{
    owner: Owner
}

struct Duplicable
{
    handle: s32
}

impl Duplicable
{
    mtd opDrop() {}
    mtd opPostCopy() {}
    mtd opPostMove() {}
}

#test
{
    var a: Owner
    var b = a     // swc-expected-error {{sema_err_cannot_copy_owning}}
}

#test
{
    var a: Owner
    var b: Owner
    b = a     // swc-expected-error {{sema_err_cannot_copy_owning}}
}

// A struct owning through a member states no copy either, and the diagnostic names the member.
#test
{
    var a: Holder
    var b = a     // swc-expected-error {{sema_err_cannot_copy_owning}}
}

// Copying an lvalue into a struct literal field is a copy.
#test
{
    var a: Owner
    var w = Holder{a}     // swc-expected-error {{sema_err_cannot_copy_owning}}
}

// Copying an lvalue into an array literal element is a copy.
#test
{
    var a   = Owner{1}
    var arr = [a, a]     // swc-expected-error {{sema_err_cannot_copy_owning}}
}

// Reading through a '#move' parameter without forwarding it is a copy.
var g_target: Owner

#test
{
    func sink(v: #move Owner)
    {
        g_target = v     // swc-expected-error {{sema_err_cannot_copy_owning}}
    }

    var h = Owner{1}
    sink(#move h)
}

// '#move' transfers instead of copying, and 'opPostCopy' makes the type copyable again.
#test
{
    var a = Owner{1}
    var b = #move a
    Swag.assert(b.handle == 1)

    var c = Duplicable{2}
    var d = c
    Swag.assert(d.handle == 2)
}
