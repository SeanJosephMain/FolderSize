Folder Size Analyzer
====================

A lightweight Windows GUI tool, written as a single PowerShell script,
for finding out where your disk space is actually going. Point it at any
folder and it shows every file and immediate subfolder inside, ranked
by size, so the things eating your drive are right at the top.

No installer, no dependencies. Just one .ps1 file.


Features
--------

- Folder tree on the left with lazy-loaded drive and folder navigation.
  Click any folder to scan it. The tree follows the current path
  automatically when you navigate from the path bar, the list, or the
  Up button. Collapse it with the toggle button to give the data view
  the full window.

- Mixed file and folder listing for the selected folder. Subfolders
  show recursive size and file count, and loose files in the folder
  are listed alongside them so a single bloated file does not hide
  behind a folder count.

- Live scanning. The work happens on a background runspace and streams
  into the list as it is computed. The UI never freezes, even on huge
  trees like C:\Windows or AppData.

- Real progress feedback. A progress bar fills as folders complete,
  and the status bar shows the folder being scanned plus a running
  size total.

- Cancellable. You can abort a slow scan and keep whatever has already
  been collected.

- Last modified dates. Files show their own modified time. Folders
  show the most recent modification of anything inside them, which is
  more accurate than the folder timestamps Windows shows in Explorer.

- Sortable columns: Type, Name, Size, Bytes, Items, Percent of Total,
  Modified. Click any header to toggle ascending or descending.

- Easy navigation: double-click a folder to drill in, double-click a
  file to open it, Up button or Backspace for the parent folder,
  Browse for a folder dialog, or type a path and press Enter to jump
  anywhere.

- Right-click actions: Open, Show in Explorer, Copy path.


Requirements
------------

- Windows 10 or 11 + Server
- Windows PowerShell 5.1 (built in) or PowerShell 7 or newer
- No additional modules needed


Installation
------------

Save FolderSizeGUI.ps1 anywhere you like. That is it.


Usage
-----

From a PowerShell prompt:

    powershell -ExecutionPolicy Bypass -File .\FolderSizeGUI.ps1

Or right-click the file in Explorer and choose Run with PowerShell.

On first launch it scans your user profile folder so the list is not
empty. From there:

- Click a folder in the left tree to scan it.
- Or type a path in the address bar and press Enter.
- Or use Browse to pick one from a dialog.
- Double-click any folder in the list to drill into it.
- Double-click any file to open it with its default program.


Keyboard shortcuts
------------------

  Enter (in path box)    Scan the typed path
  Backspace (in list)    Go to the parent folder
  Click Cancel           Stop the running scan


Column reference
----------------

  Type        DIR for folders, File for files
  Name        Folder or file name
  Size        Total recursive size for folders, file size for files
  Bytes       Raw byte count, used for sorting
  Items       File count inside a folder (recursive), or 1 for a file
  Percent     Share of the parent folder's total
  Modified    For files, the file's mtime. For folders, the most
              recent mtime of any contained file.


How it works
------------

- GUI: Windows Forms, so it runs on any current Windows install
  without extra setup.

- Layout: a SplitContainer holds the folder tree on the left and the
  path and list on the right. The splitter and a toggle button let you
  resize or hide the tree.

- Tree: populated lazily. Only the immediate children of each expanded
  node are enumerated, so huge drives do not block.

- Scan: runs in a separate PowerShell runspace. Results flow through a
  ConcurrentQueue into the UI, where a 100 ms timer drains the queue
  and appends rows. A cancel flag is checked between files so aborts
  are responsive.

- Folder mtime: computed as the maximum LastWriteTime of all files
  reached during the recursive size walk. Free to track since we are
  iterating anyway.

License
-------

Use it however you like.



<img width="1497" height="602" alt="image" src="https://github.com/user-attachments/assets/70ae3d40-228f-4235-bc8c-dae996e27187" />
