#global fileprivate // swc-option sema-only

const SelfBytes = #include(#file)

#assert(#typeof(SelfBytes) == [@countof(SelfBytes)] u8)

#assert(@countof(SelfBytes) > 16)
#assert(SelfBytes[0] == '#''u8)
#assert(SelfBytes[1] == 'g''u8)

#test { const bad = #include(1) } // swc-expected-error {{sema_err_invalid_type}}
#test { const missing = #include("missing.include") } // swc-expected-error {{cmdline_err_invalid_file}}
