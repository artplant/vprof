%% @author: Andrey Tsirulev
%% @date: 13.08.2014

-module(vprof_grid).

-behaviour(wx_object).

-include_lib("wx/include/wx.hrl").
-include("vprof.hrl").

-export([
    start_link/7,
    set_data/2
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


-define(GRID, 500).

-define(EVEN(Row), ((Row rem 2) =:= 0)).
-define(BG_EVEN,    {230,230,250}).
-define(BG_ODD,     {255,255,255}).
 
-record(state, {
    parent,
    grid,
    selected,
    tabs,
    data_ref,
    data,
    columns,
    sort_key,
    sort_reversed = false,
    on_select,
    on_activate
}).

start_link(Panel, Parent, DataRef, DataTag, Columns, OnSelect, OnActivate) ->
    wx_object:start_link(?MODULE, {Panel, Parent, DataRef, DataTag, Columns, OnSelect, OnActivate}, []).

set_data(Grid, DataTag) ->
    wx_object:cast(Grid, {set_data, DataTag}).

init({Panel, Parent, DataRef, DataTag, Columns, OnSelect, OnActivate}) ->
    Data = vprof_data:info(DataRef, DataTag),
    
    Style = ?wxLC_REPORT bor ?wxLC_SINGLE_SEL bor ?wxLC_HRULES,
    Grid = wxListCtrl:new(Panel, [{winid, ?GRID}, {style, Style}]),
    Li = wxListItem:new(),
    AddListEntry =
        fun(#table_column{title = Name, alignment = Align, default_width = DefSize}, Col) ->
            wxListItem:setText(Li, Name),
            wxListItem:setAlign(Li, Align),
            wxListCtrl:insertColumn(Grid, Col, Li),
            wxListCtrl:setColumnWidth(Grid, Col, DefSize),
            Col + 1
        end,
    lists:foldl(AddListEntry, 0, Columns),
    wxListItem:destroy(Li),

    wxListCtrl:connect(Grid, command_list_item_activated),
    wxListCtrl:connect(Grid, command_list_item_selected),
    wxListCtrl:connect(Grid, command_list_col_click),
    wxListCtrl:connect(Grid, size, [{skip, true}]),

    {SortKey, SortReversed} =
        case lists:keyfind(true, #table_column.default_sort, Columns) of
            #table_column{binding = Binding, default_reversed = DefaultReversed} -> {Binding, DefaultReversed};
            false -> {(hd(Columns))#table_column.binding, (hd(Columns))#table_column.default_reversed}
        end,

    State = #state{grid = Grid, parent = Parent, data = Data, data_ref = DataRef, columns = Columns, sort_key = SortKey, sort_reversed = SortReversed,
        on_select = OnSelect, on_activate = OnActivate},
    State1 = update_grid(State),

    wxWindow:setFocus(Grid),
    {Grid, State1}.

handle_event(#wx{event=#wxList{type=command_list_col_click, col=Col}}, State) ->
    #state{grid = Grid, columns = Columns, sort_key = SortKey, sort_reversed = SortReversed} = State,
    Column = lists:nth(Col + 1, Columns),
    State1 =
        case Column#table_column.binding of
            SortKey -> State#state{sort_reversed = not SortReversed};
            NewKey -> State#state{sort_key = NewKey, sort_reversed = Column#table_column.default_reversed}
        end,
    State2 = update_grid(State1),
    wxWindow:setFocus(Grid),
    {noreply, State2};
handle_event(#wx{event=#wxSize{size={_,_}}}, State) ->
    auto_size(State),
    {noreply, State};
handle_event(#wx{event=#wxList{type=command_list_item_activated,itemIndex=Index}}, State) ->
    #state{data = Data, on_activate = OnActivate} = State,
    case OnActivate of
        undefined -> ignore;
        _ ->
            DataRow = lists:nth(Index + 1, Data),
            OnActivate(DataRow)
    end,    
    {noreply, State#state{selected=Index}};
handle_event(#wx{event=#wxList{type=command_list_item_selected, itemIndex=Index}}, State) ->
    #state{data = Data, on_select = OnSelect} = State,
    case OnSelect of
        undefined -> ignore;
        _ ->
            DataRow = lists:nth(Index + 1, Data),
            OnSelect(DataRow)
    end,    
    {noreply, State#state{selected=Index}};

handle_event(Event, _State) ->
    error({unhandled_event, Event}).

handle_sync_event(_Event, _Obj, _State) ->
    ok.

handle_call(Event, From, _State) ->
    error({unhandled_call, Event, From}).

handle_cast({set_data, DataTag}, State) ->
    Data = vprof_data:info(State#state.data_ref, DataTag),
    State1 = update_grid(State#state{data = Data}),
    {noreply, State1};
handle_cast(Event, _State) ->
    error({unhandled_cast, Event}).

handle_info({error, Error}, State) ->
    handle_error(Error),
    {noreply, State};
handle_info(_Event, State) ->
    {noreply, State}.

terminate(_Event, _State) ->
    ok.

code_change(_, _, State) ->
    State.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

handle_error(Foo) ->
    Str = io_lib:format("ERROR: ~s~n",[Foo]),
    observer_lib:display_info_dialog(Str).

update_grid(State) ->
    wx:batch(fun() -> do_update_grid(State) end).

do_update_grid(State) ->
    #state{grid = Grid, columns = Columns, sort_key = SortKey, sort_reversed = Reversed, data = Data} = State,
    Data1 = lists:keysort(SortKey, Data),
    Data2 = 
        case Reversed of
            true -> lists:reverse(Data1);
            false -> Data1
        end,
    wxListCtrl:deleteAllItems(Grid),
    Update =
        fun(DataRow, RowIndex) ->
            _Item = wxListCtrl:insertItem(Grid, RowIndex, ""),
            if ?EVEN(RowIndex) ->
                    wxListCtrl:setItemBackgroundColour(Grid, RowIndex, ?BG_EVEN);
                true -> 
                    ignore
            end,

            lists:foreach(
                fun({ColIndex, Column}) ->
                    Val = element(Column#table_column.binding, DataRow),
                    wxListCtrl:setItem(Grid, RowIndex, ColIndex, format(Column#table_column.format, Val))
                end,
                vprof_q:seq_zip(Columns, 0)),
            
            RowIndex + 1
        end,
    lists:foldl(Update, 0, Data2),
    State#state{data = Data2}.

auto_size(State) ->
    wx:batch(fun() -> do_auto_size(State) end).

do_auto_size(State) ->
    #state{grid = Grid, columns = Columns} = State,
    TotalSize = element(1, wxWindow:getClientSize(Grid)) - scroll_size(Grid),
    {_, LeftSize, AutoSizeColumns} = lists:foldl(
        fun(Column, {I, Sz, Cs}) ->
            case Column#table_column.auto_size of
                true ->
                    {I + 1, Sz, [I|Cs]};
                false ->
                    {I + 1, Sz - wxListCtrl:getColumnWidth(Grid, I), Cs}
            end
        end, {0, TotalSize, []}, Columns),
    case AutoSizeColumns of
        [] -> ignore;
        _ ->
            AutoSize = max(LeftSize div length(AutoSizeColumns), 50),
            [ wxListCtrl:setColumnWidth(Grid, I, AutoSize) || I <- AutoSizeColumns ],
            ok
    end.

scroll_size(LCtrl) ->
    case os:type() of
        {win32, nt} -> 0;
        {unix, darwin} ->
            wxSystemSettings:getMetric(?wxSYS_VSCROLL_X);
        _ ->
            case wxWindow:hasScrollbar(LCtrl, ?wxVERTICAL) of
                true -> wxSystemSettings:getMetric(?wxSYS_VSCROLL_X);
                false -> 0
            end
    end.

format(float, Value) when is_number(Value) ->
    float_to_list(float(Value));
format({float, P}, Value) when is_number(Value) ->
    float_to_list(float(Value), [{decimals, P}]);
format(mfa, {Mod,Fun,A}) ->
    io_lib:format("~p:~p/~p", [Mod,Fun,A]);
format(string, Value) when is_list(Value) ->
    io_lib:format("~s", [Value]);
format(_, Value) ->
    io_lib:format("~p", [Value]).
