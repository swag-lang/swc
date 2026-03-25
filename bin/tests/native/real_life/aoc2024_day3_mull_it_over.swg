#global fileprivate

// Advent of Code 2024 Day 3: scan corrupted memory for mul(X,Y) instructions,
// then cross-check a clean state-machine parser with a macro/mixin flavored one.

const MaxTokens = 1024

const SampleInputA = "xmul(2,4)%&mul[3,7]!@^do_not_mul(5,5)+mul(32,64]then(mul(11,8)mul(8,5))"
const SampleInputB = "xmul(2,4)&mul[3,7]!^don't()_mul(5,5)+mul(32,64](mul(11,8)undo()_mul(8,5))"

const EdgeInput = "mul(1,1)don't()mul(2,2)do()mul(3,3)"
const EmptyInput = "nothing here at all"
const ActualInput = #include("3.txt")

enum TokenKind: u8
{
    Mul
    Do
    Dont
}

struct Token
{
    kind: TokenKind
    lhs:  s32
    rhs:  s32
}

struct TokenStream
{
    count:  u32
    tokens: [MaxTokens] Token
}

struct MulResult
{
    sumAll:     s64
    sumEnabled: s64
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

func isDigit(ch: u8)->bool
{
    return ch >= '0' and ch <= '9'
}

func matchLiteral(bytes: const [..] u8, pos: u64, lit: string)->bool
{
    let litBytes = cast(const [..] u8) lit
    if pos + @countof(litBytes) > @countof(bytes) do
        return false
    for @countof(litBytes)
    {
        if bytes[pos + @index] != litBytes[@index] do
            return false
    }
    return true
}

func parseNumber(bytes: const [..] u8, pos: u64, outVal: *s32, outEnd: *u64)->bool
{
    var digits: u32
    var value: s32
    var i = pos

    while i < @countof(bytes) and isDigit(bytes[i]) and digits < 3
    {
        value = value * 10 + cast(s32) (bytes[i] - '0')
        digits += 1
        i += 1
    }

    if digits == 0 or digits > 3 do
        return false

    dref outVal = value
    dref outEnd = i
    return true
}

// ---------------------------------------------------------------------------
// Clean approach: state-machine scanner
// ---------------------------------------------------------------------------

func tokenizeClean(bytes: const [..] u8)->TokenStream
{
    var result: TokenStream
    var i: u64

    while i < @countof(bytes)
    {
        if matchLiteral(bytes, i, "don't()")
        {
            @assert(result.count < MaxTokens)
            result.tokens[result.count].kind = TokenKind.Dont
            result.count += 1
            i += 7
            continue
        }

        if matchLiteral(bytes, i, "do()")
        {
            @assert(result.count < MaxTokens)
            result.tokens[result.count].kind = TokenKind.Do
            result.count += 1
            i += 4
            continue
        }

        if matchLiteral(bytes, i, "mul(")
        {
            var lhs: s32
            var rhs: s32
            var afterLhs: u64
            var afterRhs: u64

            if parseNumber(bytes, i + 4, &lhs, &afterLhs)
            {
                if afterLhs < @countof(bytes) and bytes[afterLhs] == ','
                {
                    if parseNumber(bytes, afterLhs + 1, &rhs, &afterRhs)
                    {
                        if afterRhs < @countof(bytes) and bytes[afterRhs] == ')'
                        {
                            @assert(result.count < MaxTokens)
                            result.tokens[result.count].kind = TokenKind.Mul
                            result.tokens[result.count].lhs = lhs
                            result.tokens[result.count].rhs = rhs
                            result.count += 1
                            i = afterRhs + 1
                            continue
                        }
                    }
                }
            }
        }

        i += 1
    }

    return result
}

func evaluateClean(stream: TokenStream)->MulResult
{
    var result: MulResult
    var enabled = true

    for stream.count
    {
        let tok = stream.tokens[cast(u32) @index]
        switch tok.kind
        {
        case TokenKind.Do:
            enabled = true
        case TokenKind.Dont:
            enabled = false
        case TokenKind.Mul:
            let product = cast(s64) tok.lhs * cast(s64) tok.rhs
            result.sumAll += product
            if enabled do
                result.sumEnabled += product
        }
    }

    return result
}

// ---------------------------------------------------------------------------
// Language-features approach: mixins, macros, defer, switch-where
// ---------------------------------------------------------------------------

#[Swag.Mixin]
func declareScannerState()
{
    var scanPos: u64
    var scanTokens: TokenStream
    var scanEnabled = true
    var scanSumAll: s64
    var scanSumEnabled: s64
}

#[Swag.Mixin]
func emitToken(kind: TokenKind, lhs: s32, rhs: s32)
{
    @assert(scanTokens.count < MaxTokens)
    scanTokens.tokens[scanTokens.count].kind = kind
    scanTokens.tokens[scanTokens.count].lhs = lhs
    scanTokens.tokens[scanTokens.count].rhs = rhs
    scanTokens.count += 1
}

#[Swag.Mixin]
func accumulateMul(lhs: s32, rhs: s32)
{
    let product = cast(s64) lhs * cast(s64) rhs
    scanSumAll += product
    if scanEnabled do
        scanSumEnabled += product
}

#[Swag.Macro]
func visitTokens(stream: TokenStream, stmt: #code void)
{
    for stream.count
    {
        let #alias0 = stream.tokens[cast(u32) @index]
        let #alias1 = cast(u32) @index
        #inject(stmt)
    }
}

func tokenizeWithLanguageFeatures(bytes: const [..] u8)->TokenStream
{
    declareScannerState()
    defer @assert(scanPos >= @countof(bytes))

    while scanPos < @countof(bytes)
    {
        if matchLiteral(bytes, scanPos, "don't()")
        {
            emitToken(TokenKind.Dont, 0, 0)
            scanPos += 7
            continue
        }

        if matchLiteral(bytes, scanPos, "do()")
        {
            emitToken(TokenKind.Do, 0, 0)
            scanPos += 4
            continue
        }

        if matchLiteral(bytes, scanPos, "mul(")
        {
            var lhs: s32
            var rhs: s32
            var afterLhs: u64
            var afterRhs: u64

            if parseNumber(bytes, scanPos + 4, &lhs, &afterLhs)
            {
                if afterLhs < @countof(bytes) and bytes[afterLhs] == ','
                {
                    if parseNumber(bytes, afterLhs + 1, &rhs, &afterRhs)
                    {
                        if afterRhs < @countof(bytes) and bytes[afterRhs] == ')'
                        {
                            emitToken(TokenKind.Mul, lhs, rhs)
                            scanPos = afterRhs + 1
                            continue
                        }
                    }
                }
            }
        }

        scanPos += 1
    }

    return scanTokens
}

func evaluateWithLanguageFeatures(stream: TokenStream)->MulResult
{
    declareScannerState()

    visitTokens(|tok, idx| stream)
    {
        @assert(idx < stream.count)
        switch tok.kind
        {
        case TokenKind.Do:
            scanEnabled = true
        case TokenKind.Dont:
            scanEnabled = false
        case TokenKind.Mul:
            accumulateMul(tok.lhs, tok.rhs)
        }
    }

    var result: MulResult
    result.sumAll = scanSumAll
    result.sumEnabled = scanSumEnabled
    return result
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#test
{
    let sampleStreamA = tokenizeClean(cast(const [..] u8) SampleInputA)
    let sampleCleanA  = evaluateClean(sampleStreamA)

    @assert(sampleStreamA.count == 4'u32)
    @assert(sampleCleanA.sumAll == 161)
    @assert(sampleCleanA.sumEnabled == 161)

    let sampleFeatA = evaluateWithLanguageFeatures(tokenizeWithLanguageFeatures(cast(const [..] u8) SampleInputA))
    @assert(sampleFeatA.sumAll == sampleCleanA.sumAll)
    @assert(sampleFeatA.sumEnabled == sampleCleanA.sumEnabled)
}

#test
{
    let sampleStreamB = tokenizeClean(cast(const [..] u8) SampleInputB)
    let sampleCleanB  = evaluateClean(sampleStreamB)

    @assert(sampleCleanB.sumAll == 161)
    @assert(sampleCleanB.sumEnabled == 48)

    let sampleFeatB = evaluateWithLanguageFeatures(tokenizeWithLanguageFeatures(cast(const [..] u8) SampleInputB))
    @assert(sampleFeatB.sumAll == sampleCleanB.sumAll)
    @assert(sampleFeatB.sumEnabled == sampleCleanB.sumEnabled)
}

#test
{
    let edgeStream = tokenizeClean(cast(const [..] u8) EdgeInput)
    let edgeClean  = evaluateClean(edgeStream)

    @assert(edgeStream.count == 5'u32)
    @assert(edgeClean.sumAll == 14)
    @assert(edgeClean.sumEnabled == 10)

    let edgeFeat = evaluateWithLanguageFeatures(tokenizeWithLanguageFeatures(cast(const [..] u8) EdgeInput))
    @assert(edgeFeat.sumAll == edgeClean.sumAll)
    @assert(edgeFeat.sumEnabled == edgeClean.sumEnabled)
}

#test
{
    let emptyStream = tokenizeClean(cast(const [..] u8) EmptyInput)
    let emptyClean  = evaluateClean(emptyStream)

    @assert(emptyStream.count == 0'u32)
    @assert(emptyClean.sumAll == 0)
    @assert(emptyClean.sumEnabled == 0)

    let emptyFeat = evaluateWithLanguageFeatures(tokenizeWithLanguageFeatures(cast(const [..] u8) EmptyInput))
    @assert(emptyFeat.sumAll == 0)
    @assert(emptyFeat.sumEnabled == 0)
}

#test
{
    let actualStream = tokenizeClean(cast(const [..] u8) ActualInput)
    let actualClean  = evaluateClean(actualStream)

    @assert(actualClean.sumAll == 196826776)
    @assert(actualClean.sumEnabled == 106780429)

    let actualFeat = evaluateWithLanguageFeatures(tokenizeWithLanguageFeatures(cast(const [..] u8) ActualInput))
    @assert(actualFeat.sumAll == actualClean.sumAll)
    @assert(actualFeat.sumEnabled == actualClean.sumEnabled)
}
