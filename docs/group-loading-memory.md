# Group loading: review and memory measurements

Measured on 10 November 2026 with Connect IQ SDK 9.2.0, against upstream `main` at `795a986`.

Lazy loading improves memory while an expensive group is unopened and reduces request memory after it is closed. It does not guarantee that the group will fit when opened. Delayed loading mainly prioritizes the first response; its total memory benefit was small in these tests.

## Method

- Release builds (`-r`), without unit-test mode or profiling, on Instinct 2 and fēnix 9 Pro 47 mm simulators. Reported application memory budgets were 94,112 and 781,976 bytes respectively.
- Synthetic menus with eight ordinary information rows, seven forecast group summaries, and either eight or 34 forecast rows. The eight-row fixture has 23 templates and 2,708 bytes of JSON; the 34-row fixture has 49 templates and 5,959 bytes. The nested forecast has two locations, each with Daily and Hourly groups.
- Real `Communications` JSON decoding over a loopback HTTP server, production menu construction, request generation and response application. No HA configuration, credentials or live data were used. Menu-file caching was disabled and type icons were enabled.
- An instrumented app entry displayed the same blank view in each mode; menu trees were instantiated but not drawn. Timer-separated samples after callbacks returned released their local references. Garbage collection remained automatic.
- `System.getSystemStats()` reports current application memory. The maximum sampled value is **not a true peak**, and excludes unobserved allocation/parser spikes. Four refresh cycles test only short-term behavior, not leak freedom or long-run reliability. See [Garmin's Stats documentation](https://developer.garmin.com/connect-iq/api-docs/Toybox/System/Stats.html).

All feature modes on a given device use the same instrumented binary. The upstream harness omits the unavailable lazy-navigation branch, so an absolute upstream-versus-feature difference also includes unequal instrumentation overhead. The feature itself adds code, group flags and batch caches; there is no memory-saving claim for an unchanged all-eager menu. Physical watch, BLE, cached-menu startup and real HA rendering remain to be tested.

## Settled application memory

Values are bytes. Separate initial and repeated eager values avoid comparing different stages as if they were identical.

| Feature mode / stage | Instinct 2, eight forecast rows | fēnix 9, 34 forecast rows |
| --- | ---: | ---: |
| Eager, first complete refresh | 86,008 | 103,568 |
| Eager, subsequent refreshes | 86,008 | 105,696 |
| Lazy, closed before first visit | 77,488 | 81,536 |
| Lazy, first opened refresh | 86,008 | 103,568 |
| Lazy, closed after visit | 82,888 | 95,000 |
| Delayed, subsequent complete refreshes | 85,720 | 103,608 |

On Instinct 2, initial lazy loading saves **8,520 bytes (9.9%)** versus feature eager loading. After visiting and closing the forecast, the saving is **3,120 bytes (3.6%)**. On fēnix 9, the initial lazy saving is **22,032 bytes (21.3%)**, comparing first refreshes. The following closed refresh retained the same value as the preceding closed refresh in both lazy runs.

For context, upstream eager settled at 83,752 bytes on the small fixture and 103,768 bytes on the large fixture after repeated refreshes. The feature eager values are higher; the branch is not a universal memory optimization without opting into the new flags. Those absolute differences include the instrumentation caveat above.

## Delayed requests and sampled maxima

| Measurement | Instinct 2, eight rows | fēnix 9, 34 rows |
| --- | ---: | ---: |
| Eager first outgoing request, used memory | 85,240 | 101,352 |
| Delayed first ordinary request, used memory | 77,504 | 81,560 |
| Delayed first descendant request, used memory | 86,208 | 102,648 |
| Eager maximum sampled used memory | 88,608 | 110,912 |
| Delayed maximum sampled used memory | 87,272 | 108,104 |

Delayed loading lowers the observed maximum by 1,336 bytes on Instinct 2 in this fixture, but retains both batches and eventually constructs all non-lazy descendants. It is useful for responsiveness and smaller responses, not guaranteed lower resident or peak memory.

The large eager request contains 49 templates: 4,477 bytes of request JSON and 1,892 bytes of response JSON. A closed lazy forecast sends nine templates: 609 bytes requested and 334 bytes returned. Delayed mode sends those nine first, then 40 descendants in a second request. These are synthetic payload sizes, not a measured real-world latency or battery improvement.

## Capacity limits

With the 34-row forecast on Instinct 2, upstream eager loading and feature eager loading exhausted memory during menu construction. Feature lazy loading completed the closed refresh at **83,944 bytes**, but opening the same forecast also exhausted memory. Delayed loading completed its first ordinary request and then exhausted memory constructing descendants. A 14-row upstream fixture reached a response-parser out-of-memory error on a later refresh, illustrating why one successful initial refresh does not establish capacity.

The complete JSON must still fit during download. Deferred groups retain their definitions until construction, and constructed menu trees stay allocated after closing. On constrained watches, mark expensive nested Daily/Hourly groups lazy as well and keep each opened subtree small; that recommendation is not a guarantee that an arbitrary menu will fit.

## Review changes and verification

The review corrected overlapping cache-check/render requests, delayed OOM retries that starved ordinary controls, repeated rebuilding of unchanged batches, unnecessary invalidation on ordinary navigation, and action refreshes lost while another request was running. Retry paths now preserve OOM backoff and resume ordinary items first. Low-memory cache-check disabling and malformed cache responses resume polling.

All **33 simulator regression tests** passed: 11 upstream API tests, nine group tests, and 13 request/scheduling tests. The latter use mock requests/timers and cover caching identity, stale responses, nested eligibility, empty batches, cache-check serialization, delayed errors and queued action refreshes. Tests ran with an isolated app ID and default settings. Their expanded unit-test memory allowance was not used for the capacity measurements above.

Release builds passed for Instinct 2, Venu 2 and fēnix 9 Pro 47 mm. Eighteen schema checks passed, including flag combinations, rejected non-booleans/non-group flags and the documented forecast example. Local build files selected installed targets because upstream also names devices missing from the installed SDK; tracked target/resource definitions were preserved.

The [benchmark harness](../tests/memory-benchmark/README.md), [raw memory samples](group-loading-memory.csv), and [fixture hashes and test settings](group-loading-fixtures.json) are included for reproduction. Generated binaries, staging sources and host logs are excluded from Git. The temporary simulator HTTP setting was restored byte-for-byte and the loopback server was stopped after testing.
