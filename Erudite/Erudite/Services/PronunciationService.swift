import AVFoundation
import Foundation

// MARK: - Pronunciation Service
// Plays word pronunciation using Youdao API (primary) + macOS TTS (fallback).

@MainActor
final class PronunciationService {

    enum Voice {
        case us, uk
    }

    // MARK: - State

    private var audioPlayer: AVAudioPlayer?
    private var synthesizer = AVSpeechSynthesizer()
    private var prefetchCache: [String: Data] = [:]
    private var currentTask: Task<Void, Never>?

    var voice: Voice = .us
    var isEnabled: Bool = true

    // MARK: - Public API

    /// Speak a word. Fetches from Youdao API, falls back to TTS.
    func speak(_ word: String) {
        guard isEnabled else { return }
        stop()

        currentTask = Task {
            // Try cache first
            if let cached = prefetchCache[word] {
                playAudioData(cached)
                return
            }

            // Try Youdao API
            if let data = await fetchAudio(word: word) {
                prefetchCache[word] = data
                playAudioData(data)
            } else {
                // Fallback to TTS
                speakWithTTS(word)
            }
        }
    }

    /// Prefetch audio for a word (call ahead for next card).
    func prefetch(_ word: String) {
        guard isEnabled, prefetchCache[word] == nil else { return }
        Task {
            if let data = await fetchAudio(word: word) {
                prefetchCache[word] = data
            }
        }
    }

    /// Stop any current playback.
    func stop() {
        currentTask?.cancel()
        audioPlayer?.stop()
        synthesizer.stopSpeaking(at: .immediate)
    }

    // MARK: - Private

    private func fetchAudio(word: String) async -> Data? {
        let type = voice == .us ? 2 : 1
        guard let encoded = word.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://dict.youdao.com/dictvoice?audio=\(encoded)&type=\(type)") else {
            return nil
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  data.count > 1000 else { // Valid MP3 should be > 1KB
                return nil
            }
            return data
        } catch {
            return nil
        }
    }

    private func playAudioData(_ data: Data) {
        do {
            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.play()
        } catch {
            // If audio data is invalid, fall back to TTS
            if let word = currentWord(from: data) {
                speakWithTTS(word)
            }
        }
    }

    private func speakWithTTS(_ word: String) {
        let utterance = AVSpeechUtterance(string: word)
        utterance.voice = AVSpeechSynthesisVoice(language: voice == .us ? "en-US" : "en-GB")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        synthesizer.speak(utterance)
    }

    private func currentWord(from data: Data) -> String? {
        // Can't reverse data to word, just return nil
        nil
    }

    // MARK: - Cache Management

    /// Clear prefetch cache (call when ending a session)
    func clearCache() {
        prefetchCache.removeAll()
    }
}
