import SwiftUI

@main
struct WorldClockSyncApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

struct ContentView: View {
    @StateObject private var ble = ClockBLE()
    @State private var timeZoneID = TimeZone.current.identifier

    private var timeZone: TimeZone { TimeZone(identifier: timeZoneID) ?? .current }

    var body: some View {
        NavigationStack {
            List {
                if ble.connectedName == nil {
                    clocksSection
                } else {
                    syncSection
                }
                if !ble.log.isEmpty {
                    Section("Journal") {
                        ForEach(Array(ble.log.enumerated()), id: \.offset) { _, line in
                            Text(line).font(.caption.monospaced())
                        }
                    }
                }
            }
            .navigationTitle("WorldClockSync")
        }
    }

    @ViewBuilder private var clocksSection: some View {
        Section {
            switch ble.state {
            case .bluetoothOff:
                Label("Active le Bluetooth pour trouver ton horloge.", systemImage: "antenna.radiowaves.left.and.right.slash")
            case .connecting:
                HStack { ProgressView(); Text("Connexion…") }
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
            default:
                if ble.clocks.isEmpty {
                    HStack { ProgressView(); Text("Recherche des horloges…") }
                }
            }
            ForEach(ble.clocks) { clock in
                Button { ble.connect(clock) } label: {
                    HStack {
                        Image(systemName: "clock")
                        Text(clock.name)
                        Spacer()
                        Text("\(clock.rssi) dBm").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Horloges à proximité")
        } footer: {
            Text("Ferme l'app officielle avant de te connecter : l'horloge n'accepte qu'une connexion à la fois.")
        }
        Section { Button("Relancer la recherche") { ble.startScan() } }
    }

    @ViewBuilder private var syncSection: some View {
        Section("Connectée") {
            Label(ble.connectedName ?? "", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        }
        Section {
            Picker("Fuseau horaire", selection: $timeZoneID) {
                ForEach(TimeZone.knownTimeZoneIdentifiers, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.navigationLink)
            LabeledContent("Heure locale") {
                Text(Date.now, format: .dateTime.hour().minute().timeZone()).environment(\.timeZone, timeZone)
            }
        } footer: {
            Text("Code envoyé : \(PosixTZ.string(for: timeZone))")
        }
        Section {
            Button {
                Task { await ble.syncTime(timeZone: timeZone) }
            } label: {
                HStack {
                    Text("Régler l'heure").bold()
                    Spacer()
                    if ble.state == .sending { ProgressView() }
                }
            }
            .disabled(ble.state == .sending)
            switch ble.state {
            case .done:
                Label("Envoyé. L'horloge se met à l'heure dans une minute ou deux.", systemImage: "checkmark")
                    .foregroundStyle(.green)
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
            default:
                EmptyView()
            }
        } footer: {
            Text("Active l'heure automatique (NTP), envoie le fuseau, puis sauvegarde.")
        }
        Section { Button("Déconnecter", role: .destructive) { ble.disconnect() } }
    }
}
