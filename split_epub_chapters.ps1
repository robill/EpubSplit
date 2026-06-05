<#
.SYNOPSIS
    Splits an EPUB into multiple files by chapter count with auto-formatted titles.

.DESCRIPTION
    First pass: calls epubsplit.py to list all split points.
    Detects chapter boundaries using the same toc/id patterns as ebooks.zsh.
    Groups them into chunks of N chapters, then produces one epub per chunk.
    Patterns can be overridden via $env:esP1 and $env:esP2 (same as ebooks.zsh).

.PARAMETER EpubFile
    Path to the source EPUB file.

.PARAMETER StartIndex
    Chapter number to start splitting from (inclusive). Chapters with a number
    below this value are skipped. Default: 1 (include all chapters).

.PARAMETER EndIndex
    Chapter number to stop at (inclusive). Chapters with a number above this
    value are skipped. Default: 0 (no limit, include all remaining chapters).

.PARAMETER ChaptersPerSplit
    Number of chapters per output file.

.PARAMETER TitlePattern
    Title template. Use 'xxxx' for first chapter number and 'yyyy' for last,
    zero-padded to the number of characters used (4 x's = 4-digit padding).
    Example: "TGR Chapter xxxx-yyyy"

.EXAMPLE
    .\split_epub_chapters.ps1 "mybook.epub" 50 "TGR Chapter xxxx-yyyy"
    Produces: "TGR Chapter 0001-0050.epub", "TGR Chapter 0051-0100.epub", ...

.EXAMPLE
    .\split_epub_chapters.ps1 "mybook.epub" 100 50 "TGR Chapter xxxx-yyyy"
    Starts from chapter 100, produces: "TGR Chapter 0100-0149.epub", ...

.EXAMPLE
    .\split_epub_chapters.ps1 "mybook.epub" 100 200 50 "TGR Chapter xxxx-yyyy"
    Chapters 100-200 only, in groups of 50.
#>

param(
    [Parameter(Mandatory, Position=0)][string]$EpubFile,
    [Parameter(Position=1)][int]$StartIndex = 1,
    [Parameter(Position=2)][int]$EndIndex = 0,
    [Parameter(Mandatory, Position=3)][int]$ChaptersPerSplit,
    [Parameter(Mandatory, Position=4)][string]$TitlePattern
)

$ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$EpubSplitPy = Join-Path $ScriptDir "epubsplit.py"

# Detect placeholder widths from pattern, e.g. "xxxx" -> 4-digit padding
$xMatch       = [regex]::Match($TitlePattern, 'x+')
$yMatch       = [regex]::Match($TitlePattern, 'y+')
$padX         = if ($xMatch.Success) { $xMatch.Length } else { 4 }
$padY         = if ($yMatch.Success) { $yMatch.Length } else { 4 }
$xPlaceholder = if ($xMatch.Success) { $xMatch.Value } else { $null }
$yPlaceholder = if ($yMatch.Success) { $yMatch.Value } else { $null }

# Chapter detection patterns (same defaults as ebooks.zsh esP1/esP2, overridable via env vars)
# Updated to match both single and double quotes for toc entries
$pToc  = if ($env:esP1) { $env:esP1 } else { "toc:\s+\[.{0,1}.*?(\d+)" }
$pIdPat = if ($env:esP2) { $env:esP2 } else { "id:\s+[cC]\D*(\d+)" }

Write-Host "Listing split points in: $EpubFile"
$epubOutput = python $EpubSplitPy $EpubFile

# Parse chapter entries: collect (Line, Chap) per unique chapter boundary.
# Note: The Line Numbers in epubsplit.py output are consistently off by +1 from chapter numbers.
# We track chapter numbers and will add 1 when passing to epubsplit.py.
$chapters = @()
foreach ($line in $epubOutput) {
    if ($line -match $pToc) {
        $num = [int]$Matches[1]
        if ($num -ne $lm1) {
            $chapters += [PSCustomObject]@{ Chap = $num }
        }
        $lm1 = $num
    }

    if ($line -match $pIdPat) {
        $num = [int]$Matches[1]
        if ($num -ne $lm2) {
            $chapters += [PSCustomObject]@{ Chap = $num }
        }
        $lm2 = $num
    }
}

$chapters = $chapters | Sort-Object -Property Chap -Unique

Write-Host "Found $($chapters.Count) chapter entries."

# Apply start/end index filters
if ($StartIndex -gt 1) {
    $before   = $chapters.Count
    $chapters = @($chapters | Where-Object { $_.Chap -ge $StartIndex })
    Write-Host "StartIndex=${StartIndex}: skipped $($before - $chapters.Count) entries before start, $($chapters.Count) remaining."
}
if ($EndIndex -gt 0) {
    $before   = $chapters.Count
    $chapters = @($chapters | Where-Object { $_.Chap -le $EndIndex })
    Write-Host "EndIndex=${EndIndex}: skipped $($before - $chapters.Count) entries after end, $($chapters.Count) remaining."
}

if ($chapters.Count -eq 0) {
    Write-Error "No chapter entries found. Verify the toc/id patterns match your epub structure.`nTry overriding via `$env:esP1 / `$env:esP2."
    exit 1
}

# Split into chunks of $ChaptersPerSplit and generate one epub per chunk
$total      = $chapters.Count
$fileCount  = 0

for ($i = 0; $i -lt $total; $i += $ChaptersPerSplit) {
    $end   = [Math]::Min($i + $ChaptersPerSplit - 1, $total - 1)
    $chunk = $chapters[$i..$end]

    $firstChap = $chunk[0].Chap
    $lastChap  = $chunk[-1].Chap

    $xStr = $firstChap.ToString("D$padX")
    $yStr = $lastChap.ToString("D$padY")

    $titleStr = $TitlePattern
    if ($xPlaceholder) { $titleStr = $titleStr.Replace($xPlaceholder, $xStr) }
    if ($yPlaceholder) { $titleStr = $titleStr.Replace($yPlaceholder, $yStr) }

    $outputFile = "$titleStr.epub"
    # Add 1 to chapter numbers to get the correct Line Numbers for epubsplit.py
    $lineNums   = $chunk | ForEach-Object { "$($_.Chap + 1)" }

    Write-Host "Creating: $outputFile  (chapters $firstChap-$lastChap, $($chunk.Count) sections)"
    python $EpubSplitPy --title $titleStr -o $outputFile $EpubFile @lineNums
    $fileCount++
}

Write-Host "`nDone. Created $fileCount file(s)."
