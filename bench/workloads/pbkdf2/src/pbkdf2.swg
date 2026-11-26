#global private

using Core

func processMicroseconds()->u64
{
    var stamp: Linux.timespec
    let status = Linux.clock_gettime(Linux.CLOCK_PROCESS_CPUTIME_ID, &stamp)
    Swag.require(status == 0)
    return cast(u64, stamp.tv_sec) * 1_000_000 + cast(u64, stamp.tv_nsec) / 1000
}

func derive(algorithm: string, password, salt: const [..] u8, iterations: u32, destination: [..] u8) fail
{
    switch algorithm
    {
    case "sha224": try Crypto.pbkdf2HmacSha224(password, salt, iterations, destination)
    case "sha256": try Crypto.pbkdf2HmacSha256(password, salt, iterations, destination)
    case "sha384": try Crypto.pbkdf2HmacSha384(password, salt, iterations, destination)
    case "sha512": try Crypto.pbkdf2HmacSha512(password, salt, iterations, destination)
    default:       unreachable
    }
}

#main
{
    let args = Env.arguments()
    Swag.require(args.count == 6)
    let algorithm    = args[1]
    let iterations   = expect StrConv.toU32(args[2])
    let passwordSize = expect StrConv.toU32(args[3])
    let saltSize     = expect StrConv.toU32(args[4])
    let tagSize      = expect StrConv.toU32(args[5])

    var password: Array'u8
    password.resize(passwordSize)
    for index in password.count do
        password[index] = cast(u8, (index * 31 + 17) & 255)
    var salt: Array'u8
    salt.resize(saltSize)
    for index in salt.count do
        salt[index] = cast(u8, (index * 47 + 29) & 255)
    var warmup, tag: Array'u8
    warmup.resize(tagSize)
    tag.resize(tagSize)

    expect derive(algorithm, password.toSlice(), salt.toSlice(), iterations, warmup.toSlice())
    var watch: Time.Stopwatch
    watch.start()
    let cpuStart = processMicroseconds()
    expect derive(algorithm, password.toSlice(), salt.toSlice(), iterations, tag.toSlice())
    let cpuElapsed = processMicroseconds() - cpuStart
    watch.stop()
    Swag.require(Crypto.constantTimeEqual(warmup.toSlice(), tag.toSlice()))

    const Digits = "0123456789abcdef"
    var text: Array'u8
    text.resize(tagSize * 2)
    for byte, index in tag.toSlice()
    {
        text[2 * index]     = Digits[byte >> 4]
        text[2 * index + 1] = Digits[byte & 15]
    }

    Console.println(watch.elapsedMicroseconds(), " ", cpuElapsed, " ", cast(string, text.toSlice()))
}
