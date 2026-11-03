#global private

// Real-life example: route SaaS support tickets with nested switches on plan,
// priority, product area, subject tags, and impact ranges.

enum CustomerPlan: s32
{
    Trial,
    Standard,
    Business,
    Enterprise
}

enum TicketPriority: s32
{
    Low,
    Normal,
    High,
    Critical
}

enum TicketChannel: s32
{
    Email,
    Chat,
    Phone,
    Api
}

enum ProductArea: s32
{
    Billing,
    Identity,
    Automation,
    Security,
    Analytics
}

struct SupportTicket
{
    plan:          CustomerPlan
    priority:      TicketPriority
    channel:       TicketChannel
    area:          ProductArea
    impactedUsers: s32
    waitedMinutes: s32
    subjectTag:    string
}

struct TriageDecision
{
    queue:                 string
    responseTargetMinutes: s32
    escalationLevel:       s32
    pageOnCall:            bool
    notifyCustomerSuccess: bool
    sendStatusPageLink:    bool
}

func routeQueue(ticket: SupportTicket)->string
{
    switch #complete ticket.area
    {
    case .Billing:
        return "finance-ops"

    case .Identity:
        switch ticket.subjectTag
        {
        case "password-reset", "mfa-lockout":
            return "identity-urgent"

        default:
            return "identity"
        }

    case .Automation, .Analytics:
        return "platform-automation"

    case .Security:
        return "security-response"
    }
}

func computeResponseTargetMinutes(ticket: SupportTicket)->s32
{
    switch #complete ticket.plan
    {
    case .Trial:
        switch #complete ticket.priority
        {
        case .Low:
            return 1440
        case .Normal:
            return 1440
        case .High:
            return 240
        case .Critical:
            return 60
        }

    case .Standard:
        switch #complete ticket.priority
        {
        case .Low:
            return 480
        case .Normal:
            return 240
        case .High:
            return 60
        case .Critical:
            return 30
        }

    case .Business:
        switch #complete ticket.priority
        {
        case .Low:
            return 240
        case .Normal:
            return 120
        case .High:
            return 30
        case .Critical:
            return 15
        }

    case .Enterprise:
        switch #complete ticket.priority
        {
        case .Low:
            return 120
        case .Normal:
            return 60
        case .High:
            return 15
        case .Critical:
            return 5
        }
    }
}

func subjectEscalationBonus(subjectTag: string)->s32
{
    var bonus = 0
    switch subjectTag
    {
    case "security-breach":
        bonus += 2
        fallthrough

    case "mfa-lockout", "sso-outage":
        bonus += 1
        break

    case "bulk-export":
        bonus += 1
        break

    default:
        break
    }

    return bonus
}

func computeEscalationLevel(ticket: SupportTicket)->s32
{
    var level = 0

    switch #complete ticket.priority
    {
    case .Low:
        level = 0
        break

    case .Normal:
        level = 1
        break

    case .High:
        level = 2
        break

    case .Critical:
        level = 3
        break
    }

    switch ticket.impactedUsers
    {
    case 0:
        break

    case 1 to 24:
        break

    case 25 to 199:
        level += 1
        break

    default:
        level += 2
        break
    }

    switch ticket.channel
    {
    case .Phone, .Api:
        level += 1
        break

    default:
        break
    }

    level += subjectEscalationBonus(ticket.subjectTag)

    var overdueMinutes = ticket.waitedMinutes - computeResponseTargetMinutes(ticket)
    if overdueMinutes < 0 do
        overdueMinutes = 0

    switch overdueMinutes
    {
    case 0:
        break

    case 1 to 59:
        level += 1
        break

    default:
        level += 2
        break
    }

    return level
}

func buildTriageDecision(ticket: SupportTicket)->TriageDecision
{
    var result: TriageDecision =
        TriageDecision{
        queue: routeQueue(ticket),
        responseTargetMinutes: computeResponseTargetMinutes(ticket),
        escalationLevel: computeEscalationLevel(ticket),
        pageOnCall: false,
        notifyCustomerSuccess: false,
        sendStatusPageLink: false
        }

    switch #complete ticket.priority
    {
    case .Critical:
        result.pageOnCall = true
        break

    case .High:
        switch ticket.area
        {
        case .Identity, .Security:
            result.pageOnCall = true
            break

        case .Billing, .Automation, .Analytics:
            result.pageOnCall = false
            break
        }
        break

    case .Low, .Normal:
        result.pageOnCall = false
        break
    }

    switch ticket.plan
    {
    case .Business, .Enterprise:
        result.notifyCustomerSuccess = true
        break

    default:
        result.notifyCustomerSuccess = false
        break
    }

    switch ticket.subjectTag
    {
    case "security-breach", "sso-outage":
        result.sendStatusPageLink = true
        break

    default:
        switch ticket.impactedUsers
        {
        case 200 to 1000000:
            result.sendStatusPageLink = true
            break

        default:
            result.sendStatusPageLink = false
            break
        }
        break
    }

    return result
}

#test
{
    const securityIncident: SupportTicket =
        SupportTicket{
        plan: CustomerPlan.Enterprise,
        priority: TicketPriority.Critical,
        channel: TicketChannel.Api,
        area: ProductArea.Security,
        impactedUsers: 850,
        waitedMinutes: 12,
        subjectTag: "security-breach"
        }

    let securityDecision = buildTriageDecision(securityIncident)

    Swag.require(securityDecision.queue == "security-response")
    Swag.require(securityDecision.responseTargetMinutes == 5)
    Swag.require(securityDecision.escalationLevel == 10)
    Swag.require(securityDecision.pageOnCall == true)
    Swag.require(securityDecision.notifyCustomerSuccess == true)
    Swag.require(securityDecision.sendStatusPageLink == true)

    const billingRequest: SupportTicket =
        SupportTicket{
        plan: CustomerPlan.Standard,
        priority: TicketPriority.Normal,
        channel: TicketChannel.Email,
        area: ProductArea.Billing,
        impactedUsers: 3,
        waitedMinutes: 30,
        subjectTag: "invoice-copy"
        }

    let billingDecision = buildTriageDecision(billingRequest)

    Swag.require(billingDecision.queue == "finance-ops")
    Swag.require(billingDecision.responseTargetMinutes == 240)
    Swag.require(billingDecision.escalationLevel == 1)
    Swag.require(billingDecision.pageOnCall == false)
    Swag.require(billingDecision.notifyCustomerSuccess == false)
    Swag.require(billingDecision.sendStatusPageLink == false)

    const identityLockout: SupportTicket =
        SupportTicket{
        plan: CustomerPlan.Business,
        priority: TicketPriority.High,
        channel: TicketChannel.Chat,
        area: ProductArea.Identity,
        impactedUsers: 18,
        waitedMinutes: 80,
        subjectTag: "mfa-lockout"
        }

    let identityDecision = buildTriageDecision(identityLockout)

    Swag.require(identityDecision.queue == "identity-urgent")
    Swag.require(identityDecision.responseTargetMinutes == 30)
    Swag.require(identityDecision.escalationLevel == 4)
    Swag.require(identityDecision.pageOnCall == true)
    Swag.require(identityDecision.notifyCustomerSuccess == true)
    Swag.require(identityDecision.sendStatusPageLink == false)

    const analyticsBacklog: SupportTicket =
        SupportTicket{
        plan: CustomerPlan.Business,
        priority: TicketPriority.Normal,
        channel: TicketChannel.Chat,
        area: ProductArea.Analytics,
        impactedUsers: 320,
        waitedMinutes: 90,
        subjectTag: "dashboard-timeout"
        }

    let analyticsDecision = buildTriageDecision(analyticsBacklog)

    Swag.require(analyticsDecision.queue == "platform-automation")
    Swag.require(analyticsDecision.responseTargetMinutes == 120)
    Swag.require(analyticsDecision.escalationLevel == 3)
    Swag.require(analyticsDecision.pageOnCall == false)
    Swag.require(analyticsDecision.notifyCustomerSuccess == true)
    Swag.require(analyticsDecision.sendStatusPageLink == true)
}
