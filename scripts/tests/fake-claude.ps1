$args | Set-Content -LiteralPath $env:FAKE_ARGS -Encoding UTF8
$stdinStream = [Console]::OpenStandardInput()
$buffer = New-Object byte[] 1048576
$total = New-Object Collections.Generic.List[byte]
while (($read = $stdinStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
    for ($i = 0; $i -lt $read; $i++) { [void]$total.Add($buffer[$i]) }
}
[IO.File]::WriteAllBytes($env:FAKE_STDIN, $total.ToArray())
(Get-Location).Path | Set-Content -LiteralPath $env:FAKE_CWD -NoNewline -Encoding UTF8

switch ($env:FAKE_MODE) {
    "empty" { exit 0 }
    "fail" { [Console]::Error.WriteLine("fake failure"); exit 7 }
    "sleep" { Start-Sleep -Seconds 5; exit 0 }
    "edit-env-example" {
        Set-Content -LiteralPath (Join-Path (Get-Location) ".env.example") -Value "changed" -NoNewline -Encoding UTF8
        [Console]::Out.WriteLine("fake response")
        exit 0
    }
    "edit-env-example-and-sample" {
        Set-Content -LiteralPath (Join-Path (Get-Location) ".env.example") -Value "changed" -NoNewline -Encoding UTF8
        Set-Content -LiteralPath (Join-Path (Get-Location) ".env.sample") -Value "changed" -NoNewline -Encoding UTF8
        [Console]::Out.WriteLine("fake response")
        exit 0
    }
    default { [Console]::Out.WriteLine("fake response"); exit 0 }
}
