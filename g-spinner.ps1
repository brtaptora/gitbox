function Start-Spinner {
    param([string]$Label)
    if ([Console]::IsOutputRedirected) { return $null }
    $rs = [runspacefactory]::CreateRunspace()
    $rs.Open()
    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddScript({
        param($lbl)
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
        $useUnicode = $env:WT_SESSION -and [Console]::OutputEncoding.CodePage -eq 65001
        $frames = if ($useUnicode) {
            [char[]]@(0x280B,0x2819,0x2839,0x2838,0x283C,0x2834,0x2826,0x2827,0x2807,0x280F)
        } else {
            [char[]]@('|', '/', '-', '\')
        }
        $count = $frames.Length
        $e = [char]27
        $i = 0
        while ($true) {
            [Console]::Write("${e}[36m`r$($frames[$i % $count])${e}[0m $lbl")
            [System.Threading.Thread]::Sleep(80)
            $i++
        }
    }).AddArgument($Label)
    $ps.BeginInvoke() | Out-Null
    return [pscustomobject]@{ PS = $ps; RS = $rs; Label = $Label }
}

function Stop-Spinner {
    param([object]$Spinner)
    if (-not $Spinner) { return }
    try { $Spinner.PS.Stop()    } catch {}
    try { $Spinner.PS.Dispose() } catch {}
    try { $Spinner.RS.Close()   } catch {}
    try { $Spinner.RS.Dispose() } catch {}
    [Console]::Write("`r$(' ' * ($Spinner.Label.Length + 5))`r")
}
