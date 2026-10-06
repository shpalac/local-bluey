import AVFoundation
import FlutterMacOS

/// Failures the Dart side maps to SttErrorKind.decoderError (#196/#197).
enum AudioDecoderError: Error {
  /// The file could not be opened or parsed as media.
  case unreadable
  /// The file parses but carries no audio samples.
  case empty
  /// The file parses but has no audio track.
  case noAudioTrack
  /// Longer than the hard duration cap.
  case tooLong
  /// Decoded output exceeded the size cap.
  case tooLarge
  /// AVAssetReader failed mid-stream.
  case readerFailed
}

/// Decoded mono 16 kHz Int16 PCM.
struct DecodedPcm {
  let data: Data
  let sampleRate: Int
  let durationMs: Int
}

/// m4a (AAC-LC) -> PCM via AVFoundation (#197 prework): every local STT
/// backend (whisper.cpp, sherpa-onnx) consumes PCM, not the recorded AAC.
/// Decoding is fully in memory - no intermediate files are written, so the
/// capture cleanup behavior (#116/#128) is unchanged.
enum AudioDecoder {
  /// Output sample rate every STT backend here expects.
  static let sampleRate = 16000

  /// Hard duration cap; AudioCapture already caps at 2 minutes (#117),
  /// this is the defensive backstop.
  static let maxDurationSeconds: Double = 600

  /// Sanity cap on decoded output (600s * 16kHz * 2B is ~19MB).
  static let maxOutputBytes = 40 * 1024 * 1024

  /// Decodes the m4a at [path] to mono 16 kHz Int16 PCM. Stereo or
  /// multi-channel input is downmixed; any input sample rate is resampled.
  static func decodeM4a(at path: String) throws -> DecodedPcm {
    let url = URL(fileURLWithPath: path)
    let asset = AVURLAsset(url: url)
    let (duration, track) = try loadDurationAndTrack(asset)

    let seconds = CMTimeGetSeconds(duration)
    guard seconds.isFinite, seconds > 0 else { throw AudioDecoderError.empty }
    guard seconds <= maxDurationSeconds else { throw AudioDecoderError.tooLong }

    let reader: AVAssetReader
    do {
      reader = try AVAssetReader(asset: asset)
    } catch {
      throw AudioDecoderError.unreadable
    }

    let outputSettings: [String: Any] = [
      AVFormatIDKey: kAudioFormatLinearPCM,
      AVSampleRateKey: sampleRate,
      AVNumberOfChannelsKey: 1,
      AVLinearPCMBitDepthKey: 16,
      AVLinearPCMIsFloatKey: false,
      AVLinearPCMIsBigEndianKey: false,
      AVLinearPCMIsNonInterleaved: false,
    ]
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
    guard reader.canAdd(output) else { throw AudioDecoderError.unreadable }
    reader.add(output)
    guard reader.startReading() else { throw AudioDecoderError.unreadable }

    var pcm = Data()
    pcm.reserveCapacity(Int(seconds * Double(sampleRate) * 2) + 4096)
    while reader.status == .reading {
      guard let buffer = output.copyNextSampleBuffer() else { break }
      guard let blockBuffer = CMSampleBufferGetDataBuffer(buffer) else { continue }
      var length = 0
      var pointer: UnsafeMutablePointer<Int8>?
      let status = CMBlockBufferGetDataPointer(
        blockBuffer, atOffset: 0, lengthAtOffsetOut: nil,
        totalLengthOut: &length, dataPointerOut: &pointer)
      if status == kCMBlockBufferNoErr, let pointer {
        pcm.append(pointer, count: length)
      }
      if pcm.count > maxOutputBytes {
        reader.cancelReading()
        throw AudioDecoderError.tooLarge
      }
    }

    guard reader.status != .failed else { throw AudioDecoderError.readerFailed }
    guard !pcm.isEmpty else { throw AudioDecoderError.empty }

    return DecodedPcm(
      data: pcm, sampleRate: sampleRate, durationMs: Int(seconds * 1000))
  }

  /// Loads duration and the first audio track with the modern async API,
  /// bridged to sync because the channel handler is a plain callback.
  private static func loadDurationAndTrack(
    _ asset: AVURLAsset
  ) throws -> (CMTime, AVAssetTrack) {
    let semaphore = DispatchSemaphore(value: 0)
    var loadedDuration: CMTime?
    var loadedTracks: [AVAssetTrack]?
    var loadFailed = false
    Task {
      do {
        loadedDuration = try await asset.load(.duration)
        loadedTracks = try await asset.load(.tracks)
      } catch {
        loadFailed = true
      }
      semaphore.signal()
    }
    semaphore.wait()
    if loadFailed { throw AudioDecoderError.unreadable }
    guard let duration = loadedDuration else { throw AudioDecoderError.unreadable }
    guard let track = loadedTracks?.first(where: { $0.mediaType == .audio })
    else { throw AudioDecoderError.noAudioTrack }
    return (duration, track)
  }
}

/// Flutter MethodChannel exposing [AudioDecoder] to Dart (#197 prework).
final class AudioDecoderChannel {
  static let name = "local_bluey/audio"

  static func register(with controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: name, binaryMessenger: controller.engine.binaryMessenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "decodeM4aToPcm":
        let args = call.arguments as? [String: Any] ?? [:]
        guard let path = args["path"] as? String, !path.isEmpty else {
          result(FlutterError(
            code: "bad_args", message: "decodeM4aToPcm needs a path", details: nil))
          return
        }
        // Decode off the main thread; answer on it.
        DispatchQueue.global(qos: .userInitiated).async {
          do {
            let pcm = try AudioDecoder.decodeM4a(at: path)
            DispatchQueue.main.async {
              result([
                "pcm": FlutterStandardTypedData(bytes: pcm.data),
                "sampleRate": pcm.sampleRate,
                "durationMs": pcm.durationMs,
              ])
            }
          } catch let error as AudioDecoderError {
            DispatchQueue.main.async {
              result(FlutterError(
                code: "decoder_error",
                message: String(describing: error),
                details: nil))
            }
          } catch {
            DispatchQueue.main.async {
              result(FlutterError(
                code: "decoder_error",
                message: error.localizedDescription,
                details: nil))
            }
          }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
