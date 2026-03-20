#global fileprivate

// Real-life example: route SaaS support tickets with nested switches on plan,
// priority, product area, subject tags, and impact ranges.

enum CustomerPlan : s32
{
    Trial,
    Standard,
    Business,
    Enterprise,
}

enum TicketPriority : s32
{
    Low,
    Normal,
    High,
    Critical,
}

enum TicketChannel : s32
{
    Email,
    Chat,
    Phone,
    Api,
}

enum ProductArea : s32
{
    Billing,
    Identity,
    Automation,
    Security,
    Analytics,
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
    switch ticket.area
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
    #[Swag.Complete]
    switch ticket.plan
    {
        case .Trial:
            #[Swag.Complete]
            switch ticket.priority
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
            #[Swag.Complete]
            switch ticket.priority
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
            #[Swag.Complete]
            switch ticket.priority
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
            #[Swag.Complete]
            switch ticket.priority
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

    #[Swag.Complete]
    switch ticket.priority
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
    var result: TriageDecision
    result.queue = routeQueue(ticket)
    result.responseTargetMinutes = computeResponseTargetMinutes(ticket)
    result.escalationLevel = computeEscalationLevel(ticket)

    #[Swag.Complete]
    switch ticket.priority
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
    {
        plan: CustomerPlan.Enterprise,
        priority: TicketPriority.Critical,
        channel: TicketChannel.Api,
        area: ProductArea.Security,
        impactedUsers: 850,
        waitedMinutes: 12,
        subjectTag: "security-breach",
    }

    let securityDecision = buildTriageDecision(securityIncident)

    @assert(securityDecision.queue == "security-response")
    @assert(securityDecision.responseTargetMinutes == 5)
    @assert(securityDecision.escalationLevel == 10)
    @assert(securityDecision.pageOnCall == true)
    @assert(securityDecision.notifyCustomerSuccess == true)
    @assert(securityDecision.sendStatusPageLink == true)

    const billingRequest: SupportTicket =
    {
        plan: CustomerPlan.Standard,
        priority: TicketPriority.Normal,
        channel: TicketChannel.Email,
        area: ProductArea.Billing,
        impactedUsers: 3,
        waitedMinutes: 30,
        subjectTag: "invoice-copy",
    }

    let billingDecision = buildTriageDecision(billingRequest)

    @assert(billingDecision.queue == "finance-ops")
    @assert(billingDecision.responseTargetMinutes == 240)
    @assert(billingDecision.escalationLevel == 1)
    @assert(billingDecision.pageOnCall == false)
    @assert(billingDecision.notifyCustomerSuccess == false)
    @assert(billingDecision.sendStatusPageLink == false)

    const identityLockout: SupportTicket =
    {
        plan: CustomerPlan.Business,
        priority: TicketPriority.High,
        channel: TicketChannel.Chat,
        area: ProductArea.Identity,
        impactedUsers: 18,
        waitedMinutes: 80,
        subjectTag: "mfa-lockout",
    }

    let identityDecision = buildTriageDecision(identityLockout)

    @assert(identityDecision.queue == "identity-urgent")
    @assert(identityDecision.responseTargetMinutes == 30)
    @assert(identityDecision.escalationLevel == 4)
    @assert(identityDecision.pageOnCall == true)
    @assert(identityDecision.notifyCustomerSuccess == true)
    @assert(identityDecision.sendStatusPageLink == false)

    const analyticsBacklog: SupportTicket =
    {
        plan: CustomerPlan.Business,
        priority: TicketPriority.Normal,
        channel: TicketChannel.Chat,
        area: ProductArea.Analytics,
        impactedUsers: 320,
        waitedMinutes: 90,
        subjectTag: "dashboard-timeout",
    }

    let analyticsDecision = buildTriageDecision(analyticsBacklog)

    @assert(analyticsDecision.queue == "platform-automation")
    @assert(analyticsDecision.responseTargetMinutes == 120)
    @assert(analyticsDecision.escalationLevel == 3)
    @assert(analyticsDecision.pageOnCall == false)
    @assert(analyticsDecision.notifyCustomerSuccess == true)
    @assert(analyticsDecision.sendStatusPageLink == true)
}
