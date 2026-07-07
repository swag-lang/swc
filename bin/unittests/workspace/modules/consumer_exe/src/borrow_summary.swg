// Imported borrow summaries ('Swag.BorrowSummary' in the generated API): caller-owned
// data flows through summarized callees without a diagnostic; the error cases (local
// data through the same callees) are covered in bin/unittests/sanity/borrow_escape.swg
// for the intra-module half, and rely on the same judgement path here.
var gConsumerBorrowInt: s32 = 3

func verifyImportedBorrowSummaries()
{
    let p = depBorrowPassthrough(&gConsumerBorrowInt)
    @assert(p == &gConsumerBorrowInt)

    let q = depBorrowWrap(&gConsumerBorrowInt)
    @assert(q == &gConsumerBorrowInt)

    depBorrowStash(&gConsumerBorrowInt)
    @assert(depBorrowStashed() == &gConsumerBorrowInt)

    var local: s32 = 5
    @assert(depBorrowRead(&local) == 5)

    // Imported pair summary: caller-owned data into a global container is fine.
    gConsumerContainer.add(&gConsumerBorrowInt)
    @assert(gConsumerContainer.slot == &gConsumerBorrowInt)
}

var gConsumerContainer: DepBorrowContainer

