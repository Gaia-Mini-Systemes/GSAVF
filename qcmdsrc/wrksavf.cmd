CMD        PROMPT('Gérer les *SAVF')
PARM       KWD(SAVFILE) TYPE(*CHAR) LEN(10) SPCVAL((*ALL)) MIN(1) PROMPT('Nom du fichier')
PARM       KWD(SAVFILE_L) TYPE(*CHAR) LEN(10) MIN(1) PROMPT('Bibliothèque')
DEP        CTL(&SAVFILE *EQ *ALL) PARM((&SAVFILE_L *NE *LIBL))
