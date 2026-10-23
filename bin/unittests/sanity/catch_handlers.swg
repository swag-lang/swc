#global private

func scopedHandlerFailure()->any? fail
{
    fail 7
}

func escapeHandlerFallback()->any?
{
    return catch scopedHandlerFailure() as error else error     // swc-expected-error {{sanity_err_borrow_escape}}
}

func escapeExplicitOwner()->any?
{
    var owner: Swag.Error
    discard catch scopedHandlerFailure() as &owner
    return owner.value()     // swc-expected-error {{sanity_err_borrow_escape}}
}

func overwriteExplicitOwner()
{
    var owner: Swag.Error
    discard catch scopedHandlerFailure() as &owner
    let view = owner.value()
    discard catch scopedHandlerFailure() as &owner     // swc-expected-error {{sanity_err_borrow_invalidated}}
    Swag.assert(view != null)
}

func readReplacedOwnerInFallback()
{
    var owner: Swag.Error
    discard catch scopedHandlerFailure() as &owner
    let view   = owner.value()
    let result = catch scopedHandlerFailure() as &owner else view     // swc-expected-error {{sanity_err_borrow_invalidated}}
    discard result
}

func readOwnerBeforeReplacement()
{
    var owner: Swag.Error
    discard catch scopedHandlerFailure() as &owner
    let view = owner.value()
    catch
    {
        Swag.assert(view != null)
        fail 7
    } as &owner
}

// A view of the owner itself stays valid when only its retained payload changes.
func keepOwnerObjectView()
{
    var owner: Swag.Error
    let object = Swag.makeAny(&owner, #typeof(owner))
    discard catch scopedHandlerFailure() as &owner
    Swag.assert(object is Swag.Error)
}
