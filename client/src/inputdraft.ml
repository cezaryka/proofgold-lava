(* Copyright (c) 2020 The Proofgold developers *)
(* Copyright (c) 2019 The Dalilcoin developers *)
(* Distributed under the MIT software license, see the accompanying
   file COPYING or http://www.opensource.org/licenses/mit-license.php. *)

open Hash
open Logic
open Mathdata
open Cryptocurr

(* Check if a character is whitespace *)
let whitespace_p c = c = ' ' || c = '\t' || c = '\r' || c = '\n';;

(* Skip over whitespace and comments in the input channel *)
let skip_whitespace ch =
  try
    while true do
      let c = input_char ch in
      if c = '%' then
	begin
	  try
	    while true do
	      let c = input_char ch in
	      if c = '\r' || c = '\n' then raise Exit
	    done
	  with Exit -> ()
	end
      else if not (whitespace_p c) then raise Exit
    done
  with Exit ->
    seek_in ch (pos_in ch - 1);;

(* Read the next token from the input channel *)
let input_token ch =
  skip_whitespace ch;
  let tokb = Buffer.create 10 in
  try
    while true do
      let c = input_char ch in
      if whitespace_p c || c = '%' then
	raise Exit
      else
	Buffer.add_char tokb c
    done;
    ""
  with Exit ->
    Buffer.contents tokb;;

(* Read a list of tokens enclosed in square brackets from the input channel *)
let input_token_rev_list ch =
  let rec input_token_rev_list_r acc =
    let tok = input_token ch in
    if tok = "]" then
      acc
    else
      input_token_rev_list_r (tok::acc)
  in
  let stok = input_token ch in
  if stok = "[" then
    input_token_rev_list_r []
  else
    raise (Failure (Printf.sprintf "expected [ but found %s" stok))

(* Return the position of an element in a list, raising Not_found if not present *)
let pos x l =
  let rec posr x l i =
    match l with
    | [] -> raise Not_found
    | y::r when x = y -> i
    | _::r -> posr x r (i+1)
  in
  posr x l 0;;

(* Read a logic type from the input channel, using a hash table to look up base types *)
let rec input_stp bash ch tvl =
  let l = input_token ch in
  if l = "TpArr" then
    let a = input_stp bash ch tvl in
    let b = input_stp bash ch tvl in
    Logic.TpArr(a,b)
  else if l = "Prop" then
    Logic.Prop
  else
    try
      let i = Hashtbl.find bash l in
      Logic.Base(i)
    with Not_found ->
      raise (Failure (Printf.sprintf "Unknown type %s" l));;

(* Read a logic term from the input channel, using hash tables to look up base types and previously defined terms *)
let rec input_trm bash trmh ch tvl vl =
  let l = input_token ch in
  if l = "Ap" then
    let m1 = input_trm bash trmh ch tvl vl in
    let m2 = input_trm bash trmh ch tvl vl in
    Logic.Ap(m1,m2)
  else if l = "Lam" then
    let x = input_token ch in
    let a = input_stp bash ch tvl in
    let m2 = input_trm bash trmh ch tvl (x::vl) in
    Logic.Lam(a,m2)
  else if l = "Imp" then
    let m1 = input_trm bash trmh ch tvl vl in
    let m2 = input_trm bash trmh ch tvl vl in
    Logic.Imp(m1,m2)
  else if l = "All" then
    let x = input_token ch in
    let a = input_stp bash ch tvl in
    let m2 = input_trm bash trmh ch tvl (x::vl) in
    Logic.All(a,m2)
  else if l = "Ex" then
    let x = input_token ch in
    let a = input_stp bash ch tvl in
    let m2 = input_trm bash trmh ch tvl (x::vl) in
    Logic.Ex(a,m2)
  else if l = "Eq" then
    let a = input_stp bash ch tvl in
    let m2 = input_trm bash trmh ch tvl vl in
    let m3 = input_trm bash trmh ch tvl vl in
    Logic.Eq(a,m2,m3)
  else if l = "Prim" then
    let x = input_token ch in
    let i = int_of_string x in
    if i >= 0 then
      Logic.Prim(i)
    else
      raise (Failure "negative primitive?")
  else
    try
      let (_,m) = Hashtbl.find trmh l in
      m
    with Not_found ->
      try
	let i = pos l vl in
	Logic.DB(i)
      with Not_found ->
	raise (Failure (Printf.sprintf "Unknown term %s" l));;

(* Read a proof term from the input channel, using hash tables to look up base types, previously defined terms, and previously proven propositions *)
let rec input_pf bash trmh proph ch tvl vl hl =
  let l = input_token ch in
  if l = "PrAp" then
    let d1 = input_pf bash trmh proph ch tvl vl hl in
    let d2 = input_pf bash trmh proph ch tvl vl hl in
    Logic.PrAp(d1,d2)
  else if l = "TmAp" then
    let d1 = input_pf bash trmh proph ch tvl vl hl in
    let m2 = input_trm bash trmh ch tvl vl in
    Logic.TmAp(d1,m2)
  else if l = "PrLa" then
    let x = input_token ch in
    let p1 = input_trm bash trmh ch tvl vl in
    let d2 = input_pf bash trmh proph ch tvl vl (x::hl) in
    Logic.PrLa(p1,d2)
  else if l = "TmLa" then
    let x = input_token ch in
    let a1 = input_stp bash ch tvl in
    let d2 = input_pf bash trmh proph ch tvl (x::vl) hl in
    Logic.TmLa(a1,d2)
  else if l = "Ext" then
    let a1 = input_stp bash ch tvl in
    let a2 = input_stp bash ch tvl in
    Logic.Ext(a1,a2)
  else
    try
      let h = Hashtbl.find proph l in
      Logic.Known(h)
    with Not_found ->
      try
	let i = pos l hl in
	Logic.Hyp(i)
      with Not_found ->
	raise (Failure (Printf.sprintf "Unknown known or hyp ref %s" l))

(* Read a theory specification from the input channel *)
let input_theoryspec ch =
  let basec = ref 0 in
  let baseh : (string,int) Hashtbl.t = Hashtbl.create 10 in
  let primc = ref 0 in
  let trmh : (string,Logic.stp * Logic.trm) Hashtbl.t = Hashtbl.create 100 in
  let proph : (string,hashval) Hashtbl.t = Hashtbl.create 100 in
  let prophrev : (hashval,string) Hashtbl.t = Hashtbl.create 100 in
  let propownsh : (hashval,payaddr) Hashtbl.t = Hashtbl.create 100 in
  let proprightsh : (bool * hashval,payaddr * (int64 option)) Hashtbl.t = Hashtbl.create 100 in
  let thyspec = ref [] in
  let nonce = ref None in
  let gamma = ref None in
  let pr l f =
    try
      f()
    with End_of_file ->
      raise (Failure (Printf.sprintf "Incomplete %s" l))
  in
  try
    while true do
      let l = input_token ch in
      if l = "Nonce" then
	pr l
	  (fun () ->
	    let h = input_token ch in
	    match !nonce with
	    | None -> nonce := Some(hexstring_hashval h)
	    | Some(_) -> raise (Failure "two nonces where at most one is expected"))
      else if l = "Publisher" then
	pr l
	  (fun () ->
	    let h = input_token ch in
	    match !gamma with
	    | None -> gamma := Some(pfgaddrstr_addr h)
	    | Some(_) -> raise (Failure "two publishers where at most one is expected"))
      else if l = "NewOwner" then
	pr l
	  (fun () ->
	    let nm = input_token ch in
	    let gammas = input_token ch in
	    let gamma = pfgaddrstr_addr gammas in
	    if payaddr_p gamma then
	      let gammap = let (i,xs) = gamma in (i = 1,xs) in
	      begin
		try
		  let h = Hashtbl.find proph nm in
		  Hashtbl.add propownsh h gammap;
		with Not_found ->
		  if Hashtbl.mem trmh nm then
		    raise (Failure (Printf.sprintf "Only axioms of the theory are given owners initially, so cannot assign owner to %s." nm))
		  else
		    raise (Failure (Printf.sprintf "Unknown axiom %s to assign ownership to" nm))
	      end
	    else
	      raise (Failure (Printf.sprintf "%s cannot be an owner since it is not a pay address" gammas)))
      else if l = "NewRights" then
	pr l
	  (fun () ->
	    let nm = input_token ch in
	    let gammas = input_token ch in
	    let gamma = pfgaddrstr_addr gammas in
	    if payaddr_p gamma then
	      let gammap = let (i,xs) = gamma in (i = 1,xs) in
	      begin
		let price = input_token ch in
		let price =
		  if price = "Free" then
		    Some(0L)
		  else if price = "None" then
		    None
		  else
		    Some(atoms_of_bars price)
		in
		begin
		  try
		    let h = Hashtbl.find proph nm in
		    Hashtbl.add proprightsh (false,h) (gammap,price);
		    Hashtbl.add proprightsh (true,h) (gammap,price);
		  with Not_found ->
		    if Hashtbl.mem trmh nm then
		      raise (Failure (Printf.sprintf "Only axioms of the theory are given owners initially, so cannot assign rights for %s." nm))
		    else
		      raise (Failure (Printf.sprintf "Unknown axiom %s to give rights for" nm))
		end
	      end
	    else
	      raise (Failure (Printf.sprintf "%s cannot be an address for rights since it is not a pay address" gammas)))
      else if l = "NewPureRights" then
	pr l
	  (fun () ->
	    let nm = input_token ch in
	    let gammas = input_token ch in
	    let gamma = pfgaddrstr_addr gammas in
	    if payaddr_p gamma then
	      let gammap = let (i,xs) = gamma in (i = 1,xs) in
	      begin
		let price = input_token ch in
		let price =
		  if price = "Free" then
		    Some(0L)
		  else if price = "None" then
		    None
		  else
		    Some(atoms_of_bars price)
		in
		begin
		  try
		    let h = Hashtbl.find proph nm in
		    Hashtbl.add proprightsh (false,h) (gammap,price);
		  with Not_found ->
		    if Hashtbl.mem trmh nm then
		      raise (Failure (Printf.sprintf "Only axioms of the theory are given owners initially, so cannot assign rights for %s." nm))
		    else
		      raise (Failure (Printf.sprintf "Unknown axiom %s to give rights for" nm))
		end
	      end
	    else
	      raise (Failure (Printf.sprintf "%s cannot be an address for rights since it is not a pay address" gammas)))
      else if l = "NewTheoryRights" then
	pr l
	  (fun () ->
	    let nm = input_token ch in
	    let gammas = input_token ch in
	    let gamma = pfgaddrstr_addr gammas in
	    if payaddr_p gamma then
	      let gammap = let (i,xs) = gamma in (i = 1,xs) in
	      begin
		let price = input_token ch in
		let price =
		  if price = "Free" then
		    Some(0L)
		  else if price = "None" then
		    None
		  else
		    Some(atoms_of_bars price)
		in
		begin
		  try
		    let h = Hashtbl.find proph nm in
		    Hashtbl.add proprightsh (true,h) (gammap,price);
		  with Not_found ->
		    if Hashtbl.mem trmh nm then
		      raise (Failure (Printf.sprintf "Only axioms of the theory are given owners initially, so cannot assign rights for %s." nm))
		    else
		      raise (Failure (Printf.sprintf "Unknown axiom %s to give rights for" nm))
		end
	      end
	    else
	      raise (Failure (Printf.sprintf "%s cannot be an address for rights since it is not a pay address" gammas)))
      else if l = "Base" then
	pr l
	  (fun () ->
	    let nm = input_token ch in
	    Hashtbl.add baseh nm !basec;
	    incr basec)
      else if l = "Prim" then
	pr l
	  (fun () ->
	    let nm = input_token ch in
	    if not (input_token ch = ":") then raise (Failure "bad format for type of Prim");
	    let a = input_stp baseh ch [] in
	    Hashtbl.add trmh nm (a,Logic.Prim(!primc));
	    incr primc;
	    thyspec := Logic.Thyprim(a)::!thyspec)
      else if l = "Def" then
	pr l
	  (fun () ->
	    let nm = input_token ch in
	    if not (input_token ch = ":") then raise (Failure "bad format for type of Def");
	    let a = input_stp baseh ch [] in
	    if not (input_token ch = ":=") then raise (Failure "bad format for term of Def");
	    let m = input_trm baseh trmh ch [] [] in
	    match Checking.beta_eta_norm_fixed (ref 0) m with
	    | Some(m) ->
		Hashtbl.add trmh nm (a,Logic.TmH(Mathdata.tm_hashroot m));
		thyspec := Logic.Thydef(a,m)::!thyspec
	    | None -> raise (Failure (Printf.sprintf "trouble normalizing Def %s" nm)))
      else if l = "Axiom" then
	pr l
	  (fun () ->
	    let nm = input_token ch in
	    if not (input_token ch = ":") then raise (Failure "bad format for prop of Axiom");
	    let m = input_trm baseh trmh ch [] [] in
	    match Checking.beta_eta_norm_fixed (ref 0) m with
	    | Some(m) ->
		let h = Mathdata.tm_hashroot m in
		Hashtbl.add proph nm h;
		Hashtbl.add prophrev h nm;
		thyspec := Logic.Thyaxiom(m)::!thyspec
	    | None -> raise (Failure (Printf.sprintf "trouble normalizing Axiom %s" nm)))
      else
	raise (Failure (Printf.sprintf "Unknown theory spec item %s" l))
    done;
    (!thyspec,!nonce,!gamma,proph,prophrev,propownsh,proprightsh)
  with
  | End_of_file -> close_in_noerr ch; (!thyspec,!nonce,!gamma,proph,prophrev,propownsh,proprightsh)
  | e -> close_in_noerr ch; raise e;;

(* Function to lookup a signature in the signature tree, raising a failure
   if the signature is not found *)
let ostree_lookup_fail sgt h =
  try
    ostree_lookup sgt h
  with Not_found ->
    raise (Failure (Printf.sprintf "Could not find signature %s\n" (match h with Some(h) -> hashval_hexstring h | None -> "Empty")))

(* Function to associate names with objects and propositions in a signature,
   raising a failure if there are insufficient or too many names given *)
let assoc_signa objhrev prophrev sgt sdone paramh trmh proph sg tmnl knnl =
  let tmnlr = ref tmnl in
  let knnlr = ref knnl in
  let rec assoc_signa_r sg =
    let (isl,(tml,knl)) = sg in
    (* Process the imported signatures *)
    List.iter
      (fun h ->
	if not (Hashtbl.mem sdone h) then
	  begin
	    Hashtbl.add sdone h ();
	    let (_,sg2) = ostree_lookup_fail sgt (Some(h)) in
	    assoc_signa_r sg2
	  end)
      (List.rev isl);
    (* Process the object names *)
    List.iter
      (fun ((h,a),_) ->
	match !tmnlr with
	| nm::nr ->
	    Hashtbl.add trmh nm (a,Logic.TmH(h));
	    Hashtbl.add paramh nm (a,h);
	    Hashtbl.add objhrev h nm;
	    tmnlr := nr
	| [] -> raise (Failure "insufficient obj names given with import"))
      (List.rev tml);
    (* Process the proposition names *)
    List.iter
      (fun (h,p) ->
	match !knnlr with
	| nm::nr ->
	    Hashtbl.add proph nm h;
	    Hashtbl.add prophrev h nm;
	    knnlr := nr
	| [] -> raise (Failure "insufficient prop names given with import"))
      (List.rev knl);
  in
  assoc_signa_r sg;
  (* Check that all names have been used *)
  begin
    match (!tmnlr,!knnlr) with
    | (nm1::_,nm2::_) -> raise (Failure (Printf.sprintf "too many names given starting at obj name %s and prop name %s" nm1 nm2))
    | (nm1::_,[]) -> raise (Failure (Printf.sprintf "too many obj names given starting at %s" nm1))
    | ([],nm2::_) -> raise (Failure (Printf.sprintf "too many prop names given starting at %s" nm2))
    | _ -> ()
  end

(* Function to read a signature specification from an input channel *)
let input_signaspec ch th sgt =
  let basec = ref 0 in
  let baseh : (string,int) Hashtbl.t = Hashtbl.create 10 in
  let sdone : (hashval,unit) Hashtbl.t = Hashtbl.create 100 in
  let paramh : (string,Logic.stp * hashval) Hashtbl.t = Hashtbl.create 100 in
  let objhrev : (hashval,string) Hashtbl.t = Hashtbl.create 100 in
  let trmh : (string,Logic.stp * Logic.trm) Hashtbl.t = Hashtbl.create 100 in
  let proph : (string,hashval) Hashtbl.t = Hashtbl.create 100 in
  let prophrev : (hashval,string) Hashtbl.t = Hashtbl.create 100 in
  let signaspec = ref [] in
  let nonce = ref None in
  let gamma = ref None in
  (* Function to process a single line of the signature specification *)
  let pr l f =
    try
      f()
    with End_of_file ->
      raise (Failure (Printf.sprintf "Incomplete %s" l))
  in
  try
    while true do
      let l = input_token ch in
      (* Process the nonce *)
      if l = "Nonce" then
	pr l
	  (fun () ->
	    let h = input_token ch in
	    match !nonce with
	    | None -> nonce := Some(hexstring_hashval h)
	    | Some(_) -> raise (Failure "two nonces where at most one is expected"))
      (* Process the publisher *)
      else if l = "Publisher" then
	pr l
	  (fun () ->
	    let h = input_token ch in
	    match !gamma with
	    | None -> gamma := Some(pfgaddrstr_addr h)
	    | Some(_) -> raise (Failure "two publishers where at most one is expected"))
      (* Process an included signature *)
      else if l = "Include" then
	pr l
	  (fun () ->
	    let h = hexstring_hashval (input_token ch) in
	    let (th2,sg) = ostree_lookup_fail sgt (Some(h)) in
	    if not (th = th2) then
	      raise (Failure (Printf.sprintf "signature %s is for a different theory: %s" (hashval_hexstring h) (match th2 with None -> "Empty" | Some(k) -> hashval_hexstring k)));
	    let rtokl1 = input_token_rev_list ch in
	    let rtokl2 = input_token_rev_list ch in
	    assoc_signa objhrev prophrev sgt sdone paramh trmh proph sg (List.rev rtokl1) (List.rev rtokl2);
	    signaspec := Logic.Signasigna(h)::!signaspec)
      (* Process a base type declaration *)
      else if l = "Base" then
	pr l
	  (fun () ->
	    let nm = input_token ch in
	    Hashtbl.add baseh nm !basec;
	    incr basec)
      (* Process a let binding (not part of the signature, but used to ease
         writing terms) *)
      else if l = "Let" then (** not part of the signature, but just to ease writing terms **)
	pr l
	  (fun () ->
	    let nm = input_token ch in
	    if not (input_token ch = ":") then raise (Failure "bad format for type of Let");
	    let a = input_stp baseh ch [] in
	    if not (input_token ch = ":=") then raise (Failure "bad format for term of Let");
	    let m = input_trm baseh trmh ch [] [] in
	    Hashtbl.add trmh nm (a,m))
      (* Process a parameter declaration *)
      else if l = "Param" then
	pr l
	  (fun () ->
	    let h = input_token ch in
	    let h = hexstring_hashval h in
	    let nm = input_token ch in
	    if not (input_token ch = ":") then raise (Failure "bad format for type of Prim");
	    let a = input_stp baseh ch [] in
	    Hashtbl.add trmh nm (a,Logic.TmH(h));
	    Hashtbl.add paramh nm (a,h);
	    Hashtbl.add objhrev h nm;
	    signaspec := Logic.Signaparam(h,a)::!signaspec)
      (* Process a definition *)
      else if l = "Def" then
	pr l
	  (fun () ->
	    let nm = input_token ch in
	    if not (input_token ch = ":") then raise (Failure "bad format for type of Def");
	    let a = input_stp baseh ch [] in
	    if not (input_token ch = ":=") then raise (Failure "bad format for term of Def");
	    let m = input_trm baseh trmh ch [] [] in
	    match Checking.beta_eta_norm_fixed (ref 0) m with
	    | Some(m) ->
		let h = Mathdata.tm_hashroot m in
		Hashtbl.add trmh nm (a,Logic.TmH(h));
		Hashtbl.add objhrev h nm;
		signaspec := Logic.Signadef(a,m)::!signaspec
	    | None -> raise (Failure (Printf.sprintf "trouble normalizing Def %s" nm)))
      (* Process a known proposition *)
      else if l = "Known" then
	pr l
	  (fun () ->
	    let nm = input_token ch in
	    if not (input_token ch = ":") then raise (Failure "bad format for prop of Known");
	    let m = input_trm baseh trmh ch [] [] in
	    match Checking.beta_eta_norm_fixed (ref 0) m with
	    | Some(m) ->
		let h = Mathdata.tm_hashroot m in
		Hashtbl.add proph nm h;
		Hashtbl.add prophrev h nm;
		signaspec := Logic.Signaknown(m)::!signaspec
	    | None -> raise (Failure (Printf.sprintf "trouble normalizing Axiom %s" nm)))
      (* Unknown signature specification item *)
      else
	raise (Failure (Printf.sprintf "Unknown signature spec item %s" l))
    done;
    (* Return the signature specification, nonce, publisher, and hash tables *)
    (!signaspec,!nonce,!gamma,paramh,objhrev,proph,prophrev)
  with
  | End_of_file -> close_in_noerr ch; (!signaspec,!nonce,!gamma,paramh,objhrev,proph,prophrev)
  | e -> close_in_noerr ch; raise e;;

(* Function to read a document from an input channel *)
let input_doc ch th sgt =
  (* Similar structure to input_signaspec, but with different processing for
     document-specific items such as NewOwner, NewRights, and Bounty *)
  let basec = ref 0 in
  let baseh : (string,int) Hashtbl.t = Hashtbl.create 10 in
  let sdone : (hashval,unit) Hashtbl.t = Hashtbl.create 100 in
  let paramh : (string,Logic.stp * hashval) Hashtbl.t = Hashtbl.create 100 in
  let objhrev : (hashval,string) Hashtbl.t = Hashtbl.create 100 in
  let defh : (string,hashval) Hashtbl.t = Hashtbl.create 100 in
  let trmh : (string,Logic.stp * Logic.trm) Hashtbl.t = Hashtbl.create 100 in
  let proph : (string,hashval) Hashtbl.t = Hashtbl.create 100 in
  let prophrev : (hashval,string) Hashtbl.t = Hashtbl.create 100 in
  let conjh : (string,hashval) Hashtbl.t = Hashtbl.create 100 in
  let thmh : (string,hashval) Hashtbl.t = Hashtbl.create 100 in
  let objownsh : (hashval,payaddr) Hashtbl.t = Hashtbl.create 100 in
  let objrightsh : (bool * hashval,payaddr * (int64 option)) Hashtbl.t = Hashtbl.create 100 in
  let propownsh : (hashval,payaddr) Hashtbl.t = Hashtbl.create 100 in
  let proprightsh : (bool * hashval,payaddr * (int64 option)) Hashtbl.t = Hashtbl.create 100 in
  let bountyh : (hashval,int64 * (payaddr * int64) option) Hashtbl.t = Hashtbl.create 100 in
  let doc = ref [] in
  let nonce = ref None in
  let gamma = ref None in
  let pr l f =
    try
      f()
    with
    | End_of_file ->
      raise (Failure (Printf.sprintf "Incomplete %s" l))
  in
  try
    while true do
      let l = input_token ch in
      if l = "Nonce" then
	pr l
	  (fun () ->
	    let h = input_token ch in
	    match !nonce with
	    | None -> nonce := Some(hexstring_hashval h)
	    | Some(_) -> raise (Failure "two nonces where at most one is expected"))
      else if l = "Publisher" then
	pr l
	  (fun () ->
	    let h = input_token ch in
	    match !gamma with
	    | None -> gamma := Some(pfgaddrstr_addr h)
	    | Some(_) -> raise (Failure "two publishers where at most one is expected"))
      else if l = "Include" then
	pr l
	  (fun () ->
	    let h = hexstring_hashval (input_token ch) in
	    let (th2,sg) = ostree_lookup_fail sgt (Some(h)) in
	    if not (th = th2) then
	      raise (Failure (Printf.sprintf "signature %s is for a different theory: %s" (hashval_hexstring h) (match th2 with None -> "Empty" | Some(k) -> hashval_hexstring k)));
	    let rtokl1 = input_token_rev_list ch in
	    let rtokl2 = input_token_rev_list ch in
	    assoc_signa objhrev prophrev sgt sdone paramh trmh proph sg (List.rev rtokl1) (List.rev rtokl2);
	    doc := Logic.Docsigna(h)::!doc)
      else if l = "NewOwner" then
	pr l
	  (fun () ->
	    let nm = input_token ch in
	    let gammas = input_token ch in
	    let gamma = pfgaddrstr_addr gammas in
	    if payaddr_p gamma then
	      let gammap = let (i,xs) = gamma in (i = 1,xs) in
	      begin
		try
		  let h = Hashtbl.find thmh nm in
		  Hashtbl.add propownsh h gammap
		with Not_found ->
		  try
		    let h = Hashtbl.find defh nm in
		    Hashtbl.add objownsh h gammap
		  with Not_found ->
		    if not (Hashtbl.mem trmh nm) then
		      raise (Failure (Printf.sprintf "Unknown definition or theorem %s to assign ownership to" nm))
	      end
	    else
	      raise (Failure (Printf.sprintf "%s cannot be an owner since it is not a pay address" gammas)))
      else if l = "NewRights" then
	pr l
	  (fun () ->
	    let nm = input_token ch in
	    let gammas = input_token ch in
	    let gamma = pfgaddrstr_addr gammas in
	    if payaddr_p gamma then
	      let gammap = let (i,xs) = gamma in (i = 1,xs) in
	      begin
		let price = input_token ch in
		let price =
		  if price = "Free" then
		    Some(0L)
		  else if price = "None" then
		    None
		  else
		    Some(atoms_of_bars price)
		in
		begin
		  try
		    let h = Hashtbl.find thmh nm in
		    Hashtbl.add proprightsh (false,h) (gammap,price);
		    Hashtbl.add proprightsh (true,h) (gammap,price)
		  with Not_found ->
		    try
		      let h = Hashtbl.find defh nm in
		      Hashtbl.add objrightsh (false,h) (gammap,price);
		      Hashtbl.add objrightsh (true,h) (gammap,price)
		    with Not_found ->
		      if not (Hashtbl.mem trmh nm) then
			raise (Failure (Printf.sprintf "Unknown definition or theorem %s to give rights for" nm))
		end
	      end
	    else
	      raise (Failure (Printf.sprintf "%s cannot be an address for rights since it is not a pay address" gammas)))
      else if l = "NewPureRights" then
	pr l
	  (fun () ->
	    let nm = input_token ch in
	    let gammas = input_token ch in
	    let gamma = pfgaddrstr_addr gammas in
	    if payaddr_p gamma then
	      let gammap = let (i,xs) = gamma in (i = 1,xs) in
	      begin
		let price = input_token ch in
		let price =
		  if price = "Free" then
		    Some(0L)
		  else if price = "None" then
		    None
		  else
		    Some(atoms_of_bars price)
		in
		begin
		  try
		    let h = Hashtbl.find thmh nm in
		    Hashtbl.add proprightsh (false,h) (gammap,price)
		  with Not_found ->
		    try
		      let h = Hashtbl.find defh nm in
		      Hashtbl.add objrightsh (false,h) (gammap,price)
		    with Not_found ->
		      if not (Hashtbl.mem trmh nm) then
			raise (Failure (Printf.sprintf "Unknown definition or theorem %s to give rights for" nm))
		end
	      end
	    else
	      raise (Failure (Printf.sprintf "%s cannot be an address for rights since it is not a pay address" gammas)))
      else if l = "NewTheoryRights" then
	pr l
	  (fun () ->
	    let nm = input_token ch in
	    let gammas = input_token ch in
	    let gamma = pfgaddrstr_addr gammas in
	    if payaddr_p gamma then
	      let gammap = let (i,xs) = gamma in (i = 1,xs) in
	      begin
		let price = input_token ch in
		let price =
		  if price = "Free" then
		    Some(0L)
		  else if price = "None" then
		    None
		  else
		    Some(atoms_of_bars price)
		in
		begin
		  try
		    let h = Hashtbl.find thmh nm in
		    Hashtbl.add proprightsh (true,h) (gammap,price)
		  with Not_found ->
		    try
		      let h = Hashtbl.find defh nm in
		      Hashtbl.add objrightsh (true,h) (gammap,price)
		    with Not_found ->
		      if not (Hashtbl.mem trmh nm) then
			raise (Failure (Printf.sprintf "Unknown definition or theorem %s to give rights for" nm))
		end
	      end
	    else
	      raise (Failure (Printf.sprintf "%s cannot be an address for rights since it is not a pay address" gammas)))
      else if l = "Bounty" then
	pr l
	  (fun () ->
	    let nm = input_token ch in
	    let amt = atoms_of_bars (input_token ch) in
	    try
	      let h = Hashtbl.find conjh nm in
	      let lkh = input_token ch in (** potential lock height for reclaiming bounty without proof **)
	      if lkh = "NoTimeout" then
		Hashtbl.add bountyh h (amt,None)
	      else
		let lkh = Int64.of_string lkh in (** lock height, after which the bounty can be reclaimed by gamma if unclaimed **)
		let gammas = input_token ch in
		let gamma = pfgaddrstr_addr gammas in
		if payaddr_p gamma then
		  let gammap = let (i,xs) = gamma in (i = 1,xs) in
		  begin
		    Hashtbl.add bountyh h (amt,Some(gammap,lkh))
		  end
		else
		  raise (Failure (Printf.sprintf "%s is not a pay address" gammas))
	    with Not_found ->
	      raise (Failure (Printf.sprintf "%s is not the name of a conjecture" nm)))
      else if l = "Base" then
	pr l
	  (fun () ->
	    let nm = input_token ch in
	    Hashtbl.add baseh nm !basec;
	    incr basec)
      else if l = "Let" then (** not part of the document, but just to ease writing terms **)
	pr l
	  (fun () ->
	    let nm = input_token ch in
	    if not (input_token ch = ":") then raise (Failure "bad format for type of Let");
	    let a = input_stp baseh ch [] in
	    if not (input_token ch = ":=") then raise (Failure "bad format for term of Let");
	    let m = input_trm baseh trmh ch [] [] in
	    Hashtbl.add trmh nm (a,m))
      else if l = "Param" then
	pr l
	  (fun () ->
	    let h = input_token ch in
	    let h = hexstring_hashval h in
	    let nm = input_token ch in
	    if not (input_token ch = ":") then raise (Failure "bad format for type of Prim");
	    let a = input_stp baseh ch [] in
	    Hashtbl.add trmh nm (a,Logic.TmH(h));
	    Hashtbl.add paramh nm (a,h);
	    Hashtbl.add objhrev h nm;
	    doc := Logic.Docparam(h,a)::!doc)
      else if l = "Def" then
	pr l
	  (fun () ->
	    let nm = input_token ch in
	    if not (input_token ch = ":") then raise (Failure "bad format for type of Def");
	    let a = input_stp baseh ch [] in
	    if not (input_token ch = ":=") then raise (Failure "bad format for term of Def");
	    let m = input_trm baseh trmh ch [] [] in
	    match Checking.beta_eta_norm_fixed (ref 0) m with
	    | Some(m) ->
		let h = Mathdata.tm_hashroot m in
		Hashtbl.add trmh nm (a,Logic.TmH(h));
		Hashtbl.add defh nm h; (* definition; if this is "new" then an owner and rights will be given *)
		Hashtbl.add objhrev h nm;
		doc := Logic.Docdef(a,m)::!doc
	    | None -> raise (Failure (Printf.sprintf "trouble normalizing Def %s" nm)))
      else if l = "Known" then
	pr l
	  (fun () ->
	    let nm = input_token ch in
	    if not (input_token ch = ":") then raise (Failure "bad format for prop of Known");
	    let m = input_trm baseh trmh ch [] [] in
	    match Checking.beta_eta_norm_fixed (ref 0) m with
	    | Some(m) ->
		let h = Mathdata.tm_hashroot m in
		Hashtbl.add proph nm h;
		Hashtbl.add prophrev h nm;
		doc := Logic.Docknown(m)::!doc
	    | None -> raise (Failure (Printf.sprintf "trouble normalizing Axiom %s" nm)))
      else if l = "Conj" then
	pr l
	  (fun () ->
	    let nm = input_token ch in
	    if not (input_token ch = ":") then raise (Failure "bad format for prop of Conj");
	    let m = input_trm baseh trmh ch [] [] in
	    match Checking.beta_eta_norm_fixed (ref 0) m with
	    | Some(m) ->
 	        let h = Mathdata.tm_hashroot m in
		Hashtbl.add conjh nm h; (* conjecture: a bounty can be declared *)
		Hashtbl.add prophrev h nm;
		doc := Logic.Docconj(m)::!doc
	    | None -> raise (Failure (Printf.sprintf "trouble normalizing Axiom %s" nm)))
      else if l = "Thm" then
	pr l
	  (fun () ->
	    let nm = input_token ch in
	    if not (input_token ch = ":") then raise (Failure "bad format for prop of Thm");
	    let m = input_trm baseh trmh ch [] [] in
	    if not (input_token ch = ":=") then raise (Failure "bad format for proof of Thm");
	    let d = input_pf baseh trmh proph ch [] [] [] in
	    match Checking.beta_eta_norm_fixed (ref 0) m with
	    | Some(m) ->
		let h = Mathdata.tm_hashroot m in
		Hashtbl.add proph nm h;
		Hashtbl.add prophrev h nm;
		Hashtbl.add thmh nm h; (* theorem: if this is a newly proven proposition, then an owner and rights will be declared *)
		doc := Logic.Docpfof(m,d)::!doc
	    | None -> raise (Failure (Printf.sprintf "trouble normalizing Axiom %s" nm)))
      else
	raise (Failure (Printf.sprintf "Unknown document item %s" l))
    done;
    (!doc,!nonce,!gamma,paramh,objhrev,proph,prophrev,conjh,objownsh,objrightsh,propownsh,proprightsh,bountyh)
  with
  | End_of_file -> close_in_noerr ch; (!doc,!nonce,!gamma,paramh,objhrev,proph,prophrev,conjh,objownsh,objrightsh,propownsh,proprightsh,bountyh)
  | e -> close_in_noerr ch; raise e;;

(* Recursively output a string representation of a type *)
let rec output_stp a bh =
  match a with
  | TpArr(a,b) ->
     Printf.sprintf "TpArr %s %s" (output_stp a bh) (output_stp b bh)
  | Prop -> "Prop"
  | Base(i) -> try Hashtbl.find bh i with _ -> "?"

(* Recursively output a string representation of a term *)
let rec output_trm m bh trmh leth vl =
  try
    Hashtbl.find leth m
  with Not_found ->
        match m with
        | DB(i) -> (try List.nth vl i with _ -> "?")
        | TmH(h) -> (try Hashtbl.find trmh h with _ -> "?")
        | Prim(i) -> Printf.sprintf "Prim %d" i
        | Ap(m1,m2) ->
           Printf.sprintf "Ap %s %s" (output_trm m1 bh trmh leth vl) (output_trm m2 bh trmh leth vl)
        | Lam(a,m1) ->
           let x = Printf.sprintf "X%d" (List.length vl) in
           Printf.sprintf "Lam %s %s %s" x (output_stp a bh) (output_trm m1 bh trmh leth (x::vl))
        | Imp(m1,m2) ->
           Printf.sprintf "Imp %s %s" (output_trm m1 bh trmh leth vl) (output_trm m2 bh trmh leth vl)
        | All(a,m1) ->
           let x = Printf.sprintf "X%d" (List.length vl) in
           Printf.sprintf "All %s %s %s" x (output_stp a bh) (output_trm m1 bh trmh leth (x::vl))
        | Ex(a,m1) ->
           let x = Printf.sprintf "X%d" (List.length vl) in
           Printf.sprintf "Ex %s %s %s" x (output_stp a bh) (output_trm m1 bh trmh leth (x::vl))
        | Eq(a,m1,m2) ->
           Printf.sprintf "Eq %s %s %s" (output_stp a bh) (output_trm m1 bh trmh leth vl) (output_trm m2 bh trmh leth vl)
       
(* Recursively output a string representation of a proof *)
let rec output_pf d bh trmh leth knh vl hypl =
  match d with
  | Hyp(i) -> (try List.nth hypl i with _ -> "?")
  | Known(h) -> (try Hashtbl.find knh h with _ -> "?")
  | PrAp(d1,d2) ->
     Printf.sprintf "PrAp %s %s"
       (output_pf d1 bh trmh leth knh vl hypl)
       (output_pf d2 bh trmh leth knh vl hypl)
  | TmAp(d1,m2) ->
     Printf.sprintf "TmAp %s %s"
       (output_pf d1 bh trmh leth knh vl hypl)
       (output_trm m2 bh trmh leth vl)
  | PrLa(p1,d2) ->
     let u = Printf.sprintf "H%d" (List.length hypl) in
     Printf.sprintf "PrLa %s %s %s" u
       (output_trm p1 bh trmh leth vl)
       (output_pf d2 bh trmh leth knh vl (u::hypl))
  | TmLa(a1,d2) ->
     let x = Printf.sprintf "X%d" (List.length vl) in
     Printf.sprintf "TmLa %s %s %s" x
       (output_stp a1 bh)
       (output_pf d2 bh trmh leth knh (x::vl) hypl)
  | Ext(a,b) -> Printf.sprintf "Ext %s %s" (output_stp a bh) (output_stp b bh)

(* Recursively output let bindings for primitive recursive functions used in a term *)
let rec decl_let_hfprims c bh leth m =
  match m with
  | Prim(i) ->
     begin
       if not (Hashtbl.mem leth (Prim(i))) then
         begin
           try
             let nm = Checking.hfprimnamesa.(i) in
             let a = List.nth Checking.hfprimtps i in
             Printf.fprintf c "Let %s : %s := Prim %d\n" nm (output_stp a bh) i;
             Hashtbl.add leth (Prim(i)) nm
           with _ -> ()
         end
     end
  | Ap(m1,m2) -> decl_let_hfprims c bh leth m1; decl_let_hfprims c bh leth m2
  | Lam(_,m1) -> decl_let_hfprims c bh leth m1
  | Imp(m1,m2) -> decl_let_hfprims c bh leth m1; decl_let_hfprims c bh leth m2
  | All(_,m1) -> decl_let_hfprims c bh leth m1
  | Ex(_,m1) -> decl_let_hfprims c bh leth m1
  | Eq(_,m1,m2) -> decl_let_hfprims c bh leth m1; decl_let_hfprims c bh leth m2
  | _ -> ()
           
