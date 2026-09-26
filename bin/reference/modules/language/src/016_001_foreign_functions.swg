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

A Swag declaration uses the Swag ABI unless it says otherwise. A function of a
native library names 'Swag.CallConv.C' in 'Foreign', or inherits it from an
enclosing 'Swag.CallingConvention(.C)' scope. Function values and callbacks
crossing the native boundary also need that convention:

```swag
#[Swag.CallingConvention(.C)]
alias NativeCallback = func(u64, u64, u64, u64, f32)->u32

#[Swag.CallingConvention(.C)]
func onNativeEvent(a: u64, b: u64, c: u64, d: u64, value: f32)->u32
{
    return value > 0 ? 1 : 0
}
```

The attribute may also decorate a struct of native vtable entries or a scope
containing native callbacks. Ordinary Swag function values retain the Swag ABI.

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
func openVendorHandle(flags: u32)->*void?
```

The declaration is an ABI contract, not a conversion layer. A mismatched
parameter type, struct layout, calling convention, or nullability annotation
can corrupt memory even when the code compiles.

'.C' selects the target platform's C ABI, which is also the callback ABI of
the Windows APIs shown here. It is not a promise that every external API uses
the C ABI on every architecture; use the ABI specified by that API.
*/
