%% @author: Andrey Tsirulev
%% @date: 29.11.2013

-module(vprof_gui).

-behaviour(wx_object).

%% Include files
-include_lib("wx/include/wx.hrl").
-include("vprof.hrl").

%% Exported Functions

-export([
    start/1,
    start_link/1,
    init/1,
    handle_event/2,
    handle_cast/2,
    handle_call/3,
    handle_info/2,
    terminate/2,
    code_change/3
]).

-record(state, {
    data,
    frame,
    menubar,
    menus = [],
    status_bar,
    notebook,
    main_panel,
    active_tab,
    pages = []
}).

-record(page, {
    id,
    module,
    content
}).

-define(ID_NOTEBOOK, 3).

%%%===================================================================
%%% API
%%%===================================================================
start(Data) ->
    wx_object:start(?MODULE, Data, []).

start_link(Data) ->
    wx_object:start_link(?MODULE, Data, []).

init(Data) ->
    wx:new(),
    Frame = wxFrame:new(wx:null(), ?wxID_ANY, "vprof analysis visualizer", [{size, {850, 600}}, {style, ?wxDEFAULT_FRAME_STYLE}]),
    State = #state{frame = Frame, data = Data},
    UpdState = setup(State),
    process_flag(trap_exit, true),
    {Frame, UpdState}.

handle_event(#wx{event=#wxNotebook{type=command_notebook_page_changing}}, State) ->
    {noreply, State};
handle_event(#wx{event = #wxClose{}}, State) ->
    {stop, normal, State};
handle_event(#wx{id = ?wxID_EXIT, event = #wxCommand{type = command_menu_selected}}, State) ->
    {stop, normal, State};
handle_event(#wx{id = ?wxID_ABOUT, event = #wxCommand{type = command_menu_selected}},
    State = #state{frame=Frame}) ->
    AboutString = "vprof analysis visualizer",
    Style = [{style, ?wxOK bor ?wxSTAY_ON_TOP}, {caption, "About"}],
    wxMessageDialog:showModal(wxMessageDialog:new(Frame, AboutString, Style)),
    {noreply, State};
handle_event(_Event, State) ->
    {noreply, State}.

handle_cast({status_bar, Msg}, State=#state{status_bar=SB}) ->
    wxStatusBar:setStatusText(SB, Msg),
    {noreply, State};
handle_cast(_Cast, State) ->
    {noreply, State}.

handle_call(_Msg, _From, State) ->
    {reply, ok, State}.

handle_info({'EXIT', Pid, _Reason}, State) ->
    io:format("Child crashed exiting:  ~p ~p~n", [Pid,_Reason]),
    {stop, normal, State};
handle_info({open_page, Content, Title, Module}, State) ->
    State1 = open_page(State, Content, Title, Module),
    {noreply, State1};
handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, #state{frame = Frame}) ->
    wxFrame:destroy(Frame),
    ok.

code_change(_, _, State) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
setup(#state{frame = Frame} = State) ->
    %% Setup Menubar & Menus
    MenuBar = wxMenuBar:new(),

    DefMenus = default_menus(),
    create_menus(DefMenus, MenuBar, default),

    wxFrame:setMenuBar(Frame, MenuBar),
    StatusBar = wxFrame:createStatusBar(Frame, []),
    Filename = vprof_data:filename(State#state.data),
    wxFrame:setTitle(Frame, Filename),
    wxStatusBar:setStatusText(StatusBar, Filename),
    
    %% Setup panels
    Panel = wxPanel:new(Frame, []),
    Notebook = wxNotebook:new(Panel, ?ID_NOTEBOOK, [{style, ?wxBK_DEFAULT}]),

    Data = State#state.data,

    FunsPanel = vprof_functions:start_link(Notebook, Data, self()),
    wxNotebook:addPage(Notebook, FunsPanel, "Functions", []),

    ProcessesPanel = vprof_processes:start_link(Notebook, Data, self()),
    wxNotebook:addPage(Notebook, ProcessesPanel, "Processes", []),

    %% Setup sizer create early to get it when window shows
    MainSizer = wxBoxSizer:new(?wxVERTICAL),

    wxSizer:add(MainSizer, Notebook, [{proportion, 1}, {flag, ?wxEXPAND}]),
    wxPanel:setSizer(Panel, MainSizer),

    wxNotebook:connect(Notebook, command_notebook_page_changing),
    wxFrame:connect(Frame, close_window, [{skip, true}]),
    wxMenu:connect(Frame, command_menu_selected),
    wxFrame:show(Frame),

    %% Force redraw (window needs it)
    wxWindow:refresh(Panel),
    wxWindow:setFocus(Panel),

    SysPid = wx_object:get_pid(FunsPanel),
    SysPid ! {active, node()},
    UpdState = State#state{main_panel = Panel,
                    notebook = Notebook,
                    menubar = MenuBar,
                    status_bar = StatusBar,
                    active_tab = SysPid},
    UpdState.

-record(create_menu, {
    id,
    text,
    help = [],
    type = append,
    check = false
}).

default_menus() ->
    Quit  = #create_menu{id = ?wxID_EXIT, text = "Quit"},
    About = #create_menu{id = ?wxID_ABOUT, text = "About"},
    [{"&File", [Quit]}, {"&Help", [About]}].

create_menus([], _MenuBar, _Type) -> ok;
create_menus(Menus, MenuBar, Type) ->
    Add = fun({Tag, Ms}, Index) ->
		  create_menu(Tag, Ms, Index, MenuBar, Type)
	  end,
    wx:foldl(Add, 0, Menus),
    ok.

create_menu(Name, MenuItems, Index, MenuBar, _Type) ->
    Menu = wxMenu:new(),
    lists:foldl(fun(Record, N) ->
        create_menu_item(Record, Menu, N)
    end, 0, MenuItems),
    wxMenuBar:insert(MenuBar, Index, Menu, Name),
    Index+1.

create_menu_item(#create_menu{id = ?wxID_HELP=Id}, Menu, Index) ->
    wxMenu:insert(Menu, Index, Id),
    Index+1;
create_menu_item(#create_menu{id=Id, text=Text, help=Help, type=Type, check=Check},
		 Menu, Index) ->
    Opts = case Help of
	       [] -> [];
	       _ -> [{help, Help}]
	   end,
    case Type of
	append ->
	    wxMenu:insert(Menu, Index, Id,
			  [{text, Text}|Opts]);
	check ->
	    wxMenu:insertCheckItem(Menu, Index, Id, Text, Opts),
	    wxMenu:check(Menu, Id, Check);
	radio ->
	    wxMenu:insertRadioItem(Menu, Index, Id, Text, Opts),
	    wxMenu:check(Menu, Id, Check);
	separator ->
	    wxMenu:insertSeparator(Menu, Index)
    end,
    Index+1;
create_menu_item(separator, Menu, Index) ->
    wxMenu:insertSeparator(Menu, Index),
    Index+1.

find_page(Notebook, Id) ->
    PageCount = wxNotebook:getPageCount(Notebook),
    hd([ N || N <- lists:seq(0, PageCount - 1), wxWindow:getId(wxNotebook:getPage(Notebook, N)) =:= Id ]).

open_page(State, Content, Title, Module) ->
    #state{pages = Pages, notebook = Notebook, data = Data} = State,
    case lists:keyfind(Content, #page.content, Pages) of
        #page{id = Id} ->
            PageIndex = find_page(Notebook, Id),
            wxNotebook:setSelection(Notebook, PageIndex),
            State;
        false ->
            Panel = Module:start_link(Notebook, Data, self(), Content),
            wxNotebook:addPage(Notebook, Panel, Title, [{bSelect, true}]),
            Id = wxWindow:getId(Panel),
            NewPages = [ #page{id = Id, module = Module, content = Content} | Pages ],
            State#state{pages = NewPages}
    end.
