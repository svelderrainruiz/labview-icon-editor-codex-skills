Unicode True
SetCompressor /SOLID lzma
RequestExecutionLevel user
SilentInstall silent
ShowInstDetails nevershow
Name "LVIE Codex Skill Layer"

!ifndef OUT_FILE
  !define OUT_FILE "lvie-codex-skill-layer-installer.exe"
!endif

!ifndef PAYLOAD_DIR
  !define PAYLOAD_DIR "."
!endif

!ifndef INSTALL_ROOT
  !define INSTALL_ROOT "C:\Users\Public\lvie\codex-skill-layer\current"
!endif

OutFile "${OUT_FILE}"
InstallDir "${INSTALL_ROOT}"
Page instfiles

Section "Install"
  SetOutPath "$INSTDIR"
  File /r "${PAYLOAD_DIR}\*"
SectionEnd
