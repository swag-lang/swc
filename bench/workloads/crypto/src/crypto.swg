using Core

alias Operation = func(const [..] u8, [..] u8)

const Key   = "0123456789abcdefghijklmnopqrstuv"
const Nonce = "0123456789ab"
const AssociatedData = "swag-crypto-1"
const AesXtsKey = "0123456789abcdefghijklmnopqrstuvvutsrqponmlkjihgfedcba9876543210"
const AesXtsTweak = "0123456789abcdef"

func(T) writeChecksum(value: T, output: [..] u8)
{
    cast([*] T, output.buffer)[0] = Math.nativeToLittleEndian(value)
}

func(T) writeDigest(words: const [..] T, output: [..] u8)
{
    let destination = cast([*] T, output.buffer)
    for index in words.count do
        destination[index] = Math.nativeToBigEndian(words[index])
}

func adler32(input: const [..] u8, output: [..] u8)   => writeChecksum(Hash.Adler32.compute(input), output)
func crc32(input: const [..] u8, output: [..] u8)     => writeChecksum(Hash.Crc32.compute(input), output)
func crc64Ecma(input: const [..] u8, output: [..] u8) => writeChecksum(Hash.Crc64.compute(input), output)
func crc64Iso(input: const [..] u8, output: [..] u8)  => writeChecksum(Hash.Crc64.compute(input, .Iso), output)
func crc64Xz(input: const [..] u8, output: [..] u8)   => writeChecksum(Hash.Crc64.compute(input, .IsoXz), output)

func md5(input: const [..] u8, output: [..] u8)
{
    let digest = Hash.Md5.compute(input)
    Memory.copy(output.buffer, digest.buffer, digest.count)
}

func sha1(input: const [..] u8, output: [..] u8)    => writeDigest'u32(Hash.Sha1.compute(input), output)
func sha224(input: const [..] u8, output: [..] u8)  => writeDigest'u32(Hash.Sha224.compute(input), output)
func sha256(input: const [..] u8, output: [..] u8)  => writeDigest'u32(Hash.Sha256.compute(input), output)
func sha384(input: const [..] u8, output: [..] u8)  => writeDigest'u64(Hash.Sha384.compute(input), output)
func sha512(input: const [..] u8, output: [..] u8)  => writeDigest'u64(Hash.Sha512.compute(input), output)
func sha3(input: const [..] u8, output: [..] u8)    => expect Hash.Sha3.compute(input, output)
func blake2b(input: const [..] u8, output: [..] u8) => expect Hash.Blake2b.compute(input, output)
func blake2s(input: const [..] u8, output: [..] u8) => expect Hash.Blake2s.compute(input, output)
func blake3(input: const [..] u8, output: [..] u8)  => expect Hash.Blake3.compute(input, output)

func hmacSha384(input: const [..] u8, output: [..] u8)
{
    let tag = Crypto.HmacSha384.compute(Key, input)
    Memory.copy(output.buffer, tag.buffer, tag.count)
}

func hmacSha512(input: const [..] u8, output: [..] u8)
{
    let tag = Crypto.HmacSha512.compute(Key, input)
    Memory.copy(output.buffer, tag.buffer, tag.count)
}

func poly1305(input: const [..] u8, output: [..] u8)
{
    let tag = expect Crypto.Poly1305.compute(Key, input)
    Memory.copy(output.buffer, tag.buffer, tag.count)
}

func chacha20(input: const [..] u8, output: [..] u8) =>
    expect Crypto.chacha20Xor(Key, Nonce, input, output, 1)

func chacha20Poly1305(input: const [..] u8, output: [..] u8) =>
    expect Crypto.chacha20Poly1305Seal(Key, Nonce, input, AssociatedData, output[until input.count], output[input.count until output.count])

func aes256Ctr(input: const [..] u8, output: [..] u8) =>
    expect Crypto.aesCtrCrypt(Key, "0123456789abcdef", input, output)

func aes256Gcm(input: const [..] u8, output: [..] u8) =>
    expect Crypto.aesGcmEncrypt(Key, Nonce, AssociatedData, input, output[until input.count], output[input.count until output.count])

func aes256Ccm(input: const [..] u8, output: [..] u8) =>
    expect Crypto.aesCcmEncrypt(Key, Nonce, AssociatedData, input, output[until input.count], output[input.count until output.count])

func aes256GcmAad(input: const [..] u8, output: [..] u8) =>
    expect Crypto.aesGcmEncrypt(Key, Nonce, input, "", output[until 0], output)

func aes256XtsEncrypt(input: const [..] u8, output: [..] u8) =>
    expect Crypto.aesXtsCrypt(AesXtsKey, AesXtsTweak, input, output, false)

func aes256XtsDecrypt(input: const [..] u8, output: [..] u8) =>
    expect Crypto.aesXtsCrypt(AesXtsKey, AesXtsTweak, input, output, true)

func x25519Public(input: const [..] u8, output: [..] u8) =>
    expect Crypto.x25519PublicKey(input, output)

func x25519Shared(input: const [..] u8, output: [..] u8) =>
    expect Crypto.x25519SharedSecret(Key, input, output)

func ed25519Public(input: const [..] u8, output: [..] u8) =>
    expect Crypto.ed25519PublicKey(input, output)

func ed25519Sign(input: const [..] u8, output: [..] u8) =>
    expect Crypto.ed25519Sign(Key, input, output)

func p256Public(input: const [..] u8, output: [..] u8) =>
    expect Crypto.p256PublicKey(input, output)

func p256Sign(input: const [..] u8, output: [..] u8) =>
    expect Crypto.p256EcdsaSign(Key, input, output)

func hkdfSha224(input: const [..] u8, output: [..] u8) =>
    expect Crypto.hkdfSha224(Nonce, Key, input[until Math.min(input.count, 48)], output)

func hkdfSha256(input: const [..] u8, output: [..] u8) =>
    expect Crypto.hkdfSha256(Nonce, Key, input[until Math.min(input.count, 48)], output)

func hkdfSha384(input: const [..] u8, output: [..] u8) =>
    expect Crypto.hkdfSha384(Nonce, Key, input[until Math.min(input.count, 48)], output)

func hkdfSha512(input: const [..] u8, output: [..] u8) =>
    expect Crypto.hkdfSha512(Nonce, Key, input[until Math.min(input.count, 48)], output)

func selectOperation(name: string, size: u64)->{operation: Operation, outputSize: u64}
{
    switch name
    {
    case "adler32":           return {&adler32, 4}
    case "crc32":             return {&crc32, 4}
    case "crc64-ecma":        return {&crc64Ecma, 8}
    case "crc64-iso":         return {&crc64Iso, 8}
    case "crc64-xz":          return {&crc64Xz, 8}
    case "md5":               return {&md5, 16}
    case "sha1":              return {&sha1, 20}
    case "sha224":            return {&sha224, 28}
    case "sha256":            return {&sha256, 32}
    case "sha384":            return {&sha384, 48}
    case "sha512":            return {&sha512, 64}
    case "sha3-256":          return {&sha3, 32}
    case "blake2b-512":       return {&blake2b, 64}
    case "blake2s-256":       return {&blake2s, 32}
    case "blake3":            return {&blake3, 32}
    case "hmac-sha384":       return {&hmacSha384, 48}
    case "hmac-sha512":       return {&hmacSha512, 64}
    case "poly1305":          return {&poly1305, 16}
    case "chacha20":          return {&chacha20, size}
    case "chacha20-poly1305": return {&chacha20Poly1305, size + 16}
    case "aes-256-ctr":       return {&aes256Ctr, size}
    case "aes-256-gcm":       return {&aes256Gcm, size + 16}
    case "aes-256-ccm":       return {&aes256Ccm, size + 16}
    case "aes-256-gcm-aad":   return {&aes256GcmAad, 16}
    case "aes-256-xts-encrypt": return {&aes256XtsEncrypt, size}
    case "aes-256-xts-decrypt": return {&aes256XtsDecrypt, size}
    case "x25519-public":     return {&x25519Public, 32}
    case "x25519-shared":     return {&x25519Shared, 32}
    case "ed25519-public":    return {&ed25519Public, 32}
    case "ed25519-sign":      return {&ed25519Sign, 64}
    case "p256-public":       return {&p256Public, 65}
    case "p256-sign":         return {&p256Sign, 64}
    case "hkdf-sha224":       return {&hkdfSha224, size}
    case "hkdf-sha256":       return {&hkdfSha256, size}
    case "hkdf-sha384":       return {&hkdfSha384, size}
    case "hkdf-sha512":       return {&hkdfSha512, size}
    default:                  unreachable
    }
}

func processTicks()->u64
{
    var stamp: Linux.timespec
    let status = Linux.clock_gettime(Linux.CLOCK_PROCESS_CPUTIME_ID, &stamp)
    Swag.require(status == 0)
    return cast(u64, stamp.tv_sec) * 1_000_000_000 + cast(u64, stamp.tv_nsec)
}

#main
{
    let args = Env.arguments()
    Swag.require(args.count == 6)
    let iterations = expect StrConv.toU64(args[4])
    let offset     = expect StrConv.toU64(args[5])
    let source     = expect File.readAllBytes(args[2])
    Swag.require(iterations and offset <= source.count)
    let input    = source.toSlice()[offset until source.count]
    let selected = selectOperation(args[1], input.count)
    var output: Array'u8
    output.resize(selected.outputSize)
    let destination = output.toSlice()

    let workerLimit = Env.variable("SWAG_RUNTIME_THREADS")
    let requested   = workerLimit.isEmpty() ? 1'u32 : expect StrConv.toU32(workerLimit.toString())
    let workers     = Swag.max(requested, 1)
    Swag.setWorkerCount(workers)
    Swag.startWorkers()
    Swag.require(Swag.workerCount() == workers)
    selected.operation(input, destination)
    let wallStart = Time.monotonicTicks()
    let cpuStart  = processTicks()
    for iterations do
        selected.operation(input, destination)
    let cpuElapsed  = processTicks() - cpuStart
    let wallElapsed = Time.monotonicTicks() - wallStart

    discard expect File.writeAllBytes(args[3], destination)
    Console.println(wallElapsed, " ", cpuElapsed, " ", Time.monotonicFrequency())
}
