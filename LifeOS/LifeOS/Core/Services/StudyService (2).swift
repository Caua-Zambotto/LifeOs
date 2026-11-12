import Foundation

/// Revisão espaçada: ao concluir um assunto, agenda revisões em 1, 7, 15, 30 e 60 dias.
enum StudyReview {
    static let intervals = [1, 7, 15, 30, 60]

    static func setStatus(_ status: TopicStatus, for topic: StudyTopic, now: Date = Date()) {
        topic.status = status
        switch status {
        case .concluido:
            topic.lastStudied = now
            topic.reviewStage = 0
            topic.nextReview = now.startOfDay.adding(days: intervals[0])
        case .revisar:
            topic.nextReview = now.startOfDay
        case .estudando:
            topic.lastStudied = now
        case .naoIniciado:
            topic.nextReview = nil
            topic.reviewStage = 0
        }
        NotificationScheduler.schedule(topic)
    }

    /// Marca uma revisão como feita e agenda a próxima.
    static func markReviewed(_ topic: StudyTopic, now: Date = Date()) {
        topic.lastStudied = now
        topic.status = .concluido
        topic.reviewStage += 1
        if topic.reviewStage < intervals.count {
            topic.nextReview = now.startOfDay.adding(days: intervals[topic.reviewStage])
        } else {
            topic.nextReview = nil
        }
        NotificationScheduler.schedule(topic)
    }

    static func isDue(_ topic: StudyTopic, now: Date = Date()) -> Bool {
        guard let next = topic.nextReview else { return false }
        return next <= now
    }

    /// Todos os assuntos, incluindo subtópicos.
    static func flatten(_ topics: [StudyTopic]) -> [StudyTopic] {
        topics.flatMap { [$0] + flatten($0.children) }
    }

    static func progress(_ topics: [StudyTopic]) -> Double {
        let all = flatten(topics)
        guard !all.isEmpty else { return 0 }
        return Double(all.filter { $0.status == .concluido }.count) / Double(all.count)
    }

    /// Média ponderada (0–10).
    static func weightedAverage(_ grades: [Grade]) -> Double? {
        let totalWeight = grades.reduce(0) { $0 + $1.weight }
        guard totalWeight > 0 else { return nil }
        return grades.reduce(0) { $0 + $1.normalized * $1.weight } / totalWeight
    }
}
