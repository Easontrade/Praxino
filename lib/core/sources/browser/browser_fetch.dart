/// Fetches an HTTP body through a real browser engine.
///
/// Some sources reject an ordinary HTTP client before any parsing happens:
/// they inspect the TLS fingerprint, require HTTP/2, or answer with a
/// JavaScript challenge page. No amount of parsing fixes that — the request has
/// to come from something that looks like a browser — so adapters take this as
/// an injected fallback and only use it when the cheap path failed.
abstract class BrowserFetch {
  /// Returns the page body as text, or null when the browser could not load it.
  Future<String?> fetch(String url);
}

/// Used where no browser engine is available (tests, other platforms).
class NoBrowserFetch implements BrowserFetch {
  const NoBrowserFetch();

  @override
  Future<String?> fetch(String url) async => null;
}
