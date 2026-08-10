#global namespace Globalization

// Provides culture-specific information for formatting and parsing numeric values.
public struct NumberFormatInfo
{
    public
    {
        // The byte that denotes that the associated number is negative. The default is "-".
        negativeSign: u8 = '-'     // Negative sign associated with this value.

        // The byte that denotes that the associated number is positive. The default is "+".
        positiveSign: u8 = '+'     // Positive sign associated with this value.

        // The byte to use as the decimal separator in numeric values. The default is ".".
        decimalSeparator: u8 = '.'     // Decimal separator associated with this value.
    }
}
