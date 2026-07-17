#global private

struct SemaNonNullItem
{
    value: s32
}

struct SemaNonNullLegacyOpCastBox
{
}

impl SemaNonNullLegacyOpCastBox
{
    #[Swag.ConstExpr, Swag.Implicit]
    mtd const opCast()->string => "legacy-op-cast"
}

struct SemaNonNullRequiredOpCastBox
{
}

impl SemaNonNullRequiredOpCastBox
{
    #[Swag.ConstExpr, Swag.Implicit]
    mtd const opCast()->#nonull string => "required-op-cast"
}

alias SemaNonNullPointerAlias = #nonull *SemaNonNullItem
alias SemaConstPointerAlias   = const *SemaNonNullItem

const SEMA_NONULL_POINTER_DEFAULT_TEXT = "fallback"

const SEMA_NONULL_NULL_VALUE_POINTER: *void = null
const SEMA_NONULL_PRESENT_VALUE_POINTER = cast(#nonull *void) 1'u64
const SEMA_NONULL_NULL_BLOCK_POINTER: [*] void = null
const SEMA_NONULL_PRESENT_BLOCK_POINTER = cast(#nonull [*] void) 1'u64

#assert(SEMA_NONULL_NULL_VALUE_POINTER < SEMA_NONULL_PRESENT_VALUE_POINTER)
#assert(SEMA_NONULL_NULL_VALUE_POINTER <= SEMA_NONULL_PRESENT_VALUE_POINTER)
#assert(SEMA_NONULL_PRESENT_VALUE_POINTER > SEMA_NONULL_NULL_VALUE_POINTER)
#assert(SEMA_NONULL_PRESENT_VALUE_POINTER >= SEMA_NONULL_NULL_VALUE_POINTER)
#assert((SEMA_NONULL_NULL_VALUE_POINTER <=> SEMA_NONULL_PRESENT_VALUE_POINTER) == -1)
#assert((SEMA_NONULL_PRESENT_VALUE_POINTER <=> SEMA_NONULL_NULL_VALUE_POINTER) == 1)
#assert(SEMA_NONULL_NULL_BLOCK_POINTER < SEMA_NONULL_PRESENT_BLOCK_POINTER)
#assert((SEMA_NONULL_NULL_BLOCK_POINTER <=> SEMA_NONULL_PRESENT_BLOCK_POINTER) == -1)

struct SemaNonNullStringDefault
{
    value: #nonull string = "fallback"
}

struct(T) SemaNonNullGenericBox
{
    value: T
}

alias SemaNonNullStringDefaultAlias = SemaNonNullStringDefault

struct SemaNonNullDefaultContainer
{
    direct:  SemaNonNullStringDefault
    array:   [2] SemaNonNullStringDefault
    aliased: SemaNonNullStringDefaultAlias
}

const SEMA_NONULL_DEFAULT_CONTAINER: SemaNonNullDefaultContainer = {}
const SEMA_NONULL_PARTIAL_ARRAY: [2] SemaNonNullStringDefault = [{value: "explicit"}]

#assert(SEMA_NONULL_DEFAULT_CONTAINER.direct.value == "fallback")
#assert(SEMA_NONULL_DEFAULT_CONTAINER.array[0].value == "fallback")
#assert(SEMA_NONULL_DEFAULT_CONTAINER.array[1].value == "fallback")
#assert(SEMA_NONULL_DEFAULT_CONTAINER.aliased.value == "fallback")
#assert(SEMA_NONULL_PARTIAL_ARRAY[0].value == "explicit")
#assert(SEMA_NONULL_PARTIAL_ARRAY[1].value == "fallback")

struct SemaNonNullHolder
{
    required: #nonull *SemaNonNullItem
    optional: #null *SemaNonNullItem
    legacy:   *SemaNonNullItem
    count:    s32 = 7
}

alias SemaNonNullHolderAlias = SemaNonNullHolder

struct SemaNonNullPointerDefault
{
    required: #nonull const [*] u8 = @dataof(SEMA_NONULL_POINTER_DEFAULT_TEXT)
}

struct SemaNonNullMoveDefault
{
    required: #nonull string = "move-default"
}

impl SemaNonNullMoveDefault
{
    mtd opDrop()
    {
    }
}

struct SemaNonNullUndefinedHolder
{
    required: #nonull *SemaNonNullItem = undefined
}

struct SemaNonNullBlockHolder
{
    required: #nonull [*] SemaNonNullItem
}

struct SemaNonNullFamilies
{
    valuePointer:  #nonull *SemaNonNullItem
    blockPointer:  #nonull [*] SemaNonNullItem
    slice:         #nonull [..] SemaNonNullItem
    text:          #nonull string
    ctext:         #nonull cstring
    boxed:         #nonull any
    reflectedType: #nonull typeinfo
}

struct SemaNonNullNested
{
    holder: SemaNonNullHolder
}

struct SemaNonNullCompleteSet
{
    required: #nonull *SemaNonNullItem
}

impl SemaNonNullCompleteSet
{
    #[Swag.Complete]
    mtd opSet(value: #nonull *SemaNonNullItem)
    {
        .required = value
    }
}

func acceptSemaNonNullHolder(value: SemaNonNullHolder)
{
}

func migrateSemaLegacyPointer(value: *SemaNonNullItem)->#nonull *SemaNonNullItem => value

func semaNonNullConstruction()
{
    var first  = SemaNonNullItem{value: 11}
    var second = SemaNonNullItem{value: 22}
    var blockStorage: [2] SemaNonNullItem = [{value: 31}, {value: 32}]
    var cstringStorage: [4] u8 = ['a''u8, 'b''u8, 'c''u8, 0]

    let direct: #nonull *SemaNonNullItem = &first
    let readOnly: #nonull const *SemaNonNullItem = &first
    let block: #nonull [*] SemaNonNullItem = cast([*] SemaNonNullItem) &blockStorage[0]
    let slice: #nonull [..] SemaNonNullItem = blockStorage
    let text: #nonull string = "nonull"
    let ctext: #nonull cstring = cast(cstring) &cstringStorage[0]
    let boxed: #nonull any = 123
    let reflectedType: #nonull typeinfo = SemaNonNullItem
    let legacyOpCast: #nonull string = SemaNonNullLegacyOpCastBox{}
    let widenedRequiredOpCast: #null string = SemaNonNullRequiredOpCastBox{}
    let aliasReadOnly: const SemaNonNullPointerAlias = &first
    let aliasRequired: #nonull SemaConstPointerAlias = &first
    #assert(#typeof(direct) == #nonull *SemaNonNullItem)
    #assert(#typeof(readOnly) == #nonull const *SemaNonNullItem)
    #assert(#typeof(block) == #nonull [*] SemaNonNullItem)
    #assert(#typeof(slice) == #nonull [..] SemaNonNullItem)
    #assert(#typeof(text) == #nonull string)
    #assert(#typeof(ctext) == #nonull cstring)
    #assert(#typeof(boxed) == #nonull any)
    #assert(#typeof(reflectedType) == #nonull typeinfo)
    #assert(#typeof(legacyOpCast) == #nonull string)
    #assert(#typeof(widenedRequiredOpCast) == #null string)
    #assert(#typeof(aliasReadOnly) == #nonull const *SemaNonNullItem)
    #assert(#typeof(aliasRequired) == #nonull const *SemaNonNullItem)

    var defaultItem: SemaNonNullStringDefault
    var defaultArray: [2] SemaNonNullStringDefault
    let omittedDefaults = SemaNonNullDefaultContainer{}
    let partialDefaults: [2] SemaNonNullStringDefault = [{value: "explicit"}]

    // A legacy pointer can migrate to '#nonull', and '#nonull' can widen to '#null'.
    let legacySource: *SemaNonNullItem = &first
    let migrated: #nonull *SemaNonNullItem = migrateSemaLegacyPointer(legacySource)
    let widened: #null *SemaNonNullItem = migrated
    let completeSet = cast(SemaNonNullCompleteSet) &first
    let genericRequired: SemaNonNullGenericBox'(#nonull *SemaNonNullItem) = {value: &first}
    var genericDefault: SemaNonNullGenericBox'SemaNonNullStringDefault
    #assert(#typeof(migrated) == #nonull *SemaNonNullItem)
    #assert(#typeof(widened) == #null *SemaNonNullItem)
    #assert(#typeof(completeSet.required) == #nonull *SemaNonNullItem)
    #assert(#typeof(genericRequired.value) == #nonull *SemaNonNullItem)
    #assert(#typeof(genericDefault.value) == SemaNonNullStringDefault)

    let holder = SemaNonNullHolder{required: &first}
    var moveSource = SemaNonNullHolder{required: &first}
    let moveTarget = #move moveSource
    let blockHolder = SemaNonNullBlockHolder{required: block}
    let contextual: SemaNonNullHolder = {required: &second, count: 9}
    let nested = SemaNonNullNested{holder: {required: &first}}
    let array: [2] SemaNonNullHolder = [
        {required: &first},
        {required: &second, count: 8},
    ]
    let pointerArray: [2] #nonull *SemaNonNullItem = [&first, &second]
    let aliasedHolder: SemaNonNullHolderAlias = {required: &first}
    let pointerDefault = SemaNonNullPointerDefault{}
    var moveDefaultSource = SemaNonNullMoveDefault{required: "explicit"}
    let moveDefaultTarget = #move moveDefaultSource
    let families = SemaNonNullFamilies{
        valuePointer:  direct,
        blockPointer:  block,
        slice:         slice,
        text:          text,
        ctext:         ctext,
        boxed:         boxed,
        reflectedType: reflectedType,
    }

    let nullableValuePointer: #null *SemaNonNullItem = null
    let nullableBlockPointer: #null [*] SemaNonNullItem = null
    let nullableSlice: #null [..] SemaNonNullItem = null
    let nullableString: #null string = null
    let nullableCString: #null cstring = null
    let nullableTypeInfo: #null typeinfo = null
    let boxedNullableValuePointer: #nonull any = nullableValuePointer
    let boxedNullableBlockPointer: #nonull any = nullableBlockPointer
    let boxedNullableSlice: #nonull any = nullableSlice
    let boxedNullableString: #nonull any = nullableString
    let boxedNullableCString: #nonull any = nullableCString
    let boxedNullableTypeInfo: #nonull any = nullableTypeInfo

    #assert(boxedNullableValuePointer != null)
    #assert(boxedNullableBlockPointer != null)
    #assert(boxedNullableSlice != null)
    #assert(boxedNullableString != null)
    #assert(boxedNullableCString != null)
    #assert(boxedNullableTypeInfo != null)

    acceptSemaNonNullHolder({required: &first})

    var mutable = holder
    @init(mutable)(&second)

    // 'undefined' remains an explicit low-level escape hatch from initialization checks.
    var undefinedPointer: #nonull *SemaNonNullItem = undefined
    var undefinedHolder = SemaNonNullUndefinedHolder{}

    // Explicitly nullable and unannotated pointers retain their legacy defaults.
    var nullableDefault: #null *SemaNonNullItem
    var legacyDefault: *SemaNonNullItem
    var legacyHolder: struct {ptr: *SemaNonNullItem}

    #assert(#typeof(holder.required) == #nonull *SemaNonNullItem)
    #assert(#typeof(moveTarget.required) == #nonull *SemaNonNullItem)
    #assert(#typeof(blockHolder.required) == #nonull [*] SemaNonNullItem)
    #assert(#typeof(holder.optional) == #null *SemaNonNullItem)
    #assert(#typeof(holder.legacy) == *SemaNonNullItem)
    #assert(#typeof(contextual.required) == #nonull *SemaNonNullItem)
    #assert(#typeof(nested.holder.required) == #nonull *SemaNonNullItem)
    #assert(#typeof(array[0].required) == #nonull *SemaNonNullItem)
    #assert(#typeof(pointerArray[0]) == #nonull *SemaNonNullItem)
    #assert(#typeof(aliasedHolder) == SemaNonNullHolder)
    #assert(#typeof(aliasedHolder.required) == #nonull *SemaNonNullItem)
    #assert(#typeof(pointerDefault.required) == #nonull const [*] u8)
    #assert(#typeof(moveDefaultSource.required) == #nonull string)
    #assert(#typeof(moveDefaultTarget.required) == #nonull string)
    #assert(#typeof(families.valuePointer) == #nonull *SemaNonNullItem)
    #assert(#typeof(families.blockPointer) == #nonull [*] SemaNonNullItem)
    #assert(#typeof(families.slice) == #nonull [..] SemaNonNullItem)
    #assert(#typeof(families.text) == #nonull string)
    #assert(#typeof(families.ctext) == #nonull cstring)
    #assert(#typeof(families.boxed) == #nonull any)
    #assert(#typeof(families.reflectedType) == #nonull typeinfo)
    #assert(#typeof(mutable.required) == #nonull *SemaNonNullItem)
    #assert(#typeof(undefinedPointer) == #nonull *SemaNonNullItem)
    #assert(#typeof(undefinedHolder.required) == #nonull *SemaNonNullItem)
    #assert(#typeof(nullableDefault) == #null *SemaNonNullItem)
    #assert(#typeof(legacyDefault) == *SemaNonNullItem)
    #assert(#typeof(legacyHolder.ptr) == *SemaNonNullItem)
}
