#global #if #command == Swag.CompilerCommand.Test
#global private
using Swag

func md5String(buffer: const [..] u8)->String
{
    return Hash.Md5.toString(Hash.Md5.compute(buffer))
}

func assertMd5(buffer: const [..] u8, expected: string)
{
    @assert(md5String(buffer) == expected)

    var md5: Hash.Md5
    md5.init()
    md5.update(buffer)
    md5.update("")

    var digest: Hash.Md5.Digest
    md5.final(digest)
    @assert(Hash.Md5.toString(digest) == expected)
}

func assertMd5Split(buffer: const [..] u8, split0, split1: u64, expected: string)
{
    var md5: Hash.Md5
    md5.init()
    md5.update(buffer[until split0])
    md5.update(buffer[split0 until split1])
    md5.update(buffer[split1 until @countof(buffer)])

    var digest: Hash.Md5.Digest
    md5.final(digest)
    @assert(Hash.Md5.toString(digest) == expected)
}

func fillMd5Pattern(buffer: [..] u8)
{
    var i = 0'u64
    while i < @countof(buffer)
    {
        buffer[i] = cast(u8) ((i * 37 + 11) & 0xff)
        i += 1
    }
}

#test
{
    assertMd5("", "D41D8CD98F00B204E9800998ECF8427E")
    assertMd5("a", "0CC175B9C0F1B6A831C399E269772661")
    assertMd5("abc", "900150983CD24FB0D6963F7D28E17F72")
    assertMd5("message digest", "F96B697D7CB7938D525A2F31AAF161D0")
    assertMd5("abcdefghijklmnopqrstuvwxyz", "C3FCD3D76192E4007DFB496CCA67E13B")
    assertMd5("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789", "D174AB98D277D9F5A5611C2C9F419D9F")
    assertMd5("12345678901234567890123456789012345678901234567890123456789012345678901234567890", "57EDF4A22BE3C955AC49DA2E2107B67A")

    var md5: Hash.Md5
    md5.update("dirty")
    md5.init()
    @assert(md5String("") == "D41D8CD98F00B204E9800998ECF8427E")

    var data: [130] u8
    fillMd5Pattern(data)

    assertMd5(data[until 0], "D41D8CD98F00B204E9800998ECF8427E")
    assertMd5(data[until 1], "13C8FFD977013703A701CF8E11DEAC65")
    assertMd5(data[until 2], "A22664EDCE89FAFC28F264D313C39D51")
    assertMd5(data[until 3], "876D16C575F9D3D7F51F12FEF37237EB")
    assertMd5(data[until 15], "D58E0093DCB633D2398902489F1DA5B7")
    assertMd5(data[until 16], "887B610071C85B140D8615F5CEC4875E")
    assertMd5(data[until 31], "3657C259ABA7EEDFAF3957B2D5E2CC1F")
    assertMd5(data[until 32], "8E2C0CBA10572C7B479ACA4E43974FB4")
    assertMd5(data[until 55], "D872AA0473A24DA995CE4AC518ADE767")
    assertMd5(data[until 56], "E23567645846677C205DE80F9779081B")
    assertMd5(data[until 57], "1FE5E4A27E12484D7203D0B60C21C51F")
    assertMd5(data[until 63], "4775B66278A8FC132FF80923378216CD")
    assertMd5(data[until 64], "71E123B70C7AA64826FCFE472694CD1C")
    assertMd5(data[until 65], "5949948F26E35203661075214FAA3966")
    assertMd5(data[until 119], "87F72C7241C5FE218BB4DF8C0ABA3232")
    assertMd5(data[until 120], "BF240B8B7407FBA3805ADEEC63A03B77")
    assertMd5(data[until 121], "C51004ED1EF4271C82106468A13FE8CF")
    assertMd5(data[until 129], "D1AE06BBF9128955A34BEDB6231EEE62")
    assertMd5(data[until 130], "8A2682A4B1A920CCCC7C09422B233D76")

    assertMd5Split(data[until 65], 1, 64, "5949948F26E35203661075214FAA3966")
    assertMd5Split(data[until 130], 7, 73, "8A2682A4B1A920CCCC7C09422B233D76")
}
