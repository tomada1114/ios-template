#if DEBUG
    import Foundation
    import MyAppCore
    import MyAppTestSupport
    import Testing

    @Suite("UpdateFailingTodoRepository")
    struct UpdateFailingTodoRepositoryTests {
        private static let createdAt = Date(timeIntervalSinceReferenceDate: 0)

        private static func item(_ title: String) throws -> TodoItem {
            try TodoItem(id: UUID(), title: title, createdAt: createdAt)
        }

        @Test
        func `a save of a new item is stored`() async throws {
            let inner = InMemoryTodoRepository()
            let repository = UpdateFailingTodoRepository(wrapping: inner)
            let item = try Self.item("Buy milk")

            try await repository.save(item)

            #expect(await inner.snapshot == [item])
        }

        @Test
        func `a save that replaces a stored item fails and leaves it unchanged`() async throws {
            let stored = try Self.item("Buy milk")
            let inner = InMemoryTodoRepository(items: [stored])
            let repository = UpdateFailingTodoRepository(wrapping: inner)
            var toggled = stored
            toggled.isDone = true

            await #expect(throws: TodoRepositoryError.storageFailure) {
                try await repository.save(toggled)
            }
            #expect(await inner.snapshot == [stored])
        }

        @Test(.timeLimit(.minutes(1)))
        func `a held failure waits for a release before it throws`() async throws {
            let stored = try Self.item("Buy milk")
            let inner = InMemoryTodoRepository(items: [stored])
            let gate = FailedUpdateGate()
            let repository = UpdateFailingTodoRepository(wrapping: inner, holdingFailuresAt: gate)
            var toggled = stored
            toggled.isDone = true
            let save = Task {
                try await repository.save(toggled)
            }

            await gate.nextHold()
            await gate.release()

            await #expect(throws: TodoRepositoryError.storageFailure) {
                try await save.value
            }
            #expect(await inner.snapshot == [stored])
        }

        @Test(.timeLimit(.minutes(1)))
        func `a release that comes before the failure lets it through at once`() async throws {
            let stored = try Self.item("Buy milk")
            let inner = InMemoryTodoRepository(items: [stored])
            let gate = FailedUpdateGate()
            let repository = UpdateFailingTodoRepository(wrapping: inner, holdingFailuresAt: gate)
            var toggled = stored
            toggled.isDone = true

            await gate.release()

            await #expect(throws: TodoRepositoryError.storageFailure) {
                try await repository.save(toggled)
            }
            #expect(await inner.snapshot == [stored])
        }

        @Test(.timeLimit(.minutes(1)))
        func `one release lets one failure through`() async throws {
            let stored = try Self.item("Buy milk")
            let inner = InMemoryTodoRepository(items: [stored])
            let gate = FailedUpdateGate()
            let repository = UpdateFailingTodoRepository(wrapping: inner, holdingFailuresAt: gate)
            var toggled = stored
            toggled.isDone = true
            await gate.release()
            await #expect(throws: TodoRepositoryError.storageFailure) {
                try await repository.save(toggled)
            }

            let second = Task { [toggled] in
                try await repository.save(toggled)
            }
            await gate.nextHold()
            await gate.release()

            await #expect(throws: TodoRepositoryError.storageFailure) {
                try await second.value
            }
        }

        @Test(.timeLimit(.minutes(1)))
        func `a held failure throws at once when its task is cancelled`() async throws {
            let stored = try Self.item("Buy milk")
            let inner = InMemoryTodoRepository(items: [stored])
            let gate = FailedUpdateGate()
            let repository = UpdateFailingTodoRepository(wrapping: inner, holdingFailuresAt: gate)
            var toggled = stored
            toggled.isDone = true
            let save = Task {
                try await repository.save(toggled)
            }

            await gate.nextHold()
            save.cancel()

            await #expect(throws: TodoRepositoryError.storageFailure) {
                try await save.value
            }
            #expect(await inner.snapshot == [stored])
        }

        @Test(.timeLimit(.minutes(1)))
        func `a failure whose task is already cancelled is not held`() async throws {
            let stored = try Self.item("Buy milk")
            let inner = InMemoryTodoRepository(items: [stored])
            let gate = FailedUpdateGate()
            let repository = UpdateFailingTodoRepository(wrapping: inner, holdingFailuresAt: gate)
            var toggled = stored
            toggled.isDone = true
            let save = Task {
                withUnsafeCurrentTask { $0?.cancel() }
                try await repository.save(toggled)
            }

            await #expect(throws: TodoRepositoryError.storageFailure) {
                try await save.value
            }
        }

        @Test(.timeLimit(.minutes(1)))
        func `a cancelled hold leaves the next release for the next failure`() async throws {
            let stored = try Self.item("Buy milk")
            let inner = InMemoryTodoRepository(items: [stored])
            let gate = FailedUpdateGate()
            let repository = UpdateFailingTodoRepository(wrapping: inner, holdingFailuresAt: gate)
            var toggled = stored
            toggled.isDone = true
            let cancelled = Task { [toggled] in
                try await repository.save(toggled)
            }
            await gate.nextHold()
            cancelled.cancel()
            _ = await cancelled.result

            await gate.release()

            await #expect(throws: TodoRepositoryError.storageFailure) {
                try await repository.save(toggled)
            }
        }

        @Test(.timeLimit(.minutes(1)))
        func `a gate never holds back a save of a new item`() async throws {
            let inner = InMemoryTodoRepository()
            let gate = FailedUpdateGate()
            let repository = UpdateFailingTodoRepository(wrapping: inner, holdingFailuresAt: gate)
            let item = try Self.item("Buy milk")

            try await repository.save(item)

            #expect(await inner.snapshot == [item])
        }

        @Test
        func `a failing read fails the save before anything is stored`() async throws {
            let inner = InMemoryTodoRepository()
            await inner.fail(.fetchAll, with: .storageFailure)
            let repository = UpdateFailingTodoRepository(wrapping: inner)

            await #expect(throws: TodoRepositoryError.storageFailure) {
                try await repository.save(Self.item("Buy milk"))
            }
            #expect(await inner.snapshot.isEmpty)
        }

        @Test
        func `reads and deletes pass through`() async throws {
            let stored = try Self.item("Buy milk")
            let inner = InMemoryTodoRepository(items: [stored])
            let repository = UpdateFailingTodoRepository(wrapping: inner)

            #expect(try await repository.fetchAll() == [stored])
            try await repository.delete(id: stored.id)
            #expect(await inner.snapshot.isEmpty)
            await #expect(throws: TodoRepositoryError.notFound(stored.id)) {
                try await repository.delete(id: stored.id)
            }
        }
    }
#endif
