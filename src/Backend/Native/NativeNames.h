#pragma once
#include "Support/Core/Utf8.h"

SWC_BEGIN_NAMESPACE();

class CompilerInstance;
class SymbolFunction;
class TaskContext;

inline constexpr auto K_R_DATA_BASE_SYMBOL = "__swc_rdata_base";
inline constexpr auto K_DATA_BASE_SYMBOL   = "__swc_data_base";
inline constexpr auto K_BSS_BASE_SYMBOL    = "__swc_bss_base";

Utf8 nativeArtifactScopeName(const CompilerInstance& compiler);
Utf8 nativeScopedSectionBaseSymbol(const CompilerInstance& compiler, std::string_view baseName);
Utf8 nativeScopedRDataAllocationSymbol(const CompilerInstance& compiler, uint32_t shardIndex, uint32_t sourceOffset);
Utf8 unresolvedFunctionSymbolName(const TaskContext& ctx, const SymbolFunction& function);

SWC_END_NAMESPACE();
