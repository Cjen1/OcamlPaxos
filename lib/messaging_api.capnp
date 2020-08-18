@0xd66c44db48f005fe;

struct Op {
  key @0 :Data;
  union {
    read @1 :Void;

    write :group {
      value @2 :Data;
    }
  }
}

struct Command {
  op @0 :Op;
  id @1 :Int64;
}

struct CommandResult {
  union {
    success @0 : Void;
    readSuccess @1 : Data;
    failure @2 : Void;
  }
}

struct LogEntry {
  command @0: Command;
  term @1 : Int64;
}

struct RequestVote {
  term @0:Int64;
  leaderCommit @1:Int64;
}

struct RequestVoteResp {
  term @0:Int64;
  voteGranted @1: Bool;
  entries @2: List(LogEntry);
  startIndex @3: Int64;
}

struct AppendEntries {
      term @0: Int64;
      prevLogIndex @1: Int64;
      prevLogTerm @2: Int64;
      entries @3: List(LogEntry);
      leaderCommit @4: Int64;
}

struct AppendEntriesResp {
  term @0: Int64;
  union {
    success @1 : Int64; # Match Index
    failure @2 : Int64; # Prev_log_index
  }
}

struct ClientResponse {
  id @0 : Int64 ;
  result @1 : CommandResult;
}

struct ServerMessage {
  union {
    requestVote @0: RequestVote;
    requestVoteResp @1: RequestVoteResp;
    appendEntries @2: AppendEntries;
    appendEntriesResp @3: AppendEntriesResp;
    clientRequest @4: Command;
    clientResponse @5: ClientResponse;
  }
}
