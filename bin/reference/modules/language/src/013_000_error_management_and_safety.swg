#global private
/**
Swag separates four concerns:

- fallible functions propagate error values with 'fail', 'try', and 'catch';
- runtime safety guards detect invalid operations in generated code;
- static sanity checks reject faults the compiler can prove;
- the borrow rules reject programs where a view outlives what it views;
- warnings report code that compiles but is very likely a mistake.

Build configuration selects defaults for the first three, and attributes can narrow
them for a declaration or scope. The borrow rules are different in kind: they are part
of the language and no attribute or build configuration turns them off.
*/
