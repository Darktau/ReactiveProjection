# ReactiveProjection

A lightweight reactive projection layer for Swift.

ReactiveProjection provides a way to create consumer-oriented reactive representations of model objects without duplicating observation and transformation logic across multiple UI flows.

## The Problem

A single model object often participates in multiple independent editing flows.

For example, a `Note` entity may be used by:

- a note editor,
- a contact organizer,
- a task creation flow,
- a preview screen.

Each consumer usually needs a slightly different representation of the same underlying model:

- different properties,
- different relationships,
- different levels of detail.

Without an intermediate layer, this logic tends to be duplicated across ViewModels and UI components.

ReactiveProjection introduces a dedicated layer between the model and consumers.

A Projection owns:

- reactive observation,
- transformation logic.

The model remains responsible for persistence.
The consumer remains responsible for deciding what it needs.

## Why not ViewModel?

A ViewModel usually represents the needs of a specific screen or user flow. It often combines:

- UI state,
- user actions,
- navigation decisions,
- validation logic,
- presentation-specific transformations.

Because of this, ViewModels are usually consumer-specific.

ReactiveProjection solves a different problem. A Projection represents a reusable reactive state view of a model object. It does not know:

- which screen consumes it,
- how the UI is presented,
- what actions are performed.

For example, multiple independent flows may consume the same `Note`:

```
                      Note
                       |
          ---------------------------
          |                         |
   NoteProjection           NoteProjection
     (.contacts)           (.tags, .title)
          |                         |
    Contact Flow               Editor Flow
```

Each consumer activates only the part of the projection surface that it requires.

## Core Idea

A Projection declaratively describes the available reactive surface of a model. Consumers decide which parts of that surface are active.

```swift
let projection = NoteProjection(
    item: note,
    features: [.contacts]
)
```

The Projection can describe many possible properties:

```swift
@ReactiveProjection(source: Note.self)
final class NoteProjection {
    @Projected(\Note.title, transform: { $0 ?? "" })
    var title: ProjectedValue<String>

    @Projected(\Note.contacts, transform: { contacts in
        (contacts as? Set<Contact>)?.compactMap {
            OutlineFactory.contact(for: $0)
        } ?? []
    })
    var contacts: Projection<[OutlineItem]>
}
```

The consumer activates only the required features.

## ReactiveProjectionSource

A `ReactiveProjectionSource` defines how a model object provides reactive access to its properties.

```swift
public protocol ReactiveProjectionSource {
    associatedtype ReactiveObject = Self

    func projection<Value>(
        for keyPath: KeyPath<ReactiveObject, Value>
    ) -> AnyPublisher<Value, Never>
}
```

ReactiveProjection does not define persistence rules. Any object capable of exposing reactive property streams can become a projection source.

## ProjectedValue

Projected properties use `ProjectedValue` to represent their current reactive state.

```swift
public typealias Projection<Value> = CurrentValueSubject<Value, Never>
```

A projected value provides:

- the current value,
- updates when the source changes.

## Core Data Example

ReactiveProjection can work with `NSManagedObject` subclasses. Example:

```swift
extension Note: ReactiveProjectionSource {
    public func projection<Value>(
        for keyPath: KeyPath<Note, Value>
    ) -> AnyPublisher<Value, Never> {
        publisher(for: keyPath)
            .eraseToAnyPublisher()
    }
}
```

The Projection does not depend on Core Data details. The Core Data object only provides the reactive source implementation.

## Complete Example

**Model:**

```swift
class Note: NSManagedObject {
    @NSManaged var title: String?
    @NSManaged var contacts: NSSet?
}
```

**Projection:**

```swift
@ReactiveProjection(source: Note.self)
final class NoteProjection {
    @Projected(
        \Note.title,
        transform: { $0 ?? "" }
    )
    var title: Projection<String>

    @Projected(
        \Note.contacts,
        transform: { (contacts: NSSet?) in
            (contacts as? Set<Contact>)?.compactMap {
                OutlineFactory.contact(for: $0)
            } ?? []
        }
    )
    var contacts: Projection<[OutlineItem]>
}
```

**Consumer:**

```swift
let projection = NoteProjection(
    item: note,
    features: [.contacts]
)
```

Only the required reactive properties are activated.

## Design Principles

**Compose sources, not consumers**
Observation and transformation belong in the projection layer instead of being repeated across consumers.

**A Projection represents state, not transactions**
A Projection describes the current reactive state of a model. It does not represent commands or editing operations.

**A Projection owns transformation, not persistence**
A Projection transforms model data into consumer-oriented representations. It does not own storage or persistence rules.

**Multiple consumers can share one Projection**
Different flows can use the same Projection while activating different subsets of available properties.

## Status

ReactiveProjection is experimental. The API may change while the design evolves.
