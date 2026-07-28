//
//  ReactiveProjectionSource.swift
//  ReactiveProjectionSource
//
//  Created by Sergey Tristan on 25.07.2026.
//

import Foundation
import Combine

public typealias ProjectedValue<Value> = CurrentValueSubject<Value, Never>

public protocol ReactiveProjectionSource {
    associatedtype ReactiveObject = Self
    func projection<Value>(
        for keyPath: KeyPath<ReactiveObject, Value>
    ) -> AnyPublisher<Value, Never>
}
