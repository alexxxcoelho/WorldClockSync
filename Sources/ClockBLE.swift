import CoreBluetooth
import Foundation

/// Connexion Bluetooth à l'horloge : service 0xABCD, caractéristique 0x2025.
/// Protocole texte : "AT1" (heure auto/NTP), "TZ<posix>" (fuseau), "SS" (sauvegarder).
@MainActor
final class ClockBLE: NSObject, ObservableObject {
    enum State: Equatable {
        case bluetoothOff, idle, scanning, connecting, ready, sending, done, failed(String)
    }

    struct Clock: Identifiable, Equatable {
        let id: UUID
        let name: String
        let rssi: Int
    }

    static let serviceUUID = CBUUID(string: "ABCD")
    static let charUUID = CBUUID(string: "2025")

    @Published private(set) var state: State = .idle
    @Published private(set) var clocks: [Clock] = []
    @Published private(set) var connectedName: String?
    @Published private(set) var log: [String] = []

    private var central: CBCentralManager!
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var peripheral: CBPeripheral?
    private var characteristic: CBCharacteristic?
    private var writeContinuation: CheckedContinuation<Void, Error>?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func startScan() {
        guard central.state == .poweredOn else { state = .bluetoothOff; return }
        clocks = []
        state = .scanning
        central.scanForPeripherals(withServices: [Self.serviceUUID])
    }

    func connect(_ clock: Clock) {
        guard let p = peripherals[clock.id] else { return }
        central.stopScan()
        state = .connecting
        peripheral = p
        p.delegate = self
        central.connect(p)
    }

    func disconnect() {
        if let p = peripheral { central.cancelPeripheralConnection(p) }
        peripheral = nil
        characteristic = nil
        connectedName = nil
        state = .idle
    }

    /// Active l'heure automatique, envoie le fuseau, puis sauvegarde.
    func syncTime(timeZone: TimeZone) async {
        let posix = PosixTZ.string(for: timeZone)
        state = .sending
        do {
            for cmd in ["AT1", "TZ" + posix, "SS"] {
                try await write(cmd)
                try await Task.sleep(for: .seconds(1.5))
            }
            state = .done
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func write(_ command: String) async throws {
        guard let p = peripheral, let c = characteristic else {
            throw NSError(domain: "ClockBLE", code: 1, userInfo: [NSLocalizedDescriptionKey: "Horloge non connectée"])
        }
        log.append("→ \(command)")
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            writeContinuation = cont
            p.writeValue(Data(command.utf8), for: c, type: .withResponse)
        }
    }
}

extension ClockBLE: CBCentralManagerDelegate, CBPeripheralDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated {
            if central.state == .poweredOn {
                if state == .bluetoothOff || state == .idle { startScan() }
            } else {
                state = .bluetoothOff
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any], rssi RSSI: NSNumber) {
        MainActor.assumeIsolated {
            let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name ?? "Horloge"
            peripherals[peripheral.identifier] = peripheral
            let clock = Clock(id: peripheral.identifier, name: name, rssi: RSSI.intValue)
            if let i = clocks.firstIndex(where: { $0.id == clock.id }) { clocks[i] = clock } else { clocks.append(clock) }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        MainActor.assumeIsolated {
            connectedName = clocks.first { $0.id == peripheral.identifier }?.name ?? peripheral.name
            peripheral.discoverServices([Self.serviceUUID])
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated {
            state = .failed(error?.localizedDescription ?? "Connexion impossible. L'app officielle est peut-être déjà connectée.")
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated {
            writeContinuation?.resume(throwing: error ?? NSError(domain: "ClockBLE", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Horloge déconnectée"]))
            writeContinuation = nil
            characteristic = nil
            connectedName = nil
            if state != .done { state = .idle }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        MainActor.assumeIsolated {
            guard let s = peripheral.services?.first(where: { $0.uuid == Self.serviceUUID }) else {
                state = .failed("Service de l'horloge introuvable"); return
            }
            peripheral.discoverCharacteristics([Self.charUUID], for: s)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        MainActor.assumeIsolated {
            guard let c = service.characteristics?.first(where: { $0.uuid == Self.charUUID }) else {
                state = .failed("Caractéristique 2025 introuvable"); return
            }
            characteristic = c
            peripheral.setNotifyValue(true, for: c)
            state = .ready
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        MainActor.assumeIsolated {
            if let error { writeContinuation?.resume(throwing: error) } else { writeContinuation?.resume() }
            writeContinuation = nil
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        MainActor.assumeIsolated {
            if let data = characteristic.value, !data.isEmpty {
                log.append("← " + (String(data: data, encoding: .utf8) ?? data.map { String(format: "%02x", $0) }.joined()))
            }
        }
    }
}
