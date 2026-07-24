using Core, Pixel

// Placeholder shown by an editor when the edited instances disagree on a field value.
const PropMixedText = "—"

// Multi-selection support for the property grid.
//
// The grid can edit several instances of the same struct type at once (like the
// property inspectors in Unity/Unreal). Every item keeps the field address in each
// edited instance in `dataInstances` (`[0]` aliases the single-instance `data`).
//
//  - Reading: a field whose value differs across the instances is "mixed"; the editor
//    shows a neutral placeholder instead of a concrete value.
//  - Writing: editing a field writes the new value into every instance.
//
// Instance addresses are derived from the per-instance struct base and the field's
// fixed offset, so this covers scalars, nested structs, static arrays and vectors.
// Items inside a dynamic array are left single-instance (their element addresses are
// not at a fixed offset from the struct base).

internal impl Properties
{
    // Number of edited instances (always >= 1).
    mtd instanceCount(item: *PropertiesItem)->u64
    {
        return Math.max(item.dataInstances.count, 1)
    }

    // Field address in instance 'k'. Falls back to the single 'data' pointer.
    mtd instanceAddr(item: *PropertiesItem, k: u64)->#null *u8
    {
        if k < item.dataInstances.count do
            return item.dataInstances[k]
        return item.data
    }

    // True when more than one instance is being edited.
    mtd isMultiEdit(item: *PropertiesItem)->bool
    {
        return item.dataInstances.count > 1
    }

    // True when the item (or an ancestor) is a dynamic array.
    mtd isUnderDynamicArray(item: *PropertiesItem)->bool
    {
        var scan = cast(#null *PropertiesItem) item
        while scan
        {
            if isDynamicArrayType(scan.type) do
                return true
            scan = scan.parent
        }

        return false
    }

    // True when the field differs across the edited instances (multi-selection only).
    mtd fieldIsMixed(item: *PropertiesItem)->bool
    {
        let n = item.dataInstances.count
        if n <= 1 do
            return false

        // Dynamic strings own a heap buffer, so compare by content not by bytes.
        if item.type == Core.String
        {
            let s0 = notnull cast(#null *String) item.dataInstances[0]
            for [i] in 1 until n
            {
                if (dref notnull cast(#null *String) item.dataInstances[i]) != dref s0 do
                    return true
            }

            return false
        }

        let sz = .fieldSize(item)
        if sz == 0 do
            return false

        let a0 = cast(#null const [*] void) item.dataInstances[0]
        for [i] in 1 until n
        {
            if Memory.compare(a0, cast(#null const [*] void) item.dataInstances[i], sz) != 0 do
                return true
        }

        return false
    }

    // Copy the just-edited field value from instance 0 into the other instances.
    mtd propagateField(item: *PropertiesItem)
    {
        let n = item.dataInstances.count
        if n <= 1 do
            return

        if item.type == Core.String
        {
            for [i] in 1 until n do
                dref notnull cast(#null *String) item.dataInstances[i] = dref notnull cast(#null *String) item.dataInstances[0]
            return
        }

        let sz = .fieldSize(item)
        if sz == 0 do
            return

        for [i] in 1 until n do
            Memory.copy(cast(#null [*] void) item.dataInstances[i], cast(#null const [*] void) item.dataInstances[0], sz)
    }

    // Show the value box as "mixed" when the instances disagree (blank text + dash note),
    // otherwise clear the note so the concrete value set by the caller shows through.
    // Returns true when mixed, so the caller can skip writing a concrete value.
    #[Swag.Discardable]
    mtd setEditMixed(item: *PropertiesItem, ed: *EditBox)->bool
    {
        if .fieldIsMixed(item)
        {
            ed.setText("")
            ed.setNote(PropMixedText)
            return true
        }

        ed.setNote("")
        return false
    }

    // Like fieldIsMixed but for a sub-range of the field (e.g. one vector component at
    // byte offset 'byteOffset', 'sz' bytes wide).
    mtd subFieldIsMixed(item: *PropertiesItem, byteOffset, sz: u64)->bool
    {
        let n = item.dataInstances.count
        if n <= 1 or sz == 0 do
            return false

        let a0 = cast(#null const [*] void) (cast(#null [*] u8) item.dataInstances[0] + byteOffset)
        for [i] in 1 until n
        {
            let ai = cast(#null const [*] void) (cast(#null [*] u8) item.dataInstances[i] + byteOffset)
            if Memory.compare(a0, ai, sz) != 0 do
                return true
        }

        return false
    }

    // setEditMixed for a sub-range of the field (used by the vector component boxes).
    #[Swag.Discardable]
    mtd setEditMixedSub(item: *PropertiesItem, ed: *EditBox, byteOffset, sz: u64)->bool
    {
        if .subFieldIsMixed(item, byteOffset, sz)
        {
            ed.setText("")
            ed.setNote(PropMixedText)
            return true
        }

        ed.setNote("")
        return false
    }

    // Write a single f32 component (at byte offset 'byteOffset') into every instance.
    // Used by the vector editor so editing one component leaves the others untouched.
    mtd writeFloatComponent(item: *PropertiesItem, byteOffset: u64, val: f32)
    {
        let n = .instanceCount(item)
        for [k] in n do
            dref notnull cast(#null *f32) (cast(#null [*] u8) .instanceAddr(item, k) + byteOffset) = val
    }

    // Set or clear the masked bits of the enum-flags field in every instance, leaving the
    // other flag bits (which may legitimately differ per instance) untouched.
    mtd writeEnumBit(item: *PropertiesItem, mask: u64, set: bool)
    {
        let n  = .instanceCount(item)
        let sz = .fieldSize(item)
        for [k] in n
        {
            let addr = .instanceAddr(item, k)
            var v    = readEnumBits(addr, sz)
            if set do
                v |= mask
            else do
                v &= ~mask
            writeEnumBits(addr, sz, v)
        }
    }

    // True when the masked bits of an enum-flags field disagree across the instances.
    // 'mask' is the flag value of one row; the row is "mixed" when some instances have
    // the bit set and others do not.
    mtd flagBitIsMixed(item: *PropertiesItem, mask: u64)->bool
    {
        let n = item.dataInstances.count
        if n <= 1 do
            return false

        let sz   = .fieldSize(item)
        let bit0 = readEnumBits(item.dataInstances[0], sz) & mask
        for [i] in 1 until n
        {
            if (readEnumBits(item.dataInstances[i], sz) & mask) != bit0 do
                return true
        }

        return false
    }
}

private impl Properties
{
    func readEnumBits(addr: #null *u8, sz: u64)->u64
    {
        switch sz
        {
        case 1: return cast(u64) dref notnull cast(#null *u8) addr
        case 2: return cast(u64) dref notnull cast(#null *u16) addr
        case 4: return cast(u64) dref notnull cast(#null *u32) addr
        case 8: return dref notnull cast(#null *u64) addr
        }

        return 0
    }

    func writeEnumBits(addr: #null *u8, sz, val: u64)
    {
        switch sz
        {
        case 1: dref notnull cast(#null *u8) addr = cast(u8) val
        case 2: dref notnull cast(#null *u16) addr = cast(u16) val
        case 4: dref notnull cast(#null *u32) addr = cast(u32) val
        case 8: dref notnull cast(#null *u64) addr = val
        }
    }
}

private impl Properties
{
    // The field's byte size (the pointed type of the value).
    mtd fieldSize(item: *PropertiesItem)->u64
    {
        if !item.type do
            return 0
        return item.type.sizeof
    }

    func isDynamicArrayType(t: #null typeinfo)->bool
    {
        if !t do
            return false
        if !Reflection.isStruct(t) do
            return false
        return (cast(#null const *Swag.TypeInfoStruct) t).fromGeneric == Array
    }
}
