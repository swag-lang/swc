#global private

using Core

func processTicks()->u64
{
    var stamp: Linux.timespec
    let status = Linux.clock_gettime(Linux.CLOCK_PROCESS_CPUTIME_ID, &stamp)
    Swag.require(status == 0)
    return cast(u64, stamp.tv_sec) * 1_000_000_000 + cast(u64, stamp.tv_nsec)
}

func u32le(input: const [..] u8, offset: u64)->u64
{
    var value: u32
    Swag.memcpy(&value, input.buffer + offset, 4)
    return cast(u64, value)
}

func operate(name: string, modulus, privateExponent, publicExponent, signature, ciphertext, message: const [..] u8, output: [..] u8)->u64
{
    switch name
    {
        case "rsa-pss-verify":
            output[0] = cast(u8, expect Crypto.rsaPssSha256Verify(modulus, publicExponent, message, signature))
            return 1
        case "rsa-oaep-decrypt":
            return expect Crypto.rsaOaepSha256Decrypt(modulus, privateExponent, ciphertext, message[until 0], output)
        case "rsa-pss-sign":
            expect Crypto.rsaPssSha256Sign(modulus, privateExponent, message, output[until modulus.count])
            return modulus.count
        case "rsa-oaep-encrypt":
            expect Crypto.rsaOaepSha256Encrypt(modulus, publicExponent, message, message[until 0], output[until modulus.count])
            return modulus.count
        default:
            Swag.require(false, "unknown RSA workload")
            return 0
    }
}

#main
{
    let arguments = Env.arguments()
    Swag.require(arguments.count == 6)
    let iterations = expect StrConv.toU64(arguments[4])
    let offset     = expect StrConv.toU64(arguments[5])
    let file       = expect File.readAllBytes(arguments[2])
    let input      = file.toSlice()[offset to]
    Swag.require(iterations and input.count >= 12)
    let width       = u32le(input, 0)
    let messageSize = u32le(input, 4)
    let exponentSize = u32le(input, 8)
    let modulus         = input[12 until 12 + width]
    let privateExponent = input[12 + width until 12 + width * 2]
    let publicExponent  = input[12 + width * 2 until 12 + width * 2 + exponentSize]
    let signatureStart  = 12 + width * 2 + exponentSize
    let signature       = input[signatureStart until signatureStart + width]
    let ciphertext      = input[signatureStart + width until signatureStart + width * 2]
    let message         = input[signatureStart + width * 2 until signatureStart + width * 2 + messageSize]
    var output: [Crypto.RsaMaxModulusSize] u8

    let name = arguments[1]
    var outputSize = operate(name, modulus, privateExponent, publicExponent, signature, ciphertext, message, output)
    let wallStart = Time.monotonicTicks()
    let cpuStart  = processTicks()
    for iterations do
        outputSize = operate(name, modulus, privateExponent, publicExponent, signature, ciphertext, message, output)
    let cpuElapsed  = processTicks() - cpuStart
    let wallElapsed = Time.monotonicTicks() - wallStart

    discard expect File.writeAllBytes(arguments[3], output[until outputSize])
    Console.println(wallElapsed, " ", cpuElapsed, " ", Time.monotonicFrequency())
}
