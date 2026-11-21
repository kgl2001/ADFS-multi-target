;*******************************************************************************
;* VFS_Far.asm - calls between the two halves of a split VFS                   *
;*                                                                             *
;* With VFS_SPLIT_LOWER this builds the filing system's half, with             *
;* VFS_SPLIT_UPPER the video/mouse half.  The two images go in sideways banks  *
;* x and x+1.  Nothing assumes a particular x: the lower half finds the upper  *
;* half at its own bank + 1 at reset (VFS_PartnerInit) and checks its title.   *
;*                                                                             *
;* A far call is made through a small stub in the calling image:              *
;*                                                                             *
;*        php / pha / lda #index / jmp FarCall                                 *
;*                                                                             *
;* FarCall stacks P, A, index, X, Y, the calling bank and a return address to  *
;* FarReturn, then jumps to FarSwitch.  FarSwitch and FarReturn sit at the     *
;* same address in both images (segment "vfs_far", fixed in the link script)   *
;* and are byte-for-byte the same, so execution carries on at the next         *
;* instruction after the bank is switched.  &F4 is always written before       *
;* ROMSEL, so an interrupt in between re-selects the bank we are switching to. *
;* All registers and flags go to the target unchanged, and all registers and   *
;* flags it returns come back to the caller unchanged.                          *
;*                                                                             *
;* The target runs with &F4 = its own bank, as it would if the MOS had called  *
;* it.  If it raises an error (BRK) the frame is simply abandoned, as it would *
;* be in an unsplit ROM.                                                        *
;*******************************************************************************

		.include "config.inc"
		.include "os.inc"
		.include "workspace.inc"
		.include "hardware.inc"

.ifndef VFS_MODELB
		.error "the split VFS is only built for the Model B (VFS_MODELB)"
.endif

VFS_0D96_PARTNER	= $0D96		; bank of the upper half, or bit 7 set if none
					; (&0D96 was VFS's, never used by 2.02)
OSRDRM			= $FFB9		; read byte from ROM Y at (&F6)

; index (byte offset into FarTable) of each routine callable across the split
; ...in the lower image, called from the upper image
FARL_CommandExecXY		= 0
FARL_GenerateError		= 2
FARL_ErrorEscapeACKReloadFSM	= 4
FARL_myCmosRead			= 6
FARL_L92CB			= 8
FARL_ReloadFSMandDIR		= 10
FARL_GenerateErrorAtB2		= 12
FARL_SCSI_Command_AXY		= 14		; Model B: video commands via the bounce buffer
; ...in the upper image, called from the lower image
FARU_ServiceCallsExtra		= 0
FARU_Serv9_extra		= 2
FARU_FSC3_STARCMD		= 4
FARU_swap7PWSP_373_N933		= 6
FARU_swapP373N933brkTurnIlaceOn	= 8
FARU_Serv27			= 10
FARU_TubeService		= 12		; Model B: Tube host (service &FE/&FF)

;===============================================================================
; Fixed part - must be identical in both images and at the same address
;===============================================================================
		.segment "vfs_far"

; A = bank to switch to.  Stack: RtL RtH bank0 Y0 X0 idx A0 P0 (top first)
FarSwitch:	sta	ZP_MOS_CURROM
		sta	ROMSEL				; --- now in the other image ---
		tsx
		ldy	$0106,X				; idx
		lda	FarTable+1,Y			; push target-1
		pha
		lda	FarTable,Y
		pha
		ldy	$0104,X				; Y = Y0
		lda	$0108,X				; P0
		pha
		lda	$0107,X				; A0
		pha
		lda	$0105,X				; X = X0
		tax
		pla					; A = A0
		plp					; P = P0
		rts					; into the target

; The target returns here, in its own image.
; Stack: bank0 Y0 X0 idx A0 P0 callerRet (top first)
FarReturn:	php
		pha
		txa
		pha
		tya
		pha					; Y1 X1 A1 P1 bank0 ...
		tsx
		lda	$0105,X				; calling bank
		sta	ZP_MOS_CURROM
		sta	ROMSEL				; --- back in the calling image ---
		lda	$0104,X				; move results over the frame:
		sta	$010A,X				; P1 -> P0
		lda	$0103,X
		sta	$0109,X				; A1 -> A0
		lda	$0102,X
		sta	$0108,X				; X1 -> idx
		lda	$0101,X
		sta	$0107,X				; Y1 -> X0
		txa					; drop the other six bytes
		clc
		adc	#6
		tax
		txs
		pla
		tay
		pla
		tax
		pla
		plp
		rts					; back to the caller

;-------------------------------------------------------------------------------
; FarCopyPage - copy 256 bytes between banks, switching bank for every byte.
; ($B2) = source, ($B4) = destination, $B6 = source bank, $B7 = destination
; bank.  Returns in the bank it was called from.  Corrupts A, X, Y.
;-------------------------------------------------------------------------------
FarCopyPage:	lda	ZP_MOS_CURROM
		pha
		ldy	#0
@lp:		lda	$B6
		sta	ZP_MOS_CURROM
		sta	ROMSEL
		lda	($B2),Y
		tax
		lda	$B7
		sta	ZP_MOS_CURROM
		sta	ROMSEL
		txa
		sta	($B4),Y
		iny
		bne	@lp
		pla
		sta	ZP_MOS_CURROM
		sta	ROMSEL
		rts

; Each image's own entry points (address-1).  Same address in both images,
; different contents.
FarTable:
.ifdef VFS_SPLIT_LOWER
		.word	CommandExecXY-1
		.word	GenerateError-1
		.word	ErrorEscapeACKReloadFSM-1
		.word	myCmosRead-1
		.word	L92CB-1
		.word	FarReloadFSMandDIR-1
		.word	GenerateErrorAtB2-1
		.word	SCSI_Command_AXY-1
		.word	0,0,0,0				; spare - keep both tables the same length
.endif
.ifdef VFS_SPLIT_UPPER
		.word	VFS_ServiceCallsExtra-1
		.word	VFS_Serv9_extra-1
		.word	VFS_FSC3_STARCMD-1
		.word	swap7PWSP_373_N933-1
		.word	swapP373N933brkTurnIlaceOn-1
		.word	VFSM_Serv27-1
  .ifdef VFS_TUBEHOST
		.word	VFSM_TubeService-1
  .else
		.word	0
  .endif
		.word	0,0,0,0,0
.endif

;===============================================================================
; Image-specific part
;===============================================================================
		.segment "vfs_far_code"

; Stack on entry: A0 P0 (top first), A = index of the routine in the other image
FarCall:	pha					; idx
		txa
		pha					; X0
		tya
		pha					; Y0
		lda	ZP_MOS_CURROM
		pha					; bank0
		lda	#>(FarReturn-1)
		pha
		lda	#<(FarReturn-1)
		pha
		lda	VFS_0D96_PARTNER		; upper bank
.ifdef VFS_SPLIT_UPPER
		sec
		sbc	#1				; lower bank = upper bank - 1
.endif
		jmp	FarSwitch

.macro FARSTUB name, index
name:		php
		pha
		lda	#index
		jmp	FarCall
.endmacro

;-------------------------------------------------------------------------------
.ifdef VFS_SPLIT_LOWER
;-------------------------------------------------------------------------------
		.export VFS_ServiceCallsExtra
		.export VFS_Serv9_extra
		.export VFS_FSC3_STARCMD
		.export swap7PWSP_373_N933
		.export swapP373N933brkTurnIlaceOn
		.export VFSM_Serv27
		.export VFS_PartnerInit
.ifdef VFS_MODELB
		.export VFS_ResetB
.endif
		.export VFS_0D96_PARTNER
		.export SCSI_Command_AXY_CkErr
		.exportzp SCSICMD_C8_VENDOR_FCMDRESULT
		.exportzp SCSICMD_1B_STARTSTOPUNIT
		.export VFS_N93A_SEARCHING_IN_PROGRESS
		.import L89D8
		.import GenerateErrorAtB2

SCSICMD_C8_VENDOR_FCMDRESULT	= $C8
SCSICMD_1B_STARTSTOPUNIT	= $1B
VFS_N93A_SEARCHING_IN_PROGRESS	= $093A		; must match VFS_Mouse.asm
WKSP_ADFS_215_CMDBUF		= WKSP_BASE + $0215

; Called on every service call.  Only *commands (4) and the 100Hz poll (&15)
; go to the upper half.
VFS_ServiceCallsExtra:
.ifdef VFS_TUBEHOST
		cmp	#$FE				; Tube post-init (&FE) / init (&FF)?
		bcc	@nottube
		bne	@tubeinit
		bit	VFS_0D96_PARTNER		; &FE comes after service 2
		bmi	@rts
		jmp	fu_TubeService
@tubeinit:	pha					; &FF comes before services 1 and 2,
		txa					; so find the upper half first
		pha
		tya
		pha
		jsr	VFS_PartnerInit
		pla
		tay
		pla
		tax
		pla
		bit	VFS_0D96_PARTNER
		bmi	@rts
		jmp	fu_TubeService
@nottube:
.endif
		bit	VFS_0D96_PARTNER
		bmi	@rts
		cmp	#SERVICE_04_UK_OSCLI
		beq	fu_ServiceCallsExtra
		cmp	#SERVICE_15_100Hz_POLL
		beq	fu_ServiceCallsExtra
@rts:		rts
		FARSTUB	fu_ServiceCallsExtra, FARU_ServiceCallsExtra

VFS_Serv9_extra:
		bit	VFS_0D96_PARTNER
		bmi	@rts
		jmp	fu_Serv9_extra
@rts:		rts
		FARSTUB	fu_Serv9_extra, FARU_Serv9_extra

; The upper half returns C=1 if it ran the command.  In the unsplit ROM it
; dropped this routine's return address instead; do that here.
VFS_FSC3_STARCMD:
		bit	VFS_0D96_PARTNER
		bmi	@rts
		jsr	fu_FSC3_STARCMD
		bcc	@rts
		pla
		pla
@rts:		rts
		FARSTUB	fu_FSC3_STARCMD, FARU_FSC3_STARCMD

swap7PWSP_373_N933:
		bit	VFS_0D96_PARTNER
		bmi	@rts
		jmp	fu_swap7PWSP_373_N933
@rts:		rts
		FARSTUB	fu_swap7PWSP_373_N933, FARU_swap7PWSP_373_N933

		FARSTUB	swapP373N933brkTurnIlaceOn, FARU_swapP373N933brkTurnIlaceOn
.ifdef VFS_TUBEHOST
		FARSTUB	fu_TubeService, FARU_TubeService
.endif
		FARSTUB	VFSM_Serv27, FARU_Serv27

; Reload the FSM and directory without raising an error (the upper half
; raises its own, from its own bank).
FarReloadFSMandDIR:
		jsr	L89D8
		rts

;-------------------------------------------------------------------------------
; VFS_PartnerInit - find the upper half at bank (this bank + 1) and give it this
; ROM's private workspace pointer.  Returns A = VFS_0D96_PARTNER, N set if the
; upper half is missing (then all video/mouse features are left out).
;-------------------------------------------------------------------------------
VFS_PartnerInit:
		lda	$F6				; OSRDRM uses &F6/&F7
		pha
		lda	$F7
		pha
		ldy	ZP_MOS_CURROM
		iny					; candidate = this bank + 1
		cpy	#16
		bcs	@none
		lda	#$80
		sta	$F7
		ldx	#UpperSigLen-1
@lp:		txa
		clc
		adc	#$09				; title starts at &8009
		sta	$F6
		txa
		pha
		tya
		pha
		jsr	OSRDRM
		sta	VFS_0D96_PARTNER		; scratch
		pla
		tay
		pla
		tax
		lda	VFS_0D96_PARTNER
		cmp	UpperSig,X
		bne	@none
		dex
		bpl	@lp
.ifdef VFS_MODELB
		lda	#VFS_UPPER_DF0			; found: its private pages are in its own bank
		sta	SYSVARS_DF0_PWSKPTAB,Y
.else
		ldx	ZP_MOS_CURROM			; found: share the private workspace
		lda	SYSVARS_DF0_PWSKPTAB,X
		sta	SYSVARS_DF0_PWSKPTAB+1,X
.endif
		tya
		bpl	@done				; always (bank 0-15)
@none:		lda	#$FF
@done:		sta	VFS_0D96_PARTNER
		pla
		sta	$F7
		pla
		sta	$F6
		lda	VFS_0D96_PARTNER
		rts

.ifdef VFS_MODELB
;-------------------------------------------------------------------------------
; VFS_ResetB - Model B: the reset work the Master does on service &27, called
; at the end of service 2 (which the MOS issues to every ROM on every reset).
; Y is preserved.
;-------------------------------------------------------------------------------
XBYTEV_BANK	= $0D9F + 5*3 + 2		; ROM number of the extended BYTEV

VFS_ResetB:	tya
		pha
		jsr	VFS_PartnerInit
		bmi	@noupper
		lda	BYTEV+1				; already hooked?  (some ROMs issue a
		cmp	#$FF				; reset service call twice; hooking
		bne	@hook				; again would make BYTEV loop)
		lda	BYTEV
		cmp	#$0F
		bne	@hook
		lda	XBYTEV_BANK
		cmp	VFS_0D96_PARTNER
		beq	@done
@hook:		jsr	VFSM_Serv27			; mouse, poll, Pi1MHz redirect (far call)
		jmp	@done
@noupper:
  .ifdef VFS_Pi1MHz_Redirect
		lda	$FC88				; Pi1MHz screen redirector on its own
		cmp	#$8E
		bne	@done
		lda	#2
		sta	$FC88
		jsr	$FD03
  .endif
@done:		pla
		tay
		ldx	ZP_MOS_CURROM
		rts
.endif

UpperSig:	.byte	"VFS Video+Mouse"
UpperSigLen	= * - UpperSig

;-------------------------------------------------------------------------------
; SCSI command helper used by the filing system itself (the upper half has its
; own copy in VFS_Mouse.asm).
;-------------------------------------------------------------------------------
SCSI_Command_AXY_CkErr:
		jsr	SCSI_Command_AXY
		beq	@rts
		jmp	GenerateError
@rts:		rts

SCSI_Command_AXY:
		stx	WKSP_ADFS_215_CMDBUF+1
		sty	WKSP_ADFS_215_CMDBUF+2
		ldx	#$FF
		stx	WKSP_ADFS_215_CMDBUF+3
		stx	WKSP_ADFS_215_CMDBUF+4
		sta	WKSP_ADFS_215_CMDBUF+5
		lda	#$00
		sta	WKSP_ADFS_215_CMDBUF
		ldy	#$04
@clp:		sta	WKSP_ADFS_215_CMDBUF+6,Y
		dey
		bpl	@clp
		inc	WKSP_ADFS_215_CMDBUF+9
		ldx	#<WKSP_ADFS_215_CMDBUF
		ldy	#>WKSP_ADFS_215_CMDBUF
		jmp	CommandExecXY

.endif ; VFS_SPLIT_LOWER

;-------------------------------------------------------------------------------
.ifdef VFS_SPLIT_UPPER
;-------------------------------------------------------------------------------
		.export CommandExecXY
		.export GenerateError
		.export ErrorEscapeACKReloadFSM
		.export myCmosRead
		.export L92CB
		.export ReloadFSMandDIR_ThenBRK
		.export GenerateErrorNoSuff

		FARSTUB	CommandExecXY, FARL_CommandExecXY
		FARSTUB	GenerateError, FARL_GenerateError
		FARSTUB	ErrorEscapeACKReloadFSM, FARL_ErrorEscapeACKReloadFSM
		FARSTUB	myCmosRead, FARL_myCmosRead
		FARSTUB	L92CB, FARL_L92CB
		FARSTUB	fl_ReloadFSMandDIR, FARL_ReloadFSMandDIR
		FARSTUB	fl_GenerateErrorAtB2, FARL_GenerateErrorAtB2
.ifdef VFS_MODELB
		FARSTUB	fl_SCSI_Command_AXY, FARL_SCSI_Command_AXY
.endif

; JSR ReloadFSMandDIR_ThenBRK / .byte errnum, "message", 0
ReloadFSMandDIR_ThenBRK:
		jsr	fl_ReloadFSMandDIR
						; fall into GenerateErrorNoSuff

; JSR GenerateErrorNoSuff / .byte errnum, "message", 0
; The message is in this bank, so copy it to &0100 here and let the filing
; system's error code (which adds "on channel n" if needed) take it from there.
GenerateErrorNoSuff:
		pla
		sta	$B2
		pla
		sta	$B3
		ldy	#$00
@lp:		iny
		lda	($B2),Y
		sta	$0100,Y
		bne	@lp
		lda	#$00
		sta	$B2
		lda	#$01
		sta	$B3				; ($B2)+1 = &0101: copies onto itself
		ldx	#$00				; no suffix
		jmp	fl_GenerateErrorAtB2

.ifdef VFS_MODELB
;-------------------------------------------------------------------------------
; SCSI_Command_AXY - Model B.  The video commands build F-codes in their text
; buffer in this bank, which the filing system half's SCSI code cannot see.
; If XY is that buffer, copy it to the lower half's buffer (WKSP_BASE+&E00,
; the Master's &CE00), run the command there, and copy the reply back.  Any
; other XY (*RESET passes whatever is in X and Y; it moves no data) is passed
; straight through.  Returns A = result with N/Z set from it, as before.
;-------------------------------------------------------------------------------
		.export SCSI_Command_AXY
SCSI_BOUNCE	= WKSP_BASE + $E00

SCSI_Command_AXY:
		pha					; cmd
		txa
		pha					; X
		tya
		pha					; Y
		lda	$B2				; FarCopyPage uses $B2-$B7
		pha
		lda	$B3
		pha
		lda	$B4
		pha
		lda	$B5
		pha
		lda	$B6
		pha
		lda	$B7
		pha
		; frame: $0101,X=B7 .. $0106,X=B2, $0107,X=Y, $0108,X=X, $0109,X=cmd
		cpx	#<WKSP_VFS_E00_TXTBUF
		bne	@direct
		cpy	#>WKSP_VFS_E00_TXTBUF
		bne	@direct
		lda	#<WKSP_VFS_E00_TXTBUF		; copy the text buffer down
		sta	$B2
		lda	#>WKSP_VFS_E00_TXTBUF
		sta	$B3
		lda	#<SCSI_BOUNCE
		sta	$B4
		lda	#>SCSI_BOUNCE
		sta	$B5
		lda	ZP_MOS_CURROM
		sta	$B6
		jsr	LowerBank
		sta	$B7
		jsr	FarCopyPage
		tsx
		lda	$0109,X				; cmd
		ldx	#<SCSI_BOUNCE
		ldy	#>SCSI_BOUNCE
		jsr	fl_SCSI_Command_AXY
		pha					; result
		lda	#<SCSI_BOUNCE			; copy the buffer (and any reply) back
		sta	$B2
		lda	#>SCSI_BOUNCE
		sta	$B3
		lda	#<WKSP_VFS_E00_TXTBUF
		sta	$B4
		lda	#>WKSP_VFS_E00_TXTBUF
		sta	$B5
		jsr	LowerBank
		sta	$B6
		lda	ZP_MOS_CURROM
		sta	$B7
		jsr	FarCopyPage
		pla
		jmp	@exit
@direct:	tsx
		lda	$0108,X				; X
		sta	$B2
		ldy	$0107,X				; Y
		lda	$0109,X				; cmd
		ldx	$B2
		jsr	fl_SCSI_Command_AXY
@exit:		tsx
		sta	$0109,X				; result over cmd
		pla
		sta	$B7
		pla
		sta	$B6
		pla
		sta	$B5
		pla
		sta	$B4
		pla
		sta	$B3
		pla
		sta	$B2
		pla
		tay
		pla
		tax
		pla					; A = result, N/Z set
		rts

LowerBank:	lda	VFS_0D96_PARTNER
		sec
		sbc	#1
		rts
.endif

.endif ; VFS_SPLIT_UPPER
