using Core

var g_Driver: Driver

// Creates the process-wide audio engine.
//
// Call this once before using [[Audio.SoundFile]], [[Audio.Voice]], or
// [[Audio.Bus]]. `kind` selects the native or headless backend. Pair a
// successful call with [[Audio.destroyEngine]] after all voices and buses have
// been released.
public func createEngine(kind: DriverKind = .Default) fail
{
    g_Driver.create(kind)
}

// Creates the process-wide engine without opening an audio device.
//
// This is equivalent to [[Audio.createEngine]] with
// [[Audio.DriverKind.NoSound]] and is intended for deterministic tests and
// headless programs.
public func createNoSoundEngine() fail => createEngine(.NoSound)

// Destroys the process-wide audio engine and its backend resources.
//
// All voices and buses must have finished or been destroyed before this call.
public func destroyEngine()
{
    g_Driver.destroy()
}

// Sets the mastering output gain.
//
// `volume` is a linear gain. Backend implementations may clamp it to their
// supported range.
public func setOutputVolume(volume: f32) fail => g_Driver.setOutputVolume(volume)

// Returns the current mastering output gain as a linear value.
public func getOutputVolume()->f32 => g_Driver.getOutputVolume()
