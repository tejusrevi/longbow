import Foundation
import os

/// Event logging (spec A21). Provider chosen later; Milestone 1 logs locally.
protocol AnalyticsService: AnyObject {
    func log(_ event: String, _ properties: [String: Any])
}

extension AnalyticsService {
    func log(_ event: String) { log(event, [:]) }
}

final class LocalAnalyticsService: AnalyticsService {
    private let logger = Logger(subsystem: "com.tejusrevi.longbow", category: "analytics")
    private let sessionId = UUID().uuidString

    func log(_ event: String, _ properties: [String: Any]) {
        let props = properties.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: " ")
        logger.debug("\(event, privacy: .public) session=\(self.sessionId, privacy: .public) \(props, privacy: .public)")
    }
}
