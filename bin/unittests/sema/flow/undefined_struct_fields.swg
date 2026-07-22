#global private

// Struct fields whose DEFAULT is '= undefined' expose the same garbage-read risk
// as '= undefined' locals: an uninitialized declaration of such a struct is
// tracked by the definite-assignment analysis, starting from the defaulted
// fields. Literal initializations ('X{}') are not tracked: the runtime poison
// remains the net there.

struct UndPartDefault
{
    ready: bool = true
    count: s32  = undefined
    total: s32  = undefined
}

struct UndAllDefault
{
    x: s32 = undefined
    y: s32 = undefined
}

func undFillPart(p: *UndPartDefault)
{
    p.count = 1
    p.total = 2
}

// -----------------------------------------------------------------------------
// Accepted patterns.
// -----------------------------------------------------------------------------

// Reading a defaulted field is fine.
func undOkDefaultedField()->bool
{
    var p: UndPartDefault
    return p.ready
}

// Assign-then-read of an undefined-default field.
func undOkAssignedField()->s32
{
    var p: UndPartDefault
    p.count = 3
    return p.count
}

// Out-parameter fill counts as initialization.
func undOkOutParam()->s32
{
    var p: UndPartDefault
    undFillPart(&p)
    return p.count + p.total
}

// Whole copy of a plain-POD struct with at least its defaulted fields is the
// usual partial-copy tolerance.
func undTakePart(p: UndPartDefault)->bool => p.ready

func undOkWholeCopy()->bool
{
    var p: UndPartDefault
    return undTakePart(p)
}

// -----------------------------------------------------------------------------
// Rejected patterns.
// -----------------------------------------------------------------------------

// Reading a field left undefined by the struct's default.
func undErrPartField()->s32
{
    var p: UndPartDefault
    return p.count // swc-expected-error {{sema_err_undefined_field_use}}
}

// Same with a struct whose fields are ALL undefined by default.
func undErrAllField()->s32
{
    var v: UndAllDefault
    return v.x // swc-expected-error {{sema_err_undefined_field_use}}
}

// Initialized on one path only.
func undErrHalfInit(c: bool)->s32
{
    var p: UndPartDefault
    if c do
        p.count = 1
    return p.count // swc-expected-error {{sema_err_undefined_field_use}}
}
