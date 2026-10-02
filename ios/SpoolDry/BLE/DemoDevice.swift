import Foundation
import SpoolDryKit

/// A clearly labelled, simulated dryer for trying the app (and for App Review) without hardware.
/// It speaks the real BLE Protocol v1 byte format through the same codec as a physical device,
/// runs 60x faster than real time, and its sessions never count towards the free limit.
@MainActor
final class DemoDevice {
    static let deviceID = UUID(uuidString: "5D0F0000-DE30-4000-8000-000000000001")!
    static let speedup: Double = 60

    weak var link: DeviceLink?
    private var timer: Timer?
    private var state: DeviceState = .idle
    private var endReason: SessionEndReason = .none
    private var chamber: Double = 23
    private var moisture: Double = 1
    private var target: Double = 50
    private var duration: UInt32 = 4 * 3600
    private var elapsedDrying: Double = 0
    private var phaseElapsed: Double = 0
    private var material: MaterialCode = .pla
    private var fanMode: FanMode = .auto
    private var sessionCounter: UInt32 = 0
    private var sessionId: UInt32 = 0
    private var startUnix: UInt32 = 0
    private var uptime: Double = 0
    private var seq: UInt16 = 0

    var sessionInfo: DryingSessionInfo {
        DryingSessionInfo(sessionId: sessionId, material: material, endReason: endReason, targetCelsius: target,
                          durationSeconds: duration, elapsedDryingSeconds: UInt32(elapsedDrying),
                          startDate: startUnix == 0 ? nil : Date(timeIntervalSince1970: TimeInterval(startUnix)))
    }

    var info: DeviceInfo {
        DeviceInfo(protocolVersion: SpoolDryProtocol.protocolVersion, hardwareRevision: 1,
                   deviceId: Data([0x44, 0x45, 0x4D, 0x4F, 0x00, 0x01]), firmwareVersion: SpoolDryProtocol.referenceFirmwareVersion,
                   minTargetCelsius: 35, maxTargetCelsius: 70, maxDurationSeconds: SpoolDryProtocol.maxDurationSec,
                   capabilities: [.heaterNtc, .fanTach, .safetyRelay, .identifyLed, .localButton],
                   resetCause: .powerOn, lastFault: .none)
    }

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick(realSeconds: 1) }
        }
        tick(realSeconds: 0)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private var humidity: Double {
        let psat: (Double) -> Double = { 6.112 * exp(17.62 * $0 / (243.12 + $0)) }
        return min(100, max(1, 52 * moisture * psat(23) / psat(chamber)))
    }

    private func tick(realSeconds: Double) {
        let dt = realSeconds * Self.speedup
        uptime += dt
        let heating = state == .preheating || state == .drying
        var power: Double = 0
        if heating { power = max(0, min(100, (target - chamber) * 14 + 30)) }
        chamber += (power - 1.2 * (chamber - 23)) / 3000 * dt
        if chamber > 35 { moisture -= 0.00004 * (chamber - 35) * moisture * dt }
        moisture = max(0.05, moisture)
        phaseElapsed += dt
        switch state {
        case .preheating where chamber >= target - 2:
            state = .drying
            phaseElapsed = 0
        case .drying:
            elapsedDrying += dt
            if elapsedDrying >= Double(duration) {
                elapsedDrying = Double(duration)
                state = .cooldown
                endReason = .completed
                phaseElapsed = 0
            }
        case .cooldown where chamber <= 45 || phaseElapsed > 900:
            state = endReason == .completed ? .completed : .idle
        default:
            break
        }
        link?.ingest(status: snapshot(heaterDuty: UInt8(power.rounded())))
    }

    private func snapshot(heaterDuty: UInt8) -> DeviceStatus {
        seq &+= 1
        let active = state == .preheating || state == .drying || state == .cooldown
        let heating = state == .preheating || state == .drying
        var flags: StatusFlags = [.chamberSensorOk, .heaterSensorOk, .clientConnected]
        if heating { flags.formUnion([.heaterRelay, .heaterOutput]) }
        if active || fanMode == .on { flags.insert(.fanOn) }
        if active { flags.insert(.sessionActive) }
        if startUnix != 0 { flags.insert(.timeSynced) }
        let remaining: UInt32?
        switch state {
        case .preheating: remaining = duration
        case .drying: remaining = UInt32(max(0, Double(duration) - elapsedDrying))
        case .cooldown, .completed: remaining = 0
        default: remaining = nil
        }
        let status = DeviceStatus(state: state, error: .none, flags: flags,
                                  chamberCelsius: (chamber * 100).rounded() / 100, humidityPercent: (humidity * 100).rounded() / 100,
                                  heaterCelsius: chamber + (heating ? 3 : 0), targetCelsius: target, remainingSeconds: remaining,
                                  elapsedDryingSeconds: UInt32(elapsedDrying), sessionId: sessionId, material: material,
                                  heaterDutyPercent: heating ? heaterDuty : 0, fanRPM: flags.contains(.fanOn) ? 6800 : 0,
                                  uptimeSeconds: UInt32(uptime), fanMode: fanMode, endReason: endReason, sequence: seq)
        // Round-trip through the wire format so the demo exercises the same decoder as real hardware.
        return (try? DeviceStatus.decode(status.encode())) ?? status
    }

    /// Executes a command frame exactly like the firmware would and returns the encoded response.
    func handle(frame: Data) -> CommandResponse {
        let bytes = [UInt8](frame)
        guard bytes.count >= 4, let op = Opcode(rawValue: bytes[1]) else {
            return CommandResponse(type: .nack, sequence: bytes.count > 2 ? bytes[2] : 0, opcodeRaw: bytes.count > 1 ? bytes[1] : 0,
                                   result: .unknownOpcode, payload: [])
        }
        let seqNo = bytes[2]
        var r = ByteReader(Array(bytes.dropFirst(4)))
        func ack(_ payload: [UInt8] = []) -> CommandResponse {
            CommandResponse(type: .ack, sequence: seqNo, opcodeRaw: op.rawValue, result: .ok, payload: payload)
        }
        func nack(_ code: ResultCode) -> CommandResponse {
            CommandResponse(type: .nack, sequence: seqNo, opcodeRaw: op.rawValue, result: code, payload: [state.rawValue, 0])
        }
        let active = state == .preheating || state == .drying || state == .cooldown
        switch op {
        case .startSession:
            guard !active else { return nack(.busy) }
            guard let m = try? r.u8(), let t = try? r.i16(), let d = try? r.u32(), let now = try? r.u32(), let f = try? r.u8() else {
                return nack(.badLength)
            }
            material = MaterialCode(rawValue: m) ?? .custom
            target = Double(t) / 100
            duration = d
            startUnix = now
            fanMode = FanMode(rawValue: f) ?? .auto
            sessionCounter += 1
            sessionId = sessionCounter
            elapsedDrying = 0
            phaseElapsed = 0
            endReason = .none
            state = .preheating
            var w = ByteWriter()
            w.u32(sessionId)
            w.u32(now)
            tick(realSeconds: 0)
            return ack(w.bytes)
        case .stopSession:
            if state == .preheating || state == .drying {
                state = .cooldown
                endReason = .stoppedByUser
                phaseElapsed = 0
            }
            tick(realSeconds: 0)
            return ack()
        case .setTargetTemp:
            if let t = try? r.i16() { target = Double(t) / 100 }
            return ack()
        case .setDuration:
            if let d = try? r.u32() { duration = d }
            return ack()
        case .setFilament:
            if let m = try? r.u8() { material = MaterialCode(rawValue: m) ?? .custom }
            return ack()
        case .setFanMode:
            guard let f = try? r.u8(), let mode = FanMode(rawValue: f) else { return nack(.invalidParameter) }
            if mode == .off && active { return nack(.notAllowedInState) }
            fanMode = mode
            return ack()
        case .requestStatus, .identify, .setDeviceName:
            tick(realSeconds: 0)
            return ack()
        case .resetSession:
            guard !active else { return nack(.busy) }
            state = .idle
            endReason = .none
            tick(realSeconds: 0)
            return ack()
        }
    }
}
