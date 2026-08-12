import Foundation

/// Container/codec used when writing stems and exports.
///
/// Deliberately a short list of formats a DAW will open. Opus and Vorbis are
/// left out despite being efficient: support in music software is patchy, and a
/// stem you cannot import is worthless however small it is.
enum AudioFormat: String, CaseIterable, Identifiable, Equatable {
    case wav
    case flac
    case alac
    case mp3
    case aac

    var id: String { rawValue }

    var fileExtension: String {
        switch self {
        case .wav: return "wav"
        case .flac: return "flac"
        case .alac, .aac: return "m4a"
        case .mp3: return "mp3"
        }
    }

    var title: String {
        switch self {
        case .wav: return "WAV"
        case .flac: return "FLAC"
        case .alac: return "ALAC"
        case .mp3: return "MP3"
        case .aac: return "AAC"
        }
    }

    var detail: String {
        switch self {
        case .wav: return "Uncompressed. Largest files, universally supported."
        case .flac: return "Lossless, roughly half the size of WAV."
        case .alac: return "Apple Lossless, in an .m4a container."
        case .mp3: return "Lossy. Smallest and the most widely playable."
        case .aac: return "Lossy, better quality than MP3 at the same bitrate."
        }
    }

    var isLossy: Bool {
        switch self {
        case .mp3, .aac: return true
        case .wav, .flac, .alac: return false
        }
    }

    /// Rough size of a 3-minute stereo stem, for the size hint in the UI.
    func approximateSizeDescription(bitrateKbps: Int) -> String {
        switch self {
        case .wav: return "~30 MB per stem"
        case .flac: return "~15 MB per stem"
        case .alac: return "~16 MB per stem"
        case .mp3, .aac: return "~\(max(1, bitrateKbps * 180 / 8 / 1000)) MB per stem"
        }
    }

    /// ffmpeg encoder selection. Verified present in ffmpeg 7.1: libmp3lame,
    /// aac, alac and flac are all built in.
    func encoderArguments(bitrateKbps: Int) -> [String] {
        switch self {
        case .wav:
            return ["-c:a", "pcm_s16le"]
        case .flac:
            return ["-c:a", "flac", "-compression_level", "5"]
        case .alac:
            return ["-c:a", "alac"]
        case .mp3:
            return ["-c:a", "libmp3lame", "-b:a", "\(bitrateKbps)k"]
        case .aac:
            return ["-c:a", "aac", "-b:a", "\(bitrateKbps)k"]
        }
    }
}

/// Bitrates offered for the lossy formats.
enum AudioBitrate: Int, CaseIterable, Identifiable, Equatable {
    case k128 = 128
    case k192 = 192
    case k256 = 256
    case k320 = 320

    var id: Int { rawValue }
    var title: String { "\(rawValue) kbps" }

    static let `default` = AudioBitrate.k320
}
