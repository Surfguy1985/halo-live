import CoreLocation
import Foundation
import UIKit

struct ProofMetadata: Codable, Hashable {
    let proofID: String
    let jobID: String
    let propertyID: String?
    let unit: String
    let taskID: String?
    let taskTitle: String?
    let phase: String
    let crewLeaderID: String?
    let capturedAt: String
    let latitude: Double?
    let longitude: Double?
    let horizontalAccuracy: Double?
    let source: String
}

struct StoredProof: Hashable {
    let metadata: ProofMetadata
    let imageURL: URL
    let metadataURL: URL
}

enum ProofStorageError: LocalizedError {
    case jpegEncodingFailed

    var errorDescription: String? {
        switch self {
        case .jpegEncodingFailed: "HALO could not encode this proof photo."
        }
    }
}

actor ProofStorage {
    static let shared = ProofStorage()

    func save(
        image: UIImage,
        job: FieldJob,
        task: JobTask?,
        phase: String,
        location: CLLocation?,
        source: String
    ) throws -> StoredProof {
        guard let jpeg = image.jpegData(compressionQuality: 0.9) else {
            throw ProofStorageError.jpegEncodingFailed
        }

        let id = UUID().uuidString
        let iso = ISO8601DateFormatter().string(from: Date())
        let metadata = ProofMetadata(
            proofID: id,
            jobID: job.id,
            propertyID: job.propertyID,
            unit: job.unit,
            taskID: task?.id,
            taskTitle: task?.title,
            phase: phase,
            crewLeaderID: job.crewLeaderID,
            capturedAt: iso,
            latitude: location?.coordinate.latitude,
            longitude: location?.coordinate.longitude,
            horizontalAccuracy: location?.horizontalAccuracy,
            source: source
        )

        let fm = FileManager.default
        let base = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent("HaloProofs", isDirectory: true)
        .appendingPathComponent(job.id, isDirectory: true)

        try fm.createDirectory(at: base, withIntermediateDirectories: true)

        let imageURL = base.appendingPathComponent("\(id).jpg")
        let metadataURL = base.appendingPathComponent("\(id).json")

        try jpeg.write(to: imageURL, options: .atomic)
        let encoded = try JSONEncoder().encode(metadata)
        try encoded.write(to: metadataURL, options: .atomic)

        return StoredProof(metadata: metadata, imageURL: imageURL, metadataURL: metadataURL)
    }
}
