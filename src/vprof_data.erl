%% @author: Andrey Tsirulev
%% @date: 29.11.2013

-module(vprof_data).

-behaviour(gen_server).

-include("vprof.hrl").

-export([
    start_link/1,
    start_link/2,
    info/2,
    filename/1
]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-record(state, {
    filename,
    funs,
    procs
}).

%%%===================================================================
%%% API
%%%===================================================================
start_link(Name, FileName) ->
    gen_server:start_link({local, Name}, ?MODULE, FileName, []).

start_link(FileName) ->
    gen_server:start_link(?MODULE, FileName, []).

filename(Ref) ->
    info(Ref, filename).

info(Ref, Cmd) ->
    gen_server:call(Ref, Cmd, 10000).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init(FileName) ->
    State = load(FileName),
    {ok, State}.

handle_call(Info, _From, State) ->
    Reply = get_info(Info, State),
    {reply, Reply, State}.

handle_cast(stop, State) ->
    {stop, normal, State}.

handle_info({load, FileName}, _) ->
    State = load(FileName),
    io:format("~p loaded~n", [FileName]),
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
load(FileName) ->
    {ok, [{Procs,Funs}]} = file:consult(FileName),
    #state{
        filename = FileName,
        funs = Funs,
        procs = Procs}.

get_info(filename, State) ->
    State#state.filename;
get_info(pids, State) ->
    ordsets:from_list([ R#function.pid || R <- State#state.funs ]);
get_info(funs, State) ->
    ordsets:from_list([ R#function.mfa || R <- State#state.funs ]);
get_info({calls, Pid}, State) ->
    [ fun_to_row(Fun) || Fun <- State#state.funs, Fun#function.pid =:= Pid ];
get_info(total_calls, State) ->
    Groups = vprof_q:group(#function.mfa, State#state.funs),
    [ #row{mfa = MFA, pid_count = vprof_q:qq(Funs, [ [#function.pid], ordset, length ]), 
            cnt = vprof_q:keysum(#function.cnt, Funs), 
            acc = vprof_q:keysum(#function.acc, Funs), 
            own = vprof_q:keysum(#function.own, Funs)} || {MFA, Funs} <- Groups ];
get_info(processes, State) ->
    State#state.procs;
get_info(processes_summary, State) ->
    Procs = State#state.procs,
    [ #process{pid = length(Procs),
            cnt = vprof_q:keysum(#process.cnt, Procs),
            own = vprof_q:keysum(#process.own, Procs),
            schedules = vprof_q:keysum(#process.schedules, Procs)} ];
get_info({processes, MFA}, State) ->
    [ fun_to_row(Fun) || Fun <- State#state.funs, Fun#function.mfa =:= MFA ];
get_info({called_by, Pid, MFA}, State) ->
    case [ Fun || Fun <- State#state.funs, Fun#function.mfa =:= MFA, Fun#function.pid =:= Pid ] of
        [F | _] ->
            [ ref_to_row(Ref, Pid) || Ref <- F#function.parents ];
        [] ->
            []
    end;
get_info({called_by, MFA}, State) ->
    Groups = vprof_q:group(#function.mfa, [ #function{mfa = Ref#ref.mfa, acc = Ref#ref.acc, cnt = Ref#ref.cnt, own = Ref#ref.own, pid = Fun#function.pid} || Fun <- State#state.funs, Fun#function.mfa =:= MFA, Ref <- Fun#function.parents ]),
    [ #row{mfa = CallingMFA, pid_count = vprof_q:qq(Funs, [ [#function.pid], ordset, length ]), 
           cnt = vprof_q:keysum(#function.cnt, Funs), 
           acc = vprof_q:keysum(#function.acc, Funs), 
           own = vprof_q:keysum(#function.own, Funs)} || {CallingMFA, Funs} <- Groups ];
get_info({mfa, Pid, MFA}, State) ->
    case [ Fun || Fun <- State#state.funs, Fun#function.mfa =:= MFA, Fun#function.pid =:= Pid ] of
        [F | _] ->
            [ fun_to_row(F) ];
        [] ->
            []
    end;
get_info({mfa, MFA}, State) ->
    Funs = [ Fun || Fun <- State#state.funs, Fun#function.mfa =:= MFA ],
    [ #row{mfa = MFA, pid_count = vprof_q:qq(Funs, [ [#function.pid], ordset, length ]), 
            cnt = vprof_q:keysum(#function.cnt, Funs), 
            acc = vprof_q:keysum(#function.acc, Funs), 
            own = vprof_q:keysum(#function.own, Funs)} ];
get_info({calling, Pid, MFA}, State) ->
    case [ Fun || Fun <- State#state.funs, Fun#function.mfa =:= MFA, Fun#function.pid =:= Pid ] of
        [F | _] ->
            [ ref_to_row(Ref, Pid) || Ref <- F#function.children ];
        [] ->
            []
    end;
get_info({calling, MFA}, State) ->
    Groups = vprof_q:group(#function.mfa, [ #function{mfa = Ref#ref.mfa, acc = Ref#ref.acc, cnt = Ref#ref.cnt, own = Ref#ref.own, pid = Fun#function.pid} || Fun <- State#state.funs, Fun#function.mfa =:= MFA, Ref <- Fun#function.children ]),
    [ #row{mfa = CalledMFA, pid_count = vprof_q:qq(Funs, [ [#function.pid], ordset, length ]), 
           cnt = vprof_q:keysum(#function.cnt, Funs), 
           acc = vprof_q:keysum(#function.acc, Funs), 
           own = vprof_q:keysum(#function.own, Funs)} || {CalledMFA, Funs} <- Groups ];
get_info(Unknown, _State) ->
    io:format("unknown data tag: ~p~n", [Unknown]).

fun_to_row(Fun) ->
    #function{cnt = Cnt, acc = Acc, own = Own, pid = Pid, mfa = MFA} = Fun,
    #row{cnt = Cnt, acc = Acc, own = Own, pid = Pid, mfa = MFA}.

ref_to_row(Ref, Pid) ->
    #ref{cnt = Cnt, acc = Acc, own = Own, mfa = MFA} = Ref,
    #row{cnt = Cnt, acc = Acc, own = Own, mfa = MFA, pid = Pid}.
    