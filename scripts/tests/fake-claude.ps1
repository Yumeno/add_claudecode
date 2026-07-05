$args | Set-Content -LiteralPath $env:FAKE_ARGS -Encoding UTF8
[Console]::In.ReadToEnd() | Set-Content -LiteralPath $env:FAKE_STDIN -NoNewline -Encoding UTF8
(Get-Location).Path | Set-Content -LiteralPath $env:FAKE_CWD -NoNewline -Encoding UTF8

switch ($env:FAKE_MODE) {
    "empty" { exit 0 }
    "fail" { [Console]::Error.WriteLine("fake failure"); exit 7 }
    "sleep" { Start-Sleep -Seconds 5; exit 0 }
    default { [Console]::Out.WriteLine("fake response"); exit 0 }
}
