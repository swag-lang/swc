#global private

interface IDynamicBorrowField {}
struct DynamicBorrowField { value: s32 }
impl IDynamicBorrowField for DynamicBorrowField {}

func returnDynamicInterfaceLocalField()->*s32?
{
    var local: DynamicBorrowField
    let view:  IDynamicBorrowField = &local
    if view is DynamicBorrowField as value do
        return &value.value     // swc-expected-error {{sanity_err_borrow_escape}}
    return null
}

#[Swag.DynCast]
struct DynamicBorrowBase { value: s32 }
struct DynamicBorrowChild { using base: DynamicBorrowBase }

func returnDynamicLocal()->*DynamicBorrowChild?
{
    var value: DynamicBorrowChild
    return cast #try (*DynamicBorrowChild) value     // swc-expected-error {{sanity_err_borrow_escape}}
}

func returnDeducedDynamicLocal()->*DynamicBorrowChild?
{
    var value: DynamicBorrowChild
    return cast #try () value     // swc-expected-error {{sanity_err_borrow_escape}}
}

func returnAssumedDynamicLocal()->*DynamicBorrowChild
{
    var value: DynamicBorrowChild
    return cast #assume (*DynamicBorrowChild) &value     // swc-expected-error {{sanity_err_borrow_escape}}
}

func returnDynamicBox(number: s32)->*s32?
{
    var value: any = number
    return cast #try (*s32) value     // swc-expected-error {{sanity_err_borrow_escape}}
}

func returnDynamicParameter(value: *DynamicBorrowBase)->*DynamicBorrowChild?
{
    return cast #try (*DynamicBorrowChild) value
}

func returnRuntimeTargetView(target: typeinfo, source: any)->any?
{
    // The erased result may borrow an interface representation in this function's storage.
    // swc-expected-error@(+1) {{sanity_err_borrow_escape}}
    return cast #try(target) source
}
