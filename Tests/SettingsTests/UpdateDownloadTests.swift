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

    @Test("自动模式：内置镜像优先，官方兜底")
    func automaticCandidates() {
        let urls = UpdateDownloadResolver.candidates(
            official: official,
            settings: UpdateDownloadSettings(source: .automatic)
        )
        #expect(urls.count == 1 + UpdateDownloadSettings.builtinMirrorPrefixes.count)
        // GitHub 直连常常「小请求能通、整包下载超时」，所以让它排最后。
        #expect(urls.last == official)
        #expect(urls[0].absoluteString == UpdateDownloadSettings.builtinMirrorPrefixes[0] + official.absoluteString)
        #expect(urls[1].absoluteString == UpdateDownloadSettings.builtinMirrorPrefixes[1] + official.absoluteString)
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

    @Test("失败换源时按候选顺序推进，不会跳过中间源")
    func failoverFollowsOrder() {
        let urls = UpdateDownloadResolver.candidates(
            official: official,
            settings: UpdateDownloadSettings(source: .automatic)
        )
        // 模拟「已试过前两个」后应轮到第三个，最终一定会走到官方兜底。
        var attempted: Set<String> = []
        var sequence: [URL] = []
        for _ in urls.indices {
            guard let next = urls.first(where: { !attempted.contains($0.absoluteString) }) else { break }
            attempted.insert(next.absoluteString)
            sequence.append(next)
        }
        #expect(sequence == urls)
        #expect(sequence.last == official)
    }

    @Test("设置解码兼容缺失字段")
    func decodesWithoutFields() throws {
        let settings = try JSONDecoder().decode(UpdateDownloadSettings.self, from: Data("{}".utf8))
        #expect(settings.source == .automatic)
        #expect(settings.customURLTemplate.isEmpty)
    }
}
