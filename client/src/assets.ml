(* Copyright (c) 2020 The Proofgold developers *)
(* Copyright (c) 2015-2016 The Qeditas developers *)
(* Copyright (c) 2017-2018 The Dalilcoin developers *)
(* Distributed under the MIT software license, see the accompanying
   file COPYING or http://www.opensource.org/licenses/mit-license.php. *)

open Json
open Ser
open Hash
open Net
open Db
open Cryptocurr
open Mathdata
open Checking 
open Logic 

(*** If the obligation is Some(alpha,n,r), then the way to spend the asset is for alpha to sign after block n.
 If r is true then the asset was a reward and can be forfeited as a consequence of double signing.
 ***)
type obligation = (payaddr * int64 * bool) option

type preasset =
  | Currency of int64
  | Bounty of int64
  | OwnsObj of hashval * payaddr * int64 option
  | OwnsProp of hashval * payaddr * int64 option
  | OwnsNegProp
  | RightsObj of hashval * int64
  | RightsProp of hashval * int64
  | Marker
  | TheoryPublication of payaddr * hashval * theoryspec
  | SignaPublication of payaddr * hashval * hashval option * signaspec
  | DocPublication of payaddr * hashval * hashval option * doc

let obligation_string o =
  match o with
  | None -> "default obligation"
  | Some(beta,lkh,r) ->
      "obligation: controlled by " ^ (addr_pfgaddrstr (payaddr_addr beta)) ^ ";locked until height " ^ (Int64.to_string lkh) ^ ";" ^ (if r then "reward" else "not a reward")

let preasset_string u =
  match u with
  | Currency(v) -> bars_of_atoms v ^ " bars"
  | Bounty(v) -> "bounty of " ^ bars_of_atoms v ^ " bars"
  | OwnsObj(h,beta,None) -> "ownership of " ^ (hashval_hexstring h) ^ " as an object with payaddr " ^ (addr_pfgaddrstr (payaddr_addr beta)) ^ " with no rights available"
  | OwnsObj(h,beta,Some(r)) -> "ownership of " ^ (hashval_hexstring h) ^ " as an object with payaddr " ^ (addr_pfgaddrstr (payaddr_addr beta)) ^ "; each right to use costs " ^ bars_of_atoms r ^ " bars"
  | OwnsProp(h,beta,None) -> "ownership of " ^ (hashval_hexstring h) ^ " as a proposition with payaddr " ^ (addr_pfgaddrstr (payaddr_addr beta)) ^ " with no rights available"
  | OwnsProp(h,beta,Some(r)) -> "ownership of " ^ (hashval_hexstring h) ^ " as a proposition with payaddr " ^ (addr_pfgaddrstr (payaddr_addr beta)) ^ "; each right to use costs " ^ bars_of_atoms r ^ " bars"
  | OwnsNegProp -> "neg prop ownership"
  | RightsObj(h,l) -> "right to use " ^ (hashval_hexstring h) ^ " as an object " ^ (Int64.to_string l) ^ " times"
  | RightsProp(h,l) -> "right to use " ^ (hashval_hexstring h) ^ " as a proposition " ^ (Int64.to_string l) ^ " times"
  | Marker -> "marker"
  | TheoryPublication(beta,_,_) -> "theory published by " ^ addr_pfgaddrstr (payaddr_addr beta)
  | SignaPublication(beta,_,_,_) -> "signature published by " ^ addr_pfgaddrstr (payaddr_addr beta)
  | DocPublication(beta,_,_,_) -> "document published by " ^ addr_pfgaddrstr (payaddr_addr beta)


(*** asset is (assetid,birthday,obligation,preasset) ***)
type asset = hashval * int64 * obligation * preasset

let assetid ((h,bd,obl,u):asset) : hashval = h
let assetbday ((h,bd,obl,u):asset) : int64 = bd
let assetobl ((h,bd,obl,u):asset) : obligation = obl
let assetpre ((h,bd,obl,u):asset) : preasset = u

let hashpreasset u =
  match u with
  | Currency(v) -> hashtag (hashint64 v) 256l
  | Bounty(v) -> hashtag (hashint64 v) 257l
  | OwnsObj(h,a,None) -> hashtag (hashpair h (hashpayaddr a)) 258l
  | OwnsObj(h,a,Some(v)) -> hashtag (hashpair h (hashpair (hashpayaddr a) (hashint64 v))) 259l
  | OwnsProp(h,a,None) -> hashtag (hashpair h (hashpayaddr a)) 260l
  | OwnsProp(h,a,Some(v)) -> hashtag (hashpair h (hashpair (hashpayaddr a) (hashint64 v))) 261l
  | OwnsNegProp -> hashint32 262l
  | RightsObj(h,v) -> hashtag (hashpair h (hashint64 v)) 263l
  | RightsProp(h,v) -> hashtag (hashpair h (hashint64 v)) 264l
  | Marker -> hashint32 265l
  | TheoryPublication(a,nonce,ths) -> hashtag (hashpair (hashpayaddr a) (hashopair1 nonce (hashtheory (theoryspec_theory ths)))) 266l (*** this only ensures the compiled theory gets a unique hash value ***)
  | SignaPublication(a,nonce,th,s) -> hashtag (hashpair (hashpayaddr a) (hashpair nonce (hashopair2 th (hashsigna (signaspec_signa s))))) 267l (*** this only ensures the compiled signature gets a unique hash value ***)
  | DocPublication(a,nonce,th,d) -> hashtag (hashpair (hashpayaddr a) (hashpair nonce (hashopair2 th (hashdoc d)))) 268l

let hashobligation (x:obligation) : hashval option =
  match x with
  | None -> None
  | Some(a,n,r) -> Some(hashpair (hashpayaddr a) (hashtag (hashint64 n) (if r then 1025l else 1024l)))

let hashasset a =
  let (h,bd,obl,u) = a in
  hashopair1 (hashpair h (hashpair (hashint64 bd) (hashpreasset u))) (hashobligation obl)

type addr_assetid = addr * hashval
type addr_preasset = addr * (obligation * preasset)
type addr_asset = addr * asset

let hash_addr_assetid (alpha,h) = hashpair (hashaddr alpha) h
let hash_addr_preasset (alpha,(obl,u)) = hashpair (hashaddr alpha) (hashopair2 (hashobligation obl) (hashpreasset u))
let hash_addr_asset (alpha,a) = hashpair (hashaddr alpha) (hashasset a)

let rec new_assets bday alpha aul txh i : asset list =
  match aul with
  | [] -> []
  | (beta,(obl,u))::aur when beta = alpha ->
      (hashpair txh (hashint32 i),bday,obl,u)::new_assets bday alpha aur txh (Int32.add i 1l)
  | _::aur -> new_assets bday alpha aur txh (Int32.add i 1l)

let rec remove_assets al spent : asset list =
  match al with
  | [] -> []
  | a::ar when List.mem (assetid a) spent -> remove_assets ar spent
  | a::ar -> a::remove_assets ar spent

let rec get_spent alpha inpl : hashval list =
  match inpl with
  | [] -> []
  | (beta,a)::inpr when alpha = beta -> a::get_spent alpha inpr
  | (beta,a)::inpr -> get_spent alpha inpr

let rec add_vout bday txh outpl i =
  match outpl with
  | [] -> []
  | (alpha,(obl,u))::outpr -> (alpha,(hashpair txh (hashint32 i),bday,obl,u))::add_vout bday txh outpr (Int32.add i 1l)

let preasset_value blkh bday u =
  match u with
  | Currency v ->
      Some
	begin
	  if bday = 0L && blkh >= 730L then (*** initial distribution halves every 730 blocks (6 months) until block 39420 (27 years) at which time the initial distribution has value 0 ***)
	    if blkh < 39420L then
	      let blki = Int64.to_int blkh in
	      Int64.shift_right v (blki / 730)
	    else
	      0L
	  else
	    v
	end
  | Bounty v -> Some v
  | _ -> None

let asset_value blkh u = preasset_value blkh (assetbday u) (assetpre u)

let asset_value_sum blkh al =
  List.fold_left Int64.add 0L (List.map (fun a -> match asset_value blkh a with Some v -> v | None -> 0L) al)

let rec output_signaspec_uses_objs (outpl:addr_preasset list) : (hashval * hashval) list =
  match outpl with
  | (_,(_,SignaPublication(_,_,th,d)))::outpr ->
      List.map (fun (h,tph) -> (h,hashtag (hashopair2 th (hashpair h tph)) 32l)) (signaspec_uses_objs d)
      @ output_signaspec_uses_objs outpr
  | _::outpr -> output_signaspec_uses_objs outpr
  | [] -> []

let rec output_signaspec_uses_props (outpl:addr_preasset list) : (hashval * hashval) list =
  match outpl with
  | (_,(_,SignaPublication(_,_,th,d)))::outpr ->
      List.map (fun h -> (h,hashtag (hashopair2 th h) 33l)) (signaspec_uses_props d)
      @ output_signaspec_uses_props outpr
  | _::outpr -> output_signaspec_uses_props outpr
  | [] -> []

let rec output_doc_uses_objs (outpl:addr_preasset list) : (hashval * hashval) list =
  match outpl with
  | (_,(_,DocPublication(_,_,th,d)))::outpr ->
      List.map (fun (h,tph) -> (h,hashtag (hashopair2 th (hashpair h tph)) 32l)) (doc_uses_objs d)
      @ output_doc_uses_objs outpr
  | _::outpr -> output_doc_uses_objs outpr
  | [] -> []

let rec output_doc_uses_props (outpl:addr_preasset list) : (hashval * hashval) list =
  match outpl with
  | (_,(_,DocPublication(_,_,th,d)))::outpr ->
      List.map (fun h -> (h,hashtag (hashopair2 th h) 33l)) (doc_uses_props d)
      @ output_doc_uses_props outpr
  | _::outpr -> output_doc_uses_props outpr
  | [] -> []

let rec output_creates_objs (outpl:addr_preasset list) : (hashval option * hashval * hashval) list =
  match outpl with
  | (_,(_,DocPublication(_,_,th,d)))::outpr ->
      List.map (fun (h,k) -> (th,h,k)) (doc_creates_objs d) @ output_creates_objs outpr
  | _::outpr -> output_creates_objs outpr
  | [] -> []

let rec output_creates_props (outpl:addr_preasset list) : (hashval option * hashval) list =
  match outpl with
  | (_,(_,DocPublication(_,_,th,d)))::outpr ->
      List.map (fun h -> (th,h)) (doc_creates_props d) @ output_creates_props outpr
  | (_,(_,TheoryPublication(_,_,d)))::outpr -> (*** Axioms created by theories also need to be considered "created" so they will be given owners when published. ***)
      let (pl,kl) = theoryspec_theory d in
      let th = hashtheory (pl,kl) in
      List.map (fun h -> (th,h)) kl @ output_creates_props outpr
  | _::outpr -> output_creates_props outpr
  | [] -> []

let rec output_creates_neg_props (outpl:addr_preasset list) : (hashval option * hashval) list =
  match outpl with
  | (_,(_,DocPublication(_,_,th,d)))::outpr ->
      List.map (fun h -> (th,h)) (doc_creates_neg_props d) @ output_creates_neg_props outpr
  | _::outpr -> output_creates_neg_props outpr
  | [] -> []

let rec rights_out_obj outpl k =
  match outpl with
  | (_,(_,RightsObj(h,n)))::outpr when h = k -> Int64.add n (rights_out_obj outpr k)
  | _::outpr -> rights_out_obj outpr k
  | [] -> 0L

let rec rights_out_prop outpl k =
  match outpl with
  | (_,(_,RightsProp(h,n)))::outpr when h = k -> Int64.add n (rights_out_prop outpr k)
  | _::outpr -> rights_out_prop outpr k
  | [] -> 0L

let rec count_obj_rights al k =
  match al with
  | (_,_,_,RightsObj(h,n))::ar when h = k -> Int64.add n (count_obj_rights ar k)
  | _::ar -> count_obj_rights ar k
  | [] -> 0L

let rec count_prop_rights al k =
  match al with
  | (_,_,_,RightsProp(h,n))::ar when h = k -> Int64.add n (count_prop_rights ar k)
  | _::ar -> count_prop_rights ar k
  | [] -> 0L

let rec count_rights_used bl k =
  match bl with
  | (h1,h2)::br when h1 = k || h2 = k -> 1+count_rights_used br k
  | _::br -> count_rights_used br k
  | [] -> 0

let rec obj_rights_mentioned_aux outpl r =
  match outpl with
  | (beta,(obl,RightsObj(h,n)))::outpr ->
      obj_rights_mentioned_aux outpr (h::r)
  | (_,(_,DocPublication(_,_,th,d)))::outpr ->
      let duo = doc_uses_objs d in
      obj_rights_mentioned_aux outpr
	(List.map (fun (h,tph) -> h) duo
	 @ List.map (fun (h,tph) -> hashtag (hashopair2 th (hashpair h tph)) 32l) duo
	 @ r)
  | _::outpr -> obj_rights_mentioned_aux outpr r
  | [] -> r

let obj_rights_mentioned outpl = obj_rights_mentioned_aux outpl []

let rec prop_rights_mentioned_aux outpl r =
  match outpl with
  | (beta,(obl,RightsProp(h,n)))::outpr ->
      prop_rights_mentioned_aux outpr (h::r)
  | (_,(_,DocPublication(_,_,th,d)))::outpr ->
      let dup = doc_uses_props d in
      prop_rights_mentioned_aux outpr
	(dup @ List.map (fun h -> hashtag (hashopair2 th h) 33l) dup @ r)
  | _::outpr -> prop_rights_mentioned_aux outpr r
  | [] -> r

let prop_rights_mentioned outpl = prop_rights_mentioned_aux outpl []

let rights_mentioned outpl = prop_rights_mentioned_aux outpl (obj_rights_mentioned_aux outpl [])

let rec units_sent_to_addr beta outpl =
  match outpl with
  | (alpha,(None,Currency(u)))::outpr when alpha = beta -> Int64.add u (units_sent_to_addr beta outpr) (*** important that the default None obligation is used here, since otherwise someone could "buy" rights without turning over control of the currency paid ***)
  | _::outpr -> units_sent_to_addr beta outpr
  | [] -> 0L

(*** Sum of currency and bounties output as well as the amount that must be burned to publish theories and signatures. ***)
let rec out_cost outpl =
  match outpl with
  | (alpha,(obl,Currency(u)))::outpr -> Int64.add u (out_cost outpr)
  | (alpha,(obl,Bounty(u)))::outpr -> Int64.add u (out_cost outpr)
  | (alpha,(obl,TheoryPublication(_,_,s)))::outpr -> Int64.add (theoryspec_burncost s) (out_cost outpr)
  | (alpha,(obl,SignaPublication(_,_,_,s)))::outpr -> Int64.add (signaspec_burncost s) (out_cost outpr)
  | _::outpr -> out_cost outpr
  | [] -> 0L

(** * serialization **)

let seo_obligation o obl c =
  seo_option (seo_prod3 seo_payaddr seo_int64 seo_bool) o obl c

let sei_obligation i c =
  sei_option (sei_prod3 sei_payaddr sei_int64 sei_bool) i c

let seo_preasset o u c =
  match u with
  | Currency(v) -> (** 000 **)
      let c = o 3 0 c in
      seo_int64 o v c
  | Bounty(v) -> (** 001 **)
      let c = o 3 1 c in
      seo_int64 o v c
  | OwnsObj(h,alpha,r) -> (** 010 0 **)
      let c = o 4 2 c in
      let c = seo_hashval o h c in
      let c = seo_payaddr o alpha c in
      seo_option seo_int64 o r c
  | OwnsProp(h,alpha,r) -> (** 010 1 0 **)
      let c = o 5 10 c in
      let c = seo_hashval o h c in
      let c = seo_payaddr o alpha c in
      seo_option seo_int64 o r c
  | OwnsNegProp -> (** 010 1 1 **)
      let c = o 5 26 c in
      c
  | RightsObj(h,n) -> (** 011 0 **)
      let c = o 4 3 c in
      let c = seo_hashval o h c in
      seo_int64 o n c
  | RightsProp(h,n) -> (** 011 1 **)
      let c = o 4 11 c in
      let c = seo_hashval o h c in
      seo_int64 o n c
  | Marker -> (** 100 **)
      let c = o 3 4 c in
      c
  | TheoryPublication(alpha,h,dl) -> (** 101 **)
      let c = o 3 5 c in
      let c = seo_payaddr o alpha c in
      let c = seo_hashval o h c in
      seo_theoryspec o dl c
  | SignaPublication(alpha,h,th,dl) -> (** 110 **)
      let c = o 3 6 c in
      let c = seo_payaddr o alpha c in
      let c = seo_hashval o h c in
      let c = seo_option seo_hashval o th c in
      seo_signaspec o dl c
  | DocPublication(alpha,h,th,dl) -> (** 111 **)
      let c = o 3 7 c in
      let c = seo_payaddr o alpha c in
      let c = seo_hashval o h c in
      let c = seo_option seo_hashval o th c in
      seo_doc o dl c

let sei_preasset i c =
  let (x,c) = i 3 c in
  if x = 0 then
    let (v,c) = sei_int64 i c in
    (Currency(v),c)
  else if x = 1 then
    let (v,c) = sei_int64 i c in
    (Bounty(v),c)
  else if x = 2 then
    let (y,c) = i 1 c in
    if y = 0 then
      let (h,c) = sei_hashval i c in
      let (alpha,c) = sei_payaddr i c in
      let (r,c) = sei_option sei_int64 i c in
      (OwnsObj(h,alpha,r),c)
    else
      let (z,c) = i 1 c in
      if z = 0 then
	let (h,c) = sei_hashval i c in
	let (alpha,c) = sei_payaddr i c in
	let (r,c) = sei_option sei_int64 i c in
	(OwnsProp(h,alpha,r),c)
      else
	(OwnsNegProp,c)
  else if x = 3 then
    let (y,c) = i 1 c in
    let (h,c) = sei_hashval i c in
    let (n,c) = sei_int64 i c in
    if y = 0 then
      (RightsObj(h,n),c)
    else
      (RightsProp(h,n),c)
  else if x = 4 then
    (Marker,c)
  else if x = 5 then
    let (alpha,c) = sei_payaddr i c in
    let (h,c) = sei_hashval i c in
    let (dl,c) = sei_theoryspec i c in
    (TheoryPublication(alpha,h,dl),c)
  else if x = 6 then
    let (alpha,c) = sei_payaddr i c in
    let (h,c) = sei_hashval i c in
    let (th,c) = sei_option sei_hashval i c in
    let (dl,c) = sei_signaspec i c in
    (SignaPublication(alpha,h,th,dl),c)
  else
    let (alpha,c) = sei_payaddr i c in
    let (h,c) = sei_hashval i c in
    let (th,c) = sei_option sei_hashval i c in
    let (dl,c) = sei_doc i c in
    (DocPublication(alpha,h,th,dl),c)

let seo_asset o a c = seo_prod4 seo_hashval seo_int64 seo_obligation seo_preasset o a c
let sei_asset i c = sei_prod4 sei_hashval sei_int64 sei_obligation sei_preasset i c

let seo_addr_assetid o u c = seo_prod seo_addr seo_hashval o u c
let sei_addr_assetid i c = sei_prod sei_addr sei_hashval i c
let seo_addr_preasset o u c = seo_prod seo_addr (seo_prod seo_obligation seo_preasset) o u c
let sei_addr_preasset i c = sei_prod sei_addr (sei_prod sei_obligation sei_preasset) i c
let seo_addr_asset o a c = seo_prod seo_addr seo_asset o a c
let sei_addr_asset i c = sei_prod sei_addr sei_asset i c

module DbAsset = Dbmbasic (struct type t = asset let basedir = "asset" let seival = sei_asset seis let seoval = seo_asset seosb end)

module DbAssetIdAt = Dbmbasic (struct type t = addr let basedir = "assetidat" let seival = sei_addr seis let seoval = seo_addr seosb end)

let get_asset h =
  try
    DbAsset.dbget h
  with Not_found -> (*** request it and fail ***)
    broadcast_requestdata GetAsset h;
    raise GettingRemoteData;;

Hashtbl.add msgtype_handler GetAsset
    (fun (sin,sout,cs,ms) ->
      let (h,_) = sei_hashval seis (ms,String.length ms,None,0,0) in
      let i = int_of_msgtype GetAsset in
      let tm = Unix.time() in
      if not (recently_sent (i,h) tm cs.sentinv) then (*** don't resend ***)
	try
	  let a = DbAsset.dbget h in
	  let asb = Buffer.create 100 in
	  seosbf (seo_asset seosb a (seo_hashval seosb h (asb,None)));
	  let aser = Buffer.contents asb in
	  ignore (queue_msg cs Asset aser);
	  Hashtbl.replace cs.sentinv (i,h) tm
	with Not_found -> ());;

Hashtbl.add msgtype_handler Asset
    (fun (sin,sout,cs,ms) ->
      let (h,r) = sei_hashval seis (ms,String.length ms,None,0,0) in
      let i = int_of_msgtype GetAsset in
      if not (DbAsset.dbexists h) then (*** if we already have it, abort ***)
	let tm = Unix.time() in
	if liberally_accept_elements_p tm || recently_requested (i,h) tm cs.invreq then (*** only continue if it was requested or we're liberally accepting elements to get the full ledger ***)
          let (a,r) = sei_asset seis r in
  	  DbAsset.dbput h a;
	  Hashtbl.remove cs.invreq (i,h)
	else (*** if something unrequested was sent, then seems to be a misbehaving peer ***)
	  (Utils.log_string (Printf.sprintf "misbehaving peer? [unrequested Asset]\n")));;

let json_obligation obl =
 match obl with
 | None -> None
 | Some(gamma,lh,r) ->
     Some(JsonObj([("type",JsonStr("obligation"));
		   ("lockaddress",JsonStr(addr_pfgaddrstr (payaddr_addr gamma)));
		   ("lockheight",JsonNum(Int64.to_string lh));
		   ("reward",JsonBool(r))]))

let json_preasset u =
  match u with
  | Currency(v) -> JsonObj([("type",JsonStr("preasset"));("preassettype",JsonStr("currency"));("val",json_atoms v)])
  | Bounty(v) -> JsonObj([("type",JsonStr("preasset"));("preassettype",JsonStr("bounty"));("val",json_atoms v)])
  | OwnsObj(h,beta,None) -> JsonObj([("type",JsonStr("preasset"));("preassettype",JsonStr("ownsobj"));("objid",JsonStr(hashval_hexstring h));("objaddr",JsonStr(Cryptocurr.addr_pfgaddrstr (termaddr_addr (hashval_be160 h))));("owneraddress",JsonStr(addr_pfgaddrstr (payaddr_addr beta)))])
  | OwnsObj(h,beta,Some(r)) -> JsonObj([("type",JsonStr("preasset"));("preassettype",JsonStr("ownsobj"));("objid",JsonStr(hashval_hexstring h));("objaddr",JsonStr(Cryptocurr.addr_pfgaddrstr (termaddr_addr (hashval_be160 h))));("owneraddress",JsonStr(addr_pfgaddrstr (payaddr_addr beta)));("royalty",json_atoms r)])
  | OwnsProp(h,beta,None) -> JsonObj([("type",JsonStr("preasset"));("preassettype",JsonStr("ownsprop"));("propid",JsonStr(hashval_hexstring h));("propaddr",JsonStr(Cryptocurr.addr_pfgaddrstr (termaddr_addr (hashval_be160 h))));("owneraddress",JsonStr(addr_pfgaddrstr (payaddr_addr beta)))])
  | OwnsProp(h,beta,Some(r)) -> JsonObj([("type",JsonStr("preasset"));("preassettype",JsonStr("ownsprop"));("propid",JsonStr(hashval_hexstring h));("propaddr",JsonStr(Cryptocurr.addr_pfgaddrstr (termaddr_addr (hashval_be160 h))));("owneraddress",JsonStr(addr_pfgaddrstr (payaddr_addr beta)));("royalty",json_atoms r)])
  | OwnsNegProp -> JsonObj([("type",JsonStr("preasset"));("preassettype",JsonStr("ownsnegprop"))])
  | RightsObj(h,r) -> JsonObj([("type",JsonStr("preasset"));("preassettype",JsonStr("rightsobj"));("objid",JsonStr(hashval_hexstring h));("objaddr",JsonStr(Cryptocurr.addr_pfgaddrstr (termaddr_addr (hashval_be160 h))));("units",JsonNum(Int64.to_string r))])
  | RightsProp(h,r) -> JsonObj([("type",JsonStr("preasset"));("preassettype",JsonStr("rightsprop"));("propid",JsonStr(hashval_hexstring h));("propaddr",JsonStr(Cryptocurr.addr_pfgaddrstr (termaddr_addr (hashval_be160 h))));("units",JsonNum(Int64.to_string r))])
  | Marker -> JsonObj([("type",JsonStr("preasset"));("preassettype",JsonStr("marker"))])
  | TheoryPublication(beta,nonce,ts) -> JsonObj([("type",JsonStr("preasset"));("preassettype",JsonStr("theoryspec"));("publisher",JsonStr(addr_pfgaddrstr (payaddr_addr beta)));("nonce",JsonStr(hashval_hexstring nonce));("theoryspec",json_theoryspec ts)])
  | SignaPublication(beta,nonce,None,ss) -> JsonObj([("type",JsonStr("preasset"));("preassettype",JsonStr("signaspec"));("publisher",JsonStr(addr_pfgaddrstr (payaddr_addr beta)));("nonce",JsonStr(hashval_hexstring nonce));("signaspec",json_signaspec None ss)])
  | SignaPublication(beta,nonce,Some(th),ss) -> JsonObj([("type",JsonStr("preasset"));("preassettype",JsonStr("signaspec"));("publisher",JsonStr(addr_pfgaddrstr (payaddr_addr beta)));("nonce",JsonStr(hashval_hexstring nonce));("theoryid",JsonStr(hashval_hexstring th));("signaspec",json_signaspec (Some(th)) ss)])
  | DocPublication(beta,nonce,None,d) -> JsonObj([("type",JsonStr("preasset"));("preassettype",JsonStr("doc"));("publisher",JsonStr(addr_pfgaddrstr (payaddr_addr beta)));("nonce",JsonStr(hashval_hexstring nonce));("doc",json_doc None d)])
  | DocPublication(beta,nonce,Some(th),d) -> JsonObj([("type",JsonStr("preasset"));("preassettype",JsonStr("doc"));("publisher",JsonStr(addr_pfgaddrstr (payaddr_addr beta)));("nonce",JsonStr(hashval_hexstring nonce));("theoryid",JsonStr(hashval_hexstring th));("doc",json_doc (Some(th)) d)])

let json_asset a =
  let ah = hashval_hexstring (hashasset a) in
  let (aid,bday,obl,u) = a in
  match json_obligation obl with
  | None ->
      JsonObj([("type",JsonStr("asset"));
	       ("assethash",JsonStr(ah));
	       ("assetid",JsonStr(hashval_hexstring aid));
	       ("bday",JsonNum(Int64.to_string bday));
	       ("preasset",json_preasset u)])
  | Some(jobl) ->
      JsonObj([("type",JsonStr("asset"));
	       ("assethash",JsonStr(ah));
	       ("assetid",JsonStr(hashval_hexstring aid));
	       ("bday",JsonNum(Int64.to_string bday));
	       ("obligation",jobl);
	       ("preasset",json_preasset u)])

let obligation_from_json j =
  match j with
  | None -> None
  | Some(JsonObj(al)) ->
      let alpha = payaddr_from_json (List.assoc "lockaddress" al) in
      let lkh = int64_from_json (List.assoc "lockheight" al) in
      let r = bool_from_json (List.assoc "reward" al) in
      Some(alpha,lkh,r)
  | _ -> raise (Failure("not an obligation"))
      
let preasset_from_json j =
  match j with
  | JsonObj(al) ->
      let pat = List.assoc "preassettype" al in
      if pat = JsonStr("currency") then
	begin
	  let v = atoms_from_json (List.assoc "val" al) in
	  Currency(v)
	end
      else if pat = JsonStr("bounty") then
	begin
	  let v = atoms_from_json (List.assoc "val" al) in
	  Bounty(v)
	end
      else if pat = JsonStr("ownsobj") then
	begin
	  let h = hashval_from_json (List.assoc "objid" al) in
	  let beta = payaddr_from_json (List.assoc "owneraddress" al) in
	  let r = try Some(atoms_from_json (List.assoc "royalty" al)) with Not_found -> None in
	  OwnsObj(h,beta,r)
	end
      else if pat = JsonStr("ownsprop") then
	begin
	  let h = hashval_from_json (List.assoc "propid" al) in
	  let beta = payaddr_from_json (List.assoc "owneraddress" al) in
	  let r = try Some(atoms_from_json (List.assoc "royalty" al)) with Not_found -> None in
	  OwnsProp(h,beta,r)
	end
      else if pat = JsonStr("ownsnegprop") then
	OwnsNegProp
      else if pat = JsonStr("rightsobj") then
	begin
	  let h = hashval_from_json (List.assoc "objid" al) in
	  let r = int64_from_json (List.assoc "units" al) in
	  RightsObj(h,r)
	end
      else if pat = JsonStr("rightsprop") then
	begin
	  let h = hashval_from_json (List.assoc "propid" al) in
	  let r = int64_from_json (List.assoc "units" al) in
	  RightsProp(h,r)
	end
      else if pat = JsonStr("marker") then
	Marker
      else if pat = JsonStr("theoryspec") then
	begin
	  let beta = payaddr_from_json (List.assoc "publisher" al) in
	  let nonce = hashval_from_json (List.assoc "nonce" al) in
	  let ts = theoryspec_from_json (List.assoc "theoryspec" al) in
	  TheoryPublication(beta,nonce,ts)
	end
      else if pat = JsonStr("signaspec") then
	begin
	  let beta = payaddr_from_json (List.assoc "publisher" al) in
	  let nonce = hashval_from_json (List.assoc "nonce" al) in
	  let jth = (try Some(List.assoc "theoryid" al) with Not_found -> None) in
	  let th = (match jth with Some(jth) -> Some(hashval_from_json jth) | None -> None) in
	  let ss = signaspec_from_json (List.assoc "signaspec" al) in
	  SignaPublication(beta,nonce,th,ss)
	end
      else if pat = JsonStr("doc") then
	begin
	  let beta = payaddr_from_json (List.assoc "publisher" al) in
	  let nonce = hashval_from_json (List.assoc "nonce" al) in
	  let jth = (try Some(List.assoc "theoryid" al) with Not_found -> None) in
	  let th = (match jth with Some(jth) -> Some(hashval_from_json jth) | None -> None) in
	  let d = doc_from_json (List.assoc "doc" al) in
	  DocPublication(beta,nonce,th,d)
	end
      else
	raise (Failure("not a preasset"))
  | _ -> raise (Failure("not a preasset"))

let asset_from_json j =
  match j with
  | JsonObj(al) ->
      let aid = hashval_from_json (List.assoc "assetid" al) in
      let bday = int64_from_json (List.assoc "bday" al) in
      let u = preasset_from_json (List.assoc "preasset" al) in
      let jobl = (try Some(List.assoc "obligation" al) with Not_found -> None) in
      let obl = obligation_from_json jobl in
      (aid,bday,obl,u)
  | _ ->
      raise (Failure("not an asset"))
