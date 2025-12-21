#global internal

enum A: u32 {}

enum B: void {} // swc-expected-error {{sema_err_invalid_enum_type}}

// swc-expected-error@* {{sema_err_already_defined}}
enum C: u32 {}
enum C: f32 {}

