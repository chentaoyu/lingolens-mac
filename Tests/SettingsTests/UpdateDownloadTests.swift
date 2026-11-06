import Foundation
import Testing
@testable import Settings

private let official = URL(string: "https://github.com/chentaoyu/lingolens-mac/releases/download/v0.1.4/LingoLens-0.1.4.dmg")!

@Suite("更新下载源")
struct UpdateDownloadResolverTests {
    @Test("仅官方时只有一个候选")
    func officialOnly() {
        let urls = UpdateDownloadResolver.candidates(
            official: official,
            settings: UpdateDownloadSettings(source: .official)
        )
        #expect(urls == [official])
    }

    @Test("自动模式：官方优先，内置镜像作为备选")
    func automaticCandidates() {
        let urls = UpdateDownloadResolver.candidates(
            official: official,
            settings: UpdateDownloadSettings(source: .automatic)
        )
        #expect(urls.first == official)
        #expect(urls.count == 1 + UpdateDownloadSettings.builtinMirrorPrefixes.count)
        #expect(urls[1].absoluteString == "https://gh-proxy.com/" + official.absoluteString)
    }

    @Test("自定义镜像模板使用 {url} 占位符")
    func customMirrorTemplate() {
        let url = UpdateDownloadResolver.customURL(
            official: official,
            template: "https://mirror.example.com/{url}"
        )
        #expect(url?.absoluteString == "https://mirror.example.com/" + official.absoluteString)
    }

    @Test("自定义 CDN 模板按前缀 + 文件名拼接")
    func customCDNTemplate() {
        #expect(
            UpdateDownloadResolver.customURL(official: official, template: "https://cdn.example.com/updates")?.absoluteString
                == "https://cdn.example.com/updates/LingoLens-0.1.4.dmg"
        )
        #expect(
            UpdateDownloadResolver.customURL(official: official, template: "https://cdn.example.com/updates/")?.absoluteString
                == "https://cdn.example.com/updates/LingoLens-0.1.4.dmg"
        )
    }

    @Test("自定义模板非法时回退官方")
    func invalidCustomTemplate() {
        let settings = UpdateDownloadSettings(source: .custom, customURLTemplate: "not a url")
        let urls = UpdateDownloadResolver.candidates(official: official, settings: settings)
        #expect(urls == [official])
    }

    @Test("官方源最快时保持官方")
    func prefersOfficial() {
        let mirror = URL(string: "https://gh-proxy.com/" + official.absoluteString)!
        let chosen = UpdateDownloadResolver.choose(
            candidates: [official, mirror],
            measuredBytesPerSecond: [official: 200_000, mirror: 260_000],
            official: official
        )
        #expect(chosen == official)
    }

    @Test("官方不可用时切到镜像")
    func fallsBackToMirror() {
        let mirror = URL(string: "https://gh-proxy.com/" + official.absoluteString)!
        let chosen = UpdateDownloadResolver.choose(
            candidates: [official, mirror],
            measuredBytesPerSecond: [mirror: 200_000],
            official: official
        )
        #expect(chosen == mirror)
    }

    @Test("镜像明显更快时切换")
    func usesFasterMirror() {
        let mirror = URL(string: "https://gh-proxy.com/" + official.absoluteString)!
        let chosen = UpdateDownloadResolver.choose(
            candidates: [official, mirror],
            measuredBytesPerSecond: [official: 100_000, mirror: 400_000],
            official: official
        )
        #expect(chosen == mirror)
    }

    @Test("全部不可用时用第一个候选")
    func fallsBackToFirst() {
        let mirror = URL(string: "https://gh-proxy.com/" + official.absoluteString)!
        let chosen = UpdateDownloadResolver.choose(
            candidates: [official, mirror],
            measuredBytesPerSecond: [:],
            official: official
        )
        #expect(chosen == official)
    }

    @Test("设置解码兼容缺失字段")
    func decodesWithoutFields() throws {
        let settings = try JSONDecoder().decode(UpdateDownloadSettings.self, from: Data("{}".utf8))
        #expect(settings.source == .automatic)
        #expect(settings.customURLTemplate.isEmpty)
    }
}
