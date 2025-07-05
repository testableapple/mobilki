//
//  DeviceManager.swift
//  Mobilki
//
//  Created by Alexey Alter-Pesotskiy on 6/27/25.
//

import Foundation

class DeviceManager: ObservableObject {
    @Published var iosSimulators: [IOSSimulator] = []
    @Published var iosDevices: [IOSDevice] = []
    @Published var androidEmulators: [AndroidEmulator] = []
    @Published var androidDevices: [AndroidDevice] = []
    @Published var isLoading = false

    // MARK: - Helper Functions
    @discardableResult
    private func runProcess(launchPath: String, arguments: [String]) -> (success: Bool, output: String, error: String) {
        let task = Process()
        task.launchPath = launchPath
        task.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = errorPipe

        do {
            try task.run()
            task.waitUntilExit()

            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

            let output = String(data: outputData, encoding: .utf8) ?? ""
            let error = String(data: errorData, encoding: .utf8) ?? ""

            return (task.terminationStatus == 0, output, error)
        } catch {
            return (false, "", error.localizedDescription)
        }
    }

    private func runProcessAsync(launchPath: String, arguments: [String], completion: @escaping (Bool, String, String) -> Void) {
        DispatchQueue.global(qos: .background).async {
            let result = self.runProcess(launchPath: launchPath, arguments: arguments)
            completion(result.success, result.output, result.error)
        }
    }

    private func runProcessWithRefresh(launchPath: String, arguments: [String], refreshAction: @escaping () -> Void) {
        runProcessAsync(launchPath: launchPath, arguments: arguments) { success, output, error in
            if success {
                DispatchQueue.main.async {
                    refreshAction()
                }
            } else {
                print("Process failed: \(error)")
            }
        }
    }

    private func runProcessWithDelay(launchPath: String, arguments: [String], delay: TimeInterval, refreshAction: @escaping () -> Void) {
        runProcessAsync(launchPath: launchPath, arguments: arguments) { success, output, error in
            if success {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    refreshAction()
                }
            } else {
                print("Process failed: \(error)")
            }
        }
    }

    func refreshAll() {
        isLoading = true
        fetchIOSSimulators()
        fetchIOSDevices()
        fetchAndroidEmulators()
        fetchAndroidDevices()
    }

    // MARK: - iOS Simulators
    func fetchIOSSimulators() {
        DispatchQueue.global(qos: .background).async {
            let task = Process()
            task.launchPath = "/usr/bin/xcrun"
            task.arguments = ["simctl", "list", "devices", "--json"]

            let pipe = Pipe()
            task.standardOutput = pipe

            do {
                try task.run()
                task.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let devices = json["devices"] as? [String: Any] {

                    var simulators: [IOSSimulator] = []

                    for (runtime, deviceArray) in devices {
                        if let deviceArray = deviceArray as? [[String: Any]] {
                            for device in deviceArray {
                                if let id = device["udid"] as? String,
                                   let name = device["name"] as? String,
                                   let state = device["state"] as? String,
                                   let isAvailable = device["isAvailable"] as? Bool,
                                   isAvailable {
                                    let version = self.extractIOSVersion(from: runtime)
                                    simulators.append(
                                        IOSSimulator(
                                            id: id,
                                            name: name,
                                            state: state,
                                            runtime: runtime,
                                            version: "iOS \(version)"
                                        )
                                    )
                                }
                            }
                        }
                    }

                    DispatchQueue.main.async {
                        self.iosSimulators = simulators
                        self.isLoading = false
                    }
                }
            } catch {
                // Error fetching iOS simulators
            }
        }
    }

    func startIOSSimulator(id: String) {
        runProcessAsync(launchPath: "/usr/bin/xcrun", arguments: ["simctl", "boot", id]) { success, output, error in
            if success {
                // Open simulator app
                self.runProcessAsync(launchPath: "/usr/bin/open", arguments: ["-a", "Simulator", "--args", "-CurrentDeviceUDID", id]) { success2, output2, error2 in
                    DispatchQueue.main.async {
                        self.fetchIOSSimulators()
                    }
                }
            }
        }
    }

    func stopIOSSimulator(id: String) {
        runProcessWithRefresh(
            launchPath: "/usr/bin/xcrun",
            arguments: ["simctl", "shutdown", id],
            refreshAction: { self.fetchIOSSimulators() }
        )
    }

    // MARK: - iOS Devices
    func fetchIOSDevices() {
        DispatchQueue.global(qos: .background).async {
            // First get USB-connected device IDs
            let usbDeviceIds = self.getUSBDeviceIds()

            let task = Process()
            task.launchPath = "/usr/bin/xcrun"
            task.arguments = ["xctrace", "list", "devices"]

            let pipe = Pipe()
            task.standardOutput = pipe

            do {
                try task.run()
                task.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""

                var devices: [IOSDevice] = []
                var isOfflineSection = false
                let lines = output.components(separatedBy: .newlines)

                for line in lines {
                    if line.contains("== Devices Offline ==") {
                        isOfflineSection = true
                        continue
                    }
                    if line.contains("== Devices ==") {
                        isOfflineSection = false
                        continue
                    }
                    // Skip empty lines, Mac, and Simulators
                    if line.trimmingCharacters(in: .whitespaces).isEmpty || line.localizedCaseInsensitiveContains("macos") || line.localizedCaseInsensitiveContains("simulator") || line.contains("Mac") {
                        continue
                    }
                    // Parse: Name (Version) (UDID)
                    let regex = try! NSRegularExpression(pattern: #"^(.+?) \(([^)]+)\) \(([^)]+)\)$"#)
                    let nsLine = line as NSString
                    if let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: nsLine.length)), match.numberOfRanges == 4 {
                        let name = nsLine.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
                        let version = nsLine.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespaces)
                        let udid = nsLine.substring(with: match.range(at: 3)).trimmingCharacters(in: .whitespaces)
                        let isConnected = !isOfflineSection
                        // Determine connection type based on USB detection
                        let connectionType: IOSDevice.ConnectionType
                        let normalizedDeviceId = udid.replacingOccurrences(of: "-", with: "")
                        if usbDeviceIds.contains(normalizedDeviceId) {
                            connectionType = .usb
                        } else {
                            connectionType = .wifi
                        }
                        devices.append(IOSDevice(id: udid, name: name, isConnected: isConnected, connectionType: connectionType, version: version))
                    }
                }

                DispatchQueue.main.async {
                    self.iosDevices = devices
                }
            } catch {
                // Error fetching iOS devices
            }
        }
    }

    private func getUSBDeviceIds() -> Set<String> {
        let task = Process()
        task.launchPath = "/usr/sbin/system_profiler"
        task.arguments = ["SPUSBDataType"]

        let pipe = Pipe()
        task.standardOutput = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            var usbDeviceIds: Set<String> = []

            // Parse system_profiler output to find iOS device IDs
            let lines = output.components(separatedBy: .newlines)
            for line in lines {
                // Look for lines containing device serial numbers
                if line.contains("Serial Number:") {
                    let components = line.components(separatedBy: "Serial Number:")
                    if components.count >= 2 {
                        let serialNumber = components[1].trimmingCharacters(in: .whitespaces)
                        if serialNumber.count >= 20 { // iOS device IDs are typically 40+ characters
                            // Normalize by removing hyphens for matching
                            let normalizedId = serialNumber.replacingOccurrences(of: "-", with: "")
                            usbDeviceIds.insert(normalizedId)
                        } else if serialNumber.count >= 10 { // Android device IDs are shorter
                            usbDeviceIds.insert(serialNumber)
                        }
                    }
                }
            }

            return usbDeviceIds
        } catch {
            // Error getting USB device IDs
            return []
        }
    }

    // MARK: - Android Emulators
    private func getOfflineEmulatorAPILevel(avdName: String) -> String {
        // Always resolve the .ini file in ~/.android/avd
        let iniPath = "\(NSHomeDirectory())/.android/avd/\(avdName).ini"
        var configPath: String? = nil
        if FileManager.default.fileExists(atPath: iniPath),
           let iniContents = try? String(contentsOfFile: iniPath, encoding: .utf8) {
            for line in iniContents.components(separatedBy: .newlines) {
                if line.hasPrefix("path=") {
                    let path = line.replacingOccurrences(of: "path=", with: "")
                    configPath = path + "/config.ini"
                    break
                }
            }
        }
        // Fallback to default path if .ini not found
        if configPath == nil {
            configPath = "\(NSHomeDirectory())/.android/avd/\(avdName).avd/config.ini"
        }
        guard let configPathUnwrapped = configPath, FileManager.default.fileExists(atPath: configPathUnwrapped),
              let contents = try? String(contentsOfFile: configPathUnwrapped, encoding: .utf8) else {
            print("[Emulator API] Config not found for \(avdName). Tried: \(configPath ?? "nil")")
            return "Unknown"
        }
        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("androidApiLevel=") {
                return "API \(trimmed.replacingOccurrences(of: "androidApiLevel=", with: ""))"
            }
            if trimmed.hasPrefix("target=") {
                // target=android-34
                let value = trimmed.replacingOccurrences(of: "target=android-", with: "")
                if !value.isEmpty { return "API \(value)" }
            }
            // Use regex to match android-XX anywhere in the line
            if let match = trimmed.range(of: "android-\\d+", options: .regularExpression) {
                let api = trimmed[match].replacingOccurrences(of: "android-", with: "")
                return "API \(api)"
            }
        }
        print("[Emulator API] Could not find API in config for \(avdName). Path: \(configPathUnwrapped)\nContents:\n\(contents)")
        return "Unknown"
    }

    func fetchAndroidEmulators() {
        DispatchQueue.global(qos: .background).async {
            guard let emulatorPath = self.findEmulatorPath() else {
                DispatchQueue.main.async {
                    self.androidEmulators = []
                }
                return
            }

            let task = Process()
            task.launchPath = emulatorPath
            task.arguments = ["-list-avds"]

            let pipe = Pipe()
            task.standardOutput = pipe

            do {
                try task.run()
                task.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                let avdNames = output.components(separatedBy: .newlines).filter { !$0.isEmpty }

                // Check which emulators are running and get their device IDs
                let runningEmulators = self.getRunningAndroidEmulators()
                let emulatorDeviceIds = self.getEmulatorDeviceIds()

                let emulators = avdNames.map { name in
                    let isRunning = runningEmulators.contains(name)
                    // If running, get the device ID (using empty string key for any AVD)
                    let deviceId = isRunning ? emulatorDeviceIds[""] : nil
                    let apiLevel: String
                    if isRunning, let deviceId = deviceId {
                        apiLevel = self.getAndroidAPILevel(deviceId: deviceId)
                    } else {
                        apiLevel = self.getOfflineEmulatorAPILevel(avdName: name)
                    }
                    return AndroidEmulator(id: name, name: name, isRunning: isRunning, deviceId: deviceId, apiLevel: apiLevel)
                }

                DispatchQueue.main.async {
                    self.androidEmulators = emulators
                }
            } catch {
                // Error fetching Android emulators
                DispatchQueue.main.async {
                    self.androidEmulators = []
                }
            }
        }
    }

    private func getRunningAndroidEmulators() -> [String] {
        // Use pgrep to find qemu-system processes
        let pgrepTask = Process()
        pgrepTask.launchPath = "/usr/bin/pgrep"
        pgrepTask.arguments = ["-f", "qemu-system.*-avd"]

        let pgrepPipe = Pipe()
        pgrepTask.standardOutput = pgrepPipe

        do {
            try pgrepTask.run()
            pgrepTask.waitUntilExit()

            let pgrepData = pgrepPipe.fileHandleForReading.readDataToEndOfFile()
            let pgrepOutput = String(data: pgrepData, encoding: .utf8) ?? ""

            if pgrepOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return []
            }

            // Now get the full command line for each process
            let pids = pgrepOutput.components(separatedBy: .newlines).filter { !$0.isEmpty }
            var runningEmulators: [String] = []

            for pid in pids {
                let psTask = Process()
                psTask.launchPath = "/bin/ps"
                psTask.arguments = ["-o", "command", "-p", pid]

                let psPipe = Pipe()
                psTask.standardOutput = psPipe

                try psTask.run()
                psTask.waitUntilExit()

                let psData = psPipe.fileHandleForReading.readDataToEndOfFile()
                let psOutput = String(data: psData, encoding: .utf8) ?? ""
                let psLines = psOutput.components(separatedBy: .newlines)

                for line in psLines {
                    if line.contains("-avd") {
                        // Extract AVD name from the command line
                        let components = line.components(separatedBy: " ")
                        for (index, component) in components.enumerated() {
                            if component == "-avd" && index + 1 < components.count {
                                let avdName = components[index + 1]
                                runningEmulators.append(avdName)
                                break
                            }
                        }
                    }
                }
            }

            return runningEmulators
        } catch {
            // Error getting running Android emulators
            return []
        }
    }

    private func getEmulatorDeviceIds() -> [String: String] {
        guard let adbPath = findADBPath() else { return [:] }

        let task = Process()
        task.launchPath = adbPath
        task.arguments = ["devices"]

        let pipe = Pipe()
        task.standardOutput = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            let lines = output.components(separatedBy: .newlines)

            var deviceIds: [String] = []

            for line in lines {
                if line.contains("emulator-") && line.contains("device") {
                    let components = line.components(separatedBy: "\t")
                    if components.count >= 2 {
                        let deviceId = components[0]
                        deviceIds.append(deviceId)
                    }
                }
            }

            // For now, just return the first device ID for any running emulator
            // This is a simplified approach - in a more sophisticated implementation,
            // we'd map specific AVD names to specific device IDs
            if let firstDeviceId = deviceIds.first {
                return ["": firstDeviceId] // Use empty string as key to match any AVD
            }

            return [:]
        } catch {
            // Error getting emulator device IDs
            return [:]
        }
    }

    func startAndroidEmulator(name: String) {
        DispatchQueue.global(qos: .background).async {
            guard let emulatorPath = self.findEmulatorPath() else {
                return
            }

            let task = Process()
            task.launchPath = emulatorPath
            task.arguments = ["-avd", name]

            do {
                try task.run()
                // Don't wait for completion as emulator startup takes time
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    self.fetchAndroidEmulators()
                }
            } catch {
                // Error starting Android emulator
            }
        }
    }

    func stopAndroidEmulator(name: String) {
        guard let adbPath = self.findADBPath() else { return }

        // First get the device ID for the running emulator
        let deviceIds = self.getEmulatorDeviceIds()
        if let deviceId = deviceIds[""] {
            runProcessWithDelay(
                launchPath: adbPath,
                arguments: ["-s", deviceId, "emu", "kill"],
                delay: 2,
                refreshAction: { self.refreshAll() }
            )
        }
    }

    // MARK: - Android Devices
    func fetchAndroidDevices() {
        DispatchQueue.global(qos: .background).async {
            guard let adbPath = self.findADBPath() else {
                DispatchQueue.main.async {
                    self.androidDevices = []
                }
                return
            }

            // First get USB-connected device IDs
            let usbDeviceIds = self.getUSBDeviceIds()

            let task = Process()
            task.launchPath = adbPath
            task.arguments = ["devices", "-l"]

            let pipe = Pipe()
            task.standardOutput = pipe

            do {
                try task.run()
                task.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                let lines = output.components(separatedBy: .newlines)

                var devices: [AndroidDevice] = []

                for line in lines {
                    // Skip empty lines, header, and emulator lines
                    if line.isEmpty || line.contains("List of devices") || line.contains("emulator-") {
                        continue
                    }

                    // Check if this is a device line (contains "device" status)
                    if line.contains("device") {
                        let components = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)

                        if components.count >= 2 {
                            let deviceId = components[0]
                            let deviceInfo = components.dropFirst().joined(separator: " ")

                            // Extract device name from device info
                            let name = self.extractDeviceName(from: deviceInfo, deviceId: deviceId) ?? deviceId

                            // Determine connection type based on USB detection
                            let connectionType: AndroidDevice.ConnectionType
                            if usbDeviceIds.contains(deviceId) {
                                connectionType = .usb
                            } else {
                                connectionType = .wifi
                            }

                            devices.append(AndroidDevice(id: deviceId, name: name, isConnected: true, connectionType: connectionType, apiLevel: self.getAndroidAPILevel(deviceId: deviceId)))
                        }
                    }
                }

                DispatchQueue.main.async {
                    self.androidDevices = devices
                }
            } catch {
                // Error fetching Android devices
                DispatchQueue.main.async {
                    self.androidDevices = []
                }
            }
        }
    }

    private func extractDeviceName(from deviceInfo: String, deviceId: String) -> String? {
        // Extract device name from device info string
        // Example: "device usb:1234567890 product:device_name model:device_model"
        let components = deviceInfo.components(separatedBy: " ")
        for component in components {
            if component.hasPrefix("product:") {
                let productName = String(component.dropFirst(8))

                // Get manufacturer and model from device
                guard let adbPath = findADBPath() else { return productName }

                let task = Process()
                task.launchPath = adbPath
                task.arguments = ["-s", deviceId, "shell", "getprop", "ro.product.manufacturer"]

                let pipe = Pipe()
                task.standardOutput = pipe

                do {
                    try task.run()
                    task.waitUntilExit()

                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let manufacturer = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                    // Get model name
                    let modelTask = Process()
                    modelTask.launchPath = adbPath
                    modelTask.arguments = ["-s", deviceId, "shell", "getprop", "ro.product.model"]

                    let modelPipe = Pipe()
                    modelTask.standardOutput = modelPipe

                    try modelTask.run()
                    modelTask.waitUntilExit()

                    let modelData = modelPipe.fileHandleForReading.readDataToEndOfFile()
                    let model = String(data: modelData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                    // Combine manufacturer and model if both are available
                    if !manufacturer.isEmpty && !model.isEmpty {
                        return "\(manufacturer.capitalized) \(model)"
                    } else if !manufacturer.isEmpty {
                        return manufacturer.capitalized
                    } else if !model.isEmpty {
                        return model
                    } else {
                        return productName
                    }
                } catch {
                    return productName
                }
            }
            if component.hasPrefix("model:") {
                let modelName = String(component.dropFirst(6))
                return modelName
            }
        }
        return deviceId
    }

    // MARK: - Path Detection
    private func findADBPath() -> String? {
        let possiblePaths = [
            "/opt/homebrew/bin/adb",           // Homebrew
            "/usr/local/bin/adb",              // Manual install
            "/usr/bin/adb",                    // System
            "\(NSHomeDirectory())/Library/Android/sdk/platform-tools/adb", // User Android SDK
        ]

        // Check if any of the possible paths exist
        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        // Try using 'which' command as fallback
        let task = Process()
        task.launchPath = "/usr/bin/which"
        task.arguments = ["adb"]

        let pipe = Pipe()
        task.standardOutput = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            if !output.isEmpty && FileManager.default.fileExists(atPath: output) {
                return output
            }
        } catch {
            // Error finding adb with 'which'
        }

        return nil
    }

    private func findEmulatorPath() -> String? {
        let possiblePaths = [
            "\(NSHomeDirectory())/Library/Android/sdk/emulator/emulator", // User Android SDK
            "/opt/homebrew/bin/emulator",      // Homebrew
            "/usr/local/bin/emulator"          // Manual install
        ]

        // Check if any of the possible paths exist
        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        // Try using 'which' command as fallback
        let task = Process()
        task.launchPath = "/usr/bin/which"
        task.arguments = ["emulator"]

        let pipe = Pipe()
        task.standardOutput = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            if !output.isEmpty && FileManager.default.fileExists(atPath: output) {
                return output
            }
        } catch {
            // Error finding emulator with 'which'
        }

        return nil
    }

    func deleteIOSSimulator(id: String) {
        runProcessWithDelay(
            launchPath: "/usr/bin/xcrun",
            arguments: ["simctl", "delete", id],
            delay: 1,
            refreshAction: { self.fetchIOSSimulators() }
        )
    }

    func eraseIOSSimulator(id: String) {
        runProcessAsync(launchPath: "/usr/bin/xcrun", arguments: ["simctl", "shutdown", id]) { success, output, error in
            // Wait a moment for shutdown to complete
            Thread.sleep(forTimeInterval: 2)

            // Now erase the simulator
            self.runProcessAsync(launchPath: "/usr/bin/xcrun", arguments: ["simctl", "erase", id]) { success2, output2, error2 in
                // Wait a moment for erase to complete
                Thread.sleep(forTimeInterval: 1)

                // Boot the simulator after erasing
                self.runProcessAsync(launchPath: "/usr/bin/xcrun", arguments: ["simctl", "boot", id]) { success3, output3, error3 in
                    // Refresh after the complete process
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        self.refreshAll()
                    }
                }
            }
        }
    }

    func eraseAndroidEmulator(name: String) {
        guard let adbPath = self.findADBPath() else { return }

        runProcessAsync(launchPath: adbPath, arguments: ["devices"]) { success, output, error in
            // Find the emulator device ID
            var deviceId: String?
            let lines = output.components(separatedBy: .newlines)
            for line in lines {
                if line.contains("emulator-") && line.contains("device") {
                    let components = line.components(separatedBy: "\t")
                    if components.count >= 2 {
                        deviceId = components[0]
                        break
                    }
                }
            }

            if let deviceId = deviceId {
                // First, get list of installed packages (excluding system apps)
                self.runProcessAsync(launchPath: adbPath, arguments: ["-s", deviceId, "shell", "pm", "list", "packages", "-3"]) { success2, output2, error2 in
                    let packages = output2.components(separatedBy: .newlines)
                        .filter { $0.hasPrefix("package:") }
                        .map { String($0.dropFirst(8)) } // Remove "package:" prefix

                    // Uninstall all user-installed apps
                    for package in packages {
                        self.runProcess(launchPath: adbPath, arguments: ["-s", deviceId, "shell", "pm", "uninstall", package])
                    }

                    // Clear data for system apps
                    let systemApps = [
                        "com.android.settings",
                        "com.android.launcher",
                        "com.google.android.gm",
                        "com.android.vending",
                        "com.google.android.apps.maps"
                    ]

                    for app in systemApps {
                        self.runProcess(launchPath: adbPath, arguments: ["-s", deviceId, "shell", "pm", "clear", app])
                    }

                    // Wait a moment for operations to complete
                    Thread.sleep(forTimeInterval: 3)

                    // Refresh after erase
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        self.refreshAll()
                    }
                }
            }
        }
    }

    // MARK: - Version Extraction
    private func extractIOSVersion(from runtime: String) -> String {
        // Extract version from runtime string like "com.apple.CoreSimulator.SimRuntime.iOS-18-5-0"
        if runtime.contains("iOS-") {
            let components = runtime.components(separatedBy: "iOS-")
            if components.count >= 2 {
                let versionPart = components[1]
                // Take only the major.minor version (first two parts)
                let versionComponents = versionPart.components(separatedBy: "-")
                if versionComponents.count >= 2 {
                    return "\(versionComponents[0]).\(versionComponents[1])"
                } else if versionComponents.count == 1 {
                    return versionComponents[0]
                }
            }
        }
        // Fallback: try to extract any version-like pattern
        if runtime.contains("iOS") {
            let components = runtime.components(separatedBy: " ")
            if components.count >= 2 {
                return components[1]
            }
        }
        return runtime
    }

    private func getAndroidAPILevel(deviceId: String) -> String {
        guard let adbPath = findADBPath() else { return "Unknown" }

        let result = runProcess(launchPath: adbPath, arguments: ["-s", deviceId, "shell", "getprop", "ro.build.version.sdk"])

        if result.success && !result.output.isEmpty {
            return "API \(result.output.trimmingCharacters(in: .whitespacesAndNewlines))"
        }

        return "Unknown"
    }

    func restartIOSSimulator(id: String) {
        runProcessAsync(launchPath: "/usr/bin/xcrun", arguments: ["simctl", "shutdown", id]) { success, output, error in
            // Wait a bit for shutdown, then start
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self.startIOSSimulator(id: id)
            }
        }
    }

    func restartAndroidEmulator(name: String) {
        stopAndroidEmulator(name: name)
        // Wait a bit for shutdown, then start
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.startAndroidEmulator(name: name)
        }
    }

    // MARK: - Network Control (Android Emulators Only)
    func setInternetForAndroidEmulator(name: String, enable: Bool) {
        guard let adbPath = self.findADBPath() else { return }

        runProcessAsync(launchPath: adbPath, arguments: ["devices"]) { success, output, error in
            // Find the emulator device ID
            var deviceId: String?
            let lines = output.components(separatedBy: .newlines)
            for line in lines {
                if line.contains("emulator-") && line.contains("device") {
                    let components = line.components(separatedBy: "\t")
                    if components.count >= 2 {
                        deviceId = components[0]
                        break
                    }
                }
            }

            if let deviceId = deviceId {
                let action = enable ? "enable" : "disable"

                // Set WiFi state
                self.runProcess(launchPath: adbPath, arguments: ["-s", deviceId, "shell", "svc", "wifi", action])

                // Set mobile data state
                self.runProcess(launchPath: adbPath, arguments: ["-s", deviceId, "shell", "svc", "data", action])

                print("\(enable ? "Enabled" : "Disabled") internet for Android emulator: \(name)")
            }
        }
    }

    func deleteAndroidEmulator(name: String) {
        DispatchQueue.global(qos: .background).async {
            // Skip avdmanager due to JAXB compatibility issues and go straight to filesystem deletion
            self.deleteAndroidEmulatorFromFilesystem(name: name)
        }
    }

    private func deleteAndroidEmulatorFromFilesystem(name: String) {
        print("Deleting Android emulator: \(name)")

        // Directly delete AVD files from filesystem
        let possibleAVDPaths = [
            "\(NSHomeDirectory())/.android/avd/\(name).avd",
            "\(NSHomeDirectory())/Library/Android/sdk/avd/\(name).avd"
        ]

        for avdPath in possibleAVDPaths {
            print("Checking path: \(avdPath)")
            if FileManager.default.fileExists(atPath: avdPath) {
                print("Found AVD at: \(avdPath)")
                do {
                    try FileManager.default.removeItem(atPath: avdPath)
                    print("Successfully deleted AVD directory")

                    // Also try to remove the .ini file
                    let iniPath = avdPath.replacingOccurrences(of: ".avd", with: ".ini")
                    if FileManager.default.fileExists(atPath: iniPath) {
                        try FileManager.default.removeItem(atPath: iniPath)
                        print("Successfully deleted AVD ini file")
                    }

                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        self.fetchAndroidEmulators()
                    }
                    return
                } catch {
                    print("Error deleting AVD: \(error)")
                    // Continue to next path if this one fails
                }
            }
        }

        print("No AVD found to delete")
        // If all else fails, refresh anyway
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.fetchAndroidEmulators()
        }
    }
}
