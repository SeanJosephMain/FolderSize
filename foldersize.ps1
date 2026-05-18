<#
.SYNOPSIS
    Folder Size Analyzer - GUI with collapsible folder tree and live scanning.

.DESCRIPTION
    Windows Forms GUI that lets you browse a folder tree on the left and
    see file/folder sizes for the selected folder on the right. Scans run
    on a background runspace and stream results live. Tree is lazy-loaded
    and can be collapsed to the left to maximize the data view.

.NOTES
    Run with:  powershell -ExecutionPolicy Bypass -File .\FolderSizeGUI.ps1
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# ---------- Helpers ----------

function Format-Size {
    param([double]$Bytes)
    if ($Bytes -ge 1TB) { return ('{0:N2} TB' -f ($Bytes / 1TB)) }
    if ($Bytes -ge 1GB) { return ('{0:N2} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N2} MB' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:N2} KB' -f ($Bytes / 1KB)) }
    return ('{0} B' -f [int64]$Bytes)
}

function Format-Date {
    param($Dt)
    if ($null -eq $Dt -or $Dt -eq [datetime]::MinValue) { return '' }
    return $Dt.ToString('yyyy-MM-dd HH:mm')
}

# ---------- Form ----------

$form = New-Object System.Windows.Forms.Form
$form.Text          = 'Folder Size Analyzer'
$form.Size          = New-Object System.Drawing.Size(1100, 600)
$form.StartPosition = 'CenterScreen'
$form.MinimumSize   = New-Object System.Drawing.Size(820, 460)
$form.Font          = New-Object System.Drawing.Font('Segoe UI', 9)

# Status strip (added first; docks at bottom)
$status = New-Object System.Windows.Forms.StatusStrip
$statusLabel = New-Object System.Windows.Forms.ToolStripStatusLabel
$statusLabel.Text = 'Ready.'
$statusLabel.Spring = $true
$statusLabel.TextAlign = 'MiddleLeft'
$progress = New-Object System.Windows.Forms.ToolStripProgressBar
$progress.Size = New-Object System.Drawing.Size(180, 16)
$progress.Style = 'Continuous'
$progress.Visible = $false
$status.Items.AddRange(@($statusLabel, $progress))
$form.Controls.Add($status)

# SplitContainer: left = folder tree, right = path/list
# NOTE: Panel*MinSize and SplitterDistance are set in Add_Shown once the
# control has a real width — setting them before that triggers
# "SplitterDistance must be between Panel1MinSize and Width - Panel2MinSize".
$split = New-Object System.Windows.Forms.SplitContainer
$split.Orientation      = 'Vertical'
$split.SplitterWidth    = 4
$split.FixedPanel       = 'Panel1'
$split.Dock             = 'Fill'
$form.Controls.Add($split)

# Left: header panel + tree
$treeHeader = New-Object System.Windows.Forms.Panel
$treeHeader.Dock     = 'Top'
$treeHeader.Height   = 28
$treeHeader.BackColor = [System.Drawing.Color]::FromArgb(240, 240, 240)
$treeHeaderLbl = New-Object System.Windows.Forms.Label
$treeHeaderLbl.Text     = 'Folders'
$treeHeaderLbl.Location = New-Object System.Drawing.Point(8, 6)
$treeHeaderLbl.AutoSize = $true
$treeHeaderLbl.Font     = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$treeHeader.Controls.Add($treeHeaderLbl)
$split.Panel1.Controls.Add($treeHeader)

$tree = New-Object System.Windows.Forms.TreeView
$tree.Dock         = 'Fill'
$tree.HideSelection = $false
$tree.Indent       = 18
$tree.ShowLines    = $true
$tree.ShowRootLines = $true
$split.Panel1.Controls.Add($tree)
$tree.BringToFront()

# Right: toolbar + listview
$toolbar = New-Object System.Windows.Forms.Panel
$toolbar.Dock   = 'Top'
$toolbar.Height = 44
$split.Panel2.Controls.Add($toolbar)

# Toggle button (◀ when tree visible, ▶ when collapsed)
$toggleBtn = New-Object System.Windows.Forms.Button
$toggleBtn.Text     = [char]0x25C0     # ◀
$toggleBtn.Location = New-Object System.Drawing.Point(8, 9)
$toggleBtn.Size     = New-Object System.Drawing.Size(30, 26)
$toggleBtn.Font     = New-Object System.Drawing.Font('Segoe UI', 9)
$toolbar.Controls.Add($toggleBtn)

# Path textbox (anchored to stretch)
$pathBox = New-Object System.Windows.Forms.TextBox
$pathBox.Location = New-Object System.Drawing.Point(46, 10)
$pathBox.Size     = New-Object System.Drawing.Size(380, 24)
$pathBox.Anchor   = 'Top, Left, Right'
$pathBox.Text     = [Environment]::GetFolderPath('UserProfile')
$toolbar.Controls.Add($pathBox)

# Buttons anchored to the right side
$upBtn = New-Object System.Windows.Forms.Button
$upBtn.Text     = 'Up'
$upBtn.Size     = New-Object System.Drawing.Size(50, 26)
$upBtn.Anchor   = 'Top, Right'
$toolbar.Controls.Add($upBtn)

$browseBtn = New-Object System.Windows.Forms.Button
$browseBtn.Text     = 'Browse...'
$browseBtn.Size     = New-Object System.Drawing.Size(85, 26)
$browseBtn.Anchor   = 'Top, Right'
$toolbar.Controls.Add($browseBtn)

$scanBtn = New-Object System.Windows.Forms.Button
$scanBtn.Text     = 'Scan'
$scanBtn.Size     = New-Object System.Drawing.Size(110, 26)
$scanBtn.Anchor   = 'Top, Right'
$scanBtn.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
$scanBtn.ForeColor = [System.Drawing.Color]::White
$scanBtn.FlatStyle = 'Flat'
$toolbar.Controls.Add($scanBtn)

$cancelBtn = New-Object System.Windows.Forms.Button
$cancelBtn.Text     = 'Cancel'
$cancelBtn.Size     = New-Object System.Drawing.Size(80, 26)
$cancelBtn.Anchor   = 'Top, Right'
$cancelBtn.Enabled  = $false
$toolbar.Controls.Add($cancelBtn)

# Position right-anchored buttons relative to toolbar width
function Layout-Toolbar {
    $w = $toolbar.ClientSize.Width
    $cancelBtn.Location = New-Object System.Drawing.Point(($w - 12 - $cancelBtn.Width), 9)
    $scanBtn.Location   = New-Object System.Drawing.Point(($cancelBtn.Left - 6 - $scanBtn.Width), 9)
    $browseBtn.Location = New-Object System.Drawing.Point(($scanBtn.Left - 6 - $browseBtn.Width), 9)
    $upBtn.Location     = New-Object System.Drawing.Point(($browseBtn.Left - 6 - $upBtn.Width), 9)
    $pathBox.Width      = [Math]::Max(80, $upBtn.Left - 6 - $pathBox.Left)
}
$toolbar.Add_Resize({ Layout-Toolbar })

# ListView
$list = New-Object System.Windows.Forms.ListView
$list.Dock          = 'Fill'
$list.View          = 'Details'
$list.FullRowSelect = $true
$list.GridLines     = $true
$list.MultiSelect   = $false
$list.Columns.Add('Type',     55)  | Out-Null
$list.Columns.Add('Name',     320) | Out-Null
$list.Columns.Add('Size',     100) | Out-Null
$list.Columns.Add('Bytes',    115) | Out-Null
$list.Columns.Add('Items',    70)  | Out-Null
$list.Columns.Add('% Total',  75)  | Out-Null
$list.Columns.Add('Modified', 140) | Out-Null
$split.Panel2.Controls.Add($list)
$list.BringToFront()

# ---------- Script state ----------
$script:sortColumn  = 2
$script:sortDesc    = $true
$script:currentPath = $null
$script:totalBytes  = [int64]0
$script:folderCount = 0
$script:fileCount   = 0

$script:sync   = $null
$script:ps     = $null
$script:rs     = $null
$script:async  = $null
$script:timer  = New-Object System.Windows.Forms.Timer
$script:timer.Interval = 100

# Set true while we programmatically change the tree selection, so the
# AfterSelect handler doesn't trigger another scan and recurse.
$script:suppressTreeSelect = $false

# ---------- Tree (lazy-loaded) ----------

function Populate-TreeRoots {
    $tree.BeginUpdate()
    $tree.Nodes.Clear()
    foreach ($drive in [System.IO.DriveInfo]::GetDrives()) {
        try {
            if (-not $drive.IsReady) { continue }
            $node = New-Object System.Windows.Forms.TreeNode
            $label = $drive.Name.TrimEnd('\')
            if ($drive.VolumeLabel) { $label = "$label ($($drive.VolumeLabel))" }
            $node.Text = $label
            $node.Tag  = $drive.RootDirectory.FullName
            $node.Nodes.Add('...') | Out-Null   # dummy child = lazy placeholder
            $tree.Nodes.Add($node) | Out-Null
        } catch { }
    }
    $tree.EndUpdate()
}

function Is-DummyChild {
    param($Node)
    return ($Node.Nodes.Count -eq 1 -and $null -eq $Node.Nodes[0].Tag)
}

$tree.Add_BeforeExpand({
    param($s, $e)
    $node = $e.Node
    if (-not (Is-DummyChild $node)) { return }
    $node.Nodes.Clear()
    try {
        $children = Get-ChildItem -LiteralPath $node.Tag -Directory -Force -ErrorAction SilentlyContinue |
                    Sort-Object Name
        foreach ($c in $children) {
            $child = New-Object System.Windows.Forms.TreeNode
            $child.Text = $c.Name
            $child.Tag  = $c.FullName
            $child.Nodes.Add('...') | Out-Null
            $node.Nodes.Add($child) | Out-Null
        }
    } catch { }
})

$tree.Add_AfterSelect({
    param($s, $e)
    if ($script:suppressTreeSelect) { return }
    if ($e.Node -and $e.Node.Tag) {
        # Avoid kicking off a fresh scan if we're already on that path
        if ($script:currentPath -ne $e.Node.Tag) {
            Start-Scan -Root $e.Node.Tag
        }
    }
})

# Try to expand the tree to a given path and select that node
function Sync-TreeToPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    try {
        $full = [System.IO.Path]::GetFullPath($Path)
    } catch { return }

    $rootName = ([System.IO.Path]::GetPathRoot($full)).TrimEnd('\')
    if (-not $rootName) { return }

    $script:suppressTreeSelect = $true
    try {
        # Find root node matching this drive
        $rootNode = $null
        foreach ($n in $tree.Nodes) {
            $t = ([string]$n.Tag).TrimEnd('\')
            if ($t -ieq $rootName) { $rootNode = $n; break }
        }
        if (-not $rootNode) { return }

        $current = $rootNode
        $rel = $full.Substring($rootName.Length).TrimStart('\')
        if ($rel) {
            $parts = $rel -split '\\'
            foreach ($p in $parts) {
                if (-not $p) { continue }
                $current.Expand()
                $found = $null
                foreach ($child in $current.Nodes) {
                    if ($child.Text -ieq $p) { $found = $child; break }
                }
                if (-not $found) { break }
                $current = $found
            }
        }
        $tree.SelectedNode = $current
        $current.EnsureVisible()
    } finally {
        $script:suppressTreeSelect = $false
    }
}

# ---------- Row helpers ----------

function Add-ResultRow {
    param($Rec, [bool]$FinalTotalKnown = $false)
    $typeLabel = if ($Rec.Kind -eq 'Folder') { '[DIR]' } else { 'File' }
    $item = New-Object System.Windows.Forms.ListViewItem($typeLabel)
    $item.SubItems.Add( $Rec.Name ) | Out-Null
    $item.SubItems.Add( (Format-Size $Rec.Size) ) | Out-Null
    $item.SubItems.Add( ('{0:N0}' -f $Rec.Size) ) | Out-Null
    $item.SubItems.Add( ('{0:N0}' -f $Rec.Items) ) | Out-Null
    if ($FinalTotalKnown -and $script:totalBytes -gt 0) {
        $pct = ($Rec.Size / $script:totalBytes) * 100
        $item.SubItems.Add( ('{0:N1}%' -f $pct) ) | Out-Null
    } else {
        $item.SubItems.Add('') | Out-Null
    }
    $item.SubItems.Add( (Format-Date $Rec.Modified) ) | Out-Null
    $item.Tag = $Rec
    if ($Rec.Kind -eq 'Folder') {
        $item.ForeColor = [System.Drawing.Color]::FromArgb(0, 80, 160)
    }
    $list.Items.Add($item) | Out-Null
}

function Finalize-List {
    $records = @()
    foreach ($it in $list.Items) { if ($it.Tag) { $records += ,$it.Tag } }
    $sorted = $records | Sort-Object -Property Size -Descending
    $list.BeginUpdate()
    $list.Items.Clear()
    foreach ($r in $sorted) { Add-ResultRow -Rec $r -FinalTotalKnown $true }
    $list.EndUpdate()
}

# ---------- Background scan ----------

function Stop-BackgroundScan {
    if ($script:sync) { $script:sync.Cancel = $true }
    $script:timer.Stop()
    if ($script:ps) {
        try { $script:ps.Stop() | Out-Null } catch { }
        try { $script:ps.Dispose() } catch { }
        $script:ps = $null
    }
    if ($script:rs) {
        try { $script:rs.Close() } catch { }
        try { $script:rs.Dispose() } catch { }
        $script:rs = $null
    }
    $script:async = $null
}

function Start-Scan {
    param([string]$Root)
    try { $Root = [System.IO.Path]::GetFullPath($Root.Trim()) }
    catch {
        [System.Windows.Forms.MessageBox]::Show("Invalid path:`n$Root", 'Error', 'OK', 'Error') | Out-Null
        return
    }
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
        [System.Windows.Forms.MessageBox]::Show("Folder not found:`n$Root", 'Error', 'OK', 'Error') | Out-Null
        return
    }

    Stop-BackgroundScan

    $pathBox.Text       = $Root
    $script:currentPath = $Root
    $script:totalBytes  = [int64]0
    $script:folderCount = 0
    $script:fileCount   = 0
    $list.Items.Clear()

    # Keep the folder tree in sync with the path we're scanning
    Sync-TreeToPath $Root

    $scanBtn.Enabled   = $false
    $browseBtn.Enabled = $false
    $upBtn.Enabled     = $false
    $cancelBtn.Enabled = $true
    $progress.Visible  = $true
    $progress.Value    = 0
    $progress.Maximum  = 100
    $statusLabel.Text  = "Starting scan of $Root ..."

    $script:sync = [hashtable]::Synchronized(@{
        Queue     = New-Object 'System.Collections.Concurrent.ConcurrentQueue[object]'
        Done      = $false
        Cancel    = $false
        Status    = ''
        Total     = 0
        Processed = 0
        ErrorMsg  = $null
    })

    $script:rs = [runspacefactory]::CreateRunspace()
    $script:rs.ApartmentState = 'STA'
    $script:rs.ThreadOptions  = 'ReuseThread'
    $script:rs.Open()
    $script:rs.SessionStateProxy.SetVariable('sync', $script:sync)
    $script:rs.SessionStateProxy.SetVariable('Root', $Root)

    $script:ps = [powershell]::Create()
    $script:ps.Runspace = $script:rs
    $null = $script:ps.AddScript({
        try {
            $subDirs = @()
            $files   = @()
            try { $subDirs = @(Get-ChildItem -LiteralPath $Root -Directory -Force -ErrorAction SilentlyContinue) } catch { }
            try { $files   = @(Get-ChildItem -LiteralPath $Root -File      -Force -ErrorAction SilentlyContinue) } catch { }

            $sync.Total = $subDirs.Count + $files.Count

            foreach ($f in $files) {
                if ($sync.Cancel) { return }
                $sync.Queue.Enqueue([pscustomobject]@{
                    Kind     = 'File'
                    Name     = $f.Name
                    Path     = $f.FullName
                    Size     = [int64]$f.Length
                    Items    = [int64]1
                    Modified = $f.LastWriteTime
                })
                $sync.Processed++
            }

            foreach ($d in $subDirs) {
                if ($sync.Cancel) { return }
                $sync.Status = "Scanning: $($d.Name)"

                $size   = [int64]0
                $count  = [int64]0
                $maxMod = [datetime]::MinValue
                try {
                    Get-ChildItem -LiteralPath $d.FullName -Recurse -File -Force -ErrorAction SilentlyContinue |
                        ForEach-Object {
                            if ($sync.Cancel) { return }
                            $size  += $_.Length
                            $count += 1
                            if ($_.LastWriteTime -gt $maxMod) { $maxMod = $_.LastWriteTime }
                        }
                } catch { }
                if ($sync.Cancel) { return }
                if ($maxMod -eq [datetime]::MinValue) {
                    try { $maxMod = $d.LastWriteTime } catch { }
                }
                $sync.Queue.Enqueue([pscustomobject]@{
                    Kind     = 'Folder'
                    Name     = $d.Name
                    Path     = $d.FullName
                    Size     = $size
                    Items    = $count
                    Modified = $maxMod
                })
                $sync.Processed++
            }
        } catch {
            $sync.ErrorMsg = $_.ToString()
        } finally {
            $sync.Done = $true
        }
    })

    $script:async = $script:ps.BeginInvoke()
    $script:timer.Start()
}

$script:timer.Add_Tick({
    if (-not $script:sync) { $script:timer.Stop(); return }

    $rec = $null
    while ($script:sync.Queue.TryDequeue([ref]$rec)) {
        Add-ResultRow -Rec $rec -FinalTotalKnown $false
        $script:totalBytes += [int64]$rec.Size
        if ($rec.Kind -eq 'Folder') { $script:folderCount++ } else { $script:fileCount++ }
    }

    $total = [int]$script:sync.Total
    $done  = [int]$script:sync.Processed
    if ($total -gt 0) {
        $pct = [math]::Min(100, [int](($done / $total) * 100))
        $progress.Value = $pct
        $statusLabel.Text = "{0}  ({1}/{2})  Running total: {3}" -f `
            $script:sync.Status, $done, $total, (Format-Size $script:totalBytes)
    } else {
        $statusLabel.Text = "Scanning..."
    }

    if ($script:sync.Done -and $script:sync.Queue.Count -eq 0) {
        $script:timer.Stop()
        try { $script:ps.EndInvoke($script:async) | Out-Null } catch { }
        try { $script:ps.Dispose() } catch { }
        try { $script:rs.Close(); $script:rs.Dispose() } catch { }
        $script:ps = $null; $script:rs = $null; $script:async = $null

        if ($script:sync.Cancel) {
            $statusLabel.Text = "Cancelled. Partial: {0} folders, {1} files, {2}." -f `
                $script:folderCount, $script:fileCount, (Format-Size $script:totalBytes)
        } elseif ($script:sync.ErrorMsg) {
            $statusLabel.Text = "Error: $($script:sync.ErrorMsg)"
        } else {
            $statusLabel.Text = "Done. {0} folders, {1} files, total {2}  ({3})" -f `
                $script:folderCount, $script:fileCount, (Format-Size $script:totalBytes), $script:currentPath
        }

        Finalize-List
        $progress.Visible  = $false
        $scanBtn.Enabled   = $true
        $browseBtn.Enabled = $true
        $upBtn.Enabled     = $true
        $cancelBtn.Enabled = $false
    }
})

# ---------- Events ----------

$toggleBtn.Add_Click({
    $split.Panel1Collapsed = -not $split.Panel1Collapsed
    if ($split.Panel1Collapsed) {
        $toggleBtn.Text = [char]0x25B6   # ▶
        $toggleBtn.ToolTipText = 'Show folder tree'
    } else {
        $toggleBtn.Text = [char]0x25C0   # ◀
        $toggleBtn.ToolTipText = 'Hide folder tree'
    }
})

$scanBtn.Add_Click({ Start-Scan -Root $pathBox.Text })

$cancelBtn.Add_Click({
    if ($script:sync) { $script:sync.Cancel = $true }
    $statusLabel.Text = 'Cancelling...'
})

$browseBtn.Add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = 'Select a folder to analyze'
    if (Test-Path -LiteralPath $pathBox.Text) { $dlg.SelectedPath = $pathBox.Text }
    if ($dlg.ShowDialog() -eq 'OK') { Start-Scan -Root $dlg.SelectedPath }
})

$upBtn.Add_Click({
    $start = if ($script:currentPath) { $script:currentPath } else { $pathBox.Text }
    if ([string]::IsNullOrWhiteSpace($start)) { return }
    try {
        $full = [System.IO.Path]::GetFullPath($start.Trim())
        $di   = New-Object System.IO.DirectoryInfo($full)
        if ($null -ne $di.Parent) { Start-Scan -Root $di.Parent.FullName }
        else { $statusLabel.Text = "Already at the root: $full" }
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Could not navigate up:`n$_", 'Error', 'OK', 'Error') | Out-Null
    }
})

$pathBox.Add_KeyDown({
    if ($_.KeyCode -eq 'Enter') {
        $_.SuppressKeyPress = $true
        Start-Scan -Root $pathBox.Text
    }
})

$list.Add_DoubleClick({
    if ($list.SelectedItems.Count -gt 0) {
        $rec = $list.SelectedItems[0].Tag
        if ($null -eq $rec) { return }
        if ($rec.Kind -eq 'Folder' -and (Test-Path -LiteralPath $rec.Path -PathType Container)) {
            Start-Scan -Root $rec.Path
        } elseif ($rec.Kind -eq 'File' -and (Test-Path -LiteralPath $rec.Path -PathType Leaf)) {
            try { Start-Process -FilePath $rec.Path } catch {
                [System.Windows.Forms.MessageBox]::Show(
                    "Could not open file:`n$($rec.Path)`n`n$_", 'Error', 'OK', 'Error') | Out-Null
            }
        }
    }
})

$list.Add_KeyDown({ if ($_.KeyCode -eq 'Back') { $upBtn.PerformClick() } })

$list.Add_ColumnClick({
    param($s, $e)
    if ($script:sortColumn -eq $e.Column) { $script:sortDesc = -not $script:sortDesc }
    else { $script:sortColumn = $e.Column; $script:sortDesc = $true }
    $items = @($list.Items)
    $list.BeginUpdate()
    $list.Items.Clear()
    $sorted = $items | Sort-Object -Descending:$script:sortDesc -Property @{
        Expression = {
            switch ($script:sortColumn) {
                0 { $_.Text }
                1 { $_.SubItems[1].Text }
                2 { [int64]($_.SubItems[3].Text -replace ',', '') }
                3 { [int64]($_.SubItems[3].Text -replace ',', '') }
                4 { [int64]($_.SubItems[4].Text -replace ',', '') }
                5 {
                    $t = $_.SubItems[5].Text -replace '[%,]', ''
                    if ([string]::IsNullOrWhiteSpace($t)) { -1 } else { [double]$t }
                }
                6 { $_.SubItems[6].Text }
            }
        }
    }
    foreach ($it in $sorted) { $list.Items.Add($it) | Out-Null }
    $list.EndUpdate()
})

# Right-click menu
$menu = New-Object System.Windows.Forms.ContextMenuStrip
$openItem = $menu.Items.Add('Open')
$openItem.Add_Click({
    if ($list.SelectedItems.Count -gt 0) {
        $rec = $list.SelectedItems[0].Tag
        if ($rec -and (Test-Path -LiteralPath $rec.Path)) {
            try { Start-Process -FilePath $rec.Path } catch { }
        }
    }
})
$revealItem = $menu.Items.Add('Show in Explorer')
$revealItem.Add_Click({
    if ($list.SelectedItems.Count -gt 0) {
        $rec = $list.SelectedItems[0].Tag
        if ($rec -and (Test-Path -LiteralPath $rec.Path)) {
            if ($rec.Kind -eq 'File') { Start-Process explorer.exe -ArgumentList "/select,`"$($rec.Path)`"" }
            else { Start-Process explorer.exe -ArgumentList "`"$($rec.Path)`"" }
        }
    }
})
$copyItem = $menu.Items.Add('Copy path')
$copyItem.Add_Click({
    if ($list.SelectedItems.Count -gt 0) {
        $rec = $list.SelectedItems[0].Tag
        if ($rec) { [System.Windows.Forms.Clipboard]::SetText($rec.Path) }
    }
})
$list.ContextMenuStrip = $menu

# Cleanup
$form.Add_FormClosing({ Stop-BackgroundScan })

# Startup: populate tree, lay out toolbar, configure splitter, then scan default
$form.Add_Shown({
    # Now that the form has a real width, splitter constraints can be set
    try {
        $split.Panel1MinSize    = 50
        $split.Panel2MinSize    = 350
        $split.SplitterDistance = 340
    } catch { }

    Populate-TreeRoots
    Layout-Toolbar
    Start-Scan -Root $pathBox.Text
})

[void]$form.ShowDialog()
$form.Dispose()