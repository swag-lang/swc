#pragma once
#include "Support/Core/Utf8.h"

SWC_BEGIN_NAMESPACE();

class CompilerInstance;
class SymbolFunction;
class TaskContext;
enum class DataSegmentAllocationKind : uint8_t;

inline constexpr auto K_R_DATA_BASE_SYMBOL = "__swc_rdata_base";
inline constexpr auto K_DATA_BASE_SYMBOL   = "__swc_data_base";
inline constexpr auto K_BSS_BASE_SYMBOL    = "__swc_bss_base";

Utf8 nativeArtifactScopeName(const CompilerInstance& compiler);
Utf8 nativeScopedSectionBaseSymbol(const CompilerInstance& compiler, std::string_view baseName);
Utf8 nativeScopedSectionBaseSymbol(uint32_t scopeHash, std::string_view baseName);
Utf8 nativeScopedRDataAllocationSymbol(const CompilerInstance& compiler, uint32_t emittedOffset);
inline constexpr std::string_view K_TYPE_METADATA_SYMBOL_PREFIX = "__swc_rdata_type_";
inline constexpr std::string_view K_TYPE_IDENTITY_SYMBOL_PREFIX = "__swc_rdata_type_identity_";
Utf8                              nativeScopedRDataAllocationSymbol(uint32_t scopeHash, uint32_t emittedOffset, DataSegmentAllocationKind kind);
// The first relocation of a sealed identity is its compiler-defined runtime
// layout (e.g. Swag.TypeInfoStruct). A layout is the same across modules even
// when their private initializers have different addresses.
inline std::string_view typeIdentityLayout(const std::string_view owner, const uint64_t offset)
{
    const size_t layoutEnd = K_TYPE_IDENTITY_SYMBOL_PREFIX.size() + 2;
    if (!offset && owner.size() > layoutEnd && owner.starts_with(K_TYPE_IDENTITY_SYMBOL_PREFIX) && owner[layoutEnd] == '_')
        return owner.substr(0, layoutEnd);
    return {};
}

Utf8 unresolvedFunctionSymbolName(const TaskContext& ctx, const SymbolFunction& function);

SWC_END_NAMESPACE();
