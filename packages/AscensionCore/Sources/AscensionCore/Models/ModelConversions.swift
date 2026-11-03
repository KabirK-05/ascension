import Foundation
import SwiftData

extension Program {
    /// Builds the stored form of a program document, slots and sessions included.
    public convenience init(document: ProgramDocument, isActive: Bool = false) {
        self.init(name: document.name,
                  version: document.version,
                  updatedAt: document.updatedAt,
                  updatedBy: document.updatedBy,
                  progressionRule: document.progression.rule,
                  incrementKg: document.progression.incrementKg,
                  finisherKind: document.finisher.kind,
                  finisherMinutes: document.finisher.minutes,
                  finisherInclinePct: document.finisher.inclinePct,
                  finisherDaysPerWeek: document.finisher.daysPerWeek,
                  deloadActive: document.deload.active,
                  deloadLoadFactor: document.deload.loadFactor,
                  deloadVolumeFactor: document.deload.volumeFactor,
                  isActive: isActive)
        self.days = document.days
            .sorted { $0.weekday < $1.weekday }
            .map { ProgramDay(weekday: $0.weekday, kind: $0.kind) }
        self.sessions = document.sessions
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { kind, template in
                let session = SessionTemplate(kind: kind, name: template.name)
                session.exercises = template.exercises
                    .sorted { $0.order < $1.order }
                    .map {
                        SessionExercise(order: $0.order, exerciseId: $0.exerciseId,
                                        sets: $0.sets, repsLow: $0.repsLow,
                                        repsHigh: $0.repsHigh, finisher: $0.finisher)
                    }
                return session
            }
    }

    /// The document form, which is what syncs and what Muse writes.
    public var document: ProgramDocument? {
        guard let updatedAt = Timestamp(rawValue: updatedAt) else { return nil }
        let entries = sessions.map { session in
            (session.kind, SessionTemplateEntry(
                name: session.name,
                exercises: session.exercises
                    .sorted { $0.order < $1.order }
                    .map {
                        SessionExerciseEntry(order: $0.order, exerciseId: $0.exerciseId,
                                             sets: $0.sets, repsLow: $0.repsLow,
                                             repsHigh: $0.repsHigh, finisher: $0.finisher)
                    }))
        }
        return ProgramDocument(
            version: version,
            updatedAt: updatedAt,
            updatedBy: updatedBy,
            name: name,
            days: days
                .sorted { $0.weekday < $1.weekday }
                .map { ProgramDayEntry(weekday: $0.weekday, kind: $0.kind) },
            sessions: Dictionary(entries, uniquingKeysWith: { first, _ in first }),
            progression: ProgressionSettings(rule: progressionRule,
                                             incrementKg: incrementKg),
            finisher: FinisherSettings(kind: finisherKind, minutes: finisherMinutes,
                                       inclinePct: finisherInclinePct,
                                       daysPerWeek: finisherDaysPerWeek),
            deload: DeloadSettings(active: deloadActive, loadFactor: deloadLoadFactor,
                                   volumeFactor: deloadVolumeFactor))
    }
}

extension FoodItem {
    public convenience init(dto: FoodItemDTO) {
        self.init(id: dto.id, name: dto.name, brand: dto.brand,
                  kcalPer100g: dto.kcalPer100g, proteinPer100g: dto.proteinPer100g,
                  fatPer100g: dto.fatPer100g, carbsPer100g: dto.carbsPer100g,
                  source: dto.source, barcode: dto.barcode,
                  servingGrams: dto.servingGrams, servingName: dto.servingName)
    }

    public var dto: FoodItemDTO {
        FoodItemDTO(id: id, name: name, brand: brand, kcalPer100g: kcalPer100g,
                    proteinPer100g: proteinPer100g, fatPer100g: fatPer100g,
                    carbsPer100g: carbsPer100g, source: source, barcode: barcode,
                    servingGrams: servingGrams, servingName: servingName)
    }
}

extension Exercise {
    public convenience init(dto: ExerciseDTO) {
        self.init(id: dto.id, name: dto.name, primaryMuscles: dto.primaryMuscles,
                  secondaryMuscles: dto.secondaryMuscles, equipment: dto.equipment,
                  instructions: dto.instructions, imageRefs: dto.imageRefs,
                  cues: dto.cues, commonMistakes: dto.commonMistakes)
    }

    public var dto: ExerciseDTO {
        ExerciseDTO(id: id, name: name, primaryMuscles: primaryMuscles,
                    secondaryMuscles: secondaryMuscles, equipment: equipment,
                    instructions: instructions, imageRefs: imageRefs,
                    cues: cues, commonMistakes: commonMistakes)
    }
}
