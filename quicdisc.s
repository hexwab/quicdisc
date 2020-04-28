\\ quicdisc.asm
\\ Generates quicdisc.ssd.
\\ Usage:
\\ *QUICDSC (loads and calls at &7A00 which initializes and auto-detects
\\ floppy controller). Supports 8271, BBC B 1770, BBC Master 1770.
\\ By default the track buffer is &6000 but you can change it before any read
\\ call by modifying the pointer at &70.
\\ Currently, all access is to drive 0 (or drive 2 for the upper side).
\\ A%=5:CALL&7A03
\\ Returns immediately; seek to track 5 in progress.
\\ R%=USR(&7A09) AND &FF
\\ Now R% contains 0 if the command is done, nonzero otherwise.
\\ Returns immediately; all of current track is being read into &6000.
\\ A%=0:CALL&7A06
\\ If you want to read a track on the upper side of the disc (i.e. drive 1),
\\ use A%=1 for the read.

get_crunched_byte = $a0
;fifo_len = fifo_len_copy - get_crunched_byte_copy + get_crunched_byte
;inptr = inptr_copy - get_crunched_byte_copy + get_crunched_byte
fifo_len = get_crunched_byte
inptr = get_crunched_byte+4
ZP = &b0

NMI = &0D00
OSBYTE = &FFF4

INTEL_CMD_DRIVE0 = &40
INTEL_CMD_READ_SECTORS = &13
INTEL_CMD_SEEK = &29
INTEL_CMD_READ_STATUS = &2C
INTEL_CMD_SPECIFY = &35
INTEL_CMD_SET_PARAM = &3A
INTEL_PARAM_SPINDOWN_LOADTIME = &0F
INTEL_PARAM_DRVOUT = &23
INTEL_DRVOUT_SELECT0 = &40
INTEL_DRVOUT_LOAD_HEAD = &08

WD_CMD_RESTORE = &00
WD_CMD_SEEK = &10
WD_CMD_READ_SECTOR_MUTI_SETTLE = &94

ZP_BUF_PTR = ZP+2
ZP_WD_BASE = ZP+4
ZP_WD_DRVCTRL = ZP+6
ZP_WD_SD_0_LOWER = ZP+8
ZP_WD_SD_0_UPPER = ZP+9
ZP_TRACK = ZP+10
buf = $400

.disc_begin
    \\ base + 3, seek
.seek
	jmp entry_not_set
.read_track
    \\ base + 6, read track
	jmp entry_not_set
.get_status
    \\ base + 9, get status
	jmp entry_not_set

.entry_not_set
	BRK

.disc_init
    \\ *FX 140,0, aka. *TAPE
	lda #$8c
	ldx #0
	ldy #0
	jsr OSBYTE

    \\ Detect 8271 vs. 1770 on model B.
    \\ On i8271, &FE84 - &FE87 all map to the same data register.
    \\ On wd1770, &FE85 is the track register and &FE86 the sector register.
    LDA #42
    STA &FE85
    LDA #43
    STA &FE86

    JSR wd_delay

    LDA &FE85
    CMP #43
    BEQ detected_intel
    CMP #42
    BEQ detected_wd_fe8x

    \\ Detect 1770 on Master.
    LDA #42
    STA &FE29

    JSR wd_delay

    LDA &FE29
    CMP #42
    BEQ detected_wd_fe2x
	brk
	brk
	equs "FDC?"
	brk

.detected_intel
    \\ Set up vectors.
    LDA #LO(intel_seek)
    STA seek + 1
    LDA #HI(intel_seek)
    STA seek + 2
    LDA #LO(intel_read_track)
    STA read_track + 1
    LDA #HI(intel_read_track)
    STA read_track + 2
    LDA #LO(intel_get_status)
    STA get_status + 1
    LDA #HI(intel_get_status)
    STA get_status + 2

    \\ Copy over and patch NMI routine.
    LDA #&84
    JSR copy_patch_nmi_routine

    \\ Disable automatic spindown. On my machine, the 8271 is super picky about
    \\ starting up again after it spins down, requiring a seek to track 0??
    \\ Also set seek time to 12ms, twice as fast as standard but still slow.
    LDA #INTEL_CMD_SET_PARAM
    JSR intel_do_cmd
    LDA #INTEL_PARAM_SPINDOWN_LOADTIME
    JSR intel_do_param
    \\ No auto unload, head load 16ms.
    LDA #&F8
    JSR intel_do_param
    JSR intel_wait_command_finish

    \\ Spin up and load head.
    LDA #0
    JSR intel_set_drvout

    RTS

.detected_wd_fe8x
    LDA #&84
    STA ZP_WD_BASE
    LDA #&80
    STA ZP_WD_DRVCTRL
    LDA #&09
    STA ZP_WD_SD_0_LOWER
    LDA #&0D
    STA ZP_WD_SD_0_UPPER
    JMP detected_wd_common

.detected_wd_fe2x
    LDA #&28
    STA ZP_WD_BASE
    LDA #&24
    STA ZP_WD_DRVCTRL
    LDA #&21
    STA ZP_WD_SD_0_LOWER
    LDA #&31
    STA ZP_WD_SD_0_UPPER
    JMP detected_wd_common

.detected_wd_common
    LDA #&FE
    STA ZP_WD_BASE + 1
    STA ZP_WD_DRVCTRL + 1

    \\ Set up vectors.
    LDA #LO(wd_seek)
    STA seek + 1
    LDA #HI(wd_seek)
    STA seek + 2
    LDA #LO(wd_read_track)
    STA read_track + 1
    LDA #HI(wd_read_track)
    STA read_track + 2
    LDA #LO(wd_get_status)
    STA get_status + 1
    LDA #HI(wd_get_status)
    STA get_status + 2

    \\ Copy over and patch NMI routine.
    LDA ZP_WD_BASE
    CLC
    ADC #3
    JSR copy_patch_nmi_routine

    RTS

.intel_set_drvout
    \\ A=0, lower side. A=1, upper side.
    \\ Set drvout including side. Upper side select is 0x20.
    PHA
    LDA #(INTEL_CMD_DRIVE0 + INTEL_CMD_SET_PARAM)
    JSR intel_do_cmd
    LDA #INTEL_PARAM_DRVOUT
    JSR intel_do_param
    PLA
    AND #&01
    ASL A
    ASL A
    ASL A
    ASL A
    ASL A
    ORA #INTEL_DRVOUT_SELECT0
    ORA #INTEL_DRVOUT_LOAD_HEAD
    JSR intel_do_param
    JSR intel_wait_command_finish
    RTS

.intel_seek
    STA ZP_TRACK

    JSR intel_wait_ready

    LDA #(INTEL_CMD_DRIVE0 + INTEL_CMD_SEEK)
    JSR intel_do_cmd
    LDA ZP_TRACK
    JSR intel_do_param
    RTS

.intel_read_track
    JSR intel_set_drvout
    JSR reset_buf_ptr

    JSR intel_wait_ready

    LDA #(INTEL_CMD_DRIVE0 + INTEL_CMD_READ_SECTORS)
    JSR intel_do_cmd
    \\ Track.
    LDA ZP_TRACK
    JSR intel_do_param
    \\ Start sector.
    LDA #0
    JSR intel_do_param
    \\ 10x 256 byte sectors.
    LDA #&2A
    JSR intel_do_param
    RTS

.intel_get_status
    \\ Return nonzero if busy.
    LDA &FE80
    AND #&80
    RTS

.intel_wait_ready
    LDA #(INTEL_CMD_DRIVE0 + INTEL_CMD_READ_STATUS)
    JSR intel_do_cmd
    JSR intel_wait_command_finish
    LDA &FE81
    \\ Check RDY0.
    AND #&04
    BEQ intel_wait_ready
    RTS

.intel_do_cmd
	sta $FE80
.intel_do_cmd_loop
	bit $FE80
	bvs intel_do_cmd_loop
	rts

.intel_do_param
	sta &FE81
	lda #$20
.intel_do_param_loop
	bit $FE80
	bne intel_do_param_loop
	rts

.intel_wait_command_finish
    bit &FE80
    bmi intel_wait_command_finish
    RTS

.wd_seek
    STA ZP_TRACK
    CMP #0
    BEQ wd_seek_to_0
    \\ Desired track goes in data register.
    LDY #3
    STA (ZP_WD_BASE),Y
    LDY #0
    LDA #WD_CMD_SEEK
    STA (ZP_WD_BASE),Y
    JMP wd_delay_and_rts
  .wd_seek_to_0
    \\ Command 0, no flags is retore to track 0 + spin up.
    LDY #0
    LDA #WD_CMD_RESTORE
    STA (ZP_WD_BASE),Y
.wd_delay_and_rts
    JSR wd_delay
    RTS

.wd_read_track
    JSR reset_buf_ptr

    \\ Set side.
    CMP #0
    BEQ wd_read_track_lower
    LDA ZP_WD_SD_0_UPPER
    JMP wd_read_track_set_side_done
  .wd_read_track_lower
    LDA ZP_WD_SD_0_LOWER
  .wd_read_track_set_side_done
    LDY #0
    STA (ZP_WD_DRVCTRL),Y

    \\ Start sector.
    LDY #2
    LDA #0
    STA (ZP_WD_BASE),Y
    \\ Command. Read, multiple sectors, spin up, head settle.
    LDY #0
    LDA #WD_CMD_READ_SECTOR_MUTI_SETTLE
    STA (ZP_WD_BASE),Y

    JMP wd_delay_and_rts

.wd_get_status
    \\ Return nonzero if busy.
    LDY #0
    LDA (ZP_WD_BASE),Y
    AND #&01
    RTS

.wd_delay
    \\ Longest delay we use is write command -> read busy bit, 48us.
    LDX #20
  .wd_delay_loop
    DEX
    BNE wd_delay_loop
    RTS

.reset_buf_ptr
	lda #0
	sta outptr-nmi_routine+NMI+1
	sta fifo_len+1
	rts

.nmi_routine
	sta atmp-nmi_routine+NMI+1
.datareg
	lda $fe00
.outptr
	sta buf
	inc outptr-nmi_routine+NMI+1
	inc fifo_len+1
	beq overflow
.atmp
	lda #$ee
	rti
.overflow
	lda #$40
	sta $d00
	brk
	brk
	equs "Overflow"
	brk
.nmi_routine_end

.copy_patch_nmi_routine
    \\ Patch the data register read.
	sta datareg+1

	ldx #(nmi_routine_end-nmi_routine-1)
.copy_nmi_loop
	lda nmi_routine, X
	sta NMI, X
	dex
	bpl copy_nmi_loop
	rts

.go
.load_track_with_decrunch
	sei
	jsr disc_init
	lda #1
	jsr seek
	ldx #get_crunched_byte_copy_end-get_crunched_byte_copy-1
.gcbcloop
	lda get_crunched_byte_copy,X
	sta get_crunched_byte,X
	dex
	bpl gcbcloop
	lda #22
	jsr $ffee
	lda #1
	jsr $ffee
.seek_wait
	jsr get_status
	bne seek_wait

IF 0
	ldx #0
.l0
	ldy #0
	.l1
	dey
	bne l1
	dex
	bne l0
ENDIF
	lda #0
	jsr read_track
IF 0 ; exo
	jsr decrunch
ELSE
	lda #<$4e00
	sta LZSA_DST_LO
	lda #>$4e00
	sta LZSA_DST_HI
	jmp lzsa2_unpack
ENDIF
.done
	jmp done
	
.quicdisc_end

.get_crunched_byte_copy
.fifo_len_copy
	lda #0
	beq fifo_len_copy
.inptr_copy
	lda buf
	inc inptr+1
	dec fifo_len+1
	rts
.get_crunched_byte_copy_end

;SAVE "QUICDSC", quicdisc_begin, quicdisc_end
	
