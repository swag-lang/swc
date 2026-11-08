#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

#[Swag.NoInline]
func release(ptr: *void, size: u64)
{
    var req: AllocatorRequest
    req.address = ptr
    req.size = size
    Swag.getContext().allocator!.free(&req)
}

func rejectImportedBorrowedField()
{
    var value: s32
    let carrier = BorrowFieldProvider.createWrapped(&value)
    release(carrier.borrowed, #sizeof(s32))     // swc-expected-error {{sanity_err_free_borrowed}}
    release(carrier, #sizeof(BorrowFieldProvider.Carrier))
}

#test
{
    var value: s32 = 73
    let carrier = BorrowFieldProvider.createWrapped(&value)
    release(carrier.owned, #sizeof(s32))
    release(carrier, #sizeof(BorrowFieldProvider.Carrier))
    Swag.require(value == 73)
}
