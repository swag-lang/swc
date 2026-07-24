#global private
/**
# Compile-Time Execution

Swag reuses the language for compile-time work. Constant expressions evaluate
pure computations needed by types and declarations; '#run' executes arbitrary
compile-time code; directives select or validate source; '#message' observes
compiler events.

Compile-time execution can generate runtime declarations, but it is still part
of the build. Keep it deterministic, report errors at the source that caused
them, and avoid unnecessary filesystem or environment dependencies.
*/
