#global private

struct IndirectReleaseRecord
{
    value: s32
}

struct IndirectReleaseSlot
{
    record: *IndirectReleaseRecord?
}

struct IndirectReleaseContext
{
    slots:  [2] IndirectReleaseSlot
    marker: s32
}

#[Swag.NoInline, Swag.Sanity(.Lifecycle, true)]
func indirectReleaseRecord(record: *IndirectReleaseRecord)
{
    var request: Swag.AllocatorRequest
    request.address = record
    request.size    = #sizeof(IndirectReleaseRecord)
    Swag.getContext().allocator!.free(&request)
}

#[Swag.NoInline, Swag.Sanity(.Lifecycle, true)]
func indirectReleaseClear(context: *IndirectReleaseContext)
{
    for &slot in context.slots
    {
        let record = slot.record
        slot.record = null
        if record do
            indirectReleaseRecord(record)
    }
    context.marker = 37
}

#[Swag.NoInline, Swag.Sanity(.Lifecycle, true)]
func indirectReleaseClearAndRead(context: *IndirectReleaseContext)->s32
{
    indirectReleaseClear(context)
    return context.marker
}

// Releasing an array element's pointer field does not release its parent object.
#[Swag.Sanity(.Lifecycle, true)]
#test
{
    var request: Swag.AllocatorRequest
    request.size = #sizeof(IndirectReleaseRecord)
    Swag.getContext().allocator!.alloc(&request)

    var context: IndirectReleaseContext
    context.slots[0].record = cast(*IndirectReleaseRecord, request.address!)
    let marker = indirectReleaseClearAndRead(&context)
    Swag.assert(marker == 37)
    Swag.assert(context.slots[0].record == null)
}

var indirectReleaseSavedLocation: Swag.SourceCodeLocation
var indirectReleaseSavedRequest:  *Swag.AllocatorRequest?

#[Swag.NoInline]
func indirectReleaseKeepLocation(location: Swag.SourceCodeLocation)
{
    indirectReleaseSavedLocation = location
}

#[Swag.NoInline]
func indirectReleaseReadLocation(request: *Swag.AllocatorRequest)
{
    indirectReleaseKeepLocation(request.callerLoc)
}

#[Swag.NoInline]
func indirectReleaseCopyRequest(request: *Swag.AllocatorRequest)
{
    var copy = request[]
    indirectReleaseReadLocation(&copy)
}

// The copied location contains static strings; the intermediate request slot dies.
#test
{
    var request: Swag.AllocatorRequest
    request.callerLoc = #curlocation
    indirectReleaseCopyRequest(&request)
    Swag.assert(indirectReleaseSavedLocation.fileName == request.callerLoc.fileName)
    Swag.assert(indirectReleaseSavedLocation.lineStart == request.callerLoc.lineStart)
}

#[Swag.NoInline]
func indirectReleaseKeepRequest(request: *Swag.AllocatorRequest)
{
    indirectReleaseSavedRequest = request
}

// The address of the copied request is still frame storage, unlike its contents.
func indirectReleaseRejectCopiedSlot(request: *Swag.AllocatorRequest)
{
    var copy = request[]
    indirectReleaseKeepRequest(&copy)     // swc-expected-error {{sanity_err_borrow_escape}}
}

struct IndirectReleaseDetails
{
    pointer: *s32?
}

struct IndirectReleaseParent
{
    details: IndirectReleaseDetails
}

var indirectReleaseSavedDetails: IndirectReleaseDetails

#[Swag.NoInline]
func indirectReleaseKeepDetails(details: IndirectReleaseDetails)
{
    indirectReleaseSavedDetails = details
}

#[Swag.NoInline]
func indirectReleaseReadDetails(parent: *IndirectReleaseParent)
{
    indirectReleaseKeepDetails(parent.details)
}

// Copying a sub-struct must still retain the lifetime of pointers inside it.
func indirectReleaseRejectDetails()
{
    var local = 7
    var parent: IndirectReleaseParent
    parent.details.pointer = &local
    indirectReleaseReadDetails(&parent)     // swc-expected-error {{sanity_err_borrow_escape}}
}

// Exact field provenance still identifies a forbidden release after a value copy.
#[Swag.Sanity(.Lifecycle, true)]
func indirectReleaseRejectCopiedAddress()
{
    var local:   s32
    var request: Swag.AllocatorRequest
    request.address = &local
    request.size    = #sizeof(s32)
    var copy = request
    Swag.getContext().allocator!.free(&copy)     // swc-expected-error {{sanity_err_free_borrowed}}
}
