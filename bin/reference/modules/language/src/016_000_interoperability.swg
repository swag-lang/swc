#global private
/**
Swag interoperates with native libraries through the target C ABI. Keep the
boundary explicit: match the external declaration exactly, use fixed-width
types, model nullability, and keep ownership rules in a small wrapper that
presents ordinary Swag types to the rest of the program.

The current native toolchain targets Windows x86-64. The examples in this
chapter therefore use Windows system libraries while keeping the ABI guidance
portable.
*/
