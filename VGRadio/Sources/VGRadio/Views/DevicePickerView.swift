import SwiftUI

/// Device picker for the player bar. Hides itself when there is nothing to
/// connect to, so a single-instance setup sees no dead control.
struct DevicePickerView: View {
    @Environment(ConnectService.self) var connect
    @State private var showPopover = false

    var body: some View {
        if !connect.otherDevices.isEmpty {
            Button {
                showPopover.toggle()
            } label: {
                Image(systemName: "rectangle.on.rectangle")
                    .font(.system(size: 15))
                    .foregroundStyle(connect.isRemote ? Color.vgAccent : Color.vgTextMuted)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Dispositivos")
            .popover(isPresented: $showPopover, arrowEdge: .top) {
                DeviceListPopover { id in
                    showPopover = false
                    connect.transfer(to: id)
                }
            }
        }
    }
}

private struct DeviceListPopover: View {
    @Environment(ConnectService.self) var connect
    let onPick: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Dispositivos")
                    .font(VGFont.caption(11))
                    .foregroundStyle(Color.vgTextMuted)
                Spacer()
                if !connect.isConnected {
                    Text("sin conexión")
                        .font(VGFont.caption(10))
                        .foregroundStyle(Color.red.opacity(0.8))
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            ForEach(connect.devices) { device in
                Button { onPick(device.id) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: device.isActive ? "circle.fill" : "circle")
                            .font(.system(size: 7))
                            .foregroundStyle(device.isActive ? Color.vgAccent : Color.vgTextMuted)
                        Image(systemName: icon(for: device.type))
                            .font(.system(size: 12))
                            .foregroundStyle(Color.vgTextSec)
                            .frame(width: 18)
                        Text(label(for: device))
                            .font(VGFont.body(13))
                            .foregroundStyle(device.isActive ? Color.vgAccent : Color.vgText)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        if device.isActive {
                            Text("sonando")
                                .font(VGFont.caption(10))
                                .foregroundStyle(Color.vgAccent)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 8)
        }
        .frame(width: 260)
    }

    private func icon(for type: String) -> String {
        switch type {
        case "macos": "desktopcomputer"
        case "tv": "tv"
        default: "globe"
        }
    }

    private func label(for device: ConnectDevice) -> String {
        device.id == connect.deviceID ? "\(device.name) — este Mac" : device.name
    }
}

/// Banner shown above the transport while another device owns playback.
struct RemoteBannerView: View {
    @Environment(ConnectService.self) var connect

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "rectangle.on.rectangle")
                .font(.system(size: 11))
            Text("Sonando en \(connect.activeDevice?.name ?? "otro dispositivo")")
                .font(VGFont.caption(11))
            Spacer()
            Button {
                connect.transfer(to: connect.deviceID)
            } label: {
                Text("Reproducir acá →")
                    .font(VGFont.caption(11))
                    .fontWeight(.semibold)
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(Color.vgAccent)
        .padding(.horizontal, VGSpace.md)
        .frame(height: 26)
        .frame(maxWidth: .infinity)
        .background(Color.vgAccent.opacity(0.12))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.vgSeparator).frame(height: 1)
        }
    }
}
