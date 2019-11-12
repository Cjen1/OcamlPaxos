(* ballot.ml *)

open Types
open Base

(* Ballots are identified uniquely by their ballot number

   This consists of a pair of an integer and the id of the leader that
   initiated the ballot. There is also the Bottom variant of ballot.

   Ballots are totally ordered, based on the lexicographical ordering of the
   integer component and the leader id.

   The Bottom ballot denotes the lowest possible ballot number (used for
   initialisation in accceptors for example).
*)

(* Types of ballots *)
type t = Bottom [@key 1] | Number of int * string [@key 2]
[@@deriving protobuf, sexp]

exception BallotIsBottom

let get_leader_id_exn ballot : leader_id =
  match ballot with Bottom -> raise BallotIsBottom | Number (_, lid) -> lid

(* Function bottom returns bottom ballot *)
let bottom () = Bottom

(* Generate an initial ballot number for a given leader id *)
let init id = Number (0, id)

(* Generates the successor of a given ballot. This can result in an exception if the ballot is
   Bottom, as the bottom ballot has no successor *)
let succ_exn bal id =
  match bal with
  | Bottom ->
      failwith "Error: Bottom ballot has no successor"
  | Number (n, _) ->
      Number (n + 1, id)

(* To ensure the total ordering on ballot, two functions are provided to test
   equality of ballots and the partial ordering of ballots.

   Since integers and ids are totally ordered the pairing here is totally
   ordered *)
let phys_equal b b' =
  match (b, b') with
  | Bottom, Bottom ->
      true
  | Number (n, l), Number (n', l') ->
      n = n' && String.equal l l'
  | _, _ ->
      false

(* Comparison function for ballots.

  For reference on how comparisons should behave, from Real World OCaml...
    compare x y < 0    <=> x < y
    compare x y = 0    <=> x = y
    compare x y > 0    <=> x > y  *)
let compare b b' =
  match (b, b') with
  | Bottom, Bottom ->
      0
  | Bottom, _ ->
      -1
  | _, Bottom ->
      1
  | Number (n, _), Number (n', _) ->
      Int.compare n n'

let equal b b' = compare b b' = 0

(* Function tests if ballot b is less than b'.
   Along with equalaity function we have a total order on ballots *)
let less_than b b' = compare b b' < 0

let greater_than b b' = compare b b' > 0

(* Convert a ballot to a string *)
let to_string b = b |> sexp_of_t |> Sexp.to_string_hum

module Infix = struct
  let ( < ) = less_than
  let ( <= ) a b = compare a b <= 0 
  let ( > ) a b = compare a b > 0 
  let ( >= ) a b = compare a b >= 0 
  let ( = ) a b = compare a b = 0
end
