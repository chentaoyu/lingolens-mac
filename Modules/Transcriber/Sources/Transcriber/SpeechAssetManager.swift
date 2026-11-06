import Foundation
import Speech

/// 负责解析受支持的语言并安装系统语音模型。
public enum SpeechAssetManager {
    public static func resolvedLocale(for identifier: String) async -> Locale? {
        await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: identifier))
    }

    public static func supportedLocaleIdentifiers() async -> [String] {
        await SpeechTranscriber.supportedLocales.map(\.identifier)
    }

    @discardableResult
    public static func ensureInstalled(localeIdentifier: String) async throws -> Locale {
        guard let locale = await resolvedLocale(for: localeIdentifier) else {
            throw TranscriptionError.localeUnsupported(localeIdentifier)
        }

        let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        let status = await AssetInventory.status(forModules: [transcriber])
        if status != .installed {
            do {
                if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                    try await request.downloadAndInstall()
                }
            } catch {
                throw TranscriptionError.assetInstallationFailed(error.localizedDescription)
            }
        }
        return locale
    }
}
