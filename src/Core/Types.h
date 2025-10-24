#pragma once

using AstNodeRef  = uint32_t;
using FileRef     = uint32_t;
using TokenRef    = uint32_t;
using JobClientId = uint32_t;

constexpr AstNodeRef  INVALID_AST_NODE_REF  = UINT32_MAX;
constexpr FileRef     INVALID_FILE_REF      = UINT32_MAX;
constexpr TokenRef    INVALID_TOKEN_REF     = UINT32_MAX;
constexpr JobClientId INVALID_JOB_CLIENT_ID = UINT32_MAX;
