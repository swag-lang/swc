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
| 'callconv' | ABI: '.Swag' by default, '.C', or '.WindowsX64' |

A Swag declaration is Swag-convention unless it says otherwise, and
'#[Swag.Foreign]' only states where a function comes from. A function of a
native library therefore names 'Swag.CallConv.C' itself.

A generated module API is the one place where 'module' is left out: it names
the module the API file describes, and 'function' then defaults to the
flattened public API name instead of the declaration name.

'#foreignlib' registers the corresponding import library with the native
linker. It does not declare functions by itself.
*/

#foreignlib("kernel32")

#[Swag.Foreign(module: "kernel32", callconv: Swag.CallConv.C)]
{
    func GetCurrentProcessId()->u32
    func Sleep(milliseconds: u32)
}

#test
{
    Swag.assert(GetCurrentProcessId() != 0)
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
