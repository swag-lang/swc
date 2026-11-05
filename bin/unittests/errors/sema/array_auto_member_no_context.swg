#global private

enum AutoArrayMode { Off, Fast }

struct(T) AutoArrayBag { dummy: u8 }

impl AutoArrayBag
{
    mtd add(value: #fwd T) {}
    mtd add(values: const [..] T?) {}
}

#test
{
    var bag: AutoArrayBag'AutoArrayMode
    bag.add([.Off, .Fast]) // swc-expected-error {{sema_err_cannot_compute_auto_scope}}
}
