#global private

struct Value { first, second: u64 }
alias Reader = func(Value)->u64

#[Swag.NoInline]
func read(value: Value)->u64 => value.first

func restoredReader()->u64
{
    let address      = cast(*void, &read)
    let callback     = cast(Reader, address)
    var value: Value = {first: 383}
    return callback(value)
}

func restoredEncodedReader()->u64
{
    let encoded      = cast(u64, cast(*void, &read))
    let callback     = cast(Reader, cast(*void, encoded))
    var value: Value = {first: 389}
    return callback(value)
}

const RESTORED_READER         = #run restoredReader()
const RESTORED_ENCODED_READER = #run restoredEncodedReader()

#test
{
    let direct  = restoredReader()
    let encoded = restoredEncodedReader()
    Swag.assert(direct == 383 and RESTORED_READER == direct)
    Swag.assert(encoded == 389 and RESTORED_ENCODED_READER == encoded)
}

struct ReaderBox { callback: Reader }

func restoredReaderStorage()->u64
{
    var box:   ReaderBox = {callback: &read}
    let encoded          = cast(u64, &box)
    let restored         = cast(*ReaderBox, cast(*void, encoded))
    var value: Value     = {first: 409}
    return restored.callback(value)
}

const RESTORED_STORAGE = #run restoredReaderStorage()

#test
{
    let result = restoredReaderStorage()
    Swag.assert(result == 409 and RESTORED_STORAGE == result)
}

#[Swag.ExportType(.Methods)]
struct ReflectedReader {}

impl ReflectedReader
{
    func readValue(value: Value)->u64 => value.first
}

func reflectedReader()->u64
{
    const info = assume cast(const *Swag.TypeInfoStruct, #typeof(ReflectedReader))
    let entry        = info.methods![0]
    let callback     = cast(Reader, entry.value!)
    var value: Value = {first: 419}
    return callback(value)
}

const REFLECTED_READER = #run reflectedReader()

#test
{
    let result = reflectedReader()
    Swag.assert(result == 419 and REFLECTED_READER == result)
}
