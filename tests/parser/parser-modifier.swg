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

#assert(cast #bit #bit (s32) 9) // swc-expected-error {{ParserDuplicatedModifier}}
#assert(cast #ref1 (s32) 9) // swc-expected-error {{ParserInvalidModifier}}
#assert(a + #wrap b)

#assert(a + / b) // swc-expected-error {{ParserUnexpected}}




