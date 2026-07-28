// The Swift Programming Language
// https://docs.swift.org/swift-book


@attached(member, names: arbitrary)
public macro ReactiveProjection<S: ReactiveProjectionSource>(source: S.Type) =
    #externalMacro(
        module: "ReactiveProjectionMacros",
        type: "ReactiveProjectionMacro"
    )

@attached(peer, names: arbitrary)
public macro Projected(
    _ keyPath: AnyKeyPath,
      transform: Any = ()
) =
    #externalMacro(
        module: "ReactiveProjectionMacros",
        type: "ProjectedMacro"
    )
