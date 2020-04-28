ORG $2000
.start

INCLUDE "lzsa2.s"
.go
	lda #<lzsa2_data
	sta LZSA_SRC_LO
	lda #>lzsa2_data
	sta LZSA_SRC_HI
	lda #<$4e00
	sta LZSA_DST_LO
	lda #>$4e00
	sta LZSA_DST_HI
	jmp lzsa2_unpack
	
.lzsa2_data
INCBIN "logo.lzsa2"
.end

SAVE "lzsa",start,end,go
