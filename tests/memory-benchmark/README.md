# Group loading memory benchmark

This optional harness measures release app memory using synthetic forecast menus and real Connect IQ JSON request/response parsing. It never contacts Home Assistant. Generated sources, binaries, settings and logs stay under the ignored `bin/memory-benchmark/` directory. The generator always uses the unpopulated `ClientId` placeholder.

The harness copies production source and instruments the app entry and HTTP transport. It uses the production menu classes, template batching and response handler. A blank front view keeps drawing differences out of the comparison. Measurements include harness overhead; compare eager/lazy/delayed modes within the same feature binary for the cleanest comparison. See [recorded results and limits](../../docs/group-loading-memory.md).

Requires Node.js, Git, Java, Connect IQ SDK 9.2.0 or a compatible SDK, installed Instinct 2 and fēnix 9 Pro 47 mm device definitions, and a local signing key. The PowerShell compiler accepts `-SdkPath` and `-SigningKey`; otherwise it reads the Windows Garmin SDK configuration and uses `developer_key` in the checkout.

From the repository root:

```powershell
pwsh -File tests/memory-benchmark/compile.ps1
pwsh -File tests/memory-benchmark/compile.ps1 -Revision 795a986
node -e "require('fs').writeFileSync('bin/memory-benchmark/scenario.json', JSON.stringify({scenario:'eager',leafCount:8}))"
node tests/memory-benchmark/server.cjs
```

The server binds to `127.0.0.1:8765` only. Keep it running while using the simulator. Set `scenario` to `eager`, `lazy` or `delayed`, and `leafCount` to 8 or 34. Each fixture has eight ordinary items, seven group summaries, and the specified number of forecast rows. Run the generated **release** PRG using `monkeydo` without `/t`, for example in another terminal:

```powershell
$sdk = (Get-Content "$env:APPDATA/Garmin/ConnectIQ/current-sdk.cfg").Trim()
& "$sdk/bin/monkeydo.bat" bin/memory-benchmark/feature/instinct2.prg instinct2
```

Start the SDK simulator first. If its HTTP security requirement rejects loopback with `SECURE_CONNECTION_REQUIRED`, temporarily allow HTTP in the simulator settings and restore that setting afterward. Production security behavior is unchanged. Stop the loopback server with Ctrl+C after the runs.

`MEM` records contain scenario, cycle, stage, used bytes, free bytes, total available bytes, and request count. The harness takes timer-separated samples after callbacks return, allowing their local references to expire, but does not force garbage collection. Lazy runs open and close Forecast between refreshes. Each normal run ends with `BENCH_DONE`; errors and crashes are capacity evidence, not successful runs. The host server logs JSON and request/response sizes.

Unit-test mode can substantially enlarge the simulator's memory allowance. Do not use a `-t` build or `/t` execution to establish a weak device's memory capacity. These point-in-time samples also do not establish the true allocation or network-parser peak.
