#global fileprivate

// Real-life example: discover internal admin API handlers with `#message` and
// generate a strongly typed registry from attributes. Adding one annotated
// function automatically creates request envelopes, invoke shims, route
// metadata, and lookup helpers without maintaining a manual registration table.

using Swag

#[AttrUsage(AttributeUsage.Function)]
attr AdminRoute(method: string, path: string, permission: string, auditCode: string, critical: bool = false)

public struct InvoiceDeliveryReceipt
{
    updated:        bool
    recipientCount: s32
}

var RebuildCacheCalls = 0
var RebuildLastFull  = false
var RebuildLastIndex = ""

#[AdminRoute("GET", "/tenants/:tenantId/users", "tenant.read", "tenant.users.list")]
public func listTenantUsers(tenantId: s64, includeSuspended: bool)->s32
{
    var count = cast(s32) (tenantId % 100)
    if includeSuspended do
        count += 5
    return count
}

#[AdminRoute("POST", "/tenants/:tenantId/rotate-api-keys", "tenant.write", "tenant.keys.rotate", true)]
public func rotateTenantApiKeys(tenantId: s64, actorEmail: string, forceRevoke: bool)->bool
{
    if tenantId <= 0 do
        return false
    if @countof(actorEmail) < 12 do
        return false
    return forceRevoke
}

#[AdminRoute("POST", "/billing/invoice-delivery", "billing.write", "billing.delivery.update")]
public func setInvoiceDelivery(tenantId: s64, billingEmail: string, sendCopyToOps: bool)->InvoiceDeliveryReceipt
{
    var recipientCount = 1
    if sendCopyToOps do
        recipientCount = 2

    return {updated: tenantId > 0 and @countof(billingEmail) >= 8, recipientCount: recipientCount}
}

#[AdminRoute("POST", "/internal/search/rebuild-cache", "ops.write", "search.cache.rebuild", true)]
public func rebuildSearchCache(indexName: string, full: bool)
{
    RebuildCacheCalls += 1
    RebuildLastFull = full
    RebuildLastIndex = indexName
}

struct AdminRouteRegistration
{
    type:        typeinfo
    handlerName: string
    method:      string
    path:        string
    permission:  string
    auditCode:   string
    critical:    bool
}

const MaxAdminRoutes = 16

#[Compiler]
var g_AdminRoutes: [MaxAdminRoutes] AdminRouteRegistration

#[Compiler]
var g_AdminRouteCount: s32

#[Compiler]
func countPathParams(path: string)->s32
{
    var count: s32
    foreach c in path
    {
        if c == ':' do
            count += 1
    }

    return count
}

#[Compiler]
func appendAst(buffer: [*] u8, start: u64, text: string)->u64
{
    @memcpy(buffer + start, @dataof(text), @countof(text))
    return start + @countof(text)
}

#[Compiler]
func appendS32Literal(buffer: [*] u8, start: u64, value: s32)->u64
{
    var len = start
    var v   = cast(s64) value

    if v < 0
    {
        buffer[len] = '-'
        len += 1
        v = -v
    }

    if v == 0
    {
        buffer[len] = '0'
        return len + 1
    }

    var tmp: [24] u8
    var tmpLen: u64
    while true
    {
        if v == 0 do
            break
        tmp[tmpLen] = cast(u8) (v % 10) + '0'
        tmpLen += 1
        v /= 10
    }

    for #reverse i in tmpLen
    {
        buffer[len] = tmp[i]
        len += 1
    }

    return len
}

#[Compiler]
func appendBoolLiteral(buffer: [*] u8, start: u64, value: bool)->u64
{
    if value do
        return appendAst(buffer, start, "true")
    return appendAst(buffer, start, "false")
}

#message(CompilerMsgMask.SemFunctions)
{
    let msg = @compiler.getMessage()
    if msg == null or msg.type == null do
        return

    let typeFunc = cast(const *TypeInfoFunc) msg.type

    foreach attribute in typeFunc.attributes
    {
        if attribute.type != #typeof(AdminRoute) do
            continue

        @assert(g_AdminRouteCount < MaxAdminRoutes)
        g_AdminRoutes[g_AdminRouteCount] = {
            type: msg.type,
            handlerName: msg.name,
            method: cast(string) attribute.params[0].value,
            path: cast(string) attribute.params[1].value,
            permission: cast(string) attribute.params[2].value,
            auditCode: cast(string) attribute.params[3].value,
            critical: cast(bool) attribute.params[4].value,
        }
        g_AdminRouteCount += 1
    }
}

#message(CompilerMsgMask.PassAfterSemantic)
{
    let itf = @compiler
    var buffer: [65536] u8
    var len = 0'u64

    for var routeIndex = 0; routeIndex < g_AdminRouteCount; routeIndex += 1
    {
        let route    = g_AdminRoutes[routeIndex]
        let typeFunc = cast(const *TypeInfoFunc) route.type

        len = appendAst(&buffer[0], len, "struct AdminRouteRequest_")
        len = appendAst(&buffer[0], len, route.handlerName)
        len = appendAst(&buffer[0], len, "\n{\n")
        foreach parameter in typeFunc.parameters
        {
            len = appendAst(&buffer[0], len, "    ")
            len = appendAst(&buffer[0], len, parameter.name)
            len = appendAst(&buffer[0], len, ": ")
            len = appendAst(&buffer[0], len, parameter.pointedType.name)
            len = appendAst(&buffer[0], len, "\n")
        }
        len = appendAst(&buffer[0], len, "}\n\n")

        len = appendAst(&buffer[0], len, "func invokeAdminRoute_")
        len = appendAst(&buffer[0], len, route.handlerName)
        len = appendAst(&buffer[0], len, "(request: const &AdminRouteRequest_")
        len = appendAst(&buffer[0], len, route.handlerName)
        len = appendAst(&buffer[0], len, ")")
        if typeFunc.returnType != null and typeFunc.returnType != void
        {
            len = appendAst(&buffer[0], len, "->")
            len = appendAst(&buffer[0], len, typeFunc.returnType.name)
        }

        len = appendAst(&buffer[0], len, "\n{\n    ")
        if typeFunc.returnType != null and typeFunc.returnType != void do
            len = appendAst(&buffer[0], len, "return ")

        len = appendAst(&buffer[0], len, route.handlerName)
        len = appendAst(&buffer[0], len, "(")
        foreach parameter, index in typeFunc.parameters
        {
            if index != 0 do
                len = appendAst(&buffer[0], len, ", ")
            len = appendAst(&buffer[0], len, "request.")
            len = appendAst(&buffer[0], len, parameter.name)
        }
        len = appendAst(&buffer[0], len, ")\n}\n\n")
    }

    len = appendAst(&buffer[0], len, "const GeneratedAdminRouteCount = ")
    len = appendS32Literal(&buffer[0], len, g_AdminRouteCount)
    len = appendAst(&buffer[0], len, "\n\n")

    len = appendAst(&buffer[0], len, "struct GeneratedAdminRouteDescriptor\n{\n")
    len = appendAst(&buffer[0], len, "    handler:        string\n")
    len = appendAst(&buffer[0], len, "    method:         string\n")
    len = appendAst(&buffer[0], len, "    path:           string\n")
    len = appendAst(&buffer[0], len, "    permission:     string\n")
    len = appendAst(&buffer[0], len, "    auditCode:      string\n")
    len = appendAst(&buffer[0], len, "    pathParamCount: s32\n")
    len = appendAst(&buffer[0], len, "    paramCount:     s32\n")
    len = appendAst(&buffer[0], len, "    critical:       bool\n")
    len = appendAst(&buffer[0], len, "    returnsValue:   bool\n")
    len = appendAst(&buffer[0], len, "}\n\n")

    len = appendAst(&buffer[0], len, "func getGeneratedAdminRoute(index: s32)->GeneratedAdminRouteDescriptor\n{\n")
    len = appendAst(&buffer[0], len, "    switch index\n    {\n")
    for var routeIndex = 0; routeIndex < g_AdminRouteCount; routeIndex += 1
    {
        let route        = g_AdminRoutes[routeIndex]
        let typeFunc     = cast(const *TypeInfoFunc) route.type
        let returnsValue = typeFunc.returnType != null and typeFunc.returnType != void
        len = appendAst(&buffer[0], len, "        case ")
        len = appendS32Literal(&buffer[0], len, routeIndex)
        len = appendAst(&buffer[0], len, ": return {\n")
        len = appendAst(&buffer[0], len, "            handler: \"")
        len = appendAst(&buffer[0], len, route.handlerName)
        len = appendAst(&buffer[0], len, "\",\n")
        len = appendAst(&buffer[0], len, "            method: \"")
        len = appendAst(&buffer[0], len, route.method)
        len = appendAst(&buffer[0], len, "\",\n")
        len = appendAst(&buffer[0], len, "            path: \"")
        len = appendAst(&buffer[0], len, route.path)
        len = appendAst(&buffer[0], len, "\",\n")
        len = appendAst(&buffer[0], len, "            permission: \"")
        len = appendAst(&buffer[0], len, route.permission)
        len = appendAst(&buffer[0], len, "\",\n")
        len = appendAst(&buffer[0], len, "            auditCode: \"")
        len = appendAst(&buffer[0], len, route.auditCode)
        len = appendAst(&buffer[0], len, "\",\n")
        len = appendAst(&buffer[0], len, "            pathParamCount: ")
        len = appendS32Literal(&buffer[0], len, countPathParams(route.path))
        len = appendAst(&buffer[0], len, ",\n")
        len = appendAst(&buffer[0], len, "            paramCount: ")
        len = appendS32Literal(&buffer[0], len, cast(s32) @countof(typeFunc.parameters))
        len = appendAst(&buffer[0], len, ",\n")
        len = appendAst(&buffer[0], len, "            critical: ")
        len = appendBoolLiteral(&buffer[0], len, route.critical)
        len = appendAst(&buffer[0], len, ",\n")
        len = appendAst(&buffer[0], len, "            returnsValue: ")
        len = appendBoolLiteral(&buffer[0], len, returnsValue)
        len = appendAst(&buffer[0], len, ",\n")
        len = appendAst(&buffer[0], len, "        }\n")
    }
    len = appendAst(&buffer[0], len, "    }\n\n")
    len = appendAst(&buffer[0], len, "    return {\n")
    len = appendAst(&buffer[0], len, "        handler: \"\",\n")
    len = appendAst(&buffer[0], len, "        method: \"\",\n")
    len = appendAst(&buffer[0], len, "        path: \"\",\n")
    len = appendAst(&buffer[0], len, "        permission: \"\",\n")
    len = appendAst(&buffer[0], len, "        auditCode: \"\",\n")
    len = appendAst(&buffer[0], len, "        pathParamCount: 0,\n")
    len = appendAst(&buffer[0], len, "        paramCount: 0,\n")
    len = appendAst(&buffer[0], len, "        critical: false,\n")
    len = appendAst(&buffer[0], len, "        returnsValue: false,\n")
    len = appendAst(&buffer[0], len, "    }\n")
    len = appendAst(&buffer[0], len, "}\n\n")

    len = appendAst(&buffer[0], len, "func getGeneratedAdminRouteHandler(index: s32)->string\n{\n")
    len = appendAst(&buffer[0], len, "    switch index\n    {\n")
    for var routeIndex = 0; routeIndex < g_AdminRouteCount; routeIndex += 1
    {
        let route = g_AdminRoutes[routeIndex]
        len = appendAst(&buffer[0], len, "        case ")
        len = appendS32Literal(&buffer[0], len, routeIndex)
        len = appendAst(&buffer[0], len, ": return \"")
        len = appendAst(&buffer[0], len, route.handlerName)
        len = appendAst(&buffer[0], len, "\"\n")
    }
    len = appendAst(&buffer[0], len, "    }\n\n")
    len = appendAst(&buffer[0], len, "    return \"\"\n")
    len = appendAst(&buffer[0], len, "}\n\n")

    len = appendAst(&buffer[0], len, "func getGeneratedAdminRouteAuditCode(index: s32)->string\n{\n")
    len = appendAst(&buffer[0], len, "    switch index\n    {\n")
    for var routeIndex = 0; routeIndex < g_AdminRouteCount; routeIndex += 1
    {
        let route = g_AdminRoutes[routeIndex]
        len = appendAst(&buffer[0], len, "        case ")
        len = appendS32Literal(&buffer[0], len, routeIndex)
        len = appendAst(&buffer[0], len, ": return \"")
        len = appendAst(&buffer[0], len, route.auditCode)
        len = appendAst(&buffer[0], len, "\"\n")
    }
    len = appendAst(&buffer[0], len, "    }\n\n")
    len = appendAst(&buffer[0], len, "    return \"\"\n")
    len = appendAst(&buffer[0], len, "}\n\n")

    len = appendAst(&buffer[0], len, "func getGeneratedAdminRoutePathParamCount(index: s32)->s32\n{\n")
    len = appendAst(&buffer[0], len, "    switch index\n    {\n")
    for var routeIndex = 0; routeIndex < g_AdminRouteCount; routeIndex += 1
    {
        let route = g_AdminRoutes[routeIndex]
        len = appendAst(&buffer[0], len, "        case ")
        len = appendS32Literal(&buffer[0], len, routeIndex)
        len = appendAst(&buffer[0], len, ": return ")
        len = appendS32Literal(&buffer[0], len, countPathParams(route.path))
        len = appendAst(&buffer[0], len, "\n")
    }
    len = appendAst(&buffer[0], len, "    }\n\n")
    len = appendAst(&buffer[0], len, "    return 0\n")
    len = appendAst(&buffer[0], len, "}\n\n")

    len = appendAst(&buffer[0], len, "func getGeneratedAdminRouteParamCount(index: s32)->s32\n{\n")
    len = appendAst(&buffer[0], len, "    switch index\n    {\n")
    for var routeIndex = 0; routeIndex < g_AdminRouteCount; routeIndex += 1
    {
        let route    = g_AdminRoutes[routeIndex]
        let typeFunc = cast(const *TypeInfoFunc) route.type
        len = appendAst(&buffer[0], len, "        case ")
        len = appendS32Literal(&buffer[0], len, routeIndex)
        len = appendAst(&buffer[0], len, ": return ")
        len = appendS32Literal(&buffer[0], len, cast(s32) @countof(typeFunc.parameters))
        len = appendAst(&buffer[0], len, "\n")
    }
    len = appendAst(&buffer[0], len, "    }\n\n")
    len = appendAst(&buffer[0], len, "    return 0\n")
    len = appendAst(&buffer[0], len, "}\n\n")

    len = appendAst(&buffer[0], len, "func isGeneratedAdminRouteCritical(index: s32)->bool\n{\n")
    len = appendAst(&buffer[0], len, "    switch index\n    {\n")
    for var routeIndex = 0; routeIndex < g_AdminRouteCount; routeIndex += 1
    {
        let route = g_AdminRoutes[routeIndex]
        len = appendAst(&buffer[0], len, "        case ")
        len = appendS32Literal(&buffer[0], len, routeIndex)
        len = appendAst(&buffer[0], len, ": return ")
        len = appendBoolLiteral(&buffer[0], len, route.critical)
        len = appendAst(&buffer[0], len, "\n")
    }
    len = appendAst(&buffer[0], len, "    }\n\n")
    len = appendAst(&buffer[0], len, "    return false\n")
    len = appendAst(&buffer[0], len, "}\n\n")

    len = appendAst(&buffer[0], len, "func generatedAdminRouteReturnsValue(index: s32)->bool\n{\n")
    len = appendAst(&buffer[0], len, "    switch index\n    {\n")
    for var routeIndex = 0; routeIndex < g_AdminRouteCount; routeIndex += 1
    {
        let route        = g_AdminRoutes[routeIndex]
        let typeFunc     = cast(const *TypeInfoFunc) route.type
        let returnsValue = typeFunc.returnType != null and typeFunc.returnType != void
        len = appendAst(&buffer[0], len, "        case ")
        len = appendS32Literal(&buffer[0], len, routeIndex)
        len = appendAst(&buffer[0], len, ": return ")
        len = appendBoolLiteral(&buffer[0], len, returnsValue)
        len = appendAst(&buffer[0], len, "\n")
    }
    len = appendAst(&buffer[0], len, "    }\n\n")
    len = appendAst(&buffer[0], len, "    return false\n")
    len = appendAst(&buffer[0], len, "}\n\n")

    len = appendAst(&buffer[0], len, "func findGeneratedAdminRoute(method: string, path: string)->s32\n{\n")
    for var routeIndex = 0; routeIndex < g_AdminRouteCount; routeIndex += 1
    {
        let route = g_AdminRoutes[routeIndex]
        len = appendAst(&buffer[0], len, "    if method == \"")
        len = appendAst(&buffer[0], len, route.method)
        len = appendAst(&buffer[0], len, "\" and path == \"")
        len = appendAst(&buffer[0], len, route.path)
        len = appendAst(&buffer[0], len, "\" do\n        return ")
        len = appendS32Literal(&buffer[0], len, routeIndex)
        len = appendAst(&buffer[0], len, "\n")
    }
    len = appendAst(&buffer[0], len, "    return -1\n")
    len = appendAst(&buffer[0], len, "}\n\n")

    len = appendAst(&buffer[0], len, "func countCriticalAdminRoutes()->s32\n{\n")
    len = appendAst(&buffer[0], len, "    var count: s32\n")
    for var routeIndex = 0; routeIndex < g_AdminRouteCount; routeIndex += 1
    {
        let route = g_AdminRoutes[routeIndex]
        if route.critical do
            len = appendAst(&buffer[0], len, "    count += 1\n")
    }
    len = appendAst(&buffer[0], len, "    return count\n")
    len = appendAst(&buffer[0], len, "}\n")

    let source = cast(string) @mkslice(&buffer[0], len)
    itf.compileString(source)
}

#test
{
    @assert(GeneratedAdminRouteCount == 4)
    @assert(countCriticalAdminRoutes() == 2)

    let usersIndex = findGeneratedAdminRoute("GET", "/tenants/:tenantId/users")
    @assert(usersIndex != -1)
    let users = getGeneratedAdminRoute(usersIndex)
    @assert(users.handler == "listTenantUsers")
    @assert(users.method == "GET")
    @assert(users.path == "/tenants/:tenantId/users")
    @assert(users.permission == "tenant.read")
    @assert(users.auditCode == "tenant.users.list")
    @assert(users.pathParamCount == 1)
    @assert(users.paramCount == 2)
    @assert(!users.critical)
    @assert(users.returnsValue)

    let rotateIndex = findGeneratedAdminRoute("POST", "/tenants/:tenantId/rotate-api-keys")
    @assert(rotateIndex != -1)
    let rotate = getGeneratedAdminRoute(rotateIndex)
    @assert(rotate.handler == "rotateTenantApiKeys")
    @assert(rotate.method == "POST")
    @assert(rotate.path == "/tenants/:tenantId/rotate-api-keys")
    @assert(rotate.permission == "tenant.write")
    @assert(rotate.auditCode == "tenant.keys.rotate")
    @assert(rotate.pathParamCount == 1)
    @assert(rotate.paramCount == 3)
    @assert(rotate.critical)
    @assert(rotate.returnsValue)

    let deliveryIndex = findGeneratedAdminRoute("POST", "/billing/invoice-delivery")
    @assert(deliveryIndex != -1)
    let delivery = getGeneratedAdminRoute(deliveryIndex)
    @assert(delivery.handler == "setInvoiceDelivery")
    @assert(delivery.pathParamCount == 0)
    @assert(delivery.paramCount == 3)
    @assert(!delivery.critical)
    @assert(delivery.returnsValue)

    let rebuildIndex = findGeneratedAdminRoute("POST", "/internal/search/rebuild-cache")
    @assert(rebuildIndex != -1)
    let rebuild = getGeneratedAdminRoute(rebuildIndex)
    @assert(rebuild.handler == "rebuildSearchCache")
    @assert(rebuild.permission == "ops.write")
    @assert(rebuild.auditCode == "search.cache.rebuild")
    @assert(rebuild.pathParamCount == 0)
    @assert(rebuild.paramCount == 2)
    @assert(rebuild.critical)
    @assert(!rebuild.returnsValue)

    let missing = getGeneratedAdminRoute(99)
    @assert(missing.handler == "")
    @assert(findGeneratedAdminRoute("DELETE", "/missing") == -1)
}

#test
{
    let listReq: AdminRouteRequest_listTenantUsers =
    {
        tenantId: 42,
        includeSuspended: true,
    }

    let rotateReq: AdminRouteRequest_rotateTenantApiKeys =
    {
        tenantId: 12,
        actorEmail: "ops@tenant.test",
        forceRevoke: true,
    }

    let deliveryReq: AdminRouteRequest_setInvoiceDelivery =
    {
        tenantId: 7,
        billingEmail: "billing@tenant.test",
        sendCopyToOps: true,
    }

    @assert(invokeAdminRoute_listTenantUsers(listReq) == 47)
    @assert(invokeAdminRoute_rotateTenantApiKeys(rotateReq))

    let receipt = invokeAdminRoute_setInvoiceDelivery(deliveryReq)
    @assert(receipt.updated)
    @assert(receipt.recipientCount == 2)
}

#test
{
    RebuildCacheCalls = 0
    RebuildLastFull = false
    RebuildLastIndex = ""

    let rebuildReq: AdminRouteRequest_rebuildSearchCache =
    {
        indexName: "catalog-search",
        full: true,
    }

    invokeAdminRoute_rebuildSearchCache(rebuildReq)

    @assert(RebuildCacheCalls == 1)
    @assert(RebuildLastFull)
    @assert(RebuildLastIndex == "catalog-search")
}
