;PUTFILE "logo.bin", "logo", $ff3000, $ff3000
ORG $1c00
.start
lzsa2_get_byte = $a0
INCLUDE "lzsa2.s"
INCLUDE "quicdisc.s"
;INCLUDE "exo.s"
.end
SAVE "!BOOT",start,end,go
dummy_size = $500
CLEAR &0000,&FFFF
ORG 0
.dummy
skip dummy_size
SAVE "dummy", dummy, P%
;PUTFILE "logo.exo", "logoexo", 0, 0
PUTFILE "logo.lzsa2", "logolzs", 0, 0
PUTFILE "logo.bin", "logo", $ff4e00, $ff4e00
