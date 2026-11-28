#global namespace Input

// Identifies digital buttons and analog controls on a gamepad.
public enum GamepadButton
{
    A                        // Bottom face button
    B                        // Right face button
    Back                     // Back or View button
    BigButton                // Guide button, which the XInput backend never reports
    DPadDown                 // Directional pad down
    DPadLeft                 // Directional pad left
    DPadRight                // Directional pad right
    DPadUp                   // Directional pad up
    LeftShoulder             // Left shoulder button
    LeftStick                // Left stick: pressed when clicked, position on both axes
    LeftThumbstickDown       // Left stick pushed down past the activation threshold
    LeftThumbstickLeft       // Left stick pushed left past the activation threshold
    LeftThumbstickRight      // Left stick pushed right past the activation threshold
    LeftThumbstickUp         // Left stick pushed up past the activation threshold
    LeftTrigger              // Left trigger: pressed past the activation threshold, travel on `y`
    RightShoulder            // Right shoulder button
    RightStick               // Right stick: pressed when clicked, position on both axes
    RightThumbstickDown      // Right stick pushed down past the activation threshold
    RightThumbstickLeft      // Right stick pushed left past the activation threshold
    RightThumbstickRight     // Right stick pushed right past the activation threshold
    RightThumbstickUp        // Right stick pushed up past the activation threshold
    RightTrigger             // Right trigger: pressed past the activation threshold, travel on `y`
    Start                    // Start or Menu button
    X                        // Left face button
    Y                        // Top face button
}
