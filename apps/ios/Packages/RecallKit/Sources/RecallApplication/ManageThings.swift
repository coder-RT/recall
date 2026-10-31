import Foundation
import RecallDomain

/// The things a home remembers, in list order (unsure first).
public struct LoadThings: Sendable {
    private let memory: any HomeMemory
    public init(memory: any HomeMemory) { self.memory = memory }

    public func callAsFunction(home: String) async throws -> [Thing] {
        try await memory.things(home: home).sorted(by: Thing.listOrder)
    }
}

/// Saves the user's corrections (which also confirms the thing).
public struct CorrectThing: Sendable {
    private let memory: any HomeMemory
    public init(memory: any HomeMemory) { self.memory = memory }

    public func callAsFunction(_ thing: Thing, home: String, _ correction: Correction) async throws {
        try await memory.correct(home: home, thing: thing.id, correction)
    }
}

/// "Not there, forget it": removes the thing from memory.
public struct ForgetThing: Sendable {
    private let memory: any HomeMemory
    public init(memory: any HomeMemory) { self.memory = memory }

    public func callAsFunction(_ thing: Thing, home: String) async throws {
        try await memory.forget(home: home, thing: thing.id)
    }
}
