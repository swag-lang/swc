#global private

struct JitNonNullItem
{
    value: s32
}

alias JitNonNullPointerAlias = #nonull *JitNonNullItem
alias JitConstPointerAlias   = const *JitNonNullItem

struct JitNonNullStringDefault
{
    value: #nonull string = "fallback"
}

struct(T) JitNonNullGenericBox
{
    value: T
}

alias JitNonNullStringDefaultAlias = JitNonNullStringDefault

struct JitNonNullDefaultContainer
{
    direct:  JitNonNullStringDefault
    array:   [2] JitNonNullStringDefault
    aliased: JitNonNullStringDefaultAlias
}

const JIT_NONULL_DEFAULT_CONTAINER: JitNonNullDefaultContainer = {}
const JIT_NONULL_PARTIAL_ARRAY: [2] JitNonNullStringDefault = [{value: "explicit"}]

#assert(JIT_NONULL_DEFAULT_CONTAINER.direct.value == "fallback")
#assert(JIT_NONULL_DEFAULT_CONTAINER.array[0].value == "fallback")
#assert(JIT_NONULL_DEFAULT_CONTAINER.array[1].value == "fallback")
#assert(JIT_NONULL_DEFAULT_CONTAINER.aliased.value == "fallback")
#assert(JIT_NONULL_PARTIAL_ARRAY[0].value == "explicit")
#assert(JIT_NONULL_PARTIAL_ARRAY[1].value == "fallback")

struct JitNonNullHolder
{
    required: #nonull *JitNonNullItem
    optional: #null *JitNonNullItem
    legacy:   *JitNonNullItem
    count:    s32 = 7
}

struct JitNonNullUndefinedHolder
{
    required: #nonull *JitNonNullItem = undefined
}

struct JitNonNullBlockHolder
{
    required: #nonull [*] JitNonNullItem
}

struct JitNonNullNested
{
    holder: JitNonNullHolder
}

func jitNonNullConstruction()->bool
{
    var first  = JitNonNullItem{value: 11}
    var second = JitNonNullItem{value: 22}
    var blockStorage: [2] JitNonNullItem = [{value: 31}, {value: 32}]

    let direct: #nonull *JitNonNullItem = &first
    let block: #nonull [*] JitNonNullItem = cast([*] JitNonNullItem) &blockStorage[0]
    let aliasReadOnly: const JitNonNullPointerAlias = &first
    let aliasRequired: #nonull JitConstPointerAlias = &first
    let legacySource: *JitNonNullItem = &first
    let migrated: #nonull *JitNonNullItem = legacySource
    let widened: #null *JitNonNullItem = migrated

    #assert(#typeof(aliasReadOnly) == #nonull const *JitNonNullItem)
    #assert(#typeof(aliasRequired) == #nonull const *JitNonNullItem)

    let directType = #typeof(direct)
    if !(directType.flags & Swag.TypeInfoFlags.ExplicitNonNull) or !(directType.flags & Swag.TypeInfoFlags.RequiresExplicitInit) or directType.flags & Swag.TypeInfoFlags.Nullable do
        return false

    let aliasReadOnlyType = #typeof(aliasReadOnly)
    let aliasRequiredType = #typeof(aliasRequired)
    @assert(aliasReadOnlyType.flags & Swag.TypeInfoFlags.ExplicitNonNull)
    @assert(aliasReadOnlyType.flags & Swag.TypeInfoFlags.Const)
    @assert(aliasReadOnlyType.flags & Swag.TypeInfoFlags.RequiresExplicitInit)
    @assert(aliasRequiredType.flags & Swag.TypeInfoFlags.ExplicitNonNull)
    @assert(aliasRequiredType.flags & Swag.TypeInfoFlags.Const)
    @assert(aliasRequiredType.flags & Swag.TypeInfoFlags.RequiresExplicitInit)

    let holderType = cast(const *Swag.TypeInfoStruct) #typeof(JitNonNullHolder)
    let nestedType = #typeof(JitNonNullNested)
    let holderArrayType = #typeof([2] JitNonNullHolder)
    let pointerArrayType = #typeof([2] #nonull *JitNonNullItem)
    let defaultContainerType = #typeof(JitNonNullDefaultContainer)
    let genericRequiredType = cast(const *Swag.TypeInfoStruct) #typeof(JitNonNullGenericBox'(#nonull *JitNonNullItem))
    let genericDefaultType = cast(const *Swag.TypeInfoStruct) #typeof(JitNonNullGenericBox'JitNonNullStringDefault)
    if holderType.opInit != null or !(holderType.flags & Swag.TypeInfoFlags.RequiresExplicitInit) do
        return false
    if !(nestedType.flags & Swag.TypeInfoFlags.RequiresExplicitInit) or !(holderArrayType.flags & Swag.TypeInfoFlags.RequiresExplicitInit) or !(pointerArrayType.flags & Swag.TypeInfoFlags.RequiresExplicitInit) do
        return false
    if defaultContainerType.flags & Swag.TypeInfoFlags.RequiresExplicitInit do
        return false
    if genericRequiredType.opInit != null or !(genericRequiredType.flags & Swag.TypeInfoFlags.RequiresExplicitInit) do
        return false
    if genericDefaultType.opInit == null or genericDefaultType.flags & Swag.TypeInfoFlags.RequiresExplicitInit do
        return false

    let holder = JitNonNullHolder{required: direct}
    var moveSource = JitNonNullHolder{required: &first}
    let moveTarget = #move moveSource
    let blockHolder = JitNonNullBlockHolder{required: block}
    let contextual: JitNonNullHolder = {required: &second, count: 9}
    let nested = JitNonNullNested{holder: {required: &first}}
    let array: [2] JitNonNullHolder = [
        {required: &first},
        {required: &second, count: 8},
    ]
    let genericRequired: JitNonNullGenericBox'(#nonull *JitNonNullItem) = {value: &first}
    var genericDefault: JitNonNullGenericBox'JitNonNullStringDefault

    if holder.required != &first or holder.required.value != 11 do
        return false
    if moveTarget.required != &first do
        return false
    if holder.optional != null or holder.legacy != null or holder.count != 7 do
        return false
    if blockHolder.required[0].value != 31 or blockHolder.required[1].value != 32 do
        return false
    if contextual.required != &second or contextual.count != 9 do
        return false
    if nested.holder.required != &first or nested.holder.optional != null or nested.holder.count != 7 do
        return false
    if array[0].required != &first or array[0].count != 7 do
        return false
    if array[1].required != &second or array[1].count != 8 do
        return false
    if migrated != &first or widened != &first do
        return false
    if genericRequired.value != &first or genericDefault.value.value != "fallback" do
        return false

    var defaultItem: JitNonNullStringDefault
    var defaultArray: [2] JitNonNullStringDefault
    let omittedDefaults = JitNonNullDefaultContainer{}
    let partialDefaults: [2] JitNonNullStringDefault = [{value: "explicit"}]

    @assert(defaultItem.value == "fallback")
    @assert(defaultArray[0].value == "fallback")
    @assert(defaultArray[1].value == "fallback")
    @assert(omittedDefaults.direct.value == "fallback")
    @assert(omittedDefaults.array[0].value == "fallback")
    @assert(omittedDefaults.array[1].value == "fallback")
    @assert(omittedDefaults.aliased.value == "fallback")
    @assert(partialDefaults[0].value == "explicit")
    @assert(partialDefaults[1].value == "fallback")
    @assert(JIT_NONULL_DEFAULT_CONTAINER.array[1].value == "fallback")
    @assert(JIT_NONULL_PARTIAL_ARRAY[0].value == "explicit")
    @assert(JIT_NONULL_PARTIAL_ARRAY[1].value == "fallback")

    var mutable = holder
    @init(mutable)(&second)
    if mutable.required != &second or mutable.optional != null or mutable.legacy != null or mutable.count != 7 do
        return false

    // 'undefined' remains an explicit low-level escape hatch; its value must not be read.
    var undefinedPointer: #nonull *JitNonNullItem = undefined
    var undefinedHolder = JitNonNullUndefinedHolder{}
    #assert(#typeof(undefinedPointer) == #nonull *JitNonNullItem)
    #assert(#typeof(undefinedHolder.required) == #nonull *JitNonNullItem)

    // Explicitly nullable and unannotated pointers keep their null default during migration.
    var nullablePointer: #null *JitNonNullItem
    var legacyPointer: *JitNonNullItem
    var legacyHolder: struct {ptr: *JitNonNullItem}
    if nullablePointer != null or legacyPointer != null or legacyHolder.ptr != null do
        return false

    return true
}

#test
{
    @assert(jitNonNullConstruction())
}
