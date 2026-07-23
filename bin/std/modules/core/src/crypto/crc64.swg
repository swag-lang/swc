#global namespace Hash
#global #[Swag.CanOverflow(true)]

using Swag

// CRC-64 implementation as described in ECMA-182, Annex B.
public struct Crc64
{
    crc: u64
}

public enum Crc64Kind
{
    ECMA182
    ISO
    ISOXZ
}

impl Crc64
{
    // Initialize the hashing sequence
    mtd init(kind: Crc64Kind)
    {
        #[Swag.Complete]
        switch kind
        {
        case ECMA182, ISO, ISOXZ:
            .crc = 0
        }
    }

    // Computes the CRC-64 hash of the provided data.
    #[ConstExpr, Swag.Safety(.All, false)]
    public mtd update(data: #null const [..] u8, kind: Crc64Kind)
    {
        let length = @countof(data)
        if length == 0 do
            return

        let bytes = cast(#null const [*] u8) @dataof(data)
        var cur   = .crc
        var i     = 0'u64
        #[Swag.Complete]
        switch kind
        {
        case ECMA182:
            const POLY: u64 = 0x42F0_E1EB_A9EA_3693
            while i < length
            {
                cur ^= cast(u64) bytes[i] << 56
                for 8
                {
                    if cur & 0x8000_0000_0000_0000'u64 do
                        cur = (cur << 1) ^ POLY
                    else do
                        cur <<= 1
                }

                i += 1
            }

            .crc = cur

        case ISO:
            const POLY: u64 = 0xD800_0000_0000_0000
            cur = ~cur
            while i < length
            {
                cur ^= bytes[i]
                for 8
                {
                    if cur & 1 do
                        cur = (cur >> 1) ^ POLY
                    else do
                        cur >>= 1
                }

                i += 1
            }

            .crc = ~cur

        case ISOXZ:
            const POLY: u64 = 0xC96C_5795_D787_0F42
            cur = ~cur
            while i < length
            {
                cur ^= bytes[i]
                for 8
                {
                    if cur & 1 do
                        cur = (cur >> 1) ^ POLY
                    else do
                        cur >>= 1
                }

                i += 1
            }

            .crc = ~cur
        }
    }

    // Returns the hash value for the given buffer
    #[Swag.ConstExpr]
    public func compute(buffer: const [..] u8, kind = Crc64Kind.ECMA182)->u64
    {
        var v: Crc64
        v.init(kind)
        v.update(buffer, kind)
        return v.crc
    }
}
