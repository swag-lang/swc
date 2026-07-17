#global private

struct NativeNonNullItem
{
    value: s32
}

// Materialize the array type before its element declaration is semantically complete.
const NATIVE_NONULL_FORWARD_ARRAY_REQUIRES_INIT =
    (#typeof([2] NativeNonNullForwardHolder).flags & Swag.TypeInfoFlags.RequiresExplicitInit) != 0

struct NativeNonNullForwardHolder
{
    required: #nonull *NativeNonNullItem
}

alias NativeNonNullPointerAlias = #nonull *NativeNonNullItem
alias NativeConstPointerAlias   = const *NativeNonNullItem

const NATIVE_NONULL_POINTER_DEFAULT_TEXT = "fallback"

struct NativeNonNullStringDefault
{
    value: #nonull string = "fallback"
}

struct(T) NativeNonNullGenericBox
{
    value: T
}

alias NativeNonNullStringDefaultAlias = NativeNonNullStringDefault

struct NativeNonNullDefaultContainer
{
    direct:  NativeNonNullStringDefault
    array:   [2] NativeNonNullStringDefault
    aliased: NativeNonNullStringDefaultAlias
}

const NATIVE_NONULL_DEFAULT_CONTAINER: NativeNonNullDefaultContainer = {}
const NATIVE_NONULL_PARTIAL_ARRAY: [2] NativeNonNullStringDefault = [{value: "explicit"}]

#assert(NATIVE_NONULL_DEFAULT_CONTAINER.direct.value == "fallback")
#assert(NATIVE_NONULL_DEFAULT_CONTAINER.array[0].value == "fallback")
#assert(NATIVE_NONULL_DEFAULT_CONTAINER.array[1].value == "fallback")
#assert(NATIVE_NONULL_DEFAULT_CONTAINER.aliased.value == "fallback")
#assert(NATIVE_NONULL_PARTIAL_ARRAY[0].value == "explicit")
#assert(NATIVE_NONULL_PARTIAL_ARRAY[1].value == "fallback")

struct NativeNonNullHolder
{
    required: #nonull *NativeNonNullItem
    optional: #null *NativeNonNullItem
    legacy:   *NativeNonNullItem
    count:    s32 = 7
}

alias NativeNonNullHolderAlias = NativeNonNullHolder

struct NativeNonNullPointerDefault
{
    required: #nonull const [*] u8 = @dataof(NATIVE_NONULL_POINTER_DEFAULT_TEXT)
}

struct NativeNonNullMoveDefault
{
    required: #nonull string = "move-default"
}

impl NativeNonNullMoveDefault
{
    mtd opDrop()
    {
    }
}

struct NativeNonNullUndefinedHolder
{
    required: #nonull *NativeNonNullItem = undefined
}

struct NativeNonNullBlockHolder
{
    required: #nonull [*] NativeNonNullItem
}

struct NativeNonNullFamilies
{
    valuePointer:  #nonull *NativeNonNullItem
    blockPointer:  #nonull [*] NativeNonNullItem
    slice:         #nonull [..] NativeNonNullItem
    text:          #nonull string
    ctext:         #nonull cstring
    boxed:         #nonull any
    reflectedType: #nonull typeinfo
}

struct NativeNonNullNested
{
    holder: NativeNonNullHolder
}

func nativeHasNonNullFlags(type: typeinfo)->bool
{
    if !(type.flags & Swag.TypeInfoFlags.ExplicitNonNull) do
        return false
    if !(type.flags & Swag.TypeInfoFlags.RequiresExplicitInit) do
        return false
    return !(type.flags & Swag.TypeInfoFlags.Nullable)
}

func migrateNativeLegacyPointer(value: *NativeNonNullItem)->#nonull *NativeNonNullItem => value

func nativeNonNullConstruction()->bool
{
    var first  = NativeNonNullItem{value: 11}
    var second = NativeNonNullItem{value: 22}
    var blockStorage: [2] NativeNonNullItem = [{value: 31}, {value: 32}]
    var cstringStorage: [4] u8 = ['a''u8, 'b''u8, 'c''u8, 0]

    let direct: #nonull *NativeNonNullItem = &first
    let block: #nonull [*] NativeNonNullItem = cast([*] NativeNonNullItem) &blockStorage[0]
    let slice: #nonull [..] NativeNonNullItem = blockStorage
    let text: #nonull string = "nonull"
    let ctext: #nonull cstring = cast(cstring) &cstringStorage[0]
    let boxed: #nonull any = 123
    let reflectedType: #nonull typeinfo = NativeNonNullItem
    var nullableValuePointer: #null *NativeNonNullItem = null
    var nullableBlockPointer: #null [*] NativeNonNullItem = null
    var nullableSlice: #null [..] NativeNonNullItem = null
    var nullableString: #null string = null
    var nullableCString: #null cstring = null
    var nullableTypeInfo: #null typeinfo = null
    let boxedNullableValuePointer: #nonull any = nullableValuePointer
    let boxedNullableBlockPointer: #nonull any = nullableBlockPointer
    let boxedNullableSlice: #nonull any = nullableSlice
    let boxedNullableString: #nonull any = nullableString
    let boxedNullableCString: #nonull any = nullableCString
    let boxedNullableTypeInfo: #nonull any = nullableTypeInfo
    let aliasReadOnly: const NativeNonNullPointerAlias = &first
    let aliasRequired: #nonull NativeConstPointerAlias = &first
    let legacySource: *NativeNonNullItem = &first
    let migrated: #nonull *NativeNonNullItem = migrateNativeLegacyPointer(legacySource)
    let widened: #null *NativeNonNullItem = migrated

    #assert(#typeof(aliasReadOnly) == #nonull const *NativeNonNullItem)
    #assert(#typeof(aliasRequired) == #nonull const *NativeNonNullItem)
    #assert(#typeof(direct) == #nonull *NativeNonNullItem)
    #assert(#typeof(block) == #nonull [*] NativeNonNullItem)
    #assert(#typeof(slice) == #nonull [..] NativeNonNullItem)
    #assert(#typeof(text) == #nonull string)
    #assert(#typeof(ctext) == #nonull cstring)
    #assert(#typeof(boxed) == #nonull any)
    #assert(#typeof(reflectedType) == #nonull typeinfo)

    if !nativeHasNonNullFlags(#typeof(direct)) or
       !nativeHasNonNullFlags(#typeof(block)) or
       !nativeHasNonNullFlags(#typeof(slice)) or
       !nativeHasNonNullFlags(#typeof(text)) or
       !nativeHasNonNullFlags(#typeof(ctext)) or
       !nativeHasNonNullFlags(#typeof(boxed)) or
       !nativeHasNonNullFlags(#typeof(reflectedType)) do
        return false

    let aliasReadOnlyType = #typeof(aliasReadOnly)
    let aliasRequiredType = #typeof(aliasRequired)
    if !(aliasReadOnlyType.flags & Swag.TypeInfoFlags.ExplicitNonNull) or !(aliasReadOnlyType.flags & Swag.TypeInfoFlags.Const) or !(aliasReadOnlyType.flags & Swag.TypeInfoFlags.RequiresExplicitInit) do
        return false
    if !(aliasRequiredType.flags & Swag.TypeInfoFlags.ExplicitNonNull) or !(aliasRequiredType.flags & Swag.TypeInfoFlags.Const) or !(aliasRequiredType.flags & Swag.TypeInfoFlags.RequiresExplicitInit) do
        return false

    let holderType = cast(const *Swag.TypeInfoStruct) #typeof(NativeNonNullHolder)
    let nestedType = #typeof(NativeNonNullNested)
    let holderArrayType = #typeof([2] NativeNonNullHolder)
    let pointerArrayType = #typeof([2] #nonull *NativeNonNullItem)
    let defaultContainerType = #typeof(NativeNonNullDefaultContainer)
    let genericRequiredType = cast(const *Swag.TypeInfoStruct) #typeof(NativeNonNullGenericBox'(#nonull *NativeNonNullItem))
    let genericDefaultType = cast(const *Swag.TypeInfoStruct) #typeof(NativeNonNullGenericBox'NativeNonNullStringDefault)
    if holderType.opInit != null or !(holderType.flags & Swag.TypeInfoFlags.RequiresExplicitInit) do
        return false
    if !(nestedType.flags & Swag.TypeInfoFlags.RequiresExplicitInit) or !(holderArrayType.flags & Swag.TypeInfoFlags.RequiresExplicitInit) or !(pointerArrayType.flags & Swag.TypeInfoFlags.RequiresExplicitInit) do
        return false
    if !NATIVE_NONULL_FORWARD_ARRAY_REQUIRES_INIT do
        return false
    if defaultContainerType.flags & Swag.TypeInfoFlags.RequiresExplicitInit do
        return false
    if genericRequiredType.opInit != null or !(genericRequiredType.flags & Swag.TypeInfoFlags.RequiresExplicitInit) do
        return false
    if genericDefaultType.opInit == null or genericDefaultType.flags & Swag.TypeInfoFlags.RequiresExplicitInit do
        return false

    let holder = NativeNonNullHolder{required: direct}
    var moveSource = NativeNonNullHolder{required: &first}
    let moveTarget = #move moveSource
    let blockHolder = NativeNonNullBlockHolder{required: block}
    let contextual: NativeNonNullHolder = {required: &second, count: 9}
    let nested = NativeNonNullNested{holder: {required: &first}}
    let array: [2] NativeNonNullHolder = [
        {required: &first},
        {required: &second, count: 8},
    ]
    let genericRequired: NativeNonNullGenericBox'(#nonull *NativeNonNullItem) = {value: &first}
    var genericDefault: NativeNonNullGenericBox'NativeNonNullStringDefault
    let pointerArray: [2] #nonull *NativeNonNullItem = [&first, &second]
    let aliasedHolder: NativeNonNullHolderAlias = {required: &first}
    let pointerDefault = NativeNonNullPointerDefault{}
    var moveDefaultSource = NativeNonNullMoveDefault{required: "explicit"}
    let moveDefaultTarget = #move moveDefaultSource
    let families = NativeNonNullFamilies{
        valuePointer:  direct,
        blockPointer:  block,
        slice:         slice,
        text:          text,
        ctext:         ctext,
        boxed:         boxed,
        reflectedType: reflectedType,
    }

    #assert(#typeof(families.valuePointer) == #nonull *NativeNonNullItem)
    #assert(#typeof(families.blockPointer) == #nonull [*] NativeNonNullItem)
    #assert(#typeof(families.slice) == #nonull [..] NativeNonNullItem)
    #assert(#typeof(families.text) == #nonull string)
    #assert(#typeof(families.ctext) == #nonull cstring)
    #assert(#typeof(families.boxed) == #nonull any)
    #assert(#typeof(families.reflectedType) == #nonull typeinfo)
    #assert(#typeof(pointerArray[0]) == #nonull *NativeNonNullItem)
    #assert(#typeof(aliasedHolder) == NativeNonNullHolder)
    #assert(#typeof(aliasedHolder.required) == #nonull *NativeNonNullItem)
    #assert(#typeof(pointerDefault.required) == #nonull const [*] u8)
    #assert(#typeof(moveDefaultSource.required) == #nonull string)
    #assert(#typeof(moveDefaultTarget.required) == #nonull string)

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
    if nested.holder.required != &first or nested.holder.optional != null do
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
    if cast(s32) families.boxed != 123 or families.reflectedType.name != "NativeNonNullItem" do
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
    if pointerDefault.required != @dataof(NATIVE_NONULL_POINTER_DEFAULT_TEXT) or pointerDefault.required[0] != 'f''u8 do
        return false
    if moveDefaultTarget.required != "explicit" or moveDefaultSource.required != "move-default" do
        return false
    var defaultItem: NativeNonNullStringDefault
    var defaultArray: [2] NativeNonNullStringDefault
    let omittedDefaults = NativeNonNullDefaultContainer{}
    let partialDefaults: [2] NativeNonNullStringDefault = [{value: "explicit"}]

    if defaultItem.value != "fallback" do
        return false
    if defaultArray[0].value != "fallback" or defaultArray[1].value != "fallback" do
        return false
    if omittedDefaults.direct.value != "fallback" or omittedDefaults.array[0].value != "fallback" do
        return false
    if omittedDefaults.array[1].value != "fallback" or omittedDefaults.aliased.value != "fallback" do
        return false
    if partialDefaults[0].value != "explicit" or partialDefaults[1].value != "fallback" do
        return false
    if NATIVE_NONULL_DEFAULT_CONTAINER.array[1].value != "fallback" do
        return false
    if NATIVE_NONULL_PARTIAL_ARRAY[0].value != "explicit" or NATIVE_NONULL_PARTIAL_ARRAY[1].value != "fallback" do
        return false

    var mutable = holder
    @init(mutable)(&second)
    if mutable.required != &second or mutable.optional != null or mutable.legacy != null or mutable.count != 7 do
        return false

    // 'undefined' remains an explicit low-level escape hatch; its value must not be read.
    var undefinedPointer: #nonull *NativeNonNullItem = undefined
    var undefinedHolder = NativeNonNullUndefinedHolder{}
    #assert(#typeof(undefinedPointer) == #nonull *NativeNonNullItem)
    #assert(#typeof(undefinedHolder.required) == #nonull *NativeNonNullItem)

    // Explicitly nullable and unannotated pointers keep their null default during migration.
    var nullablePointer: #null *NativeNonNullItem
    var legacyPointer: *NativeNonNullItem
    var legacyHolder: struct {ptr: *NativeNonNullItem}
    if nullablePointer != null or legacyPointer != null or legacyHolder.ptr != null do
        return false

    return true
}

#test
{
    @assert(nativeNonNullConstruction())
}
