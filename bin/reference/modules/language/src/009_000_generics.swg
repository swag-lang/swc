#global private
/**
Generics accept types and compile-time values. Swag specializes a generic when
it is used, then applies 'where' constraints to decide whether the candidate is
valid. Prefer constraints that describe required capabilities rather than
testing a concrete type name.
*/
