#global namespace Serialization

using Swag, Core.Errors

// One serializable field of a struct, with everything the serializers would otherwise
// recompute per instance: the wire key, the wire identity of the type and the compression
// policy.
public struct PlanField
{
    public
    {
        value:      Swag.TypeValue     // The reflected field this entry describes.
        key:        String             // Stable, human-readable wire key of the field.
        wireCrc:    u32                // Static wire identity of the field type.
        compressed: bool               // Whether the field payload is deflate compressed.
    }
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
    public
    {
        structType: #null const *Swag.TypeInfoStruct     // The type this plan describes.
        version:    u32                                  // Value of the 'Serialization.Version' attribute, 0 when absent.
        hasVersion: bool                                 // Whether the type carries a 'Serialization.Version' attribute.
        podFinal:   bool                                 // Whether the type serializes as raw bytes (see [[Core.Serialization.isPodFinal]]).
        hasCustom:  bool                                 // Whether the type implements 'ISerialize' and drives its own fields.
        fields:     Array'PlanField                      // The serializable fields, in declaration order.
        keyToIndex: HashTable'(string, u64)              // Maps a field key to its index in 'fields'.
    }
}

public impl Plan
{
    // Returns the plan field matching a wire key, or null.
    mtd const fieldByKey(key: string)->#null const *PlanField
    {
        let e = .keyToIndex.tryFind(key)
        if !e do
            return null
        return .fields.buffer! + e.value
    }
}

// Plans are built once per reflected type and shared behind a lock. Pointer identity keeps
// two unrelated types from sharing a plan when their runtime CRCs collide.

private
{
    var g_Plans:    HashTable'(u64, *Plan)
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
        pf.value = field
        pf.key   = wireFieldKey(field)
        if pf.key == "" do
            fail SerializationError{"serialized field needs a non-empty key", field: field}
        pf.wireCrc    = wireTypeCrc(field.pointedType)
        pf.compressed = Reflection.hasAttribute(field, Compress) or Reflection.hasAttribute(field.pointedType, Compress)

        for &existing in plan.fields
        {
            if existing.key == pf.key do
                fail SerializationError{Errors.mkString(Format.toString("serialized struct [[%]] fields [[%]] and [[%]] use key [[%]]", structType.fullname, existing.value.name, field.name, pf.key)), field: field}
        }

        plan.fields.add(#move pf)
    }

    // Populate borrowed lookup views only after the field array has reached its final
    // allocation. Growing an array of owned strings can relocate their buffers.
    for &pf, fieldIndex in plan.fields do
        plan.keyToIndex.add(pf.key.toString(), fieldIndex)
}

// Returns the shared serialization plan of a struct type, building it on first use.
public func planFor(structType: const *Swag.TypeInfoStruct)->*Plan fail
{
    let key = cast(u64) structType

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
