(* acceptor.ml *)

open Utils
open Messaging

let acceptor = Logs.Src.create "Acceptor" ~doc:"Acceptor module"

module ALog = (val Logs.src_log acceptor : Logs.LOG)

(* Types of acceptors *)
type t =
  { id: string
  ; mutable ballot_num: Ballot.t
  ; accepted: (Types.slot_number, Pval.t) Base.Hashtbl.t
  ; wal: Unix.file_descr
  ; msg_layer: Msg_layer.t }

let p1a_callback t (p1a:p1a) =
  let open Ballot.Infix in
  ALog.debug (fun m ->
      m "Got p1a msg, ballot=%s" @@ Ballot.to_string p1a.ballot) ;
  if p1a.ballot > t.ballot_num then (
    p1a.ballot |> Ballot.to_string |> write_to_wal t.wal ;
    t.ballot_num <- p1a.ballot ;
    ALog.debug (fun m ->
        m "Sending p1b, ballot=%s" @@ Ballot.to_string t.ballot_num) ;
    { id= t.id
    ; ballot= t.ballot_num
    ; accepted=
        Base.Hashtbl.data t.accepted
        (* TODO reduce this? Can be done by including a high water mark in p1a message decisions *)
    }
    |> Protobuf.Encoder.encode_exn p1b_to_protobuf
    |> Bytes.to_string
    |> Msg_layer.send_msg t.msg_layer ~filter:"p1b" )
  else
    Lwt.return_unit

let p2a_callback t (p2a:p2a) =
  let open Ballot.Infix in
  ALog.debug (fun m -> m "Got p2a msg") ;
  let ((ib, is, _) as ipval) = p2a.pval in
  if ib >= t.ballot_num then (
    write_to_wal t.wal @@ Pval.to_string ipval ;
    Base.Hashtbl.set t.accepted ~key:is ~data:ipval ;
    ALog.debug (fun m -> m "Sending p2b msg") ;
    {id= t.id; ballot= t.ballot_num; pval= ipval}
    |> Protobuf.Encoder.encode_exn p2b_to_protobuf
    |> Bytes.to_string
    |> Msg_layer.send_msg t.msg_layer ~filter:"p2b" )
  else (
    ALog.debug (fun m -> m "Is incorrect ballot") ;
    {ballot= t.ballot_num}
    |> Protobuf.Encoder.encode_exn nack_p1_to_protobuf
    |> Bytes.to_string
    |> Msg_layer.send_msg t.msg_layer ~filter:"nack_p2" )

let create wal_loc msg_layer local =
  let t =
    { id= local
    ; ballot_num= Ballot.bottom ()
    ; accepted= Base.Hashtbl.create (module Base.Int)
    ; wal=
        Unix.openfile wal_loc [Unix.O_RDWR; Unix.O_CREAT]
        @@ int_of_string "0x660"
    ; msg_layer }
  in
  let open Messaging in
  Msg_layer.attach_watch msg_layer ~filter:"p1a" ~callback:(p1a_callback t) ~typ:P1a;
  Msg_layer.attach_watch msg_layer ~filter:"p2a" ~callback:(p2a_callback t) ~typ:P2a;
  (t, Lwt.return_unit)

(* Initialize a new acceptor *)
let create_independent wal_loc nodes local alive_timeout =
  let msg, psml = Msg_layer.create ~node_list:nodes ~local ~alive_timeout in
  let t, psa = create wal_loc msg local in
  (t, Lwt.join [psa; psml])
