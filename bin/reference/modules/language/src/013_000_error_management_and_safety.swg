#global private
/**
Swag separates five concerns:

- fallible functions propagate error values with 'fail', 'try', and 'catch';
- runtime safety guards detect invalid operations in generated code;
- static sanity checks reject faults the compiler can prove;
- the borrow rules reject programs where a view outlives what it views;
- warnings report code that compiles but is very likely a mistake.

Build configuration selects defaults for runtime guards, static sanity checks, and warnings;
attributes can narrow those defaults for a declaration or scope. Fallible calls must always
be handled. The borrow rules are also part of the language: no attribute or build
configuration turns them off.
*/
