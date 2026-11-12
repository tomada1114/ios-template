/// The response type of an ``Endpoint`` whose 2xx answer carries nothing the caller
/// reads — a `204 No Content`, or the bodiless `200` many `DELETE` and `PUT` endpoints
/// return (`Endpoint<EmptyResponse>(method: .delete, path: "items/42")`).
///
/// It exists because a bodiless call needs a type to declare: without it, a call that
/// succeeded with no body would end in ``APIError/decoding``, and a feature would be
/// tempted to catch `.decoding` as success — swallowing a real schema mismatch with it.
/// ``APIClient`` recognizes this type and returns it on any 2xx without decoding the
/// body, whatever the server sends, so a server that later adds a body does not break
/// the call. ``APIError/decoding`` means the 2xx body — an empty one included — did not
/// decode as the declared type, which an endpoint declaring this type never meets.
///
/// It conforms to `Decodable` only because ``Endpoint``'s `Response` requires it; the
/// client never decodes it.
public struct EmptyResponse: Decodable, Equatable, Sendable {
    /// The one value there is: the call succeeded, and that is all it says.
    public init() {
        // No stored properties: every empty response is the same value.
    }
}
