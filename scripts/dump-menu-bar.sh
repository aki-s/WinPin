#!/bin/sh
set -eu

osascript <<'APPLESCRIPT'
on joinLines(lineItems)
    set previousDelimiters to AppleScript's text item delimiters
    set AppleScript's text item delimiters to linefeed
    set joinedText to lineItems as text
    set AppleScript's text item delimiters to previousDelimiters
    return joinedText
end joinLines

on safeText(valueText)
    if valueText is missing value then return ""
    return valueText as text
end safeText

on safeListText(valueList)
    try
        set previousDelimiters to AppleScript's text item delimiters
        set AppleScript's text item delimiters to ","
        set joinedText to valueList as text
        set AppleScript's text item delimiters to previousDelimiters
        return joinedText
    on error
        return ""
    end try
end safeListText

on dumpMenuBarItems(processName)
    tell application "System Events"
        if not (exists process processName) then
            return processName & ": process not found"
        end if

        set outputLines to {processName & ":"}
        tell process processName
            try
                set barCount to count of menu bars
            on error errMsg
                return processName & ": cannot read menu bars: " & errMsg
            end try

            repeat with barIndex from 1 to barCount
                set end of outputLines to "  menu bar " & barIndex & ":"
                try
                    set itemCount to count of menu bar items of menu bar barIndex
                    if itemCount is 0 then
                        set end of outputLines to "    (no menu bar items)"
                    end if

                    repeat with itemIndex from 1 to itemCount
                        set itemRef to menu bar item itemIndex of menu bar barIndex
                        set itemName to ""
                        set itemDescription to ""
                        set itemPosition to ""
                        set itemSize to ""

                        try
                            set itemName to my safeText(name of itemRef)
                        end try
                        try
                            set itemDescription to my safeText(description of itemRef)
                        end try
                        try
                            set itemPosition to my safeListText(position of itemRef)
                        end try
                        try
                            set itemSize to my safeListText(size of itemRef)
                        end try

                        set end of outputLines to "    [" & itemIndex & "] name=\"" & itemName & "\" description=\"" & itemDescription & "\" position=" & itemPosition & " size=" & itemSize
                    end repeat
                on error errMsg
                    set end of outputLines to "    cannot read items: " & errMsg
                end try
            end repeat
        end tell
        return my joinLines(outputLines)
    end tell
end dumpMenuBarItems

on dumpMenuBarExtras()
    tell application "System Events"
        set outputLines to {"menu bar extra candidates:"}
        repeat with processRef in application processes
            set processName to name of processRef
            try
                set barCount to count of menu bars of processRef
                if barCount > 1 then
                    repeat with barIndex from 2 to barCount
                        set itemCount to count of menu bar items of menu bar barIndex of processRef
                        repeat with itemIndex from 1 to itemCount
                            set itemRef to menu bar item itemIndex of menu bar barIndex of processRef
                            set itemName to ""
                            set itemDescription to ""
                            set itemPosition to ""
                            set itemSize to ""

                            try
                                set itemName to my safeText(name of itemRef)
                            end try
                            try
                                set itemDescription to my safeText(description of itemRef)
                            end try
                            try
                                set itemPosition to my safeListText(position of itemRef)
                            end try
                            try
                                set itemSize to my safeListText(size of itemRef)
                            end try

                            set end of outputLines to "  " & processName & " menuBar=" & barIndex & " item=" & itemIndex & " name=\"" & itemName & "\" description=\"" & itemDescription & "\" position=" & itemPosition & " size=" & itemSize
                        end repeat
                    end repeat
                end if
            end try
        end repeat
        return my joinLines(outputLines)
    end tell
end dumpMenuBarExtras

on dumpProcessesWithMenuBars()
    tell application "System Events"
        set outputLines to {"processes with menu bars:"}
        repeat with processRef in application processes
            set processName to name of processRef
            try
                set barCount to count of menu bars of processRef
                if barCount > 0 then
                    set end of outputLines to "  " & processName & " menuBars=" & barCount
                end if
            end try
        end repeat
        return my joinLines(outputLines)
    end tell
end dumpProcessesWithMenuBars

set sections to {}
try
    set end of sections to dumpMenuBarItems("SystemUIServer")
    set end of sections to dumpMenuBarItems("WinPin")
    set end of sections to dumpMenuBarExtras()
    set end of sections to dumpProcessesWithMenuBars()
    return joinLines(sections)
on error errMsg number errNo
    return "Cannot dump menu bar items via System Events. Grant Accessibility permission to the terminal app running this script, then retry." & linefeed & "AppleScript error " & errNo & ": " & errMsg
end try
APPLESCRIPT
