(***********************************************************************)
(*  v      *   The Coq Proof Assistant  /  The Coq Development Team    *)
(* <O___,, *        INRIA-Rocquencourt  &  LRI-CNRS-Orsay              *)
(*   \VV/  *************************************************************)
(*    //   *      This file is distributed under the terms of the      *)
(*         *       GNU Lesser General Public License Version 2.1       *)
(***********************************************************************)

(* $Id$ *)  

open Pp
open Names
open Nameops
open Nametab 
open Util
open Extend
open Vernacexpr
open Ppconstrnew
open Pptacticnew
open Rawterm
open Coqast
open Genarg
open Pcoq
open Ast
open Libnames
open Ppextend
open Topconstr

open Tacinterp

let quote str = "\""^str^"\""

(* Warning: [pr_raw_tactic] globalises and fails if globalisation fails *)
let pr_raw_tactic_env l env t = 
  Pptacticnew.pr_raw_tactic env t

let pr_gen env t =
  Pptactic.pr_raw_generic (Ppconstrnew.pr_constr_env env)
    (Ppconstrnew.pr_lconstr_env env)
    (Pptacticnew.pr_raw_tactic env) t

let pr_raw_tactic tac =
  pr_raw_tactic_env [] (Global.env()) tac

let pr_raw_tactic_goal n tac =
  let (_,env) = Pfedit.get_goal_context n in
  pr_raw_tactic_env [] env tac
let pr_lconstr_goal n c =
  let (_,env) = Pfedit.get_goal_context n in
  Ppconstrnew.pr_lconstr_env env c

let rec extract_signature = function
  | [] -> []
  | Egrammar.TacNonTerm (_,(_,t),_) :: l -> t :: extract_signature l
  | _::l -> extract_signature l

let rec match_vernac_rule tys = function
    [] -> raise Not_found
  | (s,pargs)::rls ->
      if extract_signature pargs = tys then (s,pargs)
      else match_vernac_rule tys rls

let sep = fun _ -> spc()
let sep_p = fun _ -> str"."
let sep_v = fun _ -> str","
let sep_v2 = fun _ -> str"," ++ spc()
let sep_pp = fun _ -> str":"

let pr_located pr (loc,x) = pr x

let pr_ne_sep sep pr = function
    [] -> mt()
  | l -> sep() ++ pr l

let pr_entry_prec = function
  | Some Gramext.LeftA -> str"LEFTA "
  | Some Gramext.RightA -> str"RIGHTA "
  | Some Gramext.NonA -> str"NONA "
  | None -> mt()

let pr_set_entry_type = function
  | ETIdent -> str"ident"
  | ETReference -> str"global"
  | ETPattern -> str"pattern"
  | ETConstr _ -> str"constr"
  | ETOther (_,e) -> str e
  | ETBigint -> str "bigint"

let pr_non_terminal = function
  | NtQual (u,nt) -> str u ++ str" : " ++ str nt
  | NtShort nt -> str nt

let pr_production_item = function
  | VNonTerm (loc,nt,Some p) -> pr_non_terminal nt ++ str"(" ++ pr_metaid p ++ str")"
  | VNonTerm (loc,nt,None) -> pr_non_terminal nt
  | VTerm s -> str s

let pr_comment pr_c = function
  | CommentConstr c -> pr_c c
  | CommentString s -> str s
  | CommentInt n -> int n

let pr_in_out_modules = function
  | SearchInside l -> str"inside" ++ spc() ++ prlist_with_sep sep pr_reference l
  | SearchOutside [] -> str"outside"
  | SearchOutside l -> str"outside" ++ spc() ++ prlist_with_sep sep pr_reference l

let pr_search a b pr_c = match a with
  | SearchHead qid -> str"Search" ++ spc() ++ pr_reference qid ++ spc() ++ pr_in_out_modules b
  | SearchPattern c -> str"SearchPattern" ++ spc() ++ pr_c c ++ spc() ++ pr_in_out_modules b
  | SearchRewrite c -> str"SearchRewrite" ++ spc() ++ pr_c c ++ spc() ++ pr_in_out_modules b
  | SearchAbout qid -> str"SearchAbout" ++ spc() ++ pr_reference qid ++ spc() ++ pr_in_out_modules b

let pr_locality local = if local then str "Local " else str ""

let pr_class_rawexpr = function
  | FunClass -> str"FUNCLASS"
  | SortClass -> str"SORTCLASS"
  | RefClass qid -> pr_reference qid

let pr_option_ref_value = function
  | QualidRefValue id -> pr_reference id
  | StringRefValue s -> qs s

let pr_printoption a b = match a with
  | Goptions.PrimaryTable table -> str table ++ pr_opt (prlist_with_sep sep pr_option_ref_value) b
  | Goptions.SecondaryTable (table,field) -> str table ++ spc() ++ str field ++ pr_opt (prlist_with_sep sep pr_option_ref_value) b

let pr_set_option a b = 
  let pr_opt_value = function 
    | IntValue n -> spc() ++ int n
    | StringValue s -> spc() ++ str s
    | BoolValue b -> mt()
  in pr_printoption a None ++ pr_opt_value b

let pr_topcmd _ = str"(* <Warning> : No printer for toplevel commands *)"

let pr_destruct_location = function
  | Tacexpr.ConclLocation ()  -> str"Conclusion"
  | Tacexpr.HypLocation b -> if b then str"Discardable Hypothesis" else str"Hypothesis"

let pr_opt_hintbases l = match l with
  | [] -> mt()
  | _ as z -> str":" ++ spc() ++ prlist_with_sep sep str z

let pr_hints db h pr_c = 
  let db_name = function
    | [] -> (false , mt())
    | c1::c2 -> match c1 with
      |	None,_ -> (false , mt())
      |	Some name,_ -> (true , pr_id name) in
  let opth = pr_opt_hintbases db  in
  let pr_aux = function
    | CAppExpl (_,qid,[]) -> pr_reference qid
    | _ -> mt () in
  match h with
    | HintsResolve l ->
        let (f,dbn) = db_name l in
        if f then
          hov 1 (str"Hint " ++ dbn ++ spc() ++ opth ++
                 str" :=" ++ spc() ++ str"Resolve" ++ spc() ++
                 prlist_with_sep sep pr_c (List.map (fun (_,y) -> y) l))
        else hov 1
          (str"Hints Resolve " ++
          prlist_with_sep sep pr_aux
            (List.map (fun (_,y) -> y) l) ++ spc() ++ opth)
    | HintsImmediate l ->
        let (f,dbn) = db_name l in
        if f then
          hov 1 (str"Hint " ++ dbn ++ spc() ++ opth ++
                 str" :=" ++ spc() ++ str"Immediate" ++ spc() ++
                 prlist_with_sep sep pr_c (List.map (fun (_,y) -> y) l))
        else hov 1
          (str"Hints Immediate " ++
           prlist_with_sep sep pr_aux
            (List.map (fun (_,y) -> y) l) ++ spc() ++ opth)
    | HintsUnfold l ->
        let (f,dbn) = db_name l in
        if f then
          hov 1 (str"Hint" ++ spc() ++ dbn ++ spc() ++ opth ++
                 str" :=" ++ spc() ++ str"Unfold" ++ spc() ++
                 prlist_with_sep sep pr_reference
                   (List.map snd l))
        else hov 1
          (str"Hints Unfold " ++ prlist_with_sep sep pr_reference
            (List.map snd l) ++ spc() ++ opth)
    | HintsConstructors (n,c) ->
        hov 1 (str"Hint " ++ pr_id n ++ spc() ++ opth ++ str" :=" ++
               spc() ++ str"Constructors" ++ spc() ++ pr_reference c) 
    | HintsExtern (name,n,c,tac) ->
        hov 1 (str"Hint " ++ pr_id name ++ spc() ++ opth ++ str" :=" ++
               spc() ++ str"Extern " ++ int n ++ spc() ++ pr_c c ++
               spc() ++ pr_raw_tactic tac)
 
let pr_with_declaration pr_c = function
  | CWith_Definition (id,c) ->
      str"Definition" ++ spc() ++ pr_id id ++ str" := " ++ pr_c c
  | CWith_Module (id,qid) ->
      str"Module" ++ spc() ++ pr_id id ++ str" := " ++
      pr_located pr_qualid qid

let rec pr_module_type pr_c = function
  | CMTEident qid -> pr_located pr_qualid qid
  | CMTEwith (mty,decl) ->
      pr_module_type pr_c mty ++ spc() ++ str" with" ++
      pr_with_declaration pr_c decl

let pr_of_module_type prc (mty,b) =
  str (if b then ":" else "<:") ++
  pr_module_type prc mty

let pr_module_vardecls pr_c (l,mty) =
  prlist
    (fun id ->
      spc() ++ str"(" ++ pr_id id ++ str":" ++
      pr_module_type pr_c mty ++ str")")
    l

let pr_module_binders l pr_c =
  prlist (pr_module_vardecls pr_c) l

let pr_module_binders_list l pr_c = pr_module_binders l pr_c

let rec pr_module_expr = function
  | CMEident qid -> pr_located pr_qualid qid
  | CMEapply (me1,(CMEident _ as me2)) ->
      pr_module_expr me1 ++ spc() ++ pr_module_expr me2
  | CMEapply (me1,me2) ->
      pr_module_expr me1 ++ spc() ++ str"(" ++ pr_module_expr me2 ++ str")"

let pr_opt_casted_constr pr_c = function
  | CCast (loc,c,t) -> pr_c c ++ str":" ++ pr_c t
  | _ as c -> pr_c c

let pr_type_option pr_c = function
  | CHole loc -> mt()
  | _ as c -> str":" ++ pr_c c

let pr_decl_notation =
  pr_opt (fun (ntn,scopt) -> 
    str "as " ++ str (quote ntn) ++ 
    pr_opt (fun sc -> str " :" ++ str sc) scopt)

let anonymize_binder na c =
  if Options.do_translate() then
    Constrextern.extern_rawconstr (Termops.vars_of_env (Global.env()))
      (Reserve.anonymize_if_reserved na
      (Constrintern.for_grammar
        (Constrintern.interp_rawconstr Evd.empty (Global.env())) c))
  else c

let sep_fields () =
  if !Options.p1 then fnl () else str ";" ++ spc ()

let surround_binder p = 
  if !Options.p1 then str"(" ++ p ++ str")" else p

let pr_binder pr_c ty na =
  match anonymize_binder (snd na) ty with
      CHole _ -> pr_located pr_name na
    | _ ->
        hov 1
        (surround_binder (pr_located pr_name na ++ str":" ++ cut() ++ pr_c ty))

let pr_valdecls pr_c = function
  | LocalRawAssum (nal,c) ->
      let sep = if !Options.p1 then spc else pr_tight_coma in
      prlist_with_sep sep (pr_binder pr_c c) nal
  | LocalRawDef (na,c) ->
      hov 1
        (surround_binder (pr_located pr_name na ++ str":=" ++ cut() ++ pr_c c))

let pr_vbinders pr_c l =
  hv 0 (prlist_with_sep spc (pr_valdecls pr_c) l)

let pr_sbinders sbl =
  if sbl = [] then mt () else
    let bl = List.map (fun (id,c) -> ([(dummy_loc,Name id)],c)) sbl in
    pr_binders bl ++ spc ()

let pr_onescheme (id,dep,ind,s) =
  pr_id id ++ str" :=" ++ spc() ++
  (if dep then str"Induction for" else str"Minimality for")
  ++ spc() ++ pr_reference ind ++ spc() ++ str"Sort" ++ spc() ++ pr_sort s

let pr_class_rawexpr = function
  | FunClass -> str"FUNCLASS"
  | SortClass -> str"SORTCLASS"
  | RefClass qid -> pr_reference qid

let pr_assumption_token = function
  | (Decl_kinds.Local,Decl_kinds.Logical) -> str"Hypothesis"
  | (Decl_kinds.Local,Decl_kinds.Definitional) -> str"Variable"
  | (Decl_kinds.Global,Decl_kinds.Logical) -> str"Axiom"
  | (Decl_kinds.Global,Decl_kinds.Definitional) -> str"Parameter"

let pr_params pr_c (xl,(c,t)) =
  hov 2 (prlist_with_sep sep pr_id xl ++ spc() ++
         (if c then str":>" else str":" ++
         spc() ++ pr_c t))

let rec factorize = function
  | [] -> []
  | (c,(x,t))::l ->
      match factorize l with
	| (xl,t')::l' when t' = (c,t) & not !Options.p1 -> (x::xl,t')::l'
	| l' -> ([x],(c,t))::l'

let pr_ne_params_list pr_c l =
  match factorize l with
  | [params] -> surround_binder (pr_params pr_c params)
  | l ->
      prlist_with_sep spc (fun p -> str "(" ++ pr_params pr_c p ++ str ")") l

let pr_thm_token = function
  | Decl_kinds.Theorem -> str"Theorem"
  | Decl_kinds.Lemma -> str"Lemma"
  | Decl_kinds.Fact -> str"Fact"
  | Decl_kinds.Remark -> str"Remark"

let pr_require_token = function
  | Some true -> str "Export"
  | Some false -> str "Import"
  | None -> str "Closed"

let pr_syntax_modifier = function
  | SetItemLevel (l,NextLevel) ->
      prlist_with_sep sep_v2 str l ++
      spc() ++ str"at next level"
  | SetItemLevel (l,NumLevel n) ->
      prlist_with_sep sep_v2 str l ++
      spc() ++ str"at level" ++ spc() ++ int n
  | SetLevel n -> str"at level" ++ spc() ++ int n
  | SetAssoc Gramext.LeftA -> str"left associativity"
  | SetAssoc Gramext.RightA -> str"right associativity"
  | SetAssoc Gramext.NonA -> str"no associativity"
  | SetEntryType (x,typ) -> str x ++ spc() ++ pr_set_entry_type typ
  | SetOnlyParsing -> str"only parsing"

let pr_grammar_tactic_rule (name,(s,pil),t) =
  str name ++ spc() ++ str"[" ++ qs s ++ spc() ++
  prlist_with_sep sep pr_production_item pil ++ str"]" ++
  spc() ++ str"->" ++ spc() ++ str"[" ++ pr_raw_tactic t ++ str"]"

let pr_box b = let pr_boxkind = function
  | PpHB n -> str"h" ++ spc() ++ int n
  | PpVB n -> str"v" ++ spc() ++ int n
  | PpHVB n -> str"hv" ++ spc() ++ int n
  | PpHOVB n -> str"hov" ++ spc() ++ int n
  | PpTB -> str"t"
in str"<" ++ pr_boxkind b ++ str">"
 
let pr_paren_reln_or_extern = function
  | None,L -> str"L"
  | None,E -> str"E"
  | Some pprim,Any -> qs pprim
  | Some pprim,Prec p -> qs pprim ++ spc() ++ str":" ++ spc() ++ int p
  | _ -> mt()

let rec pr_next_hunks = function 
  | UNP_FNL -> str"FNL"
  | UNP_TAB -> str"TAB"
  | RO c -> qs c
  | UNP_BOX (b,ll) -> str"[" ++ pr_box b ++ prlist_with_sep sep pr_next_hunks ll ++ str"]"
  | UNP_BRK (n,m) -> str"[" ++ int n ++ spc() ++ int m ++ str"]"
  | UNP_TBRK (n,m) -> str"[ TBRK" ++ int n ++ spc() ++ int m ++ str"]"
  | PH (e,None,_) -> print_ast e
  | PH (e,Some ext,pr) -> print_ast e ++ spc() ++ str":" ++ spc() ++ pr_paren_reln_or_extern (Some ext,pr)
  | UNP_SYMBOLIC _ -> mt()

let pr_unparsing u =
  str "[ " ++ prlist_with_sep sep pr_next_hunks u ++ str " ]"

let pr_astpat a = str"<<" ++ print_ast a ++ str">>"

let pr_syntax_rule (nm,s,u) = str nm ++ spc() ++ str"[" ++ pr_astpat s ++ str"]" ++ spc() ++ str"->" ++ spc() ++ pr_unparsing u

let pr_syntax_entry (p,rl) =
  str"level" ++ spc() ++ int p ++ str" :" ++ fnl() ++
  prlist_with_sep (fun _ -> fnl() ++ str"| ") pr_syntax_rule rl

let sep_end () = if !Options.p1 then str";" else str"."

(**************************************)
(* Pretty printer for vernac commands *)
(**************************************)
let make_pr_vernac pr_constr pr_lconstr =

let pr_constrarg c = spc () ++ pr_constr c in
let pr_lconstrarg c = spc () ++ pr_lconstr c in
let pr_intarg n = spc () ++ int n in

let rec pr_vernac = function
  
  (* Proof management *)
  | VernacAbortAll -> str "Abort All"
  | VernacRestart -> str"Restart"
  | VernacSuspend -> str"Suspend"
  | VernacUnfocus -> str"Unfocus"
  | VernacGoal c -> str"Goal" ++ pr_lconstrarg c
  | VernacAbort id -> str"Abort" ++ pr_opt (pr_located pr_id) id
  | VernacResume id -> str"Resume" ++ pr_opt (pr_located pr_id) id
  | VernacUndo i -> if i=1 then str"Undo" else str"Undo" ++ pr_intarg i
  | VernacFocus i -> str"Focus" ++ pr_opt int i
  | VernacGo g -> 
      let pr_goable = function
	| GoTo i -> int i
	| GoTop -> str"top"
	| GoNext -> str"next"
	| GoPrev -> str"prev" 
      in str"Go" ++ spc() ++  pr_goable g
  | VernacShow s -> 
      let pr_showable = function
	| ShowGoal n -> str"Show" ++ pr_opt int n
	| ShowGoalImplicitly n -> str"Show Implicits" ++ pr_opt int n
	| ShowProof -> str"Show Proof"
	| ShowNode -> str"Show Node"
	| ShowScript -> str"Show Script"
	| ShowExistentials -> str"Show Existentials"
	| ShowTree -> str"Show Tree"
	| ShowProofNames -> str"Show Conjectures"
	| ShowIntros b -> str"Show " ++ (if b then str"Intros" else str"Intro")
	| ExplainProof l -> str"Explain Proof" ++ spc() ++ prlist_with_sep sep int l
	| ExplainTree l -> str"Explain Proof Tree" ++ spc() ++ prlist_with_sep sep int l 
      in pr_showable s
  | VernacCheckGuard -> str"Guarded"
  | VernacDebug b -> pr_topcmd b

  (* Resetting *)
  | VernacResetName id -> str"Reset" ++ spc() ++ pr_located pr_id id
  | VernacResetInitial -> str"Reset Initial"
  | VernacBack i -> if i=1 then str"Back" else str"Back" ++ pr_intarg i

  (* State management *)
  | VernacWriteState s -> str"Write State" ++ spc () ++ qs s
  | VernacRestoreState s -> str"Restore State" ++ spc() ++ qs s

  (* Control *)
  | VernacList l -> hov 2 (str"[" ++ spc() ++ prlist_with_sep (fun _ -> sep_end () ++ fnl() ) (pr_located pr_vernac) l ++ spc() ++ str"]") 
  | VernacLoad (f,s) -> str"Load" ++ if f then (spc() ++ str"Verbose" ++ spc()) else spc()  ++ str s
  | VernacTime v -> str"Time" ++ spc() ++ pr_vernac v
  | VernacVar id -> pr_id id
  
  (* Syntax *) 
  | VernacGrammar _ -> str"(* <Warning> : Grammar is replaced by Notation *)"
  | VernacTacticGrammar l -> hov 1 (str"Grammar tactic simple_tactic :=" ++ spc() ++ prlist_with_sep (fun _ -> brk(1,1) ++ str"|") pr_grammar_tactic_rule l) (***)
  | VernacSyntax (u,el) -> hov 1 (str"Syntax " ++ str u ++ spc() ++
    prlist_with_sep sep_v2 pr_syntax_entry el) (***)
  | VernacOpenScope (local,sc) ->
      str "Open " ++ pr_locality local ++ str "Scope" ++ spc() ++ str sc
  | VernacDelimiters (sc,key) ->
      str"Delimits Scope" ++ spc () ++ str sc ++
      spc() ++ str "with " ++ str key
  | VernacArgumentsScope (q,scl) -> let pr_opt_scope = function 
      |	None -> str"_"
      |	Some sc -> str sc in 
    str"Arguments Scope" ++ spc() ++ pr_reference q ++ spc() ++ str"[" ++ prlist_with_sep sep pr_opt_scope scl ++ str"]"
  | VernacInfix (local,a,p,s,q,_,ov8,sn) -> (* A Verifier *)
      let (a,p,s) = match ov8 with
          Some mv8 -> mv8
        | None -> (a,p,s) in
      hov 0 (str"Infix " ++ pr_locality local ++ pr_entry_prec a ++ int p
        ++ spc() ++ qs s ++ spc() ++ pr_reference q ++ (match sn with
    | None -> mt()
    | Some sc -> spc() ++ str":" ++ spc() ++ str sc))
  | VernacDistfix (local,a,p,s,q,sn) ->
      hov 0 (str"Distfix " ++ pr_locality local ++ pr_entry_prec a ++ int p
        ++ spc() ++ qs s ++ spc() ++ pr_reference q ++ (match sn with
    | None -> mt()
    | Some sc -> spc() ++ str":" ++ spc() ++ str sc))
  | VernacNotation (local,c,sl,mv8,opt) ->
      let (s,l) = match mv8 with
          None -> out_some sl
        | Some ml -> ml in
      let ps =
	let n = String.length s in
	if n > 2 & s.[0] = '\'' & s.[n-1] = '\'' 
	then str (String.sub s 1 (n-2))
	else qs s in
      hov 2( str"Notation" ++ spc() ++ pr_locality local ++ ps ++
      str " :=" ++ pr_constrarg c ++
      (match l with
        | [] -> mt()
        | _ as t ->
            spc() ++ hov 0 (str"(" ++ prlist_with_sep sep_v2 pr_syntax_modifier t ++ str")")) ++
      (match opt with
        | None -> mt()
        | Some sc -> str" :" ++ spc() ++ str sc))
  | VernacSyntaxExtension (local,sl,mv8) ->
      let (s,l) = match mv8 with
          None -> out_some sl
        | Some ml -> ml in
      str"Uninterpreted Notation" ++ spc() ++ pr_locality local ++ qs s ++
      (match l with | [] -> mt() | _ as l -> 
	str" (" ++ prlist_with_sep sep_v2 pr_syntax_modifier l ++ str")")

  (* Gallina *)
  | VernacDefinition (d,id,b,f,e) -> (* A verifier... *)
      let pr_def_token = function
        | Decl_kinds.LCoercion -> str"Coercion Local"
        | Decl_kinds.GCoercion -> str"Coercion"
        | Decl_kinds.LDefinition -> str"Local"
        | Decl_kinds.GDefinition -> str"Definition"
        | Decl_kinds.LSubClass -> str"Local SubClass"
        | Decl_kinds.GSubClass -> str"SubClass"
        | Decl_kinds.SCanonical -> str"Canonical Structure" in
      let pr_reduce = function
        | None -> mt()
        | Some r ->
            str"Eval" ++ spc() ++
            pr_red_expr (pr_constr, pr_lconstr, pr_reference) r ++
            str" in" ++ spc() in
      let pr_def_body = function
        | DefineBody (bl,red,c,d) ->
            let (bl2,body,ty) = match d with
              | None ->
                  let bl2,body = extract_lam_binders c in
                  (bl2,body,mt())
              | Some ty ->
                  let bl2,body,ty = extract_def_binders c ty in
                  (bl2,body, spc() ++ str":" ++ pr_lconstrarg ty) in
            let bindings =
              pr_ne_sep spc (pr_vbinders pr_lconstr) bl ++
              if bl2 = [] then mt() else (spc() ++ pr_binders bl2) in
            let ppred = Some (pr_reduce red ++ pr_lconstr body) in
            (bindings,ty,ppred)
        | ProveBody (bl,t) ->
            (pr_vbinders pr_lconstr bl, str" :" ++ pr_lconstrarg t, None) in
      let (binds,typ,c) = pr_def_body b in
      hov 2 (pr_def_token e ++ spc() ++ pr_id id ++ binds ++ typ ++
      (match c with
        | None -> mt()
        | Some cc -> str" :=" ++ spc() ++ cc))

  | VernacStartTheoremProof (ki,id,(bl,c),b,d) ->
      hov 1 (pr_thm_token ki ++ spc() ++ pr_id id ++ spc() ++
      (match bl with
        | [] -> mt()
        | _ -> pr_vbinders pr_lconstr bl ++ spc()) ++ str":" ++ spc() ++ pr_lconstr c)
  | VernacEndProof (opac,o) -> (match o with
    | None -> if opac then str"Qed" else str"Defined"
    | Some (id,th) -> (match th with
      |	None -> (if opac then str"Save" else str"Defined") ++ spc() ++ pr_id id
      |	Some tok -> str"Save" ++ spc() ++ pr_thm_token tok ++ spc() ++ pr_id id)) 
  | VernacExactProof c -> hov 2 (str"Proof" ++ pr_lconstrarg c)
  | VernacAssumption (stre,l) ->
      hov 2
        (pr_assumption_token stre ++ spc() ++ pr_ne_params_list pr_lconstr l)
  | VernacInductive (f,l) ->

      (* Copie simplifi�e de command.ml pour recalculer les implicites *)
      let lparams = match l with [] -> assert false | (_,_,la,_,_)::_ -> la in
      let nparams = List.length lparams
      and sigma = Evd.empty 
      and env0 = Global.env() in
      let (env_params,params) =
	List.fold_left
	  (fun (env,params) (id,t) ->
	    let p = Constrintern.interp_binder sigma env (Name id) t in
	    (Termops.push_rel_assum (Name id,p) env,
	    (Name id,None,p)::params))
	  (env0,[]) lparams in
      let lparnames = List.map (fun (na,_,_) -> na) params in
      let impl_ntns = List.map
	(fun (recname,ntnopt,_,arityc,_) ->
	  let arity = Constrintern.interp_type sigma env_params arityc in
	  let fullarity =
            Termops.prod_it arity (List.map (fun (id,_,ty) -> (id,ty)) params)
	  in
	  let impl_in =
	    if Impargs.is_implicit_args()
	    then Impargs.compute_implicits false env_params fullarity
	    else [] in
	  let impl_out =
	    if Impargs.is_implicit_args_out()
	    then Impargs.compute_implicits true env_params fullarity
	    else [] in
	  let notation =
	    option_app (fun df ->
	      (List.rev_append lparnames 
		(List.rev (List.map fst (fst (Term.decompose_prod arity)))),
	      df))
	      ntnopt in
	  (recname,impl_in,impl_out,notation)) l in
      let impls_in = List.map (fun (id,a,_,_) -> (id,a)) impl_ntns in
      let impls_out = List.map (fun (id,_,a,_) -> (id,a)) impl_ntns in
      let notations = List.map (fun (id,_,_,n) -> (id,n)) impl_ntns in
      Constrintern.set_temporary_implicits_in impls_in;
      Constrextern.set_temporary_implicits_out impls_out;
      (* Fin calcul implicites *)

      let pr_constructor (coe,(id,c)) =
        hov 2 (pr_id id ++ str" " ++
               (if coe then str":>" else str":") ++
               pr_lconstrarg c) in
      let pr_constructor_list l = match l with
        | [] -> mt()
        | _ ->
            fnl() ++ str (if List.length l = 1 then "   " else " | ") ++
            prlist_with_sep (fun _ -> fnl() ++ str" | ") pr_constructor l in
      let pr_oneind key (id,ntn,indpar,s,lc) =
	hov 0 (
          str key ++ spc() ++
          pr_id id ++ spc() ++ pr_sbinders indpar ++ str":" ++ spc() ++
          pr_lconstr s ++ 
	  pr_decl_notation ntn ++ str" :=") ++ pr_constructor_list lc in

      (* Copie simplifi�e de command.ml pour d�clarer les notations locales *)
      List.iter (fun (recname,no) ->
	option_iter (fun (larnames,(df,scope)) ->
	Metasyntax.add_notation_interpretation df
	(AVar recname,larnames) scope) no) notations;

      hov 1 (pr_oneind (if f then "Inductive" else "CoInductive") (List.hd l))
      ++ 
      (prlist (fun ind -> fnl() ++ hov 1 (pr_oneind "with" ind)) (List.tl l))


  | VernacFixpoint recs ->

      (* Copie simplifi�e de command.ml pour recalculer les implicites *)
      let sigma = Evd.empty
      and env0 = Global.env() in
      let impl_ntns = List.map
        (fun ((recname,_,arityc,_),ntnopt) -> 
          let arity = Constrintern.interp_type sigma env0 arityc in
	  let impl_in =
	    if Impargs.is_implicit_args()
	    then Impargs.compute_implicits false env0 arity
	    else [] in
	  let impl_out =
	    if Impargs.is_implicit_args_out()
	    then Impargs.compute_implicits true env0 arity
	    else [] in
	  let notations = 
	    option_app (fun ntn ->
              let larnames = List.map fst (fst (Term.decompose_prod arity)) in
	      (List.rev larnames,ntn)) ntnopt in
	  (recname,impl_in,impl_out,notations)) recs in
      let impls_in = List.map (fun (id,a,_,_) -> (id,a)) impl_ntns in
      let impls_out = List.map (fun (id,_,a,_) -> (id,a)) impl_ntns in
      let notations = List.map (fun (id,_,_,n) -> (id,n)) impl_ntns in
      Constrintern.set_temporary_implicits_in impls_in;
      Constrextern.set_temporary_implicits_out impls_out;

      (* Copie simplifi�e de command.ml pour d�clarer les notations locales *)
      List.iter (fun (recname,no) ->
	option_iter (fun (larnames,(df,scope)) ->
	Metasyntax.add_notation_interpretation df
	(AVar recname,larnames) scope) no) notations;

      let pr_onerec = function
        | (id,n,type_0,def0),ntn ->
            let (bl,def,type_) = extract_def_binders def0 type_0 in
            let ids = List.flatten (List.map fst bl) in
            let (bl,def,type_) =
              if List.length ids <= n then split_fix (n+1) def0 type_0
              else (bl,def,type_) in
            let ids = List.flatten (List.map fst bl) in
            let annot =
              if List.length ids > 1 then 
                spc() ++ str "{struct " ++
                pr_name (snd (List.nth ids n)) ++ str"}"
              else mt() in
            pr_id id ++ str" " ++ pr_binders bl ++ annot ++ spc()
            ++ pr_type_option (fun c -> spc() ++ pr_lconstr c) type_
            ++ pr_decl_notation ntn ++ str" :=" ++ brk(1,1) ++ pr_lconstr def
      in
      hov 1 (str"Fixpoint" ++ spc() ++
        prlist_with_sep (fun _ -> fnl() ++ str"with ") pr_onerec recs)

  | VernacCoFixpoint corecs ->
      let pr_onecorec (id,c,def) =
        let (bl,def,c) = extract_def_binders def c in
        pr_id id ++ spc() ++ pr_binders bl ++ spc() ++ str":" ++
        pr_lconstrarg c ++
        str" :=" ++ brk(1,1) ++ pr_lconstr def in
      hov 1 (str"CoFixpoint" ++ spc() ++
      prlist_with_sep (fun _ -> fnl() ++ str"with ") pr_onecorec corecs)  
  | VernacScheme l ->
      hov 2 (str"Scheme" ++ spc() ++
             prlist_with_sep (fun _ -> fnl() ++ str"with") pr_onescheme l)

  (* Gallina extensions *)
  | VernacRecord ((oc,name),ps,s,c,fs) ->
      let pr_record_field = function
        | (oc,AssumExpr (id,t)) ->
            hov 1 (surround_binder (pr_id id ++
            (if oc then str" :>" else str" :") ++ spc() ++
            pr_lconstr t))
        | (oc,DefExpr(id,b,opt)) -> (match opt with
	    | Some t ->
                hov 1 (surround_binder (pr_id id ++
                (if oc then str" :>" else str" :") ++ spc() ++
                pr_lconstr t ++ str" :=" ++ pr_lconstr b))
	    | None ->
                hov 1 (surround_binder (pr_id id ++ str" :=" ++ spc() ++
                pr_lconstr b))) in
      hov 2
        (str"Record" ++
         (if oc then str" > " else str" ") ++ pr_id name ++ spc() ++
         pr_sbinders ps ++ str" :" ++ spc() ++ pr_lconstr s ++ str" := " ++
         (match c with
           | None -> mt()
           | Some sc -> pr_id sc) ++ spc() ++ str"{" ++ cut() ++
        hv 0 (prlist_with_sep sep_fields pr_record_field fs)
        ++ str"}")
  | VernacBeginSection id -> hov 2 (str"Section" ++ spc () ++ pr_id id)
  | VernacEndSegment id -> hov 2 (str"End" ++ spc() ++ pr_id id)
  | VernacRequire (exp,spe,l) -> hov 2
      (str "Require " ++ pr_require_token exp ++ spc() ++
      (match spe with
      |	None -> mt()
      |	Some flag ->
          (if flag then str"Specification" else str"Implementation") ++
          spc ()) ++
      prlist_with_sep sep pr_reference l)
  | VernacImport (f,l) ->
      (if f then str"Export" else str"Import") ++ spc() ++
      prlist_with_sep sep pr_reference l
  | VernacCanonical q -> str"Canonical Structure" ++ spc() ++ pr_reference q
  | VernacCoercion (s,id,c1,c2) -> hov 1 (str"Coercion" ++ (match s with | Decl_kinds.Local -> spc() ++ str"Local" ++ spc() | Decl_kinds.Global -> spc()) ++ pr_reference id ++ spc() ++ str":" ++ spc() ++ pr_class_rawexpr c1 ++ spc() ++ str">->" ++ spc() ++ pr_class_rawexpr c2)
  | VernacIdentityCoercion (s,id,c1,c2) -> hov 1 (str"Identity Coercion" ++ (match s with | Decl_kinds.Local -> spc() ++ str"Local" ++ spc() | Decl_kinds.Global -> spc()) ++ pr_id id ++ spc() ++ str":" ++ spc() ++ pr_class_rawexpr c1 ++ spc() ++ str">->" ++ spc() ++ pr_class_rawexpr c2)

  (* Modules and Module Types *)
  | VernacDefineModule (m,bl,ty,bd) ->
      hov 2 (str"Module " ++ pr_id m ++ spc() ++
             pr_module_binders_list bl pr_lconstr ++
             pr_opt (pr_of_module_type pr_lconstr) ty ++
             pr_opt (fun me -> str ":= " ++ pr_module_expr me) bd)
  | VernacDeclareModule (id,l,m1,m2) ->
      hov 2 (str"Declare Module " ++ pr_id id ++ spc() ++
             pr_module_binders_list l pr_lconstr ++
             pr_opt (pr_of_module_type pr_lconstr) m1 ++
             pr_opt (fun me -> str ":= " ++ pr_module_expr me) m2)
  | VernacDeclareModuleType (id,l,m) ->
      hov 2 (str"Module Type " ++ pr_id id ++ spc() ++
             pr_module_binders_list l pr_lconstr ++
             pr_opt (fun mt -> str ":= " ++ pr_module_type pr_lconstr mt) m)

  (* Solving *)
  | VernacSolve (i,tac,deftac) ->
      (if i = 1 then mt() else int i ++ str ": ") ++
      (if !Options.p1 then mt () else str "By ") ++
      (if deftac then mt() else str "!! ") ++
      pr_raw_tactic_goal i tac
  | VernacSolveExistential (i,c) ->
      str"Existential " ++ int i ++ pr_lconstrarg c

  (* Auxiliary file and library management *)
  | VernacRequireFrom (exp,spe,f) -> hov 2
      (str"Require " ++ pr_require_token exp ++ spc() ++
      (match spe with
        | None -> mt()
        | Some false -> str"Implementation" ++ spc()
        | Some true -> str"Specification" ++ spc ()) ++
      qs f)
  | VernacAddLoadPath (fl,s,d) -> hov 2
      (str"Add" ++
       (if fl then str" Rec " else spc()) ++
       str"LoadPath" ++ spc() ++ qs s ++
       (match d with 
         | None -> mt()
         | Some dir -> spc() ++ str"as" ++ spc() ++ pr_dirpath dir)) 
  | VernacRemoveLoadPath s -> str"Remove LoadPath" ++ qs s
  | VernacAddMLPath (fl,s) ->
      str"Add" ++ (if fl then str" Rec " else spc()) ++ str"ML Path" ++ qs s
  | VernacDeclareMLModule l ->
      hov 2 (str"Declare ML Module" ++ spc() ++ prlist_with_sep sep qs l)
  | VernacChdir s -> str"Cd" ++ pr_opt qs s

  (* Commands *)
  | VernacDeclareTacticDefinition (rc,l) ->
      let pr_tac_body (id, body) =
        let ppb, body =
          match body with
              Tacexpr.TacFun (idl,b) ->
                 (spc() ++ prlist_with_sep spc
                   (function None -> str"_" | Some id -> pr_id id)
                   idl),
                 b
            | _ -> mt(), body in
        pr_located pr_id id ++ ppb ++ str" :=" ++ brk(1,1) ++
        pr_raw_tactic_env
          (List.map (fun ((_,id),_) -> (id,Lib.make_path id)) l) 
          (Global.env()) body in
      hov 1
        ((if !Options.p1 then
	  (if rc then str "Recursive " else mt()) ++
	  str "Tactic Definition " else
	    (* Rec by default *) str "Ltac ") ++
        prlist_with_sep (fun () -> fnl() ++ str"with ") pr_tac_body l)
  | VernacHints (dbnames,h) -> pr_hints dbnames h pr_constr
  | VernacHintDestruct (id,loc,c,i,tac) ->
      hov 2 (str"HintDestruct " ++ pr_destruct_location loc ++ spc() ++
      pr_id id ++ pr_constrarg c ++ pr_intarg i ++ spc() ++
      str"[" ++ pr_raw_tactic tac ++ str"]")
  | VernacSyntacticDefinition (id,c,None) ->
      hov 2 (str"Syntactic Definition " ++ pr_id id ++ str" :=" ++
             pr_lconstrarg c)
  | VernacSyntacticDefinition (id,c,Some n) ->
      hov 2 (str"Syntactic Definition " ++ pr_id id ++ str" :=" ++
             pr_lconstrarg c ++ spc() ++ str"|" ++ int n)
  | VernacDeclareImplicits (q,None) ->
      hov 2 (str"Implicits" ++ spc() ++ pr_reference q)
  | VernacDeclareImplicits (q,Some l) ->
      hov 1 (str"Implicits" ++ spc() ++ pr_reference q ++ spc() ++
             str"[" ++ prlist_with_sep sep int l ++ str"]")
  | VernacReserve (idl,c) ->
      hov 1 (str"Implicit Variable" ++
        str (if List.length idl > 1 then "s " else " ") ++ str "Type " ++
        prlist_with_sep spc pr_id idl ++ str " : " ++ pr_constr c)
  | VernacSetOpacity (fl,l) ->
      hov 1 ((if fl then str"Opaque" else str"Transparent") ++
             spc() ++ prlist_with_sep sep pr_reference l)
  | VernacUnsetOption na ->
      hov 1 (str"Unset" ++ spc() ++ pr_printoption na None)
  | VernacSetOption (Goptions.SecondaryTable ("Implicit","Arguments"),BoolValue true) -> str"Set Implicit Arguments"
  | VernacSetOption (Goptions.SecondaryTable ("Implicit","Arguments"),BoolValue false) -> str"Unset Implicit Arguments"
  | VernacSetOption (na,v) -> hov 2 (str"Set" ++ spc() ++ pr_set_option na v)
  | VernacAddOption (na,l) -> hov 2 (str"Add" ++ spc() ++ pr_printoption na (Some l))
  | VernacRemoveOption (na,l) -> hov 2 (str"Remove" ++ spc() ++ pr_printoption na (Some l))
  | VernacMemOption (na,l) -> hov 2 (str"Test" ++ spc() ++ pr_printoption na (Some l))
  | VernacPrintOption na -> hov 2 (str"Test" ++ spc() ++ pr_printoption na None)
  | VernacCheckMayEval (r,io,c) -> 
      let pr_mayeval r c = match r with 
      | Some r0 ->
          hov 2 (str"Eval" ++ spc() ++
          pr_red_expr (pr_constr,pr_lconstr,pr_reference) r0 ++
          spc() ++ str"in" ++ spc () ++ pr_lconstr c)
      | None -> hov 2 (str"Check" ++ spc() ++ pr_lconstr c) 
      in pr_mayeval r c
  | VernacGlobalCheck c -> hov 2 (str"Type" ++ pr_lconstrarg c)
  | VernacPrint p -> 
      let pr_printable = function
	| PrintFullContext -> str"Print All"
	| PrintSectionContext s ->
            str"Print Section" ++ spc() ++ pr_reference s
	| PrintGrammar (uni,ent) ->
            str"Print Grammar" ++ spc() ++ str uni ++ spc() ++ str ent
	| PrintLoadPath -> str"Print LoadPath"
	| PrintModules -> str"Print Modules"
	| PrintMLLoadPath -> str"Print ML Path"
	| PrintMLModules -> str"Print ML Modules"
	| PrintGraph -> str"Print Graph"
	| PrintClasses -> str"Print Classes"
	| PrintCoercions -> str"Print Coercions"
	| PrintCoercionPaths (s,t) -> str"Print Coercion Paths" ++ spc() ++ pr_class_rawexpr s ++ spc() ++ pr_class_rawexpr t
	| PrintTables -> str"Print Tables"
	| PrintOpaqueName qid -> str"Print Proof" ++ spc() ++ pr_reference qid
	| PrintHintGoal -> str"Print Hint"
	| PrintHint qid -> str"Print Hint" ++ spc() ++ pr_reference qid
	| PrintHintDb -> str"Print Hint *"
	| PrintHintDbName s -> str"Print HintDb" ++ spc() ++ str s
	| PrintUniverses fopt -> str"Dump Universes" ++ pr_opt str fopt
	| PrintName qid -> str"Print" ++ spc()  ++ pr_reference qid
	| PrintLocalContext -> str"Print"
	| PrintModuleType qid -> str"Print Module Type" ++ spc() ++ pr_reference qid
	| PrintModule qid -> str"Print Module" ++ spc() ++ pr_reference qid
	| PrintInspect n -> str"Inspect" ++ spc() ++ int n
	| PrintScope s -> str"Print Scope" ++ spc() ++ str s 
      in pr_printable p
  | VernacSearch (sea,sea_r) -> pr_search sea sea_r pr_constr
  | VernacLocate loc -> 
      let pr_locate =function
	| LocateTerm qid ->  pr_reference qid
	| LocateFile f -> str"File" ++ spc() ++ qs f
	| LocateLibrary qid -> str"Library" ++ spc () ++ pr_reference qid
	| LocateNotation s -> str ("\""^s^"\"")
      in str"Locate" ++ spc() ++ pr_locate loc
  | VernacComments l ->
      hov 2
        (str"Comments" ++ spc() ++ prlist_with_sep sep (pr_comment pr_constr) l)
  | VernacNop -> str"Proof"
  
  (* Toplevel control *)
  | VernacToplevelControl exn -> pr_topcmd exn

  (* For extension *)
  | VernacExtend (s,c) -> pr_extend s c
  | VernacV7only _ -> mt()
  | VernacV8only com -> pr_vernac com
  | VernacProof te -> str "Proof with" ++ spc() ++ pr_raw_tactic te 

and pr_extend s cl =
  let pr_arg a =
    try pr_gen (Global.env()) a
    with Failure _ -> str ("<error in "^s^">") in
  try
    let rls = List.assoc s (Egrammar.get_extend_vernac_grammars()) in
    let (hd,rl) = match_vernac_rule (List.map Genarg.genarg_tag cl) rls in
    let (pp,_) =
      List.fold_left
        (fun (strm,args) pi ->
          match pi with
              Egrammar.TacNonTerm _ -> 
                (strm ++ pr_gen (Global.env()) (List.hd args),
                List.tl args)
            | Egrammar.TacTerm s -> (strm ++ spc() ++ str s, args))
        (str hd,cl) rl in
    hov 1 pp
  with Not_found ->
    hov 1 (str ("TODO("^s) ++ prlist_with_sep sep pr_arg cl ++ str ")")

in pr_vernac

let pr_vernac = make_pr_vernac Ppconstrnew.pr_constr Ppconstrnew.pr_lconstr

