on run argv
	set procName to item 1 of argv
	set x to (item 2 of argv) as real
	set y to (item 3 of argv) as real
	tell application "System Events"
		tell process procName
			set frontmost to true
			delay 0.2
		end tell
		click at {x, y}
	end tell
end run
