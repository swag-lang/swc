#global private

// A global with no initializer, or with an all-zero one, lives in the zero segment, which
// the native backend emits as '.bss': the artifact stores its size and none of its bytes.
// Compile-time execution can still write it, and the JIT half of the build reads the value
// back, so the two halves of the language disagree unless the write is refused. '= undefined'
// is the spelling that makes such a global keep what '#run' wrote.
//
// One case per file: the refused write ends the '#run' body, so a second block in the same
// file never reaches sema. Writing a field or an array element of such a global is refused
// the same way, through the same root walk.
var g_scalar: s32

#run
{
    g_scalar = 7     // swc-expected-error {{sema_err_compile_time_global_write_dropped}}
}
