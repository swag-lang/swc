#global private

struct JitNonNullItem
{
    value: s32
}

// Materialize the array type before its element declaration is semantically complete.
const JIT_NONULL_FORWARD_ARRAY_REQUIRES_INIT =
    (#typeof([2] JitNonNullForwardHolder).flags & Swag.TypeInfoFlags.RequiresExplicitInit) != 0

struct JitNonNullForwardHolder
{
    required: *JitNonNullItem
}

alias JitNonNullPointerAlias = *JitNonNullItem
alias JitConstPointerAlias   = const *JitNonNullItem

const JIT_NONULL_POINTER_DEFAULT_TEXT = "fallback"

struct JitNonNullStringDefault
{
    value: string = "fallback"
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
    required: *JitNonNullItem
    optional: #null *JitNonNullItem
    legacy:   #null *JitNonNullItem
    count:    s32 = 7
}

alias JitNonNullHolderAlias = JitNonNullHolder

struct JitNonNullPointerDefault
{
    required: const [*] u8 = @dataof(JIT_NONULL_POINTER_DEFAULT_TEXT)
}

struct JitNonNullMoveDefault
{
    required: string = "move-default"
}

impl JitNonNullMoveDefault
{
    mtd opDrop()
    {
    }
}

struct JitNonNullUndefinedHolder
{
    required: *JitNonNullItem = undefined
}

struct JitNonNullBlockHolder
{
    required: [*] JitNonNullItem
}

struct JitNonNullFamilies
{
    valuePointer:  *JitNonNullItem
    blockPointer:  [*] JitNonNullItem
    slice:         [..] JitNonNullItem
    text:          string
    ctext:         cstring
    boxed:         any
    reflectedType: typeinfo
}

struct JitNonNullNested
{
    holder: JitNonNullHolder
}

func jitHasNonNullFlags(type: typeinfo)->bool
{
    if !(type.flags & Swag.TypeInfoFlags.RequiresExplicitInit) do
        return false
    return !(type.flags & Swag.TypeInfoFlags.Nullable)
}

func migrateJitLegacyPointer(value: *JitNonNullItem)->*JitNonNullItem => value

func jitNonNullConstruction()->bool
{
    var first  = JitNonNullItem{value: 11}
    var second = JitNonNullItem{value: 22}
    var blockStorage: [2] JitNonNullItem = [{value: 31}, {value: 32}]
    var cstringStorage: [4] u8 = ['a''u8, 'b''u8, 'c''u8, 0]

    let direct: *JitNonNullItem = &first
    let block: [*] JitNonNullItem = cast([*] JitNonNullItem) &blockStorage[0]
    let slice: [..] JitNonNullItem = blockStorage
    let text: string = "nonull"
    let ctext: cstring = cast(cstring) &cstringStorage[0]
    let boxed: any = 123
    let reflectedType: typeinfo = JitNonNullItem
    var nullableValuePointer: #null *JitNonNullItem = null
    var nullableBlockPointer: #null [*] JitNonNullItem = null
    var nullableSlice: #null [..] JitNonNullItem = null
    var nullableString: #null string = null
    var nullableCString: #null cstring = null
    var nullableTypeInfo: #null typeinfo = null
    let boxedNullableValuePointer: any = nullableValuePointer
    let boxedNullableBlockPointer: any = nullableBlockPointer
    let boxedNullableSlice: any = nullableSlice
    let boxedNullableString: any = nullableString
    let boxedNullableCString: any = nullableCString
    let boxedNullableTypeInfo: any = nullableTypeInfo
    let aliasReadOnly: const JitNonNullPointerAlias = &first
    let aliasRequired: JitConstPointerAlias = &first
    let legacySource: *JitNonNullItem = &first
    let migrated: *JitNonNullItem = migrateJitLegacyPointer(legacySource)
    var widened: #null *JitNonNullItem = migrated
    widened = null // the qualifier is real: null flows into it
    widened = migrated

    #assert(#typeof(aliasReadOnly) == const *JitNonNullItem)
    #assert(#typeof(aliasRequired) == const *JitNonNullItem)
    #assert(#typeof(direct) == *JitNonNullItem)
    #assert(#typeof(block) == [*] JitNonNullItem)
    #assert(#typeof(slice) == [..] JitNonNullItem)
    #assert(#typeof(text) == string)
    #assert(#typeof(ctext) == cstring)
    #assert(#typeof(boxed) == any)
    #assert(#typeof(reflectedType) == typeinfo)

    if !jitHasNonNullFlags(#typeof(direct)) or
       !jitHasNonNullFlags(#typeof(block)) or
       !jitHasNonNullFlags(#typeof(slice)) or
       !jitHasNonNullFlags(#typeof(text)) or
       !jitHasNonNullFlags(#typeof(ctext)) or
       !jitHasNonNullFlags(#typeof(boxed)) or
       !jitHasNonNullFlags(#typeof(reflectedType)) do
        return false

    let aliasReadOnlyType = #typeof(aliasReadOnly)
    let aliasRequiredType = #typeof(aliasRequired)
        @assert(aliasReadOnlyType.flags & Swag.TypeInfoFlags.Const)
    @assert(aliasReadOnlyType.flags & Swag.TypeInfoFlags.RequiresExplicitInit)
        @assert(aliasRequiredType.flags & Swag.TypeInfoFlags.Const)
    @assert(aliasRequiredType.flags & Swag.TypeInfoFlags.RequiresExplicitInit)

    let holderType = cast(const *Swag.TypeInfoStruct) #typeof(JitNonNullHolder)
    let nestedType = #typeof(JitNonNullNested)
    let holderArrayType = #typeof([2] JitNonNullHolder)
    let pointerArrayType = #typeof([2] *JitNonNullItem)
    let defaultContainerType = #typeof(JitNonNullDefaultContainer)
    let genericRequiredType = cast(const *Swag.TypeInfoStruct) #typeof(JitNonNullGenericBox'(*JitNonNullItem))
    let genericDefaultType = cast(const *Swag.TypeInfoStruct) #typeof(JitNonNullGenericBox'JitNonNullStringDefault)
    if holderType.opInit != null or !(holderType.flags & Swag.TypeInfoFlags.RequiresExplicitInit) do
        return false
    if !(nestedType.flags & Swag.TypeInfoFlags.RequiresExplicitInit) or !(holderArrayType.flags & Swag.TypeInfoFlags.RequiresExplicitInit) or !(pointerArrayType.flags & Swag.TypeInfoFlags.RequiresExplicitInit) do
        return false
    if !JIT_NONULL_FORWARD_ARRAY_REQUIRES_INIT do
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
    let genericRequired: JitNonNullGenericBox'(*JitNonNullItem) = {value: &first}
    var genericDefault: JitNonNullGenericBox'JitNonNullStringDefault
    let pointerArray: [2] *JitNonNullItem = [&first, &second]
    let aliasedHolder: JitNonNullHolderAlias = {required: &first}
    let pointerDefault = JitNonNullPointerDefault{}
    var moveDefaultSource = JitNonNullMoveDefault{required: "explicit"}
    let moveDefaultTarget = #move moveDefaultSource
    let families = JitNonNullFamilies{
        valuePointer:  direct,
        blockPointer:  block,
        slice:         slice,
        text:          text,
        ctext:         ctext,
        boxed:         boxed,
        reflectedType: reflectedType,
    }

    #assert(#typeof(families.valuePointer) == *JitNonNullItem)
    #assert(#typeof(families.blockPointer) == [*] JitNonNullItem)
    #assert(#typeof(families.slice) == [..] JitNonNullItem)
    #assert(#typeof(families.text) == string)
    #assert(#typeof(families.ctext) == cstring)
    #assert(#typeof(families.boxed) == any)
    #assert(#typeof(families.reflectedType) == typeinfo)
    #assert(#typeof(pointerArray[0]) == *JitNonNullItem)
    #assert(#typeof(aliasedHolder) == JitNonNullHolder)
    #assert(#typeof(aliasedHolder.required) == *JitNonNullItem)
    #assert(#typeof(pointerDefault.required) == const [*] u8)
    #assert(#typeof(moveDefaultSource.required) == string)
    #assert(#typeof(moveDefaultTarget.required) == string)

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
    if families.valuePointer != &first or families.blockPointer[1].value != 32 do
        return false
    if @countof(families.slice) != 2 or families.slice[0].value != 31 do
        return false
    if families.text != "nonull" or families.ctext[0] != 'a''u8 do
        return false
    if cast(s32) families.boxed != 123 or families.reflectedType.name != "JitNonNullItem" do
        return false
    if boxedNullableValuePointer == null or
       boxedNullableBlockPointer == null or
       boxedNullableSlice == null or
       boxedNullableString == null or
       boxedNullableCString == null or
       boxedNullableTypeInfo == null do
        return false
    if pointerArray[0] != &first or pointerArray[1] != &second or aliasedHolder.required != &first do
        return false
    if pointerDefault.required != @dataof(JIT_NONULL_POINTER_DEFAULT_TEXT) or pointerDefault.required[0] != 'f''u8 do
        return false
    if moveDefaultTarget.required != "explicit" or moveDefaultSource.required != "move-default" do
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
    var undefinedPointer: *JitNonNullItem = undefined
    var undefinedHolder = JitNonNullUndefinedHolder{}
    #assert(#typeof(undefinedPointer) == *JitNonNullItem)
    #assert(#typeof(undefinedHolder.required) == *JitNonNullItem)

    // Only explicitly nullable pointers keep a null default; bare pointers have no implicit default.
    var nullablePointer: #null *JitNonNullItem
    var legacyHolder: struct {ptr: #null *JitNonNullItem}
    if nullablePointer != null or legacyHolder.ptr != null do
        return false

    return true
}

#test
{
    @assert(jitNonNullConstruction())
}
