%% @author: Andrey Tsirulev
%% @date: 01.12.2013

-module(vprof).

%% Include files
-include("vprof.hrl").

%% Exported Functions

-export([
    trace/1,
    trace/2,
    trace_fun/1,
    start_trace/1,
    start_trace/2,
    stop_trace/0,
    profile/0,
    profile/2,
    cancel_profile/1,
    gui/0,
    gui/1
]).

-type filename() :: string().

%%%===================================================================
%%% API
%%%===================================================================
-spec trace(number()) -> 'ok'.

%% @doc Trace all processes for X seconds to "vprof.trace" file.

trace(Seconds) ->
    trace(Seconds, "vprof.trace").

-spec trace(number(), filename()) -> 'ok'.

%% @doc Trace all processes for X seconds to the specified file.

trace(Seconds, TraceFile) ->
    start_trace(all, TraceFile),
    timer:sleep(round(Seconds * 1000)),
    stop_trace().

trace_fun(Fun) ->
    start_trace(self()),
    Fun(),
    stop_trace().

start_trace(Process) ->
    start_trace(Process, "vprof.trace").

start_trace(Process, TraceFile) ->
    TraceFun = dbg:trace_port(file, TraceFile),
    {ok, _TracerPid} = dbg:tracer(port, TraceFun),
    dbg:tpl('_', []),
    dbg:p(Process, [call, timestamp, return_to, arity, running, procs]).

-spec stop_trace() -> 'ok'.

stop_trace() ->
    erlang:trace(all, false, [all]),
    dbg:stop_clear().

-spec profile() -> pid().

%% @doc Profile "vprof.trace", dump results to "vprof.out". 
%% Profile may take several minutes, pass the returned pid to cancel_profile to cancel it.

profile() ->
    profile("vprof.trace", "vprof.out").

-spec profile(filename(), filename()) -> pid().

%% @doc Profile TraceFile, dump results to DataFile.
%% Profile may take several minutes, pass the returned pid to cancel_profile to cancel it.

profile(TraceFile, DataFile) ->
    vprof_profile:profile(TraceFile, DataFile).

-spec cancel_profile(pid()) -> 'ok'.

%% @doc Cancel profile.

cancel_profile(Pid) ->
    dbg:stop_trace_client(Pid).

-spec gui() -> 'ok'.

%% @doc Show GUI with analysis for "vprof.out" file.

gui() ->
    gui("vprof.out").

-spec gui(filename()) -> 'ok'.

%% @doc Show GUI with analysis for the specified analysis file.

gui(DataFile) ->
    {ok, Pid} = vprof_data:start_link(DataFile),
    vprof_gui:start(Pid),
    ok.
