// A module type named like a runtime type wins over the runtime one in every declaration of the
// module, a file-private one included: what the module declares shadows what its persisted
// `using Swag` brings in. This file is deliberately not `#global private`, since a private type
// would be found through the file scope and hide the defect.
struct ErrorValue
{
    marker: u32
}

private func markerOf(value: ErrorValue)->u32 => value.marker

#test
{
    Swag.assert(markerOf(ErrorValue{marker: 7}) == 7)
}
