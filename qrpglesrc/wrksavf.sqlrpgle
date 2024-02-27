**free

//*--------------------------------------------------------------------------*
//*                                                                          *
//* Cette commande permet d'afficher et de gérer les SAVF d'une bibliothèque *
//*                                                                          *
//* Création: Gaia Le:08/02/2024                                             *
//* https://www.gaia.fr/                                                     *
//*                                                                          *
//*--------------------------------------------------------------------------*

  CTL-OPT DFTACTGRP(*NO);

  DCL-F WRKSAVFE   WORKSTN SFILE(sfl01:cle01) INDDS(Ds_Ind);

  DCL-PI *N;
    SAVFILE     Char(10);
    SAVFILE_L Char(10);
  END-PI;

  DCL-DS DS_Ind len(99);
    Ind_Sortie        ind pos(3);
    Ind_InviteF4      ind pos(4);
    Ind_Reaffichage   ind pos(5);
    Ind_Filtre        ind pos(7);
    Ind_Annuler       ind pos(12);
    Ind_Cacher_Opt01  ind pos(33);
    Ind_PosCurs_Ok    ind pos(34);
    Ind_SFLCLR        ind pos(40);
    Ind_SFLDSPCTL     ind pos(41);
    Ind_SFLDSP        ind pos(42);
    Ind_SFLEnd        ind pos(43);
    Ind_HideNameSort  ind pos(50);
    Ind_HideTypeSort  ind pos(51);
    Ind_HideFilter    ind pos(52);
    Ind_HideDatTim    ind pos(53);
  END-DS;

  DCL-S sqlstm       Char(1024);
  DCL-S Titre        Char(35);
  DCL-S result       Char(45);
  DCL-S TYPE_SORT    Char(7);
  DCL-S SqlForCursor Char(4096);
  DCL-S MonSQL       Char(4096);
  DCL-S CmdExec      Char(4096);
  DCL-S NB           Int(5);
  DCL-S cle01        Int(5);
  DCL-S Count_Lock   Int(5);
  DCL-S OBJLIB       Char(10);
  DCL-S Sortie       Ind;
  DCL-S Actualiser   Ind inz('1');
  DCL-S SAVFILE_SV   Like(SAVFILE);
  DCL-S SAVFILE_L_SV Like(SAVFILE_L);
  DCL-S Err_Bib      Ind;
  DCL-S Err_SAVFILE  Ind;

  // Prototypage pour programme qcmdexc
  DCL-PR Cmd     EXTPGM('QCMDEXC');
    PR_CmdStr    CHAR(4096) CONST;
    PR_CmdStrLen PACKED(15 : 5) CONST;
  END-PR;
  // Prototypage pour F4
  DCL-PR  Touche_F4 EXTPGM('TOUCHE_F4');
    Sqlstm   char(1024);
    Titre    char(35);
    Result   char(45);
  END-PR ;


    // initialisation des options de compile sql
    EXEC SQL
      SET OPTION NAMING = *SYS,
                 COMMIT = *NONE,
                 USRPRF = *USER,
              DYNUSRPRF = *USER,
                 DATFMT = *ISO,
              CLOSQLCSR = *ENDMOD;


  //Si le paramètre SAVF est a *ALL, appel a F4
  If %trim(%upper(SAVFILE)) = '*ALL';
    TrtF4_SAVF();
  EndIf;

  //Corps du programme
  Dow Not Sortie;
    If Actualiser;
       Init_SFL();
       Load_SFL();
       Actualiser = *Off;
    EndIf;
  Display_SFL();
  EndDo;

    // fin de programme
    EXEC SQL
      CLOSE Curs01;

  *Inlr = *On;


  //
  // Initialisation
  //
  DCL-PROC Init_SFL;
    num01 = 1;
    cle01 = 0;
    Ind_SFLCLR = *On;
    ERR_BIB = *Off;
    ERR_SAVFILE = *Off;
   // CLEAR ERRORMSG;

  //contrôle existence de la bibliotheque
  EXEC SQL
    SELECT count(*) INTO :NB
      FROM TABLE(qsys2.object_statistics(:SAVFILE_L, '*LIB'));

    If NB <> 1 or sqlcode <> 0;
      Err_Bib = *On;
      ERRORMSG = 'Bibliotheque inconnue';
    EndIf;

  //contrôle existence du fichier dans la bibliotheque selectionnée
  EXEC SQL
    SELECT count(*) INTO :NB
      FROM qsys2.savf_info
      WHERE save_file_library = :SAVFILE_L
      AND save_file = :SAVFILE;

    If (NB <> 1 Or sqlcode <> 0) and not ERR_BIB ;
      Err_SAVFILE = *On;
      ERRORMSG = 'Le SAVF n''existe pas dans la bibliotheque selectionnée';
    EndIf;
    If ERR_SAVFILE Or ERR_BIB;

    Return;
  ENDIF;

    Opt01 = ' ';
    //Gestion affichage des filtres
    If NAME_SORT = '' Or NAME_SORT = '%%';
     Ind_HideNameSort = *on;
    Else;
     Ind_HideNameSort = *off;
    EndIf;
    If TYPE_SORT = '' Or TYPE_SORT = '%%';
     Ind_HideTypeSort = *on;
    Else;
     Ind_HideTypeSort = *off;
    EndIf;
    If Ind_HideNameSort and Ind_HideTypeSort;
     Ind_HideFilter = *on;
    Else;
     Ind_HideFilter = *off;
    EndIf;
    write ctl01;
    Ind_SFLCLR = *Off;
    If SAVFILE = '*ALL';
       //Affichages des options de sélection
       TrtF4_SAVF();
    EndIf;
    // Verification si Objet verrouillé
    EXEC SQL
      SELECT count(*) INTO :Count_Lock
      FROM qsys2.object_lock_info
      WHERE OBJECT_NAME = :SAVFILE
      AND OBJECT_SCHEMA = :SAVFILE_L;

    If Count_Lock = 0;
      // Traitement du curseur
      EXEC SQL
        CLOSE Curs01;
      //Mise en place des options pour les filtres
      If NAME_SORT = '';
        NAME_SORT = '%%';
      Endif;
      If TYPE_SORT = '';
        TYPE_SORT = '%%';
      Endif;

      //Requête de chargement sous fichier conditionnée
      MonSQL = 'SELECT ' +
         'IfNull(object_name, ''''), ' +
         'IfNull(object_type, ''''), ' +
         'IfNull(object_attribute, ''''), ' +
         'IfNull(library_name, ''''), ' +
         'IfNull(text_description, ''''), ' +
         'IfNull(object_owner, ''''), ' +
         'Lpad(CASE WHEN object_size between 1000 and 999999' +
         ' THEN object_size/1000 concat '' Ko''' +
         ' WHEN object_size between 1000000 and 999999999' +
         ' THEN object_size/1000000 concat '' Mo''' +
         ' WHEN object_size > 999999999' +
         ' THEN object_size/1000000000 concat '' Go''' +
         ' ELSE VARCHAR(object_size)' +
         ' END , 8, '' '')' +
         ' FROM qsys2.save_file_objects' +
         ' WHERE SAVE_FILE LIKE ''' + %trim(SAVFILE)+
         ''' AND SAVE_FILE_LIBRARY = ''' + %trim(SAVFILE_L) +
         ''' AND OBJECT_TYPE LIKE ''' + %trim(TYPE_SORT) +
         ''' AND OBJECT_NAME LIKE REPLACE('''+%trim(NAME_SORT)+
         ''', ''*'', ''%'')';

    EXEC SQL
     PREPARE SqlForCursor FROM :MonSQL;

    EXEC SQL
     DECLARE curs01 CURSOR FOR SqlForCursor;

    EXEC SQL
     OPEN curs01;
    //Si objet verrouillé, chargement du sous fichier impossible
    Else;
      ERRORMSG = 'Objet verrouillé, affichage impossible';
    EndIf;
  END-PROC;


  //
  // Chargement
  //
  DCL-PROC Load_SFL;
    Ind_poscurs_ok =*off;
   DoU sqlcode <> 0;
    EXEC SQL
      FETCH FROM curs01
      INTO :NOM_OBJ, :TYPE, :ATR_OBJ, :BIB_OBJ, :TEXTE, :PRO_OBJ, :TAI_OBJ;

     If sqlcode <> 0;
       Leave ;
     EndIf;
     Cle01 = Cle01 + 1;
     If TYPE = '*LIB';
       Ind_cacher_opt01 = *On;
     Else;
       Ind_cacher_opt01 = *Off;
     EndIf;
     If not Ind_poscurs_ok and not Ind_cacher_opt01 ;
       Ind_poscurs_ok=*on;
     Else;
       Ind_poscurs_ok = *off;
     EndIf;
     Write sfl01 ;
   EndDo;
  END-PROC;


  //
  // Display
  //
  DCL-PROC Display_SFL;
    Ind_SFLDSPCTL = *On;
    Ind_SFLEnd = *On;
    If Cle01 > 0;
    Ind_SFLDSP = *On;
    Else;
    Ind_SFLDSP = *Off;
    EndIf;
    // Reqête affichage des infos du SAVF
    EXEC SQL
      SELECT date(save_timestamp), time(save_timestamp), Objects_saved
      INTO :SAV_DAT, :SAV_TIM, :NBR_OBJ
      FROM qsys2.savf_info
      WHERE save_file_library = :SAVFILE_L
      AND save_file = :SAVFILE;
    If sqlcode <> 0;
      NBR_OBJ = '0';
      Ind_HideDatTim = *On;
    Else;
      Ind_HideDatTim = *Off;
    EndIf;

    SAVFILE_SV = SAVFILE;
    SAVFILE_L_SV = SAVFILE_L;

    Write fmt01;
    Exfmt ctl01;
    ERRORMSG = '';
      // Traitement des fonctions
      Select;

        // F3 sortie
        When Ind_Sortie;
          Sortie = *On;

        // F4 Sélection dans liste
        When Ind_InviteF4 = *On;
          If zone = 'SAVFILE';
            TrtF4_SAVF();
          Else;
            ERRORMSG = 'Zone non gérée par la touche F4';
          EndIf;

        // F5 réafficher
        When Ind_Reaffichage ;
          TYPE_SORT = '';
          NAME_SORT = '';
          Actualiser = *On;

        // F7 gestion des filtres de tri
        When Ind_Filtre = *On;
          If NAME_SORT = '%%';
            NAME_SORT = '';
          Endif;
          If TYPE_SORT = '%%';
            TYPE_SORT = '';
          Endif;
        Exfmt TRIPARTYPE;
          If Ind_InviteF4;
            If zone = 'TYPE_SORT';
              sqlstm = 'SELECT DISTINCT object_type FROM TABLE ' +
              '(qsys2.save_file_objects(SAVE_FILE => ''' + %trim(SAVFILE) + ''', ' +
              'SAVE_FILE_LIBRARY => ''' + %trim(SAVFILE_L) + '''))';
              titre = 'Liste des Types';
              Touche_F4(sqlstm : titre : result);
              If result <> *blank and not Ind_Annuler;
                Actualiser = *On;
                TYPE_SORT = result;
              EndIf;
            Else;
              ERRORMSG = 'Zone non gérée par la touche F4';
            EndIf;
          EndIf;
          Actualiser = *On;

        // Si l'utilisateur a saisi une nouvelle bibliothèque et/ou un nouveau SAVF
        When SAVFILE_SV <> SAVFILE Or SAVFILE_L_SV <> SAVFILE_L;
          Actualiser = *On;
        Other;
          // Traitement des options
          Traitement();
      EndSL;

  END-PROC;


  //
  // Traitement des options
  //
  DCL-PROC Traitement;
    If Cle01 > 0;
   //   Dou %eof;
      ReadC Sfl01;
        If Not %eof;
          Select;
            // Option de restauration de la sélection
            When Opt01 = '1';
    CmdExec = '? RSTOBJ OBJ(' + %trim(NOM_OBJ) + ')' +
              ' SAVLIB(' + %trim(BIB_OBJ) + ')' +
              ' DEV(*SAVF)' +
              ' OBJTYPE(' + %trim(TYPE) + ')' +
              ' SAVF(' + %trim(SAVFILE_L) + '/' + %trim(SAVFILE) + ')' +
              ' RSTLIB(' + %trim(BIB_OBJ) + ')';
    Monitor;
              Exec_Cmd();
        ERRORMSG = %trim(NOM_OBJ) + ' de type ' + %trim(TYPE) +
         ' restauré' ;
    On-Error;
      EXEC SQL
        SELECT OBJLIB INTO :OBJLIB
        FROM TABLE(qsys2.object_statistics(
          OBJECT_SCHEMA => '*ALL',
          OBJTYPELIST => trim(:TYPE),
          OBJECT_NAME => trim(:NOM_OBJ) ))
        WHERE change_timestamp > NOW() -10 SECONDS
          ORDER BY change_timestamp DESC LIMIT 1 ;

      If sqlcode = 0;
        ERRORMSG = %trim(NOM_OBJ) + ' de type ' + %trim(TYPE) +
        ' restauré avec modification dans ' + %trim(OBJLIB) ;
      Else;
        ERRORMSG = %trim(NOM_OBJ) + ' de type ' + %trim(TYPE) +
         ' non restauré' ;
      EndIf;
    EndMon;


          EndSl;
        EndIf;
     // EndDo;
    Actualiser = *On ;
    EndIf;
  END-PROC;


  //
  // Exécution commande CL
  //
  DCL-PROC Exec_Cmd;
    Cmd(CmdExec:%LEN(CmdExec));
  END-PROC;


  //
  //F4 pour chercher les *SAVF
  //
   DCL-PROC TrtF4_SAVF;
            If SAVFILE_L <> *blank;
              sqlstm = 'SELECT DISTINCT save_file FROM qsys2.savf_info' +
                   ' WHERE save_file_library = ''' + SAVFILE_L + '''';
              titre = 'Liste des fichiers sauvegardés';
              Touche_F4(sqlstm : titre : result);
              If result <> *blank;
                SAVFILE = result;
                Actualiser = *On;
              EndIf;
            EndIf;
   END-PROC;

