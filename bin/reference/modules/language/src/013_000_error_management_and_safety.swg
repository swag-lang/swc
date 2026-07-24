#global private
/**
Swag separates three concerns:

- throwable functions propagate error values with 'throw', 'try', and 'catch';
- runtime safety guards detect invalid operations in generated code;
- static sanity checks reject faults the compiler can prove.

Build configuration selects defaults, and attributes can narrow them for a
declaration or scope.
*/
