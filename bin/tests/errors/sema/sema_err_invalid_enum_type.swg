#global fileprivate

enum B: void {} // swc-expected-error {{sema_err_invalid_enum_type}}
enum J: any {} // swc-expected-error {{sema_err_invalid_enum_type}}
enum K: cstring {} // swc-expected-error {{sema_err_invalid_enum_type}}
