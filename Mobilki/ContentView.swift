//
//  ContentView.swift
//  Mobilki
//
//  Created by Alexey Alter-Pesotskiy on 6/27/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var deviceManager = DeviceManager()
    @State private var expandedSections: Set<String> = []
    @State private var deleteConfirmation: (deviceName: String, deviceId: String, deviceType: DeviceType)? = nil
    @Environment(\.dismiss) private var dismiss

    // iOS Devices computed properties
    private var iosRunningDevices: [DeviceRowData] {
        deviceManager.iosDevices
            .filter { $0.isConnected }
            .sorted { ($0.connectionType == .usb ? 0 : 1) < ($1.connectionType == .usb ? 0 : 1) }
            .map { DeviceRowData(
                id: $0.id,
                name: $0.name,
                isRunning: $0.isConnected,
                status: $0.isConnected ? "Connected" : "Disconnected",
                statusIcon: $0.isConnected ? ($0.connectionType == .wifi ? "network" : nil) : nil,
                deviceType: .iosDevice,
                version: $0.version
            )}
    }

    private var iosStoppedDevices: [DeviceRowData] {
        deviceManager.iosDevices
            .filter { !$0.isConnected }
            .map { DeviceRowData(
                id: $0.id,
                name: $0.name,
                isRunning: $0.isConnected,
                status: $0.isConnected ? "Connected" : "Disconnected",
                statusIcon: nil,
                deviceType: .iosDevice,
                version: $0.version
            )}
    }

    // iOS Simulators computed properties
    private var iosRunningSimulators: [DeviceRowData] {
        deviceManager.iosSimulators
            .filter { $0.isRunning }
            .map { DeviceRowData(
                id: $0.id,
                name: $0.name,
                isRunning: $0.isRunning,
                status: $0.state,
                statusIcon: nil,
                deviceType: .iosSimulator,
                version: $0.version
            )}
    }

    private var iosStoppedSimulators: [DeviceRowData] {
        deviceManager.iosSimulators
            .filter { !$0.isRunning }
            .map { DeviceRowData(
                id: $0.id,
                name: $0.name,
                isRunning: $0.isRunning,
                status: $0.state,
                statusIcon: nil,
                deviceType: .iosSimulator,
                version: $0.version
            )}
    }

    // Android Devices computed properties
    private var androidRunningDevices: [DeviceRowData] {
        deviceManager.androidDevices
            .filter { $0.isConnected }
            .map { DeviceRowData(
                id: $0.id,
                name: $0.name,
                isRunning: $0.isConnected,
                status: $0.isConnected ? "Connected" : "Disconnected",
                statusIcon: $0.isConnected ? ($0.connectionType == .wifi ? "network" : nil) : nil,
                deviceType: .androidDevice,
                version: $0.apiLevel
            )}
    }

    private var androidStoppedDevices: [DeviceRowData] {
        deviceManager.androidDevices
            .filter { !$0.isConnected }
            .map { DeviceRowData(
                id: $0.id,
                name: $0.name,
                isRunning: $0.isConnected,
                status: $0.isConnected ? "Connected" : "Disconnected",
                statusIcon: nil,
                deviceType: .androidDevice,
                version: $0.apiLevel
            )}
    }

    // Android Emulators computed properties
    private var androidRunningEmulators: [DeviceRowData] {
        deviceManager.androidEmulators
            .filter { $0.isRunning }
            .map { DeviceRowData(
                id: $0.id,
                name: $0.name,
                isRunning: $0.isRunning,
                status: $0.isRunning ? "Running" : "Stopped",
                statusIcon: nil,
                deviceType: .androidEmulator,
                version: $0.apiLevel,
                deviceId: $0.deviceId
            )}
    }

    private var androidStoppedEmulators: [DeviceRowData] {
        deviceManager.androidEmulators
            .filter { !$0.isRunning }
            .map { DeviceRowData(
                id: $0.id,
                name: $0.name,
                isRunning: $0.isRunning,
                status: $0.isRunning ? "Running" : "Stopped",
                statusIcon: nil,
                deviceType: .androidEmulator,
                version: $0.apiLevel,
                deviceId: nil
            )}
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Mobilki")
                    .font(.title)
                    .fontWeight(.bold)

                Spacer()

                Button(action: {
                    deviceManager.refreshAll()
                }) {
                    Image(systemName: "arrow.trianglehead.2.clockwise")
                        .font(.system(size: 18))
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(deviceManager.isLoading)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            if deviceManager.isLoading {
                Spacer()
                ProgressView("Loading your mobilki...")
                    .font(.title3)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        // iOS Devices
                        CollapsibleDeviceSection(
                            title: "iOS Devices",
                            iconView: AnyView(AppleIcon()),
                            runningDevices: iosRunningDevices,
                            stoppedDevices: iosStoppedDevices,
                            onStart: nil,
                            onStop: nil,
                            onErase: nil,
                            onRestart: nil,
                            onDelete: nil,
                            onDisableInternet: nil,
                            onEnableInternet: nil,
                            isExpanded: expandedSections.contains("ios-devices"),
                            onToggleExpanded: { isExpanded in
                                if isExpanded {
                                    expandedSections.insert("ios-devices")
                                } else {
                                    expandedSections.remove("ios-devices")
                                }
                            }
                        )

                        // iOS Simulators
                        CollapsibleDeviceSection(
                            title: "iOS Simulators",
                            iconView: AnyView(AppleIcon()),
                            runningDevices: iosRunningSimulators,
                            stoppedDevices: iosStoppedSimulators,
                            onStart: { deviceManager.startIOSSimulator(id: $0) },
                            onStop: { deviceManager.stopIOSSimulator(id: $0) },
                            onErase: { id, _ in deviceManager.eraseIOSSimulator(id: id) },
                            onRestart: { id, _ in deviceManager.restartIOSSimulator(id: id) },
                            onDelete: { id, _ in
                                let deviceName = deviceManager.iosSimulators.first { $0.id == id }?.name ?? id
                                deleteConfirmation = (deviceName: deviceName, deviceId: id, deviceType: .iosSimulator)
                            },
                            onDisableInternet: nil,
                            onEnableInternet: nil,
                            isExpanded: expandedSections.contains("ios-simulators"),
                            onToggleExpanded: { isExpanded in
                                if isExpanded {
                                    expandedSections.insert("ios-simulators")
                                } else {
                                    expandedSections.remove("ios-simulators")
                                }
                            }
                        )

                        // Android Devices
                        CollapsibleDeviceSection(
                            title: "Android Devices",
                            iconView: AnyView(AndroidIcon()),
                            runningDevices: androidRunningDevices,
                            stoppedDevices: androidStoppedDevices,
                            onStart: nil,
                            onStop: nil,
                            onErase: nil,
                            onRestart: nil,
                            onDelete: nil,
                            onDisableInternet: nil,
                            onEnableInternet: nil,
                            isExpanded: expandedSections.contains("android-devices"),
                            onToggleExpanded: { isExpanded in
                                if isExpanded {
                                    expandedSections.insert("android-devices")
                                } else {
                                    expandedSections.remove("android-devices")
                                }
                            }
                        )

                        // Android Emulators
                        CollapsibleDeviceSection(
                            title: "Android Emulators",
                            iconView: AnyView(AndroidIcon()),
                            runningDevices: androidRunningEmulators,
                            stoppedDevices: androidStoppedEmulators,
                            onStart: { deviceManager.startAndroidEmulator(name: $0) },
                            onStop: { deviceManager.stopAndroidEmulator(name: $0) },
                            onErase: { name, _ in deviceManager.eraseAndroidEmulator(name: name) },
                            onRestart: { name, _ in deviceManager.restartAndroidEmulator(name: name) },
                            onDelete: { name, _ in
                                deleteConfirmation = (deviceName: name, deviceId: name, deviceType: .androidEmulator)
                            },
                            onDisableInternet: { deviceManager.setInternetForAndroidEmulator(name: $0, enable: false) },
                            onEnableInternet: { deviceManager.setInternetForAndroidEmulator(name: $0, enable: true) },
                            isExpanded: expandedSections.contains("android-emulators"),
                            onToggleExpanded: { isExpanded in
                                if isExpanded {
                                    expandedSections.insert("android-emulators")
                                } else {
                                    expandedSections.remove("android-emulators")
                                }
                            }
                        )
                    }
                    .padding()
                }
            }
        }
        .frame(width: 400, height: 600)
        .onAppear {
            deviceManager.refreshAll()
        }
        .alert(deleteConfirmation?.deviceType == .iosSimulator ? "Delete Simulator" : "Delete Emulator", isPresented: Binding(
            get: { deleteConfirmation != nil },
            set: { if !$0 { deleteConfirmation = nil } }
        )) {
            Button("Cancel", role: .cancel) {
                deleteConfirmation = nil
            }
            Button("Delete", role: .destructive) {
                if let confirmation = deleteConfirmation {
                    switch confirmation.deviceType {
                    case .iosSimulator:
                        deviceManager.deleteIOSSimulator(id: confirmation.deviceId)
                    case .androidEmulator:
                        deviceManager.deleteAndroidEmulator(name: confirmation.deviceName)
                    default:
                        break
                    }
                }
                deleteConfirmation = nil
            }
        } message: {
            if let confirmation = deleteConfirmation {
                let deviceType = confirmation.deviceType == .iosSimulator ? "iOS Simulator" : "Android Emulator"
                Text("Are you sure you want to delete the \(deviceType) '\(confirmation.deviceName)'? This action cannot be undone.")
            }
        }
    }
}

struct DeviceRowData {
    let id: String
    let name: String
    let isRunning: Bool
    let status: String
    let statusIcon: String?
    let deviceType: DeviceType
    let version: String
    let deviceId: String?

    init(id: String, name: String, isRunning: Bool, status: String, statusIcon: String? = nil, deviceType: DeviceType, version: String = "", deviceId: String? = nil) {
        self.id = id
        self.name = name
        self.isRunning = isRunning
        self.status = status
        self.statusIcon = statusIcon
        self.deviceType = deviceType
        self.version = version
        self.deviceId = deviceId
    }
}

enum DeviceType {
    case iosDevice
    case iosSimulator
    case androidDevice
    case androidEmulator
}

struct AndroidIcon: View {
    var body: some View {
        Image("AndroidIcon")
            .renderingMode(.original)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 20, height: 20)
    }
}

struct AppleIcon: View {
    var body: some View {
        Image(systemName: "applelogo")
            .renderingMode(.original)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 20, height: 20)
    }
}

struct CollapsibleDeviceSection: View {
    let title: String
    let iconView: AnyView
    let runningDevices: [DeviceRowData]
    let stoppedDevices: [DeviceRowData]
    let onStart: ((String) -> Void)?
    let onStop: ((String) -> Void)?
    let onErase: ((String, DeviceType) -> Void)?
    let onRestart: ((String, DeviceType) -> Void)?
    let onDelete: ((String, DeviceType) -> Void)?
    let onDisableInternet: ((String) -> Void)?
    let onEnableInternet: ((String) -> Void)?
    let isExpanded: Bool
    let onToggleExpanded: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: {
                onToggleExpanded(!isExpanded)
            }) {
                HStack {
                    iconView
                    Text(title)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    Spacer()
                    Text("\(runningDevices.count + stoppedDevices.count)")
                        .font(.title3)
                        .foregroundColor(.secondary)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(PlainButtonStyle())
            .contentShape(Rectangle())

            if isExpanded {
                if runningDevices.isEmpty && stoppedDevices.isEmpty {
                    Text("No devices found")
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .padding(.leading, 20)
                } else {
                    ForEach(runningDevices, id: \.id) { device in
                        DeviceRow(
                            device: device,
                            onStart: onStart,
                            onStop: onStop,
                            onErase: onErase,
                            onRestart: onRestart,
                            onDelete: onDelete,
                            onDisableInternet: onDisableInternet,
                            onEnableInternet: onEnableInternet
                        )
                    }
                    ForEach(stoppedDevices, id: \.id) { device in
                        DeviceRow(
                            device: device,
                            onStart: onStart,
                            onStop: onStop,
                            onErase: onErase,
                            onRestart: onRestart,
                            onDelete: onDelete,
                            onDisableInternet: onDisableInternet,
                            onEnableInternet: onEnableInternet
                        )
                    }
                }
            }
        }
    }
}

struct DeviceSection: View {
    let title: String
    let icon: String
    let devices: [DeviceRowData]
    let onStart: ((String) -> Void)?
    let onStop: ((String) -> Void)?
    let onErase: ((String, DeviceType) -> Void)?
    let onRestart: ((String, DeviceType) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.blue)
                    .frame(width: 20, alignment: .leading)
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(devices.count)")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }

            if devices.isEmpty {
                Text("No devices found")
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .padding(.leading, 20)
            } else {
                ForEach(devices, id: \.id) { device in
                    DeviceRow(
                        device: device,
                        onStart: onStart,
                        onStop: onStop,
                        onErase: onErase,
                        onRestart: onRestart,
                        onDelete: nil,
                        onDisableInternet: nil,
                        onEnableInternet: nil
                    )
                }
            }
        }
    }
}

struct DeviceRow: View {
    let device: DeviceRowData
    let onStart: ((String) -> Void)?
    let onStop: ((String) -> Void)?
    let onErase: ((String, DeviceType) -> Void)?
    let onRestart: ((String, DeviceType) -> Void)?
    let onDelete: ((String, DeviceType) -> Void)?
    let onDisableInternet: ((String) -> Void)?
    let onEnableInternet: ((String) -> Void)?

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.title3)
                    .fontWeight(.medium)
                HStack(spacing: 4) {
                    Text(device.status)
                        .font(.body)
                        .foregroundColor(device.isRunning ? .green : .secondary)
                    if let statusIcon = device.statusIcon {
                        Image(systemName: statusIcon)
                            .font(.body)
                            .foregroundColor(.green)
                    }
                }
                if !device.version.isEmpty && device.version != "Unknown" {
                    Text(device.version)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if let onStart = onStart, let onStop = onStop {
                if device.isRunning {
                    Button("Stop") {
                        onStop(device.id)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                } else {
                    Button("Start") {
                        onStart(device.id)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(6)
        .contextMenu {
            if device.deviceType == .androidEmulator, let udid = device.deviceId, !udid.isEmpty {
                Button("Copy UDID") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(udid, forType: .string)
                }
            } else if !device.id.isEmpty && device.id != device.name {
                Button("Copy UDID") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(device.id, forType: .string)
                }
            }
            Button("Copy Name") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(device.name, forType: .string)
            }
            if device.isRunning && (device.deviceType == .iosSimulator || device.deviceType == .androidEmulator) {
                if device.deviceType == .iosSimulator {
                    Button("Restart Simulator") {
                        onRestart?(device.id, device.deviceType)
                    }
                } else if device.deviceType == .androidEmulator {
                    Button("Restart Emulator") {
                        onRestart?(device.id, device.deviceType)
                    }
                }
                Button("Erase All Content") {
                    onErase?(device.id, device.deviceType)
                }

                // Network control options (Android emulators only)
                if device.deviceType == .androidEmulator {
                    Divider()

                    if let onDisableInternet = onDisableInternet {
                        Button("Disable Internet") {
                            onDisableInternet(device.id)
                        }
                    }
                    if let onEnableInternet = onEnableInternet {
                        Button("Enable Internet") {
                            onEnableInternet(device.id)
                        }
                    }
                }
            }
            if device.deviceType == .iosSimulator || device.deviceType == .androidEmulator {
                Divider()
                Button("Delete", role: .destructive) {
                    onDelete?(device.id, device.deviceType)
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
