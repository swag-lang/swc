#global namespace Serialization

using Swag, Core.Errors

// One serializable field of a struct, with everything the serializers would otherwise
// recompute per instance: the wire key, the wire identity of the type, the compression
// policy and the accepted legacy names.
public struct PlanField
{
    value:      Swag.TypeValue     // The reflected field this entry describes.
    crcName:    u32                // Crc of the field name; this is the wire key of the field.
    wireCrc:    u32                // Wire identity of the field type (see [[Core.Serialization.wireTypeCrc]]).
    compressed: bool               // Whether the field payload is deflate compressed.
    aliases:    Array'u32          // Crcs of the accepted legacy names of the field.
}

// Precomputed serialization plan of one struct type.
//
// A plan is built once per type and shared by every encoder and decoder afterwards. It
// carries the filtered field list (fields marked [[Core.Serialization.NoSerialize]] are
// absent), the struct version, and the properties that select the wire layout of the
// struct. The field list, in order, is also the wire shape of the struct: the TagBin
// format stores it once per stream and references it from every instance.
public struct Plan
{
    structType: #null const *Swag.TypeInfoStruct     // The type this plan describes.
    version:    u32                                  // Value of the 'Serialization.Version' attribute, 0 when absent.
    hasVersion: bool                                 // Whether the type carries a 'Serialization.Version' attribute.
    podFinal:   bool                                 // Whether the type serializes as raw bytes (see [[Core.Serialization.isPodFinal]]).
    hasCustom:  bool                                 // Whether the type implements 'ISerialize' and drives its own fields.
    fields:     Array'PlanField                      // The serializable fields, in declaration order.
    crcToIndex: HashTable'(u32, u64)                 // Maps a field name crc to its index in 'fields'.
}

public impl Plan
{
    // Returns the plan field matching a name crc, or null.
    mtd const fieldByCrc(crc: u32)->#null const *PlanField
    {
        let e = .crcToIndex.tryFind(crc)
        if !e do
            return null
        return .fields.buffer! + e.value
    }
}

// Plans are built once and shared, so they are stored behind a lock, keyed by the
// canonical type crc, which is identical for the same logical type seen from two modules.
private
{
    var g_Plans:    HashTable'(u32, *Plan)
    var g_PlanPool: ArrayPtr'Plan
    var g_PlanLock: Sync.RWLock
}

private func buildPlan(plan: *Plan, structType: const *Swag.TypeInfoStruct) fail
{
    plan.structType = structType

    let version = Reflection.attributeValue(structType, Serialization.Version, "v")
    if version != null
    {
        plan.version    = cast(u32) version
        plan.hasVersion = true
    }

    let {pod, ?} = isPodFinal(structType)
    plan.podFinal  = pod
    plan.hasCustom = Reflection.hasInterface(structType, ISerialize)

    for field in structType.fields
    {
        if Reflection.hasAttribute(field, NoSerialize) or Reflection.hasAttribute(field.pointedType, NoSerialize) do
            continue
        Debug.assert(field.pointedType != null)

        var pf: PlanField
        pf.value      = field
        pf.crcName    = getTypeValueCrc(field)
        pf.wireCrc    = wireTypeCrc(field.pointedType)
        pf.compressed = Reflection.hasAttribute(field, Compress) or Reflection.hasAttribute(field.pointedType, Compress)

        let aliases = Reflection.attributes(field, Serialization.Alias)
        for al in aliases
        {
            let value = Reflection.attributeValue(al, "name")
            Debug.assert(value != null)
            pf.aliases.add(Hash.Crc32.compute(cast(string) value!))
        }

        // Two fields hashing to the same wire key would overwrite each other in the
        // stream index, so the type cannot be serialized at all.
        if plan.crcToIndex.contains(pf.crcName) do
            fail SerializationError{"duplicate serialized field name crc"}
        plan.crcToIndex.add(pf.crcName, plan.fields.count)
        plan.fields.add(pf)
    }
}

// Returns the shared serialization plan of a struct type, building it on first use.
public func planFor(structType: const *Swag.TypeInfoStruct)->*Plan fail
{
    let key = getTypeInfoCrc(structType)

    // Fast path: the plan already exists.
    {
        Sync.sharedLock(&g_PlanLock)
        let e = g_Plans.tryFind(key)
        if e do
            return e.value
    }

    Sync.scopedLock(&g_PlanLock)

    // Another thread can have built the plan between the two locks.
    let again = g_Plans.tryFind(key)
    if again do
        return again.value

    let plan = g_PlanPool.addNew()
    buildPlan(plan, structType)
    g_Plans.add(key, plan)
    return plan
}
