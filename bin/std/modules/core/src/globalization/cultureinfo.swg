#global namespace Globalization

// Groups the process-wide formatting conventions.
public struct CultureInfo
{
    public numberFormat: NumberFormatInfo     // Numeric formatting conventions.
}

var g_CultureInfo: CultureInfo

// Returns the mutable process-wide culture settings.
public func currentCulture()->*CultureInfo
{
    return &g_CultureInfo
}
