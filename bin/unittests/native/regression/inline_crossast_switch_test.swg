#global private

// This #test is NOT in the InlineSw namespace and lives in a different file (=> different Ast)
// than SwClassifier.classify. When classify() is inlined here, its switch's case labels (the bare
// enum values A/B/C) must keep resolving against InlineSw.SwKind across the cross-Ast inline.

#test
{
    var c: InlineSw.SwClassifier
    c.bias = 1
    @assert(c.classify(InlineSw.SwKind.A) == 11)
    @assert(c.classify(InlineSw.SwKind.B) == 21)
    @assert(c.classify(InlineSw.SwKind.C) == 31)
}
