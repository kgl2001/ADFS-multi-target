;*******************************************************************************
;* VFS_Gxr.asm - minimal Graphics Extension for the split VFS on a Model B     *
;*                                                                             *
;* The Master's MOS has the GXR built in, and Domesday uses some of its PLOT   *
;* codes - in particular filled rectangles (PLOT &60-&67) to clear areas of    *
;* the screen.  MOS 1.20 hands unknown PLOT codes to VDUV, where nothing picks *
;* them up unless a GXR ROM is fitted.  This adds rectangle fill only.         *
;*                                                                             *
;* MOS 1.20 has already moved the new point into the graphics cursor by the    *
;* time VDUV is called, so the previous point (the rectangle's other corner)   *
;* is lost.  Like the GXR, we therefore also sit on WRCHV, and take a copy of  *
;* the graphics cursor just before the last byte of a VDU 25 for &60-&67.      *
;*                                                                             *
;* Drawing uses the MOS's own clipped horizontal line routine (the one CLG and *
;* triangle fill use), so colours, GCOL actions and the graphics window all    *
;* behave as for any other MOS plot.  Model B MOS 1.20 only.                   *
;*                                                                             *
;* IntegraB shadow modes: IBOS sets MEMSEL while the VDU drivers run, but the  *
;* extended vector that pages us in writes our bank number to ROMSEL, which    *
;* clears it.  Both handlers put it back if their caller had it: before        *
;* drawing, and before passing a character on down the WRCHV chain.           *
;*******************************************************************************
		.include "config.inc"
		.include "os.inc"
		.include "hardware.inc"

.ifdef VFS_GXR					; else this file assembles to nothing
		.export VFSM_GxrHook

; MOS 1.20 locations
MOS_VDU25	= $C98C		; VDU 25 handler: VDU_JUMPVEC while a PLOT is queued
MOS_CLR_LINE	= $D6A6		; fill line between points at &300+X and &300+Y
VDU_QSIZE	= $026A		; -(VDU parameters still to come)
VDU_JUMPVEC	= $035D
VDU_PIX_BYTE	= $0361		; pixels per byte - 1, 0 if no graphics
VDU_PLOTTYPE	= $031F		; PLOT k
VDU_G_WIN_B	= $0302		; graphics window bottom (internal)
VDU_G_WIN_T	= $0306		; graphics window top (internal)
VDU_G_LAST	= $0314		; previous graphics cursor (internal)
VDU_G_CURS	= $0324		; graphics cursor (internal)
VDU_PT_L	= $0328		; scratch points for MOS_CLR_LINE (as CLG uses)
VDU_PT_R	= $032C
ROMSEL_MEMSEL	= $80

WRCHV_IX	= ($020E - $0200) / 2 * 3	; &15
VDUV_IX		= ($0226 - $0200) / 2 * 3	; &39

; Workspace in this (upper) bank's own sideways RAM, &BB00
GX_WS		= $BB00
GX_OLDWRCH	= GX_WS + 0	; 2
GX_OLDVDUV	= GX_WS + 2	; 2
GX_P1		= GX_WS + 4	; 4: previous graphics cursor, internal
GX_YMAX		= GX_WS + 8	; 2
GX_ROWS		= GX_WS + 10	; 2

		.segment "vfs_gxr"

;-------------------------------------------------------------------------------
; Hook WRCHV and VDUV through the extended vectors (called from VFSM_Serv27,
; running in this bank, with ($A8) -> extended vector table).  Skips a vector
; that already points at us, so a second call can't make a loop.
;-------------------------------------------------------------------------------
.macro GX_HOOK vec, idx, handler, save
		.local do, skip
		lda	vec+1
		cmp	#$FF
		bne	do
		lda	vec
		cmp	#idx
		bne	do
		ldy	#idx+2
		lda	($A8),y
		cmp	ZP_MOS_CURROM
		beq	skip
do:		lda	vec
		sta	save
		lda	vec+1
		sta	save+1
		ldy	#idx
		lda	#<handler
		sta	($A8),y
		iny
		lda	#>handler
		sta	($A8),y
		iny
		lda	ZP_MOS_CURROM
		sta	($A8),y
		lda	#idx
		sta	vec
		lda	#$FF
		sta	vec+1
skip:
.endmacro

VFSM_GxrHook:
		php
		sei
		GX_HOOK	WRCHV, WRCHV_IX, GxrWrch, GX_OLDWRCH
		GX_HOOK	VDUV, VDUV_IX, GxrVdu, GX_OLDVDUV
		plp
		rts

;-------------------------------------------------------------------------------
; WRCHV: keep the graphics cursor before a rectangle PLOT is carried out
;-------------------------------------------------------------------------------
GxrWrch:	pha
		lda	VDU_QSIZE
		cmp	#$FF				; last parameter?
		bne	@chain
		lda	VDU_JUMPVEC
		cmp	#<MOS_VDU25
		bne	@chain
		lda	VDU_JUMPVEC+1
		cmp	#>MOS_VDU25
		bne	@chain
		lda	VDU_PLOTTYPE
		and	#$F8
		cmp	#$60
		bne	@chain
		lda	VDU_G_CURS
		sta	GX_P1
		lda	VDU_G_CURS+1
		sta	GX_P1+1
		lda	VDU_G_CURS+2
		sta	GX_P1+2
		lda	VDU_G_CURS+3
		sta	GX_P1+3
@chain:		tsx					; Being paged in by the extended
		lda	$0104,X				; vector cleared MEMSEL; if our
		bpl	@go				; caller (e.g. IBOS's WRCHV in a
		lda	ZP_MOS_CURROM			; shadow mode) had it set, put it
		ora	#ROMSEL_MEMSEL			; back before the VDU drivers run.
		sta	ZP_MOS_CURROM
		sta	ROMSEL
@go:		pla
		jmp	(GX_OLDWRCH)

;-------------------------------------------------------------------------------
; VDUV: C=0, A=PLOT code for an unknown PLOT; C=1 for VDU 23,2-31
;-------------------------------------------------------------------------------
GxrVdu:		bcs	@chain
		pha
		and	#$F8
		cmp	#$60
		bne	@notus
		lda	VDU_PIX_BYTE			; text-only mode: MOS hasn't
		bne	Rectangle			; touched the cursor
@notus:		pla
		clc
@chain:		jmp	(GX_OLDVDUV)

; Stack: plot code, then the extended vector's return address and the
; caller's ROMSEL value.
Rectangle:	tsx
		lda	$0104,X				; caller's ROMSEL copy
		bpl	@nomem
		lda	ZP_MOS_CURROM
		ora	#ROMSEL_MEMSEL
		sta	ZP_MOS_CURROM
		sta	ROMSEL
@nomem:
		ldx	#3				; the previous point becomes
@last:		lda	GX_P1,X				; the last graphics cursor,
		sta	VDU_G_LAST,X			; as for any other PLOT
		dex
		bpl	@last

		pla
		and	#$03				; 0: move only
		bne	@draw
		rts

@draw:		; left/right x into the two scratch points
		sec
		lda	GX_P1
		sbc	VDU_G_CURS
		lda	GX_P1+1
		sbc	VDU_G_CURS+1
		bvc	:+
		eor	#$80
:		bmi	@p1left
		lda	VDU_G_CURS			; P2 (the cursor) is left
		sta	VDU_PT_L
		lda	VDU_G_CURS+1
		sta	VDU_PT_L+1
		lda	GX_P1
		sta	VDU_PT_R
		lda	GX_P1+1
		sta	VDU_PT_R+1
		jmp	@xdone
@p1left:	lda	GX_P1				; P1 is left
		sta	VDU_PT_L
		lda	GX_P1+1
		sta	VDU_PT_L+1
		lda	VDU_G_CURS
		sta	VDU_PT_R
		lda	VDU_G_CURS+1
		sta	VDU_PT_R+1
@xdone:
		; ymin -> both points, ymax -> GX_YMAX
		sec
		lda	GX_P1+2
		sbc	VDU_G_CURS+2
		lda	GX_P1+3
		sbc	VDU_G_CURS+3
		bvc	:+
		eor	#$80
:		bmi	@p1low
		lda	VDU_G_CURS+2
		ldx	VDU_G_CURS+3
		jsr	SetYmin
		lda	GX_P1+2
		ldx	GX_P1+3
		jmp	@setymax
@p1low:		lda	GX_P1+2
		ldx	GX_P1+3
		jsr	SetYmin
		lda	VDU_G_CURS+2
		ldx	VDU_G_CURS+3
@setymax:	sta	GX_YMAX
		stx	GX_YMAX+1

		; clip to the graphics window
		sec
		lda	VDU_PT_L+2
		sbc	VDU_G_WIN_B
		lda	VDU_PT_L+3
		sbc	VDU_G_WIN_B+1
		bvc	:+
		eor	#$80
:		bpl	@botok
		lda	VDU_G_WIN_B
		ldx	VDU_G_WIN_B+1
		jsr	SetYmin
@botok:		sec
		lda	VDU_G_WIN_T
		sbc	GX_YMAX
		lda	VDU_G_WIN_T+1
		sbc	GX_YMAX+1
		bvc	:+
		eor	#$80
:		bpl	@topok
		lda	VDU_G_WIN_T
		sta	GX_YMAX
		lda	VDU_G_WIN_T+1
		sta	GX_YMAX+1
@topok:
		; rows = ymax - ymin + 1, nothing if ymax < ymin
		sec
		lda	GX_YMAX
		sbc	VDU_PT_L+2
		sta	GX_ROWS
		lda	GX_YMAX+1
		sbc	VDU_PT_L+3
		sta	GX_ROWS+1
		bvc	:+
		eor	#$80
:		bmi	@done
		inc	GX_ROWS
		bne	@row
		inc	GX_ROWS+1

@row:		ldx	#<(VDU_PT_R - $0300)
		ldy	#<(VDU_PT_L - $0300)
		jsr	MOS_CLR_LINE
		inc	VDU_PT_L+2
		bne	:+
		inc	VDU_PT_L+3
:		inc	VDU_PT_R+2
		bne	:+
		inc	VDU_PT_R+3
:		lda	GX_ROWS
		bne	:+
		dec	GX_ROWS+1
:		dec	GX_ROWS
		lda	GX_ROWS
		ora	GX_ROWS+1
		bne	@row
@done:		rts

SetYmin:	sta	VDU_PT_L+2
		sta	VDU_PT_R+2
		stx	VDU_PT_L+3
		stx	VDU_PT_R+3
		rts

.endif ; VFS_GXR
