import ActivityKit
import Foundation

public struct HaloJobActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var state: String
        public var progress: Double
        public var completedTasks: Int
        public var totalTasks: Int
        public var photoCount: Int
        public var nextAction: String

        public init(
            state: String,
            progress: Double,
            completedTasks: Int,
            totalTasks: Int,
            photoCount: Int,
            nextAction: String
        ) {
            self.state = state
            self.progress = progress
            self.completedTasks = completedTasks
            self.totalTasks = totalTasks
            self.photoCount = photoCount
            self.nextAction = nextAction
        }
    }

    public let jobID: String
    public let unit: String
    public let propertyName: String
    public let title: String

    public init(jobID: String, unit: String, propertyName: String, title: String) {
        self.jobID = jobID
        self.unit = unit
        self.propertyName = propertyName
        self.title = title
    }
}
