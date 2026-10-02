#global if #command == Swag.CompilerCommand.Test
#global private

using StaticApi

func fillImportedIndirectValue(destination: *DepBorrowIndirectValue)
{
    var source = DepBorrowIndirectValue{depBorrowIndirectGlobal()}
    depBorrowIndirectCopy(destination, &source)
}

func returnImportedIndirectValue()->DepBorrowIndirectValue
{
    var source = DepBorrowIndirectValue{depBorrowIndirectGlobal()}
    return depBorrowIndirectRead(&source)
}

// Copying a scalar does not retain the local source slot.
#test
{
    var destination = 0
    {
        var source = 42
        depBorrowIndirectCopyScalar(&destination, &source)
    }
    Swag.assert(destination == 42)
}

// A copied pointer field keeps its own lifetime, independent of the local carrier.
#test
{
    var destination: DepBorrowIndirectValue
    fillImportedIndirectValue(&destination)
    Swag.assert(destination.item![] == 37)
    let returned = returnImportedIndirectValue()
    Swag.assert(returned.item![] == 37)
}

#test
{
    {
        var source = DepBorrowIndirectValue{depBorrowIndirectGlobal()}
        depBorrowIndirectStore(&source)
    }
    Swag.assert(depBorrowIndirectStoredValue() == 37)
}

func rejectImportedIndirectCopy(destination: *DepBorrowIndirectValue)
{
    var local  = 7
    var source = DepBorrowIndirectValue{&local}
    depBorrowIndirectCopy(destination, &source)     // swc-expected-error {{sanity_err_borrow_escape}}
}

func rejectImportedIndirectReturn()->DepBorrowIndirectValue
{
    var local  = 7
    var source = DepBorrowIndirectValue{&local}
    return depBorrowIndirectRead(&source)     // swc-expected-error {{sanity_err_borrow_escape}}
}

func rejectImportedIndirectStore()
{
    var local  = 7
    var source = DepBorrowIndirectValue{&local}
    depBorrowIndirectStore(&source)     // swc-expected-error {{sanity_err_borrow_escape}}
}

func rejectImportedDirectAddress()
{
    var source = DepBorrowIndirectValue{depBorrowIndirectGlobal()}
    depBorrowIndirectKeepAddress(&source)     // swc-expected-error {{sanity_err_borrow_escape}}
}

func rejectImportedLegacyDirectMask(destination: *DepBorrowIndirectValue)
{
    var source = DepBorrowIndirectValue{depBorrowIndirectGlobal()}
    depBorrowIndirectLegacyCopy(destination, &source)     // swc-expected-error {{sanity_err_borrow_escape}}
}
