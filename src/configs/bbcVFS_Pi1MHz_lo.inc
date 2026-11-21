.ifndef __CONFIG_INC__
__CONFIG_INC__:

; Build file for Master ADFS with SCSI drivers
; For a Model B with an Integra-B and Pi1MHz - split into two 16K images,
; plain 6502 code, workspace in the sideways RAM banks (no Hazel; VFS does not raise PAGE).
; Lower image (filing system): install in sideways bank x, with the upper image in x+1.
; --------------------------------------------
;
; Why build the Model B version from the Master ADFS (TARGETOS 3)?
; ---------------------------------------------------------------
; It may look odd to start from the Master code (written for the 65C12) and
; patch it for a Model B, rather than starting from the Model B ADFS
; (TARGETOS 1).  It was done deliberately:
;
;  - VFS only ever existed on the Master ADFS, and that is what Domesday was
;    developed and tested against.  This keeps the behaviour the same as a
;    real Master AIV system.  VFS on the Model B ADFS has never existed: a
;    trial build needed several Master-only routines stubbed out to link.
;  - The Master code already keeps its workspace at fixed addresses outside
;    main memory (Hazel), independent of PAGE.  Moving that into the two
;    sideways RAM banks was mostly a change of base address (workspace.inc).
;    The Model B ADFS claims workspace from &E00 upwards and raises PAGE.
;  - The Master code keeps its settings in CMOS (OSBYTE &A1/&A2), which IBOS
;    provides, so VFS's *CONFIGURE/*STATUS options work as on a Master.  The
;    Model B ADFS has no equivalent; it relies on the keyboard links.
;  - The Model B version shares its source with the Master Pi1MHz VFS, so
;    fixes to one reach the other, and the Master builds stay byte-identical.
;
; What it costs: the Master code is about 230 bytes bigger than the Model B
; ADFS with the same VFS code (Hazel/reset service calls, ACCCON shadow
; handling, CMOS settings, spool-safe printing).  That only matters for a
; single 16K ROM; split over two banks there is plenty of room.
;
; How the Master code is adapted (all under VFS_MODELB unless noted):
;  - 65C12-only instructions have plain 6502 equivalents wherever USE65C12
;    is not defined (this config doesn't define it).
;  - Hazel workspace -> &B000-&BFFF of the lower bank, &BB00-&BFFF of the
;    upper bank (workspace.inc, the link scripts).
;  - ACCCON (&FE34, the Master's shadow control; RAMSEL on the IntegraB) ->
;    IntegraB MEMSEL (ROMSEL bit 7) for screen transfers and the pointer.
;  - The Master's 100Hz poll (service &15) and reset service (&27) don't
;    exist on a Model B: the poll is driven from the system VIA timer
;    interrupt, and the reset work is done at service 2 (VFS_ResetB).
;  - Boot command without the Master's -VFS- prefix.
;  - Optional Tube host code (VFS_TUBEHOST) and rectangle PLOTs (VFS_GXR).


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

VFS_SPLIT_LOWER := 1		; see VFS_Far.asm
VFS_MODELB := 1			; Model B + IBOS: see workspace.inc, VFS_Far.asm

; Optional parts (Model B).  Comment a line out to leave that part out; the
; two configs must agree on VFS_TUBEHOST.
VFS_TUBEHOST := 1		; Tube host code, for machines with no DNFS/DFS to
				; provide it (about 870 bytes of the upper ROM)
;VFS_GXR := 1			; rectangle-fill PLOTs (PLOT &60-&67) for use
				; without a GXR ROM; hooks WRCHV (upper ROM only)

.endif