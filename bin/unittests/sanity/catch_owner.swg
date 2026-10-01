#global private

func failBorrowedCapture() fail
{
    fail 7
}

func returnCatchView()->any?
{
    catch failBorrowedCapture() as error
    return error     // swc-expected-error {{sanity_err_borrow_escape}}
}

func returnCopiedCatchView()->any?
{
    catch failBorrowedCapture() as error
    let view = error
    return view     // swc-expected-error {{sanity_err_borrow_escape}}
}

func storeCatchViewInOuterScope()
{
    var view: any?
    {
        catch failBorrowedCapture() as error
        view = error     // swc-expected-error {{sanity_err_borrow_scope_escape}}
    }
}

func returnCatchPointer()->*s32?
{
    catch failBorrowedCapture() as error
    if error != null do
        return cast #try (*s32) error     // swc-expected-error {{sanity_err_borrow_escape}}
    return null
}
