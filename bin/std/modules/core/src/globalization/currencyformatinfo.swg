#global namespace Globalization

using Swag

// Selects where a currency symbol is placed for a positive amount.
public enum CurrencyPositivePattern
{
    SymbolBefore              // `$1.00`.
    SymbolBeforeWithSpace     // `$ 1.00`.
    SymbolAfter               // `1.00$`.
    SymbolAfterWithSpace      // `1.00 $`.
}

// Selects how a negative currency amount is represented.
public enum CurrencyNegativePattern
{
    SignBeforeSymbol     // `-$1.00`.
    SignBeforeNumber     // `$-1.00`.
    Parentheses          // `($1.00)`.
}

// Provides culture-specific currency conventions.
public struct CurrencyFormatInfo
{
    public
    {
        symbol:          string                  = "$"                   // Currency symbol borrowed from the culture profile.
        decimalDigits:   u8                      = 2                     // Number of fractional currency digits.
        positivePattern: CurrencyPositivePattern = .SymbolBefore         // Placement used for non-negative amounts.
        negativePattern: CurrencyNegativePattern = .SignBeforeSymbol     // Placement used for negative amounts.
    }
}

public impl CurrencyFormatInfo
{
    internal mtd const appendPositive(result: *String, number: string)
    {
        switch #complete .positivePattern
        {
        case .SymbolBefore:
            result.append(.symbol)
            result.append(number)

        case .SymbolBeforeWithSpace:
            result.append(.symbol)
            result.append(' 'u8)
            result.append(number)

        case .SymbolAfter:
            result.append(number)
            result.append(.symbol)

        case .SymbolAfterWithSpace:
            result.append(number)
            result.append(' 'u8)
            result.append(.symbol)
        }
    }

    // Formats an amount with this currency convention and the supplied numeric convention.
    mtd const format(value: f64, numberFormat: const &NumberFormatInfo)->String
    {
        let negative = value < 0
        let number   = numberFormat.format(Math.abs(value), decimals: .decimalDigits, grouped: true)

        var result: retval
        if !negative
        {
            .appendPositive(&result, number)
            return result
        }

        switch #complete .negativePattern
        {
        case .SignBeforeSymbol:
            result.append(numberFormat.negativeSign)
            .appendPositive(&result, number)

        case .SignBeforeNumber:
            switch .positivePattern
            {
            case .SymbolBefore:
                result.append(.symbol)
                result.append(numberFormat.negativeSign)
                result.append(number)

            case .SymbolBeforeWithSpace:
                result.append(.symbol)
                result.append(' 'u8)
                result.append(numberFormat.negativeSign)
                result.append(number)

            default:
                result.append(numberFormat.negativeSign)
                .appendPositive(&result, number)
            }

        case .Parentheses:
            result.append('('u8)
            .appendPositive(&result, number)
            result.append(')'u8)
        }

        return result
    }
}
