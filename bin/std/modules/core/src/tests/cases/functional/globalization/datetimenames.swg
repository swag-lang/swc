#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

#test
{
    var format: Globalization.DateTimeFormatInfo
    Swag.require(format.dayName(.Sunday) == "Sunday")
    Swag.require(format.dayName(.Monday) == "Monday")
    Swag.require(format.dayName(.Tuesday) == "Tuesday")
    Swag.require(format.dayName(.Wednesday) == "Wednesday")
    Swag.require(format.dayName(.Thursday) == "Thursday")
    Swag.require(format.dayName(.Friday) == "Friday")
    Swag.require(format.dayName(.Saturday) == "Saturday")
    Swag.require(format.monthName(1) == "January")
    Swag.require(format.monthName(12) == "December")
}

#test
{
    var format: Globalization.DateTimeFormatInfo
    let invalidMonth = Swag.catchPanic(func|&format|()
    {
        discard format.monthName(0)
    })
    Swag.require(invalidMonth.raised and invalidMonth.message() == "month is outside the supported range")
}
