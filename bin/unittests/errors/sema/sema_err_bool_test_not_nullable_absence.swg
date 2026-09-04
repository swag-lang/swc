#global private

// A 'typeinfo', a function value, an interface and a 'cstring' answer a condition by testing
// themselves against null. A type that cannot hold null makes that test a constant, and none of
// these families offers another question to ask, so the only repair is '?'.

interface IBoolTestAbsence
{
    mtd get()->s32
}

func boolTestAbsenceNullableTypeInfo(type: typeinfo?)->bool
{
    if type do
        return true
    return false
}

func boolTestAbsenceNullableFunc(fn: (func()->s32)?)->s32
{
    if fn do
        return fn!()
    return 0
}

func boolTestAbsenceNullableItf(itf: IBoolTestAbsence?)->s32
{
    if itf do
        return itf!.get()
    return 0
}

func boolTestAbsenceNullableCString(text: cstring?)->bool
{
    while text
    {
        return true
    }

    return false
}

// -----------------------------------------------------------------------------
// Rejected patterns.
// -----------------------------------------------------------------------------

func boolTestAbsenceErrTypeInfo(type: typeinfo)->bool
{
    if type do     // swc-expected-error {{sema_err_bool_test_not_nullable_absence}}
        return true
    return false
}

func boolTestAbsenceErrFunc(fn: func()->s32)->s32
{
    if fn do     // swc-expected-error {{sema_err_bool_test_not_nullable_absence}}
        return fn()
    return 0
}

func boolTestAbsenceErrItf(itf: IBoolTestAbsence)->s32
{
    if itf do     // swc-expected-error {{sema_err_bool_test_not_nullable_absence}}
        return itf.get()
    return 0
}

func boolTestAbsenceErrCString(text: cstring)->bool
{
    if !text do     // swc-expected-error {{sema_err_bool_test_not_nullable_absence}}
        return false
    return true
}

func boolTestAbsenceErrTernary(type: typeinfo)->s32
{
    return type ? 1 : 0     // swc-expected-error {{sema_err_bool_test_not_nullable_absence}}
}

func boolTestAbsenceErrExplicitCast(itf: IBoolTestAbsence)->bool
{
    return cast(bool) itf     // swc-expected-error {{sema_err_bool_test_not_nullable_absence}}
}
