
#if os(WASI)
import Foundation
import Sync
import OpenCombineShim
import JavaScriptKit

extension ConsumerConnection where Self == WebSocketClientConnection {

    public static func webSocket(url: URL,
                                 codingContext: EventCodingContext = .json) -> ConsumerConnection {

        return WebSocketClientConnection(url: url, codingContext: codingContext)
    }

}

public class WebSocketClientConnection: ConsumerConnection {
    enum WebSocketError: Error {
        case connectionDroppedDuringConnection
        case invalidMessageFromWebSocketOnFirstMessage
    }

    private static let webSocketConstructor = JSObject.global.WebSocket.function!

    @Published
    public fileprivate(set) var isConnected: Bool = false

    public var isConnectedPublisher: AnyPublisher<Bool, Never> {
        return $isConnected.eraseToAnyPublisher()
    }

    private let url: URL
    public let codingContext: EventCodingContext

    private var webSocketObject: JSObject?
    private let receivedDataSubject = PassthroughSubject<Data, Never>()

    public init(url: URL,
                codingContext: EventCodingContext) {

        self.url = url
        self.codingContext = codingContext
    }

    deinit {
        disconnect()
    }

    public func connect() async throws -> Data {
        return try await withCheckedThrowingContinuation { [weak self] continuation in
            guard let self = self else {
                return continuation.resume(throwing: WebSocketError.connectionDroppedDuringConnection)
            }

            var webSocketObject: JSObject? = nil
            var onOpen: JSClosure?

            var onFirstMessage: JSClosure? = nil
            var onMessage: JSClosure?
            var onClose: JSClosure?

            let close = { [weak self] in
                if let listener = onFirstMessage {
                    _ = webSocketObject?.removeEventListener!("message", listener)
                    onFirstMessage = nil
                }
                if let listener = onMessage {
                    _ = webSocketObject?.removeEventListener!("message", listener)
                    onMessage = nil
                }
                _ = webSocketObject?.removeEventListener!("close", onClose)
                if let self = self {
                    self.isConnected = false
                }
            }

            onOpen = JSClosure { [weak self] _ in
                guard let self = self else {
                    return .undefined
                }

                if let onOpen = onOpen {
                    _ = self.webSocketObject?.removeEventListener!("open", onOpen)
                }

                onOpen = nil
                self.isConnected = true
                return .undefined
            }

            onMessage = JSClosure { [weak self] arguments in
                guard let self = self else { return .undefined }
                let event = arguments.first!.object!
                event.dataFromMessageEvent { [weak self] data in
                    guard let data = data else { return }
                    self?.receivedDataSubject.send(data)
                }
                return .undefined
            }

            onFirstMessage = JSClosure { arguments in
                let event = arguments.first!.object!
                event.dataFromMessageEvent { data in
                    guard let data = data else {
                        continuation.resume(throwing: WebSocketError.invalidMessageFromWebSocketOnFirstMessage)
                        close()
                        return
                    }
                    self.receivedDataSubject.send(data)
                    _ = webSocketObject?.removeEventListener!("message", onFirstMessage)
                    onFirstMessage = nil
                    _ = webSocketObject?.addEventListener!("message", onMessage)
                    continuation.resume(returning: data)
                }
                return .undefined
            }

            onClose = JSClosure { _ in
                close()
                return .undefined
            }

            webSocketObject = Self.webSocketConstructor.new(self.url.absoluteString)
            self.webSocketObject = webSocketObject

            _ = webSocketObject?.addEventListener!("message", onFirstMessage)
            _ = webSocketObject?.addEventListener!("close", onClose)
            _ = webSocketObject?.addEventListener!("error", onClose)
            _ = webSocketObject?.addEventListener!("open", onOpen)
        }
    }

    public func disconnect() {
        guard isConnected else { return }
        _ = webSocketObject?.close!()
        isConnected = false
    }

    public func send(data: Data) {
        guard isConnected else { return }
        guard let message = String(data: data, encoding: .utf8) else { return }
        _ = webSocketObject?.send!(message)
    }

    public func receive() -> AnyPublisher<Data, Never> {
        return receivedDataSubject.eraseToAnyPublisher()
    }
}

extension JSObject {
    private static let blob = JSObject.global.Blob.function!
    private static let fileReader = JSObject.global.FileReader.function!
    private static let textEncoder = JSObject.global.TextDecoder.function!.new("utf-8")

    func dataFromMessageEvent(
        completion: @escaping (Data?) -> Void
    ) {
        switch self["data"] {
        case .string(let dataString):
            completion(String(dataString).data(using: .utf8))
        case .object(let object) where object.isInstanceOf(Self.blob):
            var onLoaded: JSClosure?
            var onError: JSClosure?
            let reader = Self.fileReader.new(object)
            onLoaded = JSClosure { arguments in
                print(arguments)
                onLoaded = nil
                onError = nil

                guard let base64String = reader.result.string?.replacingOccurrences(of: "^data:.+;base64,", with: "", options: .regularExpression) else {
                    completion(nil)
                    return .undefined
                }

                print(base64String)
                completion(Data(base64Encoded: base64String))
                return .undefined
            }

            onError = JSClosure { error in
                print(error)
                onLoaded = nil
                onError = nil
                completion(nil)
                return .undefined
            }

            reader.onloadend = .object(onLoaded!)
            reader.onerror = .object(onError!)
            reader.onabort = .object(onError!)
            _ = reader.readAsDataURL!(object)
        case .object(let object):
            let dataString = Self.textEncoder.decode!(object).string
            completion(dataString?.data(using: .utf8))
        default:
            completion(nil)
        }
    }

}

#endif

