%% @author: Andrey Tsirulev
%% @date: 01.12.2013

-module(vprof_profile).

%% Include files
-include("vprof.hrl").

%% Exported Functions

-export([
    profile/2
]).

-record(proc, {
    id = 0,
    pid,
    root_id = 0,
    own = 0,
    own_start_ts,
    schedule_out_ts,
    ts_shift = 0,
    stack = [],
    calls = array:new(),
    mfas = dict:new(),
    schedules = 1
}).

-record(call, {
    id,
    mfa,
    own = 0,
    acc = 0,
    own_start_ts,
    acc_start_ts,
    parent,
    children = [],
    recursion
}).

%%%===================================================================
%%% API
%%%===================================================================
profile(InFile, OutFile) ->
    catch file:delete(OutFile),
    io:format("vprof: Profiling ~s. This may take several minutes.~n", [InFile]),
    dbg:trace_client(file, InFile, {fun collect/2, {undefined, [], OutFile, os:timestamp()}}).

get_process_and_timestamp(#proc{pid = Pid, ts_shift = TsShift} = Process, Pid, Timestamp, Pids) ->
    {Process, Timestamp - TsShift, Pids};
get_process_and_timestamp(PrevProcess, Pid, Timestamp, Pids) ->
    if PrevProcess =:= undefined -> ok;
       true -> 
           put(PrevProcess#proc.pid, PrevProcess)
    end,
    case get(Pid) of
        undefined ->
            {#proc{own_start_ts = Timestamp, pid = Pid}, Timestamp, [Pid|Pids]};
        Process -> 
            {Process, Timestamp - Process#proc.ts_shift, Pids}
    end.

collect(Trace, {PrevProcess, Pids, OutFile, StartTime}) when element(1, Trace) =:= trace_ts ->
    Pid = element(2, Trace),
    Type = element(3, Trace),
    MFA = element(4, Trace),
    AbsTimestamp = ts(element(size(Trace), Trace)),
    {Process, Timestamp, Pids1} = get_process_and_timestamp(PrevProcess, Pid, AbsTimestamp, Pids),
    NewProcess =
        case Type of
            call ->
                call(Process, Timestamp, MFA);
            return_to ->
                case Process#proc.stack of
                    [] ->
                        call(Process, Timestamp, MFA);
                    _ ->
                        return_to(Process, Timestamp, MFA)
                end;
            in ->
                in(Process, Timestamp, MFA);
            out ->
                out(Process, Timestamp, MFA);
            _ ->
                Process
        end,
    {NewProcess, Pids1, OutFile, StartTime};
collect(end_of_trace, {PrevProcess, Pids, OutFile, StartTime}) ->
    put(PrevProcess#proc.pid, PrevProcess),
    TimeDiff1 = timer:now_diff(os:timestamp(), StartTime) div 1000000,
    io:format("vprof: End of trace in ~p seconds.~n", [TimeDiff1]),
    Res = lists:foldl(
        fun(Pid, Acc) ->
            Process = get(Pid),
            close(Pid, Process, Acc)
        end, {[], []}, Pids),
    write(OutFile, Res),
    TimeDiff = timer:now_diff(os:timestamp(), StartTime) div 1000000,
    io:format("vprof: Done in ~p seconds.~n", [TimeDiff]),
    io:format("Check ~s to see results or run~nvprof:gui(\"~s\").~n", [OutFile, OutFile]),
    ok.

write(FileName, Term) ->
    {ok, File} = file:open(FileName, [write]),
    io:format(File, "~p.~n", [Term]),
    file:close(File).

call(#proc{stack = [#call{mfa = MFA}|_]} = Process, _Timestamp, MFA) ->
    Process;
call(#proc{stack = [], id = NewId} = Process, Timestamp, MFA) ->
    New = #call{mfa = MFA, own_start_ts = Timestamp, acc_start_ts = Timestamp, id = NewId},
    Process#proc{stack = [New], id = NewId + 1, root_id = NewId};
call(#proc{stack = [Cur|Stack], id = NewId} = Process, Timestamp, MFA) ->
    #call{own_start_ts = OwnStart, own = Own, id = CurId, children = CurChildren} = Cur,
    Cur1 = Cur#call{own = Own + Timestamp - OwnStart, own_start_ts = undefined, children = [NewId|CurChildren]},
    ParentRecursion =
        case lists:keyfind(MFA, #call.mfa, Stack) of
            false -> undefined;
            #call{id = RecId} -> RecId
        end,
    New = #call{mfa = MFA, own_start_ts = Timestamp, acc_start_ts = Timestamp, id = NewId, parent = CurId, recursion = ParentRecursion},
    Process#proc{stack = [New,Cur1|Stack], id = NewId + 1}.

out(Process, Timestamp, MFA) ->
    Process1 = call(Process, Timestamp, MFA),
    Process1#proc{schedule_out_ts = Timestamp}.

in(#proc{stack = [], schedule_out_ts = undefined} = Process, Timestamp, MFA) ->
    call(Process, Timestamp, MFA);
in(#proc{ts_shift = TsShift, schedule_out_ts = ScheduledOutTs, schedules = Schedules} = Process, Timestamp, MFA) ->
    TsShiftDelta = Timestamp - ScheduledOutTs,
    TsShift1 = TsShift + TsShiftDelta,
    Process1 = Process#proc{ts_shift = TsShift1, schedule_out_ts = undefined, schedules = Schedules + 1},
    return_to(Process1, Timestamp - TsShiftDelta, MFA).

return(#proc{stack = [Cur|Stack], calls = Calls, mfas = MFAs} = Process, Timestamp) ->
    #call{mfa = MFA, own_start_ts = OwnStart, own = Own, acc = Acc, acc_start_ts = AccStart, id = Id, children = Children} = Cur,
    Acc1 = 
        case AccStart of
            undefined -> Acc;
            _ -> Acc + Timestamp - AccStart
        end,
    Own1 = 
        case OwnStart of
            undefined -> Own;
            _ -> Own + Timestamp - OwnStart
        end,
    Cur1 = Cur#call{own = Own1, acc = Acc1, own_start_ts = undefined, acc_start_ts = undefined, children = Children},
    Calls1 = array:set(Id, Cur1, Calls),
    MFAs1 = dict:append(MFA, Id, MFAs),
    Process#proc{stack = Stack, calls = Calls1, mfas = MFAs1}.

insert_head(#proc{stack = [Cur], own_start_ts = StartTs, id = NewId, calls = Calls, mfas = MFAs} = Process, _Timestamp, ToMFA) ->
    #call{id = Id} = Cur,
    Cur1 = Cur#call{parent = NewId},
    Calls1 = 
        case dict:find(ToMFA, MFAs) of
            {ok, Ids} ->
                lists:foldl(
                    fun(I, Cs) -> 
                        C = array:get(I, Cs),
                        C1 = 
                            if C#call.recursion =:= undefined -> C#call{recursion = NewId}; 
                                true -> C
                            end,
                        array:set(I, C1, Cs)
                    end, Calls, Ids);
                error ->
                    Calls
        end,
    New = #call{mfa = ToMFA, acc_start_ts = StartTs, id = NewId, children=[Id]},
    Process#proc{stack = [Cur1,New], id = NewId + 1, root_id = NewId, calls = Calls1}.

return_to(#proc{stack = [#call{mfa = MFA, own_start_ts = OwnStartTs} = Cur|Stack]} = Process, Timestamp, MFA) ->
    StartTs = if OwnStartTs =:= undefined -> Timestamp; true -> OwnStartTs end,
    Cur1 = Cur#call{own_start_ts = StartTs},
    Process#proc{stack = [Cur1|Stack]};
return_to(#proc{stack = [_]} = Process, Timestamp, unknown) ->
    P0 = insert_head(Process, Timestamp, unknown),
    P1 = return(P0, Timestamp),
    P2 = return_to(P1, Timestamp, unknown),
    return(P2, Timestamp);
return_to(Process, _Timestamp, {array,_,_}) ->
    Process;
return_to(#proc{stack = [_]} = Process, Timestamp, MFA) ->
    P0 = insert_head(Process, Timestamp, MFA),
    P1 = return(P0, Timestamp),
    return_to(P1, Timestamp, MFA);
return_to(#proc{stack = [_|_]} = Process, Timestamp, MFA) ->
    P1 = return(Process, Timestamp),
    return_to(P1, Timestamp, MFA);
return_to(#proc{stack = []} = Process, _Timestamp, _MFA) ->
    Process.
    

%%%===================================================================
%%% Internal functions
%%%===================================================================
ts({Mega, Secs, Micro}) -> (Mega * 1000000000000) + (Secs * 1000000) + Micro.

last_ts(#proc{schedule_out_ts = ScheduleOutTs}) when ScheduleOutTs =/= undefined ->
    ScheduleOutTs;
last_ts(#proc{schedule_out_ts = undefined, stack = [#call{own_start_ts = LastTs}|_]}) ->
    LastTs;
last_ts(#proc{own_start_ts = Ts}) ->
    Ts.

process_own(#proc{own_start_ts = OwnStartTs} = Process, LastTs) ->
    Process#proc{own = LastTs - OwnStartTs}.

close(Pid, Process, Result) ->
    LastTs = last_ts(Process),
    Process1 = process_own(Process, LastTs),
    Process2 = return_to(Process1, LastTs, unknown),
    result(Pid, Process2, Result).

result(Pid, Process, {Procs, Rows}) ->
    #proc{calls = Calls, own = Own, mfas = MFAs, schedules = Schedules} = Process,
    SPid = convert_pid(Pid),
    Rows1 = lists:reverse(lists:keysort(#function.acc, dict:fold(
        fun(MFA, CallIds, Acc) ->
            Cs = [ array:get(Id, Calls) || Id <- CallIds ],
            FetchCall = fun(Id) -> array:get(Id, Calls) end,
            Parents = 
            [
                #ref{mfa = MFA1,
                    cnt = length(Css),
                    own = ms_to_s(vprof_q:keysum(#call.own, Css)),
                    acc = ms_to_s(vprof_q:keysum(#call.acc, without_recursion(Css)))}
                     || {MFA1, Css} <- vprof_q:qq(Cs, [ [#call.parent], ordset, fun(Cc) -> Cc -- [undefined] end, [FetchCall], {group, #call.mfa} ] ) ],
            Children = 
            [
                #ref{mfa = MFA1,
                    cnt = length(Css),
                    own = ms_to_s(vprof_q:keysum(#call.own, Css)),
                    acc = ms_to_s(vprof_q:keysum(#call.acc, without_recursion(Css)))}
                     || {MFA1, Css} <- vprof_q:qq(Cs, [ [#call.children], '++', [FetchCall], {group, #call.mfa} ] ) ],
            Row = #function{pid = SPid, cnt = length(CallIds), mfa = MFA,
                own = ms_to_s(vprof_q:keysum(#call.own, Cs)),
                acc = ms_to_s(vprof_q:keysum(#call.acc, [C || C <- Cs, C#call.recursion =:= undefined])),
                parents = Parents,
                children = Children
            },
            [Row|Acc]
        end, [], MFAs))),
    Procs1 = [#process{pid = SPid, own = ms_to_s(Own), cnt = array:size(Calls), schedules = Schedules}|Procs],
    {Procs1, Rows1 ++ Rows}.

without_recursion(Cs) ->
    CallIds = [ CallId || #call{id = CallId} <- Cs ],
    [ C || C <- Cs, not lists:member(C#call.recursion, CallIds) ].

ms_to_s(MS) ->
    MS / 1000000.

convert_pid(Pid) ->
    List = pid_to_list(Pid),
    [_A,B,C] = string:tokens(List, "."),
    string:join(["<0",B,C], ".").