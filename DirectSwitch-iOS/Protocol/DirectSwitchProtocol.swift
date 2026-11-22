//
//  DirectSwitchProtocol.swift
//  DirectSwitch-iOS
//
//  Created by Nicolas Donati.
//  Copyright © 2026 Nicolas Donati. Tutti i diritti riservati.
//

import Foundation
import CryptoKit
import Security

enum DevicePlatform: String, Codable, Sendable {
    case ANDROID
    case IOS
}

enum SessionLicenseTier: String, Codable, Sendable {
    case INTRA_OS_FREE
    case CROSS_OS_PREVIEW
    case CROSS_OS_PRO_UNLOCKED
}

enum TransferCategory: String, Codable, Sendable {
    case CONTACTS
    case PHOTOS
    case VIDEOS
    case CALENDARS
    case DOCUMENTS
    case AUDIO
    case SMS_HISTORY
    case WHATSAPP_VAULT
}

/// Payload completo codificato solo nel QR Code (o scambiato via PIN autenticato).
struct QrPairingPayload: Codable, Equatable, Sendable {
    var proto: String = "DSWITCH_V1"
    let sessionId: String
    let receiverName: String
    let receiverPlatform: DevicePlatform
    let ips: [String]
    let port: Int
    let sessionKeyHex: String
    var wifiSsid: String? = nil
    var wifiPass: String? = nil
    var receiverHasPro: Bool = false

    enum CodingKeys: String, CodingKey {
        case proto, sessionId, receiverName, receiverPlatform, ips, port, sessionKeyHex, wifiSsid, wifiPass, receiverHasPro
    }

    init(
        proto: String = "DSWITCH_V1",
        sessionId: String,
        receiverName: String,
        receiverPlatform: DevicePlatform,
        ips: [String],
        port: Int,
        sessionKeyHex: String,
        wifiSsid: String? = nil,
        wifiPass: String? = nil,
        receiverHasPro: Bool = false
    ) {
        self.proto = proto
        self.sessionId = sessionId
        self.receiverName = receiverName
        self.receiverPlatform = receiverPlatform
        self.ips = ips
        self.port = port
        self.sessionKeyHex = sessionKeyHex
        self.wifiSsid = wifiSsid
        self.wifiPass = wifiPass
        self.receiverHasPro = receiverHasPro
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        proto = try c.decodeIfPresent(String.self, forKey: .proto) ?? "DSWITCH_V1"
        sessionId = try c.decode(String.self, forKey: .sessionId)
        receiverName = try c.decode(String.self, forKey: .receiverName)
        receiverPlatform = try c.decode(DevicePlatform.self, forKey: .receiverPlatform)
        ips = try c.decode([String].self, forKey: .ips)
        port = try c.decode(Int.self, forKey: .port)
        sessionKeyHex = try c.decode(String.self, forKey: .sessionKeyHex)
        wifiSsid = try c.decodeIfPresent(String.self, forKey: .wifiSsid)
        wifiPass = try c.decodeIfPresent(String.self, forKey: .wifiPass)
        receiverHasPro = try c.decodeIfPresent(Bool.self, forKey: .receiverHasPro) ?? false
    }

    func toCompactJson() -> String {
        guard let data = try? JSONEncoder().encode(self),
              let str = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return str
    }

    func toPublicBeacon() -> DiscoveryBeaconPayload {
        DiscoveryBeaconPayload(
            sessionId: sessionId,
            receiverName: receiverName,
            receiverPlatform: receiverPlatform,
            ips: ips,
            port: port,
            receiverHasPro: receiverHasPro
        )
    }

    static func fromJson(_ raw: String) throws -> QrPairingPayload {
        guard let data = raw.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8) else {
            throw NSError(domain: "DirectSwitch", code: -1, userInfo: [NSLocalizedDescriptionKey: "QR non valido"])
        }
        return try JSONDecoder().decode(QrPairingPayload.self, from: data)
    }
}

/// Beacon UDP pubblico privo di chiavi segrete o password Wi-Fi.
struct DiscoveryBeaconPayload: Codable, Equatable, Sendable {
    var proto: String = "DSWITCH_BEACON_V1"
    let sessionId: String
    let receiverName: String
    let receiverPlatform: DevicePlatform
    let ips: [String]
    let port: Int
    var receiverHasPro: Bool = false

    enum CodingKeys: String, CodingKey {
        case proto, sessionId, receiverName, receiverPlatform, ips, port, receiverHasPro
    }

    init(
        proto: String = "DSWITCH_BEACON_V1",
        sessionId: String,
        receiverName: String,
        receiverPlatform: DevicePlatform,
        ips: [String],
        port: Int,
        receiverHasPro: Bool = false
    ) {
        self.proto = proto
        self.sessionId = sessionId
        self.receiverName = receiverName
        self.receiverPlatform = receiverPlatform
        self.ips = ips
        self.port = port
        self.receiverHasPro = receiverHasPro
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        proto = try c.decodeIfPresent(String.self, forKey: .proto) ?? "DSWITCH_BEACON_V1"
        sessionId = try c.decode(String.self, forKey: .sessionId)
        receiverName = try c.decode(String.self, forKey: .receiverName)
        receiverPlatform = try c.decode(DevicePlatform.self, forKey: .receiverPlatform)
        ips = try c.decode([String].self, forKey: .ips)
        port = try c.decode(Int.self, forKey: .port)
        receiverHasPro = try c.decodeIfPresent(Bool.self, forKey: .receiverHasPro) ?? false
    }

    func toCompactJson() -> String {
        guard let data = try? JSONEncoder().encode(self),
              let str = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return str
    }

    /// Determina se due beacon appartengono allo stesso dispositivo fisico sulla rete locale,
    /// evitando duplicati quando la schermata 'Ricevi' viene riavviata con un nuovo `sessionId`.
    func representsSameDevice(as other: DiscoveryBeaconPayload) -> Bool {
        if sessionId == other.sessionId {
            return true
        }
        let myIps = Set(ips.filter { !$0.isEmpty })
        let otherIps = Set(other.ips.filter { !$0.isEmpty })
        if !myIps.isEmpty && !otherIps.isEmpty && !myIps.isDisjoint(with: otherIps) {
            return true
        }
        return receiverPlatform == other.receiverPlatform
            && receiverName == other.receiverName
            && port == other.port
            && (myIps.isEmpty || otherIps.isEmpty)
    }

    static func fromJson(_ raw: String) throws -> DiscoveryBeaconPayload {
        guard let data = raw.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8) else {
            throw NSError(domain: "DirectSwitch", code: -2, userInfo: [NSLocalizedDescriptionKey: "Beacon non valido"])
        }
        let decoded = try JSONDecoder().decode(DiscoveryBeaconPayload.self, from: data)
        guard decoded.proto == "DSWITCH_BEACON_V1", !decoded.sessionId.isEmpty else {
            throw NSError(domain: "DirectSwitch", code: -3, userInfo: [NSLocalizedDescriptionKey: "Protocollo beacon non riconosciuto"])
        }
        return decoded
    }
}

struct PinPairingRequest: Codable, Sendable {
    let sessionId: String
    let senderName: String
}

struct ActiveTransferScope: Codable, Equatable, Sendable {
    var contacts: Bool = false
    var photos: Bool = false
    var videos: Bool = false
    var calendars: Bool = false
    var reminders: Bool = false
    var documents: Bool = false
    var audio: Bool = false
    var callLogs: Bool = false
    var apps: Bool = false
    var whatsApp: Bool = false

    enum CodingKeys: String, CodingKey {
        case contacts, photos, videos, calendars, reminders, documents, audio, callLogs, apps, whatsApp
    }

    init(
        contacts: Bool = false,
        photos: Bool = false,
        videos: Bool = false,
        calendars: Bool = false,
        reminders: Bool = false,
        documents: Bool = false,
        audio: Bool = false,
        callLogs: Bool = false,
        apps: Bool = false,
        whatsApp: Bool = false
    ) {
        self.contacts = contacts
        self.photos = photos
        self.videos = videos
        self.calendars = calendars
        self.reminders = reminders
        self.documents = documents
        self.audio = audio
        self.callLogs = callLogs
        self.apps = apps
        self.whatsApp = whatsApp
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        contacts = try c.decodeIfPresent(Bool.self, forKey: .contacts) ?? false
        photos = try c.decodeIfPresent(Bool.self, forKey: .photos) ?? false
        videos = try c.decodeIfPresent(Bool.self, forKey: .videos) ?? false
        calendars = try c.decodeIfPresent(Bool.self, forKey: .calendars) ?? false
        reminders = try c.decodeIfPresent(Bool.self, forKey: .reminders) ?? false
        documents = try c.decodeIfPresent(Bool.self, forKey: .documents) ?? false
        audio = try c.decodeIfPresent(Bool.self, forKey: .audio) ?? false
        callLogs = try c.decodeIfPresent(Bool.self, forKey: .callLogs) ?? false
        apps = try c.decodeIfPresent(Bool.self, forKey: .apps) ?? false
        whatsApp = try c.decodeIfPresent(Bool.self, forKey: .whatsApp) ?? false
    }

    var hasAnyStandardDataCategory: Bool {
        contacts || photos || videos || calendars || reminders || documents || audio || callLogs || apps
    }

    var isWhatsAppOnly: Bool {
        whatsApp && !hasAnyStandardDataCategory
    }

    var isAppsOnly: Bool {
        apps && !contacts && !photos && !videos && !calendars && !reminders && !documents && !audio && !callLogs && !whatsApp
    }

    var hasMediaOrDocuments: Bool {
        photos || videos || documents || audio
    }

    static func inferred(from manifest: TransferManifest) -> ActiveTransferScope {
        let hasPhotos = manifest.items.contains { $0.category == .PHOTOS }
        let hasVideos = manifest.items.contains { $0.category == .VIDEOS }
        let hasDocs = manifest.items.contains { $0.category == .DOCUMENTS }
        let hasAudio = manifest.items.contains { $0.category == .AUDIO }
        let hasWaVault = manifest.items.contains { $0.category == .WHATSAPP_VAULT }
        return ActiveTransferScope(
            contacts: !manifest.contactsPayload.isEmpty,
            photos: hasPhotos,
            videos: hasVideos,
            calendars: !manifest.calendarsPayload.isEmpty,
            reminders: !(manifest.remindersPayload ?? []).isEmpty,
            documents: hasDocs,
            audio: hasAudio,
            callLogs: !(manifest.callLogsPayload ?? []).isEmpty,
            apps: !(manifest.installedAppsPayload ?? []).isEmpty,
            whatsApp: (manifest.requestNativeWhatsAppMigration == true) || hasWaVault
        )
    }
}

struct HandshakeRequest: Codable, Sendable {
    let sessionId: String
    let senderName: String
    let senderPlatform: DevicePlatform
    let senderHasPro: Bool
    var senderHasCloudSavePro: Bool = false
    var totalEstimatedBytes: Int64 = 0
    var isResume: Bool? = nil
    var transferScope: ActiveTransferScope? = nil

    enum CodingKeys: String, CodingKey {
        case sessionId, senderName, senderPlatform, senderHasPro, senderHasCloudSavePro, totalEstimatedBytes, isResume, transferScope
    }

    init(
        sessionId: String,
        senderName: String,
        senderPlatform: DevicePlatform,
        senderHasPro: Bool,
        senderHasCloudSavePro: Bool = false,
        totalEstimatedBytes: Int64 = 0,
        isResume: Bool? = nil,
        transferScope: ActiveTransferScope? = nil
    ) {
        self.sessionId = sessionId
        self.senderName = senderName
        self.senderPlatform = senderPlatform
        self.senderHasPro = senderHasPro
        self.senderHasCloudSavePro = senderHasCloudSavePro
        self.totalEstimatedBytes = totalEstimatedBytes
        self.isResume = isResume
        self.transferScope = transferScope
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessionId = try c.decode(String.self, forKey: .sessionId)
        senderName = try c.decode(String.self, forKey: .senderName)
        senderPlatform = try c.decode(DevicePlatform.self, forKey: .senderPlatform)
        senderHasPro = try c.decodeIfPresent(Bool.self, forKey: .senderHasPro) ?? false
        senderHasCloudSavePro = try c.decodeIfPresent(Bool.self, forKey: .senderHasCloudSavePro) ?? false
        totalEstimatedBytes = try c.decodeIfPresent(Int64.self, forKey: .totalEstimatedBytes) ?? 0
        isResume = try c.decodeIfPresent(Bool.self, forKey: .isResume)
        transferScope = try c.decodeIfPresent(ActiveTransferScope.self, forKey: .transferScope)
    }
}

struct HandshakeResponse: Codable, Sendable {
    let accepted: Bool
    let receiverName: String
    let receiverPlatform: DevicePlatform
    let freeStorageBytes: Int64
    let licenseTier: SessionLicenseTier
    let hasEnoughSpace: Bool
    let statusMessage: String
    var supportsCrossOsLiveMotion: Bool? = nil
    var receiverInstalledAppIds: [String]? = nil
    var supportsReconcile: Bool? = nil

    enum CodingKeys: String, CodingKey {
        case accepted, receiverName, receiverPlatform, freeStorageBytes, licenseTier, hasEnoughSpace, statusMessage
        case supportsCrossOsLiveMotion, receiverInstalledAppIds, supportsReconcile
    }

    init(
        accepted: Bool,
        receiverName: String,
        receiverPlatform: DevicePlatform,
        freeStorageBytes: Int64,
        licenseTier: SessionLicenseTier,
        hasEnoughSpace: Bool,
        statusMessage: String,
        supportsCrossOsLiveMotion: Bool? = nil,
        receiverInstalledAppIds: [String]? = nil,
        supportsReconcile: Bool? = nil
    ) {
        self.accepted = accepted
        self.receiverName = receiverName
        self.receiverPlatform = receiverPlatform
        self.freeStorageBytes = freeStorageBytes
        self.licenseTier = licenseTier
        self.hasEnoughSpace = hasEnoughSpace
        self.statusMessage = statusMessage
        self.supportsCrossOsLiveMotion = supportsCrossOsLiveMotion
        self.receiverInstalledAppIds = receiverInstalledAppIds
        self.supportsReconcile = supportsReconcile
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        accepted = try c.decode(Bool.self, forKey: .accepted)
        receiverName = try c.decode(String.self, forKey: .receiverName)
        receiverPlatform = try c.decode(DevicePlatform.self, forKey: .receiverPlatform)
        freeStorageBytes = try c.decode(Int64.self, forKey: .freeStorageBytes)
        licenseTier = try c.decode(SessionLicenseTier.self, forKey: .licenseTier)
        hasEnoughSpace = try c.decode(Bool.self, forKey: .hasEnoughSpace)
        statusMessage = try c.decode(String.self, forKey: .statusMessage)
        supportsCrossOsLiveMotion = try c.decodeIfPresent(Bool.self, forKey: .supportsCrossOsLiveMotion)
        receiverInstalledAppIds = try c.decodeIfPresent([String].self, forKey: .receiverInstalledAppIds)
        supportsReconcile = try c.decodeIfPresent(Bool.self, forKey: .supportsReconcile)
    }
}

struct ReconcileManifestRequest: Codable, Sendable {
    let sessionId: String
    let sentItemIds: [String]
    var expectedSha256ById: [String: String] = [:]

    enum CodingKeys: String, CodingKey {
        case sessionId, sentItemIds, expectedSha256ById
    }

    init(sessionId: String, sentItemIds: [String], expectedSha256ById: [String: String] = [:]) {
        self.sessionId = sessionId
        self.sentItemIds = sentItemIds
        self.expectedSha256ById = expectedSha256ById
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessionId = try c.decode(String.self, forKey: .sessionId)
        sentItemIds = try c.decodeIfPresent([String].self, forKey: .sentItemIds) ?? []
        expectedSha256ById = try c.decodeIfPresent([String: String].self, forKey: .expectedSha256ById) ?? [:]
    }
}

struct ReconcileManifestResponse: Codable, Sendable {
    var committedIds: [String] = []
    var missingIds: [String] = []
    var hashMismatchIds: [String] = []
    var totalVerified: Int = 0

    enum CodingKeys: String, CodingKey {
        case committedIds, missingIds, hashMismatchIds, totalVerified
    }

    init(committedIds: [String] = [], missingIds: [String] = [], hashMismatchIds: [String] = [], totalVerified: Int = 0) {
        self.committedIds = committedIds
        self.missingIds = missingIds
        self.hashMismatchIds = hashMismatchIds
        self.totalVerified = totalVerified
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        committedIds = try c.decodeIfPresent([String].self, forKey: .committedIds) ?? []
        missingIds = try c.decodeIfPresent([String].self, forKey: .missingIds) ?? []
        hashMismatchIds = try c.decodeIfPresent([String].self, forKey: .hashMismatchIds) ?? []
        totalVerified = try c.decodeIfPresent(Int.self, forKey: .totalVerified) ?? committedIds.count
    }
}

struct LabeledValueRecord: Codable, Equatable, Sendable {
    let label: String
    let value: String
}

struct PostalAddressTransferRecord: Codable, Equatable, Sendable {
    var label: String? = nil
    var street: String = ""
    var city: String = ""
    var state: String = ""
    var postalCode: String = ""
    var country: String = ""

    enum CodingKeys: String, CodingKey {
        case label, street, city, state, postalCode, country
    }

    init(
        label: String? = nil,
        street: String = "",
        city: String = "",
        state: String = "",
        postalCode: String = "",
        country: String = ""
    ) {
        self.label = label
        self.street = street
        self.city = city
        self.state = state
        self.postalCode = postalCode
        self.country = country
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        label = try c.decodeIfPresent(String.self, forKey: .label)
        street = try c.decodeIfPresent(String.self, forKey: .street) ?? ""
        city = try c.decodeIfPresent(String.self, forKey: .city) ?? ""
        state = try c.decodeIfPresent(String.self, forKey: .state) ?? ""
        postalCode = try c.decodeIfPresent(String.self, forKey: .postalCode) ?? ""
        country = try c.decodeIfPresent(String.self, forKey: .country) ?? ""
    }
}

struct ContactTransferRecord: Codable, Identifiable, Sendable {
    let id: String
    let displayName: String
    let phones: [String]
    var emails: [String] = []
    var organization: String? = nil
    var note: String? = nil
    var givenName: String? = nil
    var familyName: String? = nil
    var nickname: String? = nil
    var jobTitle: String? = nil
    var birthdayYear: Int? = nil
    var birthdayMonth: Int? = nil
    var birthdayDay: Int? = nil
    var labeledPhones: [LabeledValueRecord]? = nil
    var labeledEmails: [LabeledValueRecord]? = nil
    var urls: [String]? = nil
    var postalAddresses: [PostalAddressTransferRecord]? = nil
    var avatarJpegBase64: String? = nil

    enum CodingKeys: String, CodingKey {
        case id, displayName, phones, emails, organization, note
        case givenName, familyName, nickname, jobTitle
        case birthdayYear, birthdayMonth, birthdayDay
        case labeledPhones, labeledEmails, urls, postalAddresses, avatarJpegBase64
    }

    init(
        id: String,
        displayName: String,
        phones: [String],
        emails: [String] = [],
        organization: String? = nil,
        note: String? = nil,
        givenName: String? = nil,
        familyName: String? = nil,
        nickname: String? = nil,
        jobTitle: String? = nil,
        birthdayYear: Int? = nil,
        birthdayMonth: Int? = nil,
        birthdayDay: Int? = nil,
        labeledPhones: [LabeledValueRecord]? = nil,
        labeledEmails: [LabeledValueRecord]? = nil,
        urls: [String]? = nil,
        postalAddresses: [PostalAddressTransferRecord]? = nil,
        avatarJpegBase64: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.phones = phones
        self.emails = emails
        self.organization = organization
        self.note = note
        self.givenName = givenName
        self.familyName = familyName
        self.nickname = nickname
        self.jobTitle = jobTitle
        self.birthdayYear = birthdayYear
        self.birthdayMonth = birthdayMonth
        self.birthdayDay = birthdayDay
        self.labeledPhones = labeledPhones
        self.labeledEmails = labeledEmails
        self.urls = urls
        self.postalAddresses = postalAddresses
        self.avatarJpegBase64 = avatarJpegBase64
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        displayName = try c.decode(String.self, forKey: .displayName)
        phones = try c.decodeIfPresent([String].self, forKey: .phones) ?? []
        emails = try c.decodeIfPresent([String].self, forKey: .emails) ?? []
        organization = try c.decodeIfPresent(String.self, forKey: .organization)
        note = try c.decodeIfPresent(String.self, forKey: .note)
        givenName = try c.decodeIfPresent(String.self, forKey: .givenName)
        familyName = try c.decodeIfPresent(String.self, forKey: .familyName)
        nickname = try c.decodeIfPresent(String.self, forKey: .nickname)
        jobTitle = try c.decodeIfPresent(String.self, forKey: .jobTitle)
        birthdayYear = try c.decodeIfPresent(Int.self, forKey: .birthdayYear)
        birthdayMonth = try c.decodeIfPresent(Int.self, forKey: .birthdayMonth)
        birthdayDay = try c.decodeIfPresent(Int.self, forKey: .birthdayDay)
        labeledPhones = try c.decodeIfPresent([LabeledValueRecord].self, forKey: .labeledPhones)
        labeledEmails = try c.decodeIfPresent([LabeledValueRecord].self, forKey: .labeledEmails)
        urls = try c.decodeIfPresent([String].self, forKey: .urls)
        postalAddresses = try c.decodeIfPresent([PostalAddressTransferRecord].self, forKey: .postalAddresses)
        avatarJpegBase64 = try c.decodeIfPresent(String.self, forKey: .avatarJpegBase64)
    }
}

struct CalendarEventRecord: Codable, Identifiable, Sendable {
    let id: String
    let title: String
    var description: String? = nil
    var location: String? = nil
    let startEpochMillis: Int64
    let endEpochMillis: Int64
    var allDay: Bool = false
    var rrule: String? = nil
    var calendarTitle: String? = nil
    var recurrenceFrequency: String? = nil
    var recurrenceInterval: Int? = nil
    var alarmOffsetSeconds: Double? = nil

    enum CodingKeys: String, CodingKey {
        case id, title, description, location, startEpochMillis, endEpochMillis
        case allDay, rrule, calendarTitle, recurrenceFrequency, recurrenceInterval, alarmOffsetSeconds
    }

    init(
        id: String,
        title: String,
        description: String? = nil,
        location: String? = nil,
        startEpochMillis: Int64,
        endEpochMillis: Int64,
        allDay: Bool = false,
        rrule: String? = nil,
        calendarTitle: String? = nil,
        recurrenceFrequency: String? = nil,
        recurrenceInterval: Int? = nil,
        alarmOffsetSeconds: Double? = nil
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.location = location
        self.startEpochMillis = startEpochMillis
        self.endEpochMillis = endEpochMillis
        self.allDay = allDay
        self.rrule = rrule
        self.calendarTitle = calendarTitle
        self.recurrenceFrequency = recurrenceFrequency
        self.recurrenceInterval = recurrenceInterval
        self.alarmOffsetSeconds = alarmOffsetSeconds
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        location = try c.decodeIfPresent(String.self, forKey: .location)
        startEpochMillis = try c.decode(Int64.self, forKey: .startEpochMillis)
        endEpochMillis = try c.decode(Int64.self, forKey: .endEpochMillis)
        allDay = try c.decodeIfPresent(Bool.self, forKey: .allDay) ?? false
        rrule = try c.decodeIfPresent(String.self, forKey: .rrule)
        calendarTitle = try c.decodeIfPresent(String.self, forKey: .calendarTitle)
        recurrenceFrequency = try c.decodeIfPresent(String.self, forKey: .recurrenceFrequency)
        recurrenceInterval = try c.decodeIfPresent(Int.self, forKey: .recurrenceInterval)
        alarmOffsetSeconds = try c.decodeIfPresent(Double.self, forKey: .alarmOffsetSeconds)
    }
}

struct ReminderTransferRecord: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    var notes: String? = nil
    var listName: String? = nil
    var isCompleted: Bool = false
    var priority: Int = 0
    var dueEpochMillis: Int64? = nil

    enum CodingKeys: String, CodingKey {
        case id, title, notes, listName, isCompleted, priority, dueEpochMillis
    }

    init(
        id: String,
        title: String,
        notes: String? = nil,
        listName: String? = nil,
        isCompleted: Bool = false,
        priority: Int = 0,
        dueEpochMillis: Int64? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.listName = listName
        self.isCompleted = isCompleted
        self.priority = priority
        self.dueEpochMillis = dueEpochMillis
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        listName = try c.decodeIfPresent(String.self, forKey: .listName)
        isCompleted = try c.decodeIfPresent(Bool.self, forKey: .isCompleted) ?? false
        priority = try c.decodeIfPresent(Int.self, forKey: .priority) ?? 0
        dueEpochMillis = try c.decodeIfPresent(Int64.self, forKey: .dueEpochMillis)
    }
}

struct SmsTransferRecord: Codable, Identifiable, Sendable {
    let id: String
    let address: String
    let body: String
    let dateEpochMillis: Int64
    var messageType: Int = 1

    enum CodingKeys: String, CodingKey {
        case id, address, body, dateEpochMillis, messageType
    }

    init(
        id: String,
        address: String,
        body: String,
        dateEpochMillis: Int64,
        messageType: Int = 1
    ) {
        self.id = id
        self.address = address
        self.body = body
        self.dateEpochMillis = dateEpochMillis
        self.messageType = messageType
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        address = try c.decode(String.self, forKey: .address)
        body = try c.decode(String.self, forKey: .body)
        dateEpochMillis = try c.decode(Int64.self, forKey: .dateEpochMillis)
        messageType = try c.decodeIfPresent(Int.self, forKey: .messageType) ?? 1
    }
}

struct CallLogTransferRecord: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let number: String
    var cachedName: String? = nil
    /// 1 = Ricevuta, 2 = Effettuata, 3 = Persa, 5 = Rifiutata
    var callType: Int = 1
    let dateEpochMillis: Int64
    var durationSeconds: Int64 = 0

    enum CodingKeys: String, CodingKey {
        case id, number, cachedName, callType, dateEpochMillis, durationSeconds
    }

    init(
        id: String,
        number: String,
        cachedName: String? = nil,
        callType: Int = 1,
        dateEpochMillis: Int64,
        durationSeconds: Int64 = 0
    ) {
        self.id = id
        self.number = number
        self.cachedName = cachedName
        self.callType = callType
        self.dateEpochMillis = dateEpochMillis
        self.durationSeconds = durationSeconds
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        number = try c.decode(String.self, forKey: .number)
        cachedName = try c.decodeIfPresent(String.self, forKey: .cachedName)
        callType = try c.decodeIfPresent(Int.self, forKey: .callType) ?? 1
        dateEpochMillis = try c.decode(Int64.self, forKey: .dateEpochMillis)
        durationSeconds = try c.decodeIfPresent(Int64.self, forKey: .durationSeconds) ?? 0
    }
}

struct InstalledAppRecord: Codable, Identifiable, Equatable, Sendable {
    var id: String { packageName }
    let packageName: String
    let appName: String
    var appStoreId: Int? = nil
    var iconUrl: String? = nil
    var urlScheme: String? = nil
    var detectionSource: String? = nil
}

struct ManifestItem: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let category: TransferCategory
    let fileName: String
    var relativeAlbumOrFolder: String = ""
    let sizeBytes: Int64
    var capturedEpochMillis: Int64 = 0
    let dedupKey: String
    var mimeType: String = "application/octet-stream"
    var isFavorite: Bool? = nil
    var latitude: Double? = nil
    var longitude: Double? = nil
    var isLivePhoto: Bool? = nil
    var livePhotoVideoFileName: String? = nil
    var livePhotoVideoSizeBytes: Int64? = nil

    enum CodingKeys: String, CodingKey {
        case id, category, fileName, relativeAlbumOrFolder, sizeBytes, capturedEpochMillis
        case dedupKey, mimeType, isFavorite, latitude, longitude, isLivePhoto, livePhotoVideoFileName
        case livePhotoVideoSizeBytes
    }

    init(
        id: String,
        category: TransferCategory,
        fileName: String,
        relativeAlbumOrFolder: String = "",
        sizeBytes: Int64,
        capturedEpochMillis: Int64 = 0,
        dedupKey: String,
        mimeType: String = "application/octet-stream",
        isFavorite: Bool? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        isLivePhoto: Bool? = nil,
        livePhotoVideoFileName: String? = nil,
        livePhotoVideoSizeBytes: Int64? = nil
    ) {
        self.id = id
        self.category = category
        self.fileName = fileName
        self.relativeAlbumOrFolder = relativeAlbumOrFolder
        self.sizeBytes = sizeBytes
        self.capturedEpochMillis = capturedEpochMillis
        self.dedupKey = dedupKey
        self.mimeType = mimeType
        self.isFavorite = isFavorite
        self.latitude = latitude
        self.longitude = longitude
        self.isLivePhoto = isLivePhoto
        self.livePhotoVideoFileName = livePhotoVideoFileName
        self.livePhotoVideoSizeBytes = livePhotoVideoSizeBytes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        category = try c.decode(TransferCategory.self, forKey: .category)
        fileName = try c.decode(String.self, forKey: .fileName)
        relativeAlbumOrFolder = try c.decodeIfPresent(String.self, forKey: .relativeAlbumOrFolder) ?? ""
        sizeBytes = try c.decode(Int64.self, forKey: .sizeBytes)
        capturedEpochMillis = try c.decodeIfPresent(Int64.self, forKey: .capturedEpochMillis) ?? 0
        dedupKey = try c.decode(String.self, forKey: .dedupKey)
        mimeType = try c.decodeIfPresent(String.self, forKey: .mimeType) ?? "application/octet-stream"
        isFavorite = try c.decodeIfPresent(Bool.self, forKey: .isFavorite)
        latitude = try c.decodeIfPresent(Double.self, forKey: .latitude)
        longitude = try c.decodeIfPresent(Double.self, forKey: .longitude)
        isLivePhoto = try c.decodeIfPresent(Bool.self, forKey: .isLivePhoto)
        livePhotoVideoFileName = try c.decodeIfPresent(String.self, forKey: .livePhotoVideoFileName)
        livePhotoVideoSizeBytes = try c.decodeIfPresent(Int64.self, forKey: .livePhotoVideoSizeBytes)
    }
}

struct TransferManifest: Codable, Sendable {
    let sessionId: String
    let senderPlatform: DevicePlatform
    let items: [ManifestItem]
    var contactsPayload: [ContactTransferRecord] = []
    var calendarsPayload: [CalendarEventRecord] = []
    var remindersPayload: [ReminderTransferRecord]? = nil
    var smsPayload: [SmsTransferRecord] = []
    var callLogsPayload: [CallLogTransferRecord]? = nil
    var installedAppsPayload: [InstalledAppRecord]? = nil
    var requestNativeWhatsAppMigration: Bool? = nil
    var transferScope: ActiveTransferScope? = nil

    enum CodingKeys: String, CodingKey {
        case sessionId
        case senderPlatform
        case items
        case contactsPayload
        case calendarsPayload
        case remindersPayload
        case smsPayload
        case callLogsPayload
        case installedAppsPayload
        case requestNativeWhatsAppMigration
        case transferScope
    }

    init(
        sessionId: String,
        senderPlatform: DevicePlatform,
        items: [ManifestItem],
        contactsPayload: [ContactTransferRecord] = [],
        calendarsPayload: [CalendarEventRecord] = [],
        remindersPayload: [ReminderTransferRecord]? = nil,
        smsPayload: [SmsTransferRecord] = [],
        callLogsPayload: [CallLogTransferRecord]? = nil,
        installedAppsPayload: [InstalledAppRecord]? = nil,
        requestNativeWhatsAppMigration: Bool? = nil,
        transferScope: ActiveTransferScope? = nil
    ) {
        self.sessionId = sessionId
        self.senderPlatform = senderPlatform
        self.items = items
        self.contactsPayload = contactsPayload
        self.calendarsPayload = calendarsPayload
        self.remindersPayload = remindersPayload
        self.smsPayload = smsPayload
        self.callLogsPayload = callLogsPayload
        self.installedAppsPayload = installedAppsPayload
        self.requestNativeWhatsAppMigration = requestNativeWhatsAppMigration
        self.transferScope = transferScope
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionId = try container.decode(String.self, forKey: .sessionId)
        senderPlatform = try container.decode(DevicePlatform.self, forKey: .senderPlatform)
        items = try container.decodeIfPresent([ManifestItem].self, forKey: .items) ?? []
        contactsPayload = try container.decodeIfPresent([ContactTransferRecord].self, forKey: .contactsPayload) ?? []
        calendarsPayload = try container.decodeIfPresent([CalendarEventRecord].self, forKey: .calendarsPayload) ?? []
        remindersPayload = try container.decodeIfPresent([ReminderTransferRecord].self, forKey: .remindersPayload)
        smsPayload = try container.decodeIfPresent([SmsTransferRecord].self, forKey: .smsPayload) ?? []
        callLogsPayload = try container.decodeIfPresent([CallLogTransferRecord].self, forKey: .callLogsPayload)
        installedAppsPayload = try container.decodeIfPresent([InstalledAppRecord].self, forKey: .installedAppsPayload)
        requestNativeWhatsAppMigration = try container.decodeIfPresent(Bool.self, forKey: .requestNativeWhatsAppMigration)
        transferScope = try container.decodeIfPresent(ActiveTransferScope.self, forKey: .transferScope)
    }
}

struct ManifestResponse: Codable, Sendable {
    let acceptedItemIds: [String]
    let skippedDuplicateCount: Int
    let contactsMergedCount: Int
    let contactsSkippedDuplicates: Int
    let calendarsImportedCount: Int
    var calendarsAlreadyPresentCount: Int? = nil
    var remindersImportedCount: Int? = nil
    var remindersAlreadyPresentCount: Int? = nil
    var smsImportedCount: Int = 0
    var callLogsImportedCount: Int? = nil
    var gatedByCrossOsPreviewCount: Int = 0

    enum CodingKeys: String, CodingKey {
        case acceptedItemIds
        case skippedDuplicateCount
        case contactsMergedCount
        case contactsSkippedDuplicates
        case calendarsImportedCount
        case calendarsAlreadyPresentCount
        case remindersImportedCount
        case remindersAlreadyPresentCount
        case smsImportedCount
        case callLogsImportedCount
        case gatedByCrossOsPreviewCount
    }

    init(
        acceptedItemIds: [String],
        skippedDuplicateCount: Int,
        contactsMergedCount: Int,
        contactsSkippedDuplicates: Int,
        calendarsImportedCount: Int,
        calendarsAlreadyPresentCount: Int? = nil,
        remindersImportedCount: Int? = nil,
        remindersAlreadyPresentCount: Int? = nil,
        smsImportedCount: Int = 0,
        callLogsImportedCount: Int? = nil,
        gatedByCrossOsPreviewCount: Int = 0
    ) {
        self.acceptedItemIds = acceptedItemIds
        self.skippedDuplicateCount = skippedDuplicateCount
        self.contactsMergedCount = contactsMergedCount
        self.contactsSkippedDuplicates = contactsSkippedDuplicates
        self.calendarsImportedCount = calendarsImportedCount
        self.calendarsAlreadyPresentCount = calendarsAlreadyPresentCount
        self.remindersImportedCount = remindersImportedCount
        self.remindersAlreadyPresentCount = remindersAlreadyPresentCount
        self.smsImportedCount = smsImportedCount
        self.callLogsImportedCount = callLogsImportedCount
        self.gatedByCrossOsPreviewCount = gatedByCrossOsPreviewCount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        acceptedItemIds = try c.decodeIfPresent([String].self, forKey: .acceptedItemIds) ?? []
        skippedDuplicateCount = try c.decodeIfPresent(Int.self, forKey: .skippedDuplicateCount) ?? 0
        contactsMergedCount = try c.decodeIfPresent(Int.self, forKey: .contactsMergedCount) ?? 0
        contactsSkippedDuplicates = try c.decodeIfPresent(Int.self, forKey: .contactsSkippedDuplicates) ?? 0
        calendarsImportedCount = try c.decodeIfPresent(Int.self, forKey: .calendarsImportedCount) ?? 0
        calendarsAlreadyPresentCount = try c.decodeIfPresent(Int.self, forKey: .calendarsAlreadyPresentCount)
        remindersImportedCount = try c.decodeIfPresent(Int.self, forKey: .remindersImportedCount)
        remindersAlreadyPresentCount = try c.decodeIfPresent(Int.self, forKey: .remindersAlreadyPresentCount)
        smsImportedCount = try c.decodeIfPresent(Int.self, forKey: .smsImportedCount) ?? 0
        callLogsImportedCount = try c.decodeIfPresent(Int.self, forKey: .callLogsImportedCount)
        gatedByCrossOsPreviewCount = try c.decodeIfPresent(Int.self, forKey: .gatedByCrossOsPreviewCount) ?? 0
    }
}

struct TransferCompletionReport: Codable, Sendable {
    let sessionId: String
    let licenseTier: SessionLicenseTier
    let transferredFilesCount: Int
    let transferredBytes: Int64
    let mergedContactsCount: Int
    let importedCalendarsCount: Int
    var calendarsAlreadyPresentCount: Int? = nil
    var remindersImportedCount: Int? = nil
    var remindersAlreadyPresentCount: Int? = nil
    var livePhotosSavedCount: Int? = nil
    var importedSmsCount: Int = 0
    var callLogsImportedCount: Int? = nil
    let skippedDuplicatesCount: Int
    let elapsedMillis: Int64

    enum CodingKeys: String, CodingKey {
        case sessionId
        case licenseTier
        case transferredFilesCount
        case transferredBytes
        case mergedContactsCount
        case importedCalendarsCount
        case calendarsAlreadyPresentCount
        case remindersImportedCount
        case remindersAlreadyPresentCount
        case livePhotosSavedCount
        case importedSmsCount
        case callLogsImportedCount
        case skippedDuplicatesCount
        case elapsedMillis
    }

    init(
        sessionId: String,
        licenseTier: SessionLicenseTier,
        transferredFilesCount: Int,
        transferredBytes: Int64,
        mergedContactsCount: Int,
        importedCalendarsCount: Int,
        calendarsAlreadyPresentCount: Int? = nil,
        remindersImportedCount: Int? = nil,
        remindersAlreadyPresentCount: Int? = nil,
        livePhotosSavedCount: Int? = nil,
        importedSmsCount: Int = 0,
        callLogsImportedCount: Int? = nil,
        skippedDuplicatesCount: Int,
        elapsedMillis: Int64
    ) {
        self.sessionId = sessionId
        self.licenseTier = licenseTier
        self.transferredFilesCount = transferredFilesCount
        self.transferredBytes = transferredBytes
        self.mergedContactsCount = mergedContactsCount
        self.importedCalendarsCount = importedCalendarsCount
        self.calendarsAlreadyPresentCount = calendarsAlreadyPresentCount
        self.remindersImportedCount = remindersImportedCount
        self.remindersAlreadyPresentCount = remindersAlreadyPresentCount
        self.livePhotosSavedCount = livePhotosSavedCount
        self.importedSmsCount = importedSmsCount
        self.callLogsImportedCount = callLogsImportedCount
        self.skippedDuplicatesCount = skippedDuplicatesCount
        self.elapsedMillis = elapsedMillis
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessionId = try c.decode(String.self, forKey: .sessionId)
        licenseTier = try c.decodeIfPresent(SessionLicenseTier.self, forKey: .licenseTier) ?? .CROSS_OS_PRO_UNLOCKED
        transferredFilesCount = try c.decodeIfPresent(Int.self, forKey: .transferredFilesCount) ?? 0
        transferredBytes = try c.decodeIfPresent(Int64.self, forKey: .transferredBytes) ?? 0
        mergedContactsCount = try c.decodeIfPresent(Int.self, forKey: .mergedContactsCount) ?? 0
        importedCalendarsCount = try c.decodeIfPresent(Int.self, forKey: .importedCalendarsCount) ?? 0
        calendarsAlreadyPresentCount = try c.decodeIfPresent(Int.self, forKey: .calendarsAlreadyPresentCount)
        remindersImportedCount = try c.decodeIfPresent(Int.self, forKey: .remindersImportedCount)
        remindersAlreadyPresentCount = try c.decodeIfPresent(Int.self, forKey: .remindersAlreadyPresentCount)
        livePhotosSavedCount = try c.decodeIfPresent(Int.self, forKey: .livePhotosSavedCount)
        importedSmsCount = try c.decodeIfPresent(Int.self, forKey: .importedSmsCount) ?? 0
        callLogsImportedCount = try c.decodeIfPresent(Int.self, forKey: .callLogsImportedCount)
        skippedDuplicatesCount = try c.decodeIfPresent(Int.self, forKey: .skippedDuplicatesCount) ?? 0
        elapsedMillis = try c.decodeIfPresent(Int64.self, forKey: .elapsedMillis) ?? 0
    }
}

/// Richiesta cifrata inviata dal vecchio iPhone al nuovo iPhone per aprire automaticamente
/// lo Scanner Fotocamera Live delle App e sincronizzare in tempo reale l'elenco completo delle app installate.
struct RemoteAppScannerStartRequest: Codable, Equatable, Sendable {
    let sessionId: String
    let senderName: String
    var seedApps: [InstalledAppRecord] = []
    var replaceExisting: Bool? = nil
}

struct RemoteAppScannerPollRequest: Codable, Equatable, Sendable {
    let sessionId: String
}

struct RemoteAppScannerStatusResponse: Codable, Equatable, Sendable {
    let isScannerOpen: Bool
    let isCompleted: Bool
    var senderName: String = ""
    var discoveredApps: [InstalledAppRecord] = []
}

/// Fasi sincronizzate tra vecchio e nuovo telefono stile "Passa a iOS":
/// Attesa collegamento -> Prosegui sull'altro telefono -> Preparazione -> 0%..100% -> Completato.
enum TransferSessionStage: String, Codable, Equatable, Sendable {
    case waitingPairing
    case pairedWaitingSelection
    case preparing
    case transferring
    case completed
}

struct PairAckRequest: Codable, Equatable, Sendable {
    let sessionId: String
    let senderName: String
    let senderPlatform: DevicePlatform
}

struct TransferPrepareRequest: Codable, Equatable, Sendable {
    let sessionId: String
    let senderName: String
    let senderPlatform: DevicePlatform
    let transferScope: ActiveTransferScope
}

struct TransferPreparationItem: Identifiable, Equatable, Sendable {
    let id: String
    let icon: String
    let title: String
    let unitSingular: String
    let unitPlural: String
    var targetCount: Int = 0
    var isReady: Bool = false

    func formattedCount(_ value: Int) -> String {
        value == 1 ? "1 \(unitSingular)" : "\(value) \(unitPlural)"
    }
}

enum LicensePolicyEvaluator {
    static let crossOsPreviewMediaLimit = 25

    static func allowsFullCategories(_ tier: SessionLicenseTier) -> Bool {
        true
    }

    static func allowsCalendars(_ tier: SessionLicenseTier) -> Bool {
        true
    }

    static func resolveTier(
        senderPlatform: DevicePlatform,
        receiverPlatform: DevicePlatform,
        senderHasPro: Bool,
        receiverHasPro: Bool,
        senderHasCloudSavePro: Bool = false,
        receiverHasCloudSavePro: Bool = false
    ) -> SessionLicenseTier {
        if senderPlatform == receiverPlatform {
            return .INTRA_OS_FREE
        }
        return .CROSS_OS_PRO_UNLOCKED
    }

    static func filterItemsForTier(_ items: [ManifestItem], tier: SessionLicenseTier) -> ([ManifestItem], Int) {
        (items, 0)
    }
}

enum PhoneNormalizer {
    static func normalizeKey(_ rawPhone: String) -> String {
        let digits = rawPhone.filter { $0.isNumber }
        if digits.count >= 9 {
            return String(digits.suffix(10))
        }
        return digits
    }
}

/// Motore Crittografico CSGCM1 100% compatibile byte-per-byte con DirectSwitch-Android (`DirectSwitchProtocol.kt`),
/// incluso lo streaming su disco (`FileHandle`) a blocchi da 4 MiB per video 4K multi-GB senza picchi RAM.
enum DirectSwitchCrypto {
    static let chunkSizeBytes = 4 * 1024 * 1024
    private static let pinStretchRounds = 60_000
    private static let magicCSGCM1 = Data("CSGCM1".utf8)

    static func generateSessionKeyHex() -> String {
        randomTokenHex(byteCount: 32)
    }

    static func randomTokenHex(byteCount: Int = 16) -> String {
        let count = max(1, byteCount)
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// Confronto in tempo costante per token di autenticazione HTTP del Portale Bootstrap.
    static func constantTimeEquals(_ a: String, _ b: String) -> Bool {
        let aBytes = Array(a.utf8)
        let bBytes = Array(b.utf8)
        guard !aBytes.isEmpty, aBytes.count == bBytes.count else { return false }
        var diff: UInt8 = 0
        for idx in 0..<aBytes.count {
            diff |= aBytes[idx] ^ bBytes[idx]
        }
        return diff == 0
    }

    static func generatePairingPin() -> String {
        var raw: UInt32 = 0
        _ = SecRandomCopyBytes(kSecRandomDefault, MemoryLayout<UInt32>.size, &raw)
        return String(format: "%06d", raw % 1_000_000)
    }

    static func sha256Hex(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func deriveSessionSymmetricKey(sessionKeyHex: String) throws -> SymmetricKey {
        guard let ikm = Data(fromHex: sessionKeyHex), ikm.count == 32 else {
            throw NSError(domain: "DirectSwitchCrypto", code: -1, userInfo: [NSLocalizedDescriptionKey: "Chiave QR non a 256 bit"])
        }
        let salt = Data("DirectSwitch-Salt-2026".utf8)
        let info = Data("DirectSwitch-CSGCM1-v1".utf8)
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: ikm),
            salt: salt,
            info: info,
            outputByteCount: 32
        )
    }

    /// Deriva una `SymmetricKey` dal PIN a 6 cifre e dal `sessionId` con 60.000 iterazioni HMAC-SHA256
    /// (identica byte-per-byte a `DirectSwitchCrypto.derivePinAesKey` su Android).
    static func derivePinSymmetricKey(sessionId: String, pin: String) throws -> SymmetricKey {
        let cleanPin = pin.filter { $0.isNumber }
        guard cleanPin.count == 6, !sessionId.isEmpty else {
            throw NSError(domain: "DirectSwitchCrypto", code: -7, userInfo: [NSLocalizedDescriptionKey: "PIN a 6 cifre non valido"])
        }
        let saltData = Data("DirectSwitch-PIN-Salt-2026:\(sessionId)".utf8)
        let derived = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: Data(cleanPin.utf8)),
            salt: saltData,
            info: Data("DirectSwitch-PIN-v1".utf8),
            outputByteCount: 32
        )
        var acc = derived.withUnsafeBytes { Data($0) }
        let macKey = SymmetricKey(data: saltData)
        for _ in 0..<pinStretchRounds {
            let code = HMAC<SHA256>.authenticationCode(for: acc, using: macKey)
            acc = Data(code)
        }
        return SymmetricKey(data: acc)
    }

    static func sealJsonEnvelope(_ json: String, key: SymmetricKey) throws -> Data {
        try encryptDataCSGCM1(Data(json.utf8), key: key)
    }

    static func openJsonEnvelope(_ envelope: Data, key: SymmetricKey) throws -> String {
        let plain = try decryptDataCSGCM1(envelope, key: key)
        guard let str = String(data: plain, encoding: .utf8) else {
            throw NSError(domain: "DirectSwitchCrypto", code: -6, userInfo: [NSLocalizedDescriptionKey: "UTF-8 non valido"])
        }
        return str
    }

    static func encryptDataCSGCM1(_ plain: Data, key: SymmetricKey) throws -> Data {
        var out = Data()
        out.append(magicCSGCM1)
        if plain.isEmpty {
            let sealed = try AES.GCM.seal(Data(), using: key)
            guard let combined = sealed.combined else {
                throw NSError(domain: "DirectSwitchCrypto", code: -2, userInfo: nil)
            }
            var bigEndianLen = UInt32(combined.count).bigEndian
            withUnsafeBytes(of: &bigEndianLen) { out.append(contentsOf: $0) }
            out.append(combined)
            return out
        }
        var offset = 0
        while offset < plain.count {
            let end = min(offset + chunkSizeBytes, plain.count)
            let chunk = plain.subdata(in: offset..<end)
            let sealed = try AES.GCM.seal(chunk, using: key)
            guard let combined = sealed.combined else {
                throw NSError(domain: "DirectSwitchCrypto", code: -2, userInfo: nil)
            }
            var bigEndianLen = UInt32(combined.count).bigEndian
            withUnsafeBytes(of: &bigEndianLen) { out.append(contentsOf: $0) }
            out.append(combined)
            offset = end
        }
        return out
    }

    static func decryptDataCSGCM1(_ encrypted: Data, key: SymmetricKey) throws -> Data {
        guard encrypted.count >= magicCSGCM1.count,
              encrypted.prefix(magicCSGCM1.count) == magicCSGCM1 else {
            throw NSError(domain: "DirectSwitchCrypto", code: -3, userInfo: [NSLocalizedDescriptionKey: "Header CSGCM1 mancante"])
        }
        var out = Data()
        var cursor = magicCSGCM1.count
        var blockCount = 0
        while cursor < encrypted.count {
            guard cursor + 4 <= encrypted.count else {
                throw NSError(domain: "DirectSwitchCrypto", code: -4, userInfo: [NSLocalizedDescriptionKey: "Lunghezza blocco troncata"])
            }
            let lenData = encrypted.subdata(in: cursor..<(cursor + 4))
            var rawLen: UInt32 = 0
            _ = withUnsafeMutableBytes(of: &rawLen) { lenData.copyBytes(to: $0) }
            let packetLen = Int(UInt32(bigEndian: rawLen))
            cursor += 4
            guard packetLen >= 28, packetLen <= (chunkSizeBytes + 1024), cursor + packetLen <= encrypted.count else {
                throw NSError(domain: "DirectSwitchCrypto", code: -5, userInfo: [NSLocalizedDescriptionKey: "Pacchetto CSGCM1 incompleto"])
            }
            let packet = encrypted.subdata(in: cursor..<(cursor + packetLen))
            cursor += packetLen
            let box = try AES.GCM.SealedBox(combined: packet)
            let plainChunk = try AES.GCM.open(box, using: key)
            if !plainChunk.isEmpty {
                out.append(plainChunk)
            }
            blockCount += 1
        }
        guard blockCount >= 1 else {
            throw NSError(domain: "DirectSwitchCrypto", code: -8, userInfo: [NSLocalizedDescriptionKey: "Stream CSGCM1 privo di blocchi autenticati"])
        }
        return out
    }

    /// Cifra un file su disco in streaming a blocchi da 4 MiB (zero OOM sui video 4K).
    static func encryptFileCSGCM1(inputURL: URL, outputURL: URL, key: SymmetricKey) throws -> (plainBytes: Int64, sha256Hex: String) {
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        let inHandle = try FileHandle(forReadingFrom: inputURL)
        defer { try? inHandle.close() }
        let outHandle = try FileHandle(forWritingTo: outputURL)
        defer { try? outHandle.close() }

        try outHandle.write(contentsOf: magicCSGCM1)
        var hasher = SHA256()
        var totalPlain: Int64 = 0
        var wroteBlock = false

        while true {
            var shouldBreak = false
            var loopError: Error?
            autoreleasepool {
                do {
                    guard let chunk = try inHandle.read(upToCount: chunkSizeBytes), !chunk.isEmpty else {
                        shouldBreak = true
                        return
                    }
                    totalPlain += Int64(chunk.count)
                    hasher.update(data: chunk)
                    let sealed = try AES.GCM.seal(chunk, using: key)
                    guard let combined = sealed.combined else {
                        throw NSError(domain: "DirectSwitchCrypto", code: -2, userInfo: nil)
                    }
                    var lenHeader = Data(capacity: 4)
                    var bigEndianLen = UInt32(combined.count).bigEndian
                    withUnsafeBytes(of: &bigEndianLen) { lenHeader.append(contentsOf: $0) }
                    try outHandle.write(contentsOf: lenHeader)
                    try outHandle.write(contentsOf: combined)
                    wroteBlock = true
                } catch {
                    loopError = error
                    shouldBreak = true
                }
            }
            if let err = loopError { throw err }
            if shouldBreak { break }
        }

        if !wroteBlock {
            let sealed = try AES.GCM.seal(Data(), using: key)
            guard let combined = sealed.combined else {
                throw NSError(domain: "DirectSwitchCrypto", code: -2, userInfo: nil)
            }
            var lenHeader = Data(capacity: 4)
            var bigEndianLen = UInt32(combined.count).bigEndian
            withUnsafeBytes(of: &bigEndianLen) { lenHeader.append(contentsOf: $0) }
            try outHandle.write(contentsOf: lenHeader)
            try outHandle.write(contentsOf: combined)
        }

        let digestHex = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return (totalPlain, digestHex)
    }

    /// Decifra un file `CSGCM1` su disco in streaming a blocchi da 4 MiB verificando GCM e SHA-256.
    static func decryptFileCSGCM1(inputURL: URL, outputURL: URL, key: SymmetricKey) throws -> (plainBytes: Int64, sha256Hex: String) {
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        let inHandle = try FileHandle(forReadingFrom: inputURL)
        defer { try? inHandle.close() }
        let outHandle = try FileHandle(forWritingTo: outputURL)
        defer { try? outHandle.close() }

        guard let magic = try inHandle.read(upToCount: magicCSGCM1.count), magic == magicCSGCM1 else {
            throw NSError(domain: "DirectSwitchCrypto", code: -3, userInfo: [NSLocalizedDescriptionKey: "Header CSGCM1 mancante"])
        }

        var hasher = SHA256()
        var totalPlain: Int64 = 0
        var blockCount = 0

        while true {
            var shouldBreak = false
            var loopError: Error?
            autoreleasepool {
                do {
                    guard let lenData = try inHandle.read(upToCount: 4), !lenData.isEmpty else {
                        shouldBreak = true
                        return
                    }
                    guard lenData.count == 4 else {
                        throw NSError(domain: "DirectSwitchCrypto", code: -4, userInfo: [NSLocalizedDescriptionKey: "Lunghezza blocco troncata"])
                    }
                    var rawLen: UInt32 = 0
                    _ = withUnsafeMutableBytes(of: &rawLen) { lenData.copyBytes(to: $0) }
                    let packetLen = Int(UInt32(bigEndian: rawLen))
                    guard packetLen >= 28, packetLen <= (chunkSizeBytes + 1024),
                          let packet = try inHandle.read(upToCount: packetLen),
                          packet.count == packetLen else {
                        throw NSError(domain: "DirectSwitchCrypto", code: -5, userInfo: [NSLocalizedDescriptionKey: "Pacchetto CSGCM1 incompleto"])
                    }
                    let box = try AES.GCM.SealedBox(combined: packet)
                    let plainChunk = try AES.GCM.open(box, using: key)
                    hasher.update(data: plainChunk)
                    if !plainChunk.isEmpty {
                        try outHandle.write(contentsOf: plainChunk)
                        totalPlain += Int64(plainChunk.count)
                    }
                    blockCount += 1
                } catch {
                    loopError = error
                    shouldBreak = true
                }
            }
            if let err = loopError { throw err }
            if shouldBreak { break }
        }

        guard blockCount >= 1 else {
            throw NSError(domain: "DirectSwitchCrypto", code: -8, userInfo: [NSLocalizedDescriptionKey: "Stream CSGCM1 privo di blocchi autenticati"])
        }

        let digestHex = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return (totalPlain, digestHex)
    }
}

extension Data {
    init?(fromHex hex: String) {
        let clean = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count % 2 == 0 else { return nil }
        var data = Data(capacity: clean.count / 2)
        var index = clean.startIndex
        while index < clean.endIndex {
            let next = clean.index(index, offsetBy: 2)
            guard let b = UInt8(clean[index..<next], radix: 16) else { return nil }
            data.append(b)
            index = next
        }
        self = data
    }
}

/// Accetta solo destinazioni IPv4 private/locali (10/8, 172.16/12, 192.168/16, link-local 169.254/16).
enum DirectSwitchLocalNetwork {
    static func isLocalIPv4(_ ip: String) -> Bool {
        let parts = ip.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        var octets: [Int] = []
        for part in parts {
            guard let value = Int(part), (0...255).contains(value) else { return false }
            octets.append(value)
        }
        return octets[0] == 10
            || (octets[0] == 172 && (16...31).contains(octets[1]))
            || (octets[0] == 192 && octets[1] == 168)
            || (octets[0] == 169 && octets[1] == 254)
    }
}

/// Riconcilia byte stimati, clip Live Photo (.MOV) e file saltati per evitare percentuali bloccate al 50%.
struct TransferProgressAccounting: Sendable {
    let initialTotalItems: Int
    private(set) var succeededItemsCount: Int
    private(set) var failedItemsCount: Int
    private(set) var transferredBytes: Int64
    private(set) var remainingEstimatedPrimaryBytes: Int64
    private(set) var remainingEstimatedLiveBytes: Int64

    init(
        previouslyCompletedItems: Int = 0,
        queuedItemsCount: Int,
        previouslySentBytes: Int64 = 0,
        remainingEstimatedPrimaryBytes: Int64,
        remainingEstimatedLiveBytes: Int64 = 0
    ) {
        self.initialTotalItems = max(0, previouslyCompletedItems + queuedItemsCount)
        self.succeededItemsCount = max(0, previouslyCompletedItems)
        self.failedItemsCount = 0
        self.transferredBytes = max(0, previouslySentBytes)
        self.remainingEstimatedPrimaryBytes = max(0, remainingEstimatedPrimaryBytes)
        self.remainingEstimatedLiveBytes = max(0, remainingEstimatedLiveBytes)
    }

    var processedItemsCount: Int {
        succeededItemsCount + failedItemsCount
    }

    var totalBytesForProgress: Int64 {
        max(transferredBytes, transferredBytes + remainingEstimatedPrimaryBytes + remainingEstimatedLiveBytes)
    }

    var progressFraction: Double {
        let total = totalBytesForProgress
        if total > 0 && transferredBytes > 0 {
            return min(1.0, max(0.01, Double(transferredBytes) / Double(total)))
        }
        if initialTotalItems > 0 {
            let processed = processedItemsCount
            guard processed > 0 else { return 0.0 }
            return min(1.0, max(0.01, Double(processed) / Double(initialTotalItems)))
        }
        return 0.0
    }

    mutating func recordLiveVideoUploaded(estimatedLiveBytes: Int64, actualBytes: Int64) {
        transferredBytes += max(0, actualBytes)
        remainingEstimatedLiveBytes = max(0, remainingEstimatedLiveBytes - max(0, estimatedLiveBytes))
    }

    mutating func recordLiveVideoSkipped(estimatedLiveBytes: Int64) {
        remainingEstimatedLiveBytes = max(0, remainingEstimatedLiveBytes - max(0, estimatedLiveBytes))
    }

    mutating func recordPrimaryItemUploaded(estimatedPrimaryBytes: Int64, actualBytes: Int64) {
        succeededItemsCount += 1
        transferredBytes += max(0, actualBytes)
        remainingEstimatedPrimaryBytes = max(0, remainingEstimatedPrimaryBytes - max(0, estimatedPrimaryBytes))
    }

    mutating func recordItemFailedOrSkipped(estimatedPrimaryBytes: Int64, estimatedLiveBytes: Int64 = 0) {
        failedItemsCount += 1
        remainingEstimatedPrimaryBytes = max(0, remainingEstimatedPrimaryBytes - max(0, estimatedPrimaryBytes))
        remainingEstimatedLiveBytes = max(0, remainingEstimatedLiveBytes - max(0, estimatedLiveBytes))
    }
}

/// Misuratore di velocità su finestra scorrevole (4.5s) insensibile a stalli iniziali o file saltati.
struct SlidingTransferSpeedMeter: Sendable {
    private let windowSeconds: TimeInterval
    private let startTimestamp: TimeInterval
    private var samples: [(timestamp: TimeInterval, bytes: Int64)] = []
    private var totalBytesRecorded: Int64 = 0

    init(startTimestamp: TimeInterval = Date().timeIntervalSinceReferenceDate, windowSeconds: TimeInterval = 4.5) {
        self.startTimestamp = startTimestamp
        self.windowSeconds = max(1.0, windowSeconds)
    }

    mutating func record(bytes: Int64, at timestamp: TimeInterval = Date().timeIntervalSinceReferenceDate) -> Double {
        let clampedBytes = max(0, bytes)
        if clampedBytes > 0 {
            totalBytesRecorded += clampedBytes
            samples.append((timestamp: timestamp, bytes: clampedBytes))
        }
        return currentMegabytesPerSec(at: timestamp)
    }

    mutating func currentMegabytesPerSec(at timestamp: TimeInterval = Date().timeIntervalSinceReferenceDate) -> Double {
        let cutoff = timestamp - windowSeconds
        while let first = samples.first, first.timestamp < cutoff {
            samples.removeFirst()
        }
        guard totalBytesRecorded > 0 else { return 0.0 }
        let windowBytes = samples.reduce(Int64(0)) { $0 + $1.bytes }
        if windowBytes > 0, let oldest = samples.first {
            let span = max(0.35, min(windowSeconds, timestamp - oldest.timestamp + 0.15))
            return (Double(windowBytes) / (1024.0 * 1024.0)) / span
        }
        let elapsed = max(0.25, timestamp - startTimestamp)
        return (Double(totalBytesRecorded) / (1024.0 * 1024.0)) / elapsed
    }
}

/// Formattazione deterministica identica tra iOS e Android (base decimale 1000 MB/GB e percentuale intera coerente).
enum TransferDisplayFormatting {
    static func formatBytes(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "0 MB" }
        if bytes >= 1_000_000_000 {
            let gb = Double(bytes) / 1_000_000_000.0
            return String(format: "%.2f GB", locale: Locale(identifier: "it_IT"), gb)
        }
        if bytes < 100_000 {
            return "0,1 MB"
        }
        let mb = Double(bytes) / 1_000_000.0
        return String(format: "%.1f MB", locale: Locale(identifier: "it_IT"), mb)
    }

    static func percentageInt(fraction: Double, isCompleted: Bool) -> Int {
        if isCompleted { return 100 }
        let clamped = min(1.0, max(0.0, fraction))
        return min(99, max(0, Int((clamped * 100.0 + 1e-9).rounded(.down))))
    }
}

/// Calcolatore stabile del tempo rimanente aggiornato a scatti del 10% in base alla durata reale del 10% precedente.
struct TenPercentSteppedEtaTracker: Sendable {
    private var lastDecile: Int
    private var lastFraction: Double
    private var lastTimestamp: TimeInterval
    private(set) var cachedRemainingSeconds: Int?

    init(initialFraction: Double = 0.0, startTimestamp: TimeInterval = Date().timeIntervalSinceReferenceDate) {
        let clamped = min(0.99, max(0.0, initialFraction))
        self.lastDecile = min(9, max(0, Int((clamped * 10.0 + 1e-9).rounded(.down))))
        self.lastFraction = clamped
        self.lastTimestamp = startTimestamp
        self.cachedRemainingSeconds = nil
    }

    mutating func reset(initialFraction: Double = 0.0, at timestamp: TimeInterval = Date().timeIntervalSinceReferenceDate) {
        let clamped = min(0.99, max(0.0, initialFraction))
        self.lastDecile = min(9, max(0, Int((clamped * 10.0 + 1e-9).rounded(.down))))
        self.lastFraction = clamped
        self.lastTimestamp = timestamp
        self.cachedRemainingSeconds = nil
    }

    mutating func update(
        progressFraction: Double,
        isCompleted: Bool,
        hasTransferableItems: Bool = true,
        at timestamp: TimeInterval = Date().timeIntervalSinceReferenceDate
    ) -> String? {
        guard !isCompleted, hasTransferableItems else { return nil }
        let clamped = min(0.999, max(0.0, progressFraction))
        let currentDecile = min(9, max(0, Int((clamped * 10.0 + 1e-9).rounded(.down))))

        if currentDecile > lastDecile {
            let deltaFraction = max(0.01, clamped - lastFraction)
            let elapsed = max(0.2, timestamp - lastTimestamp)
            let secondsPerUnit = elapsed / deltaFraction
            let remainingFraction = max(0.0, 1.0 - clamped)
            cachedRemainingSeconds = max(1, Int((secondsPerUnit * remainingFraction).rounded()))
            lastDecile = currentDecile
            lastFraction = clamped
            lastTimestamp = timestamp
        }

        return currentLabel(isCompleted: isCompleted, hasTransferableItems: hasTransferableItems)
    }

    func currentLabel(isCompleted: Bool = false, hasTransferableItems: Bool = true) -> String? {
        guard !isCompleted, hasTransferableItems else { return nil }
        guard let sec = cachedRemainingSeconds else {
            return "Calcolo tempo rimanente…"
        }
        if sec < 60 {
            return "Meno di un minuto rimanente"
        }
        let mins = max(1, Int((Double(sec) / 60.0).rounded()))
        return "Circa \(mins) min rimanenti"
    }
}

/// Riallinea estensione e MIME quando un elemento iCloud esportato via cache locale cambia contenitore (es. HEIC -> JPG o MOV -> MP4).
enum MediaFallbackNaming {
    static func reconcileFileNameAndMime(
        fileName: String,
        originalMime: String,
        actualExtension: String?
    ) -> (fileName: String, mimeType: String, effectiveExt: String) {
        let cleanExt = (actualExtension ?? "")
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
            .lowercased()
        let origExt = URL(fileURLWithPath: fileName).pathExtension.lowercased()
        guard !cleanExt.isEmpty, cleanExt != origExt else {
            return (fileName, originalMime, origExt)
        }
        let compatPairs: [(String, String)] = [
            ("heic", "jpg"), ("heic", "jpeg"), ("heif", "jpg"), ("heif", "jpeg"),
            ("dng", "jpg"), ("png", "jpg"), ("mov", "mp4"), ("mp4", "mov")
        ]
        let isImageEquiv = ["jpg", "jpeg"].contains(origExt) && ["jpg", "jpeg"].contains(cleanExt)
        guard !isImageEquiv else {
            return (fileName, originalMime, origExt)
        }
        guard compatPairs.contains(where: { $0.0 == origExt && $0.1 == cleanExt }) || origExt.isEmpty else {
            return (fileName, originalMime, origExt)
        }
        let stem = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
        let baseStem = stem.isEmpty ? "media" : stem
        let updatedName = "\(baseStem).\(cleanExt)"
        let updatedMime: String = {
            switch cleanExt {
            case "jpg", "jpeg": return "image/jpeg"
            case "png": return "image/png"
            case "mp4": return "video/mp4"
            case "mov": return "video/quicktime"
            default: return originalMime
            }
        }()
        return (updatedName, updatedMime, cleanExt)
    }
}

/// Converte in modo bidirezionale le regole di ricorrenza tra Apple EventKit e RFC 5545 RRULE (Android CalendarProvider).
enum CalendarRecurrenceMapper {
    static func toRRule(frequency: String?, interval: Int?) -> String? {
        guard let rawFreq = frequency?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
              ["DAILY", "WEEKLY", "MONTHLY", "YEARLY"].contains(rawFreq) else {
            return nil
        }
        let safeInterval = max(1, interval ?? 1)
        return "FREQ=\(rawFreq);INTERVAL=\(safeInterval)"
    }

    static func parseRRule(_ rrule: String?) -> (frequency: String, interval: Int)? {
        guard let raw = rrule?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        var freq: String? = nil
        var interval = 1
        for part in raw.split(separator: ";") {
            let kv = part.split(separator: "=", maxSplits: 1)
            guard kv.count == 2 else { continue }
            let key = kv[0].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let val = kv[1].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if key == "FREQ", ["DAILY", "WEEKLY", "MONTHLY", "YEARLY"].contains(val) {
                freq = val.lowercased()
            } else if key == "INTERVAL", let parsed = Int(val) {
                interval = max(1, parsed)
            }
        }
        guard let freq else { return nil }
        return (freq, interval)
    }
}
