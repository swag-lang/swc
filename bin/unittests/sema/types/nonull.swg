#global private

struct SemaNonNullItem
{
    value: s32
}

alias SemaNonNullPointerAlias = #nonull *SemaNonNullItem
alias SemaConstPointerAlias   = const *SemaNonNullItem

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

struct SemaNonNullUndefinedHolder
{
    required: #nonull *SemaNonNullItem = undefined
}

struct SemaNonNullBlockHolder
{
    required: #nonull [*] SemaNonNullItem
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

func semaNonNullConstruction()
{
    var first  = SemaNonNullItem{value: 11}
    var second = SemaNonNullItem{value: 22}
    var blockStorage: [2] SemaNonNullItem = [{value: 31}, {value: 32}]

    let direct: #nonull *SemaNonNullItem = &first
    let readOnly: #nonull const *SemaNonNullItem = &first
    let block: #nonull [*] SemaNonNullItem = cast([*] SemaNonNullItem) &blockStorage[0]
    let aliasReadOnly: const SemaNonNullPointerAlias = &first
    let aliasRequired: #nonull SemaConstPointerAlias = &first
    #assert(#typeof(direct) == #nonull *SemaNonNullItem)
    #assert(#typeof(readOnly) == #nonull const *SemaNonNullItem)
    #assert(#typeof(block) == #nonull [*] SemaNonNullItem)
    #assert(#typeof(aliasReadOnly) == #nonull const *SemaNonNullItem)
    #assert(#typeof(aliasRequired) == #nonull const *SemaNonNullItem)

    var defaultItem: SemaNonNullStringDefault
    var defaultArray: [2] SemaNonNullStringDefault
    let omittedDefaults = SemaNonNullDefaultContainer{}
    let partialDefaults: [2] SemaNonNullStringDefault = [{value: "explicit"}]

    // A legacy pointer can migrate to '#nonull', and '#nonull' can widen to '#null'.
    let legacySource: *SemaNonNullItem = &first
    let migrated: #nonull *SemaNonNullItem = legacySource
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
    #assert(#typeof(mutable.required) == #nonull *SemaNonNullItem)
    #assert(#typeof(undefinedPointer) == #nonull *SemaNonNullItem)
    #assert(#typeof(undefinedHolder.required) == #nonull *SemaNonNullItem)
    #assert(#typeof(nullableDefault) == #null *SemaNonNullItem)
    #assert(#typeof(legacyDefault) == *SemaNonNullItem)
    #assert(#typeof(legacyHolder.ptr) == *SemaNonNullItem)
}
