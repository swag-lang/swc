#global namespace Globalization

// Represents culture info.
public struct CultureInfo
{
    numberFormat: NumberFormatInfo // Number format associated with this value.
}

var g_CultureInfo: CultureInfo

// Returns the global culture info structure
public func getCultureInfo()->*CultureInfo
{
    return &g_CultureInfo
}
