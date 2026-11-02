#global if Probe.Disabled
#global public
#global namespace Probe
private struct State { unused: UnknownType }
private func state(value: *void)->*State => cast(*State, value)
