#global private
/**
Swag separates three concerns:

- fallible functions propagate error values with 'fail', 'try', and 'catch';
- runtime safety guards detect invalid operations in generated code;
- static sanity checks reject faults the compiler can prove;
- warnings report code that compiles but is very likely a mistake.

Build configuration selects defaults, and attributes can narrow them for a
declaration or scope.
*/
