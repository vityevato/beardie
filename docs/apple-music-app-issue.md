## We opened feedback report "Music app AppleScript issue"

Feedback id: FB9043751 from 03.15.2021

Status: Open

Body:
```
-- run this AppleScript, and after that press and hold `option` key on keyboard
-- if to hold option key, Music app "thinks" that you use hotkey `opt + cursor right`, 
-- that leads to switch to next ALBUM!!!
-- it does not matter whether the Music app is frontmost or not

-- In other words, if the Music app executes the Apple Event 'hook'/''Next' and at this moment the modifier `option` key is pressed, then another action is executed, which is fundamentally wrong

delay 1
-- this delay needs that to press `option` key
tell application "Music"
	next track
end tell
```