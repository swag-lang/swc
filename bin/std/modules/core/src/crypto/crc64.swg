#global namespace Hash
#global #[Swag.Safety(.Overflow, false)]

using Swag

// Computes a CRC-64 checksum incrementally.
public struct Crc64
{
    internal
    {
        currentValue: u64
        kind:         Crc64Kind
    }
}

// Selects the CRC-64 polynomial and reflection convention.
public enum Crc64Kind
{
    Ecma182     // CRC-64/ECMA-182.
    Iso         // CRC-64/ISO.
    IsoXz       // CRC-64/XZ.
}

public impl Crc64
{
    // Resets the checksum and selects the algorithm used by subsequent updates.
    mtd reset(kind = Crc64Kind.Ecma182)
    {
        Swag.init(me, 1)
        switch #complete .kind
        {
        case .Ecma182, .Iso, .IsoXz: .kind = kind
        }
    }

    // Includes `data` in the running checksum.
    #[ConstExpr, Swag.Safety(.All, false)]
    mtd update(data: #null const [..] u8)
    {
        let length = data.count
        if length == 0 do
            return

        let bytes = cast(const [*] u8) data.buffer!
        var cur   = .currentValue
        var i     = 0'u64
        switch #complete kind
        {
        case .Ecma182:
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

            .currentValue = cur

        case .Iso:
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

            .currentValue = ~cur

        case .IsoXz:
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

            .currentValue = ~cur
        }
    }

    // Returns the checksum accumulated since construction or the latest [[reset]].
    mtd value() => .currentValue

    // Computes a CRC-64 checksum in one operation.
    #[Swag.ConstExpr]
    func compute(buffer: const [..] u8, kind = Crc64Kind.Ecma182)->u64
    {
        var v: Crc64
        v.reset(kind)
        v.update(buffer)
        return v.value()
    }
}
