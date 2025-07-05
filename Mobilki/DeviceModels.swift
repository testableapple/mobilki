//
//  DeviceModels.swift
//  Mobilki
//
//  Created by Alexey Alter-Pesotskiy on 6/27/25.
//

import Foundation
import SwiftUI

struct IOSSimulator: Identifiable, Codable {
    let id: String
    let name: String
    let state: String
    let runtime: String
    let version: String

    var isRunning: Bool {
        return state == "Booted"
    }
}

struct IOSDevice: Identifiable {
    let id: String
    let name: String
    let isConnected: Bool
    let connectionType: ConnectionType
    let version: String

    enum ConnectionType {
        case usb
        case wifi

        var displayName: String {
            switch self {
            case .usb: return "USB"
            case .wifi: return "WiFi"
            }
        }
    }
}

struct AndroidEmulator: Identifiable {
    let id: String
    let name: String
    let isRunning: Bool
    let deviceId: String? // The actual device ID (e.g., "emulator-5554") when running
    let apiLevel: String
}

struct AndroidDevice: Identifiable {
    let id: String
    let name: String
    let isConnected: Bool
    let connectionType: ConnectionType
    let apiLevel: String

    enum ConnectionType {
        case usb
        case wifi

        var displayName: String {
            switch self {
            case .usb: return "USB"
            case .wifi: return "WiFi"
            }
        }
    }
}
