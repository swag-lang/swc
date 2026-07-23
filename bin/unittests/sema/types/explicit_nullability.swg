#global private

struct ExplicitNullabilityItem {}

alias ExplicitNullabilityRequiredPtr = *ExplicitNullabilityItem
alias ExplicitNullabilityOptionalString = #null string

struct ExplicitNullabilityHolder
{
    valuePointer:  *ExplicitNullabilityItem
    blockPointer:  [*] ExplicitNullabilityItem
    slice:         [..] ExplicitNullabilityItem
    text:          string
    ctext:         cstring
    boxed:         any
    reflectedType: typeinfo
    optionalText:  #null string
}

func explicitNullabilityAccept(
    valuePointer: *ExplicitNullabilityItem,
    blockPointer: [*] ExplicitNullabilityItem,
    slice: [..] ExplicitNullabilityItem,
    text: string,
    ctext: cstring,
    boxed: any,
    reflectedType: typeinfo,
    optionalText: #null string)
{
    #assert(#typeof(valuePointer) == *ExplicitNullabilityItem)
    #assert(#typeof(blockPointer) == [*] ExplicitNullabilityItem)
    #assert(#typeof(slice) == [..] ExplicitNullabilityItem)
    #assert(#typeof(text) == string)
    #assert(#typeof(ctext) == cstring)
    #assert(#typeof(boxed) == any)
    #assert(#typeof(reflectedType) == typeinfo)
    #assert(#typeof(optionalText) == #null string)
}

func explicitNullabilityReturnAlias(value: ExplicitNullabilityRequiredPtr)->ExplicitNullabilityRequiredPtr => value
