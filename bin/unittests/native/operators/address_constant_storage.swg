#global private

struct ConstantAddressPair
{
    first:  u32
    second: u32
}

const SharedBytes: [2] u8 = [17, 29]

func sharedAddressA()->const *u8 => &SharedBytes[0]
func sharedAddressB()->const *u8 => &SharedBytes[0]
func sharedAddressC()->const *u8 => &SharedBytes[0]

// Compile this body, but never execute it: constant folding must not read an arbitrary address.
func explicitAddressRemainsRuntime()->u8
{
    const pointer = cast(const *u8) 1234'u64
    return pointer[]
}

// A known aggregate value still has addressable storage. Capturing that address must
// neither discard the enclosing test nor confuse its bytes with the address itself.
#test
{
    Swag.setWorkerCount(4)
    let bytes: [2] u8 = [17, 29]
    let bytesPtr      = &bytes
    let pair          = ConstantAddressPair{31, 47}
    let pairPtr       = &pair
    let secondPtr     = &pair.second
    Swag.assert(secondPtr == &pairPtr.second)
    var sums: [3] u32
    parallel for |bytesPtr, pairPtr, &sums| index in 3 do
        sums[index] = bytesPtr[][0] + bytesPtr[][1] + pairPtr.first + pairPtr.second
    for value in sums do
        Swag.assert(value == 124)

    let number    = 73'u32
    let numberPtr = &number
    #assert(numberPtr[] == 73)
    Swag.assert(numberPtr[] == 73)
    Swag.assert(numberPtr == &number)
    Swag.assert(bytesPtr == &bytes)
    Swag.assert(&bytes[1] == &(bytesPtr[][1]))

    // Persistent storage containing pointers must relocate its pointees in native output too.
    var pointerPtr = &numberPtr
    Swag.assert(pointerPtr[][] == 73)
    Swag.assert(pointerPtr == &numberPtr)
    let text    = "captured constant"
    var textPtr = &text
    Swag.assert(textPtr[] == "captured constant")

    let raw    = cast(*void) 1234'u64
    let rawPtr = &raw
    Swag.assert(cast(u64) rawPtr[] == 1234)
    let enabled    = true
    let enabledPtr = &enabled
    Swag.assert(enabledPtr[])

    // Independently compiled functions must agree on one constant allocation.
    let shared = &SharedBytes[0]
    Swag.assert(sharedAddressA() == shared)
    Swag.assert(sharedAddressB() == shared)
    Swag.assert(sharedAddressC() == shared)
}
