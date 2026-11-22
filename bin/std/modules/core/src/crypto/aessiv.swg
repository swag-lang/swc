#global public
#global namespace Crypto
#global #[Swag.Safety(.Overflow, false)]

// AES-SIV synthetic IV and authentication tag size in bytes.
public const AesSivTagSize = 16

private func aesSivDouble(value: *[AesSivTagSize] u8)
{
    var carry = 0'u8
    for index in AesSivTagSize
    {
        let byteIndex = AesSivTagSize - 1 - index
        let next      = value[][byteIndex] >> 7
        value[][byteIndex] = cast(u8, (value[][byteIndex] << 1) | carry)
        carry = next
    }

    value[][AesSivTagSize - 1] ^= 0x87'u8 & cast(u8, 0'u8 - carry)
}

private func aesSivComputeTag(macKey: const [..] u8, hasAssociatedData: bool, associatedData, plaintext: const [..] u8)->[AesSivTagSize] u8 fail
{
    var zero: [AesSivTagSize] u8
    var value = try AesCmac.compute(macKey, zero)
    defer Crypto.secureClear(value)
    if hasAssociatedData
    {
        aesSivDouble(&value)
        var associatedTag = try AesCmac.compute(macKey, associatedData)
        defer Crypto.secureClear(associatedTag)
        for index in AesSivTagSize do
            value[index] ^= associatedTag[index]
    }

    if plaintext.count >= AesSivTagSize
    {
        var cmac         = try AesCmac.create(macKey)
        let prefixLength = plaintext.count - AesSivTagSize
        if prefixLength do
            try cmac.update(plaintext[until prefixLength])
        var finalBlock: [AesSivTagSize] u8
        defer Crypto.secureClear(finalBlock)
        Swag.memcpy(&finalBlock[0], plaintext.buffer + prefixLength, AesSivTagSize)
        for index in AesSivTagSize do
            finalBlock[index] ^= value[index]
        try cmac.update(finalBlock)
        var result = try cmac.finalize()
        return result
    }

    var finalBlock: [AesSivTagSize] u8
    defer Crypto.secureClear(finalBlock)
    if plaintext.count do
        Swag.memcpy(&finalBlock[0], plaintext.buffer, plaintext.count)
    finalBlock[plaintext.count] = 0x80
    aesSivDouble(&value)
    for index in AesSivTagSize do
        finalBlock[index] ^= value[index]
    var result = try AesCmac.compute(macKey, finalBlock)
    return result
}

private func aesSivCrypt(key, associatedData: const [..] u8, hasAssociatedData: bool, input: const [..] u8, output: [..] u8, inputTag: const [..] u8, outputTag: [..] u8, decrypt: bool) fail
{
    if (key.count != 32 and key.count != 48 and key.count != 64) or
       input.count != output.count or
       (decrypt and inputTag.count != AesSivTagSize) or
       (not decrypt and outputTag.count != AesSivTagSize) do
        fail Errors.BadParameterError{"AES-SIV needs a 32, 48, or 64-byte key, matching data lengths, and a 16-byte tag"}

    let keySize = key.count / 2
    let macKey  = key[0 until keySize]
    let ctrKey  = key[keySize until key.count]
    var counter: [AesSivTagSize] u8
    defer Crypto.secureClear(counter)
    if decrypt
    {
        Swag.memcpy(&counter[0], inputTag.buffer, AesSivTagSize)
        counter[8]  &= 0x7F
        counter[12] &= 0x7F
        var plaintext: Array'u8
        plaintext.resize(input.count)
        defer Crypto.secureClear(plaintext.toSlice())
        try aesCtrCrypt(ctrKey, counter, input, plaintext.toSlice())
        var expectedTag = try aesSivComputeTag(macKey, hasAssociatedData, associatedData, plaintext.toSlice())
        defer Crypto.secureClear(expectedTag)
        let valid = Crypto.constantTimeEqual(expectedTag, inputTag)
        if not valid do
            fail Errors.BadParameterError{"AES-SIV authentication failed"}
        if input.count do
            Swag.memcpy(output.buffer, plaintext.toSlice().buffer, input.count)
        return
    }

    var computedTag = try aesSivComputeTag(macKey, hasAssociatedData, associatedData, input)
    defer Crypto.secureClear(computedTag)
    Swag.memcpy(&counter[0], &computedTag[0], AesSivTagSize)
    counter[8]  &= 0x7F
    counter[12] &= 0x7F
    try aesCtrCrypt(ctrKey, counter, input, output)
    Swag.memcpy(outputTag.buffer, &computedTag[0], AesSivTagSize)
}

// Encrypts data with AES-SIV using two equal AES keys and no associated-data item.
//
// The combined key is 32, 48, or 64 bytes; ciphertext matches plaintext length and `tag` is
// exactly 16 bytes. Exact in-place encryption and disjoint input/output are supported. The tag
// must not overlap ciphertext. AES-SIV is nonce-misuse resistant and requires no nonce.
func aesSivEncrypt(key, plaintext: const [..] u8, ciphertext, tag: [..] u8) fail
{
    var empty: Array'u8
    try aesSivCrypt(key, empty.toSlice(), false, plaintext, ciphertext, empty.toSlice(), tag, false)
}

// Encrypts data with AES-SIV while authenticating one associated-data item.
//
// Key, output, tag, and overlap requirements match [[aesSivEncrypt]]. An empty associated-data
// slice is still an authenticated associated-data item; use [[aesSivEncrypt]] for no item.
func aesSivEncryptWithAssociatedData(key, associatedData, plaintext: const [..] u8, ciphertext, tag: [..] u8) fail
{
    var empty: Array'u8
    try aesSivCrypt(key, associatedData, true, plaintext, ciphertext, empty.toSlice(), tag, false)
}

// Authenticates and decrypts AES-SIV data encrypted without associated data.
//
// The 16-byte tag is verified before any plaintext is written. The output length must match the
// ciphertext length; exact in-place operation and disjoint slices are supported.
func aesSivDecrypt(key, ciphertext, tag: const [..] u8, plaintext: [..] u8) fail
{
    var empty:    Array'u8
    var emptyTag: Array'u8
    try aesSivCrypt(key, empty.toSlice(), false, ciphertext, plaintext, tag, emptyTag.toSlice(), true)
}

// Authenticates and decrypts AES-SIV data with one associated-data item.
//
// The associated-data value must match encryption. Tag verification completes before plaintext
// is written; output length must match ciphertext length.
func aesSivDecryptWithAssociatedData(key, associatedData, ciphertext, tag: const [..] u8, plaintext: [..] u8) fail
{
    var emptyTag: Array'u8
    try aesSivCrypt(key, associatedData, true, ciphertext, plaintext, tag, emptyTag.toSlice(), true)
}
