#global private

// Same access modifier repeated, and two different access modifiers stacked, are both rejected.
public public func f1() {}                     // swc-expected-error {{parser_err_duplicated_modifier}}
public private func f2() {}                // swc-expected-error {{parser_err_duplicate_modifier}}
private internal func f3() {}         // swc-expected-error {{parser_err_duplicate_modifier}}
internal internal func f4() {}       // swc-expected-error {{parser_err_duplicated_modifier}}

// A member access block cannot contain another visibility level, whether it repeats or changes
// the enclosing level. Only bare 'readonly' can layer another restriction there.
struct NestedLevel
{
    public
    {
        public a: s32              // swc-expected-error {{parser_err_nested_member_access}}
        public readonly n: s32     // swc-expected-error {{parser_err_nested_member_access}}
        internal b: s32            // swc-expected-error {{parser_err_nested_member_access}}
        private c: s32             // swc-expected-error {{parser_err_nested_member_access}}
    }

    internal
    {
        public d: s32       // swc-expected-error {{parser_err_nested_member_access}}
        internal e: s32     // swc-expected-error {{parser_err_nested_member_access}}
        private f: s32      // swc-expected-error {{parser_err_nested_member_access}}
    }

    private
    {
        public g: s32       // swc-expected-error {{parser_err_nested_member_access}}
        internal h: s32     // swc-expected-error {{parser_err_nested_member_access}}
        private i: s32      // swc-expected-error {{parser_err_nested_member_access}}
    }

    readonly
    {
        public j: s32       // swc-expected-error {{parser_err_nested_member_access}}
        internal k: s32     // swc-expected-error {{parser_err_nested_member_access}}
        private l: s32      // swc-expected-error {{parser_err_nested_member_access}}
        readonly m: s32    // swc-expected-error {{parser_err_duplicated_modifier}}
    }
}

public
{
    // Declaration blocks and impls are different: repeating the level is rejected, while a
    // different level remains a deliberate local override.
    public func f5() {}      // swc-expected-error {{parser_err_duplicated_modifier}}
    internal func f6() {}
    private func f7() {}
}

// An impl-level modifier governs every method in the impl just like an explicit access block.
private impl NestedLevel
{
    public mtd f8() {}
    internal mtd f9() {}
    private mtd f10() {}    // swc-expected-error {{parser_err_duplicated_modifier}}
}
