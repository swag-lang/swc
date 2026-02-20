#assert(cast #bit (s32) 9)
#assert(cast #unconst (s32) 9)
#assert(cast #err (s32) 9)
#assert(cast #noerr (s32) 9)
#assert(cast #prom (s32) 9)
#assert(cast #wrap (s32) 9)
#assert(cast #nodrop (s32) 9)
#assert(cast #constref (s32) 9)
#assert(cast #reverse (s32) 9)
#assert(cast #move (s32) 9)
#assert(cast #moveraw (s32) 9)
#assert(cast #null (s32) 9)
#assert(cast #ref (s32) 9)

#assert(cast #bit #unconst (s32) 9)
#assert(cast #bit #unconst #err (s32) 9)

var a = #toto // swc-expected-error {{parser_err_invalid_compiler}}
var a = @toto(6) // swc-expected-error {{parser_err_invalid_intrinsic}}
var a = me.@t // swc-expected-error {{parser_err_invalid_intrinsic}}