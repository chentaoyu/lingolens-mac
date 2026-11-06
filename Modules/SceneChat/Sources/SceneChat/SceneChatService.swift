import Foundation
import LLMClient
import ModelLibrary
import ModelRuntime
import Settings

public enum SceneChatError: Error, LocalizedError, Equatable, Sendable {
    case noResidentModel
    case modelNotFound(String)
    case modelUnavailable(String)

    public var errorDescription: String? {
        switch self {
        case .noResidentModel:
            return "尚未设置常驻模型，请在“模型”页选择一个模型。"
        case let .modelNotFound(id):
            return "找不到模型：\(id)"
        case let .modelUnavailable(name):
            return "模型 \(name) 的目录不可用，请重新扫描或删除。"
        }
    }
}

public enum SceneChatEvent: Sendable, Equatable {
    case modelResolved(name: String)
    case delta(String)
    case finished(ChatMetrics)
}

/// 按场景解析模型、获取服务租约并流式调用本地 LLM。
@MainActor
public final class SceneChatService {
    private let client: LocalLLMClient
    private let pool: ServerPool
    private let settingsStore: SettingsStore
    private let catalog: ModelCatalog

    public init(
        client: LocalLLMClient,
        pool: ServerPool,
        settingsStore: SettingsStore,
        catalog: ModelCatalog
    ) {
        self.client = client
        self.pool = pool
        self.settingsStore = settingsStore
        self.catalog = catalog
    }

    public var settings: AppSettings {
        settingsStore.settings
    }

    public func stream(
        scene: SceneID,
        messages: [ChatMessage],
        parameters: GenerationParameters? = nil,
        modelID explicitModelID: String? = nil
    ) -> AsyncThrowingStream<SceneChatEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { @MainActor in
                do {
                    let (model, config) = try await self.resolveModel(for: scene, modelID: explicitModelID)
                    continuation.yield(.modelResolved(name: model.name))

                    let lease = try await self.pool.acquire(model: model, config: config)
                    defer {
                        Task { await self.pool.release(lease) }
                    }

                    let effectiveParameters = parameters ?? self.settingsStore.settings.scene(scene).parameters
                    let request = ChatRequest(
                        model: lease.serverModelID,
                        messages: messages,
                        parameters: effectiveParameters
                    )

                    for try await event in self.client.streamChat(baseURL: lease.baseURL, request: request) {
                        switch event {
                        case let .delta(delta):
                            continuation.yield(.delta(delta))
                        case let .finished(metrics):
                            continuation.yield(.finished(metrics))
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func resolveModel(
        for scene: SceneID,
        modelID explicitModelID: String? = nil
    ) async throws -> (ModelRef, ServerLaunchConfig) {
        let settings = settingsStore.settings
        let sceneSettings = settings.scene(scene)
        let modelID: String?
        if let explicitModelID {
            modelID = explicitModelID
        } else if sceneSettings.useResidentModel {
            modelID = settings.residentModelID
        } else {
            modelID = sceneSettings.modelID ?? settings.residentModelID
        }
        guard let modelID else { throw SceneChatError.noResidentModel }
        guard let record = await catalog.record(id: modelID) else {
            throw SceneChatError.modelNotFound(modelID)
        }
        guard record.isAvailable else {
            throw SceneChatError.modelUnavailable(record.name)
        }
        let service = settings.service(for: record.id)
        let config = ServerLaunchConfig(
            isResident: record.id == settings.residentModelID,
            idleUnloadMinutes: service.idleUnloadMinutes,
            options: ServerOptions(
                kvCacheBits: service.kvCacheBits,
                maxKVCacheLength: service.maxKVCacheLength
            )
        )
        return (
            ModelRef(id: record.id, name: record.name, directory: record.directoryURL),
            config
        )
    }
}
