#global internal

var A: #null const bool     // swc-expected-error {{sema_err_bad_type_qualifier}}
var B: const bool           // swc-expected-error {{sema_err_bad_type_qualifier}}
var C: #null bool           // swc-expected-error {{sema_err_bad_type_qualifier}}

var D0: const *s32
var D1: const [..] s32
var D2: const [*] s32

var E0: #null *s32
var E1: #null [..] s32
var E2: #null [*] s32
