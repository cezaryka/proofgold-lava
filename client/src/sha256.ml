(* Copyright (c) 2021 The Proofgold Lava developers *)
(* Copyright (c) 2015 The Qeditas developers *)
(* Copyright (c) 2017-2019 The Dalilcoin developers *)
(* Distributed under the MIT software license, see the accompanying
   file COPYING or http://www.opensource.org/licenses/mit-license.php. *)

(* This code is an implementation of the SHA-256 hash function. *)

open Utils
open Ser
open Hashaux
open Zarithint

(* Type definition for an 8-tuple of 32-bit integers, used in the SHA-256 implementation. *)
(* Following the description in http://csrc.nist.gov/groups/STM/cavp/documents/shs/sha256-384-512.pdf *)
type int32p8 = int32 * int32 * int32 * int32 * int32 * int32 * int32 * int32

(* Initial hash value for SHA-256, as specified in the NIST standard. *)
let sha256inithashval : int32 array =
  [| 0x6a09e667l; 0xbb67ae85l; 0x3c6ef372l; 0xa54ff53al;
     0x510e527fl; 0x9b05688cl; 0x1f83d9abl; 0x5be0cd19l |]

(* Current hash value, initialized to an array of zeroes. *)
let currhashval : int32 array = [| 0l; 0l; 0l; 0l; 0l; 0l; 0l; 0l |]

(* Current block, initialized to an array of zeroes. *)
let currblock : int32 array = [| 0l; 0l; 0l; 0l; 0l; 0l; 0l; 0l; 0l; 0l; 0l; 0l; 0l; 0l; 0l; 0l |]

(* Performs one round of the SHA-256 hash function on the current hash value and current block. *)
let sha256round () =
  Hashbtc.sha256_round_arrays currhashval currblock
;;

(* Initializes the current hash value to the initial hash value for SHA-256. *)
let sha256init () =
  currhashval.(0) <- sha256inithashval.(0);
  currhashval.(1) <- sha256inithashval.(1);
  currhashval.(2) <- sha256inithashval.(2);
  currhashval.(3) <- sha256inithashval.(3);
  currhashval.(4) <- sha256inithashval.(4);
  currhashval.(5) <- sha256inithashval.(5);
  currhashval.(6) <- sha256inithashval.(6);
  currhashval.(7) <- sha256inithashval.(7)

(* Returns the current hash value as an 8-tuple of 32-bit integers. *)
let getcurrint32p8 () =
  (currhashval.(0),currhashval.(1),currhashval.(2),currhashval.(3),currhashval.(4),currhashval.(5),currhashval.(6),currhashval.(7))

(* Calculates the number of padding bits needed for a given message length. *)
let sha256padnum l =
  let r = (l+1) mod 512 in
  let k = if r <= 448 then 448 - r else 960 - r in
  k

(* Sets the j-th byte of a 32-bit integer to a given value. *)
let setbyte32 x y j =
  Int32.logor x (Int32.shift_left (Int32.of_int y) (8 * (3-j)))

(* Calculates the SHA-256 hash of a given string. *)
let sha256str s = Hashbtc.sha256 s

(* Calculates the SHA-256 hash of a given double-hashed string. *)
let sha256dstr s = Hashbtc.sha256 (Be256.to_string (Hashbtc.sha256 s))

(* Serializes an 8-tuple of 32-bit integers to a byte stream. *)
let seo_int32p8 o h c =
  let (h0,h1,h2,h3,h4,h5,h6,h7) = h in
  let c = seo_int32 o h0 c in
  let c = seo_int32 o h1 c in
  let c = seo_int32 o h2 c in
  let c = seo_int32 o h3 c in
  let c = seo_int32 o h4 c in
  let c = seo_int32 o h5 c in
  let c = seo_int32 o h6 c in
  let c = seo_int32 o h7 c in
  c

(* Deserializes an 8-tuple of 32-bit integers from a byte stream. *)
let sei_int32p8 i c =
  let (h0,c) = sei_int32 i c in
  let (h1,c) = sei_int32 i c in
  let (h2,c) = sei_int32 i c in
  let (h3,c) = sei_int32 i c in
  let (h4,c) = sei_int32 i c in
  let (h5,c) = sei_int32 i c in
  let (h6,c) = sei_int32 i c in
  let (h7,c) = sei_int32 i c in
  ((h0,h1,h2,h3,h4,h5,h6,h7),c)

(* Converts an 8-tuple of 32-bit integers to a big integer. *)
let int32p8_big_int h =
  let (h0,h1,h2,h3,h4,h5,h6,h7) = h in
  let x0 = int32_big_int_bits h0 224 in
  let x1 = or_big_int x0 (int32_big_int_bits h1 192) in
  let x2 = or_big_int x1 (int32_big_int_bits h2 160) in
  let x3 = or_big_int x2 (int32_big_int_bits h3 128) in
  let x4 = or_big_int x3 (int32_big_int_bits h4 96) in
  let x5 = or_big_int x4 (int32_big_int_bits h5 64) in
  let x6 = or_big_int x5 (int32_big_int_bits h6 32) in
  or_big_int x6 (int32_big_int_bits h7 0)

(* Generates a random 8-tuple of 32-bit integers. *)
let rand_int32p8 () =
  if not !random_initialized then initialize_random_seed();
  let m0 = rand_int32() in
  let m1 = rand_int32() in
  let m2 = rand_int32() in
  let m3 = rand_int32() in
  let m4 = rand_int32() in
  let m5 = rand_int32() in
  let m6 = rand_int32() in
  let m7 = rand_int32() in
  (m0,m1,m2,m3,m4,m5,m6,m7)

(* Generates a random 256-bit integer. *)
let rand_256 () =
  int32p8_big_int (rand_int32p8 ())

(* Generates a random big-endian 256-bit integer. *)
let rand_be256 () =
  Be256.of_int32p8 (rand_int32p8 ())

(* Generates a cryptographically strong random 256-bit integer. *)
let strong_rand_256 () =
  match !Config.randomseed with
  | Some(_) -> rand_256()
  | None ->
     if Sys.file_exists "/dev/random" then
       begin
         let dr = open_in_bin "/dev/random" in
         let (n,_) = sei_int32p8 seic (dr,None) in
         close_in_noerr dr;
         int32p8_big_int n
       end
     else
       raise (Failure "Cannot generate cryptographically strong random numbers")
