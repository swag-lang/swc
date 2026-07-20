using Core

var g_Driver: Driver

// Creates the audio engine.
// Must be called once, before anything else.
public func createEngine(kind: DriverKind = .Default) throw
{
    g_Driver.create(kind)
}

// Creates the audio engine with the no-sound driver.
public func createNoSoundEngine() throw => createEngine(.NoSound)

// Destroy the audio engine.
// Must be called at the end, when engine is no more used.
public func destroyEngine()
{
    g_Driver.destroy()
}

// Set the general output volume
public func setOutputVolume(volume: f32) throw => g_Driver.setOutputVolume(volume)

// Get the general output volume
public func getOutputVolume()->f32 => g_Driver.getOutputVolume()
