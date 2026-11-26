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

private impl Crc64
{
    alias ChecksumRow   = [256] u64
    alias ChecksumTable = [8] ChecksumRow

    const Ecma182Table = #run buildTable(0x42F0_E1EB_A9EA_3693, reflected: false)
    const IsoTable     = #run buildTable(0xD800_0000_0000_0000, reflected: true)
    const XzTable      = #run buildTable(0xC96C_5795_D787_0F42, reflected: true)

    func buildTable(polynomial: u64, reflected: bool)->ChecksumTable
    {
        var table: ChecksumTable
        for index in 256
        {
            var value = cast(u64, index)
            if reflected
            {
                for 8 do
                    value = value & 1 ? (value >> 1) ^ polynomial : value >> 1
            }
            else
            {
                value <<= 56
                for 8 do
                    value = value >> 63 ? (value << 1) ^ polynomial : value << 1

                // Store ECMA-182 with its next byte's index in the low bits as well.
                value = Swag.byteSwap(value)
            }

            table[0, index] = value
        }

        for slice in 1 until 8
        {
            for index in 256
            {
                let previous = table[slice - 1, index]
                table[slice, index] = (previous >> 8) ^ table[0, previous & 0xFF]
            }
        }

        return table
    }

    #[ConstExpr, Swag.Safety(.All, false)]
    func updateTable(bytes: const [*] u8, length, initial: u64, table: const [..] ChecksumRow)->u64
    {
        var crc    = initial
        var offset = 0'u64
        while length - offset >= 8
        {
            let word  = Math.littleEndianToNative(cast(const [*] u64, bytes + offset)[0])
            let mixed = word ^ crc
            crc = table[7, mixed & 0xFF] ^
                  table[6, (mixed >> 8) & 0xFF] ^
                  table[5, (mixed >> 16) & 0xFF] ^
                  table[4, (mixed >> 24) & 0xFF] ^
                  table[3, (mixed >> 32) & 0xFF] ^
                  table[2, (mixed >> 40) & 0xFF] ^
                  table[1, (mixed >> 48) & 0xFF] ^
                  table[0, mixed >> 56]
            offset += 8
        }

        for index in offset until length do
            crc = (crc >> 8) ^ table[0, (crc & 0xFF) ^ bytes[index]]
        return crc
    }
}

public impl Crc64
{
    // Resets the checksum and selects the algorithm used by subsequent updates.
    mtd reset(kind = Crc64Kind.Ecma182)
    {
        Swag.init(me, 1)
        .kind = kind
    }

    // Includes `data` in the running checksum.
    #[ConstExpr, Swag.Safety(.All, false)]
    mtd update(data: const [..] u8?)
    {
        let length = data.count
        if length == 0 do
            return

        let bytes = cast(const [*] u8, unwrap data.buffer)
        switch #complete .kind
        {
        case .Ecma182:
            let crc = updateTable(bytes, length, Swag.byteSwap(.currentValue), Ecma182Table)
            .currentValue = Swag.byteSwap(crc)

        case .Iso:
            .currentValue = ~updateTable(bytes, length, ~.currentValue, IsoTable)

        case .IsoXz:
            .currentValue = ~updateTable(bytes, length, ~.currentValue, XzTable)
        }
    }

    // Returns the checksum accumulated since construction or the latest [[reset]].
    mtd value() => .currentValue

    // Computes the CRC-64 checksum of `buffer` with the `kind` algorithm in one operation.
    #[Swag.ConstExpr]
    func compute(buffer: const [..] u8, kind = Crc64Kind.Ecma182)->u64
    {
        var v: Crc64
        v.reset(kind)
        v.update(buffer)
        return v.value()
    }
}
