#global if #os == Swag.TargetOs.Linux and #command == Swag.CompilerCommand.Test
#global if #hastag("vault.session.x11")
#global private
using Core

#[Swag.TestTag("integration.session.x11")]
#test
{
    var monitor: SessionWatch.Monitor
    monitor.start()
    defer monitor.stop()
    Swag.assert(monitor.display != null)
    let before = monitor.poll().idleMilliseconds
    Threading.Thread.sleep(Time.Duration.fromMilliseconds(60))
    let after = monitor.poll().idleMilliseconds
    Swag.assert(after >= before + 30)
    monitor.stop()
    Swag.assert(monitor.display == null and monitor.xlib == null and monitor.xss == null)
}
