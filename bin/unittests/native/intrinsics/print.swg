#global private

// 'Swag.print' formats a value from its native kind, not from the identity of its typeinfo.
// A qualified form such as '#null string' owns its own descriptor while still being a
// string: reading it as an unrelated type panics on a null payload, and refusing it
// altogether drops the very text the call was asked to write.
//
// Only payloads that print nothing are exercised here, because the console output of a
// test is not observable; what is proved is that the string forms are accepted.
#test
{
    var missing: #null string
    Swag.print(missing)

    var empty: #null string = ""
    Swag.print(empty)

    var plain: string = ""
    Swag.print(plain)
}
