# Update the table of contents, caption numbers and cross-references of a .docx with Microsoft Word,
# so the report opens with every number filled in (no Ctrl+A, F9 needed).
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File update_word_fields.ps1 -Path report.docx
param([Parameter(Mandatory = $true)][string]$Path)
$ErrorActionPreference = "Stop"
$Path = (Resolve-Path $Path).Path
$word = New-Object -ComObject Word.Application
$word.Visible = $false
$word.DisplayAlerts = 0
try {
    $doc = $word.Documents.Open($Path, $false, $false)
    # Two passes: caption numbers (SEQ) first, then the cross-references (REF) that point to them.
    for ($pass = 0; $pass -lt 2; $pass++) {
        foreach ($story in $doc.StoryRanges) { [void]$story.Fields.Update() }
    }
    foreach ($toc in $doc.TablesOfContents) { $toc.Update() }
    $doc.Save()
    $doc.Close()
    Write-Output "Word fields updated: $Path"
}
finally {
    $word.Quit()
    [void][Runtime.InteropServices.Marshal]::ReleaseComObject($word)
}
