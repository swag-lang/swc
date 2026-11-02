#global if #os == Swag.TargetOs.Linux
#global public
#global namespace Env

internal func processEnvironmentStoredName(name: string)->String => String.from(name)

// Exits the current process; the parent observes the low eight bits of `exitCode`.
#[Swag.NoReturn]
func exit(exitCode: s32) => Linux.exit(exitCode)

// Returns a copy of the current process environment variable `name`.
//
// Names are case-sensitive. An unset variable, an empty value, or an invalid name returns
// an empty string. The caller must synchronize this with any concurrent environment mutation.
func variable(name: string)->String
{
    if not name.count do
        return ""
    for byte in name where byte == 0 or byte == '=' do
        return ""
    let native = String.from(name)
    let value  = Linux.getenv(native.storage())
    if not value do
        return ""
    return String.from(cast(string, cast(cstring, value)))
}
