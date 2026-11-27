#global private
/**
Generics accept types and compile-time values. Swag specializes a generic when
it is used, then applies 'where' constraints to decide whether the candidate is
valid. Prefer constraints that describe required capabilities rather than
testing a concrete type name.

Write explicit generic arguments in braces after `!`, as in
`readValue!{ConstantValue}(&value)`. The delimiter keeps type and value arguments
visually separate from character literals; numeric literal suffixes use `_`, as
in `42_u32`.
*/
