#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Compiler/Parser/Ast/Ast.h"
#include "Compiler/Parser/Parser/ParserJob.h"
#include "Main/TaskContext.h"
#include "Unittest/Unittest.h"
#include "Unittest/UnittestSource.h"

SWC_BEGIN_NAMESPACE();

SWC_TEST_BEGIN(ParseCache_RestoresPrivateTreeAndSourceLocations)
{
    constexpr std::string_view source = R"(namespace Cache
{
    struct Pair { public x, y: s32 }
    func sum(p: Pair)->s32 => p.x + p.y
    func apply(block: #code(var item: s32)) {}
})";
    auto&                      first  = Unittest::addTestSource(ctx, "Compiler", "ParseCacheFirst", source);
    first.ast().prepareParseImage();
    SWC_RESULT(parseLoadedSourceFile(ctx, first, {}));
    if (first.hasError())
        return Result::Error;
    std::vector<std::byte> image;
    std::vector<uint32_t>  nodes;
    first.ast().copyParseImage(image, nodes);

    auto& second                         = Unittest::addTestSource(ctx, "Compiler", "ParseCacheSecond", source);
    second.ast().srcView().tokens()      = first.ast().srcView().tokens();
    second.ast().srcView().identifiers() = first.ast().srcView().identifiers();
    second.ast().srcView().lines()       = first.ast().srcView().lines();
    const uint32_t root                  = first.ast().root().get();
    if (!second.ast().loadParseImage(image, nodes, root))
        return Result::Error;
    if (second.ast().srcView().ref() == first.ast().srcView().ref())
        return Result::Error;
    bool foundCodeParam = false;
    for (size_t index = 0; index < nodes.size(); index += 2)
    {
        const AstNodeRef ref(nodes[index]);
        const auto&      before = first.ast().node(ref);
        const auto&      after  = second.ast().node(ref);
        foundCodeParam |= after.id() == AstNodeId::CodeParam;
        if (after.id() != before.id() || after.parserFlags() != before.parserFlags() ||
            after.tokRef() != before.tokRef() || after.srcViewRef() != second.ast().srcView().ref())
            return Result::Error;
        if (&after == &before)
            return Result::Error;
    }
    if (!foundCodeParam)
        return Result::Error;
    second.ast().node(second.ast().root()).setId(AstNodeId::Invalid);
    if (first.ast().node(first.ast().root()).id() != AstNodeId::File)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(ParseCache_RejectsTruncatedImageBeforePublication)
{
    auto& source = Unittest::addTestSource(ctx, "Compiler", "ParseCacheTruncateSource", "func answer() -> s32 => 42");
    source.ast().prepareParseImage();
    SWC_RESULT(parseLoadedSourceFile(ctx, source, {}));
    std::vector<std::byte> image;
    std::vector<uint32_t>  nodes;
    source.ast().copyParseImage(image, nodes);
    auto& target                    = Unittest::addTestSource(ctx, "Compiler", "ParseCacheTruncateTarget", source.sourceView());
    target.ast().srcView().tokens() = source.ast().srcView().tokens();
    if (target.ast().loadParseImage(std::span<const std::byte>(image).first(image.size() - 1), nodes, source.ast().root().get()))
        return Result::Error;
    if (target.ast().root().isValid())
        return Result::Error;
    SWC_RESULT(parseLoadedSourceFile(ctx, target, {}));
    if (target.hasError() || target.ast().root().isInvalid())
        return Result::Error;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
