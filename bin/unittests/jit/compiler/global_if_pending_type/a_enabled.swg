#global if true
#global namespace Probe
private struct State { value: s32 = 42 }
private func state(value: *void)->*State => cast(*State, value)
#test { var value: State; Swag.assert(state(&value).value == 42) }
