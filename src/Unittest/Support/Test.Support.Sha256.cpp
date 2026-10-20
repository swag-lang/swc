#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Support/Core/Utf8Helper.h"
#include "Support/Math/Sha256.h"
#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

SWC_TEST_BEGIN(Sha256_KnownAnswers)
{
    const std::pair<std::string_view, std::string_view> vectors[] = {
        {"", "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"},
        {"abc", "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"},
        {"abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq", "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"},
    };
    for (const auto& [source, expected] : vectors)
        if (Utf8Helper::toLowerHex(sha256(std::as_bytes(std::span{source.data(), source.size()}))).view() != expected)
            return Result::Error;
    const std::string million(1'000'000, 'a');
    if (Utf8Helper::toLowerHex(sha256(std::as_bytes(std::span{million.data(), million.size()}))) != "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0")
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Sha256_FragmentedInputBoundaries)
{
    std::array<std::byte, 129> source;
    for (size_t index = 0; index < source.size(); ++index)
        source[index] = static_cast<std::byte>(index);
    const std::span<const std::byte> bytes(source);
    for (size_t split = 0; split <= source.size(); ++split)
    {
        const auto hash = sha256Parts({bytes.first(split), {}, bytes.subspan(split)});
        if (Utf8Helper::toLowerHex(hash) != "5099c6a56203f9687f7d33f4bfdf576d31dc91f6b695ecea38b2770c87631135")
            return Result::Error;
    }
    // Exercise a final one-byte fragment around the padding and block boundaries.
    for (size_t length = 54; length <= 65; ++length)
    {
        const auto hash = sha256Parts({bytes.first(length - 1), bytes.subspan(length - 1, 1)});
        if (hash != sha256(bytes.first(length)))
            return Result::Error;
    }
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
