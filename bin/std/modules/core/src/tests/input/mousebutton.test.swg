#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

func assertMouseButton(button: Input.MouseButton, index: u32)
{
    Swag.assert(cast(u32) button == index)
}

#test
{
    using Input.MouseButton

    Swag.assert(Input.MouseButton.count == 5)

    assertMouseButton(Left, 0)
    assertMouseButton(Middle, 1)
    assertMouseButton(Right, 2)
    assertMouseButton(XButton1, 3)
    assertMouseButton(XButton2, 4)
}
