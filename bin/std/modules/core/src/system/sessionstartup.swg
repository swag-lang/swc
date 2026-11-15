#global public
#global namespace Env

// Enables or removes a current-user desktop-session startup entry for an application.
//
// Uses the current executable and separate argument values. Id follows the rules of
// [[Core.Env.SessionInstance.acquire]]. Returns false for sandbox refusal, invalid inputs
// or registration errors. Disabling removes only this id's registration. The caller makes
// this persistent system change only after an explicit user choice; it needs no elevation.
// The display name is nonempty UTF-8 text on one line; arguments are UTF-8 without NUL,
// carriage returns or newlines. A failed update retains the previous registration.
#[Swag.Discardable]
func setSessionStartup(id, displayName: string, enabled: bool, arguments: const [..] string = [])->bool
{
    if denySystemMutation(.AutoStart) or
       not validSessionApplicationId(id) or
       displayName.count == 0 or
       not Utf8.isValid(displayName) do
        return false
    for value in arguments
    {
        if not Utf8.isValid(value) do
            return false
        for byte in value where byte == 0 or byte == '\n' or byte == '\r' do
            return false
    }

    for byte in displayName where byte < 32 do
        return false
    return catch setSessionStartupNative(id, displayName, enabled, arguments) { return false }
}
