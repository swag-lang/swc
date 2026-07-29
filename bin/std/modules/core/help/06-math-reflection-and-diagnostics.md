# Mathematics, reflection, and diagnostics

[[Core.Math]] contains scalar functions, vectors, matrices, rectangles,
transforms, curves, and geometric algorithms. Floating-point comparisons and
normalization helpers make their tolerance explicit; choose the tolerance that
matches the scale of the data rather than relying on exact equality.

[[Core.Reflection]] inspects Swag type information, attributes, fields, enum
cases, and arrays at runtime. Reflection values describe compiled program
metadata. Do not mutate application storage through reflected pointers unless
the API explicitly exposes a writable value.

For program output and diagnostics:

| Purpose | API |
|---|---|
| Terminal input and output | [[Core.Console]] |
| Development assertions | [[Core.Debug]] |
| Debugger interaction | [[Core.Debugger]] |
| Process, arguments, and environment | [[Core.Env]] |
| Hardware information | [[Core.Hardware]] |
| Standard system errors | [[Core.Errors]] |

Assertions protect programmer invariants; they are not a substitute for handling
invalid files, user input, or operating-system failures. Public operations that
can encounter those conditions report them through `fail`.
