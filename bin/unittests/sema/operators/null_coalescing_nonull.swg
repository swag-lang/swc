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
alias OrelseRequiredPointerAlias = *OrelseNonNullItem

const NullablePresentType: #null typeinfo = s32
const NullableMissingType: #null typeinfo = null
const RequiredFallbackType: typeinfo = u64
const FoldedPresentType = NullablePresentType orelse RequiredFallbackType
const FoldedFallbackType = NullableMissingType orelse RequiredFallbackType

#assert(#typeof(FoldedPresentType) == typeinfo)
#assert(#typeof(FoldedFallbackType) == typeinfo)
#assert(FoldedPresentType == s32)
#assert(FoldedFallbackType == u64)

func checkValuePointerTypes(nullable: #null *OrelseNonNullItem, fallback: *OrelseNonNullItem, required: *OrelseNonNullItem)
{
    let legacyResult   = nullable orelse fallback
    let requiredResult = nullable orelse required
    let nullableResult = nullable orelse nullable
    let nullResult     = nullable orelse null

    #assert(#typeof(legacyResult) == *OrelseNonNullItem)
    #assert(#typeof(requiredResult) == *OrelseNonNullItem)
    #assert(#typeof(nullableResult) == #null *OrelseNonNullItem)
    #assert(#typeof(nullResult) == #null *OrelseNonNullItem)
}

func checkBlockPointerTypes(nullable: #null [*] OrelseNonNullItem, fallback: [*] OrelseNonNullItem, required: [*] OrelseNonNullItem)
{
    let legacyResult   = nullable orelse fallback
    let requiredResult = nullable orelse required
    let nullableResult = nullable orelse nullable

    #assert(#typeof(legacyResult) == [*] OrelseNonNullItem)
    #assert(#typeof(requiredResult) == [*] OrelseNonNullItem)
    #assert(#typeof(nullableResult) == #null [*] OrelseNonNullItem)
}

func checkSliceTypes(nullable: #null [..] OrelseNonNullItem, fallback: [..] OrelseNonNullItem, required: [..] OrelseNonNullItem)
{
    let legacyResult   = nullable orelse fallback
    let requiredResult = nullable orelse required
    let nullableResult = nullable orelse nullable

    #assert(#typeof(legacyResult) == [..] OrelseNonNullItem)
    #assert(#typeof(requiredResult) == [..] OrelseNonNullItem)
    #assert(#typeof(nullableResult) == #null [..] OrelseNonNullItem)
}

func checkStringTypes(nullable: #null string, fallback: string, required: string)
{
    let legacyResult   = nullable orelse fallback
    let requiredResult = nullable orelse required
    let nullableResult = nullable orelse nullable

    #assert(#typeof(legacyResult) == string)
    #assert(#typeof(requiredResult) == string)
    #assert(#typeof(nullableResult) == #null string)
}

func checkCStringTypes(nullable: #null cstring, fallback: cstring, required: cstring)
{
    let legacyResult   = nullable orelse fallback
    let requiredResult = nullable orelse required
    let nullableResult = nullable orelse nullable

    #assert(#typeof(legacyResult) == cstring)
    #assert(#typeof(requiredResult) == cstring)
    #assert(#typeof(nullableResult) == #null cstring)
}

func checkAnyTypes(nullable: #null any, fallback: any, required: any)
{
    let legacyResult   = nullable orelse fallback
    let requiredResult = nullable orelse required
    let nullableResult = nullable orelse nullable

    #assert(#typeof(legacyResult) == any)
    #assert(#typeof(requiredResult) == any)
    #assert(#typeof(nullableResult) == #null any)
}

func checkTypeInfoTypes(nullable: #null typeinfo, fallback: typeinfo, required: typeinfo)
{
    let legacyResult   = nullable orelse fallback
    let requiredResult = nullable orelse required
    let nullableResult = nullable orelse nullable

    #assert(#typeof(legacyResult) == typeinfo)
    #assert(#typeof(requiredResult) == typeinfo)
    #assert(#typeof(nullableResult) == #null typeinfo)
}

func checkAliasOrelseTypes(nullablePointer: OrelseNullablePointerAlias, requiredPointer: *OrelseNonNullItem, nullableText: OrelseNullableStringAlias, requiredText: string)
{
    let requiredPointerResult = nullablePointer orelse requiredPointer
    let requiredTextResult    = nullableText orelse requiredText

    #assert(#typeof(requiredPointerResult) == *OrelseNonNullItem)
    #assert(#typeof(requiredTextResult) == string)
}

func checkConditionalNullabilityJoin(flag: bool, legacy: *OrelseNonNullItem, nullable: #null *OrelseNonNullItem, required: *OrelseNonNullItem, aliasNullable: OrelseNullablePointerAlias, aliasRequired: OrelseRequiredPointerAlias)
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
    #assert(#typeof(requiredOnly) == *OrelseNonNullItem)
    #assert(#typeof(aliasNullableFirst) == OrelseNullablePointerAlias)
    #assert(#typeof(aliasNullableLast) == OrelseNullablePointerAlias)
    #assert(#typeof(nullAliasRequiredFirst) == #null *OrelseNonNullItem)
    #assert(#typeof(nullAliasRequiredLast) == #null *OrelseNonNullItem)
}
