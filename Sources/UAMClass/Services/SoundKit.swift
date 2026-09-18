import Foundation
import AVFoundation

// MARK: - Sonidos de interfaz
//
// Los tonos se SINTETIZAN acá, en código: no hay ningún archivo de audio en el
// proyecto. Dos razones, y las dos importan.
//
//  · Legal: los sonidos de una consola real son de su fabricante. Estos son
//    ondas generadas, propias, apenas inspiradas en la misma idea — timbres
//    blandos tipo marimba, ataque instantáneo y caída corta.
//  · Práctica: un tono generado pesa cero, no necesita bundle ni permisos, y se
//    puede afinar cambiando un número en vez de reeditar un .wav.
//
// La regla de diseño: casi inaudibles. Un sonido de interfaz que se nota es un
// sonido que molesta a la tercera vez. Estos están para que la mano sienta que
// el clic "llegó", no para llamar la atención.

@MainActor
final class SoundKit {
    static let shared = SoundKit()

    enum Cue {
        case hover      // pasar por encima: lo más leve de todo
        case select     // elegir algo en una lista
        case confirm    // aceptar, guardar, enviar
        case back       // cerrar, cancelar
        case toggle     // encender/apagar
        case alert      // algo salió mal

        /// (armónicos en Hz con su peso, duración, volumen)
        var recipe: (partials: [(Double, Double)], duration: Double, gain: Double) {
            switch self {
            case .hover:   return ([(1_760, 1.0), (3_520, 0.15)], 0.045, 0.05)
            case .select:  return ([(987.77, 1.0), (1_975.5, 0.3), (2_963, 0.1)], 0.10, 0.13)
            case .confirm: return ([(1_318.5, 1.0), (1_975.5, 0.55), (2_637, 0.2)], 0.18, 0.15)
            case .back:    return ([(659.25, 1.0), (988, 0.25)], 0.13, 0.11)
            case .toggle:  return ([(1_174.7, 1.0), (2_349, 0.2)], 0.07, 0.10)
            case .alert:   return ([(415.30, 1.0), (622, 0.5)], 0.22, 0.14)
            }
        }
    }

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var buffers: [String: AVAudioPCMBuffer] = [:]
    private var started = false
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!

    /// Lo controla `UserPrefs`. Se lee acá para no tener que pasar prefs por
    /// cada llamada, que serían decenas.
    static var enabled: Bool {
        UserDefaults.standard.object(forKey: "UAMClass.sounds") as? Bool ?? true
    }

    private init() {}

    func play(_ cue: Cue) {
        guard Self.enabled else { return }
        start()
        guard let buffer = buffer(for: cue) else { return }
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        if !player.isPlaying { player.play() }
    }

    private func start() {
        guard !started else { return }
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 1
        do {
            try engine.start()
            started = true
        } catch {
            // Sin audio disponible la app tiene que seguir funcionando igual.
            started = false
        }
    }

    // MARK: Síntesis

    private func buffer(for cue: Cue) -> AVAudioPCMBuffer? {
        let key = String(describing: cue)
        if let cached = buffers[key] { return cached }

        let (partials, duration, gain) = cue.recipe
        let rate = format.sampleRate
        let frames = AVAudioFrameCount(rate * duration)
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let channels = buf.floatChannelData else { return nil }
        buf.frameLength = frames

        let weightSum = partials.reduce(0) { $0 + $1.1 }

        for frame in 0..<Int(frames) {
            let t = Double(frame) / rate
            let progress = t / duration

            // Ataque de 4 ms para que no chasquee, y caída exponencial: es lo
            // que hace que suene a percusión de madera y no a pitido.
            let attack = min(1, t / 0.004)
            let decay = pow(1 - progress, 2.6)
            let envelope = attack * decay

            var sample = 0.0
            for (freq, weight) in partials {
                sample += sin(2 * .pi * freq * t) * weight
            }
            sample = sample / weightSum * envelope * gain

            channels[0][frame] = Float(sample)
            channels[1][frame] = Float(sample)
        }

        buffers[key] = buf
        return buf
    }
}
