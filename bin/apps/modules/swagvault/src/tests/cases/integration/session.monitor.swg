#global if #os == Swag.TargetOs.Linux and #command == Swag.CompilerCommand.Test
#global if #hastag("vault.session.integration")
#global private

using Core

// Uses a private login1 protocol fixture; never locks or suspends the host session.
#[Swag.TestTag("integration.session")]
#test
{
    var monitor: SessionWatch.Monitor
    monitor.start()
    defer monitor.stop()
    Swag.require(monitor.bus != null and monitor.inhibitor >= 0)
    var initial = monitor.poll()
    Swag.require(not initial.locked and not initial.suspending)
    Swag.require(initial.idleMilliseconds >= 90_000 and initial.idleMilliseconds < 95_000)
    for state in [1'u32, 2, 0, 3]
    {
        var reply: *void?
        let result = monitor.call(monitor.bus,
                                  SessionWatch.LoginService.buffer,
                                  SessionWatch.ManagerPath.buffer,
                                  SessionWatch.ManagerInterface.buffer,
                                  "Advance".buffer,
                                  null,
                                  &reply,
                                  "u".buffer,
                                  state)
        if reply do
            discard monitor.messageUnref(reply)
        Swag.require(result >= 0)
        let current = monitor.poll()
        Swag.require(current.locked == (state == 1 or state == 3) and current.suspending == (state == 2))
        let repeated = monitor.poll()
        Swag.require(not repeated.locked and not repeated.suspending)
        if state == 2
        {
            monitor.finishSuspend()
            Swag.require(monitor.inhibitor == -1)
            reply = null
            let status = monitor.call(monitor.bus,
                                      SessionWatch.LoginService.buffer,
                                      SessionWatch.ManagerPath.buffer,
                                      SessionWatch.ManagerInterface.buffer,
                                      "InhibitorClosed".buffer,
                                      null,
                                      &reply,
                                      "".buffer)
            Swag.require(status >= 0 and reply != null)
            var closed: s32
            Swag.require(monitor.read(reply, "b".buffer, &closed) >= 0 and closed != 0)
            discard monitor.messageUnref(reply)
        }

        if state == 0 do
            Swag.require(monitor.inhibitor >= 0)
    }

    monitor.stop()
    Swag.require(monitor.bus == null and
                monitor.systemd == null and
                monitor.display == null and
                monitor.inhibitor == -1)
}
