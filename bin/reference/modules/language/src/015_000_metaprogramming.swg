#global private
/**
# Metaprogramming

Swag can transform code at the call site with mixins and macros, inject source
from '#ast', or add module-wide declarations through the compiler interface.

Prefer the narrowest mechanism that fits the job: a generic for type-safe
reuse, a macro for caller-context expressions, a mixin for injected statements
or declarations, '#ast' for local generated syntax, and 'compileString' for
event-driven module generation.
*/
