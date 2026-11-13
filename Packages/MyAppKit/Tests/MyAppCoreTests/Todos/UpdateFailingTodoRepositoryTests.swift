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
        func `a delayed failure waits its delay before it throws`() async throws {
            let stored = try Self.item("Buy milk")
            let inner = InMemoryTodoRepository(items: [stored])
            let clock = ManualClock()
            let repository = UpdateFailingTodoRepository(
                wrapping: inner,
                failureDelay: .seconds(3),
                clock: clock,
            )
            var toggled = stored
            toggled.isDone = true
            let save = Task {
                try await repository.save(toggled)
            }

            #expect(await clock.nextSleep() == .seconds(3))
            clock.advance(by: .seconds(3))

            await #expect(throws: TodoRepositoryError.storageFailure) {
                try await save.value
            }
            #expect(clock.sleeps == [.seconds(3)])
            #expect(await inner.snapshot == [stored])
        }

        @Test(.timeLimit(.minutes(1)))
        func `a delayed failure throws at once when its task is cancelled`() async throws {
            let stored = try Self.item("Buy milk")
            let inner = InMemoryTodoRepository(items: [stored])
            let clock = ManualClock()
            let repository = UpdateFailingTodoRepository(
                wrapping: inner,
                failureDelay: .seconds(3),
                clock: clock,
            )
            var toggled = stored
            toggled.isDone = true
            let save = Task {
                try await repository.save(toggled)
            }

            _ = await clock.nextSleep()
            save.cancel()

            await #expect(throws: TodoRepositoryError.storageFailure) {
                try await save.value
            }
            #expect(await inner.snapshot == [stored])
        }

        @Test
        func `a delay never holds back a save of a new item`() async throws {
            let inner = InMemoryTodoRepository()
            let clock = ManualClock()
            let repository = UpdateFailingTodoRepository(
                wrapping: inner,
                failureDelay: .seconds(3),
                clock: clock,
            )
            let item = try Self.item("Buy milk")

            try await repository.save(item)

            #expect(clock.sleeps.isEmpty)
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
