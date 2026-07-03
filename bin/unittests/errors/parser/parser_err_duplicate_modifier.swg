#global private

// Same access modifier repeated, and two different access modifiers stacked, are both rejected.
public public func f1() {}                     // swc-expected-error {{parser_err_duplicate_modifier}}
public private func f2() {}                // swc-expected-error {{parser_err_duplicate_modifier}}
private internal func f3() {}         // swc-expected-error {{parser_err_duplicate_modifier}}
internal internal func f4() {}       // swc-expected-error {{parser_err_duplicate_modifier}}
