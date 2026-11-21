		.include "config.inc"
		.include "os.inc"
		.include "workspace.inc"
		.include "hardware.inc"
;*******************************************************************************
;* VFS_Upper.asm - ROM header and reset code for the upper (video/mouse) half  *
;* of a split VFS.  See VFS_Far.asm.                                           *
;*                                                                             *
;* The upper half has no service handling of its own: the filing system half  *
;* (one bank below) calls into it.  The header is only there so that *ROMS     *
;* lists it and so that the lower half can recognise it.                       *
;*******************************************************************************

		.export VFSM_Serv27
		.importzp SCSICMD_C8_VENDOR_FCMDRESULT
.ifdef VFS_GXR
		.import VFSM_GxrHook
.endif

.ifndef VFS_BUG_FIX
		.error "split VFS needs VFS_BUG_FIX (Serv27 exit)"
.endif

		.segment "rom_header"
		.byte	0,0,0				; no language entry
		jmp	UpperService			; service entry
		.byte	$82				; service ROM, 6502 code
		.byte	<(UpperCopyright-1-$8000)	; offset of the 0 before "(C)"
		.byte	>VERBASE
		.byte	"VFS Video+Mouse",0		; VFS_PartnerInit checks this title
		.byte	'0'+(>VERBASE),'.','0'+((<VERBASE)>>4),'0'+((<VERBASE)&$F)
.ifdef VFS_MODELB
		.byte	"ib"				; Model B + IntegraB build
.endif
		.byte	0
UpperCopyright:	.byte	"(C)1986 Acorn",0

		.segment "vfs_upper"
UpperService:	rts					; all service calls go to the lower half

VFS_N923_flag = $0923

;*******************************************************************************
;* VFSM_Serv27 - reset: mouse/trackerball vectors, 100Hz poll, Pi1MHz redirect *
;* Moved from VFS_Serv27 in adfs.asm; the lower half far-calls it, so &F4 is   *
;* this bank and the extended vectors point here.                              *
;*******************************************************************************
VFSM_Serv27:
        	php                                     ; 9363 08                       .
        	sei                                     ; 9364 78                       x
.ifdef USE65C12
        	stz     VFS_0D95_20Hz_CTDN              ; 9365 9C 95 0D                 ...
.else
		lda	#$00
		sta	VFS_0D95_20Hz_CTDN
.endif
						; (stz &0D96 removed: &0D96 now holds the partner bank)
.ifdef USE65C12
        	stz     VFS_0D92_FLAG_POLL100           ; 936B 9C 92 0D                 ...
.else
		lda	#$00
		sta	VFS_0D92_FLAG_POLL100
.endif
        	lda     #$FF                            ; 936E A9 FF                    ..
        	sta     VFS_0D93_CTDN_SEARCH + 1        ; 9370 8D 94 0D                 ...
        	jsr     PreserveZpAndPage9              ; 9373 20 28 B2                  (.
        	lda     #OSBYTE_16_INCPOLL              ; 9376 A9 16                    ..
        	sta     VFS_N923_flag                          ; 9378 8D 23 09                 .#.
        	jsr     OSBYTE                          ; 937B 20 F4 FF                  ..
        	lda     OSDEFVEC_PTR                    ; 937E AD B7 FF                 ...
        	sta     $A8                             ; 9381 85 A8                    ..
        	lda     OSDEFVEC_PTR+1                  ; 9383 AD B8 FF                 ...
        	sta     $A9                             ; 9386 85 A9                    ..
        	ldy     #$05                            ; 9388 A0 05                    ..
VFS_L938A:  	lda     ($A8),y                         ; 938A B1 A8                    ..
        	cmp     USERV,y                         ; 938C D9 00 02                 ...
        	bne     VFS_L9399                       ; 938F D0 08                    ..
        	dey                                     ; 9391 88                       .
        	cpy		#$03

        	bne     VFS_L938A                       ; 9394 D0 F4                    ..
.ifdef USE65C12
        	stz     VFS_N923_flag                    ; 9396 9C 23 09                 .#.
.else
		lda	#$00
		sta	VFS_N923_flag
.endif
VFS_L9399:
  			lda     #OSBYTE_A8_ADDR_EXTVEC          ; 9399 A9 A8                    ..
        	ldx     #$00                            ; 939B A2 00                    ..
        	ldy     #$FF                            ; 939D A0 FF                    ..
        	jsr     OSBYTE                          ; 939F 20 F4 FF                  ..
        	stx     $A8                             ; 93A2 86 A8                    ..
        	sty     $A9                             ; 93A4 84 A9                    ..
.ifndef VFS_TRIM_REDUNDANT
        	stx     $091B                           ; 93A6 8E 1B 09                 ...
        	sty     $091C                           ; 93A9 8C 1C 09                 ...
.endif
        	lda     BYTEV                           ; 93AC AD 0A 02                 ...
        	sta     VFS_OLD_BYTEV                   ; 93AF 8D 97 0D                 ...
        	lda     BYTEV+1                         ; 93B2 AD 0B 02                 ...
        	sta     VFS_OLD_BYTEV+1                 ; 93B5 8D 98 0D                 ...

        	ldy     #$0F                            ; 93B8 A0 0F                    ..
        	sty     BYTEV                           ; 93BA 8C 0A 02                 ...
        	ldx     #$FF                            ; 93BD A2 FF                    ..
        	stx     BYTEV+1                         ; 93BF 8E 0B 02                 ...

.ifndef VFS_TRIM_REDUNDANT
        	lda     ($A8),y                         ; 93C2 B1 A8                    ..
        	sta     $091D                           ; 93C4 8D 1D 09                 ...
.endif
        	lda     #<OSBYTE_Extended_Vectorcode    ; 93C7 A9 B6                    ..
        	sta     ($A8),y                         ; 93C9 91 A8                    ..
        	iny                                     ; 93CB C8                       .

.ifndef VFS_TRIM_REDUNDANT
        	lda     ($A8),y                         ; 93CC B1 A8                    ..
        	sta     $091E                           ; 93CE 8D 1E 09                 ...
.endif
        	lda     #>OSBYTE_Extended_Vectorcode    ; 93D1 A9 B4                    ..
        	sta     ($A8),y                         ; 93D3 91 A8                    ..
        	iny                                     ; 93D5 C8                       .
.ifndef VFS_TRIM_REDUNDANT
        	lda     ($A8),y                         ; 93D6 B1 A8                    ..
        	sta     $091F                           ; 93D8 8D 1F 09                 ...
.endif
        	lda     $F4                             ; 93DB A5 F4                    ..
        	sta     ($A8),y                         ; 93DD 91 A8                    ..
.ifdef VFS_GXR
		jsr	VFSM_GxrHook			; Model B: rectangle PLOTs (VFS_Gxr.asm)
.endif
        	lda     VFS_N923_flag                   ; 93DF AD 23 09                 .#.
.ifndef VFS_BUG_FIX
        	bne     VFS_L9420                       ; 93E2 D0 3C                    .<   ; This branch surely leaves the stack un balanced BUG ??? and doesn't restore ZP etc
.else
			bne 	VFS_serv27_exit
.endif
        	lda     IRQ1V                           ; 93E4 AD 04 02                 ...
        	sta     VFS_D9D_OLD_IRQ1V               ; 93E7 8D 9D 0D                 ...
        	lda     IRQ1V+1                         ; 93EA AD 05 02                 ...
        	sta     VFS_D9D_OLD_IRQ1V+1             ; 93ED 8D 9E 0D                 ...

			; Store JSR &FF06:RTI  ( Extended_IRQ1_Vector )
			lda     #$20                            ; 93F0 A9 20                    .
        	sta     $0D99                           ; 93F2 8D 99 0D                 ...
			ldy     #$06                            ; 93F5 A0 06                    ..
        	sty     $0D9A                           ; 93F7 8C 9A 0D                 ...
			lda     #$FF                            ; 93FA A9 FF                    ..
        	sta     $0D9B                           ; 93FC 8D 9B 0D                 ...
			lda     #$40                            ; 93FF A9 40                    .@
        	sta     $0D9C                           ; 9401 8D 9C 0D                 ...
			; Store ptr to 0D99
			lda     #$99                            ; 9404 A9 99                    ..
        	sta     IRQ1V                           ; 9406 8D 04 02                 ...
        	lda     #$0D                            ; 9409 A9 0D                    ..
        	sta     IRQ1V+1                         ; 940B 8D 05 02                 ...

        	lda     #<Extended_IRQ1_Vector          ; 940E A9 4F                    .O
        	sta     ($A8),y                         ; 9410 91 A8                    ..
        	iny                                     ; 9412 C8                       .
        	lda     #>Extended_IRQ1_Vector          ; 9413 A9 B5                    ..
        	sta     ($A8),y                         ; 9415 91 A8                    ..
        	iny                                     ; 9417 C8                       .
        	lda     $F4                             ; 9418 A5 F4                    ..
        	sta     ($A8),y                         ; 941A 91 A8                    ..
.ifdef VFS_Pi1MHz_Redirect
			LDA		$FC88			; check if Pi1MHz exists
			CMP		#$8E
			BNE     noPi1MHzDetected
			LDA     #2				; select Screen redirector
			STA     $FC88
			JSR	 	$FD03			; call the Screen redirector without text
noPi1MHzDetected:
.endif

.ifdef VFS_BUG_FIX
VFS_serv27_exit:
.endif

        	jsr     RestoreZpAndPage9               ; 941C 20 E3 B1                  ..
        	plp                                     ; 941F 28                       (
VFS_L9420:
		rts
