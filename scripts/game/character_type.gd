class_name CharacterType

## Shared identifiers for the two playable climber classes.

const STRONG := 0
const ELASTIC := 1


static func is_valid(value: int) -> bool:
	return value == STRONG or value == ELASTIC


static func label(value: int) -> String:
	return "ELASTIC" if value == ELASTIC else "STRONG"
