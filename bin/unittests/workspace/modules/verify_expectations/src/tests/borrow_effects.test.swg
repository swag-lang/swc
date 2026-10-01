#global if #command == Swag.CompilerCommand.Test
#global private

using StaticApi

// An imported scalar reader has no ambient observation, even though its masks are all zero.
#[Swag.NoInline]
func clearAfterImportedReader(holder: *DepBorrowContainer, value: *s32)
{
    var counter = 0
    holder.slot = value
    discard depBorrowSummaryRead(&counter)
    holder.slot = null
}

func callImportedReaderWithLocal(holder: *DepBorrowContainer)
{
    var value = 7
    clearAfterImportedReader(holder, &value)
}

#test
{
    var holder: DepBorrowContainer
    callImportedReaderWithLocal(&holder)
    Swag.assert(holder.slot == null)
}

// The body stores this argument even though its source annotation claims no retention.
func importedAnnotatedStore()
{
    var value = 7
    depBorrowAnnotatedStash(&value)     // swc-expected-error {{sanity_err_borrow_escape}}
}

#[Swag.NoInline]
func clearAfterImportedObserver(holder: *DepBorrowContainer, value: *s32)
{
    holder.slot = value
    depBorrowAnnotatedObserve()
    holder.slot = null
}

// The exported contract must retain the computed ambient effect over an explicit false.
func importedAnnotatedObserver(holder: *DepBorrowContainer)
{
    depBorrowSetObservedOwner(holder)
    var value = 7
    clearAfterImportedObserver(holder, &value)     // swc-expected-error {{sanity_err_borrow_escape}}
}

#[Swag.NoInline]
func clearAfterLegacyObserver(holder: *DepBorrowContainer, value: *s32)
{
    holder.slot = value
    depBorrowLegacyObserver()
    holder.slot = null
}

func importedLegacyObserver(holder: *DepBorrowContainer)
{
    var value = 7
    clearAfterLegacyObserver(holder, &value)     // swc-expected-error {{sanity_err_borrow_escape}}
}
