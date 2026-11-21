.ifndef __CONFIG_INC__
__CONFIG_INC__:

; Build file for Master ADFS with SCSI drivers
; For a Model B with an Integra-B and Pi1MHz - split into two 16K images,
; plain 6502 code, workspace in the sideways RAM banks (no Hazel; VFS does not raise PAGE).
; Upper image (video commands, mouse, trackerball): install in sideways bank x+1.
; --------------------------------------------
;
; Built from the Master ADFS/VFS code on purpose: see the notes at the top of
; bbcVFS_Pi1MHz_lo.inc for why, and how it is adapted for the Model B.

TARGETOS	:=	3		; 3=Master
HD_SCSI		:=	1		; VFS SCSI drivers
HD_SCSI_VFS	:=	1
HD_SCSI_VFS_NO_INVERT := 1 ; Stop normal VFS inverting of data.
VFS_TRIM_REDUNDANT :=1 ; Remove code that is unreachable
VFS_BUG_FIX :=  1 		; fix bugs in VFS
VFS_OPTIMISE := 1		; optimisations  in VFS
VFS_Pi1MHz_Mouse_Redirect := 1 ; Enable mouse to appear on the Pi
VFS_Pi1MHz_Redirect :=1 ; enable screen redirector
VFS_Pi1MHz :=1

CMOS_PER_ROM_BASE = 30  ; fixed CMOS ram address VFS originally has 20

HDDBASE=$FC40		; VFS controller
VERBASE=$202		; Pi1MHz VFS: 2.00 + the Pi's mouse redirect, VDU redirect, USB mouse

MOUSE_REDIRECT = $FCAC ; Address of Pi mouse redirector

VFS_SPLIT_UPPER := 1		; see VFS_Far.asm
VFS_MODELB := 1			; Model B + IBOS: see workspace.inc, VFS_Far.asm

; Optional parts (Model B).  Comment a line out to leave that part out; the
; two configs must agree on VFS_TUBEHOST.
VFS_TUBEHOST := 1		; Tube host code, for machines with no DNFS/DFS to
				; provide it (about 870 bytes of the upper ROM)
;VFS_GXR := 1			; rectangle-fill PLOTs (PLOT &60-&67) for use
				; without a GXR ROM; hooks WRCHV (upper ROM only)

.endif
