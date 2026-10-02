import CoreBluetooth
import Foundation
import Observation
import SpoolDryKit

/// Errors surfaced to the UI when talking to a dryer.
enum DeviceCommandError: LocalizedError, Equatable {
    case notConnected
    case timeout
    case rejected(ResultCode, DeviceState?, DeviceErrorCode?)
    case writeFailed(String)
    case invalidCommand
    case unsupportedProtocol(UInt8)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return String(localized: "The dryer is not connected.")
        case .timeout:
            return String(localized: "The dryer did not confirm the command. Check that it is powered and in range.")
        case let .rejected(code, _, _):
            return String(localized: String.LocalizationValue(code.localizationKey))
        case let .writeFailed(message):
            return message
        case .invalidCommand:
            return String(localized: "The selected settings are outside the dryer's limits.")
        case let .unsupportedProtocol(v):
            return String(localized: "This dryer uses BLE protocol v\(Int(v)). Please update SpoolDry.")
        }
    }
}

/// One SpoolDry dryer (real BLE peripheral or the built-in demo device).
/// Always accessed on the main actor; CoreBluetooth is configured with the main queue.
@MainActor
@Observable
final class DeviceLink: Identifiable {
    let id: UUID
    var name: String
    let isDemo: Bool

    /// Link-layer state: .disconnected / .connecting / .connected.
    var linkState: DeviceState = .disconnected
    var info: DeviceInfo?
    var status: DeviceStatus?
    var sessionInfo: DryingSessionInfo?
    var lastStatusAt: Date?
    var lastErrorMessage: String?
    var needsPairing = false

    /// What the UI should show: link state until the first status arrives, then the device's own state.
    var effectiveState: DeviceState {
        guard linkState == .connected else { return linkState }
        return status?.state ?? .connected
    }

    var isReady: Bool { linkState == .connected && status != nil }
    var maxTargetCelsius: Double { info?.maxTargetCelsius ?? FilamentDatabase.deviceMaxCelsius }
    var minTargetCelsius: Double { info?.minTargetCelsius ?? FilamentDatabase.deviceMinCelsius }

    // Transport
    @ObservationIgnored var peripheral: CBPeripheral?
    @ObservationIgnored var characteristics: [CBUUID: CBCharacteristic] = [:]
    @ObservationIgnored var demo: DemoDevice?
    @ObservationIgnored private var sequence: UInt8 = 0
    @ObservationIgnored private var pending: [UInt8: CheckedContinuation<CommandResponse, Error>] = [:]
    @ObservationIgnored var onStatus: ((DeviceLink, DeviceStatus) -> Void)?
    @ObservationIgnored var onInfo: ((DeviceLink, DeviceInfo) -> Void)?

    static let commandTimeout: Duration = .seconds(5)

    init(id: UUID, name: String, isDemo: Bool = false) {
        self.id = id
        self.name = name
        self.isDemo = isDemo
    }

    // MARK: Commands

    /// Sends a command and waits for the device's ACK/NACK. Never assumes success.
    @discardableResult
    func send(_ command: DeviceCommand) async throws -> CommandResponse {
        if let info, !info.isProtocolSupported { throw DeviceCommandError.unsupportedProtocol(info.protocolVersion) }
        sequence = sequence &+ 1
        if sequence == 0 { sequence = 1 }
        let seq = sequence
        let frame: Data
        do { frame = try command.frame(sequence: seq) } catch { throw DeviceCommandError.invalidCommand }

        let response: CommandResponse
        if let demo {
            response = demo.handle(frame: frame)
        } else {
            guard linkState == .connected, let peripheral,
                  let chr = characteristics[CBUUID(string: SpoolDryCharacteristic.command.rawValue)] else {
                throw DeviceCommandError.notConnected
            }
            response = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<CommandResponse, Error>) in
                pending[seq] = cont
                peripheral.writeValue(frame, for: chr, type: .withResponse)
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: Self.commandTimeout)
                    self?.resolve(seq: seq, with: .failure(DeviceCommandError.timeout))
                }
            }
        }
        guard response.isAck else {
            let rejection = response.rejectionState
            throw DeviceCommandError.rejected(response.result, rejection?.state, rejection?.error)
        }
        return response
    }

    func resolve(seq: UInt8, with result: Result<CommandResponse, Error>) {
        guard let cont = pending.removeValue(forKey: seq) else { return }
        cont.resume(with: result)
    }

    func failAllPending(_ error: DeviceCommandError) {
        let all = pending
        pending.removeAll()
        for (_, c) in all { c.resume(throwing: error) }
    }

    // MARK: Incoming data

    func handleValue(_ data: Data, for uuid: CBUUID) {
        guard let chr = SpoolDryCharacteristic(rawValue: uuid.uuidString.uppercased()) else { return }
        do {
            switch chr {
            case .deviceStatus:
                ingest(status: try DeviceStatus.decode(data))
            case .commandResponse:
                let r = try CommandResponse.decode(data)
                resolve(seq: r.sequence, with: .success(r))
            case .deviceInfo:
                let i = try DeviceInfo.decode(data)
                info = i
                onInfo?(self, i)
            case .dryingSession:
                sessionInfo = try DryingSessionInfo.decode(data)
            default:
                break  // individual characteristics are available for third-party tools; the app uses Device Status
            }
        } catch {
            lastErrorMessage = String(localized: "Received data the app could not read. Check for app or firmware updates.")
        }
    }

    func ingest(status s: DeviceStatus) {
        let previous = status
        status = s
        lastStatusAt = Date()
        needsPairing = false
        if previous?.state != s.state || previous?.sessionId != s.sessionId {
            requestSessionInfoRefresh()
        }
        onStatus?(self, s)
    }

    /// The Drying Session characteristic carries duration/start time; re-read it when the session changes.
    func requestSessionInfoRefresh() {
        if let demo {
            sessionInfo = demo.sessionInfo
            return
        }
        guard let peripheral, let chr = characteristics[CBUUID(string: SpoolDryCharacteristic.dryingSession.rawValue)] else { return }
        peripheral.readValue(for: chr)
    }
}
