#global private

/**
# Foreign Functions

'#[Swag.Foreign]' declares a function implemented outside the Swag module. Its
parameters are:

| Parameter | Meaning |
|---|---|
| 'module' | Dynamic module used to resolve the symbol |
| 'function' | External symbol name; defaults to the Swag declaration name |
| 'link' | Native import-library name when it differs from 'module' |
| 'callconv' | ABI: '.C' by default, '.WindowsX64', or '.Swag' |

'#foreignlib' registers the corresponding import library with the native
linker. It does not declare functions by itself.
*/

#foreignlib("kernel32")

#[Swag.Foreign(module: "kernel32")]
{
    func GetCurrentProcessId()->u32
    func Sleep(milliseconds: u32)
}

#test
{
    @assert(GetCurrentProcessId() != 0)
    Sleep(0)
}

/**
# Renamed Symbols and Separate Link Names

Use 'function' when the local name should differ from the exported symbol. Use
'link' when runtime resolution and native linking use different library names:

```swag
#[Swag.Foreign(
    module: "vendor_runtime",
    function: "vendor_open_v2",
    link: "vendor_import",
    callconv: .C)]
func openVendorHandle(flags: u32)->#null *void
```

The declaration is an ABI contract, not a conversion layer. A mismatched
parameter type, struct layout, calling convention, or nullability annotation
can corrupt memory even when the code compiles.
*/
