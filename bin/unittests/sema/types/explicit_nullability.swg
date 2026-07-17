#global private
#global #[Swag.ExplicitNullability]

struct ExplicitNullabilityItem
{
}

alias ExplicitNullabilityRequiredPtr = #nonull *ExplicitNullabilityItem
alias ExplicitNullabilityOptionalString = #null string

struct ExplicitNullabilityHolder
{
    valuePointer:  #nonull *ExplicitNullabilityItem
    blockPointer:  #nonull [*] ExplicitNullabilityItem
    slice:         #nonull [..] ExplicitNullabilityItem
    text:          #nonull string
    ctext:         #nonull cstring
    boxed:         #nonull any
    reflectedType: #nonull typeinfo
    optionalText:  #null string
}

func explicitNullabilityAccept(
    valuePointer: #nonull *ExplicitNullabilityItem,
    blockPointer: #nonull [*] ExplicitNullabilityItem,
    slice: #nonull [..] ExplicitNullabilityItem,
    text: #nonull string,
    ctext: #nonull cstring,
    boxed: #nonull any,
    reflectedType: #nonull typeinfo,
    optionalText: #null string)
{
    #assert(#typeof(valuePointer) == #nonull *ExplicitNullabilityItem)
    #assert(#typeof(blockPointer) == #nonull [*] ExplicitNullabilityItem)
    #assert(#typeof(slice) == #nonull [..] ExplicitNullabilityItem)
    #assert(#typeof(text) == #nonull string)
    #assert(#typeof(ctext) == #nonull cstring)
    #assert(#typeof(boxed) == #nonull any)
    #assert(#typeof(reflectedType) == #nonull typeinfo)
    #assert(#typeof(optionalText) == #null string)
}

func explicitNullabilityReturnAlias(value: ExplicitNullabilityRequiredPtr)->ExplicitNullabilityRequiredPtr => value
