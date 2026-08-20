import AVFoundation
import Foundation

final class SpeechPlayer: NSObject, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    private var continuation: CheckedContinuation<Void, Error>?

    var isPlaying: Bool { player?.isPlaying ?? false }

    func playAndWait(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            stopInternal(resume: .cancelled)
            continuation = cont
            do {
                let audio = try AVAudioPlayer(data: data)
                audio.delegate = self
                guard audio.prepareToPlay(), audio.play() else {
                    continuation = nil
                    cont.resume(throwing: SpeechPlayerError.couldNotStart)
                    return
                }
                player = audio
            } catch {
                continuation = nil
                cont.resume(throwing: error)
            }
        }
    }

    func stop() {
        stopInternal(resume: .cancelled)
    }

    private enum ResumeAction {
        case finished
        case cancelled
        case failed(Error)
    }

    private func stopInternal(resume: ResumeAction) {
        player?.delegate = nil
        player?.stop()
        player = nil
        if let continuation {
            self.continuation = nil
            switch resume {
            case .finished:
                continuation.resume()
            case .cancelled:
                continuation.resume(throwing: CancellationError())
            case .failed(let error):
                continuation.resume(throwing: error)
            }
        }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { [weak self] in
            if flag {
                self?.stopInternal(resume: .finished)
            } else {
                self?.stopInternal(resume: .failed(SpeechPlayerError.playbackFailed))
            }
        }
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        DispatchQueue.main.async { [weak self] in
            self?.stopInternal(resume: .failed(error ?? SpeechPlayerError.playbackFailed))
        }
    }
}

enum SpeechPlayerError: LocalizedError {
    case couldNotStart
    case playbackFailed

    var errorDescription: String? {
        switch self {
        case .couldNotStart:
            return "Could not start audio playback."
        case .playbackFailed:
            return "Audio playback failed."
        }
    }
}
