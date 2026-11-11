import Foundation
import Testing
@testable import ModelRuntime

@Suite("语音模型解析")
struct SpeechModelResolveTests {
    @Test("显式选择优先于目录顺序")
    func explicitPreferred() {
        let model = SpeechModel.resolve(
            preferredID: SpeechModel.whisperTurboQ4.id,
            installedIDs: [SpeechModel.qwen3ASR.id, SpeechModel.whisperTurboQ4.id]
        )
        #expect(model == .whisperTurboQ4)
    }

    @Test("自动模式优先新模型")
    func autoPrefersNew() {
        let model = SpeechModel.resolve(
            preferredID: nil,
            installedIDs: [SpeechModel.qwen3ASR.id, SpeechModel.whisperTurboQ4.id]
        )
        #expect(model == .qwen3ASR)
    }

    @Test("所选模型未安装时回退已安装的")
    func fallbackWhenMissing() {
        let model = SpeechModel.resolve(
            preferredID: SpeechModel.qwen3ASR.id,
            installedIDs: [SpeechModel.whisperTurboQ4.id]
        )
        #expect(model == .whisperTurboQ4)
    }

    @Test("未安装任何模型时返回 nil")
    func noneInstalled() {
        #expect(SpeechModel.resolve(preferredID: nil, installedIDs: []) == nil)
        #expect(SpeechModel.resolve(preferredID: "不存在的模型", installedIDs: [SpeechModel.qwen3ASR.id]) == .qwen3ASR)
    }

    @Test("体积展示")
    func sizeText() {
        #expect(SpeechModel.qwen3ASR.sizeText == "1.0 GB")
        #expect(SpeechModel.whisperTurboQ4.sizeText == "468 MB")
    }
}
