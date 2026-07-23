#global private

struct SemaNonNullItem
{
    value: s32
}

struct SemaNonNullLegacyOpCastBox {}

impl SemaNonNullLegacyOpCastBox
{
    #[Swag.ConstExpr, Swag.Implicit]
    mtd const opCast()->string => "legacy-op-cast"
}

struct SemaNonNullRequiredOpCastBox {}

impl SemaNonNullRequiredOpCastBox
{
    #[Swag.ConstExpr, Swag.Implicit]
    mtd const opCast()->string => "required-op-cast"
}

alias SemaNonNullPointerAlias = *SemaNonNullItem
alias SemaConstPointerAlias   = const *SemaNonNullItem

const SEMA_NONULL_POINTER_DEFAULT_TEXT = "fallback"

const SEMA_NONULL_NULL_VALUE_POINTER: #null *void    = null
const SEMA_NONULL_PRESENT_VALUE_POINTER              = cast(*void) 1'u64
const SEMA_NONULL_NULL_BLOCK_POINTER: #null [*] void = null
const SEMA_NONULL_PRESENT_BLOCK_POINTER              = cast([*] void) 1'u64

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
    value: string = "fallback"
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
const SEMA_NONULL_PARTIAL_ARRAY: [2] SemaNonNullStringDefault    = [{value: "explicit"}]

#assert(SEMA_NONULL_DEFAULT_CONTAINER.direct.value == "fallback")
#assert(SEMA_NONULL_DEFAULT_CONTAINER.array[0].value == "fallback")
#assert(SEMA_NONULL_DEFAULT_CONTAINER.array[1].value == "fallback")
#assert(SEMA_NONULL_DEFAULT_CONTAINER.aliased.value == "fallback")
#assert(SEMA_NONULL_PARTIAL_ARRAY[0].value == "explicit")
#assert(SEMA_NONULL_PARTIAL_ARRAY[1].value == "fallback")

struct SemaNonNullHolder
{
    required: *SemaNonNullItem
    optional: #null *SemaNonNullItem
    legacy:   #null *SemaNonNullItem
    count:    s32 = 7
}

alias SemaNonNullHolderAlias = SemaNonNullHolder

struct SemaNonNullPointerDefault
{
    required: const [*] u8 = @dataof(SEMA_NONULL_POINTER_DEFAULT_TEXT)
}

struct SemaNonNullMoveDefault
{
    required: string = "move-default"
}

impl SemaNonNullMoveDefault
{
    mtd opDrop() {}
}

struct SemaNonNullUndefinedHolder
{
    required: *SemaNonNullItem = undefined
}

struct SemaNonNullBlockHolder
{
    required: [*] SemaNonNullItem
}

struct SemaNonNullFamilies
{
    valuePointer:  *SemaNonNullItem
    blockPointer:  [*] SemaNonNullItem
    slice:         [..] SemaNonNullItem
    text:          string
    ctext:         cstring
    boxed:         any
    reflectedType: typeinfo
}

struct SemaNonNullNested
{
    holder: SemaNonNullHolder
}

struct SemaNonNullCompleteSet
{
    required: *SemaNonNullItem
}

impl SemaNonNullCompleteSet
{
    #[Swag.Complete]
    mtd opSet(value: *SemaNonNullItem)
    {
        .required = value
    }
}

func acceptSemaNonNullHolder(value: SemaNonNullHolder) {}

func migrateSemaLegacyPointer(value: *SemaNonNullItem)->*SemaNonNullItem => value

func semaNonNullConstruction()
{
    var first  = SemaNonNullItem{value: 11}
    var second = SemaNonNullItem{value: 22}
    var blockStorage:   [2] SemaNonNullItem = [{value: 31}, {value: 32}]
    var cstringStorage: [4] u8 = ['a''u8, 'b''u8, 'c''u8, 0]

    let direct:                *SemaNonNullItem = &first
    let readOnly:              const *SemaNonNullItem = &first
    let block:                 [*] SemaNonNullItem = cast([*] SemaNonNullItem) &blockStorage[0]
    let slice:                 [..] SemaNonNullItem = blockStorage
    let text:                  string = "nonull"
    let ctext:                 cstring = cast(cstring) &cstringStorage[0]
    let boxed:                 any = 123
    let reflectedType:         typeinfo = SemaNonNullItem
    let legacyOpCast:          string = SemaNonNullLegacyOpCastBox{}
    let widenedRequiredOpCast: #null string = SemaNonNullRequiredOpCastBox{}
    let aliasReadOnly:         const SemaNonNullPointerAlias = &first
    let aliasRequired:         SemaConstPointerAlias = &first
    #assert(#typeof(direct) == *SemaNonNullItem)
    #assert(#typeof(readOnly) == const *SemaNonNullItem)
    #assert(#typeof(block) == [*] SemaNonNullItem)
    #assert(#typeof(slice) == [..] SemaNonNullItem)
    #assert(#typeof(text) == string)
    #assert(#typeof(ctext) == cstring)
    #assert(#typeof(boxed) == any)
    #assert(#typeof(reflectedType) == typeinfo)
    #assert(#typeof(legacyOpCast) == string)
    #assert(#typeof(widenedRequiredOpCast) == #null string)
    #assert(#typeof(aliasReadOnly) == const *SemaNonNullItem)
    #assert(#typeof(aliasRequired) == const *SemaNonNullItem)

    var defaultItem:  SemaNonNullStringDefault
    var defaultArray: [2] SemaNonNullStringDefault
    let omittedDefaults = SemaNonNullDefaultContainer{}
    let partialDefaults: [2] SemaNonNullStringDefault = [{value: "explicit"}]

    // A bare (non-null) pointer can widen to '#null'.
    let legacySource: *SemaNonNullItem = &first
    let migrated:     *SemaNonNullItem = migrateSemaLegacyPointer(legacySource)
    var widened:      #null *SemaNonNullItem = migrated
    widened = null     // the qualifier is real: null flows into it below
    widened = migrated
    let completeSet = cast(SemaNonNullCompleteSet) &first
    let genericRequired: SemaNonNullGenericBox'(*SemaNonNullItem) = {value: &first}
    var genericDefault:  SemaNonNullGenericBox'SemaNonNullStringDefault
    #assert(#typeof(migrated) == *SemaNonNullItem)
    #assert(#typeof(widened) == #null *SemaNonNullItem)
    #assert(#typeof(completeSet.required) == *SemaNonNullItem)
    #assert(#typeof(genericRequired.value) == *SemaNonNullItem)
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
    let pointerArray:  [2] *SemaNonNullItem = [&first, &second]
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

    let nullableValuePointer:      #null *SemaNonNullItem = null
    let nullableBlockPointer:      #null [*] SemaNonNullItem = null
    let nullableSlice:             #null [..] SemaNonNullItem = null
    let nullableString:            #null string = null
    let nullableCString:           #null cstring = null
    let nullableTypeInfo:          #null typeinfo = null
    let boxedNullableValuePointer: any = nullableValuePointer
    let boxedNullableBlockPointer: any = nullableBlockPointer
    let boxedNullableSlice:        any = nullableSlice
    let boxedNullableString:       any = nullableString
    let boxedNullableCString:      any = nullableCString
    let boxedNullableTypeInfo:     any = nullableTypeInfo

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
    var undefinedPointer: *SemaNonNullItem = undefined
    var undefinedHolder = SemaNonNullUndefinedHolder{}

    // Explicitly nullable pointers retain their default.
    var nullableDefault: #null *SemaNonNullItem
    var legacyDefault:   #null *SemaNonNullItem
    var legacyHolder:    struct {ptr: #null *SemaNonNullItem}

    #assert(#typeof(holder.required) == *SemaNonNullItem)
    #assert(#typeof(moveTarget.required) == *SemaNonNullItem)
    #assert(#typeof(blockHolder.required) == [*] SemaNonNullItem)
    #assert(#typeof(holder.optional) == #null *SemaNonNullItem)
    #assert(#typeof(holder.legacy) == #null *SemaNonNullItem)
    #assert(#typeof(contextual.required) == *SemaNonNullItem)
    #assert(#typeof(nested.holder.required) == *SemaNonNullItem)
    #assert(#typeof(array[0].required) == *SemaNonNullItem)
    #assert(#typeof(pointerArray[0]) == *SemaNonNullItem)
    #assert(#typeof(aliasedHolder) == SemaNonNullHolder)
    #assert(#typeof(aliasedHolder.required) == *SemaNonNullItem)
    #assert(#typeof(pointerDefault.required) == const [*] u8)
    #assert(#typeof(moveDefaultSource.required) == string)
    #assert(#typeof(moveDefaultTarget.required) == string)
    #assert(#typeof(families.valuePointer) == *SemaNonNullItem)
    #assert(#typeof(families.blockPointer) == [*] SemaNonNullItem)
    #assert(#typeof(families.slice) == [..] SemaNonNullItem)
    #assert(#typeof(families.text) == string)
    #assert(#typeof(families.ctext) == cstring)
    #assert(#typeof(families.boxed) == any)
    #assert(#typeof(families.reflectedType) == typeinfo)
    #assert(#typeof(mutable.required) == *SemaNonNullItem)
    #assert(#typeof(undefinedPointer) == *SemaNonNullItem)
    #assert(#typeof(undefinedHolder.required) == *SemaNonNullItem)
    #assert(#typeof(nullableDefault) == #null *SemaNonNullItem)
    #assert(#typeof(legacyDefault) == #null *SemaNonNullItem)
    #assert(#typeof(legacyHolder.ptr) == #null *SemaNonNullItem)
}
