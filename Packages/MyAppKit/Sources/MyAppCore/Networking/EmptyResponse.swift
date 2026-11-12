/// The response type of an ``Endpoint`` whose 2xx answer carries nothing the caller
/// reads — a `204 No Content`, or the bodiless `200` many `DELETE` and `PUT` endpoints
/// return (`Endpoint<EmptyResponse>(method: .delete, path: "items/42")`).
///
/// It exists because no other type decodes from zero bytes: without it, a call that
/// succeeded with no body would end in ``APIError/decoding``, and a feature would be
/// tempted to catch `.decoding` as success — swallowing a real schema mismatch with it.
/// ``APIClient`` returns it for an empty 2xx body without decoding anything, so
/// ``APIError/decoding`` keeps meaning "a body arrived and did not decode as the declared
/// type".
///
/// It also decodes from any JSON value, ignoring its content, so a server that later
/// starts answering the same call with a body does not break it. A body that is not JSON
/// at all still throws ``APIError/decoding``.
public struct EmptyResponse: Decodable, Equatable, Sendable {
    /// The one value there is: the call succeeded, and that is all it says.
    public init() {
        // No stored properties: every empty response is the same value.
    }

    /// Reads nothing, so every JSON value — an object, an array, a string, `null` —
    /// decodes as the empty response.
    public init(from _: any Decoder) {
        // Not even a container is requested: asking for a keyed one would refuse an
        // array or `null`, and the point is to accept any body.
    }
}
