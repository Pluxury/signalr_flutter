import Flutter
import UIKit

public class SwiftSignalrFlutterPlugin: NSObject, FlutterPlugin, FLTSignalRHostApi {
    private static var signalrApi: FLTSignalRPlatformApi?

    private var hub: Hub!
    private var connection: SignalR!

    public static func register(with registrar: FlutterPluginRegistrar) {
        let messenger: FlutterBinaryMessenger = registrar.messenger()
        let api: FLTSignalRHostApi & NSObjectProtocol = SwiftSignalrFlutterPlugin()
        FLTSignalRHostApiSetup(messenger, api)
        signalrApi = FLTSignalRPlatformApi(binaryMessenger: messenger)
    }

    public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
        let messenger: FlutterBinaryMessenger = registrar.messenger()
        FLTSignalRHostApiSetup(messenger, nil)
        SwiftSignalrFlutterPlugin.signalrApi = nil
    }

    public func connect(_ connectionOptions: FLTConnectionOptions, completion: @escaping (String?, FlutterError?) -> Void) {
        connection = SignalR(connectionOptions.baseUrl ?? "")

        if let queryString = connectionOptions.queryString, !queryString.isEmpty {
            let qs = queryString.components(separatedBy: "=")
            connection.queryString = [qs[0]: qs[1]]
        }

        switch connectionOptions.transport {
        case .longPolling:
            connection.transport = Transport.longPolling
        case .serverSentEvents:
            connection.transport = Transport.serverSentEvents
        case .auto:
            connection.transport = Transport.auto
        @unknown default:
            break
        }

        if let headers = connectionOptions.headers, !headers.isEmpty {
            connection.headers = headers
        }

        if let hubName = connectionOptions.hubName {
            hub = connection.createHubProxy(hubName)
        }

        if let hubMethods = connectionOptions.hubMethods, !hubMethods.isEmpty {
            for methodName in hubMethods {
                hub.on(methodName) { args in
                    
                    guard let args = args, !args.isEmpty else {
                        SwiftSignalrFlutterPlugin.signalrApi?.onNewMessageHubName(methodName, message: "null or empty", completion: { _ in })
                        return
                    }
                    
                    let jsonData = try? JSONSerialization.data(withJSONObject: args[0], options: [])
                    let jsonString = String(data: jsonData!, encoding: .utf8)
                    SwiftSignalrFlutterPlugin.signalrApi?.onNewMessageHubName(methodName, message: jsonString ?? "", completion: { _ in })
                }
            }
        }

        connection.starting = {
            let statusChangeResult = FLTStatusChangeResult()
            statusChangeResult.connectionId = nil
            statusChangeResult.status = FLTConnectionStatus.connecting
            SwiftSignalrFlutterPlugin.signalrApi?.onStatusChange(statusChangeResult, completion: { _ in })
        }

        connection.reconnecting = {
            let statusChangeResult = FLTStatusChangeResult()
            statusChangeResult.connectionId = nil
            statusChangeResult.status = FLTConnectionStatus.reconnecting
            SwiftSignalrFlutterPlugin.signalrApi?.onStatusChange(statusChangeResult, completion: { _ in })
        }

        connection.connected = { [weak self] in
            let statusChangeResult = FLTStatusChangeResult()
            statusChangeResult.connectionId = self?.connection.connectionID
            statusChangeResult.status = FLTConnectionStatus.connected
            SwiftSignalrFlutterPlugin.signalrApi?.onStatusChange(statusChangeResult, completion: { _ in })
        }

        connection.reconnected = { [weak self] in
            let statusChangeResult = FLTStatusChangeResult()
            statusChangeResult.connectionId = self?.connection.connectionID
            statusChangeResult.status = FLTConnectionStatus.connected
            SwiftSignalrFlutterPlugin.signalrApi?.onStatusChange(statusChangeResult, completion: { _ in })
        }

        connection.disconnected = { [weak self] in
            let statusChangeResult = FLTStatusChangeResult()
            statusChangeResult.connectionId = self?.connection.connectionID
            statusChangeResult.status = FLTConnectionStatus.disconnected
            SwiftSignalrFlutterPlugin.signalrApi?.onStatusChange(statusChangeResult, completion: { _ in })
        }

        connection.connectionSlow = { [weak self] in
            print("Connection slow...")
            let statusChangeResult = FLTStatusChangeResult()
            statusChangeResult.connectionId = self?.connection.connectionID
            statusChangeResult.status = FLTConnectionStatus.connectionSlow
            SwiftSignalrFlutterPlugin.signalrApi?.onStatusChange(statusChangeResult, completion: { _ in })
        }

        connection.error = { error in
            print("SignalR Error: \(error ?? [:])")
            let statusChangeResult = FLTStatusChangeResult()
            statusChangeResult.connectionId = nil
            statusChangeResult.status = FLTConnectionStatus.connectionError
            statusChangeResult.errorMessage = error?.description
            SwiftSignalrFlutterPlugin.signalrApi?.onStatusChange(statusChangeResult, completion: { _ in })
        }

        connection.start()
        completion(connection.connectionID ?? "", nil)
    }

    public func reconnect(completion: @escaping (String?, FlutterError?) -> Void) {
        if let connection = connection {
            connection.start()
            completion(self.connection.connectionID ?? "", nil)
        } else {
            completion(nil, FlutterError(code: "platform-error", message: "SignalR Connection not found or null", details: "Start SignalR connection first"))
        }
    }

    public func stop(completion: @escaping (FlutterError?) -> Void) {
        if let connection = connection {
            connection.stop()
        } else {
            completion(FlutterError(code: "platform-error", message: "SignalR Connection not found or null", details: "Start SignalR connection first"))
        }
    }

    public func isConnected(completion: @escaping (NSNumber?, FlutterError?) -> Void) {
        if let connection = connection {
            switch connection.state {
            case .connected:
                completion(true, nil)
            default:
                completion(false, nil)
            }
        } else {
            completion(false, nil)
        }
    }

    func tryToGetJsonData(input: Any?) -> Data? {
        guard let input = input else {
            return nil
        }
  
        if !JSONSerialization.isValidJSONObject(input) {
            return nil
        }

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: input, options: [])
            return jsonData
        } catch {
            return nil
        }
    }

    public func invokeMethodMethodName(_ methodName: String, arguments: [String], completion: @escaping (String?, FlutterError?) -> Void) {
        do {
            if let hub = hub {
                try hub.invoke(methodName, arguments: arguments, callback: { res, error in
                    if let error = error {
                        completion(nil, FlutterError(code: "platform-error", message: String(describing: error), details: nil))
                    } else {
                        let jsonData = self.tryToGetJsonData(input: res)

                        if jsonData == nil {
                            if res != nil {
                                let intResult = res as! Int
                                completion(String(intResult), nil)
                            } else {
                                completion("", nil)
                            }
                        } else {
                            let jsonString = String(data: jsonData!, encoding: .utf8)
                            completion(jsonString ?? "", nil)
                        }
                    }
                })
            } else {
                throw NSError(domain: "NullPointerException", code: 0, userInfo: [NSLocalizedDescriptionKey: "Hub is null. Initiate a connection first."])
            }
        } catch {
            completion(nil, FlutterError(code: "platform-error", message: error.localizedDescription, details: nil))
        }
    }
}
