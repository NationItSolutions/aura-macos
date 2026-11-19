import Foundation

/// Acepta el certificado autofirmado de la TV SOLO para su IP. El resto de las conexiones
/// siguen la validación normal del sistema.
final class TVTrustDelegate: NSObject, URLSessionDelegate, Sendable {
    let host: String

    init(host: String) {
        self.host = host
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge)
        async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        let space = challenge.protectionSpace
        guard space.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              space.host == host, let trust = space.serverTrust else {
            return (.performDefaultHandling, nil)
        }
        return (.useCredential, URLCredential(trust: trust))
    }
}

/// Conexión con una TV Samsung: WebSocket para teclas, REST para info y apps, WoL para encender.
actor SamsungTVClient {
    let deviceID: UUID
    private(set) var host: String
    private var session: URLSession?
    private var socket: URLSessionWebSocketTask?
    private(set) var isConnected = false

    init(deviceID: UUID, host: String) {
        self.deviceID = deviceID
        self.host = host
    }

    var token: String? { KeychainStore.get(account: KeychainStore.tvTokenAccount(deviceID)) }

    func updateHost(_ host: String) {
        guard host != self.host else { return }
        self.host = host
        disconnect()
    }

    // MARK: - REST

    func info(timeout: Duration = .seconds(3)) async throws -> SamsungTVProtocol.DeviceInfo {
        guard let url = SamsungTVProtocol.infoURL(host: host) else { throw SamsungTVError.invalidHost }
        var request = URLRequest(url: url)
        request.timeoutInterval = Self.seconds(timeout)
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let info = SamsungTVProtocol.parseInfo(data) else { throw SamsungTVError.unreachable }
            return info
        } catch let error as SamsungTVError {
            throw error
        } catch {
            throw Self.map(error)
        }
    }

    func launch(_ app: TVApp) async throws {
        guard let url = SamsungTVProtocol.applicationURL(host: host, appID: app.id) else {
            throw SamsungTVError.appLaunchFailed(app.name)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 3
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw SamsungTVError.appLaunchFailed(app.name)
            }
        } catch let error as SamsungTVError {
            throw error
        } catch {
            throw Self.map(error)
        }
    }

    // MARK: - WebSocket

    /// Conecta con el token guardado. Si la TV entrega uno nuevo, lo guarda en el llavero.
    /// Con `allowPairing` espera a que el usuario acepte el aviso en la TV.
    func connect(allowPairing: Bool = false, timeout: Duration = .seconds(3)) async throws {
        if isConnected, socket != nil { return }
        disconnect()
        let savedToken = token
        if savedToken == nil, !allowPairing { throw SamsungTVError.notPaired }
        guard let url = SamsungTVProtocol.remoteURL(host: host, token: savedToken) else { throw SamsungTVError.invalidHost }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = Self.seconds(timeout)
        let session = URLSession(configuration: configuration, delegate: TVTrustDelegate(host: host), delegateQueue: nil)
        let socket = session.webSocketTask(with: url)
        self.session = session
        self.socket = socket
        socket.resume()

        // Si la TV no contesta a tiempo, cerramos el socket: eso destraba el `receive()` pendiente.
        let started = ContinuousClock.now
        let watchdog = Task {
            try? await Task.sleep(for: timeout)
            if !Task.isCancelled { socket.cancel(with: .goingAway, reason: nil) }
        }
        defer { watchdog.cancel() }

        do {
            let event = try await Self.waitForChannelEvent(socket)
            switch event {
            case .connected(let newToken):
                if let newToken, newToken != savedToken {
                    KeychainStore.set(newToken, account: KeychainStore.tvTokenAccount(deviceID))
                    Log.tv.info("TV emparejada, token guardado en el llavero")
                }
                isConnected = true
            case .unauthorized:
                disconnect()
                if savedToken != nil {
                    KeychainStore.delete(account: KeychainStore.tvTokenAccount(deviceID))
                    throw SamsungTVError.tokenRejected
                }
                throw SamsungTVError.denied
            case .timeout:
                disconnect()
                throw allowPairing ? SamsungTVError.denied : SamsungTVError.timeout
            case .other:
                disconnect()
                throw SamsungTVError.unreachable
            }
        } catch let error as SamsungTVError {
            throw error
        } catch {
            disconnect()
            if ContinuousClock.now - started >= timeout {
                throw allowPairing ? SamsungTVError.denied : SamsungTVError.timeout
            }
            throw Self.map(error)
        }
    }

    private static func waitForChannelEvent(_ socket: URLSessionWebSocketTask) async throws -> SamsungTVProtocol.ChannelEvent {
        while true {
            let message = try await socket.receive()
            let text: String
            switch message {
            case .string(let string): text = string
            case .data(let data): text = String(decoding: data, as: UTF8.self)
            @unknown default: continue
            }
            // Ignoramos eventos informativos (p. ej. "ed.edenTV.update") hasta el de conexión.
            if let event = SamsungTVProtocol.parseEvent(text) {
                if case .other = event { continue }
                return event
            }
        }
    }

    func send(_ key: TVKey) async throws {
        if !isConnected { try await connect() }
        guard let socket else { throw SamsungTVError.unreachable }
        let watchdog = Task {
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled { socket.cancel(with: .goingAway, reason: nil) }
        }
        defer { watchdog.cancel() }
        do {
            try await socket.send(.string(SamsungTVProtocol.keyMessage(key)))
        } catch {
            disconnect()
            throw Self.map(error)
        }
    }

    func disconnect() {
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        session?.invalidateAndCancel()
        session = nil
        isConnected = false
    }

    func forgetPairing() {
        disconnect()
        KeychainStore.delete(account: KeychainStore.tvTokenAccount(deviceID))
    }

    // MARK: - Helpers

    private static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }

    private static func map(_ error: any Error) -> SamsungTVError {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorTimedOut: return .timeout
            case NSURLErrorBadURL, NSURLErrorUnsupportedURL: return .invalidHost
            default: return .unreachable
            }
        }
        if nsError.domain == "Network.NWError" || nsError.localizedDescription.localizedCaseInsensitiveContains("policy") {
            return .localNetworkDenied
        }
        return .unreachable
    }
}
