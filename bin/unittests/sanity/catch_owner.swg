#global private

func failBorrowedCapture() fail
{
    fail 7
}

func returnCatchView()->any?
{
    var errorOutcome: Swag.Error
    catch failBorrowedCapture() as &errorOutcome
    let error = errorOutcome.value()
    return error     // swc-expected-error {{sanity_err_borrow_escape}}
}

func returnCopiedCatchView()->any?
{
    var errorOutcome: Swag.Error
    catch failBorrowedCapture() as &errorOutcome
    let error = errorOutcome.value()
    let view  = error
    return view     // swc-expected-error {{sanity_err_borrow_escape}}
}

func storeCatchViewInOuterScope()
{
    var view: any?
    scope
    {
        var errorOutcome: Swag.Error
        catch failBorrowedCapture() as &errorOutcome
        let error = errorOutcome.value()
        view = error     // swc-expected-error {{sanity_err_borrow_scope_escape}}
    }
}

func returnCatchPointer()->*s32?
{
    catch failBorrowedCapture() as error else
    {
        return (catch cast(*s32?, error) else null)     // swc-expected-error {{sanity_err_borrow_escape}}
    }
    return null
}

#[Swag.NoInline]
func storeCatchView(destination: *(any?), value: any?)
{
    destination[] = value
}

func storeCatchViewThroughParameter(destination: *(any?))
{
    var errorOutcome: Swag.Error
    catch failBorrowedCapture() as &errorOutcome
    let error = errorOutcome.value()
    storeCatchView(destination, error)     // swc-expected-error {{sanity_err_borrow_escape}}
}

// Forwarding two caller borrows remains valid; their relative lifetimes are checked
// where the actual destination and source are known.
#[Swag.NoInline]
func forwardCatchView(destination: *(any?), value: any?)
{
    storeCatchView(destination, value)
}

func storeCatchViewInSameScope()
{
    var destination:  any?
    var errorOutcome: Swag.Error
    catch failBorrowedCapture() as &errorOutcome
    let error = errorOutcome.value()
    forwardCatchView(&destination, error)
    Swag.assert(destination != null)
}

func storeCatchViewThroughForwarder(destination: *(any?))
{
    var errorOutcome: Swag.Error
    catch failBorrowedCapture() as &errorOutcome
    let error = errorOutcome.value()
    forwardCatchView(destination, error)     // swc-expected-error {{sanity_err_borrow_escape}}
}

struct CapturedText
{
    bytes: [4] u8     = [65, 66, 67, 68]
    text:  string?
    texts: [1] string = [""]
}

impl CapturedText
{
    mtd opPostCopy()
    {
        .text     = Swag.makeString(&.bytes[0], 4)
        .texts[0] = .text
    }
}

func failBorrowedText() fail
{
    fail CapturedText{}
}

func returnCatchTextField()->string?
{
    catch failBorrowedText() as error else
    {
        let payload = assume cast(const *CapturedText, error)
        return payload.text     // swc-expected-error {{sanity_err_borrow_escape}}
    }
    return null
}

func returnCatchTextElement()->string?
{
    catch failBorrowedText() as error else
    {
        let payload = assume cast(const *CapturedText, error)
        return payload.texts[0]     // swc-expected-error {{sanity_err_borrow_escape}}
    }
    return null
}

#[Swag.NoInline]
func catchTextField(error: any)->string?
{
    let payload = assume cast(const *CapturedText, error)
    return payload.text
}

func returnCatchTextThroughAccessor()->string?
{
    catch failBorrowedText() as error else
    {
        return catchTextField(error)     // swc-expected-error {{sanity_err_borrow_escape}}
    }
    return null
}

// Reading scalar values and consuming views while the capture is alive are valid.
func readCatchTextInScope()->u8
{
    catch failBorrowedText() as error else
    {
        let payload = assume cast(const *CapturedText, error)
        let text    = payload.text
        Swag.assert(text != null)
        return payload.bytes[0]
    }
    return 0
}

struct IndependentText
{
    text: string
}

// A known container's carrier field has its own pointee lifetime. Reading it must
// not inherit the lifetime of the local slot that happens to hold the carrier.
func returnIndependentText()->string
{
    var value   = IndependentText{"permanent"}
    let pointer = &value
    return pointer.text
}

// Standard message accessors project any.buffer before reading their payload's text.
#[Swag.NoInline]
func catchTextBuffer(error: any)->string?
{
    let payload = cast(const *CapturedText, error.buffer)
    return payload.text
}

func returnCatchTextThroughBuffer()->string?
{
    catch failBorrowedText() as error else
    {
        return catchTextBuffer(error)     // swc-expected-error {{sanity_err_borrow_escape}}
    }
    return null
}

func readCatchTextBufferInScope()
{
    catch failBorrowedText() as error else { Swag.assert(catchTextBuffer(error) == "ABCD") }
}

// Choosing a shorter ordinary origin at a branch join must not hide the alternative
// whose carrier member still depends on the captured payload.
func returnJoinedCatchText(ordinaryBranch: bool)->string?
{
    catch failBorrowedText() as error else
    {
        var ordinary = CapturedText{}
        ordinary.text = "permanent"
        var selected = assume cast(const *CapturedText, error)
        if ordinaryBranch do
            selected = &ordinary
        return selected.text     // swc-expected-error {{sanity_err_borrow_escape}}
    }
    return null
}

func returnIndependentJoinedText(secondBranch: bool)->string
{
    var first    = IndependentText{"first permanent text"}
    var second   = IndependentText{"second permanent text"}
    var selected = &first
    if secondBranch do
        selected = &second
    return selected.text
}
