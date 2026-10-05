#global private

#[Swag.Inline]
func rejectedDependency()
{
    discard cast(*void) true     // swc-expected-error {{sema_err_cannot_cast}}
}

struct(T) FwdErrorContainer {}

impl FwdErrorContainer
{
    #[Swag.Inline]
    mtd add(value: #fwd T) { rejectedDependency() }
}

// Once the copy overload fails, later lookups must not diagnose the surviving move
// overload as though it were the only declaration. More callers than workers exercise
// both lookups already in flight and lookups after the failure has been published.
func caller01(type: typeinfo) { var values: FwdErrorContainer'typeinfo; values.add(type) }
func caller02(type: typeinfo) { var values: FwdErrorContainer'typeinfo; values.add(type) }
func caller03(type: typeinfo) { var values: FwdErrorContainer'typeinfo; values.add(type) }
func caller04(type: typeinfo) { var values: FwdErrorContainer'typeinfo; values.add(type) }
func caller05(type: typeinfo) { var values: FwdErrorContainer'typeinfo; values.add(type) }
func caller06(type: typeinfo) { var values: FwdErrorContainer'typeinfo; values.add(type) }
func caller07(type: typeinfo) { var values: FwdErrorContainer'typeinfo; values.add(type) }
func caller08(type: typeinfo) { var values: FwdErrorContainer'typeinfo; values.add(type) }
func caller09(type: typeinfo) { var values: FwdErrorContainer'typeinfo; values.add(type) }
func caller10(type: typeinfo) { var values: FwdErrorContainer'typeinfo; values.add(type) }
func caller11(type: typeinfo) { var values: FwdErrorContainer'typeinfo; values.add(type) }
func caller12(type: typeinfo) { var values: FwdErrorContainer'typeinfo; values.add(type) }
func caller13(type: typeinfo) { var values: FwdErrorContainer'typeinfo; values.add(type) }
func caller14(type: typeinfo) { var values: FwdErrorContainer'typeinfo; values.add(type) }
func caller15(type: typeinfo) { var values: FwdErrorContainer'typeinfo; values.add(type) }
func caller16(type: typeinfo) { var values: FwdErrorContainer'typeinfo; values.add(type) }
func caller17(type: typeinfo) { var values: FwdErrorContainer'typeinfo; values.add(type) }
func caller18(type: typeinfo) { var values: FwdErrorContainer'typeinfo; values.add(type) }
func caller19(type: typeinfo) { var values: FwdErrorContainer'typeinfo; values.add(type) }
func caller20(type: typeinfo) { var values: FwdErrorContainer'typeinfo; values.add(type) }
