#global public
#global namespace Input

using Swag

// Identifies a mouse button.
enum MouseButton
{
    Left         // Left button
    Middle       // Middle button, usually the wheel
    Right        // Right button
    XButton1     // First extra button, usually Back
    XButton2     // Second extra button, usually Forward
}

// Returns the button whose stored enum value matches an index into mouse state arrays.
public func mouseButtonFromStorageIndex(index: u64)->MouseButton
{
    if index >= MouseButton.count do
        Swag.panic("invalid mouse button storage index", #curlocation)

    let typeEnum = assume cast(const *TypeInfoEnum, #typeof(MouseButton))
    let value    = cast(s32, index)
    for &caseInfo in typeEnum.values where caseInfo.value do
        if cast(const *s32, unwrap caseInfo.value)[] == value do
            return cast(const *MouseButton, unwrap caseInfo.value)[]

    Swag.panic("mouse button enum values do not match storage indexes", #curlocation)
}
