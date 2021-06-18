%% @author: Andrey Tsirulev
%% @date: 13.08.2014

-module(vprof_processes).

-behaviour(wx_object).

-include_lib("wx/include/wx.hrl").
-include("vprof.hrl").
-include("wx_compat.hrl").

-export([
    start_link/3
]).

%% wx_object callbacks
-export([
    init/1,
    handle_info/2,
    terminate/2,
    code_change/3,
    handle_call/3,
    handle_event/2,
    handle_sync_event/3,
    handle_cast/2]).


-record(state, {
    parent,
    processes_grid
}).

start_link(Notebook, Data, Parent) ->
    wx_object:start_link(?MODULE, {Notebook, Data, Parent}, []).

init({Notebook, Data, Parent}) ->
    Panel = wxPanel:new(Notebook, [{size, wxWindow:getClientSize(Notebook)}]),
    
    Splitter = vprof_wx_utils:splitter(Panel),
    LeftPanel = wxPanel:new(Splitter, [{size, wxWindow:getClientSize(Splitter)}]),
    ProcessGrid = process_grid(Splitter, Data, undefined),
    vprof_wx_utils:split_vertical(Splitter, 0.3, LeftPanel, ProcessGrid),
    
    TotalsGrid = totals_grid(LeftPanel, Data, Parent),
    SummaryGrid = summary_grid(LeftPanel, Data),
    Box = wxBoxSizer:new(?wxVERTICAL),
    wxBoxSizer:add(Box, TotalsGrid, [{flag, ?wxEXPAND bor ?wxALL}, {proportion, 1}, {border, 5}]),
    Item =  wxBoxSizer:add(Box, 100, 50, [{flag, ?wxEXPAND bor ?wxALL}, {border, 5}]),
    wxSizerItem:?assignWindow(Item, SummaryGrid),
    wxSizerItem:setMinSize(Item, 60, 60),
    wxWindow:setSizer(LeftPanel, Box),
    
    State = #state{parent = Parent, processes_grid = ProcessGrid},
    
    {Panel, State}.

summary_grid(Panel, Data) ->
    GridColumns = [
        #table_column{title = "Total", auto_size = true, alignment = ?wxLIST_FORMAT_LEFT,
            format = string, default_width = 200, binding = #process.pid},
        #table_column{title = "Count", alignment = ?wxLIST_FORMAT_RIGHT, default_width = 100, 
            binding = #process.cnt, default_reversed = true},
        #table_column{title = "Schedules", alignment = ?wxLIST_FORMAT_RIGHT, default_width = 100, 
            binding = #process.schedules, default_reversed = true},
        #table_column{title = "Time", alignment = ?wxLIST_FORMAT_RIGHT, default_width = 100, 
            format = {float, 3}, binding = #process.own, default_reversed = true, default_sort = true}
    ],
    vprof_grid:start_link(Panel, self(), Data, processes_summary, GridColumns, undefined, undefined).

totals_grid(Panel, Data, Parent) ->
    GridColumns = [
        #table_column{title = "PID", auto_size = true, alignment = ?wxLIST_FORMAT_LEFT,
            format = string, default_width = 200, binding = #process.pid},
        #table_column{title = "Count", alignment = ?wxLIST_FORMAT_RIGHT, default_width = 100, 
            binding = #process.cnt, default_reversed = true},
        #table_column{title = "Schedules", alignment = ?wxLIST_FORMAT_RIGHT, default_width = 100, 
            binding = #process.schedules, default_reversed = true},
        #table_column{title = "Time", alignment = ?wxLIST_FORMAT_RIGHT, default_width = 100, 
            format = {float, 3}, binding = #process.own, default_reversed = true, default_sort = true}
    ],
    Self = self(),
    OnSelect = fun(DataRow) -> Self ! {select_process, DataRow} end,
    OnActivate = fun(DataRow) -> Parent ! {open_page, DataRow#process.pid, DataRow#process.pid, vprof_process} end,
    vprof_grid:start_link(Panel, self(), Data, processes, GridColumns, OnSelect, OnActivate).

process_grid(Panel, Data, Process) ->
    Columns = [
        #table_column{title = "Function", auto_size = true, alignment = ?wxLIST_FORMAT_LEFT,
            format = mfa, default_width = 70, binding = #row.mfa},
        #table_column{title = "Count", alignment = ?wxLIST_FORMAT_RIGHT, default_width = 100, 
            binding = #row.cnt, default_reversed = true},
        #table_column{title = "Acc time", alignment = ?wxLIST_FORMAT_RIGHT, default_width = 100, 
            format = {float, 3}, binding = #row.acc, default_reversed = true, default_sort = true},
        #table_column{title = "Own time", alignment = ?wxLIST_FORMAT_RIGHT, default_width = 100, 
            format = {float, 3}, binding = #row.own, default_reversed = true}
    ],
    vprof_grid:start_link(Panel, self(), Data, {calls, Process}, Columns, undefined, undefined).
    
handle_event(Event, _State) ->
    error({unhandled_event, Event}).

handle_sync_event(_Event, _Obj, _State) ->
    ok.

handle_call(Event, From, _State) ->
    error({unhandled_call, Event, From}).

handle_cast(Event, _State) ->
    error({unhandled_cast, Event}).

handle_info({select_process, DataRow}, State) ->
    vprof_grid:set_data(State#state.processes_grid, {calls, DataRow#process.pid}),
    {noreply, State};
handle_info(_Event, State) ->
    {noreply, State}.

terminate(_Event, _State) ->
    ok.

code_change(_, _, State) ->
    State.

