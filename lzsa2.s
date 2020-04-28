; ***************************************************************************
; ***************************************************************************
;
; lzsa2_6502.s
;
; NMOS 6502 decompressor for data stored in Emmanuel Marty's LZSA2 format.
;
; This code is written for the ACME assembler.
;
; Optional code is presented for two minor 6502 optimizations that break
; compatibility with the current LZSA2 format standard.
;
; The code is 241 bytes for the small version, and 267 bytes for the normal.
;
; Copyright John Brandwood 2019.
;
; Distributed under the Boost Software License, Version 1.0.
; (See accompanying file LICENSE_1_0.txt or copy at
;  http://www.boost.org/LICENSE_1_0.txt)
;
; ***************************************************************************
; ***************************************************************************

	; Macro to read a byte from the compressed source data.
	MACRO LZSA_GET_SRC
                        jsr     lzsa2_get_byte
	ENDMACRO

                ; Macro to speed up reading 50% of nibbles.
                ; This seems to save very few cycles compared to the
                ; increase in code size, and it isn't recommended.
LZSA_SLOW_NIBL  =       0

IF (LZSA_SLOW_NIBL)
MACRO LZSA_GET_NIBL
                        jsr     lzsa2_get_nibble        ; Always call a function.
ENDMACRO
ELSE
MACRO LZSA_GET_NIBL
                        lsr     <lzsa_nibflg            ; Is there a nibble waiting?
                        lda     <lzsa_nibble            ; Extract the lo-nibble.
                        bcs     skip
                        jsr     lzsa2_new_nibble        ; Extract the hi-nibble.
.skip                   ora     #$F0
ENDMACRO
ENDIF


; ***************************************************************************
; ***************************************************************************
;
; Data usage is last 11 bytes of zero-page.
;

lzsa_cmdbuf     =       $80                     ; 1 byte.
lzsa_nibflg     =       $81                     ; 1 byte.
lzsa_nibble     =       $83                     ; 1 byte.
lzsa_offset     =       $85                     ; 1 word.
lzsa_winptr     =       $87                     ; 1 word.
;lzsa_srcptr     =       $89                     ; 1 word.
lzsa_dstptr     =       $89                     ; 1 word.

lzsa_length     =       lzsa_winptr             ; 1 word.

;LZSA_SRC_LO     =       $89
;LZSA_SRC_HI     =       $8A
LZSA_DST_LO     =       $89
LZSA_DST_HI     =       $8A

; ***************************************************************************
; ***************************************************************************
;
; lzsa2_unpack - Decompress data stored in Emmanuel Marty's LZSA2 format.
;
; Args: lzsa_srcptr = ptr to compessed data
; Args: lzsa_dstptr = ptr to output buffer
; Uses: lots!
;

;DECOMPRESS_LZSA2_FAST:
.lzsa2_unpack   ldy     #0                      ; Initialize source index.
                sty     <lzsa_nibflg            ; Initialize nibble buffer.

                ; Copy bytes from compressed source data.

.cp_length      ldx     #$00                    ; Hi-byte of length or offset.

                LZSA_GET_SRC

                sta     <lzsa_cmdbuf            ; Preserve this for later.
                and     #$18                    ; Extract literal length.
                beq     lz_offset              ; Skip directly to match?

                lsr     A                      ; Get 2-bit literal length.
                lsr     A
                lsr     A
                cmp     #$03                    ; Extended length?
                bne     got_cp_len

                jsr     get_length             ; X=0 table index for literals.

.got_cp_len     cmp     #0                      ; Check the lo-byte of length.
                beq     put_cp_len

                inx                             ; Increment # of pages to copy.

.put_cp_len     stx     <lzsa_length
                tax

.cp_page        LZSA_GET_SRC
                sta     (lzsa_dstptr),y
.skip1          inc     <lzsa_dstptr + 0
                bne     skip2
                inc     <lzsa_dstptr + 1
.skip2 

                dex
                bne     cp_page
                dec     <lzsa_length            ; Any full pages left to copy?
                bne     cp_page

                ; ================================
                ; xyz  
                ; 00z  5-bit offset
                ; 01z  9-bit offset
                ; 10z  13-bit offset
                ; 110  16-bit offset
                ; 111  repeat offset

.lz_offset      lda     <lzsa_cmdbuf
                asl     A
                bcs     get_13_16_rep
                asl     A
                bcs     get_9_bits

.get_5_bits     dex                             ; X=$FF
.get_13_bits    asl     A
                php
                LZSA_GET_NIBL                  ; Always returns with CS.
                plp
                rol     A                       ; Shift into position, set C.
                eor     #$01
                cpx     #$00                    ; X=$FF for a 5-bit offset.
                bne     set_offset
                sbc     #2                      ; Subtract 512 because 13-bit
                                                ; offset starts at $FE00.
                bne     get_low8x              ; Always NZ from previous SBC.

.get_9_bits     dex                             ; X=$FF if CS, X=$FE if CC.
                asl     A
                bcc     get_low8
                dex
                bcs     get_low8               ; Always VS from previous BIT.

.get_13_16_rep  asl     A
                bcc     get_13_bits            ; Shares code with 5-bit path.

.get_16_rep     bmi     lz_length              ; Repeat previous offset.

                ; Copy bytes from decompressed window.
                ; N.B. X=0 is expected and guaranteed when we get here.
.get_16_bits    jsr     lzsa2_get_byte          ; Get hi-byte of offset.
.get_low8x      tax
.get_low8
                LZSA_GET_SRC                   ; Get lo-byte of offset.

.set_offset     stx     <lzsa_offset + 1        ; Save new offset.
                sta     <lzsa_offset + 0

.lz_length      ldx     #$00                    ; Hi-byte of length.

                lda     <lzsa_cmdbuf
                and     #$07
                clc
                adc     #$02
                cmp     #$09                    ; Extended length?
                bne     got_lz_len

                inx
                jsr     get_length             ; X=1 table index for match.

.got_lz_len     eor     #$FF                    ; Negate the lo-byte of length
                tay                             ; and check for zero.
                iny
                beq     calc_lz_addr
                eor     #$FF

                inx                             ; Increment # of pages to copy.

                clc                             ; Calc destination for partial
                adc     <lzsa_dstptr + 0        ; page.
                sta     <lzsa_dstptr + 0
                bcs     calc_lz_addr
                dec     <lzsa_dstptr + 1

.calc_lz_addr   clc                             ; Calc address of match.
                lda     <lzsa_dstptr + 0        ; N.B. Offset is negative!
                adc     <lzsa_offset + 0
                sta     <lzsa_winptr + 0
                lda     <lzsa_dstptr + 1
                adc     <lzsa_offset + 1
                sta     <lzsa_winptr + 1

.lz_page        lda     (lzsa_winptr),y
                sta     (lzsa_dstptr),y
                iny
                bne     lz_page
                inc     <lzsa_winptr + 1
                inc     <lzsa_dstptr + 1
                dex                             ; Any full pages left to copy?
                bne     lz_page

                jmp     cp_length              ; Loop around to the beginning.

                ; Lookup tables to differentiate literal and match lengths.

.nibl_len_tbl   equb    3 + $10                 ; 0+3 (for literal).
                equb    9 + $10                 ; 2+7 (for match).

.byte_len_tbl:  equb    18 - 1                  ; 0+3+15 - CS (for literal).
                equb    24 - 1                  ; 2+7+15 - CS (for match).

                ; Get 16-bit length in X:A register pair.

.get_length     LZSA_GET_NIBL
                cmp     #$FF                    ; Extended length?
                bcs     byte_length
                adc     nibl_len_tbl,x         ; Always CC from previous CMP.

.got_length     ldx     #$00                    ; Set hi-byte of 4 & 8 bit
                rts                             ; lengths.

.byte_length    jsr     lzsa2_get_byte          ; So rare, this can be slow!
                adc     byte_len_tbl,x         ; Always CS from previous CMP.
                bcc     got_length
                beq     finished

.word_length    jsr     lzsa2_get_byte          ; So rare, this can be slow!
                pha
                jsr     lzsa2_get_byte          ; So rare, this can be slow!
                tax
                pla
                rts
IF 0
.lzsa2_get_byte 
                lda     (lzsa_srcptr),y         ; Subroutine version for when
                inc     <lzsa_srcptr + 0        ; inlining isn't advantageous.
                beq     lzsa2_next_page
                rts
.lzsa2_next_page
                inc     <lzsa_srcptr + 1        ; Inc & test for bank overflow.
                rts
ENDIF
.finished       pla                             ; Decompression completed, pop
                pla                             ; return address.
                rts

                ; Get a nibble value from compressed data in A.

IF (LZSA_SLOW_NIBL)
.lzsa2_get_nibble
                lsr     <lzsa_nibflg            ; Is there a nibble waiting?
                lda     <lzsa_nibble            ; Extract the lo-nibble.
                bcs     got_nibble

                inc     <lzsa_nibflg            ; Reset the flag.
                LZSA_GET_SRC

                sta     <lzsa_nibble            ; Preserve for next time.
                lsr     A                       ; Extract the hi-nibble.
                lsr     A
                lsr     A
                lsr     A

.got_nibble     ora     #$F0
                rts

ELSE
.lzsa2_new_nibble
                inc     <lzsa_nibflg            ; Reset the flag.
                LZSA_GET_SRC

                sta     <lzsa_nibble            ; Preserve for next time.
                lsr     A                       ; Extract the hi-nibble.
                lsr     A
                lsr     A
                lsr     A
                rts

ENDIF
