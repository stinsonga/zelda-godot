class_name NesRandom
extends RefCounted
## Z_07 NMI: carry is bit 1 of byte 0 XOR byte 1, then ROR 13 bytes.
var bytes := PackedByteArray([0xA5, 0x37, 0xC1, 0x68, 0x92, 0x4B, 0xD6, 0x19, 0xF0, 0x73, 0x2D, 0x86, 0x5A])

func advance() -> void:
	var carry := ((bytes[0] ^ bytes[1]) >> 1) & 1
	for i in range(13):
		var next := bytes[i] & 1
		bytes[i] = (bytes[i] >> 1) | (carry << 7)
		carry = next

func at(index: int) -> int:
	return bytes[posmod(index, 13)]
