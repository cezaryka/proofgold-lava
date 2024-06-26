(* Copyright (c) 2021-2023 The Proofgold Lava developers *)
(* Copyright (c) 2020 The Proofgold developers *)
(* Copyright (c) 2016 The Qeditas developers *)
(* Copyright (c) 2017-2018 The Dalilcoin developers *)
(* Distributed under the MIT software license, see the accompanying
   file COPYING or http://www.opensource.org/licenses/mit-license.php. *)

open Json
open Hash
open Db
open Logic
open Htree

val term_hfbuiltin_objid : (hashval,hashval) Hashtbl.t
val term_theory_objid_history_table : (hashval,hashval option * hashval * hashval) Hashtbl.t
val term_theory_objid_bkp : (hashval option * hashval,hashval) Hashtbl.t
val term_theory_objid : (hashval option * hashval,hashval) Hashtbl.t
val term_addr_hashval : (addr,hashval) Hashtbl.t
val propid_conj_pub_history_table : (hashval,hashval * addr) Hashtbl.t
val propid_conj_pub_bkp : (hashval,addr) Hashtbl.t
val propid_conj_pub : (hashval,addr) Hashtbl.t

val enter_term_addr_hashval : hashval -> unit
val preimage_of_term_addr_json : addr -> (string * jsonval) list -> (string * jsonval) list

(** * serialization code ***)

val seo_tp : (int -> int -> 'a -> 'a) -> stp -> 'a -> 'a
val sei_tp : (int -> 'a -> int * 'a) -> 'a -> stp * 'a

val hashtp : stp -> hashval

val seo_tm : (int -> int -> 'a -> 'a) -> trm -> 'a -> 'a
val sei_tm : (int -> 'a -> int * 'a) -> 'a -> trm * 'a

val hashtm : trm -> hashval
val tm_hashroot : trm -> hashval

val seo_pf : (int -> int -> 'a -> 'a) -> pf -> 'a -> 'a
val sei_pf : (int -> 'a -> int * 'a) -> 'a -> pf * 'a

val hashpf : pf -> hashval
val pf_hashroot : pf -> hashval

val seo_theoryspec : (int -> int -> 'a -> 'a) -> theoryspec -> 'a -> 'a
val sei_theoryspec : (int -> 'a -> int * 'a) -> 'a -> theoryspec * 'a
val seo_theory : (int -> int -> 'a -> 'a) -> theory -> 'a -> 'a
val sei_theory : (int -> 'a -> int * 'a) -> 'a -> theory * 'a

module DbTheory :
    sig
      val dbinit : unit -> unit
      val dbget : hashval -> theory
      val dbexists : hashval -> bool
      val dbput : hashval -> theory -> unit
      val dbdelete : hashval -> unit
    end

module DbTheoryTree :
    sig
      val dbinit : unit -> unit
      val dbget : hashval -> hashval option * hashval list
      val dbexists : hashval -> bool
      val dbput : hashval -> hashval option * hashval list -> unit
      val dbdelete : hashval -> unit
    end

val hashtheory : theory -> hashval option

val theoryspec_theory : theoryspec -> theory
val theory_burncost : theory -> int64
val theoryspec_burncost : theoryspec -> int64

val seo_signaspec : (int -> int -> 'a -> 'a) -> signaspec -> 'a -> 'a
val sei_signaspec : (int -> 'a -> int * 'a) -> 'a -> signaspec * 'a
val seo_signa : (int -> int -> 'a -> 'a) -> signa -> 'a -> 'a
val sei_signa : (int -> 'a -> int * 'a) -> 'a -> signa * 'a

val hashsigna : signa -> hashval

val signaspec_signa : signaspec -> signa
val signa_burncost : signa -> int64
val signaspec_burncost : signaspec -> int64

module DbSigna :
    sig
      val dbinit : unit -> unit
      val dbget : hashval -> hashval option * signa
      val dbexists : hashval -> bool
      val dbput : hashval -> hashval option * signa -> unit
      val dbdelete : hashval -> unit
    end

module DbSignaTree :
    sig
      val dbinit : unit -> unit
      val dbget : hashval -> hashval option * hashval list
      val dbexists : hashval -> bool
      val dbput : hashval -> hashval option * hashval list -> unit
      val dbdelete : hashval -> unit
    end

val seo_doc : (int -> int -> 'a -> 'a) -> doc -> 'a -> 'a
val sei_doc : (int -> 'a -> int * 'a) -> 'a -> doc * 'a

val hashdoc : doc -> hashval
val doc_hashroot : doc -> hashval

val signaspec_uses_objs : signaspec -> (hashval * hashval) list
val signaspec_uses_props : signaspec -> hashval list
val doc_uses_objs : doc -> (hashval * hashval) list
val doc_uses_props : doc -> hashval list
val doc_creates_objs : doc -> (hashval * hashval) list
val doc_creates_props : doc -> hashval list
val doc_creates_neg_props : doc -> hashval list

(** * htrees to hold theories and signatures **)
type ttree = theory htree
type stree = (hashval option * signa) htree

val ottree_insert : ttree option -> bool list -> theory -> ttree
val ostree_insert : stree option -> bool list -> hashval option * signa -> stree

val ottree_hashroot : ttree option -> hashval option
val ostree_hashroot : stree option -> hashval option

val ottree_lookup : ttree option -> hashval option -> theory
val ostree_lookup : stree option -> hashval option -> hashval option * signa

exception CheckingFailure

val import_signatures : hashval option -> stree -> hashval list -> gsign -> hashval list -> (gsign * hashval list) option

val print_trm : stp list -> gsign -> trm -> stp list -> unit
val print_tp : stp -> int -> unit

val invert_neg_prop : trm -> trm
val neg_prop : trm -> trm
val propid_neg_propid : (hashval,hashval) Hashtbl.t

val mgnice : bool ref
val mgnicestp : bool ref
val mgnatnotation : bool ref

val mglegendt : (hashval,string) Hashtbl.t
val mglegend : (hashval,string) Hashtbl.t
val mglegendp : (hashval,string) Hashtbl.t
val mgifthenelse : (hashval,unit) Hashtbl.t
val mgbinder : (hashval,string) Hashtbl.t
val mgprefixop : (hashval,string) Hashtbl.t
val mgpostfixop : (hashval,string) Hashtbl.t
val mginfixop : (hashval,string) Hashtbl.t
val mgimplop : (hashval,unit) Hashtbl.t
val mgrootassoc : (hashval,hashval) Hashtbl.t
val prefixpriorities : (int,unit) Hashtbl.t
val disallowedprefixpriorities : (int,unit) Hashtbl.t
val rightinfixpriorities : (int,unit) Hashtbl.t
val disallowedrightinfixpriorities : (int,unit) Hashtbl.t
val penv_preop : (string,int) Hashtbl.t
type picase = Postfix | InfixNone | InfixLeft | InfixRight
val penv_postinfop : (string,int * picase) Hashtbl.t
val penv_binder : (string,unit) Hashtbl.t
val printenv_as_legend : unit -> unit

val json_theoryspec : theoryspec -> jsonval
val json_signaspec : hashval option -> signaspec -> jsonval
val json_doc : hashval option -> doc -> jsonval
val json_stp : stp -> jsonval
val json_trm : trm -> jsonval

val stp_from_json : jsonval -> stp
val trm_from_json : jsonval -> trm
val theoryspec_from_json : jsonval -> theoryspec
val signaspec_from_json : jsonval -> signaspec
val doc_from_json : jsonval -> doc

val mghtml_nice_stp : hashval option -> stp -> string
val mghtml_nice_trm : hashval option -> trm -> string
val hfthyroot : hashval
val hfprimnamesa : string array

val json_trm_partial : string -> int -> hashval option -> trm -> int -> bool option list -> string list -> jsonval * int
val json_pf_partial : string -> int -> hashval option -> pf -> int -> bool option list -> string list -> string list -> jsonval * int

val html_trm_partial : string -> int -> hashval option -> trm -> int -> bool option list -> string list -> string * int
val html_pf_partial : string -> int -> hashval option -> pf -> int -> bool option list -> string list -> string list -> string * int
