#global private

struct OrelseNonNullItem
{
    value: u32
}

#[Swag.Strict]
alias OrelseNullablePointerAlias = #null *OrelseNonNullItem

#[Swag.Strict]
alias OrelseNullableStringAlias = #null string

#[Swag.Strict]
alias OrelseRequiredPointerAlias = #nonull *OrelseNonNullItem

const NullablePresentType: #null typeinfo = s32
const NullableMissingType: #null typeinfo = null
const RequiredFallbackType: #nonull typeinfo = u64
const FoldedPresentType = NullablePresentType orelse RequiredFallbackType
const FoldedFallbackType = NullableMissingType orelse RequiredFallbackType

#assert(#typeof(FoldedPresentType) == #nonull typeinfo)
#assert(#typeof(FoldedFallbackType) == #nonull typeinfo)
#assert(FoldedPresentType == s32)
#assert(FoldedFallbackType == u64)

func checkValuePointerTypes(nullable: #null *OrelseNonNullItem, fallback: *OrelseNonNullItem, required: #nonull *OrelseNonNullItem)
{
    let legacyResult   = nullable orelse fallback
    let requiredResult = nullable orelse required
    let nullableResult = nullable orelse nullable
    let nullResult     = nullable orelse null

    #assert(#typeof(legacyResult) == *OrelseNonNullItem)
    #assert(#typeof(requiredResult) == #nonull *OrelseNonNullItem)
    #assert(#typeof(nullableResult) == #null *OrelseNonNullItem)
    #assert(#typeof(nullResult) == #null *OrelseNonNullItem)
}

func checkBlockPointerTypes(nullable: #null [*] OrelseNonNullItem, fallback: [*] OrelseNonNullItem, required: #nonull [*] OrelseNonNullItem)
{
    let legacyResult   = nullable orelse fallback
    let requiredResult = nullable orelse required
    let nullableResult = nullable orelse nullable

    #assert(#typeof(legacyResult) == [*] OrelseNonNullItem)
    #assert(#typeof(requiredResult) == #nonull [*] OrelseNonNullItem)
    #assert(#typeof(nullableResult) == #null [*] OrelseNonNullItem)
}

func checkSliceTypes(nullable: #null [..] OrelseNonNullItem, fallback: [..] OrelseNonNullItem, required: #nonull [..] OrelseNonNullItem)
{
    let legacyResult   = nullable orelse fallback
    let requiredResult = nullable orelse required
    let nullableResult = nullable orelse nullable

    #assert(#typeof(legacyResult) == [..] OrelseNonNullItem)
    #assert(#typeof(requiredResult) == #nonull [..] OrelseNonNullItem)
    #assert(#typeof(nullableResult) == #null [..] OrelseNonNullItem)
}

func checkStringTypes(nullable: #null string, fallback: string, required: #nonull string)
{
    let legacyResult   = nullable orelse fallback
    let requiredResult = nullable orelse required
    let nullableResult = nullable orelse nullable

    #assert(#typeof(legacyResult) == string)
    #assert(#typeof(requiredResult) == #nonull string)
    #assert(#typeof(nullableResult) == #null string)
}

func checkCStringTypes(nullable: #null cstring, fallback: cstring, required: #nonull cstring)
{
    let legacyResult   = nullable orelse fallback
    let requiredResult = nullable orelse required
    let nullableResult = nullable orelse nullable

    #assert(#typeof(legacyResult) == cstring)
    #assert(#typeof(requiredResult) == #nonull cstring)
    #assert(#typeof(nullableResult) == #null cstring)
}

func checkAnyTypes(nullable: #null any, fallback: any, required: #nonull any)
{
    let legacyResult   = nullable orelse fallback
    let requiredResult = nullable orelse required
    let nullableResult = nullable orelse nullable

    #assert(#typeof(legacyResult) == any)
    #assert(#typeof(requiredResult) == #nonull any)
    #assert(#typeof(nullableResult) == #null any)
}

func checkTypeInfoTypes(nullable: #null typeinfo, fallback: typeinfo, required: #nonull typeinfo)
{
    let legacyResult   = nullable orelse fallback
    let requiredResult = nullable orelse required
    let nullableResult = nullable orelse nullable

    #assert(#typeof(legacyResult) == typeinfo)
    #assert(#typeof(requiredResult) == #nonull typeinfo)
    #assert(#typeof(nullableResult) == #null typeinfo)
}

func checkAliasOrelseTypes(nullablePointer: OrelseNullablePointerAlias, requiredPointer: #nonull *OrelseNonNullItem, nullableText: OrelseNullableStringAlias, requiredText: #nonull string)
{
    let requiredPointerResult = nullablePointer orelse requiredPointer
    let requiredTextResult    = nullableText orelse requiredText

    #assert(#typeof(requiredPointerResult) == #nonull *OrelseNonNullItem)
    #assert(#typeof(requiredTextResult) == #nonull string)
}

func checkConditionalNullabilityJoin(flag: bool, legacy: *OrelseNonNullItem, nullable: #null *OrelseNonNullItem, required: #nonull *OrelseNonNullItem, aliasNullable: OrelseNullablePointerAlias, aliasRequired: OrelseRequiredPointerAlias)
{
    let legacyFirst            = flag ? legacy : required
    let legacySecond           = flag ? required : legacy
    let nullableFirst          = flag ? nullable : required
    let nullableLast           = flag ? required : nullable
    let nullFirst              = flag ? null : required
    let nullLast               = flag ? required : null
    let requiredOnly           = flag ? required : required
    let aliasNullableFirst     = flag ? aliasNullable : required
    let aliasNullableLast      = flag ? required : aliasNullable
    let nullAliasRequiredFirst = flag ? null : aliasRequired
    let nullAliasRequiredLast  = flag ? aliasRequired : null

    #assert(#typeof(legacyFirst) == *OrelseNonNullItem)
    #assert(#typeof(legacySecond) == *OrelseNonNullItem)
    #assert(#typeof(nullableFirst) == #null *OrelseNonNullItem)
    #assert(#typeof(nullableLast) == #null *OrelseNonNullItem)
    #assert(#typeof(nullFirst) == #null *OrelseNonNullItem)
    #assert(#typeof(nullLast) == #null *OrelseNonNullItem)
    #assert(#typeof(requiredOnly) == #nonull *OrelseNonNullItem)
    #assert(#typeof(aliasNullableFirst) == OrelseNullablePointerAlias)
    #assert(#typeof(aliasNullableLast) == OrelseNullablePointerAlias)
    #assert(#typeof(nullAliasRequiredFirst) == #null *OrelseNonNullItem)
    #assert(#typeof(nullAliasRequiredLast) == #null *OrelseNonNullItem)
}
