%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%   Copyright 2016 Purvey, Inc.
%%
%%   Licensed under the Apache License, Version 2.0 (the "License");
%%   you may not use this file except in compliance with the License.
%%   You may obtain a copy of the License at
%%
%%       http://www.apache.org/licenses/LICENSE-2.0
%%
%%   Unless required by applicable law or agreed to in writing, software
%%   distributed under the License is distributed on an "AS IS" BASIS,
%%   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%%   See the License for the specific language governing permissions and
%%   limitations under the License.
%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @author: Garrison M. Venn
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

-module(pur_utls_single_xdr_service).

% Not using pur_utls_accept_server/pur_utls_recv_slave mechanism.

-behavior(pur_utls_pipe_server).

-export([spawn/4, spawn/3,
         handle_call/3, handle_cast/2, handle_info/2, handle_pipe/2,
         terminate/2, code_change/3,
         init/1]).

-include_lib("pur_utls_misc.hrl").
-include_lib("pur_utls_xdr.hrl").
-include_lib("pur_utls_props.hrl").
-include_lib("pur_utls_pipes.hrl").

%%----------------------------------------------------------------------------
%% Records
%%----------------------------------------------------------------------------

-record(state, {port, 
                options = [], 
                socket, 
                size_length, 
                xdr_codecs,
                listen_ref = make_ref()}).

%%----------------------------------------------------------------------------
%% "Init" Behavior
%%----------------------------------------------------------------------------

init(Props) -> 
    InitFunctions =
        [fun 
             (_NProps, _Context, State = #state{options = Options}) when
                     is_list(Options) ->
                 NOptions = 
                     [binary, {packet, raw}, {active, false}] ++ Options,
                 {true, State#state{options = NOptions}};
             (_NProps, _Context, State) ->
                 Options = [binary, {packet, raw}, {active, false}],
                 {true, State#state{options = Options}}
         end,
         fun (_NProps, _Context, State) ->
             {true, State#state{xdr_codecs = pur_utls_xdr:build_codecs()}}
         end],
    pur_utls_server:auto_init(
        Props,
        [#propdesc{name = "port", 
                   index = #state.port,
                   ret_type = integer,
                   directive = default,
                   dirvalue = 0},
         #propdesc{name = "size_length", 
                   index = #state.size_length,
                   ret_type = integer,
                   directive = required,
                   dirvalue = true},
         #propdesc{name = "options", 
                   index = #state.options,
                   directive = required,
                   dirvalue = false}],
        InitFunctions,
        [],
        #state{}).

terminate(Reason, State) ->
    SState = stop_server(State),
    case Reason of
        normal -> ok;
        shutdown -> ok;
        {shutdown, _} -> ok;
        Reason -> ?LogIt(terminate,
                         "Terminated for reason: ~n~p, ~nwith state:~n~p.",
                         [Reason, SState])
    end.

code_change(_, State, _) -> 
    {ok, State}.

%%----------------------------------------------------------------------------
%% Genserver Exported Behavior
%%----------------------------------------------------------------------------

%%----------------------------------------------------------------------------
%% handle_call
%%----------------------------------------------------------------------------

%%----------------------------------------------------------------------------
%% start_server
%%----------------------------------------------------------------------------

handle_call(start_server, _From, State) ->
    {reply, ok, trigger_start_server(State)};

%%----------------------------------------------------------------------------
%% stop_server
%%----------------------------------------------------------------------------

handle_call(stop_server, _From, State) ->
    {reply, ok, stop_server(State)};

%%----------------------------------------------------------------------------
%% Unknown call expression
%%----------------------------------------------------------------------------

handle_call(Expr, _From, State) ->
    ?LogIt({handle_call, unknown}, "Unknown expr: ~n~p. ~nIgnoring", [Expr]),
    {reply, ok, State}.

%%----------------------------------------------------------------------------
%% handle_cast
%%----------------------------------------------------------------------------

%%----------------------------------------------------------------------------
%% start_server
%%----------------------------------------------------------------------------

handle_cast(start_server, State) ->
    {noreply, trigger_start_server(State)};

%%----------------------------------------------------------------------------
%% stop_server
%%----------------------------------------------------------------------------

handle_cast(stop_server, State) ->
    {noreply, stop_server(State)};


%%----------------------------------------------------------------------------
%% start_server_cont
%%----------------------------------------------------------------------------

handle_cast({start_server_cont, Ref}, State = #state{listen_ref = Ref}) ->
    {noreply, start_server(State)};

%%----------------------------------------------------------------------------
%% Unknown cast expression
%%----------------------------------------------------------------------------

handle_cast(Expr, State) ->
    ?LogIt({handle_cast, unknown}, "Unknown expr: ~n~p. ~nIgnoring", [Expr]),
    {noreply, State}.

%%----------------------------------------------------------------------------
%% handle_info
%%----------------------------------------------------------------------------

%%----------------------------------------------------------------------------
%% Unknown info expression
%%----------------------------------------------------------------------------

handle_info(Expr, State) ->
    ?LogIt({handle_info, unknown}, "Unknown expr: ~n~p. ~nIgnoring", [Expr]),
    {noreply, State}.

%%----------------------------------------------------------------------------
%% handle_pipe
%%----------------------------------------------------------------------------

%%----------------------------------------------------------------------------
%% next_xdr_args pipe expression
%%----------------------------------------------------------------------------

handle_pipe({#pipe_context{session_id = SessionId}, 
             next_xdr_args, 
             XdrCallArgs}, 
            State) ->
    {Reply, NState} = receive_and_transform(XdrCallArgs, State),
    {reply, Reply, SessionId, NState};

%%----------------------------------------------------------------------------
%% Unknown pipe expression
%%----------------------------------------------------------------------------

handle_pipe({#pipe_context{session_id = SessionId}, _Term, Expr}, State) ->
    % Skips to next in pipe
    {reply, Expr, SessionId, State}.

%%----------------------------------------------------------------------------
%% Exported Functions
%%----------------------------------------------------------------------------

%%----------------------------------------------------------------------------
%% "Spawn" Behavior
%%----------------------------------------------------------------------------

spawn(nolink, Name = {global, _RegName}, StartArgs, StartOptions) ->
    NStartArgs = [{callback_module, ?MODULE}|StartArgs],
    pur_utls_pipe_server:spawn(nolink, Name, NStartArgs, StartOptions);
spawn(nolink, Name = {local, _RegName}, StartArgs, StartOptions) ->
    NStartArgs = [{callback_module, ?MODULE}|StartArgs],
    pur_utls_pipe_server:spawn(nolink, Name, NStartArgs, StartOptions);
spawn(link, Name = {global, _RegName}, StartArgs, StartOptions) ->
    NStartArgs = [{callback_module, ?MODULE}|StartArgs],
    pur_utls_pipe_server:spawn(link, Name, NStartArgs, StartOptions);
spawn(link, Name = {local, _RegName}, StartArgs, StartOptions) ->
    NStartArgs = [{callback_module, ?MODULE}|StartArgs],
    pur_utls_pipe_server:spawn(link, Name, NStartArgs, StartOptions).

spawn(nolink, StartArgs, StartOptions) ->
    NStartArgs = [{callback_module, ?MODULE}|StartArgs],
    pur_utls_pipe_server:spawn(nolink, NStartArgs, StartOptions);
spawn(link, StartArgs, StartOptions) ->
    NStartArgs = [{callback_module, ?MODULE}|StartArgs],
    pur_utls_pipe_server:spawn(link, NStartArgs, StartOptions).

%%----------------------------------------------------------------------------
%% Internal Functions
%%----------------------------------------------------------------------------

%%----------------------------------------------------------------------------
%% listen
%%----------------------------------------------------------------------------

trigger_start_server(State = #state{socket = undefined, listen_ref = Ref}) ->
    gen_server:cast(self(), {start_server_cont, Ref}),
    State;
trigger_start_server(State) ->
    State.

%%----------------------------------------------------------------------------
%% start_server
%%----------------------------------------------------------------------------

start_server(State = #state{port = Port, 
                            options = Options, 
                            socket = undefined}) ->
    % Need to protect this code from exceptions
    {ok, ListenSocket} = gen_tcp:listen(Port, Options),
    {ok, Socket} = gen_tcp:accept(ListenSocket),
    State#state{socket = Socket};
start_server(State) ->
    State.

%%----------------------------------------------------------------------------
%% stop_server
%%----------------------------------------------------------------------------

stop_server(State = #state{socket = undefined}) ->
    State;
stop_server(State = #state{socket = Socket}) ->
    % Need to protect this code from exceptions
    % Need to close?
    gen_tcp:shutdown(Socket, read),
    % Closing anyway. Need to re-look at socket impl specs.
    gen_tcp:close(Socket),
    State#state{socket = undefined}.

%%----------------------------------------------------------------------------
%% receive_and_transform
%%----------------------------------------------------------------------------

receive_and_transform(_XdrCallArgs, State = #state{socket = undefined}) ->
    {undefined, State};
receive_and_transform(XdrCallArgs, State) ->
    {Data, RState} = receive_data(State),
    transform(Data, XdrCallArgs, RState).

%%----------------------------------------------------------------------------
%% receive_data
%%----------------------------------------------------------------------------

receive_data(State = #state{socket = Socket, size_length = SizeLength}) ->
    % Need to protect this code from exceptions
    {ok, LengthPacket} = gen_tcp:recv(Socket, SizeLength),
    <<PayloadLength:32/integer>> = LengthPacket,
    {ok, PayloadPacket} = gen_tcp:recv(Socket, PayloadLength),
    {PayloadPacket, State}.

%%----------------------------------------------------------------------------
%% transform_data
%%----------------------------------------------------------------------------

transform(Data, XdrCallArgs, State = #state{xdr_codecs = Codecs}) ->
    CallArgs = XdrCallArgs#call_args{codec_env = Codecs},
    {pur_utls_xdr:decode_generic(Data, CallArgs), State}.
