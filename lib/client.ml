open Types
open Messaging
open Lwt.Infix

let ( >>>= ) = Lwt_result.bind

let client = Logs.Src.create "Client" ~doc:"Client module"

module CLog = (val Logs.src_log client : Logs.LOG)

type t =
  { mgr: ClientConn.t
  ; addrs: address list
  ; ongoing_requests: (int, StateMachine.op_result Lwt.u) Hashtbl.t }

let send t op =
  let id = Random.int32 Int32.max_int |> Int32.to_int in
  let command : command = {op; id} in
  let msg = Send.Serialise.clientRequest ~command in
  let prom, fulfiller = Lwt.wait () in
  Hashtbl.add t.ongoing_requests id fulfiller ;
  List.iter
    (fun addr -> Lwt.async (fun () -> ClientConn.send t.mgr addr msg))
    t.addrs ;
  prom
  >>= function
  | StateMachine.Success ->
      Lwt.return_ok `Success
  | StateMachine.ReadSuccess v ->
      Lwt.return_ok (`ReadSuccess v)
  | StateMachine.Failure ->
      Lwt.return_error (`Msg "Application failed on cluster")

let fulfiller_loop t =
  let resp msg =
    let open API.Reader in
    match API.Reader.ServerMessage.get msg with
    | ServerMessage.ClientResponse resp -> (
        let id = ClientResponse.id_get_int_exn resp in
        match Hashtbl.find_opt t.ongoing_requests id with
        | Some fulfiller ->
            let res =
              match ClientResponse.result_get resp |> CommandResult.get with
              | CommandResult.Success ->
                  StateMachine.Success
              | CommandResult.Failure ->
                  StateMachine.Failure
              | CommandResult.ReadSuccess s ->
                  StateMachine.ReadSuccess s
              | Undefined d ->
                  Fmt.failwith "Got undefined client response %d" d
            in
            Hashtbl.remove t.ongoing_requests id ;
            Lwt.wakeup fulfiller res
        | None ->
            () )
    | _ ->
        ()
  in
  let rec loop () = ClientConn.recv t.mgr >>= fun msg -> resp msg ; loop () in
  loop ()

let send_wrapper t msg =
  Lwt_result.catch (send t msg)
  >|= function
  | Ok res ->
      Ok res
  | Error e ->
      Error (`Msg (Fmt.pr "Exception caught: %a" Fmt.exn e))

let op_read t k = send_wrapper t @@ StateMachine.Read (Bytes.to_string k)

let op_write t k v =
  send_wrapper t @@ StateMachine.Write (Bytes.to_string k, Bytes.to_string v)

let new_client ?(cid = Types.create_id ()) addresses () =
  let clientmgr = ClientConn.create ~id:cid () in
  let ps = List.map (ClientConn.add_connection clientmgr) addresses in
  (* get at least once connection established *)
  Lwt.choose ps
  >>= fun () ->
  let t =
    {mgr= clientmgr; addrs= addresses; ongoing_requests= Hashtbl.create 1024}
  in
  Lwt.return t
