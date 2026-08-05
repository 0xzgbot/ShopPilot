on run argv
	set procName to item 1 of argv
	tell application "System Events"
		tell process procName
			set frontmost to true
			delay 0.2
			set out to ""
			try
				set win to window 1
				set els to entire contents of win
				repeat with el in els
					set r to ""
					try
						set r to role of el
					end try
					set d to ""
					try
						set d to description of el
					end try
					set t to ""
					try
						set t to title of el
					end try
					set v to ""
					try
						set v to (value of el) as text
					end try
					set p to ""
					try
						set posn to position of el
						set p to ((item 1 of posn) as text) & "," & ((item 2 of posn) as text)
					end try
					set s to ""
					try
						set sz to size of el
						set s to ((item 1 of sz) as text) & "x" & ((item 2 of sz) as text)
					end try
					set out to out & r & "|d=" & d & "|t=" & t & "|v=" & v & "|p=" & p & "|s=" & s & linefeed
				end repeat
				return out
			on error errMsg
				return "ERROR: " & errMsg
			end try
		end tell
	end tell
end run
