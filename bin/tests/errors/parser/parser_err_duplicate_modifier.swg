#global fileprivate

// Same access modifier repeated, and two different access modifiers stacked, are both rejected.
public public func f1() {}                     // swc-expected-error {{parser_err_duplicate_modifier}}
public fileprivate func f2() {}                // swc-expected-error {{parser_err_duplicate_modifier}}
fileprivate moduleprivate func f3() {}         // swc-expected-error {{parser_err_duplicate_modifier}}
moduleprivate moduleprivate func f4() {}       // swc-expected-error {{parser_err_duplicate_modifier}}
