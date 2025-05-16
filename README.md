# Aegisub Automatic Line Break Script

## Description

This Lua script for Aegisub automates the process of adding line breaks (`\N`) to subtitle lines. It aims to keep lines at a specified maximum character length (defaulting to 30 visible characters) without splitting words. The script intelligently ignores Aegisub's formatting tags (e.g., `{\b1}`, `{\fad(100,200)}`) when counting characters to determine line length.

A key feature is that it will **skip processing for any line that already contains a manual line break (`\N`)**, preventing unwanted additional breaks or modifications to already formatted lines.

## Features

* **Automatic Line Breaking:** Inserts `\N` to wrap lines that exceed the defined character limit.
* **Character Limit:** Lines are broken to stay within a configurable maximum number of visible characters (default: 30).
* **Whole Word Preservation:** Ensures that words are not split across lines. Breaks occur at spaces.
* **Ignores Formatting Tags:** Calculates line length based on visible characters only, ignoring formatting tags.
* **Skips Pre-Formatted Lines:** Does not modify lines that already contain manual line breaks (`\N`).
* **UTF-8 Aware:** Utilizes Aegisub's `unicode` module (with fallbacks) for accurate character length counting in UTF-8 encoded text.
* **Undoable:** Operations performed by the script can be undone in Aegisub (Ctrl+Z / Cmd+Z).
* **Progress Bar:** Shows progress when processing multiple lines.

## Installation

1.  **Save the Script:** Copy the Lua code provided into a plain text file and save it with a `.lua` extension (e.g., `auto_line_break.lua`).
2.  **Locate Aegisub's Script Folder:**
    * The standard location is the `automation/autoload/` subfolder within your Aegisub application directory or user profile directory.
    * Refer to the Aegisub manual under "Automation -> Lua -> Script loading paths" for the exact path on your operating system.
3.  **Place the Script:** Move or copy your saved `.lua` file into this `automation/autoload/` folder.
4.  **Load the Script:**
    * Restart Aegisub.
    * Alternatively, you can try reloading scripts from Aegisub's "Automation" menu (if available in your version, e.g., "Rescan Autoload Dir" or "Reload Scripts").

The script should then appear in Aegisub's "Automation" menu under the name defined in the script (e.g., "Automatischer Zeilenumbruch V2 (Ignoriert bestehende Umbrüche)" or similar, depending on the `script_name` variable in the `.lua` file).

## How to Use

1.  **Open your subtitle file** in Aegisub.
2.  **Select the lines** in the subtitle grid that you want to process. You can select one or multiple lines.
3.  Go to the **"Automation" menu** in Aegisub.
4.  **Click on the script's name** (e.g., "Automatischer Zeilenumbruch V2 (Ignoriert bestehende Umbrüche)").
5.  The script will process the selected lines and add line breaks according to the rules.

## Configuration

The main configuration option is the maximum number of characters per line. You can change this by editing the script file:

* Open the `.lua` script file in a text editor.
* Find the line:
    ```lua
    local MAX_CHARS_PER_LINE = 30
    ```
* Change `30` to your desired maximum character length.
* Save the file. You may need to reload scripts or restart Aegisub for the change to take effect.

## Dependencies

* This script is designed for the Lua environment provided by **Aegisub**.
* It attempts to use Aegisub's `unicode` module for accurate UTF-8 character counting. If this module is not available, it has fallbacks to try the standard `utf8` library or, as a last resort, byte-length counting (which may be inaccurate for non-ASCII text).

## Notes and Limitations

* **Complex/Nested Tags:** While the script is designed to handle common ASS formatting tags correctly, extremely complex or unusually nested tags might lead to unexpected behavior in rare cases.
* **Single Long Words:** If a single word (without spaces) is longer than `MAX_CHARS_PER_LINE`, that word will remain on a line by itself and will exceed the character limit, as the script does not split words.
* **Log Messages:** The script contains commented-out `aegisub.log(...)` lines. If you are troubleshooting or want more verbose output on what the script is doing (e.g., which lines are skipped), you can uncomment these lines. Log messages appear in Aegisub's log window (usually accessible via "View" -> "Log..." or similar).

---

Feel free to adapt the author/version information if you make further modifications!
