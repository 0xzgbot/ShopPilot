on run argv
	set procName to item 1 of argv
	set keyStr to item 2 of argv
	set modStr to ""
	if (count of argv) > 2 then
		set modStr to item 3 of argv
	end if
	tell application "System Events"
		tell process procName
			set frontmost to true
			delay 0.2
			if modStr is "cmd" then
				keystroke keyStr using command down
			else if modStr is "shift" then
				keystroke keyStr using shift down
			else if modStr is "cmdshift" then
				keystroke keyStr using {command down, shift down}
			else
				keystroke keyStr
			end if
		end tell
	end tell
end run
