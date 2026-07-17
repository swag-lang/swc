#global private
#global #[Swag.ExplicitNullability]

struct ExplicitNullabilityErrorItem
{
}

// swc-expected-error@* {{must be explicitly declared}}
alias MissingValuePointer = *ExplicitNullabilityErrorItem
// swc-expected-error@* {{must be explicitly declared}}
alias MissingBlockPointer = [*] ExplicitNullabilityErrorItem
// swc-expected-error@* {{must be explicitly declared}}
alias MissingSlice = [..] ExplicitNullabilityErrorItem
// swc-expected-error@* {{must be explicitly declared}}
alias MissingString = string
// swc-expected-error@* {{must be explicitly declared}}
alias MissingCString = cstring
// swc-expected-error@* {{must be explicitly declared}}
alias MissingAny = any
// swc-expected-error@* {{must be explicitly declared}}
alias MissingTypeInfo = typeinfo

struct ExplicitNullabilityErrorHolder
{
    // swc-expected-error@* {{must be explicitly declared}}
    valuePointer:  *ExplicitNullabilityErrorItem
}
