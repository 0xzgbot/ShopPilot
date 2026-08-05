on run argv
	set procName to item 1 of argv
	set idx to (item 2 of argv) as integer
	set newVal to item 3 of argv
	tell application "System Events"
		tell process procName
			set frontmost to true
			set els to entire contents of window 1
			set el to item idx of els
			set value of el to newVal
		end tell
	end tell
end run
