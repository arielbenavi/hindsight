import Foundation

/// A made-up Muse reply in the format `MusePrompt` asks for, so the whole
/// sync flow can be exercised in the simulator (no Muse app there).
/// Includes one post already in the seed to show deduplication.
enum MuseSampleReply {
    static let text = """
    ```json
    [
      {"platform": "instagram", "author": "sample.studio", "kind": "reel", "date": "2026-09-29",
       "caption": "Sample: 3 sidechain tricks every producer should know", "url": "https://www.instagram.com/reel/SAMPLE00001/"},
      {"platform": "facebook", "author": "sample.kitchen", "kind": "video", "date": "2026-09-28",
       "caption": "Sample: 15-minute weeknight pasta", "url": "https://www.facebook.com/reel/900000000000001/"},
      {"platform": "instagram", "author": "sample.quant", "kind": "carousel", "date": "2026-09-28",
       "caption": "Sample: volatility regimes explained in 6 slides", "url": "https://www.instagram.com/p/SAMPLE00002/"},
      {"platform": "facebook", "author": "sample.travel", "kind": "post", "date": "2026-09-27",
       "caption": "Sample: Lisbon on a budget", "url": "https://www.facebook.com/sample.travel/posts/900000000000002"},
      {"platform": "instagram", "author": "evolving.ai", "kind": "post", "date": "2026-09-26",
       "caption": "Already in the seed, should be deduped", "url": "https://www.instagram.com/p/DdwJgsNABze/"}
    ]
    ```
    """
}
